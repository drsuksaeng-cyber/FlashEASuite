# S01 — Statistical Arbitrage (Pair Trading)
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-27 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S01 | รหัสอ้างอิงลำดับที่หนึ่งในระบบมัลติกลยุทธ์ของ FlashEASuite V2 ตัวเลข "01" ไม่ได้หมายความว่ากลยุทธ์นี้ง่ายที่สุด แต่หมายความว่าเป็นกลยุทธ์ต้นแบบที่ออกแบบมาเพื่อพิสูจน์แนวคิดหลักของสถาปัตยกรรม Hybrid ก่อนที่จะขยายไปสู่ S02-S16 |
| **Enum Name** | `S01_STAT_ARB` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) ค่า enum index = 0 (0-based array index) หมายความว่าเป็น element แรกสุดของ `g_strategy_table[16]` |
| **Enum Index** | 0 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่านฟังก์ชัน `GetStrategyInfo(S01_STAT_ARB)` |
| **ชื่อ** | Statistical Arbitrage (Stat Arb) | การทำกำไรจากส่วนต่างทางสถิติโดยอาศัยหลักการ Mean Reversion ของสินทรัพย์คู่ที่มีความสัมพันธ์เชิงบูรณาการ |
| **ประเภท** | Hybrid — Python Brain + MQL5 Trader (`CAT_HYBRID`) | ระบบลูกผสมที่แยกส่วนการคำนวณสถิติหนัก (Python) ออกจากส่วนการส่งคำสั่งแบบ Real-time (MQL5) เพื่อให้ได้ทั้งความแม่นยำของ Data Science และความเร็วของการ Execution |
| **Standalone Capable** | ✅ Yes | รองรับการทำงานในโหมดอิสระเมื่อขาดการเชื่อมต่อกับเซิร์ฟเวอร์ Python โดยใช้ค่า Beta = 1.0 และพารามิเตอร์ล่าสุดที่บันทึกไว้ใน `standalone_config.dat` ซึ่งเขียนทับทุกครั้งที่ได้รับ CONFIG_PUSH สำเร็จ |
| **Preferred Regime** | RANGING (`REGIME_RANGING`) | สภาวะตลาดที่ราคาแกว่งตัวในกรอบ (Sideways) จะส่งผลให้ค่า Z-Score กลับเข้าสู่จุดสมดุลได้บ่อยและรวดเร็วที่สุด ทำให้กลยุทธ์นี้ทำกำไรได้อย่างสม่ำเสมอ |
| **Alt Regime** | None (`REGIME_UNKNOWN`) | ไม่มี Regime รองที่เหมาะสม — S01 เป็นกลยุทธ์เฉพาะสภาวะ Ranging เท่านั้น |
| **Poor Regimes** | TRENDING, VOLATILE | สภาวะตลาดที่มีทิศทางรุนแรงหรือผันผวนสูง อาจทำให้ความสัมพันธ์เชิงบูรณาการ (Cointegration) พังทลาย ส่งผลให้ Spread วิ่งออกไปเรื่อยๆ แทนที่จะกลับมา |
| **Regime Factor** | RANGING=1.5, SQUEEZE=1.2, TRENDING=0.6, VOLATILE=0.3 | ตัวคูณที่ Python Brain ใช้ปรับค่า Confidence ตามสภาวะตลาด ออกแบบโดยอิงจากข้อมูลย้อนหลังว่ากลยุทธ์นี้ทำกำไรได้ดีแค่ไหนในแต่ละสภาวะ |
| **MQL5 Class** | `CStatArb` | คลาสหลักในภาษา MQL5 ที่ควบคุมตรรกะการคำนวณ Z-Score แบบ Tick-by-tick และการส่งคำสั่งในระดับมิลลิวินาที ไฟล์: `Include/Logic/Strategies/S01_StatArb.mqh` |
| **Python Analyzer** | `S01StatArbAnalyzer` | โมดูลบน Python (ไฟล์: `02_Brain/strategies/s01_stat_arb_analyzer.py`) ทำหน้าที่ประมวลผลการทดสอบ Cointegration และคำนวณค่า OLS Beta ทุกรอบ Optimization Cycle |
| **Magic Number** | 1001 (`MAGIC_S01_STAT_ARB`) | หมายเลขเอกลักษณ์ที่ MQL5 ใช้แท็กออเดอร์ทั้งหมดที่เปิดโดย S01 ป้องกันการปะปนกับออเดอร์จาก S02-S16 ที่รันพร้อมกัน |
| **Family** | Pairs/Neutral | กลุ่มกลยุทธ์ที่สร้างพอร์ตโฟลิโอเป็นกลาง (Market Neutral) ไม่เดาทิศทางตลาด แต่เดาการกลับมาบรรจบกันของราคาคู่สินทรัพย์ |
| **Version** | 6.00 | สถาปัตยกรรม V6 ที่ออกแบบใหม่ทั้งหมดจาก V5 โดยเน้นหลักการ "Smart Server, Powerful Client" |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S01 เป็นกลยุทธ์ **Pair Trading** หรือที่เรียกในวงวิชาการว่า **Statistical Arbitrage** โดยทำการเทรดคู่สินทรัพย์ 2 ชนิดที่มีความสัมพันธ์เชิงสถิติอย่างลึกซึ้ง (เช่น EURUSD กับ GBPUSD) พร้อมกันในทิศทางตรงข้าม เพื่อสร้างพอร์ตโฟลิโอที่ **ไม่มีทิศทาง (Market Neutral)** — หมายความว่าพอร์ตนี้ทำกำไรได้โดยไม่ขึ้นอยู่กับว่าตลาดจะขึ้นหรือลง แต่ขึ้นอยู่กับว่า "ระยะห่าง" ระหว่างคู่สินทรัพย์จะกลับมาสู่ค่าปกติหรือไม่

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมต้องชื่อ "Statistical Arbitrage"?

**ความหมายดั้งเดิมของ Arbitrage:**
คำว่า *Arbitrage* ในทางการเงินดั้งเดิมหมายถึงการซื้อสินทรัพย์ชิ้นเดียวกันในตลาดหนึ่งและขายในอีกตลาดหนึ่งพร้อมกัน เพื่อทำกำไรจากความแตกต่างของราคาที่เกิดขึ้นชั่วคราว (Price Discrepancy) ซึ่งในทางทฤษฎีถือว่าเป็นการทำกำไรที่ **ไร้ความเสี่ยงอย่างแท้จริง (Pure Risk-Free Profit)** เพราะการซื้อและขายเกิดขึ้นพร้อมกัน ณ ราคาที่กำหนดล่วงหน้า

**เหตุใดจึงต้องเป็น "Statistical" Arbitrage:**
อย่างไรก็ตาม ในตลาดการเงินยุคปัจจุบันที่ระบบซื้อขายเชิงอัลกอริทึมมีความเร็วสูงถึงระดับ Nanosecond โอกาส Pure Arbitrage แบบดั้งเดิมนั้นแทบจะไม่มีเหลืออยู่แล้ว เพราะกลไกตลาดจะปรับราคาให้เท่ากันภายในเวลาไม่กี่มิลลิวินาที ดังนั้น S01 จึงใช้แนวทางที่ชาญฉลาดกว่า นั่นคือแทนที่จะหาสินทรัพย์เดียวกันสองราคา กลยุทธ์นี้มองหา **คู่สินทรัพย์ที่แตกต่างกันแต่มีพฤติกรรมราคาที่ผูกพันกันอย่างแนบแน่น (Cointegrated Pair)** และรอให้ "ระยะห่าง" ระหว่างสองตัวนั้นเบี่ยงเบนออกไปจากค่าเฉลี่ยอย่างมีนัยสำคัญทางสถิติ จากนั้นเปิดสถานะเดิมพันว่ามันจะกลับมา

