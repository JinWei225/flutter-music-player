# Writes windows/runner/resources/app_icon.ico: the same tile make_icons.py
# draws for the other platforms (accent gradient, rounded corners, the
# graphic_eq glyph from Flutter's MaterialIcons font), without needing Python.
#
#   powershell -File packaging\make_icon_windows.ps1 [-Flutter C:\path\to\flutter]
#
# Keep ACCENT_* and GLYPH in step with make_icons.py.
param(
  [string]$Flutter = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$glyph = [char]0xF7BD                       # Icons.graphic_eq_rounded
$top = [System.Drawing.Color]::FromArgb(182, 129, 93)      # #B6815D
$bottom = [System.Drawing.Color]::FromArgb(129, 99, 78)    # #81634E
$sizes = 16, 24, 32, 48, 64, 128, 256

if (-not $Flutter) {
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($cmd) { $Flutter = Split-Path (Split-Path $cmd.Source) }
}
$fontFile = Join-Path $Flutter 'bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'
if (-not (Test-Path $fontFile)) { throw "MaterialIcons font not found at $fontFile (pass -Flutter)" }

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontFile)

function New-Tile([int]$size) {
  # Supersampled, then scaled down, so the corners and glyph stay clean.
  $scale = if ($size -le 128) { 4 } else { 2 }
  $s = $size * $scale
  $big = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'

  $r = [int]($s * 0.22)
  $d = $r * 2
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc(0, 0, $d, $d, 180, 90)
  $path.AddArc($s - $d, 0, $d, $d, 270, 90)
  $path.AddArc($s - $d, $s - $d, $d, $d, 0, 90)
  $path.AddArc(0, $s - $d, $d, $d, 90, 90)
  $path.CloseFigure()

  $rect = New-Object System.Drawing.Rectangle 0, 0, $s, $s
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90
  $g.FillPath($brush, $path)

  $font = New-Object System.Drawing.Font $fonts.Families[0], ([single]($s * 0.60)), ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $format = New-Object System.Drawing.StringFormat
  $format.Alignment = 'Center'
  $format.LineAlignment = 'Center'
  $g.DrawString([string]$glyph, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 0, $s, $s), $format)
  $g.Dispose()

  $out = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $og = [System.Drawing.Graphics]::FromImage($out)
  $og.InterpolationMode = 'HighQualityBicubic'
  $og.PixelOffsetMode = 'HighQuality'
  $og.DrawImage($big, 0, 0, $size, $size)
  $og.Dispose(); $big.Dispose()
  return $out
}

$pngs = foreach ($size in $sizes) {
  $bmp = New-Tile $size
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  if ($size -eq 256) { $bmp.Save((Join-Path $env:TEMP 'mewsic-icon-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
  $bmp.Dispose()
  , @{ Size = $size; Bytes = $ms.ToArray() }
}

# .ico: a header, one 16-byte entry per image, then the PNG data itself.
$dest = Join-Path (Split-Path $PSScriptRoot) 'windows\runner\resources\app_icon.ico'
$stream = [System.IO.File]::Create($dest)
$w = New-Object System.IO.BinaryWriter $stream
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
  $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32)
  $w.Write([uint32]$p.Bytes.Length); $w.Write([uint32]$offset)
  $offset += $p.Bytes.Length
}
foreach ($p in $pngs) { $w.Write($p.Bytes) }
$w.Dispose()
"wrote $dest ($($pngs.Count) sizes)"
