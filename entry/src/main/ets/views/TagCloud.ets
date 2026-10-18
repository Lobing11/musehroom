/**
 * 标签云：字号与色阶都按使用频次映射，点一下按它筛选（标签热力下钻）。
 *
 * 频次来自数据库聚合（`IdeaRepository.listTags()` → `TagDao.listTagsWithCount`），
 * 与顶部筛选条是同一份数据、同一个排序 —— 两处数字若不同口径，用户会立刻发现。
 *
 * **为什么要 Top-N**：`Flex(Wrap)` 铺法本身没问题，问题是它没有上限 —— 标签一多，
 * 这块就一直往长里长，半模态（`SheetSize.FIT_CONTENT`）只好跟着长到需要滚动，
 * 而「扫一眼我最近在用什么标签」本来不该需要滚动。所以默认只画前 `TOP_N` 个
 * （`listTagsWithCount` 已按频次倒序，前 N 个就是最热的 N 个），其余折进末尾的 `+N`，
 * 点开才铺全量。
 *
 * 两条相关纪律：
 * ① 展开态是**面板内的临时状态**（`@State`），面板关掉即回到折叠 —— 下次打开仍是「一眼扫完」；
 * ② 展开后的高度上限由 `StatsSheet` 的 `constraintSize` 兜住（候选一），所以最多是面板内滚动，
 *    不会把内容顶出屏幕。两条改动是耦合的，别只改一边。
 */
import { Tag } from '../model/Tag';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DEFAULT_ACCENT_VALUE,
  DARK_MODE_KEY,
  MuseRadius,
  MuseSpace,
  mixHex,
  museTextSecondary,
  onAccentColor,
  resolveAccentSoftBg,
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/** 字号区间：最少的标签 13fp，最多的 24fp —— 差一倍才看得出「热」 */
const FONT_MIN: number = 13;
const FONT_MAX: number = 24;

/** 折叠时最多画几个：12 个在真机上大约两到三行，不会一上来就吃掉面板 */
const TOP_N: number = 12;

@Component
export struct TagCloud {
  @Prop tags: Tag[] = [];
  @Prop minCount: number = 0;
  @Prop maxCount: number = 0;
  /**
   * 选中态指纹。必须把「选了哪些」编进 ForEach 的 key：
   * key 不变时旧节点会被复用，选中样式就不会重新算（M2 的筛选条踩过这个坑）。
   */
  @Prop selectedSignature: string = '';
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = DEFAULT_ACCENT_VALUE;
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  onPickTag: (name: string) => void = () => {};
  isTagSelected: (name: string) => boolean = () => false;

  /** 折叠 / 展开：只有「标签数 > TOP_N」时才用得上 */
  @State private expanded: boolean = false;

  private visibleTags(): Tag[] {
    if (this.expanded || this.tags.length <= TOP_N) {
      return this.tags;
    }
    return this.tags.slice(0, TOP_N);
  }

  /** 折起来的条数；0 = 没有可折的，末尾那个 `+N` 也就不出现 */
  private hiddenCount(): number {
    return this.tags.length > TOP_N ? this.tags.length - TOP_N : 0;
  }

  /** 0 = 最少，1 = 最多；只有一个标签时直接给满档，免得除以零 */
  private weightOf(count: number): number {
    if (this.maxCount <= this.minCount) {
      return 1;
    }
    return (count - this.minCount) / (this.maxCount - this.minCount);
  }

  private fontSizeOf(count: number): number {
    return FONT_MIN + Math.round((FONT_MAX - FONT_MIN) * this.weightOf(count));
  }

  /** 越热越靠近主题色，越冷越接近次要文字色 */
  private colorOf(count: number, selected: boolean): string {
    if (selected) {
      return resolvePrimaryColor(this.isDarkMode, this.accentColor);
    }
    return mixHex(museTextSecondary(this.isDarkMode),
      resolvePrimaryColor(this.isDarkMode, this.accentColor),
      this.weightOf(count));
  }

