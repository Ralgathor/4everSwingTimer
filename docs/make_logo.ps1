$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# In-game default flat palette "Silver, Blue, Violet" (Bars.lua FLAT_PALETTES.silver)
$fillColors = @(
    @(235, 235, 242),   # mainhand 0.92 0.92 0.95
    @(92, 153, 255),    # offhand  0.36 0.60 1.00
    @(179, 102, 230)    # ranged   0.70 0.40 0.90
)
$progs = @(0.78, 0.46, 0.22)
$labels = @("Main Hand", "Off Hand", "Ranged")
$times = @("1.1", "0.7", "1.8")

# Two-tone wordmark: the "4" in WoW gold (NORMAL_FONT_COLOR 1.00 0.82 0.20),
# "ever" in highlight white - the trademark reads even at tile sizes. With
# $targetWidth > 0 the type scales so the mark spans exactly that width
# (aligned to the bar edges) instead of a fixed point size.
function Draw-Wordmark([System.Drawing.Graphics]$g, [double]$fontSize, [double]$rectY, [bool]$withShadow, [double]$targetWidth) {
    # GenericTypographic metrics: no layout padding, so "4" and "ever" join
    # with no gap and the two measured widths sum to the real mark width.
    $fmt = New-Object System.Drawing.StringFormat([System.Drawing.StringFormat]::GenericTypographic)
    $fmt.Alignment = [System.Drawing.StringAlignment]::Near
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $origin = New-Object System.Drawing.PointF(0.0, 0.0)
    $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $w4 = $g.MeasureString("4", $font, $origin, $fmt).Width
    $wEver = $g.MeasureString("ever", $font, $origin, $fmt).Width

    if ($targetWidth -gt 0) {
        # Scale the point size so the mark spans the bars' exact width
        $fontSize = $fontSize * ($targetWidth / ($w4 + $wEver))
        $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $w4 = $g.MeasureString("4", $font, $origin, $fmt).Width
        $wEver = $g.MeasureString("ever", $font, $origin, $fmt).Width
        $startX = 80.0
    } else {
        $startX = (512.0 - $w4 - $wEver) / 2.0
    }
    $rectH = $fontSize * 1.4

    if ($withShadow) {
        $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
        $s4 = New-Object System.Drawing.RectangleF(($startX + 3.0), ($rectY + 3.0), $w4, $rectH)
        $sE = New-Object System.Drawing.RectangleF(($startX + $w4 + 3.0), ($rectY + 3.0), $wEver, $rectH)
        $g.DrawString("4", $font, $shadowBrush, $s4, $fmt)
        $g.DrawString("ever", $font, $shadowBrush, $sE, $fmt)
    }

    $goldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 209, 51))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 242, 245, 250))
    $r4 = New-Object System.Drawing.RectangleF($startX, $rectY, $w4, $rectH)
    $rE = New-Object System.Drawing.RectangleF(($startX + $w4), $rectY, $wEver, $rectH)
    $g.DrawString("4", $font, $goldBrush, $r4, $fmt)
    $g.DrawString("ever", $font, $whiteBrush, $rE, $fmt)
}

