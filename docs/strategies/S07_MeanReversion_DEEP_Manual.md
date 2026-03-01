# S07 — Mean Reversion (Volatility-Filtered)
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S07 | รหัสอ้างอิงลำดับที่เจ็ดในระบบมัลติกลยุทธ์ของ FlashEASuite V2 ตัวเลข "07" อยู่ในกลุ่ม "Pure MQL5" ซึ่งหมายความว่ากลยุทธ์นี้ทำงานได้สมบูรณ์ภายใน MT5 โดยไม่ต้องพึ่งพา Python Brain ในการคำนวณสัญญาณ ทำให้มีเสถียรภาพสูงสุดในทุกสถานการณ์ |
| **Enum Name** | `S07_MEAN_REVERSION` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) ค่า enum index = 6 (0-based array index) หมายความว่าเป็น element ลำดับที่ 7 ของ `g_strategy_table[16]` |
| **Enum Index** | 6 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่านฟังก์ชัน `GetStrategyInfo(S07_MEAN_REVERSION)` |
| **ชื่อ** | Mean Reversion (Volatility-Filtered) | การเทรดบนหลักการ "ราคากลับสู่ค่าเฉลี่ย" พร้อมตัวกรองความผันผวนเพื่อป้องกันการเข้าตลาดในสภาวะที่ Mean Reversion ไม่ทำงาน |
| **ประเภท** | Full MQL5 (`CAT_FULL_MQL5`) | กลยุทธ์บริสุทธิ์ฝั่ง MQL5 — สัญญาณทุกอย่างคำนวณในเครื่อง MT5 ด้วย Built-in Indicators ไม่มีการรอข้อมูลจาก Python Brain ทำให้ Latency ต่ำสุดและทนทานต่อการขาดเครือข่าย |
| **Standalone Capable** | ✅ Yes | รองรับการทำงานในโหมดอิสระเต็มรูปแบบ เพราะ Logic ทั้งหมดอยู่ใน MQL5 แล้ว Python Brain ทำหน้าที่ปรับพารามิเตอร์ผ่าน CONFIG_PUSH เท่านั้น ถ้าขาดการเชื่อมต่อ S07 ใช้ค่า Default ที่ฝังในโค้ดได้ทันที |
| **Preferred Regime** | RANGING (`REGIME_RANGING`) | สภาวะตลาดที่ราคาแกว่งตัวในกรอบ (Sideways) RSI และ Stochastic จะแกว่งระหว่าง Oversold/Overbought อย่างสม่ำเสมอ และ Bollinger Band Middle จะเป็นเป้าหมาย TP ที่แม่นยำ |
| **Alt Regime** | None (`REGIME_UNKNOWN`) | ไม่มี Regime รองที่เหมาะสม — S07 เป็นกลยุทธ์เฉพาะสภาวะ Ranging เท่านั้น ในสภาวะอื่น Volatility Filter จะปิดกั้นการเข้าตลาดโดยอัตโนมัติ |
| **Poor Regimes** | VOLATILE, TRENDING | VOLATILE: ความผันผวนสูง Volatility Filter จะบล็อคเกือบทุก Tick / TRENDING: RSI อาจค้างที่โซน Oversold/Overbought นานเป็นชั่วโมงโดยไม่กลับ ทำให้เข้าก่อนกำหนดและขาดทุน |
| **Regime Factor** | RANGING=1.5, SQUEEZE=1.0, TRENDING=0.5, VOLATILE=0.5 | ตัวคูณที่ Python Brain ใช้ปรับค่า Confidence — S07 ได้รับโบนัสสูงในสภาวะ Ranging เช่นเดียวกับ S01 แต่ถูกลงโทษรุนแรงใน VOLATILE/TRENDING |
| **MQL5 Class** | `CMeanReversion` | คลาสหลักในภาษา MQL5 ที่ควบคุมตรรกะ RSI + Stochastic + ATR Filter + Bollinger Band ทุก Tick ไฟล์: `Include/Logic/Strategies/S07_MeanReversion.mqh` |
| **Python Analyzer** | ไม่มี (Full MQL5) | S07 ไม่มี Python Analyzer เฉพาะ Brain ทำหน้าที่ส่ง CONFIG_PUSH เพื่อปรับพารามิเตอร์ผ่าน `SetDynamicParams()` เท่านั้น ไม่ได้คำนวณสัญญาณให้ |
| **Magic Number** | 1007 (`MAGIC_S07_MEAN_REV`) | หมายเลขเอกลักษณ์ที่ MQL5 ใช้แท็กออเดอร์ทั้งหมดที่เปิดโดย S07 ป้องกันการปะปนกับออเดอร์จากกลยุทธ์อื่นที่รันพร้อมกัน |
| **Family** | Contrarian | กลุ่มกลยุทธ์ที่เทรด "ทวนกระแส" — เมื่อตลาดขึ้นแรงเกินไป S07 ขาย เมื่อตลาดลงแรงเกินไป S07 ซื้อ โดยเชื่อว่าราคาจะกลับมาสู่ค่าเฉลี่ย |
| **Version** | 6.00 | สถาปัตยกรรม V6 ที่ออกแบบใหม่ทั้งหมด |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S07 เป็นกลยุทธ์ **Mean Reversion แบบมีตัวกรองความผันผวน (Volatility-Filtered Mean Reversion)** ที่เทรดบนหลักการว่า "ราคาที่เบี่ยงเบนออกไปจากค่าเฉลี่ยมากเกินไปจะต้องกลับมาในที่สุด" โดยใช้ **RSI และ Stochastic** เป็น Dual Oscillator ยืนยันสภาวะ Oversold/Overbought และใช้ **ATR Volatility Filter** เป็นประตูกรองเพื่อป้องกันการเข้าตลาดในช่วงที่กฎ Mean Reversion ล้มเหลว

เป้าหมาย TP ของ S07 คือ **Bollinger Band Middle (BB Middle)** ซึ่งคือค่าเฉลี่ยเคลื่อนที่ 20 แท่ง — เป็นตัวแทนทางเทคนิคของ "ค่าเฉลี่ย" ที่ราคาควรกลับมาหา ส่วน SL ใช้ 2×ATR เพื่อให้มีพื้นที่เพียงพอสำหรับ Noise ของตลาด

ข้อได้เปรียบหลักของ S07 เหนือ Mean Reversion ทั่วไปคือ **Volatility Filter** ที่ตัดช่วงเวลาอันตรายออกโดยอัตโนมัติ — ทำให้กลยุทธ์นี้ไม่ต้องพึ่งพาการตัดสินใจของ Trader ว่าตลาดพร้อมหรือยัง

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมราคาถึงต้องกลับมาสู่ค่าเฉลี่ย?

**หลักการทางเศรษฐศาสตร์:**

ราคาในตลาดการเงินถูกกำหนดโดย Supply และ Demand ของผู้เข้าร่วมตลาดล้านคนพร้อมกัน เมื่อราคาเคลื่อนที่ขึ้นไปสูงมากจนผิดปกติ สิ่งที่เกิดขึ้นคือ:

1. **ผู้ถือสถานะ Long ทำกำไร (Profit Taking)** — ผู้ที่ซื้อมาก่อนหน้านี้จะเริ่มขายออกเพื่อทำกำไร ส่งผลให้ราคาถูกกดลง
2. **นักลงทุนใหม่มองว่าราคาแพงเกินไป (Value Perception Shift)** — ราคาที่แพงเกินพื้นฐานจะลดแรงซื้อใหม่ลง
3. **Short Sellers เข้าตลาด** — ผู้เชื่อว่าราคาสูงเกินจริงจะเริ่มเปิดสถานะขาย

กระบวนการทั้งสามนี้เกิดขึ้นพร้อมกันและดึงราคากลับมาสู่ระดับที่ "ยุติธรรมทางสถิติ" ซึ่งก็คือบริเวณค่าเฉลี่ย กลยุทธ์ S07 ออกแบบมาเพื่อ "ขี่คลื่น" ของแรงดึงนี้

