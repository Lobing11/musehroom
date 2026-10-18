# 参与贡献

感谢你愿意改进灵感菇。这个项目刻意保持小：一个页面、一个数据库、没有网络层。提交改动前请先看一眼下面几条。

## 环境

- DevEco Studio 6.x，HarmonyOS SDK 6.1.1 (API 24)
- Stage 模型 + ArkTS（`strictMode` 已开）

## 本地跑起来

1. DevEco Studio 打开仓库。
2. `File → Project Structure → Signing Configs` 勾选自动签名（本机生成，勿提交）。
3. 连接真机 / 模拟器运行，或 `hvigorw assembleHap --no-daemon`。

## 代码约定

- **不要提交**：`build-profile.json5` 里的 `signingConfigs`、任何 `*.p12` / `*.cer` / `*.p7b` / 密码文件、本机绝对路径、设备序列号。已经写进 `.gitignore`，提交前仍请 `git diff` 自查。
- `build-profile.json5` 保持 **纯 ASCII**（Windows 控制台的 GBK 读写会破坏中文注释）。
- 数据层改动要带迁移：`RdbHelper.migrate()` 里按 `if (from < N)` 追加分支，不改已有建表语句。
- 纯逻辑（解析、日期、保留期、字节数）放 `entry/src/main/ets/utils/`，并在 `entry/src/test/List.test.ets` 注册单测；单测不碰 RDB / preferences / ArkUI。
- 新增系统符号用 `sys.symbol.*`，不要在界面里塞 emoji。
- 删除相关交互沿用现有约定：普通删除不弹确认（5 秒撤销 + 最近删除兜底），只有彻底删除 / 清空才确认。

## 提交与 PR

- 一个改动一个提交，信息写清「为什么」而不只是「改了什么」。
- PR 里附上真机截图或录屏（涉及 UI 时），并说明验证过的路径。
- 不引入新依赖前先开 issue 说明理由；这个项目希望保持零第三方运行时依赖。

## 报告问题

请附上：HarmonyOS 版本、设备型号、复现步骤、期望与实际结果。不要贴出签名材料或带个人信息的导出文件。
