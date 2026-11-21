# Regenerates the charts from docs/progress/data.json:
#   docs/progress/training-process.svg  (leaderboard: one row per accepted net, vs previous net and vs material eval)
#   docs/progress/loss.svg              (final loss per net + loss curves)
#   docs/progress/ladder.svg            (leaderboard: strength per node limit, first vs current search)
#   docs/progress/search-steps.svg      (leaderboard: what each search step added)
#   docs/progress/stockfish.svg         (leaderboard: our levels on the Stockfish UCI_Elo scale)
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
# 1) Training process: one row per accepted net (leaderboard), newest first
# =====================================================================
$s = New-Object Text.StringBuilder
function A($line) { [void]$s.AppendLine($line) }
function NetName($m) { ([string]$m.net -split (' ' + [char]0x00B7 + ' '))[0].Trim() }
$accepted = @($d.matches | Where-Object { $_.accepted })
$prevRows = @($accepted | Where-Object { $_.vs -like '*previous net*' } | Sort-Object { $_.finished } -Descending)
$rejected = @($d.matches | Where-Object { -not $_.accepted })
$boxTop = 70; $boxH = 104
$top = $boxTop + $boxH + 46; $rowH = 62
$bx0 = 330; $bx1 = 760
$allv = @(); foreach ($r in $prevRows) { $allv += ($r.elo + $r.err); $allv += ($r.elo - $r.err) }
foreach ($r in $accepted) { if ($r.vs -like 'material*') { $allv += ($r.elo + $r.err); $allv += ($r.elo - $r.err) } }
$dmax = [math]::Ceiling((($allv | Measure-Object -Maximum).Maximum + 10) / 50) * 50
$dmin = [math]::Min(0, [math]::Floor((($allv | Measure-Object -Minimum).Minimum) / 50) * 50)
function X($v) { $bx0 + ($v - $dmin) / ($dmax - $dmin) * ($bx1 - $bx0) }
$by = $top + $prevRows.Count * $rowH
$notesTop = $by + 64
$H = $notesTop + 24 + $rejected.Count * 18 + 40

A (T 24 38 22 $ink $ui.procTitle 'start' '700')
A (T 24 58 13 $mute $ui.procSub)
A "<rect x=`"24`" y=`"$boxTop`" width=`"$($W - 48)`" height=`"$boxH`" rx=`"6`" fill=`"$band`"/>"
$ly = $boxTop + 26
foreach ($k in 'how1', 'how2', 'how3', 'baseline') { A (T 40 $ly 12 $ink $ui.$k); $ly += 23 }

A "<rect x=`"36`" y=`"$($top - 28)`" width=`"14`" height=`"14`" rx=`"3`" fill=`"$blue`"/>"
A (T 56 ($top - 16) 12 $ink $ui.procPrev)
A "<rect x=`"270`" y=`"$($top - 28)`" width=`"14`" height=`"14`" rx=`"3`" fill=`"$gray`"/>"
A (T 290 ($top - 16) 12 $ink $ui.procMat)

