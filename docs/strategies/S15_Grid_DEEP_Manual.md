# S15 — Immortal Grid (Elastic Grid Trading)
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S15 | รหัสลำดับที่ 15 ในระบบมัลติกลยุทธ์ FlashEASuite V2 เป็นกลยุทธ์ Grid Trading ที่มีเอกลักษณ์สำคัญคือ Elastic Step ที่ปรับตัวตาม ATR |
| **Enum Name** | `S15_GRID` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) |
| **Enum Index** | 14 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[16]` — element ที่ 15 (นับจาก 0) |
| **ชื่อ** | Immortal Grid (Elastic Grid Trading) | "Immortal" สื่อถึงความสามารถในการ "ฟื้นคืนชีพ" จากสถานะขาดทุนชั่วคราวด้วยการเพิ่ม Lot ที่ Level ลึกกว่า และรอให้ราคากลับมาเพื่อปิดกำไรทั้งกริด |
| **ประเภท** | Full MQL5 — Legacy Wrapper over `CStrategyGrid` | เป็น Full MQL5 Strategy แต่มีสถาปัตยกรรม Wrapper ที่ซ้อนชั้น Legacy Core ไว้ภายใน |
| **Standalone Capable** | ✅ Yes (มีข้อจำกัด) | รองรับ Standalone แต่ต้องได้รับ CONFIG_PUSH อย่างน้อยหนึ่งครั้งเพื่อรับ `grid_direction` — ถ้าไม่เคยได้รับเลย `m_csm_data_received = false` และ Grid จะไม่เปิด Level ใดๆ |
| **Preferred Regime** | RANGING (`REGIME_RANGING`) | ตลาดที่ราคาแกว่งตัวในกรอบ — Grid ทำกำไรได้มากที่สุดเมื่อราคาเคลื่อนไปมาผ่าน Level ต่างๆ ซ้ำๆ |
| **Poor Regimes** | Strong TRENDING | ตลาดที่มีทิศทางรุนแรงจะทำให้ Grid เปิด Level ซ้อนกันเรื่อยๆ โดยไม่เคย Close เป็นกำไร สร้าง Drawdown สะสมสูงมาก |
| **MQL5 Wrapper Class** | `CS15Grid` | คลาส Wrapper ใน `Include/Logic/Strategies/S15_Grid.mqh` ทำหน้าที่เป็น IStrategy Interface |
| **MQL5 Core Class** | `CStrategyGrid` | คลาสแก่นกลางใน `Include/Logic/Grid/GridCore.mqh` — มี Logic ครบทุกอย่างของ Elastic Grid |
| **Python Role** | Grid Direction Provider (CSM) | Python Brain ไม่ได้ทำ Signal เอง แต่ส่ง Currency Strength Matrix (CSM) เพื่อให้ MQL5 ตัดสินใจทิศทาง BUY/SELL/NONE |
| **Magic Number** | 1015 (`MAGIC_S15_GRID`) | หมายเลขเอกลักษณ์สำหรับ Tag ออเดอร์ Grid ทั้งหมด ป้องกันการปะปนกับ S01-S14, S16 |
| **Family** | Grid/Mean-Reversion | กลุ่มกลยุทธ์ที่อาศัยการแกว่งตัวของราคาในกรอบ |
| **Version** | 6.03 | V6 Architecture พร้อม Phase 3.5 (ATR Protection) และ Phase 3.6 (Swap Filter) |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S15 คือกลยุทธ์ **Elastic Grid Trading** หรือที่เรียกในวงการว่า **"Immortal Grid"** เป็นกลยุทธ์ที่แทนที่จะเดาทิศทางตลาด กลับ **"ครอบตลาด"** ด้วยตาข่ายของออเดอร์ที่วางซ้อนกันเป็นระดับ (Level) ตามระยะห่างที่กำหนด — เมื่อราคาเคลื่อนที่ครบ "ระยะหนึ่ง" ระบบจะเปิด Level ใหม่โดยอัตโนมัติ

หัวใจของ S15 อยู่ที่ 3 องค์ประกอบ:

1. **Elastic Grid Step** — ระยะห่างระหว่าง Level ปรับตัวตาม ATR ทำให้ Grid "หายใจตามตลาด" ไม่แน่นเกินไปในช่วง Volatile ไม่กว้างเกินไปในช่วง Quiet
2. **Martingale-Style Lot Progression** — Lot ที่ Level ลึกกว่าใหญ่กว่า (1.0→1.5→2.0→3.0→4.5×) ทำให้เมื่อราคากลับมาแม้แต่บางส่วน กำไรจาก Level ลึกๆ ก็เพียงพอชดเชยขาดทุน Level ต้นๆ
3. **Multi-Layer Protection** — ATR Regime Filter (H1/D1) + Swap Filter + Brain Cooldown ทำให้ Grid ไม่เปิดในตลาดที่ไม่เหมาะสม

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมต้องชื่อ "Immortal Grid"?

**กลยุทธ์ Grid Trading ทั่วไป:**
Grid Trading แบบดั้งเดิม (Pure Grid) เปิดออเดอร์ Buy และ Sell สลับกันตามระดับราคาที่กำหนดล่วงหน้า เช่น วาง Buy ทุก 50 pips ลง และ Sell ทุก 50 pips ขึ้น โดยไม่สนใจทิศทางตลาด Grid ทำกำไรเมื่อราคาแกว่งข้ามระดับเหล่านี้ซ้ำๆ แต่ปัญหาคือเมื่อตลาดวิ่งในทิศทางเดียวนานๆ จะสะสมออเดอร์ขาดทุนจำนวนมาก

**สิ่งที่ทำให้ S15 "Immortal":**
S15 ต่างจาก Pure Grid ตรงที่มีทิศทาง (Directional Grid) — ระบบเลือกทิศทางเดียว (BUY หรือ SELL) ตาม Currency Strength Matrix ของ Python Brain แล้ว **"ซื้อลงไปเรื่อยๆ"** (DCA-style สำหรับ BUY) หรือ **"ขายขึ้นไปเรื่อยๆ"** (สำหรับ SELL) โดยเพิ่ม Lot ขึ้นที่ Level ที่ลึกกว่า

คำว่า "Immortal" มาจากแนวคิดว่า **"ตราบใดที่ตลาดยังกลับมาในที่สุด กริดนี้จะไม่ตาย"** — เพราะ Lot ที่ Level ลึกใหญ่กว่า เมื่อราคากลับมาแม้แต่ครึ่งทาง กำไรสะสมจาก Level ลึกก็เพียงพอปิดกำไรทั้งระบบ

**คำเตือนที่ต้องเข้าใจ:** ความ "Immortal" นี้มีเงื่อนไข — ตลาดต้องกลับมาในที่สุด ถ้าตลาด Trend ยาวมากโดยไม่กลับ Drawdown จะสะสมจนถึงระดับที่ Risk Management บังคับปิด

---

### 1.3 ธรรมชาติของ Grid Trading: กฎข้อที่หนึ่ง (The First Law of Grid)

**ทำไมตลาด Forex จึงเหมาะกับ Grid:**
ตลาด Forex มีธรรมชาติ 2 อย่างที่สนับสนุน Grid Trading:

1. **Mean Reversion ในระยะสั้น** — คู่เงินส่วนใหญ่ใช้เวลา 60-80% ของเวลาทั้งหมดในสภาวะ Ranging ไม่มีทิศทางชัดเจน ราคาแกว่งขึ้นลงในกรอบ ซึ่งเป็นสภาวะที่ Grid ทำกำไรได้ดีที่สุด
2. **Liquidity และ Swap** — ตลาด Forex มี Liquidity สูง ทำให้เปิด/ปิดออเดอร์หลายๆ รายการพร้อมกันได้โดยไม่มี Slippage มาก และ Swap (ดอกเบี้ยค้างคืน) บางทิศทางเป็นบวก ซึ่ง S15 ใช้ประโยชน์ผ่าน Swap Filter

**กฎข้อที่หนึ่งของ Grid Trading:**
> "Grid ทำกำไรจากความถี่ของการเคลื่อนที่ ไม่ใช่ทิศทางของการเคลื่อนที่"

ยิ่งราคาผ่านระดับ Grid บ่อยเท่าไหร่ Grid ยิ่งทำกำไรได้มากเท่านั้น ในตลาด Ranging ที่ราคาแกว่ง ±50 pips ต่อวัน และ Grid Step = 20 pips ราคาอาจผ่าน Grid Level หลายสิบครั้งต่อวัน สร้างกำไรเล็กๆ สะสมอย่างสม่ำเสมอ

---

### 1.4 กรณีศึกษาจริง (Case Study — ตลาด Ranging EURUSD)

**สถานการณ์:** วันอังคาร เวลา 10:00-16:00 GMT (London Session) EURUSD แกว่งตัวในกรอบ 1.0800-1.0850 ไม่มีข่าวสำคัญ

**ข้อมูลจาก Python Brain:**
```
CSM Analysis (10:00 GMT):
  USD Strength: 0.45
  EUR Strength: 0.58
  Strength_diff = USD - EUR = 0.45 - 0.58 = -0.13 < -0.10
  → grid_direction = GRID_DIR_BUY  (EUR แข็งกว่า USD)

