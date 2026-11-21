# Search

เอกสารนี้อธิบายวิธีที่ engine เลือก move อ้างอิงโค้ดใน `engine/src/lib.rs` ส่วนการให้คะแนนตำแหน่งด้วย net ดู [NET.md](NET.md)

**สารบัญ:** [1. ภาพรวม](#1-ภาพรวม) · [2. Iterative deepening](#2-iterative-deepening) · [3. Negamax](#3-negamax) · [4. Alpha-beta](#4-alpha-beta) ·
[5. Quiescence search](#5-quiescence-search) · [6. Move ordering](#6-move-ordering) · [7. Pruning, reductions, extensions](#7-pruning-reductions-และ-extensions) ·
[8. Node limit](#8-node-limit-การคุมความแรง) · [9. ประวัติรุ่น s1–s9](#9-ประวัติรุ่น-s1-ถึง-s9) · [10. สิ่งที่ยังไม่มี](#10-สิ่งที่ยังไม่มี)

---

## 1. ภาพรวม

search คือการลองเดินล่วงหน้าหลาย ply เป็นต้นไม้ แล้วเลือก move แรกที่นำไปสู่ผลดีที่สุด โดยสมมติว่าคู่ต่อสู้เล่นดีที่สุดเช่นกัน
ที่ปลายต้นไม้ search เรียก net ให้คะแนนตำแหน่ง ([NET.md](NET.md) ข้อ 1)

```text
search            วน depth 1, 2, 3, ... (iterative deepening)
 └─ negamax       ค้นแบบ minimax ที่ depth ที่กำหนด + alpha-beta ตัด branch ที่ไม่มีวันถูกเลือก
     └─ (depth หมด)
         quiesce  ค้นต่อเฉพาะ capture/promotion จนตำแหน่งสงบ แล้วประเมินด้วย net
```

| เทคนิค | หน้าที่ | ฟังก์ชัน |
|---|---|---|
| Iterative deepening | ค้นทีละ depth ให้มีคำตอบใช้ได้เสมอ | `Searcher::search` |
| Negamax | ค้นต้นไม้ของทั้งสองฝ่ายด้วยฟังก์ชันเดียว | `negamax` / `negamax_node` |
| Alpha-beta | pruning โดยไม่เปลี่ยนผลลัพธ์ | ภายใน `negamax_node` และ `quiesce` |
| Quiescence | หลีกเลี่ยงการประเมิน (evaluation) กลางการแลกหมาก | `quiesce` |

คะแนนทุกค่าเป็น centipawn (cp) จากมุมมองของ side to move

---

## 2. Iterative deepening

`Searcher::search(&board, max_depth)` ค้น depth 1, 2, 3, ... จนถึง `max_depth` หรือจนหมด node แต่ละรอบ:

1. เรียง move ที่ราก (ตำแหน่งปัจจุบัน) ตามข้อ 6
2. ลองทีละ move ด้วย `negamax` ที่ `depth - 1` เก็บ move ที่ได้คะแนนสูงสุด
3. ถ้าไม่ถูกขัดจังหวะ ใช้ผลรอบนี้เป็นคำตอบ และย้าย move ที่ดีที่สุดไว้หน้าสุดสำหรับรอบถัดไป

ประโยชน์: **มีคำตอบเสมอ** (ถ้า node หมดกลางรอบ จะทิ้งผลรอบนั้น คืนผลของ depth ล่าสุดที่เสร็จ) และ **pruning ได้มากขึ้น** เพราะ move ที่ดีที่สุดของรอบก่อนมักยังดีที่สุดในรอบลึกกว่า
ถ้าไม่มี legal move คืน `None`

---

## 3. Negamax

minimax ปกติ: ฝ่ายเราเลือก move ที่ให้คะแนนสูงสุด ฝ่ายตรงข้ามเลือก move ที่ให้คะแนนเราต่ำสุด negamax อาศัยข้อเท็จจริงว่า
**คะแนนของฝ่ายหนึ่งเท่ากับค่าติดลบของคะแนนอีกฝ่าย** จึงเขียนฟังก์ชันเดียวสำหรับทั้งสองฝ่ายได้:

```rust
let score = -self.negamax(&next, depth - 1, -beta, -alpha, ply + 1);
```

ขั้นตอนของแต่ละ node ใน `negamax_node`:

1. **ตรวจจบเกม:** รุกฆาตคืน `-MATE + ply` (ยิ่งรุกฆาตเร็ว ply ยิ่งน้อย จึงยิ่งดีสำหรับฝ่ายที่รุกฆาต) เสมอคืน 0
2. **depth หมด** (`depth <= 0`): ส่งต่อให้ `quiesce`
3. **นับ node** (`tick`): ถ้าถึง `node_limit` ตั้งธง `stopped` แล้วหยุด
4. **สร้าง move ทั้งหมด** เรียงลำดับ ลองทีละ move แล้วเก็บคะแนนที่ดีที่สุด (ข้อ 7 แทรกอยู่ในขั้นนี้)

---

## 4. Alpha-beta

ระหว่าง search เก็บสองค่า:

| ค่า | ความหมาย |
|---|---|
| `alpha` | คะแนนที่ดีที่สุดที่ side to move การันตีได้แล้ว |
| `beta` | คะแนนสูงสุดที่ฝ่ายตรงข้ามยอมให้ side to move ได้ |

ถ้าพบ move ที่ให้คะแนน `>= beta` (`if alpha >= beta { break; }`) แปลว่าฝ่ายตรงข้ามจะไม่ยอมให้เกิดตำแหน่งนี้ตั้งแต่ ply ก่อนหน้า
จึงไม่ต้องลอง move ที่เหลือใน node นี้ (beta cutoff)

ตัวอย่าง: move ที่ลองไปแล้วการันตีได้ +100 ตอนนี้ลองอีกทางหนึ่ง ถ้าพบว่าคู่ต่อสู้มีคำตอบเดียวที่ทำให้เหลือ −300 ก็ไม่ต้องหาต่อ
เพราะทางนี้แย่กว่า +100 แน่นอน ผลลัพธ์ **เหมือน minimax เต็มรูปแบบทุกประการ** แต่ค้นน้อยลงมาก ยิ่งลอง move ที่ดีก่อน pruning ยิ่งได้มาก (ข้อ 6)

---

## 5. Quiescence search

**ปัญหา:** ถ้าหยุดที่ depth คงที่แล้วประเมินทันที อาจหยุดกลางการแลกหมาก เช่นเพิ่งกินม้า แต่อีกฝ่ายกินกลับได้ใน ply ถัดไป คะแนนจึงคลาดเคลื่อนมาก
(horizon effect) `quiesce` แก้โดยเมื่อ depth หมด ยังไม่ประเมินทันที แต่:

1. คำนวณ `stand` คือคะแนนของตำแหน่งนี้ด้วย net (หรือ material eval ถ้าไม่มี net) แทนคะแนนถ้า side to move "ไม่กินอะไรต่อ" ใช้เป็นขอบล่างของ node
2. ถ้า `stand >= beta` ตัดทันที
3. ปรับ `alpha` ให้ไม่ต่ำกว่า `stand`
4. ลองเฉพาะ **capture และ promotion** แล้วเรียก `quiesce` ซ้ำ โดยมี **delta pruning** (ข้อ 7) ตัด capture ที่ไม่มีทางทำให้คะแนนถึง alpha
5. ทำต่อจนไม่มี capture เหลือ ตำแหน่งนั้นจึงถือว่า "quiet"

การประเมินด้วย net จึงเกิดกับตำแหน่ง quiet เป็นหลัก ซึ่งสอดคล้องกับ datagen ที่เก็บเฉพาะตำแหน่ง quiet

---

## 6. Move ordering

`move_score` ให้คะแนนเพื่อเรียง move จากมากไปน้อยก่อนลอง (คำนวณครั้งเดียวต่อ move ด้วย `sort_by_cached_key`):

| ลำดับ | ชนิด move | คะแนนเรียง |
|---|---|---:|
| 1 | move ที่เก็บใน transposition table (move ดีสุดที่เคยพบในตำแหน่งนี้) | 30,000 |
| 2 | capture | `10,000 + 10 × มูลค่าหมากที่ถูกกิน − มูลค่าหมากที่กิน` (MVV-LVA: กินของแพงด้วยของถูกก่อน) |
| 3 | promotion | `+9,000` |
| 4 | killer move ตัวที่ 1 / 2 ของ ply นั้น | 8,000 / 7,000 |
| 5 | quiet move อื่น ๆ | ค่า history ÷ 8 (ติดลบได้) |

- **killer moves:** quiet move 2 ตัวต่อ ply ที่เพิ่งทำให้เกิด beta cutoff ใน node พี่น้อง
- **history heuristic:** ตาราง `[ฝ่าย][จาก][ไป]` ของ `i16` (16 KB) move ที่ทำให้ cutoff ได้โบนัสตาม depth² (สูงสุด 400)
  quiet move ที่ลองก่อนแล้วไม่ cutoff ถูกหักคะแนน ใช้สูตร gravity ไม่ให้ค่าเกิน ±16,384
- **ที่ราก:** move ดีสุดของรอบ iterative deepening ก่อนหน้าไปก่อน move อื่นคงลำดับเดิม

มูลค่าหมากที่ใช้เรียง: pawn 100, knight 320, bishop 330, rook 500, queen 900, king 0

ข้อสังเกต: `is_capture` ตรวจว่าช่องปลายทางมีหมากฝ่ายตรงข้ามอยู่ จึง **ไม่นับ en passant** เป็น capture ผลคือ en passant ไม่ถูกลองใน `quiesce`
และเรียงเป็น quiet move ธรรมดาใน `negamax` ยังไม่ได้ทดสอบว่ามีผลต่อความแรง และไม่กระทบความถูกต้องของ move เพราะ `legal_moves` ยังสร้าง move นี้ตามกติกา

---

## 7. Pruning, reductions และ extensions

ทั้งหมดอยู่ใน `negamax_node` (ยกเว้น delta pruning อยู่ใน `quiesce`) ผลที่วัดได้ของแต่ละอย่างอยู่ใน [EVALUATION.md](EVALUATION.md) ข้อ 7

| เทคนิค | รุ่น | ทำอะไร | เงื่อนไข / ค่า |
|---|---|---|---|
| **Repetition detection** | s2 | `Searcher` เก็บ hash ของตำแหน่งที่เล่นมา (ประวัติเกมจาก UCI `position ... moves` บวกเส้นทางที่ค้นอยู่) ตำแหน่งที่เคยเกิดแล้วหนึ่งครั้งนับเป็นเสมอ (0) | ภายในช่วงที่ halfmove clock อนุญาต |
| **Move ordering** | s3 | killer + history + move ดีสุดที่ราก (ข้อ 6) | |
| **Null-move pruning** | s4 | ถ้า "ข้ามตา" แล้วค้นตื้นลง (R = 2) ยังได้คะแนนถึง beta ก็ตัด branch | depth ≥ 3, ไม่ถูกรุก, มีหมากที่ไม่ใช่ pawn/king (กัน zugzwang), beta ไม่ใช่คะแนนรุกฆาต, ไม่ทำซ้อนสองครั้งติด |
| **Late move reductions (LMR)** | s5 | quiet move ที่ไม่ใช่ killer และไม่รุก ค้นตื้นลง 1 ply ก่อน ถ้าได้คะแนนเกิน alpha ค่อยค้นซ้ำเต็ม depth | move ลำดับที่ 3 ขึ้นไป (index ≥ 2), depth ≥ 3; ลด 2 ply เมื่อ index ≥ 5 และ depth ≥ 5 |
| **Transposition table (TT)** | s6 | ตารางจำผลของตำแหน่งที่เคยค้น: ใช้ตัด branch เมื่อ depth ที่เก็บพอ และใช้ move ที่เก็บเป็น move แรก | 64 KB (UCI `Hash` เป็น KiB, 0 = ปิด), ช่องละ 8 ไบต์, bucket ละ 2 ช่อง, key ตรวจ 16 บิต, เก็บ move/score/depth/ชนิดขอบเขต (exact/lower/upper); คะแนนรุกฆาตเก็บแบบสัมพัทธ์กับ node; สร้างใหม่ทุกครั้งที่สั่ง `go` |
| **Futility pruning** | s7 | ใกล้ปลายต้นไม้ ถ้าคะแนนประเมิน + margin ยังไม่ถึง alpha ข้าม quiet move ที่ไม่รุก | depth ≤ 2, margin 150 ต่อ ply, ไม่ถูกรุก, alpha ไม่ใช่คะแนนรุกฆาต; ไม่ข้าม move แรก |
| **Delta pruning** | s8 | ใน quiescence ถ้าคะแนน `stand` + มูลค่าหมากที่กิน + margin ยังไม่ถึง alpha ข้าม capture นั้น | margin 200, ไม่ถูกรุก, ไม่ใช่ promotion, en passant นับเป็น pawn |
| **Check extension** | s9 | move ที่รุกคิงค้นลึกขึ้น 1 ply | ply < 32 และเฉพาะ move ที่ไม่ผ่าน LMR ยังไม่ใช้ที่ move ระดับราก |

| **SEE** (static exchange evaluation) | s10 | คำนวณผลลัพธ์ของการแลกหมากต่อเนื่องบนช่องที่ถูกกิน (ใช้หมากที่มูลค่าต่ำสุดกินก่อน แต่ละฝ่ายหยุดได้) ใช้ 2 ที่: (1) move ordering: capture ที่ SEE < 0 ถูกลองหลัง killer และ quiet move (2) quiescence: ข้าม capture ที่ SEE < 0 | ไม่ถูกรุก, ไม่ใช่ promotion (ใน quiescence); capture ที่กินของมูลค่า ≥ ตัวที่กินไม่ต้องคำนวณ SEE (ผลไม่ติดลบเสมอ); en passant ยังไม่ผ่าน SEE |
| **Reverse futility pruning** | s11 | ใกล้ปลายต้นไม้ ถ้าคะแนนประเมิน − margin ยังสูงกว่า beta ถือว่า node นี้ fail high คืนค่านั้นโดยไม่ค้น | depth ≤ 3, margin 80 ต่อ ply, ไม่ถูกรุก, ไม่ใช่ราก, beta ไม่ใช่คะแนนรุกฆาต |

ลองแล้วไม่รับ: **PVS** (ลอง 3 ครั้ง: ก่อนมี TT, หลังมี TT และหลังมี SEE/s11 ไม่ผ่านกฎทั้งสามครั้ง) และ **aspiration window** (ที่ราก delta 100 ได้ราว +6 ที่ 10k และ +21 ที่ 50k รวม 1,200 เกม ที่ 10k ไม่ผ่าน; EVALUATION.md ข้อ 7.7) และ **LMR แบบ logarithmic** (ลดตาม ilog2(depth) × ilog2(index) / 2: +12 ± 22 ที่ 10k, −9 ± 23 ที่ 50k; EVALUATION.md ข้อ 7.8)

ค่า margin/ขนาดทั้งหมดข้างบนเป็นค่าที่ลองครั้งเดียว ไม่ได้ปรับอย่างเป็นระบบ

---

## 8. Node limit: การคุมความแรง

ความแรงควบคุมด้วย `node_limit` (กฎเหล็กข้อ 6 ใน `CLAUDE.md`):

- ทุกครั้งที่เข้า `negamax` (ที่ depth ยังเหลือ) หรือ `quiesce` นับเป็นหนึ่ง **node** (ตำแหน่งหนึ่งที่ search พิจารณา ไม่เกี่ยวกับ neuron ของ net)
- เมื่อถึงขีดจำกัด search หยุด และ iterative deepening คืนผลของ depth ที่เสร็จล่าสุด
- node น้อย → ค้นลึกได้น้อย → เล่นอ่อนลง โดยใช้ net เดิม
- ตั้งผ่าน UCI ได้ด้วย `setoption name Nodes value N` (ค่าตั้งต้น 20,000) หรือ `go nodes N` สำหรับ move เดียว

ระดับ node แต่ละระดับเทียบเป็น Elo สัมพัทธ์แล้ว (ladder) ดู [EVALUATION.md](EVALUATION.md) ข้อ 5

**ข้อควรระวัง:** node ต่อวินาทีต่างกันตามรุ่น search (เทคนิคใหม่บางตัวทำให้แต่ละ node แพงขึ้น) จึงเทียบรุ่นที่ node เท่ากันไม่ได้บอกผลที่เวลาเท่ากัน
ผลเทียบที่เวลาเท่ากันอยู่ใน [EVALUATION.md](EVALUATION.md) ข้อ 7.2

---

## 9. ประวัติรุ่น s1 ถึง s9

Elo คือผล A/B match ที่ node เท่ากันเทียบกับรุ่นก่อนหน้า (`wyrd-iv` ทั้งสองฝั่ง) จำนวนเกมและรายละเอียดอยู่ใน [EVALUATION.md](EVALUATION.md) ข้อ 7
เวลาคือเวลาที่ใช้ค้น 3,000,000 node บนเครื่องพัฒนา (ยิ่งน้อยยิ่งเร็วต่อ node) ค่าจับเวลาคลาดเคลื่อนราว ±5%

| รุ่น | เพิ่มอะไร | Elo ที่ 10k node | Elo ที่ 50k node | ความเร็วต่อ node เทียบรุ่นก่อน | RAM ที่เพิ่ม |
|---|---|---:|---:|---|---|
| s1 | negamax + alpha-beta + quiescence + iterative deepening | (ฐาน) | (ฐาน) | ~660–700 ms | |
| s2 | repetition detection | +44 | ไม่ได้วัด | ไม่ต่าง | เล็กน้อย (hash ของเส้นทาง) |
| s3 | killer + history + move ดีสุดที่ราก | +79 | +92 | ไม่ต่าง | ~17 KB |
| s4 | null-move pruning | +20 | +44 | ไม่ได้จับแยก | 0 |
| s5 | late move reductions | +28 | +23 | ช้าลง ~13% | 0 |
| s6 | transposition table 64 KB | +52 | +125 | ไม่ต่าง | 64 KB |
| s7 | futility pruning | +25 | +37 | ช้าลง ~12% | 0 |
| s8 | delta pruning | +33 | +31 | ช้าลง ~12% (ตัวเลขนี้ไม่แน่ชัด ดู EVALUATION.md) | 0 |
| s9 | check extension | +53 | +31 | ไม่ต่าง | 0 |
| s10 | SEE ใน move ordering และ quiescence | +97 (`wyrd-vi`) | +65 (`wyrd-vi`) | ช้าลง ~20–24% (วัดจากเวลาต่อ move ใน A/B) | 0 |
| s11 | reverse futility pruning | +40 (`wyrd-vii`) | +19 (ไม่ผ่านที่ node เท่ากัน) | เร็วขึ้น ~13–14% (ดูข้อ 7.6) | 0 |

- ที่ 1,000 node ทุกขั้นตั้งแต่ s3 ขึ้นไปได้ผลใกล้ศูนย์ (node ต่ำไม่ได้ประโยชน์จาก search ใหม่)
- Elo รายรุ่น **บวกกันตรง ๆ ไม่ได้** (วัดทีละขั้นเทียบรุ่นก่อน)
- **ที่ node เท่ากัน s9 ช้ากว่า s6 ต่อ node ราว 29%** แต่ที่เวลาเท่ากัน s9 ยังชนะ s6 ชัดเจน (+92 ± 24 ที่ระดับ 50k, +74 ± 26 ที่ 10k) แปลว่า s7–s9 รวมกันคุ้มกับต้นทุนความเร็ว (EVALUATION.md ข้อ 7.2)
- s10 วัดด้วย `wyrd-vi` ไม่ใช่ `wyrd-iv` จึงเทียบตรง ๆ กับแถวอื่นไม่ได้ ที่เวลาเท่ากันยังชนะ s9 (+45 ± 25 ที่ 10k, +30 ± 25 ที่ 50k, EVALUATION.md ข้อ 7.5)
- s11 ที่ node เท่ากันไม่ผ่านที่ 50k แต่เร็วขึ้นต่อ node จึงวัดที่เวลาเท่ากัน: +62 ± 24 (10k), +60 ± 24 (50k) (EVALUATION.md ข้อ 7.6)
- PVS ลองแล้วไม่รับ (EVALUATION.md ข้อ 7.3)

---

## 10. สิ่งที่ยังไม่มี

จากโค้ดปัจจุบัน ไม่มีเทคนิคต่อไปนี้ (รายการเพื่อให้ทราบสถานะ ไม่ใช่งานที่กำหนดไว้ ดู [ROADMAP.md](ROADMAP.md)):

- transposition table ที่เก็บข้ามตา (ตอนนี้สร้างใหม่ทุกครั้งที่ `go`)
- aspiration window
- SEE (static exchange evaluation) ในการเรียง capture
- ตรวจเสมอเพราะหมากไม่พอ (เช่น king vs king)
- search ด้วยเวลา (time management) ตอนนี้จำกัดด้วย node เท่านั้น
- โค้ดที่ไม่จัดสรรหน่วยความจำ (ยังใช้ `Vec` ต่อ node จึงใช้ใน firmware `no_std` ไม่ได้)
