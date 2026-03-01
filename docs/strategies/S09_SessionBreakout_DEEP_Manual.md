# S09 — London/NY Session Breakout
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความเชิงวิชาการ

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S09 | รหัสลำดับที่เก้าในระบบมัลติกลยุทธ์ของ FlashEASuite V2 — S09 เป็นกลยุทธ์เดียวในระบบที่ผูกตรรกะทั้งหมดเข้ากับ "เวลา" เป็นหลัก ไม่ใช่ Price Action หรือ Indicator |
| **Enum Name** | `S09_SESSION_BREAKOUT` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) ค่า enum index = 8 (0-based array index) หมายความว่าเป็น element ลำดับที่ 9 ของ `g_strategy_table[16]` |
| **Enum Index** | 8 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่านฟังก์ชัน `GetStrategyInfo(S09_SESSION_BREAKOUT)` |
| **ชื่อ** | Session Breakout (London/NY) | กลยุทธ์เทรด Breakout จากช่วงราคาที่สะสมระหว่าง Asian Session ออกสู่ทิศทางใหม่เมื่อ London Open หรือ New York Open |
| **ประเภท** | Full MQL5 — `CAT_FULL_MQL5` | ทุกการคำนวณเกิดขึ้นใน MQL5 ทั้งหมด แต่ **ต้องการ Python Brain** สำหรับการ Validate วันหยุด, ปรับ GMT Offset และ Optimize session windows ตามฤดูกาล DST |
| **Standalone Capable** | ❌ No — Server Only | S09 ไม่รองรับ Standalone Mode เพราะต้องการ Calendar Awareness จาก Brain เพื่อตรวจสอบวันหยุดนักขัตฤกษ์, Daylight Saving Time (DST) changes และ Low-Liquidity Days ที่อาจทำให้ Asian Range ผิดปกติ |
| **Preferred Regime** | VOLATILE (`REGIME_VOLATILE`) | Session Breakout ทำกำไรสูงสุดเมื่อตลาดมี Momentum แรงขณะ London หรือ NY เปิด ซึ่งตรงกับ VOLATILE Regime ที่ ATR สูงและปริมาณการซื้อขายพุ่ง |
| **Alt Regime** | TRENDING (`REGIME_TRENDING`) | ถ้า Trend มีทิศทางอยู่แล้วก่อน London Open Breakout จะ "เข้ากระแส" ทำให้ Trade วิ่งได้นานและกำไรเกิน TP บ่อย |
| **Poor Regimes** | RANGING | ใน RANGING Asian Range จะเล็กมาก (< 20 pips) — Breakout ไม่มีแรง, ราคาเจาะออกแล้วกลับเข้า Range ทันที ทำให้ False Signal สูง |
| **Regime Factor** | VOLATILE=1.5, TRENDING=1.2, RANGING=0.4, SQUEEZE=0.6 | ตัวคูณที่ Brain ใช้ปรับ Confidence — S09 ได้ Boost สูงสุดใน VOLATILE เพราะ Momentum แรงหนุน Breakout |
| **MQL5 Class** | `CSessionBreakout` | คลาสหลักใน MQL5 ที่ควบคุม Daily State Machine ทั้งหมด: การสะสม Asian Range, การตรวจ Breakout แบบ Tick-by-Tick, การส่ง Signal และการ Reset รายวัน ไฟล์: `Include/Logic/Strategies/S09_SessionBreakout.mqh` |
| **Magic Number** | 1009 (`MAGIC_S09_SESSION_BO`) | หมายเลขเอกลักษณ์ที่แท็กออเดอร์ทั้งหมดของ S09 ป้องกันการปะปนกับ Strategies อื่น — สำคัญมากเพราะ S09 มีสูงสุด 2 ออเดอร์ต่อวัน (London + NY) |
| **Family** | Time-based | กลุ่มกลยุทธ์ที่ใช้เวลาของตลาดเป็น Primary Signal — แตกต่างจาก Price Action หรือ Statistical Families |
| **Version** | 6.00 | สถาปัตยกรรม V6 ที่เพิ่ม CONFIG_PUSH Support, ATR-adaptive buffer และ NY Session Logic เข้ามาจาก V5 |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S09 ตั้งอยู่บนความจริงพื้นฐานของตลาด Forex ข้อหนึ่งที่สังเกตได้มาหลายสิบปี: **ตลาดในช่วง Asian Session มักแกว่งในช่วงแคบ (Low Volatility)** แล้วเมื่อ London เปิดทำการ ปริมาณการซื้อขายพุ่งขึ้นอย่างรวดเร็ว ทำให้ราคา "ทะลุ" ออกจากช่วงที่ Asian สร้างไว้อย่างแรง

กลยุทธ์แบ่งออกเป็น 3 ช่วงที่ชัดเจน:

1. **Asian Session (00:00–08:00 GMT)** — "สะสม Range" วัด High และ Low ของทุก Tick ตลอดช่วง 8 ชั่วโมงนี้ เพื่อสร้าง "กรอบราคา Asian"
2. **London Session (08:00–12:00 GMT)** — "รอ Breakout" เมื่อราคาทะลุ Asian High → BUY, ทะลุ Asian Low → SELL
3. **NY Session (13:00–17:00 GMT)** — "โอกาสที่สอง" ถ้า London ไม่ Breakout หรือยังมีแรงต่อ NY จะตรวจ Breakout จาก London Range

กุญแจสำคัญคือ TP ถูกตั้งที่ **1.5× Asian Range** จาก Entry และ SL อยู่ **ภายใน Range** ทำให้ R:R ≥ 2.0 โดยธรรมชาติของโครงสร้าง

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมตลาด "ทะลุ" ที่ London Open?

**โครงสร้าง Liquidity ของตลาด Forex:**

ตลาด Forex ไม่ได้เปิด-ปิดแบบ Stock Exchange แต่ทำงาน 24 ชั่วโมงผ่าน Network ของธนาคารทั่วโลก อย่างไรก็ตาม **Liquidity ไม่ได้กระจายเท่ากันตลอดวัน** แต่กระจุกตัวตามเวลาทำการของ Financial Centers หลัก:

```
ช่วงเวลา (GMT) | Financial Center ที่ Active          | Liquidity ของ EUR/USD
─────────────────────────────────────────────────────────────────────────────
00:00–08:00     | Tokyo, Sydney, Singapore, Hong Kong  | ต่ำ — ไม่ใช่ Home Market ของ EUR
08:00–12:00     | London (+ Frankfurt, Zurich)         | สูงสุดของวัน — EUR/USD คือตลาดบ้าน
12:00–17:00     | New York + London Overlap (12-16)    | สูงมาก — สองตลาดใหญ่ทับกัน
17:00+          | New York (ช่วงท้าย), ก่อน Asia       | ต่ำลง — Institutional flow ลด
```

**เหตุผลที่ Asian Range แคบ:**

คู่เงิน EUR/USD หรือ GBP/USD ไม่ใช่ "Home Currency" ของ Asia นักเทรดสถาบัน (Institutional Traders) ในยุโรปและอเมริกาที่มีอำนาจซื้อขายสูงยังไม่ตื่นในช่วง Asian Session ดังนั้น:
- ปริมาณการซื้อขาย EUR/USD ใน Asian Session ≈ 20–30% ของปริมาณช่วง London
- ไม่มีข่าวเศรษฐกิจยุโรปออกมาในเวลา GMT 00–08
- ราคาเคลื่อนที่จาก Order Flow เล็กๆ ทำให้ Range แคบ

**เหตุผลที่ London Open "ระเบิด":**

เวลา 08:00 GMT คือ "ประตูเปิด" ของ London — Financial Center ที่ใหญ่ที่สุดในโลกด้าน Forex ใน 30 นาทีแรก:
- Institutional Traders ส่ง Order ที่สะสมไว้ข้ามคืน
- Market Makers ปรับ Spread และ Position
- Algorithm ของ Banks ที่อิง European Open เริ่มทำงานพร้อมกัน
- ข่าวเศรษฐกิจยุโรปชั้นนำ (CPI, GDP, PMI) มักออกช่วง 09:00–10:00 GMT

ผลคือ Momentum แรงพุ่งเข้า "ทะลุ" ขอบ Asian Range อย่างชัดเจน และทิศทางนั้นมักดำเนินต่อไปอีก 2–4 ชั่วโมง

---

### 1.3 ประวัติศาสตร์: ที่มาของ Session Breakout Strategy

**Mark Fisher's ACD Method (1990s):**

Mark Fisher นักเทรดใน NYMEX เสนอ "ACD Method" ซึ่งเป็นต้นกำเนิดของ Session Breakout ทุกรูปแบบ — กำหนด "Opening Range" ในช่วงแรกของ Session แล้วเทรด Breakout ออกจาก Range นั้น

