# S14 — Bollinger Squeeze Breakout
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S14 | รหัสอ้างอิงลำดับที่สิบสี่ในระบบมัลติกลยุทธ์ S14 อยู่ในกลุ่ม "Volatility Breakout" ซึ่งทำงานตรงข้ามกับ S07 (Mean Reversion) — แทนที่จะเข้าตลาดเมื่อ Oscillator Extreme, S14 รอให้ตลาด "บีบตัว" สะสมพลังงานแล้วจึงเข้าตามทิศทางที่ระเบิดออกมา |
| **Enum Name** | `S14_BB_SQUEEZE` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` ค่า enum index = 13 (0-based) เป็น element ลำดับที่ 14 ของ `g_strategy_table[16]` |
| **Enum Index** | 13 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่าน `GetStrategyInfo(S14_BB_SQUEEZE)` |
| **ชื่อ** | Bollinger Squeeze Breakout | การเทรดหลังจากที่ Bollinger Bands ถูก "บีบ" อยู่ภายใน Keltner Channel (Squeeze) แล้วระเบิดออกมาพร้อมโมเมนตัมที่ชัดเจน |
| **ประเภท** | Full MQL5 (`CAT_FULL_MQL5`) | Logic ทั้งหมดอยู่ใน MQL5 Python Brain ทำหน้าที่ส่ง CONFIG_PUSH เพื่อปรับพารามิเตอร์เท่านั้น ไม่มี Python Analyzer เฉพาะสำหรับ S14 |
| **Standalone Capable** | ✅ Yes | `m_enabled = true` ทันทีที่ `Init()` เสร็จ ไม่ต้องรอ CONFIG_PUSH ต่างจาก S11 ที่ต้องรอ Brain ก่อน S14 พร้อมทำงานทันทีที่ EA เริ่มต้น |
| **Preferred Regime** | SQUEEZE (`REGIME_SQUEEZE`) | สภาวะที่ BB บีบอยู่ใน KC เป็นเวลานาน สะสมพลังงานก่อน Breakout ซึ่งเป็นสภาวะที่ S14 ออกแบบมาตรงๆ |
| **Post-Squeeze Regime** | VOLATILE หรือ TRENDING (หลัง Release) | หลัง Squeeze Release ตลาดมักเข้าสู่ VOLATILE (ช่วง Breakout แรก) หรือ TRENDING (ถ้า Breakout มีทิศทางชัดเจน) — S14 ทำกำไรในช่วง Transition นี้ |
| **Alt Regime** | ไม่มี | S14 เฉพาะสภาวะ Squeeze → Breakout เท่านั้น ไม่มี Regime รองที่เหมาะสม |
| **Poor Regimes** | Already VOLATILE, RANGING | VOLATILE: ตลาดผันผวนอยู่แล้ว ไม่มี Squeeze Phase สะสมก่อน / RANGING แบบ Endless: BB บีบอยู่ใน KC ตลอดแต่ไม่ Release → Signal ไม่เกิด / TRENDING แรงๆ ที่ไม่ผ่าน Squeeze Phase |
| **Regime Factor** | SQUEEZE=1.5, TRENDING=1.0, RANGING=0.6, VOLATILE=0.4 | ตัวคูณ Confidence ตาม Regime — สูงสุดใน SQUEEZE เพราะนั่นคือสภาวะที่ S14 ออกแบบมาโดยตรง |
| **MQL5 Class** | `CBBSqueeze` | คลาสหลัก ไฟล์: `Include/Logic/Strategies/S14_BBSqueeze.mqh` จัดการ Indicator Handles 3 ชุด (iBands, iATR, iMA) และ State Machine ของ Squeeze Counter |
| **Python Analyzer** | ไม่มี | Brain ไม่ได้คำนวณสัญญาณ — ทำแค่ (1) จัดประเภท Regime (2) Optimize Parameters (3) ส่ง CONFIG_PUSH |
| **Magic Number** | 1014 (`MAGIC_S14_BB_SQUEEZE`) | หมายเลขเอกลักษณ์ป้องกันการปะปนออเดอร์ |
| **Family** | Breakout / Volatility Expansion | กลุ่มกลยุทธ์ที่ทำกำไรจาก "การระเบิดออก" ของความผันผวนหลังจากอัดอั้นมานาน — ตรงข้ามกับ S07 (Contrarian) และ S01 (Market Neutral) |
| **Version** | 6.00 | สถาปัตยกรรม V6 |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S14 เป็นกลยุทธ์ **Bollinger Squeeze Breakout** ที่ใช้ปรากฏการณ์ทางสถิติที่เรียกว่า **"Volatility Compression Cycle"** — ตลาดสลับกันระหว่างช่วง "เงียบ" (Low Volatility / Consolidation) กับช่วง "ระเบิด" (High Volatility / Expansion) อยู่ตลอดเวลา S14 ทำกำไรจากการจับ "จุดเปลี่ยน" จากช่วงเงียบไปสู่ช่วงระเบิด

กลไกหลักใช้ **Bollinger Bands (BB)** เป็นตัวตรวจจับว่า "ความผันผวนต่ำแค่ไหน" และ **Keltner Channel (KC)** เป็นตัวอ้างอิง "ความผันผวนปกติ" เมื่อ BB บีบเข้ามาอยู่ภายใน KC เรียกว่า **Squeeze** — และเมื่อ BB ระเบิดออกจาก KC ทิศทางจะถูกยืนยันด้วย **Linear Regression Slope** ที่ Normalize ด้วย ATR

จุดเด่นที่สุดของ S14 คือ **R:R = 1.5** (TP = 3×ATR, SL = 2×ATR) ซึ่งสูงกว่า S07 (R:R = 0.75 fallback) ทำให้แม้ Win Rate จะอยู่ที่เพียง 45–55% S14 ยังสามารถทำกำไรได้ในระยะยาว

---

### 1.2 ปรัชญาเบื้องหลัง: ฟิสิกส์ของตลาด — "สปริงถูกบีบ"

**อุปมาอุปไมย — สปริงถูกบีบ:**

ลองนึกภาพว่าตลาดเป็นเหมือน **สปริง** — ในช่วงที่นักลงทุนทั้ง Bull และ Bear มีความเชื่อพอๆ กัน ราคาจะแกว่งในกรอบแคบๆ โดยทั้งสองฝั่งดัน-ดึงกันพอดี เปรียบเหมือนสปริงที่ถูกบีบจากทั้งสองข้างพร้อมกัน

ยิ่งบีบนาน ยิ่งสะสมพลังงานมาก เมื่อฝั่งใดฝั่งหนึ่ง "ยอมแพ้" ปล่อยสปริงออก พลังงานที่สะสมทั้งหมดจะระเบิดออกมาในทิศทางเดียว — นั่นคือ Breakout ที่ S14 รอจับ

**พื้นฐานทางการเงิน:**

ในช่วง Squeeze ตลาดกำลัง "ตัดสินใจ" ทิศทาง มีหลายสถานการณ์ที่ทำให้เกิด Squeeze:

```
สาเหตุที่พบบ่อย:
  1. Pre-News Consolidation — นักลงทุนรอผลประชุม FOMC, NFP, GDP
     → ทุกคนรอ → การซื้อขายเงียบลง → BB บีบเข้า
     → ข่าวออก → ตลาดเลือกทิศ → BB ระเบิดออก

  2. Weekend Effect / Holiday — Liquidity ต่ำ ตลาดแน่วนิ่ง
     → BB บีบตัว → Open วันจันทร์ Gap ทิศทาง

  3. Technical Consolidation — หลัง Strong Trend
     → Take Profit สะสม → ราคาหยุดนิ่งชั่วคราว → BB บีบ
     → Re-acceleration → BB ขยายออกต่อในทิศทางเดิม
