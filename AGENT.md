# Wyrdmate — agent notes

Read this first; it replaces re-exploring the repo. Keep it short and update it when facts change.

## Goal
Small "weak but clever" chess engine for ESP32-class boards (IoT wizard-chess board).
Rust. NNUE trained supervised with bullet (jw1912/bullet), not AlphaZero-style RL.

## Layout (Cargo workspace)
- `engine/`   wyrdmate-engine: cozy-chess movegen, material eval, negamax+alpha-beta+quiescence, node limit. Public: `Searcher::new(node_limit).search(&board, max_depth) -> Option<(Move, cp)>`, `evaluate`, `legal_moves`.
- `datagen/`  self-play -> text lines `FEN | score_cp_white_pov | result(1.0/0.5/0.0 white POV)` (bullet text format). Usage: `wyrdmate-datagen [games] [nodes] [seed] [out]`.
- `trainer/`  bullet training driver (see status below).
- `firmware/` no_std ESP32 inference. NOT a workspace member (`exclude`); build separately.
- `nets/`     quantised nets (small, commit them). Record git hash + bullet config + data used.
- git-ignored: `target/`, `checkpoints/`, `data/`, `*.binpack`.

## Status
- [x] workspace, engine (3 tests pass), datagen (verified: 20 games ~1.4s)
- [x] trainer compiles (bullet pinned to rev 5d70177 via git; `cuda` feature off by default). NOT yet run: needs CUDA Toolkit.
  Flow: datagen text -> `bullet-utils convert --from text --input X.txt --output X.data` (bullet-utils: build from bullet repo `crates/utils`) -> `wyrdmate-trainer X.data [superbatches] [batches_per_sb] [batch_size]` -> `checkpoints/wyrd-N/`.
- [ ] first net -> replace `evaluate`, then loop datagen -> train
- [ ] A/B test new net vs old (fastchess / cutechess-cli, hundreds of games) before merging
- [ ] no_std inference port, incremental accumulator, int16/int8 quantisation
- Planned net: `768 -> (16-64)x2 -> 1`, STM/NSTM perspectives.

## Environment (Windows 11, user machine)
- Rust stable installed via rustup; cargo is NOT on PATH in new shells. In PowerShell: `$env:Path += ";$env:USERPROFILE\.cargo\bin"`; in Bash: `export PATH="$PATH:$HOME/.cargo/bin"`.
- MSVC Build Tools (C++) + Windows SDK installed.
- GPU: NVIDIA RTX 4060 8 GB, driver 610.88 (supports CUDA up to 13.3). CUDA Toolkit NOT installed yet. bullet needs: full Toolkit (links cuda, cudart, nvrtc, cublas), newest version <= 13.3 recommended, env var `CUDA_PATH` set (dirs bin/lib/include), build with `--features cuda`. Ask the user before the big system install.
- No `winget`. Use official installers, verify signature.
- Cargo prints progress to stderr: PowerShell shows a harmless NativeCommandError; judge by exit code/output.

## Conventions
- cozy-chess 0.3.4 API: `Board::default()`, `board.generate_moves(|ms| {..; false})`, `play_unchecked`, `status() -> Ongoing/Won(side to move is mated)/Drawn`, `board.to_string()` = FEN.
- Eval/search scores are centipawns, side-to-move POV; datagen converts to white POV.
- Commit messages end with the Co-Authored-By line from the session's attribution reminder.
- Don't re-check name availability (crates.io/GitHub/domain) unless asked; only unverified item is trademark/domain.

## Saving tokens
- Don't re-derive decisions above (name, bullet, monorepo, cozy-chess).
- Read only the file you need; engine is one file (`engine/src/lib.rs`), datagen one file.
- Run `cargo test -p wyrdmate-engine` rather than whole-workspace builds when iterating.
- bullet's API changes often: read its `examples/` from a shallow clone in the scratchpad, don't guess from memory.
