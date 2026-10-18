import { describe, it, expect } from '@ohos/hypium';
import { DAY_MS, isTrashExpired, trashRemainingDays } from '../main/ets/utils/TrashRetention';

/**
 * 「最近删除」保留期单测。
 *
 * 用固定时间戳（不依赖运行时刻）：`now` 取本地时间 2026-10-18 12:00，
 * 断言只关心「相对 now 的差值」，所以机器时区不影响结果。
 */
const DAY: number = 24 * 60 * 60 * 1000;
const NOW: number = new Date(2026, 9, 18, 12, 0).getTime();

export default function trashRetentionTest() {
  describe('TrashRetention', () => {
    it('DAY_MS 是 24 小时', 0, () => {
      expect(DAY_MS).assertEqual(DAY);
    });

    it('刚删除时还剩 7 天', 0, () => {
      expect(trashRemainingDays(NOW, NOW)).assertEqual(7);
      expect(trashRemainingDays(NOW - 60 * 60 * 1000, NOW)).assertEqual(7);
    });

    it('走字滞后或时钟回拨也不会算出 8 天', 0, () => {
      // 界面的 now 来自每分钟一次的 nowTick：刚删完时它可能还没走到，差值会多出一小节
      expect(trashRemainingDays(NOW, NOW - 30 * 1000)).assertEqual(7);
      expect(trashRemainingDays(NOW, NOW - 5 * 60 * 1000)).assertEqual(7);
    });

    it('第 6 天整天仍显示 1 天（向上取整）', 0, () => {
      expect(trashRemainingDays(NOW - 6 * DAY, NOW)).assertEqual(1);
      expect(trashRemainingDays(NOW - 6 * DAY - 23 * 60 * 60 * 1000, NOW)).assertEqual(1);
      expect(trashRemainingDays(NOW - 7 * DAY + 1000, NOW)).assertEqual(1);
    });

    it('恰好满 7 天算今天到期（0 天）', 0, () => {
      expect(trashRemainingDays(NOW - 7 * DAY, NOW)).assertEqual(0);
      expect(trashRemainingDays(NOW - 7 * DAY - 1, NOW)).assertEqual(0);
    });

    it('没有删除时间的行按 0 天处理', 0, () => {
      expect(trashRemainingDays(0, NOW)).assertEqual(0);
    });

    it('过期判断与 DAO 的清理口径一致（严格小于截止点）', 0, () => {
      expect(isTrashExpired(NOW - 7 * DAY + 1000, NOW)).assertFalse();
      expect(isTrashExpired(NOW - 7 * DAY, NOW)).assertFalse();
      expect(isTrashExpired(NOW - 7 * DAY - 1, NOW)).assertTrue();
      expect(isTrashExpired(0, NOW)).assertTrue();
    });
  });
}
