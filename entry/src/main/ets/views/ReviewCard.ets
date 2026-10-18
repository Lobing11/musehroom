/**
 * 「灵光再现」卡片：展示随机抽到的一条旧灵感。
 *
 * 刻意做成纯展示组件（数据由页面抽好传进来）：
 * 抽签要写 preferences（24 小时去重窗口），放在 build 路径里会变成
 * 「每渲一帧抽一次」，那既不随机也会疯狂写盘。
 */
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DEFAULT_ACCENT_VALUE,
  DARK_MODE_KEY,
  MuseRadius,
  MuseSpace,
  museTextPrimary,
  museTextSecondary,
  resolveAccentSoftBg,
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryButtonColor,
  resolvePrimaryColor,
  onAccentColor
} from '../utils/DesignTokens';
import { formatDayLabel, formatTime } from '../utils/DateUtil';

@Component
export struct ReviewCard {
  @Prop content: string = '';
  @Prop createdAt: number = 0;
  @Prop pinned: boolean = false;
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = DEFAULT_ACCENT_VALUE;
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  onAnother: () => void = () => {};
  onTogglePin: () => void = () => {};
  onEdit: () => void = () => {};

  private whenLabel(): string {
    const now = Date.now();
    return `${formatDayLabel(this.createdAt, now)} ${formatTime(this.createdAt)}`;
  }

  build() {
    Column({ space: MuseSpace.md }) {
      Row() {
        Row({ space: MuseSpace.xs }) {
          SymbolGlyph($r('sys.symbol.leaf'))
            .fontSize(14)
            .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentColor)])
          Text('灵光再现').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
        }
        Blank()
        Text(this.whenLabel())
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
      .width('100%')

      Text(this.content)
        .width('100%')
        .fontSize(17)
        .lineHeight(26)
        .maxLines(14)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor(museTextPrimary(this.isDarkMode))

      Row({ space: MuseSpace.sm }) {
        Button('换一条')
          .fontSize(13)
          .constraintSize({ minHeight: 36 })
          .layoutWeight(1)
          .backgroundColor(resolvePrimaryButtonColor(this.isDarkMode, this.accentColor))
          .fontColor(onAccentColor(this.accentColor))
          .onClick(() => this.onAnother())

        Button(this.pinned ? '取消钉住' : '钉到最前')
          .fontSize(13)
          .constraintSize({ minHeight: 36 })
          .layoutWeight(1)
          .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
          .onClick(() => this.onTogglePin())

        Button('去编辑')
          .fontSize(13)
          .constraintSize({ minHeight: 36 })
          .layoutWeight(1)
          .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
          .onClick(() => this.onEdit())
      }
      .width('100%')

      Text('每次给你翻出一条旧灵感，24 小时内不会重复同一条。')
        .fontSize(10)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .padding(MuseSpace.lg)
    .borderRadius(MuseRadius.card)
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentColor) })
  }
}
