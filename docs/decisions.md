# Decision log

Records the significant design decisions of Wyrdmate and the reasons behind them.

**Rules**

- Append new entries; never rewrite old ones (supersede with a new `D-xxx`).
- Each entry states the decision first, then the reason or evidence.
- Where evidence is a hypothesis rather than a tested fact, the entry says so.

**Index**

| ID | Topic |
|---|---|
| D-001 | Project name |
| D-002 | Training approach (bullet, supervised) |
| D-003 | Repository layout |
| D-004 | Move generation |
| D-005 | Development loop |
| D-006 | Net architecture |
| D-007 | Which files are committed |
| D-008 | Process discipline for nets |
| D-009 | Documentation layout |
| D-010 | Training recipe |
| D-011 | Documentation language and layout (supersedes the layout part of D-009) |

Related: [ARCHITECTURE.md](ARCHITECTURE.md) (Thai), [`../nets/RECORDS.md`](../nets/RECORDS.md).

---

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
- **D-011 Docs language and layout:** `docs/` prose stays Thai, but key technical terms
  are kept in English and not translated (hidden layer, weights, search, evaluation,
  pruning, node, centipawn, ...); `GLOSSARY.md` lists them. Each fact lives in one
  document and the others link to it (measurements in `EVALUATION.md`, net structure in
  the new `NET.md`, file tour in `STRUCTURE.md`). Reason: translated terms such as
  "ชั้นซ่อน" for hidden layer made the documents harder to match with outside material.
- **D-012 Training recipe update (supersedes the `wdl 0.0` part of D-010):** train with `wdl 0.1` from round 8 on
  (the rest of D-010 stays: 200 superbatches, all rounds' data combined). Evidence, same round-8 data and recipe, vs `wyrd-vii`, 600
  games each: wdl 0.0 gave -9 +/- 25 (10k nodes) and -12 +/- 24 (50k); wdl 0.1 gave +57 +/- 26 / +80 +/- 25 (and +79 / +63 on a
  second opening book); wdl 0.2 +20 / +38; wdl 0.3 -60 / -22; wdl 0.4 -114 / -113. A small share of the real game result helps,
  a large one hurts. Hypothesis (not tested separately): the search scores come from the previous net, so a little real outcome
  information corrects its bias; the game results are noisy, so more than a little hurts. One training run per value: the
  run-to-run variation is not known. D-010's reason for wdl 0.0 (most games drawn) no longer holds (about 46% draws now).
