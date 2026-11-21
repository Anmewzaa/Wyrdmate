# เอกสารโครงการ Wyrdmate

ดัชนีของเอกสารทั้งหมดในโฟลเดอร์ `docs/` เลือกอ่านตามวัตถุประสงค์

| ต้องการ | อ่าน |
|---|---|
| **เข้าใจว่า net คืออะไร** (hidden layer, weights ฯลฯ) | [NET.md](NET.md) |
| เข้าใจภาพรวมและการออกแบบระบบ | [ARCHITECTURE.md](ARCHITECTURE.md) |
| เข้าใจวิธีที่ engine เลือก move | [SEARCH.md](SEARCH.md) |
| สร้าง net ใหม่ | [TRAINING.md](TRAINING.md) |
| ทดสอบและตัดสินว่ารุ่นใหม่แรงกว่าเดิมหรือไม่ | [EVALUATION.md](EVALUATION.md) |
| รู้ว่าแต่ละไฟล์ทำหน้าที่อะไร | [STRUCTURE.md](STRUCTURE.md) |
| ดูสถานะและงานถัดไป | [ROADMAP.md](ROADMAP.md) |
| ตรวจสอบศัพท์ | [GLOSSARY.md](GLOSSARY.md) |
| ทราบเหตุผลของการตัดสินใจเชิงออกแบบ | [decisions.md](decisions.md) (ภาษาอังกฤษ) |
| ตรวจสอบที่มาของ net แต่ละตัว | [`../nets/RECORDS.md`](../nets/RECORDS.md) |

`progress/` เก็บข้อมูลและกราฟความคืบหน้า (`data.json` และกราฟ SVG ที่สร้างจากมันด้วย `scripts/make-progress-svg.ps1`)

**ถ้าเพิ่งเริ่ม** อ่านตามลำดับ: [NET.md](NET.md) → [SEARCH.md](SEARCH.md) → [TRAINING.md](TRAINING.md) → [EVALUATION.md](EVALUATION.md)

## เอกสารนอกโฟลเดอร์นี้

- [`../README.md`](../README.md): หน้าแรกของ repository (ภาษาอังกฤษ)
- [`../CLAUDE.md`](../CLAUDE.md): คู่มือและกฎเหล็กของโครงการ ผู้ช่วย AI อ่านโดยอัตโนมัติ เป็นแหล่งอ้างอิงหลักของกฎ ถ้าเอกสารใดขัดแย้ง ให้ยึด `CLAUDE.md`

## แนวทางการเขียนเอกสาร

- เนื้อหาเป็นภาษาไทย **คงศัพท์เทคนิคเป็นภาษาอังกฤษ** ไม่แปลศัพท์สำคัญ (เช่น hidden layer, weights, search, evaluation, pruning, node) รายการศัพท์อยู่ที่ [GLOSSARY.md](GLOSSARY.md)
- ตัวเลขผลทดลองต้องระบุจำนวนเกมและ error bar และต้องตรงกับ `nets/RECORDS.md`
- ตัวเลขที่ไม่ได้วัดจริง (ประมาณ, คำนวณเอง, ยังไม่ได้วัดบนบอร์ด) ต้องบอกว่าเป็นค่าประมาณ
- การตัดสินใจที่เปลี่ยนแปลงให้เพิ่มรายการ D-xxx ใหม่ใน `decisions.md` ห้ามแก้รายการเดิม
- เพิ่มไฟล์ใหม่ในโครงการแล้ว ให้อัปเดต `STRUCTURE.md` และตารางในไฟล์นี้
- แต่ละข้อมูลควรอยู่ที่เดียว ที่อื่นให้ลิงก์ไปหา (เช่น ผลวัดอยู่ที่ EVALUATION.md, โครงสร้าง net อยู่ที่ NET.md)