for ($v = $dmin; $v -le $dmax; $v += 50) {
  $x = X $v
  A "<line x1=`"$(F $x)`" y1=`"$top`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$grid`"/>"
  A (T $x ($by + 16) 11 $mute $v 'middle')
}
$i = 0
foreach ($r in $prevRows) {
  $cy = $top + $i * $rowH + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $i * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  $name = NetName $r
  $detail = ([string]$r.net).Substring($name.Length).TrimStart(" ", [char]0x00B7).Trim()
  $meta = "$($r.finished) $dot $($r.games) $($ui.games)"
  if ($r.commit) { $meta += " $dot $($ui.commit) $($r.commit)" }
  A (T 36 ($cy - 10) 15 $ink $name 'start' '700')
  A (T 36 ($cy + 6) 11 $ink $detail)
  A (T 36 ($cy + 21) 11 $mute $meta)
  # main bar: vs previous net
  $x0 = X 0; $x1 = X $r.elo
  A "<rect x=`"$(F ([math]::Min($x0, $x1)))`" y=`"$(F ($cy - 17))`" width=`"$(F ([math]::Max(1, [math]::Abs($x1 - $x0))))`" height=`"16`" rx=`"3`" fill=`"$blue`"/>"
  $sign = if ($r.elo -gt 0) { '+' } else { '' }
  A (T ($x1 + 8) ($cy - 4) 12 $ink "$sign$($r.elo) $pm $($r.err)" 'start' '700')
  # thin bar: the same net vs the material eval, when that match exists
  $mat = $accepted | Where-Object { (NetName $_) -eq $name -and $_.vs -like 'material*' } | Select-Object -First 1
  if ($mat) {
    $m1 = X $mat.elo
    A "<rect x=`"$(F ([math]::Min($x0, $m1)))`" y=`"$(F ($cy + 2))`" width=`"$(F ([math]::Max(1, [math]::Abs($m1 - $x0))))`" height=`"10`" rx=`"3`" fill=`"$gray`"/>"
    A (T ($m1 + 8) ($cy + 11) 11 $mute "+$($mat.elo) $pm $($mat.err)" 'start')
  }
  $i++
}
A "<line x1=`"$(F (X 0))`" y1=`"$top`" x2=`"$(F (X 0))`" y2=`"$by`" stroke=`"$ink`" stroke-width=`"1.5`"/>"
A (T (($bx0 + $bx1) / 2) ($by + 38) 12 $mute $ui.axis 'middle')

A (T 24 $notesTop 13 $ink $ui.procRejected 'start' '700')
$ny = $notesTop + 20
foreach ($r in $rejected) {
  $sign = if ($r.elo -gt 0) { '+' } else { '' }
  A (T 36 $ny 11 $mute "$($r.net) $dot $($ui.vs) $($r.vs): $sign$($r.elo) $pm $($r.err) ($($r.finished))")
  $ny += 18
}
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.procTitle 'docs/progress/training-process.svg'

# =====================================================================
# 2) Loss: final loss per net (rows double as the legend) + curves
# =====================================================================
$s = New-Object Text.StringBuilder
function A($line) { [void]$s.AppendLine($line) }
$pal = @('#2a78d6', '#eb6834', '#1baf7a', '#6250d6', '#c99a06', '#c43f8c')
$series = @($d.loss)
$n = $series.Count
$rowH = 54; $top = 120; $bx0 = 450; $bx1 = 830
$fin = @($series | ForEach-Object { [double]$_.points[$_.points.Count - 1][1] })
$vmax = [math]::Ceiling((($fin | Measure-Object -Maximum).Maximum) * 1.15 / 0.0005) * 0.0005
function BX($v) { $bx0 + $v / $vmax * ($bx1 - $bx0) }
$barsEnd = $top + $n * $rowH

A (T 24 38 22 $ink $ui.lossTitle 'start' '700')
A (T 24 58 13 $mute $ui.lossSub)
A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
A (T 40 91 11 $ink $ui.lossNote)

