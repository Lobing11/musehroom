# Flatten the layered app icon into square PNGs for store submission.
#
# Why this exists: HarmonyOS ships the app icon as a LAYERED icon
# (`background.png` + `foreground.png` + `layered_image.json`, made by
# tools/gen-icons.ps1), but AGC asks for a single flat square image
# (PNG/WebP accepted). This script composites exactly what the launcher
# shows, so the store icon can never drift from the on-device icon.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\gen-store-icon.ps1
# Output: docs\store\app-icon-<size>.png
#
# ASCII-only on purpose (Windows PowerShell 5.1 mangles non-BOM UTF-8 scripts).

param(
    [string]$MediaDir = (Join-Path $PSScriptRoot '..\entry\src\main\resources\base\media'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\docs\store'),
    [int[]]$Sizes = @(1024, 512, 216, 144, 108)
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing

$bgPath = Join-Path $MediaDir 'background.png'
$fgPath = Join-Path $MediaDir 'foreground.png'
foreach ($p in @($bgPath, $fgPath)) {
    if (-not (Test-Path $p)) { throw "missing layered icon layer: $p" }
}

$bg = [System.Drawing.Image]::FromFile($bgPath)
$fg = [System.Drawing.Image]::FromFile($fgPath)
Write-Host ("layers: background {0}x{1}, foreground {2}x{3}" -f $bg.Width, $bg.Height, $fg.Width, $fg.Height)
if ($bg.Width -ne $fg.Width -or $bg.Height -ne $fg.Height) { throw 'layers must share the same canvas size' }

$size = $bg.Width
$icon = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($icon)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($bg, 0, 0, $size, $size)
$g.DrawImage($fg, 0, 0, $size, $size)
$g.Dispose()

# Stores usually want a full-bleed square; report (do not silently "fix") if
# the design leaves transparent corners, because that changes how it looks
# inside the store's own mask.
$corners = @(
    $icon.GetPixel(0, 0).A,
    $icon.GetPixel($size - 1, 0).A,
    $icon.GetPixel(0, $size - 1).A,
    $icon.GetPixel($size - 1, $size - 1).A
)
Write-Host ("corner alpha: {0}" -f ($corners -join ', '))
if (($corners | Where-Object { $_ -lt 255 }).Count -gt 0) {
    Write-Warning 'icon has transparent corners - check how it looks inside the store mask'
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

foreach ($s in $Sizes) {
    $out = Join-Path $OutDir ("app-icon-{0}.png" -f $s)
    if ($s -eq $size) {
        $icon.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    else {
        $small = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gs = [System.Drawing.Graphics]::FromImage($small)
        $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gs.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gs.DrawImage($icon, 0, 0, $s, $s)
        $gs.Dispose()
        $small.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $small.Dispose()
    }
    Write-Host ("wrote {0} ({1} B)" -f $out, (Get-Item $out).Length)
}

$icon.Dispose()
$bg.Dispose()
$fg.Dispose()
Write-Host 'store icon done'
