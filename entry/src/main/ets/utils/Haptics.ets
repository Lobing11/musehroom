import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

/**
 * 触感反馈。
 *
 * 为什么需要：这是一个「一两秒就要记完」的应用，用户常常不看屏幕——按下去有没有成，
 * 手上那一下比屏幕上的 toast 更快也更不打断思路。
 *
 * 三条纪律：
 * 1. **只用时长振动（`type: 'time'`）**，不用系统预置效果 id：效果 id 在不同机型上
 *    支持程度不一（要先 `isSupportEffect` 探测），而「短促的一下」本来就够用，
 *    不值得为它引入一张设备能力表。
 * 2. **时长必须短**（十几毫秒）：振动是确认，不是通知。超过 30ms 就从「咯噔一下」
 *    变成「嗡嗡作响」，在图书馆里会让人立刻想关掉。
 * 3. **失败了不打扰用户**：机型没有马达、权限缺失、系统限流都只记一条 debug 日志。
 *    触感是锦上添花，它挂掉绝不能让「保存灵感」这条主路径报错。
 *
 * 权限：`ohos.permission.VIBRATE`（normal 级、安装即授予、不涉及任何数据访问）。
 * 这是本应用唯一的权限声明，见 `module.json5`。
 */
export class Haptics {
  /** 轻触：切换、翻一条、撤销这类「按到了」 */
  private static readonly TAP_MS: number = 12;
  /** 确认：灵感真的写进库了，比轻触稍长一点，手指能分辨出区别 */
  private static readonly CONFIRM_MS: number = 18;

  /** 轻触一下（切换/翻页/撤销） */
  static tap(): void {
    Haptics.fire(Haptics.TAP_MS, '轻触');
  }

  /** 确认一下（保存成功、删除完成） */
  static confirm(): void {
    Haptics.fire(Haptics.CONFIRM_MS, '确认');
  }

  private static fire(duration: number, label: string): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: duration },
        { id: 0, usage: 'touch' }
      ).then(() => {
      }).catch((err: BusinessError) => {
        Logger.debug(`触感反馈（${label}）不可用：${err.code}`);
      });
    } catch (err) {
      const error = err as Error;
      Logger.debug(`触感反馈（${label}）调用异常：${error.message}`);
    }
  }
}
