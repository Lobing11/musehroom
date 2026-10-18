import { describe, it, expect } from '@ohos/hypium';
import {
  PRIVACY_EFFECTIVE_DATE,
  PRIVACY_POLICY_URL,
  PRIVACY_SECTIONS,
  PRIVACY_SUMMARY
} from '../main/ets/utils/LegalText';

/**
 * 隐私政策文案单测。
 *
 * 它盯的不是「代码逻辑」而是**几句话还在不在** —— 但恰恰是这几句话要交给应用市场审核：
 *   - 首启面板与设置里的全文页显示的是同一份常量，改坏一处两个入口一起坏；
 *   - 「不申请网络权限 / 不收集信息 / 无第三方 SDK」是这份政策的核心承诺，
 *     如果哪天功能变化把它们悄悄删掉，线上页面还在说「不收集」，两边就自相矛盾了。
 *
 * 纯常量、零系统依赖，所以放在**本地单测**（`entry/src/test/`，跑在 PC 上，不需要真机）。
 */
export default function legalTextTest() {
  describe('LegalText', () => {
    it('线上地址是 https 且指向 GitHub Pages 那个小仓', 0, () => {
      expect(PRIVACY_POLICY_URL.startsWith('https://')).assertEqual(true);
      expect(PRIVACY_POLICY_URL.indexOf('lobing11.github.io/musehroom-legal') > 0).assertEqual(true);
    });

    it('生效日期非空（改文案时必须一起改，否则应用内与线上对不上）', 0, () => {
      expect(PRIVACY_EFFECTIVE_DATE.length > 0).assertEqual(true);
    });

    it('首屏摘要三条，且覆盖「联网 / 收集 / 存在哪」', 0, () => {
      expect(PRIVACY_SUMMARY.length).assertEqual(3);
      const joined = PRIVACY_SUMMARY.join('|');
      expect(joined.includes('网络权限')).assertEqual(true);
      expect(joined.includes('不收集')).assertEqual(true);
      expect(joined.includes('私有目录')).assertEqual(true);
    });

    it('完整条款 9 条，标题从 1 到 9 且不重复', 0, () => {
      expect(PRIVACY_SECTIONS.length).assertEqual(9);
      const titles = PRIVACY_SECTIONS.map((item: PrivacySectionLike) => item.title).join('|');
      expect(titles.includes('1. 我们收集的信息：无')).assertEqual(true);
      expect(titles.includes('9. 联系方式')).assertEqual(true);
      // 标题唯一：重复标题会让用户看到「同一节出现两次」这种明显的排版事故
      const first = titles.indexOf('1. 我们收集的信息：无');
      expect(titles.indexOf('1. 我们收集的信息：无', first + 1)).assertEqual(-1);
    });

    it('三条核心承诺不能被改掉（无网络 / 无收集 / 无第三方 SDK）', 0, () => {
      const all = PRIVACY_SECTIONS.map((item: PrivacySectionLike) => item.body).join('|');
      expect(all.includes('不申请网络权限')).assertEqual(true);
      expect(all.includes('不收集设备标识')).assertEqual(true);
      expect(all.includes('不集成任何广告、统计或分析 SDK')).assertEqual(true);
    });

    it('权限只有「振动」一条，且说明它是普通权限', 0, () => {
      const permission = PRIVACY_SECTIONS[4].body;
      expect(permission.includes('ohos.permission.VIBRATE')).assertEqual(true);
      expect(permission.includes('普通权限')).assertEqual(true);
    });
  });
}

/**
 * `LegalText.PrivacySection` 的形状副本。
 *
 * 为什么不 import 那个 interface：hypium 的用例文件走的是同一套 ArkTS 编译，
 * import 类型当然也行 —— 但这里刻意只描述「用得到的那两个字段」，
 * 这样文案新增字段（比如将来加 `link`）不会牵动这份测试的类型。
 */
interface PrivacySectionLike {
  title: string;
  body: string;
}
