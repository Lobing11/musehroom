# 灵感菇（Musehroom）图标生成脚本
#
# 为什么用脚本画图标而不是塞两个 png 进来：
#   1. 可复现、可微调（改一个数字就能看效果，不用找人重画）；
#   2. 设计语言和应用内一致 —— 破土绿底 + 米白蘑菇 + 琥珀色星光，色值直接抄 DesignTokens；
#   3. 分层图标（layered_image）本来就是「背景层 + 前景层」两张图，脚本一次生成成套资源。
#
# 用法：pwsh -File tools/gen-icons.ps1
# 产出：
#   AppScope/resources/base/media/{background,foreground}.png   1024×1024  应用图标（分层，启动器用它）
#   entry/src/main/resources/base/media/{background,foreground}.png  同上（模块级副本，module.json5 也引用）
#   entry/src/main/resources/base/media/startIcon.png           144×144    启动窗口图标（48vp × 3 倍屏）
#   entry/src/main/resources/base/media/shortcut_capture.png    512×512    「记一条灵感」桌面快捷方式
#   entry/src/main/resources/base/media/shortcut_review.png     512×512    「灵光再现」桌面快捷方式
#   build/icon-preview.png                                      预览拼版（几个尺寸并排，肉眼验收用）
#
# 注意：全部用 GDI+ 画，抗锯齿打开；颜色一律走 sRGB 十六进制，别用命名色（命名色在不同机器上会跑偏）。

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ---------- 设计令牌（与 entry/src/main/ets/utils/DesignTokens.ets 保持同源） ----------
$GREEN = '#2E9E6B'   # 破土绿（主色）
$GREEN_DARK = '#1C7248'
$GREEN_LIGHT = '#48B783'
$CREAM = '#F7FBF8'
$MINT = '#DCEFE4'
$AMBER = '#EFC15C'

function Get-Color([string]$hex, [int]$alpha = 255) {
  $h = $hex.TrimStart('#')
  $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
  $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
  $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
  return [System.Drawing.Color]::FromArgb($alpha, $r, $g, $b)
}

function New-Canvas([int]$size, [bool]$opaque = $true) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  if (-not $opaque) { $g.Clear([System.Drawing.Color]::Transparent) }
  return @{ Bitmap = $bmp; Graphics = $g }
}

function New-RoundedPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

# 四角星（「灵光」）：四个尖角 + 内凹的边，靠贝塞尔控制点往中心收
function Add-Sparkle($path, [double]$cx, [double]$cy, [double]$radius, [double]$pinch = 0.26) {
  $tips = @(@(0.0, -1.0), @(1.0, 0.0), @(0.0, 1.0), @(-1.0, 0.0))
  for ($i = 0; $i -lt 4; $i++) {
    $a = $tips[$i]
    $b = $tips[($i + 1) % 4]
    $ax = $cx + $a[0] * $radius; $ay = $cy + $a[1] * $radius
    $bx = $cx + $b[0] * $radius; $by = $cy + $b[1] * $radius
    $px = $cx + ($a[0] + $b[0]) * $radius * $pinch * 0.5
    $py = $cy + ($a[1] + $b[1]) * $radius * $pinch * 0.5
    $path.AddBezier([single]$ax, [single]$ay, [single]$px, [single]$py, [single]$px, [single]$py, [single]$bx, [single]$by)
  }
  $path.CloseFigure()
}

function New-SparklePath([double]$cx, [double]$cy, [double]$radius, [double]$pinch = 0.26) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  Add-Sparkle $path $cx $cy $radius $pinch
  return $path
}