คำว่า **"Statistical"** หมายความว่า การทำกำไรนี้ไม่ได้รับประกัน 100% เหมือน Pure Arbitrage แต่มีความน่าจะเป็นสูงมากตามหลักสถิติ ซึ่งเมื่อทำซ้ำหลายครั้งในระยะยาว จะสร้างผลตอบแทนที่เป็นบวกอย่างสม่ำเสมอ

---

### 1.3 ธรรมชาติของการกลับคืนสู่ค่าเฉลี่ย (The Law of Mean Reversion)

**พื้นฐานทางเศรษฐศาสตร์:**
สินทรัพย์ที่มีความสัมพันธ์สูง เช่น EURUSD และ GBPUSD มักได้รับผลกระทบจากปัจจัยมหภาคเดียวกัน เช่น นโยบายการเงินของธนาคารกลางสหรัฐฯ (Federal Reserve), ดัชนีความเชื่อมั่นทางเศรษฐกิจ (Economic Sentiment) หรือ Risk-On/Risk-Off ของนักลงทุนทั่วโลก

เมื่อ USD อ่อนค่าลงจากข่าว Non-Farm Payrolls ที่อ่อนแอกว่าคาด ทั้ง EURUSD และ GBPUSD ต่างก็ควรปรับตัวสูงขึ้นในสัดส่วนที่ใกล้เคียงกัน เพราะทั้งสองมีตัวหารเดียวกันคือ USD

หาก EURUSD ขึ้นแรงกว่า GBPUSD มากเกินไปในช่วงเวลาสั้นๆ นั่นคือสัญญาณว่าเกิด **"ความไม่สมดุลชั่วคราว (Temporary Disequilibrium)"** ซึ่งกลไกตลาดจะแก้ไขตัวเองผ่านการซื้อขายของ Arbitrageur รายอื่นๆ ในตลาดด้วย ทำให้ราคากลับมาสมดุล ระบบ S01 คือการ "ขี่คลื่น" ของกระบวนการแก้ไขตัวเองของตลาดนี้

**มุมมองทางคณิตศาสตร์:**
เมื่อพิสูจน์ด้วย Engle-Granger Cointegration Test แล้วว่าคู่สินทรัพย์มีความสัมพันธ์เชิงบูรณาการ (Cointegrated) นั่นหมายความว่าแม้ราคาแต่ละตัวจะเป็น Random Walk (Non-Stationary) แต่ **ส่วนต่าง (Spread)** ระหว่างทั้งสองจะมีคุณสมบัติ Stationary ซึ่งหมายความว่า Spread มีค่าเฉลี่ยและความแปรปรวนที่คงที่ในระยะยาว และเมื่อใดที่ Spread เบี่ยงเบนออกไป มันจะต้องกลับมาหาค่าเฉลี่ยนั้นในที่สุดตามทฤษฎี Mean Reversion

---

### 1.4 กรณีศึกษาจริง (Case Study — 27 กุมภาพันธ์ 2026)

**สถานการณ์:** เวลา 09:00 น. GMT ในช่วง London Session Open ซึ่งเป็นช่วงที่ Liquidity สูงที่สุดของวัน

```
ราคาตลาดก่อนเหตุการณ์:
  EURUSD (EU) = 1.08500  (ค่า Bid ณ 08:59:50)
  GBPUSD (GU) = 1.26500  (ค่า Bid ณ 08:59:50)

Spread ปกติ (โดยประมาณ):
  Spread = EU - β × GU
         = 1.08500 - 0.8 × 1.26500
         = 1.08500 - 1.01200
         = 0.07300  (ค่าเฉลี่ยปกติ)

Z-Score ณ เวลานั้น = (0.07300 - 0.07300) / StdDev = 0.0  (สมดุลสมบูรณ์)
```

**เหตุการณ์:** เวลา 09:00:12 น. Bloomberg รายงานข้อมูล Euro Area PMI ที่สูงกว่าคาดมากจน EUR ได้รับแรงซื้อทันที แต่ข่าวดังกล่าวไม่เกี่ยวข้องกับ GBP โดยตรง

```
ราคาตลาดหลังเหตุการณ์ 45 วินาที:
  EURUSD (EU) = 1.09000  (ขึ้น +50 pips ภายใน 45 วินาที)
  GBPUSD (GU) = 1.26530  (ขึ้นเพียง +3 pips — แทบไม่ขยับ)

Spread ใหม่:
  Spread = 1.09000 - 0.8 × 1.26530
         = 1.09000 - 1.01224
         = 0.07776  (เพิ่มขึ้นอย่างผิดปกติ)

ค่าเฉลี่ย (MA20) ของ Spread ยังคงอยู่ที่ 0.07300
StdDev ของ Spread = 0.00238

Z-Score ใหม่:
  Z = (0.07776 - 0.07300) / 0.00238 = +2.00
```

**การตัดสินใจของระบบ:** Z-Score = +2.00 ≥ EntryZ (2.0) → ระบบส่งสัญญาณ `SIGNAL_SELL`

```
คำสั่งที่ระบบเปิด:
  SELL EURUSD (Short EU ตัวที่แพงเกินจริง)  Lot = 0.10
  BUY  GBPUSD (Long GU ตัวที่ถูกเกินจริง)  Lot = 0.068

  (Lot GU คำนวณจาก: 0.10 × 0.8 × (1.265 / 1.09) ≈ 0.0927)
  (ปัดลงตาม Lot Step ของโบรกเกอร์ = 0.09)
```

**ผลลัพธ์หลังจาก 3 ชั่วโมง (เวลา 12:00 น.):**
```
EURUSD ลงมาที่ 1.08750  (ลง -25 pips จาก 1.09000)
GBPUSD ขึ้นมาที่ 1.26590  (ขึ้น +6 pips จาก 1.26530)

Spread ใหม่:
  = 1.08750 - 0.8 × 1.26590
  = 1.08750 - 1.01272
  = 0.07478

Z-Score ปัจจุบัน = (0.07478 - 0.07300) / 0.00238 = +0.748

Z-Score ต่ำกว่า ExitZ (0.2)? ยังไม่ถึง — ระบบยัง Hold
```

**ผลลัพธ์สุดท้าย (เวลา 14:30 น.):**
```
EURUSD ลงมาที่ 1.08520  (ลง -48 pips จาก Entry 1.09000)
GBPUSD อยู่ที่ 1.26620   (ขึ้น +9 pips จาก Entry 1.26530)

Spread = 1.08520 - 0.8 × 1.26620 = 1.08520 - 1.01296 = 0.07224
Z-Score = (0.07224 - 0.07300) / 0.00238 = -0.319

|Z-Score| = 0.319 > ExitZ (0.2) → ยังไม่ออก (ใกล้แล้ว)

เวลา 15:00 น.:
Spread = 0.07290 → Z = -0.042 → |Z| < 0.2 → ปิดสถานะ!

กำไรสุทธิ:
  EURUSD Short: เข้า 1.09000 ออก 1.08520 = +48 pips × 0.10 lot = +$48
  GBPUSD Long:  เข้า 1.26530 ออก 1.26600 = +7 pips × 0.09 lot = +$6.30
  รวมกำไร: +$54.30 ใน 6 ชั่วโมง โดยไม่เดาทิศทาง
```

**บทเรียนจากกรณีนี้:** กำไรเกิดจาก "การปิดช่องว่าง" ของ Spread ไม่ใช่จากการเดาว่าตลาดจะขึ้นหรือลง แม้ EURUSD จะลงน้อยมาก ระบบยังกำไรได้เพราะ GBPUSD ก็ขึ้นมาช่วยชดเชย

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 สมการ Spread และการคืนสู่ค่าเฉลี่ย (Spread & Mean Reversion)

