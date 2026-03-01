# S16 — Spike Hunter
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความ 10×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S16 | รหัสอ้างอิงลำดับที่สิบหกและลำดับสุดท้ายของระบบ S16 เป็น "ด่านสุดท้าย" ของมัลติกลยุทธ์ ทำหน้าที่จับโอกาสที่เกิดขึ้นอย่างฉับพลันและหายไปเร็ว ซึ่งกลยุทธ์อื่นๆ มักพลาด เพราะ S16 คำนวณและตัดสินใจในระดับ Tick ไม่ใช่ระดับแท่งราคา |
| **Enum Name** | `S16_SPIKE` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` ค่า enum index = 15 (0-based) — เป็น element สุดท้ายของ `g_strategy_table[16]` |
| **Enum Index** | 15 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่าน `GetStrategyInfo(S16_SPIKE)` |
| **ชื่อ** | Spike Hunter | "นักล่า Spike" — ตรวจจับและเข้าเทรดในทิศทางของการเคลื่อนที่แบบฉับพลันของราคา |
| **ประเภท** | Full MQL5 (`CAT_FULL_MQL5`) | Logic ทั้งหมดรันใน MQL5 Python Brain ทำหน้าที่เพียง Optimize พารามิเตอร์และส่ง CONFIG_PUSH — ไม่ได้วิเคราะห์ Spike โดยตรง |
| **สถาปัตยกรรม** | Legacy Wrapper | `CS16Spike` เป็น IStrategy Wrapper ครอบ `CStrategySpike` (อัลกอริทึมดั้งเดิม) เพิ่ม P6-3 Extensions โดยไม่ Rewrite Core |
| **Standalone Capable** | ✅ Yes | `m_initialized = true` ทันทีที่ `CStrategySpike.Init()` สำเร็จ ไม่ต้องรอ CONFIG_PUSH |
| **Preferred Regime** | VOLATILE (`REGIME_VOLATILE`) | สภาวะที่มีการเคลื่อนที่ฉับพลันของราคา เช่น ช่วงประกาศข่าวเศรษฐกิจสำคัญ Session Opens หรือ Flash Crash |
| **Alt Regime** | ไม่มี | S16 เฉพาะสภาวะ VOLATILE เท่านั้น — ไม่มี Regime รองที่ให้ผลดีเหมือนกัน |
| **Poor Regimes** | RANGING | สภาวะที่ราคาแกว่งเบาๆ ในกรอบ ไม่มี Spike Event เกิดขึ้น S16 จะนั่งรอโดยไม่ทำอะไร |
| **Regime Factor** | VOLATILE=×1.5, TRENDING=×1.0, SQUEEZE=×1.0, RANGING=×0.6 | คำนวณจาก `_regime_bonus()` ใน `BaseAnalyzer` — VOLATILE เป็น preferred[0] จึงได้ "perfect" multiplier |
| **MQL5 Class** | `CS16Spike` ใน `S16_Spike.mqh` | Wrapper class ที่ครอบ `CStrategySpike` พร้อม P6-3 Extensions (HiddenTPSL, TrailingStop, MMManager, MaxHold) |
| **Legacy Core** | `CStrategySpike` ใน `Strategy_Spike.mqh` | อัลกอริทึมการตรวจจับ Spike ดั้งเดิม v2.02 — มี 6 sub-components เป็น heap-allocated pointers |
| **Python Analyzer** | `S16SpikeAnalyzer` ใน `02_Brain/strategies/s16_spike_analyzer.py` | ประเมิน "สภาวะตลาดเหมาะกับ S16 แค่ไหน" — ส่งออก Confidence 0.0–1.0 ไม่ได้สร้าง Entry Signal |
| **Magic Number** | 1016 (`MAGIC_S16_SPIKE`) | หมายเลขเอกลักษณ์แท็กออเดอร์ทุกตัวที่ S16 เปิด |
| **Family** | Spike / News | กลุ่มกลยุทธ์ที่ทำกำไรจากเหตุการณ์พิเศษ (Spike Events) ไม่ใช่จากแนวโน้มระยะยาวหรือการกลับคืนสู่ค่าเฉลี่ย |
| **Version** | 6.05 | P6-3 Release — เพิ่ม HiddenTPSL, CTrailingStop, MaxHold, EmergencyTransferToGrid |
| **Critical Bug Fix** | v2.02 (P9-4b) | Memory Leak แก้ไขแล้ว — เปลี่ยน `CStrategySpike*` pointer เป็น `CStrategySpike` direct member |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S16 คือกลยุทธ์ **Spike Hunter** ที่ตรวจจับการเคลื่อนที่แบบฉับพลัน (Price Spike) ของตลาดโดยใช้ระบบให้คะแนน 4 องค์ประกอบ (Spike Score 0–100 คะแนน) แล้วเข้า Trade ในทิศทางของ Spike พร้อม TP=0.8×ATR และ SL=0.4×ATR (R:R = 2.0) โดย Trade จะถูกบังคับปิดถ้าถือนาน ≥ 15 นาที

จุดเด่นที่สำคัญที่สุดของ S16:
- **ความเร็ว**: ตัดสินใจทุก Tick ไม่รอแท่งราคาปิด
- **ความปลอดภัย**: Hidden TP/SL ที่โบรกเกอร์มองไม่เห็น + บังคับปิดหลัง 15 นาที
- **ความยืดหยุ่น**: Legacy Wrapper ทำให้ปรับ Core ได้โดยไม่ต้อง Rewrite

---

### 1.2 ปรัชญาเบื้องหลัง: Spike คืออะไรและทำไมต้องจับ?

**Spike คืออะไร?**

Spike คือการเคลื่อนที่ของราคา **อย่างฉับพลันและรุนแรง** ภายในเวลาสั้นมาก (วินาทีถึงนาที) ที่เกิดจากเหตุการณ์เฉพาะ:

```
ประเภทของ Spike Events ที่พบบ่อย:
  1. News Spike (ข่าวเศรษฐกิจ)
     → NFP, CPI, FOMC, GDP, PMI ออกมาต่างจากคาดมาก
     → ราคาวิ่ง 30–100 pips ภายใน 1–5 วินาที
     → Volume พุ่งสูง 3–10× ค่าเฉลี่ยปกติ

  2. Liquidity Spike (ขาด Liquidity)
     → ช่วง Market Open (London 07:00 GMT, NY 12:00 GMT)
     → ราคากระโดดข้ามช่วง Bid-Ask ที่ว่างเปล่า

  3. Stop Hunt Spike
     → Market Maker กวาด Stop Loss ของฝูงชนก่อน Reverse
     → เกิดขึ้นบ่อยในช่วงที่ราคาชนแนวรับ-แนวต้านสำคัญ

  4. Flash Crash
     → Algorithm ทำงานผิดปกติ หรือ Circuit Breaker ถูก Trigger
     → ราคาดิ่ง/พุ่งอย่างผิดปกติแล้วกลับมาเร็วมาก
```

**ทำไม Spike จึงทำกำไรได้?**

Spike มีคุณสมบัติที่สำคัญ: **โมเมนตัมเริ่มต้น (Initial Momentum)** มักต่อเนื่องในทิศทางเดิมอีก 0.5–3 ATR ก่อนที่จะ Retrace กลับ ระบบ S16 ออกแบบมาเพื่อ "ขี่คลื่น" ของโมเมนตัมนี้ โดยปิดกำไรเร็ว (0.8×ATR) ก่อนที่ Retracement จะเกิดขึ้น

**ทำไมต้อง TP เร็วกว่า SL?**

```
TP = 0.8 × ATR   (เล็กกว่า 1 ATR เต็ม)
SL = 0.4 × ATR   (ครึ่งหนึ่งของ TP)

R:R = 0.8 / 0.4 = 2.0

สมมติ Win Rate = 40%:
  EV = 0.4 × (0.8 ATR) − 0.6 × (0.4 ATR)
     = 0.32 ATR − 0.24 ATR
     = +0.08 ATR per trade  → ยังเป็นบวก!

สมมติ Win Rate = 50%:
  EV = 0.5 × 0.8 − 0.5 × 0.4 = 0.40 − 0.20 = +0.20 ATR per trade
```

นี่คือเหตุผลที่แม้ Win Rate ต่ำ S16 ยังทำกำไรได้ในระยะยาวด้วย R:R ที่ 2.0

---

### 1.3 ปรัชญาสถาปัตยกรรม: ทำไมต้องเป็น Legacy Wrapper?

`CStrategySpike` ถูกพัฒนาขึ้นก่อนที่สถาปัตยกรรม V6 IStrategy จะถูกออกแบบ — มัน "มีชีวิต" อยู่ในระบบก่อนที่จะมีมาตรฐานใดๆ แทนที่จะ Rewrite อัลกอริทึมการตรวจจับ Spike ใหม่ทั้งหมด (ซึ่งเสี่ยงที่จะ Introduce Bugs ใหม่) ทีมพัฒนาเลือกใช้แนวทาง **Adapter Pattern**:

```
IStrategy (มาตรฐาน V6)
    ↑ implements
CS16Spike (Adapter)
    ↓ contains (direct member)
CStrategySpike (Algorithm — battle-tested, ไม่แตะ Logic)
    ↓ contains (heap pointers)
6 Sub-Components
```

ข้อดีของ Wrapper Design:
1. **ไม่ต้อง Rewrite** — อัลกอริทึมที่ทดสอบแล้วไม่ถูกแตะต้อง
2. **เพิ่ม Feature ได้** — P6-3 Extensions ถูกเพิ่มใน CS16Spike ชั้นนอก
3. **Isolate Bug** — Bug ใน Core ไม่กระทบ Wrapper และในทางกลับกัน

---

### 1.4 กรณีศึกษาจริง (Case Study — NFP Spike)

**สถานการณ์:** วันศุกร์แรกของเดือน เวลา 12:30 GMT (Non-Farm Payrolls)

```
ก่อนข่าว (12:29:50 GMT):
  EURUSD Bid = 1.08350
  ATR(14) = 0.00080 (80 pips)
  Spread = 1.2 pips (ปกติ)
  m_entry_price = 1.08350 (ราคาอ้างอิงขณะนั้น)
  m_squeeze_bars ใน S14 กำลังสะสม — แต่ S16 เฝ้าอยู่แล้ว
```

**เหตุการณ์:** ตัวเลข NFP ออกมา +350K (คาด +185K) — ดีกว่าคาดมาก USD แข็งค่าทันที

```
ลำดับเหตุการณ์ภายใน 3 วินาที (12:30:00.000 → 12:30:03.000):

  Tick #1 — 12:30:00.045:
    bid = 1.08350 → 1.08340 (ลง 1 pip)
    m_prev_bid > bid → m_last_direction = SIGNAL_SELL
    m_density.Update(timestamp) → tick count เพิ่ม

  Tick #2 — 12:30:00.180:
    bid = 1.08300 (ลง 4 pips จาก prev)
    m_last_direction = SIGNAL_SELL

  Tick #3 — 12:30:00.290:
    bid = 1.08220 (ลง 8 pips)
    m_last_direction = SIGNAL_SELL
    m_density → 10 ticks ในช่วง 0.29 วินาที ≈ 34.5 ticks/sec

  ...

  Tick #10 — 12:30:00.890:
    bid = 1.08100 (ลง 25 pips ในเวลา 0.89 วินาที!)
    price_change = |1.08100 - 1.08350| = 0.00250 = 25 pips
    ATR(14) = 0.00080
    ATR_spike_mult = 2.0
    ATR × mult = 0.00080 × 2.0 = 0.00160 = 16 pips
    price_change (25 pips) >= threshold (16 pips) → Velocity Score = 40.0 points ✅

    ROC = (1.08100 - 1.08350) / 1.08350 × 100 = -0.231%
    |ROC| = 0.231 vs threshold 0.5 → ROC Score = 0.231/0.5 × 30 = 13.9 points

    Volume: ปัจจุบัน 847 vs เฉลี่ย 120 → 847/120 = 7.06× → IsVolumeSpike(1.5) = true
    Volume Score = 10.0 points ✅

    TickDensity: 34.5 ticks/sec vs threshold 3.0 → IsHighDensity = true
    Density Score = 20.0 points ✅

    TOTAL SCORE = 40.0 + 13.9 + 10.0 + 20.0 = 83.9 คะแนน

    83.9 >= m_pattern_score_min (70.0) → CheckEntry() = true ✅
    m_last_direction = SIGNAL_SELL → Entry!
