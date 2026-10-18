import { relationalStore } from '@kit.ArkData';
import { Idea, IdeaSource } from '../model/Idea';
import { DayStat } from '../model/DayStat';
import { IdeaFilter } from '../model/IdeaFilter';
import { closeQuietly, execute, query } from './RdbSql';
import { Logger } from '../utils/Logger';

/**
 * 查询列。显式列出而不是 `SELECT *`：
 * 以后加列时 `*` 会悄悄带回多余数据，显式列能让「加字段忘改映射」立刻暴露成编译错误。
 */
const COLUMNS: string = 'id, content, created_at, updated_at, pinned, deleted, deleted_at, source';

const SQL_FIND_BY_ID: string = `SELECT ${COLUMNS} FROM idea WHERE id = ?`;

/**
 * 带表名前缀的列清单：下面那条要 JOIN `idea_tag`，不加前缀时
 * 「哪张表的列」只能靠人去核对，加前缀后即使以后 `idea_tag` 也加同名列也不会突然歧义。
 */
const COLUMNS_QUALIFIED: string = 'idea.id AS id, idea.content AS content, idea.created_at AS created_at, ' +
  'idea.updated_at AS updated_at, idea.pinned AS pinned, idea.deleted AS deleted, ' +
  'idea.deleted_at AS deleted_at, idea.source AS source';

/** 排序是产品语义（置顶恒在最前，其余按创建时间倒序），筛选条目的顺序不影响它 */
const SQL_ORDER: string = 'ORDER BY pinned DESC, created_at DESC';

/** 没有任何标签关联的灵感（自愈用）。排序与列表一致，保证优先修用户最可能看到的那几条 */
const SQL_IDEAS_WITHOUT_LINKS: string = `SELECT ${COLUMNS_QUALIFIED} FROM idea ` +
  'LEFT JOIN idea_tag ON idea_tag.idea_id = idea.id ' +
  `WHERE idea.deleted = 0 AND idea_tag.idea_id IS NULL ${SQL_ORDER} LIMIT ?`;

/**
 * 全量导出用（M4）：所有未删除的灵感，按创建时间**正序**。
 *
 * 两点刻意为之：
 *  ① **不带任何筛选条件** —— 导出是备份，只导「当前筛选出来的那几条」等于骗用户；
 *  ② 排除 `deleted = 1` —— 软删除的行留在库里是为了 5 秒撤销与「最近删除」（回收站），
 *     把它们写进备份文件等于把垃圾桶一起打包，导入时又得再判一次。
 */
const SQL_LIST_ALL_ACTIVE_HEAD: string = `SELECT ${COLUMNS} FROM idea WHERE `;

/**
 * 导入查重：同正文 + 同创建时间即视为同一条，**只和仍未删除的行比**。
 *
 * 为什么不再把软删除的行一起算（1.0.0 审核问题 1）：用户「删除 → 再导入备份」时，
 * 那些行其实还在库里（只标了 `deleted = 1`），旧口径把每一条都判成重复，
 * 界面上就只剩「跳过重复」，备份一条也导不回来。备份的语义是「把这份文件里的东西找回来」，
 * 已经删掉的那条恰恰最需要被找回 —— 所以命中的软删除行交给 `SQL_FIND_DELETED_SAME` 复活，
 * 而不是当作重复丢弃。同一份备份导入两次时，第二次命中的是已经复活的行，照样一条都不新增。
 */
const SQL_COUNT_SAME_ACTIVE: string = 'SELECT COUNT(*) AS total FROM idea WHERE deleted = 0 AND content = ? AND created_at = ?';

/**
 * 导入时找一条**被软删除的**同内容同时间记录（取 id 最小的那条），供「复活」用。
 * 恢复只需要把 `deleted` 置回 0：正文、置顶状态、标签关联都原样还在，
 * 比重新插一条更省事，也不会让同一条灵感在库里出现两份。
 */
const SQL_FIND_DELETED_SAME: string = 'SELECT id FROM idea WHERE deleted = 1 AND content = ? AND created_at = ? ORDER BY id ASC LIMIT 1';

