/**
 * 设计令牌（DesignTokens）—— 灵感菇主题机制
 * ============================================================================
 * 目标：用户切换主题色 / 深浅模式，**全应用立即变色，无需重启**。
 *
 * 整套机制的支点只有两条，**缺一不可**：
 *
 *     MuseColor（模块级**可变对象**）   负责「值」   —— 重建时去哪里取色
 *     AppStorage 的广播键               负责「通知」 —— 通知谁该重建
 *
 * 为什么非要两条线：
 *   1) ArkUI **不会**因为「普通对象的属性」变化而重建组件（`MuseColor.primary = x` 是静默的），
 *      所以颜色集中放在 `MuseColor` 里运行时改写 —— 它保证的是「重建发生时能取到新值」。
 *   2) 要触发重建，必须有**真正渲染出来的表达式**读到 AppStorage 订阅键，
 *      ArkUI 才会把节点标脏。所以颜色还必须广播出去。
 *
 * ----------------------------------------------------------------------------
 * 两条必须遵守的规则
 * ----------------------------------------------------------------------------
 * 规则 A｜**表达式里必须出现订阅变量**
 *     ✗ `.backgroundColor(musePageBackground(this.isDarkMode))`       切主题色不刷新
 *     ✓ `.backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))`
 *   `resolve*` 与 `muse*` 取值**逐档一致**，区别只在于前者把广播值作为入参，
 *   于是表达式里真正读到了订阅键。
 *
 * 规则 B｜**按值传进来的东西不会刷新**
 *   - `@Prop` 默认值 / 模块级常量只在构造时求值一次，需要在其生命周期内变化的值都不能用它承接。
 *   - `@Builder` 的**按值参数**（string / number / boolean）同样只求值一次：
 *       ✗ `@Builder Row(label: string, value: string)` + `this.Row('深浅', this.pageBackground)`
 *       ✓ `@Builder Row(item: RowItem)` + `this.Row({ label: '深浅', value: this.pageBackground })`
 *     传**对象字面量**才算「按引用传递」，参数里读到的订阅变量变化才会刷新 builder 内的 UI。
 *     这个坑的现场症状：同一屏上两处显示同一个状态，一处跟着变、另一处纹丝不动。
 *
 * ----------------------------------------------------------------------------
 * 例外（本文件里为什么不给文字色也加 resolve 版）
 * ----------------------------------------------------------------------------
 * `museTextPrimary(isDark)` 这类**只依赖深浅模式**的取色可以直接用纯函数：
 * `isDark` 本身就来自 `@StorageProp('isDarkMode')`，表达式里已经读到了订阅键。
 * 只有**依赖主题色**的取色才必须走 `resolve*` 版（主题色不是这里的入参）。
 */

/** 可变色板：整套机制的支点 */
export interface MuseColorPalette {
  /** 主题色（前景：文字、链接、选中态） */
  primary: string;
  /** 页面底色（由 applyAppTheme 按深浅 + 主题色派生写入） */
  background: string;
  /** 深色页面底色（applyAppTheme 尚未跑过时的兜底） */
  backgroundDark: string;
  /** 卡片/输入框表面色 */
  surface: string;
  textPrimary: string;
  textSecondary: string;
  border: string;
  danger: string;
  success: string;
}

/**
 * ⚠️ 必须是 `export const MuseColor = { ... }`（**可变对象**），
 * 不能写成 `const PRIMARY = '#2E9E6B'` 这种字符串常量 —— 后者无法在运行时改写。
 */
export const MuseColor: MuseColorPalette = {
  primary: '#2E9E6B',
  background: '#F4F6F4',
  backgroundDark: '#0E1210',
  surface: '#FFFFFF',
  textPrimary: '#1B211D',
  textSecondary: '#7C877F',
  border: '#1A2E9E6B',
  danger: '#D94838',
  success: '#00AA72'
};

/** 圆角刻度 */
export interface MuseRadiusScale {
  card: number;
  control: number;
  pill: number;
}

export const MuseRadius: MuseRadiusScale = {
  card: 18,
  control: 12,
  pill: 999
};

/** 间距刻度 */
export interface MuseSpaceScale {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export const MuseSpace: MuseSpaceScale = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};

// ============================================================================
// 1. 主题色：预设、默认值、存储键、广播键
// ============================================================================

export interface AccentPreset {
  key: string;
  label: string;
  value: string;
}