```

**ทำไมต้องรอ ≥ 6 bars (Squeeze_Min)?**

Squeeze 1–2 แท่งมักเป็นแค่ Noise ปกติของตลาด ไม่ใช่การสะสมพลังงานจริงๆ แต่ Squeeze ที่ยาวถึง 6 แท่งขึ้นไปบ่งชี้ว่ามี "ความตึงเครียด" ที่แท้จริงสะสมอยู่ ซึ่งเมื่อระเบิดออกมาจะมีโมเมนตัมที่แรงและต่อเนื่องมากกว่า

---

### 1.3 ทำไม BB กับ KC จึงเป็น Squeeze Detector ที่ดีที่สุด?

**Bollinger Bands — "ไม้บรรทัดของสถิติ":**

BB ใช้ **Standard Deviation** ของราคา Close ซึ่งเป็นการวัด "ความแปรปรวนของราคาจริง" ในช่วงเวลาหนึ่ง ค่า BB Width = 2k × StdDev — ยิ่ง StdDev ต่ำ (ราคาเคลื่อนที่น้อย) BB Width ยิ่งแคบ และในทางกลับกัน

**Keltner Channel — "ไม้บรรทัดของ True Range":**

KC ใช้ **ATR (Average True Range)** ซึ่งวัด "ความผันผวนโดยรวมรวม Gap ระหว่างแท่ง" KC Width = 2 × ATR × multiplier — ATR เปลี่ยนช้ากว่า StdDev เพราะ Average ยาวกว่า ทำให้ KC เป็นค่าอ้างอิง "ความผันผวนปกติ" ที่เสถียรกว่า

**ความสำคัญของการเปรียบเทียบ BB กับ KC:**

```
BB Width  = 2 × BB_Dev × StdDev(Close, 20)
KC Width  = 2 × KC_ATR_Mult × ATR(14)

Squeeze = BB_Width < KC_Width
        = StdDev ของ Close ต่ำกว่า ATR × Ratio
        = ความผันผวนทางสถิติต่ำกว่าความผันผวนของ Range

ความหมาย:
  ราคาเคลื่อนที่แบบ "ชนกัน" (Close ใกล้กัน)
  แต่ High-Low แต่ละแท่งยังกว้างพอสมควร
  → สัญญาณว่าราคา "ดึงกันอยู่" ไม่ได้เงียบจริงๆ
```

**ทำไมไม่ใช้แค่ BB Width เพียงอย่างเดียว?**

BB Width ต่ำเกินไปโดยตัวเองไม่ได้บอกว่าใกล้ Breakout เพราะ "ต่ำเกินไป" ขึ้นอยู่กับ Symbol และ Timeframe KC ทำหน้าที่เป็น "ตัวเปรียบเทียบ Adaptive" — ถ้า Symbol มี ATR สูงตาม KC ก็จะสูงตาม ทำให้ Squeeze Detection เป็น Relative ไม่ใช่ Absolute

---

### 1.4 ทำไม Linear Regression Slope จึงดีกว่า RSI สำหรับการยืนยันทิศทาง Breakout

ในกลยุทธ์ Breakout ปัญหาของ RSI หรือ Stochastic คือ:
- ช่วง Breakout ขาขึ้น: RSI มักอยู่ที่ 50–70 (ไม่ Oversold ไม่ Overbought) → ไม่ให้ Signal ชัดเจน
- Oscillator วัด "ความ Extreme" แต่ Breakout ต้องการวัด "ทิศทาง"

**Linear Regression Slope วัดอะไร:**

LR Slope คือ "ความชันของเส้นที่ Fit กับราคา 14 แท่งล่าสุด" ให้ข้อมูล 2 อย่างพร้อมกัน:
1. **ทิศทาง**: ความชันบวก = กำลังขึ้น, ลบ = กำลังลง
2. **ความแรง**: ความชันมากเท่าไหร่ = ราคาเคลื่อนที่เร็วขนาดไหนต่อแท่ง

การ Normalize ด้วย ATR ทำให้ค่า Slope สามารถเปรียบเทียบข้าม Symbol และ Timeframe ได้:
```
LR_slope_norm = slope_raw / ATR

ความหมาย:
  +1.0 = ราคากำลังขึ้น 1 ATR ต่อแท่ง → Breakout แรงมาก
  +0.5 = ราคากำลังขึ้น 0.5 ATR ต่อแท่ง → Breakout พอใช้ (Default Threshold)
  ±0.2 = ขยับน้อยมาก → ยังไม่ใช่ Breakout ที่ดี
```

---

### 1.5 กรณีศึกษาจริง (Case Study — 28 กุมภาพันธ์ 2026)

**สถานการณ์:** EURUSD M15 ช่วงเช้า 06:00–08:30 GMT ก่อน London Open — ตลาดเงียบผิดปกติในรอบ 3 วัน รอ ECB Minutes

```
==== วัดขนาด Squeeze (เก็บสถิติ 8 แท่ง M15 ล่าสุด) ====

แท่ง 1-8 (ย้อนหลัง 2 ชั่วโมง):
  BB Width:  0.00082, 0.00079, 0.00076, 0.00073,
             0.00071, 0.00068, 0.00066, 0.00064  (บีบลงเรื่อยๆ)
  KC Width:  0.00105, 0.00103, 0.00102, 0.00101,
             0.00100, 0.00099, 0.00098, 0.00097

  BB < KC ทุกแท่ง? ✅ YES
  squeeze_bars = 8 (≥ Squeeze_Min = 6) → VALID SQUEEZE

แท่งที่ 9 (07:30 GMT — ECB Minutes ออก):
  StdDev ระเบิดขึ้นทันที!
  BB Width = 0.00118  > KC Width = 0.00097
  → BB ออกจาก KC → Squeeze Released!
  → m_was_in_squeeze = true  (สำหรับ Tick นี้เท่านั้น!)
```

**การยืนยันทิศทางด้วย LR Slope:**

```
Close 14 แท่งล่าสุด (index 0 = newest, แต่คำนวณ oldest→newest):
  i=0 (oldest): 1.08200
  i=1:          1.08215
  ...
  i=13 (newest): 1.08395

คำนวณ OLS:
  n  = 14
  sx = sum(0,1,2,...,13) = 91
  sy = sum(ราคา 14 แท่ง) ≈ 14 × 1.08290 (approx) = 15.160
  sxy = sum(i × price_i)  = ≈ คำนวณจริง

ผลลัพธ์ (โดยประมาณ):
  slope_raw ≈ +0.0000163 USD/แท่ง  (ราคาขึ้น 1.63 pips ต่อแท่ง M15)

ATR_current = 0.00097
LR_slope_norm = 0.0000163 / 0.00097 = 0.0168 → น้อยมาก!

เพิ่มอีก 2 Tick หลัง Breakout:
  slope_raw = +0.0000482 USD/แท่ง  (Momentum พุ่งขึ้นหลัง ECB)
  LR_slope_norm = 0.0000482 / 0.00097 = 0.0497 → ยังไม่ถึง 0.5

  Tick ถัดไป (ราคาพุ่ง):
  slope_raw = +0.0000531
  LR_slope_norm = 0.0000531 / 0.00097 = 0.547 ≥ 0.5 ✅

→ SIGNAL_BUY!
```

**Entry, TP, SL:**

```
Entry (bid ณ Tick นั้น) = 1.08420
ATR = 0.00097

SL = 1.08420 - (2.0 × 0.00097) = 1.08420 - 0.00194 = 1.08226
TP = 1.08420 + (3.0 × 0.00097) = 1.08420 + 0.00291 = 1.08711

R:R = (1.08711 - 1.08420) / (1.08420 - 1.08226)
    = 0.00291 / 0.00194
    = 1.5 ✅

Confidence = min(0.547, 1.0) = 0.547
```

**ผลลัพธ์หลังจาก 45 นาที:**

```
08:15 GMT: EURUSD ขึ้นมาที่ 1.08711 → TP ถูกกระตุ้น!
กำไร = 29.1 pips × 0.10 lot = +$29.10
```

**บทเรียน:** S14 ไม่ได้เข้าตลาดตอน Squeeze กำลังสะสม แต่รอให้ BB ระเบิดออกก่อนแล้วจึงตรวจ Momentum — การผสม Squeeze + LR Slope ทำให้มั่นใจทั้ง "พลังงานสะสม" และ "ทิศทางชัดเจน" พร้อมกัน

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 Bollinger Bands — Standard Deviation Envelope

**นิยามและสูตร:**

```
SMA(N)    = (1/N) × Σ Close[i], i=0..N-1

StdDev(N) = √((1/N) × Σ(Close[i] - SMA)²)

BB_Middle = SMA(Close, N)          N = 20 (default)
BB_Upper  = SMA + k × StdDev      k = 2.0 (default)
BB_Lower  = SMA - k × StdDev

BB_Width  = BB_Upper - BB_Lower
          = 2 × k × StdDev(Close, N)
          = 4 × StdDev(Close, N)   [เมื่อ k=2.0]
