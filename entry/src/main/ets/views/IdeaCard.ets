import { relativeTime } from '../utils/DateUtil';
import { splitHighlight, TextSegment } from '../utils/Highlight';
import { bodyText, buildBodySegments, LinkSegment } from '../utils/LinkParser';
import { openExternalUrl } from '../utils/UrlLauncher';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  mixHex,
  MuseRadius,
  MuseSpace,
  museTextPrimary,
  museTextSecondary,
  onAccentColor,
  resolveAccentSoftBg,
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/**
 * 命中文字在浅色下要压暗多少才够读。
 *
 * 主题色本身（比如破土绿 #2E9E6B）在白底上对比度只有 3.3:1，当正文用不达 WCAG AA；
 * 压暗 22% 后约 5.2:1，既达标又还是「主题色」，不会变成另一种颜色。
 */
const HIGHLIGHT_DARKEN: number = 0.22;

/** 正文最多显示几行：卡片的职责是「让人认得出是哪一条」，不是把全文摊在列表里 */
const BODY_MAX_LINES: number = 8;
const BODY_LINE_HEIGHT: number = 24;
const BODY_FONT_SIZE: number = 16;

/**
 * 卡片上最多平铺几颗标签 chip，其余折成 `+N`。
 *
 * 为什么不按「恰好两行」折：chip 宽度随标签长度变（1 个字符和 24 个字符差好几倍），
 * 想按行折就得测量每一颗的宽度，为了一个列表元素值得吗——按数量卡 8 颗，实测≈两行。
 */
const TAG_TOP_N: number = 8;

