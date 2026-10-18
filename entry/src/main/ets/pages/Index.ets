import { common } from '@kit.AbilityKit';
import { getAppContext } from '../utils/AppContext';
import {
  LAUNCH_ACTION_CAPTURE,
  LAUNCH_ACTION_KEY,
  LAUNCH_ACTION_REVIEW,
  NAVIGATION_BAR_HEIGHT_KEY,
  PRIVACY_ACCEPTED_KEY,
  STATUS_BAR_HEIGHT_KEY,
  TIME_TICK_MS,
  UNDO_WINDOW_MS
} from '../utils/Constants';
import { Logger } from '../utils/Logger';
import { toast } from '../utils/Feedback';
import { Haptics } from '../utils/Haptics';
import { LazyList } from '../utils/LazyList';
import { IdeaRepository } from '../repository/IdeaRepository';
import { getIdeaRepository } from '../repository/RdbIdeaRepository';
import { Idea } from '../model/Idea';
import { HeatCell } from '../model/StatsData';
import { TimelineRow, TimelineRowKind, TimelineViewModel } from '../viewmodels/TimelineViewModel';
import { StatsViewModel } from '../viewmodels/StatsViewModel';
import { ReviewService } from '../service/ReviewService';
import { Tag } from '../model/Tag';
import { MAX_TAG_COUNT, parseTags } from '../utils/TagParser';
import { CaptureBar } from '../views/CaptureBar';
import { DayHeader } from '../views/DayHeader';
import { IdeaCard } from '../views/IdeaCard';
import { IdeaDetailSheet } from '../views/IdeaDetailSheet';
import { SettingsSheet } from '../views/SettingsSheet';
import { PrivacySheet, PRIVACY_MODE_FULL, PRIVACY_MODE_ONBOARDING } from '../views/PrivacySheet';
import { TrashSheet } from '../views/TrashSheet';
import { AppSettingsStore } from '../storage/AppSettingsStore';
import { ExportService } from '../service/ExportService';
import { FileBridge } from '../utils/FileBridge';
import { utf8ByteLength } from '../utils/ByteSize';
import { SearchBar } from '../views/SearchBar';
import { TagFilterBar } from '../views/TagFilterBar';
import { StatsSheet } from '../views/StatsSheet';
import { ReviewCard } from '../views/ReviewCard';
import { formatDayLabel } from '../utils/DateUtil';
import {
  ACCENT_COLOR_KEY,
  CARD_SURFACE_KEY,
  DARK_MODE_KEY,
  DEFAULT_ACCENT_VALUE,
  MuseRadius,
  MuseSpace,
  PAGE_BACKGROUND_KEY,
  museDanger,
  museTextPrimary,
  museTextSecondary,
  onAccentColor,
  resolveCardBorder,
  resolveCardSurface,
  resolvePageBackground,
  resolvePrimaryButtonColor,
  resolvePrimaryColor
} from '../utils/DesignTokens';

/**
 * 首页 = 时间轴。
 *
 * 这一屏要同时容纳「记」和「翻」两件事，所以布局是固定的三段：
 *   顶部 —— 品牌与总数（尽量矮）；
 *   中间 —— 时间轴（唯一可滚动的部分）；
 *   底部 —— 常驻记录栏（拇指区，任何时刻都能开始输入）。
 *
 * 状态分工：本组件只持有**渲染用的 @State**（加载中/还有更多/总数/错误），
 * 数据本身在 `TimelineViewModel` 里；两者通过 `vm.onChange` 单向同步。
 * 这样视图模型不依赖 ArkUI 装饰器，将来可以单独做单元测试。
 */
@Entry
@Component
struct Index {
  // ---- 主题（全部是订阅变量，取色表达式里必须用到它们，见 DesignTokens 规则 A）----
  @StorageProp(PAGE_BACKGROUND_KEY) pageBackground: string = '';
  @StorageProp(CARD_SURFACE_KEY) cardSurface: string = '';
  @StorageProp(ACCENT_COLOR_KEY) accentColor: string = '';
  @StorageProp(DARK_MODE_KEY) isDarkMode: boolean = false;
  @StorageProp(STATUS_BAR_HEIGHT_KEY) statusBarHeight: number = 0;
  @StorageProp(NAVIGATION_BAR_HEIGHT_KEY) navigationBarHeight: number = 0;
  /**
   * 启动意图（桌面快捷方式「记一条灵感」/「灵光再现」带进来的动作）。
   *
   * 为什么既要 `aboutToAppear` 读一次、又要 `@Watch`：应用热启动时页面还活着、
   * `aboutToAppear` 不会再跑，只有 AppStorage 的值变化能叫醒页面
   * （`EntryAbility.onNewWant` 写完值 → 这里被调到）。
   */
  @StorageProp(LAUNCH_ACTION_KEY) @Watch('onLaunchActionChanged') launchAction: string = '';

  // ---- 时间轴状态（由 ViewModel 同步过来）----
  @State private loading: boolean = true;
  @State private hasMore: boolean = true;
  @State private totalCount: number = 0;
  @State private errorText: string = '';

  // ---- 筛选状态。也是从 ViewModel 抄过来的：ViewModel 不是可观察对象，@State 才能驱动重绘 ----
  @State private searchOpen: boolean = false;
  @State private appliedKeyword: string = '';
  @State private filterActive: boolean = false;
  @State private selectedTagCount: number = 0;
  /**
   * 标签清单的**响应式副本**。
   *
   * 必须抄成 @State，不能让 render 路径直接问 ViewModel 要：标签是异步读出来的，
   * 首帧那一刻它还是空的，而 `showTagBar()` 又决定「筛选条这个元素要不要创建」——
   * 判断里没读到任何可观察变量时，ArkUI 不会重跑这个分支，
   * 标签后来到了也永远不显示（真机验收时就是这么发现的：卡片上 chips 都出来了，筛选条却不见）。
   */
  @State private tagItems: Tag[] = [];
  /** 每次筛选条件变化都自增，专门用来当重绘指纹（见 tagSignature） */
  @State private tagVersion: number = 0;

  // ---- 删除撤销 ----
  @State private undoVisible: boolean = false;

  // ---- 详情半模态。字段摊平成 @State 而不是存一个 Idea 对象：渲染路径上没有可空对象更省心 ----
  @State private detailVisible: boolean = false;
  @State private selectedId: number = 0;
  @State private selectedContent: string = '';
  @State private selectedCreatedAt: number = 0;
  @State private selectedUpdatedAt: number = 0;
  @State private selectedPinned: boolean = false;

  @State private settingsVisible: boolean = false;

  // ---- 多选（长按进入）：页面持有勾选状态，卡片只是开关 ----
  @State private selecting: boolean = false;
  @State private selectedIds: number[] = [];
  /** 多选导出进行中：底部按钮禁用，避免连点弹出两个系统文件选择器 */
  @State private selectionBusy: boolean = false;

  // ---- 最近删除（回收站）：与统计面板同一策略，打开时才拉数据 ----
  @State private trashVisible: boolean = false;
  @State private trashLoading: boolean = false;
  @State private trashError: string = '';
  @State private trashItems: Idea[] = [];

  // ---- 隐私政策半模态：首启告知（onboarding）与完整条款（full）共用一个组件，只切 mode ----
  @State private privacyVisible: boolean = false;
  @State private privacyMode: string = PRIVACY_MODE_ONBOARDING;
  /**
   * 首启同意闸门是否还开着（true = 用户尚未做出同意/拒绝的选择）。
   *
   * 它同时决定完整条款页顶部是否显示返回：从告知面板进来的必须能**回到告知面板**，
   * 而不是把整张半模态关掉（1.0.0 审核问题 2 的「返回后弹窗消失」）。
   */
  @State private privacyGate: boolean = false;
  /** 导出/导入进行中：按钮禁用 + 面板显示「处理中…」 */
  @State private dataBusy: boolean = false;
  /** 上一次数据操作的结果，直接显示在设置面板里（导出 N 条 / 新增 N 条 / 失败原因） */
  @State private dataStatus: string = '';

  // ---- M3 统计面板（热力图 + 标签云）：打开时才拉数据，不进冷启动路径 ----
  @State private statsVisible: boolean = false;
  @State private statsLoading: boolean = false;
  @State private statsError: string = '';
  @State private statsSummary: string = '';
  @State private statsCells: HeatCell[] = [];
  @State private statsMaxCount: number = 0;
  @State private statsTags: Tag[] = [];
  @State private statsMinTagCount: number = 0;
  @State private statsMaxTagCount: number = 0;

  // ---- M3「灵光再现」：抽签结果摊平成 @State（渲染路径上没有可空对象） ----
  @State private reviewVisible: boolean = false;
  @State private reviewLoading: boolean = false;
  @State private reviewContent: string = '';
  @State private reviewCreatedAt: number = 0;
  @State private reviewPinned: boolean = false;
  @State private reviewIdeaId: number = 0;
  /** 当前按天筛选的那一天（空串 = 没按天筛），由视图模型同步过来 */
  @State private dayFilterKey: string = '';

