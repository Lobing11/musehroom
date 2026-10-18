import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { CardRefresher } from '../widget/CardRefresher';
import { Logger } from '../utils/Logger';
import {
  ACCENT_COLOR_KEY,
  ACCENT_CUSTOM_STORAGE,
  ACCENT_KEY_STORAGE,
  ACCENT_PRESETS,
  AccentPreset,
  CARD_SURFACE_KEY,
  DARK_MODE_DARK,
  DARK_MODE_KEY,
  DARK_MODE_LIGHT,
  DARK_MODE_PREF_STORAGE,
  DARK_MODE_SYSTEM,
  DEFAULT_ACCENT_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  applyAppTheme,
  museTextPrimary,
  museTextSecondary,
  onAccentColor,
  resolveAccentColor,
  resolveAccentSoftBg,
  resolveCardSurface,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/**
 * 设置半模态：外观（M0 的验证卡片转正）+ 数据（M4 的导出/导入入口）。
 *
 * 主题设置的「三连」写法在这里落地，缺一不可：
 *   ① 落盘 Preferences —— 否则重启丢设置
 *   ② 写 AppStorage —— 否则订阅者拿不到新值
 *   ③ 重算 token 并广播 —— 否则 token 还是旧值，界面不刷新
 *
 * 还有一个容易漏的点：`@StorageProp` 的取色表达式里**必须出现订阅变量**（见 DesignTokens 规则 A），
 * 不能图省事直接调 `currentAccentColor()`——那样读的是 AppStorage 快照，切主题色后颜色不跟着变。
 *
 * 数据区**只负责长什么样**：拼文件、弹系统选择器、写库这些事都在页面里（它拿得到仓库与上下文），
 * 这个组件通过回调把它们要回来。半模态与业务逻辑混在一起，将来换入口（比如服务卡片里也能导）
 * 就得把这一整块搬过去。
 */
@Component
export struct SettingsSheet {
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(ACCENT_CUSTOM_STORAGE) accentCustom: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  @StorageLink(ACCENT_KEY_STORAGE) accentKey: string = DEFAULT_ACCENT_KEY;
  @StorageLink(DARK_MODE_PREF_STORAGE) darkModePreference: string = DARK_MODE_SYSTEM;

  /** 导出/导入进行中（按钮要禁用，避免用户连点两次导出两个文件） */
  @Prop busy: boolean = false;
  /** 上一次操作的结果，逐字显示给用户（导出 N KB / 新增 N 条 / 失败原因） */
  @Prop status: string = '';

  onExportJson: () => void = () => {
  };
  onExportMarkdown: () => void = () => {
  };
  onImportJson: () => void = () => {
  };
  /** 「隐私政策」入口：面板只负责发出请求，真正的打开动作在页面里（与导出/导入同一分工） */
  onOpenPrivacy: () => void = () => {
  };
  /** 「最近删除」入口：同上，面板只发请求 */
  onOpenTrash: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: MuseSpace.lg }) {
      Row() {
        Text('设置')
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

      // ---- 深浅模式：三态，不是开关 ----
      Column({ space: MuseSpace.sm }) {
        Text('深浅模式')
          .fontSize(12)
          .fontColor(museTextSecondary(this.isDarkMode))

        Row() {
          this.ModeChip(DARK_MODE_SYSTEM, '跟随系统')
          this.ModeChip(DARK_MODE_LIGHT, '浅色')
          this.ModeChip(DARK_MODE_DARK, '深色')
        }
        .width('100%')
        .padding(4)
        .borderRadius(MuseRadius.control)
        .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColorOrPrimary()))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      // ---- 主题色 ----
      Column({ space: MuseSpace.sm }) {
        Row() {
          Text('主题色')
            .fontSize(12)
            .fontColor(museTextSecondary(this.isDarkMode))
          Blank()
          Text(this.accentColorOrPrimary())
            .fontSize(12)
            .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColorOrPrimary()))
        }
        .width('100%')

        Row() {
          ForEach(ACCENT_PRESETS, (item: AccentPreset) => {
            this.AccentSwatch(item)
          }, (item: AccentPreset) => item.key)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      // ---- 数据：导出 / 导入 ----
      Column({ space: MuseSpace.sm }) {
        Row() {
          Text('数据')
            .fontSize(12)
            .fontColor(museTextSecondary(this.isDarkMode))
          Blank()
          if (this.busy) {
            Text('处理中…')
              .fontSize(11)
              .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentColorOrPrimary()))
          }
        }
        .width('100%')

        this.DataRow($r('sys.symbol.arrow_up_circle'), '导出为 JSON', '完整备份：含标签与原始时间，可以再导回来', () => {
          this.onExportJson();
        })
        this.DataRow($r('sys.symbol.doc_text_2'), '导出为 Markdown', '给人读：按日期排好，可直接粘进笔记软件', () => {
          this.onExportMarkdown();
        })
        this.DataRow($r('sys.symbol.arrow_down_circle'), '从 JSON 导入', '合并式导入：已删除的会恢复，仍在库里的才跳过', () => {
          this.onImportJson();
        })
        // 放在导出/导入之后：先备份、再整理，回收站是「整理」这条线的兜底
        this.DataRow($r('sys.symbol.trash'), '最近删除', '删除的灵感保留 7 天，可在这里找回', () => {
          this.onOpenTrash();
        })

        if (this.status.length > 0) {
          Text(this.status)
            .fontSize(11)
            .width('100%')
            .fontColor(museTextPrimary(this.isDarkMode))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      // ---- 关于：隐私政策入口 ----
      // 审核要求用户**随时**能查到完整条款，不能只有首次启动那一次提示。
      Column({ space: MuseSpace.sm }) {
        Text('关于')
          .fontSize(12)
          .fontColor(museTextSecondary(this.isDarkMode))

        this.DataRow($r('sys.symbol.lock'), '隐私政策', '不联网、不收集信息；查看完整条款', () => {
          this.onOpenPrivacy();
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Text('设置与数据都只保存在这台设备上；导出文件放在你选择的位置。')
        .fontSize(11)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: MuseSpace.lg, right: MuseSpace.lg, bottom: MuseSpace.lg })
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
  }

  // ==========================================================================
  // 片段（参数都是常量，不存在 @Builder 按值传参的刷新陷阱）
  // ==========================================================================

  @Builder
  ModeChip(pref: string, label: string) {
    Text(label)
      .fontSize(14)
      .constraintSize({ minHeight: 36 })
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .borderRadius(MuseRadius.control - 4)
      .backgroundColor(this.darkModePreference === pref
        ? resolveCardSurface(this.isDarkMode, this.cardSurface)
        : '#00000000')
      .fontColor(this.darkModePreference === pref
        ? resolvePrimaryColor(this.isDarkMode, this.accentColorOrPrimary())
        : museTextSecondary(this.isDarkMode))
      .fontWeight(this.darkModePreference === pref ? FontWeight.Medium : FontWeight.Normal)
      .onClick(() => {
        this.setDarkModePreference(pref);
      })
  }

  @Builder
  AccentSwatch(item: AccentPreset) {
    Column({ space: 4 }) {
      Stack() {
        // 用 Column + backgroundColor 画圆点，而不是 Circle().fill()：
        // `fill()` 是 API 26 才有的接口，本项目 compatibleSdkVersion 是 6.1.1(24)，用它会有兼容性告警
        Column()
          .width(32)
          .height(32)
          .borderRadius(MuseRadius.pill)
          .backgroundColor(item.value)
        if (this.accentKey === item.key) {
          // 记号颜色按亮度自动切黑/白：琥珀黄这类浅色压白字看不清
          Text('✓')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(onAccentColor(item.value))
        }
      }
      .width(44)
      .height(44)
      .borderRadius(MuseRadius.pill)
      .borderWidth(this.accentKey === item.key ? 2 : 0)
      .borderColor(museTextPrimary(this.isDarkMode))

      Text(item.label)
        .fontSize(11)
        .fontColor(this.accentKey === item.key
          ? resolvePrimaryColor(this.isDarkMode, this.accentColorOrPrimary())
          : museTextSecondary(this.isDarkMode))
    }
    .onClick(() => {
      this.setAccentKey(item.key);
    })
  }

  /** 数据区的一行：图标 + 标题 + 说明 + 右侧箭头（整行可点，命中区域才够大） */
  @Builder
  DataRow(icon: Resource, title: string, subtitle: string, action: () => void) {
    Row({ space: MuseSpace.md }) {
      // 系统符号是单色的：统一跟随主题色，与整行的淡底（`resolveAccentSoftBg`）配套
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentColorOrPrimary())])
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor(museTextPrimary(this.isDarkMode))
        Text(subtitle)
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(16)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .padding(MuseSpace.md)
    .borderRadius(MuseRadius.control)
    .backgroundColor(resolveAccentSoftBg(this.isDarkMode, this.accentColorOrPrimary()))
    .opacity(this.busy ? 0.5 : 1)
    .onClick(() => {
      if (!this.busy) {
        action();
      }
    })
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  private accentColorOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }

  private setDarkModePreference(pref: string): void {
    this.darkModePreference = pref;
    AppSettingsStore.setString(DARK_MODE_PREF_STORAGE, pref);
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);

    const isDark = this.resolveDarkMode(pref);
    applyAppTheme(isDark, this.accentColorOrPrimary());
    AppStorage.setOrCreate(DARK_MODE_KEY, isDark);
    this.applySystemColorMode(pref);
    this.refreshCards();
  }

  private setAccentKey(key: string): void {
    this.accentKey = key;
    AppSettingsStore.setString(ACCENT_KEY_STORAGE, key);
    AppStorage.setOrCreate(ACCENT_KEY_STORAGE, key);

    const resolved = resolveAccentColor(key, this.accentCustom);
    AppStorage.setOrCreate(ACCENT_COLOR_KEY, resolved);
    applyAppTheme(this.isDarkMode, resolved);
    this.refreshCards();
  }

  /**
   * 卡片进程读不到 App 的 `AppStorage`，也拿不到「用户强制了浅色/深色」这件事，
   * 所以改了深浅偏好或主题色之后要主动推一次数据（卡片颜色本身由卡片页按系统深浅现算）。
   * 失败只记日志：卡片没刷新不该影响设置本身。
   */
  private refreshCards(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      CardRefresher.refreshAll(ctx);
    } catch (err) {
      Logger.warn(`设置变更后刷新卡片失败：${(err as Error).message}`);
    }
  }

  private resolveDarkMode(pref: string): boolean {
    if (pref === DARK_MODE_DARK) {
      return true;
    }
    if (pref === DARK_MODE_LIGHT) {
      return false;
    }
    return this.systemDarkMode();
  }

  private systemDarkMode(): boolean {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config = ctx.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  /** 把选择交给系统（管弹窗/输入法外观），失败不影响自绘界面 */
  private applySystemColorMode(pref: string): void {
    let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (pref === DARK_MODE_DARK) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (pref === DARK_MODE_LIGHT) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.getApplicationContext().setColorMode(mode);
    } catch (err) {
      // 自绘界面已经跟着变了，系统控件没跟上不算致命
    }
  }
}
