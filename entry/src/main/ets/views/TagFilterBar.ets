import { Tag } from '../model/Tag';
import {
  ACCENT_COLOR_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  museTextSecondary,
  onAccentColor,
  PAGE_BACKGROUND_KEY,
  resolveAccentSoftBg,
  resolvePageBackground,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/** 右缘渐隐遮罩的宽度：够看见「这里还有东西」，又不至于盖住半颗 chip */
const FADE_WIDTH: number = 24;
/** 小于 1vp 的差值当没溢出（布局取整会让内容宽度比可视区多零点几个 vp） */
const OVERFLOW_EPSILON: number = 1;

/** `Length`（number | string | Resource）→ vp 数；量不出来按 0 处理 */
function toVp(value: Length): number {
  const n: number = typeof value === 'number' ? value : Number.parseFloat(`${value}`);
  return Number.isFinite(n) ? n : 0;
}

/**
 * 标签筛选条：顶部横滑 chips，多选取**交集**。
 *
 * 为什么不跳到独立筛选页：筛选状态和时间轴留在同一屏，翻找时不会迷路，
 * 也不会出现「筛完要返回才知道筛了什么」。
 *
 * 为什么选中态要额外传一个 `selectedSignature`：选中态活在 ViewModel 里，
 * 而 ViewModel 不是可观察对象。只给回调的话，父组件重绘时子组件未必跟着重绘，
 * chips 的选中样式就会停在上一次。给它一个**每次筛选都变**的 @Prop 才是最稳的触发方式；
 * 同时把选中与否编进 ForEach 的 key，保证旧 chip 被重建而不是被复用。
 *
 * 为什么右缘要渐隐：横滑条默认关掉滚动条（`BarState.Off`，一排出滚动条很吵），
 * 代价是「右边还有标签」在视觉上完全没有线索——最后一个 chip 会被屏幕边缘切一半，
 * 看起来像渲染坏了。渐隐只在「真的溢出」且「还没滑到头」时出现。
 */
@Component
export struct TagFilterBar {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(PAGE_BACKGROUND_KEY) pageBackground: string = '';

  @Prop tags: Tag[] = [];
  /** 仅用于触发重绘的指纹，格式不重要，变就行 */
  @Prop selectedSignature: string = '';
  @Prop selectedCount: number = 0;

  isTagSelected: (name: string) => boolean = (name: string): boolean => false;
  onToggle: (name: string) => void = (name: string) => {
  };
  onClearTags: () => void = () => {
  };

  @State private fadeRight: boolean = false;
  private viewportWidth: number = 0;
  private contentWidth: number = 0;
  private scrollX: number = 0;

  build() {
    Scroll() {
      Row({ space: MuseSpace.xs }) {
        ForEach(this.tags, (tag: Tag) => {
          TagChip({
            name: tag.name,
            selected: this.isTagSelected(tag.name),
            onToggle: (name: string): void => {
              this.onToggle(name);
            }
          })
        }, (tag: Tag) => `${tag.id}:${tag.name}:${this.isTagSelected(tag.name) ? 1 : 0}`)

        if (this.selectedCount > 0) {
          Text('清空标签')
            .fontSize(12)
            .fontColor(museTextSecondary(this.isDarkMode))
            .padding({
              left: MuseSpace.sm,
              right: MuseSpace.sm,
              top: MuseSpace.xs,
              bottom: MuseSpace.xs
            })
            .onClick(() => {
              this.onClearTags();
            })
        }
      }
      .padding({ top: MuseSpace.xs, bottom: MuseSpace.sm })
      // 横滑容器里的 Row 拿到的是不限宽，所以它的宽度就是「内容总宽」
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.contentWidth = toVp(newValue.width);
        this.updateFade();
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.viewportWidth = toVp(newValue.width);
      this.updateFade();
    })
    .onDidScroll((xOffset: number, yOffset: number) => {
      this.scrollX = xOffset;
      this.updateFade();
    })
    // 渐隐用 overlay 画在筛选条自己身上，**不要用 Stack 包一层**：
    // Stack 会把「高度 100%」的遮罩当成参与测量的子节点，于是整条筛选条被撑到占满
    // 页面剩余高度，把时间轴挤成 0 高（真机 2026-10-06 实测：卡片全部消失、
    // chips 被 alignContent.End 竖直居中飘在半空）。overlay 只画不参与布局，没有这个副作用。
    .overlay(this.RightFade(), { align: Alignment.End })
  }

  @Builder
  RightFade() {
    if (this.fadeRight) {
      // 渐隐块只负责「提示」，必须让开手势：否则它在最右边吃掉一段滑动区域
      Column()
        .width(FADE_WIDTH)
        .height('100%')
        // 起点用全透明黑、终点用页面底色：任意主题下都能融进背景，不需要额外算 alpha
        .linearGradient({
          angle: 90,
          colors: [['#00000000', 0.0], [resolvePageBackground(this.isDarkMode, this.pageBackground), 1.0]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  /** 溢出且没滑到头才显示渐隐；只在状态真变时写 @State，避免自激重排 */
  private updateFade(): void {
    const overflow: number = this.contentWidth - this.viewportWidth;
    const next: boolean = overflow > OVERFLOW_EPSILON && this.scrollX < overflow - OVERFLOW_EPSILON;
    if (next !== this.fadeRight) {
      this.fadeRight = next;
    }
  }
}

/**
 * 单个标签 chip。
 *
 * 做成 @Component 而不是 @Builder：@Builder 的按值参数只在构造时求值一次，
 * 选中态一旦变化就不会刷新（M0 真机上踩过这个坑）。组件用 @Prop 收数据，
 * 刷新语义是完整的。
 */
@Component
struct TagChip {
  @Prop name: string = '';
  @Prop selected: boolean = false;

  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';

  onToggle: (name: string) => void = (name: string) => {
  };

  build() {
    Text(`#${this.name}`)
      .fontSize(12)
      .fontColor(this.selected
        ? onAccentColor(this.chipColor())
        : resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
      .padding({
        left: MuseSpace.md,
        right: MuseSpace.md,
        top: MuseSpace.xs,
        bottom: MuseSpace.xs
      })
      .borderRadius(MuseRadius.pill)
      .backgroundColor(this.chipColor())
      .accessibilityText(`标签 ${this.name}`)
      .accessibilityChecked(this.selected)
      .accessibilityDescription('点两下切换这个筛选条件')
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.onToggle(this.name);
      })
  }

  /** 选中是实心主题色，未选中是主题色的淡底——一眼能看出「哪些条件在生效」 */
  private chipColor(): string {
    if (this.selected) {
      return resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary());
    }
    return resolveAccentSoftBg(this.isDarkMode, this.accentOrPrimary());
  }

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }
}
