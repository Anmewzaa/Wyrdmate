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

## wyrd-vi.bin — ACCEPTED (previous best, superseded by wyrd-vii)

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

## wyrd-vii.bin — ACCEPTED (previous best, superseded by wyrd-viii; checkpoint run `r7c`)

- Tooling: commit `0b31292` (search s10; datagen and trainer code unchanged since `69d4dcb`).
- Data: round-7 self-play (4 runs x 2500 games, seeds 101-104, 5000 nodes/move, played by `wyrd-vi.bin` with
  **search s10**; 1,037,064 positions) **plus all round-2 to round-6 data** (`data/r6all.txt`, made with older search
  versions) = 6,597,914 positions. `wyrdmate-datagen 2500 5000 <seed> data/r7cpartSEED.txt nets/wyrd-vi.bin`, concatenated
  after `data/r6all.txt`, then `bullet-utils convert --from text`, `shuffle --mem-used-mb 2048`.
- Training: `wyrdmate-trainer data/r7ctrain.data 200 403 16384 0.0 r7c` (wdl 0.0, `--features cuda`). Final running loss
  0.001560 as printed by the trainer (not comparable across datasets).
- Match vs `wyrd-vi` (fastchess, same engine `0b31292` = s10 on both sides, 600 games each): 10,000 nodes **+34 +/- 25 Elo**
  (lower bound +8); 50,000 nodes **+23 +/- 24** (lower bound -2, does not pass alone). A second independent 600 games at
  50,000 nodes with another opening book (`data/book2.epd`): **+35 +/- 24** (lower bound +11). Pooling the two independent 50k sets by
  hand (trinomial, 1200 games): about +29 +/- 18, lower bound about +11.5. Owner accepted it on this evidence (2026-11-21).
  Raw logs `logs/ab-net-r7c-10000.txt`, `logs/ab-net-r7c-50000.txt`, `logs/ab-net-r7c-50k-book2.txt` (git-ignored).
- Not run: ladder and Stockfish measurements with this net (the ladder in docs/EVALUATION.md section 5 is wyrd-vi + s10).
- Gain per round: +115, +81, +31, +64, +47, +34.

## wyrd-ix.bin — ACCEPTED (current best; checkpoint run `r9a`, round 9 data, wdl 0.1)

- Tooling: commit `654b740` (search s11; datagen and trainer code unchanged since `69d4dcb`). Data: round-9 self-play (4 x 2500 games,
  seeds 121-124, 5000 nodes/move, played by `wyrd-viii.bin` with search s11; 1,046,337 positions) **plus all round-2 to round-8
  data** (`data/r8all.txt`) = 8,693,520 positions (`data/r9train.data`). Pipeline as before: `wyrdmate-datagen 2500 5000 <seed>
  data/r9partSEED.txt nets/wyrd-viii.bin`, concatenated after `data/r8all.txt`, `bullet-utils convert --from text`, `shuffle --mem-used-mb 2048`.
- Training: `wyrdmate-trainer data/r9train.data 200 531 16384 0.1 r9a` (wdl 0.1 per D-012, `--features cuda`). Final running loss 0.002692
  (not comparable with other datasets).
- Match vs `wyrd-viii` (fastchess, same engine s11, 600 games per set, three independent opening books: `data/book.epd` seed 99,
  `data/book2.epd` seed 100, `data/book3.epd` seed 200): 10,000 nodes **+30 +/- 24** (lower bound +6), **+8 +/- 26** (-17), **+38 +/- 25** (+13);
  50,000 nodes **+41 +/- 24** (+18), **+12 +/- 24** (-12), **+20 +/- 24** (-4). Pooling the three independent sets by hand
  (trinomial, 1800 games): 10,000 nodes about **+25 +/- 15** (lower bound about +10.5), 50,000 nodes about **+24 +/- 14** (lower bound about +10).
  Three of the six sets alone do not pass; all six are positive. Owner-delegated decision: accepted on the pooled result.
  Raw logs `logs/ab-net-r9a-10000.txt`, `-50000.txt`, `-10000-book2.txt`, `-50000-book2.txt`, `-10000-book3.txt`, `-50000-book3.txt` (git-ignored).
