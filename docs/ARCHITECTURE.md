# สถาปัตยกรรมของ Wyrdmate

ภาพรวมการออกแบบระบบ และข้อกำหนดที่ `trainer`, `engine` และ `firmware` ต้องปฏิบัติตรงกัน
รายละเอียดของ net อยู่ที่ [NET.md](NET.md) รายละเอียดของ search อยู่ที่ [SEARCH.md](SEARCH.md)

## 1. วัตถุประสงค์

Wyrdmate เป็นโปรแกรมหมากรุกขนาดเล็กสำหรับบอร์ดระดับ ESP32 เป้าหมายคือ **เล่นอย่างสมเหตุสมผลและปรับระดับความแรงได้** (weak but clever)
ไม่ได้มุ่งเป็น engine ที่แรงที่สุด ความแรงถูกควบคุมอย่างเปิดเผยด้วย node limit (`node_limit`) ไม่มีการลดความสามารถด้วยวิธีซ่อนเร้น
(กฎเหล็กข้อ 6 ใน `CLAUDE.md`)

## 2. องค์ประกอบ

| ส่วน | ตำแหน่ง | หน้าที่ | เรียนรู้ได้ |
|---|---|---|---|
| กฎหมากรุก | `cozy-chess` (ไลบรารีภายนอก) | สร้าง legal moves | ไม่ |
| search | `engine/src/lib.rs` | เลือก move โดยคิดล่วงหน้า ([SEARCH.md](SEARCH.md)) | ไม่ |
| evaluation (net) | `engine/src/nnue.rs` | ให้คะแนนตำแหน่งด้วย NNUE ([NET.md](NET.md)) | **ได้** |
| UCI front end | `engine/src/main.rs` | สื่อสารกับโปรแกรมภายนอกตามโปรโตคอล UCI (options `Nodes`, `EvalFile`, `Hash`) | ไม่ |
| datagen | `datagen/` | ให้ engine เล่นกับตัวเอง (self-play) และบันทึกตำแหน่ง | ไม่ |
| trainer | `trainer/` | training net ด้วย bullet | — |
| firmware | `firmware/` | รัน NNUE บน ESP32 (`no_std`) ยังเป็นโครงเปล่า | — |
| web demo | `web/` | engine คอมไพล์เป็น WebAssembly สำหรับหน้าเล่นบนเว็บ ([`../web/README.md`](../web/README.md)) | — |

## 3. การไหลของข้อมูล

```text
engine ──(เล่นเกม)──▶ datagen ──▶ data/*.txt ──[bullet-utils]──▶ *.data
                                                                   │
firmware ◀──(ฝังไฟล์ net)── nets/ ◀── checkpoints/ ◀── trainer (bullet)
```

วงวนพัฒนา (D-005): self-play ด้วย node limit → training → A/B match → ถ้า net ใหม่ชนะอย่างมีนัยสำคัญ ให้ใช้ net นั้นสร้างข้อมูลรอบถัดไป
ขั้นตอนละเอียดอยู่ที่ [TRAINING.md](TRAINING.md) และเกณฑ์รับ net อยู่ที่ [EVALUATION.md](EVALUATION.md)

## 4. Search และการควบคุมความแรง

- อัลกอริทึม: negamax + alpha-beta, quiescence search, iterative deepening และเทคนิค pruning/caching (รุ่น s1 ถึง s9) ดู [SEARCH.md](SEARCH.md)
- `Searcher::new(node_limit)`: เมื่อนับ node ถึงขีดจำกัด search หยุดและคืนผลของ depth ล่าสุดที่เสร็จสมบูรณ์
- UCI option `Nodes` มีค่าตั้งต้น 20,000 สั่ง `go nodes N` เพื่อเปลี่ยนเฉพาะ move เดียวได้ **engine ยังไม่มีระบบจับเวลา** (จำกัดได้เฉพาะ node)
- คะแนนเป็น centipawn จากมุมมอง side to move รุกฆาตใช้ `MATE = 30000`

Public API:

```rust
Searcher::new(node_limit).with_net(net).search(&board, max_depth) -> Option<(Move, cp)>
Searcher::with_history(hashes)    // ไม่บังคับ: ประวัติเกมสำหรับตรวจ repetition
Searcher::with_tt_kb(kb)          // ขนาด transposition table (ค่าตั้งต้น 64 KB, 0 = ปิด)
evaluate(&board) -> i32           // material eval (ตัวตั้งต้นสำหรับเทียบกับ net)
legal_moves(&board) -> Vec<Move>
```

## 5. ข้อควรระวังด้านความเข้ากันได้

การเปลี่ยนสิ่งต่อไปนี้ต้องแก้ทุกฝั่งพร้อมกันและ training ใหม่ (ดู `CLAUDE.md` หัวข้อ Compatibility surfaces):

1. โครงสร้างของ net ใน `trainer/src/main.rs` ↔ `engine/src/nnue.rs` ↔ `firmware/` (hidden size, จำนวน layer, feature)
2. ค่า `QA`, `QB`, `SCALE`
3. ลำดับและการแมป feature
4. รูปแบบข้อมูลข้อความของ datagen (`FEN | คะแนน | ผลเกม`) ซึ่ง `bullet-utils convert --from text` ใช้อ่าน
5. Public API ของ `Searcher` ซึ่ง datagen, UCI front end และ `web/` ใช้

## 6. ข้อจำกัดปัจจุบัน

- ยังไม่มีโค้ดใน `firmware/` และยังไม่เคยรันบนบอร์ด ตัวเลขหน่วยความจำและความเร็วบนบอร์ดเป็นการประมาณทั้งหมด
- search ยังใช้ `Vec` และ clone กระดานต่อ node (รวมถึง `accumulator_after` ที่ทำสำเนาต่อทุก move) firmware ต้องใช้บัฟเฟอร์ขนาดคงที่แทน
- transposition table (64 KB) และตาราง history (16 KB) ต้องนับในงบ RAM ของ firmware
- ผลวัดทั้งหมดเทียบกับรุ่นก่อนของโครงการเอง ส่วนผลเทียบ Stockfish จำกัดความแรงเป็นค่าประมาณหยาบ ไม่ใช่ Elo มาตรฐาน ([EVALUATION.md](EVALUATION.md))
