# Regenerates docs/progress/progress.svg from docs/progress/data.js.
# Run from the repo root:  powershell -File scripts/make-progress-svg.ps1
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path -Parent $PSScriptRoot
$js = Get-Content (Join-Path $root 'docs/progress/data.js') -Raw
$json = ($js -replace '^\s*window\.WYRD_DATA\s*=\s*', '') -replace ';\s*$', ''
$d = $json | ConvertFrom-Json
function F($x) { ([double]$x).ToString('0.##', $inv) }
function Esc($s) { [Security.SecurityElement]::Escape($s) }

$W = 760; $ink = '#1f1f1e'; $mute = '#6b6a66'; $grid = '#e1e0d9'
$blue = '#2a78d6'; $red = '#e34948'; $gray = '#898781'
$rows = @($d.matches)
$px0 = 250; $px1 = 725
$lim = [math]::Ceiling((($rows | ForEach-Object { [math]::Abs($_.elo) + $_.err } | Measure-Object -Maximum).Maximum + 50) / 50) * 50
$step = if ($lim -gt 250) { 100 } else { 50 }
function X($v) { $px0 + ($v + $lim) / (2 * $lim) * ($px1 - $px0) }

$eloTop = 70; $rowH = 44; $eloH = $rows.Count * $rowH
$axisY = $eloTop + $eloH + 6
$lossTop = $axisY + 90; $lossH = 220
$H = $lossTop + $lossH + 60