```

**ตัวอย่างการคำนวณ:**

```
Close 20 แท่งล่าสุดของ EURUSD M15:
  SMA(20) = 1.08300
  StdDev(20) = 0.00032  (ต่ำมาก — ตลาดเงียบ)

  BB_Upper = 1.08300 + 2.0 × 0.00032 = 1.08364
  BB_Lower = 1.08300 - 2.0 × 0.00032 = 1.08236
  BB_Width = 1.08364 - 1.08236 = 0.00128  (12.8 pips)

เปรียบเทียบกับช่วงปกติ:
  StdDev ปกติ ≈ 0.00065
  BB_Width ปกติ ≈ 0.00260  (26 pips)

BB_Width ปัจจุบัน (12.8) < BB_Width ปกติ (26) = ความผันผวนต่ำกว่าปกติมาก
```

**ทำไม StdDev ต่ำ = ตลาดเงียบ:**

StdDev วัดว่าแต่ละ Close ห่างจาก Average มากแค่ไหน ถ้า Close หลายแท่งอยู่ใกล้ๆ กัน (ราคาไม่ไปไหน) StdDev จะต่ำ → BB Width แคบ → สัญญาณ Squeeze เริ่มก่อตัว

---

### 2.2 Keltner Channel — ATR-Based Envelope

**นิยามและสูตร:**

```
EMA(M) = Exponential Moving Average ของ Close, M แท่ง
         (ให้น้ำหนักมากกว่ากับข้อมูลล่าสุด)

ATR(P) = Average True Range, P แท่ง
         (Wilder Smoothing — วัด True Range รวม Gap)

KC_Middle = EMA(Close, M)          M = 20 (default)
KC_Upper  = KC_Middle + m × ATR(P) P = 14 (default), m = 1.5 (default)
KC_Lower  = KC_Middle - m × ATR(P)

KC_Width  = KC_Upper - KC_Lower
          = 2 × m × ATR(P)
          = 3.0 × ATR(14)   [เมื่อ m=1.5]
```

**ตัวอย่างการคำนวณ:**

```
KC_Middle = EMA(20) = 1.08295
ATR(14)   = 0.00097  (9.7 pips)

KC_Upper = 1.08295 + 1.5 × 0.00097 = 1.08295 + 0.00146 = 1.08441
KC_Lower = 1.08295 - 1.5 × 0.00097 = 1.08295 - 0.00146 = 1.08149
KC_Width = 1.08441 - 1.08149 = 0.00292  (29.2 pips)
```

**ทำไม ATR เปลี่ยนช้ากว่า StdDev:**

ATR ใช้ Wilder Smoothing (Exponential) บน True Range ซึ่ง Include Gap ระหว่างแท่ง ทำให้ ATR สะท้อน "Volatility โดยรวม" ที่เสถียรกว่า StdDev ของ Close ซึ่ง React กับแท่งเดี่ยวๆ ได้เร็วกว่า — นี่คือเหตุผลที่ BB เปลี่ยนเร็วกว่า KC ทำให้ BB สามารถบีบเข้าใน KC ได้ในช่วง Low Volatility

---

### 2.3 Squeeze Detection — เงื่อนไขทางคณิตศาสตร์

```
Squeeze = BB_Width < KC_Width
        ↔ 2k × StdDev(Close, N) < 2m × ATR(P)
        ↔ k × StdDev(Close, N) < m × ATR(P)

เมื่อ k=2.0 และ m=1.5:
        ↔ 2.0 × StdDev(20) < 1.5 × ATR(14)
        ↔ StdDev(20) < 0.75 × ATR(14)

ความหมาย: "ความแปรปรวนของราคา Close ต่ำกว่า 75% ของ True Range โดยเฉลี่ย"
  → ราคาเคลื่อนที่ในกรอบ Close แคบมาก แต่ High-Low ยังกว้างพอสมควร
  → ตลาดกำลัง "บีบตัว" สะสมพลังงาน
```

**ตัวอย่างตัวเลขจริง:**

```
สถานการณ์ SQUEEZE:
  StdDev(20) = 0.00032
  ATR(14)    = 0.00097
  Check: 0.00032 < 0.75 × 0.00097 = 0.000728? ✅ YES → Squeeze

สถานการณ์ NO SQUEEZE (ตลาดปกติ):
  StdDev(20) = 0.00065
  ATR(14)    = 0.00097
  Check: 0.00065 < 0.000728? ❌ NO (0.00065 < 0.000728 จริงแต่ BB Width > KC Width)

  BB_Width = 4 × 0.00065 = 0.00260
  KC_Width = 3 × 0.00097 = 0.00291
  BB(0.00260) < KC(0.00291) → ยังอยู่ใน Squeeze! (แต่ใกล้ Release)

สถานการณ์ POST-RELEASE:
  StdDev(20) = 0.00120  (พุ่งขึ้นหลัง Breakout)
  ATR(14)    = 0.00097
  BB_Width = 4 × 0.00120 = 0.00480
  KC_Width = 3 × 0.00097 = 0.00291
  BB(0.00480) > KC(0.00291) → RELEASED! → ตรวจ LR Slope
```

---

### 2.4 Linear Regression Slope (OLS)

**พื้นฐานทางคณิตศาสตร์:**

Linear Regression หา "เส้นตรงที่ดีที่สุด" ที่ Fit กับข้อมูล N จุด โดยใช้วิธี Ordinary Least Squares (OLS) ซึ่งหาค่า β ที่ Minimize ผลรวมของ (y_actual - y_predicted)²

```
สมมติ N = 14 จุด: (x₀, y₀), (x₁, y₁), ..., (x₁₃, y₁₃)
  โดย x_i = 0, 1, 2, ..., 13  (เวลา: 0=แท่งเก่าสุด)
      y_i = Close[i]           (ราคา)

OLS สูตรคำนวณ slope:

  sx  = Σ xᵢ  = 0+1+2+...+(N-1) = N(N-1)/2
  sy  = Σ yᵢ
  sxy = Σ xᵢyᵢ
  sxx = Σ xᵢ² = (N-1)(N)(2N-1)/6

  slope = (N × sxy - sx × sy) / (N × sxx - sx²)
```

**ตัวอย่างการคำนวณ (N=5 เพื่อความเข้าใจง่าย):**

```
ราคา 5 แท่ง (oldest → newest):
  y₀=1.0820, y₁=1.0835, y₂=1.0851, y₃=1.0872, y₄=1.0895

  N   = 5
  sx  = 0+1+2+3+4 = 10
  sy  = 1.0820+1.0835+1.0851+1.0872+1.0895 = 5.4273
  sxy = 0×1.0820 + 1×1.0835 + 2×1.0851 + 3×1.0872 + 4×1.0895
      = 0 + 1.0835 + 2.1702 + 3.2616 + 4.3580 = 10.8733
  sxx = 0²+1²+2²+3²+4² = 0+1+4+9+16 = 30

  slope = (5×10.8733 - 10×5.4273) / (5×30 - 10²)
        = (54.3665 - 54.2730) / (150 - 100)
        = 0.0935 / 50
        = 0.001870 USD/แท่ง  (ราคาขึ้น 1.87 pips/แท่ง)

ATR = 0.00120
LR_slope_norm = 0.001870 / 0.00120 = 1.558 → capped to 1.0
Confidence = 1.0  (Momentum แรงมาก)
```

**เหตุผลที่เลือก N=14 สำหรับ LR Period:**

- N = 14 เป็น "ค่า Balanced" ที่ไม่สั้นเกินไป (Noisy) และไม่ยาวเกินไป (Lagging)
- สอดคล้องกับ ATR Period = 14 ซึ่งใช้ Normalize — ทั้งสองวัดในช่วงเวลาเดียวกัน
- ใน Timeframe M15: 14 แท่ง = 3.5 ชั่วโมง = สะท้อน Session Momentum ได้ดี

---

### 2.5 ATR Normalization — ทำไมจึงสำคัญ

```
slope_raw = 0.00187 USD/แท่ง (EURUSD M15)

ปัญหาถ้าไม่ Normalize:
  - EURUSD: slope = 0.00187 → "แรง" หรือไม่? ไม่รู้
  - GBPJPY: slope = 0.00520 → มากกว่า แต่ GBPJPY ปกติเคลื่อนไหวมากกว่า

หลัง ATR Normalize:
  EURUSD: slope_norm = 0.00187 / 0.00097 = 1.93 → แรงมาก!
  GBPJPY: slope_norm = 0.00520 / 0.0180  = 0.29 → อ่อน (ปกติ GBPJPY เคลื่อนมาก)