```

**คำสั่งที่ระบบเปิด:**

```
SELL EURUSD @ 1.08100 (Bid)
Hidden TP = 1.08100 - 0.8 × 0.00080 = 1.08100 - 0.00064 = 1.08036
Hidden SL = 1.08100 + 0.4 × 0.00080 = 1.08100 + 0.00032 = 1.08132
MaxHold   = 900 วินาที (15 นาที)
```

**ผลลัพธ์หลังจาก 4 นาที 20 วินาที:**

```
12:34:20 GMT:
  bid = 1.08033 → CHiddenTPSL ตรวจว่า bid <= HiddenTP (1.08036)
  bid (1.08033) <= TP (1.08036) → CheckAndClose() ปิด Trade!

กำไร:
  Entry = 1.08100 (Sell)
  Exit  = 1.08033 (TP hit)
  = (1.08100 - 1.08033) / 0.00001 = 67 pips × Lot × pip value
  ใน EURUSD 0.10 lot: 67 pips × $1 = $6.70 ใน 4 นาที 20 วินาที
```

**บทเรียนจากกรณีนี้:** Spike Score สูงถึง 83.9 จาก 100 (สูงกว่า Threshold 70 อย่างชัดเจน) Velocity Component คือแรงขับหลัก (40 คะแนนเต็ม) การปิดกำไรเร็วที่ 0.8×ATR ทำให้ไม่ติด Retracement ที่เกิดขึ้นในภายหลัง

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 ระบบให้คะแนน Spike 4 องค์ประกอบ (4-Component Spike Score)

**หัวใจของ S16** คือฟังก์ชัน `CalculateSpikeScore()` ใน `CStrategySpike` ที่รวมสัญญาณ 4 ชนิดเป็นคะแนนรวม 0–100:

```
Spike Score = Velocity_Score + ROC_Score + Volume_Score + Density_Score

Max possible:  40 + 30 + 10 + 20 = 100 คะแนน
Entry trigger: Score >= m_pattern_score_min (default 70.0)
```

**เหตุผลที่น้ำหนักไม่เท่ากัน:**

| Component | น้ำหนัก | เหตุผล |
|-----------|--------|--------|
| Velocity (ATR) | 40 | ความเร็วราคา = ลายเซ็นหลักของ Spike แท้จริง — ถ้าราคาไม่เคลื่อนเร็ว ไม่มีอะไรที่เรียกว่า Spike |
| ROC Momentum | 30 | ยืนยันว่าโมเมนตัมยังต่อเนื่อง ไม่ใช่แค่ 1 Tick ผิดปกติแล้วกลับ |
| Tick Density | 20 | ยืนยันว่ามีกิจกรรม Real Market (ไม่ใช่ Quote Update เดี่ยวๆ) |
| Volume Spike | 10 | Volume ใน Forex เป็น Tick Volume ไม่แม่นยำ จึงให้น้ำหนักต่ำที่สุด |

---

### 2.2 องค์ประกอบที่ 1: ATR Velocity Score (น้ำหนัก 40 คะแนน)

**หลักการ:** วัดว่าราคาเคลื่อนที่เร็วแค่ไหนเทียบกับ ATR ที่ Normalize ไว้

```
สูตรคำนวณ:
  price_change = |tick.bid - m_entry_price|
  velocity_threshold = ATR(14) × m_atr_spike_mult   (default: ATR × 2.0)

  ถ้า price_change >= velocity_threshold:
      Velocity_Score = 40.0   (full score — ราคาวิ่งเกิน 2×ATR แล้ว)
  ถ้า price_change < velocity_threshold:
      Velocity_Score = (price_change / velocity_threshold) × 40.0   (partial)
```

**ตัวอย่างการคำนวณ:**

```
Case 1: ATR = 0.00080, m_atr_spike_mult = 2.0
  velocity_threshold = 0.00080 × 2.0 = 0.00160 (16 pips)

  price_change = 0.00250 (25 pips ≥ 16 pips):
      Velocity_Score = 40.0 (full)

  price_change = 0.00100 (10 pips < 16 pips):
      Velocity_Score = (0.00100 / 0.00160) × 40.0
                     = 0.625 × 40.0
                     = 25.0 คะแนน (partial)

  price_change = 0.00000 (ไม่ขยับ):
      Velocity_Score = 0.0
```

**ทำไมใช้ ATR เป็น Normalizer?**

ATR วัด "ความผันผวนปกติ" ของแต่ละ Symbol และ Timeframe ดังนั้นการใช้ ATR × multiplier เป็น threshold ทำให้ระบบ **Adaptive** โดยอัตโนมัติ:
- EURUSD M1: ATR ≈ 2–5 pips → threshold ≈ 4–10 pips
- XAUUSD M1: ATR ≈ 80–150 pips → threshold ≈ 160–300 pips
- ระบบเดียวกันทำงานได้ดีกับทุก Symbol โดยไม่ต้อง Hard-code ค่า

**ข้อสังเกตสำคัญ:** `m_entry_price` ใช้เป็น Reference Price ไม่ใช่ราคา Entry จริง — มันถูก Set จาก tick.bid ปัจจุบัน ทำให้ Velocity Score วัด "ราคาขยับจากตอนนี้แค่ไหน" ในระหว่างที่ตรวจสอบ Score

---

### 2.3 องค์ประกอบที่ 2: ROC Momentum Score (น้ำหนัก 30 คะแนน)

**ROC (Rate of Change)** วัดความเร็วของราคาในช่วง N bars ที่ผ่านมา:

```
สูตร ROC:
  ROC = (Price_Now - Price_N_bars_ago) / Price_N_bars_ago × 100

โดย:
  Price_Now        = Midprice ปัจจุบัน (bid + ask) / 2
  Price_N_bars_ago = Midprice เมื่อ m_roc_period (10) ticks ก่อน
  ผลลัพธ์          = % เปลี่ยนแปลงใน 10 ticks ล่าสุด
```

**การใช้ ROC ใน 3 จุด:**

```
จุดที่ 1 — Pre-Check (CheckEntry() Gate):
  ตรวจก่อน CalculateSpikeScore()
  ถ้า |ROC| < m_roc_threshold (0.5%) → return false ทันที
  → ป้องกันการคำนวณ Score เมื่อ Momentum ยังไม่พอ

จุดที่ 2 — Score Component:
  ถ้า |ROC| >= m_roc_threshold:  ROC_Score = 30.0 (full)
  ถ้า |ROC| < m_roc_threshold:   ROC_Score = (|ROC|/threshold) × 30.0 (partial)
  → แต่กรณีนี้ไม่เกิดขึ้นเพราะถูกกรองออกแล้วในจุดที่ 1

จุดที่ 3 — Reversal Detection (DetectReversal()):
  ถ้า Position เป็น BUY  และ ROC < -0.5% → Reversal ลง → ปิด
  ถ้า Position เป็น SELL และ ROC > +0.5% → Reversal ขึ้น → ปิด
  → Early Exit เมื่อ Spike กลับทิศ
```

**การทำงานภายในของ CROCCalculator:**

```mql5
// Circular buffer ขนาด 1,000 ticks
double m_price_history[1000];
int    m_index;   // ตัวชี้ circular

void UpdatePrice(double price) {
    m_price_history[m_index] = price;
    m_index = (m_index + 1) % 1000;
}

double Calculate(int period = 10) {
    int current_idx = (m_index - 1 + 1000) % 1000;
    int old_idx     = (m_index - period - 1 + 1000) % 1000;

    double current = m_price_history[current_idx];
    double old_p   = m_price_history[old_idx];

    if(old_p == 0) return 0;
    return ((current - old_p) / old_p) * 100.0;   // % change
}
```

**ทำไมใช้ % ไม่ใช่ Absolute pips?**

การใช้ % ทำให้ ROC Threshold เดียวกัน (0.5%) ใช้ได้กับทุก Symbol — EURUSD ที่ราคา 1.08 และ USDJPY ที่ราคา 150 มีระดับ Noise ต่างกันมาก แต่ % change สะท้อนความผิดปกติได้ดีกว่า

---

### 2.4 องค์ประกอบที่ 3: Volume Spike Score (น้ำหนัก 10 คะแนน)

```
CVolumeAnalyzer: Rolling 100-tick Circular Buffer

UpdateVolume(tick_volume):
    m_volume_history[m_index] = tick_volume
    m_index = (m_index + 1) % 100

IsVolumeSpike(multiplier = 1.5):
    current_volume = m_volume_history[m_index - 1]
    avg_volume = SUM(last 20 ticks) / 20

    return (current_volume >= avg_volume × multiplier)

Score:
    IsVolumeSpike() = true  → +10.0 คะแนน (binary — ไม่มี partial)
    IsVolumeSpike() = false → +0.0 คะแนน
```

**ข้อจำกัดสำคัญ:** Volume ใน Forex คือ **Tick Volume** (จำนวน price updates) ไม่ใช่ Real Traded Volume ทำให้ไม่แม่นยำเท่า Equity Markets นี่คือเหตุผลที่ Volume ได้น้ำหนักต่ำที่สุด (10 จาก 100)

**แต่ก็ยังมีประโยชน์:** ในช่วง News Spike แม้ Tick Volume จะไม่ใช่ Real Volume แต่มันสะท้อนถึง "กิจกรรมการอัปเดตราคา" ที่เพิ่มขึ้นอย่างมีนัยสำคัญ ซึ่ง Correlated กับ Real Volume Spike ในระดับที่ยอมรับได้

---

### 2.5 องค์ประกอบที่ 4: Tick Density Score (น้ำหนัก 20 คะแนน)

Tick Density คือตัวบ่งชี้ "ความเร่งด่วนของตลาด" ที่แม่นยำกว่า Volume ในบริบทของ Spike:

```
CTickDensity: Shift Buffer ขนาด 100 ticks (timestamps in milliseconds)

Update(time_msc):
    // Shift all elements right by 1
    for(i = 99; i > 0; i--)
        m_tick_times[i] = m_tick_times[i-1]
    m_tick_times[0] = time_msc
    m_count++

GetTicksPerSecond(period = 10):
    // ดู 10 ticks ล่าสุด
    time_span = m_tick_times[0] - m_tick_times[9]   (milliseconds)
    seconds   = time_span / 1000.0
    return 10 / seconds   (ticks per second)

IsHighDensity(threshold = 3.0):
    return (GetTicksPerSecond(10) >= threshold)

