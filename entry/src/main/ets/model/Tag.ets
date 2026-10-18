/**
 * 标签（带使用频次）。
 *
 * `count` 是「未删除灵感」里的出现次数，M2 的筛选条用它排序，
 * M3 的标签云还会用同一个数字映射字号 —— 口径只在这里定义一次。
 */
export class Tag {
  id: number = 0;
  name: string = '';
  count: number = 0;
}