/**
 * 「最近删除」列表：已删除、且删除时间还在保留期内。
 *
 * `deleted_at > 0` 是给手工改库/异常行兜底：迁移会把历史行补成迁移时刻，
 * 正常不会有 0；真遇到 0 时宁可不显示，也不要让它们永远霸占回收站。
 * 排序按 `deleted_at DESC`：回收站里用户关心的是「最近删的」，不是「最早建的」。
 */
const SQL_LIST_DELETED: string = `SELECT ${COLUMNS} FROM idea ` +
  'WHERE deleted = 1 AND deleted_at > 0 AND deleted_at >= ? ORDER BY deleted_at DESC, id DESC';

/** 与 `SQL_LIST_DELETED` 同口径的条数 */
const SQL_COUNT_DELETED: string = 'SELECT COUNT(*) AS total FROM idea WHERE deleted = 1 AND deleted_at > 0 AND deleted_at >= ?';

/** 清理口径：早于截止时间的已删除行（列表用 >=，清理用 <，同一条不会既显示又被删） */
const SQL_COUNT_EXPIRED: string = 'SELECT COUNT(*) AS total FROM idea WHERE deleted = 1 AND deleted_at > 0 AND deleted_at < ?';
const SQL_COUNT_ALL_DELETED: string = 'SELECT COUNT(*) AS total FROM idea WHERE deleted = 1';

/**
 * 物理删除分两步：先断 `idea_tag` 关联，再删主行。
 *
 * 不引入 `beginTransaction/commit/rollBack`：ArkTS 下这套同步 API 的异常路径要写三处 try，
 * 而中途失败最坏只留下孤儿关联行 —— 所有读取都 JOIN `idea` 且带 `deleted = 0`，用户看不见；
 * 正文里的标签还能由启动自愈补回。**顺序不能反**：先删主行会留下无法定位的关联。
 */
const SQL_DELETE_LINKS_BY_IDEA: string = 'DELETE FROM idea_tag WHERE idea_id = ?';
const SQL_DELETE_IDEA_IF_DELETED: string = 'DELETE FROM idea WHERE id = ? AND deleted = 1';
const SQL_DELETE_LINKS_EXPIRED: string = 'DELETE FROM idea_tag WHERE idea_id IN ' +
  '(SELECT id FROM idea WHERE deleted = 1 AND deleted_at > 0 AND deleted_at < ?)';
const SQL_DELETE_EXPIRED: string = 'DELETE FROM idea WHERE deleted = 1 AND deleted_at > 0 AND deleted_at < ?';
const SQL_DELETE_LINKS_ALL_DELETED: string = 'DELETE FROM idea_tag WHERE idea_id IN ' +
  '(SELECT id FROM idea WHERE deleted = 1)';
const SQL_DELETE_ALL_DELETED: string = 'DELETE FROM idea WHERE deleted = 1';

/**
 * 顶层的「未删除」条件。
 * 筛选条件拼在它后面，全部用 AND —— 关键词与标签是**取交集**，不是二选一。
 */
const CONDITION_ACTIVE: string = 'deleted = 0';

/**
 * 导出用：整库未删除的灵感，按时间正序。
 * 拼在 `CONDITION_ACTIVE` 之后（常量声明有先后，ArkTS 不接受「先用后声明」）。
 */
const SQL_LIST_ALL_ACTIVE: string = `${SQL_LIST_ALL_ACTIVE_HEAD}${CONDITION_ACTIVE} ` +
  'ORDER BY created_at ASC, id ASC';

/**
 * `LIKE` 的转义字符。
 * 默认的 `LIKE` 把 `%` / `_` 当通配符：用户搜「50%」时那个 `%` 会变成「任意字符」，
 * 搜出一条毫不相干的记录。所以显式声明 `\` 为转义符，并在 `escapeLike` 里转义用户输入。
 */
const LIKE_ESCAPE: string = " ESCAPE '\\'";

/** 一次查询里拼出来的 WHERE 子句与它的参数（顺序必须与 `?` 一一对应） */
class WhereParts {
  clause: string = CONDITION_ACTIVE;
  args: relationalStore.ValueType[] = [];
}

/**
 * 转义用户输入里的 LIKE 元字符。
 * 用 split/join 而不是正则 + `replaceAll`：正则要处理 `\` 自身的转义，
 * 写错一个反斜杠就会静默搜错结果，而 split/join 的语义一眼可读。
 */
