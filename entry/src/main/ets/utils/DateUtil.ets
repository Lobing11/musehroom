/**
 * 日期与时间工具。
 *
 * 分工约定（避免各处各写一套、口径不一致）：
 *   - `dateKey()`      —— 分组键 `YYYY-MM-DD`，时间轴按它分日期组
 *   - `startOfDay()`   —— 当天 00:00 的时间戳，热力图分桶与「天数差」都基于它
 *   - `formatDayLabel()` —— 人类可读的日期头（今天 / 昨天 / 8 月 3 日）
 *   - `relativeTime()` —— 卡片右下角的相对时间（刚刚 / 12 分钟前）
 */

const MS_PER_MINUTE: number = 60000;
const MS_PER_HOUR: number = 3600000;
const MS_PER_DAY: number = 86400000;

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

/** 当天 00:00:00.000 的时间戳 */
export function startOfDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/** 分组键：`YYYY-MM-DD`（本地时区） */
export function dateKey(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear().toString()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** `HH:mm` */
export function formatTime(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** 两个时间戳相差几个自然日（按本地 00:00 计算，不受时分秒影响） */
export function daysBetween(fromMs: number, toMs: number): number {
  return Math.round((startOfDay(toMs) - startOfDay(fromMs)) / MS_PER_DAY);
}

/**
 * 日期头文案。
 *
 * 只给「今天/昨天」做特判：再往前用「几天前」反而要在脑子里换算，
 * 直接给日期更好用。
 */
export function formatDayLabel(ms: number, now: number): string {
  const days = daysBetween(ms, now);
  if (days <= 0) {
    return '今天';
  }
  if (days === 1) {
    return '昨天';
  }
  const d = new Date(ms);
  const monthDay = `${(d.getMonth() + 1).toString()} 月 ${d.getDate().toString()} 日`;
  const sameYear = d.getFullYear() === new Date(now).getFullYear();
  return sameYear ? monthDay : `${d.getFullYear().toString()} 年 ${monthDay}`;
}

/** 相对时间：7 天内用「N 天前」，更早回落成日期头 */
export function relativeTime(ms: number, now: number): string {
  const diff = now - ms;
  if (diff < MS_PER_MINUTE) {
    return '刚刚';
  }
  if (diff < MS_PER_HOUR) {
    return `${Math.floor(diff / MS_PER_MINUTE).toString()} 分钟前`;
  }
  if (diff < MS_PER_DAY) {
    return `${Math.floor(diff / MS_PER_HOUR).toString()} 小时前`;
  }
  const days = daysBetween(ms, now);
  if (days === 1) {
    return '昨天';
  }
  if (days < 7) {
    return `${days.toString()} 天前`;
  }
  return formatDayLabel(ms, now);
}
