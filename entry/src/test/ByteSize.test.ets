import { describe, it, expect } from '@ohos/hypium';
import { utf8ByteLength } from '../main/ets/utils/ByteSize';

/**
 * 导出提示里的「文件多大」单测。
 *
 * 用例就是真机踩到的那次：一篇只有中文的 Markdown，字符数 151、实际落盘 205 B。
 */
export default function byteSizeTest() {
  describe('ByteSize', () => {
    it('空串是 0 字节', 0, () => {
      expect(utf8ByteLength('')).assertEqual(0);
    });

    it('ASCII 一个字符一个字节', 0, () => {
      expect(utf8ByteLength('multi-one')).assertEqual(9);
      expect(utf8ByteLength('{\n  "count": 2\n}')).assertEqual(16);
    });

    it('汉字与全角标点各 3 字节', 0, () => {
      expect(utf8ByteLength('灵感菇')).assertEqual(9);
      expect(utf8ByteLength('。')).assertEqual(3);
      expect(utf8ByteLength('·')).assertEqual(2);
    });

    it('emoji（代理对）算 4 字节而不是 2', 0, () => {
      expect(utf8ByteLength('🍄')).assertEqual(4);
      expect(utf8ByteLength('你好🍄')).assertEqual(10);
    });

    it('混合文本按段相加', 0, () => {
      expect(utf8ByteLength('a你')).assertEqual(4);
      expect(utf8ByteLength('A1中。')).assertEqual(8);
    });
  });
}
