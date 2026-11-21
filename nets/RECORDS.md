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

## wyrd-iv.bin — ACCEPTED

- Tooling: commit `c3ed243` (unchanged through round 4).
- Data: round-4 self-play (4 runs x 2500 games, seeds 51-54, 5000 nodes/move, played by
  `wyrd-iii.bin`; 1,063,137 positions) **plus all round-2 and round-3 data** = 3,477,195 positions.
  `wyrdmate-datagen 2500 5000 <seed> data/r4partSEED.txt nets/wyrd-iii.bin`, concatenated with the
  earlier files, then `bullet-utils convert --from text`, `shuffle`.
- Training: `wyrdmate-trainer data/r234train.data 200 212 16384 0.0 r234a` (wdl 0.0;
  212 batches/superbatch ~ one pass). Final running loss 0.001057 (higher than earlier nets
  because the data now holds more decisive, harder positions; loss is not comparable across datasets).
- Match (fastchess, 600 games, 10000 nodes, same book): vs wyrd-iii **+31 +/- 22 Elo**
  (lower bound still above 0); vs material eval **+212 +/- 27 Elo**.
- Gains per round are shrinking: +115, +81, +31 Elo over the previous net.

## wyrd-v.bin — ACCEPTED

- Tooling: commit `3a32a05` (search s9: futility pruning, delta pruning, check extension on top of s6;
  datagen and trainer code unchanged since `c3ed243`).
- Data: round-5 self-play (4 runs x 2500 games, seeds 61-64, 5000 nodes/move, played by `wyrd-iv.bin`
  with search s9; 1,058,916 positions) **plus all round-2, 3 and 4 data** = 4,536,111 positions.
  `wyrdmate-datagen 2500 5000 <seed> data/r5partSEED.txt nets/wyrd-iv.bin`, concatenated after
  `data/r234all.txt`, then `bullet-utils convert --from text`, `shuffle`.
  Note: rounds 2-4 were played with the older search (s1), round 5 with s9, so the gain below mixes new
  data and more data; not separated.
- Training: `wyrdmate-trainer data/r5train.data 200 277 16384 0.0 r5a` (wdl 0.0; 277 batches/superbatch ~ one
  pass; `--features cuda`, ~36 s on the RTX 4060). Final running loss 0.001279 (not comparable across datasets).
- Match (fastchess, 600 games, same book, engine s9 on both sides, new net vs `wyrd-iv`):
  10,000 nodes **+64 +/- 25 Elo** (lower bound +40), 50,000 nodes **+83 +/- 26 Elo** (lower bound +58).
  Raw logs `logs/ab-net-r5a-10k.txt`, `logs/ab-net-r5a-50k.txt` (git-ignored).
- Not run: match against the material eval; ladder and Stockfish measurements with this net.
- Gain per round: +115, +81, +31, +64 (the last round also changed the search used to make labels).

## wyrd-vi.bin — ACCEPTED (current best)

- Tooling: commit `0cbd1a6` (search s9; datagen and trainer code unchanged since `c3ed243`).
- Data: round-6 self-play (4 runs x 2500 games, seeds 71-74, 5000 nodes/move, played by `wyrd-v.bin`
  with search s9; 1,024,739 positions) **plus all round-2 to round-5 data** = 5,560,850 positions.
  `wyrdmate-datagen 2500 5000 <seed> data/r6partSEED.txt nets/wyrd-v.bin`, concatenated after
  `data/r5all.txt`, then `bullet-utils convert --from text`, `shuffle`.
- Training: `wyrdmate-trainer data/r6train.data 200 339 16384 0.0 r6a` (wdl 0.0; 339 batches/superbatch ~ one
  pass; `--features cuda`). Final running loss 0.001436 (not comparable across datasets).
- Match (fastchess, 600 games, same book, engine s9 on both sides, new net vs `wyrd-v`):
  10,000 nodes **+47 +/- 25 Elo** (lower bound +22), 50,000 nodes **+42 +/- 25 Elo** (lower bound +17).
  Raw logs `logs/ab-net-r6a-10k.txt`, `logs/ab-net-r6a-50k.txt` (git-ignored).
- Not run: match against the material eval or `wyrd-iv`; ladder and Stockfish measurements with this net.
- Gain per round: +115, +81, +31, +64, +47. Still positive after the label/search change, not yet shrinking
  clearly; two data points since s9 are too few to call a trend.