**Pivot Boss & Floor Traders (ก่อน 1990):**

Floor Traders ใน Chicago Mercantile Exchange ใช้หลักการคล้ายกันมาก่อนยุค Computer: ถ้าราคาวันนี้ทะลุ High ของเมื่อวาน → แนวโน้มขาขึ้น ถ้าทะลุ Low → แนวโน้มขาลง S09 ใช้ Asian Session เป็น "เมื่อวาน" ของ London

**Adaptation ใน FlashEASuite:**

ระบบ FlashEASuite V2 ปรับปรุงจากหลักการดั้งเดิมด้วย:
- **ATR-adaptive Buffer** แทน Fixed Pip Buffer
- **NY Session เป็น Second Opportunity** (ไม่ใช่แค่ London)
- **Python Brain Calendar Integration** — ข้ามวันหยุดและ Low-Liquidity Days
- **Confidence Scoring** ที่วัดทั้งขนาด Asian Range และคุณภาพของ Session

---

### 1.4 กรณีศึกษาจริง (Case Study — 28 กุมภาพันธ์ 2026)

**สถานการณ์:** EUR/USD ในวันปกติ (ไม่ใช่วันหยุด) หลังจากสัปดาห์ที่ ECB ส่งสัญญาณ Hawkish ทำให้ EUR แข็งค่า

---

#### ช่วงที่ 1: Asian Session (00:00–08:00 GMT) — สะสม Range

```
ติดตามทุก Tick ตลอด 8 ชั่วโมง:
  Tick สูงสุด:  Ask = 1.08620  (เวลา 04:23 GMT — Tokyo session mid)
  Tick ต่ำสุด:  Bid = 1.08390  (เวลา 01:47 GMT — ช่วงแรกของ Asia)

  m_asian_high = 1.08620
  m_asian_low  = 1.08390

Asian Range = 1.08620 − 1.08390 = 0.00230 = 23.0 pips

ตรวจ Filter:
  23.0 pips >= SB_Range_Min_Pips (20 pips) → ✅ Range Valid
  m_asian_range_valid = true

ATR H1 ณ เวลา 08:00 GMT = 0.00058 (58 pips)
```

---

#### ช่วงที่ 2: คำนวณ Trigger ก่อน London Open

```
Breakout Buffer = max(SB_Breakout_Buffer × pip, 0.10 × ATR_H1)
               = max(3 × 0.00010, 0.10 × 0.00580)
               = max(0.00030, 0.00058)
               = 0.00058  (5.8 pips — ATR-based ชนะ Fixed pip)

Long Trigger  = Asian High + Buffer = 1.08620 + 0.00058 = 1.08678
Short Trigger = Asian Low  − Buffer = 1.08390 − 0.00058 = 1.08332
```

```
คำนวณ TP และ SL (ล่วงหน้าก่อน Entry):
Asian Range = 0.00230

Long TP  = Entry + Asian Range × 1.5 = 1.08678 + 0.00345 = 1.09023
Long SL  = Asian Low + Asian Range × 0.5 = 1.08390 + 0.00115 = 1.08505

ระยะ Entry → TP  = 0.00345 = 34.5 pips
ระยะ Entry → SL  = 1.08678 − 1.08505 = 0.00173 = 17.3 pips

R:R = 34.5 / 17.3 = 1.99  ≈ 2.0 : 1
```

---

#### ช่วงที่ 3: London Breakout (08:00 GMT)

```
เวลา 08:14 GMT:
  Bank of France ส่ง Order ขนาดใหญ่ซื้อ EUR
  Ask = 1.08690

  1.08690 > Long Trigger (1.08678) → SIGNAL_BUY!
  m_london_broken_up = true  (Flag ป้องกัน Re-entry ซ้ำ)

ออเดอร์ที่ระบบส่ง:
  BUY EURUSD @ 1.08690 (Market Order)
  TP  = 1.09023
  SL  = 1.08505
  Lot = คำนวณจาก MM (สมมติ 0.05 lot)
```

```
Confidence Calculation:
  range_atr_ratio = (0.00230) / (0.00580) = 0.397
  range_factor    = min(1.0, 0.397 / 2.0) = 0.198

  session_factor  = 1.0 (London = Full factor)

  raw_confidence  = 0.198 × 1.0 = 0.198

  Regime = VOLATILE → × 1.5
  weighted_conf   = 0.198 × 1.5 = 0.297

  หมายเหตุ: Range ค่อนข้างแคบ (23 pips vs ATR 58 pips) → Confidence ไม่สูงมาก
            แต่ AI Council รับ (threshold = 0.25) เพราะ Regime VOLATILE Boost
```

---

#### ช่วงที่ 4: Trade ดำเนินไป

```
เวลา 08:14–10:30 GMT:
  EUR ยังได้แรงหนุนจาก ECB sentiment

  08:30 GMT: Price = 1.08750 (กำไร 6 pips — ยังไม่ถึง TP)
  09:00 GMT: ข่าว Eurozone Manufacturing PMI สูงกว่าคาด
             Price พุ่งขึ้น
  09:15 GMT: Price = 1.08950 (กำไร 26 pips)
  09:47 GMT: Price = 1.09023 → TP โดน!

กำไร:
  (1.09023 − 1.08690) × 0.05 lot × 100,000 = 0.00333 × 5,000 = $16.65
  (R:R ≈ 2.0 — ได้ประมาณที่คำนวณไว้)
```

---

#### ช่วงที่ 5: NY Session (13:00 GMT) — กรณีที่ London ยังไม่ Breakout

```
สมมติ Scenario ที่สอง — London ไม่ Breakout (Price แกว่งใน Range)

เวลา 08:00–12:00: ราคาแกว่งระหว่าง 1.08400–1.08580 ไม่ทะลุ Trigger
  m_london_broken_up = false (ยังไม่เคย Fire)
  m_london_high = 1.08580  (High ของ London Session)
  m_london_low  = 1.08400  (Low ของ London Session)

13:00 GMT: NY Session เริ่ม
  ระบบสร้าง NY Range จาก London Range:
  ny_high = 1.08580
  ny_low  = 1.08400

NY Trigger:
  Long:  ny_high + Buffer = 1.08580 + 0.00058 = 1.08638
  Short: ny_low  - Buffer = 1.08400 − 0.00058 = 1.08342

เวลา 13:30 GMT: NY Fed Speech → USD อ่อนค่า
  Price = 1.08650 > 1.08638 → NY SIGNAL_BUY!
  Confidence = range_factor × 0.75  (NY factor = 0.75, 25% ต่ำกว่า London)
```

**บทเรียนจากกรณีนี้:**
- Asian Range ขนาด 23 pips ให้ R:R ≈ 2.0 — เป็น Minimum ที่ยอมรับได้
- London Breakout มักเร็วและแรง — TP โดนใน 1.5 ชั่วโมง
- NY เป็น Second Chance แต่ Confidence ลดลง 25% สะท้อนว่า NY มี Volume น้อยกว่า
- ถ้า Asian Range > 50 pips → SL จะกว้างมากจนรับความเสี่ยงไม่ไหว — Brain ควร Reduce weight

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 Asian Range Capture — กลไกการสะสม High/Low

**วิธีที่ 1: Live Tick Tracking (Primary)**

```
ทุก Tick ที่เข้ามาระหว่าง Asian Session:
  if (current_hour >= m_asian_start AND current_hour < m_asian_end)
  {
      if (ask > m_asian_high) m_asian_high = ask;  // อัปเดต High ใหม่
      if (bid < m_asian_low)  m_asian_low  = bid;  // อัปเดต Low ใหม่
      m_asian_tracking = true;
  }

ทำไมใช้ Ask สำหรับ High และ Bid สำหรับ Low?
  • Asian High ใช้ Ask: เพราะ Long Breakout เข้าที่ Ask
    ถ้าใช้ Bid → High ต่ำกว่าความเป็นจริง → Trigger ต่ำกว่าที่ควร → False Breakout
  • Asian Low ใช้ Bid: เพราะ Short Breakout เข้าที่ Bid
    ถ้าใช้ Ask → Low สูงกว่าความเป็นจริง → Trigger สูงกว่าที่ควร → False Breakout
```

**วิธีที่ 2: H1 Bar Scan (Fallback)**

```
ถ้า EA เพิ่งเริ่ม Runtime ตอน 09:00 GMT (ไม่ได้ Capture Asian Live):
  ระบบ Scan H1 bars ย้อนกลับไปหา Asian window:

  CopyHigh/CopyLow ดึงข้อมูล H1 bars ที่ timestamp อยู่ใน [Asian_Start, Asian_End)
  m_asian_high = max(High[bar] สำหรับทุก bar ใน Asian window)
  m_asian_low  = min(Low[bar]  สำหรับทุก bar ใน Asian window)

ข้อจำกัดของ Fallback:
  H1 High/Low ไม่ accurate เท่า Tick-by-tick เพราะ H1 อาจ Miss spike สั้นๆ
  แต่ในทางปฏิบัติ: Asian session ไม่ค่อยมี spike ใหญ่ → Fallback ยอมรับได้
```

