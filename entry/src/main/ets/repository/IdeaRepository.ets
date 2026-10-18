import { Idea } from '../model/Idea';
import { DayStat } from '../model/DayStat';
import { IdeaFilter } from '../model/IdeaFilter';
import { IdeaTagLink } from '../model/IdeaTagLink';
import { Tag } from '../model/Tag';

/**
 * 灵感仓库的领域接口。
 *
 * 存在的意义不是「将来可能换数据库」，而是让 ViewModel **不依赖 relationalStore**：
 * 单元测试里可以塞一个内存实现，把分页、分组、排序、筛选这些逻辑单独测掉
 * （真正碰 RDB 的部分留给 ohosTest 的集成测试）。
 * 因此这里的方法一律以 `Idea` / `Tag` 领域对象进出，不出现 ResultSet / ValuesBucket 之类的存储类型。
 */
export interface IdeaRepository {
  /**
   * 新建并返回落库后的对象（带 id 与时间戳），供调用方做乐观插入。
   * 正文里的 `#标签` 由实现方解析入库 —— 标签是正文的索引，
   * 保存正文时顺手同步，调用方不必自己记得这件事。
   * 但**标签同步失败不会让保存失败**：正文是主数据，索引出问题由启动自愈发回。
   */
  insert(content: string, source: number): Promise<Idea>;

  listPage(offset: number, limit: number, filter: IdeaFilter): Promise<Idea[]>;

  findById(id: number): Promise<Idea | null>;

  /** 与 `listPage` 同口径的条数统计（筛选时也是筛后的条数） */
  countActive(filter: IdeaFilter): Promise<number>;

  /**
   * 与 `listPage` 同口径的**按天**统计，供时间轴分组头显示「9 月 5 日 300 条」。
   *
   * 分组头的数字必须来自整库（而不是已加载的行），否则它会随翻页长大；
   * 筛选时也带条件，这样分组头说的是「符合条件的那天有几条」。
   */
  listDayStats(filter: IdeaFilter): Promise<DayStat[]>;

  /** 标签清单（带未删除灵感里的使用频次），供筛选条与 M3 标签云使用 */
  listTags(): Promise<Tag[]>;

  /**
   * 从整个库里随机取一条未删除的灵感（「灵光再现」用）。
   *
   * `excludeIds` 是 24 小时展示窗口：抽到的条会被排除，避免短时间内反复看到同一条。
   * 返回 null 表示**排除之后一条都不剩**，由调用方决定是清空窗口重抽还是罢手 ——
   * 仓库层不替产品做这个取舍。
   */
  randomActive(excludeIds: number[]): Promise<Idea | null>;

  /**
   * 全量导出：所有未删除的灵感（含置顶），按创建时间正序。
   * 与 `listPage` 的区别是**不筛选、不分页** —— 备份必须完整，
   * 只导「当前筛选出来的那几条」会在用户最需要它的时候才发现不对。
   */
  listAllActive(): Promise<Idea[]>;

  /** 全量「灵感 ↔ 标签名」关联。导出时把标签写进文件，导入时才不用靠正文反推 */
  listAllLinks(): Promise<IdeaTagLink[]>;

  /**
   * 导入一条灵感：**保留原始创建/修改时间与置顶状态**，并同步标签。
   *
   * 时间戳必须原样写回：导入的灵感若被压成「刚刚创建」，时间轴分组与热力图会散成一片，
   * 用户会以为导入把数据弄坏了。标签同步沿用「失败不阻断正文」的既有约定（见 `insert`）。
   * 返回新记录的 id。
   */
  insertImported(content: string, createdAt: number, updatedAt: number, pinned: boolean,
    tags: string[]): Promise<number>;

  /**
   * 导入查重：同正文 + 同创建时间即视为同一条，**只和仍未删除的记录比**。
   * 命中的软删除记录交给 `reviveDeleted` 恢复 —— 备份的意图是把东西找回来，
   * 而不是因为「库里还留着一条被删的行」就判重丢掉（1.0.0 审核问题 1）。
   */
  countSameActive(content: string, createdAt: number): Promise<number>;

  /**
   * 把一条被软删除的同内容同时间记录恢复成未删除，返回它的 id。
   * 没有可恢复的记录时返回 -1，调用方据此插入新行。
   */
  reviveDeleted(content: string, createdAt: number): Promise<number>;

  /** 改内容，并**按新正文重建**该条灵感的标签关联（失败同样不阻断正文保存） */
  updateContent(id: number, content: string): Promise<void>;

  /**
   * 启动时的标签自愈：把「正文里有 `#标签`、库里却没有关联行」的灵感补回来，
   * 返回实际修好的条数（0 表示一条都不需要修）。
   *
   * 标签关联是派生数据，历史版本的写入失败会让那条灵感从筛选里消失；
   * 让 App 每次启动自己修一遍，比要求用户重新编辑一遍靠谱。
   */
  repairTagLinks(limit: number): Promise<number>;

  setPinned(id: number, pinned: boolean): Promise<void>;

  /** 软删除（`deleted = 1` 并记下删除时间），可撤销；记录进入「最近删除」 */
  setDeleted(id: number, deleted: boolean): Promise<void>;

  /** 最近删除：保留期内的已删除记录，最近删的在前 */
  listDeleted(): Promise<Idea[]>;

  /** 与 `listDeleted` 同口径的条数 */
  countDeleted(): Promise<number>;

  /** 彻底删除一条**已删除**的灵感（不可恢复） */
  deleteForever(id: number): Promise<void>;

  /** 清空最近删除，返回清掉的条数 */
  clearDeleted(): Promise<number>;

  /** 清理超过保留期的已删除记录，返回清掉的条数（启动 / 打开回收站时调用） */
  purgeExpired(): Promise<number>;
}
