# S05 — Supply & Demand Zones
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: P9-5 | 2026-02-27 | Jimmi Deep-Dive Edition

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S05 | รหัสอ้างอิงลำดับที่ห้าในระบบมัลติกลยุทธ์ FlashEASuite V2 เป็น Full MQL5 Strategy ที่เน้นการตรวจจับ "โซนราคา" ที่สถาบันทิ้งร่องรอยไว้ในรูปแบบของ Pattern 5–7 แท่งที่ชัดเจนกว่า OB/FVG ใน S03 |
| **ชื่อ** | Supply & Demand Zones | แนวคิดที่มองว่าการเคลื่อนไหวของราคาทุกครั้งเกิดจากความไม่สมดุลระหว่าง Order ซื้อ (Demand) และ Order ขาย (Supply) โซน SD คือบริเวณที่ความไม่สมดุลนั้นฝังอยู่และรอการ "ล้าง" |
| **ประเภท** | Full MQL5 | การตรวจจับโซน, การคำนวณ Strength, การนับ Touches, และการตัดสินใจเข้า Trade ทั้งหมดเกิดขึ้นใน MQL5 โดย `CZoneDetector` Python Brain ทำหน้าที่ Regime Scoring และ Config Delivery |
| **Standalone Capable** | ❌ No (Server Only) | มี ServerOnly Guard: `if(m_config.confidence < 0.01) return;` โซน SD ที่ตรวจจับได้โดยไม่มี Regime Filter จะมี False Positive Rate สูงมากในตลาด VOLATILE |
| **Preferred Regime** | TRENDING, RANGING | TRENDING: Supply/Demand Zones ที่เกิดในทิศทางแนวโน้มหลักมีความน่าเชื่อถือสูงมาก / RANGING: Zones บนขอบบนล่างของกรอบราคาเป็น Reaction Point ที่แม่นยำ |
| **Poor Regimes** | VOLATILE, extreme news | ใน VOLATILE โซนถูกทำลายก่อนที่จะทำหน้าที่ได้ Departure Move ที่เกิดจาก News Spike ไม่ใช่ Institutional Order ทำให้ Zone ไม่ Valid |
| **MQL5 Class** | `CSupplyDemand` | คลาสหลักที่ประสานงาน `CZoneDetector` ตรวจสอบเงื่อนไข Entry, คำนวณ Confidence, SL และ TP แบบ Zone-to-Zone |
| **Sub-Component** | `CZoneDetector` | คลาสย่อยที่ตรวจจับและติดตาม Supply/Demand Zones ทั้งหมด รองรับสูงสุด `MAX_SD_ZONES = 16` โซนพร้อมกัน |

### สรุปแนวคิด (Summary of Concepts)

S05 เป็นกลยุทธ์ที่ตั้งอยู่บนหลักการ **Supply & Demand Zone Analysis** — ปรัชญาการวิเคราะห์ที่มองว่าราคาทุกจุดในตลาดเป็นผลของการ "ต่อสู้" ระหว่างฝ่ายซื้อ (Demand) และฝ่ายขาย (Supply) โดยในบางช่วงเวลา ความไม่สมดุลระหว่างสองฝ่ายนี้รุนแรงมากพอจนทำให้ราคา "ระเบิด" ออกจากบริเวณหนึ่งอย่างรวดเร็ว

บริเวณที่ราคา "ระเบิด" ออกไปนั้นเรียกว่า **Supply หรือ Demand Zone** และตามทฤษฎี เมื่อราคากลับมาทดสอบโซนนั้นอีกครั้ง คำสั่งซื้อหรือขายที่ยังค้างอยู่จากครั้งแรก (Unfilled Orders) จะถูก Activate และผลักราคาออกในทิศทางเดิมอีกครั้ง

ระบบตรวจจับโซนด้วยสองรูปแบบหลัก:
- **(1) DBR — Drop Base Rally** = Demand Zone (โซนซื้อ)
- **(2) RBD — Rally Base Drop** = Supply Zone (โซนขาย)

และติดตามสถานะของแต่ละโซนด้วย **Freshness System** — โซนใหม่มีคะแนนสูง ทุกครั้งที่ราคาเข้ามาทดสอบ คะแนนลด เมื่อถูกทดสอบครบ 3 ครั้ง โซนจะถือว่า "หมดอายุ" และถูกยกเลิก

---

### ทำไมต้องชื่อ "Supply & Demand Zones"?

**ต้นกำเนิดแนวคิด:**

Supply & Demand Zone Analysis ถูกนำมาใช้อย่างแพร่หลายโดย Sam Seiden อดีตนักเทรดของ Chicago Mercantile Exchange (CME) ในทศวรรษ 2000s เขาสังเกตว่าราคาในตลาด Futures มักจะ "วิ่งกลับ" ไปยังจุดที่เกิดการ Imbalance ครั้งแรก เพราะ Order ขนาดใหญ่ที่ไม่ได้รับการ Fill ในครั้งแรก (Pending Unfilled Orders) ยังคงรออยู่ในระบบ

**ทำไม Unfilled Orders ถึงยังอยู่?**

เมื่อสถาบันต้องการ Long ตลาด และตั้ง Limit Buy Order จำนวนมหาศาล (เช่น 500 ล้าน USD) ที่ราคา 1.0840 แต่ราคากลับ "ระเบิด" ขึ้นอย่างรวดเร็วจาก 1.0840 ไปถึง 1.0890 ภายในไม่กี่แท่ง — หมายความว่า Limit Order บางส่วนของสถาบันไม่ได้ถูก Fill ทั้งหมด (เพราะไม่มี Seller เพียงพอ ณ ราคา 1.0840 ในช่วงเวลาสั้น) Order ส่วนที่เหลือยังคง "รอ" อยู่ที่ 1.0840 เมื่อราคากลับลงมา 1.0840 อีกครั้ง Order เหล่านั้นจะถูก Activate และผลักราคาขึ้นอีกครั้ง

**ความแตกต่างจาก S03 SMC:**

แม้ทั้ง S03 และ S05 จะมองหา "รอยเท้า" ของสถาบัน แต่ต่างกันที่ระดับรายละเอียด:

| ด้าน | S03 SMC | S05 Supply & Demand |
|------|---------|---------------------|
| Pattern | Order Block (1–2 แท่ง) | DBR/RBD (5–7 แท่ง) |
| Context | ต้องมี BOS ยืนยัน | ตรวจจับโดยตรงจาก Departure |
| Zone Tracking | MarkRetested (1 Touch = Inactive) | Freshness System (ทนได้สูงสุด 3 Touches) |
| TP Logic | Fixed ATR Multiple | Zone-to-Zone (TP ที่ Supply/Demand ฝั่งตรงข้าม) |
| Time Decay | ไม่มี | มี (0.2% ต่อแท่ง) |

---

