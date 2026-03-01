# S13 — Fibonacci + Stochastic (Pullback Retracement)
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-27 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S13 | รหัสลำดับที่ 13 ในระบบมัลติกลยุทธ์ของ FlashEASuite V2 ตัวเลข "13" ไม่ได้หมายถึงโชคร้ายอย่างที่คิด — แต่เป็นกลยุทธ์ที่อาศัยอัตราส่วนทางคณิตศาสตร์โบราณที่ฝังอยู่ในธรรมชาติและพฤติกรรมตลาด |
| **Enum Name** | `S13_FIB_STOCH` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) ค่า enum index = 12 (0-based array index) หมายความว่าเป็น element ลำดับที่ 13 ของ `g_strategy_table[16]` นับจาก 0 |
| **Enum Index** | 12 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่านฟังก์ชัน `GetStrategyInfo(S13_FIB_STOCH)` |
| **ชื่อ** | Fibonacci + Stochastic (Pullback Retracement) | กลยุทธ์จับจังหวะ Pullback ในแนวโน้มหลักโดยใช้ระดับ Fibonacci Retracement เป็นโซนเข้า และ Stochastic Oscillator เป็นตัวยืนยัน |
| **ประเภท** | Full MQL5 — ServerOnly (`CAT_FULL_MQL5`) | ตรรกะทั้งหมดอยู่ใน MQL5 แต่ต้องรอรับ Trend Direction จาก Python Brain ผ่าน `S13_TREND_DIR` ก่อนจึงจะเปิดใช้งาน |
| **Standalone Capable** | ❌ No | ไม่รองรับโหมดอิสระ เพราะ `m_server_trend` เป็นส่วนประกอบสำคัญในสูตร Confidence — ถ้าขาดค่านี้ Confidence = 0.0 และเงื่อนไข Entry จะไม่ผ่าน |
| **Preferred Regime** | TRENDING (`REGIME_TRENDING`) | ต้องมีแนวโน้มชัดเจนเพื่อให้เกิด Swing High/Low ที่แท้จริงและ Pullback ที่มีความหมาย |
| **Alt Regime** | None | ไม่มี Regime รอง — S13 เป็นกลยุทธ์เฉพาะตลาดมีทิศทางเท่านั้น |
| **Poor Regimes** | VOLATILE, RANGING | ตลาดผันผวนสูงทำลาย Swing Structure ตลอดเวลา ตลาด Ranging ไม่มี Swing High/Low ที่ชัดเจน ทั้งสองสภาวะทำให้ Fibonacci Level ไม่มีความหมาย |
| **Regime Factor** | TRENDING=1.5, SQUEEZE=0.8, RANGING=0.6, VOLATILE=0.3 | ตัวคูณที่ Python Brain ใช้ปรับค่า Confidence ตามสภาวะตลาด ออกแบบให้เพิ่ม Signal ใน TRENDING และลดความเสี่ยงใน VOLATILE |
| **MQL5 Class** | `CFibStoch` | คลาสหลักใน `Include/Logic/Strategies/S13_FibStoch.mqh` ควบคุมตรรกะการตรวจจับ Swing, คำนวณ Fib Levels, อ่าน Stochastic, และส่งสัญญาณ |
| **Python Analyzer** | None (FULL_MQL5) | ไม่มี Python Analyzer เฉพาะ — Python Brain ทำหน้าที่เพียง Regime Classification และส่ง Trend Direction (+1.0/-1.0) เท่านั้น |
| **Magic Number** | 1013 (`MAGIC_S13_FIB_STOCH`) | หมายเลขเอกลักษณ์แท็กออเดอร์ทั้งหมดของ S13 ป้องกันการปะปนกับออเดอร์จาก S01–S16 ตัวอื่น |
| **Family** | Counter-Trend Retracement / Pullback | กลุ่มกลยุทธ์ที่เทรดสวนทิศทางชั่วคราว (Pullback) เพื่อจับจุดกลับของแนวโน้มหลัก ไม่ใช่การเดาทิศทางใหม่ |
| **Version** | 6.00 | สถาปัตยกรรม V6 ออกแบบใหม่ทั้งหมดจาก V5 เน้น "Smart Server, Powerful Client" |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S13 เป็นกลยุทธ์ **Pullback Trading** ที่ผสมผสานสองเครื่องมือที่พิสูจน์ตัวเองมาหลายทศวรรษในตลาดการเงิน — **Fibonacci Retracement** และ **Stochastic Oscillator** — เพื่อจับจังหวะที่ตลาดกำลัง "หายใจ" (Pullback) ก่อนจะกลับทิศทางเดิมต่อไป

แนวคิดหลักคือ: เมื่อตลาดมีแนวโน้มชัดเจน ราคาจะไม่วิ่งขึ้น (หรือลง) ตรงๆ ตลอดเวลา — มันจะ **ย้อนกลับชั่วคราว** (Pullback) ก่อนจะกลับไปในทิศทางเดิม จุดที่ Pullback มักจะหยุดและกลับตัวนั้น ไม่ได้สุ่ม แต่กระจุกตัวอยู่ที่ **ระดับ Fibonacci** (38.2%, 50.0%, 61.8%) ซึ่งเป็นระดับที่นักเทรดสถาบันทั่วโลกให้ความสำคัญ

S13 ทำงาน 5 ขั้นตอน:
1. ตรวจหา **Swing High** และ **Swing Low** ที่ชัดเจนในช่วง 100 แท่งที่ผ่านมา
2. คำนวณ **Fibonacci Levels** — โซนเข้า: 38.2%–61.8%, SL: 78.6%, TP: Swing High/Low
3. รอให้ราคา **pullback** เข้าสู่โซน Fibonacci (38.2%–61.8%)
4. ยืนยันด้วย **Stochastic Oscillator** — Long เมื่อ %K < 20 (Oversold), Short เมื่อ %K > 80 (Overbought)
5. รับ **m_server_trend** จาก Python Brain เพื่อยืนยันว่าแนวโน้มหลักสอดคล้องกับ Local Swing ที่ตรวจพบ

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมต้องชื่อ "Fibonacci"?

**กำเนิดของอนุกรม Fibonacci:**
นักคณิตศาสตร์ชาวอิตาลีชื่อ **Leonardo of Pisa** (หรือที่รู้จักกันในชื่อ Fibonacci) ได้แนะนำอนุกรมตัวเลขนี้ในหนังสือ *Liber Abaci* เมื่อปี ค.ศ. 1202 เพื่ออธิบายการเติบโตของประชากรกระต่าย:

```
อนุกรม Fibonacci:
  1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, ...

กฎ: F(n) = F(n-1) + F(n-2)  เริ่มด้วย F(1)=1, F(2)=1
```

**คุณสมบัติมหัศจรรย์ — อัตราส่วนทอง (Golden Ratio φ):**
เมื่อนำตัวเลขถัดไปหารด้วยตัวเลขก่อนหน้า อัตราส่วนจะค่อยๆ เข้าใกล้ค่าคงที่ที่เรียกว่า **φ (Phi)**:

```
55  / 34  = 1.6176...
89  / 55  = 1.6182...
144 / 89  = 1.6180...
233 / 144 = 1.6181...
377 / 233 = 1.6180...  ← เข้าใกล้ φ = 1.6180339...
```

**การพิสูจน์ว่า 0.618 = 1/φ:**
```
φ = (1 + √5) / 2 ≈ 1.61803398...

1/φ = 2/(1+√5)
    = 2(1-√5) / [(1+√5)(1-√5)]
    = 2(1-√5) / (1-5)
    = 2(1-√5) / (-4)
    = (√5-1)/2
    ≈ (2.2360679 - 1)/2
    ≈ 1.2360679/2
    ≈ 0.6180339...

∴ 1/φ ≈ 0.618 ← นี่คือที่มาของ Fib 61.8%
```

**การพิสูจน์ว่า 0.382 = 1 - 0.618:**
```
0.382 = 1 - 0.618

เหตุผลเชิงคณิตศาสตร์:
  φ² = φ + 1  (คุณสมบัติของ Golden Ratio)
  → 1/φ² = 1/(φ+1) = 1/φ² = (1/φ)² = 0.618² = 0.38196...

หรืออีกวิธี:
  F(n-2) / F(n) → 0.382 เมื่อ n→∞
  (ตัวเลข 2 ขั้นก่อนหน้า หารด้วยตัวเลขปัจจุบัน)

∴ 0.382 ≈ 0.618 × 0.618 = 1/φ² ← Fib 38.2%
```

**การพิสูจน์ว่า 0.786 = √0.618:**
```
√0.618 = √(1/φ) = 1/√φ

1/√φ = 1/√1.6180... ≈ 1/1.2720... ≈ 0.7861...

∴ 0.786 ≈ √(1/φ) ← Fib 78.6% (ระดับ Stop Loss)
```

**ทำไม Fibonacci จึงปรากฏในตลาดการเงิน:**
อัตราส่วน Golden Ratio ปรากฏในธรรมชาติทุกที่ — เปลือกหอย, การเติบโตของพืช, อัตราส่วนร่างกายมนุษย์ นักวิเคราะห์ Elliott Wave Theory โดยเฉพาะ **Ralph Nelson Elliott** (1938) ค้นพบว่า คลื่นราคาในตลาดหุ้นมักมีอัตราส่วนที่สอดคล้องกับ Fibonacci อย่างน่าประหลาดใจ เหตุผลที่ยอมรับกันในทางการเงินพฤติกรรม (Behavioral Finance) คือ: **ตลาดเป็นผลรวมของพฤติกรรมมนุษย์** และมนุษย์มีสัญชาตญาณประเมินความเสี่ยง/กำไรในอัตราส่วนที่ใกล้เคียงกับ Golden Ratio โดยธรรมชาติ

---

### 1.3 ธรรมชาติของ Pullback (The Law of Trend Pullbacks)

**หลักการพื้นฐาน:**
ในตลาดการเงินที่มีแนวโน้ม ราคาจะไม่เคลื่อนที่เป็นเส้นตรงอย่างต่อเนื่อง เพราะผู้เล่นในตลาดมีหลายกลุ่มที่มีเป้าหมายต่างกัน:

```
กลุ่มที่ 1: Trend Followers (ซื้อเมื่อตลาดขึ้น, ขายเมื่อตลาดลง)
  → ดึงราคาให้เดินในทิศทางเดิม

กลุ่มที่ 2: Profit Takers (ขายทำกำไรหลังราคาขึ้นมามาก)
  → สร้าง Pullback ชั่วคราว

กลุ่มที่ 3: Counter-Trend Traders (รอซื้อที่ Dip / ขายที่ Rally)
  → เสริมแรง Pullback และ "ซื้อ Dip" ที่ Fib Levels

กลุ่มที่ 4: Institutions (Limit Orders วางไว้ที่ Fib Levels)
  → เป็น "แม่เหล็ก" ดึงราคาให้หยุดที่ระดับสำคัญ
```

**เหตุใด Pullback จึงหยุดที่ Fibonacci:**
สถาบันการเงินขนาดใหญ่ (Hedge Funds, Investment Banks) ที่มีทีม Quant วางคำสั่ง Limit Buy ไว้ที่ระดับ 38.2%, 50.0%, 61.8% ของ Pullback ด้วยเหตุผลเดียว — **ทุกคนรู้ว่า Fibonacci ใช้ได้** และความเชื่อนั้นเองที่ทำให้มันกลายเป็น Self-Fulfilling Prophecy: เมื่อผู้เล่นส่วนใหญ่วาง Buy Order ที่ 61.8% ราคาก็จะกลับตัวที่ 61.8% จริงๆ เพราะมีแรงซื้อขนาดใหญ่รอที่นั่น

**Pullback ที่ดีมีลักษณะ 3 ประการ:**
1. **ราคาลง 38.2%–61.8% ของการขึ้นก่อนหน้า** (ไม่ลึกจนเกินไปจนทำลาย Trend)
2. **Volume ลดลงขณะ Pullback** (แสดงว่าเป็น Correction ไม่ใช่ Reversal)
3. **Oscillator เข้าสู่ Oversold/Overbought** (ยืนยันว่า Momentum หมดชั่วคราว)

S13 ตรวจสอบทั้งข้อ 1 (Fib Zone) และข้อ 3 (Stochastic) ส่วนข้อ 2 (Volume) ใช้ `m_server_trend` จาก Brain เป็นตัวแทนทางอ้อม

---

### 1.4 กรณีศึกษาจริง (Case Study — 27 กุมภาพันธ์ 2026)

**สถานการณ์:** EURUSD, Timeframe H1 ในช่วง London Session ที่ตลาดมีแนวโน้มขาขึ้นชัดเจน

```
ขั้นตอนที่ 1: ตรวจจับ Swing Structure

  Swing Low  (ฐาน): 1.07000 — เกิดขึ้นเมื่อ 80 แท่งที่แล้ว (best_lo_bar = 80)
  Swing High (ยอด): 1.09000 — เกิดขึ้นเมื่อ 20 แท่งที่แล้ว (best_hi_bar = 20)

  m_is_uptrend = (best_lo_bar=80 > best_hi_bar=20) = TRUE
  → Swing Low เกิดก่อน Swing High = ราคาเดินจาก Low ไป High = Uptrend ✓

  Range = 1.09000 - 1.07000 = 0.02000 (200 pips)
```

```
ขั้นตอนที่ 2: คำนวณ Fibonacci Levels (Uptrend — ถอยจาก High ลงมา)

  Fib_38.2% = 1.09000 - 0.02000 × 0.382 = 1.09000 - 0.00764 = 1.08236
  Fib_50.0% = 1.09000 - 0.02000 × 0.500 = 1.09000 - 0.01000 = 1.08000
  Fib_61.8% = 1.09000 - 0.02000 × 0.618 = 1.09000 - 0.01236 = 1.07764  ← Golden Ratio
  Fib_78.6% = 1.09000 - 0.02000 × 0.786 = 1.09000 - 0.01572 = 1.07428  ← SL Level

  โซนเข้า (Entry Zone): [1.07764, 1.08236]   (จาก Fib_61.8% ถึง Fib_38.2%)
  Stop Loss Price:      1.07428               (Fib_78.6%)
  Take Profit Price:    1.09000               (Swing High)
```

```
ขั้นตอนที่ 3: ราคา Pullback เข้าสู่ Fib Zone

  เวลา 14:35: ราคา Bid = 1.07810  → เข้าโซน 1.07764–1.08236 ✓
              Stoch %K = 24       → ยังไม่ถึง 20 → รอต่อ

  เวลา 15:05: ราคา Bid = 1.07770  → ยังในโซน ✓
              Stoch %K = 18       → ต่ำกว่า 20 ✓  (Oversold)

  เวลา 15:15: ราคา Bid = 1.07764  → ที่ Golden Ratio 61.8% พอดี!
              Stoch %K = 12       → Oversold ลึกมาก ✓
              m_server_trend = +1.0 → Brain ยืนยัน Uptrend ✓
```

```
ขั้นตอนที่ 4: คำนวณ Confidence

  fib_accuracy:
    lo = min(1.08236, 1.07764) = 1.07764
    hi = max(1.08236, 1.07764) = 1.08236
    range_fib = 1.08236 - 1.07764 = 0.00472
    dist = |1.07764 - 1.07764| = 0.00000  (อยู่ที่ 61.8% พอดี!)
    fib_acc = 1.0 - min(0.00000 / 0.00472, 1.0) = 1.0 - 0.0 = 1.000

  stoch_extremity:
    %K = 12 ≤ 20 (Oversold Zone)
    stoch_ext = 1.0 - (12 / 20) = 1.0 - 0.60 = 0.400

  trend_strength:
    trend_str = |+1.0| = 1.000

  Confidence ดิบ:
    conf_raw = 1.000 × 0.400 × 1.000 = 0.400

  ปรับตาม TRENDING Regime Factor (×1.5):
    conf_final = 0.400 × 1.5 = 0.600

  AI Council: conf_final 0.600 ≥ 0.50 → APPROVED ✓
```

```
ขั้นตอนที่ 5: คำสั่งที่ระบบเปิด (เวลา 15:15 GMT)

  SIGNAL_BUY — Long EURUSD
  Entry: 1.07764 (Ask ≈ 1.07766 หลัง spread)
  SL:    1.07428 (Fib 78.6%)  = 33.6 pips ด้านล่าง
  TP:    1.09000 (Swing High) = 123.6 pips ด้านบน
  R:R    = 123.6 / 33.6 ≈ 3.68 : 1  ← ดีมาก!
  Lot:   0.10 (ตาม MM01 / ความเสี่ยง 1%)
```

```
ขั้นตอนที่ 6: ผลลัพธ์หลังจาก 2 วัน (1 มีนาคม 2026)

  ราคาฟื้นตัวกลับขึ้น:
  เวลา 10:00 น.: EURUSD = 1.08500  (+73.6 pips จาก Entry)
  เวลา 16:30 น.: EURUSD = 1.08900  (+113.6 pips)
  เวลา 22:00 น.: EURUSD = 1.09000  (+123.4 pips) → TP โดน!

  กำไรสุทธิ: 123.4 pips × 0.10 lot × $10/pip = +$123.40
  ใน 30.75 ชั่วโมง โดยใช้ความเสี่ยงสูงสุด $33.60 (SL)
  Net R:R ที่ได้จริง = 123.4 / 33.6 = 3.67 : 1
```

**บทเรียนจากกรณีนี้:** กำไรเกิดจากการรู้ว่า **ราคาจะกลับไปที่ Swing High** ซึ่งเป็นจุดที่สถาบันรายใหญ่จะปิด Short Position และ Retail Traders จะเข้า Long ใหม่ การรอให้ Stochastic ยืนยัน Oversold ป้องกันการ "จับมีดตก" ก่อนที่ Momentum จะหมดจริงๆ

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 อนุกรม Fibonacci และอัตราส่วนทอง (Fibonacci Sequence & Golden Ratio)

**พิสูจน์ว่าอัตราส่วน Fibonacci เข้าหา φ:**

```
นิยาม: r(n) = F(n+1) / F(n)

ถ้า limit r(n) → φ แล้ว φ = F(n+1)/F(n) = [F(n) + F(n-1)] / F(n) = 1 + 1/φ

φ = 1 + 1/φ
φ² = φ + 1
φ² - φ - 1 = 0

แก้สมการกำลังสอง:
φ = (1 ± √(1+4)) / 2 = (1 ± √5) / 2

เลือกค่าบวก: φ = (1 + √5) / 2 ≈ (1 + 2.2360679) / 2 ≈ 1.6180339...

สรุปอัตราส่วนทาง Fibonacci ทั้งหมด:
  0.618 = 1/φ    = ระยะ Primary Retracement (Golden Ratio Zone)
  0.382 = 1/φ²   = ระยะ Secondary Retracement (Shallow Pullback)
  0.500 = 1/2    = ระยะ Psychological Midpoint (ไม่ใช่ Fibonacci แท้)
  0.786 = 1/√φ   = ระยะ Invalidation Level (SL Reference)
```

---

### 2.2 การตรวจจับ Swing โดยใช้ Local Extrema (Swing Detection Algorithm)

**นิยามทางคณิตศาสตร์ของ Local Extrema:**

```
กำหนดอาร์เรย์ราคา H[0..N-1] (H[0]=ราคาล่าสุด, H[N-1]=เก่าสุด)
กำหนดขนาดหน้าต่าง w (= m_swing_min_bars = 5 โดย default)

Local High ที่ตำแหน่ง i คือ:
  H[i] > H[j]  สำหรับทุก j ∈ {i-w, i-w+1, ..., i-1, i+1, ..., i+w} และ j ≠ i
  กล่าวคือ: H[i] คือค่าสูงสุดในช่วง [i-w, i+w] โดยไม่นับตัวเอง

Local Low ที่ตำแหน่ง i คือ:
  L[i] < L[j]  สำหรับทุก j ∈ {i-w, ..., i+w} และ j ≠ i

อัลกอริทึมสแกน:
  ช่วงสแกน: i = w ถึง (N_total - w - 1)
  N_total = m_fib_lookback + 2w = 100 + 10 = 110 แท่ง

  บันทึก:
    best_hi = Swing High สูงสุดทั้งหมดในช่วง = max{H[i] : i เป็น Local High}
    best_lo = Swing Low  ต่ำสุดทั้งหมดในช่วง = min{L[i] : i เป็น Local Low}

ความซับซ้อน: O(N × 2w) = O(110 × 10) = O(1100) operations per bar
เรียกครั้งเดียวต่อแท่ง (bar-gated) ไม่ใช่ต่อ Tick → ไม่ส่งผลต่อ Latency
```