ATR H1: 0.00123  (123 pips)
ATR D1: 0.00180  (180 pips)
ATR Ratio: 0.00123 / 0.00180 = 0.683 → ต่ำกว่า 0.8 ✅ ALLOWED

Swap Long: +0.42 → POSITIVE ✅ ALLOWED

python_confidence: 0.72
python_risk_multiplier: 1.0
```

**การคำนวณ Elastic Step:**
```
ATR_H1_in_points = 0.00123 / 0.00001 = 123 points
m_atr_reference  = 100.0 points
atr_ratio        = 123 / 100 = 1.23

Elastic_Step = 100 × 1.23 = 123 points
  → ยังอยู่ในช่วง [50, 200] ✅
  → ใช้ 123 points เป็นระยะห่างระหว่าง Level
```

**การเปิด Level 0 (10:01 GMT):**
```
EURUSD Ask = 1.08200
active_grid_count = 0 → ShouldOpenNewGridLevel() = true (Level แรก)

Grid Score = 1.0 × 0.72 (conf) × 1.0 (risk) × 1.5 (fresh bonus)
           = 1.08  → ส่งสัญญาณ BUY

CalculateGridLotSize(level=0):
  lot = 0.01 × 1.0 (progression[0]) × 1.0 (risk_mult)
      = 0.01 lot

ExecuteGridOrder(ORDER_TYPE_BUY):
  Price: 1.08200  Lot: 0.01  Comment: "Grid_L0"  Magic: 1015
```

**ราคาขึ้นไป 123 points → 1.08323 แต่กลับลงมาที่ 1.08077:**
```
เวลา 11:30: EURUSD = 1.08077 (ลงจาก L0 = 1.08200 → -123 points)
price_diff_points = |1.08077 - 1.08200| / 0.00001 = 123 points ≥ Elastic Step
→ ShouldOpenNewGridLevel() = true → เปิด Level 1

CalculateGridLotSize(level=1):
  lot = 0.01 × 1.5 × 1.0 = 0.015 lot

[Grid] Opened Level 1 | BUY | Lot: 0.015 | Price: 1.08077

Grid Score = 1.0 × 0.72 × 1.0 × 1.0 (ไม่มี bonus, ไม่ถึง penalty)
           = 0.72
```

**ราคาลงต่อไปอีก 123 points → 1.07954:**
```
เวลา 12:15: EURUSD = 1.07954 (ลงจาก L1 = 1.08077 → -123 points)
→ เปิด Level 2

CalculateGridLotSize(level=2):
  lot = 0.01 × 2.0 × 1.0 = 0.02 lot

Grid Score = 1.0 × 0.72 × 1.0 × 0.7 (penalty: active_count=2 ยังไม่ถึง 3)
           = 0.504  (ยังเปิดได้ เพราะ > 0)

[Grid] Opened Level 2 | BUY | Lot: 0.020 | Price: 1.07954
```

**สถานการณ์ ณ เวลา 12:15:**
```
L0: BUY 0.010 lot @ 1.08200  → P/L = (1.07954-1.08200) × 0.010 = -$2.46
L1: BUY 0.015 lot @ 1.08077  → P/L = (1.07954-1.08077) × 0.015 = -$1.85
L2: BUY 0.020 lot @ 1.07954  → P/L = 0 (เพิ่งเปิด)

Total Floating P/L: -$4.31 (Drawdown ชั่วคราว)
Total Exposure: 0.045 lot
```

**ราคากลับขึ้นมา (14:00 GMT):**
```
EURUSD = 1.08300 (ขึ้นจาก 1.07954 → +346 points)

L0: BUY 0.010 @ 1.08200 → P/L = (1.08300-1.08200) × 0.010 = +$1.00 ✅
L1: BUY 0.015 @ 1.08077 → P/L = (1.08300-1.08077) × 0.015 = +$3.35 ✅
L2: BUY 0.020 @ 1.07954 → P/L = (1.08300-1.07954) × 0.020 = +$6.92 ✅

Total Net P/L: +$11.27

→ Net Profit Target ถูกตี → ปิดทั้ง 3 Level พร้อมกัน
→ กำไรสุทธิ = +$11.27 ใน 4 ชั่วโมง
```

**บทเรียนจากกรณีนี้:**
กำไรไม่ได้เกิดจากการเดาทิศทางถูก (ราคาลงก่อนแล้วค่อยขึ้น) แต่เกิดจาก **Lot ที่ Level 2 ใหญ่กว่า Level 0** ทำให้เมื่อราคากลับมาแม้แต่บางส่วน กำไรจาก L2 (0.020 lot) สูงกว่าขาดทุนสะสม ระบบจึง "ชนะ" แม้จะ "แพ้ทิศทางชั่วคราว"

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 Elastic Grid Step — สมการหลัก

ความแตกต่างที่ใหญ่ที่สุดระหว่าง S15 กับ Grid Trading ทั่วไปคือ **Elastic Step** — ระยะห่างระหว่าง Level ไม่คงที่ แต่ปรับตาม Volatility ปัจจุบัน:

```
สมการ Elastic Step:

Step_Raw = Base_Step × (ATR_H1_points / ATR_Reference)

โดย:
  Base_Step      = m_base_elastic_step  (default = 100 points)
  ATR_H1_points  = ATR(14) บน H1 แปลงเป็น Points  = atr_h1_value / _Point
  ATR_Reference  = m_atr_reference  (default = 100.0 points)

Elastic_Step = Clamp(Step_Raw, Base_Step×0.5, Base_Step×2.0)
             = Clamp(Step_Raw, 50 points, 200 points)
```

**ตัวอย่างการคำนวณในสภาวะต่างๆ:**

| สภาวะตลาด | ATR H1 | ATR H1 (points) | Step_Raw | Elastic_Step | ความหมาย |
|-----------|--------|-----------------|----------|--------------|----------|
| Quiet (ช่วงกลางคืน) | 0.00050 | 50 pts | 50 pts | 50 pts | กริดแน่นกว่า — เข้าบ่อยขึ้น |
| Normal (ตลาดปกติ) | 0.00100 | 100 pts | 100 pts | 100 pts | กริดมาตรฐาน |
| Active (London Open) | 0.00123 | 123 pts | 123 pts | 123 pts | กริดกว้างขึ้น — ลดการ Over-trade |
| Volatile (ข่าวสำคัญ) | 0.00200 | 200 pts | 200 pts | 200 pts | กริดกว้างสูงสุด (clamped) |
| Extreme (Flash Crash) | 0.00350 | 350 pts | 350 pts | 200 pts | Clamped ที่ max — ป้องกัน Level ห่างมากเกินไป |

**เหตุผลที่ต้องมี Elastic Step:**
ถ้าใช้ Fixed Step 100 points ในช่วง Volatile ที่ราคาแกว่ง 200 points ต่อชั่วโมง ระบบจะเปิด Level ใหม่เร็วมากจน Exposure ทับซ้อนกันในเวลาอันสั้น ในขณะที่ช่วง Quiet ที่แกว่งแค่ 30 points ต่อชั่วโมง Fixed Step 100 อาจไม่เคยเปิด Level ใหม่เลย Elastic Step แก้ปัญหาทั้งสองด้านพร้อมกัน

---

### 2.2 Lot Progression (Martingale-Style)

```
ตาราง Lot Progression ใน CGridConfig:

m_lot_progression[0] = 1.0  →  Level 0: base_lot × 1.0
m_lot_progression[1] = 1.5  →  Level 1: base_lot × 1.5
m_lot_progression[2] = 2.0  →  Level 2: base_lot × 2.0
m_lot_progression[3] = 3.0  →  Level 3: base_lot × 3.0
m_lot_progression[4] = 4.5  →  Level 4: base_lot × 4.5

สำหรับ Level ≥ 5: ใช้ progression[4] = 4.5× (ไม่เพิ่มอีก)
```

**การคำนวณสมบูรณ์ (base_lot = 0.01):**

```
CalculateGridLotSize(level):
  lot = m_base_lot × m_lot_progression[min(level,4)]
      × m_python_risk_multiplier

  Normalize: lot = floor(lot / lot_step) × lot_step
  Clamp:     lot = max(min_lot, min(lot, max_lot))
```

**ตัวอย่าง (base_lot=0.01, risk_mult=1.0):**

| Level | Lot | Cumulative Exposure | Break-even Return |
|-------|-----|---------------------|-------------------|
| 0 | 0.010 | 0.010 | ราคากลับ 100% |
| 1 | 0.015 | 0.025 | ราคากลับ ~60% |
| 2 | 0.020 | 0.045 | ราคากลับ ~44% |
| 3 | 0.030 | 0.075 | ราคากลับ ~27% |
| 4 | 0.045 | 0.120 | ราคากลับ ~18% |

**คำเตือนเชิงคณิตศาสตร์:**
Lot ที่ Level 4 = 4.5× Level 0 หมายความว่าออเดอร์ชุดล่าสุดมีขนาดใหญ่กว่าออเดอร์แรก 4.5 เท่า ถ้าเปิดครบทุก Level และราคายังไม่กลับ Total Exposure = 12× base_lot ซึ่งต้องวางแผน Position Sizing ด้วย MM ที่รอบคอบ

---

### 2.3 ATR Regime Protection — หลักฐานเชิงคณิตศาสตร์ว่าตลาดกำลัง Trend

**ทฤษฎีเบื้องหลัง:**
ถ้าตลาด Ranging จะมีคุณสมบัติ:
- ATR H1 (Volatility ระยะสั้น) ควรเป็นสัดส่วนที่ "สมเหตุสมผล" กับ ATR D1 (Volatility ระยะยาว)
- ถ้า H1 Volatile มากเทียบกับ D1 หมายความว่า ในช่วงชั่วโมงที่ผ่านมา ราคาเคลื่อนไหวสูงผิดปกติเมื่อเทียบกับช่วงทั้งวัน — นั่นคือสัญญาณของ Trending Regime

```
สูตร:
ATR_Ratio = ATR_H1(14) / ATR_D1(14)

