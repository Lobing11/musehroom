import { common } from '@kit.AbilityKit';
import { Idea } from '../model/Idea';
import { DayStat } from '../model/DayStat';
import { IdeaFilter } from '../model/IdeaFilter';
import { IdeaTagLink } from '../model/IdeaTagLink';
import { Tag } from '../model/Tag';
import { IdeaDao } from '../database/IdeaDao';
import { TagDao } from '../database/TagDao';
import { RdbHelper } from '../database/RdbHelper';
import { IdeaRepository } from './IdeaRepository';
import { parseTags } from '../utils/TagParser';
import { TRASH_RETENTION_MS } from '../utils/Constants';
import { Logger } from '../utils/Logger';

/**
 * `IdeaRepository` 的 relationalStore 实现。
 *
 * 分工：`IdeaDao` / `TagDao` 管 SQL 与行映射，这里管**生命周期**——延迟打开数据库、缓存 DAO、
 * 把「写入成功」翻译成调用方要的领域对象，以及维护「正文 → 标签」这条不变量。
 * DAO 延迟到第一次真正读写时才创建：冷启动路径上不该有任何数据库开销，
 * 否则「打开即可输入 ≤ 1s」这条验收会被建表拖累。
 */
export class RdbIdeaRepository implements IdeaRepository {
  private context: common.Context;
  private dao: IdeaDao | null = null;
  private tagDao: TagDao | null = null;

  constructor(context: common.Context) {
    this.context = context;
  }

  private async daoRef(): Promise<IdeaDao> {
    const cached = this.dao;
    if (cached !== null) {
      return cached;
    }
    const store = await RdbHelper.getStore(this.context);
    const dao = new IdeaDao(store);
    this.dao = dao;
    return dao;
  }

  private async tagDaoRef(): Promise<TagDao> {
    const cached = this.tagDao;
    if (cached !== null) {
      return cached;
    }
    const store = await RdbHelper.getStore(this.context);
    const dao = new TagDao(store);
    this.tagDao = dao;
    return dao;
  }

  /**
   * 插入并回传完整的领域对象。
   *
   * 时间戳在这里算一次并同时用于 created_at / updated_at，保证两者的差值恰好是 0，
   * 不会让 `wasEdited()` 把刚记下的灵感误判成「已编辑」。
   *
   * 标签同步放在正文插入之后，而且**失败不算保存失败**：
   * 正文是主数据、标签只是它的索引，真机实测过「正文写进去了、标签报错、用户却看到
   * 『保存失败』」这种半截写入 —— 用户的反应是再点一次保存，于是库里多出一条重复灵感。
   * 所以标签失败只记警告，关联由下一次编辑或启动自愈补回来。
   */
  async insert(content: string, source: number): Promise<Idea> {
    const dao = await this.daoRef();
    const now = Date.now();
    const id = await dao.insert(content, now, source);
    await this.syncTagsQuietly(id, parseTags(content));

    const idea = new Idea();
    idea.id = id;
    idea.content = content;
    idea.createdAt = now;
    idea.updatedAt = now;
    idea.pinned = false;
    idea.deleted = false;
    idea.source = source;
    return idea;
  }

  async listPage(offset: number, limit: number, filter: IdeaFilter): Promise<Idea[]> {
    const dao = await this.daoRef();
    return await dao.listPage(offset, limit, filter);
  }

  async findById(id: number): Promise<Idea | null> {
    const dao = await this.daoRef();
    return await dao.findById(id);
  }

  async countActive(filter: IdeaFilter): Promise<number> {
    const dao = await this.daoRef();
    return await dao.countActive(filter);
  }

  async listDayStats(filter: IdeaFilter): Promise<DayStat[]> {
    const dao = await this.daoRef();
    return await dao.listDayStats(filter);
  }

  async listTags(): Promise<Tag[]> {
    const tagDao = await this.tagDaoRef();
    return await tagDao.listTagsWithCount();
  }

  async randomActive(excludeIds: number[]): Promise<Idea | null> {
    const dao = await this.daoRef();
    return await dao.randomActive(excludeIds);
  }

  async updateContent(id: number, content: string): Promise<void> {
    const dao = await this.daoRef();
    await dao.updateContent(id, content, Date.now());
    await this.syncTagsQuietly(id, parseTags(content));
  }

  async listAllActive(): Promise<Idea[]> {
    const dao = await this.daoRef();
    return await dao.listAllActive();
  }

  async listAllLinks(): Promise<IdeaTagLink[]> {
    const tagDao = await this.tagDaoRef();
    return await tagDao.listAllLinks();
  }

  /**
   * 导入一条灵感。
   *
   * 标签口径与新建保持一致：**以正文解析结果为准**，只有正文里解析不出标签时
   * 才退回用文件里记的标签名 —— 万一用户的 JSON 被手工改过（把 `#` 删了），
   * 文件里的标签数组就是唯一的线索，扔掉它等于静默丢标签。
   */
  async insertImported(content: string, createdAt: number, updatedAt: number, pinned: boolean,
    tags: string[]): Promise<number> {
    const dao = await this.daoRef();
    const id = await dao.insertImported(content, createdAt, updatedAt, pinned);
    const parsed = parseTags(content);
    await this.syncTagsQuietly(id, parsed.length > 0 ? parsed : tags);
    return id;
  }