/**
 * 默认主题色 = 预设首位那一档。
 *
 * **「默认色」不要单列成第 6 个预设**：否则设置页会同时出现两个绿，
 * 用户分不清哪个是默认。「默认」是一个**语义**，不是一个颜色。
 */
export const DEFAULT_ACCENT_KEY: string = 'sprout';
export const DEFAULT_ACCENT_VALUE: string = '#2E9E6B';

/**
 * 预设里刻意留了**浅色**（琥珀黄）：
 * 它上面压白字基本看不清，所以凡是「主题色底 + 文字」的地方一律走
 * `onAccentColor()` 按亮度自动切黑/白字，新增浅色预设时不必再去改调用点。
 */
export const ACCENT_PRESETS: AccentPreset[] = [
  { key: 'sprout', label: '破土绿', value: '#2E9E6B' },
  { key: 'harmony', label: '鸿蒙蓝', value: '#0A59F7' },
  { key: 'spore', label: '孢子紫', value: '#7C5CD6' },
  { key: 'amber', label: '琥珀黄', value: '#E0A02E' },
  { key: 'clay', label: '陶土橙', value: '#C2703D' }
];

/** 主题色设置键：存预设 key 或字符串 'custom' */
export const ACCENT_KEY_STORAGE: string = 'accentKey';
/** 自定义主题色设置键：存 RRGGBB（不含 #） */
export const ACCENT_CUSTOM_STORAGE: string = 'accentCustom';

/** 主题色广播键：最终解析好的 `#RRGGBB`。所有 UI 依赖的是它，不是上面的持久化键 */
export const ACCENT_COLOR_KEY: string = 'accentColor';
/** 页面底色广播键：由 applyAppTheme 发布，页面订阅它 */
export const PAGE_BACKGROUND_KEY: string = 'pageBackground';
/** 卡片底色广播键 */
export const CARD_SURFACE_KEY: string = 'cardSurface';

/**
 * 深色模式偏好：`'system'` / `'light'` / `'dark'`。
 *
 * 教学要点｜**为什么是字符串三态而不是布尔开关：**
 *   布尔一旦被用户拨动过就永久生效，**再也没法回到「跟随系统」**
 *   （表现为「深色模式不跟随系统」，只能靠重置设置救回来）。
 *   三态让「跟随系统」始终是一个能选回来的状态。
 */
export const DARK_MODE_PREF_STORAGE: string = 'darkModePreference';
export const DARK_MODE_SYSTEM: string = 'system';
export const DARK_MODE_LIGHT: string = 'light';
export const DARK_MODE_DARK: string = 'dark';
/** 深色模式广播键（其它页面只读它） */
export const DARK_MODE_KEY: string = 'isDarkMode';

// ============================================================================
// 2. 校验与派生工具
// ============================================================================

/**
 * 校验自定义主题色输入：只接受 6 位十六进制（可带 #），大小写均可。
 * 返回规范化后的 `#RRGGBB`，**非法时返回空串**（调用方据此判定非法）。
 */
export function normalizeAccentHex(input: string): string {
  const raw = input.trim().replace('#', '');
  if (raw.length !== 6) {
    return '';
  }
  for (let i = 0; i < raw.length; i++) {
    const c = raw.charAt(i).toLowerCase();
    const isDigit = c >= '0' && c <= '9';
    const isHex = c >= 'a' && c <= 'f';
    if (!isDigit && !isHex) {
      return '';
    }
  }
  return `#${raw.toUpperCase()}`;
}

/**
 * 给 `#RRGGBB` 叠加透明度，返回 `#AARRGGBB`。`alpha` 取 0~1。
 *
 * 教学要点｜凡是「主题色的浅色底」**都用它，不要写字面量**：
 *   写死的半透明色（例如 `'#1A2E9E6B'`）切主题色后不会跟着变，选中态会露出旧色的底。
 */
export function withAlpha(color: string, alpha: number): string {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return color;
  }
  const clamped = Math.max(0, Math.min(1, alpha));
  const channel = Math.round(clamped * 255).toString(16).toUpperCase().padStart(2, '0');
  return `#${channel}${normalized.substring(1)}`;
}

/**
 * 两个 `#RRGGBB` 线性混合：ratio=0 取 base，ratio=1 取 tint。
 * 任一输入非法时原样返回 base，**绝不返回半成品颜色**。
 */