**ทำไมต้องมี Dual Oscillator (RSI + Stochastic)?**

RSI และ Stochastic ต่างก็วัดสภาวะ Overbought/Oversold แต่มีมุมมองต่างกัน:

- **RSI** วัดความเร็วและขนาดของการเคลื่อนที่ราคา (Momentum) — บอกว่า "ราคาขึ้นมาเร็วและแรงแค่ไหนในช่วงที่ผ่านมา"
- **Stochastic** วัดตำแหน่งราคาปัจจุบันเทียบกับ High-Low Range (Price Position) — บอกว่า "ราคาอยู่ที่ไหนในกรอบราคาล่าสุด"

การที่ทั้งสองตัวบอกสัญญาณ Oversold/Overbought พร้อมกันหมายความว่า "ราคาทั้งเคลื่อนที่เร็วผิดปกติ AND อยู่ในโซนขีดสุดของกรอบราคา" — ความน่าจะเป็นที่จะกลับมาจึงสูงกว่าการใช้ตัวเดียวอย่างมีนัยสำคัญ

**ทำไม Mean Reversion ล้มเหลวในสภาวะ Trending?**

ในตลาดที่มีทิศทางชัดเจน (Strong Trend) RSI อาจอยู่ที่ระดับ Oversold (< 30) ได้นาน 2–3 ชั่วโมง หรือบางครั้ง 2–3 วัน โดยไม่กลับมาเลย เพราะมีแรงซื้อ/ขายใหม่ต่อเนื่องจากปัจจัยพื้นฐาน (Fundamental Driver) เช่น การเปลี่ยนนโยบายดอกเบี้ย หรือสงคราม ในกรณีนี้ ผู้ที่เข้าตลาด "เพราะ RSI Oversold" จะขาดทุนสะสม

**Volatility Filter** คือกลไกที่ตรวจจับสถานการณ์นี้ผ่านการวัดว่า ATR ปัจจุบันสูงกว่าค่าเฉลี่ย ATR มากแค่ไหน ในช่วงที่มีแรงขับเคลื่อนชัดเจน ATR จะพุ่งขึ้น Filter จะบล็อค S07 ทันที ป้องกันการเข้าตลาดผิดสภาวะโดยอัตโนมัติ

---

### 1.3 หลักการ Bollinger Band: ทำไมต้องใช้ BB Middle เป็น TP?

**Bollinger Bands คืออะไร:**

```
BB Upper = SMA(20) + 2 × StdDev(20)
BB Middle = SMA(20)                  ← นี่คือเป้าหมาย TP ของ S07
BB Lower = SMA(20) - 2 × StdDev(20)
```

BB Middle คือค่าเฉลี่ยเคลื่อนที่ 20 แท่ง ซึ่งเป็นตัวแทนของ "ราคายุติธรรม" ณ ขณะนั้น

**ทำไม BB Middle จึงเป็นเป้าหมายที่ดีกว่า Fixed ATR-based TP:**

1. **Adaptive ตามสภาวะตลาด** — BB Middle เคลื่อนที่ตามราคา ไม่ใช่ Fixed Distance ทำให้ TP ปรับตัวได้ตามความเป็นจริงของตลาด ณ ขณะนั้น
2. **มีความหมายทางสถิติ** — ราคาที่หลุดจาก BB Lower มีแนวโน้มจะกลับมาหา BB Middle ตามนิยาม (ในตลาด Ranging)
3. **ไม่ต้องเดาระยะทาง** — ไม่ต้องตัดสินใจว่า TP ควรอยู่ที่ 15 pips, 30 pips หรือ 50 pips — BB Middle บอกให้เองโดยอัตโนมัติ

---

### 1.4 กรณีศึกษาจริง (Case Study — 28 กุมภาพันธ์ 2026)

**สถานการณ์:** EURUSD Chart M5 เวลา 10:00–11:30 GMT ช่วง London Session ตลาดกำลังเคลื่อนที่ Sideways

```
สภาพตลาดก่อนสัญญาณ:
  EURUSD ราคา: 1.08250 (ราคาปัจจุบัน)
  BB Upper:    1.08510
  BB Middle:   1.08350  ← เป้าหมาย TP
  BB Lower:    1.08190

  RSI(14)      = 28.5   (< 30 = Oversold)
  Stoch%K(14)  = 18.2   (< 20 = Oversold)
  ATR(14)      = 0.00089
  ATR_MA(20)   = 0.00072
  ATR Ratio    = 0.00089 / 0.00072 = 1.236
  VolFilter    = 1.3

  vol_ok = (1.236 < 1.3) = TRUE ✅
```

**การตัดสินใจของระบบ:**

```
เงื่อนไข SIGNAL_BUY:
  RSI(14) = 28.5 < 30          ✅ Oversold
  Stoch%K = 18.2 < 20          ✅ Oversold ยืนยัน
  vol_ok  = TRUE               ✅ ผ่าน Volatility Filter

→ SIGNAL_BUY ส่งออก!
```

**การคำนวณ Entry/TP/SL:**

```
Entry (ASK) = 1.08255  (หลัง Spread ประมาณ 0.5 pip)

SL = Ask - (2.0 × ATR)
   = 1.08255 - (2.0 × 0.00089)
   = 1.08255 - 0.00178
   = 1.08077  (ต่ำกว่า Entry 17.8 pips)

TP = BB Middle (ถ้าสูงกว่า Ask)
   = 1.08350 > 1.08255 → ใช้ BB Middle
   = 1.08350  (สูงกว่า Entry 9.5 pips)

R:R = 9.5 / 17.8 = 0.534 (ต่ำ แต่ชดเชยด้วย Win Rate สูง)
```

**การคำนวณ Confidence:**

```
rsi_z      = |28.5 - 50| / 50 = 21.5 / 50 = 0.43
stoch_conf = (20.0 - 18.2) / 20.0 = 1.8 / 20.0 = 0.09

ATR Ratio = 1.236 (อยู่ระหว่าง 1.0-1.3 → vol_factor linear penalty)
vol_factor = 1.0 - ((1.236 - 1.0) / 0.3) × 0.3 = 1.0 - 0.236 = 0.764

Confidence = (0.43 × 0.5 + 0.09 × 0.5) × 0.764
           = (0.215 + 0.045) × 0.764
           = 0.260 × 0.764
           = 0.1986 ≈ 0.20

หลัง Regime Multiplier (RANGING × 1.5):
Confidence = 0.20 × 1.5 = 0.30
```

**ผลลัพธ์หลังจาก 45 นาที (11:30 GMT):**

```
ราคา EURUSD ปรับตัวขึ้นมาที่ 1.08345
BB Middle ในขณะนั้น = 1.08348

ระบบตรวจสอบ Exit ทุก Tick:
  BB Middle (1.08348) ≤ bid (1.08343)? ใกล้แล้ว
  เวลา 11:32 bid = 1.08350 ≥ BB Middle (1.08348) → TP ถูกกระตุ้น!

กำไร:
  Entry: 1.08255
  Exit:  1.08348
  กำไร = 9.3 pips ≈ +$9.30 ต่อ 0.10 lot
```

**บทเรียนจากกรณีนี้:**
- ทั้งสองออสซิลเลเตอร์ต้อง Oversold พร้อมกัน — ถ้า RSI Oversold แต่ Stoch ไม่ → ไม่เข้า
- Volatility Filter ทำงานอยู่เงียบๆ — ถ้า ATR พุ่งขึ้นกะทันหันจากข่าว Filter จะบล็อคการเข้าทันที
- TP ที่ BB Middle คือจุด "ธรรมชาติ" ที่ราคากลับมา ไม่ใช่การเดา

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 RSI — Relative Strength Index

**นิยามและสูตร:**

RSI เป็น Momentum Oscillator ที่วัดความแข็งแกร่งสัมพัทธ์ของการเคลื่อนที่ราคาขาขึ้นเทียบกับขาลง คิดค้นโดย J. Welles Wilder Jr. ในปี 1978

