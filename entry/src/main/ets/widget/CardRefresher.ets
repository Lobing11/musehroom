import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { CardData, WidgetData } from './WidgetData';
import { CardRegistry } from './CardRegistry';
import { Logger } from '../utils/Logger';

/**
 * 主动把**所有**已登记的卡片重画一遍。
 *
 * 触发点：
 *   - 用户在设置里换了深浅偏好或主题色（`SettingsSheet` 侧调用）—— 卡片进程读不到 App 的
 *     `AppStorage`，也拿不到「用户强制了浅色/深色」这件事，只能由 App 侧推过去；
 *   - 系统深浅色变了（`WidgetAbility.onConfigurationUpdate`）—— **这条只是兜底**：
 *     卡片页自己用 `Environment` 订阅了系统 `colorMode`，系统一变色它就重算重画，
 *     不需要任何进程活着。扩展进程万一还在，顺势推一次也无害。
 *
 * 取数只做一次（两张卡共用一份 `CardData`，见 `WidgetData` 的说明），再逐个 formId 推。
 */
export class CardRefresher {
  static refreshAll(context: common.Context): void {
    const ids = CardRegistry.list(context);
    if (ids.length === 0) {
      Logger.info('卡片刷新：名单为空，跳过');
      return;
    }
    Logger.info(`卡片刷新：${ids.length} 张`);
    WidgetData.build(context).then((data: CardData) => {
      const binding = formBindingData.createFormBindingData(data);
      for (let i = 0; i < ids.length; i++) {
        const formId = ids[i];
        formProvider.updateForm(formId, binding).then(() => {
          Logger.info(`卡片已刷新：${formId}`);
        }).catch((err: Error) => {
          // 卡片很可能已经被用户删了：顺手从名单里摘掉，别让名单越攒越长、每次都白刷
          Logger.warn(`卡片刷新失败（可能已移除）：${formId} ${err.message}`);
          CardRegistry.forget(context, formId);
        });
      }
    }).catch((err: Error) => {
      Logger.warn(`卡片取数失败：${err.message}`);
    });
  }
}