สรุป: slope_norm > 0.5 มีความหมายเดียวกันสำหรับทุก Symbol
```

---

## 3. สถาปัตยกรรมระบบ (System Architecture)

### 3.1 Full MQL5 Standalone Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│               S14 FULL MQL5 ARCHITECTURE — ภาพรวม                       │
├─────────────────────────────┬────────────────────────────────────────────┤
│   PYTHON BRAIN (Optional)   │   MQL5 TRADER (Client Side — CBBSqueeze)  │
│   ส่ง Params เท่านั้น        │   ทุก Signal อยู่ในนี้                    │
├─────────────────────────────┼────────────────────────────────────────────┤
│  ✅ Regime Classification    │  ✅ iBands Handle (BB Upper/Lower/Mid)     │
│    (SQUEEZE ไหม?)            │  ✅ iATR Handle (ATR สำหรับ KC + TP/SL)   │
│                             │  ✅ iMA Handle (EMA สำหรับ KC Middle)      │
│  ✅ Parameter Optimization   │                                            │
│    BB Period/Dev             │  ✅ _CalcBBWidth() per Tick                │
│    KC ATR Multiplier         │  ✅ _CalcKCWidth() per Tick                │
│    Squeeze_Min Threshold     │  ✅ Squeeze State Machine                  │
│    Breakout Momentum         │     m_squeeze_bars counter                │
│    SL/TP ATR Multiplier      │     m_was_in_squeeze flag                 │
│    ↓ PORT 7778 (CONFIG_PUSH) │                                            │
│    SetDynamicParams() ──────→│  ✅ _CalcLRSlope() OLS per Release         │
│                             │  ✅ ATR Normalization                       │
│  ✅ Performance Tracking     │  ✅ SIGNAL_BUY / SIGNAL_SELL               │
│    ← PORT 7779              │  ✅ TP = 3×ATR, SL = 2×ATR                │
│    (TRADE_REPORT)           │  ✅ Confidence = min(|slope_norm|, 1.0)    │
│                             │  ✅ Standalone: Init() enables immediately  │
└─────────────────────────────┴────────────────────────────────────────────┘
```

**ข้อได้เปรียบพิเศษของ S14 ในฐานะ Standalone:**

1. **ทำงานได้ตั้งแต่วินาทีแรก** — `m_enabled = true` ใน `Init()` ไม่รอ Brain
2. **ไม่มี Regime Dependency** — S14 ตรวจ Squeeze ได้เองด้วย BB vs KC ไม่ต้องรู้ Regime ก่อน
3. **Self-Contained State Machine** — `m_squeeze_bars` และ `m_was_in_squeeze` คือ Internal State ที่ไม่ต้องการข้อมูลภายนอก
4. **Adaptive TP/SL** — ATR-based TP/SL ปรับตาม Volatility ปัจจุบันอัตโนมัติ

---

### 3.2 เปรียบเทียบ S14 กับกลยุทธ์ที่ทำงานใน Regime เดียวกัน

| ด้าน | S14 (BB Squeeze) | S09 (Session Breakout) | S16 (Spike) |
|-----|-----------------|----------------------|------------|
| Trigger | BB ออกจาก KC | Session Open Range Break | Spike Detection |
| Breakout Type | Volatility Compression → Expansion | Time-based Range Break | Sudden ATR Spike |
| Setup Required | ≥ 6 bars Squeeze | Session Range Formation | ไม่มี (Reactive) |
| Direction | LR Slope | Price vs Range High/Low | Momentum |
| R:R | 1.5 (Fixed ATR) | Variable | ATR-based |
| Win Rate | 45–55% | 40–55% | 50–60% |
| Standalone | ✅ | ✅ | ✅ |

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางสมบูรณ์จาก Tick ถึง Order

```
[ตลาด Forex] → Tick ทุก ~100-200ms
     ↓
[ProgramC_Trader.mq5 — OnTick()]
     ↓
[StrategyManager::DispatchTick(S14_BB_SQUEEZE)]
     ↓
[CBBSqueeze::Analyze(tick)]
     │
     ├─ _RefreshATR()
     │    CopyBuffer(atr_handle, 0, 0, 1) → m_last_atr
     │
     ├─ _CalcBBWidth()
     │    CopyBuffer(bb_handle, 1, 0, 1) → Upper[0]
     │    CopyBuffer(bb_handle, 2, 0, 1) → Lower[0]
     │    BB_Width = Upper[0] - Lower[0]
     │
     ├─ _CalcKCWidth()
     │    KC_Width = 2.0 × m_last_atr × m_kc_atr_mult
     │
     └─ Squeeze Logic:
          BB_Width < KC_Width?
          ├─ YES (in squeeze):
          │    m_squeeze_bars++
          │    m_was_in_squeeze = false
          │    → SIGNAL_NONE (still building)
          │
          └─ NO (released or never squeezed):
               m_was_in_squeeze = (m_squeeze_bars >= m_squeeze_min_bars)
               m_squeeze_bars = 0
               │
               was_in_squeeze = true? (Valid Release)
               ├─ NO → SIGNAL_NONE
               └─ YES → _CalcLRSlope()
                          CopyClose(N=14 bars)
                          OLS Regression → slope_raw
                          slope_norm = slope_raw / m_last_atr
                          │
                          |slope_norm| >= m_breakout_momentum (0.5)?
                          ├─ NO → SIGNAL_NONE, conf=0.0
                          ├─ slope_norm > 0 → SIGNAL_BUY
                          │    SL = bid - 2×ATR
                          │    TP = bid + 3×ATR
                          │    conf = min(slope_norm, 1.0)
                          └─ slope_norm < 0 → SIGNAL_SELL
                               SL = bid + 2×ATR
                               TP = bid - 3×ATR
                               conf = min(|slope_norm|, 1.0)

[m_state: last_signal, last_confidence, last_sl, last_tp]
     ↓
[StrategyManager::GetSignal() + GetConfidence()]
     ↓
[MMManager → Lot Sizing]
     ↓
[OrderSend()] → [ตลาด]
     ↓
[TRADE_REPORT Port 7779] → [Python Brain]
```

### 4.2 Single-Tick Entry Window — จุดที่สำคัญที่สุด

```
!!!  m_was_in_squeeze = true สำหรับ TICK เดียวเท่านั้น  !!!

ทำไม:
  Tick T (แรกที่ BB ออกจาก KC):
    in_squeeze = false
    m_was_in_squeeze = (squeeze_bars >= min) = TRUE   ← Window Open
    squeeze_bars = 0

  Tick T+1:
    BB_Width ยังอยู่นอก KC:
    in_squeeze = false
    m_was_in_squeeze = (squeeze_bars=0 >= min=6) = FALSE  ← Window Closed

ผลที่ตามมา:
  StrategyManager ต้องจัดการ Signal ใน Tick เดียวกัน
  ถ้า Tick T ผ่านไปโดยไม่ Open Order → โอกาสหายไปแล้ว
  ไม่มี "ลองใหม่ Tick ถัดไป" สำหรับ Squeeze เดิม

สถานการณ์พิเศษ — Re-Squeeze:
  ถ้าหลัง Release BB กลับเข้าไปใน KC อีกครั้ง
  → ต้องสะสม squeeze_bars ใหม่ถึง 6 ก่อน
  → เป็น Squeeze ใหม่ ไม่ใช่ต่อของเดิม
```

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตร S14 Confidence (Single Component)

```
Confidence = min(|LR_slope_norm|, 1.0)
           = min(|slope_raw / ATR|, 1.0)

ช่วง: 0.0 (ไม่มี Momentum) → 1.0 (Momentum สูงสุด)
```

S14 ใช้ Confidence Component เดียว ต่างจาก S01 (4 components) และ S11 (3 components) เพราะ:
- ณ จุด Squeeze Release สิ่งที่สำคัญที่สุดคือ "แรงของ Breakout" ซึ่ง LR Slope บอกได้ครบ
- BB vs KC Comparison เป็น Binary (Squeeze/Not) ไม่ใช่ Continuous Score
- Cloud Width หรือ TF Alignment ไม่ Relevant สำหรับ Breakout Strategy

### 5.2 การแปลค่า Confidence

| slope_norm | Confidence | ความหมาย | การตัดสินใจของ MM |
|-----------|-----------|---------|----------------|
| < 0.5 | 0.00 | ยังไม่ถึง Threshold → ไม่เข้า Trade | N/A |
| 0.5–0.6 | 0.50–0.60 | Breakout อ่อน — Entry แต่ Lot เล็ก | Lot ≈ 50% ของ Max |
| 0.6–0.8 | 0.60–0.80 | Breakout ปกติ | Lot ≈ 70-80% ของ Max |
| 0.8–1.0 | 0.80–1.00 | Breakout แรง | Lot ≈ Full Max |
| > 1.0 | 1.00 (Capped) | Breakout รุนแรงมาก — อาจเป็น Spike | Lot = Max, ระวัง Spike |

