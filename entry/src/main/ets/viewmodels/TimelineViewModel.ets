import { Idea, IdeaSource } from '../model/Idea';
import { DayStat } from '../model/DayStat';
import { IdeaFilter } from '../model/IdeaFilter';
import { Tag } from '../model/Tag';
import { IdeaRepository } from '../repository/IdeaRepository';
import { PAGE_SIZE, TAG_REPAIR_LIMIT } from '../utils/Constants';
import { dateKey, formatDayLabel } from '../utils/DateUtil';
import { LazyList } from '../utils/LazyList';
import { Logger } from '../utils/Logger';
import { parseTags } from '../utils/TagParser';

/** 行类型。用静态常量类而非 enum，避免 number→enum 的转换（同 `IdeaSource`） */
export class TimelineRowKind {
  /** 日期分组头 / 置顶分组头 */
  static readonly HEADER: number = 0;
  /** 一条灵感 */
  static readonly IDEA: number = 1;
}

/**
 * 时间轴的一行。
 *
 * 刻意做成**扁平记录**（分组头字段和灵感字段放在同一个类里），而不是
 * 「`Idea | Header` 联合类型 + 渲染时判空」：
 * ArkTS 的严格模式对联合类型与可空链很不友好，渲染路径上每多一次 `?.`/`!`
 * 就多一处运行期风险。扁平结构下 `LazyForEach` 的 item builder 只需要读基本类型，
 * 不存在空对象。
 *
 * 两个工厂方法保证「哪些字段有意义」这件事只在这里出现一次。
 */
export class TimelineRow {
  kind: number = TimelineRowKind.IDEA;
  /** LazyForEach 的键，必须**包含所有会变的展示字段**，理由见 `fromIdea` */
  key: string = '';
  /**
   * 不含条数的分组键。
   * 分组头的条数需要数完整组才能回填，回填时要重新造一个 header，这里存下「身份」，
   * 免得把已经拼进 `key` 的条数再拼一遍（`group:day:X#0#12`）。
   */
  baseKey: string = '';

  // ---- 分组头 ----
  title: string = '';
  count: number = 0;
  isPinnedGroup: boolean = false;

  // ---- 灵感 ----
  ideaId: number = 0;
  content: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  pinned: boolean = false;
  edited: boolean = false;
  /**
   * 正文里解析出的标签（只用于卡片上显示 chips）。
   * 直接从正文解析而不是再查一次数据库：`TagParser` 才是「什么算标签」的唯一定义，
   * 数据库里那两张表只是它的索引，多查一次既慢又多一处可能不一致的地方。
   */
  tagNames: string[] = [];

  static header(key: string, title: string, count: number, isPinnedGroup: boolean): TimelineRow {
    const row = new TimelineRow();
    row.kind = TimelineRowKind.HEADER;
    row.baseKey = key;
    row.key = `${key}#${count}`;
    row.title = title;
    row.count = count;
    row.isPinnedGroup = isPinnedGroup;
    return row;
  }

  /**
   * 由灵感生成行。
   *
   * ⚠️ key 里必须带上所有会变的展示字段：`pinned`、`updatedAt`，以及**当前搜索词**。
   * `LazyForEach` 判断「这一项要不要重建」靠的就是 key 有没有变。若只用 `idea:5`，
   * 则改内容、切置顶之后 key 不变，ArkUI 会复用旧组件**不重新执行 item builder**，
   * 界面就停在旧文字/旧样式上——这类「数据对了、界面没动」的问题最难查。
   * 搜索词同理：换了关键词，即使命中的还是同几条，卡片上的高亮也必须重画。
   */
  static fromIdea(idea: Idea, keyword: string): TimelineRow {
    const row = new TimelineRow();
    row.kind = TimelineRowKind.IDEA;
    row.key = `idea:${idea.id}:${idea.pinned ? 1 : 0}:${idea.updatedAt}:${keyword}`;
    row.ideaId = idea.id;
    row.content = idea.content;
    row.createdAt = idea.createdAt;
    row.updatedAt = idea.updatedAt;
    row.pinned = idea.pinned;
    row.edited = idea.wasEdited();
    row.tagNames = parseTags(idea.content);
    return row;
  }
}

