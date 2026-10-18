# Turn the raw device screenshots (1272x2860, ~9:20) into AGC-compliant
# 1080x1920 (9:16) store screenshots.
#
# Why fit-and-pad instead of crop: AGC wants 9:16, our device is 9:20, so a
# plain centre-crop would have to throw away ~600 px of a 2860 px screenshot --
# that lands in the middle of the UI (header or capture bar) and the result
# reads as "cut off". So we strip the system chrome (status bar + gesture bar),
# scale the app area to fit 1920 px high, and fill the side gutters with the
# page background colour sampled from the screenshot itself: the app area keeps
# its real proportions and the padding is invisible against the flat page bg.
#
# Usage: powershell -ExecutionPolicy Bypass -File tools\gen-store-shots.ps1
# Input:  docs\store\shot-*.png        (originals are never modified)
# Output: docs\store\9x16\shot-*-1080x1920.png
#
# ASCII-only on purpose (Windows PowerShell 5.1 mangles non-BOM UTF-8 scripts).

param(
    [string]$InDir = (Join-Path $PSScriptRoot '..\docs\store'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\docs\store\9x16'),
    [int]$CropTop = 150,
    [int]$CropBottom = 150,
    [int]$TargetW = 1080,
    [int]$TargetH = 1920
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$shots = Get-ChildItem (Join-Path $InDir 'shot-*.png') -File | Sort-Object Name
if ($shots.Count -eq 0) { throw "no shot-*.png found in $InDir" }

foreach ($shot in $shots) {
    $src = [System.Drawing.Image]::FromFile($shot.FullName)
    $cropH = $src.Height - $CropTop - $CropBottom
    if ($cropH -le 0) { throw "bad crop for $($shot.Name)" }

    # sample the page background: median-ish colour of the left edge of the crop
    $samples = @()
    foreach ($y in 10, 60, 120, ($cropH - 120), ($cropH - 60), ($cropH - 10)) {
        $samples += $src.GetPixel(2, $CropTop + $y)
    }
    $bgR = [int](($samples | ForEach-Object { $_.R } | Measure-Object -Average).Average)
    $bgG = [int](($samples | ForEach-Object { $_.G } | Measure-Object -Average).Average)
    $bgB = [int](($samples | ForEach-Object { $_.B } | Measure-Object -Average).Average)

    # app area scaled to fit the target height
    $scale = [double]$TargetH / $cropH
    $drawW = [int][Math]::Round($src.Width * $scale)
    if ($drawW -gt $TargetW) {
        $scale = [double]$TargetW / $src.Width
        $drawW = $TargetW
        $drawH = [int][Math]::Round($cropH * $scale)
    }
    else {
        $drawH = $TargetH
    }

    $canvas = New-Object System.Drawing.Bitmap($TargetW, $TargetH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.Color]::FromArgb(255, $bgR, $bgG, $bgB))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $destRect = New-Object System.Drawing.Rectangle(([int](($TargetW - $drawW) / 2)), ([int](($TargetH - $drawH) / 2)), $drawW, $drawH)
    $srcRect = New-Object System.Drawing.Rectangle(0, $CropTop, $src.Width, $cropH)
    $g.DrawImage($src, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()

    $out = Join-Path $OutDir ($shot.BaseName + '-1080x1920.png')
    $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("{0} -> {1}  app {2}x{3}  gutter {4}px  bg #{5:X2}{6:X2}{7:X2}  {8} B" -f `
        $shot.Name, (Split-Path $out -Leaf), $drawW, $drawH, [int](($TargetW - $drawW) / 2), $bgR, $bgG, $bgB, (Get-Item $out).Length)

    $canvas.Dispose()
    $src.Dispose()
}
Write-Host 'store screenshots done'
