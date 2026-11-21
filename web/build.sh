#!/usr/bin/env bash
# Same as build.ps1 for Linux/macOS/CI: builds the static web version into web/dist.
# Needs: rustup target add wasm32-unknown-unknown
set -euo pipefail
cd "$(dirname "$0")/.."

(cd web && cargo build --release --locked --target wasm32-unknown-unknown)

D=web/dist
rm -rf "$D"
mkdir -p "$D/nets"
cp web/target/wasm32-unknown-unknown/release/wyrdmate_web.wasm "$D/wyrd.wasm"
cp web/backend.js "$D/backend.js"
cp nets/*.bin "$D/nets/"

names=$(cd nets && ls ./*.bin | sed 's#^\./##; s/\.bin$//' | sort | sed 's/.*/"&"/' | paste -sd, -)
printf '{"nets":[%s,"material"],"default":"wyrd-viii"}\n' "$names" > "$D/nets.json"

# The page is the same one scripts/play.py serves; only the backend script is added.
sed 's#</head>#<script src="backend.js"></script>\n</head>#' scripts/play.html > "$D/index.html"

ls -l "$D" "$D/nets"