  /**
   * 给卡片算「多久以前」用的当前时间，每分钟推进一格。
   *
   * 为什么要有它：相对时间是渲染那一刻算出来的，页面不重绘它就永远停在「刚刚」。
   * 把时间做成会变的 @State 并**按值传给 IdeaCard**，变化的只有那几张卡片的文案，
   * 不动列表数据、也不动 `TimelineRow.key`（改 key 会让 LazyForEach 重建可见项、列表会跳）。
   */
  @State private nowTick: number = Date.now();

  /** 列表数据源。字段直接初始化，保证 build() 第一次执行时它就是有效的 */
  private rows: LazyList<TimelineRow> = new LazyList<TimelineRow>();
  /** 列表滚动控制器：筛选条件变化后要能回到顶部 */
  private listScroller: Scroller = new Scroller();
  private vm: TimelineViewModel | null = null;
  private statsVm: StatsViewModel | null = null;
  private reviewService: ReviewService | null = null;
  /**
   * 仓库与导出服务的引用。
   * 导出/导入不经过 ViewModel：它不改变「当前这一页怎么排」，
   * 而是直接和整库打交道；用完再让 ViewModel 重载一次即可。
   */
  private repo: IdeaRepository | null = null;
  private exportService: ExportService | null = null;
  /** 撤销倒计时的定时器 id，-1 表示没有在计时 */
  private undoTimerId: number = -1;
  /**
   * 这次删除动了哪些 id。
   *
   * 单条删除与多选批量删除共用一条撤销条：数组长度为 1 时就是「删了一条」，
   * 大于 1 时文案变「已删除 N 条」——撤销要把整批一起还回来，而不是只还最后一条。
   */
  private undoIds: number[] = [];
  /** 相对时间走字的定时器 id，-1 表示没在跑（页面隐藏时必须停掉，别在后台空转） */
  private tickTimerId: number = -1;

  aboutToAppear(): void {
    const repo = this.createRepository();
    if (repo === null) {
      this.loading = false;
      this.errorText = '本地存储在初始化时出错了';
      return;
    }
    const vm = new TimelineViewModel(repo, this.rows);
    vm.onChange = () => {
      this.syncFromViewModel(vm);
    };
    this.vm = vm;
    this.repo = repo;
    this.exportService = new ExportService(repo);
    // 7 天过期清理放到后台：不阻塞首屏。清失败也只是「多留几天」，下次打开再清，
    // 而且列表查询本身也会挡住过期行，所以用户永远看不到不该看到的东西。
    repo.purgeExpired().then((removed: number) => {
      if (removed > 0) {
        Logger.info(`启动时清理最近删除 ${removed} 条`);
      }
    }).catch((err: Error) => {
      Logger.warn(`启动清理最近删除失败：${err.message}`);
    });
    vm.loadFirstPage();
    // 冷启动时 Want 参数在 aboutToAppear 之前就写好了（EntryAbility.onCreate），
    // 这里补一次消费；页面若已在运行，则由 @Watch 那条路径兜住。
    this.consumeLaunchAction();
    // 首次启动的隐私政策告知（上架审核硬要求）。放在最后：它是盖在最上层的半模态，
    // 不该抢在时间轴首屏加载之前打断渲染。
    this.ensurePrivacyNotice();
  }

  /**
   * 系统返回键：多选模式下先退出多选，而不是直接退出应用。
   * 这是安卓/鸿蒙用户的肌肉记忆 —— 返回上一层（多选是一层模式），再按才离开。
   */
  onBackPress(): boolean {
    if (this.selecting) {
      this.exitSelect();
      return true;
    }
    return false;
  }

  aboutToDisappear(): void {
    this.clearUndoTimer();
    this.stopTimeTick();
  }

  /**
   * 页面可见时才走字。
   *
   * 用 onPageShow/onPageHide 而不是 aboutToAppear/aboutToDisappear：后者在单页应用里
   * 基本只在进程销毁时跑一次，切到后台页面的状态还在、定时器也就一直转，
   * 那是最典型的「看不见的耗电」。
   */
  onPageShow(): void {
    // 先立刻对一次表：从后台回来时，「5 分钟前」可能已经过时很久，
    // 等下一次 tick 才更新会让用户看见一个明显错误的数字。
    this.nowTick = Date.now();
    this.startTimeTick();
  }

  onPageHide(): void {
    this.stopTimeTick();
  }

  private startTimeTick(): void {
    if (this.tickTimerId !== -1) {
      return;
    }
    this.tickTimerId = setInterval(() => {
      this.nowTick = Date.now();
    }, TIME_TICK_MS);
  }

  private stopTimeTick(): void {
    if (this.tickTimerId === -1) {
      return;
    }
    clearInterval(this.tickTimerId);
    this.tickTimerId = -1;
  }

  // ==========================================================================
  // 隐私政策
  // ==========================================================================

  /**
   * 首次启动要显著提示隐私政策。
   *
   * 判据是「用户在空白复选框上打勾并点过『同意并继续』」这条落盘标记，**不是**「第几次启动」：
   * 没同意也没拒绝（比如被系统打断）就下次启动再提示一次——否则「提示过」无法自证。
   */
  private ensurePrivacyNotice(): void {
    if (AppSettingsStore.getBoolean(PRIVACY_ACCEPTED_KEY, false)) {
      return;
    }
    this.openPrivacy(PRIVACY_MODE_ONBOARDING);
  }

  private openPrivacy(mode: string): void {
    this.privacyMode = mode;
    if (mode === PRIVACY_MODE_ONBOARDING) {
      this.privacyGate = true;
    }
    this.privacyVisible = true;
  }

  private acceptPrivacy(): void {
    // 落盘失败也要把面板关掉：本次会话用户已经明确同意了，纠结「有没有记住」
    // 只会把一个已经完成的动作变成一次报错（下次启动会再提示一遍，不是坏事）
    AppSettingsStore.setBoolean(PRIVACY_ACCEPTED_KEY, true);
    this.privacyGate = false;
    this.privacyVisible = false;
    this.privacyMode = PRIVACY_MODE_ONBOARDING;
  }