for ($v = 0; $v -le $vmax + 1e-9; $v += 0.0005) {
  $x = BX $v
  A "<line x1=`"$(F $x)`" y1=`"$top`" x2=`"$(F $x)`" y2=`"$barsEnd`" stroke=`"$grid`"/>"
  A (T $x ($barsEnd + 16) 11 $mute ([double]$v).ToString('0.0000', $inv) 'middle')
}
for ($r = 0; $r -lt $n; $r++) {
  $k = $n - 1 - $r                        # newest first
  $ser = $series[$k]; $c = $pal[$k % 6]
  $cy = $top + $r * $rowH + $rowH / 2
  if ($r % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $r * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  A "<rect x=`"36`" y=`"$($cy - 22)`" width=`"12`" height=`"12`" rx=`"3`" fill=`"$c`"/>"
  A (T 56 ($cy - 11) 14 $ink $ser.name 'start' '700')
  $dt = [string]$ser.data; if ($dt.Length -gt 62) { $dt = $dt.Substring(0, 60) + [char]0x2026 }
  A (T 36 ($cy + 5) 11 $ink $dt)
  A (T 36 ($cy + 20) 10 $mute "$($ser.detail) $dot $($ui.trainedAt) $($ser.finished) $dot $($ui.commit) $($ser.commit)")
  $v = $fin[$k]
  A "<rect x=`"$bx0`" y=`"$($cy - 10)`" width=`"$(F ((BX $v) - $bx0))`" height=`"20`" rx=`"3`" fill=`"$c`"/>"
  A (T ((BX $v) + 8) ($cy + 5) 12 $ink $v.ToString('0.000000', $inv) 'start' '700')
}
A (T 24 ($barsEnd + 46) 13 $ink $ui.lossBars 'start' '700')

# curves, first superbatches cut off so the spike does not flatten everything
$cut = 5
$cTop = $barsEnd + 100; $cH = 230; $cBy = $cTop + $cH
$lx0 = 90; $lx1 = 860
$vals = @(); foreach ($ser in $series) { foreach ($p in $ser.points) { if ($p[0] -ge $cut) { $vals += [double]$p[1] } } }
$ymin = ($vals | Measure-Object -Minimum).Minimum * 0.92; $ymax = ($vals | Measure-Object -Maximum).Maximum * 1.08
$maxX = 1; foreach ($ser in $series) { foreach ($p in $ser.points) { if ($p[0] -gt $maxX) { $maxX = $p[0] } } }
function LY($v) { $cTop + (1 - ([math]::Log10($v) - [math]::Log10($ymin)) / ([math]::Log10($ymax) - [math]::Log10($ymin))) * $cH }
function LXc($sb) { $lx0 + ($sb - $cut) / ($maxX - $cut) * ($lx1 - $lx0) }
A (T 24 ($cTop - 24) 13 $ink $ui.lossCurves 'start' '700')
foreach ($t in 0.0008, 0.001, 0.0012, 0.0015, 0.002) {
  if ($t -ge $ymin -and $t -le $ymax) {
    $y = LY $t
    A "<line x1=`"$lx0`" y1=`"$(F $y)`" x2=`"$lx1`" y2=`"$(F $y)`" stroke=`"$grid`"/>"
    A (T ($lx0 - 8) ($y + 4) 11 $mute ([double]$t).ToString('0.0000', $inv) 'end')
  }
}
for ($k = 0; $k -lt $n; $k++) {
  $c = $pal[$k % 6]
  $pts = ($series[$k].points | Where-Object { $_[0] -ge $cut } | ForEach-Object { "$(F (LXc $_[0])),$(F (LY $_[1]))" }) -join ' '
  $sw = if ($k -eq $n - 1) { 3 } else { 2 }
  A "<polyline points=`"$pts`" fill=`"none`" stroke=`"$c`" stroke-width=`"$sw`" stroke-linejoin=`"round`"/>"
  $last = $series[$k].points[$series[$k].points.Count - 1]
  A "<circle cx=`"$(F (LXc $last[0]))`" cy=`"$(F (LY $last[1]))`" r=`"4`" fill=`"$c`"/>"
}
foreach ($t in $cut, 50, 100, 150, 200) { if ($t -le $maxX) { A (T (LXc $t) ($cBy + 18) 11 $mute $t 'middle') } }
A (T (($lx0 + $lx1) / 2) ($cBy + 40) 12 $mute $ui.lossX 'middle')
$H = $cBy + 70
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.lossTitle 'docs/progress/loss.svg'

# =====================================================================
# Leaderboard-style charts (3-5): one row per item, horizontal bars, value at the bar end.
# =====================================================================
function Bar($xa, $xb, $cy, $bh, $col) {
  $x = [math]::Min($xa, $xb); $bw = [math]::Max(1, [math]::Abs($xb - $xa))
  A "<rect x=`"$(F $x)`" y=`"$(F ($cy - $bh / 2))`" width=`"$(F $bw)`" height=`"$bh`" rx=`"3`" fill=`"$col`"/>"
}
function Sgn($v) { if ($v -gt 0) { '+' } else { '' } }
function Head($title, $sub, $note) {
  A (T 24 38 22 $ink $title 'start' '700')
  A (T 24 58 13 $mute $sub)
  A "<rect x=`"24`" y=`"72`" width=`"$($W - 48)`" height=`"28`" rx=`"6`" fill=`"$band`"/>"
  A (T 40 91 11 $ink $note)
}
function Legend($items) {   # items: @(@(color, text), ...)
  $x = 36
  foreach ($it in $items) {
    A "<rect x=`"$x`" y=`"114`" width=`"14`" height=`"14`" rx=`"3`" fill=`"$($it[0])`"/>"
    A (T ($x + 20) 126 12 $ink $it[1])
    $x += 40 + 7 * ([string]$it[1]).Length
  }
}

# ---- 3) Strength by node limit -------------------------------------
$s = New-Object Text.StringBuilder
$rows = @($d.ladder | Sort-Object { [double]$_.nodes } -Descending)
$rowH = 44; $top = 146; $bx0 = 300; $bx1 = 790; $dmin = -350; $dmax = 600
function LX($v) { $bx0 + ($v - $dmin) / ($dmax - $dmin) * ($bx1 - $bx0) }
$by = $top + $rows.Count * $rowH; $H = $by + 56
Head $ui.ladderTitle $ui.ladderSub $ui.ladderNote
Legend @(, @($blue, $ui.ladderS6))
for ($t = -300; $t -le 600; $t += 100) {
  $x = LX $t
  A "<line x1=`"$(F $x)`" y1=`"$top`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$grid`"/>"
  A (T $x ($by + 16) 11 $mute $t 'middle')
}
$i = 0
foreach ($r in $rows) {
  $cy = $top + $i * $rowH + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $i * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  A (T 36 ($cy + 5) 14 $ink "$(([int]$r.nodes).ToString('N0', $inv)) $($ui.nodes)" 'start' '700')
  $v = $r.s6; $e = $v[0]
  Bar (LX 0) (LX $e) $cy 18 $blue
  $lab = "$(Sgn $e)$e $pm $($v[1])"
  if ($e -ge 0) { A (T ((LX $e) + 6) ($cy + 4) 12 $blue $lab 'start' '700') } else { A (T ((LX $e) - 6) ($cy + 4) 12 $blue $lab 'end' '700') }
  $i++
}
A "<line x1=`"$(F (LX 0))`" y1=`"$top`" x2=`"$(F (LX 0))`" y2=`"$by`" stroke=`"$ink`" stroke-width=`"1.5`"/>"
A (T (($bx0 + $bx1) / 2) ($by + 38) 12 $mute $ui.ladderY 'middle')
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.ladderTitle 'docs/progress/ladder.svg'

# ---- 4) What each search step added --------------------------------
$s = New-Object Text.StringBuilder
$rows = @($d.steps | Sort-Object { if ($null -ne $_.n10k) { -[double]$_.n10k[0] } else { -[double]$_.n50k[0] } })
$rowH = 50; $top = 146; $bx0 = 300; $bx1 = 780; $dmin = -40; $dmax = 160
function LX($v) { $bx0 + ($v - $dmin) / ($dmax - $dmin) * ($bx1 - $bx0) }
$by = $top + $rows.Count * $rowH; $H = $by + 56
Head $ui.stepsTitle $ui.stepsSub $ui.stepsNote
Legend @(@('#2a78d6', "10,000 $($ui.nodes)"), @('#9cc3ee', "50,000 $($ui.nodes)"))
for ($t = -40; $t -le 160; $t += 40) {
  $x = LX $t
  A "<line x1=`"$(F $x)`" y1=`"$top`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$grid`"/>"
  A (T $x ($by + 16) 11 $mute $t 'middle')
}
$i = 0
foreach ($st in $rows) {
  $cy = $top + $i * $rowH + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $i * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  A (T 36 ($cy - 3) 14 $ink $st.id 'start' '700')
  if ($st.rejected) { A (T (36 + 10 * ([string]$st.id).Length) ($cy - 3) 11 $red $ui.stepsRejected 'start' '700') }
  A (T 36 ($cy + 14) 11 $mute $st.what)
  $cols = @('#2a78d6', '#9cc3ee'); if ($st.rejected) { $cols = @('#898781', '#d7d5ce') }
  $li = 0
  foreach ($key in 'n10k', 'n50k') {
    $v = $st.$key
    if ($null -ne $v) {
      $e = $v[0]; $yy = $cy - 7 + 15 * $li; $bh = 14 - 5 * $li
      Bar (LX 0) (LX $e) $yy $bh $cols[$li]
      $lab = "$(Sgn $e)$e $pm $($v[1])"
      if ($e -ge 0) { A (T ((LX $e) + 6) ($yy + 4) 11 $ink $lab 'start' '700') } else { A (T ((LX $e) - 6) ($yy + 4) 11 $ink $lab 'end' '700') }
    }
    $li++
  }
  $i++
}
A "<line x1=`"$(F (LX 0))`" y1=`"$top`" x2=`"$(F (LX 0))`" y2=`"$by`" stroke=`"$ink`" stroke-width=`"1.5`"/>"
A (T (($bx0 + $bx1) / 2) ($by + 38) 12 $mute $ui.stepsY 'middle')
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.stepsTitle 'docs/progress/search-steps.svg'

# ---- 5) Our levels on the Stockfish UCI_Elo scale ------------------
$s = New-Object Text.StringBuilder
$rows = @($d.stockfish.levels | Sort-Object { -[double]$_.nodes })
$rowH = 50; $top = 168; $bx0 = 300; $bx1 = 800; $smin = 1250; $smax = 1650
function SX($v) { $bx0 + ($v - $smin) / ($smax - $smin) * ($bx1 - $bx0) }
$by = $top + $rows.Count * $rowH; $H = $by + 56
Head $ui.sfTitle $ui.sfSub $ui.sfNote
Legend @(@($blue, $ui.ladderS6), @($gray, $ui.ladderS1))
for ($v = 1300; $v -le 1600; $v += 100) {
  $x = SX $v
  A "<line x1=`"$(F $x)`" y1=`"$top`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$grid`"/>"
  A (T $x ($by + 16) 11 $mute $v 'middle')
}
foreach ($ru in $d.stockfish.rulers) {
  $x = SX $ru
  A "<line x1=`"$(F $x)`" y1=`"$($top - 10)`" x2=`"$(F $x)`" y2=`"$by`" stroke=`"$mute`" stroke-width=`"1.2`" stroke-dasharray=`"4 3`"/>"
  A (T $x ($top - 16) 11 $mute "SF $ru" 'middle' '700')
}
$i = 0
foreach ($r in $rows) {
  $cy = $top + $i * $rowH + $rowH / 2
  if ($i % 2 -eq 0) { A "<rect x=`"24`" y=`"$($top + $i * $rowH)`" width=`"$($W - 48)`" height=`"$rowH`" fill=`"$band`" opacity=`"0.7`"/>" }
  A (T 36 ($cy + 5) 14 $ink "$(([int]$r.nodes).ToString('N0', $inv)) $($ui.nodes)" 'start' '700')
  foreach ($ser in @(@('s6', $blue, -7, 14), @('s1', $gray, 8, 9))) {
    $v = $r.($ser[0]); $yy = $cy + $ser[2]
    if ($null -eq $v -or $v -lt 1320) {
      A (T ((SX $smin) + 6) ($yy + 4) 11 $ser[1] $ui.sfBelow 'start')
    } else {
      Bar (SX $smin) (SX $v) $yy $ser[3] $ser[1]
      A (T ((SX $v) + 6) ($yy + 4) 11 $ser[1] "~$v" 'start' '700')
    }
  }
  $i++
}
A (T (($bx0 + $bx1) / 2) ($by + 38) 12 $mute $ui.sfX 'middle')
A (T 24 ($H - 12) 10 $mute $ui.generated)
Save-Svg $s $W $H $ui.sfTitle 'docs/progress/stockfish.svg'