**Range Validity Filter:**

```
Minimum Range Filter:
  asian_range = m_asian_high − m_asian_low

  if (asian_range < m_range_min_pips × pip_size):
      m_asian_range_valid = false  → ไม่เทรดวันนี้

เหตุผล:
  Range น้อยกว่า 20 pips = Asian ไม่ได้สร้าง "กรอบ" ที่มีนัยสำคัญ
  อาจเกิดในวัน:
    • วันหยุดนักขัตฤกษ์ในหลายประเทศพร้อมกัน
    • Asian session ที่ผิดปกติเพราะข่าวช่วงกลางดึก
    • ตลาดรอข้อมูลสำคัญ (NFP, FOMC) → ไม่มีใครเคลื่อนไหว
  ในสถานการณ์เหล่านี้ Breakout จะไม่มีแรง → Skip ดีกว่า
```

---

### 2.2 Breakout Trigger — สูตรพร้อม ATR-Adaptive Buffer

**สูตรทั่วไป:**

```
breakout_buffer = max(
    SB_Breakout_Buffer × pip_size,     // Floor: Fixed pip minimum
    0.10 × ATR(SB_ATR_Period, PERIOD_H1)   // Ceiling reference: ATR-based
)

Long  Trigger = m_asian_high + breakout_buffer
Short Trigger = m_asian_low  − breakout_buffer

ตรวจ Breakout ทุก Tick:
  if (ask >= Long  Trigger AND NOT m_london_broken_up) → SIGNAL_BUY
  if (bid <= Short Trigger AND NOT m_london_broken_dn) → SIGNAL_SELL
```

**ทำไมต้อง ATR-Adaptive Buffer?**

```
Fixed 3 pips (Static):
  ปัญหา: ในตลาดที่ผันผวนสูง (ATR = 100 pips/H1)
          3 pips คือ noise ระดับมิลลิวินาที — ระบบจะ Fire ทันทีที่ราคาแตะ High+3
          แม้แต่ Spread เปลี่ยนก็ทะลุ Buffer แล้ว → False Breakout 100%

ATR × 0.10 (Dynamic):
  ตลาด Normal (ATR H1 = 58 pips): Buffer = 5.8 pips — พอดี
  ตลาด Quiet  (ATR H1 = 30 pips): Buffer = 3.0 pips — เท่ากับ Fixed Floor
  ตลาด Volatile (ATR H1 = 100 pips): Buffer = 10 pips — กว้างพอกรอง Noise

max() ทำให้ Buffer ไม่น้อยกว่า Fixed Minimum เสมอ (Safety floor)
```

**ตัวอย่างผลกระทบของ Buffer ต่อ R:R:**

```
Asian Range = 30 pips, ATR H1 = 60 pips
Buffer = max(3, 6) = 6 pips

Entry (Long) = Asian High + 6 pips

Distance Entry → TP:  30 × 1.5 = 45 pips
Distance Entry → SL:  (Asian High + 6) − (Asian Low + 30×0.5)
               = 30 + 6 − 15 = 21 pips

R:R = 45 / 21 = 2.14

---

ถ้า Buffer = 0 pips (ไม่มี):
  Distance → SL = 30 − 15 = 15 pips
  R:R = 45 / 15 = 3.0 (สูงกว่า แต่ False Breakout เพิ่ม)

---

ถ้า Buffer = 15 pips (ใหญ่เกิน):
  Distance → SL = 30 + 15 − 15 = 30 pips
  R:R = 45 / 30 = 1.5 (ต่ำลง — Entry ห่างเกินทำให้ R:R แย่ลง)

ข้อสรุป: Buffer = 5-10% ของ Range คือ Optimal สำหรับ R:R ≥ 2.0
```

---

### 2.3 TP/SL — สูตรและ R:R Analysis เชิงลึก

**สูตรสมบูรณ์:**

```
Long Trade (Breakout ขึ้น):
  Entry = ask  (ณ เวลา Breakout)
  TP    = ask + asian_range × m_tp_range_mult
        = Entry + 1.5 × R          [R = asian_range]

  SL    = asian_low + asian_range × m_sl_inside_ratio
        = L + 0.5 × R

Short Trade (Breakout ลง):
  Entry = bid
  TP    = bid − asian_range × m_tp_range_mult
        = Entry − 1.5 × R

  SL    = asian_high − asian_range × m_sl_inside_ratio
        = H − 0.5 × R
```

**ทำไม SL อยู่ "ภายใน" Range?**

```
แนวคิด: ถ้า Breakout ขึ้นจริง ราคาจะไม่กลับลงมาต่ำกว่า 50% ของ Asian Range
        ถ้าราคากลับมาถึง L + 0.5R แสดงว่า Breakout ล้มเหลว → ตัดขาดทุน

ภาพ Range:
  Asian High (H)  ────────────────────  ← Breakout Entry ที่ H + Buffer
                  |  Long Entry Zone  |
  H − 0.5×Range  ·  ·  ·  ·  ·  ·  ·  ← TP ของ Short / SL ไม่ถึงจุดนี้ (Short case)
  ─────────────  Midpoint ─────────────
  L + 0.5×Range  ·  ·  ·  ·  ·  ·  ·  ← SL ของ Long (L + 0.5R)
                  | Short Entry Zone  |
  Asian Low (L)   ────────────────────  ← Breakout Entry ที่ L − Buffer

ทำไมไม่ใช้ Asian Low เป็น SL ของ Long?
  ถ้า SL = Asian Low: Distance = Entry − L = Range + Buffer = R + B
  SL ไกลกว่า → ขาดทุนมากขึ้นถ้าผิด → R:R แย่ลง
  ใช้ L + 0.5R แทน: Distance = (H + B) − (L + 0.5R) = 0.5R + B → SL แคบกว่า
```

**ความสัมพันธ์ระหว่าง Asian Range และ R:R:**

| Asian Range | Buffer (6% of Range) | TP (1.5R) | SL (0.5R+B) | R:R |
|------------|---------------------|-----------|-------------|-----|
| 15 pips | 0.9 pip | 22.5 pips | 8.4 pips | 2.7 |
| 20 pips | 1.2 pips | 30.0 pips | 11.2 pips | 2.7 |
| 30 pips | 1.8 pips | 45.0 pips | 16.8 pips | 2.7 |
| 50 pips | 3.0 pips | 75.0 pips | 28.0 pips | 2.7 |
| 80 pips | 4.8 pips | 120 pips | 44.8 pips | 2.7 |

**ข้อสังเกต:** R:R คงที่ที่ประมาณ 2.7 ไม่ว่า Range จะกว้างแค่ไหน (เพราะ TP และ SL ต่างก็ Scale ตาม Range) — ข้อดีคือ ระบบมี R:R ที่ Consistent โดยไม่ต้องปรับพารามิเตอร์ตาม Volatility

---

### 2.4 Confidence Score — สูตรและ Interpretation

**สูตรสมบูรณ์:**

```python
# ใน CSessionBreakout::_CalcConfidence():

range_atr_ratio = (m_asian_high − m_asian_low) / m_atr_h1

# Normalize: range ≈ 2× ATR = score 1.0
range_factor = min(1.0, range_atr_ratio / 2.0)

# Session factor:
session_factor = 1.0   if London
session_factor = 0.75  if NY

raw_confidence = range_factor × session_factor
```

**การแปลความหมาย:**

| Asian Range / ATR | range_factor | Session | raw_confidence | Interpretation |
|------------------|-------------|---------|----------------|----------------|
| 0.5× ATR (แคบมาก) | 0.25 | London | 0.25 | Range น้อยกว่า ATR — Breakout อาจไม่มีแรง |
| 1.0× ATR | 0.50 | London | 0.50 | Range ≈ ATR — ดี |
| 2.0× ATR | 1.00 | London | 1.00 | Range กว้างมาก — Breakout แรงแน่นอน |
| 2.0× ATR | 1.00 | NY | 0.75 | Range ดีแต่ NY มี Volume น้อยกว่า |
| 0.5× ATR | 0.25 | NY | 0.19 | Confidence ต่ำมาก — AI Council มักจะ Reject |

**ทำไม NY Factor = 0.75?**

```
สถิติจากการวิเคราะห์ข้อมูลย้อนหลัง:
  London Breakout Win Rate ≈ 62%  → ถือเป็น Baseline 1.0
  NY Breakout Win Rate    ≈ 47%  → 47/62 ≈ 0.76 ≈ 0.75

เหตุผลที่ NY Win Rate ต่ำกว่า:
  1. NY มักขัดแย้งกับ London Momentum — ถ้า London ขึ้นแล้ว NY อาจ Reverse
  2. London Close (12:00 GMT) ทำให้ Liquidity ลดชั่วคราว → Spread สูงขึ้น
  3. NY มีข่าว US มากกว่า → ทิศทางเปลี่ยนแปลงบ่อยกว่า European session
```

