import { describe, it, expect } from '@ohos/hypium';
import { dateKey, daysBetween, formatDayLabel, formatTime, relativeTime, startOfDay } from '../main/ets/utils/DateUtil';

/**
 * `DateUtil` 单测（本地单测，跑在 PC 上）。
 *
 * 全部用 `new Date(y, m, d, h, min)` **按本地时区构造**再取时间戳：
 * 这些函数的口径就是「本地日期」（时间轴分组、热力图分桶都按它），
 * 用固定 UTC 毫秒当输入会让测试随运行机器的时区飘。
 */
export default function dateUtilTest() {
  describe('DateUtil', () => {
    it('dateKey 补零到 YYYY-MM-DD', 0, () => {
      expect(dateKey(new Date(2026, 0, 3, 5, 6).getTime())).assertEqual('2026-01-03');
      expect(dateKey(new Date(2026, 11, 31, 23, 59).getTime())).assertEqual('2026-12-31');
    });

    it('startOfDay 抹掉时分秒毫秒', 0, () => {
      const d = new Date(startOfDay(new Date(2026, 9, 5, 17, 42, 33, 123).getTime()));
      expect(d.getHours()).assertEqual(0);
      expect(d.getMinutes()).assertEqual(0);
      expect(d.getSeconds()).assertEqual(0);
      expect(d.getMilliseconds()).assertEqual(0);
      expect(d.getDate()).assertEqual(5);
    });

    it('formatTime 是 HH:mm', 0, () => {
      expect(formatTime(new Date(2026, 9, 5, 9, 5).getTime())).assertEqual('09:05');
      expect(formatTime(new Date(2026, 9, 5, 23, 59).getTime())).assertEqual('23:59');
    });

    it('daysBetween 只看自然日、不看时分秒', 0, () => {
      const lateYesterday = new Date(2026, 9, 4, 23, 59).getTime();
      const earlyToday = new Date(2026, 9, 5, 0, 1).getTime();
      expect(daysBetween(lateYesterday, earlyToday)).assertEqual(1);
      expect(daysBetween(new Date(2026, 9, 5, 1, 0).getTime(), new Date(2026, 9, 5, 23, 0).getTime())).assertEqual(0);
    });

    it('formatDayLabel 今天/昨天/月日/跨年带年份', 0, () => {
      const now = new Date(2026, 9, 5, 12, 0).getTime();
      expect(formatDayLabel(new Date(2026, 9, 5, 8, 0).getTime(), now)).assertEqual('今天');
      expect(formatDayLabel(new Date(2026, 9, 4, 8, 0).getTime(), now)).assertEqual('昨天');
      expect(formatDayLabel(new Date(2026, 9, 1, 8, 0).getTime(), now)).assertEqual('10 月 1 日');
      expect(formatDayLabel(new Date(2025, 11, 31, 8, 0).getTime(), now)).assertEqual('2025 年 12 月 31 日');
    });

    it('relativeTime 刚刚 / 分钟 / 小时', 0, () => {
      const now = new Date(2026, 9, 5, 12, 0).getTime();
      expect(relativeTime(now - 30000, now)).assertEqual('刚刚');
      expect(relativeTime(now - 12 * 60000, now)).assertEqual('12 分钟前');
      expect(relativeTime(now - 3 * 3600000, now)).assertEqual('3 小时前');
    });

    it('relativeTime 昨天 / N 天前 / 更早回落日期', 0, () => {
      const now = new Date(2026, 9, 5, 12, 0).getTime();
      expect(relativeTime(new Date(2026, 9, 4, 12, 0).getTime(), now)).assertEqual('昨天');
      expect(relativeTime(new Date(2026, 9, 2, 12, 0).getTime(), now)).assertEqual('3 天前');
      expect(relativeTime(new Date(2026, 8, 20, 12, 0).getTime(), now)).assertEqual('9 月 20 日');
    });

    it('relativeTime 在小时间隔内按小时向下取整', 0, () => {
      const now = new Date(2026, 9, 5, 12, 0).getTime();
      expect(relativeTime(now - (3600000 + 59 * 60000), now)).assertEqual('1 小时前');
    });
  });
}
