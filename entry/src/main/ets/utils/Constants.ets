/**
 * 全局常量。
 *
 * 约定：**表名/列名/存储键一律从这里取**，不要在业务代码里写字符串字面量 ——
 * 一处拼错就是一次静默的「读不到数据」，而且很难查。
 */

/** hilog 域（0x0000 ~ 0xFFFF，应用内自查用 0 即可） */
export const LOG_DOMAIN: number = 0x0000;

/** hilog 业务标签 */
export const LOG_TAG: string = 'Musehroom';

/** preferences 文件名：外观与设置（用户可改的少量配置） */
export const PREF_STORE_NAME: string = 'musehroom_settings';

/** 关系型数据库文件名（M1 接入） */
export const DB_NAME: string = 'musehroom.db';

/** 数据库版本号：**每次改表结构必须 +1**，迁移逻辑见 RdbHelper（M1） */
export const DB_VERSION: number = 2;

/** 时间轴每页条数 */
export const PAGE_SIZE: number = 50;

/** 单条灵感正文长度上限 */
export const MAX_CONTENT_LENGTH: number = 5000;

/** 删除后的可撤销窗口（毫秒） */
export const UNDO_WINDOW_MS: number = 5000;

/**
 * 「最近删除」的保留期（毫秒）。
 *
 * 为什么是 7 天：足够覆盖「过两天才想起来删错了」，又不至于让回收站变成第二个库；
 * 这是主流笔记应用（Apple Notes / Google Keep）共同的量级。
 */
export const TRASH_RETENTION_MS: number = 7 * 24 * 60 * 60 * 1000;

/** 搜索输入防抖（毫秒） */
export const SEARCH_DEBOUNCE_MS: number = 300;

/**
 * 相对时间（「5 分钟前」「2 小时前」）的走字间隔（毫秒）。
 *
 * 为什么需要它：卡片上的相对时间是**渲染那一刻**算出来的，页面不动它就永远停在
 * 「刚刚」——用户盯着看一分钟，数字纹丝不动，会怀疑应用是不是没在记时间。
 *
 * 为什么是 1 分钟而不是 1 秒：这个文案的最小刻度就是分钟，每秒重算纯属白烧电；
 * 而且 1 秒一次的重绘会让长列表在滚动时明显掉帧。
 */
export const TIME_TICK_MS: number = 60 * 1000;

/**
 * 每次启动最多自愈多少条灵感的标签关联。
 *
 * 上限是给「启动不能变慢」兜底的：自愈是逐条 `解析正文 + 写关联`，条数不设上限时
 * 一次异常（比如历史上大批写入失败）会让冷启动背上几千次写库。
 * 一次修 100 条已经远超真实场景，修不完的留到下次启动继续。
 */
export const TAG_REPAIR_LIMIT: number = 100;

/**
 * 「灵光再现」的 24 小时去重窗口（毫秒）。
 *
 * 为什么不是「不重复」：库小了必然抽空，而且完全随机本来就会出现连续两条一样，
 * 用户的感受是「这也叫随机？」。24 小时窗口是一次能兼顾「新鲜」与「抽得到」的折中。
 */
export const REVIEW_WINDOW_MS: number = 24 * 60 * 60 * 1000;

/** 展示历史在 preferences 里的键（存 'id:时间戳' 字符串数组） */
export const REVIEW_HISTORY_KEY: string = 'reviewHistory';

/** 展示历史最多留多少条（防止 preferences 无限长大；24 小时窗口通常只有几十条） */
export const REVIEW_HISTORY_LIMIT: number = 200;

/**
 * 「首次启动的隐私政策告知」是否已被用户**明示同意**（preferences 里存布尔）。
 *
 * 为什么只在用户「勾选空白复选框 + 点『同意并继续』」之后才落盘 true：
 * 应用市场审核要求首次启动必须显著提示隐私政策，并由用户自愿、明确地勾选同意。
 * 没同意也没拒绝（比如被系统打断）时下次启动必须再提示一次——否则「确实同意过」无法自证。
 */
export const PRIVACY_ACCEPTED_KEY: string = 'privacyAccepted';

/**
 * 窗口避让高度广播键（单位 vp）。
 *
 * 页面开了全屏布局（内容顶到状态栏下），必须拿这两个值做 padding 避让，
 * 否则首行文字会被状态栏压住。
 */
export const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';
export const NAVIGATION_BAR_HEIGHT_KEY: string = 'navigationBarHeight';

/**
 * 「从桌面直接进某个动作」的启动意图（M4 鸿蒙特色）。
 *
 * 谁写：`EntryAbility.onCreate` / `onNewWant` 解析 `Want.parameters` 后写进 AppStorage
 *       （桌面快捷方式、服务卡片的 postCardAction 都会带这个参数）。
 * 谁读：首页 `aboutToAppear` 与 `@Watch` 回调，**消费一次就把键清空**——
 *       否则用户从快捷方式进来一次之后，之后每次冷启动都会再自动弹一次面板。
 */
export const LAUNCH_ACTION_KEY: string = 'launchAction';
export const LAUNCH_ACTION_PARAM: string = 'action';
/** 直接聚焦输入框，准备记录 */
export const LAUNCH_ACTION_CAPTURE: string = 'capture';
/** 直接打开「灵光再现」随机回顾 */
export const LAUNCH_ACTION_REVIEW: string = 'review';