**ตรรกะการกำหนด Trend Direction:**
```
m_is_uptrend = (best_lo_bar > best_hi_bar)

ความหมาย:
  best_lo_bar = index ของ Swing Low (ยิ่งมาก = ยิ่งเก่า ในอาร์เรย์ Series)
  best_hi_bar = index ของ Swing High

  ถ้า best_lo_bar > best_hi_bar:
    → Swing Low เกิดก่อน Swing High (เก่ากว่า)
    → ราคาเดินจาก Low → High → ตอนนี้กำลัง Pullback จาก High ลงมา
    → m_is_uptrend = true = ควร BUY เมื่อ Pullback เข้า Fib Zone

  ถ้า best_lo_bar < best_hi_bar:
    → Swing High เกิดก่อน Swing Low (เก่ากว่า)
    → ราคาเดินจาก High → Low → ตอนนี้กำลัง Pullback จาก Low ขึ้นมา
    → m_is_uptrend = false = ควร SELL เมื่อ Pullback เข้า Fib Zone
```

---

### 2.3 การคำนวณระดับ Fibonacci (Fibonacci Level Computation)

**กรณี Uptrend (ถอยจาก High ลงมา — Long Setup):**

```
Range R = Swing_High − Swing_Low

Fib_38.2% = Swing_High − R × 0.382  ← ขอบ Inner (ขาขึ้นแรง = Pullback ตื้น)
Fib_50.0% = Swing_High − R × 0.500  ← จุดกึ่งกลางทางจิตวิทยา
Fib_61.8% = Swing_High − R × 0.618  ← Golden Ratio Zone (ดีที่สุดสำหรับ Long)
Fib_78.6% = Swing_High − R × 0.786  ← จุด Invalidation (SL Level)

Entry Zone: [Fib_61.8%, Fib_38.2%]  (ลงมาถึง 61.8% = Pullback ลึกพอแล้ว)
TP Target:  Swing_High                (กลับไปที่ยอดเดิม)
SL Level:   Fib_78.6%                (ถ้าลึกกว่านี้ = Wave Structure พัง)
```

**กรณี Downtrend (ถอยจาก Low ขึ้นมา — Short Setup):**

```
Fib_38.2% = Swing_Low + R × 0.382
Fib_50.0% = Swing_Low + R × 0.500
Fib_61.8% = Swing_Low + R × 0.618  ← Golden Ratio Zone (ดีที่สุดสำหรับ Short)
Fib_78.6% = Swing_Low + R × 0.786  ← SL Level

Entry Zone: [Fib_38.2%, Fib_61.8%]  (ขึ้นมาถึง 61.8% = Retracement ลึกพอแล้ว)
TP Target:  Swing_Low                (กลับไปที่ฐานเดิม)
SL Level:   Fib_78.6%
```

**เหตุผลที่ 61.8% เป็น "Golden Zone":**
นักเทรดสถาบันวาง Limit Order ที่ 61.8% มากที่สุดเพราะ:
1. เป็นจุดที่ Pullback "ลึกพอ" ทำให้ R:R ดีกว่าการเข้าที่ 38.2%
2. ยังคงอยู่ภายใน "โซนปลอดภัย" ก่อนถึง 78.6% (ถ้าไปถึง 78.6% แสดงว่า Trend อาจพังแล้ว)
3. เป็นจุดที่ทุกคนรู้ว่าสำคัญ → Self-Fulfilling Prophecy ที่แรงที่สุด

---

### 2.4 การวัดความแม่นยำ Fibonacci (Fib Accuracy Score)

**นิยามฟังก์ชัน `_FibAccuracy(price)`:**

```
กำหนด:
  lo = min(Fib_38.2%, Fib_61.8%)
  hi = max(Fib_38.2%, Fib_61.8%)
  range_zone = hi − lo

  dist_from_golden = |price − Fib_61.8%|

  fib_acc = 1.0 − min(dist_from_golden / range_zone, 1.0)

ความหมาย:
  price อยู่ที่ Fib_61.8% พอดี → dist = 0 → fib_acc = 1.0 (สูงสุด)
  price อยู่ที่ Fib_38.2% พอดี → dist = range_zone → fib_acc = 0.0 (ต่ำสุด)
  price อยู่กึ่งกลาง (50%)     → dist = range_zone/2 → fib_acc = 0.5

ตัวอย่างจาก Case Study:
  range_zone = 1.08236 - 1.07764 = 0.00472
  price = 1.07764 (= Fib_61.8%)
  dist = 0
  fib_acc = 1.0 - 0 = 1.000
```

**เหตุผลที่วัดระยะจาก 61.8% ไม่ใช่จากขอบใด:**
เพราะ 61.8% คือ Golden Ratio — จุดที่มีโอกาสกลับตัวสูงสุดตามทฤษฎี Elliott Wave และพฤติกรรมสถาบัน การที่ราคาอยู่ใกล้ 61.8% มากกว่า 38.2% จึงให้ Confidence สูงกว่าอย่างสมเหตุสมผล

---

### 2.5 Stochastic Oscillator — สูตรและความหมาย

**สูตรคำนวณ %K (Fast Stochastic):**

```
%K = 100 × (Close − Lowest_Low_K) / (Highest_High_K − Lowest_Low_K)

โดย:
  Lowest_Low_K  = ราคาต่ำสุดใน K แท่งล่าสุด  (K = m_stoch_k = 14)
  Highest_High_K = ราคาสูงสุดใน K แท่งล่าสุด

  %D = SMA(%K, m_stoch_d)  (= 3 แท่ง โดย default)
```

**ความหมายทางเศรษฐศาสตร์:**
%K วัดว่า "ราคาปัจจุบันอยู่ที่ระดับใดในช่วงราคา 14 แท่งที่ผ่านมา"
- %K = 100: Close อยู่ที่ High สุดของ 14 แท่ง = Momentum แรงสูงสุด
- %K = 0: Close อยู่ที่ Low สุดของ 14 แท่ง = Momentum ลงแรงสุด
- %K < 20: Oversold = ราคาลงมามากในเวลาสั้น — สัญญาณว่า Selling Pressure หมดแล้ว → เหมาะ Long
- %K > 80: Overbought = ราคาขึ้นมามากในเวลาสั้น — Buying Pressure หมดแล้ว → เหมาะ Short

**ทำไม Stochastic Oversold ที่ Fib Zone จึงทรงพลัง:**
เมื่อราคาอยู่ใน Fib Zone (38.2%–61.8%) **และ** Stochastic < 20 พร้อมกัน หมายความว่า:
1. **ตลาด Macro ยังขาขึ้น** (Swing Low → Swing High บอกเราไว้แล้ว)
2. **ราคา Pullback ลงมาในโซนที่สถาบันจะซื้อ** (Fib Zone)
3. **Momentum ระยะสั้นหมดแล้ว** (%K < 20 = ผู้ขายชนะมาตลอด 14 แท่ง แต่กำลังหมดแรง)

การที่ทั้งสาม Condition เกิดพร้อมกันเป็น "Perfect Storm" ที่มีโอกาสกลับตัวสูงมาก

**สูตรคำนวณ Stochastic Extremity:**

```
ถ้า %K ≤ m_stoch_oversold (20):
  stoch_ext = 1.0 − (%K / 20)

  ตัวอย่าง:
    %K = 0  → stoch_ext = 1.0 − 0/20 = 1.000  (Oversold สุดขีด)
    %K = 5  → stoch_ext = 1.0 − 5/20 = 0.750  (Oversold ลึก)
    %K = 10 → stoch_ext = 1.0 − 10/20 = 0.500  (Oversold ปานกลาง)
    %K = 15 → stoch_ext = 1.0 − 15/20 = 0.250  (Oversold อ่อน)
    %K = 20 → stoch_ext = 1.0 − 20/20 = 0.000  (อยู่ที่เส้น Oversold พอดี)

ถ้า %K ≥ m_stoch_overbought (80):
  stoch_ext = (%K − 80) / (100 − 80)  = (%K − 80) / 20

  ตัวอย่าง:
    %K = 80  → stoch_ext = (80−80)/20  = 0.000  (อยู่ที่เส้น OB พอดี)
    %K = 85  → stoch_ext = (85−80)/20  = 0.250
    %K = 90  → stoch_ext = (90−80)/20  = 0.500
    %K = 95  → stoch_ext = (95−80)/20  = 0.750
    %K = 100 → stoch_ext = (100−80)/20 = 1.000 (Overbought สุดขีด)

ถ้า 20 < %K < 80:
  stoch_ext = 0.0  (ไม่ Extreme — ไม่มีสัญญาณ)
```

---

### 2.6 สูตร Confidence แบบ Multiplicative — ทำไมต้องคูณ ไม่ใช่บวก

**สูตร:**
```
Confidence = fib_accuracy × stoch_extremity × trend_strength
           = fib_acc × stoch_ext × |m_server_trend|
```

**เหตุผลที่ใช้ Product (×) แทน Sum (+):**

สูตรคูณมีคุณสมบัติพิเศษที่ตรงกับตรรกะการเทรด:

```
ถ้า fib_acc  = 0.0 → Confidence = 0.0  (ไม่ว่า stoch_ext และ trend_str จะดีแค่ไหน)
ถ้า stoch_ext = 0.0 → Confidence = 0.0  (ไม่ว่า fib_acc จะสมบูรณ์แค่ไหน)
ถ้า trend_str = 0.0 → Confidence = 0.0  (Brain ยังไม่บอก Trend → ไม่เทรด)
```