$s = New-Object Text.StringBuilder
[void]$s.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$W`" height=`"$H`" viewBox=`"0 0 $W $H`" font-family=`"Segoe UI,Helvetica,Arial,sans-serif`" role=`"img`" aria-label=`"Wyrdmate progress: match Elo per net and training loss`">")
[void]$s.AppendLine("<rect width=`"$W`" height=`"$H`" fill=`"#ffffff`"/>")
[void]$s.AppendLine("<text x=`"20`" y=`"32`" font-size=`"20`" font-weight=`"600`" fill=`"$ink`">Wyrdmate progress</text>")
[void]$s.AppendLine("<text x=`"20`" y=`"54`" font-size=`"12`" fill=`"$mute`">Strength vs opponent in Elo (0 = equal). Whisker = error margin; blue accepted, red worse, gray inconclusive.</text>")

# grid + axis labels
for ($v = -$lim; $v -le $lim; $v += $step) {
  $x = F (X $v)
  [void]$s.AppendLine("<line x1=`"$x`" y1=`"$eloTop`" x2=`"$x`" y2=`"$axisY`" stroke=`"$grid`"/>")
  [void]$s.AppendLine("<text x=`"$x`" y=`"$($axisY + 16)`" font-size=`"11`" fill=`"$mute`" text-anchor=`"middle`">$v</text>")
}
$zx = F (X 0)
[void]$s.AppendLine("<line x1=`"$zx`" y1=`"$eloTop`" x2=`"$zx`" y2=`"$axisY`" stroke=`"$mute`"/>")
[void]$s.AppendLine("<text x=`"$zx`" y=`"$($axisY + 32)`" font-size=`"11`" fill=`"$mute`" text-anchor=`"middle`">Elo</text>")

$i = 0
foreach ($r in $rows) {
  $cy = $eloTop + $i * $rowH + $rowH / 2
  $col = if ($r.accepted) { $blue } elseif (($r.elo + $r.err) -lt 0) { $red } else { $gray }
  $x0 = X 0; $x1 = X $r.elo
  $bx = F ([math]::Min($x0, $x1)); $bw = F ([math]::Abs($x1 - $x0))
  [void]$s.AppendLine("<text x=`"$($px0 - 12)`" y=`"$($cy - 3)`" font-size=`"12`" fill=`"$ink`" text-anchor=`"end`">$(Esc $r.net)</text>")
  [void]$s.AppendLine("<text x=`"$($px0 - 12)`" y=`"$($cy + 12)`" font-size=`"11`" fill=`"$mute`" text-anchor=`"end`">vs $(Esc $r.vs)</text>")
  [void]$s.AppendLine("<rect x=`"$bx`" y=`"$(F ($cy - 10))`" width=`"$bw`" height=`"20`" rx=`"3`" fill=`"$col`"/>")
  $lo = X ($r.elo - $r.err); $hi = X ($r.elo + $r.err)
  [void]$s.AppendLine("<path d=`"M$(F $lo) $(F $cy)H$(F $hi)M$(F $lo) $(F ($cy-5))V$(F ($cy+5))M$(F $hi) $(F ($cy-5))V$(F ($cy+5))`" stroke=`"$ink`" stroke-width=`"1.5`" fill=`"none`"/>")
  $sign = if ($r.elo -gt 0) { '+' } else { '' }
  $pm = [char]0x00B1
  $label = "$sign$($r.elo) $pm $($r.err)"
  if ($r.elo -ge 0) { $tx = $hi + 8; $anchor = 'start' } else { $tx = $lo - 8; $anchor = 'end' }
  [void]$s.AppendLine("<text x=`"$(F $tx)`" y=`"$(F ($cy + 4))`" font-size=`"12`" fill=`"$ink`" text-anchor=`"$anchor`">$label</text>")
  $i++
}

# loss chart (log y)
$lx0 = 70; $lx1 = 725; $ymin = 0.0005; $ymax = 0.02
function LY($v) { $lossTop + 30 + (1 - ([math]::Log10($v) - [math]::Log10($ymin)) / ([math]::Log10($ymax) - [math]::Log10($ymin))) * ($lossH - 30) }
[void]$s.AppendLine("<text x=`"20`" y=`"$($lossTop + 8)`" font-size=`"14`" font-weight=`"600`" fill=`"$ink`">Training loss (log scale, lower = predicts stored scores better)</text>")
foreach ($t in 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02) {
  $y = F (LY $t)
  [void]$s.AppendLine("<line x1=`"$lx0`" y1=`"$y`" x2=`"$lx1`" y2=`"$y`" stroke=`"$grid`"/>")
  [void]$s.AppendLine("<text x=`"$($lx0 - 8)`" y=`"$(F ([double]$y + 4))`" font-size=`"11`" fill=`"$mute`" text-anchor=`"end`">$(([double]$t).ToString("0.####", $inv))</text>")
}
$maxRound = 1
foreach ($p in $d.loss.PSObject.Properties) { foreach ($q in $p.Value) { if ($q[0] -gt $maxRound) { $maxRound = $q[0] } } }
$pal = @('#2a78d6', '#eb6834', '#1baf7a', '#6250d6'); $k = 0
foreach ($p in $d.loss.PSObject.Properties) {
  $pts = ($p.Value | ForEach-Object { "$(F ($lx0 + $_[0] / $maxRound * ($lx1 - $lx0))),$(F (LY $_[1]))" }) -join ' '
  [void]$s.AppendLine("<polyline points=`"$pts`" fill=`"none`" stroke=`"$($pal[$k % 4])`" stroke-width=`"2`" stroke-linejoin=`"round`"/>")
  [void]$s.AppendLine("<text x=`"$lx1`" y=`"$($lossTop + 28 + 14 * $k)`" font-size=`"11`" fill=`"$($pal[$k % 4])`" text-anchor=`"end`">$(Esc $p.Name)</text>")
  $k++
}
$by = $lossTop + $lossH + 18
foreach ($t in 0, 50, 100, 150, 200) { if ($t -le $maxRound) { [void]$s.AppendLine("<text x=`"$(F ($lx0 + $t / $maxRound * ($lx1 - $lx0)))`" y=`"$by`" font-size=`"11`" fill=`"$mute`" text-anchor=`"middle`">$t</text>") } }
[void]$s.AppendLine("<text x=`"$(F (($lx0 + $lx1) / 2))`" y=`"$($by + 18)`" font-size=`"11`" fill=`"$mute`" text-anchor=`"middle`">training round</text>")
[void]$s.AppendLine('</svg>')

$out = Join-Path $root 'docs/progress/progress.svg'
[IO.File]::WriteAllText($out, $s.ToString(), (New-Object Text.UTF8Encoding($false)))
"wrote $out ($($s.Length) chars)"