- One training run only (run-to-run variation unknown). Not run: ladder and Stockfish with this net.
- Gain per round: +115, +81, +31, +64, +47, +34, +57..+80 (round 8 at wdl 0.1), then about +25 (this one).

## wyrd-viii.bin — ACCEPTED (previous best, superseded by wyrd-ix; checkpoint run `r8w1`, round 8 data with wdl 0.1)

- Tooling: commit `0558764` (search s11; datagen and trainer code unchanged since `69d4dcb`). Data: the same round-8 data as `r8a`
  (round-8 self-play, 4 x 2500 games, seeds 111-114, 5000 nodes/move, played by `wyrd-vii.bin` with search s11; 1,049,269 positions)
  **plus all round-2 to round-7 data** = 7,647,183 positions (`data/r8train.data`).
- Training: `wyrdmate-trainer data/r8train.data 200 467 16384 0.1 r8w1` (**wdl 0.1**, `--features cuda`). Final running loss 0.002605
  (not comparable with other wdl values or datasets). This is the only change from `r8a` (wdl 0.0) and from D-010; see D-012.
- Match vs `wyrd-vii` (fastchess, same engine s11, 600 games each, two independent opening books): 10,000 nodes **+57 +/- 26**
  (lower bound +31) and **+79 +/- 26** (`data/book2.epd`, lower bound +52); 50,000 nodes **+80 +/- 25** (lower bound +55) and
  **+63 +/- 25** (`data/book2.epd`, lower bound +38). All four sets pass rule 2 by a wide margin.
  Raw logs `logs/ab-net-r8w1-10000.txt`, `-50000.txt`, `-10000-book2.txt`, `-50000-book2.txt` (git-ignored).
- One training run only: the run-to-run variation of training is not known. Not run: ladder and Stockfish with this net.
- Gain per round: +115, +81, +31, +64, +47, +34, +57..+80 (this one comes from the target mix, not from new data: the same data gave -9 / -12 at wdl 0.0).

## wdl experiment on the round-8 data (r8a, r8w1, r8w2, r8w3, r8w4)

Same data and recipe, only the 5th trainer argument changes; all vs `wyrd-vii`, 600 games each (first opening book):

| wdl | net | final running loss | 10,000 nodes | 50,000 nodes |
|---:|---|---:|---|---|
| 0.0 | r8a | 0.001656 | -9 +/- 25 | -12 +/- 24 |
| **0.1** | **r8w1 = wyrd-viii** | 0.002605 | **+57 +/- 26** | **+80 +/- 25** |
| 0.2 | r8w2 | 0.005226 | +20 +/- 25 | +38 +/- 26 |
| 0.3 | r8w3 | 0.009397 | -60 +/- 26 | -22 +/- 26 |
| 0.4 | r8w4 | 0.015218 | -114 +/- 26 | -113 +/- 27 |

Only `r8w1` was re-checked on a second opening book. Details: docs/EVALUATION.md section 8.3.

## r8a (round 8 candidate, wdl 0.0) — NOT ACCEPTED

- Tooling: commit `0558764` (search s11). Data: round-8 self-play (4 x 2500 games, seeds 111-114, 5000 nodes/move, played by
  `wyrd-vii.bin` with search s11; 1,049,269 positions) **plus all round-2 to round-7 data** (`data/r7call.txt`) = 7,647,183 positions.
  Training: `wyrdmate-trainer data/r8train.data 200 467 16384 0.0 r8a` (final running loss 0.001656). The net is only in
  `checkpoints/r8a-200/quantised.bin` (git-ignored).
- Match vs `wyrd-vii` (fastchess, same engine s11, 600 games each): 10,000 nodes **-9 +/- 25** (lower bound -35); 50,000 nodes
  **-12 +/- 24** (lower bound -37). Neither passes rule 2; both slightly negative.
