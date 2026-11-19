# Decisions

Append new entries; never rewrite old ones (supersede with a new D-xxx).

- **D-001 Name: Wyrdmate** (wyrd = fate + mate). Rejected: Hexmate (existing
  hex-chess, used Lichess account), Spellmate (itch.io game). Crates.io/GitHub/
  domain/trademark availability not exhaustively verified.
- **D-002 Training: bullet, supervised NNUE.** Not AlphaZero-style RL. bullet
  pinned to a git rev (crates.io `bullet_lib` 1.0.0 is yanked).
- **D-003 Repo: monorepo, Cargo workspace** (`engine`, `datagen`, `trainer`;
  `firmware` excluded, `nets/` for artefacts).
- **D-004 Movegen: `cozy-chess`**; search written in-house.
- **D-005 Loop:** simple eval → self-play with fixed nodes → train → replace eval
  → repeat (or seed with ready-made data).
- **D-006 Net:** start `768 -> (16–64)x2 -> 1`, STM/NSTM perspectives, quantised
  int16/int8; trainer currently uses hidden size 32.
- **D-007 Files:** quantised nets are committed (embedded in firmware with
  `include_bytes!`); checkpoints and training data are not (data may live in
  object storage / Hugging Face; Git LFS if nets grow).
- **D-008 Discipline:** record git hash + bullet config + data for every net;
  A/B match (hundreds of games) before accepting; tag the version flashed to a
  board.
- **D-009 Docs:** `CLAUDE.md` is the single agent guide (replaces the earlier
  `AGENT.md`), modelled on the TerraFlow project's.
- **D-010 Training recipe (from experiments, 600-game matches vs the previous best):**
  train with `wdl 0.0` (fit the engine's search scores, not game results), 200
  superbatches, and from round 3 on train on the data of **all rounds combined**.
  Evidence: wdl 0.5 gave -148 +/- 24 Elo vs the material eval, wdl 0.3 gave -35 +/-
  19 (round-2 data) while wdl 0.0 gave +115 +/- 23; round-3 data alone gave +63 +/-
  22 vs wyrd-ii, rounds 2+3 together +81 +/- 22. The explanation (game results are
  noisy when most games are draws; more varied data helps) is a hypothesis, not
  tested separately. Revisit if the data stops being draw-heavy.