# ---------- 背景层：整块渐变 + 一团柔光（分层图标的 background） ----------
function Draw-IconBackground($g, [int]$size, [bool]$rounded = $false) {
  $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (Get-Color $GREEN_LIGHT), (Get-Color $GREEN_DARK), 90.0)
  if ($rounded) {
    $path = New-RoundedPath 0 0 $size $size ($size * 0.22)
    $g.FillPath($brush, $path)
    $path.Dispose()
  } else {
    $g.FillRectangle($brush, $rect)
  }
  $brush.Dispose()

  # 左上柔光：让平面色有一点体积，深色壁纸下也不发闷
  $glow = new-object System.Drawing.Drawing2D.GraphicsPath
  $glow.AddEllipse(($size * -0.15), ($size * -0.25), ($size * 1.0), ($size * 1.0))
  $gb = New-Object System.Drawing.SolidBrush (Get-Color '#FFFFFF' 26)
  $g.FillPath($gb, $glow)
  $gb.Dispose(); $glow.Dispose()
}

# ---------- 前景层：蘑菇 + 星光（分层图标的 foreground，背景透明） ----------
function Draw-Mushroom($g, [int]$size, [double]$scale = 1.0) {
  $c = $size / 2.0
  $g.TranslateTransform([single]$c, [single]$c)
  $g.ScaleTransform([single]$scale, [single]$scale)
  $g.TranslateTransform([single](-$c), [single](-$c))

  # 菌盖：半椭圆（下缘是直的）。宽而扁的伞形才像菇 —— 之前做成 0.52×0.40 时像顶帐篷。
  # 尺寸约束：分层图标的前景层内容占画布约 67%（量过 DevEco 模板 foreground.png 的内容边界
  # 是 1024 画布上的 160..848），所以蘑菇 + 星光都排进 0.16..0.85 这个安全区里。
  $capW = $size * 0.54
  $capH = $size * 0.28
  $capX = $c - $capW / 2.0
  $capBottom = $size * 0.58
  $capTop = $capBottom - $capH
  $cap = New-Object System.Drawing.Drawing2D.GraphicsPath
  $cap.AddArc([single]$capX, [single]$capTop, [single]$capW, [single]($capH * 2), 180, 180)
  $cap.AddLine([single]($capX + $capW), [single]$capBottom, [single]$capX, [single]$capBottom)
  $cap.CloseFigure()
  $capBrush = New-Object System.Drawing.SolidBrush (Get-Color $CREAM)
  $g.FillPath($capBrush, $cap)
  $capBrush.Dispose(); $cap.Dispose()

  # 菌盖上的斑点（破土绿 22%）：小尺寸下也要能看出是「菇」
  $spots = @(
    @(0.28, 0.42, 0.048),
    @(0.56, 0.26, 0.037),
    @(0.74, 0.48, 0.027)
  )
  $spotBrush = New-Object System.Drawing.SolidBrush (Get-Color $GREEN 56)
  foreach ($s in $spots) {
    $r = $size * $s[2]
    $x = $capX + $capW * $s[0] - $r
    $y = $capTop + $capH * $s[1] - $r
    $g.FillEllipse($spotBrush, [single]$x, [single]$y, [single]($r * 2), [single]($r * 2))
  }
  $spotBrush.Dispose()

  # 菌柄：圆角竖条，从菌盖下缘伸出来一截，收口用半圆
  $stemW = $size * 0.115
  $stemH = $size * 0.25
  $stemX = $c - $stemW / 2.0
  $stemY = $capBottom - $size * 0.01
  $stem = New-RoundedPath $stemX $stemY $stemW $stemH ($stemW * 0.48)
  $stemBrush = New-Object System.Drawing.SolidBrush (Get-Color $MINT)
  $g.FillPath($stemBrush, $stem)
  $stemBrush.Dispose(); $stem.Dispose()

  # 星光：琥珀色四角星 + 一颗小的，落在菌盖右上（灵感冒出来的位置）
  # 位置写绝对值而不是相对菌盖 —— 菌盖高度一改，相对坐标就会把星光顶出安全区
  $big = New-SparklePath ($size * 0.725) ($size * 0.345) ($size * 0.082) 0.24
  $b1 = New-Object System.Drawing.SolidBrush (Get-Color $AMBER)
  $g.FillPath($b1, $big)
  $b1.Dispose(); $big.Dispose()

  $small = New-SparklePath ($size * 0.805) ($size * 0.235) ($size * 0.038) 0.24
  $b2 = New-Object System.Drawing.SolidBrush (Get-Color $AMBER 220)
  $g.FillPath($b2, $small)
  $b2.Dispose(); $small.Dispose()

  $g.ResetTransform()
}