- Gain per round: +115, +81, +31, +64, +47, +34, then about -10 (not accepted): the loop has plateaued at this net size and recipe.

## r7a (round 7 candidate) — NOT ACCEPTED (owner decision 2026-11-21: the 50k result does not clearly pass)

- Tooling: commit `684c637` (search s9). Data: round-7 self-play (4 x 2500 games, seeds 81-84, 5000 nodes/move,
  played by `wyrd-vi.bin` with search s9; 1,023,103 positions) **plus all round-2 to round-6 data** = 6,579,953 positions.
  Training: `wyrdmate-trainer data/r7train.data 200 402 16384 0.0 r7a` (final running loss 0.001576).
  The net is only in `checkpoints/r7a-200/quantised.bin` (git-ignored); it was not copied to `nets/`.
- Match vs `wyrd-vi` (fastchess, same engine, 600 games each): 10,000 nodes **+39 +/- 26** (lower bound +14, passes);
  50,000 nodes **+17 +/- 25** (lower bound -9, does not pass). A second, independent 600 games at 50,000 nodes with
  another opening book (`data/book2.epd`, seed 100): **+20 +/- 24** (lower bound -3). Pooling the two independent
  50k sets by hand (trinomial, 1200 games): about +18 +/- 18, lower bound about +0.7, i.e. borderline.
- A first attempt at 1200 games on one 300-position book is **invalid**: openings repeated and node-limited games repeat
  exactly, so every game was played twice (Elo identical to the 600-game run, error bar falsely smaller).
  `scripts/ab.ps1` now warns when `-Rounds` exceeds the book size and takes `-Book` for another opening set.
- Gain per round: +115, +81, +31, +64, +47, then +39 (10k) / about +18 (50k) for this candidate: shrinking again.

## r7b (datagen quality: 20,000 nodes/move) — NOT ACCEPTED, not copied to `nets/`

- Tooling: commit `69d4dcb` (search s9). Data: round-7 self-play (4 x 2500 games, seeds 91-94, **20000 nodes/move**, played by
  `wyrd-vi.bin`) **plus all round-2 to round-6 data** = 6,594,606 positions (datagen took 32 min).
  Training: `wyrdmate-trainer data/r7btrain.data 200 403 16384 0.0 r7b` (final running loss 0.001635).
  The net is only in `checkpoints/r7b-200/quantised.bin` (git-ignored).
- Match vs `wyrd-vi` (600 games each, same engine): 10,000 nodes **+22 +/- 25** (lower bound -2); 50,000 nodes **+14 +/- 24**
  (lower bound -10). Neither passes rule 2. `r7b` vs `r7a` (600 games each): 10,000 nodes +34 +/- 25, 50,000 nodes -3 +/- 24. Details: docs/EVALUATION.md section 8.2.

## Hidden size experiment (r6h16, r6h64, r6h128) — NOT ACCEPTED, none copied to `nets/`

- Tooling: commit `53bbbb8` plus the trainer change that makes hidden size the 7th argument (this commit). Data: the same
  round 2-6 data as `wyrd-vi` (5,560,850 positions). Training: `wyrdmate-trainer data/r6train.data 200 339 16384 0.0 r6h<H> <H>`
  for H = 16, 64, 128 (one run each). Final running loss 0.001599 / 0.001269 / 0.001090 (`wyrd-vi`, H = 32: 0.001436).
- Matches vs `wyrd-vi` (600 games each, same engine): equal nodes at 10k / 50k: H16 -24 +/- 26 / -27 +/- 24, H64 +25 +/- 25 / +21 +/- 25,
  H128 +30 +/- 25 / +34 +/- 25. Equal time (fewer nodes for the bigger net): H64 -19 +/- 26 (10k) and +1 +/- 25 (50k),
  H128 -53 +/- 26 and -18 +/- 26. Details and caveats: docs/EVALUATION.md section 8.1.
- Conclusion: keep H = 32. The checkpoints are in `checkpoints/r6h*-200/` (git-ignored).
