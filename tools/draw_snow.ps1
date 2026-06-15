# Draws the Snow block tile into the atlas at index 37 (col5,row4 -> 1280,1024).
# Run from anywhere; edits assets/textures/blocks/atlas.png in place.
Add-Type -AssemblyName System.Drawing
$p = Join-Path $PSScriptRoot "..\assets\textures\blocks\atlas.png"
$p = (Resolve-Path $p).Path
$src = [System.Drawing.Image]::FromFile($p)
$bmp = New-Object System.Drawing.Bitmap $src.Width, $src.Height
$g0 = [System.Drawing.Graphics]::FromImage($bmp); $g0.DrawImage($src,0,0,$src.Width,$src.Height); $g0.Dispose(); $src.Dispose()
$g = [System.Drawing.Graphics]::FromImage($bmp)
$ox = 1280; $oy = 1024; $T = 256
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,242,246,251))), $ox, $oy, $T, $T)
$rng = New-Object System.Random 42
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,222,230,240))
for ($i=0; $i -lt 60; $i++) { $g.FillRectangle($shade, ($ox + $rng.Next(0,$T-18)), ($oy + $rng.Next(0,$T-18)), $rng.Next(6,16), $rng.Next(6,16)) }
$hi = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,255,255))
for ($i=0; $i -lt 30; $i++) { $g.FillRectangle($hi, ($ox + $rng.Next(0,$T-10)), ($oy + $rng.Next(0,$T-10)), $rng.Next(4,10), $rng.Next(4,10)) }
$g.Dispose()
$bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output "snow tile written to atlas index 37"
