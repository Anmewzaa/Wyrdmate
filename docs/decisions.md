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