export function mixHex(base: string, tint: string, ratio: number): string {
  const a = normalizeAccentHex(base);
  const b = normalizeAccentHex(tint);
  if (a.length === 0 || b.length === 0) {
    return a.length > 0 ? a : base;
  }
  const clamped = Math.max(0, Math.min(1, ratio));
  let out = '#';
  for (let i = 1; i < 7; i += 2) {
    const ca = parseInt(a.substring(i, i + 2), 16);
    const cb = parseInt(b.substring(i, i + 2), 16);
    const mixed = Math.round(ca + (cb - ca) * clamped);
    out += mixed.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}

/**
 * 压在主题色上的前景色（黑或白），按 sRGB 加权亮度自动决定。
 *
 * 教学要点｜**不要让调用点各写各的**：主题色不都是深色，
 *   破土绿 0.51、琥珀黄 0.65 → 阈值取 0.62（偏保守，宁可早一点切黑字）。
 *
 * ⚠️ 调用时要把**订阅变量**传进来（`onAccentColor(this.accentOrPrimary())`）：
 *    直接写 `onAccentColor(MuseColor.primary)` 读的是模块级对象、登记不上依赖，切色后字色不变。
 */
export function onAccentColor(accentColor: string): string {
  const normalized = normalizeAccentHex(accentColor);
  if (normalized.length === 0) {
    return '#FFFFFF';
  }
  const r = parseInt(normalized.substring(1, 3), 16);
  const g = parseInt(normalized.substring(3, 5), 16);
  const b = parseInt(normalized.substring(5, 7), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.62 ? '#1A1A1A' : '#FFFFFF';
}

/** 是否是内置预设的 key（`'custom'` 不是预设，返回 false） */
export function isPresetAccentKey(key: string): boolean {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === key) {
      return true;
    }
  }
  return false;
}

/** 是否是内置预设主题色（按**颜色值**判定）—— 页面背景只跟随预设色 */
export function isPresetAccent(color: string): boolean {
  const normalized = normalizeAccentHex(color);
  if (normalized.length === 0) {
    return false;
  }
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (normalizeAccentHex(ACCENT_PRESETS[i].value) === normalized) {
      return true;
    }
  }
  return false;
}

/**
 * 按当前设置解析主题色。
 * 预设命中则用预设值；未命中（custom）时用自定义值，**自定义非法则回落默认主题色**。
 */
export function resolveAccentColor(accentKey: string, customHex: string): string {
  for (let i = 0; i < ACCENT_PRESETS.length; i++) {
    if (ACCENT_PRESETS[i].key === accentKey) {
      return ACCENT_PRESETS[i].value;
    }
  }
  const normalized = normalizeAccentHex(customHex);
  return normalized.length > 0 ? normalized : DEFAULT_ACCENT_VALUE;
}

/** 读 AppStorage 里的当前主题色；读不到时回落默认主题色 */
export function currentAccentColor(): string {
  try {
    const stored = AppStorage.get<string>(ACCENT_COLOR_KEY);
    if (stored !== undefined && normalizeAccentHex(stored).length > 0) {
      return normalizeAccentHex(stored);
    }
  } catch (err) {
    // AppStorage 不可用时走兜底
  }
  return MuseColor.primary;
}

// ============================================================================
// 3. 深浅模式取值函数族
// ============================================================================

/**
 * 深色模式下主题色向白色抬升的比例（越大越亮）。
 * 深色分支也**由主题色派生**，不能写死一个绿，否则浅色预设压在纯黑底上会看不清。
 */
const DARK_ACCENT_LIFT: number = 0.4;
/** 深色模式下主按钮底色向黑色压深的比例（配白字更清晰） */
const DARK_BUTTON_DEEPEN: number = 0.32;

function textPrimaryDark(): string {
  return '#E8EDE9';
}

function textSecondaryDark(): string {
  return '#9AA69E';
}

