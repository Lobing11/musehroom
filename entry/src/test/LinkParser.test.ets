import { describe, it, expect } from '@ohos/hypium';
import { bodyText, buildBodySegments, LinkSegment, splitLinks } from '../main/ets/utils/LinkParser';

/**
 * `LinkParser` 单测。
 *
 * 它是「什么算一个链接」的唯一定义（卡片正文的分段与点击都从这儿来），纯函数、无系统依赖，
 * 所以放在**本地单测**（`entry/src/test/`，跑在 PC 上，不需要真机）。
 *
 * 这里盯三类回归：
 *   ① 识别边界——只认 `http(s)://`，中文标点收尾，英文收尾标点要吐回正文；
 *   ② **字符不丢**——`splitLinks` 的片段首尾相接必须等于原文；`https://` 后面空无一物
 *      这种退化输入最容易在这里出错（曾经把它当普通文字时从中间切开，丢掉了半截 scheme）；
 *   ③ 与 `stripTags` 的先后顺序——先切链接、再削标签。反过来的话
 *      `https://a.com/p#产品` 会被削成两截，点不动。
 */
export default function linkParserTest() {
  describe('LinkParser', () => {
    it('识别链接并保留前后文字', 0, () => {
      const segments: LinkSegment[] =
        splitLinks('看这个 https://ohpm.openharmony.cn/#/cn/detail 很好用');
      expect(segments.length).assertEqual(3);
      expect(segments[0].isLink).assertFalse();
      expect(segments[0].text).assertEqual('看这个 ');
      expect(segments[1].isLink).assertTrue();
      expect(segments[1].text).assertEqual('https://ohpm.openharmony.cn/#/cn/detail');
      expect(segments[2].text).assertEqual(' 很好用');
    });

    it('中文句号收尾不进链接', 0, () => {
      const segments: LinkSegment[] = splitLinks('见 https://a.com。');
      expect(segments[1].isLink).assertTrue();
      expect(segments[1].text).assertEqual('https://a.com');
      expect(segments[2].text).assertEqual('。');
    });

    it('英文右括号是收尾标点，要吐回正文', 0, () => {
      const segments: LinkSegment[] = splitLinks('(https://a.com)');
      expect(segments[1].text).assertEqual('https://a.com');
      expect(segments[2].text).assertEqual(')');
    });

    it('http 也认，问号等号属于链接', 0, () => {
      const segments: LinkSegment[] = splitLinks('a http://b.com/c?d=1 e');
      expect(segments[1].isLink).assertTrue();
      expect(segments[1].text).assertEqual('http://b.com/c?d=1');
    });

    it('裸域名与 www. 不算链接', 0, () => {
      const segments: LinkSegment[] = splitLinks('灵感.md 与 3.5 与 www.a.com');
      expect(segments.length).assertEqual(1);
      expect(segments[0].isLink).assertFalse();
      expect(segments[0].text).assertEqual('灵感.md 与 3.5 与 www.a.com');
    });

    it('只有 scheme 后面空无一物时，正文一个字都不能少', 0, () => {
      const segments: LinkSegment[] = splitLinks('https://');
      let joined: string = '';
      for (let i = 0; i < segments.length; i++) {
        expect(segments[i].isLink).assertFalse();
        joined += segments[i].text;
      }
      expect(joined).assertEqual('https://');
    });

    it('多个链接之间是普通文字', 0, () => {
      const segments: LinkSegment[] = splitLinks('https://a.com 和 https://b.com');
      expect(segments.length).assertEqual(3);
      expect(segments[0].isLink).assertTrue();
      expect(segments[1].isLink).assertFalse();
      expect(segments[1].text).assertEqual(' 和 ');
      expect(segments[2].isLink).assertTrue();
    });

    it('先去标签会把链接削断，所以必须先切链接', 0, () => {
      expect(bodyText('https://a.com/p#产品 试试 #灵感')).assertEqual('https://a.com/p#产品 试试');
    });

    it('正文片段去掉标签，但换行留着', 0, () => {
      const segments: LinkSegment[] = buildBodySegments('第一行 #灵感\n第二行');
      expect(segments.length).assertEqual(1);
      expect(segments[0].isLink).assertFalse();
      expect(segments[0].text).assertEqual('第一行 \n第二行');
    });

    it('正文两端不残留空白，中间的空格只留一个', 0, () => {
      const segments: LinkSegment[] = buildBodySegments(' 试试   #灵感  很好 #产品 ');
      expect(segments.length).assertEqual(1);
      expect(segments[0].text).assertEqual('试试 很好');
    });

    it('整条正文只有标签时不留空片段', 0, () => {
      const segments: LinkSegment[] = buildBodySegments('#灵感 #产品');
      expect(segments.length).assertEqual(1);
      expect(segments[0].isLink).assertFalse();
      expect(segments[0].text).assertEqual('');
    });

    it('空正文返回一个空片段，调用方不用判空数组', 0, () => {
      const segments: LinkSegment[] = buildBodySegments('');
      expect(segments.length).assertEqual(1);
      expect(segments[0].text).assertEqual('');
    });
  });
}
