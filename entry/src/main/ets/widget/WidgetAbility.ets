import { formBindingData, formInfo, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Configuration, Want } from '@kit.AbilityKit';
import { CardData, WidgetData } from './WidgetData';
import { CardRefresher } from './CardRefresher';
import { CardRegistry } from './CardRegistry';
import { Logger } from '../utils/Logger';

/**
 * 服务卡片（`FormExtensionAbility`）。
 *
 * 三种触发路径共用同一个 `refresh`：
 *   - `onAddForm`     —— 用户把卡片加到桌面（**必须同步返回**，见下面的注释）
 *   - `onUpdateForm`  —— 系统按 `updateDuration` 定时刷新（`form_config.json` 里 30 分钟一次）
 *   - `onFormEvent`   —— 卡片上「换一条」按钮发来的 message 事件
 *
 * 卡片数据由 `WidgetData.build` 统一产出（两张卡共用一份，见那里的说明）。
 */
export default class WidgetAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = WidgetAbility.formIdOf(want);
    Logger.info(`卡片创建：${formId}`);
    // 系统只在这里给一次 formId，之后要主动刷新时必须自己找回来
    CardRegistry.remember(this.context, formId);
    // 这里必须**同步**返回数据，而取数要查库（异步）：先交一张「颜色对、内容空」的卡
    // （见 WidgetData.empty），数据到了再用 formProvider.updateForm 推一次。
    // 反过来的写法（等 Promise）在这里不被允许。
    this.refresh(formId);
    return formBindingData.createFormBindingData(WidgetData.empty(this.context));
  }

  onUpdateForm(formId: string): void {
    Logger.info(`卡片定时刷新：${formId}`);
    CardRegistry.remember(this.context, formId);
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    Logger.info(`卡片事件：${message}`);
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {
    Logger.info(`卡片移除：${formId}`);
    CardRegistry.forget(this.context, formId);
  }

  /**
   * 系统配置变化（深浅色、语言、字号…）。
   *
   * **这里只是兜底**：卡片页自己用 `Environment.envProp('colorMode', …)` 订阅了系统深浅，
   * 系统一变色卡片就重算重画，不需要本进程活着（真机实测过：用户切系统深色时扩展进程早被回收，
   * 只靠这个回调根本收不到）。进程侥幸还在时顺势推一次，至少能让「相对时间」也刷新一遍。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    Logger.info(`系统配置变化：colorMode=${newConfig.colorMode}，重推卡片`);
    CardRefresher.refreshAll(this.context);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  /** 取数 → 推给卡片；两层 catch 都只记日志：卡片刷新失败不该让扩展进程崩掉 */
  private refresh(formId: string): void {
    if (formId.length === 0) {
      Logger.warn('卡片刷新缺少 formId');
      return;
    }
    WidgetData.build(this.context).then((data: CardData) => {
      const binding = formBindingData.createFormBindingData(data);
      formProvider.updateForm(formId, binding).then(() => {
        Logger.info(`卡片已刷新：${formId}`);
      }).catch((err: Error) => {
        Logger.warn(`卡片刷新失败：${err.message}`);
      });
    }).catch((err: Error) => {
      Logger.warn(`卡片取数失败：${err.message}`);
    });
  }

  /** `onAddForm` 的 want 里带 formId（`formInfo.FormParam.IDENTITY_KEY`） */
  private static formIdOf(want: Want): string {
    const params = want.parameters;
    if (params === undefined) {
      return '';
    }
    const raw = params[formInfo.FormParam.IDENTITY_KEY];
    if (typeof raw !== 'string') {
      return '';
    }
    return raw as string;
  }
}
