import { MAX_CONTENT_LENGTH } from '../utils/Constants';
import { parseTags } from '../utils/TagParser';
import { Haptics } from '../utils/Haptics';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  museTextPrimary,
  museTextSecondary,
  onAccentColor,
  resolveAccentSoftBg,
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/** 剩余字数少于这个值时开始显示计数，平时不打扰 */
const COUNTER_THRESHOLD: number = 500;
/** 实时标签预览最多摆几个，剩下的收成 +N */
const PREVIEW_TAG_LIMIT: number = 4;

/**
 * 记录栏 —— 全应用最该被优化的一个控件。
 *
 * 产品定位是「3—5 秒记一条」，所以这里的设计取舍都围绕「少一次操作」：
 *   - 常驻在页面底部（拇指区），不需要先找入口、不需要开新页面；
 *   - 不做标题/分类/确认弹窗，写完直接点保存；
 *   - 保存成功后**保持焦点**，可以连着记第二条；
 *   - 保存失败时**不清空输入框**，用户打的字不会白费。
 *
 * 回车键刻意保留为「换行」而不是「保存」：灵感经常是一句话写不完的两三行，
 * 抢掉回车反而要用户去找按钮；保存统一走右侧按钮，认知负担更低。
 *
 * 「实时标签预览」是这一版新增的：标签在正文里是 `#` 号，写完才发觉得回头改很烦，
 * 所以边打边把「会被归入哪些标签」摆出来。预览用的是与入库完全相同的 TagParser，
 * 不另写一套判断——两套规则迟早会不一致，而那种不一致最难对账。
 */
@Component
export struct CaptureBar {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';

  @State private draft: string = '';
  @State private saving: boolean = false;

  onSubmitted: (content: string) => Promise<boolean> = (content: string): Promise<boolean> => {
    return Promise.resolve(false);
  };

  build() {
    Column({ space: MuseSpace.xs }) {
      Row({ space: MuseSpace.sm }) {
        TextArea({ text: this.draft, placeholder: '记下此刻的灵感…' })
          .id('capture_input')
          .layoutWeight(1)
          .maxLength(MAX_CONTENT_LENGTH)
          .fontSize(16)
          .lineHeight(22)
          .fontColor(museTextPrimary(this.isDarkMode))
          .placeholderFont({ size: 16 })
          .placeholderColor(museTextSecondary(this.isDarkMode))
          .backgroundColor('#00000000')
          .padding({ left: 0, right: 0, top: MuseSpace.sm, bottom: MuseSpace.sm })
          .borderRadius(MuseRadius.control)
          .constraintSize({ minHeight: 40, maxHeight: 132 })
          .onChange((value: string) => {
            this.draft = value;
          })

        Button('保存')
          .type(ButtonType.Capsule)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canSave() ? onAccentColor(this.buttonColor()) : museTextSecondary(this.isDarkMode))
          .backgroundColor(this.canSave() ? this.buttonColor() : this.disabledButtonColor())
          .padding({ left: 22, right: 22 })
          .constraintSize({ minHeight: 40 })
          .enabled(this.canSave())
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (this.draftTags().length > 0) {
        this.TagPreview()
      }

      if (this.showCounter()) {
        Row() {
          Blank()
          Text(`${this.draft.length} / ${MAX_CONTENT_LENGTH}`)
            .fontSize(11)
            .fontColor(museTextSecondary(this.isDarkMode))
        }
        .width('100%')
      }
    }
    .width('100%')
    // 只留上下间距：左右留白由页面根容器的「装订线」统一给，
    // 组件自己再写 margin 就会和 width('100%') 打架、顶到屏幕边
    .margin({ top: MuseSpace.sm, bottom: MuseSpace.md })
    .padding({
      left: MuseSpace.lg,
      right: MuseSpace.md,
      top: MuseSpace.sm,
      bottom: MuseSpace.sm
    })
    .borderRadius(MuseRadius.card)
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentOrDefault()) })
  }

  @Builder
  TagPreview() {
    Row({ space: MuseSpace.xs }) {
      Text('保存后归入')
        .fontSize(11)
        .fontColor(museTextSecondary(this.isDarkMode))
      ForEach(this.visibleDraftTags(), (name: string) => {
        Text(`#${name}`)
          .fontSize(11)
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrDefault()))
          .padding({
            left: MuseSpace.sm,
            right: MuseSpace.sm,
            top: 2,
            bottom: 2
          })
          .borderRadius(MuseRadius.pill)
          .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentOrDefault()))
      }, (name: string) => name)
      if (this.draftTags().length > PREVIEW_TAG_LIMIT) {
        Text(`+${this.draftTags().length - PREVIEW_TAG_LIMIT}`)
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
      Blank()
    }
    .width('100%')
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  private async submit(): Promise<void> {
    const text = this.draft.trim();
    if (text.length === 0 || this.saving) {
      return;
    }
    this.saving = true;
    try {
      const ok = await this.onSubmitted(text);
      if (ok) {
        this.draft = '';
        // 手上那一下比屏幕上的提示更快：用户常常不看屏幕就接着打第二条
        Haptics.confirm();
        this.keepFocus();
      }
    } finally {
      this.saving = false;
    }
  }

  /**
   * 保存后把焦点要回输入框，方便连着记下一条。
   * 失败无所谓（用户顶多多点一下），所以吞掉异常——但绝不吞掉保存本身的异常。
   */
  private keepFocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('capture_input');
    } catch (err) {
      // 焦点拿不回来不影响功能
    }
  }

  /** 当前草稿里会被入库的标签（与入库同一套解析规则） */
  private draftTags(): string[] {
    return parseTags(this.draft);
  }

  private visibleDraftTags(): string[] {
    return this.draftTags().slice(0, PREVIEW_TAG_LIMIT);
  }

  private canSave(): boolean {
    return !this.saving && this.draft.trim().length > 0;
  }

  private showCounter(): boolean {
    return this.draft.length > MAX_CONTENT_LENGTH - COUNTER_THRESHOLD;
  }

  private buttonColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentOrDefault());
  }

  private disabledButtonColor(): string {
    return this.isDarkMode ? '#2A322C' : '#E4E7E4';
  }

  private accentOrDefault(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }
}
