/**
 * 隐私政策半模态：**两种形态共用一个组件**。
 *
 *   mode = onboarding —— 首次启动的告知（摘要 + 空白复选框 + 「同意并继续」/「不同意」）
 *   mode = full       —— 完整条款（设置里的入口、以及首启面板点「查看完整」后切过来）
 *
 * 为什么两态放一个组件：审查看的是「启动时显著提示 + 随时能查到完整条款」这一件事，
 * 两种情况显示的是同一份 `LegalText` 常量。分成两个半模态反而会出现
 * 「首启面板改过、设置里那页忘了改」这种漂移。
 *
 * 1.0.1 审核整改的两处修改：
 *   ① 首启面板加了**默认不勾选的空白复选框**与**拒绝按钮**：勾选前「同意并继续」不可点，
 *      「不同意」走 `onDecline`（页面确认后退出应用）。不再有「点一下就默认同意」的路径，
 *      也不再用 ✕ 逃避选择（首启形态没有关闭按钮，下滑/返回也被页面拦下）；
 *   ② 首启面板切到完整条款后，顶部出现「‹ 返回」，系统返回/下滑也回到告知面板而不是
 *      把整张半模态关掉 —— 之前「查看完整隐私政策 → 返回」会把同意流程一起丢掉。
 *
 * 这个组件**只负责长什么样**：不改设置、不落盘。接受/拒绝动作由页面处理
 * （页面才拿得到 `AppSettingsStore` 与 UIAbilityContext），与 `SettingsSheet` 的分工一致。
 *
 * ⚠️ 本应用**没有网络权限**：下面的「在浏览器打开」是交给系统浏览器（隐式 Want）去访问，
 * 应用自己不发任何请求；万一设备上没有浏览器，回落成「复制链接」。
 */
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Logger } from '../utils/Logger';
import { toast } from '../utils/Feedback';
import { openExternalUrl } from '../utils/UrlLauncher';
import { Haptics } from '../utils/Haptics';
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
  resolveCardBorder,
  resolveCardSurface,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';
import {
  PRIVACY_APP_LINE,
  PRIVACY_EFFECTIVE_DATE,
  PRIVACY_POLICY_URL,
  PRIVACY_SECTIONS,
  PRIVACY_SUMMARY,
  PrivacySection
} from '../utils/LegalText';

/** 首次启动的告知形态 */
export const PRIVACY_MODE_ONBOARDING: string = 'onboarding';
/** 完整条款形态 */
export const PRIVACY_MODE_FULL: string = 'full';

@Component
export struct PrivacySheet {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = DEFAULT_ACCENT_VALUE;
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';

  @Prop mode: string = PRIVACY_MODE_ONBOARDING;
  /** 从首启告知切到完整条款时为 true：顶部出现返回，返回动作是「回到告知面板」而不是关面板 */
  @Prop showBack: boolean = false;

  /**
   * 复选框状态：**默认不勾选**。
   *
   * 审核明确要求「空白复选框 + 用户自愿、明确勾选」，所以这个值只能由用户点出来，
   * 初始值是 false 且没有任何代码替用户置 true。切到完整条款再回来时它会被保留
   * （状态挂在组件上，mode 只是换渲染分支）。
   */
  @State private agreed: boolean = false;