Score:
    IsHighDensity() = true  → +20.0 คะแนน (binary)
    IsHighDensity() = false → +0.0 คะแนน
```

**ตัวอย่างการแปลผล:**

```
ปกติ (ตลาดเงียบ):
  10 ticks ใน 5 วินาที = 2.0 ticks/sec < 3.0 → ไม่ High Density

ช่วง News Spike:
  10 ticks ใน 0.29 วินาที = 34.5 ticks/sec >= 3.0 → High Density! → +20 points

ช่วง London Open:
  10 ticks ใน 1.2 วินาที = 8.3 ticks/sec >= 3.0 → High Density! → +20 points
```

**ทำไม Tick Density สำคัญกว่า Volume?**

ในช่วง Spike จริงๆ ราคาอัปเดตถี่มากในเวลาสั้น แม้ Volume แต่ละ Tick จะไม่ใหญ่มาก แต่ **ความถี่ของ Tick** สะท้อน "ความเร่งด่วน" ของตลาดได้ดีกว่า เพราะโบรกเกอร์จะส่ง Quote ถี่ขึ้นเมื่อราคาเคลื่อนไหวเร็ว

---

### 2.6 การรวมคะแนนและ Entry Gate

```
Entry Conditions (ต้องผ่านทั้งหมด):

  Gate 1 — Spread Check:
    spread_points <= (ATR × m_spread_max_atr_pct) / _Point
    ป้องกันเข้าตลาดเมื่อโบรกเกอร์ขยาย Spread ในช่วง Spike
    (เป็นเรื่องปกติมากที่โบรกเกอร์ขยาย Spread ช่วงข่าว!)

  Gate 2 — ROC Pre-Check:
    |ROC| >= m_roc_threshold (0.5%)
    ถ้าโมเมนตัมยังไม่แรงพอ → ไม่คำนวณ Score เลย (ประหยัด CPU)

  Gate 3 — No Existing Position:
    m_entry_ticket == 0 (ไม่มี Position อยู่แล้ว)
    S16 ถือ Position เดียวต่อครั้ง (Single Position Logic)

  Gate 4 — Spike Score Threshold:
    CalculateSpikeScore() >= m_pattern_score_min (70.0)

  Gate 5 — Direction Known (CS16Spike level):
    m_last_direction != SIGNAL_NONE
    ต้องมีการเคลื่อนไหวของ bid ก่อน → Direction จึงจะถูก Set

Entry Signal:
  Pass All Gates → m_last_direction = SIGNAL_BUY หรือ SIGNAL_SELL
  Confidence     = min(score / 100.0, 1.0)
                 = min(83.9 / 100.0, 1.0) = 0.839 ในตัวอย่าง
```

---

### 2.7 Direction Inference Algorithm — ทำไมต้อง Infer?

**ปัญหาหลัก:** `CStrategySpike` (Legacy Core) ไม่มีฟังก์ชัน `GetSpikeDirection()` — มันบอกแค่ว่า "มี Spike" แต่ไม่บอกว่า "Spike ไปทิศไหน"

**วิธีแก้ใน CS16Spike.Analyze():**

```mql5
void Analyze(const MqlTick &tick)
{
    if(!m_initialized || !m_enabled) return;

    m_spike.OnTick();   // อัปเดต sub-components ทั้งหมด

    // ─── Direction Inference ───────────────────────────────────
    // เปรียบ bid ปัจจุบัน กับ bid ก่อนหน้า
    if(m_prev_bid > 0.0)   // ต้องมี tick ก่อนหน้าอย่างน้อย 1 ครั้ง
    {
        if(tick.bid > m_prev_bid)       m_last_direction = SIGNAL_BUY;
        else if(tick.bid < m_prev_bid)  m_last_direction = SIGNAL_SELL;
        // ถ้าเท่ากัน: m_last_direction ไม่เปลี่ยน (ใช้ทิศเดิม)
    }
    m_prev_bid = tick.bid;   // อัปเดตสำหรับ tick ถัดไป
    // ──────────────────────────────────────────────────────────

    bool entry = m_spike.CheckEntry();
    if(entry && m_last_direction != SIGNAL_NONE)
    {
        m_state.last_signal     = m_last_direction;   // BUY หรือ SELL
        m_state.last_confidence = MathMin(m_spike.GetScore() / 100.0, 1.0);
    }
    else
    {
        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
    }
}
```

**ข้อจำกัดและการบรรเทา:**

```
ข้อจำกัด: tick แรกสุด (m_prev_bid = 0.0) จะไม่มี Direction
  → SIGNAL_NONE ถูก Return ทำให้ไม่เปิด Trade
  → ปลอดภัย — รอ tick ที่ 2 ก่อน

ข้อจำกัด: bid เท่ากันกับ prev (Quote เดิม)
  → m_last_direction ไม่เปลี่ยน — ใช้ทิศล่าสุดที่ทราบ
  → ปลอดภัยในช่วง Spike เพราะราคาแทบไม่ซ้ำกัน
```

---

### 2.8 R:R และคณิตศาสตร์ความเสี่ยง (Risk/Reward Math)

```
Hidden TP (Long):  open_price + m_tp_atr_mult × ATR = open + 0.8 × ATR
Hidden SL (Long):  open_price - m_sl_atr_mult × ATR = open - 0.4 × ATR

Hidden TP (Short): open_price - 0.8 × ATR
Hidden SL (Short): open_price + 0.4 × ATR

R:R = TP / SL = 0.8 / 0.4 = 2.0

Expected Value Analysis:
┌──────────────┬──────────────┬──────────────┬──────────────┐
│ Win Rate (%) │ EV per trade │ Break-even?  │ Verdict      │
├──────────────┼──────────────┼──────────────┼──────────────┤
│    35%       │ 0.35×0.8 - 0.65×0.4 = +0.02 ATR │ ✅ กำไร  │
│    40%       │ 0.40×0.8 - 0.60×0.4 = +0.08 ATR │ ✅ กำไร  │
│    50%       │ 0.50×0.8 - 0.50×0.4 = +0.20 ATR │ ✅ กำไร  │
│    33.3%     │ 0.333×0.8 - 0.667×0.4 = 0.00     │ ⚖️ Breakeven │
│    30%       │ 0.30×0.8 - 0.70×0.4 = -0.04 ATR │ ❌ ขาดทุน │
└──────────────┴──────────────┴──────────────┴──────────────┘

Breakeven Win Rate = SL / (TP + SL) = 0.4 / (0.8 + 0.4) = 33.3%
```

MaxHold เป็น Mechanism ป้องกัน "Dead Trade" ที่ไม่ไปถึง TP หรือ SL ภายใน 15 นาที — ปิดที่ราคาตลาด ซึ่งมักเป็น Float P&L เล็กน้อยบวกหรือลบ

---

## 3. สถาปัตยกรรมระบบ (System Architecture)

### 3.1 ตารางแบ่งความรับผิดชอบ — สถาปัตยกรรม Legacy Wrapper

```
┌──────────────────────────────────────────────────────────────────────┐
│            S16 LAYERED ARCHITECTURE — V6 Legacy Wrapper              │
├──────────────────────┬───────────────────────────────────────────────┤
│  IStrategy Interface │  CS16Spike (S16_Spike.mqh v6.05)              │
│  (V6 Standard)       │  ─── Outer Shell ───────────────────────────  │
│  + GetSignal()       │  • Analyze(): Direction Inference + Entry     │
│  + GetConfidence()   │  • ManagePositions(): 4-step position mgmt   │
│  + SetDynParams()    │  • SetParameters(): JSON → SDynamicParams    │
│  + Deinit()          │  • SetDynamicParams(): hot-reload params      │
│                      │  • EmergencyTransferToGrid(): handoff S15     │
│                      │  • SetMMManager() / GetActiveMM()            │
│                      │  • SetTPSLConfig(): configure hidden levels  │
├──────────────────────┼───────────────────────────────────────────────┤
│  P6-3 Extensions     │  CHiddenTPSL m_htpsl (direct member)         │
│  (Phase 6-3 added)   │  • SetHiddenTP/SL per ticket                │
│                      │  • CheckAndClose() every tick                │
│                      │  • GetTrackedCount()                         │
│                      │  CTrailingStop m_trail (direct member)       │
│                      │  • Register/Unregister ticket                │
│                      │  • Update() moves real broker SL             │
│                      │  _CheckMaxHold(): force-close at 900s        │
│                      │  CMMManager* m_mm_mgr (external pointer)     │
├──────────────────────┼───────────────────────────────────────────────┤
│  Legacy Core         │  CStrategySpike m_spike (DIRECT MEMBER)      │
│  (v2.02 BUG-FIX)     │  ← Strategy_Spike.mqh (v2.02)               │
│                      │  • Init(): allocates 6 sub-components        │
│                      │  • Deinit(): frees all — idempotent          │
│                      │  • OnTick(): updates all buffers             │
│                      │  • CheckEntry(): 3-gate entry logic          │
│                      │  • CheckExit(): MaxHold + Reversal           │
│                      │  • CalculateSpikeScore(): 4-component        │
│                      │  • GetScore() / GetATR()                     │
│                      │  • SetDynamicParams(): 11 live params        │
├──────────────────────┼───────────────────────────────────────────────┤
│  Sub-Components      │  CVolumeAnalyzer* m_volume  (heap)           │
│  (heap-allocated     │  • 100-tick circular buffer                  │
│   inside CSpike)     │  • IsVolumeSpike(1.5×) → +10 pts            │
│                      │  CROCCalculator* m_roc  (heap)               │
│                      │  • 1000-price circular buffer                │
│                      │  • Calculate(10) → % change → +30 pts       │
│                      │  CTickDensity* m_density  (heap)             │
│                      │  • 100-tick timestamp buffer                 │
│                      │  • IsHighDensity(3.0) → +20 pts             │
│                      │  CADXFilter* m_adx  (heap, DISABLED)        │
│                      │  CZScoreFilter* m_zscore  (heap, DISABLED)  │
│                      │  CSpreadFilter* m_spread  (heap)             │
│                      │  • Blocks entry if spread > 20% ATR          │
├──────────────────────┼───────────────────────────────────────────────┤
│  Python Brain        │  S16SpikeAnalyzer (s16_spike_analyzer.py)    │
│  (Server Side)       │  • ประเมิน Confidence 0.0–1.0               │
│                      │  • ไม่ Generate Entry Signal (MQL5 ทำเอง)   │
│                      │  • ส่ง CONFIG_PUSH ผ่าน ZMQ Port 7778       │
└──────────────────────┴───────────────────────────────────────────────┘
```

---

### 3.2 การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

```
[ตลาด Forex] → [MT5 Platform]
                     ↓ OnTick() every price update
              [ProgramC_Trader.mq5]
                     ↓ Analyze(tick)
              [CS16Spike::Analyze()]
                     ↓ m_spike.OnTick()
     ┌───────────────────────────────────────────┐
     │  CStrategySpike.OnTick() ทุก Tick:        │
     │  1. m_density.Update(time_msc)            │
     │  2. m_roc.UpdatePrice(midprice)           │
     │  3. m_volume.UpdateVolume(tick_vol)       │
     └──────────────────┬────────────────────────┘
                        ↓
              [Direction Inference]
              bid > prev_bid → SIGNAL_BUY
              bid < prev_bid → SIGNAL_SELL
                        ↓
              [m_spike.CheckEntry()]
              Gate1: SpreadFilter.IsSpreadOK()?
              Gate2: |ROC| >= threshold?
              Gate3: No position open?
                        ↓ Pass all gates
              [CalculateSpikeScore()]
              Velocity + ROC + Volume + Density
                        ↓ Score >= 70?
              [SIGNAL_BUY or SIGNAL_SELL]
              conf = score / 100.0
                        ↓
              [StrategyManager → MMManager]
              Lot = CalculateLot(MM_method, conf)
                        ↓
              [OrderSend() to Broker]
                        ↓ Position opened
              [ManagePositions() ทุก Tick]
              ├── _RegisterNewPositions()
              │       SetHiddenTP = open + 0.8×ATR
              │       SetHiddenSL = open - 0.4×ATR
              ├── m_trail.Update() (ถ้า enabled)
              ├── m_htpsl.CheckAndClose()
              │       bid <= HiddenTP? → Close TP
              │       bid >= HiddenSL? → Close SL
              └── _CheckMaxHold()
                      hold >= 900s? → Force Close
                        ↓ Closed
              [TRADE_REPORT] Port 7779
                        ↓
              [Python Brain PerformanceTracker]
              EMA weight update for S16

