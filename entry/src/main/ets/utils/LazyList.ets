/**
 * 给 `LazyForEach` 用的数据源。
 *
 * ArkUI 的 `LazyForEach` 只认 `IDataSource` 这套「按索引取数 + 变更回调」协议，
 * 它不知道数组是什么，所以每处用到都要写一遍这段样板。抽成泛型类后，
 * M3 的标签云、回顾卡片都能直接复用。
 *
 * 关键点：**只提供 `setAll`（整表替换）**，不做增量通知。
 * 时间轴的行序列是「按日期分组摊平」出来的——插入一条灵感可能让分组头出现、消失、
 * 或改变条数，增量通知很容易与实际行号错位，出现「删了一条却消失了两条」这类鬼现象。
 * 整表替换配合 LazyForEach 的按需渲染，几百行规模下开销可以忽略；
 * 真到几千行再引入按 key 的增量更新。
 */
export class LazyList<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    // 重复注册会导致同一次变更触发多轮渲染，这里去重
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  isEmpty(): boolean {
    return this.items.length === 0;
  }

  /** 整表替换并通知重新加载 */
  setAll(next: T[]): void {
    this.items = next;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