### ธรรมชาติของ Supply & Demand ในตลาด Forex

**Imbalance คือเหตุผลที่ราคาเคลื่อนไหว:**

ในตลาดที่มีสภาพคล่องสมบูรณ์ (Perfectly Liquid Market) ราคาไม่ควรเคลื่อนไหวเลย เพราะทุก Order ซื้อมี Order ขายรองรับพอดี แต่ในความเป็นจริง ตลาด Forex มีช่วงเวลาที่ฝ่ายซื้อหรือฝ่ายขายมี "น้ำหนัก" มากกว่าอีกฝ่ายอย่างมีนัยสำคัญ ทำให้ราคาต้อง "วิ่ง" ไปหา Order ของฝ่ายตรงข้ามในระดับราคาอื่น

ราคาที่วิ่งออกไปเพื่อหา Order ฝั่งตรงข้าม เรียกว่า **Departure Move** ซึ่งทิ้งร่องรอยไว้ในกราฟในรูปแบบของแท่งเทียนขนาดใหญ่ (Large Candle) ที่ออกจากบริเวณ Base Candle อย่างรวดเร็ว

**วงจรชีวิตของโซน (Zone Life Cycle):**

```
ระยะที่ 1 — Zone Formation:
  ราคาอยู่ใน Range แคบ (Base) → สถาบันสะสม Order ไม่สามารถ Fill ได้ทั้งหมด
  จากนั้นราคา Breakout (Departure) อย่างรุนแรง → Zone ก่อตัว

ระยะที่ 2 — Fresh Zone (Untested):
  ราคาวิ่งออกไปจาก Zone — โซนถือว่า "New" (touches = 0)
  โอกาส Reaction สูงสุด เพราะ Unfilled Orders เต็มที่

ระยะที่ 3 — First Retest (touches = 1):
  ราคากลับมาทดสอบโซน → Order บางส่วนถูก Fill
  โอกาส Reaction ลดลงเล็กน้อย แต่ยังดีมาก

ระยะที่ 4 — Second Retest (touches = 2):
  Order ถูก Fill เพิ่มขึ้น โซนยังใช้ได้
  Confidence ลดลงตาม Freshness Formula

ระยะที่ 5 — Third Retest (touches = 3):
  โซน "หมดแรง" → is_active = false → ระบบยกเลิกโซนนี้
  Order ที่เหลืออาจไม่เพียงพอที่จะ Absorb ราคาได้อีก
```

---

### ตัวอย่างเหตุการณ์จริง (Case Study)

สมมติเหตุการณ์ ณ วันที่ 27 กุมภาพันธ์ 2026 บนกราฟ EURUSD H1:

**ส่วนที่ 1 — การก่อตัวของ Demand Zone (DBR Pattern, 20 แท่งที่แล้ว):**

```
ATR(14) = 0.0018 (18 pips)
BaseMult = 0.6 → Base ต้องมี range ≤ 0.6 × 0.0018 = 0.00108 (10.8 pips)
DepartureMult = 1.2 → Departure ต้องมี move > 1.2 × 0.0018 = 0.00216 (21.6 pips)
```

**Drop Before Base (bar[i+3] ถึง bar[i+1]):**
```
Open[23]  = 1.0865   ← ราคาเริ่มต้นของ Drop phase
Close[21] = 1.0840   ← ราคาสิ้นสุดของ Drop phase
move = 1.0840 - 1.0865 = -0.0025 < -0.00216 ✅  DROP ผ่านเกณฑ์
```

**Base Candle (bar[i=20]):**
```
High[20] = 1.0845 | Low[20] = 1.0836 | Range = 0.0009 ≤ 0.00108 ✅  BASE ผ่านเกณฑ์
```

**Bar[19] ขยายโซน (i+1 = 19 ≡ bar ก่อน Base):**
```
Low[19] = 1.0834 | High[19] = 1.0843
Zone bottom = min(1.0836, 1.0834) = 1.0834
Zone top    = max(1.0845, 1.0843) = 1.0845
Zone Width  = 1.0845 - 1.0834 = 0.0011 (11 pips)
```

**Rally After Base (bar[i-1] ถึง bar[i-3]):**
```
Open[19]  = 1.0841   ← ราคาเริ่มต้นของ Rally phase
Close[17] = 1.0875   ← ราคาสิ้นสุดของ Rally phase
move = 1.0875 - 1.0841 = +0.0034 > +0.00216 ✅  RALLY ผ่านเกณฑ์
→ DBR Pattern ยืนยัน → ZONE_DEMAND ก่อตัว
```

**Zone Strength ณ เวลาที่สร้าง:**
```
width_ratio = min(1.0, 0.0011 / (0.0018 × 2.0)) = min(1.0, 0.306) = 0.306
freshness   = max(0.0, 1.0 - 0 × 0.25)          = 1.0   (fresh zone)
age         = 0 bars ณ เวลาที่สร้าง
time_decay  = max(0.2, 1.0 - 0 × 0.002)          = 1.0
strength    = min(1.0, 0.306 × 1.0 × 1.0)        = 0.306
```

**ส่วนที่ 2 — Retest และ Entry (วันนี้ เวลา 08:30 UTC):**

ราคาดึงกลับจาก 1.0875 ลงมาทดสอบ Demand Zone:
```
bid (mid_price) = 1.0839   อยู่ใน Zone [1.0834, 1.0845] ✅
Zone เป็น Fresh (touches = 0) ✅
strength = 0.247 (หลัง time_decay 20 แท่ง: max(0.2, 1.0-20×0.002)=0.96)
         = min(1.0, 0.306 × 1.0 × 0.96) = 0.294

strength ≥ MinZoneStrength (0.25) ✅
```

**การคำนวณ Confidence:**
```
freshness   = max(0.1, 1.0 - 0 × 0.25) = 1.000   (ยังไม่เคยถูก Touch)
width_ratio = min(1.0, 0.0011/(0.0018×1.5)) = min(1.0, 0.407) = 0.407
strength    = 0.294

confidence  = min(1.0, 1.000×0.4 + 0.407×0.3 + 0.294×0.3)
            = min(1.0, 0.400 + 0.122 + 0.088)
            = min(1.0, 0.610) = 0.610

conf (0.610) ≥ MinConfidence (0.40) ✅ → SIGNAL_BUY
```

**การวางออเดอร์:**
```
SL = zone.bottom - SL_ATRBuffer × ATR = 1.0834 - 0.5 × 0.0018 = 1.0825

TP: _FindOppositeTP(true, 1.0839, 0.0018)
  → ค้นหา Supply Zone ที่ Active เหนือราคาปัจจุบัน
  → พบ Supply Zone [1.0868, 1.0878] (ก่อตัวจาก RBD เมื่อ 35 แท่งที่แล้ว)
  → TP = zone.bottom = 1.0868

SL Distance = 1.0839 - 1.0825 = 14 pips
TP Distance = 1.0868 - 1.0839 = 29 pips
R:R Ratio   = 29 / 14 ≈ 2.07:1

หาก ไม่มี Supply Zone → Fallback TP = 1.0839 + 2.5×0.0018 = 1.0884 (45 pips)
                                      R:R = 45/14 ≈ 3.21:1
```