ฝั่ง Python (async, ทุก 30-60 วินาที):
[FeederEA] → Port 7777 → [Python Brain]
                              ↓
                    [S16SpikeAnalyzer.analyze()]
                    Confidence = f(spike_score, atr_ratio, volume_spike, news, momentum)
                              ↓ ผ่าน AI Council
                    [CONFIG_PUSH Type=10] Port 7778
                    S16_VELOCITY_THRESH, S16_SPREAD_THRESH,
                    S16_VOLUME_THRESH, S16_MOMENTUM_THRESH,
                    S16_PATTERN_SCORE_MIN, S16_ATR_TP_MULT,
                    S16_ATR_SL_MULT, S16_MAX_HOLD_SEC
                              ↓
                    [CS16Spike::SetParameters()]
                    → _BuildDynamicParamsFromJson()
                    → m_spike.SetDynamicParams()
                    (Hot-reload — ไม่ต้อง Restart EA)
```

---

## 4. Python Confidence Scoring (S16SpikeAnalyzer)

### 4.1 สูตร Composite Confidence

`S16SpikeAnalyzer.analyze()` ประเมินว่า "สภาวะตลาดปัจจุบันเหมาะกับ S16 แค่ไหน" จาก 5 องค์ประกอบ:

```python
raw = spike_s + atr_s + vol_s + news_s + mom_s
confidence = _apply_regime(raw, regime)
```

**สูงสุดที่เป็นไปได้ (ก่อนปรับ Regime):** 0.35 + 0.25 + 0.20 + 0.10 + 0.10 = **1.00**

---

### 4.2 องค์ประกอบที่ 1: Spike Score จาก Spike Analyzer หลัก (น้ำหนัก 0.35)

```python
spike_score = float(indicators.get("spike_score", 0.0))   # 0.0–1.0
spike_s     = _clamp(spike_score) * 0.35
```

`spike_score` มาจาก Spike Detector ของ Brain (Module แยก) ซึ่งตรวจสอบ Tick Stream จาก Port 7777 ค่า 1.0 = ตรวจพบ Spike ชัดเจนในข้อมูลที่ Brain เห็น

---

### 4.3 องค์ประกอบที่ 2: ATR Spike Ratio (น้ำหนัก 0.25)

```python
atr_spike_r = float(indicators.get("atr_spike_ratio", 1.0))
# = ATR_ปัจจุบัน / ATR_ปกติ (เช่น MA20 ของ ATR)
# > 2.0 = ATR พุ่งสูงกว่าปกติ 2 เท่า → Spike กำลังเกิด

atr_s = min(0.25, (atr_spike_r - 1.0) / 3.0 * 0.25) if atr_spike_r > 1.0 else 0.0

ตัวอย่าง:
  atr_spike_r = 1.0 (ปกติ):          atr_s = 0.00
  atr_spike_r = 2.0 (2× ปกติ):       atr_s = min(0.25, 1.0/3.0 × 0.25) = 0.083
  atr_spike_r = 4.0 (4× ปกติ!):      atr_s = min(0.25, 3.0/3.0 × 0.25) = 0.25 (max)
```

---

### 4.4 องค์ประกอบที่ 3: Volume Spike Ratio (น้ำหนัก 0.20)

```python
vol_spike = float(indicators.get("volume_spike", 1.0))
# = Volume_ปัจจุบัน / MA_Volume
# > 3.0 = Volume สูงกว่าปกติ 3 เท่า → กิจกรรมตลาดสูงมาก

vol_s = min(0.20, (vol_spike - 1.0) / 4.0 * 0.20) if vol_spike > 1.0 else 0.0

ตัวอย่าง:
  vol_spike = 1.0 (ปกติ):             vol_s = 0.00
  vol_spike = 3.0 (3× ปกติ):          vol_s = min(0.20, 2.0/4.0 × 0.20) = 0.10
  vol_spike = 5.0 (5× ปกติ):          vol_s = min(0.20, 4.0/4.0 × 0.20) = 0.20 (max)
```

---

### 4.5 องค์ประกอบที่ 4: News Imminent (น้ำหนัก 0.10)

```python
news_imminent = bool(indicators.get("news_imminent", False))
# true = มีข่าว High-Impact ภายใน 15 นาที (จาก News Calendar)

news_s = 0.10 if news_imminent else 0.0
```

เมื่อมีข่าวสำคัญใกล้เข้ามา Confidence จะเพิ่มขึ้น 10% — สะท้อนว่า S16 ทำงานได้ดีที่สุดก่อน/ระหว่างข่าว

---

### 4.6 องค์ประกอบที่ 5: Price Momentum (น้ำหนัก 0.10)

```python
price_mom = abs(float(indicators.get("price_momentum", 0.0)))
# = ความเร็วของราคาในหน่วย pips/bar

mom_s = min(0.10, price_mom / 50.0 * 0.10)

ตัวอย่าง:
  price_mom = 0 pips/bar:   mom_s = 0.00
  price_mom = 25 pips/bar:  mom_s = min(0.10, 25/50 × 0.10) = 0.05
  price_mom = 50 pips/bar:  mom_s = min(0.10, 50/50 × 0.10) = 0.10 (max)
```

---

### 4.7 ตัวคูณปรับตาม Market Regime

ระบบใช้ `_apply_regime()` จาก `BaseAnalyzer`:

| Regime | ตัวคูณ | เหตุผล |
|--------|--------|--------|
| **VOLATILE** | **×1.5** | Perfect match — นี่คือสภาวะที่ S16 ออกแบบมาโดยตรง Spike Events เกิดบ่อยและรุนแรงที่สุด |
| **TRENDING** | **×1.0** | Neutral — ตลาดมีทิศทางแต่อาจไม่มี Spike พอ S16 ทำงานได้แต่ไม่ถึงศักยภาพสูงสุด |
| **SQUEEZE** | **×1.0** | Neutral — ช่วงบีบตัวก่อน Breakout อาจมี Spike เล็กๆ แต่ไม่ใช่ Volatile Spike จริงๆ |
| **RANGING** | **×0.6** | Poor — ตลาดเงียบ ราคาแกว่งเบาๆ ไม่มี Spike Event เกิดขึ้น S16 นั่งรอเปล่าๆ |

ตัวอย่าง: raw_confidence = 0.80, Regime = RANGING → 0.80 × 0.6 = **0.48** ต่ำกว่า AI Council Threshold 0.50 → S16 ไม่ถูกเปิดใช้งาน

---

## 5. MQL5: การทำงานภายในแบบละเอียด (MQL5 Internals)

### 5.1 โครงสร้างข้อมูลทั้งหมดของ CS16Spike

```mql5
class CS16Spike : public IStrategy
{
private:
    // ─── Legacy Core (direct member — Bug Fix v2.02) ─────────────
    CStrategySpike    m_spike;       // ไม่ใช่ pointer → ไม่รั่ว memory

    // ─── Direction Tracking ──────────────────────────────────────
    double            m_prev_bid;           // bid ของ tick ก่อนหน้า
    ENUM_TRADE_SIGNAL m_last_direction;     // BUY/SELL/NONE

    double            m_risk_multiplier;    // risk multiplier จาก Brain

    // ─── P6-3: External MM Manager ───────────────────────────────
    CMMManager*       m_mm_mgr;      // pointer (ไม่ได้ own — ไม่ delete)

    // ─── P6-3: Position Management (direct members) ──────────────
    CHiddenTPSL       m_htpsl;       // Virtual TP/SL tracking
    CTrailingStop     m_trail;       // Real broker SL trailing

    // ─── TP/SL Configuration ─────────────────────────────────────
    double            m_tp_atr_mult;   // default 0.8
    double            m_sl_atr_mult;   // default 0.4
    bool              m_trail_enabled; // default false
    int               m_max_hold_sec;  // default 900 (15 min)
};

// CStrategySpike Internal Structure:
class CStrategySpike : public CStrategyBase
{
private:
    // ─── 6 Sub-Components (heap-allocated pointers) ──────────────
    CVolumeAnalyzer*  m_volume;    // Volume spike detector
    CADXFilter*       m_adx;       // ADX directional filter (disabled)
    CZScoreFilter*    m_zscore;    // Z-Score volatility filter (disabled)
    CROCCalculator*   m_roc;       // Rate of Change calculator
    CTickDensity*     m_density;   // Tick density tracker
    CSpreadFilter*    m_spread;    // Spread width guard

    // ─── ATR Indicator Handle ─────────────────────────────────────
    int               m_atr_handle;

    // ─── Detection Thresholds ─────────────────────────────────────
    int               m_atr_period;         // 14
    double            m_atr_spike_mult;     // 2.0 → velocity threshold
    double            m_atr_tp_mult;        // 0.8
    double            m_atr_sl_mult;        // 0.4
    int               m_roc_period;         // 10
    double            m_roc_threshold;      // 0.5%
    double            m_volume_spike_mult;  // 1.5×
    double            m_density_threshold;  // 3.0 ticks/sec
    double            m_spread_max_atr_pct; // 0.20 (20% ATR)
    int               m_max_hold_seconds;   // 900

    // ─── Optional Filters (ปิดอยู่) ──────────────────────────────
    bool              m_use_adx_filter;     // false
    double            m_adx_minimum;        // 20.0
    bool              m_use_zscore_filter;  // false
    double            m_zscore_threshold;   // 2.0

    // ─── Dynamic Params ───────────────────────────────────────────
    double            m_pattern_score_min;  // 70.0 — Entry threshold
    double            m_risk_multiplier_dyn;// จาก Brain

    // ─── Position Tracking ────────────────────────────────────────
    ulong             m_entry_ticket;    // 0 = no position
    long              m_entry_time_msc; // timestamp (milliseconds)
    double            m_entry_price;    // Reference price for Velocity
};
```

---

### 5.2 Init() — ลำดับการเริ่มต้น (Initialization Sequence)

```mql5
// CS16Spike::Init()
virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
{
    // Step 1: เรียก Base Class Init ก่อน (บันทึก m_symbol, m_timeframe)
    if(!IStrategy::Init(symbol, tf)) return false;

    // Step 2: Init CStrategySpike (legacy core)
    //         ซึ่งภายในจะ: Deinit() ก่อน (BUG-001 FIX) แล้ว allocate ใหม่
    if(!m_spike.Init())
    {
        Print("[S16] ERROR: CStrategySpike.Init() failed");
        return false;
    }

    // Step 3: Reset direction tracking
    m_prev_bid = 0.0;   // ยังไม่มี tick ก่อนหน้า

    // Step 4: Enable HiddenTPSL ทันที (ไม่รอ CONFIG_PUSH)
    m_htpsl.SetEnabled(true, true);   // TP enabled, SL enabled

    // Step 5: Mark as initialized
    m_initialized = true;

    PrintFormat("[S16] Spike initialized | Symbol=%s TF=%s | TP×%.1f SL×%.1f ATR",
                symbol, EnumToString(tf), m_tp_atr_mult, m_sl_atr_mult);
    return true;
}

