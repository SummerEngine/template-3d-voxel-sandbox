# Draws proper item icons + log faces into the block atlas (8x8, 256px tiles).
# Items go in previously-empty tiles; WOOD side + log-ring top are (re)drawn.
# Run from the project root. Loads/saves assets/textures/blocks/atlas.png in place.
Add-Type -AssemblyName System.Drawing

$root   = (Resolve-Path '.').Path
$atlasP = Join-Path $root 'assets\textures\blocks\atlas.png'
$backup = Join-Path $root 'assets\textures\blocks\atlas_pre_items.png'

if (-not (Test-Path $backup)) { Copy-Item $atlasP $backup }

# Load into a writable bitmap copy (FromFile locks the file).
$src = [System.Drawing.Image]::FromFile($atlasP)
$bmp = New-Object System.Drawing.Bitmap $src.Width, $src.Height
$g0  = [System.Drawing.Graphics]::FromImage($bmp)
$g0.DrawImage($src, 0, 0, $src.Width, $src.Height)
$g0.Dispose()
$src.Dispose()

$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

$T = 256   # tile size

function Col([int]$r,[int]$gr,[int]$b,[int]$a=255){ return [System.Drawing.Color]::FromArgb($a,$r,$gr,$b) }
function SBrush($c){ return New-Object System.Drawing.SolidBrush $c }
function Pen($c,[single]$w){ $p = New-Object System.Drawing.Pen $c, $w; $p.StartCap=[System.Drawing.Drawing2D.LineCap]::Round; $p.EndCap=[System.Drawing.Drawing2D.LineCap]::Round; return $p }

# Origin (x,y) for a tile index in the 8-wide atlas.
function Ox([int]$idx){ return ($idx % 8) * $T }
function Oy([int]$idx){ return [math]::Floor($idx / 8) * $T }

# Clear a tile to fully transparent (SourceCopy so it replaces, not blends).
function ClearTile([int]$idx){
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $g.FillRectangle((SBrush (Col 0 0 0 0)), (Ox $idx), (Oy $idx), $T, $T)
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
}

function Pt([single]$x,[single]$y){ return New-Object System.Drawing.PointF $x, $y }

# ---- WOOD bark side (tile 9, opaque) -------------------------------------------------
$ox = Ox 9; $oy = Oy 9
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.FillRectangle((SBrush (Col 107 74 43)), $ox, $oy, $T, $T)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
# vertical grain streaks
$streakX = @(18, 52, 96, 140, 150, 196, 232)
$shades  = @(92, 120, 84, 110, 70, 128, 96)
for ($i=0; $i -lt $streakX.Count; $i++){
  $sx = $ox + $streakX[$i]
  $c  = Col ($shades[$i]) ([int]($shades[$i]*0.66)) ([int]($shades[$i]*0.38))
  $g.FillRectangle((SBrush $c), $sx, $oy, (8 + ($i % 3)*4), $T)
}
# a couple of knots
$g.FillEllipse((SBrush (Col 78 52 28)), $ox+70,  $oy+150, 34, 22)
$g.FillEllipse((SBrush (Col 120 86 50)), $ox+78, $oy+156, 16, 10)

# ---- WOOD top: log rings (tile 36, opaque) ------------------------------------------
$ox = Ox 36; $oy = Oy 36
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.FillRectangle((SBrush (Col 150 112 66)), $ox, $oy, $T, $T)   # bark border base
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$cx = $ox + 128; $cy = $oy + 128
$ringR = @(112, 92, 72, 52, 34, 18)
$ringC = @((Col 138 100 58), (Col 168 128 78), (Col 146 106 62), (Col 176 136 84), (Col 150 110 66), (Col 184 144 92))
for ($i=0; $i -lt $ringR.Count; $i++){
  $r = $ringR[$i]
  $g.FillEllipse((SBrush $ringC[$i]), ($cx-$r), ($cy-$r), ($r*2), ($r*2))
}
$g.FillEllipse((SBrush (Col 120 84 48)), ($cx-6), ($cy-6), 12, 12)  # heart

# ---- STICK (tile 28) ----------------------------------------------------------------
ClearTile 28
$ox = Ox 28; $oy = Oy 28
$g.DrawLine((Pen (Col 92 58 30) 40), $ox+74, $oy+196, $ox+182, $oy+60)   # dark edge
$g.DrawLine((Pen (Col 140 92 46) 26), $ox+74, $oy+196, $ox+182, $oy+60)  # core
$g.DrawLine((Pen (Col 170 120 66) 8), $ox+86, $oy+182, $ox+170, $oy+74)  # highlight

# ---- COAL lump (tile 29) ------------------------------------------------------------
ClearTile 29
$ox = Ox 29; $oy = Oy 29
$pts = @((Pt ($ox+70) ($oy+96)), (Pt ($ox+120) ($oy+58)), (Pt ($ox+186) ($oy+84)), (Pt ($ox+196) ($oy+150)), (Pt ($ox+150) ($oy+198)), (Pt ($ox+78) ($oy+188)), (Pt ($ox+50) ($oy+140)))
$g.FillPolygon((SBrush (Col 34 34 40)), [System.Drawing.PointF[]]$pts)
$g.FillPolygon((SBrush (Col 58 58 66)), [System.Drawing.PointF[]]@((Pt ($ox+108) ($oy+96)), (Pt ($ox+150) ($oy+110)), (Pt ($ox+120) ($oy+150))))
$g.FillPolygon((SBrush (Col 20 20 24)), [System.Drawing.PointF[]]@((Pt ($ox+78) ($oy+150)), (Pt ($ox+120) ($oy+158)), (Pt ($ox+92) ($oy+184))))

