import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger } from '../utils/Logger';

/**
 * 系统备份/恢复扩展（云备份、换机克隆走的就是这里）。
 *
 * ============================================================================
 * 「数据库包不包进去」这件事由谁决定？
 * ============================================================================
 * 不是靠 `backup_config.json` 里列目录 —— 那个文件只有一个开关
 * `{"allowToBackupRestore": true}`（见 `entry/src/main/resources/base/profile/backup_config.json`），
 * 它的语义是「允许本应用参与系统备份/恢复」。真正的范围由**扩展有没有覆写** `onBackup` /
 * `onRestore` 决定：
 *   - 不覆写（或只打日志、不做过滤）→ 系统按默认策略整包备份应用沙箱，
 *     **`database/musehroom.db` 与 `preferences/` 都在里面**，这正是我们要的；
 *   - 覆写 `onBackupEx` / `onRestoreEx` 并用其中的 `includes`/`excludes` 做裁剪，
 *     才有「只备份某些目录」的说法。
 * 所以这里**故意不做任何裁剪**：灵感库是全应用的唯一主数据，
 * 少备份任何一个目录都等于「用户换机后丢数据」，而多加过滤规则只会增加这种风险。
 *
 * 两套防护的分工：
 *   - 系统备份：跟着系统账号走，用户无感（本文件负责）；
 *   - 「设置 → 导出为 JSON」：用户自己掌握的文件级备份，可以拷到任何地方（M4 已完成）。
 * 备份策略出问题时，`Logger` 的日志前缀是 `Musehroom`，用 `hdc shell hilog` 能直接捞到。
 */
export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    Logger.info('系统备份开始：整包（含 database 与 preferences）');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    // bundleVersion 是「备份来自哪个版本」，将来做数据迁移要靠它分支
    Logger.info(`系统恢复开始：备份版本 ${bundleVersion.name}(${bundleVersion.code})`);
    await Promise.resolve();
  }
}
