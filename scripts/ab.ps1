# A/B match: a new engine against an old one at the same node limit (docs/EVALUATION.md section 3).
#
#   powershell -File scripts/ab.ps1                       # working tree vs HEAD
#   powershell -File scripts/ab.ps1 -New HEAD -Old c81e99b -Rounds 300
#   powershell -File scripts/ab.ps1 -Net nets/wyrd-v.bin -OldNet nets/wyrd-iv.bin   # net vs net (same engine build)
#
# -New / -Old: a git ref (built once from a temporary worktree and cached in tools/engines),
# WORKTREE for the uncommitted code in this checkout (always rebuilt), or the path of a .exe
# (e.g. a snapshot of an uncommitted baseline copied to tools/engines/).
# Needs tools/fastchess (see CLAUDE.md) and the opening book data/book.epd (made if missing).
# The verdict line applies the project rule: accept only if the lower bound of the Elo range is above 0.
param(
    [string]$New = 'WORKTREE',
    [string]$Old = 'HEAD',
    [string]$Net = 'nets/wyrd-iv.bin',
    [string]$OldNet = '',
    [int]$Nodes = 10000,
    [int]$Rounds = 300,
    [int]$Concurrency = 12,
    [string]$Tag = '',
    [string]$Book = 'data\book.epd',   # opening book (EPD), relative to the repo root; use another seed for an independent second set
    [int]$NewHash = -1   # transposition table size in KiB for the new engine only (default: the engine's own)
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$env:Path += ";$env:USERPROFILE\.cargo\bin"
$fastchess = "$root\tools\fastchess\fastchess-windows-x86-64\fastchess.exe"
if (-not (Test-Path $fastchess)) { throw "fastchess not found at $fastchess (see CLAUDE.md)" }
if (-not $OldNet) { $OldNet = $Net }
New-Item -ItemType Directory -Force "$root\tools\engines", "$root\logs" | Out-Null

function Get-Engine([string]$ref) {
    if ($ref -like '*.exe' -and (Test-Path $ref)) { return (Resolve-Path $ref).Path }   # a ready-made binary
    Push-Location $root
    try {
        if ($ref -eq 'WORKTREE') {
            Write-Host "building working tree..."
            cargo build --release -p wyrdmate-engine 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' }
            $dest = "$root\tools\engines\wyrdmate-wt-$(Get-Date -Format yyyyMMdd-HHmmss).exe"
            Copy-Item "$root\target\release\wyrdmate-engine.exe" $dest
            return $dest
        }
        $sha = (git rev-parse --short $ref).Trim()
        if ($LASTEXITCODE -ne 0) { throw "unknown git ref $ref" }
        $dest = "$root\tools\engines\wyrdmate-$sha.exe"
        if (Test-Path $dest) { Write-Host "using cached $dest"; return $dest }
        $wt = "$root\tools\build\$sha"
        Write-Host "building $ref ($sha) in a temporary worktree..."
        git worktree add --detach $wt $sha 2>&1 | Out-Host
        try {
            $env:CARGO_TARGET_DIR = "$root\tools\build\target"
            Push-Location $wt
            cargo build --release -p wyrdmate-engine 2>&1 | Out-Host
            $ok = ($LASTEXITCODE -eq 0)
            Pop-Location
            if (-not $ok) { throw 'cargo build failed' }
            Copy-Item "$root\tools\build\target\release\wyrdmate-engine.exe" $dest
        } finally {
            Remove-Item Env:\CARGO_TARGET_DIR -ErrorAction SilentlyContinue
            git worktree remove --force $wt 2>&1 | Out-Null
        }
        return $dest
    } finally { Pop-Location }
}

$newExe = Get-Engine $New
$oldExe = Get-Engine $Old

if (($Book -eq 'data\book.epd') -and -not (Test-Path "$root\data\book.epd")) {
    Push-Location $root
    cargo run --release -p wyrdmate-engine --example book -- 300 99 data\book.epd 2>&1 | Out-Host
    Pop-Location
}

$bookLines = @(Get-Content "$root\$Book" | Where-Object { $_.Trim() }).Count
if ($Rounds -gt $bookLines) {
    Write-Warning "Rounds ($Rounds) is more than the $bookLines openings in ${Book}: openings repeat and node-limited games repeat exactly, so the extra games are copies and the error bar is too small. Use more openings (-Book) instead."
}

$name = if ($Tag) { $Tag } else { "$([IO.Path]::GetFileNameWithoutExtension($newExe))-vs-$([IO.Path]::GetFileNameWithoutExtension($oldExe))" }
$pgn = "$root\logs\ab-$name.pgn"
$txt = "$root\logs\ab-$name.txt"

$fc = @(
    '-engine', 'name=new', "cmd=$newExe", "option.EvalFile=$root\$Net", "option.Nodes=$Nodes",
    '-engine', 'name=old', "cmd=$oldExe", "option.Nodes=$Nodes",
    '-each', 'proto=uci', 'tc=inf', "nodes=$Nodes",
    '-openings', "file=$root\$Book", 'format=epd', 'order=random',
    '-rounds', $Rounds, '-games', 2, '-repeat', '-concurrency', $Concurrency, '-maxmoves', 120,
    '-draw', 'movenumber=30', 'movecount=8', 'score=10', '-resign', 'movecount=4', 'score=800',
    '-pgnout', "file=$pgn"
)
if ($NewHash -ge 0) { $fc = $fc[0..4] + @("option.Hash=$NewHash") + $fc[5..($fc.Count - 1)] }
# old engine: a net unless OldNet is 'material'
if ($OldNet -ne 'material') { $fc = $fc[0..8] + @("option.EvalFile=$root\$OldNet") + $fc[9..($fc.Count - 1)] }

Write-Host "new: $newExe ($Net)"
Write-Host "old: $oldExe ($OldNet)"
Write-Host "nodes=$Nodes, $($Rounds * 2) games, log: $txt"
# sidecar for scripts/monitor.py: which nets played, so the page can name them
[ordered]@{ new = $Net; old = $OldNet; nodes = $Nodes; games = $Rounds * 2; book = $Book; started = (Get-Date -Format 'yyyy-MM-dd HH:mm') } |
    ConvertTo-Json | Set-Content -Encoding UTF8 "$root\logs\ab-$name.meta.json"
& $fastchess @fc > $txt 2>&1

$tail = Get-Content $txt -Tail 25
$tail | Select-String -Pattern 'Elo|Games|LOS|Ptnml|Total Time' | ForEach-Object { $_.Line }
$m = [regex]::Match(($tail -join "`n"), 'Elo:\s*(-?[\d.]+)\s*\+/-\s*([\d.]+|nan)')
if ($m.Success -and $m.Groups[2].Value -ne 'nan') {
    $lo = [double]$m.Groups[1].Value - [double]$m.Groups[2].Value
    if ($lo -gt 0) { Write-Host "VERDICT: lower bound $([math]::Round($lo,1)) > 0 -> passes the rule (rule 2)" }
    else { Write-Host "VERDICT: lower bound $([math]::Round($lo,1)) <= 0 -> NOT accepted by the rule (rule 2)" }
} else { Write-Host 'VERDICT: could not read the Elo line; check the log' }