/**
 * 时间轴的视图模型。
 *
 * 持有「已加载的全部灵感」这一份内存真相（`loaded`），每次变更后**整表重算**成
 * `TimelineRow[]` 推给 `LazyList`。为什么不做增量更新：
 *   - 分组头依赖一整组数据（「今天 12 条」），任何时候插入/删除都可能让分组头出现、
 *     消失或改数字，增量维护的复杂度远高于它的收益；
 *   - 已加载规模是页数 × 50，几百行重算一次是微秒级，真正的开销在 ArkUI 渲染，
 *     而那一层由 `LazyForEach` 按需处理。
 *
 * 与页面的分工：页面持有 `@State`（加载中、还有更多、总数）用于渲染，
 * 本类只管数据，通过 `onChange` 回调通知页面把 `@State` 同步过去。
 * 这样视图模型不依赖任何 ArkUI 装饰器，可以被单元测试直接实例化。
 */
export class TimelineViewModel {
  private repo: IdeaRepository;
  private rows: LazyList<TimelineRow>;

  /** 已加载的灵感（内存真相），顺序始终与 SQL 的 `pinned DESC, created_at DESC` 一致 */
  private loaded: Idea[] = [];
  private hasMoreFlag: boolean = true;
  private loadingFlag: boolean = false;
  private totalCountValue: number = 0;
  private errorText: string = '';

  /** 已应用的搜索词（防抖之后的值，卡片高亮也用它） */
  private keyword: string = '';
  /** 已选中的标签（存对象而不是 id：标签被删光后仍要能显示在筛选条上、还要能取消选中） */
  private selectedTags: Tag[] = [];
  /**
   * 只保留某一天（'YYYY-MM-DD'），来自统计面板里点热力图的某一格。
   *
   * 它是**筛选条件**的一种，与其他条件是交集：关键词 + 标签 + 某一天。
   * 空串表示没有按天筛选（默认）。
   */
  private dayKey: string = '';
  /** 当前全部标签（带频次），供筛选条渲染 */
  private tags: Tag[] = [];
  /**
   * 标签清单是否需要重读。
   *
   * 标签只依赖**正文**，不依赖筛选条件 —— 用户换关键词、点标签时清单一个字都没变。
   * 而这份清单是全库聚合（1 万条灵感 + 3 万条关联实测 59–68ms），每次筛选都重查一遍
   * 纯属浪费，所以记一个脏标记，只有正文变了才重读。
   */
  private tagsDirty: boolean = true;
  /** 标签自愈是否已经跑过（启动级维护动作，每次改筛选都会重走 loadFirstPage，不能跟着跑） */
  private repairRequested: boolean = false;
  /**
   * 按天统计（分组头「9 月 5 日 300 条」里的 300）。
   *
   * 数字来自数据库的整库聚合，**不是**数已加载的行 —— 后者会随翻页长大
   * （真机反馈：翻到 300 条时显示 300，再翻 50 条变成 350）。见 `DayStat` 的注释。
   * 只在第一页查询时取一次；之后增删改走内存增减，避免为了一个数字再查库。
   */
  private dayStats: DayStat[] = [];
  /** 置顶区那一行的条数（全库置顶总数，按天统计里逐日累加得到） */
  private pinnedTotal: number = 0;

  /** 数据状态发生变化时的回调（页面在这里同步 @State） */
  onChange: () => void = () => {
  };

  constructor(repo: IdeaRepository, rows: LazyList<TimelineRow>) {
    this.repo = repo;
    this.rows = rows;
  }

  dataSource(): LazyList<TimelineRow> {
    return this.rows;
  }

  isLoading(): boolean {
    return this.loadingFlag;
  }

  hasMore(): boolean {
    return this.hasMoreFlag;
  }