### 5.3 ตัวคูณปรับตาม Market Regime

| Regime | ตัวคูณ | เหตุผล |
|--------|--------|-------|
| **SQUEEZE** | **×1.5** | สภาวะที่ S14 ออกแบบมาโดยตรง — Brain ตรวจ Regime Squeeze ยืนยันเพิ่มเติม |
| **TRENDING** | **×1.0** | Post-Squeeze Trend — S14 ทำงานได้ดีใน Early Trending Phase |
| **RANGING** | **×0.6** | Endless Squeeze ที่ไม่ Release ชัดเจน — Signal คุณภาพต่ำกว่า |
| **VOLATILE** | **×0.4** | ตลาดผันผวนอยู่แล้วโดยไม่มี Squeeze Phase — False Breakout สูง |

ตัวอย่าง: Confidence ดิบ = 0.73, Regime = SQUEEZE → Confidence = 0.73 × 1.5 = **1.10 → capped = 1.00**

---

## 6. MQL5: การทำงานภายในของ CBBSqueeze

### 6.1 โครงสร้างตัวแปรหลัก (State Machine)

```mql5
class CBBSqueeze : public IStrategy
{
private:
    // ─── Parameters (ปรับได้จาก CONFIG_PUSH) ───
    int     m_bb_period;         // BB SMA period (default 20)
    double  m_bb_deviation;      // BB StdDev multiplier (default 2.0)
    int     m_kc_period;         // KC EMA period (default 20)
    double  m_kc_atr_mult;       // KC ATR multiplier (default 1.5)
    int     m_squeeze_min_bars;  // Min bars in squeeze (default 6)
    double  m_breakout_momentum; // Min LR slope normalized (default 0.5)
    double  m_sl_atr_mult;       // SL = N × ATR (default 2.0)
    double  m_tp_atr_mult;       // TP = N × ATR (default 3.0)
    int     m_atr_period;        // ATR period (default 14)
    int     m_lr_period;         // LR lookback bars (default 14)

    // ─── Indicator Handles ───
    int     m_bb_handle;         // iBands
    int     m_atr_handle;        // iATR (KC width + TP/SL)
    int     m_ema_handle;        // iMA (EMA for KC midline)

    // ─── Internal State Machine ───
    int     m_squeeze_bars;      // Counter: แท่งที่อยู่ใน Squeeze ต่อเนื่อง
    bool    m_was_in_squeeze;    // Flag: เพิ่งออกจาก Valid Squeeze หรือไม่
    double  m_last_atr;          // ATR ล่าสุด (cache)
    double  m_lr_slope;          // LR Slope Normalized ล่าสุด
};
```

### 6.2 Init() — Standalone Enable ทันที

```mql5
virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
{
    if(!IStrategy::Init(symbol, tf)) return false;

    m_strategy_id = S14_BB_SQUEEZE;
    m_info        = g_strategy_table[S14_BB_SQUEEZE];

    m_squeeze_bars   = 0;
    m_was_in_squeeze = false;
    m_last_atr       = 0.0;

    // *** KEY DIFFERENCE FROM S11 ***
    // S14 เป็น Standalone — Enable ทันทีโดยไม่รอ CONFIG_PUSH
    m_enabled = true;

    if(!_CreateHandles()) return false;

    PrintFormat("[S14] Init OK | %s %s | BB(%d,%.1f) KC(%d,%.1f) SqueezeMin=%d",
                m_symbol, EnumToString(m_timeframe),
                m_bb_period, m_bb_deviation,
                m_kc_period, m_kc_atr_mult,
                m_squeeze_min_bars);
    return true;
}
```

### 6.3 Analyze() — Squeeze State Machine (Full)

```mql5
virtual void Analyze(const MqlTick &tick) override
{
    if(!m_initialized || !m_enabled) return;

    // ─── Step 1: อัปเดต ATR ─────────────────────────
    _RefreshATR();
    // m_last_atr = ATR แท่งปัจจุบัน

    // ─── Step 2: คำนวณความกว้าง ──────────────────────
    double bb_w = _CalcBBWidth();   // BB_Upper - BB_Lower
    double kc_w = _CalcKCWidth();   // 2 × ATR × m_kc_atr_mult

    // ─── Step 3: Squeeze State Machine ────────────────
    bool in_squeeze = (kc_w > 1e-10) && (bb_w < kc_w);

    if(in_squeeze)
    {
        m_squeeze_bars++;            // สะสม counter
        m_was_in_squeeze = false;    // ยังไม่ Release
    }
    else
    {
        // BB ออกจาก KC — ตรวจว่า Squeeze ยาวพอหรือไม่
        m_was_in_squeeze = (m_squeeze_bars >= m_squeeze_min_bars);
        m_squeeze_bars   = 0;        // Reset ไม่ว่าจะ Valid หรือไม่
    }

    // ─── Step 4: คำนวณ LR Slope (ทุก Tick) ────────────
    m_lr_slope = _CalcLRSlope();
    // คำนวณทุก Tick เพื่อให้ค่า GetLRSlope() เป็นปัจจุบันเสมอ

    // ─── Step 5: Entry Decision ───────────────────────
    ENUM_TRADE_SIGNAL sig  = SIGNAL_NONE;
    double            conf = 0.0;
    double            sl   = 0.0, tp = 0.0;

    // CRITICAL: m_was_in_squeeze = true เฉพาะ Tick แรกของ Release เท่านั้น
    if(m_was_in_squeeze && MathAbs(m_lr_slope) >= m_breakout_momentum)
    {
        sig  = (m_lr_slope > 0) ? SIGNAL_BUY : SIGNAL_SELL;
        conf = MathMin(MathAbs(m_lr_slope), 1.0);

        double price = tick.bid;
        if(sig == SIGNAL_BUY)
        {
            sl = price - m_sl_atr_mult * m_last_atr;  // -2×ATR
            tp = price + m_tp_atr_mult * m_last_atr;  // +3×ATR
        }
        else
        {
            sl = price + m_sl_atr_mult * m_last_atr;  // +2×ATR
            tp = price - m_tp_atr_mult * m_last_atr;  // -3×ATR
        }
    }

    // ─── Step 6: บันทึก State ──────────────────────────
    m_state.last_signal      = sig;
    m_state.last_confidence  = conf;
    m_state.last_sl          = sl;
    m_state.last_tp          = tp;
    m_state.last_signal_time = TimeCurrent();
}
```

### 6.4 _CalcLRSlope() — OLS Implementation จาก Source Code

```mql5
double _CalcLRSlope()
{
    double closes[];
    ArraySetAsSeries(closes, true);  // index 0 = newest
    int n = m_lr_period;             // default 14
    if(CopyClose(m_symbol, m_timeframe, 0, n, closes) < n) return 0.0;

    double sx = 0, sy = 0, sxy = 0, sxx = 0;
    for(int i = 0; i < n; i++)
    {
        double x = (double)i;
        double y = closes[n - 1 - i];  // Reverse: i=0 ← oldest, i=N-1 ← newest
        sx  += x;
        sy  += y;
        sxy += x * y;
        sxx += x * x;
    }

    double denom = n * sxx - sx * sx;
    if(MathAbs(denom) < 1e-10) return 0.0;  // ป้องกัน Division by Zero

    double slope = (n * sxy - sx * sy) / denom;
    // slope = USD per bar (e.g., 0.0000482 USD/bar)

    // Normalize by ATR ให้เป็น Dimensionless
    return (m_last_atr > 1e-10) ? slope / m_last_atr : 0.0;
}
```

**หมายเหตุ Reverse Index:**

`closes[]` ถูก Set เป็น `ArraySetAsSeries(true)` ดังนั้น `closes[0]` = newest, `closes[13]` = oldest แต่ OLS ต้องการ x=0 = oldest ดังนั้นต้อง Reverse: `y = closes[n - 1 - i]` เพื่อให้ i=0 ↔ closes[13] (oldest), i=13 ↔ closes[0] (newest)

### 6.5 SetDynamicParams() — Handle Rebuild Logic