**ผลลัพธ์:** ราคาสะท้อนจาก Demand Zone ตามคาด วิ่งขึ้นไปถึง TP ที่ Supply Zone 1.0868 ใน 2.5 ชั่วโมง

---

### เหตุผลที่ราคาต้องกลับมา Reaction ที่ Zone

**Mechanical Reason — Limit Order Activation:**

เมื่อสถาบันตั้ง Limit Buy ที่ 1.0834–1.0845 แต่ราคาวิ่งขึ้นไปก่อน (Departure) Orders เหล่านั้นยังคง Pending อยู่ในระบบ ครั้งที่ราคากลับมาถึง Zone ระบบ Matching Engine จะ Execute Orders เหล่านั้น สร้าง Buying Pressure ที่ผลักราคาขึ้น

**Psychological Reason — Memory Effect:**

นักเทรดสถาบันที่ "จำ" ว่าราคา 1.0840 เคยเป็นจุดที่ "ถูก" เมื่อครั้งก่อน จะตั้ง Buy Limit ซ้ำในบริเวณเดิม ทำให้เกิด Self-fulfilling Prophecy

**Statistical Reason — Mean Reversion at Extremes:**

ณ ขอบ Demand Zone ราคาอยู่ในสภาวะ "Oversold" ชั่วคราว (เมื่อเทียบกับ Context ของ Zone) ซึ่งทางสถิติมีแรงดูดให้ราคากลับมา

---

## 2. ทฤษฎีหลัก (Core Theory)

### 2.1 DBR Pattern — การตรวจจับ Demand Zone

**นิยาม DBR (Drop → Base → Rally):**

DBR คือ Pattern 5–7 แท่งที่บ่งบอกว่าสถาบัน "สะสม" Long Position ระหว่าง Base Phase หลังจาก Drop ทำให้ราคา "ถูก" ก่อนจะ Rally ขึ้นไป

```
Pattern Timeline (อ่านจากซ้าย = อดีต ไปขวา = ปัจจุบัน):

bar[i+3]──────bar[i+1]──bar[i]──bar[i-1]──────bar[i-3]
   ↑                ↑     ↑         ↑                ↑
   DROP เริ่ม    DROP จบ  BASE    RALLY เริ่ม    RALLY จบ

การตรวจสอบ (จากโค้ดจริง):
  Drop   : _IsDeparture(i+3, i+1, atr, false)
           → Open[i+3] to Close[i+1], move < -DepartureMult × ATR
  Base   : _IsBase(i, atr)
           → High[i] - Low[i] ≤ BaseRangeMult × ATR
  Rally  : _IsDeparture(i-1, i-3, atr, true)
           → Open[i-1] to Close[i-3], move > +DepartureMult × ATR
```

**Zone Boundaries:**
```
z.bottom = min(Low[i],  Low[i+1])   ← ขยาย Zone ลงรวม bar ก่อน Base
z.top    = max(High[i], High[i+1])  ← ขยาย Zone ขึ้นรวม bar ก่อน Base
```
การขยาย Zone ด้วย bar[i+1] ทำให้ Zone ครอบคลุมบริเวณที่ราคา Congested จริงก่อนการ Drop รวมถึง Wick ที่อาจเกิดขึ้นระหว่างการสะสม

**ทำไม Base Candle ต้องเล็ก (≤ 0.6×ATR)?**

Base Candle ที่เล็กแสดงถึง "ความลังเล" ของตลาด หรือสภาวะที่ราคา Consolidate ก่อนการตัดสินใจทิศทาง ถ้า Base Candle ใหญ่เกินไป หมายความว่ามีการซื้อขายสองทิศทางแบบสมดุล ซึ่งไม่ใช่ลักษณะของ "Institutional Accumulation" ที่แท้จริง

---

### 2.2 RBD Pattern — การตรวจจับ Supply Zone

**นิยาม RBD (Rally → Base → Drop):**

RBD คือ Mirror Image ของ DBR สถาบัน "กระจาย" Short Position ระหว่าง Base Phase หลังจาก Rally ทำให้ราคา "แพง" ก่อนจะ Drop ลงไป

```
Pattern Timeline:

bar[i+3]──────bar[i+1]──bar[i]──bar[i-1]──────bar[i-3]
   ↑                ↑     ↑         ↑                ↑
 RALLY เริ่ม   RALLY จบ  BASE    DROP เริ่ม     DROP จบ

การตรวจสอบ:
  Rally  : _IsDeparture(i+3, i+1, atr, true)
           → Open[i+3] to Close[i+1], move > +DepartureMult × ATR
  Base   : _IsBase(i, atr)
           → High[i] - Low[i] ≤ BaseRangeMult × ATR
  Drop   : _IsDeparture(i-1, i-3, atr, false)
           → Open[i-1] to Close[i-3], move < -DepartureMult × ATR
```

**ตัวอย่าง Supply Zone จาก Case Study:**
```
ณ bar[35] ที่แล้ว (35 ชั่วโมงที่แล้วบน H1):
  Rally: Open[38]=1.0850, Close[36]=1.0885 → +0.0035 > +0.00216 ✅
  Base : High[35]=1.0890, Low[35]=1.0883 → Range=0.0007 ≤ 0.00108 ✅
  Drop : Open[34]=1.0888, Close[32]=1.0855 → -0.0033 < -0.00216 ✅
  → RBD ยืนยัน → ZONE_SUPPLY ก่อตัว

  Zone bottom = min(1.0883, 1.0880) = 1.0880
  Zone top    = max(1.0890, 1.0892) = 1.0892
```

---

### 2.3 Zone Strength Formula — คะแนนคุณภาพโซน

ทุกครั้งที่ `UpdateTouches()` ถูกเรียก ระบบจะ Recalculate Strength ของโซนที่ถูก Touch:

```
_CalcStrength(zone, atr):

  width_ratio = min(1.0, (zone.top - zone.bottom) / (ATR × 2.0))
              ← โซนที่กว้าง 2×ATR ถือว่า width_ratio = 1.0 (กว้างเต็ม)

  freshness   = max(0.0, 1.0 - zone.touches × 0.25)
              touches=0: 1.000 (Fresh สมบูรณ์)
              touches=1: 0.750
              touches=2: 0.500
              touches=3: 0.250 → แต่โซนถูก Deactivate ก่อน (touches ≥ max_touches)

  age         = (TimeCurrent() - zone.created_time) / PeriodSeconds(timeframe)
              = อายุโซนในหน่วย "แท่ง"

  time_decay  = max(0.2, 1.0 - age × 0.002)
              age=0:    time_decay = 1.000  (ใหม่สุด)
              age=100:  time_decay = max(0.2, 0.800) = 0.800
              age=250:  time_decay = max(0.2, 0.500) = 0.500
              age=400+: time_decay = max(0.2, ≤0.200) = 0.200  (ขั้นต่ำ)

  strength    = min(1.0, width_ratio × freshness × time_decay)
```

