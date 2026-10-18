import { relationalStore } from '@kit.ArkData';
import { Tag } from '../model/Tag';
import { IdeaTagLink } from '../model/IdeaTagLink';
import { closeQuietly, execute, query } from './RdbSql';
import { Logger } from '../utils/Logger';

/**
 * `tag` / `idea_tag` 两张表的读写。
 *
 * 标签与正文的关系是「正文是唯一事实来源，这两张表只是它的索引」：
 * 每次保存正文都**按当前正文重建**这条灵感的标签关联（先清空再插入），
 * 而不是去算增删差异 —— 差异算法要考虑改名/大小写/转义，出错概率远高于
 * 「删掉重来」这点开销（一条灵感通常两三个标签）。
 *
 * 频次统计只算未删除的灵感：软删除的行留在库里，但不该继续给标签云贡献权重。
 */
const SQL_LIST_TAGS: string = `
SELECT t.id AS id, t.name AS name, COUNT(it.idea_id) AS cnt
FROM tag t
JOIN idea_tag it ON it.tag_id = t.id
JOIN idea i ON i.id = it.idea_id
WHERE i.deleted = 0
GROUP BY t.id, t.name
ORDER BY cnt DESC, t.name ASC`;

const SQL_CLEAR_LINKS: string = 'DELETE FROM idea_tag WHERE idea_id = ?';

/** 删除「本条灵感上、但已不属于当前正文」的旧关联（占位符数量随标签数动态拼） */
const SQL_DELETE_STALE_PREFIX: string = 'DELETE FROM idea_tag WHERE idea_id = ? AND tag_id NOT IN (';

/**
 * 大小写不敏感地找标签。
 *
 * 建表时 `name` 上的 UNIQUE 是区分大小写的（SQLite 默认 BINARY），
 * 而产品要求是「大小写归一、保留首次写法」，所以查重必须显式 `COLLATE NOCASE`：
 * 先按 NOCASE 查，查不到才插入 —— 这样 `#Idea` 之后再打 `#idea` 会复用同一行。
 * UNIQUE 仍然保留，作为「完全相同」的最后一道保险。
 */
const SQL_FIND_TAG_ID: string = 'SELECT id FROM tag WHERE name = ? COLLATE NOCASE';
const SQL_INSERT_TAG: string = 'INSERT OR IGNORE INTO tag (name, created_at) VALUES (?, ?)';
const SQL_LINK: string = 'INSERT OR IGNORE INTO idea_tag (idea_id, tag_id) VALUES (?, ?)';

/**
 * 全量「灵感 ↔ 标签名」关联（M4 导出用）。
 *
 * 这里**不做产品判断**（不加 `i.deleted = 0`）：导出只会写出未删除的灵感，
 * 由导出服务拿着灵感集合去对这份关联表，命中不了的关联自然被丢掉。
 * 一条 SQL 只管一件事，将来回收站要按标签查也不会被这个条件挡回来。
 */
const SQL_LIST_ALL_LINKS: string = 'SELECT it.idea_id AS idea_id, t.name AS name '
  + 'FROM idea_tag it JOIN tag t ON t.id = it.tag_id ORDER BY it.idea_id ASC, t.name ASC';

export class TagDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 标签清单（按使用频次倒序，同频次按名字），M2 的筛选条与 M3 的标签云共用 */
  async listTagsWithCount(): Promise<Tag[]> {
    const resultSet = await query(this.store, SQL_LIST_TAGS);
    try {
      const tags: Tag[] = [];
      while (resultSet.goToNextRow()) {
        const tag = new Tag();
        tag.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        tag.name = resultSet.getString(resultSet.getColumnIndex('name'));
        tag.count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
        tags.push(tag);
      }
      return tags;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取标签清单失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 全量关联（导出用，见 `SQL_LIST_ALL_LINKS`）。
   * 返回的是「灵感 id + 标签名」的扁平行，导出服务按 id 归拢成每条灵感的标签数组。
   */
  async listAllLinks(): Promise<IdeaTagLink[]> {
    const resultSet = await query(this.store, SQL_LIST_ALL_LINKS);
    try {
      const links: IdeaTagLink[] = [];
      while (resultSet.goToNextRow()) {
        const link = new IdeaTagLink();
        link.ideaId = resultSet.getLong(resultSet.getColumnIndex('idea_id'));
        link.tagName = resultSet.getString(resultSet.getColumnIndex('name'));
        links.push(link);
      }
      return links;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取全部标签关联失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 把一条灵感的标签关联更新为 `names`。
   *
   * ⚠️ 这里**不能用事务**，原因是真机实测出来的：
   *   - `beginTrans()` → `801 Capability not support`（`rollback(txId)` 同理），
   *     裸 `ROLLBACK` SQL 也是 801；
   *   - 只有 `beginTransaction()` + `commit()` 这一对能用，而**没有配套回滚**——
   *     一旦中途失败，留下的是一个未提交的事务，之后所有写入都会莫名其妙挂在它上面。
   * 所以事务在这里不是「更安全」，而是「更危险」，改用「**先加、后删**」的幂等写法：
   *   ① 先把当前正文里的标签全部关联上（`INSERT OR IGNORE`，重复执行无副作用）
   *   ② 最后才删掉不再需要的旧关联
   * 中途失败的后果是「多留几个旧标签」或「少几个新标签」，都是派生数据的小偏差：
   * 正文才是唯一事实来源，筛选条按正文解析，下一次编辑或启动自愈会把它修回来。
   * 相比之下，原来「先清空、再重建」的写法在中间失败会让这条灵感丢掉**全部**标签。
   */
  async syncIdeaTags(ideaId: number, names: string[]): Promise<void> {
    const now = Date.now();
    const tagIds: number[] = [];
    for (const name of names) {
      const tagId = await this.ensureTagId(name, now);
      if (tagId > 0) {
        tagIds.push(tagId);
        await execute(this.store, SQL_LINK, [ideaId, tagId]);
      }
    }
    await this.deleteStaleLinks(ideaId, tagIds);
  }

  /** 清掉不属于当前正文的旧关联（必须晚于新增执行，见 `syncIdeaTags` 的注释） */
  private async deleteStaleLinks(ideaId: number, tagIds: number[]): Promise<void> {
    if (tagIds.length === 0) {
      await execute(this.store, SQL_CLEAR_LINKS, [ideaId]);
      return;
    }
    const args: relationalStore.ValueType[] = [ideaId];
    let placeholders: string = '';
    for (const tagId of tagIds) {
      args.push(tagId);
      placeholders += placeholders.length === 0 ? '?' : ', ?';
    }
    await execute(this.store, `${SQL_DELETE_STALE_PREFIX}${placeholders})`, args);
  }

  /** 取已有标签 id，没有就建一个，返回它的 id（0 表示既没查到也建不出来） */
  private async ensureTagId(name: string, now: number): Promise<number> {
    const existing = await this.findTagId(name);
    if (existing > 0) {
      return existing;
    }
    await execute(this.store, SQL_INSERT_TAG, [name, now]);
    return await this.findTagId(name);
  }

  private async findTagId(name: string): Promise<number> {
    const resultSet = await query(this.store, SQL_FIND_TAG_ID, [name]);
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('id'));
      }
      return 0;
    } catch (err) {
      const error = err as Error;
      Logger.error(`查找标签失败（${name}）：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }
}