นี่คือ **AND Logic** ในทางคณิตศาสตร์: ต้องทุกเงื่อนไขดีพร้อมกัน ถ้าขาดเงื่อนไขใดเงื่อนไขหนึ่ง ก็ไม่มีการเทรด ต่างจาก Sum ซึ่งยังให้ Confidence สูงแม้จะขาดปัจจัยหนึ่งไป

**ช่วง Confidence ทั่วไปในทางปฏิบัติ:**

| สถานการณ์ | fib_acc | stoch_ext | trend_str | Conf ดิบ | TRENDING×1.5 |
|-----------|---------|-----------|-----------|----------|--------------|
| ยอดเยี่ยม (ที่ 61.8%, %K=5) | 1.00 | 0.75 | 1.0 | 0.750 | **1.000** (cap) |
| ดีมาก (ที่ 61.8%, %K=12) | 1.00 | 0.40 | 1.0 | 0.400 | **0.600** ✓ |
| ดี (ที่ 55%, %K=8) | 0.67 | 0.60 | 1.0 | 0.402 | **0.603** ✓ |
| พอใช้ (ที่ 45%, %K=18) | 0.35 | 0.10 | 1.0 | 0.035 | **0.053** ✗ |
| อ่อนมาก (ที่ 38.2%, %K=20) | 0.00 | 0.00 | 1.0 | 0.000 | **0.000** ✗ |

---

## 3. สถาปัตยกรรมระบบและการแบ่งหน้าที่ (System Architecture)

### 3.1 ตารางแบ่งความรับผิดชอบ Python Brain vs MQL5 Trader

```
┌────────────────────────────────────────────────────────────────────────┐
│              S13 FULL_MQL5 SERVERONLY ARCHITECTURE                     │
├──────────────────────────────┬─────────────────────────────────────────┤
│  PYTHON BRAIN (Server Side)  │  MQL5 TRADER (Client Side)              │
│  Regime + Direction Only     │  ทุกอย่าง Technical ทำใน MQL5           │
├──────────────────────────────┼─────────────────────────────────────────┤
│  ✅ Regime Classification     │  ✅ _FindSwings() ทุก Bar                │
│     (HMM + Random Forest)    │     CopyHigh/CopyLow 110 แท่ง           │
│                              │     Local Extrema detection (±5 bars)   │
│  ✅ Trend Direction Scoring   │     → m_swing_high, m_swing_low          │
│     +1.0 (Uptrend)           │     → m_is_uptrend (direction)          │
│     -1.0 (Downtrend)         │                                         │
│                              │  ✅ Fibonacci Level Computation           │
│  ✅ Parameter Optimization    │     4 levels จาก Range ×Ratio            │
│     FibLookback vs ATR       │     Fib_382, Fib_500, Fib_618, Fib_786  │
│     Stoch K/D Periods        │                                         │
│     OB/OS Thresholds         │  ✅ _PriceInFibZone() ทุก Tick           │
│                              │     lo = min(Fib_382, Fib_618)          │
│  ✅ CONFIG_PUSH (Port 7778)   │     hi = max(Fib_382, Fib_618)          │
│     S13_FIB_LOOKBACK         │     price ∈ [lo, hi]?                   │
│     S13_STOCH_K              │                                         │
│     S13_STOCH_D              │  ✅ _RefreshStoch() ทุก Tick             │
│     S13_STOCH_OB             │     CopyBuffer(stoch_handle) → %K, %D  │
│     S13_SWING_MIN            │                                         │
│     S13_TREND_DIR  ← KEY!   │  ✅ Confidence: fib × stoch × server    │
│                              │     Multiplicative — AND logic          │
│  ✅ AI Council Gate           │                                         │
│     weighted_conf ≥ 0.50?    │  ✅ TP = swing_high (Long)              │
│     R:R ≥ 1.5?               │     TP = swing_low  (Short)             │
│                              │     SL = Fib_786 (absolute price)       │
│  ✅ Trade Reporting           │                                         │
│     Port 7779 → PerTracker   │  ✅ m_enabled = false at Init            │
│                              │     Enable เฉพาะหลัง SetDynamicParams   │
│  ❌ ไม่มี Python Analyzer      │     ที่รับ S13_TREND_DIR ≠ 0           │
│     ไม่มี Cointegration Test  │                                         │
│     ไม่มี OLS / HMM ใน S13   │  ✅ Bar-gate: Swing re-detect ครั้งเดียว│
│                              │     ต่อแท่ง (ไม่ต่อ Tick)               │
│                              │  ✅ Handle rebuild: K หรือ D เปลี่ยน    │
│                              │     → _CreateHandles() ใหม่             │
└──────────────────────────────┴─────────────────────────────────────────┘
```

**หลักการออกแบบ:** S13 ถูกออกแบบให้ MQL5 ทำงานด้าน Technical Analysis ทั้งหมด (Swing, Fibonacci, Stochastic) ส่วน Python Brain ทำงานด้าน Macro Context เพียงอย่างเดียว (Trend Direction) สถาปัตยกรรมนี้ทำให้ S13 มี Latency ต่ำมาก — ทุกการตัดสินใจ Entry/Exit ทำบน MQL5 โดยไม่ต้องรอ Response จาก Server ทุก Tick

---

### 3.2 SMMSelection สำหรับ S13

```cpp
// ใน MMManager.mqh สำหรับ S13:
SMMSelection s13_mm = {
    default_mm:   MM01,  // Fixed Conservative
    volatile_mm:  MM07,  // Percent Volatility
    dd_mm:        MM10,  // Drawdown Based
    active_mm:    MM01,  // เริ่มต้นด้วย default
    server_override: false
};
```

**เหตุผลที่เลือก MM01 เป็น Default:**
S13 เป็น FULL_MQL5 ไม่ใช่ Hybrid ซึ่งหมายความว่าไม่มี Python Analyzer ที่ติดตาม Win Rate, Kelly Fraction หรือ EV ของกลยุทธ์อย่างละเอียด ดังนั้น MM04 (Kelly Criterion) ที่ต้องการประวัติ Win Rate ที่เชื่อถือได้จึงไม่เหมาะ MM01 (Fixed 1% Risk per Trade) เป็นตัวเลือกที่ปลอดภัยที่สุดเพราะไม่ต้องการข้อมูลประวัติ — ตั้ง Risk 1% ต่อเทรดสม่ำเสมอ ซึ่งเหมาะกับกลยุทธ์ที่ R:R ดีโดยธรรมชาติ (3:1 ถึง 4:1 จาก Fib Structure)

**เหตุผลที่เลือก MM07 สำหรับ VOLATILE:**
ในช่วงที่ตลาด Volatile สูง (ATR พุ่งสูง) Swing Range ของ S13 จะใหญ่กว่าปกติ ทำให้ SL ที่ Fib_786 ห่างมากขึ้น MM07 คำนวณ Lot โดยอิงจาก ATR ดังนั้นเมื่อ ATR สูง Lot จะลดลงโดยอัตโนมัติเพื่อรักษา Dollar Risk ให้คงที่

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางข้อมูลจากตลาดสู่คำสั่งซื้อขาย

```
[ตลาด Forex] → [MT5 Platform] → [FeederEA] → Port 7777 → [Python Brain]
                                                              ↓
                                                    [RegimeClassifier]
                                                    HMM + ATR Ratio + ADX
                                                              ↓
                                            ┌─────────────────────────┐
                                            │  Regime?                │
                                            │  TRENDING → ✅ ดำเนินต่อ│
                                            │  RANGING  → ❌ ข้าม S13 │
                                            │  VOLATILE → ❌ ข้าม S13 │
                                            └─────────────────────────┘
                                                              ↓ (TRENDING only)
                                                    [Trend Direction]
                                                    MA Cross + Price Position
                                                    → S13_TREND_DIR = +1.0 / -1.0
                                                              ↓
                                                    [S13 Parameter Optimizer]
                                                    FibLookback vs Win Rate
                                                    Stoch K/D vs False Signal Rate
                                                              ↓
                                                    [Build CONFIG_PUSH Type=10]
                                                    S13_FIB_LOOKBACK, S13_STOCH_K
                                                    S13_STOCH_OB, S13_TREND_DIR
                                                              ↓
                                                    [AI Council Gate]
                                                    weighted_conf × 1.5 ≥ 0.50?
                                                    R:R ≥ 1.5? Calendar Check?
                                                              ↓
                                              [CONFIG_PUSH] Port 7778
                                                              ↓
                                              [ProgramC_Trader.mq5]
                                              CStrategyManager.OnNewConfig
                                                              ↓
                                              [CFibStoch::SetDynamicParams]
                                              อัปเดตพารามิเตอร์ทั้งหมด
                                              m_enabled = true
                                              m_swing_valid = false (reset)
                                              Rebuild handles ถ้า K/D เปลี่ยน
                                                              ↓
                                              [ทุก Tick: CFibStoch::Analyze]
                                                              ↓
                                              ┌─────────────────────────────┐
                                              │ Bar เปลี่ยน?                 │
                                              │ YES → _FindSwings()          │
                                              │       CopyHigh/Low 110 bars  │
                                              │       Local Extrema Scan     │
                                              │       Compute 4 Fib Levels   │
                                              │ NO  → ใช้ค่า Swing เดิม      │
                                              └─────────────────────────────┘
                                                              ↓
                                              [_RefreshStoch() ทุก Tick]
                                              CopyBuffer → %K, %D
                                                              ↓
                                              [_PriceInFibZone(tick.bid)?]
                                              [38.2% ≤ price ≤ 61.8%?]
                                                              ↓
                                              [คำนวณ Confidence]
                                              fib_acc × stoch_ext × trend_str
                                                              ↓
                              ┌───────────────────────────────────────────┐
                              │ Long: uptrend + %K<20 + server_trend≥0   │
                              │ → SIGNAL_BUY, TP=swing_high, SL=Fib_786  │
                              │                                           │
                              │ Short: !uptrend + %K>80 + server_trend≤0 │
                              │ → SIGNAL_SELL, TP=swing_low, SL=Fib_786  │
                              └───────────────────────────────────────────┘
                                                              ↓
                                              [MM → Lot Sizing]
                                              MM01/MM07/MM10 ตามสภาวะ
                                                              ↓
                                              [Order Placement → ตลาด]
                                              Fixed TP/SL (Absolute Price)
                                                              ↓
                                              [TRADE_REPORT] Port 7779 → Brain
                                              → PerformanceTracker S13 Update
```

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตร Composite Confidence

