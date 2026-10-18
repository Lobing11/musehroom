/**
 * 统计（热力图 + 标签云）的数据。
 *
 * 一次把两份聚合都拉回来：它们各是一次全库查询（万条量级几十毫秒），而统计面板是
 * **用户主动打开**的，不在冷启动路径上，所以没必要做缓存表或增量维护。
 */
import { IdeaFilter } from '../model/IdeaFilter';
import { Tag } from '../model/Tag';
import { HeatmapData } from '../model/StatsData';
import { IdeaRepository } from '../repository/IdeaRepository';
import { buildHeatmap } from '../utils/Heatmap';
import { Logger } from '../utils/Logger';

export class StatsViewModel {
  private repo: IdeaRepository;
  private heatData: HeatmapData = new HeatmapData();
  private tags: Tag[] = [];
  private loadingFlag: boolean = false;
  private errorText: string = '';

  constructor(repo: IdeaRepository) {
    this.repo = repo;
  }

  /**
   * 重新加载统计。
   *
   * 热力图刻意**不带当前筛选条件**：统计页看的是「我一共记录了多少」，
   * 而筛选是时间轴上的临时视角；否则用户点了一天再打开统计，会看到被自己筛过的小数字。
   */
  async load(): Promise<void> {
    this.loadingFlag = true;
    this.errorText = '';
    try {
      const stats = await this.repo.listDayStats(new IdeaFilter());
      this.heatData = buildHeatmap(stats, Date.now());
      this.tags = await this.repo.listTags();
    } catch (err) {
      const error = err as Error;
      this.errorText = '统计加载失败，稍后再试';
      Logger.error(`加载统计失败：${error.message}`);
    } finally {
      this.loadingFlag = false;
    }
  }

  heat(): HeatmapData {
    return this.heatData;
  }

  /** 标签权重清单（已按条数降序，来自数据库聚合） */
  tagWeights(): Tag[] {
    return this.tags;
  }

  isLoading(): boolean {
    return this.loadingFlag;
  }

  lastError(): string {
    return this.errorText;
  }

  /** 热力图上方的概览文案 */
  summary(): string {
    const heat = this.heatData;
    if (heat.totalCount === 0) {
      return '近 12 周还没有记录';
    }
    const streak = heat.currentStreak > 0 ? ` · 连续记录 ${heat.currentStreak} 天` : '';
    return `近 12 周 · 共 ${heat.totalCount} 条 · 有记录 ${heat.activeDays} 天${streak}`;
  }

  /** 标签云的字号要按「最大权重」归一，这里是那个分母 */
  maxTagCount(): number {
    let max = 0;
    for (let i = 0; i < this.tags.length; i++) {
      if (this.tags[i].count > max) {
        max = this.tags[i].count;
      }
    }
    return max;
  }

  minTagCount(): number {
    if (this.tags.length === 0) {
      return 0;
    }
    let min = this.tags[0].count;
    for (let i = 1; i < this.tags.length; i++) {
      if (this.tags[i].count < min) {
        min = this.tags[i].count;
      }
    }
    return min;
  }
}
