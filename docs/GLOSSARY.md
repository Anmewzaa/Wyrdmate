# Glossary

ศัพท์เทคนิคของโครงการ เรียงตามตัวอักษรภาษาอังกฤษ **คงเป็นภาษาอังกฤษทั้งหมดในเอกสาร** เพื่อให้ค้นหาและอ่านเอกสารภายนอกได้ตรงกัน

| ศัพท์ | ความหมาย |
|---|---|
| **A/B match** | การแข่งระหว่าง engine รุ่นใหม่กับรุ่นเดิมที่ node limit เท่ากัน เพื่อตัดสินว่าควรรับรุ่นใหม่หรือไม่ ([EVALUATION.md](EVALUATION.md)) |
| **accumulator** | ผลรวม weights ของ hidden layer ก่อนผ่าน activation function ณ ตำแหน่งปัจจุบัน ใน NNUE ปรับเฉพาะส่วนที่หมากเปลี่ยน (incremental update) ([NET.md](NET.md) ข้อ 5) |
| **activation function** | ฟังก์ชันที่ใช้กับผลของ neuron ทำให้ net จับความสัมพันธ์ที่ไม่ใช่เส้นตรงได้ ที่นี่ใช้ SCReLU |
| **alpha-beta** | เทคนิค pruning ของ search ที่ไม่ต้องพิจารณา move ที่ไม่มีทางถูกเลือก ผลเหมือน minimax เต็มรูปแบบ ([SEARCH.md](SEARCH.md) ข้อ 4) |
| **bias** | ค่าคงที่ที่บวกเพิ่มในแต่ละ neuron และ output เรียนรู้ได้เช่นเดียวกับ weights |
| **batch / superbatch** | batch คือข้อมูลก้อนหนึ่ง (16,384 ตำแหน่ง) ที่ใช้ปรับ weights หนึ่งครั้ง superbatch คือชุดของ batch ที่บันทึก checkpoint หนึ่งครั้ง |
| **beta cutoff** | การหยุดลอง move ที่เหลือใน node เมื่อพบ move ที่ให้คะแนน ≥ beta |
| **bullet** | ไลบรารี training NNUE ที่โครงการใช้ ตรึงที่ git rev (D-002) |
| **capacity** | ความจุในการเก็บความรู้ของ net ขึ้นกับจำนวน weights (hidden size) |
| **centipawn (cp)** | หน่วยคะแนน 100 cp ≈ ได้เปรียบเบี้ยหนึ่งตัว |
| **check extension** | ค้นลึกขึ้น 1 ply เมื่อ move รุกคิง (s9) |
| **checkpoint** | สถานะ training ณ จุดหนึ่ง เก็บใน `checkpoints/` (ไม่เข้า git) |
| **cozy-chess** | ไลบรารีสร้าง legal moves (D-004) |
| **datagen** | โปรแกรมสร้างข้อมูล training ด้วย self-play |
| **delta pruning** | ใน quiescence ข้าม capture ที่ต่อให้ได้หมากก็ไม่ถึง alpha (s8) |
| **depth / ply** | depth คือความลึกที่ search ค้น ply คือหนึ่งการเดินของฝ่ายใดฝ่ายหนึ่ง |
| **Elo** | หน่วยวัดความต่างของความแรงจากผลแข่ง 0 = เท่ากัน ในโครงการนี้เป็นค่า **สัมพัทธ์** ไม่ใช่ Elo มาตรฐาน |
| **error bar (±)** | ช่วงความคลาดเคลื่อนของ Elo ที่วัดได้ ยิ่งแข่งมากเกม (อิสระกัน) ยิ่งแคบ |
| **evaluation** | การให้คะแนนตำแหน่ง ใน engine นี้ทำโดย net (หรือ material eval ถ้าไม่มี net) |
| **fastchess** | โปรแกรมจัดการแข่งระหว่าง engine ที่ใช้ใน A/B match |
| **feature** | ค่า input หนึ่งตัวของ net ที่นี่คือ "ช่องนี้มีหมากชนิดนี้สีนี้ไหม" (768 ตัว) |
| **FEN** | ข้อความมาตรฐานที่ใช้อธิบายตำแหน่งบนกระดาน |
| **firmware** | โค้ดที่รันบน ESP32 (`no_std`) ยังเป็นโครงเปล่า |
| **futility pruning** | ใกล้ปลายต้นไม้ ข้าม quiet move ที่คะแนน + margin ยังไม่ถึง alpha (s7) |
| **hidden layer** | ชั้นกลางของ net ระหว่าง input กับ output แต่ละ neuron จับรูปแบบหนึ่งอย่างจากกระดาน ของเรามีชั้นเดียว 32 neurons ([NET.md](NET.md) ข้อ 4) |
| **hidden size** | จำนวน neuron ใน hidden layer (ตอนนี้ 32) คือสิ่งที่เรียกว่า "ขนาด net" |
| **input layer / output layer** | ชั้นข้อมูลเข้า (768 ค่า) / ชั้นผลลัพธ์ (คะแนน 1 ค่า) |
| **iterative deepening** | ค้นทีละ depth 1, 2, 3 ... เพื่อให้มีผลที่ใช้ได้เสมอเมื่อ node หมด |
| **killer move / history heuristic** | เทคนิค move ordering ที่จำ quiet move ที่เคยทำให้เกิด cutoff |
| **ladder** | ตารางความแรงของ engine ที่ node limit ต่าง ๆ วัดด้วยการแข่ง round-robin ([EVALUATION.md](EVALUATION.md) ข้อ 5) |
| **late move reductions (LMR)** | ค้น move ท้าย ๆ ในลำดับให้ตื้นลงก่อน แล้วค้นซ้ำเต็ม depth ถ้าได้คะแนนเกิน alpha (s5) |
| **loss** | ความคลาดเคลื่อนของ net จากเฉลย ยิ่งน้อยยิ่งทายใกล้ **เปรียบเทียบข้ามชุดข้อมูลไม่ได้** และต่ำไม่ได้แปลว่าเล่นเก่ง |
| **material eval** | evaluation ที่นับแค่มูลค่าหมาก (pawn 100, queen 900 ฯลฯ) ใช้เป็นตัวเทียบ (baseline) |
| **move ordering** | การเรียง move ก่อนลอง ยิ่งลอง move ที่ดีก่อน pruning ยิ่งได้มาก ([SEARCH.md](SEARCH.md) ข้อ 6) |
| **MVV-LVA** | Most Valuable Victim – Least Valuable Attacker: ลอง capture ที่กินของแพงด้วยของถูกก่อน |
| **negamax** | รูปแบบเขียน minimax ที่ใช้ฟังก์ชันเดียวสำหรับทั้งสองฝ่าย |
| **net** | ไฟล์ weights ของ NNUE ที่ผ่านการ training (`nets/*.bin`) และตัวประเมินตำแหน่งที่ใช้ weights นั้น ([NET.md](NET.md)) |
| **neuron** | หน่วยคิดหนึ่งหน่วยใน hidden layer: รวม input ด้วย weights + bias แล้วผ่าน activation function |
| **NNUE** | Efficiently Updatable Neural Network: net ขนาดเล็กที่ปรับค่าได้เร็วเมื่อหมากขยับเพียงเล็กน้อย |
| **node / node limit** | node คือตำแหน่งหนึ่งที่ search พิจารณา (ไม่เกี่ยวกับ neuron) node limit คือจำนวนสูงสุดต่อ move ใช้ควบคุมความแรง |
| **null-move pruning** | ลอง "ข้ามตา" แล้วค้นตื้น ถ้ายังได้คะแนนถึง beta ก็ตัด branch (s4) |
| **overfitting** | net จดจำตัวอย่างใน training แทนที่จะสรุปรูปแบบ ทำให้ใช้กับตำแหน่งใหม่ได้ไม่ดี |
| **perspective (STM / NTM)** | มุมมองของ net: ฝ่ายที่ถึงตา (side to move) และอีกฝ่าย (not to move) |
| **pruning** | การไม่ค้นบาง branch เพื่อประหยัด node |
| **quantisation** | การปัด weights ทศนิยมเป็นจำนวนเต็ม (`i16`) เพื่อให้ไฟล์เล็กและคำนวณบน microcontroller ได้ |
| **quiescence search** | การค้นต่อเฉพาะ capture/promotion จนตำแหน่ง quiet ก่อนประเมิน ([SEARCH.md](SEARCH.md) ข้อ 5) |
| **repetition detection** | ตรวจตำแหน่งซ้ำ นับเป็นเสมอ (s2) |
| **round** | หนึ่งรอบของวงวน: datagen → training → A/B match |
| **SCReLU** | activation function `clamp(x, 0, QA)²` |
| **search** | การลองเดินล่วงหน้าหลาย ply เพื่อเลือก move ที่ดีที่สุด ([SEARCH.md](SEARCH.md)) |
| **self-play** | ให้ engine เล่นกับตัวเองเพื่อสร้างข้อมูล |
| **training** | กระบวนการปรับ weights ให้ net ทายคะแนนใกล้เฉลยขึ้น ([TRAINING.md](TRAINING.md)) |
| **transposition table (TT)** | ตารางจำผลของตำแหน่งที่เคยค้น ใช้ตัด branch และเลือก move แรก (s6) |
| **UCI** | Universal Chess Interface โปรโตคอลที่โปรแกรมหมากรุกใช้สื่อสารกัน |
| **wdl** | weight ที่ให้ผลแพ้/เสมอ/ชนะจริงในเฉลยตอน training (0.0 = ใช้คะแนนของ engine ล้วน) ใช้ 0.0 ตาม D-010 |
| **weights** | ตัวเลขที่เรียนรู้ได้ของ net คือ "ความรู้" ทั้งหมดที่เก็บในไฟล์ `.bin` คงที่ตอนเล่น |
