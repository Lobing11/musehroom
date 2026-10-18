import byteSizeTest from './ByteSize.test';
import dateUtilTest from './DateUtil.test';
import heatmapTest from './Heatmap.test';
import legalTextTest from './LegalText.test';
import linkParserTest from './LinkParser.test';
import localUnitTest from './LocalUnit.test';
import tagParserTest from './TagParser.test';
import trashRetentionTest from './TrashRetention.test';

/**
 * 本地单测入口（`entry/src/test/`，跑在 PC 上，不需要真机）。
 *
 * 只放**纯逻辑**：`utils/` 下不碰系统的函数。需要数据库、preferences、ArkUI 的一律进
 * `entry/src/ohosTest/`（集成测试）。新增测试文件后记得在这里挂上，否则不会被跑到。
 */
export default function testsuite() {
  localUnitTest();
  tagParserTest();
  linkParserTest();
  dateUtilTest();
  heatmapTest();
  legalTextTest();
  trashRetentionTest();
  byteSizeTest();
}