// CStrategySpike::Init() — ภายใน:
virtual bool Init() override
{
    // ★ BUG-001 FIX: ต้อง Deinit() ก่อนเสมอ ป้องกัน double-Init leak
    Deinit();

    // Allocate 6 sub-components
    m_volume  = new CVolumeAnalyzer();
    m_adx     = new CADXFilter();
    m_zscore  = new CZScoreFilter();
    m_roc     = new CROCCalculator();
    m_density = new CTickDensity(100);   // buffer 100 ticks
    m_spread  = new CSpreadFilter();

    // Init each component
    m_volume.Init(20, m_volume_spike_mult);   // 20-tick average window
    m_adx.Init(m_symbol, PERIOD_CURRENT, 14, m_adx_minimum, m_use_adx_filter);
    m_zscore.Init(100, m_zscore_threshold, m_use_zscore_filter);
    m_roc.Init(m_roc_period, m_roc_threshold);

    // SpreadFilter: max_spread = 20% of ATR (in points)
    double atr = GetATR();
    double max_spread = (atr > 0) ? (atr * m_spread_max_atr_pct) / _Point : 30.0;
    m_spread.Init(m_symbol, max_spread);

    // ATR Indicator Handle
    m_atr_handle = iATR(m_symbol, PERIOD_CURRENT, m_atr_period);

    m_initialized = true;
    return true;
}
```

---

### 5.3 OnTick() — การอัปเดต Buffer ทุก Tick

```mql5
virtual void OnTick() override
{
    if(!m_initialized) return;

    MqlTick tick;
    if(!SymbolInfoTick(m_symbol, tick)) return;

    // ─── อัปเดต 3 Buffers ─────────────────────────────────────────
    // 1. Tick Density Buffer (timestamp)
    if(m_density != NULL)
        m_density.Update(tick.time_msc);
        // Push tick.time_msc เข้า 100-element buffer
        // ใช้คำนวณ ticks/second ในภายหลัง

    // 2. ROC Price Buffer (midprice)
    if(m_roc != NULL)
    {
        double mid = (tick.bid + tick.ask) / 2.0;
        m_roc.UpdatePrice(mid);
        // Push midprice เข้า 1000-element circular buffer
    }

    // 3. Volume Buffer (tick volume)
    if(m_volume != NULL)
        m_volume.UpdateVolume((long)tick.volume);
        // Push tick.volume เข้า 100-element circular buffer
}
// สังเกต: ADXFilter และ ZScoreFilter ไม่มี OnTick() update
//         เพราะใช้ Indicator Handle (ATR + ADX) ดึงข้อมูลตาม demand
```

---

### 5.4 ManagePositions() — 4-Step Position Manager

ฟังก์ชันนี้ต้องถูกเรียกทุก Tick โดย StrategyManager หลังจาก Analyze():

```mql5
void ManagePositions(const MqlTick &tick)
{
    if(!m_initialized) return;

    // ─── Step 1: Register New Positions ───────────────────────────
    // ตรวจ Position ที่เปิดอยู่ทุก Position ที่ยังไม่มี HiddenTPSL
    _RegisterNewPositions();

    // ─── Step 2: Update Trailing Stop ─────────────────────────────
    // ถ้า m_trail_enabled: เลื่อน Real Broker SL ตาม Method ที่เลือก
    if(m_trail_enabled) m_trail.Update();

    // ─── Step 3: Check Hidden TP/SL ───────────────────────────────
    // ตรวจทุก Position ที่ Register แล้ว
    // ถ้า Price ถึง HiddenTP หรือ HiddenSL → ปิด Position
    m_htpsl.CheckAndClose();

    // ─── Step 4: Check Max Hold Time ──────────────────────────────
    // Position ที่ถือเกิน m_max_hold_sec → Force Close
    _CheckMaxHold();
}

// _RegisterNewPositions() ทำงานอย่างไร:
void _RegisterNewPositions()
{
    double atr = m_spike.GetATR();   // ATR ปัจจุบัน

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;

        // กรอง: ต้องเป็น S16 Position ของ Symbol นี้เท่านั้น
        if(PositionGetString(POSITION_SYMBOL)  != m_symbol)      continue;
        if(PositionGetInteger(POSITION_MAGIC)  != MAGIC_S16_SPIKE) continue;

        // ข้ามถ้า Register แล้ว (มี HiddenTP หรือ HiddenSL อยู่แล้ว)
        if(_IsHiddenTracked(ticket)) continue;

        bool   is_buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        double open_pr = PositionGetDouble(POSITION_PRICE_OPEN);

        // Set Hidden TP
        double tp = is_buy ? open_pr + m_tp_atr_mult * atr
                           : open_pr - m_tp_atr_mult * atr;
        m_htpsl.SetHiddenTP(ticket, tp);

        // Set Hidden SL
        double sl = is_buy ? open_pr - m_sl_atr_mult * atr
                           : open_pr + m_sl_atr_mult * atr;
        m_htpsl.SetHiddenSL(ticket, sl);

        // Register Trailing Stop ถ้า enabled
        if(m_trail_enabled) m_trail.Register(ticket);
    }
}

// _CheckMaxHold() ทำงานอย่างไร:
void _CheckMaxHold()
{
    if(m_max_hold_sec <= 0) return;
    datetime now = TimeCurrent();

    // ต้องวนจาก index สูงไปต่ำ (เพราะ Force Close อาจทำให้ index เปลี่ยน)
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        // ... filter Symbol + Magic ...

        datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
        int hold_seconds = (int)(now - open_time);

        if(hold_seconds < m_max_hold_sec) continue;   // ยังไม่ถึงเวลา

        // Force Close!
        PrintFormat("[S16] MaxHold %ds exceeded for #%d — closing",
                    m_max_hold_sec, ticket);

        MqlTradeRequest req = {};
        req.action   = TRADE_ACTION_DEAL;
        req.position = ticket;
        req.type     = (pos_type==POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        req.price    = (pos_type==POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                      : SymbolInfoDouble(sym, SYMBOL_ASK);
        req.comment  = "S16_MaxHold";

        if(OrderSend(req, res))
        {
            m_htpsl.ClearHidden(ticket);    // ลบ Hidden TP/SL
            m_trail.Unregister(ticket);      // ยกเลิก Trailing
        }
    }
}
```

---

## 6. Memory Leak Fix — ประวัติ v2.02 (P9-4b)

### 6.1 Bug ดั้งเดิม (ก่อน v2.02)

```mql5
// ─── OLD CODE (PRE-v2.02) — เกิด Memory Leak ───────────────────
class CS16Spike : public IStrategy
{
private:
    CStrategySpike* m_spike;   // POINTER — heap allocated ❌

    CS16Spike() {
        m_spike = new CStrategySpike();   // allocate ครั้งแรก
    }

    virtual bool Init() {
        // ปัญหา: ถ้า Init() ถูกเรียกซ้ำ (เช่น RegisterAllStrategies() เรียก 2 ครั้ง)
        // m_spike ยังชี้ไปที่ object เดิม ไม่ถูก delete ก่อน
        m_spike->Init();   // ภายใน Init() allocate sub-objects ใหม่
        // → sub-objects เก่า (m_volume, m_adx, m_roc ฯลฯ) สูญหายโดยไม่ถูก free!
        // → Memory Leak ทุกครั้งที่ Init() ถูกเรียกซ้ำ
    }
};
```

**ผลกระทบของ Bug:**
- Memory เพิ่มขึ้นทุกครั้งที่ EA Restart หรือ Init() ถูกเรียกซ้ำ
- ใน Stress Test (Test_P9_1_S16_MemoryLeak.mq5): Memory เพิ่ม ~6KB ต่อรอบ Init()
- ใน Production: EA จะใช้ Memory มากขึ้นเรื่อยๆ จนอาจ Crash หลังทำงานหลายชั่วโมง

---

### 6.2 การแก้ไข (v2.02 Fix)

**แนวทางที่ 1 (สำหรับ CS16Spike):** เปลี่ยน Pointer เป็น Direct Member

```mql5
// ─── NEW CODE (v2.02) — Memory Safe ────────────────────────────
class CS16Spike : public IStrategy
{
private:
    CStrategySpike m_spike;    // DIRECT MEMBER ✅ ไม่ใช่ Pointer

    // เมื่อ CS16Spike ถูก Destroy → m_spike ถูก Destroy อัตโนมัติ (Stack semantics)
    // ไม่ต้อง new/delete เลย!
};

// Deinit() ต้องเรียก m_spike.Deinit() โดยตรง:
virtual void Deinit() override
{
    m_htpsl.SetEnabled(false, false);
    m_trail.SetEnabled(false);
    m_spike.Deinit();    // ★ CRITICAL: ต้องเรียกเอง — destructor ของ direct member
                          //   ไม่รัน Deinit() อัตโนมัติในบริบทนี้
    m_initialized    = false;
    m_prev_bid       = 0.0;
    m_last_direction = SIGNAL_NONE;
    IStrategy::Deinit();
}
```

**แนวทางที่ 2 (สำหรับ CStrategySpike):** ทำ Deinit() เป็น Idempotent

```mql5
void Deinit()
{
    // CheckPointer ก่อน delete ทุกครั้ง — ป้องกัน double-free
    if(CheckPointer(m_volume)  == POINTER_DYNAMIC) { delete m_volume;  m_volume  = NULL; }
    if(CheckPointer(m_adx)     == POINTER_DYNAMIC) { delete m_adx;     m_adx     = NULL; }
    if(CheckPointer(m_zscore)  == POINTER_DYNAMIC) { delete m_zscore;  m_zscore  = NULL; }
    if(CheckPointer(m_roc)     == POINTER_DYNAMIC) { delete m_roc;     m_roc     = NULL; }
    if(CheckPointer(m_density) == POINTER_DYNAMIC) { delete m_density; m_density = NULL; }
    if(CheckPointer(m_spread)  == POINTER_DYNAMIC) { delete m_spread;  m_spread  = NULL; }

    // INVALID_HANDLE guard — ป้องกัน double-release
    if(m_atr_handle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atr_handle);
        m_atr_handle = INVALID_HANDLE;
    }
    m_initialized = false;
}

virtual bool Init() override
{
    // ★ BUG-001 FIX: เรียก Deinit() ก่อนเสมอ
    Deinit();   // ถ้ามี objects เก่า → free ก่อน
                // ถ้า Deinit() ก่อนหน้าแล้ว → ทำอะไรไม่มี (Idempotent)

    // Allocate ใหม่อย่างปลอดภัย
    m_volume  = new CVolumeAnalyzer();
    // ...
}
```

**ทำไม Direct Member ดีกว่า Pointer ในกรณีนี้:**

| | Pointer (`CStrategySpike*`) | Direct Member (`CStrategySpike`) |
|--|--|--|
| Lifetime | ต้อง `new`/`delete` เอง | Automatic (RAII) |
| Re-Init Risk | ต้อง `delete` ก่อน `new` ใหม่ — ลืมได้ | `Deinit()` เพียงพอ |
| Memory Safety | ต้องระวัง double-free | ไม่มีปัญหา |
| Overhead | Heap allocation (เล็กน้อย) | Stack (ไม่มี overhead) |

---

## 7. โหมดการทำงาน (Operating Modes)

### 7.1 Standalone Mode (ไม่มี Python Brain)

```
เมื่อ Brain ขาดการเชื่อมต่อ:

ลำดับการตัดสินใจ:
1. ลอง Load standalone_config.dat
   → มีไฟล์: ใช้พารามิเตอร์ S16 ล่าสุดที่ได้รับจาก CONFIG_PUSH
     (S16_VELOCITY_THRESH, S16_VOLUME_THRESH, S16_MOMENTUM_THRESH,
      S16_PATTERN_SCORE_MIN, S16_ATR_TP_MULT, S16_ATR_SL_MULT, S16_MAX_HOLD_SEC)
   → ไม่มีไฟล์: ใช้ Constructor Defaults
     (Velocity=2.0, Volume=1.5, Momentum=0.5, Score_Min=70.0, TP=0.8, SL=0.4, Hold=900s)

2. Risk × 0.5 (Conservative)
   → m_risk_multiplier = 0.5 ใน Standalone Mode

3. m_enabled = true ทันที (Spike Detection ทำได้เลยโดยไม่มี Brain)

4. ทุก Tick:
   CS16Spike::Analyze() → m_spike.OnTick() → CheckEntry() → Signal
   CS16Spike::ManagePositions() → HiddenTPSL + MaxHold

5. เมื่อ Brain กลับมา:
   CONFIG_PUSH ถูกรับ → _BuildDynamicParamsFromJson() → Hot-reload params
   Risk กลับเป็น 1.0
```

**ข้อแตกต่างหลักในสถาปัตยกรรมระหว่าง Standalone กับ Server Mode:**

| ด้าน | Standalone | Server Mode |
|------|-----------|-------------|
| Detection Params | Defaults หรือ saved | Brain-optimized |
| Regime Classification | ไม่มี (ใช้ VOLATILE ถ้า Score >= 70) | Brain จัดประเภทด้วย HMM |
| Risk Multiplier | ×0.5 | ×1.0 (หรือตาม Brain) |
| Parameter Updates | ไม่มี | ทุก 30–60 วินาที |

---

### 7.2 Server Mode (Full Optimization)

```
ทุก Optimization Cycle (Python Brain):

1. รับ Tick Stream จาก Port 7777
   → คำนวณ spike_score, atr_spike_ratio, volume_spike, price_momentum

2. S16SpikeAnalyzer.analyze():
   raw = spike_s + atr_s + vol_s + news_s + mom_s
   confidence = raw × regime_multiplier

3. ผ่าน AI Council:
   weighted_confidence >= 0.50? AND R:R >= 1.5 (2.0 ≥ 1.5 ✅)

4. Tune Detection Parameters:
   ถ้าตลาด Choppy มาก → เพิ่ม S16_PATTERN_SCORE_MIN (เช่น 80)
   ถ้า ATR ต่ำกว่าปกติ → ลด S16_VELOCITY_THRESH (เช่น 1.5)
   ถ้า Spread กว้างช่วงข่าว → ปรับ S16_SPREAD_THRESH

5. CONFIG_PUSH Type=10 → Port 7778
   → CS16Spike::SetParameters() → _BuildDynamicParamsFromJson()
   → m_spike.SetDynamicParams() (11 params, Hot-reload ทันที)
   → ไม่ต้อง Restart EA

6. ผลการเทรด Port 7779 → PerformanceTracker
   → EMA-based weight update สำหรับ S16 ใน AI Council
```

---

## 8. ตรรกะการเข้า-ออกสถานะแบบสมบูรณ์ (Full Entry/Exit State Machine)

### 8.1 State Diagram

```
[Init OK] → [SCANNING]
                │
                │ ทุก Tick: m_spike.OnTick() updates buffers
                │           Direction Inference (bid vs prev_bid)
                │
                ├── Spread ไม่ OK? → [SCANNING] (SpreadFilter block)
                │
                ├── |ROC| < 0.5%? → [SCANNING] (Momentum pre-check fail)
                │
                ├── Score < 70? → [SCANNING] (Score insufficient)
                │
                └── Score >= 70 AND Direction known
                         │
                         ├── direction = BUY  → SIGNAL_BUY
                         └── direction = SELL → SIGNAL_SELL
                                  │
                                  ↓ StrategyManager เปิด Position
                    [POSITION OPEN] (Long หรือ Short)
                                  │
                    ┌─────────────┤ ManagePositions() ทุก Tick
                    │             │
                    │    _RegisterNewPositions():
                    │      SetHiddenTP = open ± 0.8×ATR
                    │      SetHiddenSL = open ∓ 0.4×ATR
                    │             │
                    ↓             │
             [MONITORING]         │
                    │             │
          ┌─────────┤             │
          │         │             │
          ↓         ↓             ↓
    [HiddenTP Hit] [HiddenSL Hit] [MaxHold ≥ 900s]
    bid <= HiddenTP bid >= HiddenSL  TimeCurrent() - OpenTime >= 900
          │         │             │
          └────┬────┘             │
               ↓                 ↓
         [CLOSE POSITION]   [FORCE CLOSE]
         CheckAndClose()    _CheckMaxHold() → OrderSend()
               │                 │
               ↓                 ↓
         ClearHidden(ticket)  ClearHidden(ticket)
         Unregister(ticket)   Unregister(ticket)
               │
               └── TRADE_REPORT → Port 7779 → Brain
```

### 8.2 ตารางสรุปเงื่อนไขเข้า-ออก

| สถานะ | เงื่อนไข | การกระทำ |
|-------|---------|---------|
| **Scanning** | ทุก Tick ปกติ | m_spike.OnTick() อัปเดต Buffer |
| **Spread Block** | spread > 20% ATR | ปฏิเสธ Entry — รอ Spread แคบลง |
| **ROC Pre-filter** | \|ROC\| < 0.5% | ข้าม Score Calculation |
| **Score Insufficient** | Score < 70 | ไม่เปิด Position |
| **Long Entry** | Score >= 70, Direction = BUY | SIGNAL_BUY + conf = score/100 |
| **Short Entry** | Score >= 70, Direction = SELL | SIGNAL_SELL + conf = score/100 |
| **Register Hidden** | New Position ตรวจพบ | SetHiddenTP + SetHiddenSL |
| **TP Hit (Long)** | bid <= HiddenTP | CheckAndClose() → Market Sell |
| **SL Hit (Long)** | bid >= HiddenSL | CheckAndClose() → Market Sell |
| **TP Hit (Short)** | bid >= HiddenTP | CheckAndClose() → Market Buy |
| **SL Hit (Short)** | bid <= HiddenSL | CheckAndClose() → Market Buy |
| **Reversal (Long)** | ROC < −0.5% | CheckExit() = true → ออก |
| **Reversal (Short)** | ROC > +0.5% | CheckExit() = true → ออก |
| **MaxHold Expired** | hold >= 900 วินาที | Force Close ที่ราคาตลาด |

---

## 9. ระบบ Hidden TP/SL (CHiddenTPSL System)

### 9.1 ทำไมต้องซ่อน TP/SL จากโบรกเกอร์?

ในช่วง High-Impact News (Spike Events) โบรกเกอร์บางรายมีพฤติกรรมที่เป็นปัญหา:

```
ปัญหาที่ 1: Stop Hunt
  → โบรกเกอร์ทราบ SL ระดับราคาของทุก Position
  → ราคาอาจถูก "ดัน" ไปแตะ SL ก่อนแล้วกลับทิศ
  → ลูกค้าขาดทุนโดยไม่จำเป็น

ปัญหาที่ 2: Requote ที่ SL/TP Level
  → ช่วง High Volatility โบรกเกอร์อาจ "Requote" เมื่อราคาถึง SL/TP
  → ทำให้ Exit ได้ราคาที่แย่กว่าที่ตั้งไว้

วิธีแก้ของ S16:
  → ไม่ตั้ง SL/TP จริงบน Server โบรกเกอร์เลย
  → จัดการ Virtual TP/SL เองใน EA
  → CheckAndClose() ตรวจทุก Tick และ Close ตาม Market เมื่อถึงระดับ
```

### 9.2 CHiddenTPSL ทำงานอย่างไร

```mql5
// Internal Map: ticket → (HiddenTP, HiddenSL)
// ─── การ Set ─────────────────────────────────────
SetHiddenTP(ticket, tp_price):
    m_tp_map[ticket] = tp_price

SetHiddenSL(ticket, sl_price):
    m_sl_map[ticket] = sl_price

// ─── การ Check (ทุก Tick) ─────────────────────────
CheckAndClose():
    for each tracked ticket:
        PositionSelectByTicket(ticket)
        current_price = bid (for longs) / ask (for shorts)

        // TP Check
        if position is BUY  AND bid >= HiddenTP[ticket]:
            Close (Market Sell) → กำไร!
        if position is SELL AND ask <= HiddenTP[ticket]:
            Close (Market Buy)  → กำไร!

        // SL Check
        if position is BUY  AND bid <= HiddenSL[ticket]:
            Close (Market Sell) → ขาดทุนตาม SL
        if position is SELL AND ask >= HiddenSL[ticket]:
            Close (Market Buy)  → ขาดทุนตาม SL

// ─── การ Clear ────────────────────────────────────
ClearHidden(ticket):
    remove from m_tp_map
    remove from m_sl_map
```

### 9.3 CTrailingStop Integration

```mql5
// Trailing Stop เป็น Optional Feature (ปิดโดย default)
// เมื่อ enabled: จะเลื่อน Real Broker SL ตามราคา

SetTPSLConfig(
    tp_atr_mult  = 0.8,    // Hidden TP = 0.8 × ATR
    sl_atr_mult  = 0.4,    // Hidden SL = 0.4 × ATR
    trail_enabled = true,   // เปิด Trailing
    trail_method  = TS_ATR, // วิธี Trail: TS_ATR, TS_FIXED, TS_PERCENT
    max_hold_sec  = 900     // MaxHold 15 min
)

// เมื่อ trail_enabled:
//   _RegisterNewPositions() เรียก m_trail.Register(ticket)
//   ManagePositions() เรียก m_trail.Update() ทุก Tick
//   → Broker SL จะเลื่อนตามราคาเมื่อกำไร
//   → ป้องกัน Profit Lock ถ้า Spike ต่อเนื่องยาวนาน
```

---

## 10. Emergency Transfer to Grid (S15)

### 10.1 เมื่อไรที่ Transfer ถูก Trigger?

```
EmergencyTransferToGrid() ถูกเรียกจาก StrategyManager เมื่อ:

  1. S16 ได้รับ Signal แต่ Brain เปลี่ยนใจ → ต้องการให้ S15 Grid รับผิดชอบแทน
  2. Drawdown Emergency → StrategyManager ตัดสินใจ Hedge ด้วย Grid
  3. Manual Override จาก Operator (ผ่าน CONFIG_PUSH พิเศษ)