  async countSameActive(content: string, createdAt: number): Promise<number> {
    const dao = await this.daoRef();
    return await dao.countSameActive(content, createdAt);
  }

  /**
   * 恢复一条被软删除的同内容同时间记录。
   *
   * 只改 `deleted`：正文、置顶状态与标签关联都还在，恢复后和删除前完全一致，
   * 不需要再解析一遍正文重建标签。返回 -1 表示没有可恢复的记录。
   */
  async reviveDeleted(content: string, createdAt: number): Promise<number> {
    const dao = await this.daoRef();
    const id = await dao.findDeletedSame(content, createdAt);
    if (id <= 0) {
      return -1;
    }
    // 恢复即离开「最近删除」：updateDeleted 会把 deleted_at 一并清零
    await dao.updateDeleted(id, false, Date.now());
    return id;
  }

  /**
   * 启动时的标签自愈：把「正文里有 `#标签`、库里却没有关联行」的灵感补回来。
   *
   * 为什么需要它：标签关联是派生数据，历史上真机出现过「正文写入成功、标签写入失败」，
   * 那条灵感因此从筛选和标签云里消失（正文还在，但用户找不到它）。
   * 与其要求用户重新编辑一遍，不如启动时自己修 —— 修完返回条数，调用方据此刷新标签条。
   *
   * 单条修不动只记警告、继续修下一条：自愈本身绝不能变成新的故障源。
   */
  async repairTagLinks(limit: number): Promise<number> {
    const dao = await this.daoRef();
    const ideas = await dao.listWithoutLinks(limit);
    if (ideas.length === 0) {
      return 0;
    }
    const tagDao = await this.tagDaoRef();
    let repaired = 0;
    for (const idea of ideas) {
      const names = parseTags(idea.content);
      if (names.length === 0) {
        continue;
      }
      try {
        await tagDao.syncIdeaTags(idea.id, names);
        repaired++;
      } catch (err) {
        const error = err as Error;
        Logger.warn(`标签自愈失败（idea=${idea.id}）：${error.message}`);
      }
    }
    return repaired;
  }

  /**
   * 同步标签，失败只记警告。
   *
   * 吞掉异常在这里是**故意的**，和 `RdbSql` 里「异常必须外抛」的规则不矛盾：
   * 那条规则针对的是「数据库操作失败要让人知道」，而这里失败的只是索引，
   * 主数据（正文）已经落库成功；把它抛出去只会让保存显示失败、诱导用户重复提交。
   */
  private async syncTagsQuietly(ideaId: number, names: string[]): Promise<void> {
    try {
      const tagDao = await this.tagDaoRef();
      await tagDao.syncIdeaTags(ideaId, names);
    } catch (err) {
      const error = err as Error;
      Logger.warn(`标签同步失败，正文已保存（idea=${ideaId}），启动时会自动补回：${error.message}`);
    }
  }

  async setPinned(id: number, pinned: boolean): Promise<void> {
    const dao = await this.daoRef();
    await dao.updatePinned(id, pinned);
  }

  async setDeleted(id: number, deleted: boolean): Promise<void> {
    const dao = await this.daoRef();
    // 删除时间在这里取一次：DAO 只管写，不做时间决定；撤销时同一入口写回 0
    await dao.updateDeleted(id, deleted, Date.now());
  }

  async listDeleted(): Promise<Idea[]> {
    const dao = await this.daoRef();
    return await dao.listDeleted(this.trashCutoff());
  }

  async countDeleted(): Promise<number> {
    const dao = await this.daoRef();
    return await dao.countDeleted(this.trashCutoff());
  }

  async deleteForever(id: number): Promise<void> {
    const dao = await this.daoRef();
    await dao.deleteForever(id);
  }

  async clearDeleted(): Promise<number> {
    const dao = await this.daoRef();
    return await dao.clearDeleted();
  }

  async purgeExpired(): Promise<number> {
    const dao = await this.daoRef();
    return await dao.purgeExpired(this.trashCutoff());
  }

  /** 保留期截止点：删除时间早于它就算过期 */
  private trashCutoff(): number {
    return Date.now() - TRASH_RETENTION_MS;
  }
}

/**
 * 全应用唯一的仓库实例。
 *
 * 页面在 `aboutToAppear` 里调用它即可，不需要自己管生命周期：
 * `RdbHelper` 已经把「连接只开一次」这件事兜住了，这里再保证「DAO 只建一次」。
 */
let repository: IdeaRepository | null = null;

export function getIdeaRepository(context: common.Context): IdeaRepository {
  const cached = repository;
  if (cached !== null) {
    return cached;
  }
  const created: IdeaRepository = new RdbIdeaRepository(context);
  repository = created;
  return created;
}
