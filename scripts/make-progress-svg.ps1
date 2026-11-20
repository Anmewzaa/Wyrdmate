# Regenerates the charts from docs/progress/data.json:
#   docs/progress/training-process.svg  (head-to-head match results per net)
#   docs/progress/loss.svg              (training loss curves, with version/timestamp)
#   docs/progress/ladder.svg            (strength by node limit, first search vs current search)
#   docs/progress/search-steps.svg      (what each search step added, per node limit)
#   docs/progress/stockfish.svg         (our levels placed on the Stockfish UCI_Elo scale)
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

# =====================================================================
# 3) Strength by node limit: first search vs current search
# =====================================================================
$s = New-Object Text.StringBuilder
$px0 = 90; $px1 = 860; $top = 128; $ph = 340; $by = $top + $ph; $H = $by + 90
$ymin = -350; $ymax = 600
$nmin = [double]$d.ladder[0].nodes; $nmax = [double]$d.ladder[$d.ladder.Count - 1].nodes
function GY($v) { $top + (1 - ($v - $ymin) / ($ymax - $ymin)) * $ph }
function GX($n) { $px0 + ([math]::Log($n, 2) - [math]::Log($nmin, 2)) / ([math]::Log($nmax, 2) - [math]::Log($nmin, 2)) * ($px1 - $px0) }
A (T 24 38 22 $ink $ui.ladderTitle 'start' '700')
A (T 24 58 13 $mute $ui.ladderSub)
A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
A (T 40 91 11 $ink $ui.ladderNote)
for ($t = -300; $t -le 600; $t += 100) {
  $y = GY $t
  $sw = if ($t -eq 0) { 1.5 } else { 1 }; $c = if ($t -eq 0) { $ink } else { $grid }  # not $w: PowerShell names are case-insensitive and $W is the page width
  A "<line x1=`"$px0`" y1=`"$(F $y)`" x2=`"$px1`" y2=`"$(F $y)`" stroke=`"$c`" stroke-width=`"$sw`"/>"
  A (T ($px0 - 8) ($y + 4) 11 $mute $t 'end')
}
foreach ($r in $d.ladder) { A (T (GX $r.nodes) ($by + 18) 11 $mute (([int]$r.nodes).ToString('N0', $inv)) 'middle') }
A (T (($px0 + $px1) / 2) ($by + 42) 12 $mute $ui.ladderX 'middle')
A "<text transform=`"translate(24 $(F ($top + $ph / 2))) rotate(-90)`" font-size=`"12`" fill=`"$mute`" text-anchor=`"middle`">$(Esc $ui.ladderY)</text>"
foreach ($ser in @(@('s1', $gray, -4), @('s6', $blue, 4))) {
  $key = $ser[0]; $c = $ser[1]; $dx = $ser[2]
  $pts = ($d.ladder | ForEach-Object { "$(F ((GX $_.nodes) + $dx)),$(F (GY $_.$key[0]))" }) -join ' '
  A "<polyline points=`"$pts`" fill=`"none`" stroke=`"$c`" stroke-width=`"2.5`" stroke-linejoin=`"round`"/>"
  foreach ($r in $d.ladder) {
    $x = (GX $r.nodes) + $dx; $e = $r.$key[0]; $err = $r.$key[1]
    A "<path d=`"M$(F $x) $(F (GY ($e - $err)))V$(F (GY ($e + $err)))`" stroke=`"$c`" stroke-width=`"1.5`" fill=`"none`"/>"
    A "<circle cx=`"$(F $x)`" cy=`"$(F (GY $e))`" r=`"4`" fill=`"$c`"/>"
  }
  $last = $d.ladder[$d.ladder.Count - 1]
  $lv = $last.$key[0]; $sign = if ($lv -gt 0) { '+' } else { '' }
  $up = 0; if ($key -eq 's6') { $up = 8 }
  A (T ((GX $last.nodes) + $dx - 10) ((GY $lv) - 10 - $up) 12 $c "$sign$lv" 'end' '700')
}
A "<rect x=`"110`" y=`"$($top + 10)`" width=`"14`" height=`"14`" rx=`"3`" fill=`"$gray`"/>"
A (T 132 ($top + 22) 12 $ink $ui.ladderS1)
A "<rect x=`"110`" y=`"$($top + 32)`" width=`"14`" height=`"14`" rx=`"3`" fill=`"$blue`"/>"
A (T 132 ($top + 44) 12 $ink $ui.ladderS6)
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.ladderTitle 'docs/progress/ladder.svg'