# ---------- 「记一条灵感」：斜放的笔 + 笔尖的星光 ----------
function Draw-CaptureGlyph($g, [int]$size) {
  $u = $size / 512.0
  $g.TranslateTransform([single]($size / 2.0), [single]($size / 2.0))
  $g.RotateTransform(-45)
  $white = New-Object System.Drawing.SolidBrush (Get-Color $CREAM)

  # 笔身（圆角长条）
  $body = New-RoundedPath (-45 * $u) (-162 * $u) (90 * $u) (270 * $u) (36 * $u)
  $g.FillPath($white, $body)
  $body.Dispose()

  # 笔尖（三角）
  $nib = New-Object System.Drawing.Drawing2D.GraphicsPath
  $nib.AddPolygon(@(
    (New-Object System.Drawing.PointF ([single](-45 * $u), [single](104 * $u))),
    (New-Object System.Drawing.PointF ([single](45 * $u), [single](104 * $u))),
    (New-Object System.Drawing.PointF ([single](0), [single](176 * $u)))
  ))
  $g.FillPath($white, $nib)
  $nib.Dispose()

  # 笔尖上的墨点（用底色打一个洞，笔尖就不会糊成一坨）
  $hole = New-Object System.Drawing.SolidBrush (Get-Color $GREEN 200)
  $g.FillEllipse($hole, [single](-14 * $u), [single](112 * $u), [single](28 * $u), [single](28 * $u))
  $hole.Dispose()
  $g.ResetTransform()

  # 右上星光：与「灵光再现」用同一套星光语言
  $spark = New-SparklePath ($size * 0.735) ($size * 0.265) ($size * 0.115) 0.24
  $sb = New-Object System.Drawing.SolidBrush (Get-Color $AMBER)
  $g.FillPath($sb, $spark)
  $sb.Dispose(); $spark.Dispose()
}

# ---------- 「灵光再现」：白色大星光 + 环绕的循环弧 ----------
function Draw-ReviewGlyph($g, [int]$size) {
  $u = $size / 512.0
  $cx = $size * 0.5
  $cy = $size * 0.52

  # 循环弧：留一个缺口 + 箭头，表示「再来一条 / 随机回顾」
  $ringR = 168 * $u
  $ringRect = New-Object System.Drawing.RectangleF ([single]($cx - $ringR)), ([single]($cy - $ringR)), ([single]($ringR * 2)), ([single]($ringR * 2))
  $pen = New-Object System.Drawing.Pen (Get-Color $MINT 210), ([single](22 * $u))
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawArc($pen, $ringRect, 160, 260)
  $pen.Dispose()

  # 箭头：必须沿圆弧末端的切线方向摆。之前用固定朝下的三角形，看着像一颗逗号。
  $endDeg = 60.0
  $rad = $endDeg * [Math]::PI / 180.0
  $ax = $cx + $ringR * [Math]::Cos($rad)
  $ay = $cy + $ringR * [Math]::Sin($rad)
  $tx = -[Math]::Sin($rad); $ty = [Math]::Cos($rad)   # 切线方向（GDI+ 角度顺时针）
  $nx = [Math]::Cos($rad); $ny = [Math]::Sin($rad)    # 径向
  $tipL = 30 * $u; $halfW = 21 * $u
  $arrow = New-Object System.Drawing.Drawing2D.GraphicsPath
  $arrow.AddPolygon(@(
    (New-Object System.Drawing.PointF ([single]($ax + $tx * $tipL), [single]($ay + $ty * $tipL))),
    (New-Object System.Drawing.PointF ([single]($ax - $nx * $halfW), [single]($ay - $ny * $halfW))),
    (New-Object System.Drawing.PointF ([single]($ax + $nx * $halfW), [single]($ay + $ny * $halfW)))
  ))
  $ab = New-Object System.Drawing.SolidBrush (Get-Color $MINT 210)
  $g.FillPath($ab, $arrow)
  $ab.Dispose(); $arrow.Dispose()

  # 中间的大星光
  $spark = New-SparklePath $cx $cy (108 * $u) 0.24
  $sb = New-Object System.Drawing.SolidBrush (Get-Color $CREAM)
  $g.FillPath($sb, $spark)
  $sb.Dispose(); $spark.Dispose()
}

