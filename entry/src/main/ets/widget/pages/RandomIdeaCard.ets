import { DEFAULT_ACCENT_VALUE, withAlpha } from '../../utils/DesignTokens';

let randomCardStorage: LocalStorage = new LocalStorage();

/**
 * 服务卡片「灵光再现」（2×2）。
 *
 * 交互分工（**两块可点区域在结构上是分开的，不是嵌套的**）：
 *   - 上半部分 → `action: 'router'` 拉起 App 并带上 `action=review`，首页会直接弹「灵光再现」
 *   - 「换一条」→ `action: 'message'`，扩展收到后换一条随机灵感再推回来（不打开 App）
 *
 * 为什么不把按钮嵌在可点区域里：ArkUI 的 `ClickEvent` **没有** `stopPropagation`
 * （M2 的标签 chip 上踩过：点 chip 会连带卡片一起响应），只能靠结构隔离。
 *
 * **颜色怎么来的（M5 返工第二版，很重要）**：
 *   - 底色与文字色用**资源**：`base/element/color.json` 与 `dark/element/color.json` 各一份，
 *     系统切深浅时由框架直接换掉，**不需要 App 或扩展进程活着**。
 *   - 主题色只以「半透明叠加」的形式出现（淡染底、下划线、按钮描边/浅底），
 *     不与「深浅」耦合，因此不必在这里判断当前是深是浅。
 *
 * 为什么不像上一版那样「由扩展算好色值再推」：色值是快照，系统切深色换不动写死的十六进制值，
 * 而 `FormExtensionAbility.onConfigurationUpdate` 只在扩展进程存活时回调 —— 真机实测用户切系统深色时
 * 进程早已被回收，两张卡片停在旧色。另外卡片是 form 应用，`Environment`/`ColorMode`/`@StorageProp`
 * 都被编译器禁止（`11706006 can't support form application`），能自动跟随系统的只有资源。
 */
@Entry(randomCardStorage)
@Component
struct RandomIdeaCard {
  @LocalStorageProp('randomContent') content: string = '';
  @LocalStorageProp('randomMeta') meta: string = '';
  @LocalStorageProp('randomTags') tags: string = '';
  @LocalStorageProp('randomEmpty') empty: boolean = true;
  @LocalStorageProp('accent') accentRaw: string = DEFAULT_ACCENT_VALUE;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.card_surface'))

      // 主题色淡染：一层低透明度主题色盖在中性底色上，浅色/深色两种底色下都成立
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.tintColor())

      Column() {
        Column() {
          Row() {
            Text('灵光再现')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.card_text'))
            Blank()
            Text(this.empty ? '' : this.meta)
              .fontSize(10)
              .fontColor($r('app.color.card_text_soft'))
          }
          .width('100%')

          // 标题下一条主题色短线：卡片的「这是灵感菇」信号，比 emoji 稳
          Row()
            .width(18)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.accentColor())
            .margin({ top: 4 })

          if (this.empty) {
            Text('还没有灵感，来记一条')
              .fontSize(12)
              .fontColor($r('app.color.card_text_soft'))
              .margin({ top: 8 })
          } else {
            if (this.content.length > 0) {
              Text(this.content)
                .fontSize(13)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor($r('app.color.card_text'))
                .margin({ top: 6 })
            }
            if (this.tags.length > 0) {
              Text(this.tags)
                .fontSize(10)
                .fontColor($r('app.color.card_text_soft'))
                .margin({ top: 4 })
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { action: 'review' }
          });
        })

        Row() {
          Blank()
          // 次操作走描边而不是浅底：浅底在深色下和卡片底色几乎同色，会被看成「禁用」
          Text('换一条')
            .fontSize(11)
            .fontColor($r('app.color.card_text'))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(11)
            .borderWidth(1)
            .borderColor(this.accentEdgeColor())
            .onClick(() => {
              postCardAction(this, {
                action: 'message',
                params: { event: 'shuffle' }
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
  }

  private accent(): string {
    return this.accentRaw.length > 0 ? this.accentRaw : DEFAULT_ACCENT_VALUE;
  }

  /** 淡染底：10% 主题色，浅色下是淡彩、深色下是暗彩，都靠同一层半透明实现 */
  private tintColor(): string {
    return withAlpha(this.accent(), 0.1);
  }

  private accentColor(): string {
    return this.accent();
  }

  /** 描边色：70% 主题色（叫 `accentEdgeColor` 而不是 `outlineColor`/`borderColor`，
   *  后两个是 ArkUI 组件基类已有的属性名，自定义同名方法会编译报「not assignable to base type」） */
  private accentEdgeColor(): string {
    return withAlpha(this.accent(), 0.7);
  }
}
