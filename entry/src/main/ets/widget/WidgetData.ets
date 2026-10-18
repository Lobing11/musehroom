import { common } from '@kit.AbilityKit';
import { Idea } from '../model/Idea';
import { IdeaFilter } from '../model/IdeaFilter';
import { RdbIdeaRepository } from '../repository/RdbIdeaRepository';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { relativeTime } from '../utils/DateUtil';
import {
  ACCENT_CUSTOM_STORAGE,
  ACCENT_KEY_STORAGE,
  DEFAULT_ACCENT_KEY,
  resolveAccentColor
} from '../utils/DesignTokens';
import { parseTags, stripTags } from '../utils/TagParser';
import { Logger } from '../utils/Logger';

/** 卡片正文最多显示多少个字（卡片地方小，超出截断加省略号） */
const CARD_TEXT_LIMIT: number = 72;
/** 卡片上最多显示几个标签 */
const CARD_TAG_LIMIT: number = 3;

/**
 * 卡片数据（`formBindingData` 的对象形态）。
 *
 * 字段名会被当成卡片页 `LocalStorage` 的键，改这里必须同步改
 * `entry/src/main/ets/widget/pages/RandomIdeaCard.ets` 与 `RecentIdeaCard.ets`。
 * 两张卡片共用同一份数据 —— 理由见 `WidgetData.build`。
 *
 * 最后一个字段是**主题输入**而不是算好的色值：`accent` 是原始主题色，卡片页把它当半透明叠加用
 * （淡染底、下划线、按钮）。**不带「当前是不是深色」**：卡片是 form 应用，`Environment`/`ColorMode`/
 * `@StorageProp` 都被编译器禁止，深浅只能交给资源（`base/` 与 `dark/` 两份 color.json），
 * 由框架在系统换色时直接替换 —— 这样不需要 App 或扩展进程活着。
 *
 * 为什么不让扩展算好色值（M5 第一版的做法）：色值是**快照**，系统切深色时
 * 写死的十六进制值不会被替换（系统只替换 `$r('sys.color.*')` 这类资源引用），
 * 而 `FormExtensionAbility.onConfigurationUpdate` 只在扩展进程存活时回调 ——
 * 用户切系统深色时进程往往是死的，卡片就会停在旧色（真机实测：两张卡片没跟着变）。
 */
export class CardData {
  randomContent: string = '';
  randomMeta: string = '';
  randomTags: string = '';
  randomEmpty: boolean = true;
  recentContent: string = '';
  recentMeta: string = '';
  recentTags: string = '';
  recentEmpty: boolean = true;
  total: string = '';
  /** 原始主题色（未经深浅变体处理，卡片侧只做半透明叠加） */
  accent: string = '';
}

/**
 * 服务卡片取数。
 *
 * **为什么两张卡的数据一次都算出来**：`onUpdateForm` / `onFormEvent` 只给 formId、
 * 不给卡片名字，扩展里查不到「这个 formId 是哪张卡」；与其维护一份
 * formId → 卡片名 的映射（扩展进程一重启就丢），不如让刷新逻辑与卡片种类彻底无关，
 * 两张卡各取所需字段。代价是多查一次库：两条都是 `LIMIT 1`，可以忽略。
 */
export class WidgetData {
  static async build(context: common.Context): Promise<CardData> {
    const data = new CardData();
    WidgetData.applyPreference(data, context);
    const repo = new RdbIdeaRepository(context);
    const filter = new IdeaFilter();
    try {
      const recent = await repo.listPage(0, 1, filter);
      if (recent.length > 0) {
        WidgetData.fillRecent(data, recent[0]);
      }
      const random = await repo.randomActive([]);
      if (random !== null) {
        WidgetData.fillRandom(data, random);
      }
      const total = await repo.countActive(filter);
      data.total = `${total}`;
    } catch (err) {
      // 卡片取数失败不该让卡片崩掉：交回带默认文案的空卡，日志留下原因
      const error = err as Error;
      Logger.warn(`卡片取数失败：${error.message}`);
    }
    return data;
  }

  /**
   * 只算主题、不查库的空卡。
   *
   * `onAddForm` 必须**同步**返回数据（见 `WidgetAbility`），而查库是异步的；
   * 用这张带正确主题的空卡顶上，用户看到的是「还没有灵感 + 正确的主题色」，
   * 而不是一闪而过的黑白卡；数据随后由 `formProvider.updateForm` 补上。
   */
  static empty(context: common.Context): CardData {
    const data = new CardData();
    WidgetData.applyPreference(data, context);
    return data;
  }

  /**
   * 读出用户选的主题色放进数据。
   *
   * 卡片进程里没有 `EntryAbility` 走过的主题广播，也没有 App 的 `AppStorage`，
   * 所以这里自己读一次 preferences。**只带主题色、不带深浅**：深浅交给卡片侧的资源。
   */
  private static applyPreference(data: CardData, context: common.Context): void {
    // 跨进程不共享内存里的句柄，卡片这边要自己开一次 preferences
    AppSettingsStore.init(context);
    data.accent = resolveAccentColor(
      AppSettingsStore.getString(ACCENT_KEY_STORAGE, DEFAULT_ACCENT_KEY),
      AppSettingsStore.getString(ACCENT_CUSTOM_STORAGE, '')
    );
  }

  private static fillRandom(data: CardData, idea: Idea): void {
    data.randomContent = WidgetData.bodyOf(idea.content);
    data.randomMeta = relativeTime(idea.createdAt, Date.now());
    data.randomTags = WidgetData.tagLine(idea.content);
    data.randomEmpty = false;
  }

  private static fillRecent(data: CardData, idea: Idea): void {
    data.recentContent = WidgetData.bodyOf(idea.content);
    data.recentMeta = relativeTime(idea.createdAt, Date.now());
    data.recentTags = WidgetData.tagLine(idea.content);
    data.recentEmpty = false;
  }

  /**
   * 正文：先**去掉 `#标签`** 再压成一行。
   *
   * 标签在卡片上单独成行显示，正文里再带一遍就是同一句话写两遍（用户报的观感病灶之一）；
   * 去掉之后如果什么都不剩（这条灵感只有标签），就由标签行独自撑起卡片。
   * 换行与连续空格都收成一个空格——卡片里换行会把版面撑破。
   */
  private static bodyOf(content: string): string {
    const oneLine = stripTags(content).replace(/\s+/g, ' ').trim();
    if (oneLine.length <= CARD_TEXT_LIMIT) {
      return oneLine;
    }
    return `${oneLine.substring(0, CARD_TEXT_LIMIT)}…`;
  }

  private static tagLine(content: string): string {
    const tags = parseTags(content);
    const names: string[] = [];
    for (let i = 0; i < tags.length && names.length < CARD_TAG_LIMIT; i++) {
      names.push(`#${tags[i]}`);
    }
    return names.join(' ');
  }
}
