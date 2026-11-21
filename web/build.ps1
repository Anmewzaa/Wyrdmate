# Builds the static web version into web/dist (git-ignored): wyrd.wasm, nets, page.
# Run from anywhere:  powershell -File web/build.ps1
# Then try it locally:  python -m http.server 8002 --directory web/dist
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:Path += ";$env:USERPROFILE\.cargo\bin"

Push-Location "$root\web"
try {
    cargo build --release --target wasm32-unknown-unknown
    if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' }
} finally { Pop-Location }

$dist = "$root\web\dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force "$dist\nets" | Out-Null

Copy-Item "$root\web\target\wasm32-unknown-unknown\release\wyrdmate_web.wasm" "$dist\wyrd.wasm"
Copy-Item "$root\web\backend.js" "$dist\backend.js"
Copy-Item "$root\nets\*.bin" "$dist\nets\"

# The page is the same one scripts/play.py serves; only the backend script is added.
$names = (Get-ChildItem "$root\nets\*.bin" | Sort-Object Name | ForEach-Object { $_.BaseName }) + 'material'
$json = @{ nets = @($names); default = 'wyrd-ix' } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText("$dist\nets.json", $json, (New-Object System.Text.UTF8Encoding($false)))
$page = Get-Content -Raw -Encoding utf8 "$root\scripts\play.html"
$page = $page.Replace('</head>', "<script src=`"backend.js`"></script>`n</head>")
[System.IO.File]::WriteAllText("$dist\index.html", $page, (New-Object System.Text.UTF8Encoding($false)))

Get-ChildItem $dist -Recurse -File | Select-Object @{n='file';e={$_.FullName.Substring($dist.Length + 1)}}, Length