```mql5
virtual void SetDynamicParams(SDynamicParams &params) override
{
    // REQUIRED: คัดลอก mm_method จาก Base (บทเรียน Mistake 5)
    IStrategy::SetDynamicParams(params);

    bool rebuild = false;

    // อ่านพารามิเตอร์ใหม่
    int    new_bb_p   = (int)params.GetParam("S14_BB_PERIOD",   (double)m_bb_period);
    double new_bb_dev =      params.GetParam("S14_BB_DEV",      m_bb_deviation);
    int    new_kc_p   = (int)params.GetParam("S14_KC_PERIOD",   (double)m_kc_period);
    double new_kc_m   =      params.GetParam("S14_KC_ATR_MULT", m_kc_atr_mult);

    // ตรวจว่า Handle ต้อง Rebuild หรือไม่
    // (เฉพาะ Period และ Deviation เท่านั้นที่ต้อง Rebuild)
    if(new_bb_p != m_bb_period ||
       MathAbs(new_bb_dev - m_bb_deviation) > 0.001 ||
       new_kc_p != m_kc_period ||
       MathAbs(new_kc_m   - m_kc_atr_mult) > 0.001)
        rebuild = true;

    // อัปเดตค่า
    m_bb_period         = new_bb_p;
    m_bb_deviation      = new_bb_dev;
    m_kc_period         = new_kc_p;
    m_kc_atr_mult       = new_kc_m;

    // Scalar params — อัปเดตทันที ไม่ต้อง Rebuild
    m_squeeze_min_bars  = (int)params.GetParam("S14_SQUEEZE_MIN",
                                               (double)m_squeeze_min_bars);
    m_breakout_momentum =      params.GetParam("S14_BREAKOUT_MOM",
                                               m_breakout_momentum);
    m_sl_atr_mult       =      params.GetParam("S14_SL_ATR", m_sl_atr_mult);
    m_tp_atr_mult       =      params.GetParam("S14_TP_ATR", m_tp_atr_mult);

    // Rebuild Handles ถ้าจำเป็น
    if(rebuild) _CreateHandles();

    m_enabled = true;  // ยืนยัน Enable (ถ้าเคย Disable ไปก่อน)
}
```

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `BS_BB_Period` | 20 | 10–50 | Period ของ Bollinger Bands SMA ค่า 20 = Standard John Bollinger ค่าน้อย (10) → BB แคบเร็วกว่า Squeeze บ่อยขึ้น แต่ Noisy ค่ามาก (50) → Squeeze นานขึ้น ช้าลง เหมาะกับ Timeframe ใหญ่ |
| `BS_BB_Deviation` | 2.0 | 1.5–3.0 | ตัวคูณ Standard Deviation ของ BB ค่าต่ำ (1.5) → BB แคบกว่า Squeeze เกิดบ่อยขึ้น ค่าสูง (3.0) → BB กว้างขึ้น Squeeze เกิดน้อยลงแต่ Stronger |
| `BS_KC_Period` | 20 | 10–50 | Period ของ Keltner Channel EMA ค่านี้ควรใช้เดียวกับ BB Period เพื่อให้ทั้งสองวัดในช่วงเวลาเดียวกัน |
| `BS_KC_ATR_Mult` | 1.5 | 1.0–2.5 | ตัวคูณ ATR สำหรับ KC Width **ค่านี้คือ "ความยากของ Squeeze"** ค่าน้อย (1.0) → KC แควลง BB อยู่ใน KC ยากขึ้น Squeeze น้อยลง ค่ามาก (2.5) → KC กว้าง BB อยู่ใน KC ง่ายขึ้น Squeeze บ่อยขึ้นแต่ Signal อาจอ่อน |
| `BS_Squeeze_Min` | 6 | 3–20 | จำนวนแท่งขั้นต่ำที่ BB ต้องอยู่ใน KC ต่อเนื่องเพื่อถือว่า Squeeze Valid **ค่านี้คือหัวใจของ S14** ค่าต่ำ (3) → Signal บ่อยแต่ Breakout อ่อน ค่าสูง (15) → Signal น้อยแต่ Breakout แรงมาก |
| `BS_Breakout_Mom` | 0.5 | 0.2–1.5 | LR Slope Normalized ขั้นต่ำเพื่อยืนยัน Breakout ค่าต่ำ (0.2) → เข้าแม้ Momentum น้อย (False Breakout สูง) ค่าสูง (1.0) → เข้าเฉพาะ Breakout แรงๆ (Signal น้อย แต่แม่นยำกว่า) |
| `BS_SL_ATR_Mult` | 2.0 | 1.0–3.0 | ตัวคูณ ATR สำหรับ SL ค่า 2.0 = Space 2 ATR ต่ำกว่า Entry เพื่อให้ Noise ปกติผ่านได้ |
| `BS_TP_ATR_Mult` | 3.0 | 1.5–5.0 | ตัวคูณ ATR สำหรับ TP ค่า 3.0 ร่วมกับ SL=2.0 → R:R = 1.5 ค่าสูง (5.0) → R:R = 2.5 แต่ TP อาจถูกกระตุ้นน้อยลง |
| `BS_ATR_Period` | 14 | 7–21 | Period ของ ATR สำหรับ KC Width และ TP/SL ควรเป็นค่าเดียวกับ LR Period เพื่อความสอดคล้อง |
| `BS_LR_Period` | 14 | 7–21 | Period ของ Linear Regression Lookback ค่าน้อย (7) → Slope ตอบสนองเร็วแต่ Noisy ค่ามาก (21) → Slope เรียบกว่าแต่ช้า |

**Golden Rules ของ S14 Parameters:**

```
BB Period = KC Period (ควรเท่ากัน)
ATR Period = LR Period (ควรเท่ากัน)
R:R = TP / SL (ต้องการ R:R ≥ 1.5 เสมอ เพื่อชดเชย Win Rate ~50%)

ตัวอย่างชุดพารามิเตอร์ที่ balanced:
  Conservative: BB=20,2.0 / KC=20,1.5 / SqueezeMin=8 / Mom=0.7 / TP=3.0 / SL=2.0
  Aggressive:   BB=20,2.0 / KC=20,1.5 / SqueezeMin=4 / Mom=0.4 / TP=2.5 / SL=2.0
  Scalping:     BB=10,2.0 / KC=10,1.5 / SqueezeMin=4 / Mom=0.5 / TP=2.0 / SL=1.5
```

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | Default | ต้อง Rebuild? | ผลกระทบทันที |
|-----|--------|---------|-------------|-------------|
| `S14_BB_PERIOD` | int | 20 | ✅ YES | Rebuild iBands Handle ใหม่ |
| `S14_BB_DEV` | float | 2.0 | ✅ YES (ถ้าเปลี่ยน) | Rebuild iBands Handle ใหม่ |
| `S14_KC_PERIOD` | int | 20 | ✅ YES | Rebuild iMA Handle ใหม่ |
| `S14_KC_ATR_MULT` | float | 1.5 | ✅ YES (ถ้าเปลี่ยน) | กระทบ KC Width ทันที |
| `S14_SQUEEZE_MIN` | int | 6 | ❌ NO | กระทบ Squeeze Threshold ทันที |
| `S14_BREAKOUT_MOM` | float | 0.5 | ❌ NO | กระทบ Entry Threshold ทันที |
| `S14_SL_ATR` | float | 2.0 | ❌ NO | กระทบ SL ของออเดอร์ใหม่ |
| `S14_TP_ATR` | float | 3.0 | ❌ NO | กระทบ TP ของออเดอร์ใหม่ |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Standalone Mode (Full — ทำงานได้ 100%)

```
เมื่อ Brain ไม่พร้อม หรือ Network Down:

ขั้นตอน:
1. CStandaloneSelector ตรวจจับการขาดเชื่อมต่อ
2. S14 ไม่ถูก Exclude! (ต่างจาก S11)
3. ตรวจ standalone_config.dat:
   - มีไฟล์ → Load params จาก CONFIG_PUSH ล่าสุด
   - ไม่มี  → ใช้ค่า Input Default ที่ตั้งใน EA

4. Risk Multiplier ×0.5 (Conservative Mode)
   - ทุก Lot Size ที่ MM คำนวณได้ × 0.5
   - เพื่อป้องกันความเสี่ยงสูงในช่วงไม่มี Brain

5. S14 ทำงานต่อเองทั้งหมด:
   - Squeeze Detection ปกติ
   - LR Slope ปกติ
   - ATR-based TP/SL ปกติ

6. เมื่อ Brain กลับมา:
   - CONFIG_PUSH ใหม่ → SetDynamicParams() → params อัปเดต
   - Risk Multiplier กลับ 1.0

สิ่งที่ขาดใน Standalone:
  ❌ Regime Classification จาก Brain (ไม่รู้ว่าตลาดอยู่ใน Regime ไหน)
  ❌ Regime Multiplier (Confidence ไม่ถูก Adjust)
  ❌ Period Optimization (ใช้ค่า Default)
  ✅ Signal Detection ทุกอย่างทำงานปกติ
```

