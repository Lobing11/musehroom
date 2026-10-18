import { relationalStore } from '@kit.ArkData';
import { Logger } from '../utils/Logger';

/**
 * SQL 收口（各 DAO 共用）。
 *
 * 三件事只在这里做一次：
 *  ① 日志里带上 SQL —— 出问题时不用再猜是哪条语句；
 *     但**参数不写进日志**：参数里可能就是用户的灵感正文，不该出现在系统日志里。
 *  ② 异常照原样抛出。DAO 层吞掉数据库错误只会变成「点了没反应」，
 *     故障必须让 ViewModel → 页面看得见并给出提示。
 *  ③ ArkTS 会检查「会抛异常的接口是否被显式处理」，`try/finally` **不算**处理，
 *     必须带 `catch`；把 catch 集中在几个函数里，业务代码才不必满屏 try/catch。
 */
export async function query(
  store: relationalStore.RdbStore,
  sql: string,
  args?: relationalStore.ValueType[]
): Promise<relationalStore.ResultSet> {
  try {
    if (args === undefined) {
      return await store.querySql(sql);
    }
    return await store.querySql(sql, args);
  } catch (err) {
    const error = err as Error;
    Logger.error(`查询失败：${sql}：${error.message}`);
    throw error;
  }
}

export async function execute(
  store: relationalStore.RdbStore,
  sql: string,
  args?: relationalStore.ValueType[]
): Promise<void> {
  try {
    if (args === undefined) {
      await store.executeSql(sql);
      return;
    }
    await store.executeSql(sql, args);
  } catch (err) {
    const error = err as Error;
    Logger.error(`执行 SQL 失败：${sql}：${error.message}`);
    throw error;
  }
}

/**
 * 关游标。**这是唯一被吞掉的异常**：关失败没有补救手段，记一笔就行，
 * 更不能让它盖掉真正有价值的那个查询异常。
 */
export function closeQuietly(resultSet: relationalStore.ResultSet): void {
  try {
    resultSet.close();
  } catch (err) {
    const error = err as Error;
    Logger.warn(`关闭 ResultSet 失败：${error.message}`);
  }
}
