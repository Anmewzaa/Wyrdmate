# web/ — เล่น Wyrdmate บนเบราว์เซอร์ (WebAssembly)

เวอร์ชันสำหรับโฮสต์เป็นไฟล์ static (เช่น GitHub Pages) ไม่ต้องมี server
ใช้ engine ตัวเดียวกับ `engine/` คอมไพล์เป็น `wyrd.wasm` ไม่แตะโค้ดหลัก
อยู่นอก workspace (เหมือน `firmware/`) จึงไม่กระทบ `cargo test` / `cargo check` ปกติ

| ไฟล์ | หน้าที่ |
|---|---|
| `src/lib.rs` | ฟังก์ชัน C ABI ที่หน้าเว็บเรียก: `alloc`, `dealloc`, `best_move`, `result_ptr` |
| `backend.js` | โหลด `wyrd.wasm` และ net แล้วเรียก `best_move` แทนการเรียก `play.py` |
| `build.ps1` | build ทั้งหมดไปที่ `web/dist/` (git-ignored) |

หน้าเว็บคือ `scripts/play.html` ไฟล์เดียวกับที่ใช้เล่นในเครื่อง `build.ps1` แค่แทรก `backend.js` เข้าไป

## Build และลองในเครื่อง

ต้องมี target ครั้งเดียว: `rustup target add wasm32-unknown-unknown`

```powershell
powershell -File web/build.ps1
python -m http.server 8002 --directory web/dist
```

แล้วเปิด http://localhost:8002/ (เปิดด้วย `file://` ตรง ๆ ไม่ได้ เพราะเบราว์เซอร์ไม่ยอมโหลด WASM จากไฟล์)

## ข้อควรรู้

- ผลต้องตรงกับ engine บนพีซี: ตรวจแล้วที่ 1 ตำแหน่ง (3,000 node, `wyrd-iv`; ยังไม่ได้ตรวจซ้ำกับ `wyrd-vi`) ได้ `e7e6` คะแนน +5 เหมือนกัน
- ตัวเลข Elo ในเมนูวัดด้วย `wyrd-vi` และ search s10 (EVALUATION.md ข้อ 5) ไม่ได้วัดซ้ำกับ `wyrd-vii`
- ยังไม่ได้ deploy ที่ใดเลย
