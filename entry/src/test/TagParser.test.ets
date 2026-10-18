import { describe, it, expect } from '@ohos/hypium';
import { hasTags, parseTags, stripTags } from '../main/ets/utils/TagParser';

/**
 * `TagParser` 单测。
 *
 * 它是「什么算标签」的唯一定义（数据库索引、界面 chips、卡片标签行都从这儿来），
 * 纯函数、无系统依赖，所以放在**本地单测**（`entry/src/test/`，跑在 PC 上，不需要真机）。
 *
 * 这里盯两类回归：
 *   ① 中文/全角/emoji/转义这些「用户随手打出来」的边界（历史上最容易悄悄坏掉）；
 *   ② `stripTags` 与 `parseTags` **必须同源**——卡片正文去掉的东西，
 *      和卡片标签行显示的东西，不能出现「去掉了却没显示」或「显示了却没去掉」。
 */
export default function tagParserTest() {
  describe('TagParser', () => {
    it('解析基本标签并保序', 0, () => {
      const tags = parseTags('#产品 #灵感 试试 #英文Tag #tag2024 #混合_标签');
      expect(tags.length).assertEqual(5);
      expect(tags[0]).assertEqual('产品');
      expect(tags[1]).assertEqual('灵感');
      expect(tags[2]).assertEqual('英文Tag');
      expect(tags[3]).assertEqual('tag2024');
      expect(tags[4]).assertEqual('混合_标签');
    });

    it('全角井号当成同一个符号', 0, () => {
      const tags = parseTags('＃全角 也算');
      expect(tags.length).assertEqual(1);
      expect(tags[0]).assertEqual('全角');
    });

    it('emoji 终止标签', 0, () => {
      const tags = parseTags('#灵感🎉');
      expect(tags.length).assertEqual(1);
      expect(tags[0]).assertEqual('灵感');
    });

    it('反斜杠转义不算标签，双反斜杠算', 0, () => {
      expect(parseTags('\\#不是标签').length).assertEqual(0);
      expect(parseTags('\\\\#是标签').length).assertEqual(1);
    });

    it('连写井号只吃掉井号本身', 0, () => {
      const tags = parseTags('##想法');
      expect(tags.length).assertEqual(1);
      expect(tags[0]).assertEqual('想法');
    });

    it('大小写不敏感去重且保留首次写法', 0, () => {
      const tags = parseTags('#Idea #idea #IDEA');
      expect(tags.length).assertEqual(1);
      expect(tags[0]).assertEqual('Idea');
    });

    it('hasTags 与 parseTags 同口径', 0, () => {
      expect(hasTags('今天想到一件事')).assertFalse();
      expect(hasTags('今天想到 #一件事')).assertTrue();
    });

    it('stripTags 去掉标签只留正文', 0, () => {
      expect(stripTags('#产品 #灵感 试试 #英文Tag #tag2024 #混合_标签')).assertEqual('试试');
    });

    it('stripTags 收掉多余空白并 trim', 0, () => {
      expect(stripTags('前 #标签\n后')).assertEqual('前 后');
    });

    it('stripTags 保留被转义与无名的井号', 0, () => {
      // 被转义的 `#` 是普通字符，连同它前面的反斜杠一起原样保留（与列表里显示原文一致）
      expect(stripTags('\\#不是标签')).assertEqual('\\#不是标签');
      // `##想法`：第一个 `#` 后面没有名字、留下；第二个 `#想法` 是合法标签、被去掉
      expect(stripTags('##想法')).assertEqual('#');
    });

    it('stripTags 与 parseTags 同源：去掉的正是解析出来的那些', 0, () => {
      const content = '#产品 中间 #灵感 结尾';
      const tags = parseTags(content);
      expect(tags.length).assertEqual(2);
      const plain = stripTags(content);
      expect(plain).assertEqual('中间 结尾');
      // 正文里不应再出现任何已解析出来的标签名
      expect(plain.includes('#产品')).assertFalse();
      expect(plain.includes('#灵感')).assertFalse();
    });

    it('只有标签时 stripTags 返回空串', 0, () => {
      expect(stripTags('#产品 #灵感')).assertEqual('');
    });
  });
}