  /** 未删除的灵感总数（来自数据库 COUNT，不是已加载条数） */
  total(): number {
    return this.totalCountValue;
  }

  lastError(): string {
    return this.errorText;
  }

  isEmpty(): boolean {
    return this.loaded.length === 0 && !this.loadingFlag;
  }

  /**
   * 已加载的全部灵感 id（多选「全选」用）。
   *
   * 只返回**已经翻到的**，不替用户虚构还没加载的：全选之后按删除，
   * 用户预期的是「屏幕上这些」，而不是「库里所有（包括我没看见的）」。
   */
  loadedIdeaIds(): number[] {
    const ids: number[] = [];
    for (const idea of this.loaded) {
      ids.push(idea.id);
    }
    return ids;
  }

  // ==========================================================================
  // 筛选（关键词 + 标签）
  // ==========================================================================

  /** 当前是否有任何筛选条件——决定空状态是「灵感库还是空的」还是「没有匹配的灵感」 */
  isFiltered(): boolean {
    return this.keyword.length > 0 || this.selectedTags.length > 0 || this.dayKey.length > 0;
  }

  currentKeyword(): string {
    return this.keyword;
  }

  /** 当前按天筛的那一天（空串 = 没按天筛），页面用它显示日期 chip */
  currentDayKey(): string {
    return this.dayKey;
  }

  /**
   * 按某一天筛选（统计面板点热力图的一格）。
   * 传空串等于取消按天筛选。
   */
  async setDayKey(day: string): Promise<void> {
    const next = day.trim();
    if (next === this.dayKey) {
      return;
    }
    this.dayKey = next;
    await this.loadFirstPage();
  }

  /** 标签清单：把「已选中但已不在清单里」的标签补在最前面，否则用户没法取消选中 */
  tagList(): Tag[] {
    const merged: Tag[] = [];
    for (let i = 0; i < this.selectedTags.length; i++) {
      const selected = this.selectedTags[i];
      if (this.findTagByName(selected.name) === null) {
        merged.push(selected);
      }
    }
    return merged.concat(this.tags);
  }

  isTagSelected(name: string): boolean {
    return this.indexOfSelectedTag(name) >= 0;
  }

  selectedTagCount(): number {
    return this.selectedTags.length;
  }

  /** 应用搜索词（调用方负责防抖，这里只认「最终要查什么」） */
  async setKeyword(keyword: string): Promise<void> {
    const next = keyword.trim();
    if (next === this.keyword) {
      return;
    }
    this.keyword = next;
    await this.loadFirstPage();
  }

  /**
   * 按名字切换标签选中状态（多选取交集）。
   * 对外只暴露**名字**而不是 id：卡片上的 chips 是从正文解析出来的，
   * 那里没有 id；由视图模型在自己的标签清单里解析成 id，界面就不必关心两套标识。
   */
  async toggleTagByName(name: string): Promise<void> {
    const selectedIndex = this.indexOfSelectedTag(name);
    if (selectedIndex >= 0) {
      this.selectedTags.splice(selectedIndex, 1);
      await this.loadFirstPage();
      return;
    }
    const tag = this.findTagByName(name);
    if (tag === null) {
      // 清单里找不到就不动筛选条件：宁可不响应，也不要筛出一个必然为空的结果
      Logger.warn(`切换标签失败，清单里没有：${name}`);
      return;
    }
    this.selectedTags.push(tag);
    await this.loadFirstPage();
  }

  async clearFilters(): Promise<void> {
    if (!this.isFiltered()) {
      return;
    }
    this.keyword = '';
    this.selectedTags = [];
    this.dayKey = '';
    await this.loadFirstPage();
  }

  /** 只清标签、保留关键词（筛选条上的「清空标签」用） */
  async clearSelectedTags(): Promise<void> {
    if (this.selectedTags.length === 0) {
      return;
    }
    this.selectedTags = [];
    await this.loadFirstPage();
  }

  // ==========================================================================
  // 加载
  // ==========================================================================

