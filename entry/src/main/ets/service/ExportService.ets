import { IdeaRepository } from '../repository/IdeaRepository';
import { Idea } from '../model/Idea';
import { IdeaTagLink } from '../model/IdeaTagLink';
import { dateKey, formatTime } from '../utils/DateUtil';

/**
 * 备份文件的格式版本。
 * 改字段含义时 +1，导入端就能明确说「这个文件比本应用新」，
 * 而不是拿着不认识的结构硬 parse、导出一堆空记录。
 */
export const EXPORT_VERSION: number = 1;

const EXPORT_APP: string = 'Musehroom';

/** 单次导入的条数上限：给「被程序生成的巨型文件」兜个底，别让界面卡死在一个手滑上 */
const IMPORT_MAX_IDEAS: number = 100000;

/** 导出文件里的一条灵感（字段名用 camelCase：这份文件是给人看的，不是内部缓存） */
export class ExportIdea {
  /** 导出时的本地 id，仅供对照；导入时会重新分配 */
  id: number = 0;
  content: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  pinned: boolean = false;
  /** 标签名（不带 `#`）。正文里其实也带着 `#标签`，这里是给外部工具读的规范化副本 */
  tags: string[] = [];
}

/** 备份文件的根对象 */
export class ExportBundle {
  app: string = EXPORT_APP;
  version: number = EXPORT_VERSION;
  exportedAt: number = 0;
  count: number = 0;
  ideas: ExportIdea[] = [];
}

/** 导入结果：给用户一句准确的交代（新增了几条、恢复几条、跳过几条、文件里一共几条） */
export class ImportResult {
  added: number = 0;
  /** 恢复 = 内容与创建时间对得上一条**被删除**的记录，已把它从回收状态还原 */
  restored: number = 0;
  /** 跳过 = 内容与创建时间对得上一条**仍在库里**的记录（重复导入同一份备份），或正文为空 */
  skipped: number = 0;
  total: number = 0;
}

/**
 * 数据导出 / 导入（M4「数据不丢」）。
 *
 * 设计取向：
 *  - **只用 JSON 一种交换格式**（另一种是给人读的 Markdown，不参与导入）：
 *    两种可导入格式就要维护两套字段映射与两套兼容策略，收益为零；
 *  - 导出**不带筛选**、**不含软删除**：备份是「我记过的灵感」，不是数据库转储；
 *  - 导入是**合并**而不是替换：用户点导入的意图是「把这份备份里的东西找回来」，
 *    不是「清空我现在写的一切」——替换式导入一旦点错，代价是不可逆的；
 *  - 导入按「同正文 + 同创建时间」去重，所以同一份备份导入两次不会变成两份；
 *    但**命中的若是被删除的记录，就把它恢复**（见 `importJson`）：用户删掉几条、
 *    再用备份导回来时，那些内容必须回来，而不是被一句「跳过重复」挡住（1.0.0 审核问题 1）。
 */
export class ExportService {
  private repo: IdeaRepository;

  constructor(repo: IdeaRepository) {
    this.repo = repo;
  }

  /** 导出为 JSON（缩进 2 空格，方便用任意文本编辑器打开检查） */
  async buildJson(): Promise<string> {
    return this.jsonOf(await this.collect());
  }

  /**
   * 只导出选中的几条（多选模式的「导出所选」）。
   *
   * 与整库导出同一套结构、同一份字段：这样导出的文件照样能再导入回来，
   * 而不是「导出的是备份的缩水版」。`ids` 的顺序不决定文件顺序 ——
   * 文件里仍按创建时间正序，和整库导出一致（导入端的去重也按这个顺序做）。
   */
  async buildJsonFor(ids: number[]): Promise<string> {
    return this.jsonOf(await this.collect(ids));
  }

  /**
   * 导出为 Markdown：给人读、能直接粘进笔记软件。
   *
   * 排序与首页时间轴同口径（置顶在前，其次按创建时间倒序），
   * 日期用 `YYYY-MM-DD` 做二级标题 —— 这是唯一在纯文本里仍然可排序、可搜索的写法。
   * 标签**不另起一行重复写**：正文里本来就带着 `#标签`，再列一遍只会让文件变长。
   */
  async buildMarkdown(): Promise<string> {
    return this.markdownOf(await this.collect());
  }

