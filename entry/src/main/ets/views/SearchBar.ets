import { SEARCH_DEBOUNCE_MS } from '../utils/Constants';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  museTextPrimary,
  museTextSecondary,
  resolveCardBorder,
  resolveCardSurface
} from '../utils/DesignTokens';

/**
 * 搜索栏。
 *
 * 防抖放在**组件内部**而不是页面里：输入框自己最清楚「用户什么时候停下来了」，
 * 页面只该收到一个「要查什么」的结论（`onDebounced`），不该持有定时器。
 *
 * 300ms 的选择依据：中文输入法一个字一个字上屏，短于此会在组词途中就发查询，
 * 长于此用户会觉得「卡了一下」。这个值同时是 `SEARCH_DEBOUNCE_MS`，M2 验收口径之一。
 */
@Component
export struct SearchBar {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';

  @State private draft: string = '';

  /**
   * 已生效的搜索词，由父组件单向写入。
   *
   * 必须用 @Watch 把它同步回输入框：否则「清除筛选条件」清掉关键词之后，
   * 输入框里还留着旧词、列表却是全量的，看起来就像搜索坏了。
   * 反向（用户打字）不走这里——打字只改 draft，再由防抖回调通知父级。
   */
  @Prop @Watch('onAppliedKeywordChanged') appliedKeyword: string = '';

  onDebounced: (keyword: string) => void = (keyword: string) => {
  };

  /** 防抖定时器 id，-1 表示没有在计时 */
  private debounceTimerId: number = -1;

  aboutToDisappear(): void {
    this.cancelDebounce();
  }

  build() {
    Row({ space: MuseSpace.xs }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass_circle'))
        .fontSize(14)
        .fontColor([museTextSecondary(this.isDarkMode)])

      TextInput({ text: this.draft, placeholder: '搜索灵感…' })
        .id('search_input')
        .layoutWeight(1)
        .constraintSize({ minHeight: 36 })
        .fontSize(14)
        .fontColor(museTextPrimary(this.isDarkMode))
        .placeholderFont({ size: 14 })
        .placeholderColor(museTextSecondary(this.isDarkMode))
        .backgroundColor('#00000000')
        .padding({ left: 0, right: 0 })
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.handleChange(value);
        })
        .onSubmit(() => {
          // 按了搜索键就是「现在就要结果」，不必再等防抖那 300ms
          this.submitNow();
        })

      if (this.draft.length > 0) {
        Text('✕')
          .fontSize(14)
          .fontColor(museTextSecondary(this.isDarkMode))
          .padding(MuseSpace.xs)
          .accessibilityText('清空搜索词')
          .onClick(() => {
            this.clearNow();
          })
      }
    }
    .width('100%')
    .padding({
      left: MuseSpace.md,
      right: MuseSpace.sm,
      top: 0,
      bottom: 0
    })
    .margin({ bottom: MuseSpace.sm })
    .borderRadius(MuseRadius.pill)
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentOrPrimary()) })
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  onAppliedKeywordChanged(): void {
    if (this.appliedKeyword !== this.draft) {
      this.cancelDebounce();
      this.draft = this.appliedKeyword;
    }
  }

  private handleChange(value: string): void {
    this.draft = value;
    this.cancelDebounce();
    this.debounceTimerId = setTimeout(() => {
      this.debounceTimerId = -1;
      this.onDebounced(value);
    }, SEARCH_DEBOUNCE_MS);
  }

  private submitNow(): void {
    this.cancelDebounce();
    this.onDebounced(this.draft);
  }

  /** 清空是明确意图，立刻生效，不必再等 300ms */
  private clearNow(): void {
    this.cancelDebounce();
    this.draft = '';
    this.onDebounced('');
  }

  private cancelDebounce(): void {
    if (this.debounceTimerId !== -1) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = -1;
    }
  }

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }
}
