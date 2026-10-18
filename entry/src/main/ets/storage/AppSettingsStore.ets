import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PREF_STORE_NAME } from '../utils/Constants';
import { Logger } from '../utils/Logger';

/**
 * 设置持久化（preferences）。
 * ============================================================================
 * 核心纪律：**「通知」和「持久化」是两件事，都要做。**
 *
 *   写进 preferences 只保证「重启后还在」，**不会**让界面刷新；
 *   让界面刷新的是 `AppStorage` 广播（见 DesignTokens.reloadAppTheme）。
 *
 * 所以设置项的标准写法是「三连」：
 *
 *     AppSettingsStore.setString(KEY, v);   // ① 落盘
 *     AppStorage.setOrCreate(KEY, v);       // ② 建/更新订阅键（@StorageLink 才有初值）
 *     reloadAppTheme();                     // ③ 重算 token 并广播
 *
 *   漏掉 ①：重启后设置丢失。
 *   漏掉 ②：@StorageLink 拿不到初值，开关会「点一下弹回去」。
 *   漏掉 ③：token 是旧值，界面不刷新。
 *
 * 用**同步** preferences（`getPreferencesSync`）：设置量小、又要在首屏渲染前读完，
 * 同步读最省事也最不容易出错。
 *
 * ----------------------------------------------------------------------------
 * 为什么每个方法都套了 try/catch
 * ----------------------------------------------------------------------------
 * ① preferences 的这批接口**都会抛异常**（磁盘满、文件损坏、句柄失效…），
 *    编译器会逐处提示「Function may throw exceptions」。设置项读失败不该让应用起不来。
 * ② 失败策略分两种，刻意不同：
 *      读 → 回落到 default value（`getString` 等），让应用带着默认设置继续跑；
 *      写 → 只记日志（`setXxx`），因为调用方通常已经先更新了 AppStorage，
 *           本次会话仍然是对的，只是「重启后丢」。
 *    两种都会打 error 日志，方便真机上定位。
 */
export class AppSettingsStore {
  private static prefs: preferences.Preferences | null = null;

  /**
   * 必须在 `EntryAbility.onCreate` 里调用，且要在读任何设置**之前**。
   *
   * 入参刻意收的是基类 `common.Context` 而不是 `common.UIAbilityContext`：
   * 服务卡片跑在 `FormExtensionAbility` 里，拿到的是 `FormExtensionContext`——
   * 它**不是** UIAbilityContext，但一样能开 preferences。卡片要按用户的主题色出图
   * （见 `widget/WidgetData.ets`），就必须让这条路径对它也开放。
   */
  static init(context: common.Context): void {
    if (AppSettingsStore.prefs !== null) {
      return;
    }
    try {
      AppSettingsStore.prefs = preferences.getPreferencesSync(context, {
        name: PREF_STORE_NAME
      });
      Logger.info('AppSettingsStore initialized');
    } catch (err) {
      // 初始化失败不阻断启动：后续读取都会回落到默认值，用户顶多发现「设置没记住」
      AppSettingsStore.prefs = null;
      Logger.error(`AppSettingsStore 初始化失败：${JSON.stringify(err)}`);
    }
  }

  /** 供调用方判断「存储是否已就绪」，避免未初始化就读取时抛异常 */
  static isReady(): boolean {
    return AppSettingsStore.prefs !== null;
  }

  private static store(): preferences.Preferences {
    if (AppSettingsStore.prefs === null) {
      throw new Error('AppSettingsStore 未初始化：请先在 EntryAbility.onCreate 里调 init()');
    }
    return AppSettingsStore.prefs;
  }

  static has(key: string): boolean {
    try {
      return AppSettingsStore.store().hasSync(key);
    } catch (err) {
      Logger.error(`has 失败 key=${key}：${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 读布尔。
   *
   * 用 `typeof` 校验而不直接信返回值：存储内容可能是**旧版本写入的另一种类型**
   * （例如某个键以前存字符串，现在改成布尔），直接当布尔用会得到一个「真值」的字符串。
   */
  static getBoolean(key: string, defaultValue: boolean): boolean {
    try {
      const value = AppSettingsStore.store().getSync(key, defaultValue);
      return typeof value === 'boolean' ? value : defaultValue;
    } catch (err) {
      Logger.error(`getBoolean 失败 key=${key}：${JSON.stringify(err)}`);
      return defaultValue;
    }
  }

  static getString(key: string, defaultValue: string): string {
    try {
      const value = AppSettingsStore.store().getSync(key, defaultValue);
      return typeof value === 'string' ? value : defaultValue;
    } catch (err) {
      Logger.error(`getString 失败 key=${key}：${JSON.stringify(err)}`);
      return defaultValue;
    }
  }

  static getNumber(key: string, defaultValue: number): number {
    try {
      const value = AppSettingsStore.store().getSync(key, defaultValue);
      return typeof value === 'number' ? value : defaultValue;
    } catch (err) {
      Logger.error(`getNumber 失败 key=${key}：${JSON.stringify(err)}`);
      return defaultValue;
    }
  }

  /**
   * 字符串数组。
   *
   * ⚠️ preferences **不直接支持数组**，所以统一存成 JSON 字符串；
   *    读入时解析失败一律回落到默认值 —— 存储内容可能被外部改坏或残留旧版本数据。
   */
  static getStringArray(key: string, defaultValue: string[]): string[] {
    const raw = AppSettingsStore.getString(key, '');
    if (raw.length === 0) {
      return defaultValue.slice();
    }
    try {
      const parsed = JSON.parse(raw) as Object;
      if (parsed instanceof Array) {
        return parsed.map((item: Object) => String(item));
      }
    } catch (err) {
      Logger.warn(`getStringArray: failed to parse key=${key}`);
    }
    return defaultValue.slice();
  }

  // --- 写：一律 putSync + flushSync -----------------------------------------
  // flushSync 是「立刻落盘」。外观设置不 flush 也能用（系统会择机写），
  // 但用户切完主题色就杀进程时会丢，代价只有几毫秒，不值得省。

  static setBoolean(key: string, value: boolean): void {
    try {
      AppSettingsStore.store().putSync(key, value);
      AppSettingsStore.store().flushSync();
    } catch (err) {
      Logger.error(`setBoolean 失败 key=${key}：${JSON.stringify(err)}`);
    }
  }

  static setString(key: string, value: string): void {
    try {
      AppSettingsStore.store().putSync(key, value);
      AppSettingsStore.store().flushSync();
    } catch (err) {
      Logger.error(`setString 失败 key=${key}：${JSON.stringify(err)}`);
    }
  }

  static setNumber(key: string, value: number): void {
    try {
      AppSettingsStore.store().putSync(key, value);
      AppSettingsStore.store().flushSync();
    } catch (err) {
      Logger.error(`setNumber 失败 key=${key}：${JSON.stringify(err)}`);
    }
  }

  static setStringArray(key: string, value: string[]): void {
    AppSettingsStore.setString(key, JSON.stringify(value));
  }

  static delete(key: string): void {
    try {
      AppSettingsStore.store().deleteSync(key);
      AppSettingsStore.store().flushSync();
    } catch (err) {
      Logger.error(`delete 失败 key=${key}：${JSON.stringify(err)}`);
    }
  }
}