/** `SizeOptions.width/height` 是 `Length`（可能是 number、带单位的字符串、甚至是 Resource），统一读成数字 */
function sizeToNumber(value: Length | undefined): number {
  if (typeof value === 'number') {
    return value;
  }
  const parsed: number = Number.parseFloat(`${value}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * 时间轴上的一条灵感。
 *
 * 只负责展示与「被点开」，所有写操作都在详情半模态里做——
 * 卡片上摆一排小按钮会让列表变吵，也让误触成本变高（灵感是不可再生的，删错很痛）。
 * 卡片上可点的小东西只有两类：标签 chip（点它=只看这个标签）、正文里的链接（点它=交给浏览器）。
 */
@Component
export struct IdeaCard {
  @Prop content: string = '';
  @Prop createdAt: number = 0;
  @Prop pinned: boolean = false;
  @Prop edited: boolean = false;
  /** 当前搜索词：非空时正文按命中片段着色 */
  @Prop keyword: string = '';
  /** 标签名（由正文解析而来，不是查库结果——TagParser 才是标签的唯一定义） */
  @Prop tagNames: string[] = [];
  /**
   * 当前时间（毫秒），由页面每分钟推进一次。
   *
   * 相对时间必须在**父组件推动**下重算：卡片自己不会因为时间流逝而重绘，
   * 页面把新时间按值传下来，`@Prop` 一变这张卡就重新渲染一次。
   * 默认 0 表示「页面没给」，此时回落 `Date.now()`（单测/预览等场景不至于显示 1970 年）。
   */
  @Prop now: number = 0;
  /** 是否处于多选模式（长按进入）。多选时整张卡变成「勾选 / 取消」的开关 */
  @Prop selecting: boolean = false;
  /** 多选模式下这一条是否被选中 */
  @Prop selected: boolean = false;

  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';

  /** 正文被截断（超过 `BODY_MAX_LINES`）时在底行提示「展开」——整张卡片就是入口 */
  @State private bodyTruncated: boolean = false;
  /** 标签是否已展开（默认只平铺 `TAG_TOP_N` 颗） */
  @State private tagsExpanded: boolean = false;

  onOpen: () => void = () => {
  };
  onTagClick: (name: string) => void = (name: string) => {
  };
  /** 长按：非多选时进入多选并选中这一条；多选时等价于点一下（切换选中） */
  onLongPress: () => void = () => {
  };
  onToggleSelect: () => void = () => {
  };

  build() {
    Column({ space: MuseSpace.sm }) {
      // 可点区域只包正文与底行：标签 chip 自己带点击（点它=筛选），
      // 正文里的链接自己 `stopPropagation`（点它=浏览器）。
      // 这样「点 chip / 点链接会不会顺带弹出详情」就不依赖 ArkUI 的事件冒泡语义了。
      Column({ space: MuseSpace.sm }) {
        // 多选态：卡片顶部右侧出现勾选圈。放在正文上方而不是浮在角上，
        // 是因为它会改变卡片高度 —— 浮层盖住第一行字比「整体下移 22vp」更难读。
        if (this.selecting) {
          Row() {
            this.SelectionMark()
            Blank()
          }
          .width('100%')
        }

        if (this.keyword.length > 0) {
          // 搜索态：主题色加粗命中片段（Text 改局部样式只能靠 Span）。
          // 这一支**刻意保留原文里的 `#标签`**：搜索可能就是在搜标签名，
          // 削掉之后卡片上看不到任何命中痕迹，用户会以为「搜到了但没高亮」。
          // 文案没变、只有关键词变时，是 TimelineRow 的 key 里编进了 keyword 才让这里重画。
          Text() {
            ForEach(splitHighlight(this.content, this.keyword), (segment: TextSegment) => {
              Span(segment.text)
                .fontColor(segment.matched ? this.highlightColor() : museTextPrimary(this.isDarkMode))
                .fontWeight(segment.matched ? FontWeight.Bold : FontWeight.Normal)
            }, (segment: TextSegment, index: number) => `${index}:${segment.matched ? 1 : 0}:${segment.text.length}`)
          }
          .fontSize(BODY_FONT_SIZE)
          .lineHeight(BODY_LINE_HEIGHT)
          .width('100%')
          .maxLines(BODY_MAX_LINES)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          // 非搜索态：正文只渲染「纯文字 + 链接」，`#标签` 交给下面的 chip 行——
          // 同一份信息在一张卡上出现两次，等于把卡片撑高一倍（服务卡片早就是这么做的）。
          // 顺序很关键：先切链接再削标签，否则 `https://a.com/p#产品` 会被削断（见 LinkParser）。
          Text() {
            ForEach(this.bodySegments(), (segment: LinkSegment) => {
              if (segment.isLink) {
                Span(segment.text)
                  .fontColor(this.highlightColor())
                  .decoration({ type: TextDecorationType.Underline, color: this.highlightColor() })
                  .onClick(() => {
                    // 多选时点链接 = 勾选这一条：链接自己 stopPropagation，
                    // 不在这里拦一下的话，用户想勾选却弹出浏览器
                    if (this.selecting) {
                      this.onToggleSelect();
                      return;
                    }
                    openExternalUrl(this.getUIContext(), segment.text, '没找到能打开链接的应用');
                  })
              } else {
                Span(segment.text)
                  .fontColor(museTextPrimary(this.isDarkMode))
              }
            }, (segment: LinkSegment, index: number) =>
            `${index}:${segment.isLink ? 1 : 0}:${segment.text.length}`)
          }
          .fontSize(BODY_FONT_SIZE)
          .lineHeight(BODY_LINE_HEIGHT)
          .width('100%')
          .maxLines(BODY_MAX_LINES)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 截断提示只能自己量：`text.d.ts` 里没有 `onTextLayout` 这类回调，
          // 拿不到「渲染时有没有溢出」。宽度由布局给，量出来的行数超过上限就提示展开。
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.measureTruncation(newValue.width);
          })
        }

        Row({ space: MuseSpace.xs }) {
          if (this.pinned) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(11)
              .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentColor)])
          }
          // 只留相对时间：精确时刻在详情面板里（「记于 10月6日 12:33」），
          // 卡片右侧再摆一个绝对时间只会让人猜「哪个才是创建时间」。
          Text(relativeTime(this.createdAt, this.currentTime()))
            .fontSize(11)
            .fontColor(museTextSecondary(this.isDarkMode))
          if (this.edited) {
            Text('· 已编辑')
              .fontSize(11)
              .fontColor(museTextSecondary(this.isDarkMode))
          }
          if (this.bodyTruncated) {
            Blank()
            // 不是按钮：整张卡片就是入口（点开详情看全文），这里只把「后面还有」说出来
            Text('展开')
              .fontSize(11)
              .fontColor(this.highlightColor())
          }
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 无障碍：整块正文+时间读成一句，读完再告诉用户可以点开。
      // 不 group 的话读屏会逐行念「5 分钟前」「13:45」，听到的信息碎成两段；
      // 置顶那枚系统符号是纯装饰，读屏要听到的「已置顶」由 accessibilityText 的前缀给。
      .accessibilityGroup(true)
      .accessibilityText(this.selecting
        ? `${this.selected ? '已选中' : '未选中'}，${this.cardAccessibilityText()}`
        : this.cardAccessibilityText())
      .accessibilityDescription(this.selecting ? '点两下选中或取消' : '点两下打开，可编辑、置顶或删除；长按多选')
      // 按下时轻微缩一下：这是全局唯一的「物理感」来源，0.98 而不是系统默认的 0.90——
      // 整张卡片缩 10% 视觉上像被捏扁，2% 只让人觉得「按到了」。
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
      .onClick(() => {
        if (this.selecting) {
          this.onToggleSelect();
          return;
        }
        this.onOpen();
      })
      // 长按 420ms：比系统默认（500ms）稍快一点，多选是高频整理动作，等半秒会以为没按到
      .gesture(LongPressGesture({ repeat: false, duration: 420 })
        .onAction(() => {
          this.onLongPress();
        }))

      if (this.tagNames.length > 0) {
        // 用 Flex 换行而不是 Row：标签是用户写出来的、数量不可控，Row 溢出会被裁掉。
        // 这里的 margin 是 chip 之间的行内间距，与「页面装订线只有一处来源」不冲突。
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.visibleTags(), (name: string) => {
            Text(`#${name}`)
              .fontSize(11)
              .fontColor(this.chipTextColor())
              .padding({
                left: MuseSpace.sm,
                right: MuseSpace.sm,
                top: 2,
                bottom: 2
              })
              .margin({ right: MuseSpace.xs, top: MuseSpace.xs })
              .borderRadius(MuseRadius.pill)
              .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentOrDefault()))
              // 单个标签可以有 24 个字符（见 `TagParser.MAX_TAG_LENGTH`）：
              // 不限宽的话一颗 chip 就能把整行撑爆，卡片高度随之失控
              .constraintSize({ maxWidth: '100%' })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .accessibilityText(`标签 ${name}`)
              .accessibilityDescription('点两下只看这个标签')
              // 多选时 chip 不参与交互：点标签改筛选会把正在选中的列表换掉
              .enabled(!this.selecting)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.onTagClick(name);
              })
          }, (name: string) => `${this.tagsExpanded ? 'all' : 'top'}:${name}`)

          if (this.hiddenTagCount() > 0) {
            Text(`+${this.hiddenTagCount()}`)
              .fontSize(11)
              .fontColor(museTextSecondary(this.isDarkMode))
              .padding({
                left: MuseSpace.sm,
                right: MuseSpace.sm,
                top: 2,
                bottom: 2
              })
              .margin({ right: MuseSpace.xs, top: MuseSpace.xs })
              .borderRadius(MuseRadius.pill)
              .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentOrDefault()))
              .accessibilityText(`还有 ${this.hiddenTagCount()} 个标签`)
              .accessibilityDescription('点两下展开全部标签')
              .enabled(!this.selecting)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.tagsExpanded = true;
              })
          } else if (this.tagsExpanded && this.tagNames.length > TAG_TOP_N) {
            Text('收起')
              .fontSize(11)
              .fontColor(museTextSecondary(this.isDarkMode))
              .padding({
                left: MuseSpace.sm,
                right: MuseSpace.sm,
                top: 2,
                bottom: 2
              })
              .margin({ right: MuseSpace.xs, top: MuseSpace.xs })
              .borderRadius(MuseRadius.pill)
              .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentOrDefault()))
              .accessibilityText('收起标签')
              .accessibilityDescription('点两下只显示前几个标签')
              .enabled(!this.selecting)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.tagsExpanded = false;
              })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(MuseSpace.lg)
    .borderRadius(MuseRadius.card)
    // 多选选中时整卡换底色 + 加粗描边：只靠右上角一个勾，在长列表里扫一眼看不出来
    .backgroundColor(this.selecting && this.selected
      ? resolveAccentSoftBg(this.isDarkMode, this.accentOrDefault())
      : resolveCardSurface(this.isDarkMode, this.cardSurface))
    .border({
      width: this.selecting && this.selected ? 2 : 1,
      color: this.selecting && this.selected
        ? resolvePrimaryColor(this.isDarkMode, this.accentOrDefault())
        : resolveCardBorder(this.isDarkMode, this.accentOrDefault())
    })
  }

  /** 多选态的勾选圈：选中是实心 + 勾，未选中是空心圈（用 border 画圈，避开 Circle 的 fill/stroke 高版本 API） */
  @Builder
  SelectionMark() {
    Text(this.selected ? '✓' : '')
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(onAccentColor(resolvePrimaryColor(this.isDarkMode, this.accentOrDefault())))
      .width(22)
      .height(22)
      .textAlign(TextAlign.Center)
      .borderRadius(11)
      .backgroundColor(this.selected ? resolvePrimaryColor(this.isDarkMode, this.accentOrDefault()) : Color.Transparent)
      .border({
        width: 1.5,
        color: this.selected
          ? resolvePrimaryColor(this.isDarkMode, this.accentOrDefault())
          : resolveCardBorder(this.isDarkMode, this.accentOrDefault())
      })
  }

  /** 页面推下来的当前时间；页面没给（0）时用本机时间兜底 */
  private currentTime(): number {
    return this.now > 0 ? this.now : Date.now();
  }

  /** 正文片段：链接已切好、标签已削掉（`LinkParser.buildBodySegments`） */
  private bodySegments(): LinkSegment[] {
    return buildBodySegments(this.content);
  }

  /** 正文最终显示出来的纯文字（削掉标签、保留链接原文） */
  private displayText(): string {
    return bodyText(this.content);
  }

  /** 默认只平铺前 `TAG_TOP_N` 颗标签，展开后全给 */
  private visibleTags(): string[] {
    return this.tagsExpanded ? this.tagNames : this.tagNames.slice(0, TAG_TOP_N);
  }

  /** 被折进 `+N` 的标签数量（未折叠时为 0） */
  private hiddenTagCount(): number {
    return this.tagNames.length - this.visibleTags().length;
  }

  /**
   * 量一量正文在给定宽度下会不会超过 `BODY_MAX_LINES` 行。
   *
   * 用 `UIContext.getMeasureUtils().measureTextSize`（旧的 `MeasureText.measureTextSize`
   * 已标记废弃）。量不出来就不提示：宁可少一个「展开」，也不能让一次测量失败影响列表渲染。
   */
  private measureTruncation(width: Length): void {
    const available: number = typeof width === 'number' ? width : Number.parseFloat(`${width}`);
    if (!Number.isFinite(available) || available <= 0) {
      return;
    }
    let truncated: boolean = false;
    try {
      const measure = this.getUIContext().getMeasureUtils();
      const total: SizeOptions = measure.measureTextSize({
        textContent: this.displayText(),
        constraintWidth: available,
        fontSize: BODY_FONT_SIZE,
        lineHeight: BODY_LINE_HEIGHT
      });
      // 量出来的高度是 vp 还是 px，d.ts 里没有写清，所以**不去猜单位**：
      // 再用同样的参数量一个单行文本当基准，用比值算行数——比值与单位无关，
      // 换台密度不同的设备也不会错。（早期版本直接拿高度比 `8 * 24`，
      // 结果是「一条两行的正文也被判成截断」，「展开」恒亮。）
      const oneLine: SizeOptions = measure.measureTextSize({
        textContent: '一',
        constraintWidth: available,
        fontSize: BODY_FONT_SIZE,
        lineHeight: BODY_LINE_HEIGHT
      });
      const totalHeight: number = sizeToNumber(total.height);
      const lineHeight: number = sizeToNumber(oneLine.height);
      truncated = lineHeight > 0 && totalHeight / lineHeight > BODY_MAX_LINES + 0.01;
    } catch (err) {
      truncated = false;
    }
    // 只在真的变了才写 @State：否则「提示出现 → 重新布局 → 再量一次」可能自激
    if (truncated !== this.bodyTruncated) {
      this.bodyTruncated = truncated;
    }
  }

  /**
   * 读屏用的整卡描述。
   *
   * 顺序刻意是「相对时间 → 置顶/已编辑 → 正文」：读屏用户最需要先知道这条有多旧，
   * 而正文可能很长；标签由 chip 自己再念一遍，所以这里不重复。
   * 念的内容与屏幕上显示的一致（都走 `displayText()`），否则会出现「听见了看不见的字」。
   */
  private cardAccessibilityText(): string {
    const prefix = this.pinned ? '已置顶，' : '';
    const edited = this.edited ? '，已编辑' : '';
    return `${prefix}${relativeTime(this.createdAt, this.currentTime())}${edited}，${this.displayText()}`;
  }

  /** 命中片段与链接共用的颜色（深浅模式各取一个够读的主题色） */
  private highlightColor(): string {
    const accent = this.accentOrDefault();
    return this.isDarkMode ? resolvePrimaryColor(true, accent) : mixHex(accent, '#000000', HIGHLIGHT_DARKEN);
  }

  private chipTextColor(): string {
    return resolvePrimaryColor(this.isDarkMode, this.accentOrDefault());
  }

  private accentOrDefault(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }
}
