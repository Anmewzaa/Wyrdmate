# Net records

Every net here lists what is needed to reproduce it (CLAUDE.md, rule 1).
Architecture for all: `(768 -> 32)x2 -> 1`, SCReLU, QA 255, QB 64, scale 400.
Format: bullet `quantised.bin` (load with `Network::load` / UCI option `EvalFile`).
Trainer: bullet rev `5d70177680437b7c0ddf958bd4722d95afa78b0c`, batch 16384,
76 batches/superbatch, 200 superbatches, lr 0.001 stepped x0.1 at 3/4, AdamW.

## wyrd-ii.bin — ACCEPTED (current best)

- Code commit for tooling: `c3ed243` (datagen with net support, trainer wdl arg).
- Data: round 2 self-play, 4 runs x 2500 games, seeds 31-34, 5000 nodes/move,
  played by `wyrd-i.bin`; 1,274,079 positions.
  `wyrdmate-datagen 2500 5000 <seed> data/r2partSEED.txt nets/wyrd-i.bin`
  then `bullet-utils convert --from text`, `shuffle`.
- Training: `wyrdmate-trainer data/r2train.data 200 76 16384 0.0 r2a` (wdl 0.0).
- Final running loss 0.000823.
- Match (fastchess, 600 games, 10000 nodes, 300 random 8-ply openings x2 colours):
  vs material eval **+115 +/- 23 Elo**; vs wyrd-i **+117 +/- 22 Elo**.

## wyrd-i.bin — teacher only (not accepted as a strength gain)

- Data: round 1 self-play with the material eval, 4 runs x 2500 games, seeds 11-14,
  5000 nodes/move; 1,249,336 positions (80% draws). Tooling commit `472c8e7`
  (datagen of that time had no net argument; material eval only).
- Training: `wyrdmate-trainer data/train.data 200 76 16384 0.0 w0`.
- Match vs material eval, 600 games: +14 +/- 20 Elo (not significant).
- Kept because wyrd-ii's data was generated with it.

## Rejected experiments (not committed)

- wdl 0.5, 20 superbatches on round-1 data: -148 +/- 24 vs material.
- wdl 0.3, 200 superbatches on round-2 data: -35 +/- 19 vs material, -76 +/- 19 vs wyrd-i.

## wyrd-iii.bin — ACCEPTED (current best)

- Tooling: commit `c3ed243` (datagen with net argument, trainer with wdl/net_id args; unchanged through round 3).
- Data: round-3 self-play (4 runs x 2500 games, seeds 41-44, 5000 nodes/move, played by
  `wyrd-ii.bin`; 1,139,979 positions) **plus all round-2 data** (1,274,079 positions) = 2,414,058 positions.
  `wyrdmate-datagen 2500 5000 <seed> data/r3partSEED.txt nets/wyrd-ii.bin`, concatenated with the round-2 file,
  then `bullet-utils convert --from text`, `shuffle`.
- Training: `wyrdmate-trainer data/r23train.data 200 152 16384 0.0 r23a` (wdl 0.0;
  152 batches/superbatch ~ one pass over the larger set). Final running loss 0.000964.
- Match (fastchess, 600 games, 10000 nodes, same book as before):
  vs wyrd-ii **+81 +/- 22 Elo**; vs material eval **+166 +/- 25 Elo**.

## Round-3 experiment not committed

- r3a (round-3 data only, 76 batches/superbatch, wdl 0.0): +63 +/- 22 vs wyrd-ii, +143 +/- 23 vs material.
  Weaker than wyrd-iii, so combining the rounds' data helped. Not kept.