**ตารางผลกระทบของอายุโซนต่อ Strength:**

| อายุ (H1 bars) | อายุจริง | time_decay | width_ratio=0.5 | freshness=1.0 | Strength |
|----------------|----------|-----------|----------------|--------------|----------|
| 0 (ใหม่มาก) | ทันที | 1.000 | 0.5 | 1.0 | **0.500** |
| 20 แท่ง | 20 ชั่วโมง | 0.960 | 0.5 | 1.0 | **0.480** |
| 100 แท่ง | ~4 วัน | 0.800 | 0.5 | 1.0 | **0.400** |
| 250 แท่ง | ~10 วัน | 0.500 | 0.5 | 1.0 | **0.250** |
| 400+ แท่ง | 16+ วัน | 0.200 (Min) | 0.5 | 1.0 | **0.100** |

**ทำไม time_decay มีค่าขั้นต่ำที่ 0.2 ไม่ใช่ 0?**

โซน SD ที่เก่ามากยังคงมีความสำคัญเชิงประวัติศาสตร์ (Historical Zone) ที่นักเทรดสถาบันจำได้และอาจใช้อ้างอิง การตั้งค่า Floor ที่ 0.2 ทำให้โซนเก่ายังคงมีคะแนน Strength อยู่บ้าง แทนที่จะเป็น 0 ซึ่งอาจทำให้โซนนั้นถูก Filter ออกอย่างไม่สมควร

---

### 2.4 Zone Invalidation — การยกเลิกโซน

ระบบมีสองเงื่อนไข Invalidate โซนใน `UpdateTouches()`:

**เงื่อนไขที่ 1 — Touch Count (Exhaustion):**
```
ทุก Tick ที่ price อยู่ใน [zone.bottom, zone.top]:
  zone.touches++
  zone.strength = _CalcStrength(zone, atr)  ← Recalculate ทันที

ถ้า zone.touches ≥ max_touches (3):
  zone.is_active = false  ← Zone หมดแรง ยกเลิก
```

**เงื่อนไขที่ 2 — Zone Broken (Price Penetration):**
```
DEMAND Zone: ถ้า price < zone.bottom - ATR
  → ราคาทะลุผ่านโซนลงไปมากกว่า 1 ATR
  → Zone ถูกทำลาย → is_active = false

SUPPLY Zone: ถ้า price > zone.top + ATR
  → ราคาทะลุผ่านโซนขึ้นไปมากกว่า 1 ATR
  → Zone ถูกทำลาย → is_active = false
```

**ทำไมต้องใช้ 1 ATR เป็น Buffer สำหรับ Broken Zone?**

การใช้ `price < zone.bottom` อย่างเดียวอาจทำให้ Zone ถูก Invalidate จาก Wick ชั่วคราว การเพิ่ม Buffer 1 ATR ทำให้ระบบยืนยันว่าราคาทะลุโซนจริงๆ ไม่ใช่แค่ Wick Rejection ปกติ

---

### 2.5 TP Targeting — Zone-to-Zone (_FindOppositeTP)

S05 มีคุณสมบัติพิเศษที่แตกต่างจาก S03 และ S04 คือ **TP จะอยู่ที่ขอบของ Zone ฝั่งตรงข้าม** แทนที่จะใช้ Fixed ATR Multiple:

```
_FindOppositeTP(is_long, entry_price, atr):

  สำหรับ Long Trade:
    opp_zone_type = ZONE_SUPPLY
    หา Supply Zone ที่ Active และ mid_price > entry_price
    (เลือกโซนที่มี Strength สูงสุด ถ้ามีหลายโซน)
    TP = supply_zone.bottom  ← ขอบล่างของ Supply Zone

    ถ้าไม่พบ Supply Zone:
    TP = entry_price + TP_ATRMult × ATR  ← Fallback ATR TP

  สำหรับ Short Trade:
    opp_zone_type = ZONE_DEMAND
    หา Demand Zone ที่ Active และ mid_price < entry_price
    TP = demand_zone.top  ← ขอบบนของ Demand Zone

    ถ้าไม่พบ Demand Zone:
    TP = entry_price - TP_ATRMult × ATR
```

**ทำไม Zone-to-Zone TP ถึงดีกว่า Fixed ATR?**

TP ที่ Fixed ATR (เช่น 2.5×ATR) ไม่ได้พิจารณาโครงสร้างตลาดจริงๆ แต่ Zone-to-Zone TP ตั้ง Target ไว้ที่ Supply Zone ที่แท้จริง ซึ่ง:
1. เป็นระดับที่ตลาดมีแนวโน้ม Reject ราคาสูง → TP ถูก Hit บ่อยขึ้น
2. TP ระยะสั้นกว่าหรือยาวกว่า Fixed ATR ขึ้นอยู่กับโครงสร้างตลาดจริง
3. สะท้อนตรรกะ "เทรด Zone ไป Zone" ที่สมบูรณ์แบบ

**การเลือกโซนสำหรับ TP (GetNearestFreshZone):**

ระบบเลือกโซนที่มี **Strength สูงสุด** (ไม่ใช่ใกล้ที่สุด) ที่อยู่เหนือหรือต่ำกว่าราคา Entry:
```
GetNearestFreshZone(zone_type, price, out):
  เปรียบเทียบ strength ของทุกโซนที่ Active และอยู่ถูกด้าน
  out = โซนที่มี strength สูงสุด
```

---

## 3. ตรรกะการให้คะแนนความเชื่อมั่น (Confidence Scoring)

ระบบใช้สูตรบวกถ่วงน้ำหนักสามองค์ประกอบ:

| Component | น้ำหนัก | ช่วงค่า | คำอธิบาย |
|-----------|--------|---------|----------|
| **Freshness** | 0.40 | 0.10–1.00 | วัดความ "ใหม่" ของโซน ยิ่ง Touches น้อย ยิ่งน่าเชื่อถือ เป็น Component ที่มีน้ำหนักสูงสุด |
| **Width Ratio** | 0.30 | 0.00–1.00 | วัดขนาดโซนเทียบกับ ATR×1.5 โซนกว้างกว่า = Order ที่ฝังอยู่มากกว่า = Reaction แรงกว่า |
| **Zone Strength** | 0.30 | ขึ้นอยู่กับ | ค่าจาก `_CalcStrength()` ที่รวม width, freshness และ time_decay ไว้แล้ว |