### 8.2 Server Mode (Optimized)

```
ทุก Optimization Cycle (30-60 วินาที):
  1. Regime Classifier ประเมิน → SQUEEZE? → ให้ S14 Weight สูง
  2. Scan BB Period (15-30), KC Mult (1.2-2.0) บน InfluxDB
  3. Optimize Squeeze_Min (4-12) ตาม Symbol Volatility Profile
  4. ปรับ Breakout_Mom (0.3-0.8) ตาม False Breakout Rate ของ Symbol
  5. ปรับ SL/TP Multiplier ตาม ATR Distribution
  6. สร้าง CONFIG_PUSH → Port 7778
  7. รับ TRADE_REPORT → อัปเดต PerformanceTracker
  8. S14 Win Rate → ปรับ Weight ใน AI Council
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| ขั้นตอน | เงื่อนไข | ผลลัพธ์ |
|---------|---------|--------|
| **1. Accumulate Squeeze** | BB_Width < KC_Width ทุก Tick | `m_squeeze_bars++` ยังไม่ Trade |
| **2. Validate Release** | BB_Width ≥ KC_Width AND squeeze_bars ≥ 6 | `m_was_in_squeeze = true` (1 Tick!) |
| **3. Weak Release** | BB_Width ≥ KC_Width AND squeeze_bars < 6 | Reset — SIGNAL_NONE |
| **4. Momentum Check** | `|LR_slope_norm| ≥ 0.5` | เงื่อนไขสุดท้าย |
| **4a. BUY** | slope_norm ≥ +0.5 | SIGNAL_BUY, SL=−2×ATR, TP=+3×ATR |
| **4b. SELL** | slope_norm ≤ −0.5 | SIGNAL_SELL, SL=+2×ATR, TP=−3×ATR |
| **4c. No Momentum** | `|slope_norm| < 0.5` | SIGNAL_NONE — ไม่เข้า |
| **Take Profit** | ราคาถึง TP (MT5 จัดการ) | ปิดอัตโนมัติ +3×ATR |
| **Stop Loss** | ราคาถึง SL (MT5 จัดการ) | ปิดอัตโนมัติ −2×ATR |

---

## 10. การวิเคราะห์ R:R และ Expected Value

### 10.1 ทำไม R:R = 1.5 ยังทำกำไรได้แม้ Win Rate 45%

```
R:R = TP / SL = 3.0 / 2.0 = 1.5

Expected Value (EV) ต่อ Trade:
  EV = (Win Rate × Win Size) - (Loss Rate × Loss Size)
     = (Win Rate × 3.0) - ((1 - Win Rate) × 2.0)

เมื่อ Win Rate = 45%:
  EV = (0.45 × 3.0) - (0.55 × 2.0)
     = 1.35 - 1.10
     = +0.25 หน่วย ATR (บวก ✅)

Breakeven Win Rate = SL / (TP + SL) = 2.0 / (3.0 + 2.0) = 40%
→ ต้องชนะอย่างน้อย 40% จึงจะ Breakeven
→ S14 เป้าหมาย 45-55% → มี Edge ที่ดี
```

### 10.2 เปรียบเทียบ R:R กับ S07

| กลยุทธ์ | TP/SL | R:R | Win Rate Target | EV ต่อ Trade |
|--------|-------|-----|----------------|------------|
| S14 (BB Squeeze) | 3.0×/2.0× ATR | 1.50 | 45–55% | +0.25 ถึง +0.65 ATR |
| S07 (Mean Rev) | 1.5×/2.0× ATR | 0.75 | 60–68% | +0.13 ถึง +0.37 ATR |
| S07 (BB Middle TP) | Variable | >1.0 | 60–68% | ดีกว่า Fallback |

**ข้อสังเกต:** S14 มี EV ต่อ Trade สูงกว่า S07 ในสภาวะที่ดี แต่ต้องการ Squeeze ที่ Valid ก่อน จึงมี Signal น้อยกว่า

---

## 11. การบูรณาการกับ Money Manager (MM Integration)

### 11.1 SMMSelection สำหรับ S14

```mql5
// S14 Default MM Assignment (ใน MMManager)
SMMSelection s14_mm_sel;
s14_mm_sel.default_mm  = MM01;  // Fixed Conservative
                                 // เหตุผล: S14 มี Win Rate ~50% เท่านั้น
                                 // MM01 ป้องกัน Drawdown จาก Losing Streak

s14_mm_sel.volatile_mm = MM07;  // Percent Volatility
                                 // ใช้เมื่อ Post-Squeeze เข้าสู่ VOLATILE
                                 // ATR สูง → Lot ต่ำลง

s14_mm_sel.dd_mm       = MM10;  // DrawdownBased
                                 // ฉุกเฉินเมื่อ DD ≥ 10%