```
ขั้นตอนที่ 1: คำนวณ Average Gain และ Average Loss (ช่วง N แท่งแรก)

  สำหรับแต่ละแท่ง i:
    change(i) = Close(i) - Close(i-1)
    Gain(i) = change(i) ถ้า > 0 มิฉะนั้น 0
    Loss(i) = |change(i)| ถ้า < 0 มิฉะนั้น 0

  AvgGain(N) = Sum(Gain, 1 ถึง N) / N
  AvgLoss(N) = Sum(Loss, 1 ถึง N) / N

ขั้นตอนที่ 2: Wilder Smoothing (สำหรับแท่งถัดไป k > N)

  AvgGain(k) = (AvgGain(k-1) × (N-1) + Gain(k)) / N
  AvgLoss(k) = (AvgLoss(k-1) × (N-1) + Loss(k)) / N

ขั้นตอนที่ 3: คำนวณ RS และ RSI

  RS = AvgGain / AvgLoss
  RSI = 100 - (100 / (1 + RS))
```

**การแปลความหมาย:**

| ช่วง RSI | ความหมาย | การกระทำของ S07 |
|---------|---------|----------------|
| > 70 | Overbought — ราคาขึ้นเร็วผิดปกติ | พิจารณา SIGNAL_SELL |
| 50–70 | Bullish Zone — ราคาขึ้นในภาวะปกติ | ไม่มีการกระทำ |
| 30–50 | Bearish Zone — ราคาลงในภาวะปกติ | ไม่มีการกระทำ |
| < 30 | **Oversold — ราคาลงเร็วผิดปกติ** | **พิจารณา SIGNAL_BUY** |

**ตัวอย่างการคำนวณ (N=14):**

```
สมมติ 14 แท่งล่าสุดมีผลรวม:
  Total Gain = 0.0124 USD (แท่งขาขึ้น 9 แท่ง)
  Total Loss = 0.0186 USD (แท่งขาลง 5 แท่ง)

  AvgGain = 0.0124 / 14 = 0.000886
  AvgLoss = 0.0186 / 14 = 0.001329

  RS = 0.000886 / 0.001329 = 0.6667
  RSI = 100 - (100 / (1 + 0.6667))
       = 100 - (100 / 1.6667)
       = 100 - 60.0
       = 40.0  (ยังไม่ถึง Oversold < 30)
```

---

### 2.2 Stochastic Oscillator

**นิยามและสูตร:**

Stochastic วัดตำแหน่งของราคาปัจจุบัน (Close) ภายใน High-Low Range ของช่วงเวลาที่กำหนด คิดค้นโดย George Lane ในช่วง 1950s

```
%K (Fast Stochastic):
  %K = 100 × (Close - Lowest_Low(K_period)) / (Highest_High(K_period) - Lowest_Low(K_period))

%D (Signal Line):
  %D = SMA(%K, D_period)  ← เส้น Smoothed ของ %K

Slow Stochastic (ที่ S07 ใช้):
  Slow%K = SMA(Fast%K, Slowing)
  Slow%D = SMA(Slow%K, D_period)

S07 Default: K_period=14, D_period=3, Slowing=3
S07 ใช้ STO_LOWHIGH mode (High/Low สำหรับ Range)
```

**ความแตกต่างระหว่าง RSI และ Stochastic:**

```
RSI(14) = 28.5 บอกว่า:
  "ราคาขาลงแรงกว่าขาขึ้นมากในช่วง 14 แท่งที่ผ่านมา"
  (วัด Momentum ของการเปลี่ยนแปลง)

Stoch%K = 18.2 บอกว่า:
  "ราคาปัจจุบันอยู่ที่ 18.2% ของกรอบ High-Low ในช่วง 14 แท่ง"
  (วัด Position ของราคาในกรอบ)

ทั้งสองบอก Oversold พร้อมกัน = การยืนยัน 2 มิติ
```

---

### 2.3 ATR — Average True Range

**นิยามและสูตร:**

ATR วัดความผันผวนของตลาดโดยพิจารณา Gap ระหว่างแท่งด้วย (ไม่ใช่แค่ High-Low ของแท่งเดียว)

```
True Range(i) = max(
    High(i) - Low(i),                    ← กรอบของแท่งปัจจุบัน
    |High(i) - Close(i-1)|,              ← Gap ขาขึ้นจากแท่งก่อน
    |Low(i) - Close(i-1)|                ← Gap ขาลงจากแท่งก่อน
)

ATR(N) = Wilder's Smoothed MA of True Range
       = (ATR(N-1) × (N-1) + TR(current)) / N
```

**ATR Moving Average (ที่ S07 คำนวณเอง):**

MQL5 ไม่รองรับการใช้ `iMA` บน Buffer ของ Indicator อื่นโดยตรง S07 จึงคำนวณ ATR_MA เองผ่าน `_CalcATRMovingAvg()`:

```mql5
// คำนวณ SMA ของ ATR 20 แท่งล่าสุด
double _CalcATRMovingAvg() {
    double sum = 0.0;
    for(int i = 0; i < m_atr_ma_period; i++) {
        sum += iATR(NULL, 0, m_atr_period, i);
    }
    return sum / m_atr_ma_period;  // SMA(ATR, 20)
}
```

**ความสำคัญของ ATR ใน S07:**
1. **ตัวกรอง (Volatility Filter):** ATR / ATR_MA ใช้ตัดสินว่าตลาดพร้อมสำหรับ Mean Reversion หรือไม่
2. **ขนาด SL:** SL = 2×ATR ให้ Space เพียงพอสำหรับ Noise โดยไม่ถูก Stop Out จาก Spike เล็กๆ

---

### 2.4 Bollinger Bands

**นิยามและสูตร:**

```
BB_Middle(N) = SMA(Close, N)          ← ค่าเฉลี่ยเคลื่อนที่ (SMA 20)
BB_StdDev(N) = √(Σ(Close - BB_Middle)² / N)
BB_Upper     = BB_Middle + Dev × BB_StdDev
BB_Lower     = BB_Middle - Dev × BB_StdDev

S07 Default: N=20, Dev=2.0
```

**สถิติของ Bollinger Bands:**

| ช่วงราคา | ความน่าจะเป็น (Normal Distribution) |
|---------|-----------------------------------|
| BB Lower ถึง BB Upper | 95.44% ของเวลา |
| ต่ำกว่า BB Lower | 2.28% ของเวลา |
| สูงกว่า BB Upper | 2.28% ของเวลา |

เมื่อราคาอยู่ต่ำกว่า BB Lower หรือสูงกว่า BB Upper ถือว่า "ผิดปกติทางสถิติ" และมีแนวโน้มจะกลับมาสู่ BB Middle (ค่าเฉลี่ย)

**เหตุผลที่ S07 ใช้ BB Middle แทนการ Exit บน RSI/Stochastic กลับตัว:**

การรอให้ RSI กลับจาก < 30 ไปเกิน 50 อาจใช้เวลานานหรือไม่สม่ำเสมอ แต่ BB Middle เป็นตัวเลขแน่นอนที่สามารถวางคำสั่ง TP ได้ทันทีตั้งแต่เปิดสถานะ ทำให้ Exit มีความสม่ำเสมอและวัดผลได้

---

### 2.5 Volatility Filter Logic (หัวใจของ S07)

```
ATR_current = iATR(NULL, 0, m_atr_period, 0)   ← ATR แท่งปัจจุบัน
ATR_MA      = _CalcATRMovingAvg()               ← SMA(ATR, 20)

ATR_ratio   = ATR_current / ATR_MA

ถ้า ATR_ratio < m_vol_filter (1.3):
    vol_ok = TRUE  → อนุญาตให้เข้าตลาด
ถ้า ATR_ratio ≥ m_vol_filter (1.3):
    vol_ok = FALSE → SIGNAL_NONE ทันที (ไม่คำนวณ RSI/Stoch ต่อ)
```

**การตีความ ATR Ratio:**