**สูตรการคำนวณจริง (จากซอร์สโค้ด `_CalcConfidence()`):**

```
freshness   = max(0.1, 1.0 - zone.touches × 0.25)
width       = zone.top - zone.bottom
width_ratio = min(1.0, width / (ATR × 1.5))

confidence  = min(1.0, freshness × 0.4
                      + width_ratio × 0.3
                      + zone.strength × 0.3)
```

**หมายเหตุ:** ค่า Minimum ของ freshness คือ 0.1 (ไม่ใช่ 0) เพื่อให้ confidence ไม่เป็น 0 อย่างสมบูรณ์แม้ zone จะถูก Touch ครบ 3 ครั้งแล้ว (แต่โซนถูก Deactivate ก่อนถึงจุดนั้น)

**ตารางสถานการณ์ Confidence:**

| สถานการณ์ | Freshness | Width Ratio | Strength | Confidence |
|-----------|-----------|-------------|----------|------------|
| Fresh, Zone แคบ | 1.000 (0T) | 0.20 | 0.15 | 0.40+0.06+0.045 = **0.505** |
| Fresh, Zone ปกติ | 1.000 (0T) | 0.40 | 0.29 | 0.40+0.12+0.087 = **0.607** |
| Touch 1, Zone ดี | 0.750 (1T) | 0.50 | 0.28 | 0.30+0.15+0.084 = **0.534** |
| Touch 2, Zone ดี | 0.500 (2T) | 0.50 | 0.20 | 0.20+0.15+0.060 = **0.410** |
| Fresh, Zone กว้างมาก | 1.000 (0T) | 1.00 | 0.60 | 0.40+0.30+0.180 = **0.880** |

**จาก Case Study:**
`freshness=1.0, width_ratio=0.407, strength=0.294`
`confidence = 0.400 + 0.122 + 0.088 = 0.610` ✅ ผ่าน MinConf (0.40)

**ทำไม Freshness มีน้ำหนักสูงสุด (0.40)?**

เพราะ "ความใหม่" ของโซนคือปัจจัยที่มีผลมากที่สุดต่อโอกาสสำเร็จ — Fresh Zone ที่ไม่เคย Tested มีโอกาส Reaction สูงกว่า Zone ที่ถูก Tested 2 ครั้งแล้วอย่างมีนัยสำคัญทางสถิติ

---

## 4. โครงสร้างสถาปัตยกรรมระบบ (System Architecture)

```
┌─────────────────────────────────────────────────────────────────────┐
│  S05 — FULL MQL5 | Zone Detection Pipeline                         │
├──────────────────────────────┬──────────────────────────────────────┤
│  Python Brain (Server)       │  MQL5 Trader — CSupplyDemand        │
│  หน้าที่: Regime & Config    │  หน้าที่: Zone Detection & Tracking │
├──────────────────────────────┼──────────────────────────────────────┤
│  • Regime Classification     │  • CZoneDetector.Scan()             │
│    (TRENDING/RANGING)        │    100 bars × DBR/RBD patterns      │
│  • Confidence Scoring        │  • Zone Strength (_CalcStrength)    │
│  • AI Council vote           │  • UpdateTouches() every tick       │
│  • Parameter optimization    │  • _EvaluateEntry() Long/Short      │
│  • CONFIG_PUSH delivery      │  • _FindOppositeTP() Zone-to-Zone   │
│                              │  • _CalcConfidence() Freshness      │
└──────────────────────────────┴──────────────────────────────────────┘
```

**ความสัมพันธ์ระหว่าง Scan (New Bar) และ UpdateTouches (Every Tick):**

```
New Bar Event:
  m_zone_det.Scan()        ← สร้างโซนใหม่ทั้งหมด (รีเซ็ตและสแกน 100 แท่ง)
  นับ m_demand_count และ m_supply_count สำหรับ Diagnostics

Every Tick:
  m_zone_det.UpdateTouches(price, atr)  ← ติดตามว่าราคาเข้าโซนไหน
  _EvaluateEntry(price)                 ← ตรวจสอบ Entry
```

**ทำไม Scan ทุก New Bar ไม่ใช่ทุก Tick?**

DBR/RBD Pattern ตรวจสอบข้อมูล 7 แท่งย้อนหลัง (i-3 ถึง i+3) ซึ่งไม่เปลี่ยนแปลงระหว่างแท่ง Pattern ใหม่จะเกิดขึ้นได้เฉพาะเมื่อมีแท่งใหม่ปรากฏ การ Scan ทุก Tick จึงสิ้นเปลือง CPU โดยไม่จำเป็น

---

## 5. โครงสร้างการไหลของข้อมูล (Full System Dataflow)

```
A: FeederEA (MQL5 Program)
   ├── รวบรวม OHLCV Data ทุกแท่ง
   ├── Pack ด้วย MessagePack Binary Protocol
   └── ส่งออก ZMQ PUB → Port 7777
                ↓
B: Python Brain — core/ingestion.py
   ├── รับข้อมูลจาก Port 7777
   ├── Unpack → InfluxDB
   └── ส่งต่อ OHLCV ให้ Regime Classifier
                ↓
C: Python Brain — core/strategy/analysis.py
   ├── วิเคราะห์ Regime: TRENDING / RANGING / VOLATILE / SQUEEZE
   ├── คำนวณ Regime Score สำหรับ S05:
   │   TRENDING  → bonus × 1.3  (Trend + Zone = strong combination)
   │   RANGING   → bonus × 1.2  (Zone edges = natural turn points)
   │   VOLATILE  → bonus × 0.2  (Zones break too fast — ไม่อนุมัติ)
   └── ส่งผล Regime ให้ Policy Engine
                ↓
D: Python Brain — core/strategy/policy.py
   ├── AI Council: ถ่วงน้ำหนักด้วย hist_perf × regime_bonus
   ├── หาก weighted_conf ≥ 0.50 → อนุมัติ S05
   ├── Parameter Optimization:
   │   TRENDING:  เพิ่ม Lookback (100→150) ค้นหา Zone ไกลขึ้น
   │               เพิ่ม TP_ATRMult (2.5→3.5) TP ไกลขึ้นตามทิศ Trend
   │   RANGING:   ลด Lookback (100→60) เน้น Zone ล่าสุด
   │               ลด MaxTouches (3→2) เพิ่มความเข้มงวด
   └── สร้าง CONFIG_PUSH (type=10)
                ↓
E: ZMQ PUSH → Port 7778
   CONFIG_PUSH Array:
   [10, timestamp, symbol, "S05", entry, lot, max_orders,
    tp, sl, confidence, risk_mult]
   + SDynamicParams: SD_LOOKBACK, SD_MAX_TOUCHES, SD_BASE_RANGE_MULT, ...
                ↓
F: MQL5 Trader — CSupplyDemand::SetDynamicParams()
   ├── _ApplyDynamicParams(params) → อัพเดทพารามิเตอร์ทั้งหมด
   ├── _SetupDetector() → m_zone_det.Setup(...) Reconfigure Zone Detector
   └── m_config.confidence > 0.01 → ServerOnly Guard ผ่าน
                ↓
G: CSupplyDemand::Analyze() — ทุก Tick
   ├── ServerOnly Guard: if(m_config.confidence < 0.01) return
   ├── _GetATR() → m_last_atr (bar[1] ค่า ATR)
   ├── New Bar Detection (s_last_bar vs iTime):
   │   ├── m_zone_det.Scan()     ← สแกน 100 แท่ง หา DBR/RBD
   │   ├── นับ m_demand_count / m_supply_count
   │   └── Diagnostics update
   ├── m_zone_det.UpdateTouches(price, atr) ← ทุก Tick
   └── _EvaluateEntry(price)
       ├── GetNearestFreshZone(ZONE_DEMAND, price, dz)
       ├── GetNearestFreshZone(ZONE_SUPPLY, price, sz)
       ├── Long Check: price ∈ [dz.bottom, dz.top] + strength ≥ 0.25 + conf ≥ 0.40
       └── Short Check: price ∈ [sz.bottom, sz.top] + strength ≥ 0.25 + conf ≥ 0.40
                ↓
H: Order Manager — เปิด Position
   ├── Long:  SL = dz.bottom - SL_ATRBuffer × ATR
   │          TP = _FindOppositeTP → Supply Zone bottom หรือ Fallback ATR
   ├── Short: SL = sz.top + SL_ATRBuffer × ATR
   │          TP = _FindOppositeTP → Demand Zone top หรือ Fallback ATR
   └── Magic Number = 1005 (MAGIC_S05_SUPPLY_DEM)
                ↓
I: ZMQ PUSH → Port 7779
   TRADE_REPORT → Python Brain
   → อัพเดท hist_perf[S05] สำหรับ AI Council รอบถัดไป
```