**นิยามสมการ Spread:**
หัวใจทางคณิตศาสตร์ของ S01 คือการสร้าง **อนุกรมเวลาใหม่** ที่เรียกว่า Spread หรือ Residual Series ซึ่งนำเอาราคาของสินทรัพย์ A ลบด้วยราคาของสินทรัพย์ B ที่ถูกปรับสัดส่วนด้วยค่า Beta แล้ว:

```
Spread(t) = Price_A(t) − β × Price_B(t)
```

**ความหมายของแต่ละองค์ประกอบ:**

- **`Price_A(t)`** — ราคาของสินทรัพย์หลัก (Primary Asset) ณ เวลา t เช่น ราคา Ask ของ EURUSD ณ เวลานั้น หน่วยเป็น Quote Currency (USD)
- **`Price_B(t)`** — ราคาของสินทรัพย์รอง (Secondary Asset) ณ เวลา t เช่น ราคา Bid ของ GBPUSD หน่วยเป็น USD เช่นกัน
- **`β (Beta / Hedge Ratio)`** — ตัวคูณปรับสัดส่วน คำนวณโดยวิธี OLS (Ordinary Least Squares) บน Python Brain ทุกรอบ Optimization Cycle มีความหมายว่า "สำหรับทุกๆ 1 หน่วยที่ Price_A เปลี่ยน Price_B ควรเปลี่ยนตาม β หน่วย"
- **`Spread(t)`** — ส่วนต่างที่ปรับสัดส่วนแล้ว ถ้า Cointegration เป็นจริง Spread จะมีคุณสมบัติ Stationary

**ใน Standalone Mode:** β ถูกตั้งค่าเป็น 1.0 เพื่อความเรียบง่าย ซึ่งหมายความว่าสมมติว่าทั้งสองสินทรัพย์มีน้ำหนักเท่ากัน ซึ่งเป็นการประมาณที่ยอมรับได้สำหรับคู่เงินที่มีราคาใกล้เคียงกัน แต่จะมีความแม่นยำน้อยกว่า Server Mode ที่ใช้ค่า β จากการคำนวณจริง

---

### 2.2 การคำนวณ Hedge Ratio ด้วย OLS (Ordinary Least Squares Beta)

**นิยามทางคณิตศาสตร์:**
OLS Beta คือค่าความชันของเส้นถดถอยเชิงเส้น (Linear Regression Line) ที่ฟิตความสัมพันธ์ระหว่าง `Price_A` และ `Price_B` โดยมีสูตรดังนี้:

```
β = Cov(Price_A, Price_B) / Var(Price_B)

โดย:
  Cov(A, B) = (1/N) × Σ[(A_i - Ā)(B_i - B̄)]
  Var(B)    = (1/N) × Σ[(B_i - B̄)²]
  Ā, B̄     = ค่าเฉลี่ยของ A และ B ตามลำดับ
  N         = จำนวนแท่งราคาที่ใช้คำนวณ (lookback_bars = 100)
```

**ตัวอย่างการคำนวณจริง:**
สมมติมีข้อมูล OHLC 100 แท่ง (Close Price) ของ EURUSD และ GBPUSD:

```
กำหนดให้:
  Cov(EU, GU) = 0.000312  (EU และ GU เคลื่อนไปในทิศทางเดียวกัน)
  Var(GU)     = 0.000389  (GU มีความแปรปรวนสูงกว่า EU เล็กน้อย)

β = 0.000312 / 0.000389 = 0.8021 ≈ 0.80

ความหมาย: เมื่อ GU เคลื่อนที่ 1 pip EU ควรเคลื่อนที่ 0.80 pip
           หาก EU เคลื่อนที่มากกว่า 0.80 pip → เกิด Divergence
```

**เหตุใด Beta จึงต้องอัปเดตบ่อย:**
ความสัมพันธ์ระหว่างคู่เงินไม่ได้คงที่ตลอดไป ช่วงที่ UK กำลังเจรจา Brexit หรือในช่วงวิกฤติ Eurozone ค่า Beta อาจเปลี่ยนแปลงอย่างมีนัยสำคัญภายในไม่กี่ชั่วโมง ดังนั้น Python Brain จึงต้องคำนวณ Beta ใหม่ทุก 30-60 วินาที

---

### 2.3 การปรับมาตรฐาน Z-Score (Z-Score Normalization)

**ปัญหาของ Spread ดิบ:**
ค่า Spread ดิบมีหน่วยเป็นราคาสินทรัพย์ (เช่น 0.073) ซึ่งเปรียบเทียบข้ามช่วงเวลาได้ยาก เพราะระดับราคาเปลี่ยนไปตลอด การจะบอกว่า Spread = 0.073 นั้น "มากเกินไป" หรือไม่ ต้องรู้ว่าปกติมันอยู่ที่เท่าไหร่และแกว่งแค่ไหน

**Z-Score คือคำตอบ:**
```
Z-Score(t) = (Spread(t) − MA(t)) / StdDev(t)

โดย:
  MA(t)     = ค่าเฉลี่ยเคลื่อนที่ (SMA) ของ Spread ในช่วง N แท่งล่าสุด
              (N = StatArb_Period = 20 โดย default)
  StdDev(t) = ค่าเบี่ยงเบนมาตรฐานของ Spread ในช่วง N แท่งเดียวกัน
```

**การแปลความหมาย Z-Score:**

| ช่วง Z-Score | ความหมาย | การกระทำของระบบ |
|------------|----------|----------------|
| −1.0 ถึง +1.0 | Normal Zone — Spread อยู่ในระดับปกติ | ไม่มีการกระทำใดๆ (SIGNAL_NONE) |
| +1.0 ถึง +2.0 | Pre-Signal Zone — Spread เริ่มแยกตัว | ติดตามสถานการณ์อย่างใกล้ชิด |
| **> +2.0** | **Entry Zone — Spread สูงผิดปกติ (2 SD)** | **SIGNAL_SELL (Short A / Long B)** |
| ≈ 0.0 (< 0.2) | Exit Zone — Mean Reversion สำเร็จ | SIGNAL_EXIT (ปิดกำไร) |
| **> +3.0** | **Danger Zone — Spread สูงผิดปกติมาก (3 SD)** | **Stop Loss (ความสัมพันธ์อาจพัง)** |
| < −2.0 | Entry Zone — Spread ต่ำผิดปกติ | SIGNAL_BUY (Long A / Short B) |
| < −3.0 | Danger Zone — ด้านลบ | Stop Loss |

**เหตุผลที่เลือก ±2.0 เป็น Threshold:**
ในการแจกแจงแบบปกติ (Normal Distribution) ช่วง ±2.0 Standard Deviation ครอบคลุมข้อมูล 95.45% ของทั้งหมด ซึ่งหมายความว่ามีโอกาสเพียง 4.55% ที่ Spread จะเบี่ยงเบนไปไกลกว่า 2.0 SD โดยบังเอิญ สถิติระบุว่าการเบี่ยงเบนในระดับนี้มีโอกาสสูงมากที่จะเป็น "Temporary Shock" ที่จะกลับมาไม่ใช่ "Structural Shift" ที่ถาวร

---

### 2.4 การทดสอบ Cointegration แบบ Engle-Granger (Academic Foundation)

**พื้นฐานทฤษฎี:**
กลยุทธ์ Pair Trading จะทำงานได้ก็ต่อเมื่อสินทรัพย์คู่นั้นมีความสัมพันธ์ประเภทพิเศษที่เรียกว่า **Cointegration (ความสัมพันธ์เชิงบูรณาการ)** ซึ่งแตกต่างจาก Correlation ธรรมดาอย่างมีนัยสำคัญ:

- **Correlation (สหสัมพันธ์ธรรมดา):** บอกว่าสินทรัพย์ A และ B เคลื่อนที่ไปทิศทางเดียวกันในระยะสั้น แต่ไม่ได้การันตีว่าพวกมันจะกลับมาหากันในระยะยาว
- **Cointegration (ความสัมพันธ์เชิงบูรณาการ):** บอกว่ามี "แรงดึง" ระยะยาวที่ผูกสินทรัพย์ทั้งสองไว้ด้วยกัน ถ้าแยกออกจากกันในระยะสั้น จะมี Mean-Reverting Force ดึงกลับมา

**ขั้นตอนการทดสอบ Engle-Granger:**

```
ขั้นตอนที่ 1: ทำ OLS Regression
  Regress Price_A on Price_B: Price_A = α + β × Price_B + ε
  บันทึก Residuals: ε(t) = Price_A(t) - α - β × Price_B(t)

ขั้นตอนที่ 2: ทดสอบ Unit Root บน Residuals
  ใช้ ADF Test (Augmented Dickey-Fuller) บน ε(t)
  H₀: ε(t) มี Unit Root (Non-Stationary = ไม่ Cointegrated)
  H₁: ε(t) เป็น Stationary (= Cointegrated)

ขั้นตอนที่ 3: แปลผล p-value
  p < 0.05: Reject H₀ → Cointegration สูง → coint_score = 0.35
  p < 0.10: Weak evidence → coint_score = 0.20
  p ≥ 0.10: Cannot reject H₀ → ไม่มี Cointegration → ข้าม S01
```

**ทำไม Python จึงต้องทำแทน MQL5:**
การทดสอบ Engle-Granger ต้องใช้ไลบรารี `statsmodels` ของ Python ซึ่ง MQL5 ไม่รองรับ นอกจากนี้การ Regression บนข้อมูล 100 แท่งยังต้องการ Matrix Algebra ที่ MQL5 ไม่มีคลาสพร้อมใช้ งาน Python จึงถูกออกแบบมาทำ "งานหนักทางสถิติ" นี้บน Server ก่อนส่งผลลัพธ์ (Beta + Confidence) มาให้ MQL5 ทำ Execution แทน

---

### 2.5 การคำนวณ Lot เพื่อความเป็นกลางทางการเงิน (Dollar-Neutral Lot Sizing)

**เป้าหมาย:** ให้มูลค่าเงิน Dollar ที่เสี่ยงในฝั่ง Long และ Short เท่ากัน เพื่อให้ผลกำไร/ขาดทุนจากการเคลื่อนที่ของตลาดโดยรวม (Market Beta) หักล้างกัน

```
สูตรคำนวณ Lot_B จาก Lot_A ที่กำหนด:

Lot_B = Lot_A × β × (Price_A / Price_B)

ตัวอย่าง:
  Lot_A = 0.10 (EU), β = 0.80, Price_A = 1.09000, Price_B = 1.26500

  Lot_B = 0.10 × 0.80 × (1.09000 / 1.26500)
        = 0.10 × 0.80 × 0.8617
        = 0.10 × 0.6893
        = 0.0689

ปัดตาม Lot Step โบรกเกอร์: Lot_B ≈ 0.07
```

**เหตุผลที่ต้องคูณด้วย (Price_A / Price_B):**
เนื่องจาก 1 pip มีมูลค่าเป็นเงิน Dollar แตกต่างกันระหว่าง EURUSD และ GBPUSD การปรับสัดส่วนด้วยอัตราส่วนราคาช่วยให้ทั้งสองฝั่งมีมูลค่า Dollar Risk เท่ากัน ทำให้พอร์ตโฟลิโอเป็น Market Neutral อย่างแท้จริง

**เหตุผลที่ต้องออก Lot ขนาดใหญ่:**
เนื่องจาก Spread ของคู่เงินที่ Cointegrated กันนั้นมีความผันผวนต่ำมาก (โดยทั่วไป 10-30 pips ต่อวัน เทียบกับ EURUSD เดี่ยวที่อาจเคลื่อน 80-150 pips) หากใช้ Lot เล็กเกินไป กำไรจะไม่คุ้มค่า Commission และ Spread ของโบรกเกอร์ ระบบจึงต้องใช้ Lot ที่ใหญ่กว่าปกติ แต่ความเสี่ยงโดยรวมยังต่ำกว่าการเทรดหน้าเดียว เพราะเป็นการเดิมพันบน "ความนิ่งทางสถิติ" ไม่ใช่การเดาทิศทาง

---

## 3. สถาปัตยกรรมระบบและการแบ่งหน้าที่ (System Architecture)

### 3.1 ตารางแบ่งความรับผิดชอบ Python Brain vs MQL5 Trader

```
┌────────────────────────────────────────────────────────────────────────┐
│               S01 HYBRID ARCHITECTURE — ภาพรวมสถาปัตยกรรม              │
├──────────────────────────────┬─────────────────────────────────────────┤
│   PYTHON BRAIN (Server Side) │  MQL5 TRADER (Client Side)              │
│   ประมวลผลสถิติหนัก           │  Execute แบบ Real-time                  │
├──────────────────────────────┼─────────────────────────────────────────┤
│  ✅ Cointegration Test        │  ✅ Circular Spread Buffer               │
│     (Engle-Granger p-value)  │     (Rolling Window, ขนาด Period)       │
│                              │                                         │
│  ✅ OLS Beta Calculation      │  ✅ Z-Score Computation Per Tick         │
│     (Matrix Algebra)         │     (< 1ms latency)                     │
│                              │                                         │
│  ✅ Pearson Correlation       │  ✅ Entry/Exit Signal Generation         │
│     (Rolling 100 bars)       │     (SIGNAL_BUY/SELL/EXIT/NONE)         │
│                              │                                         │
│  ✅ Confidence Scoring        │  ✅ Lot Sizing via MM Method             │
│     (4-component composite)  │     (MM01-MM19 ตามที่ Brain กำหนด)     │
│                              │                                         │
│  ✅ Pair Selection            │  ✅ Order Placement                      │
│     (Scan best p-value pair) │     (Buy/Sell A และ B พร้อมกัน)         │
│                              │                                         │
│  ✅ Regime Adjustment         │  ✅ Standalone Fallback                  │
│     (×1.5/×0.6/×0.3)        │     (Beta=1.0 ถ้าไม่มีเซิร์ฟเวอร์)     │
│                              │                                         │
│  ✅ CONFIG_PUSH (Port 7778)   │  ✅ Trade Reporting (Port 7779)          │
│     (Beta, Period, EntryZ)   │     (ผลกำไร/ขาดทุนกลับไป Brain)        │
└──────────────────────────────┴─────────────────────────────────────────┘
```

**หลักการออกแบบ:** Python Brain ทำหน้าที่ "วิทยาศาสตร์" (คำนวณสถิติอย่างถูกต้องแม่นยำ) ส่วน MQL5 ทำหน้าที่ "วิศวกรรม" (Execute คำสั่งด้วยความเร็วสูงสุดและความน่าเชื่อถือสูงสุด) สถาปัตยกรรมแบบนี้ช่วยให้ระบบได้ประโยชน์ทั้งสองด้านโดยไม่ต้องแลกสิ่งใดสิ่งหนึ่ง

---

### 3.2 โครงสร้างข้อมูลใน MQL5: `SMMSelection` และการบริหาร MM

ใน `MMManager.mqh` ระบบเก็บข้อมูลการเลือก MM ของ S01 ในโครงสร้าง `SMMSelection`:

```cpp
struct SMMSelection
{
    int  default_mm;       // MM ที่ใช้ในสภาวะปกติ
                           // S01: MM04 (Kelly Criterion)
                           // เหตุผล: S01 มีประวัติเทรดสะสมจาก Pair Trading
                           //         ทำให้ Kelly มีข้อมูลพอคำนวณ Win Rate ได้แม่นยำ

    int  volatile_mm;      // MM ที่ใช้เมื่อตลาด VOLATILE หรือ SQUEEZE
                           // S01: MM07 (Percent Volatility)
                           // เหตุผล: ในช่วง VOLATILE Spread แกว่งมากกว่าปกติ
                           //         MM07 จะลด Lot ลงเมื่อ ATR สูง ป้องกัน Drawdown

    int  dd_mm;            // MM ที่ใช้เมื่อ Drawdown ≥ 10% (เสมอคือ MM10)
                           // S01: MM10 (DrawdownBased)
                           // เหตุผล: เมื่อ Portfolio ขาดทุนหนัก ต้องลด Exposure
                           //         MM10 มี 3-tier protection (50%/25%/min lot)

    int  active_mm;        // MM ที่กำลังใช้งานอยู่จริงในขณะนี้
                           // อาจเป็น Server Override จาก Brain

    bool server_override;  // true = Brain บังคับ MM เฉพาะ
                           // false = ให้ MMManager เลือกเองตาม Logic
};
```

**ลำดับความสำคัญในการเลือก MM (SelectMM Priority):**

```
ลำดับที่ 1 (สูงสุด): Standalone Mode หรือ ไม่มี Server
  → ใช้ MM01 (Fixed Conservative) ทันที
  → เหตุผล: MM01 ไม่ต้องการข้อมูลใดๆ นอกจาก Balance และ SL

ลำดับที่ 2: Server Override
  → Brain ส่ง mm_method ใน CONFIG_PUSH
  → ApplyConfig(idx, mm_id) → server_override = true
  → ใช้ mm_id ที่ Brain กำหนด

ลำดับที่ 3: Drawdown Emergency
  → AccountDrawdown ≥ 10% → ใช้ DD_MM (MM10)
  → ลด Lot ทันที ลด Drawdown ก่อนเป็นอันดับแรก

ลำดับที่ 4: Regime Volatile/Squeeze
  → ตลาดผันผวนสูง → ใช้ Volatile_MM (MM07)

ลำดับที่ 5 (ต่ำสุด): Default Normal
  → S01 ใช้ default_mm = MM04 (Kelly)
```

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางข้อมูลจากตลาดสู่คำสั่งซื้อขาย

```
[ตลาด Forex] → [MT5 Platform] → [FeederEA] → Port 7777 → [Python Brain]
                                                              ↓
                                                     [S01StatArbAnalyzer]
                                                              ↓
                                                   [InfluxDB + Tick Buffer]
                                                              ↓
                                         [คำนวณ Beta, Cointegration, Z-Score]
                                                              ↓
                                                     [Confidence Scoring]
                                                              ↓
                                              [AI Council: ผ่าน/ไม่ผ่าน?]
                                                              ↓
                                                    [CONFIG_PUSH] Port 7778
                                                              ↓
                                              [ProgramC_Trader.mq5] → [CStatArb]
                                                              ↓
                                              [Z-Score ทุก Tick] → [Signal]
                                                              ↓
                                                     [MM → Lot Sizing]
                                                              ↓
                                                   [Order Placement] → [ตลาด]
                                                              ↓
                                              [TRADE_REPORT] Port 7779 → [Brain]
```

### 4.2 เหตุผลที่เลือก Port 7777, 7778, 7779

**Port 7777 — Data Ingestion (FeederEA → Brain):**
- เป็น ZMQ **PUB-SUB** Pattern: FeederEA เป็น Publisher, Brain เป็น Subscriber
- เหตุผลที่ใช้ PUB-SUB: รองรับ FeederEA หลายตัวพร้อมกัน (Multi-Tenant) แต่ละ Chart สามารถ Publish ข้อมูล Symbol ของตัวเองได้
- เหตุผลที่เลือก Port 7777: เป็น Port ที่ไม่ถูกใช้งานโดย System Services ทั่วไปและจำง่าย ตัวเลข 7 ซ้ำสามครั้งสื่อถึง "Data Input" ใน Convention ของโครงการ
- ข้อมูลที่ส่ง: TICK_DATA (ราคา Ask/Bid ทุก Tick), OHLC (ราคาแท่งเทียน), สถานะออเดอร์

**Port 7778 — Configuration Push (Brain → Trader):**
- เป็น ZMQ **PUSH-PULL** Pattern: Brain เป็น PUSH, Trader เป็น PULL
- เหตุผลที่ใช้ PUSH-PULL: รับประกันว่าทุก CONFIG_PUSH จะถูก Trader รับเสมอ (Guaranteed Delivery) ต่างจาก PUB-SUB ที่อาจ Miss ข้อความได้
- เหตุผลที่เลือก Port 7778: ตัวเลข 8 แทน "Config" — มาจาก Convention ว่า Port เลขคู่ใช้สำหรับ Control Messages
- ข้อมูลที่ส่ง: CONFIG_PUSH Type=10 (Beta, Period, EntryZ, StopZ, MM Method, Regime)

**Port 7779 — Feedback/Report (Trader → Brain):**
- เป็น ZMQ **PUSH-PULL** Pattern: Trader เป็น PUSH, Brain เป็น PULL
- เหตุผลที่ใช้ PUSH-PULL: เช่นเดียวกับ Port 7778 — รับประกันว่าทุก Trade Report จะถูก Brain รับ
- เหตุผลที่เลือก Port 7779: ตัวเลข 9 แทน "Feedback" ตัวเลขสูงกว่า 7778 สื่อถึงข้อมูลที่ "ตอบกลับ"
- ข้อมูลที่ส่ง: TRADE_REPORT Type=9 (ticket, pnl, strategy_id, lot, confidence, timestamp)

### 4.3 MessagePack — ทำไมไม่ใช้ JSON?

MessagePack เป็นโปรโตคอล Binary Serialization ที่มีข้อดีเหนือ JSON ดังนี้:

| คุณสมบัติ | JSON | MessagePack |
|----------|------|-------------|
| ขนาดข้อมูล | 100% | ~30-40% (เล็กกว่า 60-70%) |
| ความเร็ว Encode | ช้า (Text Parsing) | เร็วกว่า 3-5× (Binary) |
| รองรับ Binary Data | ต้องแปลง Base64 | รองรับโดยตรง |
| Human Readable | ✅ ใช่ | ❌ ไม่ |
| Library ใน MQL5 | ต้องเขียนเอง | มีไลบรารีพร้อม |

ในระบบที่รับ Tick Data ทุก 100-200 มิลลิวินาที การลดขนาดข้อมูล 60% และเพิ่มความเร็ว Encoding 3× มีผลอย่างมากต่อ Latency โดยรวม

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตร Composite Confidence

Python Brain คำนวณค่า Confidence รวมจาก 4 องค์ประกอบ:

```python
confidence = coint_score + z_score_component + corr_score + beta_score
confidence = _apply_regime(confidence, current_regime)
```

**สูงสุดที่เป็นไปได้:** 0.35 + 0.45 + 0.15 + 0.05 = **1.00** (ก่อนปรับ Regime)

---

### 5.2 องค์ประกอบที่ 1: Cointegration Score (น้ำหนัก 0.35 — สูงที่สุด)

```
coint_p = ค่า p-value จาก Engle-Granger Test

ถ้า coint_p < 0.05:  coint_score = 0.35  (Cointegration แข็งแกร่ง)
ถ้า coint_p < 0.10:  coint_score = 0.20  (Cointegration ปานกลาง)
ถ้า coint_p ≥ 0.10:  coint_score = 0.00  (ไม่มี Cointegration → ข้ามไป)
```