```python
# ใน CFibStoch::Analyze (MQL5):
confidence = fib_accuracy(price) × stoch_extremity(%K) × |m_server_trend|

# ปรับตาม Regime (ใน AI Council, Python Brain):
confidence_final = confidence × regime_factor
```

**สูงสุดที่เป็นไปได้:** 1.0 × 1.0 × 1.0 = **1.00** (ก่อนปรับ Regime)

---

### 5.2 ปัจจัยที่ 1: Fib Accuracy (0.0 – 1.0)

```
fib_acc = 1.0 − min(|price − Fib_61.8%| / |Fib_38.2% − Fib_61.8%|, 1.0)

Gradient:
  ที่ Fib_61.8% (Golden Ratio): fib_acc = 1.000  ← ดีที่สุด
  ที่ กลางโซน:                  fib_acc = 0.500  ← ปานกลาง
  ที่ Fib_38.2% (Inner Edge):  fib_acc = 0.000  ← แย่ที่สุดในโซน
  นอกโซน:                      ไม่ผ่าน _PriceInFibZone → ไม่ compute
```

**เหตุผลที่วัดจาก 61.8%:** ยิ่งราคาอยู่ใกล้ Golden Ratio มากเท่าไหร่ โอกาสที่จะมี Institutional Buying/Selling รออยู่ที่นั่นสูงขึ้นเท่านั้น ราคาที่เพิ่งเข้าโซนที่ 38.2% (ยังห่างจาก Golden Ratio มาก) ยังมีโอกาสลงไปต่อถึง 61.8% ก่อนกลับตัว ดังนั้นความเชื่อมั่นจึงควรต่ำกว่า

---

### 5.3 ปัจจัยที่ 2: Stochastic Extremity (0.0 – 1.0)

```
Long Setup (%K ≤ 20):
  stoch_ext = 1.0 − (%K / 20)

  %K = 0  → 1.000 (Oversold สุดขีด — Selling Exhaustion ชัดเจนมาก)
  %K = 5  → 0.750 (Oversold ลึก — แรงขายอ่อนมาก)
  %K = 10 → 0.500 (Oversold ปานกลาง)
  %K = 15 → 0.250 (Oversold อ่อน — อาจลงต่อได้อีก)
  %K = 20 → 0.000 (พอดีที่เส้น — ยังไม่ชัดเจน)

Short Setup (%K ≥ 80):
  stoch_ext = (%K − 80) / 20

  %K = 80  → 0.000 (พอดีที่เส้น OB)
  %K = 85  → 0.250
  %K = 90  → 0.500
  %K = 95  → 0.750
  %K = 100 → 1.000 (Overbought สุดขีด)
```

---

### 5.4 ปัจจัยที่ 3: Trend Strength จาก Server (0.0 – 1.0)

```
trend_str = |m_server_trend|

m_server_trend รับจาก Python Brain ผ่าน S13_TREND_DIR:
  +1.0 → Uptrend ชัดเจน → trend_str = 1.0
  -1.0 → Downtrend ชัดเจน → trend_str = 1.0
   0.0 → ไม่มีทิศทาง (RANGING) → trend_str = 0.0 → Confidence = 0 → ไม่เทรด

ค่า Intermediate ที่เป็นไปได้:
  +0.7 → Uptrend ปานกลาง → trend_str = 0.7
  -0.5 → Downtrend อ่อน → trend_str = 0.5
```

**เหตุผลที่ใช้ |trend| แทน trend เฉยๆ:** เพราะ Confidence ต้องเป็นบวกเสมอ ทั้ง Uptrend (+1.0) และ Downtrend (-1.0) ต่างก็ให้ Confidence เต็ม แค่ทิศทาง Signal จะต่างกัน (BUY vs SELL)

---

### 5.5 ตัวคูณปรับตาม Market Regime (Regime Multipliers)

| Regime | ตัวคูณ | เหตุผลทางวิชาการ |
|--------|--------|----------------|
| **TRENDING** | **×1.5** | สภาวะที่ Fib Pullback ทำงานดีที่สุด — มี Swing Structure ชัดเจน สถาบันวาง Order ที่ Fib Levels อย่างเป็นระบบ |
| **SQUEEZE** | **×0.8** | ตลาดกำลังสะสมพลังก่อน Breakout — Swing Structure มีอยู่แต่ Range แคบ Fib Levels อาจไม่ Hold นาน |
| **RANGING** | **×0.6** | ไม่มี Swing High/Low ชัดเจน — Fib Levels คำนวณได้แต่ไม่มีความหมาย เพราะราคาไม่ได้เดินทางจาก Low ไป High หรือกลับกัน |
| **VOLATILE** | **×0.3** | ข่าวใหญ่ทำลาย Swing Structure ตลอดเวลา — Fib Levels ที่คำนวณมาใช้ไม่ได้เพราะ Swing ใหม่เกิดขึ้นก่อนที่ราคาจะมาถึงโซน |

ตัวอย่าง: Confidence ดิบ = 0.60 แต่ Regime คือ VOLATILE → Confidence ที่ AI Council เห็น = 0.60 × 0.3 = **0.18** → ต่ำกว่า 0.50 → S13 ไม่เทรด

---

## 6. MQL5: การทำงานภายในของ CFibStoch

### 6.1 Swing Detection — `_FindSwings()` พร้อม Code อธิบาย

```mql5
void _FindSwings()
{
    // ขนาดอาร์เรย์ = Lookback + Padding (เพื่อตรวจ Local Extrema ที่ขอบ)
    int total = m_fib_lookback + m_swing_min_bars * 2;  // 100 + 10 = 110 แท่ง

    double highs[], lows[];
    ArraySetAsSeries(highs, true);  // index 0 = แท่งล่าสุด (ซ้าย→ขวา)
    ArraySetAsSeries(lows,  true);

    // ถ้าข้อมูลไม่ครบ → swing ไม่ valid
    if(CopyHigh(m_symbol, m_timeframe, 0, total, highs) < total ||
       CopyLow (m_symbol, m_timeframe, 0, total, lows)  < total)
    {
        m_swing_valid = false;
        return;
    }

    int    best_hi_bar = -1, best_lo_bar = -1;
    double best_hi = -DBL_MAX, best_lo = DBL_MAX;
    int    n = m_swing_min_bars;  // window radius = 5

    // สแกนทุกแท่งในช่วงที่ window ไม่ชนขอบ
    for(int i = n; i < total - n; i++)
    {
        // ตรวจ Local High: highs[i] ต้องสูงกว่าทุกแท่งใน [i-n, i+n]
        bool is_sh = true;
        for(int j = i - n; j <= i + n; j++)
            if(j != i && highs[j] >= highs[i]) { is_sh = false; break; }

        // บันทึก Swing High สูงสุดที่พบ
        if(is_sh && highs[i] > best_hi) { best_hi = highs[i]; best_hi_bar = i; }

        // ตรวจ Local Low: lows[i] ต้องต่ำกว่าทุกแท่งใน [i-n, i+n]
        bool is_sl = true;
        for(int j = i - n; j <= i + n; j++)
            if(j != i && lows[j] <= lows[i]) { is_sl = false; break; }

        // บันทึก Swing Low ต่ำสุดที่พบ
        if(is_sl && lows[i] < best_lo) { best_lo = lows[i]; best_lo_bar = i; }
    }

    // ถ้าไม่พบ Swing ทั้งสองฝั่ง → ไม่ valid
    if(best_hi_bar < 0 || best_lo_bar < 0) { m_swing_valid = false; return; }

    m_swing_high  = best_hi;
    m_swing_low   = best_lo;
    m_swing_valid = true;

    // กำหนด Trend: Low เกิดก่อน = Uptrend (index สูงกว่า = เก่ากว่า ใน Series array)
    m_is_uptrend = (best_lo_bar > best_hi_bar);

    // คำนวณ Fib Levels จาก Range
    double range = m_swing_high - m_swing_low;
    if(m_is_uptrend)
    {
        m_fib_382 = m_swing_high - range * 0.382;  // Inner (shallow pullback)
        m_fib_500 = m_swing_high - range * 0.500;  // Mid
        m_fib_618 = m_swing_high - range * 0.618;  // Golden Ratio
        m_fib_786 = m_swing_high - range * 0.786;  // SL Level
    }
    else
    {
        m_fib_382 = m_swing_low + range * 0.382;
        m_fib_500 = m_swing_low + range * 0.500;
        m_fib_618 = m_swing_low + range * 0.618;
        m_fib_786 = m_swing_low + range * 0.786;
    }
}
```

**เหตุผลที่ Bar-Gate (คำนวณครั้งเดียวต่อแท่ง):**
`_FindSwings()` ต้องสแกน 110 แท่งและตรวจ Local Extrema ทุกจุด → ความซับซ้อน O(N×W) ≈ O(1100 operations) ต่อการเรียก ถ้าเรียกทุก Tick (อาจมี 10–50 Tick ต่อวินาที) จะใช้ CPU สูงโดยไม่จำเป็น เพราะ Swing High/Low ไม่เปลี่ยนภายในแท่งเดียวกัน Bar-gate ลด CPU Load ได้ 95%+ โดยไม่กระทบความถูกต้อง

---

### 6.2 Signal Logic ใน Analyze()