  /** 首启面板 → 完整条款（页面切 mode） */
  onReadFull: () => void = () => {
  };
  /** 「同意并继续」：页面负责落盘并关闭 */
  onAccept: () => void = () => {
  };
  /** 「不同意」：页面负责二次确认并退出应用（本应用没有不涉及个人信息的「基础功能」可退守） */
  onDecline: () => void = () => {
  };
  /** 完整条款顶部返回：回到首启告知（仅 showBack 时出现） */
  onBack: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: MuseSpace.md }) {
      Row({ space: MuseSpace.sm }) {
        // 从「首启告知」进来查看全文时，左上角必须有回去的路：
        // 之前这里没有返回，用户只能下滑/系统返回把整张半模态关掉，同意流程也就一起没了
        if (this.mode === PRIVACY_MODE_FULL && this.showBack) {
          Text('‹')
            .fontSize(22)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
            .padding({ left: MuseSpace.xs, right: MuseSpace.xs })
            .accessibilityText('返回隐私政策告知')
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              Haptics.tap();
              this.onBack();
            })
        }
        Text(this.mode === PRIVACY_MODE_ONBOARDING ? '欢迎使用灵感菇' : '隐私政策')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(museTextPrimary(this.isDarkMode))
        Blank()
        if (this.mode === PRIVACY_MODE_FULL) {
          Text(PRIVACY_EFFECTIVE_DATE)
            .fontSize(11)
            .fontColor(museTextSecondary(this.isDarkMode))
            .margin({ right: MuseSpace.sm })
        }
        // 首启形态**刻意不提供 ✕**：同意与否必须由复选框 + 两个按钮明确表达，
        // 不能靠一个「关掉就走」的入口绕过（1.0.0 审核问题 2 的一部分）。
        if (this.mode === PRIVACY_MODE_FULL && !this.showBack) {
          Text('✕')
            .fontSize(16)
            .fontColor(museTextSecondary(this.isDarkMode))
            .padding(MuseSpace.xs)
            .accessibilityText('关闭')
            .onClick(() => {
              this.onClose();
            })
        }
      }
      .width('100%')
      .padding({ top: MuseSpace.md })

      // 两种形态各用**自己的 Scroll**：切换时组件重建，滚动位置自然回到顶部。
      // 共用同一个 Scroll 的话，完整条款读到一半返回，告知面板会停在半截空白处。
      if (this.mode === PRIVACY_MODE_ONBOARDING) {
        Scroll() {
          Column({ space: MuseSpace.md }) {
            this.OnboardingBody()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: MuseSpace.md })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        Scroll() {
          Column({ space: MuseSpace.md }) {
            this.FullBody()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: MuseSpace.md })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }

      this.Actions()
    }
    .width('100%')
    // 半模态给的是确定高度，这里必须撑满：里面的 Scroll 才有可滚动的空间
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: MuseSpace.lg, right: MuseSpace.lg, bottom: MuseSpace.lg })
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
  }

  // ==========================================================================
  // 两种形态的正文
  // ==========================================================================

  @Builder
  OnboardingBody() {
    Text('灵感菇是一个「先捕捉、再整理、后回顾」的灵感记录本。开始之前，请先了解它怎么对待你的内容。')
      .fontSize(13)
      .fontColor(museTextPrimary(this.isDarkMode))
      .width('100%')

    this.SummaryList()

    // 摘要是「三句话」，完整条款给一个明确的入口：审核要求用户随时能查到全文
    Row({ space: MuseSpace.sm }) {
      Text('查看完整隐私政策')
        .fontSize(13)
        .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
      Blank()
      Text('›')
        .fontSize(16)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.control)
    .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
    .accessibilityText('查看完整隐私政策')
    .onClick(() => {
      Haptics.tap();
      this.onReadFull();
    })
  }

  @Builder
  FullBody() {
    Text(PRIVACY_APP_LINE)
      .fontSize(11)
      .fontColor(museTextSecondary(this.isDarkMode))
      .width('100%')

    this.SummaryList()

    ForEach(PRIVACY_SECTIONS, (item: PrivacySection) => {
      this.SectionItem(item)
    }, (item: PrivacySection) => item.title)

    Text('以上条款与线上页面完全一致；线上地址见下方，可在任意浏览器打开核对。')
      .fontSize(11)
      .fontColor(museTextSecondary(this.isDarkMode))
      .width('100%')
      .margin({ top: MuseSpace.xs })
  }

  /** 三条摘要：首启面板与完整条款页共用同一份文案（LegalText.PRIVACY_SUMMARY） */
  @Builder
  SummaryList() {
    Column({ space: MuseSpace.sm }) {
      ForEach(PRIVACY_SUMMARY, (line: string) => {
        Row({ space: MuseSpace.sm }) {
          Text('✓')
            .fontSize(13)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
          Text(line)
            .fontSize(13)
            .fontColor(museTextPrimary(this.isDarkMode))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (line: string) => line)
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.control)
    .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
  }

  /** 单条条款。参数是常量数组里的元素，不涉及 @Builder 按值传参的刷新陷阱 */
  @Builder
  SectionItem(item: PrivacySection) {
    Column({ space: 4 }) {
      Text(item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(museTextPrimary(this.isDarkMode))
      Text(item.body)
        .fontSize(12)
        .lineHeight(19)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==========================================================================
  // 底部动作区
  // ==========================================================================

  @Builder
  Actions() {
    if (this.mode === PRIVACY_MODE_ONBOARDING) {
      Column({ space: MuseSpace.sm }) {
        // 「空白复选框」：默认不勾选，只能由用户自己点出来。
        // 勾选前「同意并继续」不可点 —— 这正是审核要的「自愿、明确勾选」
        Row({ space: MuseSpace.xs }) {
          Checkbox({ name: 'privacyAgree' })
            .select(this.agreed)
            .selectedColor(this.filledButtonColor())
            .width(20)
            .height(20)
            .accessibilityText('我已阅读并同意隐私政策')
            .onChange((value: boolean) => {
              this.agreed = value;
              if (value) {
                Haptics.tap();
              }
            })
          Text('我已阅读并同意')
            .fontSize(13)
            .fontColor(museTextPrimary(this.isDarkMode))
            .onClick(() => {
              this.agreed = !this.agreed;
            })
          Text('《隐私政策》')
            .fontSize(13)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
            .onClick(() => {
              Haptics.tap();
              this.onReadFull();
            })
          Blank()
        }
        .width('100%')

        // 同意与拒绝并排、都可点：审核要看到「用户可以选择不授权」
        Row({ space: MuseSpace.sm }) {
          Button('不同意')
            .fontSize(15)
            .layoutWeight(1)
            .constraintSize({ minHeight: 44 })
            .backgroundColor('#00000000')
            .borderWidth(1)
            .borderColor(resolveCardBorder(this.isDarkMode, this.accentColor))
            .fontColor(museDanger(this.isDarkMode))
            .onClick(() => {
              Haptics.tap();
              this.onDecline();
            })
          Button('同意并继续')
            .fontSize(15)
            .layoutWeight(1)
            .constraintSize({ minHeight: 44 })
            .enabled(this.agreed)
            .opacity(this.agreed ? 1 : 0.45)
            .backgroundColor(this.filledButtonColor())
            .fontColor(onAccentColor(this.filledButtonColor()))
            .onClick(() => {
              Haptics.confirm();
              this.onAccept();
            })
        }
        .width('100%')

        Text('勾选后才能继续。不同意将退出应用；本应用不联网，也不会收集你的任何信息。')
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
    } else {
      Column({ space: MuseSpace.sm }) {
        // 链接本身可长按复制（不依赖剪贴板权限，用户主动选择文本）
        Text(PRIVACY_POLICY_URL)
          .fontSize(12)
          .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')

        Row({ space: MuseSpace.sm }) {
          Button('复制链接')
            .fontSize(14)
            .layoutWeight(1)
            .constraintSize({ minHeight: 42 })
            .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColor))
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColor))
            .onClick(() => {
              this.copyLink();
            })
          Button('在浏览器打开')
            .fontSize(14)
            .layoutWeight(1)
            .constraintSize({ minHeight: 42 })
            .backgroundColor(this.filledButtonColor())
            .fontColor(onAccentColor(this.filledButtonColor()))
            .onClick(() => {
              this.openInBrowser();
            })
        }
        .width('100%')

        Text('本应用没有网络权限，「在浏览器打开」由系统浏览器访问；应用自身不发任何请求。')
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
          .width('100%')
      }
      .width('100%')
    }
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  private filledButtonColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentColor);
  }

  /** 复制线上地址。写剪贴板不需要额外权限；失败就把话说清楚，别让用户以为点了没反应 */
  private copyLink(): void {
    Haptics.tap();
    const ui = this.getUIContext();
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, PRIVACY_POLICY_URL);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        toast(ui, '已复制隐私政策链接');
      }).catch((err: BusinessError) => {
        Logger.warn(`复制隐私政策链接失败：${err.message}`);
        toast(ui, '复制失败，可长按上方链接手动复制');
      });
    } catch (err) {
      const error = err as Error;
      Logger.warn(`复制隐私政策链接异常：${error.message}`);
      toast(ui, '复制失败，可长按上方链接手动复制');
    }
  }

  /**
   * 交给系统浏览器。
   *
   * 隐式 Want（`ohos.want.action.viewData` + `entity.system.browsable`）由系统挑一个能看网页的应用，
   * 这样应用不需要（也不该）持有网络权限；设备上没装浏览器时 startAbility 会失败，回落成提示复制链接。
   */
  private openInBrowser(): void {
    Haptics.tap();
    openExternalUrl(this.getUIContext(), PRIVACY_POLICY_URL, '没能打开浏览器，可复制链接后手动访问');
  }
}
