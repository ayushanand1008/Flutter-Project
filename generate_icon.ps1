Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap 512, 512
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Make background completely transparent
$g.Clear([System.Drawing.Color]::Transparent)

# Calculator Body Outline
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 24)
$pen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Center
$g.DrawRectangle($pen, 100, 60, 312, 392)

# Solid White Brush for interior shapes
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

# Screen
$g.FillRectangle($brush, 140, 100, 232, 80)

# Buttons Row 1
$g.FillRectangle($brush, 140, 220, 60, 60)
$g.FillRectangle($brush, 226, 220, 60, 60)
$g.FillRectangle($brush, 312, 220, 60, 60)

# Buttons Row 2
$g.FillRectangle($brush, 140, 306, 60, 60)
$g.FillRectangle($brush, 226, 306, 60, 60)
$g.FillRectangle($brush, 312, 306, 60, 60)

# Save the final transparent PNG
$bmp.Save("d:\test_proto\assets\calculator_foreground.png", [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()
