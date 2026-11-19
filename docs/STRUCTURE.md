# โครงสร้างโปรเจกต์ Wyrdmate (อธิบายทีละไฟล์)

เอกสารนี้เขียนให้คนอ่านเพื่อเข้าใจว่าแต่ละส่วนทำอะไร (ส่วน `CLAUDE.md` เขียนให้ AI อ่าน)

## ภาพรวมการไหลของงาน

```
engine ──(ใช้เล่นเกม)──▶ datagen ──▶ data/*.txt ──[bullet-utils แปลง]──▶ *.data
                                                                          │
firmware ◀──(ฝัง net ที่ quantise แล้ว)── nets/ ◀── checkpoints/ ◀── trainer (bullet)
```

1. `engine` คือสมองของหมากรุก: หาตาเดินที่ดีที่สุด
2. `datagen` ให้ engine เล่นกับตัวเองเพื่อสร้าง "ตำแหน่ง + คะแนน + ผลเกม"
3. `trainer` เอาข้อมูลนั้นไปสอน neural network (NNUE) ให้ประเมินตำแหน่งได้
4. net ที่ได้จะถูกเอาไปแทนฟังก์ชันประเมินตำแหน่งเดิมใน engine แล้วเอาไปรันบน ESP32 ผ่าน `firmware`

---

## ไฟล์และโฟลเดอร์ที่อยู่ใน git

### ระดับบนสุด

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ไฟล์หลักของ Cargo workspace ระบุว่า `engine`, `datagen`, `trainer` เป็นสมาชิก และ `firmware` ถูก `exclude` (เพราะ build สำหรับ ESP32 คนละ target) ตั้งค่า version/edition/license กลางไว้ที่นี่ |
| `Cargo.lock` | ล็อกเวอร์ชันของ library ทุกตัวที่ใช้ เพื่อให้ build ซ้ำได้ผลเหมือนเดิม (รวมถึง commit ของ bullet) ไม่ต้องแก้มือ |
| `.gitignore` | บอก git ว่าไม่ต้องเก็บอะไร: `target/` (ผล build), `checkpoints/` (ผลระหว่างเทรน), `data/` (ข้อมูลเทรนขนาดใหญ่), `*.binpack` |
| `README.md` | หน้าแรกของ repo แนะนำโปรเจกต์สั้นๆ |
| `LICENSE` | สัญญาอนุญาตการใช้โค้ด (MIT) |
| `CLAUDE.md` | คู่มือหลักสำหรับ AI (Claude Code โหลดอัตโนมัติ): เป้าหมาย กฎเหล็ก โครงสร้าง วิธีตรวจสอบ สภาพแวดล้อมเครื่อง เขียนตามแบบโปรเจกต์ TerraFlow ช่วยประหยัด token |
| `docs/STRUCTURE.md` | ไฟล์นี้ |
| `docs/decisions.md` | บันทึกการตัดสินใจสำคัญ (ชื่อ, bullet, monorepo ฯลฯ) |

### `engine/` — เครื่องยนต์หมากรุก (crate `wyrdmate-engine`)

| ไฟล์ | หน้าที่ |
|---|---|
| `engine/Cargo.toml` | ประกาศ crate และ dependency `cozy-chess` (ตัวสร้างตาเดินที่ถูกกติกา) |
| `engine/src/lib.rs` | โค้ดทั้งหมดของ engine: <br>• `evaluate` ประเมินตำแหน่งแบบนับมูลค่าหมาก (ชั่วคราว จะถูกแทนด้วย NNUE) <br>• `Searcher` ค้นหาตาเดินด้วย negamax + alpha-beta + quiescence search (ดูต่อจนตำแหน่งสงบ) + iterative deepening <br>• จำกัดความแรงได้ด้วย `node_limit` (ยิ่งน้อยยิ่งอ่อน) <br>• `legal_moves` ตาเดินที่ถูกกติกาทั้งหมด <br>• เทสต์ 3 ข้อท้ายไฟล์: eval ตำแหน่งเริ่มต้นเป็น 0, หา mate in 1 ได้, เคารพ node limit |