ตีความ:
  ATR_Ratio < 0.5:  H1 เงียบมาก เทียบกับ D1 → ช่วง Consolidation ลึก
  ATR_Ratio 0.5-0.8: H1 ปกติ เทียบกับ D1 → RANGING ✅ Grid เปิดได้
  ATR_Ratio > 0.8:  H1 Active มากผิดปกติ → อาจเป็น TRENDING 🚫 Grid ถูกบล็อก

ตัวอย่างตัวเลขจริง:
  ตลาด Ranging (วันปกติ):
    ATR_H1 = 0.00080  (80 pts/ชั่วโมง)
    ATR_D1 = 0.00150  (150 pts/วัน)
    Ratio   = 0.80 / 1.50 = 0.533  → ✅ ALLOWED (< 0.8)

  ตลาด Trending (หลัง NFP):
    ATR_H1 = 0.00160  (160 pts/ชั่วโมง!)
    ATR_D1 = 0.00150  (ยังเป็น 150 pts ก่อน update)
    Ratio   = 1.60 / 1.50 = 1.067  → 🚫 BLOCKED (> 0.8)
```

**เหตุผลที่ใช้ 0.8 เป็น Threshold:**
จากการทดสอบย้อนหลัง พบว่าเมื่อ ATR Ratio > 0.8 โอกาสที่ Grid จะ Drawdown รุนแรงสูงขึ้นอย่างมีนัยสำคัญ เพราะตลาดกำลัง "เดินทาง" ไม่ใช่ "แกว่ง" ค่า 0.8 เป็น Sweet Spot ระหว่างความไวในการตรวจจับ Trend และการหลีกเลี่ยง False Positive มากเกินไป

---

### 2.4 Swap Filter — ต้นทุนแฝงของ Grid

Grid Trading มีปัญหาพิเศษที่กลยุทธ์อื่นไม่ค่อยมี: **การสะสมออเดอร์หลายรายการที่ค้างอยู่ข้ามวัน**

```
สูตรต้นทุน Swap สะสม:

Daily_Swap_Cost = Σ[lot_i × SYMBOL_SWAP_per_lot]

สำหรับ S15 ที่มี 3 Level เปิดค้าง:
  L0: 0.010 lot × swap_rate
  L1: 0.015 lot × swap_rate
  L2: 0.020 lot × swap_rate
  Total exposure: 0.045 lot

ถ้า swap_long = -0.50 (ลบ):
  Daily_Swap_Cost = 0.045 × (-0.50) = -$0.0225 ต่อวัน
  ต่อสัปดาห์ = -$0.157 (เล็กน้อย)
  แต่ถ้า Grid ค้างอยู่ 30 วัน = -$0.675 ต้นทุนเพิ่มเติมที่กินกำไร

ถ้า swap_long = +0.42 (บวก):
  Daily_Swap = 0.045 × 0.42 = +$0.019 ต่อวัน (ได้เงินพิเศษ!)
```

**ตรรกะ Swap Filter ใน Code:**
```mql5
bool CheckSwapFilter()
{
    double swap_long  = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
    double swap_short = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);

    if(direction == GRID_DIR_BUY)
        return (swap_long > 0);    // เปิดได้เฉพาะเมื่อ Carry เป็นบวก

    if(direction == GRID_DIR_SELL)
        return (swap_short > 0);   // เปิดได้เฉพาะเมื่อ Carry เป็นบวก

    return true;  // ไม่มีทิศทาง → ไม่บล็อก
}
```

**เหตุผลที่สำคัญ:** Grid ที่เปิด Level ซ้อนกันหลาย Level อาจค้างอยู่นานหลายวันจนกว่าราคาจะกลับมา ถ้า Swap เป็นลบตลอดช่วงนั้น ต้นทุนสะสมจะกัดกินกำไรอย่างเงียบๆ Swap Filter ป้องกันปัญหานี้

---

### 2.5 Grid Score — สูตรคำนวณความน่าเชื่อถือ

เมื่อผ่านการตรวจสอบทั้งหมดแล้ว ระบบคำนวณ Grid Score เพื่อใช้เป็นค่า Confidence:

```
CalculateGridScore():

score = 1.0
      × m_python_confidence      (ความเชื่อมั่นจาก Brain, ช่วง 0-1)
      × m_python_risk_multiplier (ตัวคูณความเสี่ยง, default 1.0)

Bonus/Penalty ตาม Grid Depth:
  ถ้า active_grid_count == 0: score × 1.5  (Fresh Grid Bonus — โอกาสเต็ม)
  ถ้า active_grid_count >= 3: score × 0.7  (Deep Grid Penalty — ระวังมากขึ้น)

ช่วง Score:
  สูงสุด: 1.0 × 1.0 × 1.0 × 1.5 = 1.5  (fresh grid, conf=1.0)
  ต่ำสุดที่เปิดได้: > 0  (เพราะเช็ค > 0 ใน Analyze())
```

**ความหมายของแต่ละองค์ประกอบ:**

| องค์ประกอบ | ช่วงค่า | ความหมาย |
|------------|---------|----------|
| `m_python_confidence` | 0.0–1.0 | ความแม่นยำของ CSM Direction จาก Brain |
| `m_python_risk_multiplier` | 0.5–2.0 | ปรับขนาด Lot ตาม Regime (Brain กำหนด) |
| Fresh Grid ×1.5 | เมื่อ Level=0 | ไม่มีออเดอร์ค้าง — Grid เริ่มใหม่สดๆ ได้รับ Boost |
| Deep Grid ×0.7 | เมื่อ Level≥3 | มีออเดอร์ค้างอยู่ลึก — ลด Score เพื่อลด Aggressive Entry |

---

### 2.6 Currency Strength Matrix (CSM) — เข็มทิศ Grid

Python Brain ใช้ **Currency Strength Matrix (CSM)** เพื่อวัดความแข็งแกร่งสัมพัทธ์ของ 8 สกุลเงินหลัก:

```
8 สกุลเงิน: USD, EUR, GBP, JPY, AUD, CAD, CHF, NZD

คำนวณ Strength ของแต่ละสกุล:
  ดูการเคลื่อนไหวของทุกคู่เงินที่เกี่ยวข้อง
  เช่น EUR Strength = ค่าเฉลี่ย % การเปลี่ยนแปลง ของ EURUSD, EURGBP, EURJPY, EURAUD, EURCAD, EURCHF, EURNZD

สำหรับ EURUSD:
  Strength_diff = m_csm_usd - m_csm_eur

  ถ้า diff > +0.10: USD แข็งกว่า EUR มาก → SELL EURUSD
  ถ้า diff < -0.10: EUR แข็งกว่า USD มาก → BUY EURUSD
  ถ้า |diff| ≤ 0.10: เกือบเท่ากัน → GRID_DIR_NONE (ไม่เปิด)
```

**PolicyMessage ที่ Brain ส่งมาทาง Port 7778:**
```
PolicyMessage {
    symbol:              "EURUSD"
    confidence:          0.72
    risk_multiplier:     1.0
    is_in_cooldown:      false
    grid_direction:      1  (1=BUY, 2=SELL, 0=NONE)
    csm_usd:             0.45
    csm_eur:             0.58
    csm_gbp:             0.51
    csm_jpy:             0.38
    csm_aud:             0.42
    csm_cad:             0.47
    csm_chf:             0.55
    csm_nzd:             0.40
}
```

**เหตุผลที่ Python Brain ทำ CSM แทน MQL5:**
การคำนวณ CSM ต้องดึงข้อมูลจากหลายคู่เงินพร้อมกัน (28 คู่ Major) และคำนวณ Normalized Strength สัมพัทธ์ ซึ่ง Python สามารถทำได้อย่างมีประสิทธิภาพด้วย NumPy/Pandas ในขณะที่ MQL5 ต้องเปิด Chart หลายอันหรือใช้ `iCustom` ที่ซับซ้อนกว่ามาก

---

### 2.7 Net Profit Recovery Theory — ทำไม Martingale Grid ถึง "ชนะ" ในระยะสั้น

**สมมติฐาน:** ราคาที่เบี่ยงเบนออกไป N ระดับ จะมีโอกาสสูงกว่า 50% ที่จะกลับมาอย่างน้อย 1 ระดับก่อนที่จะเดินต่อ

**สูตร Net Profit Target:**
```
กำหนดให้ราคากลับมาอย่างน้อย M ระดับจากจุดต่ำสุด

Profit จาก Level N ที่ปิดกำไร = lot_N × M × elastic_step × point_value

Breakeven condition:
  Σ(profit_i from M levels recovery) > |Total_Floating_Loss|

