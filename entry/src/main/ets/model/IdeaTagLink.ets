/**
 * 「灵感 ↔ 标签名」的一条关联，只在全量导出时用到。
 *
 * 为什么不直接读 `idea_tag`：那张表里存的是 `tag_id`，要还原成人看得懂的标签名
 * 还得再 JOIN 一次 `tag`。导出是一次性的整库动作，与其在图里绕，不如把这个「导出要的行形状」
 * 单独定成一个模型，DAO 里那条 JOIN 也就能一眼看出是给谁用的。
 */
export class IdeaTagLink {
  ideaId: number = 0;
  /** 标签名（不带 `#`，与 `Tag.name` 同一口径） */
  tagName: string = '';
}
