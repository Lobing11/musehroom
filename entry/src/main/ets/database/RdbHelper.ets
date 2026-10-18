import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DB_NAME, DB_VERSION } from '../utils/Constants';
import { closeQuietly, query } from './RdbSql';
import { Logger } from '../utils/Logger';

/**
 * 建表语句。
 *
 * 三张表一次建齐（哪怕标签解析 M2 才做）：数据库版本迁移是应用里最容易出事的一段代码，
 * 能少升一次版本就少一次风险。`idea_tag` 的主键是 (idea_id, tag_id) 复合主键，
 * 天然保证「同一条灵感同一个标签不会重复关联」，解析时配合 `INSERT OR IGNORE` 即可。
 */
export const SQL_CREATE_IDEA: string = `
CREATE TABLE IF NOT EXISTS idea (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0,
  source INTEGER NOT NULL DEFAULT 0
)`;

/**
 * 时间轴主查询的覆盖索引。
 * 顺序刻意与 `ORDER BY pinned DESC, created_at DESC` 一致，且把 `deleted` 放在最前——
 * 它出现在每一个 WHERE 里，选择性虽低但能免掉回表判断。
 */
export const SQL_CREATE_IDEA_INDEX: string = `
CREATE INDEX IF NOT EXISTS idx_idea_created ON idea (deleted, pinned DESC, created_at DESC)`;

export const SQL_CREATE_TAG: string = `
CREATE TABLE IF NOT EXISTS tag (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)`;

export const SQL_CREATE_IDEA_TAG: string = `
CREATE TABLE IF NOT EXISTS idea_tag (
  idea_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (idea_id, tag_id)
)`;

/** 标签云/标签筛选要从 tag 反查 idea，必须单独给 tag_id 建索引 */
export const SQL_CREATE_IDEA_TAG_INDEX: string = `
CREATE INDEX IF NOT EXISTS idx_idea_tag_tag ON idea_tag (tag_id)`;

/**
 * v2：软删除的时间戳。
 *
 * 7 天保留期必须知道「什么时候删的」，而 `updated_at` 只记录内容修改：
 * 一条三年前记、昨天改、今天删的灵感，复用 `updated_at` 会让它一进回收站就过期。
 */
export const SQL_ADD_DELETED_AT: string = `
ALTER TABLE idea ADD COLUMN deleted_at INTEGER NOT NULL DEFAULT 0`;

/**
 * 回收站查询（`deleted = 1 AND deleted_at >= ?`）与清理（`deleted_at < ?`）的复合索引。
 * 与 `idx_idea_created` 一样，把区分度最低、但每条语句都出现的 `deleted` 放最前。
 */
export const SQL_CREATE_TRASH_INDEX: string = `
CREATE INDEX IF NOT EXISTS idx_idea_trash ON idea (deleted, deleted_at DESC)`;

/**
 * 数据库句柄的持有者。
 *
 * 三个要点：
 *  ① **单例**：relationalStore 每次 open 都是一个真实连接，重复打开会浪费内存并可能拿到
 *     不同的连接导致写冲突；全应用共用一个 store。
 *  ② **并发去重**：首次打开是异步的，页面 aboutToAppear 里可能同时发起两个查询。
 *     只缓存结果（store）不缓存过程（promise）的话，两次调用会同时走到 open。
 *     所以这里额外缓存 `opening`，让并发的第一波调用共享同一个打开过程。
 *  ③ **失败要能重试**：打开失败时不把失败结果缓存下来，否则一次偶发失败会让应用
 *     在这次生命周期里永久用不了数据库。
 */
export class RdbHelper {
  private static store: relationalStore.RdbStore | null = null;
  private static opening: Promise<relationalStore.RdbStore> | null = null;