ตัวอย่าง: Grid เปิด 3 Level (L0, L1, L2) และราคาลง 3 steps แล้วขึ้น 3 steps:
  L0: 0.010 lot × 3 steps × 100 pts × $0.01/pt = $3.00
  L1: 0.015 lot × 2 steps × 100 pts × $0.01/pt = $3.00
  L2: 0.020 lot × 1 step  × 100 pts × $0.01/pt = $2.00
  Total Profit: $8.00

  vs. Maximum Floating Loss (when all 3 are open at L2 level):
  L0: 0.010 × 200 pts = $2.00
  L1: 0.015 × 100 pts = $1.50
  L2: 0.020 ×   0 pts = $0.00
  Total Max Loss: $3.50

  Net: +$8.00 - $3.50 = +$4.50 กำไรสุทธิ ✅
```

---

## 3. สถาปัตยกรรมระบบ (System Architecture)

### 3.1 Legacy Wrapper Design — ทำไมต้องมี Wrapper?

S15 ใช้สถาปัตยกรรม **Legacy Wrapper** ซึ่งหมายความว่า Algorithm หลักของ Grid ถูกเขียนไว้ใน `CStrategyGrid` ก่อนที่ V6 จะมี `IStrategy` Interface ทีมพัฒนาตัดสินใจ **"ห่อ"** แทนที่จะเขียนใหม่ เพราะ:

1. **ลดความเสี่ยงของ Regression Bug** — Code ที่ผ่านการทดสอบมาแล้วไม่ควรถูกเขียนใหม่โดยไม่จำเป็น
2. **แยก Concern ได้ชัดเจน** — `CS15Grid` ดูแลเรื่อง V6 Interface, MM, HiddenTPSL, Emergency Transfer ในขณะที่ `CStrategyGrid` ดูแลเรื่อง Grid Logic ล้วนๆ
3. **Thin Wrapper Philosophy** — `CS15Grid` มีโค้ดน้อยมาก แทบทุก Method delegate ไปที่ `m_grid` (CStrategyGrid)

### 3.2 Class Hierarchy (ลำดับชั้นคลาส)

```
IStrategy (Interface — ไฟล์: IStrategy.mqh)
  ↓
CS15Grid (Wrapper — ไฟล์: Strategies/S15_Grid.mqh)
  │
  ├── CStrategyGrid m_grid  (direct member — core engine)
  │     ↓ extends
  │   CGridState  (GridState.mqh — position tracking)
  │     ↓ extends
  │   CGridConfig (GridConfig.mqh — config + state variables)
  │     ↓ extends
  │   CStrategyBase (StrategyBase.mqh — base utilities)
  │
  ├── CHiddenTPSL m_htpsl   (direct member — virtual TP/SL)
  ├── CTrailingStop m_trail (direct member — real broker SL trail)
  └── CMMManager* m_mm_mgr  (pointer — injected externally by StrategyManager)
```

**ความสำคัญของ CGridConfig:**
`CGridConfig` เป็น Base Class ที่เก็บตัวแปรสำคัญทั้งหมด:
- Grid State: `m_active_grid_count`, `m_grid_orders[]`, `m_last_grid_price`
- Config: `m_max_grid_levels`, `m_base_lot`, `m_lot_progression[]`
- Dynamic Params: `m_elastic_factor`, `m_conf_threshold`, `m_atr_ratio_thresh_dyn`
- Python Brain Data: `m_python_confidence`, `m_python_risk_multiplier`, `m_is_in_cooldown`
- CSM Data: `m_csm_usd/eur/gbp/jpy/aud/cad/chf/nzd`, `m_csm_data_received`

### 3.3 ตารางแบ่งความรับผิดชอบ Python Brain vs MQL5 Trader

```
┌────────────────────────────────────────────────────────────────────────┐
│              S15 ARCHITECTURE — ภาพรวมการแบ่งหน้าที่                    │
├──────────────────────────────┬─────────────────────────────────────────┤
│   PYTHON BRAIN (Server Side) │  MQL5 TRADER (Client Side)              │
│   คำนวณทิศทางและประเมิน      │  Execute Grid แบบ Real-time             │
├──────────────────────────────┼─────────────────────────────────────────┤
│  ✅ CSM Analysis              │  ✅ Elastic Step Calculation             │
│     (8 currencies, 28 pairs) │     (ATR H1 × ratio, clamped)           │
│                              │                                         │
│  ✅ Grid Direction Decision   │  ✅ ATR Regime Protection                │
│     (BUY/SELL/NONE)          │     (H1/D1 ratio check)                 │
│                              │                                         │
│  ✅ Confidence Scoring        │  ✅ Swap Filter                          │
│     (CSM diff score)         │     (SYMBOL_SWAP_LONG/SHORT)            │
│                              │                                         │
│  ✅ Risk Multiplier           │  ✅ Level Trigger Logic                  │
│     (Regime-based scaling)   │     (ShouldOpenNewGridLevel)            │
│                              │                                         │
│  ✅ Cooldown Control          │  ✅ Lot Progression                      │
│     (is_in_cooldown flag)    │     (1.0/1.5/2.0/3.0/4.5 × base_lot)   │
│                              │                                         │
│  ✅ CONFIG_PUSH (Port 7778)   │  ✅ HiddenTPSL per Position              │
│     (direction, conf, risk)  │     (ATR-based virtual exits)           │
│                              │                                         │
│  ✅ Regime Override           │  ✅ TrailingStop                         │
│     (cooldown when volatile) │     (real broker SL movement)           │
│                              │                                         │
│  ❌ Elastic Step               │  ✅ Emergency Transfer                   │
│     (computed in MQL5)       │     (absorb S16 positions)              │
│                              │                                         │
│  ❌ Level Open/Close           │  ✅ MM Selection                         │
│     (real-time in MQL5)      │     (via CMMManager)                    │
└──────────────────────────────┴─────────────────────────────────────────┘
```

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางข้อมูลหลัก (Main Data Path)

```
[ตลาด Forex] → [MT5 Platform] → [FeederEA] → Port 7777 → [Python Brain]
                                                              ↓
                                                     [CSM Calculation]
                                              (ดึง 28 pairs จาก InfluxDB)
                                                              ↓
                                                  [Strength Diff Analysis]
                                              (USD-EUR, USD-GBP, etc.)
                                                              ↓
                                                [Grid Direction Decision]
                                              (BUY / SELL / NONE + score)
                                                              ↓
                                              [PolicyMessage — Port 7778]
                                              (type=10, direction, conf, CSM)
                                                              ↓
                                               [ProgramC_Trader.mq5]
                                                              ↓
                                          [CS15Grid::SetParameters(jsonParams)]
                                                              ↓
                                    [_BuildDynamicParamsFromJson → SDynamicParams]
                                                              ↓
                                      [CStrategyGrid::SetDynamicParams(params)]
                                                              ↓
                                      [UpdateFromPolicy → CSM + Direction stored]
                                                              ↓
                                              [ทุก Tick: CS15Grid::Analyze()]
                                                              ↓
                                              [CStrategyGrid::GetScore()]
                                              Safety Chain: 6 Checks
                                                              ↓
                                                 [CalculateGridScore()]
                                                              ↓
                                    [m_state.last_signal = BUY/SELL/NONE]
                                                              ↓
                                          [StrategyManager: ExecuteGridOrder]
                                              (Lot by Level Progression)
                                                              ↓
                                          [CS15Grid::ManagePositions()]
                                    (RegisterNew → HiddenTPSL + Trail Update)
                                                              ↓
                                              [TRADE_REPORT — Port 7779]
                                              (pnl, level, ticket → Brain)
```

### 4.2 Update Path เมื่อ CONFIG_PUSH มาถึง

```
ProgramC_Trader::OnNewConfig(jsonString)
    ↓
StrategyManager::DistributeDynamicParams()
    ↓
CS15Grid::SetParameters(jsonString)     ← IStrategy interface
    ↓
_BuildDynamicParamsFromJson(jsonString)  ← parse JSON → SDynamicParams p
    │
    ├── p.SetParam("S15_MAX_ORDERS",  ...)
    ├── p.SetParam("S15_BASE_STEP",   ...)
    ├── p.SetParam("S15_ELASTIC_FACTOR", ...)
    ├── p.SetParam("S15_CONF_THRESHOLD", ...)
    ├── p.SetParam("S15_ATR_RATIO",   ...)
    ├── p.SetParam("S15_SWAP_FILTER", ...)
    ├── m_tp_atr_mult   ← parse S15_TP_ATR_MULT
    ├── m_sl_atr_mult   ← parse S15_SL_ATR_MULT
    └── m_trail_enabled ← parse S15_TRAIL_ENABLED
    ↓
CStrategyGrid::SetDynamicParams(p)
    ↓
CGridConfig::ApplyDynamicParams(p)      ← ปรับ m_max_grid_levels, m_base_elastic_step, etc.
    ↓
