/**
 * UTF-8 字节数 —— 导出提示要报「文件多大」，用户看到的是文件管理器里的字节数。
 *
 * 曾经直接拿 `content.length` 当字节数：它是 UTF-16 码元数，一个汉字算 1，
 * 而 UTF-8 里汉字占 3 字节。于是一篇中文 Markdown 实际 205 B，提示却写 151 B。
 * JSON 里 ASCII 占多数，偏差小到看不出来，中文多的 Markdown 一眼就能看出不对。
 */
export function utf8ByteLength(text: string): number {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      // 代理对（emoji 等）在 UTF-16 里占两个码元，UTF-8 里共 4 字节；
      // 这里把高低位并成一次 4 字节，并跳过低位。
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}
