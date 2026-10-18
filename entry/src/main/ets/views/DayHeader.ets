import { DARK_MODE_KEY, MuseSpace, museTextPrimary, museTextSecondary } from '../utils/DesignTokens';

/**
 * 日期分组头（也是置顶分组头：置顶那一行的文字前会多一枚「顶到最前」的系统符号）。
 *
 * 做成 `@Component` 而不是 `@Builder`，是 M0 定下的纪律：
 * `@Builder` 的按值参数只在构造时求值一次，数据变了界面不动（真机上踩过）；
 * 组件用 `@Prop` 收数据，父组件重渲染时值会跟着更新。
 */
@Component
export struct DayHeader {
  @Prop title: string = '';
  @Prop count: number = 0;
  @Prop isPinnedGroup: boolean = false;
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;

  build() {
    Row({ space: MuseSpace.sm }) {
      // 置顶组头带一个「顶到最前」的符号：文案里的 emoji 已经拿掉，图标改由视图渲染
      // （VM 只发文字，不让数据层掺排版）
      if (this.isPinnedGroup) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(13)
          .fontColor([museTextPrimary(this.isDarkMode)])
      }
      Text(this.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isPinnedGroup ? museTextPrimary(this.isDarkMode) : museTextSecondary(this.isDarkMode))

      if (this.count > 0) {
        Text(`${this.count} 条`)
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }

      Blank()
    }
    .width('100%')
    // 无障碍：分组头读成一句「昨天，5 条」；不 group 的话读屏会把「昨天」和「5 条」念成两个独立对象
    .accessibilityGroup(true)
    .accessibilityText(this.count > 0 ? `${this.title}，${this.count} 条` : this.title)
    .accessibilityLevel('yes')
    .padding({
      left: MuseSpace.xs,
      right: MuseSpace.xs,
      // 置顶组在最上面，不需要额外上边距（列表本身已有内边距）
      top: this.isPinnedGroup ? 0 : MuseSpace.md,
      bottom: MuseSpace.sm
    })
  }
}