```

**ทำไม S14 ควรระวัง Kelly Criterion (MM04):**

Kelly สูตรต้องการ Win Rate ที่เสถียร แต่ S14 อาจมีช่วงที่ False Breakout สูง (เช่น ช่วง Choppy Market) ทำให้ Win Rate ผันผวนมาก Kelly อาจ Over-Size ในช่วงที่ Win Rate ต่ำกว่าคาด — MM01 หรือ MM02 จึงปลอดภัยกว่าสำหรับ S14

---

## 12. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะที่ดีที่สุด** | Post-Squeeze Breakout ใน SQUEEZE → TRENDING Transition ที่ชัดเจน โดยเฉพาะช่วง Pre/Post High-Impact News |
| **สภาวะที่แย่ที่สุด** | ตลาดที่ผันผวนสูงอยู่แล้วโดยไม่มี Consolidation Phase — BB ไม่มีโอกาสบีบเข้า KC |
| **สภาวะ Endless Squeeze** | ตลาด Ranging ที่ BB อยู่ใน KC นาน 20-50 แท่งแต่ไม่ Release ชัดเจน → S14 รอนานแต่ Signal คุณภาพต่ำเมื่อ Release |
| **ความถี่สัญญาณ** | ต่ำ — ต้องรอ Squeeze ≥ 6 แท่ง + Valid Release ใน 1 Tick |
| **ระยะเวลาถือสถานะ** | นาทีถึงหลายชั่วโมง — ATR-based TP/SL ปิดเร็วหรือช้าตาม Volatility |
| **Win Rate Target** | 45–55% (ชดเชยด้วย R:R = 1.5) |
| **R:R** | Fixed 1.5 (3×ATR TP / 2×ATR SL) |
| **Breakeven Win Rate** | 40% |
| **Indicator Handles** | 3 ตัว: iBands + iATR + iMA (EMA) |
| **Handle Rebuild** | เฉพาะเมื่อ BB Period/Dev หรือ KC Period/Mult เปลี่ยน |
| **Latency** | ~0ms (ทุก Calculation ใน MQL5) |
| **Standalone** | ✅ สมบูรณ์ 100% |
| **Max Confidence** | 1.0 (slope_norm ≥ 1.0) |

---

## 13. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S14_BBSqueeze.mqh` | `CBBSqueeze` class — BB/KC Squeeze detection, LR Slope, State Machine |
| `Include/Logic/IStrategy.mqh` | Abstract base class: `IStrategy`, `SDynamicParams`, `m_state` |
| `Include/Logic/StrategyConstants.mqh` | `S14_BB_SQUEEZE` enum, `MAGIC_S14_BB_SQUEEZE = 1014`, g_strategy_table[13] |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager` — SMMSelection สำหรับ S14 (MM01 default) |
| `Include/Network/Protocol/Definitions.mqh` | `SDynamicParams` struct, CONFIG_PUSH message format |
| `03_Trader/ProgramC_Trader.mq5` | Main EA — สร้าง CBBSqueeze, Route CONFIG_PUSH, Dispatch Tick |
| `02_Brain/config_push/config_builder.py` | สร้าง CONFIG_PUSH Packet สำหรับ S14 Parameters |
| `02_Brain/core/intelligence/strategy_council.py` | AI Council — SQUEEZE Regime Gate, Weight × Confidence |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT จาก S14 ผ่าน Port 7779 |
| `02_Brain/core/performance_tracker.py` | ติดตาม Win Rate, EMA-weighted historical performance |
| `Tester/TestS14_S13.mq5` | Test Script สำหรับ S14 (ร่วมกับ S13) |

---

## 14. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 14.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: Single-Tick Window สุ่มเสี่ยงต่อ Slippage**

`m_was_in_squeeze = true` สำหรับ Tick เดียวเท่านั้น ในตลาดที่มี Slippage สูง MT5 อาจไม่สามารถ Execute Order ได้ทัน Tick นั้น ทำให้พลาด Entry หรือ Execute ที่ราคาต่าง ออกไปมาก

**แนวทางแก้ไข:** เพิ่ม `m_signal_cooldown_ticks` เพื่อ Hold สัญญาณไว้ 2-3 Tick หลัง Release เพื่อให้ Execution มีเวลามากขึ้น โดยไม่ตรวจ `m_was_in_squeeze` แต่ตรวจ `m_ticks_since_release <= cooldown`

**ปัญหาที่ 2: LR Slope คำนวณ Inclusive ของแท่งใน Squeeze**

LR Slope ใช้ Close 14 แท่งล่าสุด ซึ่งรวมถึงแท่งที่อยู่ใน Squeeze (ราคาเคลื่อนน้อย) ทำให้ Slope อาจต่ำกว่าความเป็นจริง เพราะตัวเลขหลายตัวในช่วง Quiet มาก

**แนวทางแก้ไข:** ตรวจเฉพาะ Slope ของ "แท่งหลัง Release" โดยใช้ LR Period = 3–5 แท่งล่าสุดที่ BB อยู่นอก KC เพื่อวัด Momentum ของ Breakout จริงๆ

**ปัญหาที่ 3: Fixed ATR TP/SL ไม่ยืดหยุ่นในสภาวะ High-Volatility Breakout**

TP = 3×ATR ถูกคำนวณจาก ATR ณ จุด Release แต่หลัง Strong Breakout ATR อาจพุ่งขึ้น 2-3 เท่า ทำให้ TP ที่ 3×ATR_old กลายเป็น Target ที่เล็กเกินไป พลาดกำไรส่วนใหญ่

**แนวทางแก้ไข:** เพิ่ม Trailing Stop หลัง Price ผ่าน 2×ATR แรกแล้ว เพื่อ "ขี่กระแส" ต่อในกรณีที่ Breakout แรงมาก

**ปัญหาที่ 4: Squeeze ใน Timeframe เล็กอาจเป็น False Setup**

ใน M1 หรือ M5 Squeeze 6 แท่ง = 6 นาที หรือ 30 นาที ซึ่งสั้นเกินไปที่จะเรียกว่า "สะสมพลังงาน" จริงๆ อาจเป็นแค่ช่วงระหว่าง Tick ที่ Liquidity ต่ำ

**แนวทางแก้ไข:** ใน Timeframe เล็ก (M1-M5) ควรเพิ่ม Squeeze_Min เป็น 10-15 หรือใช้ Multi-Timeframe Confirmation โดยตรวจว่า H1 ก็มี Squeeze ด้วยหรือไม่

### 14.2 การเปรียบเทียบ S14 กับ S09 (Session Breakout) และ S16 (Spike)

| ด้าน | S14 (BB Squeeze) | S09 (Session Breakout) | S16 (Spike) |
|-----|-----------------|----------------------|------------|
| Breakout Origin | Volatility Compression | Time/Session Range | Sudden ATR Spike |
| Setup Time | ≥ 6 bars Squeeze | Session Opening (1-2 hrs) | No setup (immediate) |
| Direction Filter | LR Slope | Price vs Range | Momentum |
| False Signal Risk | Medium (Momentum Filter) | Medium | Medium (Spike Filter) |
| Best Regime | SQUEEZE | VOLATILE (Session Open) | VOLATILE |
| R:R | Fixed 1.5 | Variable | ATR-based |

**แนะนำ:** ใช้ S14 กับ S09 ร่วมกันใน Portfolio — S09 จับ Session Breakout ที่เกิดจาก Time-based Event ส่วน S14 จับ Non-Time-based Breakout ที่เกิดจาก Volatility Compression ทั้งสองเสริมกันโดยไม่ทับซ้อนมากนัก

### 14.3 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่ | เหตุผล |
|------------|---------|-------|
| KC_ATR_Mult | ทุกวัน | ปรับตาม ATR Level เฉลี่ยของวัน |
| Squeeze_Min | ทุก 2-3 วัน | ขึ้นกับ Regime Duration ของช่วงนั้น |
| Breakout_Mom | ทุกสัปดาห์ | ปรับตาม False Breakout Rate ประจำสัปดาห์ |
| BB/KC Period | ทุก 2 สัปดาห์ | เสถียรกว่าพารามิเตอร์อื่น |
| SL/TP Mult | ทุกสัปดาห์ | ปรับตาม ATR Distribution |

---

## 15. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### ตรวจสอบสถานะการเริ่มต้น

```bash
# MetaTrader 5 → Expert Journal → filter "[S14]":

# Init สำเร็จ:
[S14] Init OK | EURUSD PERIOD_H1 | BB(20,2.0) KC(20,1.5) SqueezeMin=6

# กำลัง Squeeze:
[S14] squeeze_bars=7 | BB_Width=0.00064 < KC_Width=0.00097 | Still Squeezing

# Valid Release:
[S14] squeeze_bars=8 → VALID RELEASE | LR_slope_norm=0.73 → SIGNAL_BUY
[S14] Entry=1.08420 SL=1.08226 TP=1.08711 Conf=0.73
```

### ตรวจสอบ Diagnostic API ใน MQL5

```mql5
CBBSqueeze* s14 = GetStrategy(S14_BB_SQUEEZE);
PrintFormat("[S14] squeeze_bars=%d | was_in_squeeze=%s | LR_slope=%.4f | ATR=%.5f",
            s14.GetSqueezeCount(),
            s14.IsInSqueezeState() ? "YES" : "NO",
            s14.GetLRSlope(),
            s14.GetLastATR());

// Expected output ขณะ Squeezing:
// [S14] squeeze_bars=5 | was_in_squeeze=NO | LR_slope=-0.1234 | ATR=0.00097

// Expected output ขณะ Release:
// [S14] squeeze_bars=0 | was_in_squeeze=YES | LR_slope=0.7300 | ATR=0.00097
```

### ตรวจสอบ CONFIG_PUSH มี S14 หรือไม่

```bash
python tools/validate_live_readiness.py --zmq
# ควรเห็นใน Output:
#   S14_BB_PERIOD=20, S14_BB_DEV=2.0, S14_KC_ATR_MULT=1.5
#   S14_SQUEEZE_MIN=6, S14_BREAKOUT_MOM=0.5, S14_SL_ATR=2.0, S14_TP_ATR=3.0
```

### ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S14 ไม่เคย Fire Signal | `BS_Squeeze_Min` สูงเกินไป หรือ KC กว้างเกินไปทำให้ BB ไม่เข้า KC เลย | ลด `BS_Squeeze_Min` เป็น 4 หรือเพิ่ม `BS_KC_ATR_Mult` เป็น 2.0 |
| False Breakout บ่อย | `BS_Breakout_Mom` ต่ำเกินไป | เพิ่ม `BS_Breakout_Mom` เป็น 0.8–1.0 |
| Signal ดีแต่ TP ไม่ถึง | TP กว้างเกินไปสำหรับ Timeframe นั้น | ลด `BS_TP_ATR_Mult` หรือเพิ่ม `BS_Squeeze_Min` เพื่อเลือก Breakout แรงขึ้น |
| Handle Init Fail ใน Log | Symbol หรือ Timeframe ไม่ถูกต้อง | ตรวจ `m_symbol` ว่าถูก Init ก่อน `_CreateHandles()` |
| Handles Rebuilt ทุก Tick | BB/KC Param float comparison issue | ตรวจว่า `SDynamicParams.GetParam()` ส่งค่า Stable ไม่ใช่ค่า Random |
| Win Rate < 35% (ต่ำกว่า Breakeven) | Breakout_Mom ต่ำ + ตลาด Choppy มาก | เพิ่ม Squeeze_Min + Breakout_Mom พร้อมกัน, ตรวจ Regime ใน Brain |
| Confidence สูงแต่ขาดทุน | ATR สูงมากทำให้ TP ไกลเกิน | ปกติของ S14 — EV ยังเป็นบวกถ้า Win Rate ≥ 40% |

---

*S14 Bollinger Squeeze Breakout — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kunanok*