function escapeLike(keyword: string): string {
  return keyword
    .split('\\').join('\\\\')
    .split('%').join('\\%')
    .split('_').join('\\_');
}

/**
 * `idea` 表的读写。
 *
 * 只做两件事：拼 SQL、把 ResultSet 映射成 `Idea`。
 * 单条查询**不做分页缓存、不做内存索引**——万条以内的数据量交给 SQLite 的索引更划算，
 * 等 M3 的热力图/标签云真的慢了再加聚合缓存表。
 *
 * 关于异常：所有会抛异常的调用都收口到 `RdbSql` 的 `query` / `closeQuietly`，
 * 这里只补业务上下文日志再原样抛出。
 */
export class IdeaDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /**
   * 插入一条灵感，返回自增主键。
   *
   * `pinned` / `deleted` / `source` 显式写值而不是依赖建表时的 DEFAULT：
   * relationalStore 的 ValuesBucket 会忽略 undefined，靠 DEFAULT 也能跑，
   * 但显式写出来后，「新建的灵感一定是未置顶未删除」这件事在代码里就是看得见的。
   */
  async insert(content: string, now: number, source: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'content': content,
      'created_at': now,
      'updated_at': now,
      'pinned': 0,
      'deleted': 0,
      'deleted_at': 0,
      'source': source
    };
    try {
      return await this.store.insert('idea', values);
    } catch (err) {
      const error = err as Error;
      Logger.error(`插入灵感失败：${error.message}`);
      throw error;
    }
  }

  /**
   * 取一页（按 `pinned DESC, created_at DESC`），带上筛选条件。
   * 用 `querySql` 而不是 `RdbPredicates`：谓词的 orderByDesc 多次调用时链式顺序
   * 依赖实现细节，而这里「置顶优先、再按时间倒序」的顺序是产品语义，必须写死；
   * 标签交集需要子查询，谓词 API 也表达不了。
   */
  async listPage(offset: number, limit: number, filter: IdeaFilter): Promise<Idea[]> {
    const where = IdeaDao.buildWhere(filter);
    const sql = `SELECT ${COLUMNS} FROM idea WHERE ${where.clause} ${SQL_ORDER} LIMIT ? OFFSET ?`;
    const args: relationalStore.ValueType[] = where.args.concat([limit, offset]);
    const resultSet = await query(this.store, sql, args);
    try {
      const list: Idea[] = [];
      while (resultSet.goToNextRow()) {
        list.push(IdeaDao.mapRow(resultSet));
      }
      return list;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取列表失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  async findById(id: number): Promise<Idea | null> {
    const resultSet = await query(this.store, SQL_FIND_BY_ID, [id]);
    try {
      if (resultSet.goToNextRow()) {
        return IdeaDao.mapRow(resultSet);
      }
      return null;
    } catch (err) {
      const error = err as Error;
      Logger.error(`按 id 读取灵感失败（id=${id}）：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 统计条数。
   * 必须带上与列表**完全相同的**筛选条件：顶部「N 条灵感」和尾部「到底了 · 共 N 条」
   * 都读这个数字，筛选时如果还在报全库总数，用户会以为筛选没生效。
   */
  async countActive(filter: IdeaFilter): Promise<number> {
    const where = IdeaDao.buildWhere(filter);
    const sql = `SELECT COUNT(*) AS total FROM idea WHERE ${where.clause}`;
    const resultSet = await query(this.store, sql, where.args);
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('total'));
      }
      return 0;
    } catch (err) {
      const error = err as Error;
      Logger.error(`统计灵感条数失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 按天统计（时间轴分组头的条数）。
   *
   * 日期用 `date(created_at / 1000, 'unixepoch', 'localtime')`，与 `DateUtil.dateKey`
   * 一样是**本地时区**的日期——两边口径必须一致，否则分组头会和它所在的组错开一天。
   * `created_at` 存的是毫秒，而 SQLite 的 `unixepoch` 只认秒，所以先整除 1000。
   *
   * 为什么不让界面自己数已加载的行：那个数字会随翻页长大（见 `DayStat` 的注释）。
   */
  async listDayStats(filter: IdeaFilter): Promise<DayStat[]> {
    const where = IdeaDao.buildWhere(filter);
    const sql = "SELECT date(created_at / 1000, 'unixepoch', 'localtime') AS day, COUNT(*) AS total, "
      + 'SUM(CASE WHEN pinned = 1 THEN 1 ELSE 0 END) AS pinned_total '
      + `FROM idea WHERE ${where.clause} GROUP BY day ORDER BY day DESC`;
    const resultSet = await query(this.store, sql, where.args);
    try {
      const list: DayStat[] = [];
      while (resultSet.goToNextRow()) {
        const stat = new DayStat();
        stat.day = resultSet.getString(resultSet.getColumnIndex('day'));
        stat.count = resultSet.getLong(resultSet.getColumnIndex('total'));
        stat.pinnedCount = resultSet.getLong(resultSet.getColumnIndex('pinned_total'));
        list.push(stat);
      }
      return list;
    } catch (err) {
      const error = err as Error;
      Logger.error(`按天统计失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 找出「正文里有标签、库里却没有任何关联行」的灵感（启动时标签自愈用）。
   *
   * 会出现这种记录，是因为真机上标签写入一度失败（见 `TagDao.syncIdeaTags` 的注释）：
   * 正文安全落库了，标签关联没写进去，那条灵感在筛选和标签云里就等于不存在。
   * 这里用 `LEFT JOIN ... IS NULL` 把它捞回来；正文里本来就没标签的灵感也会被捞出，
   * 由调用方解析正文后跳过 —— 一次字符串扫描，比在 SQL 里判断 `content LIKE '%#%'` 可靠。
   */
  async listWithoutLinks(limit: number): Promise<Idea[]> {
    const resultSet = await query(this.store, SQL_IDEAS_WITHOUT_LINKS, [limit]);
    try {
      const list: Idea[] = [];
      while (resultSet.goToNextRow()) {
        list.push(IdeaDao.mapRow(resultSet));
      }
      return list;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取缺少标签关联的灵感失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 随机取一条未删除的灵感（「灵光再现」用）。
   *
   * `excludeIds` 是 24 小时展示窗口，条数很小，直接用 `NOT IN` 排除。
   * `ORDER BY RANDOM()` 在万条量级是一次全表扫描（十几毫秒），而这个入口一天点几次，
   * 不值得为它维护一列随机数或额外索引——那是给「每秒抽一次」准备的复杂度。
   */
  async randomActive(excludeIds: number[]): Promise<Idea | null> {
    let sql = `SELECT ${COLUMNS} FROM idea WHERE ${CONDITION_ACTIVE}`;
    const args: relationalStore.ValueType[] = [];
    if (excludeIds.length > 0) {
      const holders: string[] = [];
      for (let i = 0; i < excludeIds.length; i++) {
        holders.push('?');
        args.push(excludeIds[i]);
      }
      sql += ` AND id NOT IN (${holders.join(',')})`;
    }
    sql += ' ORDER BY RANDOM() LIMIT 1';

    const resultSet = await query(this.store, sql, args);
    try {
      if (!resultSet.goToNextRow()) {
        return null;
      }
      return IdeaDao.mapRow(resultSet);
    } catch (err) {
      const error = err as Error;
      Logger.error(`随机抽取灵感失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 全量导出：所有未删除的灵感（含置顶、含正文里的全部内容），按创建时间正序。
   *
   * 不复用 `listPage`：那个口子要 offset/limit，还要拼筛选条件，
   * 拿它导全库得像调用方那样循环翻页，反而更容易漏掉尾巴上的几条。
   */
  async listAllActive(): Promise<Idea[]> {
    const resultSet = await query(this.store, SQL_LIST_ALL_ACTIVE);
    try {
      const list: Idea[] = [];
      while (resultSet.goToNextRow()) {
        list.push(IdeaDao.mapRow(resultSet));
      }
      return list;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取全部灵感失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 导入一条灵感：**原样写回创建/修改时间与置顶状态**，来源记为 `IdeaSource.IMPORT`。
   *
   * 为什么不复用 `insert(content, now, source)`：它只收正文，时间戳由它自己取当前时间，
   * 导入的灵感会全部被压成「刚刚创建」——时间轴分组、热力图、相对时间会一起散掉，
   * 用户看到的是「导入把我的数据弄坏了」。备份还原之后，应该长得和导出前一样。
   */
  async insertImported(content: string, createdAt: number, updatedAt: number, pinned: boolean): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'content': content,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'pinned': pinned ? 1 : 0,
      'deleted': 0,
      'deleted_at': 0,
      'source': IdeaSource.IMPORT
    };
    try {
      return await this.store.insert('idea', values);
    } catch (err) {
      const error = err as Error;
      Logger.error(`导入灵感失败：${error.message}`);
      throw error;
    }
  }

  /** 导入查重（见 `SQL_COUNT_SAME_ACTIVE`），只统计仍未删除的同内容同时间记录 */
  async countSameActive(content: string, createdAt: number): Promise<number> {
    const resultSet = await query(this.store, SQL_COUNT_SAME_ACTIVE, [content, createdAt]);
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('total'));
      }
      return 0;
    } catch (err) {
      const error = err as Error;
      Logger.error(`导入查重失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /**
   * 导入时找一条被软删除的同内容同时间记录（见 `SQL_FIND_DELETED_SAME`），返回它的 id。
   * 找不到返回 -1：这个负数同时表示「没有可复活的记录」，调用方据此决定是否插入新行。
   */
  async findDeletedSame(content: string, createdAt: number): Promise<number> {
    const resultSet = await query(this.store, SQL_FIND_DELETED_SAME, [content, createdAt]);
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('id'));
      }
      return -1;
    } catch (err) {
      const error = err as Error;
      Logger.error(`查找被删除的重复灵感失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /** 改内容。同时刷新 `updated_at`，卡片上的「已编辑」与列表排序都依赖它 */
  async updateContent(id: number, content: string, now: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'content': content,
      'updated_at': now
    };
    return await this.updateById(id, values);
  }

  /**
   * 置顶 / 取消置顶。
   * **刻意不刷新 `updated_at`**：置顶是整理动作不是内容修改，
   * 刷新它会让列表里冒出一堆「已编辑」提示，也会打乱「最近修改」的将来用途。
   */
  async updatePinned(id: number, pinned: boolean): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'pinned': pinned ? 1 : 0
    };
    return await this.updateById(id, values);
  }

  /**
   * 软删除 / 撤销删除。
   *
   * `at` 由调用方传入（仓库层取 `Date.now()`）：DAO 不自己取时间，将来单元测试
   * 才能喂固定时刻验证 7 天保留期的边界。
   */
  async updateDeleted(id: number, deleted: boolean, at: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'deleted': deleted ? 1 : 0,
      'deleted_at': deleted ? at : 0
    };
    return await this.updateById(id, values);
  }

  /** 最近删除列表（保留期内，最近删的在前）。`cutoff` = 现在 - 保留期 */
  async listDeleted(cutoff: number): Promise<Idea[]> {
    const resultSet = await query(this.store, SQL_LIST_DELETED, [cutoff]);
    try {
      const list: Idea[] = [];
      while (resultSet.goToNextRow()) {
        list.push(IdeaDao.mapRow(resultSet));
      }
      return list;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取最近删除失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  /** 与 `listDeleted` 同口径的条数 */
  async countDeleted(cutoff: number): Promise<number> {
    return await this.countScalar(SQL_COUNT_DELETED, [cutoff]);
  }

  /** 彻底删除一条已删除的灵感。SQL 带 `deleted = 1`，未删除的 id 不会被误删 */
  async deleteForever(id: number): Promise<void> {
    try {
      await execute(this.store, SQL_DELETE_LINKS_BY_IDEA, [id]);
      await execute(this.store, SQL_DELETE_IDEA_IF_DELETED, [id]);
    } catch (err) {
      const error = err as Error;
      Logger.error(`彻底删除灵感失败（id=${id}）：${error.message}`);
      throw error;
    }
  }

  /** 清空最近删除，返回清掉的条数 */
  async clearDeleted(): Promise<number> {
    const total = await this.countScalar(SQL_COUNT_ALL_DELETED, []);
    if (total === 0) {
      return 0;
    }
    await execute(this.store, SQL_DELETE_LINKS_ALL_DELETED);
    await execute(this.store, SQL_DELETE_ALL_DELETED);
    return total;
  }

  /** 清掉早于 `before` 的已删除行，返回清掉的条数 */
  async purgeExpired(before: number): Promise<number> {
    const total = await this.countScalar(SQL_COUNT_EXPIRED, [before]);
    if (total === 0) {
      return 0;
    }
    await execute(this.store, SQL_DELETE_LINKS_EXPIRED, [before]);
    await execute(this.store, SQL_DELETE_EXPIRED, [before]);
    return total;
  }

  /** 单值 COUNT 查询的收口（trash 相关的三条统计共用） */
  private async countScalar(sql: string, args: relationalStore.ValueType[]): Promise<number> {
    const resultSet = await query(this.store, sql, args);
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('total'));
      }
      return 0;
    } catch (err) {
      const error = err as Error;
      Logger.error(`统计失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }

  private async updateById(id: number, values: relationalStore.ValuesBucket): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('idea');
    predicates.equalTo('id', id);
    try {
      return await this.store.update(values, predicates);
    } catch (err) {
      const error = err as Error;
      Logger.error(`更新灵感失败（id=${id}）：${error.message}`);
      throw error;
    }
  }

  /**
   * 拼筛选条件。
   *
   * 标签交集用子查询表达：「选中标签全部命中」= 按 idea_id 分组后，
   * 命中的不同标签数等于选中个数。
   *   `HAVING COUNT(DISTINCT tag_id) = ?`
   * 比在内存里求多条 `IN` 的交集少一次往返，也能直接用上 `idx_idea_tag_tag`。
   */
  private static buildWhere(filter: IdeaFilter): WhereParts {
    const parts = new WhereParts();
    const keyword = filter.keyword.trim();
    if (keyword.length > 0) {
      parts.clause += ` AND content LIKE ?${LIKE_ESCAPE}`;
      parts.args.push(`%${escapeLike(keyword)}%`);
    }
    const tagIds = filter.tagIds;
    if (tagIds.length > 0) {
      const holders: string[] = [];
      for (let i = 0; i < tagIds.length; i++) {
        holders.push('?');
        parts.args.push(tagIds[i]);
      }
      parts.clause += ` AND id IN (SELECT idea_id FROM idea_tag WHERE tag_id IN (${holders.join(',')})`
        + ' GROUP BY idea_id HAVING COUNT(DISTINCT tag_id) = ?)';
      parts.args.push(tagIds.length);
    }
    const day = filter.dayKey;
    if (day.length > 0) {
      // 按天筛（热力图点某一格）。日期是算出来的，用不上 created_at 索引，
      // 万条量级一次全表扫描十几毫秒，够用；真要更快就改成 [当天 00:00, 次日 00:00) 的区间条件。
      parts.clause += " AND date(created_at / 1000, 'unixepoch', 'localtime') = ?";
      parts.args.push(day);
    }
    return parts;
  }

  private static mapRow(resultSet: relationalStore.ResultSet): Idea {
    try {
      const idea = new Idea();
      idea.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      idea.content = resultSet.getString(resultSet.getColumnIndex('content'));
      idea.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
      idea.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
      // SQLite 没有布尔类型，用 INTEGER 0/1 存
      idea.pinned = resultSet.getLong(resultSet.getColumnIndex('pinned')) === 1;
      idea.deleted = resultSet.getLong(resultSet.getColumnIndex('deleted')) === 1;
      idea.deletedAt = resultSet.getLong(resultSet.getColumnIndex('deleted_at'));
      idea.source = resultSet.getLong(resultSet.getColumnIndex('source'));
      if (idea.source !== IdeaSource.MANUAL
        && idea.source !== IdeaSource.FORM
        && idea.source !== IdeaSource.SHORTCUT
        && idea.source !== IdeaSource.IMPORT) {
        // 兜底：遇到不认识的值（比如手工改过库）当手动记录处理，不要让它传播出去
        idea.source = IdeaSource.MANUAL;
      }
      return idea;
    } catch (err) {
      const error = err as Error;
      Logger.error(`解析结果行失败：${error.message}`);
      throw error;
    }
  }
}