# =====================================================================
# 4) What each search step added, per node limit
# =====================================================================
$s = New-Object Text.StringBuilder
$px0 = 90; $px1 = 880; $top = 128; $ph = 300; $by = $top + $ph; $H = $by + 110
$ymin = -80; $ymax = 160
function SY($v) { $top + (1 - ($v - $ymin) / ($ymax - $ymin)) * $ph }
A (T 24 38 22 $ink $ui.stepsTitle 'start' '700')
A (T 24 58 13 $mute $ui.stepsSub)
A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
A (T 40 91 11 $ink $ui.stepsNote)
for ($t = -80; $t -le 160; $t += 40) {
  $y = SY $t
  $sw = if ($t -eq 0) { 1.5 } else { 1 }; $c = if ($t -eq 0) { $ink } else { $grid }  # not $w: PowerShell names are case-insensitive and $W is the page width
  A "<line x1=`"$px0`" y1=`"$(F $y)`" x2=`"$px1`" y2=`"$(F $y)`" stroke=`"$c`" stroke-width=`"$sw`"/>"
  A (T ($px0 - 8) ($y + 4) 11 $mute $t 'end')
}
A "<text transform=`"translate(24 $(F ($top + $ph / 2))) rotate(-90)`" font-size=`"12`" fill=`"$mute`" text-anchor=`"middle`">$(Esc $ui.stepsY)</text>"
$okCols = @('#9cc3ee', '#2a78d6', '#16427c'); $noCols = @('#d7d5ce', '#aeaca5', '#7d7b75')
$levels = @(@('n1k', '1,000'), @('n10k', '10,000'), @('n50k', '50,000'))
$gw = ($px1 - $px0) / @($d.steps).Count; $bw = 24; $gap = 4
$gi = 0
foreach ($st in $d.steps) {
  $cx = $px0 + $gw * ($gi + 0.5)
  $cols = $okCols; if ($st.rejected) { $cols = $noCols }
  for ($li = 0; $li -lt 3; $li++) {
    $v = $st.($levels[$li][0])
    if ($null -eq $v) { continue }
    $x = $cx + ($li - 1) * ($bw + $gap) - $bw / 2
    $e = $v[0]; $err = $v[1]
    $y0 = SY 0; $y1 = SY $e
    A "<rect x=`"$(F $x)`" y=`"$(F ([math]::Min($y0, $y1)))`" width=`"$bw`" height=`"$(F ([math]::Max(1, [math]::Abs($y1 - $y0))))`" rx=`"2`" fill=`"$($cols[$li])`"/>"
    $xm = $x + $bw / 2
    A "<path d=`"M$(F $xm) $(F (SY ($e - $err)))V$(F (SY ($e + $err)))M$(F ($xm - 4)) $(F (SY ($e - $err)))H$(F ($xm + 4))M$(F ($xm - 4)) $(F (SY ($e + $err)))H$(F ($xm + 4))`" stroke=`"$ink`" stroke-width=`"1.2`" fill=`"none`"/>"
    $sign = if ($e -gt 0) { '+' } else { '' }
    if ($e -ge 0) { $ly = (SY ($e + $err)) - 5 } else { $ly = (SY ($e - $err)) + 14 }
    A (T $xm $ly 10 $ink "$sign$e" 'middle' '700')
  }
  A (T $cx ($by + 20) 13 $ink $st.id 'middle' '700')
  A (T $cx ($by + 36) 10 $mute $st.what 'middle')
  if ($st.rejected) { A (T $cx ($by + 50) 10 $red $ui.stepsRejected 'middle' '700') }
  $gi++
}
$lx = 110
for ($li = 0; $li -lt 3; $li++) {
  A "<rect x=`"$lx`" y=`"$($top - 18)`" width=`"12`" height=`"12`" rx=`"2`" fill=`"$($okCols[$li])`"/>"
  A (T ($lx + 18) ($top - 8) 11 $ink "$($levels[$li][1]) $($ui.nodes)")
  $lx += 130
}
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.stepsTitle 'docs/progress/search-steps.svg'