เงื่อนไขที่ Transfer: TRANSFER_STRATEGY_SIGNAL (default)
```

### 10.2 กระบวนการ Transfer

```mql5
STransferResult EmergencyTransferToGrid(
    ENUM_TRANSFER_REASON reason = TRANSFER_STRATEGY_SIGNAL)
{
    // Step 1: ทำความสะอาดก่อน Transfer
    for each open position (Magic = S16):
        m_htpsl.ClearHidden(ticket)    // ยกเลิก Virtual TP/SL ของ S16
        m_trail.Unregister(ticket)      // ยกเลิก Trailing ของ S16
        // Position ยังเปิดอยู่ — S15 จะ Take Over

    // Step 2: Transfer
    return TransferToGrid(m_symbol, MAGIC_S15_GRID, reason)
    // TransferToGrid() จะ:
    //   • Re-tag Magic Number จาก 1016 → 1015
    //   • ลงทะเบียน Position ใน S15 Grid System
    //   • S15 จะ Manage Position ต่อตาม Grid Logic
}
```

---

## 11. Optional Filters (ปิดอยู่โดย Default)

### 11.1 CZScoreFilter — Statistical Significance Gate

```mql5
// คำนวณ Z-Score ของ price_change เทียบกับ Distribution ล่าสุด
// Z-Score = (current_change - mean_change) / stddev_change

// ถ้า enabled (m_use_zscore_filter = true):
//   ต้องผ่านเงื่อนไข Z-Score >= m_zscore_threshold (2.0)
//   ก่อนจึงจะ Entry ได้

// ทำไมปิดอยู่: ใน Forex ช่วง Spike
//   Distribution ของ price_change ไม่ Normal → Z-Score มีความหมายจำกัด
//   การเพิ่ม Gate นี้อาจ Filter out Spike จริงๆ ได้บ้าง

// เปิดใช้ผ่าน CONFIG_PUSH:
//   S16_VOLATILITY_THRESH = 2.0  (พร้อมเปิด Filter ใน Code ก่อน)
```

### 11.2 CADXFilter — Directional Strength Gate

```mql5
// ตรวจว่า ADX(14) >= m_adx_minimum (20.0) ก่อน Entry
// ความหมาย: มีแนวโน้มชัดเจนก่อนจะเข้า

// ทำไมปิดอยู่: Spike เกิดได้แม้ ADX ต่ำ
//   (Ranging Market ที่ Break ออกมาจาก Spike ก็มีค่า ADX ต่ำตอนแรก)
//   การบังคับ ADX >= 20 อาจทำให้พลาด Spike ที่ดีจากตลาดที่เงียบก่อนหน้า

// เปิดใช้ผ่าน CONFIG_PUSH:
//   S16_DIRECTION_CONSIST = 20.0 (threshold)  พร้อมเปิด m_use_adx_filter ใน Code
```

---

## 12. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 12.1 CStrategySpike Constructor Defaults (ค่าเริ่มต้นใน MQL5)

| Parameter (Internal) | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|---------------------|---------|------------|----------------|
| `m_atr_period` | 14 | 7–21 | ATR Period สำหรับวัด "ความผันผวนปกติ" ค่า 14 เป็นมาตรฐาน Wilder Original |
| `m_atr_spike_mult` | 2.0 | 1.5–3.0 | price_change ต้องเกิน N×ATR จึงได้ Velocity Score เต็ม ค่าต่ำ=เข้าง่าย, ค่าสูง=เลือกเฉพาะ Spike แรงจริงๆ |
| `m_atr_tp_mult` | 0.8 | 0.5–1.5 | Hidden TP = N×ATR ค่าน้อย=ปิดกำไรเร็ว Win Rate สูงขึ้น แต่กำไรต่อ Trade ลดลง |
| `m_atr_sl_mult` | 0.4 | 0.2–0.8 | Hidden SL = N×ATR ค่าน้อย=SL แน่น ตัดขาดทุนเร็ว แต่ False Stop มากขึ้น |
| `m_roc_period` | 10 | 5–20 | ROC ดู N ticks ย้อนหลัง ค่าน้อย=ตอบสนองไวแต่ Noisy, ค่ามาก=เรียบแต่ช้า |
| `m_roc_threshold` | 0.5 | 0.2–1.0 | ROC ต้องเกิน N% จึงผ่าน Pre-filter ค่าสูง=เลือกเฉพาะ Spike แรง, ค่าต่ำ=ยืดหยุ่นมากขึ้น |
| `m_volume_spike_mult` | 1.5 | 1.2–3.0 | Volume ปัจจุบันต้องสูงกว่าเฉลี่ย N× จึงได้ +10 pts ค่าสูง=เลือก Spike ที่มี Volume หนัก |
| `m_density_threshold` | 3.0 | 2.0–10.0 | ticks/second ต้องเกิน N จึงได้ +20 pts ค่าสูง=เลือกเฉพาะช่วงตลาด Active มาก |
| `m_spread_max_atr_pct` | 0.20 | 0.10–0.30 | Spread สูงสุดที่ยอมรับ = N×ATR ค่าต่ำ=เข้มงวดกับ Spread (ปลอดภัยกว่า) |
| `m_max_hold_seconds` | 900 | 300–3600 | Force Close หลัง N วินาที ค่าน้อย=เทรดเร็วออก (Active), ค่ามาก=ให้โอกาสถึง TP มากขึ้น |
| `m_pattern_score_min` | 70.0 | 60–90 | Score ขั้นต่ำ Entry ค่าต่ำ=เข้าง่าย (False Positives มากขึ้น), ค่าสูง=เฉพาะ Spike แน่ใจ |
| `m_use_adx_filter` | false | — | เปิด/ปิด ADX Gate (เปิดเพื่อเพิ่ม Directional Filter) |
| `m_use_zscore_filter` | false | — | เปิด/ปิด Z-Score Gate (เปิดเพื่อ Filter Statistical Outlier เท่านั้น) |

### 12.2 CS16Spike Wrapper Defaults

| Parameter | Default | คำอธิบาย |
|-----------|---------|---------|
| `m_tp_atr_mult` | 0.8 | ส่งให้ CHiddenTPSL — TP = 0.8×ATR จาก Open Price |
| `m_sl_atr_mult` | 0.4 | ส่งให้ CHiddenTPSL — SL = 0.4×ATR จาก Open Price |
| `m_trail_enabled` | false | CTrailingStop ปิดอยู่ (enable ผ่าน CONFIG_PUSH) |
| `m_max_hold_sec` | 900 | Force-close หลัง 15 นาที |
| `m_risk_multiplier` | 1.0 | 0.5 ใน Standalone, 1.0 ใน Server Mode |
| `m_prev_bid` | 0.0 | เริ่มต้นเป็น 0 — tick แรกจะไม่มี Direction |
| `m_last_direction` | SIGNAL_NONE | เริ่มต้นเป็น NONE — ต้องรอ Bid Movement |

### 12.3 CONFIG_PUSH Keys (Server Mode — Hot-Reload)

| Key | Type | Default | Maps to | ผลทันที |
|-----|------|---------|---------|---------|
| `S16_VELOCITY_THRESH` | float | 2.0 | `m_atr_spike_mult` | เปลี่ยน Velocity threshold ใน CalculateSpikeScore() |
| `S16_SPREAD_THRESH` | float | 0.20 | `m_spread_max_atr_pct` | เปลี่ยน max allowable spread |
| `S16_VOLUME_THRESH` | float | 1.5 | `m_volume_spike_mult` | เปลี่ยน Volume spike multiplier |
| `S16_MOMENTUM_THRESH` | float | 0.5 | `m_roc_threshold` | เปลี่ยน ROC Pre-filter และ Reversal threshold |
| `S16_VOLATILITY_THRESH` | float | 2.0 | `m_zscore_threshold` | Z-Score threshold (ถ้า Filter enabled) |
| `S16_DIRECTION_CONSIST` | float | 20.0 | `m_adx_minimum` | ADX minimum (ถ้า Filter enabled) |
| `S16_PATTERN_SCORE_MIN` | float | 70.0 | `m_pattern_score_min` | Entry Score threshold |
| `S16_ATR_SPIKE_MULT` | float | 2.0 | `m_atr_spike_mult` | Velocity component threshold (duplicate of VELOCITY_THRESH) |
| `S16_ATR_TP_MULT` | float | 0.8 | `m_tp_atr_mult` | Hidden TP distance (ปรับ R:R) |
| `S16_ATR_SL_MULT` | float | 0.4 | `m_sl_atr_mult` | Hidden SL distance (ปรับ R:R) |
| `S16_MAX_HOLD_SEC` | int | 900 | `m_max_hold_seconds` | Force-close timeout |
| `S16_TRAIL_ENABLED` | float | 0.0 | `m_trail_enabled` | 1.0 = enable trailing stop |
| `S16_RISK_MULT` | float | 1.0 | `m_risk_multiplier` | Risk multiplier (0.5 = conservative) |

**ตัวอย่าง CONFIG_PUSH JSON สำหรับ S16 ช่วง NFP:**

```json
{
    "S16_VELOCITY_THRESH": 1.5,
    "S16_SPREAD_THRESH": 0.30,
    "S16_VOLUME_THRESH": 2.0,
    "S16_MOMENTUM_THRESH": 0.3,
    "S16_PATTERN_SCORE_MIN": 65.0,
    "S16_ATR_TP_MULT": 1.0,
    "S16_ATR_SL_MULT": 0.5,
    "S16_MAX_HOLD_SEC": 600,
    "S16_TRAIL_ENABLED": 0.0,
    "S16_RISK_MULT": 0.8
}
```
ความหมาย: ลด Threshold ให้เข้าง่ายขึ้น (Velocity 1.5×, Score 65), ยอมรับ Spread กว้างขึ้น (30% ATR เพราะช่วงข่าว Spread กว้างเป็นปกติ), TP กว้างขึ้น (1.0×ATR), ลด Risk (0.8×), MaxHold 10 นาที (ข่าวมักจบใน 10 นาที)

---

## 13. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | VOLATILE — News Events (NFP, CPI, FOMC), London/NY Open, Flash Events |
| **สภาวะตลาดที่แย่ที่สุด** | RANGING — ตลาดเงียบ ราคาแกว่งเบา ไม่มี Spike Event Score ไม่ถึง 70 |
| **ระยะเวลาถือสถานะ** | 30 วินาที ถึง 15 นาที (MaxHold บังคับปิด) |
| **Win Rate เป้าหมาย** | 40–55% (R:R 2.0 ทำให้ Breakeven ที่ 33.3%) |
| **R:R Ratio** | 2.0 (TP=0.8×ATR / SL=0.4×ATR) |
| **Score Threshold** | 70/100 (configurable — Brain ปรับได้) |
| **Latency ฝั่ง MQL5** | Tick-level — ตัดสินใจทันทีที่ Tick มาถึง |
| **Python Cycle** | 30–60 วินาที (Param Optimization ไม่ใช่ Signal) |
| **Max Confidence ดิบ** | 1.00 (ทุก Component เต็ม + VOLATILE Regime) |
| **Hidden TP/SL** | Default ON — โบรกเกอร์มองไม่เห็น |
| **Trailing Stop** | Default OFF — Enable ผ่าน CONFIG_PUSH |
| **Emergency Handoff** | EmergencyTransferToGrid() → S15 Grid |
| **Memory Safety** | v2.02+ — Direct Member, Idempotent Deinit |
| **Sub-component Heap** | 6 objects allocated ใน Init(), freed ใน Deinit() |

---

## 14. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S16_Spike.mqh` | `CS16Spike` — V6 IStrategy Wrapper + P6-3 Extensions (v6.05) |
| `Include/Logic/Strategy_Spike.mqh` | `CStrategySpike` — Core Spike Detection Algorithm (v2.02, BUG-001 Fixed) |
| `Include/Logic/Spike/VolumeAnalyzer.mqh` | `CVolumeAnalyzer` — 100-tick rolling volume spike detector |
| `Include/Logic/Spike/ROCCalculator.mqh` | `CROCCalculator` — 1000-tick circular buffer, Rate of Change |
| `Include/Logic/Spike/ADXFilter.mqh` | `CADXFilter` — Optional ADX directional strength filter (disabled by default) |
| `Include/Logic/Spike/ZScoreFilter.mqh` | `CZScoreFilter` — Optional Z-Score statistical filter (disabled by default) |
| `Include/Logic/TickDensity.mqh` | `CTickDensity` — 100-tick timestamp buffer, ticks/second calculator |
| `Include/Logic/SpreadFilter.mqh` | `CSpreadFilter` — Spread width guard (ATR-percentage based) |
| `Include/Logic/Common/HiddenTPSL.mqh` | `CHiddenTPSL` — Virtual TP/SL system (broker-invisible) |
| `Include/Logic/Common/TrailingStop.mqh` | `CTrailingStop` — Real broker SL trailing (optional) |
| `Include/Logic/Common/TransferToGrid.mqh` | `TransferToGrid()` — Emergency position handoff to S15 Grid |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager` — MM selection by regime/account state |
| `Include/Logic/Strategies/S16_Spike_Deinit_Fix.mqh` | Supplemental Deinit safety patch (P9-4b reference file) |
| `Include/Logic/StrategyConstants.mqh` | `ENUM_STRATEGY_ID`, Magic Numbers, `g_strategy_table[16]` |
| `Include/Network/Protocol/Definitions.mqh` | `SDynamicParams`, CONFIG_PUSH message format |
| `03_Trader/ProgramC_Trader.mq5` | Main EA — routes ticks, distributes CONFIG_PUSH |
| `02_Brain/strategies/s16_spike_analyzer.py` | `S16SpikeAnalyzer` — Confidence scoring (5 components) |
| `02_Brain/strategies/base_analyzer.py` | `BaseAnalyzer` — Regime multipliers, IncrementalIndicatorCache |
| `02_Brain/core/strategy/engine.py` | `StrategyEngineThreaded` — Optimization cycle driver |
| `Tester/Test_P9_1_S16_MemoryLeak.mq5` | Memory Leak regression test — เรียก Init() ซ้ำ 100 ครั้ง |
| `02_Brain/tests/test_p9_1_python.py` | Python-side memory regression test สำหรับ S16 |

---

## 15. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### 15.1 ตรวจสอบว่า S16 ทำงานอยู่

```mql5
// ใน EA Console — เรียก PrintDiagnostics():
CS16Spike* s16 = (CS16Spike*)g_strategy_manager.GetStrategy(S16_SPIKE);
s16.PrintDiagnostics();

