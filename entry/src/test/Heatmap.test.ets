import { describe, it, expect } from '@ohos/hypium';
import { buildHeatmap, HEATMAP_WEEKS } from '../main/ets/utils/Heatmap';
import { DayStat } from '../main/ets/model/DayStat';
import { HeatCell } from '../main/ets/model/StatsData';
import { dateKey } from '../main/ets/utils/DateUtil';

/**
 * `buildHeatmap` 单测（纯函数，本地单测，不需要真机）。
 *
 * 热力图是「看一眼就知道自己最近记了没」的界面，最怕两类静默错误：
 *   ① 格子数/对齐算错 —— 整排日期错位一格，没人看得出来但每天都是错的；
 *   ② 把「未来」的格子算进统计 —— 总数、有记录天数、最大密度会被虚高的 0 撑坏口径（纪律 16）。
 *
 * 因此这里全部用**固定时间戳**（`now` 是入参，不是 `Date.now()`），结果可完全复现：
 * 2026-10-05 是周一，回推 11 周（77 天）正好是 2026-07-20，网格最后一天是 2026-10-11。
 */

function statOf(day: string, count: number, pinnedCount: number): DayStat {
  const stat = new DayStat();
  stat.day = day;
  stat.count = count;
  stat.pinnedCount = pinnedCount;
  return stat;
}

function cellOf(cells: HeatCell[], day: string): HeatCell {
  for (let i = 0; i < cells.length; i++) {
    if (cells[i].day === day) {
      return cells[i];
    }
  }
  // 找不到就返回一个「哨兵」格，让断言以可读的方式失败，而不是抛运行时异常
  const missing = new HeatCell();
  missing.day = `缺失:${day}`;
  missing.count = -1;
  missing.weekIndex = -1;
  missing.weekday = -1;
  return missing;
}

function monthLabelOf(cells: HeatCell[], week: number): string {
  return cells[week * 7].monthLabel;
}

export default function heatmapTest() {
  describe('Heatmap', () => {
    const NOW = new Date(2026, 9, 5, 15, 30, 0).getTime(); // 2026-10-05(周一) 15:30
    const stats: DayStat[] = [
      statOf('2026-10-05', 3, 1), // 今天
      statOf('2026-10-04', 2, 0),
      statOf('2026-10-03', 1, 0),
      statOf('2026-09-30', 5, 0),
      statOf('2020-01-01', 99, 0) // 窗口之外，必须完全不影响统计
    ];

    it('网格是 12 周 × 7 天，且从 11 周前的周一开始', 0, () => {
      const data = buildHeatmap(stats, NOW);
      expect(data.cells.length).assertEqual(HEATMAP_WEEKS * 7);
      expect(data.cells.length).assertEqual(84);
      expect(data.cells[0].day).assertEqual('2026-07-20');
      expect(data.cells[0].weekday).assertEqual(0);
      expect(data.cells[83].day).assertEqual('2026-10-11');
      expect(data.cells[83].weekday).assertEqual(6);
    });

    it('今天落在最后一列的周一格', 0, () => {
      const data = buildHeatmap(stats, NOW);
      const today = cellOf(data.cells, dateKey(NOW));
      expect(today.day).assertEqual('2026-10-05');
      expect(today.weekIndex).assertEqual(11);
      expect(today.weekday).assertEqual(0);
      expect(today.inFuture).assertEqual(false);
      expect(today.count).assertEqual(3);
    });

    it('今天之后的一周内是未来格，不计入任何统计', 0, () => {
      const data = buildHeatmap(stats, NOW);
      // 2026-10-06 ~ 10-11 共 6 格在未来
      let future = 0;
      for (let i = 0; i < data.cells.length; i++) {
        if (data.cells[i].inFuture) {
          future = future + 1;
        }
      }
      expect(future).assertEqual(6);
      expect(cellOf(data.cells, '2026-10-06').inFuture).assertEqual(true);
      expect(cellOf(data.cells, '2026-10-11').inFuture).assertEqual(true);
      // 窗口外的 2020-01-01 有 99 条，但不该出现在总数里
      expect(data.totalCount).assertEqual(11);
      expect(data.activeDays).assertEqual(4);
      expect(data.maxCount).assertEqual(5);
    });

    it('连续记录天数：今天没记就从昨天往回数', 0, () => {
      const withToday = buildHeatmap(stats, NOW);
      expect(withToday.currentStreak).assertEqual(3); // 10-05 / 10-04 / 10-03，到 10-02 断

      const withoutToday = buildHeatmap([statOf('2026-10-04', 2, 0), statOf('2026-10-03', 1, 0)], NOW);
      expect(withoutToday.currentStreak).assertEqual(2);

      expect(buildHeatmap([], NOW).currentStreak).assertEqual(0);
    });

    it('空数据时网格依然完整、统计全为 0', 0, () => {
      const data = buildHeatmap([], NOW);
      expect(data.cells.length).assertEqual(84);
      expect(data.totalCount).assertEqual(0);
      expect(data.activeDays).assertEqual(0);
      expect(data.maxCount).assertEqual(0);
      expect(data.currentStreak).assertEqual(0);
      for (let i = 0; i < data.cells.length; i++) {
        expect(data.cells[i].count).assertEqual(0);
      }
    });

    it('月份标签标在「含某月 1 号的那一列」上，第一列永远有', 0, () => {
      const data = buildHeatmap(stats, NOW);
      expect(monthLabelOf(data.cells, 0)).assertEqual('7 月'); // 第一列＝起点那一列（2026-07-20 那周）
      expect(monthLabelOf(data.cells, 1)).assertEqual('8 月'); // 含 2026-08-01（周六）
      expect(monthLabelOf(data.cells, 6)).assertEqual('9 月'); // 含 2026-09-01（周二）
      expect(monthLabelOf(data.cells, 10)).assertEqual('10 月'); // 含 2026-10-01（周四）
      expect(monthLabelOf(data.cells, 2)).assertEqual('');
      expect(monthLabelOf(data.cells, 11)).assertEqual('');
      // 标签只写在每列第一格，列内其它格不能重复带标签
      expect(data.cells[1].monthLabel).assertEqual('');
      expect(data.cells[7 * 2].monthLabel).assertEqual('');
    });
  });
}
