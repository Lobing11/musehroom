import { DEFAULT_ACCENT_VALUE, withAlpha } from '../../utils/DesignTokens';

let recentCardStorage: LocalStorage = new LocalStorage();

/**
 * 服务卡片「最近想到」（2×4）。
 *
 * 比 2×2 多一个按钮「记一条」：`action: 'router'` 带 `action=capture` 拉起 App，
 * 首页消费到这个意图会把焦点直接放进底部输入框（见 `Index.consumeLaunchAction`），
 * 用户点一下卡片就能开始打字 —— 这条链路和桌面快捷方式共用同一套深链。
 *
 * 版面：正文块 `layoutWeight(1)` 顶着上边，底部一行「统计 + 两个按钮」。
 * 上一版把按钮摆在右上、`共 N 条灵感` 钉在左下，正文只有一行时两者中间裂开一大块空白
 * （用户报的第二个观感病灶），现在两个按钮与统计同处一行，空白由正文块自然吃掉。
 *
 * 三块可点区域同样是**并列**而非嵌套（`ClickEvent` 不能阻止冒泡）。
 *
 * 颜色：底色/文字走资源（`base/` + `dark/` 两份，系统切深浅时框架直接换），
 * 主题色只以半透明叠加出现 —— 详细理由与踩过的坑见 `RandomIdeaCard.ets` 顶部注释。
 */
@Entry(recentCardStorage)
@Component
struct RecentIdeaCard {
  @LocalStorageProp('recentContent') content: string = '';
  @LocalStorageProp('recentMeta') meta: string = '';
  @LocalStorageProp('recentTags') tags: string = '';
  @LocalStorageProp('recentEmpty') empty: boolean = true;
  @LocalStorageProp('total') total: string = '';
  @LocalStorageProp('accent') accentRaw: string = DEFAULT_ACCENT_VALUE;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.card_surface'))

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.tintColor())

      Column() {
        Column() {
          Row() {
            Text('最近想到')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.card_text'))
            Blank()
            Text(this.empty ? '' : this.meta)
              .fontSize(10)
              .fontColor($r('app.color.card_text_soft'))
          }
          .width('100%')

          Row()
            .width(18)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.accentColor())
            .margin({ top: 4 })

          if (this.empty) {
            Text('还没有灵感，点下面「记一条」开始')
              .fontSize(12)
              .fontColor($r('app.color.card_text_soft'))
              .margin({ top: 8 })
          } else {
            if (this.content.length > 0) {
              Text(this.content)
                .fontSize(13)
                .maxLines(3)
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
          Text(this.total.length > 0 ? `共 ${this.total} 条灵感` : '')
            .fontSize(10)
            .fontColor($r('app.color.card_text_soft'))
          Blank()
          // 主操作：主题色半透明实底 + 资源里的文字色，深浅两头都读得清
          //（不用「不透明主题色 + 按亮度选黑白字」：那要在卡片里判断深浅，form 不给这个能力）
          Text('记一条')
            .fontSize(11)
            .fontColor($r('app.color.card_text'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(11)
            .backgroundColor(this.strongTintColor())
            .onClick(() => {
              postCardAction(this, {
                action: 'router',
                abilityName: 'EntryAbility',
                params: { action: 'capture' }
              });
            })
          // 次操作走描边而不是浅底：浅底在深色下和卡片底色几乎同色，会被看成「禁用」
          Text('换一条')
            .fontSize(11)
            .fontColor($r('app.color.card_text'))
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(11)
            .borderWidth(1)
            .borderColor(this.accentEdgeColor())
            .margin({ left: 8 })
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

  private tintColor(): string {
    return withAlpha(this.accent(), 0.1);
  }

  /** 主按钮的浅实底：22% 主题色，仍然透出底色，所以深浅都能自己适配 */
  private strongTintColor(): string {
    return withAlpha(this.accent(), 0.22);
  }

  private accentColor(): string {
    return this.accent();
  }

  /** 描边色：70% 主题色（不叫 `outlineColor`/`borderColor`：那是 ArkUI 组件基类已有的属性名） */
  private accentEdgeColor(): string {
    return withAlpha(this.accent(), 0.7);
  }
}
