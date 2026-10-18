/**
 * 「最近删除」保留期的纯计算。
 *
 * 为什么单独拆出来：7 天边界是最容易差一天的地方，而 DAO/仓库层直接取 `Date.now()`，
 * 在本地单测里没法喂固定时刻。把算术放进纯函数，边界就能被 `TrashRetention.test.ets`
 * 钉死；DAO 的 SQL 口径（列表 `>= cutoff`、清理 `< cutoff`）与这里一一对应。
 */
import { TRASH_RETENTION_MS } from './Constants';

/** 一天的毫秒数（保留期按 7×24 小时算，不按「自然日 0 点」切） */
export const DAY_MS: number = 24 * 60 * 60 * 1000;

/** 保留期是几天：界面上「还剩 N 天」的上限，也用来防止走字滞后把 N 算成 8 */
export const TRASH_RETENTION_DAYS: number = Math.round(TRASH_RETENTION_MS / DAY_MS);

/**
 * 还能放几天：向上取整，0 表示**今天到期**（调用方仍应显示、只是文案换成「今天到期」）。
 *
 * `deletedAt <= 0` 视为没有删除时间（历史行/异常行），直接返回 0，不让它显示成 7 天。
 * 刚删除时返回 7；删除后 1 小时仍是 7，到第 7 天整天结束才变 0。
 *
 * 上限夹到 `TRASH_RETENTION_DAYS`：界面的 `now` 来自每分钟走一次的 `nowTick`，
 * 刚删完那一刻它最多落后一分钟，`ceil(7 天差 + 落后量)` 会算出 8 天 —— 真机上就是这么看到的。
 */
export function trashRemainingDays(deletedAt: number, now: number): number {
  if (deletedAt <= 0) {
    return 0;
  }
  const remaining = deletedAt + TRASH_RETENTION_MS - now;
  if (remaining <= 0) {
    return 0;
  }
  return Math.min(TRASH_RETENTION_DAYS, Math.ceil(remaining / DAY_MS));
}

/**
 * 是否已过保留期。
 *
 * 与 DAO 的清理口径严格一致：`deleted_at < now - 保留期`；恰好等于截止点的记录
 * 仍算「今天到期」，列表还能看到，下一次启动才会被清掉。
 */
export function isTrashExpired(deletedAt: number, now: number): boolean {
  if (deletedAt <= 0) {
    return true;
  }
  return deletedAt < now - TRASH_RETENTION_MS;
}