**เหตุผลที่ให้น้ำหนักสูงสุด:** Cointegration คือเงื่อนไขพื้นฐานสุดของกลยุทธ์นี้ ถ้าไม่มี Cointegration แม้ Z-Score จะสูงแค่ไหนก็ไม่มีความหมาย เพราะ Spread อาจไม่กลับมาเลย ดังนั้นน้ำหนัก 35% จึงเป็นการให้ความสำคัญกับ "เงื่อนไขจำเป็น (Necessary Condition)" ก่อนสิ่งอื่น

---

### 5.3 องค์ประกอบที่ 2: Z-Score Component (น้ำหนัก 0.45 — สูงที่สุดรวม)

```
abs_z = |Z-Score| (ค่าสัมบูรณ์)

ถ้า abs_z < 1.0:  z_score_component = 0.0  (ไม่มีสัญญาณ)
ถ้า 1.0 ≤ abs_z < 2.0:  z_score_component = (abs_z - 1.0) × 0.30  (ค่อยๆ เพิ่ม)
ถ้า abs_z ≥ 2.0:  z_score_component = 0.30 + (abs_z - 2.0) × 0.15 (เพิ่มเพิ่มเติม)
                  (สูงสุด = 0.45 เมื่อ abs_z ≈ 3.0)
```

**เหตุผลที่ให้น้ำหนักสูงสุด:** Z-Score คือตัวบ่งชี้โดยตรงว่า "โอกาสทำกำไรมากแค่ไหน" — ยิ่ง Z-Score สูง (ราคาห่างกันมาก) ยิ่งมีโอกาสกำไรมากเมื่อมันกลับมา แต่ก็มีความเสี่ยงสูงขึ้นด้วย ระบบจึง Scale Score แบบ Linear ไม่ใช่ Binary

---

### 5.4 องค์ประกอบที่ 3: Correlation Score (น้ำหนัก 0.15)

```
corr = Pearson Correlation Coefficient ระหว่าง Price_A และ Price_B
       (คำนวณบน 100 แท่งล่าสุด ใน Python Brain)

ถ้า corr > 0.90:  corr_score = 0.15  (ความสัมพันธ์สูงมาก — ดีที่สุด)
ถ้า corr > 0.70:  corr_score = 0.10  (ความสัมพันธ์สูง — ยังดี)
ถ้า corr > 0.50:  corr_score = 0.05  (ความสัมพันธ์ปานกลาง — มีความเสี่ยง)
ถ้า corr ≤ 0.50:  corr_score = 0.00  (ความสัมพันธ์ต่ำ — ไม่น่าเชื่อถือ)
```

**ความแตกต่างระหว่าง Correlation กับ Cointegration:**
- Correlation วัด "ในระยะสั้นว่าทั้งสองเดินตามกันแค่ไหน"
- Cointegration วัด "ในระยะยาวว่ามีแรงผูกพันที่จะดึงกลับมาหากันหรือไม่"
- คู่เงินสามารถมี Correlation สูงแต่ไม่ Cointegrate ได้ (เช่น ช่วงวิกฤติ) และสามารถ Cointegrate แต่ Correlation ต่ำชั่วคราวได้เช่นกัน
- ระบบต้องการทั้งสองอย่าง — Cointegration เป็น Gate (ผ่าน/ไม่ผ่าน) และ Correlation เป็น Quality Score

---

### 5.5 องค์ประกอบที่ 4: Beta Score (น้ำหนัก 0.05)

```
ถ้า β คำนวณสำเร็จ (ไม่ใช่ None และไม่ใช่ 0):  beta_score = 0.05
ถ้า β ไม่มีหรือ 0 (Standalone Mode):             beta_score = 0.00
```

**เหตุผลที่น้ำหนักน้อย:** Beta Score เป็นเพียง "Sanity Check" ว่า Python Brain สามารถคำนวณ OLS ได้สำเร็จหรือไม่ ไม่ได้วัดคุณภาพของ Beta เอง เพราะคุณภาพของ Beta สะท้อนอยู่ใน Cointegration Score แล้ว

---

### 5.6 ตัวคูณปรับตาม Market Regime (Regime Multipliers)

| Regime | ตัวคูณ | เหตุผลทางวิชาการ |
|--------|--------|----------------|
| **RANGING** | **×1.5** | สภาวะที่ Mean Reversion ทำงานดีที่สุด ราคาไม่มีทิศทาง Spread มีโอกาสสูงมากที่จะกลับมา |
| **SQUEEZE** | **×1.2** | ช่วงก่อน Breakout — ตลาดยังไม่มีทิศทางชัดเจน S01 ยังทำงานได้ดีพอสมควร |
| **TRENDING** | **×0.6** | สภาวะอันตรายสำหรับ Mean Reversion — ราคาอาจวิ่งไปทิศทางเดียวนาน ทำให้ Spread ห่างออกไปเรื่อยๆ |
| **VOLATILE** | **×0.3** | สภาวะที่แย่ที่สุด — ราคาแกว่งอย่างไม่มีรูปแบบ ความสัมพันธ์คู่เงินอาจพังชั่วคราวในช่วงข่าวใหญ่ |

ตัวอย่าง: ถ้า Confidence ดิบ = 0.80 แต่ Regime คือ VOLATILE → Confidence ที่ส่งให้ AI Council = 0.80 × 0.3 = **0.24** ซึ่งต่ำกว่า Threshold 0.50 → S01 จะไม่ถูกเปิดใช้งาน

---

## 6. MQL5: การทำงานภายในของ CStatArb

### 6.1 Circular Spread Buffer

`CStatArb` ใช้ Circular Buffer (Ring Buffer) เพื่อเก็บค่า Spread ล่าสุด N ค่า โดยไม่ต้องเลื่อนข้อมูลทั้งอาร์เรย์ทุก Tick:

```mql5
// ตัวแปรหลักภายใน CStatArb
double m_spread_buffer[];  // Circular buffer ขนาด m_period
int    m_buf_idx;          // ตัวชี้ตำแหน่งปัจจุบัน (circular pointer)
int    m_buf_count;        // จำนวนข้อมูลที่เติมแล้ว (0 ถึง m_period)

// ทุก Tick:
double current_spread = ask_a - m_beta * bid_b;
m_spread_buffer[m_buf_idx % m_period] = current_spread;
m_buf_idx++;

// ต้องมีข้อมูลครบ m_period แท่งก่อน จึงจะคำนวณ Z-Score ได้
if(m_buf_count < m_period) {
    m_buf_count++;
    return SIGNAL_NONE;  // ยังไม่พร้อม
}
```

**เหตุผลที่ใช้ Circular Buffer แทนการ Shift Array:**
การ Shift Array ทั้งหมดทุก Tick มีความซับซ้อน O(N) ส่วน Circular Buffer มีความซับซ้อน O(1) สำหรับ Tick ที่มาถี่ถึง 10-50 ครั้งต่อวินาที ความแตกต่างนี้มีนัยสำคัญต่อประสิทธิภาพโดยรวมของ EA

### 6.2 ตรรกะการส่งสัญญาณ (Signal Logic)

```mql5
// คำนวณ Z-Score จาก Buffer ปัจจุบัน
double ma     = _CalcMean(m_spread_buffer, m_period);
double stddev = _CalcStdDev(m_spread_buffer, m_period, ma);

if(stddev < 0.000001) return SIGNAL_NONE;  // ป้องกัน Division by Zero

double zscore = (current_spread - ma) / stddev;

// Entry Signals
if(zscore < -m_entry_z)    return SIGNAL_BUY;   // Long A / Short B
if(zscore > +m_entry_z)    return SIGNAL_SELL;  // Short A / Long B

// Exit Signals (ถ้ามีสถานะเปิดอยู่)
if(m_has_position && MathAbs(zscore) < m_exit_z)  return SIGNAL_EXIT;  // TP
if(m_has_position && MathAbs(zscore) > m_stop_z)  return SIGNAL_EXIT;  // SL

return SIGNAL_NONE;  // Hold position
```