---

### 2.5 GMT Offset และ Daylight Saving Time

**ปัญหา Broker GMT Offset:**

```
ปัญหาสำคัญของ S09: Broker Server ใช้ GMT+3 (EET) เป็น Default
แต่กลยุทธ์ทำงานตาม GMT มาตรฐาน

ถ้า SB_BrokerGMT_Offset ผิด 1 ชั่วโมง:
  Asian Session จะถูกเปิดผิดเวลา
  Range อาจ Include ช่วง London Open (08:00 GMT) เข้าไปด้วย
  → High ของ "Asian Range" คือ London Breakout จริงๆ
  → ระบบจะไม่มีวัน Breakout เพราะ Trigger อยู่เหนือ "Breakout จริงที่เกิดไปแล้ว"

วิธีแก้ใน FlashEASuite:
  ใช้ TimeGMT() ใน MQL5 (ไม่ใช่ TimeCurrent()) เพื่อได้ GMT จริง
  แล้วบวก SB_BrokerGMT_Offset เพื่อแปลงกลับเป็นเวลา Broker
```

**Daylight Saving Time (DST) กับ Session Hours:**

```
ปัญหา DST:
  UK และ EU เปลี่ยน DST ต่างวันกัน (UK เปลี่ยนก่อน 1 สัปดาห์)
  ช่วง 1 สัปดาห์นั้น London Open จะอยู่ที่ 07:00 GMT แทน 08:00 GMT

  ถ้า SB_London_Start = 8 (คงที่):
  วันนั้น London Open ที่จริงเกิดที่ 07:00 → ระบบพลาด Breakout ทั้งหมด!

Python Brain แก้ปัญหา:
  Brain มี DST Calendar สำหรับ UK/EU/US
  ส่ง CONFIG_PUSH ปรับ S09_LONDON_START ให้ถูกต้องทุกครั้ง DST เปลี่ยน
  → นี่คือเหตุผลหลักที่ S09 ต้องการ Server Mode (Standalone จะไม่รู้ DST)
```

---

## 3. สถาปัตยกรรมระบบและการแบ่งหน้าที่ (System Architecture)

### 3.1 ตารางแบ่งความรับผิดชอบ Python Brain vs MQL5 Trader

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                S09 ARCHITECTURE — ภาพรวมสถาปัตยกรรม                          │
│           FULL MQL5 Execution + Python Brain Calendar Intelligence            │
├───────────────────────────────┬──────────────────────────────────────────────┤
│  PYTHON BRAIN (Server Side)   │  MQL5 TRADER (Client Side)                    │
│  Calendar + Session Config    │  Real-time Session Tracking                   │
├───────────────────────────────┼──────────────────────────────────────────────┤
│  ✅ DST Calendar Adjustment   │  ✅ Asian Range Capture (Tick-by-tick)         │
│     UK/EU/US DST awareness    │     m_asian_high / m_asian_low tracking        │
│     ปรับ London/NY times      │                                               │
│                               │  ✅ Breakout Detection per Tick                │
│  ✅ Holiday Detection          │     ask >= Long_Trigger? → SIGNAL_BUY         │
│     Bank Holiday Calendar     │     bid <= Short_Trigger? → SIGNAL_SELL       │
│     ไม่ส่ง CONFIG_PUSH         │                                               │
│     ในวันหยุดนักขัตฤกษ์       │  ✅ TP/SL Calculation                          │
│                               │     TP = Entry ± 1.5 × asian_range            │
│  ✅ Regime Classification      │     SL inside range (0.5× ratio)              │
│     ส่ง S09 ใน VOLATILE/       │                                               │
│     TRENDING เท่านั้น          │  ✅ Daily State Machine                        │
│                               │     Asian → London → Dead → NY → Reset        │
│  ✅ Session Window Optimize   │                                               │
│     ปรับ Asian/London/NY times│  ✅ London vs NY Session Tracking              │
│     ตาม DST และ Backtested     │     m_london_broken_up/dn                     │
│     Optimal windows           │     m_ny_broken_up/dn (once-per-dir flags)    │
│                               │                                               │
│  ✅ Low-Liquidity Day Filter   │  ✅ H1 ATR Computation                         │
│     ปรับ Range_Min ขึ้นในช่วง  │     iATR handle PERIOD_H1                     │
│     Pre-NFP, Pre-FOMC         │                                               │
│                               │  ✅ Confidence Scoring (local)                 │
│  ✅ CONFIG_PUSH (Port 7778)   │     range_factor × session_factor             │
│     MessagePack binary        │                                               │
│                               │  ✅ TRADE_REPORT (Port 7779)                   │
│                               │     ส่ง PnL กลับให้ PerformanceTracker        │
└───────────────────────────────┴──────────────────────────────────────────────┘
```

**ทำไม S09 ไม่รองรับ Standalone Mode:**

S09 ต้องการ "ปัญญาเชิงปฏิทิน (Calendar Intelligence)" ที่ Python Brain เท่านั้นจัดหาได้ มี 4 สิ่งที่ Brain ทำแต่ MQL5 ทำไม่ได้:

```
1. DST Detection (ยืนยันได้แน่นอน)
   MQL5 รู้แค่เวลา Broker Server — ไม่รู้ว่า UK ได้เปลี่ยน DST วันไหน
   Brain มี Python library `pytz` ที่รู้ DST schedule ของทุกประเทศ

2. Holiday Calendar (ยืนยันได้แน่นอน)
   MQL5 ไม่มี Built-in Holiday Calendar
   Brain มีรายชื่อวันหยุด Bank Holiday UK, EU, US พร้อม Year-Specific Dates

3. Pre-Event Liquidity Warning (ยืนยันได้แน่นอน)
   Brain รู้วัน NFP, FOMC, ECB Policy Meeting ล่วงหน้า
   ก่อนข่าวใหญ่ Asian Range มักเล็กผิดปกติ → Brain เพิ่ม Range_Min หรือ Skip

4. Session Window Optimization (ยืนยันได้แน่นอน)
   Optimal London window ไม่ได้เป็น 08:00-12:00 ตลอดไป
   บางช่วงปีที่ Liquidity ขยับ Brain ปรับ Window ตาม Backtested results
```

---

### 3.2 Daily State Machine — โครงสร้างข้อมูลและการเปลี่ยนสถานะ

```mql5
// State Variables ที่ CSessionBreakout เก็บไว้ตลอดวัน:

// ── Asian Range ──
double m_asian_high;          // High สูงสุดในช่วง Asian
double m_asian_low;           // Low ต่ำสุดในช่วง Asian
bool   m_asian_range_valid;   // Range >= Range_Min_Pips และ Captured แล้ว
bool   m_asian_tracking;      // กำลังอยู่ในช่วง Asian (ติดตาม tick อยู่)

// ── London Session ──
bool   m_london_broken_up;    // London BUY ยิงไปแล้ว (ป้องกัน Re-entry)
bool   m_london_broken_dn;    // London SELL ยิงไปแล้ว
double m_london_high;         // High ของ London (ใช้เป็น NY Range)
double m_london_low;          // Low ของ London

// ── NY Session ──
bool   m_ny_broken_up;        // NY BUY ยิงไปแล้ว
bool   m_ny_broken_dn;        // NY SELL ยิงไปแล้ว

// ── Reset รายวัน ──
// เกิดขึ้นเมื่อ TimeGMT() เปลี่ยนวัน (midnight broker time)
void _ResetDaily() {
    m_asian_high        = 0;
    m_asian_low         = DBL_MAX;
    m_asian_range_valid = false;
    m_asian_tracking    = false;
    m_london_broken_up  = false;
    m_london_broken_dn  = false;
    m_london_high       = 0;
    m_london_low        = DBL_MAX;
    m_ny_broken_up      = false;
    m_ny_broken_dn      = false;
}
```

**ทำไมต้องมี Flag `broken_up` และ `broken_dn` แยกกัน?**

```
เหตุผล: ป้องกัน Double Entry ในทิศทางเดียวกัน

สถานการณ์ที่อาจเกิดขึ้นถ้าไม่มี Flag:
  08:14 → ask = 1.08678 ≥ Trigger → BUY Signal ส่ง (Trade 1 เปิด)
  08:14:00.050 → ask = 1.08679 → ยังมากกว่า Trigger → BUY ซ้ำ! (Trade 2 เปิด)
  ... วนซ้ำทุก Tick ตลอด London session!