---

## 6. ตารางอ้างอิงพารามิเตอร์ (Parameter Reference)

| Parameter | Default | Range | คำอธิบายรายละเอียดเชิงลึก |
|-----------|---------|-------|---------------------------|
| `SD_LookbackBars` | 100 | 50–300 | จำนวนแท่งย้อนหลังสำหรับ Scan Pattern ค่าต่ำ (50) = เน้น Zone ใหม่ Reaction เร็ว / ค่าสูง (300) = รวม Zone เก่าที่ยังใช้งานได้ (Historical Zones) แต่ Scan ช้าลง |
| `SD_MaxTouches` | 3 | 1–5 | จำนวนครั้งสูงสุดที่ Zone รับ Touch ได้ก่อน Invalidate ค่า 1 = เข้าได้ครั้งเดียว (High Win Rate, น้อย Signal) / ค่า 5 = Zone ทนทาน (Signal มาก, Win Rate ลด) |
| `SD_BaseRangeMult` | 0.6 | 0.3–1.0 | เพดานขนาดของ Base Candle เป็นทวีคูณ ATR ค่าต่ำ (0.3) = Base ต้องแคบมาก (Zone คุณภาพสูง, น้อย) / ค่าสูง (1.0) = ยอมรับ Base กว้างขึ้น (Zone มาก, คุณภาพลด) |
| `SD_DepartureMult` | 1.2 | 0.8–3.0 | ขนาดขั้นต่ำของ Departure Move เป็นทวีคูณ ATR ค่าต่ำ (0.8) = ยอมรับ Departure เล็ก (Zone มาก, False Positive สูง) / ค่าสูง (3.0) = เฉพาะ Explosive Move เท่านั้น |
| `SD_SL_ATRBuffer` | 0.5 | 0.2–1.5 | ระยะ Buffer ของ SL จากขอบโซน ค่าต่ำ (0.2) = SL ชิดโซน (แน่น, เสี่ยง Stop Hunt) / ค่าสูง (1.5) = SL ห่างโซน (ปลอดภัยกว่าแต่ R:R แย่ลง) |
| `SD_TP_ATRMult` | 2.5 | 1.5–5.0 | ตัวคูณ ATR สำหรับ Fallback TP (ใช้เมื่อไม่พบ Opposite Zone) ค่าสูงขึ้นเหมาะกับ TRENDING ที่ราคาวิ่งต่อได้ไกล |
| `SD_MinZoneStrength` | 0.25 | 0.10–0.60 | Strength ขั้นต่ำที่โซนต้องมีก่อนพิจารณา Entry กรองโซนเก่า (High time_decay) หรือโซนที่ถูก Touch บ่อยออกก่อน |
| `SD_MinConfidence` | 0.40 | 0.25–0.70 | Confidence ขั้นต่ำสำหรับสร้างสัญญาณ ค่าต่ำ (0.25) = Signal บ่อย แต่คุณภาพต่ำ / ค่าสูง (0.70) = เฉพาะ Fresh Zone ขนาดกว้างเท่านั้น |

**CONFIG_PUSH Parameter Keys:**

| CONFIG_PUSH Key | MQL5 Parameter | ประเภท | หมายเหตุ |
|-----------------|---------------|---------|---------|
| `SD_LOOKBACK` | `SD_LookbackBars` | int | cast จาก double |
| `SD_MAX_TOUCHES` | `SD_MaxTouches` | int | cast จาก double |
| `SD_BASE_RANGE_MULT` | `SD_BaseRangeMult` | double | |
| `SD_DEPARTURE_MULT` | `SD_DepartureMult` | double | |
| `SD_SL_ATR_BUFFER` | `SD_SL_ATRBuffer` | double | |
| `SD_TP_ATR_MULT` | `SD_TP_ATRMult` | double | |
| `SD_MIN_ZONE_STRENGTH` | `SD_MinZoneStrength` | double | |
| `SD_MIN_CONFIDENCE` | `SD_MinConfidence` | double | |

หลังรับ CONFIG_PUSH ระบบเรียก `_SetupDetector()` ทันที → `m_zone_det.Setup(...)` → Zone Detector ถูก Reconfigure และรีเซ็ต (m_count = 0) Zone จะถูก Rebuild ในรอบ New Bar ถัดไป

---

## 7. โหมดเดี่ยว vs โหมดเซิร์ฟเวอร์ (Standalone vs Server Mode)

### 7.1 โหมดเดี่ยว — ไม่รองรับ

**เหตุผลที่ 1 — ServerOnly Guard:**
```mql5
if(m_config.confidence < 0.01) return;   // ใน Analyze()
```
ไม่มี CONFIG_PUSH = ไม่มีสัญญาณ ไม่ว่า Zone จะดีแค่ไหน

