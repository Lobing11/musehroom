/**
 * 灵感的数据模型。
 *
 * 为什么用 `class` 而不是 `interface` 或对象字面量：
 * ArkTS 严格模式下禁用动态属性访问、也不鼓励用 `as` 硬转 JSON，用 class + 显式字段
 * 让「数据库行 → 领域对象」的映射在编译期就受检查，改字段时忘记改映射会直接报错。
 */

/**
 * 灵感来源。用「静态常量类」而不是 `enum`：
 * ArkTS 里把 number 赋给 enum 类型变量需要转换，而这里的值来自数据库 INTEGER 列，
 * 用 number 常量可以两边直接赋值，省掉一次转换和一类报错。
 * （M4 的卡片/快捷方式入口会写入非 MANUAL 的值）
 */
export class IdeaSource {
  /** 首页手动记录 */
  static readonly MANUAL: number = 0;
  /** 服务卡片一键记录（M4） */
  static readonly FORM: number = 1;
  /** 桌面快捷方式（M4） */
  static readonly SHORTCUT: number = 2;
  /** 从 JSON 备份导入（M4）。留下来源是为了出问题时能一眼看出「这条不是手打的」 */
  static readonly IMPORT: number = 3;
}

export class Idea {
  id: number = 0;
  content: string = '';
  /** 创建时间，毫秒时间戳 */
  createdAt: number = 0;
  /** 最后修改时间，毫秒时间戳（只改置顶不改内容时不刷新它） */
  updatedAt: number = 0;
  pinned: boolean = false;
  /** 软删除标记。查询一律带 `deleted = 0`，被删的行留着是为了 5 秒撤销和「最近删除」 */
  deleted: boolean = false;
  /**
   * 被删除的时间（毫秒）。0 表示未删除。
   *
   * 单独一列而不是复用 `updatedAt`：编辑和删除是两件事，复用会让「删除时间」
   * 随最后一次编辑漂移，7 天保留期就不准了。
   */
  deletedAt: number = 0;
  /** 取值见 `IdeaSource` */
  source: number = IdeaSource.MANUAL;

  /**
   * 内容被改过。
   * 留 1 秒容差：创建与入库在同一毫秒级操作里，两者本来就可能差几毫秒，
   * 不设容差会让刚记下的每一条都显示「已编辑」。
   */
  wasEdited(): boolean {
    return this.updatedAt - this.createdAt > 1000;
  }
}
