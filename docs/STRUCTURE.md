# โครงสร้างโครงการ Wyrdmate

หน้าที่ของแต่ละไฟล์และโฟลเดอร์ เขียนสำหรับผู้อ่านที่เป็นมนุษย์ (`CLAUDE.md` เขียนสำหรับผู้ช่วย AI)
ภาพรวมการออกแบบและการไหลของข้อมูลอยู่ที่ [ARCHITECTURE.md](ARCHITECTURE.md) รายการเอกสารอยู่ที่ [README.md](README.md) ของโฟลเดอร์นี้

**สารบัญ:** [1. ระดับบนสุด](#1-ระดับบนสุด) · [2. engine](#2-engine) · [3. datagen](#3-datagen) · [4. trainer](#4-trainer) · [5. firmware](#5-firmware) ·
[6. web](#6-web) · [7. scripts](#7-scripts) · [8. nets](#8-nets) · [9. ไม่อยู่ใน git](#9-สิ่งที่มีบนเครื่องแต่ไม่อยู่ใน-git) · [10. คำสั่งที่ใช้บ่อย](#10-คำสั่งที่ใช้บ่อย)

---

## 1. ระดับบนสุด

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | Cargo workspace สมาชิกคือ `engine`, `datagen`, `trainer` ส่วน `firmware` (build ด้วย target ของ ESP32) และ `web` (engine เป็น WebAssembly) ถูก `exclude` |
| `Cargo.lock` | ล็อกเวอร์ชันไลบรารีทุกตัว รวมถึง commit ของ bullet เพื่อให้ build ซ้ำได้ ไม่ต้องแก้ด้วยมือ |
| `.gitignore` | ไฟล์ที่ไม่เก็บใน git (ข้อ 9) |
| `.github/workflows/pages.yml` | build `web/` แล้ว deploy ขึ้น GitHub Pages เมื่อ push ที่แก้ `web/`, `engine/`, `nets/` หรือ `scripts/play.html` |
| `README.md` | หน้าแรกของ repository (ภาษาอังกฤษ): ภาพรวม ผลการเทรน วิธีลองใช้ผ่าน UCI |
| `LICENSE` | สัญญาอนุญาต MIT |
| `CLAUDE.md` | คู่มือและกฎเหล็กของโครงการ ผู้ช่วย AI โหลดอัตโนมัติ |
| `docs/` | เอกสารทั้งหมด ดู [README.md](README.md) |

---

## 2. `engine/`

crate `wyrdmate-engine` คือเครื่องยนต์หมากรุก

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ประกาศ crate และ dependency `cozy-chess` (ตัวสร้าง legal moves) |
| `src/lib.rs` | โค้ดหลัก: `evaluate` (material eval), `Searcher` (search ทั้งหมดตาม [SEARCH.md](SEARCH.md)), `legal_moves`, `node_limit`, transposition table, test ท้ายไฟล์ |
| `src/nnue.rs` | อ่านไฟล์ net (`quantised.bin`) และคำนวณคะแนนตามโครงสร้างเดียวกับ trainer ([NET.md](NET.md)) accumulator เป็นแบบ incremental (`accumulator_after`) และมี test เทียบกับการคำนวณใหม่ทั้งกระดาน |
| `src/main.rs` | UCI front end รองรับ option `Nodes` (ความแรง), `EvalFile` (ไฟล์ net), `Hash` (ขนาด TT เป็น KiB) |
| `examples/validate.rs` | เทียบคะแนนจาก net กับคะแนนในไฟล์ข้อมูล ตรวจว่าอ่าน net ถูกต้อง |
| `examples/book.rs` | สร้างตำแหน่งเปิดเกมสุ่มที่สมดุลสำหรับ A/B match |

## 3. `datagen/`

crate `wyrdmate-datagen` สร้างข้อมูลเทรนด้วย self-play

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | crate ที่ใช้ `wyrdmate-engine` |
| `src/main.rs` | ให้ engine เล่นกับตัวเองและเขียนบรรทัด `FEN \| คะแนน \| ผลเกม` กติกาของแต่ละเกมและคำสั่งดู [TRAINING.md](TRAINING.md) ข้อ 2 |

## 4. `trainer/`

crate `wyrdmate-trainer` เป็นตัวขับ bullet

| ไฟล์ | หน้าที่ |
|---|---|
| `Cargo.toml` | ดึง `bullet_lib` จาก git โดยตรึงที่ commit หนึ่ง (API เปลี่ยนบ่อย) มี feature `cuda` สำหรับ GPU NVIDIA |
| `src/main.rs` | กำหนดโครงสร้าง net `(768 → H) × 2 → 1` (H = hidden size เป็นอาร์กิวเมนต์ ค่าเริ่มต้น 32) และตารางเทรน แล้วสั่ง bullet ผลเป็น net ที่ quantise แล้วใน `checkpoints/` |

## 5. `firmware/`

โค้ดสำหรับ ESP32 **ยังเป็นโครงเปล่า** `Cargo.toml` เป็น crate แยกจาก workspace และ `src/lib.rs` เป็น `#![no_std]` ที่ว่างอยู่ แผนอยู่ที่ [ROADMAP.md](ROADMAP.md)

## 6. `web/`

engine คอมไพล์เป็น WebAssembly (`cdylib` ใช้ C ABI) สำหรับหน้าเล่นบนเว็บ ไม่แก้โค้ด engine

| ไฟล์ | หน้าที่ |
|---|---|
| `src/lib.rs`, `Cargo.toml` | ตัวห่อ engine เป็น WebAssembly |
| `backend.js` | ฝั่ง JavaScript ที่เรียก wasm |
| `build.ps1`, `build.sh` | สร้าง `web/dist` (wasm + nets + หน้าเล่น) `build.sh` ใช้ใน GitHub Actions |
| `README.md` | รายละเอียดและข้อจำกัดของเว็บเดโม |

`web/dist/` ไม่อยู่ใน git ต้องรัน `build.ps1` ใหม่ทุกครั้งที่มี net หรือ engine ใหม่

## 7. `scripts/`

| ไฟล์ | หน้าที่ |
|---|---|
| `ab.ps1` | รัน A/B match ครบขั้นตอน ([EVALUATION.md](EVALUATION.md) ข้อ 3) |
| `monitor.py` | หน้าเว็บในเครื่อง (`python scripts/monitor.py` แล้วเปิด http://localhost:8765) ดูความคืบหน้า datagen, training และ A/B match จากไฟล์ log แบบอ่านอย่างเดียว มีหน้า `/datagen`, `/train`, `/match` |
| `make-progress-svg.ps1` | สร้างกราฟใน `docs/progress/` จาก `data.json` |
| `dedup.py` | ตัดตำแหน่งซ้ำออกจากไฟล์ข้อมูลของ datagen (ใช้สร้างข้อมูลของ `wyrd-1`) |
| `play.py`, `play.html` | หน้าเล่นกับ engine ในเครื่อง (engine vs engine ได้ด้วย) `play.html` เป็นหน้าเดียวกับที่ `web/` ใช้ |
| `pgn-viewer.html` | เปิด PGN จาก fastchess เพื่อดูเกมซ้ำ |

## 8. `nets/`

| ไฟล์ | หน้าที่ |
|---|---|
| `wyrd-i.bin` | net รอบ 1 เก็บไว้เป็นผู้เล่นสร้างข้อมูลรอบ 2 เท่านั้น (ไม่ผ่านเกณฑ์ความแรง) |
| `wyrd-ii.bin` ถึง `wyrd-v.bin` | net รอบ 2–5 ที่ผ่านเกณฑ์ (รุ่นเก่า เก็บไว้เทียบ) |
| `wyrd-vi.bin` | net รอบ 6 (รุ่นก่อนหน้า เก็บไว้เทียบ) |
| `wyrd-vii.bin` | net รอบ 7 (รุ่นก่อนหน้า เก็บไว้เทียบ) |
| `wyrd-viii.bin` | net รอบ 8 (รุ่นก่อนหน้า เก็บไว้เทียบ) |
| `wyrd-ix.bin` | net รอบ 9 (รุ่นก่อนหน้า เก็บไว้เทียบ) |
| `wyrd-1.bin` | net รอบ 9 ข้อมูลตัดตำแหน่งซ้ำ เริ่มเลขใหม่ (D-013) **ปัจจุบัน** |
| `RECORDS.md` | ที่มาของ net ทุกตัวและการทดลองที่ไม่ผ่าน (กฎเหล็กข้อ 1) |
| `.gitkeep` | ไฟล์เปล่าจากสมัยที่โฟลเดอร์ยังว่าง |

ผลแข่งของแต่ละ net อยู่ใน [EVALUATION.md](EVALUATION.md) ข้อ 8

## 9. สิ่งที่มีบนเครื่องแต่ไม่อยู่ใน git

| โฟลเดอร์/ไฟล์ | คืออะไร |
|---|---|
| `data/` | ข้อมูลเทรน (`.txt` จาก datagen และ `.data` ที่แปลงแล้ว) และ opening book สร้างใหม่ได้จาก seed ที่บันทึกใน `nets/RECORDS.md` |
| `target/`, `web/target/`, `web/dist/` | ผล build ลบได้ทุกเมื่อ |
| `checkpoints/` | net ระหว่างเทรน เฉพาะตัวที่ผ่านเกณฑ์จึงคัดลอกไป `nets/` |
| `logs/` | log, PGN และ `.meta.json` จาก A/B match และ ladder |
| `tools/` | fastchess, Stockfish, ไบนารี engine ที่ `ab.ps1` build ไว้ |
| `config.json` | ไฟล์ที่ fastchess สร้างในโฟลเดอร์ที่รัน |
| `__pycache__/`, `*.pyc` | cache ของ Python |

## 10. คำสั่งที่ใช้บ่อย

```bash
cargo test -p wyrdmate-engine                                           # ทดสอบ engine
cargo run --release -p wyrdmate-datagen -- 1000 5000 1 data/a.txt       # สร้างข้อมูล 1,000 เกม
cargo run --release -p wyrdmate-trainer --features cuda -- data/a.data  # training (ต้องมี CUDA)
powershell -File scripts/ab.ps1 -Net nets/wyrd-1.bin -OldNet nets/wyrd-ix.bin   # A/B match
python scripts/monitor.py                                               # หน้าดูความคืบหน้า
```

สถานะปัจจุบันของโครงการดู [ROADMAP.md](ROADMAP.md)