// Output ตัวอย่าง (S16 กำลัง Scan หา Spike):
// [S16] Spike | Symbol=EURUSD | ATR=0.00082 | RawScore=45.3
// [S16] Signal=NONE | Confidence=0.000 | Direction=SELL | RiskMult=1.00
// [S16] MM=ATR_Based | ActiveMM=MM08_ATR_Volatility
// [S16] HiddenTPSL=0 tracked | Trail=0 tracked | MaxHold=900s
// [S16] TPSL config: TP×0.8 ATR | SL×0.4 ATR

// Output ตัวอย่าง (S16 มี Position เปิดอยู่):
// [S16] Spike | Symbol=EURUSD | ATR=0.00098 | RawScore=83.9
// [S16] Signal=SELL | Confidence=0.839 | Direction=SELL | RiskMult=1.00
// [S16] MM=ATR_Based | ActiveMM=MM08_ATR_Volatility
// [S16] HiddenTPSL=1 tracked | Trail=0 tracked | MaxHold=900s
// [S16] TPSL config: TP×0.8 ATR | SL×0.4 ATR
```

### 15.2 ตรวจสอบ Score Components แบบ Live

```mql5
PrintFormat("S16 Score=%.1f ATR=%.5f TickDensity=%.1f tps",
            s16.GetRawScore(),
            s16.GetSpikeATR(),
            // density ไม่มี Public accessor — ดูผ่าน Log ของ CTickDensity
            0.0);

// ตรวจ HiddenTPSL ที่ Track อยู่:
PrintFormat("S16 HiddenTPSL tracked: %d | Trail tracked: %d",
            s16.GetHiddenTPSLCount(),
            s16.GetTrailCount());
```

### 15.3 ตรวจสอบ CONFIG_PUSH มี S16 หรือไม่

```bash
# Python — ตรวจ validate_live_readiness
python tools/validate_live_readiness.py --zmq
# ควรเห็นใน Output:
# TEST 5: CONFIG_PUSH dry-run
#   ✅ S16_VELOCITY_THRESH=2.5
#   ✅ S16_VOLUME_THRESH=2.0
#   ✅ S16_MOMENTUM_THRESH=0.5
#   ✅ S16_PATTERN_SCORE_MIN=70.0
#   ✅ S16_ATR_TP_MULT=0.8
#   ✅ S16_ATR_SL_MULT=0.4
#   ✅ S16_MAX_HOLD_SEC=900
```

### 15.4 ทดสอบ Memory Leak Regression

```bash
# หลังการแก้ไขใดๆ ที่ CStrategySpike หรือ CS16Spike:
# MQL5 side: Tester → TestScript = Test_P9_1_S16_MemoryLeak.mq5
#   → เรียก Init() ซ้ำ 100 ครั้ง → วัด Memory ก่อน/หลัง
#   → ถ้า Diff < 1KB = PASS

# Python side:
python 02_Brain/tests/test_p9_1_python.py
# → ตรวจสอบว่า Analyzer init ซ้ำๆ ไม่สะสม Memory
```

### 15.5 ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S16 ไม่เคย Fire Signal ในช่วงข่าว | `S16_PATTERN_SCORE_MIN` สูงเกินไป หรือ Spread กว้างทำให้ Gate 1 Block | ลด Score_Min เป็น 65 หรือเพิ่ม Spread_Thresh เป็น 0.30 |
| S16 Fire ตลอดแม้ตลาดเงียบ | `S16_PATTERN_SCORE_MIN` ต่ำเกินไป (< 60) | เพิ่ม Score_Min เป็น 75–80 |
| MaxHold Fire บ่อยมาก | Score ถึง 70 แต่ Spike ไม่มีทิศทางชัด → TP/SL ไม่ถูก Hit | ลด TP เป็น 0.6×ATR หรือเพิ่ม Score_Min |
| Memory เพิ่มขึ้นเรื่อยๆ | CStrategySpike ยังเป็น v2.01 (ก่อน BUG-001 Fix) | อัปเดตเป็น v2.02 — ตรวจ `#property version "2.02"` |
| Direction = NONE ตลอด | m_prev_bid ไม่อัปเดต — Analyze() ไม่ถูกเรียกทุก Tick | ตรวจ StrategyManager ว่าเรียก Analyze() ทุก OnTick() |
| HiddenTPSL ไม่ปิด Trade | m_tp_atr_mult = 0 หรือ m_htpsl.SetEnabled(false) | ตรวจ Constructor defaults และ CONFIG_PUSH values |
| Trade ถูกปิดทันทีหลัง Open | MaxHold ต่ำเกินไปหรือ SL แน่นเกินไป | เพิ่ม MAX_HOLD_SEC, ลด SL_ATR_MULT |
| Win Rate < 33% (ขาดทุน) | Spike Score 70 แต่ตลาดมี False Spikes มาก | เพิ่ม Score_Min + เพิ่ม Density_Threshold + เพิ่ม ROC_Threshold พร้อมกัน |
| Config ไม่ Hot-reload | JSON Parse ผิดพลาด ใน `_ParseJsonDouble()` | ดู [S16] SetDynamicParams Log — ถ้าไม่มี Log แสดงว่า SetParameters ไม่ถูกเรียก |

---

## 16. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 16.1 จุดอ่อนเชิงโครงสร้าง

**ปัญหาที่ 1: m_entry_price ใช้ Bid ปัจจุบัน ไม่ใช่ราคา Confirmation**

```
ปัจจุบัน: m_entry_price = tick.bid ณ ขณะคำนวณ Score
ปัญหา:   ถ้า Spike เกิดขึ้นแล้วราคา Pullback บางส่วน
          price_change = |bid_ปัจจุบัน - m_entry_price| อาจน้อยกว่าความเป็นจริง
          → Velocity Score ต่ำกว่าที่ควรจะเป็น

แนวทางแก้: ใช้ High-Water Mark สำหรับ Upspike และ Low-Water Mark สำหรับ Downspike
            ติดตาม max_bid และ min_bid ตั้งแต่เริ่ม Session
```

**ปัญหาที่ 2: Tick Density ใช้ O(N) Shift ทุก Tick**

```
CTickDensity.Update(): Shift array 100 elements ทุก Tick
ความซับซ้อน: O(100) = O(1) ในทางปฏิบัติ แต่...
ในช่วง Spike ที่มี 30+ ticks/second:
  = 100 × 30 = 3,000 element copies per second

แนวทางแก้: เปลี่ยนเป็น Circular Buffer แบบเดียวกับ ROCCalculator
            m_index = (m_index + 1) % 100 → O(1) per tick
```

**ปัญหาที่ 3: Single Position Constraint**

```
m_entry_ticket > 0 → CheckEntry() = false ทันที
ปัญหา: ถ้า Position แรกยังถืออยู่และ Spike ใหม่เกิดขึ้น → พลาดโอกาส

แนวทางแก้: อนุญาตหลาย Position แต่ Limit ด้วย MaxPositions (เช่น 2)
            แต่ต้องระวัง Drawdown เมื่อทั้งสอง SL ถูก Hit พร้อมกัน
```

### 16.2 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่แนะนำ | เหตุผล |
|------------|--------------|-------|
| Score_Min | ทุก 5–10 นาที | ปรับตาม "คุณภาพ" ของ Spike ในช่วงนั้น |
| Velocity_Thresh | ทุก 5 นาที | ATR เปลี่ยนตาม Session |
| ROC_Threshold | ทุก 5–10 นาที | Momentum ของตลาดเปลี่ยนตลอด |
| TP/SL Mult | ทุก 1–4 ชั่วโมง | R:R ขึ้นอยู่กับ Session Volatility |
| MaxHold_Sec | ก่อนข่าวสำคัญ | NFP: 600s, FOMC: 900s, ปกติ: 900s |

### 16.3 Regime Interaction กับกลยุทธ์อื่น

```
S16 ทำงานดีที่สุดเมื่อ:
  VOLATILE: S16 Active, S07 (MeanRev) ลด Risk, S01 (StatArb) ระวัง

S16 ทำงานแย่เมื่อ:
  RANGING: S16 นั่งรอ, S07 Active, S01 Active, S14 (Squeeze) สะสม Squeeze

ใน Multi-Strategy Context:
  เมื่อ Brain ตรวจพบ VOLATILE → เพิ่ม S16 Weight, ลด S01/S07 Weight
  เมื่อกลับเป็น RANGING → S16 ยังมี HiddenTPSL ทำงานต่อ แต่ไม่เปิด Trade ใหม่
```

---

*S16 Spike Hunter — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