### 6.3 Confidence ฝั่ง MQL5 (Local Confidence)

```mql5
// ใช้ Interpolation เชิงเส้นระหว่าง EntryZ และ StopZ
double abs_z    = MathAbs(zscore);
double raw_conf = MathMin(1.0,
    (abs_z - m_entry_z) / (m_stop_z - m_entry_z));

// ลงโทษเมื่อ Z-Score ใกล้ Stop Zone (เสี่ยงมากขึ้น)
if(abs_z > m_stop_z * 0.9)
    raw_conf *= 0.7;  // ลด Confidence 30%
```

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `StatArb_Period` | 20 | 10–100 | จำนวนแท่งราคาที่ใช้คำนวณ MA และ StdDev ของ Spread ค่าน้อย (10) → ตอบสนองไวแต่ Noisy ค่ามาก (100) → เรียบแต่ช้า ค่า 20 เหมาะสมสำหรับ Timeframe M1-M5 |
| `StatArb_EntryZ` | 2.0 | 1.5–3.0 | ระดับ Z-Score ที่เริ่มเปิดสถานะ ค่า 2.0 หมายถึงต้องเกิน 2 Standard Deviation ก่อน ค่าต่ำ (1.5) → เข้าบ่อยแต่ False Signal มาก ค่าสูง (3.0) → เข้าน้อยแต่โอกาสสำเร็จสูงขึ้น |
| `StatArb_ExitZ` | 0.2 | 0.0–0.5 | ระดับ Z-Score ที่ถือว่า Mean Reversion สำเร็จ ค่า 0.2 หมายถึงออกเมื่อ Spread กลับมาใกล้ค่าเฉลี่ยมาก ค่า 0.0 = รอกลับมาสู่สมดุลสมบูรณ์ (อาจรอนาน) |
| `StatArb_StopZ` | 3.0 | 2.5–4.0 | จุด Stop Loss เมื่อ Spread ห่างเกิน 3 SD ซึ่งมีโอกาสเกิดขึ้น < 0.3% ในการแจกแจงปกติ ถ้า Spread วิ่งไปถึงจุดนี้แสดงว่าความสัมพันธ์อาจพังแล้ว |
| `StatArb_Beta` | 1.0 | 0.1–5.0 | Hedge Ratio ในโหมด Standalone ค่า 1.0 หมายถึง 1:1 ratio ค่านี้จะถูก Override ด้วย CONFIG_PUSH ทุกครั้งที่ Brain คำนวณ Beta ใหม่ |
| `StatArb_SymbolA` | EURUSD | — | สินทรัพย์หลักในโหมด Standalone เป็นตัว Long เมื่อ SIGNAL_BUY |
| `StatArb_SymbolB` | GBPUSD | — | สินทรัพย์รองในโหมด Standalone เป็นตัว Short เมื่อ SIGNAL_BUY |

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | คำอธิบาย | ผลกระทบทันที |
|-----|--------|----------|-------------|
| `S01_BETA` | float | OLS Hedge Ratio คำนวณจาก Python | อัปเดต `m_beta` ทันทีโดยไม่ต้อง Restart |
| `S01_PERIOD` | int | จำนวนแท่งที่ผ่านการ Optimize แล้ว | Rebuild Spread Buffer ขนาดใหม่ |
| `S01_ENTRY_Z` | float | Entry Z-Score ที่ Optimize แล้ว | อัปเดต `m_entry_z` ใน Tick ถัดไป |
| `S01_STOP_Z` | float | Stop Z-Score ที่ Optimize แล้ว | อัปเดต `m_stop_z` ใน Tick ถัดไป |
| `stat_arb_pair` | string | คู่เงินที่เลือก เช่น `"EURUSD:GBPUSD"` | ใช้เพื่อ Log และ Validation |
| `stat_arb_zscore` | float | Z-Score ณ ขณะที่ Brain วิเคราะห์ | ใช้ Cross-check กับค่าที่ MQL5 คำนวณ |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Standalone Mode (ไม่มีเซิร์ฟเวอร์)

เมื่อ Brain ขาดการเชื่อมต่อ (Network Down, Brain Crash, PC รีสตาร์ท) ระบบจะสลับไป Standalone Mode โดยอัตโนมัติ:

```
ลำดับการตัดสินใจ:
1. ลอง Load standalone_config.dat
   → มีไฟล์: ใช้ Beta, Period, EntryZ ที่บันทึกไว้จาก CONFIG_PUSH ล่าสุด
   → ไม่มีไฟล์: ใช้ค่า Default (Beta=1.0, Period=20, EntryZ=2.0, StopZ=3.0)

2. ลด Risk Multiplier เหลือ 50% ของปกติ
   → เหตุผล: ไม่มีข้อมูล Cointegration สด อาจเสี่ยงมากขึ้น

3. ใช้ Regime Classifier เฉพาะ MQL5 (Rule-based)
   → ไม่มี Random Forest/HMM จาก Brain
   → ใช้เพียง ATR Ratio และ ADX เพื่อจัดประเภท Regime

4. รอการเชื่อมต่อกลับ → สลับกลับ Server Mode ทันที
```

### 8.2 Server Mode (Full Optimization)

ใน Server Mode Python Brain ทำงานทุก 30-60 วินาทีต่อรอบ:

```
ทุกรอบ Optimization Cycle:
1. ดึง OHLC 100 แท่งจาก InfluxDB
2. S01StatArbAnalyzer.analyze() ทำงาน:
   a. คำนวณ OLS Beta ใหม่
   b. คำนวณ Spread Series
   c. ทดสอบ Engle-Granger Cointegration
   d. คำนวณ Pearson Correlation
   e. วัด Z-Score ปัจจุบัน
3. รวม Confidence Score (4 องค์ประกอบ)
4. ปรับตาม Regime Multiplier
5. ส่งให้ AI Council ตัดสิน:
   - weighted_confidence ≥ 0.50?
   - R:R ≥ 1.5?
6. ถ้าผ่าน: สร้าง CONFIG_PUSH และส่งผ่าน Port 7778
7. ผลการเทรด (Port 7779) → อัปเดต PerformanceTracker
8. PerformanceTracker ส่งผลให้ AI Council ใช้ครั้งต่อไป (Feedback Loop)
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| สถานะ | เงื่อนไข | การกระทำ |
|-------|---------|---------|
| **Monitoring** | `|Z-Score| < EntryZ (2.0)` | รอ — ไม่มีการกระทำใดๆ |
| **Long Spread** | `Z-Score < −2.0` | Buy A (EU) + Sell B (GU) พร้อมกัน |
| **Short Spread** | `Z-Score > +2.0` | Sell A (EU) + Buy B (GU) พร้อมกัน |
| **Take Profit** | `|Z-Score| < 0.2` (ขณะมีสถานะ) | ปิดทั้งสองฝั่งพร้อมกัน |
| **Stop Loss** | `|Z-Score| > 3.0` (ขณะมีสถานะ) | ปิดทั้งสองฝั่งพร้อมกัน |

---

## 10. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | RANGING (ตลาดแกว่งในกรอบ) — Regime Factor ×1.5 |
| **สภาวะตลาดที่แย่ที่สุด** | VOLATILE (ข่าวใหญ่, Flash Crash) — Regime Factor ×0.3 |
| **ระยะเวลาถือสถานะทั่วไป** | 2–12 ชั่วโมง (ขึ้นอยู่กับความเร็วของ Mean Reversion) |
| **เป้าหมาย Win Rate** | 60–70% (Edge จาก Cointegration) |
| **R:R Gate (AI Council)** | ≥ 1.5 ต้องผ่าน |
| **Latency (MQL5 Signal)** | ~0 ms (คำนวณในเครื่อง) |
| **Python Cycle** | 30–60 วินาที |
| **สูงสุด Confidence ดิบ** | 1.00 (ทุกองค์ประกอบสูงสุด) |
| **ต่ำสุดที่ AI Council รับ** | 0.50 × Regime Factor |

---

## 11. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `02_Brain/strategies/s01_stat_arb_analyzer.py` | Python: OLS Beta, Cointegration Test, Confidence Scoring |
| `02_Brain/strategies/base_analyzer.py` | Base Class: Regime Multipliers, IncrementalIndicatorCache |
| `Include/Logic/Strategies/S01_StatArb.mqh` | MQL5: CStatArb — Circular Buffer, Z-Score, Signal Logic |
| `Include/Logic/StrategyConstants.mqh` | ENUM_STRATEGY_ID, Magic Numbers, g_strategy_table |
| `Include/Logic/MM/MMManager.mqh` | CMMManager: MM Selection Logic, SMMSelection struct |
| `03_Trader/ProgramC_Trader.mq5` | Main EA: Strategy dispatch, CONFIG_PUSH parsing |
| `02_Brain/config_push/config_builder.py` | สร้าง CONFIG_PUSH MessagePack payload |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT ผ่าน Port 7779 |
| `02_Brain/core/performance_tracker.py` | EMA-based Historical Performance Weights |
| `02_Brain/core/intelligence/strategy_council.py` | AI Council: weighted_conf, R:R Gate, Calendar Adj |

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 12.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: Beta Drift (ค่า Beta เปลี่ยนตามเวลา)**
ค่า OLS Beta ที่คำนวณจาก 100 แท่งเมื่อวาน อาจไม่ตรงกับความเป็นจริงของตลาดวันนี้ โดยเฉพาะในช่วงที่ Monetary Policy ของ BOE (Bank of England) และ ECB (European Central Bank) เริ่มแตกต่างกัน ค่า Beta อาจเลื่อนจาก 0.80 ไปเป็น 0.65 ภายในสัปดาห์เดียว

**แนวทางแก้ไข:** Python Brain ควรอัปเดต Beta ทุก 30 วินาทีในช่วง London Session และทุก 5 นาทีในช่วง Asian Session ที่ Volatility ต่ำกว่า

**ปัญหาที่ 2: Cointegration Breakdown ช่วงข่าว**
ในช่วงที่มีการประกาศตัวเลขสำคัญ เช่น UK CPI, Eurozone GDP ความสัมพันธ์ของคู่เงินอาจพังชั่วคราว ทำให้ Spread วิ่งออกไปและไม่กลับมา

**แนวทางแก้ไข:** ติดตั้ง News Calendar Filter ใน AI Council เพื่อลด Confidence ก่อน 30 นาทีและหลัง 30 นาทีของการประกาศ Economic Data สำคัญ

**ปัญหาที่ 3: Liquidity Mismatch**
EURUSD และ GBPUSD มี Liquidity ต่างกัน ทำให้ในช่วงที่ตลาดบางคู่เกิด Slippage สูง การ Execute คำสั่งคู่อาจเกิดความไม่สมดุลระหว่าง Leg A กับ Leg B

### 12.2 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่ที่แนะนำ | เหตุผล |
|------------|--------------|-------|
| Beta (OLS) | ทุก 30-60 วินาที | เปลี่ยนได้เร็วตาม Market Conditions |
| Cointegration Test | ทุก 5-10 นาที | คำนวณหนัก ไม่ต้องทำบ่อยเกินไป |
| EntryZ Threshold | ทุก 4-8 ชั่วโมง | ขึ้นอยู่กับ Regime ที่ค่อนข้างเสถียร |
| Period (Window) | ทุกวัน (สิ้นวัน) | อิงจากการ Backtest รายวัน |
| Symbol Pair | ทุกสัปดาห์ | ตรวจสอบว่ายังมี Cointegration หรือไม่ |

### 12.3 การเลือกคู่สินทรัพย์ที่ดี

คู่สินทรัพย์ที่ดีควรมีคุณสมบัติครบ 3 ประการ:

1. **p-value < 0.05 อย่างสม่ำเสมอ** — ทดสอบ Cointegration ย้อนหลัง 6 เดือน ต้องผ่านอย่างน้อย 80% ของเดือน
2. **Correlation > 0.70** — ความสัมพันธ์ระยะสั้นยังต้องแน่นอยู่
3. **Spread มีความผันผวนพอสมควร** — ถ้า StdDev ต่ำเกินไป แม้จะเกิด Divergence กำไรก็น้อย ถ้า StdDev สูงเกินไป SL จะกว้างมาก

**คู่ที่แนะนำสำหรับ Forex:**
- EURUSD / GBPUSD (คู่หลัก — Correlation มักสูงกว่า 0.85)
- AUDUSD / NZDUSD (คู่ Oceania — บ่อยครั้ง Cointegrate สูงกว่า)
- USDJPY / USDCHF (Safe Haven คู่ — ดีในช่วง Risk-Off)

---

## 13. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### ตรวจสอบว่า S01 ทำงานอยู่

```bash
# ใน Dashboard Python:
python 02_Brain/dashboard.py
# ดูที่ "Active Strategies" panel → ควรเห็น "S01" พร้อม Confidence %

# ตรวจสอบ Cointegration:
python -c "
from strategies.s01_stat_arb_analyzer import S01StatArbAnalyzer
a = S01StatArbAnalyzer()
result = a.analyze('EURUSD', 'GBPUSD')
print('Beta:', result.get('beta'))
print('Coint p-value:', result.get('coint_pval'))
print('Confidence:', result.get('confidence'))
"
```

### ตรวจสอบ CONFIG_PUSH มี S01 หรือไม่

```bash
python tools/validate_live_readiness.py --zmq
# ดูที่ TEST 5: CONFIG_PUSH dry-run
# ควรเห็น S01_BETA, S01_PERIOD, S01_ENTRY_Z, S01_STOP_Z ใน Output
```

### ตรวจสอบ Z-Score ใน MT5

```mql5
// ใน EA Console หรือ Expert Log:
s01.PrintDiagnostics();
// Output ตัวอย่าง:
// [S01] StatArb | EURUSD/GBPUSD | Beta=0.8021 | Period=20
// [S01] Spread=0.07234 MA=0.07301 StdDev=0.00238 Z=-0.282
// [S01] Signal=NONE | Conf=0.00 | Pos=LONG(open)
// [S01] LONG P/L=+$23.40 | Target Z<0.20 | Current Z=0.282 → waiting
```

### ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S01 ไม่เคยเปิด Trade | Confidence ต่ำกว่า 0.50 หรือ Regime VOLATILE | ตรวจสอบ Regime และ Cointegration Test |
| Spread วิ่งผ่าน StopZ บ่อย | Beta ค้าง — ไม่อัปเดต | ตรวจสอบ Brain Connection และ Port 7778 |
| Trade อยู่นานผิดปกติ | ExitZ สูงเกินไป หรือ Mean Reversion ช้า | ลด ExitZ หรือเพิ่ม Period |
| กำไรน้อย Lot เล็กเกินไป | MM01 ให้ 1% Risk แต่ Spread น้อยมาก | ลองใช้ MM04 Kelly หรือเพิ่ม Base Risk |
| ใน Standalone Beta = 1.0 | ปกติ — ไม่มีเซิร์ฟเวอร์ Python | ตรวจสอบ Brain และ standalone_config.dat |

---

*S01 Statistical Arbitrage — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-27*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