  /** 首次加载 / 重新加载第一页（筛选条件变化、出错重试都走这里） */
  async loadFirstPage(): Promise<void> {
    this.loaded = [];
    this.hasMoreFlag = true;
    this.rows.setAll([]);
    await this.loadNextPage();
    await this.refreshTagsIfStale();
    // 标签是这一句之前才读回来的，所以**必须再通知一次**：
    // loadNextPage 内部那两次 onChange 都发生在标签到达之前，页面手里的 tagItems 还是空的，
    // 而标签筛选条正是靠它决定要不要创建（真机验收时筛选条整条不出现，根因就在这）
    this.onChange();
    this.scheduleTagRepair();
  }

  /**
   * 启动时的一次性标签自愈（详见 `IdeaRepository.repairTagLinks`）。
   *
   * 为什么放在这里而不是 EntryAbility：它需要「正文 → 标签」的解析与仓库，属于视图模型的地盘；
   * 而且**必须在首屏渲染之后**跑 —— 自愈要读库写库，塞进启动路径会和「冷启动到可输入 ≤ 1s」打架。
   * 不 await：用户可能立刻开始打字，自愈慢一点无所谓。
   * 失败只记日志：兜底手段绝不能变成新的报错来源。
   */
  private scheduleTagRepair(): void {
    if (this.repairRequested) {
      return;
    }
    this.repairRequested = true;
    this.repo.repairTagLinks(TAG_REPAIR_LIMIT).then((repaired: number) => {
      if (repaired <= 0) {
        return;
      }
      Logger.info(`标签自愈：补回 ${repaired} 条灵感的标签关联`);
      this.refreshTags().then(() => {
        this.onChange();
      }).catch((err: Error) => {
        Logger.warn(`标签自愈后刷新标签条失败：${err.message}`);
      });
    }).catch((err: Error) => {
      Logger.warn(`标签自愈失败：${err.message}`);
    });
  }

  /** 上拉加载下一页。已在加载或已到底时静默返回（滚到底会连续触发多次） */
  async loadMore(): Promise<void> {
    if (this.loadingFlag || !this.hasMoreFlag) {
      return;
    }
    await this.loadNextPage();
  }

  private async loadNextPage(): Promise<void> {
    const offset = this.loaded.length;
    // 一次查询用的筛选条件取同一份快照：列表与总数必须同口径，
    // 否则用户在查询途中改了条件，会出现「列表是新的、条数是旧的」这种自相矛盾的界面
    const filter = this.buildFilter();
    this.loadingFlag = true;
    this.errorText = '';
    this.onChange();
    try {
      const page = await this.repo.listPage(offset, PAGE_SIZE, filter);
      this.loaded = offset === 0 ? page : this.loaded.concat(page);
      // 拿满一页就假定还有下一页；最后一页恰好是 PAGE_SIZE 的整数倍时会多查一次空页，
      // 代价是一次空查询，换掉「总数要额外 COUNT 一次」的耦合，划算。
      this.hasMoreFlag = page.length >= PAGE_SIZE;
      // 分组头的条数只在第一页时取一次：它属于「整库按天聚合」，与翻到第几页无关。
      // 放在 rebuild 之前，第一屏的分组头数字就不会先错一帧
      if (offset === 0) {
        await this.refreshDayStats(filter);
      }
      this.rebuild();
      this.totalCountValue = await this.repo.countActive(filter);
    } catch (err) {
      const error = err as Error;
      Logger.error(`加载时间轴失败：${error.message}`);
      this.errorText = '读取灵感失败，请稍后重试';
      // 出错就停下，不要让「滚到底」变成无限重试
      this.hasMoreFlag = false;
    } finally {
      this.loadingFlag = false;
      this.onChange();
    }
  }

  // ==========================================================================
  // 增删改（乐观更新：先改内存，再信数据库）
  // ==========================================================================