**เหตุผลที่ 2 — False Zone ใน VOLATILE:**

DBR/RBD Pattern สามารถเกิดขึ้นได้ในทุก Regime รวมถึงในช่วง News Release ที่ Departure เกิดจาก Spike ไม่ใช่ Institutional Accumulation โดยไม่มี Server กรอง Regime โซนเหล่านี้จะถูกนำมา Trade โดยไม่ควร

**เหตุผลที่ 3 — Zone ต้องการ Dynamic Parameter Tuning:**

ค่า `SD_BaseRangeMult` และ `SD_DepartureMult` ที่เหมาะสมแตกต่างกันมากระหว่าง TRENDING และ RANGING ตลาด Python Brain ปรับค่าเหล่านี้ Real-time ตาม Regime

### 7.2 โหมดเซิร์ฟเวอร์ — การทำงานเต็มรูปแบบ

```
Python Brain
   ├── Regime: TRENDING หรือ RANGING
   ├── S05 Scoring: hist_perf × regime_bonus
   │   TRENDING → 1.3 | RANGING → 1.2 | VOLATILE → 0.2
   │
   ├── AI Council: weighted_conf ≥ 0.50 → อนุมัติ S05
   │
   ├── Optimization:
   │   TRENDING  → Lookback=150, TP_ATRMult=3.5, MaxTouches=3
   │   RANGING   → Lookback=60,  TP_ATRMult=2.0, MaxTouches=2
   │
   └── CONFIG_PUSH → Port 7778 → CSupplyDemand::SetDynamicParams()
```

---

## 8. ลำดับขั้นตอนการทำงาน (Step-by-Step Operational Flow)

**ขั้นที่ 1 — Initialization:**
- `Init()`: สร้าง `iATR(14)` handle
- `_SetupDetector()`: Setup Zone Detector เริ่มต้น
- พิมพ์: `[S05] Init OK | EURUSD PERIOD_H1`

**ขั้นที่ 2 — รับ CONFIG_PUSH:**
- `SetDynamicParams()` → `_ApplyDynamicParams()` → `_SetupDetector()`
- m_zone_det รีเซ็ต (m_count=0) พร้อม Parameters ใหม่
- m_config.confidence > 0.01 → ServerOnly Guard ปลดล็อก

**ขั้นที่ 3 — New Bar: Zone Scan:**
```
m_zone_det.Scan():
  ATR = _ATR(14)  ← คำนวณ ATR จาก 14 แท่งย้อนหลัง

  วนซ้ำจาก bar[lookback-6] ถึง bar[4]:
    ตรวจสอบ DBR Pattern → ถ้าผ่าน: เพิ่ม ZONE_DEMAND
    ตรวจสอบ RBD Pattern → ถ้าผ่าน: เพิ่ ZONE_SUPPLY
    (สูงสุด MAX_SD_ZONES = 16 โซน)

  นับ m_demand_count / m_supply_count
```

**ขั้นที่ 4 — ทุก Tick: UpdateTouches:**
```
สำหรับทุกโซนที่ Active:
  ถ้า price ∈ [zone.bottom, zone.top]:
    zone.touches++
    zone.strength = _CalcStrength(zone, atr)
    ถ้า touches ≥ max_touches: zone.is_active = false

  ถ้า (DEMAND + price < bottom - ATR) หรือ (SUPPLY + price > top + ATR):
    zone.is_active = false  ← Zone ถูกทำลาย
```

**ขั้นที่ 5 — ทุก Tick: EvaluateEntry:**
```
_EvaluateEntry(price):
  1. GetNearestFreshZone(ZONE_DEMAND, price, dz)
     → หา Demand Zone ที่ mid_price < price และ strength สูงสุด

  2. ถ้า found_d AND dz.strength ≥ MinZoneStrength:
     ถ้า price ∈ [dz.bottom, dz.top]:
       conf = _CalcConfidence(dz, atr)
       ถ้า conf ≥ MinConfidence:
         SIGNAL_BUY
         SL = dz.bottom - SL_ATRBuffer × ATR
         TP = _FindOppositeTP(true, price, atr)
         return

  3. ทำซ้ำสำหรับ ZONE_SUPPLY → SIGNAL_SELL
```

**ขั้นที่ 6 — TRADE_REPORT:**
- ส่งผล Trade กลับ Port 7779
- Brain อัพเดท hist_perf[S05]

---

## 9. ลักษณะประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|------|-----------|
| **สภาวะตลาดที่ดีที่สุด** | TRENDING ที่มี Pullback ชัดเจน หรือ RANGING ที่ Zones อยู่บนขอบบน-ล่างของ Range |
| **สภาวะตลาดที่แย่ที่สุด** | VOLATILE หลังข่าวใหญ่ — Departure เกิดจาก Spike ไม่ใช่ Institutional Order |
| **ความถี่สัญญาณ** | ต่ำ: 2–4 สัญญาณต่อวัน (เฉพาะ Fresh Zone เท่านั้น) |
| **Win Rate เป้าหมาย** | 60–70% (Fresh Zone Touch 0–1 มี Reaction Rate สูง) |
| **R:R Ratio** | 2:1 ถึง 4:1 ขึ้นอยู่กับระยะ Zone-to-Zone หรือ TP_ATRMult |
| **Zone Buffer** | สูงสุด 16 โซน (MAX_SD_ZONES) ทั้ง Demand และ Supply รวมกัน |
| **ATR Period** | 14 แท่ง (คำนวณใน ZoneDetector._ATR() และใน CSupplyDemand._GetATR()) |
| **Magic Number** | 1005 (MAGIC_S05_SUPPLY_DEM) |
| **Unique Feature** | Zone Freshness System + Zone-to-Zone TP Targeting |

**R:R จาก Case Study:**
- SL Distance = entry(1.0839) - SL(1.0825) = **14 pips**
- TP Distance = TP(1.0868) - entry(1.0839) = **29 pips**
- R:R = 29/14 ≈ **2.07:1** (Zone-to-Zone)
- Fallback TP = 1.0884 → R:R = 45/14 ≈ **3.21:1** (ATR Mult)

---

## 10. ไฟล์อ้างอิง (Files Reference)

| ไฟล์ | บทบาท |
|------|--------|
| `Include/Logic/Strategies/S05_SupplyDemand.mqh` | คลาสหลัก `CSupplyDemand` — Entry logic, Confidence, SL/TP |
| `Include/Logic/Strategies/SuppyDemand/ZoneDetector.mqh` | `CZoneDetector` — DBR/RBD detection, Strength, Touches tracking |
| `02_Brain/strategies/s05_supply_demand_analyzer.py` | Python Regime Scoring สำหรับ S05 |
| `Include/Logic/StrategyConstants.mqh` | ค่าคงที่: `S05_SUPPLY_DEMAND` enum, `MAGIC_S05_SUPPLY_DEM = 1005` |
| `Include/Network/Protocol/Definitions.mqh` | `SDynamicParams`, CONFIG_PUSH structure |