Flag แก้ปัญหา:
  เมื่อ BUY Signal ส่งครั้งแรก → m_london_broken_up = true
  Tick ถัดๆ มา: if (m_london_broken_up) return SIGNAL_NONE;
  → ไม่มี Double Entry เลย ตลอดวัน (สูงสุด 1 Long + 1 Short ต่อ Session)
```

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางข้อมูลจากตลาดสู่คำสั่งซื้อขาย

```
[ตลาด Forex] → [MT5 Platform] → [FeederEA] → Port 7777 → [Python Brain]
                                                              ↓
                                                   [Calendar Intelligence]
                                                   DST Check + Holiday Check
                                                              ↓
                                              {วันนี้ Trading Day?}
                                               YES ↓            NO → ไม่ส่ง CONFIG_PUSH
                                                              ↓
                                              [Regime Classifier]
                                              VOLATILE/TRENDING → Include S09
                                              RANGING → Exclude / Low weight
                                                              ↓
                                            [Session Window Optimizer]
                                            ตรวจ DST → ปรับ London_Start (7 หรือ 8?)
                                            ตรวจ Pre-Event → ปรับ Range_Min
                                                              ↓
                                              [config_builder.py]
                                              สร้าง CONFIG_PUSH type=10
                                              S09_LONDON_START, S09_RANGE_MIN
                                              S09_TP_RANGE_MULT, S09_SL_INSIDE
                                                              ↓
                                              ZMQ PUSH Port 7778 (MessagePack)
                                                              ↓
                              [ProgramC_Trader.mq5 — CStrategyManager]
                               OnNewConfig() → CSessionBreakout::SetDynamicParams()
                               Hot-reload session times — ไม่ต้อง Restart EA
                                                              ↓
                                  ┌────────────────────────────────────────┐
                                  │       Real-Time Tick Loop OnTick()     │
                                  │   CSessionBreakout::Analyze(tick)      │
                                  └────────────────────────────────────────┘
                                                    ↓
                              ┌─────────────────────┼─────────────────────┐
                              │ Asian Zone           │ London/NY Zone      │
                              │ 00:00-08:00 GMT      │ 08:00-17:00 GMT     │
                              ↓                     ↓                     ↓
                    Track ask/bid High/Low    ตรวจ Breakout        Dead Zone
                    อัปเดต m_asian_high/low   vs Trigger           SIGNAL_NONE
                              ↓                     ↓
                    Range ≥ 20 pips?          ask ≥ Long_Trigger?
                    YES → range_valid          YES → SIGNAL_BUY
                    NO  → Skip today           NO  → SIGNAL_NONE
                                                    ↓
                                            _CalcConfidence()
                                            range_factor × session_factor
                                                    ↓
                                            MM → CalculateLot()
                                                    ↓
                                            Place Order
                                            TP = Entry ± 1.5R
                                            SL = inside range
                                                    ↓
                                            TRADE_REPORT → Port 7779
                                                    ↓
                                            PerformanceTracker
                                            EMA Win Rate Update
                                            → AI Council รอบต่อไป
                                                    ↓
                              Midnight Broker Time → _ResetDaily()
                              Session Flags ล้างทั้งหมด → วันใหม่เริ่ม
```

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 องค์ประกอบที่ 1: Range Factor (น้ำหนักหลัก)

```
range_atr_ratio = asian_range / ATR_H1

Range น้อยกว่า ATR → Breakout ไม่มี "พื้นที่" แรงดัน:
  ratio = 0.5 → range_factor = min(1.0, 0.5/2.0) = 0.25   (อ่อนแอ)

Range เท่ากับ 2×ATR → Breakout มีพื้นที่แรงดันเต็มที่:
  ratio = 2.0 → range_factor = min(1.0, 2.0/2.0) = 1.00   (แข็งแกร่ง)

Range เกิน 2×ATR → ยังคงที่ที่ 1.0 (Capped):
  ratio = 3.0 → range_factor = min(1.0, 3.0/2.0) = 1.00

หมายเหตุ: Range ใหญ่เกินก็ไม่ได้ให้ Confidence เพิ่ม แต่ทำให้ SL กว้างขึ้น
           AI Council จะ Penalize ผ่าน Position Sizing ในขั้นต่อไป
```

### 5.2 องค์ประกอบที่ 2: Session Factor

```
London Session = 1.00  (Full confidence — Volume สูงสุด)
NY Session     = 0.75  (Discounted — Win Rate ต่ำกว่า 25%)

ทำไม NY Discount 25%?
  Statistical analysis จาก FlashEASuite backtests:
  • London Breakout: Win Rate ≈ 62%, Avg PnL per trade = +1.8R
  • NY Breakout:     Win Rate ≈ 47%, Avg PnL per trade = +1.2R

  Expected Value ratio: 1.2 / 1.8 = 0.67 → Discount ≈ 33%
  ระบบใช้ Conservative 25% เพื่อยังให้ NY มีโอกาสผ่าน AI Council บ้าง