# ---------- 组装与落盘 ----------
function Save-Png($bitmap, $graphics, [string]$path) {
  $graphics.Dispose()
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
}

function New-LayeredBackground([int]$size, [string]$path) {
  $c = New-Canvas $size $true
  Draw-IconBackground $c.Graphics $size $false
  Save-Png $c.Bitmap $c.Graphics $path
}

function New-LayeredForeground([int]$size, [string]$path) {
  $c = New-Canvas $size $false
  Draw-Mushroom $c.Graphics $size 1.0
  Save-Png $c.Bitmap $c.Graphics $path
}

function New-CompositeIcon([int]$size, [string]$path, [scriptblock]$glyph) {
  $c = New-Canvas $size $false
  $canvas2 = New-Canvas $size $false
  Draw-IconBackground $canvas2.Graphics $size $true
  $c.Graphics.DrawImage($canvas2.Bitmap, 0, 0, $size, $size)
  $canvas2.Bitmap.Dispose(); $canvas2.Graphics.Dispose()
  & $glyph $c.Graphics $size
  Save-Png $c.Bitmap $c.Graphics $path
}

$appDirs = @(
  (Join-Path $root 'AppScope/resources/base/media'),
  (Join-Path $root 'entry/src/main/resources/base/media')
)
foreach ($d in $appDirs) {
  New-LayeredBackground 1024 (Join-Path $d 'background.png')
  New-LayeredForeground 1024 (Join-Path $d 'foreground.png')
}

$entryMedia = Join-Path $root 'entry/src/main/resources/base/media'

# 启动窗口图标：48vp 图标 × 3 倍屏 = 144px（保持仓库里原有的尺寸，别让系统去做缩放）
$startCanvas = New-Canvas 144 $false
$startBg = New-Canvas 144 $false
Draw-IconBackground $startBg.Graphics 144 $true
$startCanvas.Graphics.DrawImage($startBg.Bitmap, 0, 0, 144, 144)
$startBg.Bitmap.Dispose(); $startBg.Graphics.Dispose()
Draw-Mushroom $startCanvas.Graphics 144 1.0
Save-Png $startCanvas.Bitmap $startCanvas.Graphics (Join-Path $entryMedia 'startIcon.png')

New-CompositeIcon 512 (Join-Path $entryMedia 'shortcut_capture.png') ${function:Draw-CaptureGlyph}
New-CompositeIcon 512 (Join-Path $entryMedia 'shortcut_review.png') ${function:Draw-ReviewGlyph}

