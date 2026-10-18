/**
 * `#标签` 解析。
 *
 * 这里是「什么算一个标签」的唯一定义：数据库里的 `tag` / `idea_tag` 只是它的索引，
 * 界面上的 chips 也从同一个函数来。因此它是纯函数、不碰存储，方便单测。
 *
 * 规则：
 *   - `#` 后接 1–24 个「标签字符」，遇到空白/标点/换行即终止
 *   - `#` 前面有**奇数个**反斜杠表示被转义（`\#不是标签`、`\\#是标签`）
 *   - 大小写不敏感去重，保留首次出现的写法（`#Idea` + `#idea` → 只留 `#Idea`）
 *
 * 为什么手写扫描而不用正则的 `\p{L}`：
 * `\p{...}` 需要 `u` 标志与完整的 Unicode 属性表，一旦运行时不支持就是
 * 「输入中文标签全部失效」这种致命且难查的故障。手写码点区间虽然长，
 * 但每个区间都是可读、可测、可增量补的。
 */

const TAG_PREFIX: string = '#';
/** 中文输入法下很容易打出的全角井号，当同一个符号处理，否则用户会以为解析坏了 */
const TAG_PREFIX_FULL_WIDTH: string = '＃';
const BACKSLASH: string = '\\';
const MAX_TAG_LENGTH: number = 24;

/**
 * 一条灵感上「标签有点多」的门槛。
 *
 * 只用来**提醒**，不参与解析——`parseTags` 照旧把正文里的标签全部收进来。
 * 硬砍会造出「正文里明明写着这个标签、却筛不出来」的假象：数据与索引必须一致，
 * 提醒一次的成本远低于不一致的代价。
 */
export const MAX_TAG_COUNT: number = 10;

function inRange(code: number, from: number, to: number): boolean {
  return code >= from && code <= to;
}

/**
 * 是否是「标签字符」。
 *
 * 注意刻意**不含**空白、标点与 emoji（emoji 走代理对，高位码点不落在任何区间里，
 * 因此天然终止标签）——`#灵感🎉` 解析出的是 `灵感`。
 */
function isTagChar(ch: string): boolean {
  if (ch.length === 0) {
    return false;
  }
  if (ch === '_' || ch === '-') {
    return true;
  }
  const code: number = ch.charCodeAt(0);
  // 0-9 / A-Z / a-z
  if (inRange(code, 0x30, 0x39) || inRange(code, 0x41, 0x5A) || inRange(code, 0x61, 0x7A)) {
    return true;
  }
  // 拉丁扩展（带音标的欧洲语言字母）
  if (inRange(code, 0xC0, 0x24F)) {
    return true;
  }
  // 希腊字母 / 西里尔字母
  if (inRange(code, 0x370, 0x3FF) || inRange(code, 0x400, 0x4FF)) {
    return true;
  }
  // 日文假名
  if (inRange(code, 0x3040, 0x30FF)) {
    return true;
  }
  // 中日韩统一表意文字（含扩展 A 与兼容区）
  if (inRange(code, 0x3400, 0x4DBF) || inRange(code, 0x4E00, 0x9FFF) || inRange(code, 0xF900, 0xFAFF)) {
    return true;
  }
  // 谚文
  if (inRange(code, 0xAC00, 0xD7A3)) {
    return true;
  }
  // 全角字母数字
  if (inRange(code, 0xFF10, 0xFF19) || inRange(code, 0xFF21, 0xFF3A) || inRange(code, 0xFF41, 0xFF5A)) {
    return true;
  }
  return false;
}

/** 这个 `#` 是否被反斜杠转义（前面连续反斜杠个数为奇数则被转义） */
function isEscaped(content: string, index: number): boolean {
  let backslashes = 0;
  let i = index - 1;
  while (i >= 0 && content.charAt(i) === BACKSLASH) {
    backslashes++;
    i--;
  }
  return backslashes % 2 === 1;
}

/**
 * 从正文里解析出标签名（保留原文大小写，按小写去重）。
 * 标签之外的文字一律忽略——本函数不负责去掉正文里的 `#`。
 */
export function parseTags(content: string): string[] {
  const tags: string[] = [];
  const seenKeys: string[] = [];
  let i = 0;
  while (i < content.length) {
    const ch = content.charAt(i);
    if (ch !== TAG_PREFIX && ch !== TAG_PREFIX_FULL_WIDTH) {
      i++;
      continue;
    }
    if (isEscaped(content, i)) {
      i++;
      continue;
    }
    let j = i + 1;
    let name = '';
    while (j < content.length && name.length < MAX_TAG_LENGTH && isTagChar(content.charAt(j))) {
      name += content.charAt(j);
      j++;
    }
    if (name.length > 0) {
      const key = name.toLowerCase();
      if (!seenKeys.includes(key)) {
        seenKeys.push(key);
        tags.push(name);
      }
    }
    // 有名字就跳过整个标签，没有名字（`#` 后面直接是空格）只跳过井号本身，
    // 否则 `##想法` 这种连写会被吃掉一个。
    i = name.length > 0 ? j : i + 1;
  }
  return tags;
}

/** 正文里是否含有标签——输入区用来决定要不要显示预览行 */
export function hasTags(content: string): boolean {
  return parseTags(content).length > 0;
}

/**
 * 去掉正文里的 `#标签` 记号，只留纯文字（连续空白收成一个空格，首尾去空）。
 *
 * **为什么要它**：服务卡片上标签要单独成行显示，正文里再带一遍 `#产品 #灵感` 就是同一句话
 * 写了两遍（M5 返工的第一批病灶之一）。这里刻意复用 `parseTags` 的同一套扫描规则，
 * 保证「卡片正文去掉的东西」和「卡片标签行显示的东西」永远一致。
 *
 * 与 `parseTags` 的差别只有一处：被转义（`\#不是标签`）或后面没有名字（`##想法` 的第一个 `#`）
 * 的井号是普通字符，**原样保留**。
 *
 * `collapseWhitespace` 默认 `true`（连续空白收成一个空格、首尾去空），服务卡片要的就是一行。
 * 应用内卡片传 `false`：正文是用户手写的，换行与首尾空格属于他的排版，折成一行会把
 * 「记下来的一段话」压成一坨；标签处补的那个空格仍然保留，避免「试试#标签」被削成「试试」。
 */
export function stripTags(content: string, collapseWhitespace: boolean = true): string {
  let out: string = '';
  let i = 0;
  while (i < content.length) {
    const ch = content.charAt(i);
    if (ch !== TAG_PREFIX && ch !== TAG_PREFIX_FULL_WIDTH) {
      out += ch;
      i++;
      continue;
    }
    if (isEscaped(content, i)) {
      out += ch;
      i++;
      continue;
    }
    let j = i + 1;
    let name = '';
    while (j < content.length && name.length < MAX_TAG_LENGTH && isTagChar(content.charAt(j))) {
      name += content.charAt(j);
      j++;
    }
    if (name.length === 0) {
      out += ch;
      i++;
      continue;
    }
    // 标签整个去掉，补一个空格，避免「试试#标签」被削成「试试」
    out += ' ';
    i = j;
  }
  return collapseWhitespace ? out.replace(/\s+/g, ' ').trim() : out;
}