  /** 新建。返回落库后的对象（带 id），失败返回 null */
  async addIdea(content: string): Promise<Idea | null> {
    const text = content.trim();
    if (text.length === 0) {
      return null;
    }
    try {
      const created = await this.repo.insert(text, IdeaSource.MANUAL);
      if (this.isFiltered()) {
        // 筛选状态下不能乐观插入：新灵感很可能不满足当前条件（比如关键词不匹配），
        // 直接插进列表会看到一条「本不该出现」的记录。按当前条件重查第一页最省心。
        await this.loadFirstPage();
      } else {
        this.loaded.push(created);
        // 分组头条数跟着 +1（乐观路径不能为了一个数字再查库）
        this.bumpDayStat(dateKey(created.createdAt), 1, 0);
        this.rebuild();
        this.totalCountValue = this.totalCountValue + 1;
        await this.refreshTags();
      }
      this.onChange();
      return created;
    } catch (err) {
      const error = err as Error;
      Logger.error(`保存灵感失败：${error.message}`);
      this.errorText = '保存失败，内容仍在输入框里';
      this.onChange();
      return null;
    }
  }

  async updateContent(id: number, content: string): Promise<boolean> {
    const text = content.trim();
    if (text.length === 0) {
      return false;
    }
    try {
      await this.repo.updateContent(id, text);
      const index = this.indexOf(id);
      if (index >= 0) {
        this.loaded[index].content = text;
        // updated_at 由 DAO 在库里刷新，这里跟上毫秒级差异；它同时也是行的 key 的一部分，
        // 改了才会触发卡片重建
        this.loaded[index].updatedAt = Date.now();
      }
      // 正文变了标签就可能变（加/删/改名），筛选条的频次也要跟着更新
      await this.refreshTags();
      this.rebuild();
      this.onChange();
      return true;
    } catch (err) {
      const error = err as Error;
      Logger.error(`更新灵感失败：${error.message}`);
      this.errorText = '保存失败，请重试';
      this.onChange();
      return false;
    }
  }

  async setPinned(id: number, pinned: boolean): Promise<boolean> {
    try {
      await this.repo.setPinned(id, pinned);
      const index = this.indexOf(id);
      if (index >= 0) {
        this.loaded[index].pinned = pinned;
      }
      // 置顶总数与那一行的显示口径一致：库里变了，统计就跟着变
      this.bumpPinnedTotal(pinned ? 1 : -1);
      // 置顶会改变行序，必须整表重算（`rebuild` 内部会先按新置顶态重排）
      this.rebuild();
      this.onChange();
      return true;
    } catch (err) {
      const error = err as Error;
      Logger.error(`置顶操作失败：${error.message}`);
      this.errorText = '操作失败，请重试';
      this.onChange();
      return false;
    }
  }

  /** 软删除：数据库里只标记 `deleted = 1`，界面先移走，5 秒内可撤销 */
  async softDelete(id: number): Promise<boolean> {
    try {
      await this.repo.setDeleted(id, true);
      const index = this.indexOf(id);
      if (index >= 0) {
        const removed = this.loaded[index];
        this.loaded.splice(index, 1);
        // 那天的条数与置顶总数各减一（撤销时会加回来）
        this.bumpDayStat(dateKey(removed.createdAt), -1, 0);
        if (removed.pinned) {
          this.bumpPinnedTotal(-1);
        }
      }
      this.rebuild();
      this.totalCountValue = Math.max(0, this.totalCountValue - 1);
      await this.refreshTags();
      this.onChange();
      return true;
    } catch (err) {
      const error = err as Error;
      Logger.error(`删除灵感失败：${error.message}`);
      this.errorText = '删除失败，请重试';
      this.onChange();
      return false;
    }
  }