# ---- IRON INGOT (tile 30) -----------------------------------------------------------
ClearTile 30
$ox = Ox 30; $oy = Oy 30
$g.FillPolygon((SBrush (Col 150 150 156)), [System.Drawing.PointF[]]@((Pt ($ox+60) ($oy+170)), (Pt ($ox+196) ($oy+170)), (Pt ($ox+176) ($oy+120)), (Pt ($ox+80) ($oy+120))))  # body
$g.FillPolygon((SBrush (Col 200 200 206)), [System.Drawing.PointF[]]@((Pt ($ox+80) ($oy+120)), (Pt ($ox+176) ($oy+120)), (Pt ($ox+158) ($oy+96)), (Pt ($ox+98) ($oy+96))))    # top face
$g.DrawLine((Pen (Col 120 120 126) 4), $ox+72, $oy+150, $ox+184, $oy+150)

# ---- GOLD INGOT (tile 31) -----------------------------------------------------------
ClearTile 31
$ox = Ox 31; $oy = Oy 31
$g.FillPolygon((SBrush (Col 214 168 44)), [System.Drawing.PointF[]]@((Pt ($ox+60) ($oy+170)), (Pt ($ox+196) ($oy+170)), (Pt ($ox+176) ($oy+120)), (Pt ($ox+80) ($oy+120))))
$g.FillPolygon((SBrush (Col 244 212 86)), [System.Drawing.PointF[]]@((Pt ($ox+80) ($oy+120)), (Pt ($ox+176) ($oy+120)), (Pt ($ox+158) ($oy+96)), (Pt ($ox+98) ($oy+96))))
$g.DrawLine((Pen (Col 180 134 28) 4), $ox+72, $oy+150, $ox+184, $oy+150)

# ---- DIAMOND gem (tile 32) ----------------------------------------------------------
ClearTile 32
$ox = Ox 32; $oy = Oy 32
$g.FillPolygon((SBrush (Col 73 214 224)), [System.Drawing.PointF[]]@((Pt ($ox+74) ($oy+104)), (Pt ($ox+182) ($oy+104)), (Pt ($ox+128) ($oy+200))))   # lower
$g.FillPolygon((SBrush (Col 120 230 238)), [System.Drawing.PointF[]]@((Pt ($ox+74) ($oy+104)), (Pt ($ox+104) ($oy+66)), (Pt ($ox+152) ($oy+66)), (Pt ($ox+182) ($oy+104))))  # crown
$g.DrawLine((Pen (Col 200 245 250) 5), $ox+104, $oy+66, $ox+128, $oy+200)
$g.DrawLine((Pen (Col 200 245 250) 5), $ox+152, $oy+66, $ox+128, $oy+200)
$g.DrawLine((Pen (Col 36 150 162) 4), $ox+74, $oy+104, $ox+182, $oy+104)

# ---- APPLE (tile 33) ----------------------------------------------------------------
ClearTile 33
$ox = Ox 33; $oy = Oy 33
$g.FillEllipse((SBrush (Col 198 40 36)), $ox+70, $oy+86, 116, 120)
$g.FillEllipse((SBrush (Col 168 28 26)), $ox+118, $oy+92, 64, 108)   # shaded right lobe
$g.FillEllipse((SBrush (Col 240 120 108)), $ox+92, $oy+104, 34, 30)  # highlight
$g.FillRectangle((SBrush (Col 96 60 30)), $ox+124, $oy+66, 10, 30)   # stem
$g.FillPolygon((SBrush (Col 86 168 70)), [System.Drawing.PointF[]]@((Pt ($ox+134) ($oy+74)), (Pt ($ox+178) ($oy+58)), (Pt ($ox+158) ($oy+92))))  # leaf

# ---- RAW MEAT (tile 34) -------------------------------------------------------------
ClearTile 34
$ox = Ox 34; $oy = Oy 34
$g.FillEllipse((SBrush (Col 198 86 96)), $ox+66, $oy+78, 132, 120)    # outer flesh
$g.FillEllipse((SBrush (Col 224 138 146)), $ox+92, $oy+98, 86, 78)    # lighter center
$g.FillEllipse((SBrush (Col 240 232 214)), $ox+58, $oy+150, 44, 44)   # bone knob
$g.FillEllipse((SBrush (Col 210 200 180)), $ox+70, $oy+162, 18, 18)
$g.DrawArc((Pen (Col 170 64 74) 6), $ox+96, $oy+104, 70, 66, 200, 200)

# ---- COOKED MEAT / steak (tile 35) --------------------------------------------------
ClearTile 35
$ox = Ox 35; $oy = Oy 35
$g.FillEllipse((SBrush (Col 122 67 38)), $ox+66, $oy+78, 132, 120)    # browned outer
$g.FillEllipse((SBrush (Col 162 100 58)), $ox+92, $oy+98, 86, 78)     # lighter center
$g.FillEllipse((SBrush (Col 237 227 207)), $ox+58, $oy+150, 44, 44)   # bone knob
$g.FillEllipse((SBrush (Col 206 196 176)), $ox+70, $oy+162, 18, 18)
# grill marks
$g.DrawLine((Pen (Col 78 44 24) 7), $ox+104, $oy+108, $ox+168, $oy+150)
$g.DrawLine((Pen (Col 78 44 24) 7), $ox+92,  $oy+134, $ox+156, $oy+176)

$g.Dispose()

$bmp.Save($atlasP, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output 'atlas.png updated with item icons + log faces'
