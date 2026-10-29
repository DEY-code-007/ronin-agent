# Draws RONIN's icon (purple ring + "R") and writes ronin.png (favicon) and ronin.ico (shortcuts).
# Run with Windows PowerShell 5.1:  powershell -NoProfile -File make_icon.ps1
Add-Type -AssemblyName System.Drawing
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$size = 256
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([System.Drawing.Color]::Transparent)

$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 0, $size, $size), ([System.Drawing.Color]::FromArgb(255, 46, 16, 101)), ([System.Drawing.Color]::FromArgb(255, 12, 4, 30)), 45
$g.FillEllipse($bg, 8, 8, $size - 16, $size - 16)
$ring = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 168, 85, 247)), 14
$g.DrawEllipse($ring, 18, 18, $size - 36, $size - 36)

$font = New-Object System.Drawing.Font 'Segoe UI', 120, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
$txt = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 233, 213, 255))
$g.DrawString('R', $font, $txt, (New-Object System.Drawing.RectangleF 0, 6, $size, $size), $fmt)
$g.Dispose()

$pngPath = Join-Path $dir 'ronin.png'
$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# ICO = 6-byte header + one 16-byte directory entry + the PNG bytes (PNG-in-ICO, Vista and later).
$png = [System.IO.File]::ReadAllBytes($pngPath)
$ms = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $ms
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]1)
$w.Write([Byte]0); $w.Write([Byte]0); $w.Write([Byte]0); $w.Write([Byte]0)  # 256x256, no palette
$w.Write([UInt16]1); $w.Write([UInt16]32)
$w.Write([UInt32]$png.Length); $w.Write([UInt32]22)
$w.Write($png)
[System.IO.File]::WriteAllBytes((Join-Path $dir 'ronin.ico'), $ms.ToArray())
Write-Output "icon ok"
