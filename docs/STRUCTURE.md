# โครงสร้างโครงการ Wyrdmate

เอกสารนี้อธิบายหน้าที่ของแต่ละไฟล์และโฟลเดอร์ เขียนสำหรับผู้อ่านที่เป็นมนุษย์
(`CLAUDE.md` เขียนสำหรับผู้ช่วย AI) ภาพรวมเชิงออกแบบอยู่ที่ [ARCHITECTURE.md](ARCHITECTURE.md)

**สารบัญ:** [ภาพรวม](#1-ภาพรวมการไหลของงาน) · [ระดับบนสุด](#2-ระดับบนสุด) · [engine](#3-engine) ·
[datagen](#4-datagen) · [trainer](#5-trainer) · [firmware](#6-firmware) · [nets](#7-nets) ·
[ไม่อยู่ใน git](#8-สิ่งที่มีบนเครื่องแต่ไม่อยู่ใน-git) · [คำสั่งที่ใช้บ่อย](#9-คำสั่งที่ใช้บ่อย)

---

## 1. ภาพรวมการไหลของงาน

```text
engine ──(เล่นเกม)──▶ datagen ──▶ data/*.txt ──[bullet-utils แปลง]──▶ *.data
                                                                      │
firmware ◀──(ฝัง net ที่ quantise แล้ว)── nets/ ◀── checkpoints/ ◀── trainer (bullet)
```

1. `engine` ค้นหาตาเดินที่ดีที่สุดในตำแหน่งหนึ่ง
2. `datagen` ให้ engine เล่นกับตัวเอง แล้วบันทึกตำแหน่งเป็นบรรทัด `FEN | คะแนน | ผลเกม`
3. `trainer` ใช้ข้อมูลนั้นสอน neural network (NNUE) ให้ประเมินตำแหน่งได้
4. net ที่ผ่านการแข่งทดสอบจะแทนฟังก์ชันประเมินเดิมใน engine และ (ในอนาคต) ถูกฝังใน `firmware` สำหรับ ESP32

---

## 2. ระดับบนสุด

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ไฟล์หลักของ Cargo workspace สมาชิกคือ `engine`, `datagen`, `trainer` ส่วน `firmware` และ `web` ถูก `exclude` (`firmware` build ด้วย target ของ ESP32, `web` เป็น engine คอมไพล์เป็น WebAssembly สำหรับหน้าเล่นบนเว็บ ดู `web/README.md`) กำหนดค่ากลาง (version, edition, license) |
| `Cargo.lock` | ล็อกเวอร์ชันไลบรารีทุกตัว รวมถึง commit ของ bullet เพื่อให้ build ซ้ำได้ ไม่ต้องแก้ด้วยมือ |
| `.gitignore` | ไฟล์ที่ไม่เก็บใน git: `target/`, `checkpoints/`, `data/`, `*.binpack` |
| `README.md` | หน้าแรกของ repository (ภาษาอังกฤษ): ภาพรวม ผลการเทรน วิธีลองใช้ผ่าน UCI |
| `LICENSE` | สัญญาอนุญาต MIT |
| `CLAUDE.md` | คู่มือและกฎเหล็กของโครงการ ผู้ช่วย AI โหลดอัตโนมัติ |
| `docs/` | เอกสารทั้งหมด ดู [README.md](README.md) ของโฟลเดอร์นี้ |
| `scripts/make-progress-svg.ps1` | สคริปต์ PowerShell สร้างกราฟความคืบหน้าจาก `docs/progress/data.json` |

### เอกสารใน `docs/`

| ไฟล์ | หน้าที่ |
|---|---|
| `README.md` | ดัชนีของเอกสาร |
| `ARCHITECTURE.md` | สถาปัตยกรรม และรูปแบบไฟล์ net |
| `SEARCH.md` | กระบวนการค้นหาของ engine |
| `STRUCTURE.md` | ไฟล์นี้ |
| `TRAINING.md` | ขั้นตอนเทรน NNUE ทั้งกระบวนการ |
| `EVALUATION.md` | วิธีแข่ง A/B และเกณฑ์รับ net |
| `decisions.md` | บันทึกการตัดสินใจ (D-001 ขึ้นไป) |
| `GLOSSARY.md` | อภิธานศัพท์ |
| `ROADMAP.md` | สถานะและงานที่เหลือ |
| `progress/data.json` | ข้อมูลผลแข่ง (Elo) และ loss ตอนเทรน รวมข้อความในกราฟ เพิ่มแถวใหม่ทุกครั้งที่แข่งเสร็จ |
| `progress/training-process.svg`, `progress/loss.svg` | กราฟสองใบที่ฝังใน README สร้างจาก `data.json` |

---

## 3. `engine/`

crate `wyrdmate-engine` คือเครื่องยนต์หมากรุก

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ประกาศ crate และ dependency `cozy-chess` (ตัวสร้างตาเดินที่ถูกกติกา) |
| `src/lib.rs` | โค้ดหลักของ engine (รายละเอียดด้านล่าง) |
| `src/nnue.rs` | อ่านไฟล์ net (`quantised.bin`) และคำนวณคะแนนตามโครงสร้างเดียวกับ trainer accumulator เป็นแบบ incremental (`accumulator_after`) และมี test เทียบกับการคำนวณใหม่ทั้งกระดาน |
| `src/main.rs` | หน้าด่าน UCI รองรับ option `Nodes` (ความแรง) และ `EvalFile` (ไฟล์ net) |
| `examples/validate.rs` | เทียบคะแนนจาก net กับคะแนนที่เก็บในไฟล์ข้อมูล เพื่อตรวจว่าอ่าน net ถูกต้อง |
| `examples/book.rs` | สร้างตำแหน่งเปิดเกมสุ่มที่สมดุลสำหรับการแข่ง A/B |

**`src/lib.rs` ประกอบด้วย**

- `evaluate`: ประเมินแบบนับมูลค่าหมาก (ตัวตั้งต้นสำหรับเทียบกับ net)
- `Searcher`: negamax + alpha-beta + quiescence search + iterative deepening
- `Searcher::with_net`: ให้ค้นหาโดยใช้ NNUE แทนการนับมูลค่าหมาก
- `node_limit`: จำกัดความแรง ยิ่งน้อยยิ่งอ่อน
- `legal_moves`: ตาเดินที่ถูกกติกาทั้งหมด
- เทสต์ท้ายไฟล์ 3 ข้อ: eval ตำแหน่งเริ่มต้นเป็น 0, พบ mate in 1, เคารพ node limit

---

## 4. `datagen/`

crate `wyrdmate-datagen` สร้างข้อมูลเทรน

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ประกาศ crate ที่ใช้ `wyrdmate-engine` |
| `src/main.rs` | ให้ engine เล่นกับตัวเองและเขียนข้อมูลเป็นบรรทัดรูปแบบ FEN, คะแนน, ผลเกม (คั่นด้วยเครื่องหมายขีดตั้ง ดู TRAINING.md) |

พฤติกรรมของ `src/main.rs`:

- เปิดเกมด้วยการเดินสุ่ม 8–9 ตา เพื่อให้แต่ละเกมแตกต่างกัน
- เล่นต่อด้วยการค้นหาที่จำกัด node
- จบเกมเมื่อจบตามกติกา, เมื่อได้เปรียบเกิน 15 เบี้ยติดกัน 4 ตา หรือเมื่อครบ 300 ตา
- บันทึกเฉพาะตำแหน่งที่ "สงบ" (ไม่ถูกรุก และตาที่เดินไม่ใช่การกิน)

การใช้งาน:

```text
wyrdmate-datagen [เกม] [nodes] [seed] [ไฟล์ออก] [net.bin (ไม่บังคับ)]
```

หากระบุ `net.bin` ตัว net จะเป็นผู้เล่นสร้างข้อมูล (ใช้ในรอบที่ 2 เป็นต้นไป)

---

## 5. `trainer/`

crate `wyrdmate-trainer` เป็นตัวขับ bullet

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ดึง `bullet_lib` จาก git โดยตรึงที่ commit หนึ่ง (API เปลี่ยนบ่อย) มี feature `cuda` สำหรับเทรนบน GPU NVIDIA |
| `src/main.rs` | กำหนดโครงสร้าง net `768 → 32×2 → 1` และตารางเทรน แล้วสั่ง bullet เทรน ผลเป็น net ที่ quantise แล้วใน `checkpoints/` |

การใช้งาน:

```text
wyrdmate-trainer <data.data> [superbatches] [batches_per_sb] [batch_size] [wdl] [net_id]
```

รายละเอียดของโครงสร้าง net ดู [ARCHITECTURE.md](ARCHITECTURE.md) หัวข้อ 5

---

## 6. `firmware/`

โค้ดสำหรับ ESP32 **ยังเป็นโครงเปล่า**

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | crate แยกจาก workspace (build ด้วย target ของ ESP32) ยังไม่มี dependency ของชิป |
| `src/lib.rs` | `#![no_std]` ปัจจุบันว่าง จะเป็นที่อยู่ของการรัน NNUE |

---

## 7. `nets/`

| ไฟล์ | หน้าที่ |
|---|---|
| `wyrd-i.bin` | net รอบที่ 1 เก็บไว้เป็นตัวสร้างข้อมูลของรอบที่ 2 (ยังไม่ผ่านเกณฑ์ความแรง) |
| `wyrd-ii.bin` | net รอบที่ 2 ผ่านเกณฑ์ (+115 Elo เทียบ engine นับมูลค่าหมาก) |
| `wyrd-iii.bin` | net รอบที่ 3 (+81 Elo เทียบ wyrd-ii, +166 เทียบ engine นับมูลค่าหมาก) |
| `wyrd-iv.bin` | net รอบที่ 4 **ปัจจุบัน** (+31 Elo เทียบ wyrd-iii, +212 เทียบ engine นับมูลค่าหมาก) |
| `RECORDS.md` | บันทึกที่มาของ net ทุกตัวและการทดลองที่ไม่ผ่าน |
| `.gitkeep` | ไฟล์เปล่าจากสมัยที่โฟลเดอร์ยังว่าง |

---

## 8. สิ่งที่มีบนเครื่องแต่ไม่อยู่ใน git

| โฟลเดอร์/ไฟล์ | คืออะไร |
|---|---|
| `data/` | ข้อมูลเทรน (`.txt` จาก datagen และ `.data` ที่แปลงแล้ว) ขนาดใหญ่ สร้างใหม่ได้จาก seed และค่าที่บันทึกใน `nets/RECORDS.md` |
| `target/` | ผล build ของ Cargo ลบได้ทุกเมื่อ |
| `checkpoints/` | net ระหว่างเทรน เฉพาะตัวที่ผ่านเกณฑ์จึงคัดลอกไป `nets/` |
| `logs/` | log และ PGN จากการแข่ง A/B |
| `config.json` | ไฟล์ที่ fastchess สร้างในโฟลเดอร์ที่รัน (อยู่ใน `.gitignore`) |

---

## 9. คำสั่งที่ใช้บ่อย

```bash
cargo test -p wyrdmate-engine                                          # ทดสอบ engine
cargo run --release -p wyrdmate-datagen -- 1000 5000 1 data/a.txt      # สร้างข้อมูล 1,000 เกม
cargo run --release -p wyrdmate-trainer --features cuda -- data/a.data # เทรน (ต้องมี CUDA)
```

สถานะปัจจุบันของโครงการดู [ROADMAP.md](ROADMAP.md)
