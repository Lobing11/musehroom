import { common } from '@kit.AbilityKit';

/**
 * Ability 上下文的持有者。
 *
 * 为什么不让页面自己去取：页面里能拿到上下文的途径（`getUIContext().getHostContext()`、
 * 已废弃的 `getContext(this)`）都有**时机**问题——`aboutToAppear` 里 UIContext 是否已经绑好
 * 属于实现细节，赌错了就是启动即白屏。
 *
 * `EntryAbility.onCreate` 里的 `this.context` 是确定可用的，由它显式交给页面最稳。
 * 这里只存一个引用、不做任何包装，页面拿到后自行决定是否用它。
 */
let abilityContext: common.UIAbilityContext | null = null;

export function setAppContext(context: common.UIAbilityContext): void {
  abilityContext = context;
}

export function getAppContext(): common.UIAbilityContext | null {
  return abilityContext;
}
