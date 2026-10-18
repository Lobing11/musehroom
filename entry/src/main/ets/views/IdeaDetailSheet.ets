import { MAX_CONTENT_LENGTH } from '../utils/Constants';
import { formatDayLabel, formatTime } from '../utils/DateUtil';
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
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryButtonColor
} from '../utils/DesignTokens';

/**
 * 灵感详情 / 编辑半模态。
 *
 * 为什么用半模态而不是新页面：编辑一条灵感是「顺手改两个字」的轻动作，
 * 跳页面会打断回顾的节奏，也丢掉了背景里列表的上下文。
 *
 * 三个入口（置顶 / 删除 / 保存）都放在这一层，卡片上不摆按钮——
 * 列表要能一眼扫过去，操作收进详情里，误触代价也更低。
 */
@Component
export struct IdeaDetailSheet {
  /**
   * `@Watch` 是必需的，不是保险：bindSheet 的 builder 内容可能在多次打开之间被复用，
   * 而 `aboutToAppear` 只在首次创建时跑。没有 @Watch，第二次打开别的灵感时
   * 编辑框里会残留上一条的内容——这是「看着对、其实在改错对象」的严重 bug。
   */
  @Prop @Watch('onInitialContentChanged') initialContent: string = '';
  @Prop createdAt: number = 0;
  @Prop updatedAt: number = 0;
  @Prop pinned: boolean = false;

  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';

  @State private draft: string = '';

  onSave: (content: string) => void = () => {
  };
  onTogglePin: () => void = () => {
  };
  onDelete: () => void = () => {
  };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.draft = this.initialContent;
  }

  onInitialContentChanged(): void {
    this.draft = this.initialContent;
  }

  build() {
    Column({ space: MuseSpace.md }) {
      this.TitleRow()

      TextArea({ text: this.draft })
        .layoutWeight(1)
        .maxLength(MAX_CONTENT_LENGTH)
        .fontSize(16)
        .lineHeight(24)
        .fontColor(museTextPrimary(this.isDarkMode))
        .backgroundColor(this.fieldColor())
        .borderRadius(MuseRadius.control)
        .padding(MuseSpace.md)
        .onChange((value: string) => {
          this.draft = value;
        })

      this.TimeRow()
      this.ActionRow()
    }
    .width('100%')
    .height('100%')
    .padding({ left: MuseSpace.lg, right: MuseSpace.lg, bottom: MuseSpace.lg })
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
  }

  @Builder
  TitleRow() {
    Row() {
      Text('编辑灵感')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(museTextPrimary(this.isDarkMode))
      Blank()
      Text('✕')
        .fontSize(16)
        .fontColor(museTextSecondary(this.isDarkMode))
        .padding(MuseSpace.xs)
        .accessibilityText('关闭')
        .onClick(() => {
          this.onClose();
        })
    }
    .width('100%')
    .padding({ top: MuseSpace.md })
  }

  @Builder
  TimeRow() {
    Row() {
      Text(`记于 ${formatDayLabel(this.createdAt, Date.now())} ${formatTime(this.createdAt)}`)
        .fontSize(11)
        .fontColor(museTextSecondary(this.isDarkMode))
      Blank()
      if (this.updatedAt - this.createdAt > 1000) {
        Text('已修改')
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
    }
    .width('100%')
  }

  @Builder
  ActionRow() {
    Row({ space: MuseSpace.sm }) {
      Button(this.pinned ? '取消置顶' : '置顶')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .fontColor(museTextPrimary(this.isDarkMode))
        .backgroundColor(this.fieldColor())
        .constraintSize({ minHeight: 40 })
        .layoutWeight(1)
        .onClick(() => {
          this.onTogglePin();
        })

      Button('删除')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .fontColor(museDanger(this.isDarkMode))
        .backgroundColor(this.fieldColor())
        .constraintSize({ minHeight: 40 })
        .layoutWeight(1)
        .onClick(() => {
          this.onDelete();
        })

      Button('保存')
        .type(ButtonType.Capsule)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(onAccentColor(this.buttonColor()))
        .backgroundColor(this.buttonColor())
        .constraintSize({ minHeight: 40 })
        .layoutWeight(1)
        .enabled(this.canSave())
        .opacity(this.canSave() ? 1 : 0.5)
        .onClick(() => {
          this.onSave(this.draft);
        })
    }
    .width('100%')
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  private canSave(): boolean {
    return this.draft.trim().length > 0 && this.draft.trim() !== this.initialContent.trim();
  }

  private buttonColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentOrDefault());
  }

  /** 输入区与次级按钮共用的底色：比卡片再深/浅一档，让「可输入」这件事看得出来 */
  private fieldColor(): string {
    return this.isDarkMode ? '#2A322C' : '#F1F3F1';
  }

  private accentOrDefault(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }
}
