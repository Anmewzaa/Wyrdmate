# CLAUDE.md

Claude Code reads this file automatically. It is the **single guide** for working
on Wyrdmate — goal, hard rules, layout, verification, environment. Read it
instead of re-exploring the repo; keep it short and update it when facts change.

Wyrdmate is a small "weak but clever" chess AI for ESP32-class boards (an IoT
wizard-chess board). Rust engine + a tiny NNUE evaluation net trained
**supervised** with [bullet](https://github.com/jw1912/bullet) (not AlphaZero-style
RL). The product runs `no_std` on the board; training and datagen run on a PC.

**Decisions are in `docs/decisions.md`** (name, bullet, monorepo, cozy-chess).
Don't re-open them unless the user does. For a file-by-file tour read
`docs/STRUCTURE.md` (Thai, for humans).

> Status: engine (search + NNUE eval + UCI), datagen and the bullet trainer work.
> Accepted nets: `wyrd-i` (teacher only), `wyrd-ii`, `wyrd-iii` (current: +81 +/- 22
> Elo vs wyrd-ii, +166 +/- 25 vs the material eval; 600 games, 10k nodes). Provenance
> and failed experiments: `nets/RECORDS.md`; training recipe: decision D-010.
> Results are only vs our own earlier versions, never vs outside engines.
> Next: more self-play rounds while Elo still rises, strength levels measured in Elo,
> incremental accumulator, then the `no_std` firmware (nothing has run on a board).

## Start here — read only what your task needs

| Task | Read |
|---|---|
| Anything (always) | this file |
| Search / eval / movegen | `engine/src/lib.rs` (one file) |
| Training data | `datagen/src/main.rs` (one file) |
| Training / net shape | `trainer/src/main.rs`, bullet `examples/` (see Hard rule 4) |
| ESP32 / `no_std` | `firmware/`, then bullet's example inference code |
| What exists / why | `docs/STRUCTURE.md`, `docs/decisions.md` |
| How a net is made, step by step | `docs/TRAINING.md` |
| Which nets exist and how they were made | `nets/RECORDS.md` |

## Hard rules (never violate — these are the project, not preferences)

1. **Reproducible nets.** Every net committed to `nets/` records: git commit
   hash, the bullet config (the `trainer` args and rev), and the data used
   (datagen seed, nodes, game count). A net without that record is not accepted.
2. **No net merges without a match.** A new net replaces the old one only after
   hundreds of games against it (`fastchess` / `cutechess-cli`) show a gain
   beyond the error bar. Lower loss alone proves nothing.
3. **Training data and checkpoints never go in git.** `data/`, `checkpoints/`,
   `target/`, `*.binpack` are ignored. Only small quantised nets are committed.
   Store seed + config so data is regenerable.
4. **bullet is pinned to a git rev, never crates.io** (`bullet_lib` 1.0.0 there
   is yanked) and its API changes often: read `examples/` from a shallow clone in
   the scratchpad, never write bullet code from memory. Bumping the rev is a
   deliberate change.
5. **Firmware stays `no_std` and in budget.** ESP32 has ~520 KB SRAM. Net
   weights int16/int8, incremental accumulator, no allocation in the search hot
   path of firmware code. `firmware/` is excluded from the workspace and built
   with its own target.
6. **Strength is a feature.** The engine is meant to be *weak but clever*:
   strength is limited by `node_limit`/depth and randomness, never by hidden
   hacks. Keep the limit an explicit, documented parameter.
7. **Honest results.** Report failing tests, unverified steps and skipped
   checks as they are. Never claim a net is "better" without match numbers.

## Working rules

- Read affected files before editing. Keep each change focused; no unrelated
  refactors, renames or reformatting.
- Add or update tests for behaviour changes, and update the matching doc
  (`docs/STRUCTURE.md` when files are added; `docs/decisions.md` when a decision
  changes — add a new D-xxx entry, never rewrite an old one).
- Prefer the smallest correct change. If two readings of a request differ
  materially, stop and ask.
- Ask before system-level installs (CUDA, build tools) and before downloads;
  verify installer signatures. Never commit secrets or tokens.
- Don't re-check name availability (crates.io / GitHub / domain); the only
  unverified item is trademark/domain.

## Directory ownership

- `engine/` — `wyrdmate-engine`: `cozy-chess` movegen, material eval (baseline)
  and NNUE eval (`src/nnue.rs`, recomputed from scratch each call, not yet
  incremental), negamax + alpha-beta + quiescence + iterative deepening,
  `node_limit`. Public: `Searcher::new(node_limit).with_net(net).search(&board,
  max_depth) -> Option<(Move, cp)>`, `evaluate`, `legal_moves`. Scores are
  centipawns, side to move POV. `src/main.rs` is the UCI front end (options `Nodes`,
  `EvalFile`). `examples/validate.rs` checks a net against stored scores,
  `examples/book.rs` makes opening books. **Highest-value tests live here; never weaken them.**
- `datagen/` — self-play → text lines `FEN | score_cp_white_pov | result` where
  result is `1.0` / `0.5` / `0.0` (white POV), the bullet text format. Usage:
  `wyrdmate-datagen [games] [nodes] [seed] [out] [net.bin]` (net optional: it plays).
