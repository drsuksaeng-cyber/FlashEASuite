# S06 — KAMA (Kaufman's Adaptive Moving Average)
## คู่มือเทคนิคเชิงลึก | Jimmi Deep-Dive Edition
### FlashEASuite V2 | Phase P9-5 | 2026-02-27

---

## 1. ภาพรวมกลยุทธ์ (Strategy Overview)

| รายการ | รายละเอียด |
|--------|-----------|
| ชื่อเต็ม | S06 — KAMA (Kaufman's Adaptive Moving Average) |
| Enum | `S06_KAMA` |
| Index | **5** (0-based, ตำแหน่งที่ 6 ใน `g_strategy_table[]`) |
| Magic Number | **1006** (`MAGIC_S06_KAMA`) |
| Category | `FULL_MQL5` (`CAT_FULL_MQL5`) |
| Standalone | **YES** — ทำงานได้อิสระโดยไม่ต้องรับ CONFIG_PUSH จาก Python Brain |
| Best Regime | **TRENDING** (`REGIME_TRENDING`) — ER สูง |
| Poor Regime | **RANGING** — ER ต่ำ → ไม่มีสัญญาณ (Regime factor = 0.5) |
| Class | `CKAMATrend` |
| Source File | `Include/Logic/Strategies/S06_KAMA.mqh` |
| ShouldExit() | **YES** — ออกจากตลาดอัตโนมัติเมื่อราคาตัดกลับผ่าน KAMA |
| TP/SL Format | **ATR Offset** — `GetTP()`/`GetSL()` คืนค่าระยะห่าง ไม่ใช่ระดับราคาสัมบูรณ์ |
| Family | Trend Following |
| Version | 6.00 |

### สรุปแนวคิดหลัก (Conceptual Summary)

S06_KAMA ประยุกต์ใช้ **Kaufman's Adaptive Moving Average (KAMA)** ซึ่งคิดค้นโดย Perry J. Kaufman หัวใจของกลยุทธ์คือการวัด **Efficiency Ratio (ER)** — อัตราส่วนระหว่าง "การเคลื่อนไหวสุทธิในทิศทางเดียว" กับ "การผันผวนรวมทั้งหมด" ในช่วงเวลาหนึ่ง

- **ER สูง** → ตลาดมีทิศทางชัดเจน (trending) → KAMA ตอบสนองเร็ว
- **ER ต่ำ** → ตลาดวนเวียน (choppy/ranging) → KAMA ตอบสนองช้าลงอย่างมาก

กลไกนี้ทำให้ S06 สามารถ **ปิดสัญญาณรบกวน** ในตลาดไม่มีทิศทาง ขณะเดียวกันก็ **จับ trend ได้ทันท่วงที** ในตลาดที่มีแรงขับเคลื่อน

**จุดเด่นที่ทำให้ S06 แตกต่างจากกลยุทธ์อื่นใน FlashEASuite V2:**

1. **Standalone Capable**: ไม่ต้องรับ CONFIG_PUSH จาก Python Brain — ทำงานได้ทันทีที่ EA เริ่มต้น
2. **Dynamic Exit (ShouldExit)**: ออกจากตลาดเมื่อราคาตัดกลับผ่าน KAMA — ไม่รอ Fixed TP เป็นหลัก
3. **ATR-Offset TP/SL**: `GetTP()`/`GetSL()` คืนค่าระยะห่างเป็น ATR multiplier ไม่ใช่ระดับราคา
4. **Regime-Adaptive ER Threshold**: `OnConfigUpdate()` ปรับ ER threshold ตาม Market Regime อัตโนมัติ
5. **Diagnostic Export**: Export `S06_KAMA_VALUE` และ `S06_ER_LAST` ให้ Brain ใช้ monitor real-time

---

## 2. พื้นฐานทฤษฎีและประวัติศาสตร์ (Core Theory & Historical Context)

### 2.1 ประวัติความเป็นมาของ KAMA

Perry J. Kaufman นักวิจัยตลาดและนักเขียนชาวอเมริกัน ตีพิมพ์ KAMA ครั้งแรกในหนังสือ *"Smarter Trading"* (1995) และพัฒนาเพิ่มเติมใน *"Trading Systems and Methods"* (1998) ซึ่งกลายเป็น textbook คลาสสิกด้าน quantitative trading

แนวคิดหลักที่ Kaufman ตั้งใจแก้ปัญหาคือ **Moving Average แบบดั้งเดิมไม่สามารถแยกแยะระหว่าง "signal" กับ "noise" ได้** การใช้ period ตายตัว (fixed period) หมายความว่า MA นั้นตอบสนองเร็วเท่ากันทุกสภาวะตลาด ซึ่งขัดกับความเป็นจริง

ปัญหาพื้นฐานของ Moving Average ทั่วไป:

- **SMA สั้น (5–10 period)**: ตอบสนองเร็ว แต่เกิด whipsaw บ่อยในตลาด choppy
- **SMA ยาว (50–200 period)**: กรอง noise ได้ดี แต่สัญญาณช้าเกินไปในตลาด trending
- **ไม่มี MA ตายตัว** ที่ดีที่สุดสำหรับทุกสภาวะตลาด

KAMA แก้ปัญหานี้โดยใช้ **Smoothing Constant (SC) ที่ปรับตัวแบบไดนามิก** — SC จะผันแปรระหว่าง FastSC (EMA 2-period) และ SlowSC (EMA 30-period) ตาม ER ที่วัดได้แบบ real-time

### 2.2 ทำไมต้อง KAMA? (The "Why")

สมมติใช้ EMA(20) บน EURUSD H1 แบบตายตัว:

- **วันที่มี High Impact News**: ราคาวิ่งทิศเดียว 80 pip ใน 3 ชั่วโมง → EMA(20) ช้าเกินไป สัญญาณมาช้า เสีย entry ที่ดี
- **วันที่ตลาด ranging**: ราคาแกว่ง 30 pip ไป-มา → EMA(20) เร็วเกินไป เกิด false signal ทุก 2–3 แท่ง

KAMA แก้ปัญหาด้วยการปรับ SC แบบ dynamic ตามสภาพตลาดจริง:

```
วันที่ trending สูง (ER = 0.85):
  SC = (0.85 × 0.6022 + 0.0645)² = (0.5564)² = 0.3096
  → KAMA ตอบสนองแบบ EMA ≈ 3-period (เร็วมาก)

วันที่ ranging (ER = 0.15):
  SC = (0.15 × 0.6022 + 0.0645)² = (0.1548)² = 0.0240
  → KAMA ตอบสนองแบบ EMA ≈ 82-period (ช้ามาก)
```

ความแตกต่างของ SC ระหว่างสองสถานการณ์นี้มากกว่า **12 เท่า** (0.3096 vs 0.0240) ซึ่งหมายความว่า KAMA ปรับพฤติกรรมอย่างรุนแรงตามสภาพตลาด

### 2.3 ทำไม Standalone แทนที่จะรอ Python Brain?

S06 ออกแบบเป็น Standalone เพราะ:

1. **KAMA เป็น self-contained algorithm**: ใช้แค่ price series ไม่ต้องการ external data หรือ ML model
2. **Regime adaptation ทำใน OnConfigUpdate()**: ถ้ามี Brain → ปรับ ER threshold ตาม Regime แต่ถ้าไม่มี Brain → ใช้ค่า default ได้
3. **Low latency requirement**: Trend-following ต้องการ low latency การรอ Brain อาจพลาด entry ที่ดีในช่วงแรกของ trend
4. **High reliability**: ถ้า Brain offline S06 ยังทำงานต่อเนื่องได้ ไม่มี downtime

---

## 3. กลไกคณิตศาสตร์ (Mathematical Framework)

### 3.1 Efficiency Ratio (ER) — วัดทิศทางของตลาด

```
ER = |Price[0] - Price[n]| / SUM(|Price[i] - Price[i-1]| for i=1..n)

โดยที่:
  Price[0] = ราคาปิดปัจจุบัน (bar ล่าสุด — newest)
  Price[n] = ราคาปิดเมื่อ n bars ที่แล้ว (oldest ใน window)
  n        = kama_period (default = 10)
  ตัวเศษ   = Net Directional Change (ขนาดการเคลื่อนไหวสุทธิ)
  ตัวส่วน  = Total Path Volatility (ผลรวมระยะทางสัมบูรณ์ทุก bar)
  ER ∈ [0, 1] — ถูก cap ที่ 1.0 ด้วย MathMin(net/volatility, 1.0)
```

กรณีพิเศษ: ถ้า volatility < 1e-10 → return 0.0 (ป้องกัน division by zero)

**การตีความ ER:**

| ช่วง ER | ความหมาย | พฤติกรรม KAMA |
|---------|-----------|---------------|
| 0.80 – 1.00 | Strong Trend | KAMA เร็วมาก (≈ EMA 2–3 period) |
| 0.50 – 0.79 | Moderate Trend | KAMA ปานกลาง (≈ EMA 5–10 period) |
| 0.30 – 0.49 | Weak Trend | KAMA ช้า (≈ EMA 15–25 period) |
| 0.00 – 0.29 | Choppy/Ranging | KAMA ช้ามาก (≈ EMA 50–82 period) |

### 3.2 Smoothing Constant (SC) — ตัวปรับความเร็ว KAMA

```
FastSC = 2 / (fast + 1) = 2 / (2+1) = 0.6667  (เทียบเท่า EMA 2-period)
SlowSC = 2 / (slow + 1) = 2 / (30+1) = 0.0645  (เทียบเท่า EMA 30-period)

SC_raw = ER × (FastSC - SlowSC) + SlowSC
       = ER × (0.6667 - 0.0645) + 0.0645
       = ER × 0.6022 + 0.0645

SC = SC_raw²   ← squared: non-linear penalization
```

- `fast = 2` (hardcoded ตามมาตรฐาน Kaufman)
- `slow = 30` (hardcoded ตามมาตรฐาน Kaufman)

**เหตุผลที่ต้อง Square SC:**

Kaufman ค้นพบว่าการยกกำลัง 2 สร้าง "non-linear penalization" ที่ทรงพลัง ค่า SC ต่ำถูกลงโทษมากกว่าสัดส่วน ทำให้ KAMA ช้าลงอย่างรวดเร็วเมื่อ ER ต่ำ:

| ER | SC_raw | SC = SC_raw² | ผลที่ได้ |
|----|--------|-------------|---------|
| 1.00 | 0.6667 | **0.4445** | เร็วสูงสุด |
| 0.75 | 0.5162 | **0.2665** | เร็วปานกลาง |
| 0.50 | 0.3656 | **0.1337** | ปานกลาง |
| 0.25 | 0.2151 | **0.0463** | ช้า |
| 0.10 | 0.1247 | **0.0155** | ช้ามาก |
| 0.00 | 0.0645 | **0.0042** | ช้าที่สุด (≈ flat line) |

**สังเกต**: เมื่อ ER ลดจาก 0.50 → 0.25 (ลดครึ่งเดียว) SC ลดจาก 0.1337 → 0.0463 (ลดมากกว่า **65%**) นี่คือ non-linear effect ที่ทำให้ KAMA "ติดอยู่กับที่" อย่างรวดเร็วเมื่อ trend อ่อนแรง

### 3.3 KAMA Update Formula

```
KAMA[t] = KAMA[t-1] + SC × (Price[t] - KAMA[t-1])

เมื่อ SC → 1 : KAMA[t] ≈ Price[t]      (ตามราคาทันที — ไม่มี smoothing)
เมื่อ SC → 0 : KAMA[t] ≈ KAMA[t-1]    (ไม่เปลี่ยนแปลง — flat line สมบูรณ์)
```

**การ Initialization ใน Init():**

```mql5
// Pre-load historical closes into circular buffer
for(int i = kama_period; i >= 0; i--) {
    m_price_buf[m_buf_idx] = iClose(_Symbol, _Period, i);
    m_buf_idx = (m_buf_idx + 1) % (kama_period + 1);
}
m_kama = m_price_buf[0]; // เริ่ม KAMA ที่ราคา oldest bar
```

Buffer ขนาด `kama_period + 1` ถูก pre-load ด้วย historical close KAMA เริ่มต้นที่ราคา oldest bar แล้ว converge เข้าสู่ค่าที่ถูกต้องใน ~10–20 bars แรก

---

## 4. กรณีศึกษา: การคำนวณ KAMA แบบทีละขั้นตอน

### Case Study: EURUSD H1 — London Session (2025-01-15 09:00 UTC)

**สมมติฐาน:**

- Symbol: EURUSD, Timeframe: H1
- `kama_period = 10`, `fast = 2`, `slow = 30`
- `er_threshold = 0.30` (default, Regime = NEUTRAL)
- ATR (14-period) = **0.0020** (20 pips)
- Previous KAMA = **1.08152**

**ข้อมูลราคาปิด (เก่า → ใหม่):**

| ลำดับ | Bar | Price (Close) |
|-------|-----|--------------|
| 9 (oldest) | -10 | 1.0800 |
| 8 | -9 | 1.0810 |
| 7 | -8 | 1.0815 |
| 6 | -7 | 1.0822 |
| 5 | -6 | 1.0818 |
| 4 | -5 | 1.0825 |
| 3 | -4 | 1.0832 |
| 2 | -3 | 1.0838 |
| 1 | -2 | 1.0836 |
| 0 (newest) | -1 | **1.0845** |

---

**ขั้นตอน 1: คำนวณ ER**

Net Change = |1.0845 − 1.0800| = **0.0045** (45 pips)

| คู่ Bars | |ΔPrice| |
|---------|---------|
| -10 → -9 | 0.0010 |
| -9 → -8 | 0.0005 |
| -8 → -7 | 0.0007 |
| -7 → -6 | 0.0004 |
| -6 → -5 | 0.0007 |
| -5 → -4 | 0.0007 |
| -4 → -3 | 0.0006 |
| -3 → -2 | 0.0002 |
| -2 → -1 | 0.0009 |
| **รวม Volatility** | **0.0057** |

```
ER = 0.0045 / 0.0057 = 0.7895 ≈ 0.79
```

**ตีความ**: ER = 0.79 อยู่ในช่วง "Moderate-to-Strong Trend" — ราคาวิ่งขึ้น 45 pip ด้วย total volatility 57 pip (มีการ pullback เล็กน้อยที่ bar -6 และ -3)

---

**ขั้นตอน 2: คำนวณ Smoothing Constant (SC)**

```
SC_raw = 0.7895 × (0.6667 - 0.0645) + 0.0645
       = 0.7895 × 0.6022 + 0.0645
       = 0.4754 + 0.0645
       = 0.5399

SC = 0.5399² = 0.2915
```

---

**ขั้นตอน 3: อัปเดต KAMA**

```
KAMA[t] = 1.08152 + 0.2915 × (1.0845 - 1.08152)
         = 1.08152 + 0.2915 × 0.00298
         = 1.08152 + 0.000869
         = 1.08239

slope = KAMA[t] - KAMA[t-1] = 1.08239 - 1.08152 = +0.00087 > 0 ✓
```

---

**ขั้นตอน 4: คำนวณ Confidence**

```
dist    = |1.0845 - 1.08239| = 0.00211
dist/ATR = 0.00211 / 0.0020 = 1.055

Confidence = min(0.7895 × 1.055, 1.0)
           = min(0.833, 1.0)
           = 0.833
```

---

**ขั้นตอน 5: ตรวจเงื่อนไขเข้าตลาด**

| เงื่อนไข | ค่า | ผล |
|---------|-----|-----|
| Price > KAMA | 1.0845 > 1.08239 | ✓ |
| Slope > 0 | +0.00087 > 0 | ✓ |
| ER ≥ ER_threshold | 0.7895 ≥ 0.30 | ✓ |
| Confidence ≥ min_conf | 0.833 ≥ 0.60 | ✓ |
| **ผลรวม** | | **→ LONG ENTRY** |

---

**ขั้นตอน 6: คำนวณ TP/SL จาก ATR Offset**

สมมติ `tp_atr = 3.0`, `sl_atr = 1.0` (ค่า default จากไฟล์), ATR = 0.0020:

```
TP Distance = 3.0 × 0.0020 = 0.0060 (60 pips)  ← ค่าที่ GetTP() คืน
SL Distance = 1.0 × 0.0020 = 0.0020 (20 pips)  ← ค่าที่ GetSL() คืน

Entry   = 1.0845
TP Level = 1.0845 + 0.0060 = 1.0905
SL Level = 1.0845 - 0.0020 = 1.0825
R:R = 60:20 = 3.0:1
```

> **หมายเหตุสำคัญ**: `GetTP()`/`GetSL()` ของ S06 คืนค่า **ระยะห่าง** (0.0060, 0.0020) ไม่ใช่ระดับราคา (1.0905, 1.0825) EA ต้องนำค่าไปบวก/ลบกับ entry price เอง ซึ่งแตกต่างจาก S03/S04/S05 ที่คืนค่าเป็นราคาสัมบูรณ์

---

**กรณีเปรียบเทียบ: ตลาด Choppy (ER ต่ำ)**

สมมติ ER = 0.18 (ตลาด ranging):

```
SC_raw = 0.18 × 0.6022 + 0.0645 = 0.1729
SC     = 0.1729² = 0.0299  ← KAMA แทบไม่ขยับ (SC เพียง 3%)

ER = 0.18 < threshold 0.30 → GetSignal() = SIGNAL_NONE (filter ทำงาน)
```

แม้ Confidence จะสูงก็ตาม ระบบ filter ER จะทำงานก่อนเสมอ

---

## 5. ระบบคะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตรจาก Source Code

```mql5
double _CalcConfidence() {
    double dist = MathAbs(m_last_price - m_kama);
    double conf = MathMin(m_last_er * (dist / m_atr), 1.0);
    return conf;
}
```

```
Confidence = min( ER × (|Price - KAMA| / ATR) , 1.0 )
```

สูตรประกอบด้วยสองปัจจัยคูณกัน:

1. **ER** — วัดความแข็งแกร่งของ trend (0.0–1.0)
2. **dist/ATR** — วัดว่าราคาอยู่ห่างจาก KAMA มากแค่ไหดเทียบกับ volatility ปัจจุบัน

**ตรรกะของการคูณ**: Confidence สูงก็ต่อเมื่อ "trend แข็งแกร่ง AND ราคาอยู่ห่างจาก KAMA พอสมควร" สองปัจจัยต้องสนับสนุนกัน:

- ER สูง แต่ราคาแตะ KAMA พอดี (dist ≈ 0) → Confidence ≈ 0
- ER ต่ำ แต่ราคาห่าง KAMA มาก → Confidence ต่ำ (อาจเป็น noise)
- ER สูง AND dist/ATR สูง → Confidence สูง ✓

### 5.2 ตารางสรุป Confidence ตามสถานการณ์

| สถานการณ์ | ER | dist/ATR | Confidence | การตัดสิน |
|-----------|-----|----------|------------|-----------|
| Strong trend, ราคาห่าง KAMA มาก | 0.85 | 1.20 | min(1.02, 1.0) = **1.00** | ENTRY ✓ |
| Moderate trend, ราคาห่าง KAMA พอดี | 0.65 | 1.10 | **0.715** | ENTRY ✓ |
| Moderate trend, ราคาแตะ KAMA | 0.65 | 0.80 | **0.520** | No Entry (< 0.60) |
| Weak trend, ราคาห่าง KAMA มาก | 0.35 | 1.50 | **0.525** | No Entry |
| Choppy (ER < threshold) | 0.22 | 2.00 | 0.440 | **No Entry** (ER filter ก่อน) |

---

## 6. ตรรกะการเข้าและออกจากตลาด (Entry & Exit Logic)

### 6.1 เงื่อนไขการเข้าตลาด (GetSignal)

```mql5
// Long Signal
if(m_last_price > m_kama && m_slope > 0.0 && m_last_er >= m_er_threshold)
    return SIGNAL_LONG;

// Short Signal
if(m_last_price < m_kama && m_slope < 0.0 && m_last_er >= m_er_threshold)
    return SIGNAL_SHORT;

return SIGNAL_NONE;
```

เงื่อนไข LONG ทั้ง 3 ต้องครบพร้อมกัน:

1. **Price > KAMA** — ราคาอยู่เหนือ KAMA (uptrend structure)
2. **Slope > 0** — KAMA กำลังชี้ขึ้น (`slope = KAMA[t] - KAMA[t-1]`)
3. **ER ≥ ER_threshold** — ความแข็งแกร่งของ trend ผ่านเกณฑ์

เงื่อนไข SHORT: Mirror image (Price < KAMA, Slope < 0, ER ≥ threshold)

### 6.2 Dynamic Exit — ShouldExit() ★ (จุดเด่นเฉพาะของ S06)

```mql5
bool ShouldExit(ENUM_POSITION_TYPE posType, double currentPrice) {
    if(posType == POSITION_TYPE_BUY)
        return (currentPrice < m_kama);   // ราคาหล่นต่ำกว่า KAMA → EXIT
    if(posType == POSITION_TYPE_SELL)
        return (currentPrice > m_kama);   // ราคาพุ่งสูงกว่า KAMA → EXIT
    return false;
}
```

**ทำไม S06 ถึงต้องมี ShouldExit()?**

S06 ใช้ KAMA เป็น **dynamic trailing indicator** ในตัวเอง:

- **ใน strong trend**: KAMA วิ่งตามราคา (SC สูง) → ShouldExit = false ตลอด → Trade วิ่งต่อเนื่อง
- **เมื่อ trend อ่อนแรง**: ราคา pullback ผ่าน KAMA → `ShouldExit = true` → ออกทันที

ข้อดีของ approach นี้:

- **ให้ trade วิ่งต่อเนื่อง** ใน strong trend (ไม่ถูกตัดก่อนเวลาด้วย fixed TP)
- **ออกเร็ว** เมื่อ trend เปลี่ยนทิศ (ป้องกันการขาดทุนสะสม)
- **ATR-based TP** ทำหน้าที่เป็น safety ceiling ถ้า KAMA ยังไม่หล่น แต่ราคาถึง TP แล้วก็ออก

**เปรียบเทียบกลยุทธ์ที่มี/ไม่มี ShouldExit():**

| Feature | S03/S04/S05 | S06 |
|---------|-------------|-----|
| ShouldExit() | ไม่มี | มี (ตัดเมื่อราคาตัด KAMA) |
| Primary Exit | Fixed TP (absolute price) | KAMA crossback (dynamic) |
| Secondary Exit | Fixed SL (absolute price) | Fixed SL (ATR offset) |
| TP/SL Return Type | ระดับราคา (absolute) | ระยะห่าง ATR (offset) |
| Trade Duration | กำหนดชัดเจนจาก TP/SL | แปรผันตาม trend strength |

### 6.3 Regime-Adaptive ER Threshold — OnConfigUpdate()

```mql5
void OnConfigUpdate(const SDynamicParams &params) {
    ENUM_MARKET_REGIME regime = (ENUM_MARKET_REGIME)params.regime;
    if(regime == REGIME_TRENDING)
        m_er_threshold = 0.25;  // ผ่อนมาตรฐาน — รับ trend อ่อนๆ ได้
    else if(regime == REGIME_RANGING)
        m_er_threshold = 0.45;  // เข้มงวดกว่า — กรอง ranging noise
    else
        m_er_threshold = 0.30;  // default neutral
    // อัปเดต params อื่นๆ จาก CONFIG_PUSH...
}
```

**ตรรกะของ Regime Adaptation:**

| Regime จาก Brain | ER Threshold | เหตุผล |
|-----------------|-------------|--------|
| TRENDING | 0.25 | Brain ยืนยัน trend → ผ่อนมาตรฐาน รับสัญญาณ trend อ่อนๆ ได้มากขึ้น |
| RANGING | 0.45 | Brain ยืนยัน ranging → ตั้ง bar สูง กรอง false signal ออก |
| VOLATILE/UNKNOWN | 0.30 | ใช้ค่ากลาง — neutral stance |

---

## 7. สถาปัตยกรรมและ IStrategy Interface

### 7.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  S06 ARCHITECTURE                                               │
├──────────────────────────┬──────────────────────────────────────┤
│  IStrategy Interface     │  CKAMATrend (S06_KAMA.mqh)           │
│                          │  • Init() — pre-load price buffer     │
│                          │  • Analyze() — per bar KAMA update    │
│                          │  • GetSignal() / GetConfidence()      │
│                          │  • GetTP() / GetSL() → ATR offsets    │
│                          │  • ShouldExit() — KAMA crossback      │
│                          │  • OnConfigUpdate() — Regime adapt    │
│                          │  • GetCurrentParams() — export diag   │
├──────────────────────────┼──────────────────────────────────────┤
│  Internal State          │  m_price_buf[] — circular buffer      │
│                          │  (size = kama_period + 1)             │
│                          │  m_kama, m_slope, m_last_er           │
│                          │  m_atr  ← iATR(period=14)             │
├──────────────────────────┼──────────────────────────────────────┤
│  Python Brain            │  CONFIG_PUSH via ZMQ Port 7778        │
│  (Server-Assisted Mode)  │  → S06_KAMA_PERIOD, S06_ER_THRESH     │
│                          │  → S06_TP_ATR, S06_SL_ATR             │
│                          │  Feedback via ZMQ Port 7779           │
│                          │  ← S06_KAMA_VALUE, S06_ER_LAST        │
└──────────────────────────┴──────────────────────────────────────┘
```

### 7.2 Method Execution Flow

```
OnTick() [ProgramC_Trader.mq5]
    │
    ├── [ถ้า new bar]
    │       └── strategy.Analyze()
    │               ├── iClose(1) → อัปเดต m_price_buf[m_buf_idx]
    │               ├── m_buf_idx = (m_buf_idx+1) % size
    │               ├── iATR(14) → อัปเดต m_atr
    │               ├── _CalcER()     → อัปเดต m_last_er
    │               └── _UpdateKAMA() → อัปเดต m_kama, m_slope
    │
    ├── [ตรวจสอบสัญญาณ]
    │       ├── strategy.GetSignal()     → SIGNAL_LONG/SHORT/NONE
    │       └── strategy.GetConfidence() → [0.0, 1.0]
    │
    ├── [มี open position — ทุก tick]
    │       └── strategy.ShouldExit(type, price) → bool
    │
    └── [รับ CONFIG_PUSH]
            └── strategy.OnConfigUpdate(params) → ปรับ er_threshold
```

### 7.3 Standalone vs Server-Assisted Mode

**Standalone Mode** (ไม่มี CONFIG_PUSH):

```
m_config.confidence = 0.0 (default)
→ ไม่มี ServerOnly Guard ใน S06   ← แตกต่างจาก S03/S04/S05
→ Analyze() ทำงานได้ทันทีโดยไม่ต้องรอ Brain
→ er_threshold = 0.30 (hardcoded default)
→ tp_atr = 3.0, sl_atr = 1.0 (default จาก MQL5 input)
```

**Server-Assisted Mode** (มี CONFIG_PUSH):

```
OnConfigUpdate() ถูกเรียกเมื่อ Brain ส่ง message
→ er_threshold ปรับตาม Regime (0.25 / 0.30 / 0.45)
→ kama_period, tp_atr, sl_atr อัปเดตได้แบบ hot-reload (ไม่ restart)
→ S06 export S06_KAMA_VALUE, S06_ER_LAST กลับให้ Brain monitoring
```

**ServerOnly Guard Pattern (เปรียบเทียบ):**

```mql5
// S03/S04/S05 — ServerOnly (ต้องรอ CONFIG_PUSH):
void Analyze() {
    if(m_config.confidence < 0.01) return; // BLOCKED ถ้าไม่มี Brain
    // ...
}

// S06 — Standalone (ไม่มี guard):
void Analyze() {
    // ทำงานเสมอ — ไม่มี guard
    _CalcER();
    _UpdateKAMA();
}
```

---

## 8. ตารางพารามิเตอร์ (Parameters Reference)

### 8.1 MQL5 Input Defaults

| Parameter | Default | คำอธิบาย |
|-----------|---------|---------|
| `KAMA_Period` | 10 | KAMA lookback window (n bars สำหรับ ER) |
| `KAMA_Fast` | 2 | Fast EMA period สำหรับคำนวณ FastSC |
| `KAMA_Slow` | 30 | Slow EMA period สำหรับคำนวณ SlowSC |
| `KAMA_ER_Thresh` | 0.30 | ER ต่ำสุดก่อน entry |
| `KAMA_TP_ATR` | 3.0 | TP = 3× ATR จาก entry |
| `KAMA_SL_ATR` | 1.0 | SL = 1× ATR จาก entry |
| `KAMA_ATR_Period` | 14 | ATR calculation period |

### 8.2 CONFIG_PUSH Keys (Server-Assisted Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `S06_KAMA_PERIOD` | int | 10 | `m_kama_period` |
| `S06_ER_THRESH` | float | 0.30 | `m_er_threshold` |
| `S06_TP_ATR` | float | 3.0 | `m_tp_atr_mult` |
| `S06_SL_ATR` | float | 1.0 | `m_sl_atr_mult` |

### 8.3 Diagnostic Export ผ่าน GetCurrentParams()

| Key | คำอธิบาย | ประโยชน์ |
|-----|---------|---------|
| `S06_KAMA_VALUE` | ค่า KAMA ปัจจุบัน | Brain monitor trend line real-time |
| `S06_ER_LAST` | ค่า ER ล่าสุด | Brain ใช้ตรวจ trend strength โดยไม่ต้องคำนวณเอง |

**S06 เป็นกลยุทธ์เดียวในชุดที่ export internal indicator values** การที่ Brain รู้ค่า ER ช่วยให้ Policy engine ตัดสินใจ Regime classification ได้ดีขึ้น

### 8.4 Hardcoded Internal Constants

| ค่าคงที่ | ค่า | เหตุผลที่ hardcode |
|---------|-----|------------------|
| `fast` (FastSC period) | 2 | ค่ามาตรฐาน Kaufman |
| `slow` (SlowSC period) | 30 | ค่ามาตรฐาน Kaufman |
| `atr_period` | 14 | มาตรฐาน Wilder's ATR |
| `min_conf` | 0.60 | Confidence ขั้นต่ำก่อน entry |

---

## 9. Dataflow และ Lifecycle

### 9.1 Dataflow ใน Standalone Mode

```
[Market Tick]
    │
    ▼ (ทุก new bar)
[iClose(1) / iATR(14)]
    │
    ▼
[m_price_buf[] Circular Buffer]
    │  ขนาด = kama_period + 1
    │  newest = m_price_buf[(m_buf_idx-1+size)%size]
    │  oldest = m_price_buf[m_buf_idx]
    ▼
[_CalcER()]
    │  ER = |newest - oldest| / SUM(|successive diffs|)
    ▼
[_UpdateKAMA()]
    │  SC_raw = ER×0.6022 + 0.0645
    │  SC = SC_raw²
    │  KAMA = KAMA_prev + SC×(Price - KAMA_prev)
    │  slope = KAMA - KAMA_prev
    ▼
[GetSignal()]
    │  Long: Price>KAMA AND slope>0 AND ER≥threshold
    ▼
[GetConfidence()]
    │  conf = min(ER × dist/ATR, 1.0)
    ▼
[EA เปิด Order]
    │  TP = Entry + GetTP()×ATR
    │  SL = Entry - GetSL()×ATR
    │
    ▼ (ทุก tick ขณะมี position)
[ShouldExit()]
    │  LONG: price < KAMA → true → EA ปิด position
    └── SHORT: price > KAMA → true → EA ปิด position
```

### 9.2 Circular Buffer — การจัดการหน่วยความจำ

```mql5
// อัปเดต buffer ทุก bar ใน Analyze()
m_price_buf[m_buf_idx] = close_price;
m_buf_idx = (m_buf_idx + 1) % (m_period + 1);

// อ่านค่าสำหรับ ER calculation
int newest_idx = (m_buf_idx - 1 + size) % size;  // Price[0] = newest
int oldest_idx = m_buf_idx;                         // Price[n] = oldest
```

Circular buffer ขนาด `kama_period+1` ประหยัดหน่วยความจำ ไม่ต้อง shift array ทุก bar ราคา oldest ถูก overwrite อัตโนมัติเมื่อ buffer หมุนครบรอบ

### 9.3 Integration กับ Python Brain

```
[Python Brain — analysis.py]
    │  วิเคราะห์ Market Regime
    │  ใช้ S06_ER_LAST ที่รับมาเพื่อ cross-validate regime
    ▼
[policy.py — CONFIG_PUSH Type=10]
    │  Array: [10, ts, symbol, strategy, entry, lot,
    │          max_orders, tp, sl, confidence, risk_mult]
    │  ส่งผ่าน ZMQ Port 7778 (MessagePack)
    ▼
[ProgramC_Trader.mq5]
    │  Decode SDynamicParams
    │  เรียก strategy.OnConfigUpdate(params)
    ▼
[CKAMATrend.OnConfigUpdate()]
    │  อ่าน params.regime → ปรับ er_threshold
    │  อัปเดต kama_period, tp_atr, sl_atr
    ▼
[GetCurrentParams() → Feedback]
    └── S06_KAMA_VALUE, S06_ER_LAST → ZMQ Port 7779
```

---

## 10. คู่มือปฏิบัติการทีละขั้นตอน (Step-by-Step Operational Manual)

### ขั้นที่ 1: EA Initialization

```
1. ProgramC_Trader.mq5 → OnInit()
2. สร้าง CKAMATrend instance พร้อม strategy config
3. เรียก strategy.Init(symbol, timeframe, params)
4. Init() วนลูป iClose(i) สำหรับ i = kama_period → 0
5. เก็บใน m_price_buf[] ทั้งหมด kama_period+1 ค่า
6. ตั้ง m_kama = ราคา oldest bar
7. กลยุทธ์พร้อมทำงานทันที (ไม่รอ Brain)
```

### ขั้นที่ 2: Bar ใหม่เปิด (New Bar Processing)

```
1. EA ตรวจพบ IsNewBar() = true
2. เรียก strategy.Analyze()
3. อ่าน Close[1] (bar ล่าสุดที่ปิดแล้ว)
4. อัปเดต m_price_buf[m_buf_idx] = Close[1]
5. m_buf_idx = (m_buf_idx + 1) % size  (advance circular index)
6. คำนวณ ER จาก buffer (newest vs oldest, sum diffs)
7. คำนวณ SC_raw, SC, อัปเดต m_kama
8. อัปเดต m_slope = m_kama - m_kama_prev
9. อัปเดต m_atr = iATR(14)
```

### ขั้นที่ 3: ตรวจสอบสัญญาณและเปิด Order

```
1. EA เรียก GetSignal()
2. ตรวจ 3 เงื่อนไข: Price>KAMA AND slope>0 AND ER≥threshold
3. ถ้า SIGNAL_LONG → เรียก GetConfidence()
4. ตรวจ Confidence ≥ 0.60
5. ถ้าผ่าน → คำนวณ lot size ด้วย Money Manager
6. EA เรียก GetTP() → offset เช่น 0.0060 (3×ATR)
7. EA เรียก GetSL() → offset เช่น 0.0020 (1×ATR)
8. TP = Entry + offset_tp, SL = Entry - offset_sl
9. เรียก OrderSend() magic=1006
```

### ขั้นที่ 4: ติดตาม Position (Dynamic Exit ทุก Tick)

```
ทุก tick ขณะมี LONG position:
1. EA เรียก strategy.ShouldExit(POSITION_TYPE_BUY, currentBid)
2. ShouldExit() ตรวจ: currentBid < m_kama?
   → ใช่: return true → EA ปิด position ด้วย market close
   → ไม่ใช่: return false → ถือต่อ รอ TP หรือ SL

หมายเหตุ: Fixed TP/SL ที่ set ใน Order ยังทำงานตามปกติ
ShouldExit() เป็น "dynamic primary exit" เมื่อ KAMA ถูก crossback ก่อน TP
```

### ขั้นที่ 5: รับ CONFIG_PUSH (Server-Assisted Mode)

```
1. EA รับ message จาก ZMQ Port 7778
2. Decode MessagePack → สร้าง SDynamicParams
3. เรียก strategy.OnConfigUpdate(params)
4. S06 อ่าน params.regime → ปรับ m_er_threshold
5. อัปเดต kama_period, tp_atr, sl_atr (hot-reload)
6. EA ส่ง feedback ผ่าน ZMQ 7779
   → export S06_KAMA_VALUE, S06_ER_LAST ให้ Brain
```

---

## 11. ประสิทธิภาพและพฤติกรรมตาม Regime

### 11.1 S06 ในแต่ละ Market Regime

| Regime | ER ทั่วไป | พฤติกรรม S06 | ผลลัพธ์ที่คาดหวัง |
|--------|----------|------------|-----------------|
| TRENDING | 0.60–0.95 | สัญญาณชัด, Confidence สูง | Win rate ดี, trade วิ่งต่อได้นาน |
| RANGING | 0.10–0.35 | ER < threshold → filter ออก | ไม่เข้าตลาด — ป้องกัน whipsaw |
| VOLATILE | 0.35–0.65 | สัญญาณ variable | ShouldExit() ช่วยตัดเร็วเมื่อ trend พลิก |
| SQUEEZE | 0.05–0.25 | ER ต่ำมาก — ไม่มีสัญญาณ | รอ breakout แล้ว ER จะพุ่งทันที |

### 11.2 ผลของ kama_period ต่อ Responsiveness

| kama_period | ลักษณะ | เหมาะกับ Timeframe |
|------------|--------|-------------------|
| 5–8 | ตอบสนองเร็วมาก, ER fluctuates | M5–M15 (scalping) |
| 10 (default) | สมดุล | M15–H1 |
| 15 | ตอบสนองช้า, ER stable | H1–H4 (swing) |
| 20 | Conservative | H4–Daily (position) |

### 11.3 ผลของ ER Threshold ต่อ Trade Frequency

| ER_threshold | Trade Frequency | Win Rate | เหมาะกับ |
|-------------|-----------------|---------|---------|
| 0.20 | สูง (รับสัญญาณอ่อนๆ) | ต่ำกว่า | Aggressive, Brain TRENDING |
| 0.30 (default) | ปานกลาง | สมดุล | ทั่วไป |
| 0.40 | ต่ำ (คัดเข้มงวด) | สูงกว่า | Conservative, Brain RANGING |

### 11.4 Performance Summary

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Strong sustained trending market |
| **Worst Condition** | RANGING — ER ต่ำ few entries, false KAMA crossback |
| **Typical Duration** | Hours to days (trend continuation) |
| **R:R Ratio** | 3.0 default (tp_atr=3.0, sl_atr=1.0) |
| **Entry Frequency** | Low — requires trending AND ER above threshold |
| **Latency** | Minimal — KAMA update O(n) circular buffer per bar |

---

## 12. ไฟล์อ้างอิงและการวินิจฉัย (Files & Diagnostics)

### 12.1 ไฟล์หลักที่เกี่ยวข้อง

| ไฟล์ | ประเภท | หน้าที่ |
|------|-------|--------|
| `Include/Logic/Strategies/S06_KAMA.mqh` | MQL5 | Logic หลักของ `CKAMATrend` |
| `Include/Logic/IStrategy.mqh` | MQL5 | IStrategy abstract interface |
| `Include/Network/Protocol/Definitions.mqh` | MQL5 | `SDynamicParams`, `ENUM_MARKET_REGIME` |
| `Include/Logic/StrategyConstants.mqh` | MQL5 | `S06_KAMA` enum, magic=1006 |
| `03_Trader/ProgramC_Trader.mq5` | MQL5 EA | EA หลักที่ instantiate และเรียกใช้ S06 |
| `02_Brain/core/strategy/policy.py` | Python | CONFIG_PUSH generator (Regime → er_threshold) |
| `02_Brain/core/strategy/analysis.py` | Python | Regime classifier ที่ส่ง Regime ให้ S06 |

### 12.2 Diagnostic Parameters และการแปลผล

| Diagnostic Key | ค่าปกติ | ค่าผิดปกติ | การวินิจฉัย |
|---------------|--------|-----------|------------|
| `S06_KAMA_VALUE` | ใกล้ราคา market (< 50 pips) | ห่างมาก (> 100 pips) | Init bug หรือ KAMA stuck |
| `S06_ER_LAST` | 0.20–0.80 (fluctuating) | 0.00 ตลอดเวลา | ราคาหยุดนิ่ง หรือ buffer ไม่อัปเดต |
| `S06_ER_LAST` | — | 1.00 ตลอดเวลา | ATR ต่ำผิดปกติ หรือ calculation error |
| slope | +/- ค่าเล็กน้อย | 0.00 ตลอดเวลา | KAMA ไม่ขยับ — SC ต่ำมาก (ER ต่ำมาก) |

### 12.3 Log Messages สำหรับ Debugging

```
[S06] Init OK | EURUSD PERIOD_H1 | KAMA(10,2,30) ER_thresh=0.30
[S06] Analyze: Price=1.08450, KAMA=1.08239, ER=0.7895, Slope=+0.00087
[S06] GetSignal: LONG (ER=0.79 >= thresh=0.30, price>KAMA, slope>0)
[S06] GetConfidence: 0.833 (ER=0.79, dist=0.00211, ATR=0.0020)
[S06] ShouldExit: BUY, Price=1.08200 < KAMA=1.08239 → EXIT
[S06] OnConfigUpdate: Regime=TRENDING, er_threshold→0.25
[S06] OnConfigUpdate: Regime=RANGING, er_threshold→0.45
[S06] Export: KAMA_VALUE=1.08239, ER_LAST=0.7895
```

### 12.4 Common Issues

| อาการ | สาเหตุที่น่าจะเป็น | วิธีแก้ |
|-------|-----------------|--------|
| S06 ไม่มีสัญญาณเลย | ER < threshold ในตลาด ranging | ลด `S06_ER_THRESH` เป็น 0.20 |
| สัญญาณ false มากเกินไป | ER threshold ต่ำเกินไป | เพิ่มเป็น 0.40–0.45 |
| ออกเร็วเกินไปทุกครั้ง | ShouldExit() ตัดที่ KAMA | พฤติกรรมปกติ — แต่ถ้าไม่ต้องการ ให้ set `tp_atr` ต่ำลง |
| ATR = 0 ตอน Init | iATR handle ล้มเหลว | ตรวจสอบ symbol name และ timeframe |
| KAMA ไม่ converge | warmup bars ไม่พอ | ให้ EA รัน 20+ bars ก่อน trade จริง |

---

## 13. การวิเคราะห์เชิงวิพากษ์และข้อจำกัด (Critical Analysis & Limitations)

### ข้อจำกัดที่ 1: KAMA Warmup ไม่มี Persistence

เมื่อ EA restart หรือ attach ใหม่ `Init()` จะ pre-load ราคา `kama_period+1` bars และตั้ง KAMA เริ่มต้นที่ราคา oldest bar (ค่าเดียว ไม่ใช่ค่า KAMA ที่ converge แล้ว)

**ผลที่เกิด**: ในช่วง warmup ~10–20 bars แรก KAMA อาจยังไม่สะท้อนสภาพตลาดที่แท้จริง slope อาจบิดเบือน ทำให้สัญญาณแรกๆ ไม่น่าเชื่อถือ

**การปรับปรุงที่แนะนำ**: เพิ่ม warmup loop วน simulate KAMA update ย้อนหลัง 50–100 bars ก่อน Analyze() แรก โดยไม่ emit signal ระหว่าง warmup

### ข้อจำกัดที่ 2: SC-Squared ทำให้ KAMA "ติดขัด" ใน Transition Period

เมื่อ ER ต่ำ (0.10–0.20) SC ถูก square ให้เล็กมาก (0.01–0.04) KAMA แทบไม่ขยับเลย

**ปัญหาที่เกิด**: เมื่อตลาดกลับมา trend ใหม่หลังช่วง ranging ยาว ER จะพุ่งสูงอย่างรวดเร็ว แต่ KAMA ยังตามไม่ทัน slope อาจยังเป็น flat ทำให้พลาด entry ช่วงแรกของ trend ใหม่

**การปรับปรุงที่แนะนำ**: เพิ่ม ER momentum filter — ถ้า ER เพิ่งพุ่งสูงขึ้นเกิน threshold อย่างรวดเร็ว (ΔER > 0.20 ใน 2 bars) ให้ boost SC เบื้องต้นเพื่อให้ KAMA ตามทัน

### ข้อจำกัดที่ 3: Fixed ATR TP vs KAMA Dynamic Exit ขัดแย้งกัน

S06 ใช้ทั้ง Fixed ATR TP (`3.0×ATR`) และ `ShouldExit()` แบบ dynamic สองระบบนี้อาจขัดแย้งกัน:

- **ใน strong trend**: ราคาอาจถึง TP (3×ATR) ก่อน KAMA exit → ออกเร็วเกินไป พลาด move ใหญ่ที่เหลือ
- **ใน moderate trend**: KAMA อาจ exit ก่อน TP → กำไรน้อยกว่า 3.0×ATR ที่ตั้งไว้

**การปรับปรุงที่แนะนำ**: ตั้ง `tp_atr` สูงขึ้น (5.0–6.0) เพื่อให้ `ShouldExit()` เป็น primary exit เสมอ ทำให้ trade วิ่งได้นานตาม trend

### ข้อจำกัดที่ 4: ShouldExit() ไม่มี Minimum Hold Period

`ShouldExit()` จะ exit ทันทีที่ราคาหลุด KAMA แม้ว่า trade จะเพิ่งเปิดมาเพียง 1–2 ticks

**ตัวอย่างสถานการณ์ที่เป็นปัญหา**:
- เปิด LONG ที่ 1.0845 (KAMA = 1.08239)
- ราคา pullback เล็กน้อยมาที่ 1.0820 < KAMA 1.08239
- ShouldExit = true → ปิด trade ขาดทุนเล็กน้อย
- ราคากลับมา trend ต่อที่ 1.0870
- เสีย trade ดีทั้งหมด

**การปรับปรุงที่แนะนำ**: เพิ่ม `m_hold_bars` counter — ถ้า trade เปิดมาน้อยกว่า N bars (เช่น 3 bars) ให้ใช้ SL เท่านั้น ยังไม่เปิดใช้ ShouldExit()

---

*เอกสารนี้จัดทำโดย Jimmi Deep-Dive Documentation System | FlashEASuite V2 Phase P9-5*
*อ้างอิงจาก source code: `Include/Logic/Strategies/S06_KAMA.mqh` (CKAMATrend)*
*สูตรทั้งหมดตรวจสอบความถูกต้องจาก source code โดยตรง — ไม่ใช่การประมาณ*
