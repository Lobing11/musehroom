import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';

/**
 * 已登记的卡片 id 名单。
 *
 * 为什么需要它：系统只在 `onAddForm` 的 want 里给一次 formId，之后**没有任何接口能列出
 * 「本应用现在有哪些卡片」**。而「系统切深色 / 用户在设置里换主题色」时我们要主动把卡片
 * 重画一遍，就必须自己记住这些 id。
 *
 * 单独一个 preferences 文件（`musehroom_cards`）：formId 是系统给的运行期标识，不是用户设置，
 * 不该混进 `musehroom_settings` 里（那份清单将来要跟着导出/迁移走）。
 */
const CARD_STORE_NAME: string = 'musehroom_cards';
const CARD_IDS_KEY: string = 'formIds';

export class CardRegistry {
  /** 记住一张卡（`onAddForm` 时调用）；重复登记会被忽略 */
  static remember(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids = CardRegistry.list(context);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    CardRegistry.save(context, ids);
  }

  /** 忘掉一张卡（`onRemoveForm`、或刷新时发现这张卡已经不在了） */
  static forget(context: common.Context, formId: string): void {
    const kept: string[] = [];
    const ids = CardRegistry.list(context);
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        kept.push(ids[i]);
      }
    }
    if (kept.length === ids.length) {
      return;
    }
    CardRegistry.save(context, kept);
  }

  /** 当前登记着的全部卡片 id；读失败按「没有卡片」处理（宁可少刷，不要崩） */
  static list(context: common.Context): string[] {
    try {
      const store = CardRegistry.store(context);
      if (store === null) {
        return [];
      }
      const raw: preferences.ValueType = store.getSync(CARD_IDS_KEY, []);
      if (!(raw instanceof Array)) {
        return [];
      }
      const ids: string[] = [];
      for (let i = 0; i < raw.length; i++) {
        const item: preferences.ValueType = raw[i];
        if (typeof item === 'string') {
          ids.push(item as string);
        }
      }
      return ids;
    } catch (err) {
      Logger.warn(`卡片清单读取失败：${(err as Error).message}`);
      return [];
    }
  }

  static clear(context: common.Context): void {
    CardRegistry.save(context, []);
  }

  private static store(context: common.Context): preferences.Preferences | null {
    try {
      const options: preferences.Options = { name: CARD_STORE_NAME };
      return preferences.getPreferencesSync(context, options);
    } catch (err) {
      Logger.warn(`卡片清单打开失败：${(err as Error).message}`);
      return null;
    }
  }

  private static save(context: common.Context, ids: string[]): void {
    const store = CardRegistry.store(context);
    if (store === null) {
      return;
    }
    try {
      store.putSync(CARD_IDS_KEY, ids);
      store.flushSync();
    } catch (err) {
      Logger.warn(`卡片清单写入失败：${(err as Error).message}`);
    }
  }
}
