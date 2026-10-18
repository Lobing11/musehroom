/**
 * 热力图网格计算（纯函数，方便单测）。
 *
 * 输入是数据库聚合出来的「每天几条」（`DayStat[]`），输出是 12 周 × 7 天的网格。
 * 刻意不做的事：不在这里查库、不数已加载的行（纪律 16）。
 *
 * 两个口径决定：
 *   1) 周对齐到**周一**（国内习惯；GitHub 那种周日开头会让人对不上「这周」是哪一列）。
 *   2) 日期推进用 `Date.setDate(getDate() ± n)` 而不是加减 86400000——
 *      后者在夏令时切换那天会错一小时（国内现在没有夏令时，但没必要留这个坑）。
 */
import { DayStat } from '../model/DayStat';
import { HeatCell, HeatmapData } from '../model/StatsData';
import { dateKey, startOfDay } from './DateUtil';

/** 展示的周数：12 周 ≈ 一个季度，够看出习惯又不会挤成一片 */
export const HEATMAP_WEEKS: number = 12;

const WEEKDAYS: number = 7;

/** 'YYYY-MM-DD' → 条数；没有记录的天返回 0 */
function countOf(stats: DayStat[], day: string): number {
  for (let i = 0; i < stats.length; i++) {
    if (stats[i].day === day) {
      return stats[i].count;
    }
  }
  return 0;
}

/** 当前连续记录天数：今天还没记就从昨天往回数（否则白天看到的永远是 0） */
function streakOf(counts: number[], todayIndex: number): number {
  let index = todayIndex;
  if (index >= 0 && index < counts.length && counts[index] === 0) {
    index = index - 1;
  }
  let streak = 0;
  while (index >= 0 && counts[index] > 0) {
    streak = streak + 1;
    index = index - 1;
  }
  return streak;
}

/**
 * 生成近 12 周热力图。
 *
 * @param stats 数据库聚合结果（`IdeaDao.listDayStats`），顺序不限
 * @param now 当前时间戳（毫秒）——写成参数而不是内部 `Date.now()`，测起来才能固定「今天」
 */
export function buildHeatmap(stats: DayStat[], now: number): HeatmapData {
  const data = new HeatmapData();
  const todayStart = startOfDay(now);

  // 本周周一
  const weekStart = new Date(todayStart);
  const weekdayOfToday = (weekStart.getDay() + 6) % 7; // getDay(): 0 = 周日 → 0 = 周一
  weekStart.setDate(weekStart.getDate() - weekdayOfToday);

  // 从 11 周前的周一开始，一天一天往后走
  const cursor = new Date(weekStart.getTime());
  cursor.setDate(cursor.getDate() - (HEATMAP_WEEKS - 1) * WEEKDAYS);

  const cells: HeatCell[] = [];
  const counts: number[] = [];
  let maxCount = 0;
  let totalCount = 0;
  let activeDays = 0;
  // 连续天数必须从「今天」往回数，不能从网格末尾（本周的周日，可能还在未来）往回数
  let todayIndex = -1;

  // 月份标签：只标在「这一列里出现某月 1 号」的那一列（第一列永远标）。
  //
  // 不能按「这一天跨月了就标」来算：标签最终画在每列第一格（周一）上，
  // 而月份常常从周中开始（例如 10 月 1 日是周三），跨月那天落在列中间，
  // 标签就永远画不出来 —— 真机上的表现是整排只显示了最左边那一个月。
  let weekFirstMonth = -1;
  let weekMonthStartLabel = '';

  for (let week = 0; week < HEATMAP_WEEKS; week++) {
    for (let weekday = 0; weekday < WEEKDAYS; weekday++) {
      const dayMs = cursor.getTime();
      const dayDate = new Date(dayMs);
      const cell = new HeatCell();
      cell.day = dateKey(dayMs);
      cell.count = countOf(stats, cell.day);
      cell.weekIndex = week;
      cell.weekday = weekday;
      cell.inFuture = dayMs > todayStart;

      if (weekday === 0) {
        weekFirstMonth = dayDate.getMonth();
        weekMonthStartLabel = '';
      }
      if (dayDate.getDate() === 1) {
        weekMonthStartLabel = `${dayDate.getMonth() + 1} 月`;
      }

      cells.push(cell);
      counts.push(cell.inFuture ? -1 : cell.count);
      if (dayMs === todayStart) {
        todayIndex = cells.length - 1;
      }

      if (!cell.inFuture) {
        totalCount = totalCount + cell.count;
        if (cell.count > 0) {
          activeDays = activeDays + 1;
        }
        if (cell.count > maxCount) {
          maxCount = cell.count;
        }
      }

      // 一列走完，把这一列的月份标签写回它的第一格（视图只读每列第一格）
      if (weekday === WEEKDAYS - 1) {
        const monday: HeatCell = cells[week * WEEKDAYS];
        monday.monthLabel = week === 0 ? `${weekFirstMonth + 1} 月` : weekMonthStartLabel;
      }

      cursor.setDate(cursor.getDate() + 1);
    }
  }

  data.cells = cells;
  data.maxCount = maxCount;
  data.totalCount = totalCount;
  data.activeDays = activeDays;
  data.currentStreak = streakOf(counts, todayIndex);
  return data;
}