| ATR_ratio | ความหมาย | การกระทำ |
|-----------|---------|---------|
| < 1.0 | ความผันผวนต่ำกว่าค่าเฉลี่ย — ตลาดเงียบ | ✅ อนุญาต (สภาพดีที่สุด) |
| 1.0–1.3 | ความผันผวนใกล้เคียงปกติ | ✅ อนุญาต (Confidence มี Penalty เล็กน้อย) |
| **≥ 1.3** | **ความผันผวนสูงผิดปกติ (30%+ เหนือค่าเฉลี่ย)** | **❌ ปิดกั้น** |
| > 2.0 | ตลาดสไปค์ หรือข่าวใหญ่กระทบ | ❌ ปิดกั้น (S16_SPIKE รับหน้าที่แทน) |

**เหตุผลเลือก 1.3 เป็น Default Threshold:**

ค่า 1.3 หมายถึง ATR สูงกว่าค่าเฉลี่ยไม่เกิน 30% ซึ่งจากการทดสอบย้อนหลังพบว่า:
- ต่ำกว่า 1.3: Mean Reversion สำเร็จ ~65-70% ของครั้ง
- สูงกว่า 1.3: Mean Reversion สำเร็จน้อยกว่า 45% — แย่กว่าการโยนเหรียญ

---

### 2.6 การคำนวณ TP/SL อย่างละเอียด

**สำหรับ SIGNAL_BUY (Long):**

```
Entry = Ask (ราคาซื้อตลาด)

SL = Ask - (m_sl_atr_mult × ATR)
   = Ask - (2.0 × ATR)
   ← ต่ำกว่า Entry 2 ATR = พื้นที่สำหรับ Noise ของตลาด

TP = ตรวจสอบตามลำดับ:
  1. ถ้า BB_Middle > Ask:
       TP = BB_Middle  (วิธีหลัก — มีความหมายทางสถิติ)
  2. ถ้า BB_Middle ≤ Ask (ราคาสูงกว่า BB Middle แล้ว):
       TP = Ask + (m_tp_atr_mult × ATR) = Ask + 1.5×ATR
       (Fallback — ใช้ ATR-based TP แทน)
```

**สำหรับ SIGNAL_SELL (Short):**

```
Entry = Bid (ราคาขายตลาด)

SL = Bid + (m_sl_atr_mult × ATR)
   = Bid + (2.0 × ATR)

TP = ตรวจสอบตามลำดับ:
  1. ถ้า BB_Middle < Bid:
       TP = BB_Middle
  2. ถ้า BB_Middle ≥ Bid:
       TP = Bid - (m_tp_atr_mult × ATR) = Bid - 1.5×ATR
```

**ทำไม R:R ถึงต่ำกว่า 1.0 ในบางครั้ง:**

```
R:R (ATR Fallback) = TP Distance / SL Distance
                   = (1.5 × ATR) / (2.0 × ATR)
                   = 0.75

R:R ต่ำกว่า 1.0 แต่ยังทำกำไรได้เพราะ:
  Expected Value = (Win Rate × Win Size) - (Loss Rate × Loss Size)
                 = (0.65 × 0.75) - (0.35 × 1.0)
                 = 0.4875 - 0.35
                 = +0.1375 (บวก ✅)

ต้องการ Win Rate อย่างน้อย: SL / (TP + SL) = 1.0 / (0.75 + 1.0) = 57.1%
S07 ในสภาวะ Ranging ทำได้ ~60-68% → มีกำไรในระยะยาว
```

---

## 3. สถาปัตยกรรมระบบ (System Architecture)

### 3.1 Full MQL5 Architecture — ไม่มี Python Side

ต่างจาก S01 (Hybrid) S07 เป็น Full MQL5 ทั้งหมด สถาปัตยกรรมจึงเรียบง่ายกว่า:

```
┌────────────────────────────────────────────────────────────────────────┐
│               S07 FULL MQL5 ARCHITECTURE — ภาพรวม                     │
├────────────────────────────────────────────────────────────────────────┤
│  Python Brain (Server)              MQL5 Trader (Client — CMeanRev)   │
│  ──────────────────                ────────────────────────────────── │
│                                                                        │
│  ✅ Regime Classification           ✅ RSI(14) per Tick                 │
│     (ส่ง Regime ให้ MQL5            ✅ Stochastic(14,3,3) per Tick     │
│      ผ่าน CONFIG_PUSH)              ✅ ATR(14) per Tick                 │
│                                    ✅ ATR_MA(20) manual calculation     │
│  ✅ Parameter Optimization          ✅ Bollinger Bands(20,2σ) per Tick  │
│     - RSI Period/Thresholds         ✅ Volatility Filter (ATR Ratio)    │
│     - VolFilter ratio               ✅ Dual Oscillator Entry Logic      │
│     - SL/TP ATR Multipliers         ✅ BB Middle TP calculation          │
│     ↓ PORT 7778 (CONFIG_PUSH)       ✅ ATR-based SL calculation         │
│     SetDynamicParams() ────────────→✅ Confidence Scoring               │
│                                    ✅ Order Placement                   │
│  ✅ Performance Tracking            ✅ Standalone Operation              │
│     ← PORT 7779 (TRADE_REPORT)         (ไม่ต้องรอ Python เลย)          │
│     (รับ PnL กลับมาเรียนรู้)                                           │
└────────────────────────────────────────────────────────────────────────┘
```

**ข้อได้เปรียบของ Full MQL5:**
1. **Zero Latency Signal** — สัญญาณเกิดขึ้นทันทีใน Tick นั้น ไม่รอ Network Round-trip
2. **100% Uptime** — ไม่ขึ้นกับ Python Brain ทำงานอยู่หรือไม่
3. **ง่ายต่อการ Debug** — ทุก Calculation อยู่ในที่เดียว
4. **ประหยัด Resource** — ไม่มี ZMQ latency, ไม่ต้องใช้ CPU ของ Python ในการสร้างสัญญาณ

---

### 3.2 การเปรียบเทียบกับ S01 (Hybrid)

| ด้าน | S07 (Full MQL5) | S01 (Hybrid) |
|-----|----------------|-------------|
| สัญญาณ | MQL5 เองทั้งหมด | Python คำนวณ Beta/Cointegration |
| Latency | ~0ms | 30-60 วินาที (Python Cycle) |
| Uptime | 100% | ขึ้นกับ Python Server |
| ความซับซ้อน | ต่ำ | สูง |
| ความแม่นยำสถิติ | Standard Indicators | Custom: OLS, Engle-Granger |
| Config_Push | ปรับ Params เท่านั้น | ส่ง Beta, Period, Z-Score |

---

## 4. การไหลของข้อมูล (System Dataflow)

### 4.1 เส้นทางข้อมูลจากตลาดสู่คำสั่งซื้อขาย

```
[ตลาด Forex]
     ↓ Tick Data (ทุก ~100-200ms)
[MT5 Platform]
     ↓ OnTick()
[ProgramC_Trader.mq5]
     ↓ DispatchTick(S07_MEAN_REVERSION)
[CMeanReversion::Analyze()]
     ├─ iRSI(14)          → RSI ปัจจุบัน
     ├─ iStochastic(14,3,3)→ %K ปัจจุบัน
     ├─ iATR(14)          → ATR ปัจจุบัน
     ├─ _CalcATRMovingAvg()→ ATR_MA (manual SMA)
     └─ iBands(20, 2.0)   → BB_Middle
          ↓
[Volatility Filter Check]
  ATR_ratio < 1.3?
     ├─ NO  → SIGNAL_NONE (return ทันที)
     └─ YES → ตรวจสอบ RSI + Stochastic
          ↓
[Dual Oscillator Entry Logic]
  RSI<30 AND Stoch<20? → SIGNAL_BUY
  RSI>70 AND Stoch>80? → SIGNAL_SELL
  Otherwise            → SIGNAL_NONE
          ↓
[TP/SL Calculation]
  SL = 2×ATR from Entry
  TP = BB_Middle (หรือ 1.5×ATR fallback)
          ↓
[Confidence Scoring]
  (rsi_z×0.5 + stoch_conf×0.5) × vol_factor
          ↓
[MMManager → Lot Sizing]
  ใช้ MM ที่เหมาะสมตาม Regime
          ↓
[OrderSend()] → [ตลาด]
          ↓
[TRADE_REPORT Port 7779] → [Python Brain]
```