/**
 * 深色模式卡片 / 输入框表面色。
 *
 * ⚠️ **这个值不能凭感觉调**，原因在深色页面底色的构成上：
 *    底色是「`#0E1210` 混 12% 主题色」，破土绿下约 `#12231B` —— 绿色分量被抬得很高，
 *    而 sRGB 相对亮度里绿色占 71.5% 权重。原来的 `#1A211C` 绿分量（0x21）与底色（0x23）
 *    几乎相同，实测两者对比度只有 **1.003 : 1**，卡片轮廓其实**全靠那圈 1px 描边撑着**，
 *    描边一去掉就完全看不见了。
 *    改用 `#232B25` 后对比度 **1.13 : 1**，轮廓肉眼可辨；
 *    同时正文 **12.2 : 1**、次要文字 **5.8 : 1**、深色主题色 **7.3 : 1**，全部达到 WCAG AA。
 *    换句话说：深色下想加深卡片分离度，改这个值；想改底色绿味，动 PAGE_TINT_DARK。
 */
function surfaceDark(): string {
  return '#232B25';
}

function borderDark(): string {
  return '#33FFFFFF';
}

function dangerDark(): string {
  return '#FF8A7A';
}

function successDark(): string {
  return '#40DB94';
}

/** 正文/标题文字色（只依赖深浅模式，可直接用） */
export function museTextPrimary(isDark: boolean): string {
  return isDark ? textPrimaryDark() : MuseColor.textPrimary;
}

/** 次要/辅助文字色 */
export function museTextSecondary(isDark: boolean): string {
  return isDark ? textSecondaryDark() : MuseColor.textSecondary;
}

/** 危险/错误文字色 */
export function museDanger(isDark: boolean): string {
  return isDark ? dangerDark() : MuseColor.danger;
}

/** 成功/在线态颜色 */
export function museSuccess(isDark: boolean): string {
  return isDark ? successDark() : MuseColor.success;
}

/** 取一个合法的主题色入参：为空或非法时回落到当前 token */
function accentOrFallback(accentColor: string): string {
  const normalized = normalizeAccentHex(accentColor);
  return normalized.length > 0 ? normalized : MuseColor.primary;
}

/**
 * 主色的**订阅版**：把 `accentColor` 作为入参传进来，表达式里就真正读到了订阅键。
 *
 * ```ets
 * .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
 * ```
 */
export function resolvePrimaryColor(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  if (!isDark) {
    return accent;
  }
  return mixHex(accent, '#FFFFFF', DARK_ACCENT_LIFT);
}

/** 主按钮底色的**订阅版**（配 `onAccentColor()` 定的字色） */
export function resolvePrimaryButtonColor(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  if (!isDark) {
    return accent;
  }
  return mixHex(accent, '#000000', DARK_BUTTON_DEEPEN);
}

/** 卡片/芯片描边色的**订阅版**：浅色是「主题色的 10%」，深色是固定中性边框 */
export function resolveCardBorder(isDark: boolean, accentColor: string): string {
  if (isDark) {
    return borderDark();
  }
  return withAlpha(accentOrFallback(accentColor), 0.1);
}

/** 主题色的浅色底（选中态背景）的**订阅版** */
export function resolveAccentSoftBg(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  return isDark ? withAlpha(accent, 0.22) : withAlpha(accent, 0.12);
}

/**
 * 页面底色。**所有页面统一走这个函数，不要直接读 `MuseColor.background`。**
 *
 * 为什么要绕一层函数：ArkUI 的局部更新按**表达式**记录依赖，而 `MuseColor`
 * 是模块级对象 —— 读它的属性不会被登记。把 `pageBackground` 作为入参传进来，
 * 调用点才真正读到了订阅键。
 *
 * 两个参数都必须是调用方声明的订阅变量（`@StorageProp`）。
 */
export function resolvePageBackground(isDark: boolean, background: string): string {
  if (background.length > 0) {
    return background;
  }
  return isDark ? MuseColor.backgroundDark : MuseColor.background;
}

/** 卡片/输入框表面色的**订阅版** */
export function resolveCardSurface(isDark: boolean, surface: string): string {
  if (surface.length > 0) {
    return surface;
  }
  return isDark ? surfaceDark() : MuseColor.surface;
}

// ============================================================================
// 4. applyAppTheme / reloadAppTheme：把值写进 token 并广播
// ============================================================================

/** 浅色模式页面底色基数 */
const PAGE_BASE_LIGHT: string = '#F4F6F4';
/** 深色模式页面底色基数 */
const PAGE_BASE_DARK: string = '#0E1210';
/** 浅色背景混入主题色的比例（**刻意很淡**：直接铺主题色会压过正文） */
const PAGE_TINT_LIGHT: number = 0.08;
/** 深色背景混入主题色的比例 */
const PAGE_TINT_DARK: number = 0.12;