CStrategyGrid::SetATRRatioThreshold()   ← sync m_atr_ratio_threshold
CStrategyGrid::SetSwapFilterEnabled()   ← sync m_swap_filter_enabled
```

**จุดสำคัญ:** การรับ CONFIG_PUSH ไม่ต้อง Restart EA — ค่าทุกอย่างอัปเดตทันทีใน Tick ถัดไป (Hot-reload via SDynamicParams)

---

## 5. CStrategyGrid: ตรรกะ Grid ภายใน (Internal Logic)

### 5.1 Safety Chain ใน GetScore() — 6 ชั้นป้องกัน

```
GetScore() — เรียกทุก Tick โดย CS15Grid::Analyze()
─────────────────────────────────────────────────────
ชั้นที่ 0: Rate Limiting (Cache per Second)
  ├── current_time == m_last_score_time AND m_cached_score >= 0
  └── return m_cached_score  (ไม่คำนวณซ้ำ — ประหยัด CPU)

ชั้นที่ 1: ATR Regime Protection (Phase 3.5)
  ├── CheckATRRegime()
  │   ├── CopyBuffer(atr_h1_handle) + CopyBuffer(atr_d1_handle)
  │   ├── ratio = atr_h1 / atr_d1
  │   └── ratio > m_atr_ratio_threshold → return false
  └── fail → m_cached_score = 0.0 → return 0.0

ชั้นที่ 2: Swap Filter (Phase 3.6)
  ├── m_swap_filter_enabled == true
  ├── CheckSwapFilter()
  │   ├── GRID_DIR_BUY:  swap_long  <= 0 → return false
  │   └── GRID_DIR_SELL: swap_short <= 0 → return false
  └── fail → m_cached_score = 0.0 → return 0.0

ชั้นที่ 3: Cooldown Flag
  ├── m_is_in_cooldown == true
  └── return 0.0  (Brain บอกให้หยุดชั่วคราว)

ชั้นที่ 4: Minimum Confidence
  ├── m_python_confidence < 0.3
  └── return 0.0  (Brain ไม่มั่นใจพอ)

ชั้นที่ 5: CSM Data Required
  ├── !m_csm_data_received → return 0.0
  └── m_current_direction == GRID_DIR_NONE → return 0.0

ผ่านทุกชั้น:
  UpdateATRAndElasticStep()
  UpdateGridState()
  DetermineGridDirection()
  ShouldOpenNewGridLevel() → true?
  → CalculateGridScore() → return score
  → false: return 0.0