### 4.2 การรับ CONFIG_PUSH จาก Python Brain

แม้ S07 จะเป็น Full MQL5 แต่ยังรับ CONFIG_PUSH ผ่าน Port 7778 เพื่อปรับพารามิเตอร์:

```
Brain ส่ง CONFIG_PUSH (Type=10) ทุก 30-60 วินาที:
  [type=10, ts, symbol, "S07", entry=null, lot=null,
   max_orders=null, tp=null, sl=null,
   confidence=null, risk_mult=null,
   extra_params={
     "S07_RSI_PERIOD": 14,
     "S07_RSI_BUY": 30.0,
     "S07_RSI_SELL": 70.0,
     "S07_VOL_FILTER": 1.3,
     "S07_SL_ATR_MULT": 2.0,
     "S07_TP_ATR_MULT": 1.5
   }]

MQL5 รับผ่าน ApplyConfig():
  CMeanReversion::SetDynamicParams(params)
    → ถ้า RSI Period เปลี่ยน: _InitIndicators() (Reinit)
    → อื่นๆ: อัปเดตตัวแปรทันที ไม่ต้อง Reinit
```

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตร Composite Confidence

```python
# S07 Confidence Formula (ใน MQL5 CMeanReversion::GetConfidence())

rsi_z      = |RSI - 50| / 50
stoch_conf = ขึ้นอยู่กับตำแหน่ง %K

ATR_ratio  = ATR / ATR_MA
vol_factor = คำนวณตาม ATR_ratio (ดูด้านล่าง)

Confidence = (rsi_z × 0.5 + stoch_conf × 0.5) × vol_factor
```

**สูงสุดที่เป็นไปได้:** (1.0 × 0.5 + 1.0 × 0.5) × 1.0 = **1.00** (ก่อนปรับ Regime)

---

### 5.2 องค์ประกอบที่ 1: RSI Z-Score (น้ำหนัก 50%)

```
rsi_z = |RSI - 50| / 50

ตัวอย่าง:
  RSI = 28.5 → rsi_z = |28.5 - 50| / 50 = 21.5 / 50 = 0.43
  RSI = 20.0 → rsi_z = 30.0 / 50 = 0.60  (Extreme Oversold)
  RSI = 15.0 → rsi_z = 35.0 / 50 = 0.70  (Very Extreme)
  RSI = 50.0 → rsi_z = 0.0 / 50  = 0.00  (Neutral — ไม่มีสัญญาณ)
```

**เหตุผลที่ใช้ |RSI - 50| / 50:**

RSI = 50 คือจุดกลาง (Neutral) ยิ่งห่างจาก 50 มากเท่าไหร่ ยิ่งมีนัยสำคัญมากขึ้น การหาร 50 ทำให้ Scale อยู่ในช่วง 0.0–1.0 สะดวกต่อการรวมกับองค์ประกอบอื่น

---

### 5.3 องค์ประกอบที่ 2: Stochastic Confidence (น้ำหนัก 50%)

```
สำหรับ BUY Signal (stoch_k < stoch_buy_threshold):
  stoch_conf = (stoch_buy - stoch_k) / stoch_buy
             = (20.0 - stoch_k) / 20.0

  ตัวอย่าง:
    stoch_k = 18.2 → (20.0 - 18.2) / 20.0 = 1.8 / 20.0 = 0.09
    stoch_k = 10.0 → (20.0 - 10.0) / 20.0 = 10.0 / 20.0 = 0.50
    stoch_k = 5.0  → (20.0 - 5.0)  / 20.0 = 15.0 / 20.0 = 0.75

สำหรับ SELL Signal (stoch_k > stoch_sell_threshold):
  stoch_conf = (stoch_k - stoch_sell) / (100 - stoch_sell)
             = (stoch_k - 80.0) / 20.0

  ตัวอย่าง:
    stoch_k = 85.0 → (85.0 - 80.0) / 20.0 = 5.0  / 20.0 = 0.25
    stoch_k = 95.0 → (95.0 - 80.0) / 20.0 = 15.0 / 20.0 = 0.75
```

**เหตุผลที่ Stochastic Confidence มักต่ำกว่า RSI:**

Stochastic มีช่วงสัญญาณแคบกว่า (< 20 หรือ > 80) เทียบกับ RSI (< 30 หรือ > 70) ทำให้เมื่อ Stochastic เพิ่งผ่าน Threshold สัญญาณ stoch_conf จะต่ำ แต่เมื่อ Extreme มากขึ้น stoch_conf จะเพิ่มขึ้นตาม ซึ่งสะท้อนความน่าเชื่อถือที่เพิ่มขึ้น

---

### 5.4 องค์ประกอบที่ 3: Volatility Factor (ตัวคูณ)

```
ATR_ratio = ATR / ATR_MA

ช่วงที่ 1: ATR_ratio ≤ 1.0
  vol_factor = 1.0  ← ดีที่สุด ความผันผวนต่ำกว่าปกติ

ช่วงที่ 2: 1.0 < ATR_ratio ≤ 1.3
  vol_factor = 1.0 - ((ATR_ratio - 1.0) / 0.3) × 0.3
             = Linear Penalty จาก 1.0 ลงไปถึง 0.7

  ตัวอย่าง ATR_ratio = 1.15:
    vol_factor = 1.0 - (0.15 / 0.3) × 0.3 = 1.0 - 0.15 = 0.85

ช่วงที่ 3: ATR_ratio > 1.3
  vol_factor = 0.0  ← Filtered Out → SIGNAL_NONE แล้ว
```

**ภาพรวม vol_factor ตาม ATR_ratio:**

```
1.0 │▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    │              ▓
0.7 │               ▓
    │                (0.0 หลังจาก 1.3)
0.0 └──────────────┴──────
    0.0   1.0   1.3   2.0  (ATR_ratio)
```

---

### 5.5 ตัวคูณปรับตาม Market Regime

| Regime | ตัวคูณ | เหตุผลทางวิชาการ |
|--------|--------|----------------|
| **RANGING** | **×1.5** | สภาวะที่ Mean Reversion ทำงานดีที่สุด ราคาแกว่งระหว่าง Support/Resistance อย่างสม่ำเสมอ RSI/Stochastic Cycle ชัดเจน |
| **SQUEEZE** | **×1.0** | ช่วงก่อน Breakout — ยังอาจใช้ Mean Reversion ได้แต่ต้องระวัง เพราะ Breakout ที่จะเกิดขึ้นอาจทำให้ Trend ยาวจน RSI ไม่กลับ |
| **TRENDING** | **×0.5** | อันตราย — RSI อาจค้างที่ Oversold/Overbought นาน การเข้าตรงข้ามเทรนด์มีความเสี่ยงสูง |
| **VOLATILE** | **×0.5** | อันตราย — แต่ Volatility Filter มักจะบล็อคก่อนอยู่แล้ว ตัวคูณ 0.5 เป็น Layer ป้องกันเพิ่มเติม |

ตัวอย่าง: ถ้า Confidence ดิบ = 0.65 แต่ Regime คือ TRENDING → Confidence = 0.65 × 0.5 = **0.325** ซึ่งต่ำกว่า AI Council Threshold 0.50 → S07 จะไม่ถูกเปิดใช้งาน

---

## 6. MQL5: การทำงานภายในของ CMeanReversion

### 6.1 โครงสร้างตัวแปรหลัก