  /**
   * 撤销删除。
   * 按 id 把那条重新读回来再插进内存，而不是重载第一页：
   * 撤销时用户可能已经滚到列表深处，重载会把位置和已翻的页全部丢掉。
   */
  async restore(id: number): Promise<boolean> {
    try {
      await this.repo.setDeleted(id, false);
      const idea = await this.repo.findById(id);
      if (idea !== null) {
        this.loaded.push(idea);
        this.bumpDayStat(dateKey(idea.createdAt), 1, 0);
        if (idea.pinned) {
          this.bumpPinnedTotal(1);
        }
        this.rebuild();
        this.totalCountValue = this.totalCountValue + 1;
        await this.refreshTags();
        this.onChange();
      }
      return true;
    } catch (err) {
      const error = err as Error;
      Logger.error(`撤销删除失败：${error.message}`);
      this.errorText = '撤销失败，请重试';
      this.onChange();
      return false;
    }
  }

  // ==========================================================================
  // 内部
  // ==========================================================================

  /** 每次查询都新建一份筛选条件快照，避免异步查询途中条件被就地改写 */
  private buildFilter(): IdeaFilter {
    const filter = new IdeaFilter();
    filter.keyword = this.keyword;
    filter.dayKey = this.dayKey;
    for (let i = 0; i < this.selectedTags.length; i++) {
      filter.tagIds.push(this.selectedTags[i].id);
    }
    return filter;
  }

  /**
   * 强制重读标签清单 —— 正文发生变化（新增/编辑/删除/撤销/自愈补回）后调用，
   * 因为这些操作会改标签集合与频次。
   */
  private async refreshTags(): Promise<void> {
    this.tagsDirty = true;
    await this.refreshTagsIfStale();
  }