# =====================================================================
# 5) Our levels placed on the Stockfish UCI_Elo scale (rough)
# =====================================================================
$s = New-Object Text.StringBuilder
$sx0 = 220; $sx1 = 820; $smin = 1250; $smax = 1650
$rowH = 58; $top = 164; $rows = @($d.stockfish.levels)
$by = $top + $rows.Count * $rowH; $H = $by + 90
function SX($v) { $sx0 + ($v - $smin) / ($smax - $smin) * ($sx1 - $sx0) }
A (T 24 38 22 $ink $ui.sfTitle 'start' '700')
A (T 24 58 13 $mute $ui.sfSub)
A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
A (T 40 91 11 $ink $ui.sfNote)
foreach ($ru in $d.stockfish.rulers) {
  $x = SX $ru
  A "<line x1=`"$(F $x)`" y1=`"$($top - 14)`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$grid`" stroke-width=`"1.5`" stroke-dasharray=`"4 3`"/>"
  A (T $x ($top - 20) 11 $mute "SF $ru" 'middle' '700')
}
A (T (($sx0 + $sx1) / 2) ($by + 40) 12 $mute $ui.sfX 'middle')
for ($v = 1300; $v -le 1600; $v += 100) { A (T (SX $v) ($by + 18) 11 $mute $v 'middle') }
$err = [double]$d.stockfish.err
$i = 0
foreach ($r in $rows) {
  $cy = $top + $i * $rowH + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $i * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  A (T 36 ($cy + 5) 13 $ink "$(([int]$r.nodes).ToString('N0', $inv)) $($ui.nodes)" 'start' '700')
  foreach ($ser in @(@('s1', $gray, -9), @('s6', $blue, 9))) {
    $v = $r.($ser[0]); $c = $ser[1]; $y = $cy + $ser[2]
    if ($null -eq $v -or $v -lt 1320) {
      $x = SX 1320
      A "<path d=`"M$(F ($x - 2)) $(F $y)l-10 -6v12z`" fill=`"$c`"/>"
      A (T ($x - 18) ($y + 4) 10 $c $ui.sfBelow 'end')
    } else {
      $x = SX $v
      A "<path d=`"M$(F (SX ($v - $err))) $(F $y)H$(F (SX ($v + $err)))`" stroke=`"$c`" stroke-width=`"1.5`" fill=`"none`"/>"
      A "<circle cx=`"$(F $x)`" cy=`"$(F $y)`" r=`"5`" fill=`"$c`"/>"
      A (T ($x + 9) ($y - 7) 11 $c "~$v" 'start' '700')
    }
  }
  $i++
}
A "<rect x=`"600`" y=`"$($top - 54)`" width=`"12`" height=`"12`" rx=`"3`" fill=`"$gray`"/>"
A (T 618 ($top - 44) 11 $ink $ui.ladderS1)
A "<rect x=`"730`" y=`"$($top - 54)`" width=`"12`" height=`"12`" rx=`"3`" fill=`"$blue`"/>"
A (T 748 ($top - 44) 11 $ink $ui.ladderS6)
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.sfTitle 'docs/progress/stockfish.svg'