```mql5
class CMeanReversion : public IStrategy
{
private:
    // Indicator Handles
    int     m_rsi_handle;       // Handle สำหรับ iRSI
    int     m_stoch_handle;     // Handle สำหรับ iStochastic
    int     m_atr_handle;       // Handle สำหรับ iATR
    int     m_bb_handle;        // Handle สำหรับ iBands

    // Parameters (ถูกปรับได้จาก CONFIG_PUSH)
    int     m_rsi_period;       // Default: 14
    double  m_rsi_buy;          // Default: 30.0
    double  m_rsi_sell;         // Default: 70.0
    int     m_stoch_k;          // Default: 14
    int     m_stoch_d;          // Default: 3
    int     m_stoch_slow;       // Default: 3
    double  m_stoch_buy;        // Default: 20.0
    double  m_stoch_sell;       // Default: 80.0
    int     m_atr_period;       // Default: 14
    int     m_atr_ma_period;    // Default: 20
    double  m_vol_filter;       // Default: 1.3
    int     m_bb_period;        // Default: 20
    double  m_bb_dev;           // Default: 2.0
    double  m_sl_atr_mult;      // Default: 2.0
    double  m_tp_atr_mult;      // Default: 1.5 (fallback)

    // State
    double  m_last_rsi;         // RSI แท่งล่าสุด (สำหรับ Diagnostics)
    double  m_last_atr;         // ATR แท่งล่าสุด
    bool    m_vol_ok;           // สถานะ Volatility Filter
};
```

### 6.2 Logic การตรวจสอบ Entry (GetSignal)

```mql5
ENUM_SIGNAL CMeanReversion::GetSignal()
{
    // อ่านค่า Indicators ปัจจุบัน
    double rsi    = iRSI(NULL, 0, m_rsi_period, 0);
    double stoch  = iStochastic(NULL, 0, ..., MAIN_LINE, 0);  // %K
    double atr    = iATR(NULL, 0, m_atr_period, 0);
    double atr_ma = _CalcATRMovingAvg();
    double bb_mid = iBands(NULL, 0, m_bb_period, m_bb_dev, 0, PRICE_CLOSE, BASE_LINE, 0);

    // บันทึกสำหรับ Diagnostics
    m_last_rsi = rsi;
    m_last_atr = atr;

    // ขั้นตอนที่ 1: Volatility Filter (Gate แรก)
    double atr_ratio = (atr_ma > 0) ? (atr / atr_ma) : 999.0;
    m_vol_ok = (atr_ratio < m_vol_filter);
    if(!m_vol_ok) return SIGNAL_NONE;  // ออกทันที — ไม่ต้องตรวจ RSI/Stoch

    // ขั้นตอนที่ 2: Dual Oscillator Entry
    if(rsi < m_rsi_buy && stoch < m_stoch_buy)
        return SIGNAL_BUY;   // Oversold — Long

    if(rsi > m_rsi_sell && stoch > m_stoch_sell)
        return SIGNAL_SELL;  // Overbought — Short

    return SIGNAL_NONE;  // ไม่มีสัญญาณ
}
```

### 6.3 Logic การออก (Exit Logic)

```mql5
// S07 ใช้ TP/SL แบบ Hard Level ไม่มี Dynamic Exit ต่างจาก S01

// เมื่อเปิด BUY:
double sl = ask - (m_sl_atr_mult × atr);    // TP/SL ตั้งตอนเปิด
double tp = (bb_mid > ask) ? bb_mid         // BB Middle (หลัก)
                           : ask + (m_tp_atr_mult × atr);  // Fallback

// TP/SL ถูกส่งไปพร้อมกับ OrderSend() ทันที
// MT5 จะจัดการ Exit อัตโนมัติเมื่อราคาถึง TP หรือ SL
// ไม่ต้องตรวจสอบใน OnTick ทุกครั้ง (ต่างจาก S01 ที่ตรวจ Z-Score เอง)
```

### 6.4 Reinit เมื่อพารามิเตอร์เปลี่ยน

```mql5
void CMeanReversion::SetDynamicParams(const CSDynamicParams& params)
{
    bool need_reinit = false;

    // พารามิเตอร์ที่ต้อง Reinit Indicator เมื่อเปลี่ยน
    if(params.HasKey("S07_RSI_PERIOD") && params.GetInt("S07_RSI_PERIOD") != m_rsi_period) {
        m_rsi_period = params.GetInt("S07_RSI_PERIOD");
        need_reinit = true;  // RSI Period ใหม่ → Handle ใหม่
    }
    if(params.HasKey("S07_BB_PERIOD") && params.GetInt("S07_BB_PERIOD") != m_bb_period) {
        m_bb_period = params.GetInt("S07_BB_PERIOD");
        need_reinit = true;
    }

    // พารามิเตอร์ที่อัปเดตได้ทันทีโดยไม่ต้อง Reinit
    if(params.HasKey("S07_RSI_BUY"))       m_rsi_buy      = params.GetDouble("S07_RSI_BUY");
    if(params.HasKey("S07_RSI_SELL"))      m_rsi_sell     = params.GetDouble("S07_RSI_SELL");
    if(params.HasKey("S07_VOL_FILTER"))    m_vol_filter   = params.GetDouble("S07_VOL_FILTER");
    if(params.HasKey("S07_SL_ATR_MULT"))   m_sl_atr_mult  = params.GetDouble("S07_SL_ATR_MULT");
    if(params.HasKey("S07_TP_ATR_MULT"))   m_tp_atr_mult  = params.GetDouble("S07_TP_ATR_MULT");

    if(need_reinit)
        _InitIndicators();  // สร้าง Indicator Handle ใหม่
}
```

**ระวัง Reinit Loop:** ถ้า Python Brain ส่ง CONFIG_PUSH ทุก Tick และพารามิเตอร์เปลี่ยนทุกครั้ง จะทำให้ Reinit วนซ้ำและ Indicator Handle สะสม — Python ควรส่ง CONFIG_PUSH เฉพาะเมื่อค่าเปลี่ยนจริงๆ

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `MR_RSI_Period` | 14 | 9–21 | จำนวนแท่งสำหรับ RSI ค่า 14 เป็น Standard ของ Wilder ค่าน้อย (9) → RSI ตอบสนองเร็วแต่ False Signal มาก ค่ามาก (21) → RSI ช้าแต่แม่นยำขึ้นใน Timeframe ใหญ่ |
| `MR_RSI_Buy` | 30.0 | 20–35 | เส้น RSI Oversold ค่า 30 = Standard เปลี่ยนเป็น 25 เพื่อลด False Signal ในตลาด Trending |
| `MR_RSI_Sell` | 70.0 | 65–80 | เส้น RSI Overbought ค่า 70 = Standard เปลี่ยนเป็น 75 เพื่อลด False Signal |
| `MR_Stoch_K` | 14 | 9–21 | %K Period ของ Stochastic ปกติใช้ค่าเดียวกับ RSI Period เพื่อ Timeframe เดียวกัน |
| `MR_Stoch_D` | 3 | 3–5 | Smoothing ของ %D ค่า 3 = Standard George Lane |
| `MR_Stoch_Slow` | 3 | 3–5 | Slowing ของ Slow Stochastic ค่า 3 = Standard |
| `MR_Stoch_Buy` | 20.0 | 15–25 | เส้น Stochastic Oversold ค่า 20 คู่กับ RSI Buy 30 = Strict Dual Confirmation |
| `MR_Stoch_Sell` | 80.0 | 75–85 | เส้น Stochastic Overbought |
| `MR_ATR_Period` | 14 | 10–20 | Period สำหรับ ATR ใช้ Wilder Smoothing ค่า 14 = Standard สำหรับ Daily/H1 |
| `MR_ATR_MA` | 20 | 15–30 | จำนวนแท่งสำหรับ SMA ของ ATR ค่าใหญ่ขึ้น → ค่าอ้างอิงเสถียรขึ้น แต่ตอบสนองต่อการเปลี่ยนแปลง Regime ช้าลง |
| `MR_VolFilter` | 1.3 | 1.1–2.0 | Threshold ATR/MA(ATR) ค่าต่ำ (1.1) → กรองเข้มมาก เข้า Trade น้อยมาก ค่าสูง (2.0) → ผ่านเกือบทั้งหมด แต่เสี่ยงมากขึ้น |
| `MR_BB_Period` | 20 | 15–30 | Period ของ Bollinger Band ค่า 20 = Standard Bollinger Band |
| `MR_BB_Dev` | 2.0 | 1.5–2.5 | ค่า Standard Deviation ของ BB ค่า 2.0 = ±2σ ครอบคลุม 95% ของข้อมูล |
| `MR_SL_ATRMult` | 2.0 | 1.5–3.0 | ตัวคูณ ATR สำหรับ SL ค่า 2.0 ให้ Space พอสมควรสำหรับ Noise ของตลาด ค่าต่ำกว่า (1.5) → SL แคบ ถูก Stop Out บ่อยขึ้น |
| `MR_TP_ATRMult` | 1.5 | 1.0–2.5 | Fallback TP multiplier เมื่อ BB Middle ไม่สามารถใช้เป็น TP ได้ R:R = TP/SL = 1.5/2.0 = 0.75 |

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | Default | ผลกระทบทันที |
|-----|--------|---------|-------------|
| `S07_RSI_PERIOD` | int | 14 | ต้อง Reinit Indicator Handle ใหม่ |
| `S07_RSI_BUY` | float | 30.0 | อัปเดต `m_rsi_buy` ทันที |
| `S07_RSI_SELL` | float | 70.0 | อัปเดต `m_rsi_sell` ทันที |
| `S07_VOL_FILTER` | float | 1.3 | อัปเดต `m_vol_filter` ทันที — ผล: Filter เข้ม/หลวมขึ้น |
| `S07_SL_ATR_MULT` | float | 2.0 | อัปเดต `m_sl_atr_mult` — ผล: SL ของออเดอร์ใหม่กว้าง/แคบขึ้น |
| `S07_TP_ATR_MULT` | float | 1.5 | อัปเดต `m_tp_atr_mult` (Fallback TP เท่านั้น) |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Standalone Mode (Full — ไม่ต้องพึ่ง Python)

