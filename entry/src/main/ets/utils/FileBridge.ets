import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { Logger } from './Logger';

/**
 * 用户文件的选择与读写（M4 数据导出/导入的传输层）。
 *
 * 为什么走 `documentViewPicker` 而不是直接写应用沙箱：
 *  - 沙箱目录（`filesDir`）用户根本拿不到，导出到那里等于没导出；
 *  - picker 的界面由系统提供，**不需要申请任何权限**，与本项目
 *    「不申请 INTERNET 权限」的取舍一致（多一个权限就多一条上架审核理由）。
 *
 * 三个真机/SDK 里量出来的细节，别踩：
 *  ① `DocumentViewPicker` 的构造函数推荐传 `UIAbilityContext`（SDK 注释写明了）；
 *  ② `fs.readTextSync(filePath)` 的 filePath 只接受**应用沙箱路径**，
 *     picker 返回的是 `file://docs/...` 形式的 URI —— 直接喂给它读不到内容，
 *     必须先 `openSync(uri)` 拿到 fd，再用 `statSync(fd).size` + `readSync` + `buffer` 解码；
 *  ③ 用户在选择器里点「取消」时返回的是**空数组**，不是异常 ——
 *     这条路径必须当成正常结果处理，否则每次取消都会弹一个「失败」。
 */
export class FileBridge {
  /**
   * 让用户选一个保存位置并写入文本。
   *
   * @returns **系统实际生成的文件名**（从返回的 URI 末段取，含扩展名）；null 表示用户取消了（不是错误）
   *
   * 为什么返回真实文件名而不是成功/失败：真机上踩过一次 —— 我们把
   * `fileSuffixChoices` 写成不带点的 `'md'`，系统在「文件名去掉扩展名 + 拼上后缀」
   * 时就把点丢了，落盘变成 `musehroom-20261005-1701md`（既不是 .md 也不是 .json，
   * 别的 App 认不出来）。当时的状态行只报「我们请求的名字」，看起来一切正常，
   * 谁都没发现。**报系统真正给出的结果**，这个 bug 才藏不住。
   */
  static async saveText(context: common.UIAbilityContext, fileName: string, suffix: string,
    content: string): Promise<string | null> {
    const uri = await FileBridge.pickSaveUri(context, fileName, suffix);
    if (uri.length === 0) {
      Logger.info('导出已取消：用户没有选择保存位置');
      return null;
    }
    FileBridge.writeText(uri, content);
    const saved = FileBridge.fileNameOf(uri);
    Logger.info(`导出完成：${saved}（${content.length} 字符）｜位置 ${uri}`);
    return saved;
  }

  /** 从 document URI 里取出系统真正落盘的文件名（取不到就返回整段 URI，宁可难看也别撒谎） */
  static fileNameOf(uri: string): string {
    const slash = uri.lastIndexOf('/');
    const tail = slash >= 0 ? uri.substring(slash + 1) : uri;
    return tail.length > 0 ? tail : uri;
  }

  /**
   * 让用户挑一个文件并读出文本。
   *
   * @returns 文件内容；null 表示用户取消了
   */
  static async pickAndReadText(context: common.UIAbilityContext): Promise<string | null> {
    const uri = await FileBridge.pickOpenUri(context);
    if (uri.length === 0) {
      Logger.info('导入已取消：用户没有选择文件');
      return null;
    }
    const text = FileBridge.readTextFromUri(uri);
    Logger.info(`导入读取完成：${text.length} 字符`);
    return text;
  }

  /** 弹系统「另存为」，返回选中的 URI（空串表示取消） */
  private static async pickSaveUri(context: common.UIAbilityContext, fileName: string,
    suffix: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = [FileBridge.normalizeSuffix(suffix)];
    const viewPicker = new picker.DocumentViewPicker(context);
    try {
      const uris = await viewPicker.save(options);
      return uris.length > 0 ? uris[0] : '';
    } catch (err) {
      const error = err as Error;
      Logger.error(`打开保存对话框失败：${error.message}`);
      throw error;
    }
  }

  /**
   * 后缀必须带点（真机踩坑，M4 缺陷修复）。
   *
   * 系统的保存流程是「拿 `newFileNames` 去掉扩展名，再拼上用户选的后缀」，
   * 而且**它不会替你补那个点**：传 `'md'` 得到 `xxxmd`，传 `'.md'` 才得到 `xxx.md`。
   * 这里统一兜一层，免得调用处再踩（传 `'md'` / `'.md'` 都得到 `'.md'`）。
   */
  private static normalizeSuffix(suffix: string): string {
    const trimmed = suffix.trim();
    if (trimmed.length === 0) {
      return trimmed;
    }
    return trimmed.charAt(0) === '.' ? trimmed : `.${trimmed}`;
  }

  /**
   * 弹系统「打开文件」。
   *
   * **故意不加 `fileSuffixFilters`**（真实机型上量出来的）：
   * 加了过滤（无论写成 `'备份文件|.json'` 还是 `'.json'`）之后，
   * 选择器里连我们自己刚导出的 `.json` 都看不见了 —— `.json` 不在系统文件管理器的
   * MIME 表里，按后缀过滤等于把所有候选文件全部藏起来，用户会以为「导入功能坏了」。
   * 选择器的正确性交给内容校验：`ExportService.parseBundle` 会对着非备份文件给出
   * 「这不是灵感菇导出的 JSON 备份」这类明确提示，比一个空列表友好得多。
   */
  private static async pickOpenUri(context: common.UIAbilityContext): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const viewPicker = new picker.DocumentViewPicker(context);
    try {
      const uris = await viewPicker.select(options);
      return uris.length > 0 ? uris[0] : '';
    } catch (err) {
      const error = err as Error;
      Logger.error(`打开文件对话框失败：${error.message}`);
      throw error;
    }
  }

  /**
   * 写文本。
   * 用 `CREATE | TRUNC`：用户在「另存为」里挑了一个已存在的文件时，
   * 系统返回的是同一个 URI，不截断就会把新备份**接在旧内容后面**，
   * 得到一个既不是旧备份也不是新备份的坏文件。
   */
  private static writeText(uri: string, content: string): void {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
    } catch (err) {
      const error = err as Error;
      Logger.error(`写文件失败：${error.message}`);
      throw error;
    } finally {
      FileBridge.closeQuietly(file);
    }
  }

  /**
   * 读文本（见类注释第 ② 条：不能直接用 `readTextSync` 读 picker 的 URI）。
   * 对沙箱路径同样有效 —— 自检脚本就用它做文件往返验证。
   */
  static readTextFromUri(uri: string): string {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const size = fileIo.statSync(file.fd).size;
      const arrayBuffer = new ArrayBuffer(size);
      const readLength = fileIo.readSync(file.fd, arrayBuffer);
      return buffer.from(arrayBuffer, 0, readLength).toString('utf-8');
    } catch (err) {
      const error = err as Error;
      Logger.error(`读文件失败：${error.message}`);
      throw error;
    } finally {
      FileBridge.closeQuietly(file);
    }
  }

  /**
   * 关文件句柄，失败只记警告。
   * 与 DAO 里「异常必须外抛」的纪律不冲突：句柄关不掉已经没有补救手段，
   * 而此时如果正文已经写完，把异常抛出去只会让用户看到「导出失败」——
   * 一个明明躺在文件管理器里的成功文件。
   */
  private static closeQuietly(file: fileIo.File | null): void {
    if (file === null) {
      return;
    }
    try {
      fileIo.closeSync(file);
    } catch (err) {
      const error = err as Error;
      Logger.warn(`关闭文件失败：${error.message}`);
    }
  }
}