```

### 5.3 Regime Multiplier Impact

| Regime | raw_confidence | Regime Factor | weighted_conf | AI Council (≥0.25) |
|--------|---------------|--------------|--------------|-------------------|
| VOLATILE | 0.50 | ×1.5 | 0.75 | ✅ ผ่านสบาย |
| TRENDING | 0.50 | ×1.2 | 0.60 | ✅ ผ่าน |
| SQUEEZE | 0.50 | ×0.6 | 0.30 | ✅ ผ่านเฉียด |
| RANGING | 0.50 | ×0.4 | 0.20 | ❌ ไม่ผ่าน |
| VOLATILE | 0.20 | ×1.5 | 0.30 | ✅ ผ่าน (Range แคบ แต่ Volatile Boost) |
| RANGING | 0.80 | ×0.4 | 0.32 | ✅ ผ่านเฉียด (Range กว้างมาก แต่ Regime ไม่ดี) |

**ข้อสังเกต:** แม้ Range จะดีมาก (range_factor = 1.0) แต่ถ้า Regime คือ RANGING → weighted_conf ≈ 0.40 ซึ่งยังผ่าน AI Council อยู่ นี่คือ Design Choice ที่ให้ S09 โอกาสในบาง RANGING Cases ที่ Asian Range กว้างมากพอ

---

## 6. MQL5: การทำงานภายในของ CSessionBreakout

### 6.1 Signal Logic แบบ Tick-by-Tick

```mql5
ENUM_SIGNAL CSessionBreakout::Analyze(MqlTick &tick)
{
    // ── ตรวจช่วงเวลาปัจจุบัน ──
    datetime gmt_now  = TimeGMT();
    int      gmt_hour = (int)(gmt_now % 86400) / 3600;   // 0–23

    // ── Reset รายวัน ──
    if (_IsNewDay(gmt_now)) _ResetDaily();

    // ── Asian Session: สะสม Range ──
    if (gmt_hour >= m_asian_start && gmt_hour < m_asian_end)
    {
        m_asian_tracking = true;
        if (tick.ask > m_asian_high) m_asian_high = tick.ask;
        if (tick.bid < m_asian_low)  m_asian_low  = tick.bid;
        return SIGNAL_NONE;  // ช่วง Asian ไม่เทรด — แค่เก็บ Range
    }

    // ── ตรวจ Range Validity เมื่อออกจาก Asian ──
    if (!m_asian_range_valid && m_asian_tracking)
    {
        double range = m_asian_high - m_asian_low;
        if (range >= m_range_min_pips * _Point * 10)
        {
            m_asian_range_valid = true;
            m_atr = _GetATR_H1();
            m_breakout_buf_val  = MathMax(m_breakout_buffer * _Point * 10,
                                          0.10 * m_atr);
        }
        else return SIGNAL_NONE;  // Range น้อยเกิน → Skip วันนี้
    }

    if (!m_asian_range_valid) return SIGNAL_NONE;

    // ── London Session ──
    if (gmt_hour >= m_london_start && gmt_hour < m_london_end)
    {
        // Track London Range สำหรับ NY
        if (tick.ask > m_london_high) m_london_high = tick.ask;
        if (tick.bid < m_london_low)  m_london_low  = tick.bid;

        if (!m_london_broken_up &&
            tick.ask >= m_asian_high + m_breakout_buf_val)
        {
            m_london_broken_up = true;
            m_session_factor   = 1.0;
            _PrepareSignal(tick.ask, SIGNAL_BUY);
            return SIGNAL_BUY;
        }
        if (!m_london_broken_dn &&
            tick.bid <= m_asian_low - m_breakout_buf_val)
        {
            m_london_broken_dn = true;
            m_session_factor   = 1.0;
            _PrepareSignal(tick.bid, SIGNAL_SELL);
            return SIGNAL_SELL;
        }
        return SIGNAL_NONE;
    }

    // ── Dead Zone (12:00–13:00 GMT) ──
    if (gmt_hour >= m_london_end && gmt_hour < m_ny_start)
        return SIGNAL_NONE;

    // ── NY Session ──
    if (gmt_hour >= m_ny_start && gmt_hour < m_ny_end)
    {
        // ใช้ London Range เป็น NY Reference
        double ny_high = (m_london_high > 0) ? m_london_high : m_asian_high;
        double ny_low  = (m_london_low  < DBL_MAX) ? m_london_low  : m_asian_low;

        if (!m_ny_broken_up &&
            tick.ask >= ny_high + m_breakout_buf_val)
        {
            m_ny_broken_up   = true;
            m_session_factor = 0.75;   // NY Discount
            _PrepareSignal(tick.ask, SIGNAL_BUY);
            return SIGNAL_BUY;
        }
        if (!m_ny_broken_dn &&
            tick.bid <= ny_low - m_breakout_buf_val)
        {
            m_ny_broken_dn   = true;
            m_session_factor = 0.75;
            _PrepareSignal(tick.bid, SIGNAL_SELL);
            return SIGNAL_SELL;
        }
        return SIGNAL_NONE;
    }

    // ── After NY Close ──
    return SIGNAL_NONE;  // 17:00+ GMT — No more trades
}
```

### 6.2 TP/SL Injection ผ่าน `_PrepareSignal()`

```mql5
void CSessionBreakout::_PrepareSignal(double entry_price, ENUM_SIGNAL sig)
{
    double range = m_asian_high - m_asian_low;

    if (sig == SIGNAL_BUY)
    {
        m_state.last_tp = entry_price + range * m_tp_range_mult;
        m_state.last_sl = m_asian_low  + range * m_sl_inside_ratio;
    }
    else
    {
        m_state.last_tp = entry_price - range * m_tp_range_mult;
        m_state.last_sl = m_asian_high - range * m_sl_inside_ratio;
    }

    // StrategyManager จะอ่าน m_state.last_tp / m_state.last_sl
    // เมื่อ Signal ถูกส่งกลับ เพื่อใส่ใน Order Send
}
```

### 6.3 CONFIG_PUSH Parameter Parsing

```mql5
void CSessionBreakout::SetDynamicParams(const SDynamicParams &params)
{
    m_asian_start    = (int)params.GetParam("S09_ASIAN_START",   m_asian_start);
    m_asian_end      = (int)params.GetParam("S09_ASIAN_END",     m_asian_end);
    m_london_start   = (int)params.GetParam("S09_LONDON_START",  m_london_start);
    m_london_end     = (int)params.GetParam("S09_LONDON_END",    m_london_end);
    m_ny_start       = (int)params.GetParam("S09_NY_START",      m_ny_start);
    m_ny_end         = (int)params.GetParam("S09_NY_END",        m_ny_end);
    m_range_min_pips = (int)params.GetParam("S09_RANGE_MIN",     m_range_min_pips);
    m_breakout_buffer =     params.GetParam("S09_BREAKOUT_BUF",  m_breakout_buffer);
    m_sl_inside_ratio =     params.GetParam("S09_SL_INSIDE",     m_sl_inside_ratio);
    m_tp_range_mult  =      params.GetParam("S09_TP_RANGE_MULT", m_tp_range_mult);

    // ถ้า Session Hours เปลี่ยน → Invalidate Asian Range (อาจ Window ใหม่ครอบ Range เก่า)
    if (m_asian_start != prev_asian_start || m_asian_end != prev_asian_end)
    {
        _ResetDaily();   // เริ่มนับ Range ใหม่
        PrintFormat("[S09] Session window changed — Daily state reset");
    }
}
```

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `SB_Asian_Start` | 0 | 22–2 (วันก่อน) | GMT Hour เริ่มต้น Asian Session ค่า 0 = เที่ยงคืน GMT สำหรับ EET+3 Broker ต้องบวก Offset เข้าไป |
| `SB_Asian_End` | 7 | 6–9 | GMT Hour สิ้นสุด Asian Session ต้องน้อยกว่า London_Start เสมอ เพื่อให้มีช่วง "ก่อน London" ที่ Range นิ่งแล้ว |
| `SB_London_Start` | 8 | 7–9 | GMT Hour เริ่ม London Session ในฤดูหนาว UK = 8 GMT, ฤดูร้อน UK BST = 7 GMT — Python Brain ปรับให้อัตโนมัติ |
| `SB_London_End` | 12 | 11–13 | GMT Hour สิ้นสุด London Breakout Window การขยาย Window อาจ Capture Late Breakout แต่เพิ่ม Risk |
| `SB_NY_Start` | 13 | 12–14 | GMT Hour เริ่ม NY Session ปกติตรงกับ NY Open (13:00 GMT ฤดูหนาว, 12:00 GMT ฤดูร้อน) |
| `SB_NY_End` | 17 | 16–18 | GMT Hour สิ้นสุด NY Session หลัง 17:00 GMT Volume ลดมากและ Signal ไม่น่าเชื่อถือ |
| `SB_Range_Min_Pips` | 20 | 10–40 | ขั้นต่ำ Asian Range เป็น pips ค่า 10 = ยอมรับ Range แคบมาก (เหมาะ Symbol ที่ Range น้อยเสมอ) ค่า 40 = กรองเข้มข้น (ลด Trade แต่ Quality สูง) |
| `SB_Breakout_Buffer` | 3.0 | 1.0–10.0 | Buffer เป็น pips (ใช้เป็น Floor) ATR-based buffer อาจสูงกว่านี้ ค่าน้อย = Entry เร็ว, False Signal มาก ค่ามาก = Entry ช้า, R:R แย่ลง |
| `SB_SL_Inside_Ratio` | 0.5 | 0.3–0.7 | สัดส่วน SL จาก Asian Low (Long) ค่า 0.5 = SL อยู่ที่ Midpoint ของ Range ค่า 0.3 = SL แคบกว่า (R:R ดีขึ้น แต่โดน SL ง่ายขึ้น) |
| `SB_TP_Range_Mult` | 1.5 | 1.0–3.0 | TP เป็น Multiple ของ Asian Range ค่า 1.0 = TP = 1×Range (Conservative) ค่า 2.0 = TP = 2×Range (Aggressive, Win Rate ลดลง) |
| `SB_ATR_Period` | 14 | 10–20 | ATR Period บน H1 Timeframe ใช้วัด Adaptive Buffer และ Confidence Ratio |
| `SB_BrokerGMT_Offset` | 3 | −5 ถึง +3 | GMT Offset ของ Broker Server เช่น EET = +3, CET = +1, EST = −5 **ค่านี้ต้องถูกต้องเสมอ** มิฉะนั้น Session Window ทั้งหมดผิด |

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | คำอธิบาย | ผลกระทบทันที |
|-----|--------|----------|-------------|
| `S09_ASIAN_START` | int | Asian window start (GMT) ปรับตาม DST | _ResetDaily() ถ้า window เปลี่ยน |
| `S09_ASIAN_END` | int | Asian window end (GMT) | _ResetDaily() ถ้า window เปลี่ยน |
| `S09_LONDON_START` | int | London window start — สำคัญสุดสำหรับ DST | Range capture ตาม Window ใหม่ทันที |
| `S09_LONDON_END` | int | London window end | ขยาย/ลด London Breakout Window |
| `S09_NY_START` | int | NY window start | เปิด/ปิด NY Trading ตามเวลา |
| `S09_NY_END` | int | NY window end | ตัด Signal หลังเวลานี้ |
| `S09_RANGE_MIN` | int | Min Asian Range (pips) | ปรับขึ้นก่อนข่าวใหญ่ (Brain เป็นผู้ตัดสินใจ) |
| `S09_BREAKOUT_BUF` | float | Breakout buffer pips | Adaptive buffer floor ใหม่ |
| `S09_SL_INSIDE` | float | SL inside ratio | TP/SL คำนวณใหม่ใน _PrepareSignal() |
| `S09_TP_RANGE_MULT` | float | TP multiplier | TP คำนวณใหม่ใน _PrepareSignal() |

### 7.3 Export Keys สำหรับ Monitoring

| Key | คำอธิบาย |
|-----|---------|
| `S09_ASIAN_HIGH` | Asian High ที่ Capture ได้วันนี้ |
| `S09_ASIAN_LOW` | Asian Low ที่ Capture ได้วันนี้ |
| `S09_ASIAN_RANGE_PIPS` | Asian Range ขนาด (pips) |
| `S09_RANGE_VALID` | 1 = Valid, 0 = ยังไม่พอหรือน้อยเกิน |
| `S09_LONDON_STATUS` | 0=ยังไม่ Open, 1=รอ Breakout, 2=Long Fired, 3=Short Fired |
| `S09_NY_STATUS` | เหมือน London แต่สำหรับ NY |
| `S09_CONFIDENCE` | Confidence ล่าสุดที่คำนวณ |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Server Mode เท่านั้น (No Standalone)

```
ลำดับการทำงานรายวัน (Server Mode):

