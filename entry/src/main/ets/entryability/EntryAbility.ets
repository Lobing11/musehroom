import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { RdbHelper } from '../database/RdbHelper';
import { setAppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { NAVIGATION_BAR_HEIGHT_KEY, STATUS_BAR_HEIGHT_KEY } from '../utils/Constants';
import {
  LAUNCH_ACTION_CAPTURE,
  LAUNCH_ACTION_KEY,
  LAUNCH_ACTION_PARAM,
  LAUNCH_ACTION_REVIEW
} from '../utils/Constants';
import {
  ACCENT_COLOR_KEY,
  ACCENT_CUSTOM_STORAGE,
  ACCENT_KEY_STORAGE,
  DARK_MODE_DARK,
  DARK_MODE_KEY,
  DARK_MODE_LIGHT,
  DARK_MODE_PREF_STORAGE,
  DARK_MODE_SYSTEM,
  DEFAULT_ACCENT_KEY,
  applyAppTheme,
  resolveAccentColor
} from '../utils/DesignTokens';

/** 状态栏/导航栏内容色：浅色底用深字，深色底用浅字 */
const BAR_CONTENT_LIGHT: string = '#182431';
const BAR_CONTENT_DARK: string = '#F0F2F5';

/**
 * 应用入口 Ability。
 *
 * ============================================================================
 * 启动顺序（**四步必须在 loadContent 之前全部做完**）
 * ============================================================================
 *   ① 初始化设置仓库（Preferences）—— 后面几步都要读它
 *   ② 读「深浅模式偏好」→ 写进 AppStorage → `setColorMode()` 交给系统
 *   ③ 把主题色设置写进 AppStorage —— 页面的 `@StorageLink` 才拿得到初值
 *   ④ 算出最终深浅 + 主题色 → 写 token 并广播 —— 首屏才不是默认色
 *
 * 少做哪一步会怎样：
 *   - 只做 ② 不做 ④：**自绘界面还是浅色，系统弹窗/输入法却是深色**，两边错配。
 *   - 只做 ④ 不做 ②：自绘深色了，但系统控件（弹窗、滚动条、输入法）不跟随。
 *   - 少做 ③：设置页里的开关「点一下又弹回去」（拿不到初值）。
 *   - 这里若整套跳过、改在页面 `aboutToAppear` 里补：**首屏会闪一下默认色**
 *     （先渲染一帧默认主题，再被改正）。
 *
 * 为什么不能换成「异步 init + 异步读盘」：那会留下「数据没读完就开始渲染」的空窗期，
 * 表现为冷启动时页面颜色跳变。设置项总量很小，同步读的耗时可以忽略。
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 桌面快捷方式（`shortcuts_config.json`）与服务卡片的深链都从 Want 参数进来，
    // 手法是「解析 → 写进 AppStorage」，由首页订阅后自己响应一次（见 Index.ets）。
    this.applyLaunchAction(want);
    this.applyStoredSettings();
    // 把上下文交给全局，页面不必去猜「UIContext 里的 HostContext 此刻是否就绪」
    setAppContext(this.context);
    this.warmUpDatabase();
    Logger.info('Ability onCreate');
  }

  /**
   * 应用已在运行时（热启动）从快捷方式/卡片再次进入。
   *
   * 这一条**不能省**：`onCreate` 只在进程冷启动时跑一次，用户第二次点「记一条灵感」
   * 时进程还活着，只有 `onNewWant` 会被调到 —— 少了它，快捷方式「点一次有效、再点没反应」。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyLaunchAction(want);
    Logger.info('Ability onNewWant');
  }

  /**
   * 解析启动意图并写进 AppStorage。
   *
   * 只认白名单里的两个动作：Want 是可以被外部构造的（`exported: true`），
   * 把任意字符串当命令用等于把「页面行为」开放给外部输入。
   */
  private applyLaunchAction(want: Want): void {
    const params = want.parameters;
    if (params === undefined) {
      return;
    }
    const raw = params[LAUNCH_ACTION_PARAM];
    if (typeof raw !== 'string') {
      return;
    }
    const action = raw as string;
    if (action !== LAUNCH_ACTION_CAPTURE && action !== LAUNCH_ACTION_REVIEW) {
      Logger.warn(`未知的启动意图：${action}`);
      return;
    }
    AppStorage.setOrCreate(LAUNCH_ACTION_KEY, action);
    Logger.info(`启动意图：${action}`);
  }

  /**
   * 预热数据库。
   *
   * 建库 + 建表这几十毫秒完全可以和「窗口还在加载」重叠：首页 `aboutToAppear` 里
   * 再要一次拿到的是同一个 Promise（`RdbHelper` 做了并发去重），不会重复打开。
   * 失败不阻断启动 —— `RdbHelper` 失败不缓存，首次真正读写时会再试一次。
   */
  private warmUpDatabase(): void {
    RdbHelper.getStore(this.context).then(() => {
      Logger.info('数据库预热完成');
    }).catch((err: Error) => {
      Logger.warn(`数据库预热失败（首次读写时会重试）：${err.message}`);
    });
  }

  onDestroy(): void {
    Logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let mainWindow: window.Window | null = null;
    try {
      mainWindow = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      // 全屏布局：让内容铺到状态栏底下，再由页面按 insets 自己留白
      mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
        Logger.error(`setWindowLayoutFullScreen 失败：${err.message}`);
      });
      this.applySystemBar(mainWindow);
    } catch (err) {
      Logger.error(`获取主窗口失败：${JSON.stringify(err)}`);
    }

    // 收窄成 const：回调里才不会因为「变量可能被改过」而丢掉非空判断
    const win: window.Window | null = mainWindow;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.error(`加载首页失败：${JSON.stringify(err)}`);
        return;
      }
      Logger.info('首页加载完成');
      // 内容就绪后再量一次避让区：此时窗口尺寸才是最终值
      if (win !== null) {
        this.publishWindowInsets(win);
        // 键盘弹出/收起、旋转、折叠都会触发它 —— 不加监听就只能靠页面自己猜高度
        win.on('avoidAreaChange', () => {
          this.publishWindowInsets(win);
        });
      }
    });
  }

  onWindowStageDestroy(): void {
    // ⚠️ 窗口销毁后对旧窗口调 off 会抛 1300002（窗口已不存在），必须吞掉并置空
    if (this.mainWindow !== null) {
      try {
        this.mainWindow.off('avoidAreaChange');
      } catch (err) {
        Logger.warn(`注销避让区监听失败：${JSON.stringify(err)}`);
      }
      this.mainWindow = null;
    }
    Logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.debug('Ability onForeground');
  }

  onBackground(): void {
    Logger.debug('Ability onBackground');
  }

  /**
   * 系统配置变化（深浅模式、语言、字号…）。
   *
   * ⚠️ **这个回调会被 `setColorMode()` 同步触发**，
   *    所以里面**绝不能再调 `setColorMode()`**，否则「回调→设色→回调」自激。
   *    这里只做一件事：把新的深浅结果算出来、广播出去。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    let pref = AppStorage.get<string>(DARK_MODE_PREF_STORAGE);
    if (pref === undefined || pref.length === 0) {
      pref = DARK_MODE_SYSTEM;
    }

    let isDark: boolean;
    if (pref === DARK_MODE_DARK) {
      isDark = true;
    } else if (pref === DARK_MODE_LIGHT) {
      isDark = false;
    } else {
      // 跟随系统：用回调带进来的新配置，比再查一次 resourceManager 更及时
      isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }

    this.publishTheme(isDark, pref);
    if (this.mainWindow !== null) {
      this.applySystemBar(this.mainWindow);
    }
    Logger.info(`配置变化：深色=${isDark.toString()}，偏好=${pref}`);
  }

  // ==========================================================================
  // 启动链路
  // ==========================================================================

  private applyStoredSettings(): void {
    // ① 设置仓库
    AppSettingsStore.init(this.context);

    // ② 深浅模式偏好
    let pref = AppSettingsStore.getString(DARK_MODE_PREF_STORAGE, DARK_MODE_SYSTEM);
    if (pref !== DARK_MODE_DARK && pref !== DARK_MODE_LIGHT) {
      pref = DARK_MODE_SYSTEM;
    }
    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);
    this.applySystemColorMode(pref);

    // ③ 主题色设置 —— 写进 AppStorage，页面的 @StorageLink 才有初值
    const accentKey = AppSettingsStore.getString(ACCENT_KEY_STORAGE, DEFAULT_ACCENT_KEY);
    const accentCustom = AppSettingsStore.getString(ACCENT_CUSTOM_STORAGE, '');
    AppStorage.setOrCreate(ACCENT_KEY_STORAGE, accentKey);
    AppStorage.setOrCreate(ACCENT_CUSTOM_STORAGE, accentCustom);

    // ④ 算最终结果并广播
    this.publishTheme(this.resolveDarkMode(pref), pref);
  }

  /** 把最终深浅与主题色写进 token / AppStorage（唯一广播出口） */
  private publishTheme(isDark: boolean, pref: string): void {
    const accentKey = AppStorage.get<string>(ACCENT_KEY_STORAGE);
    const accentCustom = AppStorage.get<string>(ACCENT_CUSTOM_STORAGE);
    const accent = resolveAccentColor(
      accentKey === undefined ? DEFAULT_ACCENT_KEY : accentKey,
      accentCustom === undefined ? '' : accentCustom
    );

    AppStorage.setOrCreate(DARK_MODE_PREF_STORAGE, pref);
    AppStorage.setOrCreate(DARK_MODE_KEY, isDark);
    // ⚠️ 第二个参数一定要传主题色：省略时页面背景的染色会被重置回默认色
    applyAppTheme(isDark, accent);
    AppStorage.setOrCreate(ACCENT_COLOR_KEY, accent);
  }

  /**
   * 交给系统：决定「系统控件」跟随哪一档。
   * 跟随系统时必须传 `COLOR_MODE_NOT_SET`（交还系统），不能传当前推断出的那一档，
   * 否则等于把用户的选择从「跟随系统」偷偷改成固定值。
   */
  private applySystemColorMode(pref: string): void {
    let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (pref === DARK_MODE_DARK) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (pref === DARK_MODE_LIGHT) {
      mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      this.context.getApplicationContext().setColorMode(mode);
    } catch (err) {
      Logger.error(`setColorMode 失败：${JSON.stringify(err)}`);
    }
  }

  /** 偏好明确则听偏好；`'system'` 才去问系统当前是不是深色 */
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
      const config = this.context.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      Logger.warn(`读取系统深浅模式失败，按浅色处理：${JSON.stringify(err)}`);
      return false;
    }
  }

  // ==========================================================================
  // 窗口
  // ==========================================================================

  private applySystemBar(win: window.Window): void {
    const isDark = AppStorage.get<boolean>(DARK_MODE_KEY) === true;
    const contentColor = isDark ? BAR_CONTENT_DARK : BAR_CONTENT_LIGHT;
    const props: window.SystemBarProperties = {
      // 透明状态栏 + 透明导航栏：页面底色自己铺满，避免顶部出现一条异色带
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor
    };
    try {
      win.setWindowSystemBarProperties(props);
    } catch (err) {
      Logger.error(`设置系统栏失败：${JSON.stringify(err)}`);
    }
  }

  /**
   * 量出避让区高度并广播（单位换算成 vp）。
   * 页面顶部/底部留白订阅它，而不是各写一个魔法数字。
   */
  private publishWindowInsets(win: window.Window): void {
    try {
      const uiContext = win.getUIContext();
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const statusBarHeight = uiContext.px2vp(systemArea.topRect.height);
      const navigationBarHeight = navArea.bottomRect.height > 0 ? uiContext.px2vp(navArea.bottomRect.height) : 0;
      AppStorage.setOrCreate(STATUS_BAR_HEIGHT_KEY, statusBarHeight);
      AppStorage.setOrCreate(NAVIGATION_BAR_HEIGHT_KEY, navigationBarHeight);
    } catch (err) {
      Logger.warn(`量取避让区失败：${JSON.stringify(err)}`);
    }
  }
}
