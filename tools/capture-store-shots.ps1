# 灵感菇 · 上架截图抓取脚本（Windows / PowerShell）
#
# 为什么要有这个脚本：应用内截图必须用**真机 + 真实数据**拍，而真机锁屏时
# `aa start` 会直接失败（Error Code:10106102 The device screen is locked during the
# application launch, unlock screen failed），开发者模式下不能自动解锁。
# 所以流程是：你先解锁手机并停在桌面 → 跑这个脚本 → 5 张图落到 docs/store/。
#
# 用法：
#   pwsh -File tools/capture-store-shots.ps1                # 抓全部 5 张
#   pwsh -File tools/capture-store-shots.ps1 -Only 3        # 只抓第 3 张（调试用）
#   pwsh -File tools/capture-store-shots.ps1 -IncludeCards  # 额外抓桌面卡片（需已添加卡片）
#
# 坐标说明：屏幕 1272×2860；下面所有坐标都是**真实坐标**，来自真机实测。
# 头部四个入口：✨灵光再现 (775,238)、📊记录足迹 (889,238)、🔍搜索 (1007,238)、⚙️设置 (1155,238)。
# 记下来的教训：半模态里的按钮会随正文行数上下移动，别把某一次的坐标当成通用值。

param(
  [int]$Only = 0,
  [switch]$IncludeCards,
  [string]$OutDir = "docs/store"
)

$ErrorActionPreference = "Stop"
$hdc = "D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$bundle = "com.lobing.musehroom"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root $OutDir

if (-not (Test-Path $hdc)) { throw "找不到 hdc：$hdc" }
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out | Out-Null }

function Shot([string]$name) {
  $remote = "/data/local/tmp/$name.png"
  & $hdc shell "uitest screenCap -p $remote" | Out-Null
  & $hdc file recv $remote (Join-Path $out "$name.png") | Select-Object -Last 1
}

function Tap([int]$x, [int]$y, [int]$sleepMs = 1200) {
  & $hdc shell "uitest uiInput click $x $y" | Out-Null
  Start-Sleep -Milliseconds $sleepMs
}

function TypeText([int]$x, [int]$y, [string]$text) {
  & $hdc shell "uitest uiInput inputText $x $y $text" | Out-Null
  Start-Sleep -Milliseconds 800
}

function AssertUnlocked() {
  $r = & $hdc shell "aa start -a EntryAbility -b $bundle -m entry" 2>&1
  if ($r -match "10106102") {
    throw "设备处于锁屏状态，无法启动应用。请先解锁手机（开发者模式不支持自动解锁），然后重跑。"
  }
  Start-Sleep -Seconds 4
}

Write-Output "== 设备检查 =="
& $hdc shell "pidof $bundle" | Out-Null
AssertUnlocked

if ($Only -eq 0) {
  # ① 首页时间轴：直接用启动后的首屏
  Write-Output "① 首页时间轴"
  Start-Sleep -Seconds 2
  Shot "shot-1-timeline"

  # ② 记录栏 + 标签实时预览：只打字不保存，不会往库里写东西
  Write-Output "② 记录栏与标签预览"
  Tap 500 2600 800           # 点底部记录栏
  TypeText 500 2600 "读书笔记：把「先捕捉、再整理」做成三秒能完成的事 #产品 #方法"
  Start-Sleep -Seconds 1
  Shot "shot-2-capture-tags"

  # 清掉草稿（长按删除不可靠，直接杀进程重启，草稿不会入库）
  & $hdc shell "aa force-stop $bundle" | Out-Null
  AssertUnlocked
  Start-Sleep -Seconds 2

  # ③ 搜索命中高亮：输入关键词 → 等 300ms 防抖 → 截图；✕ 清空
  Write-Output "③ 搜索命中高亮"
  Tap 1007 238 1500          # 🔍
  TypeText 500 560 "读书"
  Start-Sleep -Seconds 2
  Shot "shot-3-search-hit"
  Tap 1150 560 800           # ✕ 清空搜索词（右上角）
}

if ($Only -eq 0 -or $Only -eq 4) {
  # ④ 灵光再现面板
  Write-Output "④ 灵光再现"
  Tap 1007 238 800           # 先收起搜索框（有词时收起会一并清词）
  Tap 775 238 1500           # ✨
  Shot "shot-4-review"
  & $hdc shell "uitest uiInput keyEvent Back" | Out-Null
  Start-Sleep -Milliseconds 800
}

if ($Only -eq 0 -or $Only -eq 5) {
  # ⑤ 记录足迹（热力图 + 标签云）
  Write-Output "⑤ 记录足迹"
  Tap 889 238 2500           # 📊
  Shot "shot-5-stats"
  & $hdc shell "uitest uiInput keyEvent Back" | Out-Null
  Start-Sleep -Milliseconds 800
}

if ($IncludeCards) {
  # 桌面卡片：需要用户已经手动添加过（命令行加不了卡片）
  Write-Output "⑥ 桌面卡片"
  & $hdc shell "uitest uiInput keyEvent Home" | Out-Null
  Start-Sleep -Seconds 2
  for ($page = 1; $page -le 6; $page++) {
    Shot "shot-6-cards-page$page"
    & $hdc shell "uitest uiInput swipe 1000 1500 200 1500 200" | Out-Null
    Start-Sleep -Milliseconds 900
  }
  Write-Output "   六页都拍了，挑有卡片的那张改名成 shot-6-cards.png，其余删掉"
}

Write-Output "== 完成，图片在 $out =="
Write-Output "挑图建议：确认界面已是 M5 返工后的形态（卡片有主题色标题与短线、正文不带 #标签）"
