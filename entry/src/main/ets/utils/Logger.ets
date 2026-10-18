import { hilog } from '@kit.PerformanceAnalysisKit';
import { LOG_DOMAIN, LOG_TAG } from './Constants';

/**
 * 日志统一封装。
 *
 * 为什么不让业务代码直接调 hilog：
 *   - 域与标签集中管理，改一次全局生效；
 *   - 统一用 `%{public}s` 占位：**写成 `%s` 的日志在真机上是看不到内容的**，
 *     这是 hilog 最常见的「日志打不出来」原因。
 *
 * ⚠️ 日志里不要拼用户正文（灵感内容是隐私），只打 id / 数量 / 耗时这类元信息。
 */
export class Logger {
  static debug(message: string): void {
    hilog.debug(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static info(message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }
}