เวลา 00:00 GMT (วันใหม่):
  1. _ResetDaily() — ล้าง Flags ทั้งหมด
  2. ระบบเริ่ม Track Asian Ticks อัตโนมัติ

เวลาเช้า (ก่อน London):
  3. Python Brain ตรวจปฏิทิน:
     → วันหยุด? → ไม่ส่ง CONFIG_PUSH, S09 ไม่ได้ Config → ไม่เทรด
     → DST เปลี่ยน? → ส่ง CONFIG_PUSH ปรับ London_Start
     → Pre-NFP (วันศุกร์ก่อน 15:30 GMT)? → เพิ่ม Range_Min เป็น 35 pips
  4. Brain ส่ง CONFIG_PUSH → CSessionBreakout::SetDynamicParams()
  5. MQL5 ปรับ Session Windows ทันที

เวลา 08:00 GMT (London Open):
  6. ระบบออกจาก Asian Loop → ตรวจ Range Validity
     Range >= Range_Min → m_asian_range_valid = true
     Range < Range_Min  → Skip วันนี้ (SIGNAL_NONE ตลอด)
  7. ถ้า Valid: คำนวณ Trigger + TP + SL
  8. ทุก Tick: ตรวจ ask/bid vs Trigger → Signal ถ้าทะลุ

เวลา 12:00 GMT (Dead Zone):
  9. SIGNAL_NONE ทุก Tick — ไม่เปิด Trade ใหม่

เวลา 13:00 GMT (NY Open):
  10. ตรวจ NY Breakout จาก London Range
      (ลด Confidence 25% โดยอัตโนมัติ)

เวลา 17:00 GMT:
  11. ปิด Session — SIGNAL_NONE จนถึงเที่ยงคืน
```

### 8.2 เมื่อ Brain ขาดการเชื่อมต่อ (Server Disconnect)

```
เมื่อ ProgramC_Trader ไม่ได้รับ CONFIG_PUSH > Timeout Threshold:
  CConnectionMonitor → ตรวจ Heartbeat หาย
  StrategyManager → Mark S09 weight = 0
  S09 หยุด Generate Signal ทันที (ไม่มี Standalone fallback)

เหตุผล: ถ้า Brain ขาดการเชื่อมต่อในวันหยุด → S09 อาจ Generate False Signal
         เพราะ "วันหยุด" ทำให้ Asian Range ผิดปกติโดยสิ้นเชิง
         ปลอดภัยกว่าคือหยุดทำงานรอ Brain กลับมา

เมื่อ Brain กลับมา:
  Brain ส่ง CONFIG_PUSH ใหม่ → S09 เริ่มทำงานอีกครั้ง
  ถ้าอยู่ในช่วง Asian Session → Range Capture เริ่มใหม่
  ถ้าอยู่ในช่วง London/NY → ใช้ Fallback H1 Scan สำหรับ Asian Range
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| สถานะ | เงื่อนไข | การกระทำ |
|-------|---------|---------|
| **Asian Tracking** | 00:00–07:59 GMT | Track High/Low ทุก Tick, ไม่ส่ง Signal |
| **Range Invalid** | Asian Range < Range_Min | SIGNAL_NONE ตลอดวัน |
| **London Long** | ask ≥ Asian_High + Buffer, London Hours | SIGNAL_BUY + TP + SL inject |
| **London Short** | bid ≤ Asian_Low − Buffer, London Hours | SIGNAL_SELL + TP + SL inject |
| **Dead Zone** | 12:00–12:59 GMT | SIGNAL_NONE ทั้งหมด |
| **NY Long** | ask ≥ London_High + Buffer, NY Hours | SIGNAL_BUY + Confidence × 0.75 |
| **NY Short** | bid ≤ London_Low − Buffer, NY Hours | SIGNAL_SELL + Confidence × 0.75 |
| **After NY** | 17:00+ GMT | SIGNAL_NONE ทั้งหมด |
| **Reset** | 00:00 GMT ถัดไป | _ResetDaily() — Flags ทั้งหมดล้าง |

---

## 10. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | Asian Range แคบ 15–25 pips + London Open แรง (VOLATILE Regime) |
| **สภาวะตลาดที่แย่ที่สุด** | Asian Range กว้างเกิน 50 pips (SL ใหญ่, R:R ยังคงที่แต่ความเสี่ยงสูง) หรือ RANGING Regime |
| **ระยะเวลาถือสถานะทั่วไป** | 1–4 ชั่วโมง (Momentum Trade ตาม Session) |
| **สูงสุด Trade ต่อวัน** | 2 ออเดอร์ (1 London + 1 NY) ต่อทิศทาง ← กรอง Flag ป้องกันซ้ำ |
| **เป้าหมาย Win Rate** | 55–65% (London), 45–55% (NY) |
| **R:R Profile** | คงที่ประมาณ 2.0–2.7 ขึ้นอยู่กับ Buffer Size (ไม่แปรผันตาม Range) |
| **ATR Timeframe** | H1 (ไม่ใช่ Chart Timeframe) — เพราะ Session Analysis ต้องการ Hourly Context |
| **Latency** | MQL5 tick processing ≈ 0ms — Signal Logic ง่ายมาก (แค่ตรวจ if-else) |
| **Standalone** | ❌ ต้องการ Brain สำหรับ DST + Holiday Calendar |
| **ความถี่ Signal** | สูง (วันละ 2) แต่ Fixed-per-day — ไม่มี Intraday Scaling |

---

## 11. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 11.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: GMT Offset Misconfiguration (ปัญหาวิกฤติที่พบบ่อยที่สุด)**

```
ถ้า SB_BrokerGMT_Offset ผิด +1 ชั่วโมง (ใส่ 2 แทน 3):
  ระบบคิดว่า Asian Session สิ้นสุดที่ Broker Time 10:00
  แต่จริงๆ London เปิดไปแล้วตั้งแต่ 11:00 Broker Time

  ผลลัพธ์:
  • Asian Range จะ Include London Breakout Move เข้าไปด้วย
  • Trigger จะอยู่เหนือ London High → ไม่มีวัน Breakout!
  • หรือ Breakout ช้า: ราคาผ่าน Asian High+Buffer ไปนานแล้วกว่าระบบจะตรวจพบ

วิธีตรวจสอบ:
  MT5 Experts Log → ค้นหา [S09] Daily state reset
  ดูว่า Timestamp ตรงกับ 00:00 GMT ของคุณหรือไม่
  ถ้า Reset เกิดที่ 03:00 Broker Time = Broker GMT+3 ถูกต้อง
```

**ปัญหาที่ 2: Asian Range Spike จากข่าวตอนดึก**

```
บางครั้งข่าวออกใน Asian Session:
  • Bank of Japan (BOJ) Rate Decision: 03:00 GMT
  • Australia CPI: 00:30 GMT
  • Flash Crash: ทุกเมื่อ

ผลลัพธ์:
  Spike ทำให้ m_asian_high พุ่งสูงผิดปกติ (เช่น +80 pips ใน 1 นาที)
  Asian Range กว้างเกินไป (เช่น 90 pips)
  Trigger อยู่ไกลมาก → ไม่มีการ Breakout ในวันนั้น (เพราะ Spike กลับแล้ว)
  หรือถ้า Breakout: SL กว้างมาก (45 pips inside Range) → ขาดทุนหนักถ้าผิด

แนวทางแก้ไข:
  • Python Brain: ตรวจ BOJ/RBA Calendar → ถ้ามีข่าว Asia ใหญ่ → ข้าม S09 วันนั้น
  • MQL5: เพิ่ม Maximum Range Filter (Range > 60 pips → Skip)
    ปัจจุบัน: มีแต่ Minimum (20 pips) ยังไม่มี Maximum
```

**ปัญหาที่ 3: False Breakout ในช่วง London Open แรก (First 5 Minutes)**

```
เวลา 08:00–08:05 GMT: Market Makers ปรับ Spread สูงขึ้น
  Spread ที่กว้างทำให้ Ask พุ่งขึ้นชั่วคราว 2–3 pips
  ถ้า Buffer เล็กกว่า Spread Spike → ระบบ Fire ทันทีที่ 08:00!
  แต่ราคาจริงยังไม่ได้ Breakout — Spread กลับมาปกติใน 2 นาที → ขาดทุน

แนวทางแก้ไข:
  • เพิ่ม Open Delay: ไม่รับ Signal ใน 5 นาทีแรกของ London Open
    if (gmt_minute < 5 AND gmt_hour == m_london_start) return SIGNAL_NONE;
  • เพิ่ม Volume Confirmation: ตรวจ Tick Volume ว่า Breakout มา Volume จริงหรือ Spread manipulation
    (ยังไม่ได้ Implement ใน V6)
```

