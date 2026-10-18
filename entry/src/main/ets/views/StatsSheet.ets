/**
 * 统计面板（近 12 周热力图 + 标签云）。
 *
 * 纯展示：数据由页面在打开面板时拉好传进来。
 * 面板里的所有数字都来自数据库聚合，界面不做任何「数一数已加载的条目」的事（纪律 16）。
 */
import { display } from '@kit.ArkUI';
import { HeatCell } from '../model/StatsData';
import { Tag } from '../model/Tag';
import { HeatmapGrid } from './HeatmapGrid';
import { TagCloud } from './TagCloud';
import { NAVIGATION_BAR_HEIGHT_KEY, STATUS_BAR_HEIGHT_KEY } from '../utils/Constants';
import {
  ACCENT_COLOR_KEY,
  DEFAULT_ACCENT_VALUE,
  DARK_MODE_KEY,
  MuseSpace,
  museTextSecondary,
  onAccentColor,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';

@Component
export struct StatsSheet {
  @Prop loading: boolean = false;
  @Prop errorText: string = '';
  @Prop summary: string = '';
  @Prop cells: HeatCell[] = [];
  @Prop maxCount: number = 0;
  @Prop tags: Tag[] = [];
  @Prop minTagCount: number = 0;
  @Prop maxTagCount: number = 0;
  @Prop selectedSignature: string = '';
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = DEFAULT_ACCENT_VALUE;
  onPickDay: (day: string) => void = () => {};
  onPickTag: (name: string) => void = () => {};
  isTagSelected: (name: string) => boolean = () => false;
  onRetry: () => void = () => {};

  /** 内容滚动区的上限（vp）。0 = 没量出来，此时不下发上限（见 measureMaxContentHeight）。 */
  private maxContentHeight: number = 0;

  /** 底部要留出的高度（vp）：让开系统导航条，并保证至少有一份留白。 */
  private bottomInset: number = MuseSpace.xl;

  // aboutToAppear 在首次 build 之前跑，所以这里用普通字段就够，不需要 @State 去触发重绘
  aboutToAppear(): void {
    this.maxContentHeight = this.measureMaxContentHeight();
    this.bottomInset = Math.max(AppStorage.get<number>(NAVIGATION_BAR_HEIGHT_KEY) ?? 0, MuseSpace.xl);
  }

  /**
   * 量出「面板内容最多能有多高」（vp）。
   *
   * 面板在页面侧声明的是 `SheetSize.FIT_CONTENT`（按内容收缩），但内容可能比屏幕还高：
   * 标签一多，标签云会一直往长里长。上限 = 屏幕高 − 状态栏 − 导航条 − 上下留白，
   * 于是「够得着就贴着内容、够不着就在面板内部滚动」，两头都不会把内容顶出屏幕。
   *
   * 量失败时返回 0（不下发上限，退化成「按内容长、超出部分由系统裁掉」）：
   * 宁可这样，也不写一个凭感觉的魔法数字——上限必须来自这台机器的真实屏幕。
   */
  private measureMaxContentHeight(): number {
    try {
      const screenVp = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
      const statusBar = AppStorage.get<number>(STATUS_BAR_HEIGHT_KEY) ?? 0;
      const navBar = AppStorage.get<number>(NAVIGATION_BAR_HEIGHT_KEY) ?? 0;
      return screenVp - statusBar - navBar - 2 * MuseSpace.xl;
    } catch (err) {
      return 0;
    }
  }

  private scrollConstraint(): ConstraintSizeOptions {
    if (this.maxContentHeight <= 0) {
      return {};
    }
    return { maxHeight: this.maxContentHeight };
  }

  build() {
    Column({ space: MuseSpace.md }) {
      Row() {
        Text('记录足迹').fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
        Blank()
        Text(this.summary).fontSize(11).fontColor(museTextSecondary(this.isDarkMode))
      }
      .width('100%')

      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(this.accentColor)
          Text('正在统计…').fontSize(12).fontColor(museTextSecondary(this.isDarkMode))
        }
        .width('100%')
        .padding(MuseSpace.xl)
      } else if (this.errorText.length > 0) {
        Column({ space: MuseSpace.sm }) {
          Text(this.errorText).fontSize(13).fontColor(museTextSecondary(this.isDarkMode))
          Button('重新加载')
            .fontSize(13)
            .constraintSize({ minHeight: 34 })
            .backgroundColor(this.filledButtonColor())
            .fontColor(onAccentColor(this.filledButtonColor()))
            .onClick(() => this.onRetry())
        }
        .width('100%')
        .padding(MuseSpace.xl)
      } else {
        Scroll() {
          Column({ space: MuseSpace.md }) {
            HeatmapGrid({
              cells: this.cells,
              maxCount: this.maxCount,
              onPickDay: (day: string) => this.onPickDay(day)
            })

            TagCloud({
              tags: this.tags,
              minCount: this.minTagCount,
              maxCount: this.maxTagCount,
              selectedSignature: this.selectedSignature,
              onPickTag: (name: string) => this.onPickTag(name),
              isTagSelected: (name: string) => this.isTagSelected(name)
            })
          }
          .width('100%')
        }
        // 这里**不写** `.layoutWeight(1)`：下面那条约束已经定义了它的高度（内容矮就贴着内容、
        // 超过上限就在面板内部滚动）。layoutWeight 是去分「父容器的剩余空间」，而父容器现在
        // 是按内容高度撑开的，能分出多少不可预期——在 FIT_CONTENT 下会把收缩再次顶掉。
        .constraintSize(this.scrollConstraint())
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    // 同上：本面板是 FIT_CONTENT，根节点写 `.height('100%')` 会把「按内容收缩」直接顶掉，
    // 真机上的表现是「两张卡片占掉一半、下面一半全空白」（`docs/store/shot-5-stats.png`）。
    // 底部留出导航条那一份（真机实测 30vp；广播为 0 时兜 MuseSpace.xl）：按内容收缩后面板会贴着
    // 屏幕底边，最后一张卡片于是被切掉底部圆角并压在系统导航条上
    // （真机 `dumpLayout` 实测：卡片底边 = 面板底边 = 2860 = 屏幕底边）。
    .padding({
      left: MuseSpace.lg,
      right: MuseSpace.lg,
      top: MuseSpace.md,
      bottom: this.bottomInset
    })
  }

  /**
   * 实底按钮的底色。
   *
   * 字色一律用 `onAccentColor(同一底色)` 算，**不能写死 `#FFFFFF`、也不能拿原始主题色去判**：
   * 深色模式下 `resolvePrimaryButtonColor` 会把主题色压暗，而浅色主题（琥珀黄、自定义亮色）
   * 在浅色模式下需要的是黑字——写死白字在亮黄底上只有 ~2:1，读不清。
   */
  private filledButtonColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentColor);
  }
}
