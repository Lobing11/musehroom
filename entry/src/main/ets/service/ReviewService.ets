/**
 * 「灵光再现」：从整个灵感库里随机抽一条，24 小时内不重复。
 *
 * 展示历史落在 preferences 而不是内存里：用户可能今天开一次、明天再开一次，
 * 只记在内存里等于每次冷启动都从零开始，反而更容易连着抽到同一条。
 */
import { Idea } from '../model/Idea';
import { IdeaRepository } from '../repository/IdeaRepository';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { Logger } from '../utils/Logger';
import { REVIEW_HISTORY_KEY, REVIEW_HISTORY_LIMIT, REVIEW_WINDOW_MS } from '../utils/Constants';

export class ReviewService {
  private repo: IdeaRepository;

  constructor(repo: IdeaRepository) {
    this.repo = repo;
  }

  /**
   * 抽下一条。
   *
   * 返回 null 只代表「库里确实没有可回顾的灵感」（空库），不是失败。
   */
  async next(): Promise<Idea | null> {
    const recent = this.recentIds();
    let picked = await this.repo.randomActive(recent);
    if (picked === null && recent.length > 0) {
      // 库不大时 24 小时窗口会把所有灵感都排除干净：宁可重复一条，
      // 也不要给用户一张空白的「灵光再现」——那看起来像功能坏了。
      Logger.info(`灵光再现：${recent.length} 条都在 24 小时窗口内，清空窗口重抽`);
      this.clearHistory();
      picked = await this.repo.randomActive([]);
    }
    if (picked !== null) {
      this.remember(picked.id);
    }
    return picked;
  }

  /** 24 小时窗口内展示过的 id（过期的条目顺手丢掉） */
  private recentIds(): number[] {
    const raw = AppSettingsStore.getStringArray(REVIEW_HISTORY_KEY, []);
    const now = Date.now();
    const ids: number[] = [];
    for (let i = 0; i < raw.length; i++) {
      const at = ReviewService.timestampOf(raw[i]);
      if (at < 0 || now - at > REVIEW_WINDOW_MS) {
        continue;
      }
      const id = ReviewService.idOf(raw[i]);
      if (id > 0) {
        ids.push(id);
      }
    }
    return ids;
  }

  private remember(id: number): void {
    const now = Date.now();
    const raw = AppSettingsStore.getStringArray(REVIEW_HISTORY_KEY, []);
    const kept: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      const at = ReviewService.timestampOf(raw[i]);
      if (at < 0 || now - at > REVIEW_WINDOW_MS) {
        continue;
      }
      kept.push(raw[i]);
    }
    kept.push(`${id}:${now}`);
    // 只留最近的若干条（数组按写入顺序追加，从尾部截断即可）
    const start = kept.length > REVIEW_HISTORY_LIMIT ? kept.length - REVIEW_HISTORY_LIMIT : 0;
    AppSettingsStore.setStringArray(REVIEW_HISTORY_KEY, kept.slice(start));
  }

  private clearHistory(): void {
    AppSettingsStore.setStringArray(REVIEW_HISTORY_KEY, []);
  }

  /** 一条历史记录形如 'id:时间戳'；格式不对返回 -1（当作过期丢弃） */
  private static timestampOf(entry: string): number {
    const separator = entry.indexOf(':');
    if (separator <= 0) {
      return -1;
    }
    const at = Number.parseInt(entry.substring(separator + 1), 10);
    return Number.isNaN(at) ? -1 : at;
  }

  private static idOf(entry: string): number {
    const separator = entry.indexOf(':');
    if (separator <= 0) {
      return -1;
    }
    const id = Number.parseInt(entry.substring(0, separator), 10);
    return Number.isNaN(id) ? -1 : id;
  }
}