**หมายเหตุ:** ชื่อโฟลเดอร์ในโค้ดจริงคือ `SuppyDemand` (Typo ขาด 'l') — ไม่ใช่ `SupplyDemand` ควรระวังเมื่อ Include file ด้วยตนเอง

---

## 11. Quick Diagnostics

### ตรวจสอบว่า S05 Active และมีโซน
```
dashboard.py → Active Strategies → "S05" ปรากฏพร้อม D:X S:X (D=Demand Zones, S=Supply Zones)
```

### อ่าน Diagnostic String จาก GetDiagnostics()
```
[S05] ATR:0.0018 D:3 S:2 Str:0.29 Sig:BUY Conf:0.61
           ↑ATR      ↑D  ↑S ↑strength ↑สัญญาณ ↑conf

D = จำนวน Active Demand Zones
S = จำนวน Active Supply Zones
```

### Log ที่ควรเห็นใน MT5 Experts Tab
```
[S05] Init OK | EURUSD PERIOD_H1
[S05] SIGNAL_BUY  price=1.08390 Zone=[1.08340,1.08450] str=0.29 conf=0.61
[S05] SIGNAL_SELL price=1.08850 Zone=[1.08800,1.08920] str=0.31 conf=0.55
```

### กรณี S05 ไม่สร้างสัญญาณ
```
สาเหตุที่ 1: ไม่ได้รับ CONFIG_PUSH → m_config.confidence < 0.01
             แก้ไข: ตรวจสอบ Python Brain เชื่อมต่ออยู่ที่ Port 7778

สาเหตุที่ 2: Regime = VOLATILE → Brain ไม่ส่ง CONFIG_PUSH ให้ S05
             แก้ไข: รอสภาวะตลาดเปลี่ยนเป็น RANGING หรือ TRENDING

สาเหตุที่ 3: ไม่มีโซนที่ผ่านเกณฑ์ (D:0 S:0)
             แก้ไข: ลด SD_BaseRangeMult (0.6→0.8) หรือ ลด SD_DepartureMult (1.2→0.9)
             → ยอมรับ Pattern ที่หลวมขึ้น

สาเหตุที่ 4: มีโซนแต่ strength ต่ำกว่า MinZoneStrength
             แก้ไข: ลด SD_MinZoneStrength (0.25→0.15)
             หรือ ลด SD_LookbackBars เพื่อเน้น Zone ใหม่

สาเหตุที่ 5: ราคาไม่เข้าโซนเลย (ราคาไม่ทดสอบ Zone)
             แก้ไข: ปกติตามธรรมชาติของ TRENDING — รอ Pullback
```

### ตรวจสอบ Zone Health แบบ Manual
```mql5
// เรียกใน Debug เพื่อตรวจโซนทั้งหมด:
for(int i = 0; i < m_zone_det.Count(); i++) {
    SSDZone z = m_zone_det.GetZone(i);
    PrintFormat("Zone[%d] %s [%.5f-%.5f] T=%d Str=%.2f Active=%s",
        i, EnumToString(z.zone_type),
        z.bottom, z.top, z.touches, z.strength,
        z.is_active ? "YES" : "NO");
}
```

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critiques & Optimizations)

**ข้อจำกัดที่ 1 — Scan รีเซ็ตทั้งหมดทุกแท่ง:**

`Scan()` จะ `m_count = 0` และสร้างโซนใหม่ทั้งหมดทุกครั้ง หมายความว่า Touch Count ที่สะสมไว้ **หายไปหลังจาก New Bar** เพราะ `m_zone_det.Scan()` สร้าง Zone Objects ใหม่ที่มี `touches = 0` ทุกครั้ง ถ้า Scan เกิดขึ้นขณะที่โซนเดิมถูก Touch 1 ครั้ง ค่า Touch จะถูก Reset เป็น 0 ในแท่งถัดไป วิธีบรรเทา: พัฒนา Zone Persistence ที่ Match โซนใหม่กับโซนเก่าโดยตรวจสอบ Price Range ที่ซ้อนทับกัน และสืบทอด Touches จากโซนเดิม

**ข้อจำกัดที่ 2 — GetNearestFreshZone เลือก Strength สูงสุด ไม่ใช่ ใกล้ที่สุด:**

สำหรับ TP Targeting บางครั้ง Supply Zone ที่ใกล้ที่สุดกว่า (แต่ Strength ต่ำกว่า) อาจเป็น Target ที่ "ถูก Hit" ได้ง่ายกว่า แต่ระบบเลือก Zone ที่ Strength สูงสุดแทน วิธีบรรเทา: สำหรับ TP ให้พิจารณา "ใกล้ที่สุด" แทน "Strength สูงสุด" โดยเฉพาะในตลาด RANGING

**ข้อจำกัดที่ 3 — Pattern Window คงที่ (i+3 ถึง i-3):**

ระบบตรวจสอบ Drop/Rally ในช่วงคงที่ 3 แท่งก่อนและหลัง Base ซึ่งอาจ Miss Pattern ที่ใช้แท่งมากกว่า (เช่น Rally 5 แท่ง) วิธีบรรเทา: ขยาย Pattern Window เป็น Parameter ที่ปรับได้ (เช่น `SD_DepartureWindow = 3`)

**ข้อจำกัดที่ 4 — ATR ใน ZoneDetector คำนวณแยกจาก CSupplyDemand:**

ทั้ง `CZoneDetector._ATR()` และ `CSupplyDemand._GetATR()` คำนวณ ATR แยกกัน อาจได้ค่าต่างกันเล็กน้อยเนื่องจาก ZoneDetector ใช้ Manual Loop ส่วน CSupplyDemand ใช้ `iATR` Handle วิธีบรรเทา: ส่งค่า ATR จาก CSupplyDemand เข้าไปใน ZoneDetector โดยตรงเพื่อให้ใช้ค่าเดียวกัน

**แนวทางการ Tune พารามิเตอร์ตามสภาวะตลาด:**

| สภาวะ | SD_LookbackBars | SD_BaseRangeMult | SD_DepartureMult | SD_MaxTouches | SD_TP_ATRMult |
|--------|-----------------|-----------------|-----------------|--------------|--------------|
| Strong TRENDING | 150 | 0.6 | 1.5 | 3 | 3.5 |
| RANGING (Tight) | 60 | 0.7 | 1.0 | 2 | 2.0 |
| RANGING (Wide) | 80 | 0.6 | 1.2 | 3 | 2.5 |
| Default | 100 | 0.6 | 1.2 | 3 | 2.5 |

---

*S05 Supply & Demand Manual — FlashEASuite V2 | Phase P9-5 | Jimmi Deep-Dive Edition | 2026-02-27*
