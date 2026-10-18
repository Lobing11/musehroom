/**
 * 统计视图的数据结构（热力图 + 标签云）。
 *
 * 为什么单独建模型而不是在界面里现算：这些数字全都来自数据库聚合
 * （`listDayStats` / `listTagsWithCount`）。界面只负责把已经算好的值画出来，
 * 不允许自己去数「已经加载的行」——那是 M2 那个缺陷的来源（见纪律 16）。
 */

/** 热力图的一格：某一天（本地日期）的记录条数 + 它在网格里的位置。 */
export class HeatCell {
  /** 本地日期 'YYYY-MM-DD'，与 `DateUtil.dateKey` / SQL 的 date() 同一口径 */
  day: string = '';
  count: number = 0;
  /** 第几列：0 = 最左（11 周前），11 = 本周 */
  weekIndex: number = 0;
  /** 第几行：0 = 周一 … 6 = 周日 */
  weekday: number = 0;
  /** 本周还没到的日子：占位但不画数据（否则一行里会多出几个「零记录」的方块） */
  inFuture: boolean = false;
  /** 月份标签：只有「这一列是该月第一列」的格子才有值，其余为空串 */
  monthLabel: string = '';
}

/** 近 12 周热力图 + 概览数字 */
export class HeatmapData {
  /** 按列优先存放：cells[weekIndex * 7 + weekday]（界面按列渲染，取起来最直接） */
  cells: HeatCell[] = [];
  /** 这 12 周里单日最大值：色阶的分母 */
  maxCount: number = 0;
  /** 这 12 周的记录总数 */
  totalCount: number = 0;
  /** 有记录的天数 */
  activeDays: number = 0;
  /** 当前连续记录天数（今天还没记就从昨天往回数，避免白天永远显示 0） */
  currentStreak: number = 0;
}