  static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    const cached = RdbHelper.store;
    if (cached !== null) {
      return cached;
    }
    const inFlight = RdbHelper.opening;
    if (inFlight !== null) {
      return inFlight;
    }
    RdbHelper.opening = RdbHelper.open(context);
    try {
      const store = await RdbHelper.opening;
      RdbHelper.store = store;
      return store;
    } finally {
      // 无论成功失败都清掉在途标记：失败时要允许下一次调用重新尝试
      RdbHelper.opening = null;
    }
  }

  private static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    // securityLevel 决定落盘加密档位。S1 是不含敏感信息的普通数据，
    // 灵感内容属于用户私人文字，但 MVP 阶段不上 S3/S4（那要求设备级密钥与更重的开销）。
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await RdbHelper.openStore(context, config);
    await RdbHelper.migrate(store);
    Logger.info(`数据库就绪：${DB_NAME} v${store.version}`);
    return store;
  }

  /**
   * 打开数据库。
   * 异常照原样抛出：`getStore` 的调用方（预览首页、调试日志）都需要知道失败，
   * 这里只补一条带库名的日志，方便区分「打不开库」和「SQL 写错」这两类完全不同的故障。
   */
  private static async openStore(
    context: common.Context,
    config: relationalStore.StoreConfig
  ): Promise<relationalStore.RdbStore> {
    try {
      return await relationalStore.getRdbStore(context, config);
    } catch (err) {
      const error = err as Error;
      Logger.error(`打开数据库失败（${DB_NAME}）：${error.message}`);
      throw error;
    }
  }

  /**
   * 版本迁移。
   *
   * 新库的 `store.version` 是 0，所以「建表」本身就是 v1 的迁移动作。
   * 以后加字段时**不要**改上面的建表语句，而是追加 `if (from < 2) { ... }` 分支：
   * 老用户走 ALTER，新用户走完整建表，两条路都要能到同一个终态。
   */
  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    const from = store.version;
    if (from >= DB_VERSION) {
      return;
    }
    if (from < 1) {
      await RdbHelper.createInitialSchema(store);
    }
    if (from < 2) {
      await RdbHelper.migrateToV2(store);
    }
    store.version = DB_VERSION;
  }

  /**
   * v1 的建表动作。
   *
   * 五条语句**不放在一个事务里**：`executeSql` 逐个执行，中途失败时已经建好的表留着，
   * 下次启动 `IF NOT EXISTS` 会跳过它们继续补——比回滚成空库更接近「幂等重试」。
   * 异常必须往外抛：带着半套 schema 继续跑，后面的报错会离真正的原因很远。
   */
  private static async createInitialSchema(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(SQL_CREATE_IDEA);
      await store.executeSql(SQL_CREATE_IDEA_INDEX);
      await store.executeSql(SQL_CREATE_TAG);
      await store.executeSql(SQL_CREATE_IDEA_TAG);
      await store.executeSql(SQL_CREATE_IDEA_TAG_INDEX);
    } catch (err) {
      const error = err as Error;
      Logger.error(`建表失败：${error.message}`);
      throw error;
    }
  }

  /**
   * v2：加 `deleted_at`，并给升级前就存在的软删除行一次 7 天宽限。
   *
   * 三件事的顺序不能换：
   *  ① 先加列 —— 下面的 UPDATE 与索引都依赖它；
   *  ② 再建索引 —— 空表/小表都很快，放在 UPDATE 之前也不影响结果，但语义上属于新结构；
   *  ③ 最后补删除时间 —— 旧行的删除时刻没有记录，按「迁移这一刻」算，让它们像刚删的
   *     一样再保留 7 天。否则 `deleted_at = 0` 会被清理逻辑当成「早已过期」直接抹掉，
   *     用户升级后连找回的机会都没有。
   *
   * 这三条也必须**幂等可重试**：中途失败时版本号还没推进，下次启动会重跑；
   * `ALTER TABLE ADD COLUMN` 在列已存在时会报错，所以迁移函数用列探测兜住重入。
   */
  private static async migrateToV2(store: relationalStore.RdbStore): Promise<void> {
    try {
      if (!(await RdbHelper.hasColumn(store, 'idea', 'deleted_at'))) {
        await store.executeSql(SQL_ADD_DELETED_AT);
      }
      await store.executeSql(SQL_CREATE_TRASH_INDEX);
      await store.executeSql('UPDATE idea SET deleted_at = ? WHERE deleted = 1 AND deleted_at = 0', [Date.now()]);
    } catch (err) {
      const error = err as Error;
      Logger.error(`数据库 v2 迁移失败：${error.message}`);
      throw error;
    }
  }

  /** 列是否存在（`PRAGMA table_info` 的 name 列）。迁移重入时用来跳过已加过的列 */
  private static async hasColumn(store: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
    const resultSet = await query(store, `PRAGMA table_info(${table})`);
    try {
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(resultSet.getColumnIndex('name')) === column) {
          return true;
        }
      }
      return false;
    } catch (err) {
      const error = err as Error;
      Logger.error(`读取表结构失败：${error.message}`);
      throw error;
    } finally {
      closeQuietly(resultSet);
    }
  }
}