  /** 只导出选中的几条为 Markdown（给「选几条发给朋友 / 粘进笔记」用） */
  async buildMarkdownFor(ids: number[]): Promise<string> {
    return this.markdownOf(await this.collect(ids));
  }

  private jsonOf(bundle: ExportBundle): string {
    return JSON.stringify(bundle, null, 2);
  }

  private markdownOf(bundle: ExportBundle): string {
    const lines: string[] = [];
    lines.push('# 灵感菇 · 灵感存档');
    lines.push('');
    lines.push(`> 导出时间：${ExportService.stamp(bundle.exportedAt)} · 共 ${bundle.count} 条`);
    lines.push('');
    lines.push('让灵感，破土而出。');
    lines.push('');

    const sorted = bundle.ideas.slice();
    sorted.sort((a: ExportIdea, b: ExportIdea): number => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.createdAt - a.createdAt;
    });

    let currentDay = '';
    for (const item of sorted) {
      const day = dateKey(item.createdAt);
      if (day !== currentDay) {
        currentDay = day;
        lines.push('');
        lines.push(`## ${day}`);
        lines.push('');
      }
      lines.push(ExportService.markdownItem(item));
    }
    lines.push('');
    return lines.join('\n');
  }

  /**
   * 从 JSON 文本导入（合并式）。
   *
   * 逐条查重再插入：一万条备份 = 一万次 SELECT + 一万次 INSERT，听起来慢，
   * 但这是**用户主动点的一次性动作**，而且每条都在几十微秒量级
   * （M2 已实测：万条库上单条条件查询 1–2ms 以内）。真正要防的是「半天没反应」，
   * 所以 importJson 的每一轮循环都不阻塞 UI（await 之间会让出事件循环），
   * 界面上的进度由调用方的 busy 状态表示。
   */
  async importJson(text: string): Promise<ImportResult> {
    const bundle = ExportService.parseBundle(text);
    const ideas = bundle.ideas;
    if (ideas.length > IMPORT_MAX_IDEAS) {
      throw new Error(`一次最多导入 ${IMPORT_MAX_IDEAS} 条，这个文件有 ${ideas.length} 条`);
    }
    const result = new ImportResult();
    result.total = ideas.length;
    const fallbackNow = Date.now();
    for (const item of ideas) {
      const content = ExportService.textOf(item.content).trim();
      if (content.length === 0) {
        result.skipped = result.skipped + 1;
        continue;
      }
      const createdAt = ExportService.timeOf(item.createdAt, fallbackNow);
      // updated_at 不允许早于 created_at：手工改过的文件里可能出现这种组合，
      // 而 `Idea.wasEdited()` 靠两者差值判断「已编辑」，负差值会被当成没改过
      const updatedAt = Math.max(createdAt, ExportService.timeOf(item.updatedAt, createdAt));
      const existing = await this.repo.countSameActive(content, createdAt);
      if (existing > 0) {
        result.skipped = result.skipped + 1;
        continue;
      }
      // 「删了再导回来」：这一条其实还在库里，只是标了 `deleted = 1`。恢复它而不是重新插一条 ——
      // 重新插会留下两条同内容同时间的记录，之后每次导入都要在它们之间做选择。
      const revived = await this.repo.reviveDeleted(content, createdAt);
      if (revived > 0) {
        result.restored = result.restored + 1;
        continue;
      }
      const tags = ExportService.tagsOf(item.tags);
      await this.repo.insertImported(content, createdAt, updatedAt, item.pinned === true, tags);
      result.added = result.added + 1;
    }
    return result;
  }

  /**
   * 建议文件名：`musehroom-20251005-1552.json`。
   * 日期时间放前面（而不是「备份」这类前缀 + 序号），文件管理器按名字排序时自然就是时间顺序。
   */
  static suggestedFileName(ext: string, now: number): string {
    const d = new Date(now);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`
      + `-${pad(d.getHours())}${pad(d.getMinutes())}`;
    return `musehroom-${stamp}.${ext}`;
  }

  // ==========================================================================
  // 内部
  // ==========================================================================

  /**
   * 把库里的灵感与标签关联拼成导出对象。
   *
   * `ids` 为空/省略 = 整库；给了就只留这些 id（多选导出）。
   * 过滤放在**已经按创建时间正序取回**的列表上，所以文件顺序与整库导出完全一致，
   * 不需要用户按什么顺序勾选就按什么顺序排（那样同一批内容会导出两个不同顺序的文件）。
   */
  private async collect(ids?: number[]): Promise<ExportBundle> {
    const ideas = await this.repo.listAllActive();
    const links = await this.repo.listAllLinks();

    const namesById = new Map<number, string[]>();
    for (const link of links) {
      ExportService.appendName(namesById, link);
    }

    const wanted: Set<number> | null = ids === undefined ? null : new Set<number>(ids);
    const bundle = new ExportBundle();
    bundle.exportedAt = Date.now();
    const list: ExportIdea[] = [];
    for (const idea of ideas) {
      if (wanted !== null && !wanted.has(idea.id)) {
        continue;
      }
      list.push(ExportService.toExportIdea(idea, namesById));
    }
    bundle.count = list.length;
    bundle.ideas = list;
    return bundle;
  }

  private static appendName(namesById: Map<number, string[]>, link: IdeaTagLink): void {
    const existing = namesById.get(link.ideaId);
    if (existing === undefined) {
      namesById.set(link.ideaId, [link.tagName]);
      return;
    }
    existing.push(link.tagName);
  }

  private static toExportIdea(idea: Idea, namesById: Map<number, string[]>): ExportIdea {
    const item = new ExportIdea();
    item.id = idea.id;
    item.content = idea.content;
    item.createdAt = idea.createdAt;
    item.updatedAt = idea.updatedAt;
    item.pinned = idea.pinned;
    const names = namesById.get(idea.id);
    item.tags = names === undefined ? [] : names;
    return item;
  }

  /** 一行 Markdown。多行正文用两个空格缩进续行（标准列表续行写法，不依赖任何扩展） */
  private static markdownItem(item: ExportIdea): string {
    const pin = item.pinned ? '📌 ' : '';
    const rows = item.content.split('\n');
    const head = `- **${formatTime(item.createdAt)}** ${pin}${rows[0]}`;
    if (rows.length === 1) {
      return head;
    }
    const rest: string[] = [head];
    for (let i = 1; i < rows.length; i++) {
      rest.push(`  ${rows[i]}`);
    }
    return rest.join('\n');
  }

  /** `YYYY-MM-DD HH:mm`，给文件头部的说明用 */
  private static stamp(now: number): string {
    return `${dateKey(now)} ${formatTime(now)}`;
  }

  /**
   * 解析并校验文件结构。
   *
   * ArkTS 里 `JSON.parse` 的结果只能靠 `as` 断言拿到类型，**运行时什么保障都没有**：
   * 用户完全可能拿一个别的 JSON（或者其他 App 的备份）来点导入。
   * 所以这里先校验「这是不是我的文件」，把话说清楚；再让字段级兜底（见 `textOf` 等）去处理残缺字段。
   */
  private static parseBundle(text: string): ExportBundle {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      throw new Error('这个文件是空的');
    }
    if (trimmed.charCodeAt(0) !== 0x7B) {
      throw new Error('这不是灵感菇导出的 JSON 备份（开头不是 {）');
    }
    const bundle = JSON.parse(trimmed) as ExportBundle;
    if (bundle.version !== EXPORT_VERSION) {
      throw new Error(`备份版本不匹配：文件是 ${bundle.version}，本应用支持 ${EXPORT_VERSION}`);
    }
    const rawIdeas = bundle.ideas as Object;
    if (!(rawIdeas instanceof Array)) {
      throw new Error('文件里没有灵感列表（ideas）');
    }
    return bundle;
  }

  /** 字段级兜底：类型不对就当空串（宁可跳过这一条，也不要把乱七八糟的东西写进库） */
  private static textOf(value: string): string {
    return typeof value === 'string' ? value : '';
  }

  private static timeOf(value: number, fallback: number): number {
    return typeof value === 'number' && value > 0 ? value : fallback;
  }

  /** 标签数组兜底：非数组、含非字符串项时逐项过滤，剩下的仍然可用 */
  private static tagsOf(value: string[]): string[] {
    const raw = value as Object;
    if (!(raw instanceof Array)) {
      return [];
    }
    const entries = raw as string[];
    const names: string[] = [];
    for (const entry of entries) {
      if (typeof entry === 'string' && entry.length > 0) {
        names.push(entry);
      }
    }
    return names;
  }
}