/**
 * 页面底色的**纯函数版**：给定深浅与主题色，直接算出「带主题色淡染的底色」。
 *
 * 为什么需要它：`resolvePageBackground` 读的是 `MuseColor.background`，那个值要靠
 * `applyAppTheme` 写进去，而 `applyAppTheme` 又依赖 `AppStorage` 广播——
 * **服务卡片跑在独立的 ArkUI 环境里，没有这套广播**（见 `widget/WidgetData.ets`）。
 * 卡片想跟 App 一个颜色，就得走这条不依赖任何全局状态的路径。
 *
 * 两边的算式必须一致，否则「卡片底色」和「App 页面底色」会出现肉眼可见的色差。
 */
export function resolveTintedBackground(isDark: boolean, accentColor: string): string {
  const accent = accentOrFallback(accentColor);
  return isDark
    ? mixHex(PAGE_BASE_DARK, accent, PAGE_TINT_DARK)
    : mixHex(PAGE_BASE_LIGHT, accent, PAGE_TINT_LIGHT);
}

/**
 * 应用主题：把深浅值写入可变 token，并发布广播键。
 *
 * ⚠️ **第二个参数一定要传当前主题色**，省略时背景染色会被重置回默认色。
 *    最容易漏的两处：切换深浅模式时、`onConfigurationUpdate`（系统深浅色变化）里。
 *    排查方式：切一下深色模式，若页面背景从「主题色淡染」变回固定灰，就是这里漏了。
 */
export function applyAppTheme(isDark: boolean, accentColor: string = ''): void {
  if (accentColor.length > 0) {
    const normalized = normalizeAccentHex(accentColor);
    if (normalized.length > 0) {
      MuseColor.primary = normalized;
    }
  }
  // 背景只跟随**预设**色：自定义色是用户随手输的，拿它铺满整页底色容易脏。
  const followed = accentColor.length > 0 && isPresetAccent(accentColor);
  const tintedLight = followed ? mixHex(PAGE_BASE_LIGHT, accentColor, PAGE_TINT_LIGHT) : PAGE_BASE_LIGHT;
  const tintedDark = followed ? mixHex(PAGE_BASE_DARK, accentColor, PAGE_TINT_DARK) : PAGE_BASE_DARK;

  MuseColor.background = isDark ? tintedDark : tintedLight;
  MuseColor.backgroundDark = tintedDark;
  MuseColor.surface = isDark ? surfaceDark() : '#FFFFFF';
  MuseColor.textPrimary = isDark ? textPrimaryDark() : '#1B211D';
  MuseColor.textSecondary = isDark ? textSecondaryDark() : '#7C877F';
  MuseColor.border = isDark ? borderDark() : withAlpha(MuseColor.primary, 0.1);

  // 发布广播键。页面**必须订阅它们**而不是直接读 MuseColor：
  // ArkUI 按表达式记录依赖，模块级对象的属性读取不会被登记。
  AppStorage.setOrCreate(PAGE_BACKGROUND_KEY, MuseColor.background);
  AppStorage.setOrCreate(CARD_SURFACE_KEY, MuseColor.surface);
}

/**
 * 按已保存的设置重建主题并广播。
 *
 * 这里为什么**不会死循环**：`@Watch` 回调里再次调用时算出的值相同，
 * `setOrCreate` 写入等值不会触发变更通知。
 */
export function reloadAppTheme(): void {
  let isDark = false;
  try {
    isDark = AppStorage.get<boolean>(DARK_MODE_KEY) === true;
  } catch (err) {
    isDark = false;
  }
  let accentKey = DEFAULT_ACCENT_KEY;
  let accentCustom = '';
  try {
    const storedKey = AppStorage.get<string>(ACCENT_KEY_STORAGE);
    if (storedKey !== undefined && storedKey.length > 0) {
      accentKey = storedKey;
    }
    const storedCustom = AppStorage.get<string>(ACCENT_CUSTOM_STORAGE);
    if (storedCustom !== undefined) {
      accentCustom = storedCustom;
    }
  } catch (err) {
    // 存储不可用时用默认预设
  }
  const resolved = resolveAccentColor(accentKey, accentCustom);
  applyAppTheme(isDark, resolved);
  AppStorage.setOrCreate(ACCENT_COLOR_KEY, resolved);
}
