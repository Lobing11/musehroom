import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { Logger } from './Logger';
import { toast } from './Feedback';

/**
 * 用系统浏览器打开一个外部链接。
 *
 * 为什么是隐式 Want 而不是 Web 组件：灵感菇**没有网络权限**（隐私政策与上架材料都这么写），
 * 「打开链接」必须发生在别的应用里；这里只是把 URL 递出去，本应用一个字节都不请求。
 *
 * 为什么收进 utils：隐私政策面板里的「在浏览器打开」与卡片正文里的链接是同一件事，
 * 各写一遍迟早会分叉（换 scheme、漏 entities、异常没兜住）。
 *
 * 失败一定要出声：设备上没装浏览器时 `startAbility` 会失败，`failureHint` 要说清「还能怎么办」，
 * 绝不能让用户以为「点了没反应」。
 */
export function openExternalUrl(ui: UIContext, url: string, failureHint: string): void {
  try {
    const ctx = ui.getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    ctx.startAbility(want).then(() => {
      Logger.info(`已交给系统浏览器打开：${url}`);
    }).catch((err: BusinessError) => {
      Logger.warn(`打开浏览器失败：${err.message}`);
      toast(ui, failureHint);
    });
  } catch (err) {
    const error = err as Error;
    Logger.warn(`打开浏览器异常：${error.message}`);
    toast(ui, failureHint);
  }
}