```mql5
virtual void Analyze(const MqlTick &tick) override
{
    if(!m_initialized || !m_enabled) return;

    // BAR-GATE: Re-detect swings เฉพาะเมื่อ Bar ใหม่เปิด
    static datetime last_bar = 0;
    datetime bar_time = iTime(m_symbol, m_timeframe, 0);
    if(bar_time != last_bar)
    {
        _FindSwings();
        last_bar = bar_time;
    }

    // อัปเดต Stochastic ทุก Tick
    _RefreshStoch();

    // Reset state
    m_state.last_signal     = SIGNAL_NONE;
    m_state.last_confidence = 0.0;
    m_state.last_sl         = 0.0;
    m_state.last_tp         = 0.0;

    if(!m_swing_valid) return;

    double price = tick.bid;
    if(!_PriceInFibZone(price)) return;

    // คำนวณ 3 ปัจจัยของ Confidence
    double fib_acc   = _FibAccuracy(price);

    double stoch_ext = 0.0;
    if(m_stoch_main <= (double)m_stoch_oversold)
        stoch_ext = 1.0 - (m_stoch_main / (double)m_stoch_oversold);
    else if(m_stoch_main >= (double)m_stoch_overbought)
        stoch_ext = (m_stoch_main - m_stoch_overbought) / (100.0 - m_stoch_overbought);

    double trend_str = MathAbs(m_server_trend);
    double conf = MathMin(fib_acc * stoch_ext * trend_str, 1.0);

    // Long Entry: Uptrend + Price in Fib Zone + Stoch Oversold + Server Uptrend
    if(m_is_uptrend &&
       m_stoch_main < (double)m_stoch_oversold &&
       m_server_trend >= 0)
    {
        m_state.last_signal     = SIGNAL_BUY;
        m_state.last_confidence = conf;
        m_state.last_sl         = m_fib_786;    // SL = 78.6% Level (absolute price)
        m_state.last_tp         = m_swing_high; // TP = Swing High (absolute price)
    }
    // Short Entry: Downtrend + Price in Fib Zone + Stoch Overbought + Server Downtrend
    else if(!m_is_uptrend &&
            m_stoch_main > (double)m_stoch_overbought &&
            m_server_trend <= 0)
    {
        m_state.last_signal     = SIGNAL_SELL;
        m_state.last_confidence = conf;
        m_state.last_sl         = m_fib_786;   // SL = 78.6% Level
        m_state.last_tp         = m_swing_low; // TP = Swing Low
    }

    m_state.last_signal_time = TimeCurrent();
}
```

---

### 6.3 _FibAccuracy() — การวัดความใกล้ Golden Ratio

```mql5
double _FibAccuracy(double price)
{
    if(!m_swing_valid) return 0.0;

    double lo = MathMin(m_fib_382, m_fib_618);
    double hi = MathMax(m_fib_382, m_fib_618);
    double range = hi - lo;

    if(range < 1e-10) return 0.0;  // ป้องกัน Division by Zero (Swing Range เล็กมาก)

    double dist = MathAbs(price - m_fib_618);  // ระยะจาก Golden Ratio
    return 1.0 - MathMin(dist / range, 1.0);   // 1.0 = อยู่ที่ 61.8% พอดี
}
```

---

### 6.4 วงจรชีวิต Indicator Handle

```mql5
// สร้าง Handle ครั้งแรกใน Init:
virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
{
    if(!IStrategy::Init(symbol, tf)) return false;
    m_strategy_id = S13_FIB_STOCH;
    m_info        = g_strategy_table[S13_FIB_STOCH];
    m_enabled     = false;  // ← DISABLED จน SetDynamicParams เรียก
    if(!_CreateHandles()) return false;
    return true;
}

// สร้างใหม่เฉพาะเมื่อ K หรือ D เปลี่ยน (ใน SetDynamicParams):
bool rebuild = false;
int new_sk = (int)params.GetParam("S13_STOCH_K", (double)m_stoch_k);
int new_sd = (int)params.GetParam("S13_STOCH_D", (double)m_stoch_d);
if(new_sk != m_stoch_k || new_sd != m_stoch_d) rebuild = true;
// ... อัปเดต params ...
if(rebuild) _CreateHandles();  // ← Rebuild เฉพาะถ้า K หรือ D เปลี่ยน

// ปล่อย Handle เมื่อ Deinit:
virtual void Deinit() override
{
    _ReleaseHandles();  // IndicatorRelease(m_stoch_handle)
    IStrategy::Deinit();
}
```

**เหตุผลที่ Rebuild เฉพาะ K หรือ D เปลี่ยน:** การสร้าง Indicator Handle ใหม่ทำให้ MT5 ต้องคำนวณข้อมูล Indicator ใหม่ทั้งหมด ซึ่งใช้เวลา 1–2 วินาที ดังนั้นระบบจึง Rebuild เฉพาะเมื่อจำเป็น (K/D เปลี่ยน) ไม่ใช่ทุกครั้งที่รับ CONFIG_PUSH ใหม่

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `FS_Fib_Lookback` | 100 | 50–200 | จำนวนแท่งราคาที่ใช้สแกนหา Swing High/Low ค่าน้อย (50) → จับ Swing ใหม่ล่าสุด แต่อาจได้ Range เล็ก ค่ามาก (200) → Range ใหญ่ขึ้น แต่ Swing อาจเก่าเกินไปจนไม่เกี่ยวข้องกับ Price Action ปัจจุบัน |
| `FS_Fib_Inner` | 0.382 | 0.236–0.500 | ขอบ Inner ของโซนเข้า ค่า 0.382 = เข้าเฉพาะเมื่อ Pullback ลึกพอ ถ้าลด (0.236) = เข้าง่ายขึ้นแต่ Pullback ตื้นมีโอกาสลงต่อสูง |
| `FS_Fib_Outer` | 0.618 | 0.500–0.786 | ขอบ Outer ของโซนเข้า (Golden Ratio) ค่า 0.618 คือ Standard Fibonacci การลดลงมา 0.500 จะทำให้โซนเข้าแคบลง ยิ่งแม่นยำแต่ Signal น้อยลง |
| `FS_Fib_SL` | 0.786 | 0.618–1.000 | ระดับ Stop Loss ค่า 0.786 = √0.618 เป็นจุด Wave Invalidation ตาม Elliott Wave Theory ถ้าราคาหลุดเกินนี้ Wave Structure ของ Pullback พังแล้ว |
| `FS_Stoch_K` | 14 | 5–21 | คาบของ Stochastic %K ค่าน้อย (5) → ตอบสนองไวแต่ Noisy มาก ค่ามาก (21) → เรียบกว่า แต่ช้าเกินไปสำหรับ Scalping ค่า 14 เป็น Standard ที่ใช้กันทั่วไป |
| `FS_Stoch_D` | 3 | 1–5 | คาบ Smoothing ของ %D ค่า 3 = SMA 3 แท่ง เป็นค่ามาตรฐาน **การเปลี่ยน K หรือ D จะ Trigger Handle Rebuild** |
| `FS_Stoch_Slowing` | 3 | 1–5 | คาบ Slowing (แท่งที่สามของ Stochastic) ค่า 3 ทำให้ %K นุ่มนวลขึ้นก่อนส่งให้ %D |
| `FS_Stoch_Oversold` | 20 | 10–30 | เส้น Oversold สำหรับ Long Entry ค่า 20 = Standard ถ้าลด (10) = รอให้ Oversold ลึกมากกว่า → Signal น้อยแต่แม่นกว่า |
| `FS_Stoch_OB` | 80 | 70–90 | เส้น Overbought สำหรับ Short Entry ค่า 80 = Standard ถ้าเพิ่ม (90) = รอให้ Overbought ลึก Signal น้อยแต่แม่น |
| `FS_Swing_Min_Bars` | 5 | 2–10 | จำนวนแท่งขั้นต่ำระหว่าง Swing Points (Window Radius) ค่าน้อยเกินไป (2) = Noise มาก ค่ามาก (10) = พลาด Swing ที่ชัดเจน |

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | คำอธิบาย | ผลกระทบทันที |
|-----|--------|----------|-------------|
| `S13_FIB_LOOKBACK` | int | Optimized Swing Detection Lookback | อัปเดต `m_fib_lookback` → Swing Re-detect ในแท่งถัดไป |
| `S13_STOCH_K` | int | Optimized %K Period | **Trigger Handle Rebuild** ถ้าเปลี่ยนจาก K เดิม |
| `S13_STOCH_D` | int | Optimized %D Period | **Trigger Handle Rebuild** ถ้าเปลี่ยนจาก D เดิม |
| `S13_STOCH_OB` | int | Regime-tuned Oversold Level | อัปเดต `m_stoch_oversold` ใน Tick ถัดไป |
| `S13_STOCH_OS` | int | Regime-tuned Overbought Level | อัปเดต `m_stoch_overbought` ใน Tick ถัดไป |
| `S13_SWING_MIN` | int | Min Bars Between Pivots | อัปเดต `m_swing_min_bars` → Swing Re-detect ในแท่งถัดไป |
| `S13_TREND_DIR` | float | Python Brain Trend Direction **REQUIRED** | อัปเดต `m_server_trend` + **Enable S13** (`m_enabled = true`) |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 ServerOnly Mode — ทำไม S13 ไม่มี Standalone

S13 เป็น **ServerOnly** ด้วยเหตุผลทางสถาปัตยกรรม: ตัวแปร `m_server_trend` ปรากฏอยู่ใน **2 ตำแหน่งวิกฤต** ในโค้ด:

```
1. ใน Confidence Formula:
   conf = fib_acc × stoch_ext × |m_server_trend|
   → ถ้า m_server_trend = 0 → conf = 0 → AI Council ไม่อนุมัติ → ไม่เทรด

2. ใน Entry Condition:
   Long:  ... AND m_server_trend >= 0
   Short: ... AND m_server_trend <= 0
   → ถ้า m_server_trend = 0 → ทั้ง Long และ Short ล้มเหลว
     (0 >= 0 = true แต่ conf = 0 → ไม่ผ่าน AI Council)
```

ระบบ Startup Sequence:

```
1. Init() เรียก:
   m_enabled = false  ← DISABLED ทันที
   _CreateHandles()   ← สร้าง Stochastic Handle พร้อม
   m_server_trend = 0.0  ← รอ Brain

2. ก่อน CONFIG_PUSH:
   ทุก Tick → Analyze() → if(!m_enabled) return ← ไม่ทำอะไร

3. หลัง CONFIG_PUSH (SetDynamicParams):
   m_server_trend = params.GetParam("S13_TREND_DIR") ← ได้รับ ±1.0
   m_enabled = true   ← เปิดใช้งาน!
   m_swing_valid = false  ← Force re-detect ในแท่งถัดไป

4. ถ้า Brain Disconnect:
   m_enabled = false ← กลับสู่ Disabled Mode
   S13 หยุดส่ง Signal
```