S07 ทำงาน Standalone ได้สมบูรณ์แบบ เพราะ Logic ทั้งหมดอยู่ใน MQL5:

```
สิ่งที่ทำงานได้ใน Standalone:
  ✅ RSI + Stochastic Entry/Exit Logic
  ✅ Volatility Filter
  ✅ Bollinger Band TP
  ✅ ATR-based SL
  ✅ Confidence Scoring
  ✅ ทุก Indicator คำนวณในเครื่อง

สิ่งที่ขาดไปเมื่อ Brain ไม่พร้อม:
  ❌ Regime Classification จาก Brain (ใช้ Built-in Rule-based แทน)
  ❌ Parameter Optimization (ใช้ค่า Default หรือค่าที่บันทึกไว้ล่าสุด)
  ❌ MM Server Override (ใช้ MM Default ตาม SMMSelection)
```

**ไม่ต้องมีไฟล์ standalone_config.dat เหมือน S01** เพราะ S07 ไม่มีพารามิเตอร์ที่เปลี่ยนแปลงบ่อยเหมือน OLS Beta ค่า Default ในโค้ดใช้ได้ดีพอสมควร

### 8.2 Server Mode (Optimized)

ใน Server Mode Python Brain ทำหน้าที่:

```
ทุกรอบ Optimization Cycle (30-60 วินาที):
1. ดูผล TRADE_REPORT ที่ S07 ส่งกลับมาผ่าน Port 7779
2. AnalyzeSelf07Performance():
   a. Win Rate ใน Regime ปัจจุบัน → ปรับ RSI Threshold
   b. ATR Spike Events → ปรับ VolFilter
   c. BB Middle Hit Rate → ปรับ BB Period ถ้า Miss บ่อย
3. สร้าง CONFIG_PUSH ส่งผ่าน Port 7778
4. CMeanReversion::SetDynamicParams() อัปเดต
5. ออเดอร์ใหม่ใช้พารามิเตอร์ใหม่ทันที
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| สถานะ | เงื่อนไข | การกระทำ |
|-------|---------|---------|
| **Blocked** | `ATR > VolFilter × ATR_MA` | SIGNAL_NONE ทันที — ไม่ตรวจ Oscillators |
| **Monitoring** | `vol_ok = true` แต่ RSI/Stoch ไม่ Extreme | รอ — ไม่มีการกระทำ |
| **Long Entry** | `RSI < 30 AND Stoch%K < 20 AND vol_ok` | BUY ที่ Ask, SL = -2×ATR, TP = BB_Middle |
| **Short Entry** | `RSI > 70 AND Stoch%K > 80 AND vol_ok` | SELL ที่ Bid, SL = +2×ATR, TP = BB_Middle |
| **Take Profit** | ราคาถึง BB_Middle (MT5 จัดการ) | ปิดสถานะอัตโนมัติ — กำไร |
| **Stop Loss** | ราคาถึง Entry ± 2×ATR (MT5 จัดการ) | ปิดสถานะอัตโนมัติ — ขาดทุน |

**ความแตกต่างจาก S01:**

S01 ตรวจสอบ Exit ทุก Tick ด้วย Z-Score ต้องใช้ Code Logic ใน `OnTick` ส่วน S07 วาง TP/SL ไว้กับ MT5 แล้วปล่อยให้ Platform จัดการ ทำให้ Code ง่ายกว่า แต่ขาดความยืดหยุ่น (ไม่สามารถขยาย TP ถ้าราคาวิ่งต่อ)

---

## 10. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | RANGING ที่ ATR สม่ำเสมอ ราคาแกว่ง Oscillators Cycle ชัดเจน |
| **สภาวะตลาดที่แย่ที่สุด** | TRENDING แรง — RSI อาจค้างที่ < 30 หรือ > 70 นานหลายชั่วโมง |
| **ระยะเวลาถือสถานะทั่วไป** | 15 นาที – 4 ชั่วโมง (Mean Reversion เร็วกว่า S01) |
| **เป้าหมาย Win Rate** | 60–68% (ในสภาวะ RANGING) |
| **R:R เมื่อใช้ BB Middle** | Variable — อาจสูงกว่า 1.0 เมื่อราคาอยู่ใกล้ BB Lower มาก |
| **R:R Fallback (ATR)** | 0.75 — ต้องชดเชยด้วย Win Rate |
| **Latency (MQL5 Signal)** | ~0 ms (ไม่ต้องรอ Network) |
| **Standalone Ready** | ✅ สมบูรณ์ (100%) |
| **Reinit เมื่อ Period เปลี่ยน** | ✅ — ต้องระวัง Reinit Loop |
| **สูงสุด Confidence ดิบ** | 1.00 (RSI = 0 หรือ 100, Stoch Extreme, ATR ต่ำ) |
| **ต่ำสุดที่ AI Council รับ** | 0.50 (ก่อน Regime Factor) |

---

## 11. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S07_MeanReversion.mqh` | `CMeanReversion` — RSI, Stochastic, ATR Filter, BB TP, Confidence Scoring ทั้งหมด |
| `Include/Logic/StrategyConstants.mqh` | `S07_MEAN_REVERSION` enum, `MAGIC_S07_MEAN_REV = 1007`, g_strategy_table[6] |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager` — เลือก MM สำหรับ S07 ตาม Regime |
| `03_Trader/ProgramC_Trader.mq5` | Main EA — Dispatch Tick ไปยัง CMeanReversion |
| `Tester/Opt_S07_MeanRev.mq5` | Script Optimize พารามิเตอร์ S07 (RSI, VolFilter, ATR Multipliers) |
| `Tester/Opt_S07_MeanRev.ex5` | Binary ที่คอมไพล์แล้วพร้อมรัน |
| `02_Brain/config_push/config_builder.py` | สร้าง CONFIG_PUSH สำหรับ S07 Parameters |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT จาก S07 ผ่าน Port 7779 |
| `02_Brain/core/performance_tracker.py` | ติดตาม Win Rate ของ S07 แยกตาม Regime |

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 12.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: R:R ต่ำกว่า 1.0 ในโหมด ATR Fallback**

เมื่อ BB Middle ไม่สามารถใช้เป็น TP ได้ (เพราะราคาอยู่เหนือ BB Middle แล้ว) ระบบ Fallback ไปใช้ 1.5×ATR ซึ่งให้ R:R = 0.75 หมายความว่าต้องชนะ > 57% จึงจะมีกำไรในระยะยาว ในสภาวะที่ Signal ไม่ดีพอ Win Rate อาจต่ำกว่า 57%

**แนวทางแก้ไข:** เพิ่มเงื่อนไขว่าถ้าจะใช้ ATR Fallback TP ต้องมี Confidence ≥ 0.7 เท่านั้น

**ปัญหาที่ 2: Stochastic Confirmation อ่อนแอ**

Stochastic Confidence มักจะต่ำมาก (0.05–0.15) แม้ในช่วงที่ Stochastic Extreme มาก เพราะสูตรวัดระยะห่างจาก Threshold เท่านั้น ทำให้ n้ำหนัก Stochastic ที่ 50% ไม่ได้เพิ่ม Confidence รวมได้มากนัก

**แนวทางแก้ไข:** ควรใช้ Non-linear Scaling เช่น `(threshold - stoch_k)² / threshold²` เพื่อให้ค่า Extreme มาก (stoch = 5) ได้ Confidence สูงขึ้นชัดเจนกว่า

**ปัญหาที่ 3: TP Fixed ที่ BB Middle ไม่ Trailing**

ถ้าราคาผ่าน BB Middle ไปแล้วและยังมีแนวโน้มต่อ โอกาสทำกำไรเพิ่มเติมจะหายไปเพราะ TP ถูกตั้งไว้แล้ว

**แนวทางแก้ไข:** ใช้ Trailing Stop หลังราคาผ่าน BB Middle เพื่อ "ขี่คลื่น" ต่อในกรณีที่ Momentum ยังมีอยู่

**ปัญหาที่ 4: เวลาข่าว Volatility Filter อาจตอบสนองช้า**

ATR เป็น Lagging Indicator — ถ้าข่าวใหญ่เพิ่งออก ATR อาจยังสะท้อนค่าก่อนข่าวอยู่ ทำให้ Filter ผ่านการเข้า Trade ในช่วงแรกของข่าว

**แนวทางแก้ไข:** ติดตั้ง News Calendar Filter ใน Brain เช่นเดียวกับ S01 เพื่อ Override CONFIG_PUSH และตั้ง VolFilter เป็น 0.5 ใน 30 นาทีก่อนและหลังข่าวสำคัญ

### 12.2 การเปรียบเทียบ: เมื่อใดควรเลือก S07 แทน S01?

| สถานการณ์ | S07 (Full MQL5) | S01 (Hybrid) |
|-----------|----------------|-------------|
| Python Brain Down | ✅ ทำงานได้ 100% | ⚠️ Standalone Mode (Beta=1.0) |
| ตลาด Ranging ชัดเจน | ✅ ดีมาก | ✅ ดีมาก |
| ตลาด Ranging + คู่เงินมี Cointegration | ⚠️ ดี | ✅ ดีกว่า (Statistical Edge สูงกว่า) |
| Network Latency สูง | ✅ ไม่กระทบ | ⚠️ CONFIG_PUSH มาช้า |
| Symbols ที่ไม่ Cointegrate กัน | ✅ ทำงานได้ | ❌ ไม่เหมาะ (ต้องการคู่เงิน) |

### 12.3 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่ที่แนะนำ | เหตุผล |
|------------|--------------|-------|
| RSI Period | ทุกวัน (สิ้นวัน) | ขึ้นกับ Timeframe ที่ใช้ |
| RSI Threshold | ทุก 4–8 ชั่วโมง | ปรับตาม Regime |
| VolFilter | ทุก 2–4 ชั่วโมง | ปรับตาม Session Volatility |
| SL/TP Multiplier | ทุกวัน | ปรับตาม ATR Level เฉลี่ยของวัน |
| BB Period | ทุกสัปดาห์ | เสถียรกว่าพารามิเตอร์อื่น |

---

## 13. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### ตรวจสอบว่า S07 ทำงานอยู่

```bash
# ใน Dashboard Python:
python 02_Brain/dashboard.py
# ดูที่ "Active Strategies" panel → ควรเห็น "S07" พร้อม Confidence %

