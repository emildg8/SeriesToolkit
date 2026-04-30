$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$assets = Join-Path $PSScriptRoot 'assets'
if (-not (Test-Path -LiteralPath $assets)) {
    New-Item -ItemType Directory -Path $assets -Force | Out-Null
}

$outPng = Join-Path $assets 'SeriesToolkit.icon.png'
$outIco = Join-Path $assets 'SeriesToolkit.icon.ico'

$bmp = New-Object System.Drawing.Bitmap 256, 256
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'

$bgRect = New-Object System.Drawing.Rectangle 0, 0, 255, 255
$bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(28, 67, 145))
$g.FillRectangle($bgBrush, $bgRect)

$folderBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(244, 248, 255))
$g.FillRectangle($folderBrush, 42, 92, 172, 112)
$g.FillRectangle($folderBrush, 42, 72, 78, 28)

$filmPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(28, 67, 145), 8)
$g.DrawRectangle($filmPen, 76, 114, 104, 66)
for ($i = 0; $i -lt 4; $i++) {
    $x = 84 + ($i * 24)
    $g.DrawLine($filmPen, $x, 114, $x, 180)
}

$checkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(0, 214, 186), 16)
$pts = [System.Drawing.Point[]]@(
    (New-Object System.Drawing.Point(150, 188)),
    (New-Object System.Drawing.Point(178, 214)),
    (New-Object System.Drawing.Point(224, 166))
)
$g.DrawLines($checkPen, $pts)

$bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fs = [System.IO.File]::Open($outIco, [System.IO.FileMode]::Create)
$icon.Save($fs)
$fs.Close()

$g.Dispose()
$bmp.Dispose()
[System.Runtime.InteropServices.Marshal]::Release($hIcon) | Out-Null

Write-Host "Icon generated: $outIco"
