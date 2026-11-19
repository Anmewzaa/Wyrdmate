# Regenerates two charts from docs/progress/data.json:
#   docs/progress/training-process.svg  (head-to-head match results per net)
#   docs/progress/loss.svg              (training loss curves, with version/timestamp)
# Run from the repo root:  powershell -File scripts/make-progress-svg.ps1
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path -Parent $PSScriptRoot
$d = Get-Content (Join-Path $root 'docs/progress/data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ui = $d.ui
function F($x) { ([double]$x).ToString('0.##', $inv) }
function Esc($s) { [Security.SecurityElement]::Escape([string]$s) }
function T($x, $y, $size, $fill, $text, $anchor = 'start', $weight = '400') {
  "<text x=`"$(F $x)`" y=`"$(F $y)`" font-size=`"$size`" font-weight=`"$weight`" fill=`"$fill`" text-anchor=`"$anchor`">$(Esc $text)</text>"
}

$W = 940
$ink = '#1f1f1e'; $mute = '#6b6a66'; $grid = '#e1e0d9'; $band = '#f6f5f0'
$blue = '#2a78d6'; $red = '#e34948'; $gray = '#898781'
$pm = [char]0x00B1; $dot = [char]0x00B7
$font = 'Segoe UI,Helvetica,Arial,sans-serif'

function Save-Svg($sb, $w, $h, $label, $file) {
  $head = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$w`" height=`"$h`" viewBox=`"0 0 $w $h`" font-family=`"$font`" role=`"img`" aria-label=`"$(Esc $label)`">`n<rect width=`"$w`" height=`"$h`" fill=`"#ffffff`"/>`n"
  $out = Join-Path $root $file
  [IO.File]::WriteAllText($out, $head + $sb.ToString() + "</svg>`n", (New-Object Text.UTF8Encoding($false)))
  "wrote $out"
}

# =====================================================================
# 1) Training process: match results
# =====================================================================
$s = New-Object Text.StringBuilder
function A($line) { [void]$s.AppendLine($line) }
$rows = @($d.matches)
$px0 = 360; $px1 = 660
$lim = [math]::Ceiling((($rows | ForEach-Object { [math]::Abs($_.elo) + $_.err } | Measure-Object -Maximum).Maximum + 30) / 50) * 50
$step = if ($lim -gt 250) { 100 } else { 50 }
function X($v) { $px0 + ($v + $lim) / (2 * $lim) * ($px1 - $px0) }

$boxTop = 70; $boxH = 104
$eloTop = $boxTop + $boxH + 56; $rowH = 70
$axisY = $eloTop + $rows.Count * $rowH + 4
$H = $axisY + 80

A (T 24 38 22 $ink $ui.procTitle 'start' '700')
A (T 24 58 13 $mute $ui.procSub)
A "<rect x=`"24`" y=`"$boxTop`" width=`"$($W - 48)`" height=`"$boxH`" rx=`"6`" fill=`"$band`"/>"
$ly = $boxTop + 26
foreach ($k in 'how1', 'how2', 'how3', 'baseline') { A (T 40 $ly 12 $ink $ui.$k); $ly += 23 }

A (T ((X 0) - 10) ($eloTop - 14) 12 $mute "< $($ui.weaker)" 'end')
A (T ((X 0) + 10) ($eloTop - 14) 12 $mute "$($ui.stronger) >" 'start')
for ($v = -$lim; $v -le $lim; $v += $step) {
  $x = X $v
  A "<line x1=`"$(F $x)`" y1=`"$eloTop`" x2=`"$(F $x)`" y2=`"$axisY`" stroke=`"$grid`"/>"
  A (T $x ($axisY + 16) 11 $mute $v 'middle')
}
A (T (($px0 + $px1) / 2) ($axisY + 38) 12 $mute $ui.axis 'middle')

$i = 0
foreach ($r in $rows) {
  $top = $eloTop + $i * $rowH; $cy = $top + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$top`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  if ($r.accepted) { $col = $blue; $verdict = $ui.betterAccepted }
  elseif (($r.elo + $r.err) -lt 0) { $col = $red; $verdict = $ui.worse }
  elseif (($r.elo - $r.err) -gt 0) { $col = $blue; $verdict = $ui.notAccepted }
  else { $col = $gray; $verdict = $ui.unclear }
  $score = [math]::Round(100 / (1 + [math]::Pow(10, -$r.elo / 400)))
  $meta = "$($r.finished) $dot $($r.games) $($ui.games)"
  if ($r.commit) { $meta += " $dot $($ui.commit) $($r.commit)" }
  A (T 36 ($cy - 12) 13 $ink $r.net 'start' '700')
  A (T 36 ($cy + 4) 12 $ink "$($ui.vs) $($r.vs)" 'start')
  A (T 36 ($cy + 21) 11 $mute $meta 'start')
  $x0 = X 0; $x1 = X $r.elo
  A "<rect x=`"$(F ([math]::Min($x0, $x1)))`" y=`"$(F ($cy - 11))`" width=`"$(F ([math]::Abs($x1 - $x0)))`" height=`"22`" rx=`"3`" fill=`"$col`"/>"
  $lo = X ($r.elo - $r.err); $hi = X ($r.elo + $r.err)
  A "<path d=`"M$(F $lo) $(F $cy)H$(F $hi)M$(F $lo) $(F ($cy - 6))V$(F ($cy + 6))M$(F $hi) $(F ($cy - 6))V$(F ($cy + 6))`" stroke=`"$ink`" stroke-width=`"1.5`" fill=`"none`"/>"
  $sign = if ($r.elo -gt 0) { '+' } else { '' }
  $label = "$sign$($r.elo) $pm $($r.err)"
  if ($r.elo -ge 0) { A (T ($hi + 8) ($cy + 5) 13 $ink $label 'start' '700') } else { A (T ($x0 + 10) ($cy + 5) 13 $ink $label 'start' '700') }
  A (T 750 ($cy - 4) 13 $col $verdict 'start' '700')
  A (T 750 ($cy + 14) 11 $mute ($ui.scoreFmt -replace '\{0\}', $score) 'start')
  $i++
}
$zx = X 0
A "<line x1=`"$(F $zx)`" y1=`"$eloTop`" x2=`"$(F $zx)`" y2=`"$axisY`" stroke=`"$ink`" stroke-width=`"1.5`"/>"
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.procTitle 'docs/progress/training-process.svg'

# =====================================================================
# 2) Loss curves, labelled with net version + timestamp + commit
# =====================================================================
$s = New-Object Text.StringBuilder
$pal = @('#2a78d6', '#eb6834', '#1baf7a', '#6250d6')
$n = @($d.loss).Count
$legTop = 118
$lossTop = $legTop + $n * 44 + 30; $lossH = 260
$by = $lossTop + $lossH
$H = $by + 80
$lx0 = 90; $lx1 = 860; $ymin = 0.0005; $ymax = 0.02
function LY($v) { $lossTop + (1 - ([math]::Log10($v) - [math]::Log10($ymin)) / ([math]::Log10($ymax) - [math]::Log10($ymin))) * $lossH }

A (T 24 38 22 $ink $ui.lossTitle 'start' '700')
A (T 24 58 13 $mute $ui.lossSub)
A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
A (T 40 91 12 $ink $ui.lossNote)

$k = 0; $ly = $legTop + 22
foreach ($ser in $d.loss) {
  $c = $pal[$k % 4]
  A "<rect x=`"24`" y=`"$($ly - 12)`" width=`"16`" height=`"16`" rx=`"3`" fill=`"$c`"/>"
  A (T 48 $ly 13 $ink "$($ser.name) $dot $($ser.detail)" 'start' '700')
  A (T 48 ($ly + 17) 11 $mute "$($ui.data): $($ser.data) $dot $($ui.trainedAt) $($ser.finished) $dot $($ui.commit) $($ser.commit)")
  $ly += 44; $k++
}
foreach ($t in 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02) {
  $y = LY $t
  A "<line x1=`"$lx0`" y1=`"$(F $y)`" x2=`"$lx1`" y2=`"$(F $y)`" stroke=`"$grid`"/>"
  A (T ($lx0 - 8) ($y + 4) 11 $mute ([double]$t).ToString('0.####', $inv) 'end')
}
$maxX = 1
foreach ($ser in $d.loss) { foreach ($p in $ser.points) { if ($p[0] -gt $maxX) { $maxX = $p[0] } } }
$k = 0
foreach ($ser in $d.loss) {
  $c = $pal[$k % 4]
  $pts = ($ser.points | ForEach-Object { "$(F ($lx0 + $_[0] / $maxX * ($lx1 - $lx0))),$(F (LY $_[1]))" }) -join ' '
  A "<polyline points=`"$pts`" fill=`"none`" stroke=`"$c`" stroke-width=`"2.5`" stroke-linejoin=`"round`"/>"
  $last = $ser.points[$ser.points.Count - 1]
  $ex = $lx0 + $last[0] / $maxX * ($lx1 - $lx0); $ey = LY $last[1]
  A "<circle cx=`"$(F $ex)`" cy=`"$(F $ey)`" r=`"4`" fill=`"$c`"/>"
  $k++
}
# final-value labels, stacked so they never overlap
$ly = $lossTop + 14
$k = 0
foreach ($ser in $d.loss) {
  $c = $pal[$k % 4]
  $last = $ser.points[$ser.points.Count - 1]
  A (T ($lx1 + 6) ($ly) 11 $c "$($ser.name) $($ui.lossFinal) $(([double]$last[1]).ToString('0.000000', $inv))" 'end' '700')
  $ly += 16; $k++
}
foreach ($t in 0, 50, 100, 150, 200) { if ($t -le $maxX) { A (T ($lx0 + $t / $maxX * ($lx1 - $lx0)) ($by + 18) 11 $mute $t 'middle') } }
A (T (($lx0 + $lx1) / 2) ($by + 40) 12 $mute $ui.lossX 'middle')
A "<text transform=`"translate(24 $(F ($lossTop + $lossH / 2))) rotate(-90)`" font-size=`"12`" fill=`"$mute`" text-anchor=`"middle`">$(Esc $ui.lossY)</text>"
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.lossTitle 'docs/progress/loss.svg'