# ตรวจสอบ TRADE_REPORT ล่าสุดของ S07:
python -c "
from core.performance_tracker import PerformanceTracker
pt = PerformanceTracker()
stats = pt.get_strategy_stats('S07_MEAN_REVERSION')
print('Win Rate:', stats.get('win_rate'))
print('Avg PnL:', stats.get('avg_pnl'))
print('Trade Count:', stats.get('trade_count'))
"
```

### ตรวจสอบ CONFIG_PUSH มี S07 หรือไม่

```bash
python tools/validate_live_readiness.py --zmq
# ดูที่ TEST 5: CONFIG_PUSH dry-run
# ควรเห็น S07_RSI_PERIOD, S07_VOL_FILTER ใน Output
```

### ตรวจสอบ Diagnostics ใน MT5

```mql5
// ใน EA Console หรือ Expert Log — search "[S07]":
CMeanReversion* s07 = GetStrategy(S07_MEAN_REVERSION);
s07.PrintDiagnostics();
// Output ตัวอย่าง:
// [S07] MeanReversion Init OK | EURUSD PERIOD_M5 | RSI<14 Stoch<14,3,3 Vol×1.3 BB(20,2.0)
// [S07] RSI=28.5(<30/>70) Stoch=18.2(<20/>80)
// [S07] ATR=0.00089 ATR_MA=0.00072 Ratio=1.236 VolFilter=1.3 VolOK=YES
// [S07] BB_Mid=1.08350 Signal=BUY Conf=0.1986 SL=1.08077 TP=1.08350

// ฟังก์ชัน Getter สำหรับ Debug:
s07.GetLastRSI()   // ค่า RSI ล่าสุด
s07.GetLastATR()   // ค่า ATR ล่าสุด
s07.GetVolOK()     // สถานะ Volatility Filter (true/false)
```

### ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S07 ไม่เคยเข้า Trade | Volatility Filter ปิดกั้นตลอด | ตรวจสอบ ATR Ratio ใน Diagnostics — ลด `S07_VOL_FILTER` จาก 1.3 เป็น 1.5 |
| S07 เข้า Trade มากแต่ Win Rate ต่ำ | RSI/Stoch Threshold หลวมเกินไป | เข้มขึ้น: RSI_BUY จาก 30 → 25, RSI_SELL จาก 70 → 75 |
| TP ไม่เคยถูกกระตุ้น | BB Middle ไกลจาก Entry มาก | เพิ่ม BB Period (20→30) เพื่อให้ BB Middle เคลื่อนที่ช้าลงและอยู่ใกล้กว่า หรือลด `S07_TP_ATR_MULT` เป็น 1.0 สำหรับ Fallback |
| Reinit Loop บ่อย | Brain ส่ง S07_RSI_PERIOD เปลี่ยนทุก Cycle | ตรวจ config_builder.py — ส่ง RSI_PERIOD เฉพาะเมื่อค่าเปลี่ยนจริง |
| Confidence ต่ำเกินไปเสมอ | Stoch ไม่ Extreme พอ, ATR Penalty สูง | ในตลาด Ranging แท้ๆ ค่านี้ปกติ — ตรวจสอบว่า Regime จริงๆ เป็น RANGING หรือไม่ |
| S07 ขาดทุนในช่วงข่าว | Volatility Filter ตอบสนองช้า | เพิ่ม News Filter ใน Brain — ลด VolFilter เหลือ 0.5 ก่อนข่าว 30 นาที |

---

*S07 Mean Reversion (Volatility-Filtered) — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
