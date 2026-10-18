import { stripTags } from './TagParser';

/**
 * 正文里的链接识别。
 *
 * 这里是「什么算一个链接」的唯一定义，和 `TagParser` 一样是纯函数、不碰系统，方便单测。
 * 之所以要它：灵感里贴网址是常态（记一条「看到个好库」基本就等于贴个地址），
 * 而 `Text` 只能靠 `Span` 改局部样式，所以先把正文切成「链接 / 普通文字」交替的片段。
 *
 * 只认 `http://` 与 `https://` 开头的显式链接：
 *   - **不猜** `www.` 与裸域名。`灵感.md`、`3.5`、`笔记.txt`、`他说的.com` 这类文本会被大面积误判，
 *     宁可少识别几个，也不能把普通文字染成链接色——那是「界面骗人」，比不识别更糟。
 *   - 链接在空白、标点、汉字、emoji 处终止（见 `isLinkStop`）。
 *   - 紧跟其后的 ASCII 收尾标点会被吐回去：`见 https://a.com。` 不会把句号吃进链接，
 *     `(https://a.com)` 也不会把右括号吃进去。
 */

/** 段数上限：与 `Highlight` 同一理由——一段正文里链接再多，也不该切出上百个 Span 拖慢列表 */
const MAX_SEGMENTS: number = 40;

/** 只有这两种 scheme 算链接（大小写不敏感，`HTTPS://` 也认） */
const SCHEMES: string[] = ['https://', 'http://'];

/** 链接末尾要吐回去的 ASCII 标点：中文写作习惯会把句号逗号右括号直接跟在网址后面 */
const TRAILING_PUNCTUATION: string = '.,;:!?)]}\'"';

/** 终止链接的标点（U+3002 这类中文标点码点低于 0x4E00，不能只靠码点判断） */
const STOP_PUNCTUATION: string = '。、，；：！？…—‘’“”（）【】《》〈〉「」『』';

/**
 * 一段正文按链接切出来的片段。
 *
 * 用 class 而不是 interface：与 `Highlight.TextSegment` 保持同一种写法，
 * `ForEach` 遍历时也便于按值读取（ArkTS 的对象字面量类型推断在数组元素上容易出岔子）。
 */
export class LinkSegment {
  text: string;
  isLink: boolean;

  constructor(text: string, isLink: boolean) {
    this.text = text;
    this.isLink = isLink;
  }
}

/**
 * 是否是「链接终止字符」。
 *
 * 码点 ≥ 0x4E00 一律终止：那里开始是汉字、全角标点、以及 emoji（emoji 走代理对，高位码点更高），
 * 链接里出现这些字符的可能性远低于「链接后面紧跟着一句中文」。
 * 代价是中文域名（`https://中文.中国`）不会被完整识别——这属于已知取舍，写在这里免得后人当成 bug。
 */
function isLinkStop(ch: string): boolean {
  const code: number = ch.charCodeAt(0);
  if (code <= 0x20) {
    return true;
  }
  if (code >= 0x4E00) {
    return true;
  }
  return STOP_PUNCTUATION.indexOf(ch) >= 0 || ch === '<' || ch === '>'
    || ch === '"' || ch === '\'';
}

/** 从 `from` 开始找最早的 scheme 出现位置，找不到返回 -1 */
function findScheme(lower: string, from: number): number {
  let best: number = -1;
  for (let i = 0; i < SCHEMES.length; i++) {
    const at: number = lower.indexOf(SCHEMES[i], from);
    if (at >= 0 && (best < 0 || at < best)) {
      best = at;
    }
  }
  return best;
}

/** 位置 `start` 上是不是某个 scheme，是则返回它的长度（否则 0） */
function schemeLengthAt(lower: string, start: number): number {
  for (let i = 0; i < SCHEMES.length; i++) {
    const scheme: string = SCHEMES[i];
    if (lower.substring(start, start + scheme.length) === scheme) {
      return scheme.length;
    }
  }
  return 0;
}

/**
 * 从 `start` 找链接的结束位置（不含）。
 * scheme 后面什么都没跟（`https://` 就结束了）时返回 `start`，表示这里不算链接。
 */