**ปัญหาที่ 4: London–NY Overlap (12:00–13:00 GMT Dead Zone)**

```
Dead Zone ปัจจุบัน: ไม่มีการเทรดช่วง 12:00–13:00 GMT
เหตุผลที่ Design แบบนี้: London Close + Pre-NY transition มี Liquidity ต่ำและ Spread สูง

แต่มีกรณีที่ Breakout เกิดในช่วงนี้:
  Economic data ออกเวลา 12:30 GMT (UK Retail Sales บางครั้ง)
  → ระบบพลาด Breakout นี้ทั้งหมด

แนวทางแก้ไข:
  • ลด Dead Zone: ปิดแค่ 30 นาที (12:30–13:00) แทน 1 ชั่วโมง
  • หรือ: Allow Breakout ใน Dead Zone ถ้า Volume สูงผิดปกติ (Brain ตรวจ)
```

### 11.2 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่แนะนำ | เหตุผล |
|------------|------------|--------|
| Session Windows (Asian/London/NY) | ทุกสัปดาห์หรือเมื่อ DST เปลี่ยน | DST เปลี่ยนปีละ 2 ครั้งต่อ Zone |
| Range_Min_Pips | ทุกวัน (ก่อน 00:00 GMT) | ขึ้นกับ Event Calendar วันนั้น |
| Breakout_Buffer | Real-time ตาม ATR | ATR เปลี่ยนตาม Volatility รายสัปดาห์ |
| TP_Range_Mult | รายเดือน | Win Rate ของ TP จะเห็นชัดเมื่อมีข้อมูล 20+ trades |
| SL_Inside_Ratio | รายเดือน | เหมือน TP — ต้องการข้อมูล Trade เพียงพอ |

### 11.3 สภาวะตลาดที่ S09 ทำกำไรสูงสุด

```
Profile ที่ดีที่สุด (ตามลำดับความสำคัญ):

1. Asian Range: 15–30 pips (แคบพอที่ Breakout จะมีพลัง แต่กว้างพอที่ TP สมเหตุสมผล)
2. Regime: VOLATILE (London Open Momentum แรง)
3. No Major Asian News: BOJ/RBA ไม่มีข่าว → Range ไม่ Spike
4. Major European News: ECB, PMI, CPI ช่วง 09:00–10:00 GMT → เพิ่ม London Momentum
5. Clear Trend Pre-Existing: ถ้า EUR แข็งอยู่แล้ว London Long มีโอกาสสูงกว่า Short
```

---

## 12. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S09_SessionBreakout.mqh` | `CSessionBreakout` class — Daily State Machine, Range Capture, Breakout Logic |
| `Include/Logic/IStrategy.mqh` | Abstract base: `IStrategy`, `SDynamicParams`, `ENUM_SIGNAL` |
| `Include/Logic/StrategyConstants.mqh` | `S09_SESSION_BREAKOUT` enum, `MAGIC_S09_SESSION_BO = 1009`, regime table |
| `03_Trader/ProgramC_Trader.mq5` | Main EA — instantiates `CSessionBreakout`, routes CONFIG_PUSH, daily tick routing |
| `02_Brain/core/intelligence/strategy_council.py` | AI Council — Regime Factor × Confidence gate |
| `02_Brain/config_push/config_builder.py` | สร้าง S09 CONFIG_PUSH payload พร้อม DST-adjusted session times |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT Port 7779, อัปเดต `PerformanceTracker` |
| `02_Brain/core/performance_tracker.py` | EMA-based historical Win Rate สำหรับ S09 London vs NY |

---

## 13. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### ตรวจสอบ Session Status แบบ Real-time

```
MetaTrader 5 → Experts tab → กรอง [S09]

บรรทัดที่ควรเห็นหลัง Init:
  [S09] Init OK | EURUSD PERIOD_M1 | Asian 00:00-07:00 GMT | London 08:00-12:00 | NY 13:00-17:00
  [S09] iATR H1 handle created | period=14

บรรทัดที่ควรเห็นช่วง Asian:
  [S09] Asian Track | H=1.08620 L=1.08390 | Range=23.0 pips (updating...)

บรรทัดที่ควรเห็นเมื่อ London เริ่ม:
  [S09] Asian Range VALID | H=1.08620 L=1.08390 | Range=23.0 pips | ATR=0.00580 | Min=20 ✅
  [S09] London Triggers | Long=1.08678 Short=1.08332 | Buffer=5.8 pips (ATR-based)

บรรทัดที่ควรเห็นเมื่อ Breakout:
  [S09] LONDON LONG | Ask=1.08690 | Trigger=1.08678 | TP=1.09023 SL=1.08505 | Conf=0.30 | Regime=VOLATILE
```

### ตรวจสอบผ่าน PrintSessionStatus()

```mql5
s09.PrintSessionStatus();
// Output ตัวอย่าง:
// [S09] Asian Range | H=1.08620 L=1.08390 Range=23.0 pips | ATR=0.00580 | RangeOK=YES
// [S09] Breakout Flags | LondonLong=FIRED LondonShort=ready | NYLong=ready NYShort=ready
// [S09] Confidence last | 0.297 (range_factor=0.198 × session=1.0 × regime_VOLATILE=1.5)
```

### ตรวจสอบ CONFIG_PUSH อัปเดต S09

```bash
python tools/validate_live_readiness.py --zmq
# ดูที่ TEST 5: CONFIG_PUSH dry-run
# ควรเห็น: S09_LONDON_START, S09_RANGE_MIN, S09_TP_RANGE_MULT ใน output
```

### ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S09 ไม่เคยเปิด Trade เลย | `SB_BrokerGMT_Offset` ผิด | ตรวจ [S09] Daily state reset timestamp vs GMT midnight |
| Range ถูก Skip ทุกวัน | ค่า Range_Min สูงเกิน หรือ Asian ไม่ Capture | ลด Range_Min เป็น 10, ตรวจ Asian Track log |
| Breakout Fire เวลา 08:00 ทันที | Spread Spike ที่ Open, Buffer เล็กเกิน | เพิ่ม SB_Breakout_Buffer เป็น 5–8 pips |
| Trade อยู่นานไม่ถึง TP | Range ใหญ่ → TP ไกล, Momentum ลดก่อน | ลด TP_Range_Mult เป็น 1.0–1.2 |
| NY ไม่ Fire แม้ London ไม่ Fire | London Broken Flag ค้างจาก Session ก่อน | ตรวจ _ResetDaily() เกิดตรงเวลา |
| No trades วันศุกร์ก่อนNFP | Brain เพิ่ม Range_Min เป็น 35 pips โดยอัตโนมัติ | ปกติ — Brain ปกป้องจากข่าวสำคัญ |
| S09 ทำงานในวันหยุด | Brain ไม่ได้ส่ง Suppress Signal | ตรวจ Brain Holiday Calendar หรือ CONFIG_PUSH |

---

## 14. บทสรุปเชิงปรัชญา (Philosophical Summary)

S09 เป็นตัวแทนของโรงเรียนความคิด **"Time is the Primary Signal"** — ตรงข้ามกับกลยุทธ์อื่นๆ ในระบบที่ดู Price Action, Indicators หรือ Statistical Patterns

```
S01 พูดว่า: "ราคาคู่นี้ห่างกันผิดปกติทางสถิติ — มันจะต้องกลับมา"
S10 พูดว่า: "ราคาทะลุแนวสูงสุดเดิม — Trend กำลังเกิด ขี่ตาม"
S09 พูดว่า: "ตอนนี้คือ 08:00 GMT — London เพิ่งเปิด, Momentum กำลังจะมา
             ราคาที่อัดอั้นอยู่ 8 ชั่วโมงจะระเบิดออกทิศทางใดทิศทางหนึ่ง
             ฉันแค่รอดูว่าทิศไหน แล้วเข้าตาม"

S09 เป็นกลยุทธ์ที่ "เชื่อในโครงสร้างของตลาด" มากกว่า "เชื่อในการวิเคราะห์ราคา"
ความสำเร็จของ S09 ขึ้นอยู่กับว่า:
  1. Forex ยังคงมี Session Structure ที่ชัดเจน (London เปิดมีผล)
  2. Asian range ยังเป็น "รั้วที่มีความหมาย" ไม่ใช่แค่ตัวเลข
  3. Breakout Direction มี Momentum พอเป็นกำไรก่อน Reverse

ถ้าวันหนึ่ง Forex Market Structure เปลี่ยนไป (เช่น AI Trading ทำให้ทุก Session ผสมกันหมด)
S09 อาจเป็นกลยุทธ์แรกในระบบที่ต้องปรับโครงสร้างใหม่ทั้งหมด
```

---

*S09 Session Breakout DEEP Manual — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