### `datagen/` — ตัวสร้างข้อมูลเทรน (crate `wyrdmate-datagen`)

| ไฟล์ | หน้าที่ |
|---|---|
| `datagen/Cargo.toml` | ประกาศ crate ที่ใช้ `wyrdmate-engine` |
| `datagen/src/main.rs` | ให้ engine เล่นกับตัวเอง: เปิดเกมด้วยการเดินสุ่ม 8-9 ตา (ให้เกมหลากหลาย) แล้วเล่นต่อด้วยการค้นหาแบบจำกัด node จบเกมตามกติกา หรือเมื่อได้เปรียบเกิน 15 เบี้ยติดกัน 4 ตา หรือครบ 300 ตา เก็บเฉพาะตำแหน่งที่ "สงบ" (ไม่ถูกรุก ไม่ใช่ตากิน) เขียนเป็นบรรทัด `FEN \| คะแนน \| ผลเกม` ใช้: `wyrdmate-datagen [เกม] [nodes] [seed] [ไฟล์]` |

### `trainer/` — ตัวเทรน (crate `wyrdmate-trainer`)

| ไฟล์ | หน้าที่ |
|---|---|
| `trainer/Cargo.toml` | ดึง `bullet_lib` จาก git (ตรึงที่ commit หนึ่ง เพราะ API เปลี่ยนบ่อย) มี feature `cuda` สำหรับเทรนบน GPU NVIDIA |
| `trainer/src/main.rs` | กำหนดโครงสร้าง net `768 → 32×2 → 1` (768 = หมาก 6 ชนิด × 2 สี × 64 ช่อง, ซ่อน 32 โหนด ×2 มุมมอง: ฝ่ายที่ถึงตา/อีกฝ่าย) กำหนดตารางเทรน แล้วสั่ง bullet เทรน ผลเป็นไฟล์ net ที่ quantise เป็น int16 แล้วใน `checkpoints/` |

### `firmware/` — โค้ดบน ESP32 (ยังเป็นโครง)

| ไฟล์ | หน้าที่ |
|---|---|
| `firmware/Cargo.toml` | crate แยกต่างหาก ไม่อยู่ใน workspace หลัก (build ด้วย target ของ ESP32) ยังไม่มี dependency ของ chip |
| `firmware/src/lib.rs` | `#![no_std]` (ไม่ใช้ standard library เพราะรันบนไมโครคอนโทรลเลอร์) ตอนนี้ว่าง จะใส่การรัน NNUE ที่นี่ |

### `nets/` — net ที่เทรนเสร็จ

| ไฟล์ | หน้าที่ |
|---|---|
| `nets/.gitkeep` | ไฟล์เปล่าเพื่อให้ git เก็บโฟลเดอร์ที่ยังว่างไว้ เมื่อมี net จริง (ขนาดเล็ก) จะ commit ไว้ที่นี่ พร้อมบันทึก git hash, config และข้อมูลที่ใช้เทรน |

---

## โฟลเดอร์ที่มีบนเครื่องแต่ไม่อยู่ใน git

| โฟลเดอร์ | คืออะไร |
|---|---|
| `data/` | ข้อมูลเทรนที่ datagen สร้าง ตอนนี้มี `test.txt` (20 เกมที่ลองรัน ~1,900 ตำแหน่ง) ไฟล์พวกนี้ใหญ่ได้มาก จึงไม่เก็บใน git สร้างใหม่ได้เสมอจาก seed + config |
| `target/` | ผล build ของ Cargo ลบได้ทุกเมื่อ สร้างใหม่ด้วย `cargo build` |
| `checkpoints/` | (จะเกิดตอนเทรน) net ระหว่างเทรน |

## คำสั่งที่ใช้บ่อย

```bash
cargo test -p wyrdmate-engine                      # ทดสอบ engine
cargo run --release -p wyrdmate-datagen -- 1000 5000 1 data/a.txt   # สร้างข้อมูล 1,000 เกม
cargo run --release -p wyrdmate-trainer --features cuda -- data/a.data  # เทรน (ต้องมี CUDA)
```

## สถานะ

ดูหัวข้อ Status ใน `CLAUDE.md`