  /**
   * 「不同意」：确认后退出应用。
   *
   * 为什么是退出而不是「先凑合用」：本应用的全部功能都建立在本地灵感数据上，
   * 没有「不涉及个人信息的基础功能」可以退守；给一个看似能用的空壳反而更糟。
   * 这次确认防的是误触 —— 拒绝本身必须是**一次点得到的真实选项**（审核硬要求）。
   */
  private declinePrivacy(): void {
    const context = this.abilityContext();
    this.getUIContext().showAlertDialog({
      title: '不同意隐私政策',
      message: '不同意将无法继续使用灵感菇。本应用不联网，也不会收集你的任何信息。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '退出应用',
        fontColor: museDanger(this.isDarkMode),
        action: (): void => {
          if (context !== null) {
            context.terminateSelf().catch((err: Error) => {
              Logger.error(`退出应用失败：${err.message}`);
            });
          }
        }
      },
      secondaryButton: {
        value: '再看看',
        action: (): void => {
        }
      }
    });
  }

  /**
   * 隐私半模态的交互式关闭（下滑、点遮罩、系统返回）拦截。
   *
   * - 从告知面板进到完整条款：收回告知面板（用户只是「看完条款回来了」）；
   * - 告知面板本身：不放行，提示先用复选框 + 两个按钮表态；
   * - 其余（设置里的全文页）：正常关闭。
   */
  private handlePrivacyDismiss(dismiss: SheetDismiss): void {
    if (!this.privacyGate) {
      dismiss.dismiss();
      return;
    }
    if (this.privacyMode === PRIVACY_MODE_FULL) {
      this.privacyMode = PRIVACY_MODE_ONBOARDING;
      return;
    }
    toast(this.getUIContext(), '请选择「同意并继续」或「不同意」');
  }

  build() {
    Column() {
      this.Header()

      // 多选期间隐藏搜索/标签筛选/按天筛选：换筛选条件会把正在勾的列表换掉，
      // 「选中了 3 条却看见另外 10 条」比少一个筛选入口更让人困惑
      if (this.showSearchBar() && !this.selecting) {
        SearchBar({
          appliedKeyword: this.appliedKeyword,
          onDebounced: (keyword: string): void => {
            this.applyKeyword(keyword);
          }
        })
      }

      if (this.showTagBar() && !this.selecting) {
        TagFilterBar({
          tags: this.tagListForBar(),
          selectedSignature: this.tagSignature(),
          selectedCount: this.selectedTagCount,
          isTagSelected: (name: string): boolean => this.isTagSelected(name),
          onToggle: (name: string): void => {
            this.toggleTag(name);
          },
          onClearTags: (): void => {
            this.clearTags();
          }
        })
      }

      if (this.dayFilterKey.length > 0 && !this.selecting) {
        this.DayFilterBar()
      }

      if (this.selecting) {
        this.SelectionBar()
      }

      if (this.showLoadingState()) {
        this.LoadingState()
      } else if (this.showErrorState()) {
        this.ErrorState()
      } else if (this.showEmptyState()) {
        this.EmptyState()
      } else {
        this.Timeline()
      }

      if (this.undoVisible && !this.selecting) {
        this.UndoBar()
      }

      if (this.selecting) {
        this.SelectionActions()
      } else {
        CaptureBar({
          onSubmitted: (content: string): Promise<boolean> => this.handleSubmit(content)
        })
      }
    }
    .width('100%')
    .height('100%')
    // 全屏布局下自己让开状态栏与导航条：高度由 EntryAbility 量好广播，页面不写魔法数字
    // 左右留白统一放在这里（页面唯一的「装订线」）：子组件只管 width('100%')，
    // 不再各自写 margin —— width('100%') 叠加 margin 会让组件溢出父容器、
    // 结果就是「列表卡片内缩 24，底部记录栏却顶到屏幕边」这种对不齐。
    .padding({
      top: this.statusBarHeight,
      bottom: this.navigationBarHeight,
      left: MuseSpace.lg,
      right: MuseSpace.lg
    })
    .backgroundColor(resolvePageBackground(this.isDarkMode, this.pageBackground))
    .bindSheet($$this.detailVisible, this.DetailSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface)
    })
  }

  // ==========================================================================
  // 区块
  // ==========================================================================

  @Builder
  Header() {
    Column({ space: 2 }) {
      Row({ space: MuseSpace.sm }) {
        // 标题这只蘑菇刻意保留 emoji：符号库里没有蘑菇（`sys.symbol.mushroom*` 不存在），
        // 而 SymbolGlyph 是单色的，换过去会变成一只绿蘑菇、丢掉品牌标记。
        Text('🍄')
          .fontSize(22)
        Text('灵感菇')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(museTextPrimary(this.isDarkMode))
        Blank()
        // 四个入口用系统符号（`sys.symbol.*`）而不是 emoji：emoji 的字形每个 ROM 一套，
        // 也不跟随主题色。名字写错编译就不过（`Unknown resource name 'xxx'`，10903329），
        // 所以符号名这一层由编译器兜底；真机只看画出来的形状对不对（1.0.1 候选三做过核对）。
        // 无障碍：屏幕上只有符号时读屏软件念不出含义（「sparkles」对用户毫无意义）——统一给中文标签。
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(18)
          .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())])
          .padding(MuseSpace.xs)
          // 多选时收起四个工具入口：多选是「整理」模式，搜索/足迹/设置留在屏幕上
          // 会出现「点了搜索，搜索栏却被多选藏起来」的空响。
          .visibility(this.selecting ? Visibility.None : Visibility.Visible)
          .accessibilityText('灵光再现')
          .accessibilityDescription('随机翻出一条旧灵感')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.openReview();
          })
          .bindSheet($$this.reviewVisible, this.ReviewSheetBuilder(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface)
          })
        SymbolGlyph($r('sys.symbol.histogram'))
          .fontSize(18)
          .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())])
          .padding(MuseSpace.xs)
          .visibility(this.selecting ? Visibility.None : Visibility.Visible)
          .accessibilityText('记录足迹')
          .accessibilityDescription('最近 12 周的记录热力图与标签云')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.openStats();
          })
          .bindSheet($$this.statsVisible, this.StatsSheetBuilder(), {
            // 按内容收缩：热力图 + 标签云实际只占半屏，写死 LARGE 会留出半屏空白
            // （上架截图 `docs/store/shot-5-stats.png`）。内容比屏幕高时由 StatsSheet
            // 内部的 Scroll 兜住（它自己量屏幕高度设上限）。
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface)
          })
        SymbolGlyph($r('sys.symbol.magnifyingglass_circle'))
          .fontSize(18)
          .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())])
          .padding(MuseSpace.xs)
          .visibility(this.selecting ? Visibility.None : Visibility.Visible)
          .accessibilityText(this.searchOpen ? '收起搜索' : '搜索')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.toggleSearch();
          })
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(18)
          .fontColor([resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary())])
          .padding(MuseSpace.xs)
          .visibility(this.selecting ? Visibility.None : Visibility.Visible)
          .accessibilityText('设置')
          .accessibilityDescription('外观与数据备份')
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.settingsVisible = true;
          })
          .bindSheet($$this.settingsVisible, this.SettingsSheetBuilder(), {
            height: 620,
            dragBar: true,
            showClose: false,
            backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface)
          })
      }
      .width('100%')
      // 隐私政策半模态挂在标题这一行上：它不对应任何图标入口（首启自动弹、设置里也能进），
      // 而灵光再现 / 记录足迹 / 设置三个入口各自已经挂了半模态。
      .bindSheet($$this.privacyVisible, this.PrivacySheetBuilder(), {
        height: SheetSize.LARGE,
        dragBar: true,
        showClose: false,
        backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface),
        // 下滑/系统返回不再「一关了之」：完整条款先收回告知面板；
        // 还没选同意/拒绝时连告知面板也不许关 —— 之前正是这里把同意流程放走的
        shouldDismiss: (dismiss: SheetDismiss) => {
          this.handlePrivacyDismiss(dismiss);
        }
      })

      Row() {
        Text('让灵感，破土而出。')
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
        Blank()
        if (this.totalCount > 0) {
          // 筛选时口径要说清楚：这是「匹配到的条数」，不是灵感库总数
          Text(this.filterActive ? `${this.totalCount} 条匹配` : `${this.totalCount} 条灵感`)
            .fontSize(11)
            .fontColor(museTextSecondary(this.isDarkMode))
        }
      }
      .width('100%')
      // 最近删除挂在页头这一行上：它不属于时间轴，也不跟着筛选走
      .bindSheet($$this.trashVisible, this.TrashSheetBuilder(), {
        height: SheetSize.LARGE,
        dragBar: true,
        showClose: false,
        backgroundColor: resolveCardSurface(this.isDarkMode, this.cardSurface)
      })
    }
    .width('100%')
    .padding({ top: MuseSpace.sm, bottom: MuseSpace.md })
  }

  @Builder
  Timeline() {
    List({ space: MuseSpace.md, scroller: this.listScroller }) {
      LazyForEach(this.rows, (row: TimelineRow) => {
        ListItem() {
          if (row.kind === TimelineRowKind.HEADER) {
            DayHeader({
              title: row.title,
              count: row.count,
              isPinnedGroup: row.isPinnedGroup
            })
          } else {
            IdeaCard({
              content: row.content,
              createdAt: row.createdAt,
              pinned: row.pinned,
              edited: row.edited,
              keyword: this.appliedKeyword,
              tagNames: row.tagNames,
              now: this.nowTick,
              selecting: this.selecting,
              selected: this.isSelected(row.ideaId),
              onOpen: () => {
                this.openDetail(row);
              },
              onLongPress: () => {
                if (this.selecting) {
                  this.toggleSelected(row.ideaId);
                } else {
                  this.enterSelect(row.ideaId);
                }
              },
              onToggleSelect: () => {
                this.toggleSelected(row.ideaId);
              },
              onTagClick: (name: string): void => {
                this.toggleTag(name);
              }
            })
          }
        }
      }, (row: TimelineRow) => row.key)

      ListItem() {
        this.ListFooter()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  @Builder
  ListFooter() {
    Column() {
      if (this.loading) {
        Row({ space: MuseSpace.sm }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.accentOrPrimary())
          Text('加载中…')
            .fontSize(11)
            .fontColor(museTextSecondary(this.isDarkMode))
        }
      } else if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      } else if (!this.hasMore) {
        Text(`到底了 · 共 ${this.totalCount} 条`)
          .fontSize(11)
          .fontColor(museTextSecondary(this.isDarkMode))
      }
    }
    .width('100%')
    .padding({ top: MuseSpace.md, bottom: MuseSpace.lg })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  LoadingState() {
    Column({ space: MuseSpace.sm }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(this.accentOrPrimary())
      Text('正在打开灵感库…')
        .fontSize(12)
        .fontColor(museTextSecondary(this.isDarkMode))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyState() {
    Column({ space: MuseSpace.sm }) {
      // 空库与「没有匹配」是两种心情，所以给两个不同的符号
      if (this.filterActive) {
        SymbolGlyph($r('sys.symbol.magnifyingglass_circle'))
          .fontSize(40)
          .fontColor([museTextSecondary(this.isDarkMode)])
      } else {
        SymbolGlyph($r('sys.symbol.leaf'))
          .fontSize(40)
          .fontColor([museTextSecondary(this.isDarkMode)])
      }
      Text(this.filterActive ? '没有匹配的灵感' : '灵感库还是空的')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(museTextPrimary(this.isDarkMode))
      Text(this.filterActive
        ? '换个关键词试试；多个标签是「同时满足」，少选几个范围更大'
        : '在下面写下第一个念头，它会在这里长出来')
        .fontSize(13)
        .fontColor(museTextSecondary(this.isDarkMode))
        .textAlign(TextAlign.Center)
      if (this.filterActive) {
        Button('清除筛选条件')
          .type(ButtonType.Capsule)
          .fontSize(14)
          .constraintSize({ minHeight: 36 })
          .fontColor(onAccentColor(this.snackColor()))
          .backgroundColor(this.snackColor())
          .margin({ top: MuseSpace.xs })
          .onClick(() => {
            this.clearAllFilters();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(MuseSpace.lg)
    .borderRadius(MuseRadius.card)
    .backgroundColor(resolveCardSurface(this.isDarkMode, this.cardSurface))
    .border({ width: 1, color: resolveCardBorder(this.isDarkMode, this.accentOrPrimary()) })
  }

  @Builder
  ErrorState() {
    Column({ space: MuseSpace.md }) {
      SymbolGlyph($r('sys.symbol.heavy_rain'))
        .fontSize(32)
        .fontColor([museTextSecondary(this.isDarkMode)])
      Text(this.errorText)
        .fontSize(13)
        .fontColor(museTextSecondary(this.isDarkMode))
      Button('重试')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .constraintSize({ minHeight: 36 })
        .fontColor(onAccentColor(this.snackColor()))
        .backgroundColor(this.snackColor())
        .onClick(() => {
          this.reload();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 多选模式顶栏：已选条数 + 全选 + 取消。
   *
   * 放在时间轴上方而不是替换页头：页头那四个入口（灵光再现/足迹/搜索/设置）
   * 在多选期间仍然可见，但会被下方的条压住视觉重心——用户看得见自己在哪一层。
   */
  @Builder
  SelectionBar() {
    Row({ space: MuseSpace.sm }) {
      Text(this.selectionTitle())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(museTextPrimary(this.isDarkMode))
      Blank()
      Text(this.allLoadedSelected() ? '取消全选' : '全选')
        .fontSize(13)
        .fontColor(resolvePrimaryColor(this.isDarkMode, this.accentOrPrimary()))
        .padding({ left: MuseSpace.sm, right: MuseSpace.sm, top: MuseSpace.xs, bottom: MuseSpace.xs })
        .accessibilityText(this.allLoadedSelected() ? '取消全选' : '全选已加载的灵感')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.selectAllLoaded();
        })
      Text('取消')
        .fontSize(13)
        .fontColor(museTextSecondary(this.isDarkMode))
        .padding({ left: MuseSpace.sm, right: MuseSpace.sm, top: MuseSpace.xs, bottom: MuseSpace.xs })
        .accessibilityText('退出多选')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.exitSelect();
        })
    }
    .width('100%')
    .padding({ top: MuseSpace.xs, bottom: MuseSpace.sm })
  }

  /**
   * 多选模式的底栏：导出所选 / 删除。
   *
   * 替换掉记录栏而不是叠在它上面：多选时用户不该再往库里加东西，
   * 少一个输入框就少一次「正在选，却误触了输入框」。
   */
  @Builder
  SelectionActions() {
    Row({ space: MuseSpace.md }) {
      Button('导出所选')
        .type(ButtonType.Normal)
        .layoutWeight(1)
        .height(48)
        .borderRadius(MuseRadius.control)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.filledButtonColor())
        .fontColor(onAccentColor(this.filledButtonColor()))
        .enabled(this.selectionEnabled())
        .opacity(this.selectionEnabled() ? 1 : 0.45)
        .accessibilityDescription('把选中的灵感导出为 JSON 或 Markdown')
        .onClick(() => {
          this.chooseExportSelected();
        })
      Button('删除')
        .type(ButtonType.Normal)
        .layoutWeight(1)
        .height(48)
        .borderRadius(MuseRadius.control)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(Color.Transparent)
        .fontColor(museDanger(this.isDarkMode))
        .border({ width: 1, color: museDanger(this.isDarkMode) })
        .enabled(this.selectedIds.length > 0)
        .opacity(this.selectedIds.length > 0 ? 1 : 0.45)
        .accessibilityDescription('删除选中的灵感，5 秒内可撤销')
        .onClick(() => {
          this.deleteSelected();
        })
    }
    .width('100%')
    .padding({ top: MuseSpace.sm })
  }

  /**
   * 删除后的撤销条。
   * 普通删除不做二次确认弹窗：确认框会让「删一条」从 1 次操作变 2 次，与「极速」相悖；
   * 两层兜底足够：5 秒内可撤销，之后还有 7 天「最近删除」。
   * 真正不可逆的「彻底删除 / 清空」才在回收站里单独确认（见 TrashSheet 与下面的确认框）。
   */
  @Builder
  UndoBar() {
    Row({ space: MuseSpace.sm }) {
      Column({ space: 2 }) {
        Text(this.undoTitle())
          .fontSize(14)
          .fontColor(onAccentColor(this.snackColor()))
        // 5 秒撤销条只是第一层兜底；说清「还能在最近删除里找回」，用户才敢真的用删除
        Text('7 天内可在「最近删除」找回')
          .fontSize(11)
          .fontColor(onAccentColor(this.snackColor()))
          .opacity(0.75)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text('撤销')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(onAccentColor(this.snackColor()))
        .padding({ left: MuseSpace.sm, right: MuseSpace.sm, top: MuseSpace.xs, bottom: MuseSpace.xs })
        .accessibilityText('撤销删除')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.undoDelete();
        })
    }
    .width('100%')
    .padding({ left: MuseSpace.lg, right: MuseSpace.md, top: MuseSpace.sm, bottom: MuseSpace.sm })
    .margin({ bottom: MuseSpace.sm })
    .borderRadius(MuseRadius.control)
    .backgroundColor(this.snackColor())
    // 从下方浮上来：撤销条是「刚刚那件事」的延伸，从底部冒出比凭空出现更容易被看见
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 16 }))
        .animation({ duration: 200, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseIn })
    ))
  }

  // ==========================================================================
  // 半模态
  // ==========================================================================

  @Builder
  DetailSheet() {
    IdeaDetailSheet({
      initialContent: this.selectedContent,
      createdAt: this.selectedCreatedAt,
      updatedAt: this.selectedUpdatedAt,
      pinned: this.selectedPinned,
      onSave: (content: string) => {
        this.saveDetail(content);
      },
      onTogglePin: () => {
        this.togglePin();
      },
      onDelete: () => {
        this.deleteDetail();
      },
      onClose: () => {
        this.detailVisible = false;
      }
    })
  }

  @Builder
  SettingsSheetBuilder() {
    SettingsSheet({
      busy: this.dataBusy,
      status: this.dataStatus,
      onExportJson: () => {
        this.exportJson();
      },
      onExportMarkdown: () => {
        this.exportMarkdown();
      },
      onImportJson: () => {
        this.importJson();
      },
      onOpenTrash: () => {
        // 与隐私入口同样的处理：先收设置面板再开，两个半模态不叠着出现
        this.settingsVisible = false;
        setTimeout(() => {
          this.openTrash();
        }, 260);
      },
      onOpenPrivacy: () => {
        // 先收起设置面板再打开条款面板：两个半模态不该叠着出现。
        // 260ms 是「收起动画走完」的估计值，早于它打开会看到两块面板交叠。
        this.settingsVisible = false;
        setTimeout(() => {
          this.openPrivacy(PRIVACY_MODE_FULL);
        }, 260);
      },
      onClose: () => {
        this.settingsVisible = false;
      }
    })
  }

  /**
   * 最近删除半模态。
   *
   * 面板只拿已经取好的数据：剩余天数由 TrashSheet 按 nowTick 现算，
   * 页面负责的是「打开时拉一次、恢复/彻底删除后重拉」这条时序。
   */
  @Builder
  TrashSheetBuilder() {
    TrashSheet({
      items: this.trashItems,
      loading: this.trashLoading,
      errorText: this.trashError,
      // 与卡片上的相对时间共用同一个走字变量：面板开着时「还剩 N 天」也会跟着走
      now: this.nowTick,
      onRestore: (id: number) => {
        this.restoreFromTrash(id);
      },
      onDeleteForever: (id: number) => {
        this.confirmDeleteForever(id);
      },
      onClearAll: () => {
        this.confirmClearTrash();
      },
      onRetry: () => {
        this.loadTrash();
      },
      onClose: () => {
        this.trashVisible = false;
      }
    })
  }

  /** 首启告知与完整条款共用一个半模态：切 mode 而不是换组件，避免出现两份会漂移的文案 */
  @Builder
  PrivacySheetBuilder() {    PrivacySheet({
      mode: this.privacyMode,
      // 只有「从告知面板进来看条款」才需要返回；设置里的全文页直接 ✕ 关闭
      showBack: this.privacyGate && this.privacyMode === PRIVACY_MODE_FULL,
      onReadFull: () => {
        this.privacyMode = PRIVACY_MODE_FULL;
      },
      onAccept: () => {
        this.acceptPrivacy();
      },
      onDecline: () => {
        this.declinePrivacy();
      },
      onBack: () => {
        this.privacyMode = PRIVACY_MODE_ONBOARDING;
      },
      onClose: () => {
        // 还在首启流程里时，✕ 只意味着「回到告知面板」，不能把同意闸门一起关掉
        if (this.privacyGate) {
          this.privacyMode = PRIVACY_MODE_ONBOARDING;
          return;
        }
        this.privacyVisible = false;
      }
    })
  }

  /** 按天筛选时的日期 chip（点热力图某一格之后出现） */
  @Builder
  DayFilterBar() {
    Row({ space: MuseSpace.sm }) {
      // 图标与文字要一起坐在同一颗胶囊里：先包一层 Row 承担胶囊样式，里面的 Text 只管字
      // （原来是 `📅 ` 直接拼进字符串，换成符号后不能这么写）
      Row({ space: MuseSpace.xs }) {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(12)
          .fontColor([onAccentColor(this.filledButtonColor())])
        Text(this.dayFilterLabel())
          .fontSize(12)
          .fontColor(onAccentColor(this.filledButtonColor()))
      }
      .padding({
        left: MuseSpace.md,
        right: MuseSpace.md,
        top: MuseSpace.xs,
        bottom: MuseSpace.xs
      })
      .borderRadius(MuseRadius.pill)
      .backgroundColor(this.filledButtonColor())
      Text('✕')
        .fontSize(11)
        .fontColor(museTextSecondary(this.isDarkMode))
        .padding(MuseSpace.xs)
        .accessibilityText('清除日期筛选')
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.clearDayFilter();
        })
      Blank()
    }
    .width('100%')
    .padding({ bottom: MuseSpace.sm })
    // 从热力图下钻出来的日期 chip 滑入：它出现的时机是「面板刚收起」，
    // 有一下位移能让眼睛跟上「刚才点的那天变成了这里的筛选条件」。
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
        .animation({ duration: 180, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
    ))
  }

  @Builder
  StatsSheetBuilder() {
    StatsSheet({
      loading: this.statsLoading,
      errorText: this.statsError,
      summary: this.statsSummary,
      cells: this.statsCells,
      maxCount: this.statsMaxCount,
      tags: this.statsTags,
      minTagCount: this.statsMinTagCount,
      maxTagCount: this.statsMaxTagCount,
      selectedSignature: this.tagSignature(),
      isTagSelected: (name: string): boolean => this.isTagSelected(name),
      onPickDay: (day: string): void => {
        this.pickDay(day);
      },
      onPickTag: (name: string): void => {
        // 标签云是「热力下钻」入口：点一下就该看到结果列表。
        // 多选交集的精细操作留给顶部筛选条（这里点完它也会同步高亮）。
        this.statsVisible = false;
        this.toggleTag(name);
      },
      onRetry: (): void => {
        this.loadStats();
      }
    })
  }

  @Builder
  ReviewSheetBuilder() {
    Column({ space: MuseSpace.md }) {
      if (this.reviewLoading) {
        Column() {
          LoadingProgress().width(36).height(36).color(this.accentColor)
          Text('正在翻找旧灵感…').fontSize(12).fontColor(museTextSecondary(this.isDarkMode))
        }
        .width('100%')
        .padding(MuseSpace.xl)
      } else if (this.reviewContent.length === 0) {
        Column({ space: MuseSpace.sm }) {
          Text('灵感库还是空的').fontSize(15).fontColor(museTextPrimary(this.isDarkMode))
          Text('先记下几条，这里就能翻出旧灵感了。')
            .fontSize(12)
            .fontColor(museTextSecondary(this.isDarkMode))
          Button('去记录')
            .fontSize(13)
            .constraintSize({ minHeight: 34 })
            .backgroundColor(this.filledButtonColor())
            .fontColor(onAccentColor(this.filledButtonColor()))
            .onClick(() => {
              this.reviewVisible = false;
            })
        }
        .width('100%')
        .padding(MuseSpace.xl)
      } else {
        ReviewCard({
          content: this.reviewContent,
          createdAt: this.reviewCreatedAt,
          pinned: this.reviewPinned,
          onAnother: (): void => {
            this.drawReview();
          },
          onTogglePin: (): void => {
            this.pinReview();
          },
          onEdit: (): void => {
            this.editReview();
          }
        })
      }
    }
    .width('100%')
    // 这里**不能**写 `.height('100%')`：本面板声明的是 `SheetSize.FIT_CONTENT`（见上面的 bindSheet），
    // 内容一旦自己申请全高，FIT_CONTENT 就没有可收缩的余地——真机上的表现就是「内容一小块、
    // 下面四分之三全是空白」（上架截图 `docs/store/shot-4-review.png`）。宽度仍写满，
    // 让「加载中 / 空库 / 有内容」三种状态的左右留白保持一致。
    // 底部要让出系统导航条：面板按内容收缩后会贴着屏幕底边，卡片底边正好落在 2860（屏幕底边），
    // 底部圆角被切掉、内容压在导航条上（真机 `dumpLayout` 实测）。广播值给的就是导航条高度
    // （真机实测 30vp），但窗口本身已被系统让开时它会广播 0，所以再兜一个最小留白。
    .padding({
      left: MuseSpace.lg,
      right: MuseSpace.lg,
      top: MuseSpace.md,
      bottom: Math.max(this.navigationBarHeight, MuseSpace.xl)
    })
  }

  // ==========================================================================
  // 逻辑
  // ==========================================================================

  /**
   * 取上下文建仓库。
   * 优先用 EntryAbility 显式交给我们的上下文（时机确定），
   * UIContext 只作为兜底——它在 aboutToAppear 里是否已就绪属于实现细节，不适合当主路径。
   */
  private createRepository(): IdeaRepository | null {
    const fromAbility = getAppContext();
    if (fromAbility !== null) {
      return getIdeaRepository(fromAbility);
    }
    try {
      const fallback = this.getUIContext().getHostContext() as common.UIAbilityContext;
      return getIdeaRepository(fallback);
    } catch (err) {
      Logger.error('拿不到 Ability 上下文，无法打开数据库');
      return null;
    }
  }

  private syncFromViewModel(vm: TimelineViewModel): void {
    this.loading = vm.isLoading();
    this.hasMore = vm.hasMore();
    this.totalCount = vm.total();
    this.errorText = vm.lastError();
    // 筛选状态也抄进 @State：ViewModel 里的字段不是可观察对象，
    // 只有 @State 才能驱动重绘（tagVersion 每次自增，专门当重绘指纹用）
    this.filterActive = vm.isFiltered();
    this.appliedKeyword = vm.currentKeyword();
    this.selectedTagCount = vm.selectedTagCount();
    this.dayFilterKey = vm.currentDayKey();
    this.tagItems = vm.tagList();
    this.tagVersion = this.tagVersion + 1;
  }

  /** 有关键词在生效时，搜索框必须一直摆着，否则「结果被筛过却看不见条件」 */
  private showSearchBar(): boolean {
    return this.searchOpen || this.appliedKeyword.length > 0;
  }

  private showTagBar(): boolean {
    // 读的是 @State 的 tagItems（而不是去问 ViewModel）：这个分支决定筛选条要不要创建，
    // 判断里必须出现可观察变量，否则「标签是后到的」这件事永远驱动不了它
    return this.selectedTagCount > 0 || this.tagItems.length > 0;
  }

  private tagListForBar(): Tag[] {
    return this.tagItems;
  }

  /**
   * 筛选条的重绘指纹。
   *
   * 读出 `tagVersion` 是关键：ArkUI 只会更新「读过该状态变量」的元素，
   * 把自增的版本号编进指纹，选中态才一定跟着重画。
   */
  private tagSignature(): string {
    const names: string[] = [];
    for (let i = 0; i < this.tagItems.length; i++) {
      if (this.isTagSelected(this.tagItems[i].name)) {
        names.push(this.tagItems[i].name);
      }
    }
    return `v${this.tagVersion}:${names.join('|')}`;
  }

  private isTagSelected(name: string): boolean {
    const vm = this.vm;
    if (vm === null) {
      return false;
    }
    return vm.isTagSelected(name);
  }

  private toggleSearch(): void {
    if (this.searchOpen && this.appliedKeyword.length > 0) {
      // 收起搜索框就把关键词一并清掉：否则「框没了、结果还是筛过的」像是数据丢了
      this.searchOpen = false;
      this.applyKeyword('');
      return;
    }
    this.searchOpen = !this.searchOpen;
  }

  private applyKeyword(keyword: string): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.setKeyword(keyword).then(() => {
      this.scrollToTop();
    });
  }

  private toggleTag(name: string): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.toggleTagByName(name).then(() => {
      this.scrollToTop();
    });
  }

  private clearTags(): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.clearSelectedTags().then(() => {
      this.scrollToTop();
    });
  }

  private clearAllFilters(): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.clearFilters().then(() => {
      this.scrollToTop();
    });
  }

  /** 筛选后必须回到顶部：否则可能停在「旧列表的深处」，满屏都是「到底了」 */
  private scrollToTop(): void {
    try {
      this.listScroller.scrollToIndex(0);
    } catch (err) {
      // 列表可能还没建出来（筛选后一条都没有），滚不动不影响正确性
    }
  }

  // ==========================================================================
  // M3：统计面板 / 灵光再现 / 按天筛选
  // ==========================================================================

  private openStats(): void {
    this.statsVisible = true;
    this.loadStats();
  }

  /**
   * 拉一次统计。
   *
   * 每次打开面板都重拉：热力图与标签云是全库聚合（万条量级几十毫秒），
   * 面板是用户主动打开的，与其维护「数据什么时候脏了」不如每次都算一遍 —— 永远不会有陈旧数字。
   */
  private loadStats(): void {
    const repo = this.createRepository();
    if (repo === null) {
      this.statsError = '本地存储不可用';
      return;
    }
    if (this.statsVm === null) {
      this.statsVm = new StatsViewModel(repo);
    }
    const statsVm = this.statsVm;
    this.statsLoading = true;
    this.statsError = '';
    statsVm.load().then(() => {
      const heat = statsVm.heat();
      this.statsLoading = statsVm.isLoading();
      this.statsError = statsVm.lastError();
      this.statsSummary = statsVm.summary();
      this.statsCells = heat.cells;
      this.statsMaxCount = heat.maxCount;
      this.statsTags = statsVm.tagWeights();
      this.statsMinTagCount = statsVm.minTagCount();
      this.statsMaxTagCount = statsVm.maxTagCount();
    });
  }

  /** 点热力图的某一格：按那一天筛选，并收起面板看结果 */
  private pickDay(day: string): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    this.statsVisible = false;
    vm.setDayKey(day).then(() => {
      this.scrollToTop();
    });
  }

  private clearDayFilter(): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.setDayKey('').then(() => {
      this.scrollToTop();
    });
  }

  /** 'YYYY-MM-DD' → 「9 月 5 日」（chip 上显示给人看的日期） */
  private dayFilterLabel(): string {
    const parts = this.dayFilterKey.split('-');
    if (parts.length !== 3) {
      return this.dayFilterKey;
    }
    const year = Number.parseInt(parts[0], 10);
    const month = Number.parseInt(parts[1], 10);
    const day = Number.parseInt(parts[2], 10);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)) {
      return this.dayFilterKey;
    }
    const ms = new Date(year, month - 1, day).getTime();
    return formatDayLabel(ms, Date.now());
  }

  /** `@Watch` 回调：快捷方式/卡片又一次带意图进来（热启动只剩这条路径） */
  private onLaunchActionChanged(): void {
    this.consumeLaunchAction();
  }

  /**
   * 消费一次启动意图：**先清空再执行**。
   *
   * 顺序有讲究：清空之后再干活，中途任何一次重绘/重入都不会把同一个动作执行两遍
   * （`focusCaptureInput` 里还要等布局，这个窗口期足够发生一次重绘）。
   */
  private consumeLaunchAction(): void {
    const action = this.launchAction;
    if (action.length === 0) {
      return;
    }
    AppStorage.setOrCreate(LAUNCH_ACTION_KEY, '');
    if (action === LAUNCH_ACTION_CAPTURE) {
      this.focusCaptureInput();
    } else if (action === LAUNCH_ACTION_REVIEW) {
      this.openReview();
    }
  }

  /** 让底部输入框拿到焦点并弹出键盘（快捷方式「记一条灵感」的落点） */
  private focusCaptureInput(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('capture_input');
      } catch (err) {
        const error = err as Error;
        Logger.warn(`聚焦输入框失败：${error.message}`);
      }
    }, 300);
  }

  private openReview(): void {
    this.reviewVisible = true;
    this.drawReview();
  }

  /** 抽一条（「换一条」也走这里）：抽签会写 preferences，绝不能放在 build 里 */
  private drawReview(): void {
    const repo = this.createRepository();
    if (repo === null) {
      return;
    }
    if (this.reviewService === null) {
      this.reviewService = new ReviewService(repo);
    }
    const service = this.reviewService;
    // 已经显示着一条时才算「换一条」；首次打开面板是静默的——刚点开就震一下很像弹广告
    const isRedraw = this.reviewContent.length > 0;
    this.reviewLoading = true;
    service.next().then((idea: Idea | null) => {
      this.reviewLoading = false;
      if (idea === null) {
        this.reviewContent = '';
        this.reviewCreatedAt = 0;
        this.reviewPinned = false;
        this.reviewIdeaId = 0;
        return;
      }
      this.reviewIdeaId = idea.id;
      this.reviewContent = idea.content;
      this.reviewCreatedAt = idea.createdAt;
      this.reviewPinned = idea.pinned;
      if (isRedraw) {
        Haptics.tap();
      }
    }).catch((err: Error) => {
      this.reviewLoading = false;
      Logger.error(`抽取旧灵感失败：${err.message}`);
      toast(this.getUIContext(), '翻找旧灵感失败');
    });
  }

  /** 「钉到最前」/「取消钉住」：置顶后它会出现在时间轴最前 */
  private pinReview(): void {
    const vm = this.vm;
    if (vm === null || this.reviewIdeaId === 0) {
      return;
    }
    const next = !this.reviewPinned;
    vm.setPinned(this.reviewIdeaId, next).then((ok: boolean) => {
      if (!ok) {
        toast(this.getUIContext(), '置顶失败');
        return;
      }
      this.reviewPinned = next;
      Haptics.tap();
      toast(this.getUIContext(), next ? '已钉到时间轴最前' : '已取消钉住');
    });
  }

  /** 「去编辑」：收起回顾面板，打开这条灵感的详情半模态 */
  private editReview(): void {
    const id = this.reviewIdeaId;
    if (id === 0) {
      return;
    }
    this.reviewVisible = false;
    this.openDetailById(id);
  }

  private openDetailById(id: number): void {
    const repo = this.createRepository();
    if (repo === null) {
      return;
    }
    repo.findById(id).then((idea: Idea | null) => {
      if (idea === null) {
        // 抽到之后被删掉了（比如在别的窗口里删的）：给个提示就行，不当成错误
        toast(this.getUIContext(), '这条灵感已经不在了');
        return;
      }
      this.selectedId = idea.id;
      this.selectedContent = idea.content;
      this.selectedCreatedAt = idea.createdAt;
      this.selectedUpdatedAt = idea.updatedAt;
      this.selectedPinned = idea.pinned;
      this.detailVisible = true;
    }).catch((err: Error) => {
      Logger.error(`打开灵感详情失败（id=${id}）：${err.message}`);
      toast(this.getUIContext(), '打开失败');
    });
  }

  private showLoadingState(): boolean {
    return this.loading && this.totalCount === 0 && this.errorText.length === 0;
  }

  private showErrorState(): boolean {
    return this.totalCount === 0 && this.errorText.length > 0;
  }

  private showEmptyState(): boolean {
    return this.totalCount === 0 && !this.loading;
  }

  private async reload(): Promise<void> {
    const vm = this.vm;
    if (vm === null) {
      toast(this.getUIContext(), '本地存储不可用');
      return;
    }
    await vm.loadFirstPage();
  }

  // ==========================================================================
  // 数据备份：导出 / 导入（M4）
  // ==========================================================================

  /** 弹系统选择器要用 UIAbilityContext；和建仓库一样，优先用 EntryAbility 交过来的那个 */
  private abilityContext(): common.UIAbilityContext | null {
    const fromAbility = getAppContext();
    if (fromAbility !== null) {
      return fromAbility;
    }
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (err) {
      return null;
    }
  }

  private exportJson(): void {
    this.runExport('json');
  }

  private exportMarkdown(): void {
    this.runExport('markdown');
  }

  /**
   * 导出两步走：**先把内容拼好，再弹系统选择器**。
   * 反过来（先让用户选路径、再聚合）用户会对着一个已关闭的对话框等几秒，
   * 期间没有任何反馈，像是卡死了。顺序换一下，等待发生在「点下去」到「弹窗出现」之间，
   * 用户能立刻看到忙碌状态。
   */
  private async runExport(kind: string): Promise<void> {
    const service = this.exportService;
    const context = this.abilityContext();
    if (service === null || context === null) {
      this.dataStatus = '本地存储不可用，导出不了';
      return;
    }
    if (this.dataBusy) {
      return;
    }
    this.dataBusy = true;
    this.dataStatus = kind === 'json' ? '正在整理 JSON…' : '正在整理 Markdown…';
    try {
      const isJson = kind === 'json';
      const content = isJson ? await service.buildJson() : await service.buildMarkdown();
      const name = ExportService.suggestedFileName(isJson ? 'json' : 'md', Date.now());
      this.dataStatus = '正在打开文件选择器…';
      const saved = await FileBridge.saveText(context, name, isJson ? '.json' : '.md', content);
      if (saved === null) {
        this.dataStatus = '已取消导出';
        return;
      }
      // 报的是**系统实际生成的文件名**（不是我们请求的那个）：后缀里的点丢过一次，
      // 只有报真实结果才看得出落盘文件是不是真的能用（缺陷修复见 FileBridge.saveText 注释）
      this.dataStatus = `已导出 ${saved}（${this.readableSize(utf8ByteLength(content))}）`;
      Logger.info(`导出完成：${kind}，${utf8ByteLength(content)} 字节`);
    } catch (err) {
      const error = err as Error;
      this.dataStatus = `导出失败：${error.message}`;
      Logger.error(`导出失败：${kind}｜${error.message}`);
    } finally {
      this.dataBusy = false;
    }
  }

  /**
   * 导入：合并式，不覆盖。
   * 导入完成后必须 `reload()`——时间轴、标签条、统计面板全都读的是同一份库，
   * 少刷新一处就会出现「列表里没有、统计里有」的错位。
   */
  private async importJson(): Promise<void> {
    const service = this.exportService;
    const context = this.abilityContext();
    if (service === null || context === null) {
      this.dataStatus = '本地存储不可用，导入不了';
      return;
    }
    if (this.dataBusy) {
      return;
    }
    this.dataBusy = true;
    this.dataStatus = '正在等选择文件…';
    try {
      const text = await FileBridge.pickAndReadText(context);
      if (text === null) {
        this.dataStatus = '已取消导入';
        return;
      }
      this.dataStatus = '正在合并…';
      const result = await service.importJson(text);
      // 「恢复」必须单独说：用户删掉几条再导入备份时，期望看到的是「回来了」，
      // 而不是只有一句「跳过重复」（1.0.0 审核问题 1 就是这句话把他劝退的）
      const restored = result.restored > 0 ? `，恢复 ${result.restored} 条` : '';
      const skipped = result.skipped > 0 ? `，跳过重复 ${result.skipped} 条` : '';
      this.dataStatus = `导入完成：新增 ${result.added} 条${restored}${skipped}（文件里共 ${result.total} 条）`;
      await this.reload();
      Logger.info(`导入完成：新增 ${result.added} / 恢复 ${result.restored} / 跳过 ${result.skipped} / 共 ${result.total}`);
    } catch (err) {
      const error = err as Error;
      this.dataStatus = `导入失败：${error.message}`;
      Logger.error(`导入失败：${error.message}`);
    } finally {
      this.dataBusy = false;
    }
  }

  /** 字节数转成人话（导出提示里显示，用户最关心「导出来多大」） */
  private readableSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  }

  private loadMore(): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    vm.loadMore();
  }

  /**
   * 记录一条。
   * 返回 true 时 `CaptureBar` 才会清空输入框——保存失败必须把用户打的字留在原地。
   */
  private async handleSubmit(content: string): Promise<boolean> {
    const vm = this.vm;
    if (vm === null) {
      toast(this.getUIContext(), '本地存储不可用，暂时存不了');
      return false;
    }
    const created: Idea | null = await vm.addIdea(content);
    if (created === null) {
      toast(this.getUIContext(), '保存失败，内容已保留在输入框');
      return false;
    }
    // 标签一多，卡片上的 chip 行会吃掉半屏。这里**只提醒、不拦截也不截断**：
    // 硬砍会造出「正文里明明写着、却筛不出来」的不一致，代价比提示一次大得多。
    const tagCount: number = parseTags(content).length;
    if (tagCount > MAX_TAG_COUNT) {
      toast(this.getUIContext(),
        `已记下；标签有点多（${tagCount} 个），建议不超过 ${MAX_TAG_COUNT} 个`);
    } else {
      toast(this.getUIContext(), '已记下');
    }
    return true;
  }

  private openDetail(row: TimelineRow): void {
    this.selectedId = row.ideaId;
    this.selectedContent = row.content;
    this.selectedCreatedAt = row.createdAt;
    this.selectedUpdatedAt = row.updatedAt;
    this.selectedPinned = row.pinned;
    this.detailVisible = true;
  }

  private async saveDetail(content: string): Promise<void> {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    const ok = await vm.updateContent(this.selectedId, content);
    if (ok) {
      this.detailVisible = false;
      toast(this.getUIContext(), '已保存');
    } else {
      toast(this.getUIContext(), '保存失败，请重试');
    }
  }

  private async togglePin(): Promise<void> {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    const next = !this.selectedPinned;
    const ok = await vm.setPinned(this.selectedId, next);
    if (ok) {
      this.selectedPinned = next;
      Haptics.tap();
      toast(this.getUIContext(), next ? '已置顶' : '已取消置顶');
    } else {
      toast(this.getUIContext(), '操作失败，请重试');
    }
  }

  private deleteDetail(): void {
    // 先收半模态再删：撤销条要出现在列表底部，被半模态盖住就白做了
    this.detailVisible = false;
    this.performDelete(this.selectedId);
  }

  /**
   * 删除分两层：这里只做软删除 + 5 秒撤销条，撤销条收起之后内容进「最近删除」再留 7 天。
   *
   * 所以这里不弹确认框 —— 一次误触的成本是「点一下撤销」，而不是永久丢内容；
   * 真正不可逆的「彻底删除」才在回收站里单独确认。
   */
  private async performDelete(id: number): Promise<void> {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    const ok = await vm.softDelete(id);
    if (!ok) {
      toast(this.getUIContext(), '删除失败，请重试');
      return;
    }
    this.undoIds = [id];
    this.undoVisible = true;
    this.startUndoTimer();
  }

  /** 撤销条标题：批量和单条共用，只换第一行文案 */
  private undoTitle(): string {
    return this.undoIds.length > 1 ? `已删除 ${this.undoIds.length} 条` : '已删除';
  }

  /**
   * 撤销：把这一批**整批**还回来。
   *
   * 逐条恢复而不是只恢复最后一条：批量删 10 条时点「撤销」，用户期望的是
   * 回到删之前的样子，不是只回来一条；个别失败要数出来，不能假装都成功了。
   */
  private async undoDelete(): Promise<void> {
    this.clearUndoTimer();
    this.undoVisible = false;
    const ids: number[] = this.undoIds.slice();
    this.undoIds = [];
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    let restored = 0;
    for (const id of ids) {
      if (await vm.restore(id)) {
        restored += 1;
      }
    }
    if (restored === 0) {
      toast(this.getUIContext(), '撤销失败，请重试');
    } else if (restored < ids.length) {
      toast(this.getUIContext(), `已恢复 ${restored} 条，其余失败`);
    } else {
      // 东西回来了，给个轻快确认（这一下是「失而复得」，比删除时更需要反馈）
      Haptics.tap();
    }
  }

  // ==========================================================================
  // 多选：批量导出 / 批量删除
  // ==========================================================================

  /** 顶栏标题：0 条时告诉用户这一层是干什么的，选中后给准确条数 */
  private selectionTitle(): string {
    return this.selectedIds.length > 0 ? `已选 ${this.selectedIds.length} 条` : '选择灵感';
  }

  /** 全选只覆盖**已加载**的部分：没滚到的行还在库里，但用户没看见，替 TA 勾上会莫名多导出 */
  private allLoadedSelected(): boolean {
    const vm = this.vm;
    if (vm === null) {
      return false;
    }
    const loaded = vm.loadedIdeaIds();
    return loaded.length > 0 && this.selectedIds.length === loaded.length;
  }

  private selectionEnabled(): boolean {
    return this.selectedIds.length > 0 && !this.selectionBusy;
  }

  private enterSelect(id: number): void {
    this.selecting = true;
    this.selectedIds = [id];
    // 撤销条与多选栏都占着底部同一条带子；进多选先收掉撤销条，避免两条并排
    this.clearUndoTimer();
    this.undoVisible = false;
    this.undoIds = [];
    Haptics.tap();
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  /** 重建数组而不是 push/splice：@State 对同一数组实例的原地改动不一定触发刷新 */
  private toggleSelected(id: number): void {
    const next: number[] = this.selectedIds.slice();
    const index = next.indexOf(id);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(id);
    }
    this.selectedIds = next;
  }

  private selectAllLoaded(): void {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    if (this.allLoadedSelected()) {
      this.selectedIds = [];
      return;
    }
    this.selectedIds = vm.loadedIdeaIds();
  }

  /**
   * 批量删除：一条一条走同一个软删除，失败的单独数出来。
   * 不弹确认 —— 撤销条会一次性把整批还回来（见 undoDelete），之后还有 7 天回收站。
   */
  private async deleteSelected(): Promise<void> {
    const vm = this.vm;
    if (vm === null) {
      return;
    }
    const ids: number[] = this.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    this.exitSelect();
    const deleted: number[] = [];
    for (const id of ids) {
      if (await vm.softDelete(id)) {
        deleted.push(id);
      }
    }
    if (deleted.length === 0) {
      toast(this.getUIContext(), '删除失败，请重试');
      return;
    }
    this.undoIds = deleted;
    this.undoVisible = true;
    this.startUndoTimer();
    Haptics.tap();
    if (deleted.length < ids.length) {
      toast(this.getUIContext(), `有 ${ids.length - deleted.length} 条没删掉，请重试`);
    }
  }

  /** 导出格式只有一个岔路口，用系统对话框问一句就够，不另做一层页面 */
  private chooseExportSelected(): void {
    const count = this.selectedIds.length;
    if (count === 0 || this.selectionBusy) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `导出所选 ${count} 条`,
      message: 'JSON 保留完整字段，可以再导入回来；Markdown 适合阅读与粘贴。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: 'JSON',
        action: (): void => {
          this.exportSelected('json');
        }
      },
      secondaryButton: {
        value: 'Markdown',
        action: (): void => {
          this.exportSelected('markdown');
        }
      }
    });
  }

  /**
   * 批量导出：内容先在内存里拼好再弹系统选择器（与 runExport 同一个理由）。
   * 取消选择器时**保留勾选**：多数时候是选错了路径，回来还要接着导。
   */
  private async exportSelected(kind: string): Promise<void> {
    const service = this.exportService;
    const context = this.abilityContext();
    if (service === null || context === null) {
      toast(this.getUIContext(), '本地存储不可用，导出不了');
      return;
    }
    if (this.selectionBusy) {
      return;
    }
    const ids: number[] = this.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    this.selectionBusy = true;
    try {
      const isJson = kind === 'json';
      const content = isJson ? await service.buildJsonFor(ids) : await service.buildMarkdownFor(ids);
      const name = ExportService.suggestedFileName(isJson ? 'json' : 'md', Date.now());
      const saved = await FileBridge.saveText(context, name, isJson ? '.json' : '.md', content);
      if (saved === null) {
        toast(this.getUIContext(), '已取消导出');
        return;
      }
      this.exitSelect();
      toast(this.getUIContext(), `已导出 ${saved}（${this.readableSize(utf8ByteLength(content))}）`);
      Logger.info(`多选导出完成：${kind}，${ids.length} 条，${utf8ByteLength(content)} 字节`);
    } catch (err) {
      const error = err as Error;
      Logger.error(`多选导出失败：${kind}｜${error.message}`);
      toast(this.getUIContext(), `导出失败：${error.message}`);
    } finally {
      this.selectionBusy = false;
    }
  }

  // ==========================================================================
  // 最近删除
  // ==========================================================================

  private openTrash(): void {
    this.trashVisible = true;
    this.loadTrash();
  }

  /**
   * 读最近删除列表。
   *
   * 先清一遍过期的再查：列表 SQL 本身也挡着过期行，这里顺手清是为了让
   * 「7 天后自动清理」不依赖用户恰好打开过面板 —— 每次打开、每次冷启动都会送走该走的行。
   */
  private async loadTrash(): Promise<void> {
    const repo = this.createRepository();
    if (repo === null) {
      this.trashLoading = false;
      this.trashError = '本地存储在初始化时出错了';
      return;
    }
    this.trashLoading = true;
    this.trashError = '';
    try {
      await repo.purgeExpired();
      this.trashItems = await repo.listDeleted();
    } catch (err) {
      const error = err as Error;
      this.trashError = error.message;
      Logger.error(`读取最近删除失败：${error.message}`);
    } finally {
      this.trashLoading = false;
    }
  }

  /** 从回收站恢复：先改库，再同时刷新面板与时间轴，两处看到的是同一份数据 */
  private async restoreFromTrash(id: number): Promise<void> {
    const repo = this.createRepository();
    if (repo === null) {
      toast(this.getUIContext(), '本地存储不可用');
      return;
    }
    try {
      await repo.setDeleted(id, false);
      await this.loadTrash();
      await this.reload();
      Haptics.tap();
      toast(this.getUIContext(), '已恢复');
    } catch (err) {
      const error = err as Error;
      Logger.error(`恢复灵感失败：${error.message}`);
      toast(this.getUIContext(), '恢复失败，请重试');
    }
  }

  /** 彻底删除是真正的不可逆动作，只有这里值得多一次确认 */
  private confirmDeleteForever(id: number): void {
    this.getUIContext().showAlertDialog({
      title: '彻底删除这条灵感？',
      message: '彻底删除后无法恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '彻底删除',
        fontColor: museDanger(this.isDarkMode),
        action: (): void => {
          this.deleteForever(id);
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  private async deleteForever(id: number): Promise<void> {
    const repo = this.createRepository();
    if (repo === null) {
      toast(this.getUIContext(), '本地存储不可用');
      return;
    }
    try {
      await repo.deleteForever(id);
      // 撤销条如果还停在这条上，把它剔出去：它已经不存在了，再点撤销只会失败
      if (this.undoIds.indexOf(id) >= 0) {
        const next: number[] = this.undoIds.slice();
        next.splice(next.indexOf(id), 1);
        this.undoIds = next;
        if (this.undoIds.length === 0) {
          this.clearUndoTimer();
          this.undoVisible = false;
        }
      }
      await this.loadTrash();
      toast(this.getUIContext(), '已彻底删除');
    } catch (err) {
      const error = err as Error;
      Logger.error(`彻底删除灵感失败：${error.message}`);
      toast(this.getUIContext(), '彻底删除失败，请重试');
    }
  }

  private confirmClearTrash(): void {
    const count = this.trashItems.length;
    if (count === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '清空最近删除？',
      message: `将彻底删除 ${count} 条灵感，无法恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '清空',
        fontColor: museDanger(this.isDarkMode),
        action: (): void => {
          this.clearTrash();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  private async clearTrash(): Promise<void> {
    const repo = this.createRepository();
    if (repo === null) {
      toast(this.getUIContext(), '本地存储不可用');
      return;
    }
    try {
      const removed = await repo.clearDeleted();
      await this.loadTrash();
      toast(this.getUIContext(), `已清空 ${removed} 条`);
    } catch (err) {
      const error = err as Error;
      Logger.error(`清空最近删除失败：${error.message}`);
      toast(this.getUIContext(), '清空失败，请重试');
    }
  }

  /**
   * 启动撤销倒计时（单条删除与批量删除共用，倒的是同一批 `undoIds`）。
   * 到点只收起撤销条，行仍是软删除：它已经在「最近删除」里排着了，
   * 7 天后才由清理逻辑真正送走 —— 一次误触可以连撤两次（5 秒内点撤销，或之后去回收站找回）。
   */
  private startUndoTimer(): void {
    this.clearUndoTimer();
    this.undoTimerId = setTimeout(() => {
      this.undoVisible = false;
      this.undoTimerId = -1;
    }, UNDO_WINDOW_MS);
  }

  private clearUndoTimer(): void {
    if (this.undoTimerId !== -1) {
      clearTimeout(this.undoTimerId);
      this.undoTimerId = -1;
    }
  }

  private accentOrPrimary(): string {
    return this.accentColor.length > 0 ? this.accentColor : DEFAULT_ACCENT_VALUE;
  }

  /** 撤销条的底色：跟着主题色走，既醒目又不引入第二套配色 */
  private snackColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary());
  }

  /**
   * 实底按钮的底色（与 `snackColor()` 同源）。
   *
   * 单独开一个方法是为了让**字色永远按真实底色算**：`onAccentColor()` 判断的是亮度，
   * 而深色模式下 `resolvePrimaryButtonColor` 会把主题色压暗（`DARK_BUTTON_DEEPEN`），
   * 若拿**原始主题色**去判黑/白字，浅色主题（例如自定义亮黄）在深色模式下会得到
   * 「黑字 + 压暗后的底」——对比度不够，看着像没生效。
   */
  private filledButtonColor(): string {
    return resolvePrimaryButtonColor(this.isDarkMode, this.accentOrPrimary());
  }
}
