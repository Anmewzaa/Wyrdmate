"""Drop repeated positions from a datagen text file, keeping the first occurrence of each.

    python scripts/dedup.py data/r9all.txt data/r9dedup.txt

A position is the first four FEN fields (board, side to move, castling, en passant); the
move counters and the score/result are ignored. Used to make the training data of wyrd-1
(nets/RECORDS.md). Needs memory for one set of keys (about 1 GB for 8.7 million positions).
"""
import sys

seen = set()
total = kept = 0
with open(sys.argv[1], encoding="utf8") as src, open(sys.argv[2], "w", encoding="utf8", newline="\n") as out:
    for line in src:
        total += 1
        key = " ".join(line.split("|")[0].split()[:4])
        if key in seen:
            continue
        seen.add(key)
        kept += 1
        out.write(line)
print(total, "->", kept)
