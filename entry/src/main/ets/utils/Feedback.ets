import { UIContext } from '@kit.ArkUI';
import { Logger } from './Logger';

/** 轻提示停留时长：够看清一句话，又不至于挡住下面的列表 */
const TOAST_DURATION_MS: number = 1800;

/**
 * 轻提示。
 *
 * 走 `UIContext.getPromptAction()` 而不是 `promptAction.showToast()` 全局函数：
 * 后者在多窗口/多实例下不知道该弹在哪个窗口，新版本已把它标成不推荐用法。
 * 传 UIContext 也能让调用方（页面）把它当成一次普通的界面操作。
 *
 * 全部包 try/catch：提示失败绝对不能反过来把主流程（比如已经落库的保存）搞崩。
 */
export function toast(ui: UIContext, message: string): void {
  try {
    ui.getPromptAction().showToast({
      message: message,
      duration: TOAST_DURATION_MS
    });
  } catch (err) {
    Logger.warn(`轻提示弹出失败，已忽略：${message}`);
  }
}