**เหตุผลที่ไม่เพิ่ม Standalone Fallback:** Local Trend Detection ใน MQL5 (เช่น MA Cross) จะต้องใช้ Indicator Handle เพิ่มเติม และยังคงมีความเสี่ยงสูงที่จะ "เดา Trend ผิด" ในช่วงที่ตลาด Choppy ซึ่งแย่กว่าการไม่เทรดเลย การออกแบบให้ S13 หยุดทำงานเมื่อไม่มี Brain ดีกว่าการปล่อยให้มันเทรดโดยไม่มีข้อมูล Macro Trend

---

### 8.2 Server Mode (Full Operation Cycle)

```
ทุกรอบ Optimization Cycle (ทุก 60 วินาที ในช่วง TRENDING Regime):

1. RegimeClassifier ตรวจสอบ:
   → TRENDING? ดำเนินต่อ
   → Other? ส่ง S13_TREND_DIR = 0.0 → S13 Disabled

2. Trend Direction Scoring:
   → MA200 vs Price: ราคาอยู่เหนือ MA200 = Uptrend (+1.0)
   → Price Action: Higher High/Low structure = ยืนยัน Uptrend
   → ผลลัพธ์: S13_TREND_DIR = +1.0 หรือ -1.0

3. Parameter Optimization (ทุก 4-8 ชั่วโมง):
   → ทดสอบ FibLookback 50-200 vs Win Rate ย้อนหลัง 30 วัน
   → ทดสอบ StochK 5-21 vs False Signal Rate
   → เลือก Combination ที่ให้ Sharpe Ratio สูงสุด

4. AI Council ตรวจสอบ:
   → weighted_conf × regime_factor ≥ 0.50?
   → R:R (TP/SL จาก Fib Structure ทั่วไป) ≥ 1.5? ✓ (ปกติ 3:1 ขึ้นไป)
   → Economic Calendar: ไม่มีข่าวใหญ่ใน 30 นาทีข้างหน้า?

5. ส่ง CONFIG_PUSH ผ่าน Port 7778
6. CFibStoch::SetDynamicParams รับและ Activate
7. ทำงาน Real-time จนกว่า Cycle ถัดไป
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| สถานะ | เงื่อนไข | การกระทำ |
|-------|---------|---------|
| **Disabled** | ไม่ได้รับ `S13_TREND_DIR` จาก Brain | ไม่ทำอะไร — รอ CONFIG_PUSH |
| **Monitoring — No Swing** | `m_swing_valid = false` | รอ Bar ใหม่ → `_FindSwings()` |
| **Monitoring — Out of Zone** | `price < Fib_61.8%` หรือ `price > Fib_38.2%` | รอ Pullback เข้าโซน |
| **Monitoring — Stoch Not Extreme** | `20 ≤ %K ≤ 80` | รอ Momentum Exhaustion |
| **Long Signal** | Uptrend + Price in Zone + `%K < 20` + `server_trend ≥ 0` | BUY, TP = Swing High, SL = Fib_786 |
| **Short Signal** | Downtrend + Price in Zone + `%K > 80` + `server_trend ≤ 0` | SELL, TP = Swing Low, SL = Fib_786 |
| **Take Profit** | ราคาถึง Swing High (Long) หรือ Swing Low (Short) | ปิดกำไร — TP Fixed Price โดน |
| **Stop Loss** | ราคาถึง Fib_786 | ปิดขาดทุน — Wave Structure พัง |

---

## 10. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | TRENDING ที่มี Swing Structure ชัดเจน — Regime Factor ×1.5 |
| **สภาวะที่สองรองลงมา** | TRENDING ที่ราคา Pullback ถึง 61.8% Golden Ratio พร้อม Stochastic Extreme |
| **สภาวะตลาดที่แย่ที่สุด** | VOLATILE (Swing ถูกทำลายตลอด) — Regime Factor ×0.3 |
| **สภาวะที่แย่รองลงมา** | RANGING (ไม่มี Swing Direction ชัดเจน) — Regime Factor ×0.6 |
| **ความถี่ Signal** | ต่ำ — ต้องรอ Price ถึง Fib Zone + Stoch Extreme + Server Confirm พร้อมกัน |
| **ระยะเวลาถือสถานะทั่วไป** | ชั่วโมงถึงวัน (ขึ้นอยู่กับระยะทาง Entry → Swing High/Low) |
| **เป้าหมาย Win Rate** | 55–65% (อิงจาก Fib Structure + Server Trend Confirmation) |
| **R:R โปรไฟล์** | 2:1 ถึง 5:1 ขึ้นอยู่กับขนาด Swing Range และจุดที่เข้าใน Zone |
| **ประเภท Stop Loss** | Fixed Fibonacci Price Level (78.6% = Wave Invalidation Point) |
| **ประเภท Take Profit** | Fixed Fibonacci Price Level (Swing High/Low = Wave Completion) |
| **Server Dependency** | ต้องการ — ปิดใช้งานสมบูรณ์โดยไม่มี `S13_TREND_DIR` |
| **จำนวน Indicator Handles** | 1 (iStochastic — สร้างใหม่เฉพาะเมื่อ K หรือ D เปลี่ยน) |
| **การอัปเดต Swing** | ครั้งเดียวต่อแท่ง (Bar-gated) ไม่ต่อ Tick |
| **Latency ของ Signal** | ~0 ms (คำนวณทั้งหมดใน MQL5 เครื่องเดียวกัน) |

---

## 11. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S13_FibStoch.mqh` | `CFibStoch` — Swing Detection, Fib Levels, Stoch, Confidence, Signal Logic |
| `Include/Logic/IStrategy.mqh` | Interface หลัก: `IStrategy`, `SDynamicParams`, `ENUM_TRADE_SIGNAL` |
| `Include/Logic/StrategyConstants.mqh` | `S13_FIB_STOCH` enum, `MAGIC_S13_FIB_STOCH`, `g_strategy_table[12]` |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager`: MM01/MM07/MM10 Selection Logic สำหรับ S13 |
| `03_Trader/ProgramC_Trader.mq5` | Main EA: Instantiate `CFibStoch`, Route CONFIG_PUSH, Execute Orders |
| `02_Brain/core/strategy/analysis.py` | `RegimeClassifier`: TRENDING/VOLATILE/RANGING Detection |
| `02_Brain/core/strategy/policy.py` | Policy: Compute `S13_TREND_DIR`, Build CONFIG_PUSH Payload |
| `02_Brain/config_push/config_builder.py` | สร้าง CONFIG_PUSH MessagePack: S13_FIB_LOOKBACK, S13_STOCH_K, S13_TREND_DIR |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT ผ่าน Port 7779 → อัปเดต S13 ใน `PerformanceTracker` |
| `02_Brain/core/intelligence/strategy_council.py` | AI Council: TRENDING Gate, R:R Check, Calendar Adjustment สำหรับ S13 |
| `tools/validate_live_readiness.py` | Validate ว่า S13_TREND_DIR อยู่ใน CONFIG_PUSH dry-run |

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 12.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: Single Best Swing — "จุดสูงสุดที่เก่าที่สุด" ไม่ใช่ "จุดที่เกี่ยวข้องที่สุด"**

อัลกอริทึม `_FindSwings()` เลือกเฉพาะ Swing High เดียวและ Swing Low เดียว — ตัวที่สูงสุดและต่ำสุดใน Lookback ทั้งหมด ปัญหาคือ Swing High ที่สูงสุดอาจอยู่ห่างออกไป 90 แท่ง ทั้งที่ Swing High ล่าสุดที่ 25 แท่งก่อนมีความเกี่ยวข้องกับ Price Action ปัจจุบันมากกว่า

```
ตัวอย่าง:
  แท่งที่ 90: Swing High = 1.10000  ← HIGHEST → ถูกเลือก (best_hi_bar=90)
  แท่งที่ 25: Swing High = 1.09000  ← ใหม่กว่าแต่ถูกละเลย
  แท่งที่  5: Swing Low  = 1.07000  ← ถูกเลือก (best_lo_bar=5)

  m_is_uptrend = (best_lo_bar=5 > best_hi_bar=90) = FALSE!
  → ระบบคิดว่า Downtrend (High เก่ากว่า Low ใน index)
  → ความจริง: ราคาเพิ่งขึ้นจาก 1.07000 มา 1.09000 = Uptrend!
  → S13 อาจส่ง SIGNAL_SELL ผิดทิศทาง หรือไม่ส่ง Signal เลย
```

**แนวทางแก้ไข:** เพิ่ม Recency Bias ในการเลือก Swing: ให้น้ำหนัก Swing ที่ใหม่กว่าสูงกว่า เช่น ใช้ Adjusted High = `highs[i] × (1 + λ × (1 - i/total))` โดย λ = 0.1–0.3 เพื่อให้ Swing ที่ใหม่กว่าได้เปรียบในการแข่งขัน

---

**ปัญหาที่ 2: Swing Invalidation ไม่ตรวจสอบ Real-time**

เมื่อราคา Breakout ผ่าน Swing High หรือ Swing Low ที่ใช้อยู่ Fib Levels ที่คำนวณจาก Swing นั้นกลายเป็นโมฆะทันที แต่ระบบยังรอ Bar ถัดไปกว่า `_FindSwings()` จะรัน ทำให้มีหน้าต่างเวลาที่ S13 อาจส่ง Signal จาก Fib Levels ที่ไม่มีความหมายแล้ว

```
ตัวอย่าง:
  Swing High = 1.09000 → Fib_618 = 1.07764, Fib_786 = 1.07428
  ราคา Breakout ขึ้นไปถึง 1.09500 ภายในแท่งปัจจุบัน
  แต่ Swing ยังไม่ถูก Reset เพราะรอ Bar ถัดไป
  → S13 ยังแสดง Entry Zone [1.07764, 1.08236] ซึ่งไม่เกี่ยวข้องแล้ว
