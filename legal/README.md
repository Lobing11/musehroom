# 隐私政策静态页

`index.html` 是**单文件、零依赖**的隐私政策页面：自带样式、跟随系统深浅色、手机端优先、**没有脚本 / 没有外链 / 没有统计代码**（隐私政策页本身也不该埋统计）。

正文与 `docs/PRIVACY_POLICY.md` 一致 —— 那份是**源文件**，改内容时两边都要改（含页面顶部「生效日期」）。

> 为什么要这页：应用市场（AGC）要求填一个**可公开访问的隐私政策 URL**，且审核会真的点开看。

## 当前发布位置

已发布在独立公开仓库 `Lobing11/musehroom-legal`，线上地址：

**<https://lobing11.github.io/musehroom-legal/>**

改文案的流程：改 `docs/PRIVACY_POLICY.md` 与 `legal/index.html` → 把 `legal/index.html` 复制到那个小仓 → commit → push（URL 不变，Pages 会自动重建）。

> 也可以把本页放到本仓库的 `docs/legal/` 并用 GitHub Pages 的 `/docs` 目录发布；代价是 `docs/` 下的其他文件也会一并公开，本仓库目前已按此结构组织，可自行取舍。

## 发布之后

1. **用手机流量**（别只在 PC 或内网）打开该 URL，确认能打开、中文不乱码、深浅色下都看得清。
2. AppGallery Connect 的「隐私政策 URL」填同一条 URL。
3. 条款有变时同步改 `docs/PRIVACY_POLICY.md` 与 `legal/index.html`（含顶部生效日期），重新发布同一路径。
4. 第 9 条「联系方式」目前写的是「通过应用市场页面的开发者联系方式」；若想放具体邮箱，两处一起改。