─────────────────────────────────────────────────────
```

### 5.2 UpdateATRAndElasticStep() — คำนวณระยะห่างกริดแบบ Real-time

```mql5
void UpdateATRAndElasticStep()
{
    // 1. ดึง ATR(14) จาก H1 handle
    double atr_buffer[1];
    if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
    {
        // ถ้าดึงไม่ได้: คงค่าเดิม (fallback safe)
        m_atr_current = m_atr_reference;
        m_current_elastic_step = m_base_step_points;
        return;
    }

    // 2. แปลง ATR จาก Price unit → Points
    m_atr_current = atr_buffer[0] / _Point;

    // 3. คำนวณ Elastic Step
    double atr_ratio = m_atr_current / m_atr_reference;  // m_atr_reference = 100.0
    m_current_elastic_step = m_base_step_points * atr_ratio;

    // 4. Clamp ให้อยู่ในช่วง [50%, 200%] ของ base_step
    double min_step = m_base_step_points * 0.5;  // 50 points (if base=100)
    double max_step = m_base_step_points * 2.0;  // 200 points (if base=100)
    if(m_current_elastic_step < min_step) m_current_elastic_step = min_step;
    if(m_current_elastic_step > max_step) m_current_elastic_step = max_step;
}
```

**ข้อสังเกต:** `m_atr_reference = 100.0` เป็นค่าคงที่ใน Constructor ไม่ได้ถูกอัปเดตจาก ATR จริงๆ แปลว่า Elastic Step = Base_Step × (ATR_H1_in_points / 100) — ทำงานเหมือน Normalize ATR โดยถือว่า "ATR ปกติ = 100 points"

---

### 5.3 ShouldOpenNewGridLevel() — ตรรกะการ Trigger Level ใหม่

```mql5
bool ShouldOpenNewGridLevel()
{
    // Guard 1: ถึง Max Level แล้ว
    if(m_active_grid_count >= m_max_grid_levels) return false;

    // Guard 2: ไม่มีทิศทาง
    if(m_current_direction == GRID_DIR_NONE) return false;

    // Guard 3: Elastic Step ไม่พร้อม
    if(m_current_elastic_step <= 0.0) return false;

    // ดึงราคาปัจจุบัน (Ask สำหรับ BUY, Bid สำหรับ SELL)
    MqlTick tick;
    if(!SymbolInfoTick(GetSymbol(), tick)) return false;
    double price = (m_current_direction==GRID_DIR_BUY) ? tick.ask : tick.bid;

    // Level แรก: เปิดทันทีโดยไม่ต้องรอ
    if(m_active_grid_count == 0) return true;

    // Level ถัดไป: ราคาต้องเคลื่อนไหวครบ Elastic Step จากจุดล่าสุด
    double price_diff_points = MathAbs(price - m_last_grid_price) / _Point;
    return (price_diff_points >= m_current_elastic_step);
}
```

**ข้อสำคัญ:** `m_last_grid_price` คือราคา Open ของ Grid Order ล่าสุดที่เพิ่งถูกบันทึกใน `UpdateGridState()` — ไม่ใช่ราคาสูงสุดหรือต่ำสุดของช่วงเวลา

---

### 5.4 CalculateGridLotSize() — คำนวณ Lot ต่อ Level

```mql5
double CalculateGridLotSize(int level)
{
    // 1. Base lot × progression
    double lot = m_base_lot;
    lot *= (level < 5) ? m_lot_progression[level] : m_lot_progression[4];

    // 2. Risk multiplier จาก Python Policy
    lot *= m_python_risk_multiplier;

    // 3. Normalize ตาม Broker's Lot Step
    double lot_step = SymbolInfoDouble(GetSymbol(), SYMBOL_VOLUME_STEP);
    lot = MathFloor(lot / lot_step) * lot_step;

    // 4. Clamp: min_lot ≤ lot ≤ max_lot
    double min_lot = SymbolInfoDouble(GetSymbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(GetSymbol(), SYMBOL_VOLUME_MAX);
    if(lot < min_lot) lot = min_lot;
    if(lot > max_lot) lot = max_lot;

    return lot;
}
```

**ตัวอย่าง (base_lot=0.01, risk_mult=0.5 ใน Standalone):**

| Level | Formula | lot_raw | Normalized | หมายเหตุ |
|-------|---------|---------|------------|---------|
| 0 | 0.01×1.0×0.5 | 0.005 | 0.01 | min_lot clamped |
| 1 | 0.01×1.5×0.5 | 0.0075 | 0.01 | min_lot clamped |
| 2 | 0.01×2.0×0.5 | 0.01 | 0.01 | พอดี min_lot |
| 3 | 0.01×3.0×0.5 | 0.015 | 0.01 หรือ 0.02 | ขึ้นอยู่ lot_step |
| 4 | 0.01×4.5×0.5 | 0.0225 | 0.02 | floor ปัดลง |

---

### 5.5 ExecuteGridOrder() — ส่งคำสั่งจริงไปโบรกเกอร์

```mql5
void ExecuteGridOrder(ENUM_ORDER_TYPE type)
{
    int next_level = m_active_grid_count;  // Level ถัดไปที่จะเปิด
    double lot_size = CalculateGridLotSize(next_level);

    MqlTick tick;
    if(!SymbolInfoTick(GetSymbol(), tick)) return;
    double price = (type==ORDER_TYPE_BUY) ? tick.ask : tick.bid;

    // SL/TP จาก m_sl_points / m_tp_points (optional, default=0)
    // ถ้า = 0 จะไม่ตั้ง SL/TP ในระดับ Broker (ใช้ HiddenTPSL แทน)

    MqlTradeRequest req = {};
    req.action   = TRADE_ACTION_DEAL;
    req.symbol   = GetSymbol();
    req.volume   = lot_size;
    req.type     = type;
    req.price    = price;
    req.deviation = 10;         // 10 points slippage tolerance
    req.magic    = 999000;      // *** NOTE: GridCore ใช้ 999000, CS15Grid ใช้ MAGIC_S15_GRID=1015
    req.comment  = "Grid_L" + IntegerToString(next_level);

    if(OrderSend(req, result))
        Print("[Grid] Opened Level", next_level, " | Lot:", lot_size);
    else
        Print("[Grid] FAILED! Error:", GetLastError());
}
```

**หมายเหตุสำคัญเรื่อง Magic Number:**
`GridCore.mqh` (legacy) ใช้ hardcoded `999000` แต่ `CS15Grid` (wrapper) ใช้ `MAGIC_S15_GRID = 1015` ซึ่งเป็น V6 Convention ทำให้ `UpdateGridState()` ใน GridState.mqh ที่กรองด้วย `magic != 999000` จะยังทำงานได้กับออเดอร์ที่เปิดโดย GridCore

---

## 6. CS15Grid (IStrategy Wrapper) — ชั้นบน

### 6.1 ManagePositions() — เรียกทุก Tick หลัง Analyze()

```mql5
// เรียกโดย ProgramC_Trader ทุก Tick หลัง Analyze()
void ManagePositions(const MqlTick &tick)
{
    if(!m_initialized) return;

    // ขั้นตอนที่ 1: Register ออเดอร์ใหม่ที่พึ่งเปิด
    _RegisterNewPositions();

    // ขั้นตอนที่ 2: อัปเดต Trailing Stop (ถ้าเปิดใช้)
    if(m_trail_enabled) m_trail.Update();

    // ขั้นตอนที่ 3: ตรวจ Hidden TP/SL และปิดถ้าถึง
    m_htpsl.CheckAndClose();
}
```

**ความสำคัญของลำดับ:**
1. Register ก่อน — มิฉะนั้นออเดอร์ใหม่จะไม่มี Hidden TP/SL ในรอบแรก
2. Update Trail ก่อน CheckAndClose — Trail อาจขยับ SL ซึ่งอาจ trigger CheckAndClose ในรอบเดียวกัน

---

### 6.2 _RegisterNewPositions() — ติด HiddenTPSL ให้ทุกออเดอร์ใหม่

```mql5
void _RegisterNewPositions()
{
    bool want_hidden = (m_tp_atr_mult > 0.0 || m_sl_atr_mult > 0.0);
    if(!want_hidden && !m_trail_enabled) return;  // ไม่มีอะไรต้องทำ

    double atr = (want_hidden) ? _GetATR14() : 0.0;

    for each position(symbol=m_symbol, magic=MAGIC_S15_GRID):
    {
        // ข้ามถ้าติด Hidden TP/SL ไปแล้ว (ป้องกัน Double-Register)
        if(want_hidden && !_IsHiddenTracked(ticket) && atr > 0)
        {
            bool is_buy = (position_type == POSITION_TYPE_BUY);
            double open_pr = position_open_price;

            // คำนวณ Hidden TP
            if(m_tp_atr_mult > 0)
            {
                double tp = is_buy ? open_pr + m_tp_atr_mult * atr
                                   : open_pr - m_tp_atr_mult * atr;
                m_htpsl.SetHiddenTP(ticket, tp);
            }

            // คำนวณ Hidden SL
            if(m_sl_atr_mult > 0)
            {
                double sl = is_buy ? open_pr - m_sl_atr_mult * atr
                                   : open_pr + m_sl_atr_mult * atr;
                m_htpsl.SetHiddenSL(ticket, sl);
            }
        }

        // Trailing — Register ครั้งเดียว (CTrailingStop dup-check ภายใน)
        if(m_trail_enabled)
            m_trail.Register(ticket);
    }
}
```

**ทำไมต้องใช้ Hidden TP/SL:**
Broker บางรายมีนโยบายจำกัด Maximum TP/SL Distance หรือมองว่า Grid Trading ที่เปิดออเดอร์หลายรายการโดยไม่มี SL น่าสงสัย HiddenTPSL แก้ปัญหาทั้งหมดโดยให้ EA ดูแล TP/SL เองโดยไม่ผ่าน Broker

---

### 6.3 EmergencyTransferToGrid() — รับตำแหน่งฉุกเฉินจาก S16

```mql5
STransferResult EmergencyTransferToGrid(ENUM_TRANSFER_REASON reason)
{
    // 1. ล้าง HiddenTPSL + Trail ของออเดอร์ที่ไม่ใช่ Grid (เช่น S16 Spike)
    for each position(symbol, magic != MAGIC_S15_GRID):
    {
        m_htpsl.ClearHidden(ticket);
        m_trail.Unregister(ticket);
    }

    // 2. เรียก TransferToGrid() utility:
    //    - ปิดออเดอร์ S16 ที่มีอยู่
    //    - เปิดออเดอร์ Grid ใหม่ที่ราคาเดียวกันและ Net Exposure เท่ากัน
    return TransferToGrid(m_symbol, MAGIC_S15_GRID, reason);
}
```

**Scenario ที่ใช้:** เมื่อ S16 Spike Strategy เปิดออเดอร์ขาทิศทางที่ Market ไม่เป็นใจ และ Brain ตัดสินใจว่า "ควรแปลงเป็น Grid" แทนที่จะ Stop Loss ตรงๆ โดยกระจาย Exposure เป็น Grid Level แล้วรอ Recovery

---

### 6.4 MM Integration — การเลือก Money Management

```mql5
// CS15Grid เชื่อมต่อกับ CMMManager ผ่าน Pointer ที่ StrategyManager Inject เข้ามา
void SetMMManager(CMMManager* mgr) { m_mm_mgr = mgr; }

ENUM_MM_ID GetActiveMM()
{
    if(m_mm_mgr == NULL) return MM_ID_FIXED_CONSERVATIVE;  // Fallback
    SAccountState acct;
    acct.UpdateFromAccount();
    return m_mm_mgr.SelectMM((int)S15_GRID, acct);  // ใช้ Logic ของ MMManager
}
```

**MM ที่แนะนำสำหรับ S15 (จาก SMMSelection):**

| สถานการณ์ | MM ที่ใช้ | เหตุผล |
|-----------|---------|--------|
| **Default** | MM03 (Kelly หรือ Fixed Risk) | Grid มีประวัติ W/L ที่วัดได้ |
| **Volatile Regime** | MM07 (Percent Volatility) | ATR สูง → ลด Lot ลดความเสี่ยง Grid ลึก |
| **Drawdown ≥ 10%** | MM10 (Drawdown-Based) | ลด Lot อัตโนมัติเมื่อ Drawdown สูง |
| **Standalone** | MM01 (Fixed Conservative) | ไม่มีข้อมูล Server — ใช้ Lot คงที่ปลอดภัย |

---

## 7. ตารางพารามิเตอร์ฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ภายใน MQL5 (Internal Defaults จาก CGridConfig)

| Parameter | Default | ช่วงแนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|-----------|----------------|
| `m_max_grid_levels` | 5 | 3–7 | จำนวน Level สูงสุดที่ Grid เปิดได้พร้อมกัน ค่า 5 คือจุดสมดุลระหว่างโอกาส Recovery และความเสี่ยงจาก Drawdown ค่าสูง (7+) ต้องมี Account Balance ขนาดใหญ่ |
| `m_base_lot` | 0.01 | 0.01–0.10 | Lot ของ Level 0 ค่านี้เป็น Base ที่ Lot Progression คูณเข้าไป ปรับตาม Account Size |
| `m_lot_progression[5]` | {1.0,1.5,2.0,3.0,4.5} | คงที่ | อัตราส่วน Lot ต่อ Level ออกแบบให้ Level ลึกทำกำไรพอชดเชย Level ต้นเมื่อราคากลับ |
| `m_base_elastic_step` | 100.0 | 50–200 | Base Grid Spacing ในหน่วย Points ก่อนถูก Scale โดย ATR Ratio |
| `m_elastic_factor` | 1.5 | 1.0–3.0 | ตัวคูณเพิ่มเติมสำหรับ ATR Scaling (ยังไม่ได้ใช้ใน core formula ปัจจุบัน — reserved) |
| `m_conf_threshold` | 0.65 | 0.50–0.80 | ค่า Confidence ขั้นต่ำที่ต้องผ่านก่อนเปิด Grid Level ใหม่ (ตรวจสอบใน GetScore ชั้นที่ 4) |
| `m_atr_ratio_thresh_dyn` | 0.8 | 0.6–1.0 | ATR H1/D1 Threshold ค่าต่ำ (0.6) → กรองเข้มขึ้น (เปิดน้อยลง) ค่าสูง (1.0) → กรองน้อย (เปิดง่ายขึ้น) |
| `m_swap_filter_dyn` | true | true/false | เปิด/ปิด Swap Filter ปิดเฉพาะเมื่อ Swap เป็น Cost น้อยมากหรือยอมรับได้ |

### 7.2 CONFIG_PUSH Keys (Server Mode — SDynamicParams)

| Key | Type | Default | คำอธิบาย | ผลกระทบทันที |
|-----|------|---------|----------|-------------|
| `S15_MAX_ORDERS` | int | 5 | สูงสุด Grid Level / ออเดอร์พร้อมกัน | จำกัด `m_max_grid_levels` ทันที |
| `S15_BASE_STEP` | float | 100.0 | Base Grid Step ในหน่วย Points | อัปเดต `m_base_elastic_step` + `m_current_elastic_step` |
| `S15_ELASTIC_FACTOR` | float | 1.5 | ตัวคูณ ATR Scaling สำหรับ Step | อัปเดต `m_elastic_factor` |
| `S15_CONF_THRESHOLD` | float | 0.65 | Confidence ขั้นต่ำเพื่อเปิด Level | อัปเดต `m_conf_threshold` |
| `S15_ATR_RATIO` | float | 0.8 | ATR H1/D1 Protection Threshold | อัปเดต `m_atr_ratio_threshold` ผ่าน `SetATRRatioThreshold()` |
| `S15_SWAP_FILTER` | float | 1.0 | 1.0 = เปิด Swap Filter, 0.0 = ปิด | อัปเดต `m_swap_filter_enabled` ผ่าน `SetSwapFilterEnabled()` |
| `S15_TP_ATR_MULT` | float | 0.0 | Hidden TP = mult × ATR14 (0 = ปิด) | อัปเดต `m_tp_atr_mult` ใน CS15Grid |
| `S15_SL_ATR_MULT` | float | 0.0 | Hidden SL = mult × ATR14 (0 = ปิด) | อัปเดต `m_sl_atr_mult` ใน CS15Grid |
| `S15_TRAIL_ENABLED` | float | 0.0 | 1.0 = เปิด Trailing Stop | อัปเดต `m_trail_enabled` + `m_trail.SetEnabled()` |
| `S15_RISK_MULT` | float | 1.0 | Risk Multiplier (ผ่าน `risk_multiplier` field) | คูณ Lot ทุก Level |

### 7.3 Standalone Mode Defaults

| Setting | Value | Source |
|---------|-------|--------|
| Risk Multiplier | 0.5× | CStandaloneSelector บังคับ |
| Grid Params | จาก `standalone_config.dat` | CONFIG_PUSH ล่าสุดที่บันทึกไว้ |
| Grid Params (fallback) | CGridConfig constructor defaults | ไม่มีไฟล์ `dat` |
| grid_direction | ❌ ไม่มี | ต้องได้รับอย่างน้อย 1 PolicyMessage |
| HiddenTPSL | Disabled | `m_tp_atr_mult=0, m_sl_atr_mult=0` |
| Trailing Stop | Disabled | `m_trail_enabled=false` |

**ข้อจำกัดสำคัญของ Standalone Mode:**
```
ปัญหา: m_csm_data_received = false เมื่อไม่เคยรับ PolicyMessage

Safety Chain ชั้นที่ 5:
  if(!m_csm_data_received || m_current_direction == GRID_DIR_NONE)
      return 0.0;  ← Grid จะไม่เปิดเลย!

วิธีแก้: ถ้าต้องการ Standalone Grid จริงๆ ต้องได้รับ CONFIG_PUSH สักครั้ง
ก่อนที่จะขาด Connection
```

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Standalone Mode — เมื่อ Python Brain ขาดการเชื่อมต่อ

```
ลำดับการตัดสินใจเมื่อ Brain Offline:

Step 1: CStandaloneSelector ตรวจพบว่าไม่มี PolicyMessage ใน 30 วินาที
Step 2: ตั้ง risk_multiplier = 0.5 (Conservative mode)
Step 3: โหลด standalone_config.dat (ถ้ามี)
        → ได้ S15_MAX_ORDERS, S15_BASE_STEP, S15_ELASTIC_FACTOR ล่าสุด
Step 4: แต่ m_csm_data_received ยังคง = false ถ้าไม่เคยรับ PolicyMessage
        → GetScore() จะ return 0.0 เสมอ → ไม่เปิด Grid Level ใหม่

Step 5: Grid Level ที่เปิดอยู่แล้ว (ก่อน Brain Offline):
        → ManagePositions() ยังทำงาน → HiddenTPSL และ TrailingStop ยังใช้งานได้
        → สามารถปิดกำไร/ขาดทุนตาม Hidden Exits ที่ตั้งไว้

Step 6: Brain กลับมา Online
        → รับ PolicyMessage ใหม่ → m_csm_data_received = true
        → Grid กลับมาทำงานปกติ
```

### 8.2 Server Mode — Full Operation

```
Python Brain Optimization Cycle (ทุกรอบที่กำหนด):

1. ดึงข้อมูล Tick จาก InfluxDB (Port 7777 buffer)
2. คำนวณ Currency Strength สำหรับ 8 สกุลเงิน
3. เปรียบเทียบ Base vs Quote currency ของ Symbol เป้าหมาย
4. ตัดสิน Grid Direction + Confidence
5. ตรวจสอบ Regime → ถ้า VOLATILE: ตั้ง is_in_cooldown=true
6. สร้าง PolicyMessage + CONFIG_PUSH → ส่งทาง Port 7778
7. รับ TRADE_REPORT ทาง Port 7779 → อัปเดต Performance Tracker
8. ถ้า Drawdown สูง: ปรับ risk_multiplier ลง → ส่ง CONFIG_PUSH ใหม่

ฝั่ง MQL5 Trader:
1. รับ CONFIG_PUSH → CS15Grid::SetParameters() → hot-reload ทันที
2. ทุก Tick: Analyze() → GetScore() safety chain → CalculateGridScore()
3. ถ้า Score > 0: ExecuteGridOrder() → เปิด Level ใหม่
4. ManagePositions() → Register HiddenTPSL → Trail → CheckAndClose
5. ปิดกำไร → TRADE_REPORT → Port 7779 → Brain
```

---

## 9. Grid State Diagram — วงจรชีวิตของ Grid

```
┌─────────────────────────────────────────────────────────────────────┐
│                    S15 GRID LIFECYCLE                                │
└─────────────────────────────────────────────────────────────────────┘

[Init] → m_initialized = true
    │
    ▼
[Idle — รอเงื่อนไข]
    │
    ├──► [BLOCKED: ATR Ratio > 0.8]  ← Trend regime
    │         ↓ Ratio กลับต่ำ
    │         └──► [Idle]
    │
    ├──► [BLOCKED: Swap Negative]  ← Carry cost
    │         ↓ Swap เปลี่ยน
    │         └──► [Idle]
    │
    ├──► [BLOCKED: No Brain/Cooldown]  ← conf<0.3 or cooldown
    │         ↓ PolicyMessage มาถึง
    │         └──► [Idle]
    │
    └──► [Level 0 Open] ← ShouldOpenNewGridLevel() = true (count=0)
              │  Lot: 0.01 × 1.0 × risk_mult
              │  Comment: "Grid_L0"
              │
              ├──► Price ขึ้น (BUY Grid): ราคาวิ่งตาม → กำไรลอยตัว
              │    ↓ ราคากลับลง ≥ elastic_step
              │    └──► [Level 1 Open]
              │              │  Lot: 0.01 × 1.5
              │              │  Score × 1.0 (ไม่มี bonus/penalty)
              │              │
              │              ├──► [Level 2 Open]  ← ราคาลงอีก step
              │              │         Lot: 0.01 × 2.0
              │              │
              │              ├──► [Level 3 Open]  ← ราคาลงอีก step
              │              │         Lot: 0.01 × 3.0
              │              │         Score × 0.7 (deep penalty)
              │              │
              │              └──► [Max Levels — ไม่เปิด Level ใหม่]
              │                        รอ Net Profit Recovery
              │
              └──► [Closed: Net Profit Hit / HiddenTP / HiddenSL]
                        → Grid Reset → กลับ [Idle]
```

---

## 10. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | RANGING — ราคาแกว่งซ้ำผ่าน Grid Level บ่อยๆ |
| **สภาวะตลาดที่แย่ที่สุด** | Strong TRENDING — ราคาวิ่งทิศทางเดียวจน Drawdown สะสมสูงมาก |
| **ระยะเวลาถือสถานะ** | ชั่วโมงถึงหลายวัน (ขึ้นอยู่กับว่าราคากลับมาเมื่อไหร่) |
| **เป้าหมาย Win Rate** | 70–80% (Grid ปิดกำไรบ่อย เมื่อ Ranging) |
| **ความเสี่ยง Drawdown สูงสุด** | สูงมาก — 5 Level Martingale Progression ต้องจัดการ MM อย่างระมัดระวัง |
| **Lot Progression** | 1.0 / 1.5 / 2.0 / 3.0 / 4.5 × base_lot |
| **ATR Protection** | ตรวจ H1/D1 Ratio อัตโนมัติทุก Second |
| **Swap Filter** | ตรวจ Carry Cost ก่อนเปิดทุก Level |
| **HiddenTPSL** | Optional — ตั้ง ATR multiple ต่อ Position (Broker ไม่เห็น) |
| **Trailing Stop** | Optional — CTrailingStop เลื่อน SL จริงใน Broker |
| **Emergency Transfer** | รับ Position จาก S16 ได้ผ่าน EmergencyTransferToGrid() |
| **Score Latency** | O(1) หลัง Cache Miss แรก — Cache 1 วินาที |
| **Standalone** | ✅ ต้องการอย่างน้อย 1 CONFIG_PUSH สำหรับ grid_direction |
| **Hot-reload** | ✅ ทุก CONFIG_PUSH ปรับ Grid Params ทันทีโดยไม่ Restart |

---

## 11. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S15_Grid.mqh` | `CS15Grid` — IStrategy Wrapper: MM, HiddenTPSL, Trail, EmergencyTransfer |
| `Include/Logic/Grid/GridCore.mqh` | `CStrategyGrid` — Core Elastic Grid Logic: GetScore(), ExecuteGridOrder(), UpdateFromPolicy() |
| `Include/Logic/Grid/GridState.mqh` | `CGridState` — Position Tracking: UpdateGridState(), ShouldOpenNewGridLevel(), CalculateGridLotSize(), DetermineGridDirection() |
| `Include/Logic/Grid/GridConfig.mqh` | `CGridConfig` — Config + Variables: ApplyDynamicParams(), all m_ members |
| `Include/Logic/Common/HiddenTPSL.mqh` | `CHiddenTPSL` — Virtual TP/SL (Broker ไม่เห็น): SetHiddenTP/SL, CheckAndClose |
| `Include/Logic/Common/TrailingStop.mqh` | `CTrailingStop` — Real Broker SL Trail: Register, Update, SetMethod |
| `Include/Logic/Common/TransferToGrid.mqh` | `TransferToGrid()` utility — Emergency Position Transfer จาก S16 |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager` — MM Selection: SelectMM, SelectMMByRegime |
| `Include/Logic/StrategyConstants.mqh` | `ENUM_STRATEGY_ID`, `MAGIC_S15_GRID=1015`, `g_strategy_table[14]` |
| `Include/Network/Protocol/Definitions.mqh` | `ENUM_GRID_DIRECTION`, `PolicyMessage`, `SDynamicParams` |
| `03_Trader/ProgramC_Trader.mq5` | Main EA: StrategyManager routes Ticks + CONFIG_PUSH → CS15Grid |
| `02_Brain/core/strategy/engine.py` | Python Brain: CSM computation, Grid Direction Decision |
| `02_Brain/core/strategy/policy.py` | PolicyMessage generation + CONFIG_PUSH builder |

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 12.1 ปัญหาหลัก: Martingale Risk ที่ต้องเข้าใจ

**ปัญหา:**
Lot Progression 1→1.5→2→3→4.5× หมายความว่า Total Exposure ที่ Level 4 = 12× base_lot ถ้า base_lot = 0.10 (สำหรับ Account ขนาดกลาง) Total Exposure = 1.20 lot ซึ่งสำหรับ Account $10,000 หมายถึง ~$12 Margin/pip — ถ้าราคาวิ่งออกไป 500 pips = $6,000 drawdown (60% ของ Account!)

**แนวทางแก้ไข:**
1. ใช้ base_lot ที่เล็กพอ: สูตรแนะนำ = Balance × 0.0001 (เช่น $10,000 → base_lot = 0.01)
2. จำกัด MaxLevels ที่ 3-4 สำหรับ Account ขนาดกลาง แทน 5
3. ใช้ MM10 (DrawdownBased) เพื่อลด Lot อัตโนมัติเมื่อ Drawdown เกิน 5%

### 12.2 ปัญหา: CSM Direction Dependency

**ปัญหา:**
Grid จะไม่เปิดเลยถ้า `m_csm_data_received = false` ซึ่งเกิดขึ้นเมื่อ Brain ยังไม่เคยส่ง PolicyMessage มา ถ้า Brain ช้า Startup หรือมีปัญหา Network ช่วงแรก Grid จะ "นิ่งสนิท" แม้ตลาดจะ Ranging สวย

**แนวทางแก้ไข:**
เพิ่ม Local CSM Estimation Mode ใน MQL5 สำหรับกรณี Standalone — คำนวณ Strength จาก iClose ของคู่เงินที่เกี่ยวข้องที่มีอยู่แล้วใน Chart เป็นค่าประมาณ ก่อนจะถูก Override เมื่อ Real CSM จาก Brain มาถึง

### 12.3 ปัญหา: Magic Number Inconsistency

**ปัญหา:**
`GridCore.mqh` ใช้ Hardcoded Magic `999000` ใน `ExecuteGridOrder()` แต่ `CS15Grid` ส่ง Signal ด้วย Magic `1015 (MAGIC_S15_GRID)` ทำให้ `UpdateGridState()` ที่กรองด้วย `magic != 999000` จะ "มองเห็น" ออเดอร์ที่เปิดโดย ExecuteGridOrder แต่ `CS15Grid::GetMagic()` return 1015 ซึ่งใช้ใน Strategy-level operations อื่น

**แนวทางแก้ไข:**
อัปเดต `GridCore.mqh` ให้ใช้ Magic จาก Constructor Parameter แทนค่า Hardcoded ซึ่งจะทำให้ระบบ Consistent ตลอด

### 12.4 ความถี่การ Optimize ที่แนะนำ

| Parameter | ความถี่แนะนำ | เหตุผล |
|-----------|------------|-------|
| grid_direction (CSM) | ทุก 30-60 วินาที | Currency Strength เปลี่ยนบ่อย |
| S15_BASE_STEP | ทุก 1-4 ชั่วโมง | Volatility regime เปลี่ยนช้า |
| S15_ATR_RATIO | ทุกวัน | ขึ้นอยู่กับ Market Cycle |
| S15_MAX_ORDERS | ทุกสัปดาห์ | ขึ้นอยู่กับ Account Performance |
| S15_CONF_THRESHOLD | ทุก 4-8 ชั่วโมง | ปรับตาม Market Condition |

---

## 13. การวินิจฉัยระบบ (Quick Diagnostics)

### 13.1 ตรวจสอบ S15 ทำงานอยู่หรือไม่ (EA Log)

```
ค้นหาใน Expert Journal: "[S15]" และ "[Grid]"

ปกติควรเห็น:
  [S15] Grid initialized | Symbol=EURUSD TF=PERIOD_H1 MaxLevels=5
  [Grid] Phase 3.5 + 3.6 Initialized
  [Grid]   ATR Ratio Protection: Active
  [Grid]   ATR Ratio Threshold: 0.80
  [Grid]   Swap Filter: Enabled
  [Grid] Updated from Policy:
  [Grid]   Symbol: EURUSD
  [Grid]   Direction: BUY
  [Grid]   Confidence: 0.72
  [Grid] ATR regime check passed | Ratio: 0.683 (OK < 0.80)
  [Grid] Swap filter passed | Direction: BUY | Swap Long: 0.42 (POSITIVE)
  [Grid] Opened Grid Level 0 | Type: BUY | Lot: 0.01 | Price: 1.08200
```

### 13.2 Print S15 Diagnostics จาก EA

```mql5
CS15Grid* s15 = GetStrategy(S15_GRID);
s15.PrintDiagnostics();

// Output:
// [S15] Grid | Symbol=EURUSD | MaxLevels=5 | ActiveLevels=2
// [S15] Signal=BUY | Confidence=0.7350 | RiskMult=1.00
// [S15] MM=Kelly | ActiveMM=MM03_Kelly
// [S15] HiddenTPSL=2 tracked | Trail=0 tracked | TP×2.0 SL×1.5
```

### 13.3 ตรวจสอบ CONFIG_PUSH มี S15 หรือไม่

```bash
python tools/validate_live_readiness.py --zmq
# ควรเห็น:
# S15_MAX_ORDERS, S15_BASE_STEP, S15_ELASTIC_FACTOR,
# S15_CONF_THRESHOLD, S15_ATR_RATIO, S15_SWAP_FILTER,
# grid_direction (1=BUY, 2=SELL), confidence, risk_multiplier
```

### 13.4 ตรวจสอบ CSM Data

```bash
python -c "
from core.strategy.engine import StrategyEngineThreaded
e = StrategyEngineThreaded()
csm = e.get_latest_csm('EURUSD')
print('USD:', csm['usd'])
print('EUR:', csm['eur'])
print('Diff:', csm['usd'] - csm['eur'])
print('Direction:', 'SELL' if csm['usd']-csm['eur']>0.1 else 'BUY' if csm['usd']-csm['eur']<-0.1 else 'NONE')
"
```

### 13.5 ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| Grid ไม่เปิด Level ใดๆ เลย | `m_csm_data_received=false` — ไม่เคยรับ PolicyMessage | ตรวจ Brain Connection และ Port 7778 |
| ATR Regime บล็อกตลอด | ตลาดกำลัง Trend จริงๆ | อย่าแก้ Threshold — รอ Ranging หรือลด `S15_ATR_RATIO` ผ่าน CONFIG_PUSH |
| Swap Filter บล็อกตลอด | Symbol มี Negative Swap ในทิศทางนั้น | Disable `S15_SWAP_FILTER=0` หรือเปลี่ยน Symbol |
| Level เปิดเยอะเกินไป | `S15_MAX_ORDERS` สูงเกิน หรือ Elastic Step เล็กเกิน | ลด `S15_MAX_ORDERS` หรือเพิ่ม `S15_BASE_STEP` |
| Grid ค้างเปิดนานมาก | ตลาด Trend ต่อเนื่อง ไม่ยอมกลับ | ตรวจ ATR Ratio — ถ้า Ratio สูงควรบล็อกแต่ไม่ได้บล็อก ตรวจ Threshold |
| HiddenTPSL ไม่ปิดออเดอร์ | `S15_TP_ATR_MULT=0` (default) | ตั้ง `S15_TP_ATR_MULT` เป็น 2.0-3.0 ผ่าน CONFIG_PUSH |
| Standalone ทำงานได้แต่ Grid ไม่เปิด | ไม่เคยรับ PolicyMessage ก่อน Brain Offline | ระบบ Designed นี้ — ต้องรับ 1 CONFIG_PUSH ก่อน Offline |
| Confidence ต่ำกว่า 0.3 เสมอ | CSM Diff ไม่ชัดเจน (ตลาดอ่อนแอ) | รอ CSM Direction ชัดขึ้น หรือลด `S15_CONF_THRESHOLD` |

---

### 13.6 ตัวอย่าง Log เมื่อ ATR Regime บล็อก

```
[Grid] 🛡️ ATR REGIME PROTECTION ACTIVE
   ATR H1: 0.00160
   ATR D1: 0.00150
   Ratio: 1.067 (threshold: 0.80)
   🚫 Grid disabled - possible trend regime detected

→ การกระทำที่ถูกต้อง: รอให้ตลาดกลับสู่ RANGING
→ ห้ามเพิ่ม Threshold โดยพลการ เพราะจะเปิด Grid ในตลาด Trend
→ ถ้าต้องการให้ Grid ทำงานในสภาวะ Volatile มากกว่านี้:
   ส่ง CONFIG_PUSH: S15_ATR_RATIO=0.9 และตรวจสอบผลอย่างระมัดระวัง
```

---

*S15 Immortal Grid — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kukanok*