# ---------- 自检：前景层内容必须落在安全区里，否则会被启动器的遮罩裁掉 ----------
function Measure-ContentBounds([string]$path, [int]$canvas = 1024) {
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $minX = $bmp.Width; $minY = $bmp.Height; $maxX = -1; $maxY = -1
  for ($y = 0; $y -lt $bmp.Height; $y += 4) {
    for ($x = 0; $x -lt $bmp.Width; $x += 4) {
      if ($bmp.GetPixel($x, $y).A -gt 8) {
        if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  $bmp.Dispose()
  return @{
    Left   = [math]::Round($minX / $canvas, 3); Top    = [math]::Round($minY / $canvas, 3)
    Right  = [math]::Round($maxX / $canvas, 3); Bottom = [math]::Round($maxY / $canvas, 3)
  }
}

$fg = Measure-ContentBounds (Join-Path $entryMedia 'foreground.png')
Write-Output "前景层内容边界（占画布）：x $($fg.Left)..$($fg.Right)  y $($fg.Top)..$($fg.Bottom)"
if ($fg.Left -ge 0.15 -and $fg.Top -ge 0.15 -and $fg.Right -le 0.86 -and $fg.Bottom -le 0.86) {
  Write-Output '  ✓ 落在安全区内（DevEco 模板实测是 0.16..0.85）'
} else {
  Write-Output '  ✗ 有内容伸到安全区外，启动器遮罩会裁掉'
}

# ---------- 预览拼版（验收用，不进 HAP） ----------
$sheetW = 1180; $sheetH = 620
$sheet = New-Object System.Drawing.Bitmap $sheetW, $sheetH
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.Clear((Get-Color '#F4F6F4'))
$half = New-Object System.Drawing.SolidBrush (Get-Color '#1A211C')
$sg.FillRectangle($half, 590, 0, 590, $sheetH)
$half.Dispose()

$fx = [System.Drawing.Font]::new('Microsoft YaHei', 13)
$tf = New-Object System.Drawing.SolidBrush (Get-Color '#1B211D')
$tw = New-Object System.Drawing.SolidBrush (Get-Color '#E8EDE9')
$sg.DrawString('应用图标（分层合成）', $fx, $tf, 24, 18)
$sg.DrawString('记一条灵感', $fx, $tf, 24, 330)
$sg.DrawString('灵光再现', $fx, $tf, 244, 330)
$sg.DrawString('深色壁纸下的同一套图标', $fx, $tw, 614, 18)

$appFg = [System.Drawing.Image]::FromFile((Join-Path $root 'AppScope/resources/base/media/foreground.png'))
$appBg = [System.Drawing.Image]::FromFile((Join-Path $root 'AppScope/resources/base/media/background.png'))
$capture = [System.Drawing.Image]::FromFile((Join-Path $entryMedia 'shortcut_capture.png'))
$review = [System.Drawing.Image]::FromFile((Join-Path $entryMedia 'shortcut_review.png'))

# 合成应用图标（分层 → 一张图，仅预览用）
$comp = New-Object System.Drawing.Bitmap 256, 256
$cg = [System.Drawing.Graphics]::FromImage($comp)
$cg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$mask = New-RoundedPath 0 0 256 256 56
$cg.SetClip($mask)
$cg.DrawImage($appBg, 0, 0, 256, 256)
$cg.DrawImage($appFg, 0, 0, 256, 256)
$cg.ResetClip()
$cg.Dispose(); $mask.Dispose()

$sg.DrawImage($comp, 24, 52, 256, 256)
$sg.DrawImage($comp, 296, 92, 176, 176)
$sg.DrawImage($comp, 488, 152, 64, 64)
$sg.DrawImage($capture, 24, 366, 150, 150)
$sg.DrawImage($review, 244, 366, 150, 150)
$sg.DrawImage($comp, 614, 52, 256, 256)
$sg.DrawImage($comp, 886, 92, 176, 176)
$sg.DrawImage($capture, 614, 366, 150, 150)
$sg.DrawImage($review, 834, 366, 150, 150)
$sg.Dispose()

Save-Png $sheet $sg (Join-Path $root 'build/icon-preview.png')
$comp.Dispose()
$appFg.Dispose(); $appBg.Dispose(); $capture.Dispose(); $review.Dispose()

Write-Output '图标已生成：'
Get-ChildItem (Join-Path $root 'AppScope/resources/base/media'), $entryMedia -Include *.png -Recurse |
  Where-Object { $_.Name -match 'background|foreground|startIcon|shortcut_' } |
  ForEach-Object { "  $($_.FullName.Replace($root + '\', ''))  $($_.Length) B" }
Write-Output "  build/icon-preview.png（预览拼版）"
