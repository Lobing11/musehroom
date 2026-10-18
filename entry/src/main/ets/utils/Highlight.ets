/**
 * 搜索命中切分：把一段正文切成「命中 / 未命中」交替的片段，
 * 交给 `Text` + `Span` 渲染成高亮文本（ArkUI 的 `Text` 只能靠 `Span` 子组件改局部样式）。
 *
 * 为什么要有段数上限：搜索词只有一个字时（很常见），一段 5000 字的正文会切出上千段，
 * 每段都是一个 `Span` 组件 —— 这比查询本身贵得多。超过上限就把剩下的原样收尾，
 * 宁可少高亮几处，也不能让列表滚动掉帧。
 */

const MAX_SEGMENTS: number = 40;

export class TextSegment {
  text: string;
  matched: boolean;

  constructor(text: string, matched: boolean) {
    this.text = text;
    this.matched = matched;
  }
}

/**
 * 按关键词切分，大小写不敏感（英文搜索不至于要求用户记住大小写）。
 * 关键词为空或没命中时返回单段未命中，调用方可以无条件按「多段」渲染。
 */
export function splitHighlight(text: string, keyword: string): TextSegment[] {
  const segments: TextSegment[] = [];
  const needle: string = keyword.trim().toLowerCase();
  if (needle.length === 0 || text.length === 0) {
    segments.push(new TextSegment(text, false));
    return segments;
  }
  const haystack: string = text.toLowerCase();
  let from = 0;
  let at = haystack.indexOf(needle, from);
  if (at < 0) {
    segments.push(new TextSegment(text, false));
    return segments;
  }
  while (at >= 0 && segments.length < MAX_SEGMENTS) {
    if (at > from) {
      segments.push(new TextSegment(text.substring(from, at), false));
    }
    segments.push(new TextSegment(text.substring(at, at + needle.length), true));
    from = at + needle.length;
    if (from >= text.length) {
      break;
    }
    at = haystack.indexOf(needle, from);
  }
  if (from < text.length) {
    segments.push(new TextSegment(text.substring(from), false));
  }
  return segments;
}