  /**
   * 需要时才重读标签清单。
   *
   * 筛选条件变化（换关键词、点标签、清空）走的是 `loadFirstPage`，
   * 但那些操作不会改标签 —— 1 万条数据下这次查询实测约 200ms，属于白花的时间。
   */
  private async refreshTagsIfStale(): Promise<void> {
    if (!this.tagsDirty) {
      return;
    }
    try {
      this.tags = await this.repo.listTags();
      this.tagsDirty = false;
      // 调试级别：排查「筛选条不出现 / 标签没入库」时，这一行就能区分
      // 「库里确实没有标签」和「读到了但界面没刷新」——两种病因的修法完全不同
      Logger.debug(`标签清单刷新：${this.tags.length} 个`);
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取标签清单失败：${error.message}`);
    }
  }

  /**
   * 重读「按天统计」。只有第一页查询时调用：它属于整库聚合，与翻到第几页无关。
   *
   * 自己吞掉异常：分组头的数字出错不该让整个列表加载失败
   * （列表是主内容，分组头只是它的注脚，宁可数字暂时留旧值）。
   */
  private async refreshDayStats(filter: IdeaFilter): Promise<void> {
    try {
      const stats = await this.repo.listDayStats(filter);
      this.dayStats = stats;
      let pinned = 0;
      for (let i = 0; i < stats.length; i++) {
        pinned += stats[i].pinnedCount;
      }
      this.pinnedTotal = pinned;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取按天统计失败：${error.message}`);
    }
  }

  /** 按日期找那天的统计（天数不多，线性找足够；用 Map 反而多一层类型噪音） */
  private findDayStat(day: string): DayStat | null {
    for (let i = 0; i < this.dayStats.length; i++) {
      if (this.dayStats[i].day === day) {
        return this.dayStats[i];
      }
    }
    return null;
  }

  /**
   * 就地增减某天的条数。
   *
   * 增删改走的是乐观路径（先改内存再信数据库），不能为了一个数字再查一次库；
   * 找不到该天就补一条（比如新记录落在今天，而今天原本没有记录）。
   */
  private bumpDayStat(day: string, delta: number, pinnedDelta: number): void {
    const stat = this.findDayStat(day);
    if (stat === null) {
      const created = new DayStat();
      created.day = day;
      created.count = Math.max(0, delta);
      created.pinnedCount = Math.max(0, pinnedDelta);
      this.dayStats.push(created);
      return;
    }
    stat.count = Math.max(0, stat.count + delta);
    stat.pinnedCount = Math.max(0, stat.pinnedCount + pinnedDelta);
  }

  /** 置顶总数增减（`pinnedTotal` 是各天 `pinnedCount` 的合计，单独维护避免每次重算） */
  private bumpPinnedTotal(delta: number): void {
    this.pinnedTotal = Math.max(0, this.pinnedTotal + delta);
  }

  /** 分组头要显示的数字：查得到就用整库口径，查不到（统计还没回来）先退回已加载行数 */
  private dayCountFor(day: string, fallback: number): number {
    const stat = this.findDayStat(day);
    return stat === null ? fallback : stat.count;
  }

  /** 按名字找标签（大小写不敏感，与数据库的 `COLLATE NOCASE` 同口径） */
  private findTagByName(name: string): Tag | null {
    const key = name.toLowerCase();
    for (let i = 0; i < this.tags.length; i++) {
      if (this.tags[i].name.toLowerCase() === key) {
        return this.tags[i];
      }
    }
    return null;
  }

  private indexOfSelectedTag(name: string): number {
    const key = name.toLowerCase();
    for (let i = 0; i < this.selectedTags.length; i++) {
      if (this.selectedTags[i].name.toLowerCase() === key) {
        return i;
      }
    }
    return -1;
  }

  private indexOf(id: number): number {
    for (let i = 0; i < this.loaded.length; i++) {
      if (this.loaded[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  /** 排序口径必须与 SQL 完全一致，否则置顶切换后行序会跳 */
  private sortLoaded(): void {
    this.loaded.sort((a: Idea, b: Idea): number => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.createdAt - a.createdAt;
    });
  }

  /**
   * 把 `loaded` 摊平成「分组头 + 灵感」的行序列。
   *
   * 置顶区在前（数据库排序已保证置顶在最前，`sortLoaded` 再兜一次），
   * 其后按本地日期分组。分组头的条数只能数完整组才知道，所以先占位、组结束再回填。
   */
  private rebuild(): void {
    this.sortLoaded();

    const rows: TimelineRow[] = [];
    let index = 0;

    // ---- 置顶区 ----
    let pinnedCount = 0;
    while (index < this.loaded.length && this.loaded[index].pinned) {
      if (pinnedCount === 0) {
        rows.push(TimelineRow.header('group:pin', '置顶', 0, true));
      }
      pinnedCount++;
      rows.push(TimelineRow.fromIdea(this.loaded[index], this.keyword));
      index++;
    }
    if (pinnedCount > 0) {
      // 置顶区那一行报的是**全库**置顶总数：已加载的往往只是其中一部分，
      // 数已加载行会让这个数字随翻页长大（与日期分组头同一个毛病）
      const pinnedHeaderCount = this.pinnedTotal > 0 ? this.pinnedTotal : pinnedCount;
      rows[0] = TimelineRow.header('group:pin', '置顶', pinnedHeaderCount, true);
    }

    // ---- 按日期分组 ----
    const now = Date.now();
    let currentKey = '';
    let groupStart = -1;
    let groupCount = 0;
    while (index < this.loaded.length) {
      const idea = this.loaded[index];
      const key = dateKey(idea.createdAt);
      if (key !== currentKey) {
        // 上一组收尾：回填条数。数字取整库口径（`dayCountFor`），
        // 拿不到统计时才退回已加载行数
        if (groupStart >= 0) {
          const previous = rows[groupStart];
          const filled = this.dayCountFor(currentKey, groupCount);
          rows[groupStart] = TimelineRow.header(previous.baseKey, previous.title, filled, false);
        }
        currentKey = key;
        groupStart = rows.length;
        groupCount = 0;
        rows.push(TimelineRow.header(`group:day:${key}`, formatDayLabel(idea.createdAt, now), 0, false));
      }
      rows.push(TimelineRow.fromIdea(idea, this.keyword));
      groupCount++;
      index++;
    }
    if (groupStart >= 0) {
      const last = rows[groupStart];
      const filled = this.dayCountFor(currentKey, groupCount);
      rows[groupStart] = TimelineRow.header(last.baseKey, last.title, filled, false);
    }

    this.rows.setAll(rows);
  }
}
