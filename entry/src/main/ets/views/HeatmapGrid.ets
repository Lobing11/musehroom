/**
 * 近 12 周记录热力图（GitHub 风格）。
 *
 * 布局按**列**渲染：一列 = 一周（周一在上），共 12 列；`cells` 也是列优先存放
 * （`cells[week * 7 + weekday]`），所以每列取 7 个连续元素即可，不用做转置。
 *
 * 数据全部由 `StatsViewModel` 从数据库聚合后传进来（纪律 16：界面不数已加载的行）。
 */
import { HeatCell } from '../model/StatsData';
import { HEATMAP_WEEKS } from '../utils/Heatmap';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DEFAULT_ACCENT_VALUE,
  DARK_MODE_KEY,
  MuseRadius,
  MuseSpace,
  museTextSecondary,
  resolveCardBorder,
  resolveCardSurface,
  withAlpha
} from '../utils/DesignTokens';

const WEEKDAYS: number = 7;
const CELL_HEIGHT: number = 15;
/**
 * 格子圆角。用一个小圆角而不是 `MuseRadius.pill`：
 * 圆角等于半高时会变成一排药丸，格子之间的间距感消失，热力图就读不出「密度」了。
 */
const CELL_RADIUS: number = 4;
/** 色阶分 4 档，与下面的图例一一对应 */
const LEVELS: number = 4;
const LEVEL_ALPHA: number[] = [0.22, 0.42, 0.66, 1.0];
/** 周几提示：只标 4 个，标满 7 个会挤成一团 */
const WEEKDAY_LABELS: string[] = ['一', '', '三', '', '五', '', '日'];
/** 每列的行号（0..6）：写成常量数组，避免在 build 里做循环拼数组 */
const WEEKDAY_INDEXES: number[] = [0, 1, 2, 3, 4, 5, 6];
const LEGEND_LEVELS: number[] = [0, 1, 2, 3, 4];

@Component
export struct HeatmapGrid {
  /** 84 个格子（12 周 × 7 天），列优先 */
  @Prop cells: HeatCell[] = [];
  /** 单日最大值（色阶的分母）：0 表示这 12 周一条都没有 */
  @Prop maxCount: number = 0;
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = DEFAULT_ACCENT_VALUE;
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  onPickDay: (day: string) => void = () => {};

  private weekIndexes(): number[] {
    const list: number[] = [];
    for (let i = 0; i < HEATMAP_WEEKS; i++) {
      list.push(i);
    }
    return list;
  }

  /** 取某一列的 7 个格子；数据还没到时返回空数组，渲染层自然跳过 */
  private columnOf(week: number): HeatCell[] {
    const start = week * WEEKDAYS;
    if (start + WEEKDAYS > this.cells.length) {
      return [];
    }
    const column: HeatCell[] = [];
    for (let i = start; i < start + WEEKDAYS; i++) {
      column.push(this.cells[i]);
    }
    return column;
  }

  private monthLabelOf(week: number): string {
    const index = week * WEEKDAYS;
    if (index >= this.cells.length) {
      return '';
    }
    return this.cells[index].monthLabel;
  }

  /** 空格子的底色：次要文字色兑出来的一层淡灰，深浅色下都能用 */
  private emptyColor(): string {
    return withAlpha(museTextSecondary(this.isDarkMode), 0.10);
  }

  private futureColor(): string {
    return withAlpha(museTextSecondary(this.isDarkMode), 0.04);
  }

  /**
   * 一格的底色。
   * 用 `withAlpha(主题色, 档位)` 而不是 `mixHex`：半透明色会叠在卡片底色上，
   * 深浅两种背景下都能自然过渡，不必为每个档位各算一套实色。
   */
  private cellColor(cell: HeatCell): string {
    if (cell.inFuture) {
      return this.futureColor();
    }
    if (cell.count <= 0) {
      return this.emptyColor();
    }
    const denominator = this.maxCount > 0 ? this.maxCount : 1;
    let level = Math.ceil((cell.count / denominator) * LEVELS);
    if (level < 1) {
      level = 1;
    }
    if (level > LEVELS) {
      level = LEVELS;
    }
    return withAlpha(this.accentColor, LEVEL_ALPHA[level - 1]);
  }

