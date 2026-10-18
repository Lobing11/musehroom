import { Idea } from '../model/Idea';
import { formatDayLabel, formatTime } from '../utils/DateUtil';
import { trashRemainingDays } from '../utils/TrashRetention';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  museDanger,
  museTextPrimary,
  museTextSecondary,
  onAccentColor,
  resolveAccentSoftBg,
  resolveCardSurface,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/**
 * 「最近删除」半模态。
 *
 * 只负责长什么样：数据、恢复、彻底删除、清空都在页面里（与设置面板同一分工），
 * 这样面板本身不依赖仓库，将来换入口（比如从撤销条直接打开）不用搬家。
 *
 * 7 天的剩余天数走 `TrashRetention` 的纯函数，不在渲染里现算：
 * 同一套算术既被单测钉住，也被这里和文档共用，避免「界面说还剩 1 天、清理却已经删了」。
 */
@Component
export struct TrashSheet {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';

  @Prop items: Idea[] = [];
  /** 正在读库/清理过期行：显示转圈并禁用操作 */
  @Prop loading: boolean = false;
  /** 读取失败的原因（空串 = 没有错误） */
  @Prop errorText: string = '';
  /** 父层的走字时间：剩余天数与「删除于」都按它算，避免面板自己停在打开那一刻 */
  @Prop now: number = Date.now();

  onRestore: (id: number) => void = () => {
  };
  onDeleteForever: (id: number) => void = () => {
  };
  onClearAll: () => void = () => {
  };
  onRetry: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: MuseSpace.md }) {
      Row() {
        Text('最近删除')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(museTextPrimary(this.isDarkMode))
        Blank()
        Text('✕')
          .fontSize(16)
          .fontColor(museTextSecondary(this.isDarkMode))
          .padding(MuseSpace.xs)
          .accessibilityText('关闭最近删除')
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ top: MuseSpace.md })

      Text('删除的灵感会保留 7 天，之后自动清理。可以随时恢复，或彻底删除。')
        .fontSize(11)
        .fontColor(museTextSecondary(this.isDarkMode))
        .width('100%')

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        this.ErrorState()
      } else if (this.items.length === 0) {
        this.EmptyState()
      } else {
        this.TrashList()
        this.ClearButton()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: MuseSpace.lg, right: MuseSpace.lg, bottom: MuseSpace.lg })
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
  }

  // ==========================================================================
  // 片段
  // ==========================================================================

  @Builder
  TrashList() {
    List({ space: MuseSpace.sm }) {
      ForEach(this.items, (item: Idea) => {
        ListItem() {
          this.TrashRow(item)
        }
      }, (item: Idea) => `${item.id}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** 一行：正文摘要 + 删除时间/剩余天数 + 恢复/彻底删除 */
  @Builder
  TrashRow(item: Idea) {
    Column({ space: MuseSpace.sm }) {
      Text(item.content)
        .fontSize(14)
        .fontColor(museTextPrimary(this.isDarkMode))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .accessibilityText(`已删除的灵感：${item.content}`)

      Row({ space: MuseSpace.sm }) {
        Text(this.metaText(item))
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
          .layoutWeight(1)
        Text('恢复')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
          .padding({ left: MuseSpace.sm, right: MuseSpace.sm, top: MuseSpace.xs, bottom: MuseSpace.xs })
          .accessibilityText('恢复这条灵感')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.onRestore(item.id);
          })
        Text('彻底删除')
          .fontSize(13)
          .fontColor(museDanger(this.isDarkMode))
          .padding({ left: MuseSpace.sm, right: MuseSpace.sm, top: MuseSpace.xs, bottom: MuseSpace.xs })
          .accessibilityText('彻底删除这条灵感')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.onDeleteForever(item.id);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.control)
    .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentOrPrimary()))
  }

  @Builder
  EmptyState() {
    Column({ space: MuseSpace.md }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(32)
        .fontColor([museTextSecondary(this.isDarkMode)])
      Text('最近删除是空的')
        .fontSize(14)
        .fontColor(museTextPrimary(this.isDarkMode))
      Text('删除的灵感会在这里保留 7 天，期间随时能找回。')
        .fontSize(12)
        .fontColor(museTextSecondary(this.isDarkMode))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorState() {
    Column({ space: MuseSpace.md }) {
      SymbolGlyph($r('sys.symbol.heavy_rain'))
        .fontSize(32)
        .fontColor([museTextSecondary(this.isDarkMode)])
      Text(this.errorText)
        .fontSize(13)
        .fontColor(museTextSecondary(this.isDarkMode))
        .textAlign(TextAlign.Center)
      Button('重试')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .constraintSize({ minHeight: 36 })
        .fontColor(onAccentColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())))
        .backgroundColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ClearButton() {
    Button('清空最近删除')
      .type(ButtonType.Capsule)
      .fontSize(14)
      .fontColor(museDanger(this.isDarkMode))
      .backgroundColor('#00000000')
      .border({ width: 1, color: museDanger(this.isDarkMode), radius: MuseRadius.pill })
      .constraintSize({ minHeight: 40 })
      .width('100%')
      .accessibilityText('清空最近删除')
      .onClick(() => {
        this.onClearAll();
      })
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }

  private metaText(item: Idea): string {
    const days = trashRemainingDays(item.deletedAt, this.now);
    const remain = days > 0 ? `还剩 ${days} 天` : '今天到期';
    return `删除于 ${formatDayLabel(item.deletedAt, this.now)} ${formatTime(item.deletedAt)} · ${remain}`;
  }
}