- `trainer/` — bullet driver: `(768 -> 32)x2 -> 1`, screlu, i16 quantisation
  (QA 255, QB 64, scale 400). Usage: `wyrdmate-trainer <data.data> [superbatches]
  [batches_per_sb] [batch_size] [wdl=0.5] [net_id=wyrd]` (use wdl 0.0, D-010).
  Feature `cuda` enables the GPU backend.
- `firmware/` — `no_std` ESP32 inference. Not a workspace member. Skeleton only.
- `nets/` — quantised nets plus their records (`RECORDS.md`, rule 1).
- `docs/` — `STRUCTURE.md` (human tour), `TRAINING.md` (how a net is made),
  `decisions.md`, `progress/` (chart data + generated SVGs).
- `scripts/` — `make-progress-svg.ps1`.
- Git-ignored: `target/`, `checkpoints/`, `data/`, `*.binpack`.

## Compatibility surfaces (preserve or migrate; don't break silently)

- **Datagen text format** — consumed by `bullet-utils convert --from text`.
- **Net format and `trainer` architecture** — engine/firmware inference must
  match the trainer's layout, quantisation (QA/QB/scale) and feature order.
  Change both sides together and retrain.
- **Search public API** — used by datagen and (later) the UCI front end.

## Verification

```bash
cargo test -p wyrdmate-engine        # fast loop while iterating
cargo check                          # whole workspace (firmware excluded)
cargo fmt --check && cargo clippy --workspace   # when touching Rust
```

A net change additionally needs the A/B match (rule 2). Docs-only changes don't
need the Rust stack — say so in the commit.

Data → net flow:

```text
wyrdmate-datagen → data/X.txt
bullet-utils convert --from text --input data/X.txt --output data/X.data
   (build bullet-utils from the bullet repo, crates/utils)
wyrdmate-trainer data/X.data [...]  (--features cuda) → checkpoints/wyrd-N/
```

## Environment (Windows 11, user machine)

- Rust stable via rustup. `cargo` is **not** on PATH in new shells —
  PowerShell: `$env:Path += ";$env:USERPROFILE\.cargo\bin"`; Bash:
  `export PATH="$PATH:$HOME/.cargo/bin"`. Cargo prints progress to stderr, so
  PowerShell shows a harmless `NativeCommandError`; judge by exit code/output.
- MSVC Build Tools (C++) + Windows SDK installed.
- No `winget`. Use official installers and verify their signature.
- GPU: NVIDIA RTX 4060 8 GB, driver 610.88 (supports CUDA up to 13.3).
  bullet `cuda` needs the full Toolkit (links cuda, cudart, nvrtc, cublas),
  env var `CUDA_PATH` set (dirs `bin`/`lib`/`include`), and a Toolkit version
  not newer than the driver supports. CUDA 13.3.1 is installed (official network
  installer; `CUDA_PATH` set by it). To RUN a `--features cuda` binary put
  `%CUDA_PATH%\bin\x64` on PATH and launch from PowerShell (Git Bash fails with
  "cublas64_13.dll not found"). First run: 1.25M positions, 20 superbatches took
  ~2 s on the 4060; loss 0.0139 -> 0.0064 (low partly because ~80% of games are draws).
- cozy-chess 0.3.4: `Board::default()`, `generate_moves(|ms| { ..; false })`,
  `play_unchecked`, `status()` (`Won` = side to move is mated), `to_string()` = FEN.

## Saving tokens

- Engine and datagen are one file each; read only what you need.
- Iterate with `cargo test -p wyrdmate-engine`, not full-workspace builds.
- Don't re-derive decisions; don't re-explore the repo — this file is the map.

## Commits

Focused commits with imperative messages. End each with the Co-Authored-By line
from the session's attribution reminder. Don't push unless asked.

## A/B match recipe (fastchess)

Binary is not in the repo (download `fastchess-windows-x86-64.zip`, v1.8.3-alpha,
from github.com/Disservin/fastchess releases). Openings: `cargo run --release -p
wyrdmate-engine --example book -- 300 99 data/book.epd`. Run from PowerShell:

```text
fastchess -engine name=new cmd=<engine.exe> option.EvalFile=<quantised.bin> -engine name=old cmd=<engine.exe>
  -each proto=uci tc=inf nodes=10000 option.Nodes=10000 -openings file=data/book.epd format=epd order=random
  -rounds 300 -games 2 -repeat -concurrency 4 -maxmoves 120
  -draw movenumber=30 movecount=8 score=10 -resign movecount=4 score=800
```

`cargo run --release -p wyrdmate-engine --example validate -- <net> <data.txt>`
checks a net against stored scores (correlation ~0.83 means the inference matches).

## Progress page

Data: `docs/progress/data.json` (strict JSON; the generator parses it; all chart text lives in its `ui` block).
After **every** A/B match add a row to `matches` (net, vs, elo, err, games, accepted, finished, commit);
after a training run worth keeping add a series to `loss` (name, detail, data, finished, commit, points).
Then regenerate the two charts shown in the README and commit them with the data:

```text
powershell -File scripts/make-progress-svg.ps1   # writes docs/progress/training-process.svg and loss.svg
```