  /**
   * 胶囊底色：未选中 = 主题色淡底，选中 = 实心主题色。
   *
   * 与顶部筛选条（`TagFilterBar` 的 `TagChip`）**同一口径** —— 同一个标签在两处出现时，
   * 「选中长什么样」必须一样，否则用户会以为是两种筛选。
   */
  private pillBg(selected: boolean): string {
    if (selected) {
      return resolvePrimaryButtonColor(this.isDarkMode, this.accentColor);
    }
    return resolveAccentSoftBg(this.isDarkMode, this.accentColor);
  }

  /** 字色：选中用实底的反差色，未选中保留「越热越绿」的色阶 */
  private pillFg(count: number, selected: boolean): string {
    if (selected) {
      return onAccentColor(this.pillBg(true));
    }
    return this.colorOf(count, false);
  }

  private surface(): string {
    return resolveCardSurface(this.isDarkMode, this.cardSurface);
  }

  @Builder
  TagPill(tag: Tag) {
    Text(`#${tag.name}`)
      .fontSize(this.fontSizeOf(tag.count))
      .fontColor(this.pillFg(tag.count, this.isTagSelected(tag.name)))
      .padding({
        left: MuseSpace.sm,
        right: MuseSpace.sm,
        top: MuseSpace.xs,
        bottom: MuseSpace.xs
      })
      .borderRadius(MuseRadius.pill)
      .backgroundColor(this.pillBg(this.isTagSelected(tag.name)))
      // 标签名是用户自己写的，长度不可控：超长标签宁可省略号，也不能把胶囊顶出屏幕
      .constraintSize({ maxWidth: '100%' })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 有底色之后必须自己留间距：原先靠 padding 挨着排，加了背景就会连成一片
      .margin({ right: MuseSpace.sm, bottom: MuseSpace.sm })
      // 无障碍：字号是「热不热」的视觉编码，读屏听不出来，所以把条数念出来；
      // 选中与否用 accessibilityChecked 表达（读屏会念「已选中」）。
      .accessibilityText(`标签 ${tag.name}，${tag.count} 条`)
      .accessibilityChecked(this.isTagSelected(tag.name))
      .accessibilityDescription('点两下只看这个标签')
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => this.onPickTag(tag.name))
  }

  build() {
    Column({ space: MuseSpace.sm }) {
      Row() {
        Text('标签云').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
        Blank()
        Text('字号越大 = 用得越多')
          .fontSize(10)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
      .width('100%')

      if (this.tags.length === 0) {
        Text('还没有标签。在正文里写 #标签，保存后就会自动归类。')
          .fontSize(12)
          .fontColor(museTextSecondary(this.isDarkMode))
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
          ForEach(this.visibleTags(), (tag: Tag) => {
            this.TagPill(tag)
          }, (tag: Tag) => `cloud:${this.selectedSignature}:${this.expanded ? 'e' : 'c'}:${tag.id}:${tag.name}:${tag.count}:${this.isTagSelected(tag.name) ? 1 : 0}`)

          if (this.hiddenCount() > 0) {
            Text(this.expanded ? '收起' : `+${this.hiddenCount()}`)
              .fontSize(FONT_MIN)
              .fontColor(museTextSecondary(this.isDarkMode))
              .padding({
                left: MuseSpace.md,
                right: MuseSpace.md,
                top: MuseSpace.xs,
                bottom: MuseSpace.xs
              })
              .borderRadius(MuseRadius.pill)
              .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
              .margin({ right: MuseSpace.sm, bottom: MuseSpace.sm })
              .accessibilityText(this.expanded ? '收起标签' : `还有 ${this.hiddenCount()} 个标签`)
              .accessibilityDescription(this.expanded ? '点两下只留最常用的那些' : '点两下展开全部标签')
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.expanded = !this.expanded;
              })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.card)
    .backgroundColor(this.surface())
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentColor) })
  }
}