function Draw-Logo([System.Drawing.Graphics]$g, [string]$mode) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Background: rounded square, subtle radial glow
    $bgPath = New-RoundPath 0 0 512 512 112
    $bgBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($bgPath)
    $bgBrush.CenterColor = [System.Drawing.Color]::FromArgb(255, 44, 51, 69)
    $bgBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 16, 19, 26))
    $bgBrush.CenterPoint = New-Object System.Drawing.PointF(256.0, 180.0)
    $g.FillPath($bgBrush, $bgPath)
    $g.SetClip($bgPath)

    $barX = 80.0
    $barW = 352.0
    $barH = 56.0
    $barGap = 32.0

    if ($mode -eq "full") {
        $ys = @(118.0, 206.0, 294.0)
        $wordmarkRectY = 366.0
    } else {
        # Icon: trademark spanning the bars' width. The gap between the mark
        # and the first bar equals the inter-bar gap, group centered.
        $fmtTypo = New-Object System.Drawing.StringFormat([System.Drawing.StringFormat]::GenericTypographic)
        $origin = New-Object System.Drawing.PointF(0.0, 0.0)
        $probeFont = New-Object System.Drawing.Font("Segoe UI", 100.0, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $pw4 = $g.MeasureString("4", $probeFont, $origin, $fmtTypo).Width
        $pwEver = $g.MeasureString("ever", $probeFont, $origin, $fmtTypo).Width
        $fs = 100.0 * $barW / ($pw4 + $pwEver)
        $cap = 0.716 * $fs          # Segoe UI cap height (1467/2048 em)
        $rectH2 = 1.4 * $fs
        $markGap = 48.0             # wordmark-to-bar gap (wider than the 32 px bar gap)
        $groupH = $cap + $markGap + (3 * $barH + 2 * $barGap)
        $glyphTop = (512.0 - $groupH) / 2.0
        $wordmarkRectY = $glyphTop - ($rectH2 - $cap) / 2.0
        $bar0 = $glyphTop + $cap + $markGap
        $ys = @($bar0, ($bar0 + $barH + $barGap), ($bar0 + 2 * ($barH + $barGap)))
    }
    $inset = 5.0
    $fillR = 9.0
    $pipW = 12.0
    $glowR = 20.0

    $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 52, 60, 77))
    $trackPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 74, 84, 106), 1.5)
    $trackR = [Math]::Min(14.0, $barH / 4)

    for ($i = 0; $i -lt 3; $i++) {
        $y = $ys[$i]
        $p = $progs[$i]

        $track = New-RoundPath $barX $y $barW $barH $trackR
        $g.FillPath($trackBrush, $track)
        $g.DrawPath($trackPen, $track)

        $fx = $barX + $inset
        $fy = $y + $inset
        $fh = $barH - 2 * $inset
        $fw = ($barW - 2 * $inset) * $p
        if ($fw -lt 18) { $fw = 18 }

        $fillPath = New-RoundPath $fx $fy $fw $fh $fillR
        $fc = $fillColors[$i]
        $fillBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $fc[0], $fc[1], $fc[2]))
        $g.FillPath($fillBrush, $fillPath)

        # Pip at the fill's leading edge, with a soft glow
        $pipCx = $fx + $fw
        $pipCy = $y + $barH / 2
        $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $glowPath.AddEllipse($pipCx - $glowR, $pipCy - $fh * 0.8, 2 * $glowR, $fh * 1.6)
        $glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
        $glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(130, 255, 255, 255)
        $glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
        $g.FillPath($glowBrush, $glowPath)

        $pip = New-RoundPath ($pipCx - $pipW / 2) $fy $pipW $fh ($pipW / 2 - 1)
        $pipBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
        $g.FillPath($pipBrush, $pip)

        if ($mode -ne "full") { continue }

        # Blizzard_SwingTimer overlay: text-shadow gradient (ui-swingtimerbar-
        # textshadow-left, 171 px, fading right), then TypeLabel and TimeLabel
        # in GameFontHighlightSmall style - white with a dark offset shadow.
        $shadowPath = New-RoundPath $barX $y 171 $barH 14
        $shadowRect = New-Object System.Drawing.RectangleF($barX, $y, 171, $barH)
        $shadowBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($shadowRect, [System.Drawing.Color]::FromArgb(120, 0, 0, 0), [System.Drawing.Color]::FromArgb(0, 0, 0, 0), 0)
        $g.FillPath($shadowBrush, $shadowPath)

        $labelFont = New-Object System.Drawing.Font("Segoe UI", 17, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $labelFmt = New-Object System.Drawing.StringFormat
        $labelFmt.Alignment = [System.Drawing.StringAlignment]::Near
        $labelFmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $timeFmt = New-Object System.Drawing.StringFormat
        $timeFmt.Alignment = [System.Drawing.StringAlignment]::Far
        $timeFmt.LineAlignment = [System.Drawing.StringAlignment]::Center

        $labelShadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
        $labelTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))

        $labelRect = New-Object System.Drawing.RectangleF(($barX + 10.0), $y, 150.0, $barH)
        $labelShadowRect = New-Object System.Drawing.RectangleF(($barX + 11.5), ($y + 1.5), 150.0, $barH)
        $g.DrawString($labels[$i], $labelFont, $labelShadowBrush, $labelShadowRect, $labelFmt)
        $g.DrawString($labels[$i], $labelFont, $labelTextBrush, $labelRect, $labelFmt)

        $timeRect = New-Object System.Drawing.RectangleF(($barX + $barW - 10.0 - 90.0), $y, 90.0, $barH)
        $timeShadowRect = New-Object System.Drawing.RectangleF(($barX + $barW - 10.0 - 90.0 + 1.5), ($y + 1.5), 90.0, $barH)
        $g.DrawString($times[$i], $labelFont, $labelShadowBrush, $timeShadowRect, $timeFmt)
        $g.DrawString($times[$i], $labelFont, $labelTextBrush, $timeRect, $timeFmt)
    }

    if ($mode -eq "full") {
        Draw-Wordmark $g 68 366 $false 0
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $subFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 255, 209, 51))
        $g.DrawString("S W I N G   T I M E R", $subFont, $subBrush, (New-Object System.Drawing.RectangleF(0, 452, 512, 26)), $fmt)
    } else {
        # Icon: trademark spanning the bars' width, bars beneath at the shared gap
        Draw-Wordmark $g 100 $wordmarkRectY $true 352
    }

    $g.ResetClip()

    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 92, 106, 140), 2.5)
    $g.DrawPath($borderPen, $bgPath)
}

function Render-Variant([string]$mode, [string]$name) {
    $bmp = New-Object System.Drawing.Bitmap 1024, 1024
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.ScaleTransform(2, 2)
    Draw-Logo $g $mode

    $outDir = "C:\Users\Shadow\Desktop\4everSwingTimer\docs"
    $bmp.Save("$outDir\$name-1024.png", [System.Drawing.Imaging.ImageFormat]::Png)

    foreach ($size in @(512, 256)) {
        $out = New-Object System.Drawing.Bitmap $size, $size
        $og = [System.Drawing.Graphics]::FromImage($out)
        $og.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $og.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $og.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $og.DrawImage($bmp, 0, 0, $size, $size)
        $out.Save("$outDir\$name-$size.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $og.Dispose(); $out.Dispose()
    }
    $g.Dispose(); $bmp.Dispose()
}

Render-Variant "icon" "logo-icon"
Render-Variant "full" "logo-full"
Write-Output "done"