function findLinkEnd(content: string, start: number): number {
  const schemeLength: number = schemeLengthAt(content.toLowerCase(), start);
  if (schemeLength === 0) {
    return start;
  }
  let i: number = start;
  while (i < content.length && !isLinkStop(content.charAt(i))) {
    i++;
  }
  let end: number = i;
  while (end > start + schemeLength && TRAILING_PUNCTUATION.indexOf(content.charAt(end - 1)) >= 0) {
    end--;
  }
  return end > start + schemeLength ? end : start;
}

/**
 * 按链接切分正文，返回的片段首尾相接正好等于原文。
 * 没有链接时返回单段普通文字，调用方可以无条件按「多段」渲染。
 */
export function splitLinks(content: string): LinkSegment[] {
  const segments: LinkSegment[] = [];
  if (content.length === 0) {
    segments.push(new LinkSegment('', false));
    return segments;
  }
  const lower: string = content.toLowerCase();
  // 还没落段的普通文字从这里开始：`https://` 后面空无一物时只是跳过它继续找，
  // 那截字符必须留在普通片段里，不能因为「不是链接」就凭空消失
  let plainStart: number = 0;
  let cursor: number = 0;
  while (cursor < content.length && segments.length < MAX_SEGMENTS) {
    const start: number = findScheme(lower, cursor);
    if (start < 0) {
      break;
    }
    const end: number = findLinkEnd(content, start);
    if (end <= start) {
      cursor = start + schemeLengthAt(lower, start);
      continue;
    }
    if (start > plainStart) {
      segments.push(new LinkSegment(content.substring(plainStart, start), false));
    }
    segments.push(new LinkSegment(content.substring(start, end), true));
    plainStart = end;
    cursor = end;
  }
  if (plainStart < content.length) {
    segments.push(new LinkSegment(content.substring(plainStart), false));
  }
  if (segments.length === 0) {
    segments.push(new LinkSegment(content, false));
  }
  return segments;
}

/**
 * 卡片正文要渲染的片段：链接切分之后再对**非链接片段**做去标签。
 *
 * 顺序不能反：先 `stripTags` 会把 `https://a.com/p#产品` 里的 `#产品` 当标签删掉，
 * 链接就此断成两截。先切链接则网址整体受保护。
 *
 * 空白处理：**不折成一行**（`stripTags(text, false)`）——正文是用户手写的，换行属于他的排版；
 * 只把连续的半角空格/制表符收成一个（削标签时会补空格出来），并削掉正文两端的空白。
 * 被削空（整段就是标签）的片段丢掉，避免渲染出空 Span。
 */
export function buildBodySegments(content: string): LinkSegment[] {
  const raw: LinkSegment[] = splitLinks(content);
  const out: LinkSegment[] = [];
  for (let i = 0; i < raw.length; i++) {
    const segment: LinkSegment = raw[i];
    if (segment.isLink) {
      out.push(segment);
      continue;
    }
    const text: string = stripTags(segment.text, false).replace(/[ \t]+/g, ' ');
    if (text.length > 0) {
      out.push(new LinkSegment(text, false));
    }
  }
  // 正文两端不该有空白：`今晚想这个 #灵感` 削掉标签后会多出一个尾空格
  if (out.length > 0 && !out[0].isLink) {
    out[0] = new LinkSegment(out[0].text.replace(/^\s+/, ''), false);
  }
  if (out.length > 0 && !out[out.length - 1].isLink) {
    const lastIndex: number = out.length - 1;
    out[lastIndex] = new LinkSegment(out[lastIndex].text.replace(/\s+$/, ''), false);
  }
  const kept: LinkSegment[] = [];
  for (let i = 0; i < out.length; i++) {
    if (out[i].text.length > 0) {
      kept.push(out[i]);
    }
  }
  if (kept.length === 0) {
    kept.push(new LinkSegment('', false));
  }
  return kept;
}

/** 正文去掉标签记号后的纯文字（读屏文案、截断测量用） */
export function bodyText(content: string): string {
  const segments: LinkSegment[] = buildBodySegments(content);
  let out: string = '';
  for (let i = 0; i < segments.length; i++) {
    out += segments[i].text;
  }
  return out;
}