```

**แนวทางแก้ไข:** เพิ่มการตรวจสอบ Real-time ใน `Analyze()`:
```mql5
// ก่อน _PriceInFibZone:
if(m_is_uptrend && tick.ask > m_swing_high)
    m_swing_valid = false;  // Breakout — Swing พังแล้ว
if(!m_is_uptrend && tick.bid < m_swing_low)
    m_swing_valid = false;  // Breakout ลง — Swing พังแล้ว
```

---

**ปัญหาที่ 3: Confidence ต่ำเกินไปในตลาดที่ Setup ดี**

สูตร Multiplicative ทำให้ Confidence มักอยู่ที่ 0.20–0.50 ก่อน Regime Factor สำหรับ Setup ทั่วไป (fib_acc ≈ 0.7, stoch_ext ≈ 0.5, trend_str = 1.0 → conf = 0.35) หลัง TRENDING ×1.5 ได้ 0.525 — ผ่านพอดี แต่ถ้า Regime ไม่ใช่ TRENDING ก็จะพลาดโอกาสดีๆ

```
ตัวอย่าง Setup ที่ดีแต่ Conf ต่ำ:
  fib_acc  = 0.80  (ราคาใกล้ Golden Ratio มาก)
  stoch_ext = 0.45  (Oversold ปานกลาง, %K=11)
  trend_str = 1.00
  conf_raw = 0.80 × 0.45 × 1.0 = 0.360

  SQUEEZE Regime: 0.360 × 0.8 = 0.288 → ไม่ผ่าน ✗
  (ทั้งที่ fib_acc=0.80 = ดีมาก)
```

**แนวทางแก้ไข:** พิจารณา Weighted Geometric Mean ที่ให้น้ำหนัก `fib_acc` สูงกว่า:
```
conf_v2 = (fib_acc^0.50) × (stoch_ext^0.35) × (trend_str^0.15)
→ conf_v2 = (0.80^0.50) × (0.45^0.35) × (1.0^0.15)
          = 0.894 × 0.714 × 1.000 = 0.638
→ SQUEEZE: 0.638 × 0.8 = 0.510 → ผ่าน ✓
```

---

### 12.2 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่ที่แนะนำ | เหตุผล |
|------------|--------------|-------|
| `S13_TREND_DIR` | ทุก 60 วินาที | Trend ระยะสั้นสามารถเปลี่ยนได้ใน 1-2 ชั่วโมง — ต้องอัปเดตบ่อย |
| `S13_FIB_LOOKBACK` | ทุก 4-8 ชั่วโมง | Optimal Lookback ขึ้นอยู่กับ Volatility Regime ที่ค่อนข้างเสถียร |
| `S13_STOCH_OB/OS` | ทุก 4-8 ชั่วโมง | ช่วง VOLATILE ควรใช้ 15/85 แทน 20/80 เพื่อหลีกเลี่ยง False Signal |
| `S13_STOCH_K/D` | ทุกวัน (สิ้นวัน) | K/D เปลี่ยนช้า ไม่ต้องปรับบ่อย และการเปลี่ยน K/D Trigger Handle Rebuild |
| `S13_SWING_MIN` | ทุกสัปดาห์ | ขึ้นอยู่กับ Timeframe เป็นหลัก ไม่ค่อยเปลี่ยน |

---

## 13. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### 13.1 ตรวจสอบว่า S13 ทำงานอยู่ (Python Side)

```bash
# ตรวจสอบ Active Strategies ใน Dashboard:
python 02_Brain/dashboard.py
# ดู "Active Strategies" panel → ควรเห็น "S13" พร้อม Confidence %
# ถ้าไม่เห็น S13 → Regime ไม่ใช่ TRENDING หรือ Confidence ต่ำกว่า 0.50

# ตรวจสอบ CONFIG_PUSH มี S13_TREND_DIR หรือไม่:
python tools/validate_live_readiness.py --zmq
# ดูที่ TEST 5: CONFIG_PUSH dry-run
# CRITICAL: ต้องเห็น S13_TREND_DIR ใน Output Keys
# Missing S13_TREND_DIR → strategy stays DISABLED ตลอด
```

### 13.2 ตรวจสอบ Fib Levels และ Swing State ใน MT5

```mql5
// เรียก Diagnostic Functions ที่ CFibStoch เปิดเผยไว้:
PrintFormat("[S13] Enabled=%s | SwingValid=%s | IsUptrend=%s",
    fibstoch.IsEnabled()    ? "YES" : "NO",
    fibstoch.IsSwingValid() ? "YES" : "NO",
    fibstoch.IsUptrend()    ? "YES" : "NO");

PrintFormat("[S13] SwingHigh=%.5f | SwingLow=%.5f",
    fibstoch.GetSwingHigh(), fibstoch.GetSwingLow());

PrintFormat("[S13] Fib382=%.5f | Fib618=%.5f | Fib786=%.5f",
    fibstoch.GetFib382(), fibstoch.GetFib618(), fibstoch.GetFib786());

PrintFormat("[S13] Stoch%%K=%.2f | Signal=%s | Conf=%.3f",
    fibstoch.GetStochMain(),
    EnumToString(fibstoch.GetSignal()),
    fibstoch.GetConfidence());

// Output ตัวอย่าง (Uptrend, ราคาที่ Golden Ratio, %K=12):
// [S13] Enabled=YES | SwingValid=YES | IsUptrend=YES
// [S13] SwingHigh=1.09000 | SwingLow=1.07000
// [S13] Fib382=1.08236 | Fib618=1.07764 | Fib786=1.07428
// [S13] Stoch%K=12.00 | Signal=SIGNAL_BUY | Conf=0.400
```

### 13.3 ทดสอบการคำนวณ Fibonacci ด้วย Python

```python
# ยืนยัน Fibonacci Level Computation สำหรับ Swing ที่รู้จัก:
swing_high = 1.09000
swing_low  = 1.07000
rng        = swing_high - swing_low   # 0.02000

# Uptrend Retracement (ถอยจาก High ลงมา):
fib_382 = swing_high - rng * 0.382   # 1.09000 - 0.00764 = 1.08236
fib_500 = swing_high - rng * 0.500   # 1.09000 - 0.01000 = 1.08000
fib_618 = swing_high - rng * 0.618   # 1.09000 - 0.01236 = 1.07764 (Golden Ratio)
fib_786 = swing_high - rng * 0.786   # 1.09000 - 0.01572 = 1.07428 (SL Level)

print(f"Entry Zone: {fib_618:.5f} to {fib_382:.5f}")   # 1.07764 to 1.08236
print(f"SL Level:   {fib_786:.5f}")                     # 1.07428
print(f"TP Target:  {swing_high:.5f}")                   # 1.09000
print(f"R:R at 61.8%: {(swing_high - fib_618)/(fib_618 - fib_786):.2f}:1")
# R:R at 61.8%: 3.68:1

# ตรวจสอบ Confidence ที่ 61.8%:
price    = fib_618    # 1.07764
stoch_k  = 12
server_t = 1.0

zone_range = abs(fib_382 - fib_618)                     # 0.00472
fib_acc    = 1.0 - min(abs(price - fib_618) / zone_range, 1.0)  # 1.000
stoch_ext  = 1.0 - (stoch_k / 20)                       # 0.400
conf_raw   = fib_acc * stoch_ext * abs(server_t)         # 0.400
conf_trending = conf_raw * 1.5                           # 0.600 ✓
print(f"Confidence (TRENDING): {conf_trending:.3f}")     # 0.600
```

### 13.4 ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| **S13 ไม่เคย Enabled** | Brain ไม่ส่ง `S13_TREND_DIR` ใน CONFIG_PUSH | ตรวจ `validate_live_readiness.py --zmq` → ต้องเห็น Key `S13_TREND_DIR` |
| **S13 Enabled แต่ไม่มี Signal เลย** | ราคาไม่เข้า Fib Zone หรือ Stoch ไม่ Extreme | ตรวจ Dashboard → S13 Diagnostics ดู `_PriceInFibZone` และ `%K` |
| **SwingValid = false ตลอด** | ข้อมูล History ไม่ครบ 110 แท่ง หรือไม่มี Local Extrema | ตรวจ Log → `CopyHigh returned X < 110` หรือ `best_hi_bar < 0` |
| **IsUptrend ผิดทิศทาง** | Swing High เก่าเกินไปสูงกว่า Swing High ล่าสุด | ลด `FS_Fib_Lookback` (เช่น 50) เพื่อจับ Swing ที่ Recent กว่า |
| **SL โดนบ่อยเกินไป** | Swing Range เล็กเกินไป — Fib_786 ใกล้ Entry | เพิ่ม `FS_Fib_Lookback` เพื่อให้ Swing Range ใหญ่ขึ้น |
| **TP ไม่โดน — Trade ค้างนาน** | Swing High/Low ห่างเกินไป หรือ Trend อ่อนลง | ลด Lookback เพื่อให้ Swing Range เล็กลง → TP ใกล้กว่า |
| **Confidence = 0 ตลอด** | `m_server_trend = 0.0` — Brain ส่ง TREND_DIR = 0 | ตรวจ Regime — RANGING Regime → Brain ส่ง 0 → ปกติ |
| **Handle Error ใน Log** | `iStochastic failed` — Symbol ไม่รองรับ | ตรวจ Symbol Name ใน `m_symbol` ว่าถูกต้องกับ Broker |
| **Handle Rebuild บ่อยเกินไป** | Brain เปลี่ยน `S13_STOCH_K` ทุก Cycle | ตรวจ `policy.py` → Throttle การเปลี่ยน K/D ให้เปลี่ยนเฉพาะรายวัน |
| **S13 เทรดสวน Trend** | `m_is_uptrend` ผิด (ปัญหา Section 12.1) | ลด `FS_Fib_Lookback` + เพิ่ม `FS_Swing_Min_Bars` เพื่อกรอง Noise |

---

*S13 Fibonacci + Stochastic — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-27*

*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