  private surface(): string {
    return resolveCardSurface(this.isDarkMode, this.cardSurface);
  }

  /** 这一格是否值得被读屏念出来（有记录、且不是未来） */
  private isPickable(cell: HeatCell): boolean {
    return !cell.inFuture && cell.count > 0;
  }

  /** 'YYYY-MM-DD' → 'M 月 D 日'（去掉前导零，读屏念「09 月 05 日」很别扭） */
  private dayLabel(day: string): string {
    if (day.length < 10) {
      return day;
    }
    return `${Number.parseInt(day.substring(5, 7), 10)} 月 ${Number.parseInt(day.substring(8, 10), 10)} 日`;
  }

  build() {
    Column({ space: MuseSpace.sm }) {
      // 月份标签：左侧留出与周几提示同宽的占位，标签才和下面的列对得上
      Row() {
        Text('').width(16).fontSize(10)
        ForEach(this.weekIndexes(), (week: number) => {
          Text(this.monthLabelOf(week))
            .layoutWeight(1)
            .fontSize(10)
            .maxLines(1)
            .fontColor(museTextSecondary(this.isDarkMode))
        }, (week: number) => `month:${week}:${this.monthLabelOf(week)}`)
      }
      .width('100%')

      Row({ space: 3 }) {
        Column() {
          ForEach(WEEKDAY_INDEXES, (weekday: number) => {
            Text(WEEKDAY_LABELS[weekday])
              .fontSize(9)
              .height(CELL_HEIGHT)
              .fontColor(museTextSecondary(this.isDarkMode))
          }, (weekday: number) => `weekday:${weekday}`)
        }
        .width(16)

        ForEach(this.weekIndexes(), (week: number) => {
          Column({ space: 3 }) {
            ForEach(this.columnOf(week), (cell: HeatCell) => {
              Column()
                .width('100%')
                .height(CELL_HEIGHT)
                .borderRadius(CELL_RADIUS)
                .backgroundColor(this.cellColor(cell))
                // 无障碍：**只让有记录的格子可被读屏聚焦**。
                // 84 个格子全可聚焦的话，读屏用户要划 84 下才能走过这张图；
                // 空日期在视觉上是背景信息，读屏时应当被跳过。
                .accessibilityLevel(this.isPickable(cell) ? 'yes' : 'no')
                .accessibilityText(`${this.dayLabel(cell.day)}，${cell.count} 条灵感`)
                .accessibilityDescription('点两下只看这一天的灵感')
                .onClick(() => {
                  // 只有那天真有记录才值得跳筛选：点空格子会得到一个必然为空的结果
                  if (!cell.inFuture && cell.count > 0) {
                    this.onPickDay(cell.day);
                  }
                })
            }, (cell: HeatCell) => `cell:${cell.day}:${cell.count}`)
          }
          .layoutWeight(1)
        }, (week: number) => `week:${week}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 图例
      Row({ space: MuseSpace.xs }) {
        Text('少').fontSize(10).fontColor(museTextSecondary(this.isDarkMode))
        ForEach(LEGEND_LEVELS, (level: number) => {
          Column()
            .width(12)
            .height(12)
            .borderRadius(CELL_RADIUS)
            .backgroundColor(level === 0
              ? this.emptyColor()
              : withAlpha(this.accentColor, LEVEL_ALPHA[level - 1]))
        }, (level: number) => `legend:${level}`)
        Text('多').fontSize(10).fontColor(museTextSecondary(this.isDarkMode))
        Blank()
        Text('点格子看那天的灵感')
          .fontSize(10)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
      .width('100%')
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.card)
    .backgroundColor(this.surface())
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentColor) })
  }
}
