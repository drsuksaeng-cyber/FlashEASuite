# FlashEASuite V2 — Backtest Plan: All Pairs × All TF
**Date:** 2026-03-03
**Scope:** 7 Standalone Strategies × 12 Symbols × 7 Timeframes
**Tool:** MetaTrader 5 Strategy Tester

---

## Overview

### 7 Standalone Strategies (รันได้โดยไม่ต้องมี Python Brain)
| # | Enum | Magic | Best Regime | Opt EA |
|---|------|-------|-------------|--------|
| 1 | S01_STAT_ARB | 1001 | RANGING | ต้องสร้าง |
| 2 | S06_KAMA | 1006 | TRENDING | ต้องสร้าง |
| 3 | S07_MEAN_REVERSION | 1007 | RANGING | **Opt_S07_MeanRev.ex5** ✅ |
| 4 | S10_TURTLE | 1010 | TRENDING | ต้องสร้าง |
| 5 | S14_BB_SQUEEZE | 1014 | SQUEEZE | ต้องสร้าง |
| 6 | S15_GRID | 1015 | RANGING | ต้องสร้าง |
| 7 | S16_SPIKE | 1016 | VOLATILE | **Opt_S16_Spike.ex5** ✅ |

### 12 Symbols (จาก ALLOWED_SYMBOLS)
```
EURUSD  GBPUSD  USDJPY  XAUUSD
EURJPY  GBPJPY  AUDJPY  NZDJPY
GBPAUD  AUDCAD  AUDUSD  NZDUSD
```
*หมายเหตุ: เพิ่ม broker suffix ให้เหมาะกับ broker (เช่น .tp, _m)*

### 7 Timeframes
```
M5   M15   M30   H1   H4   D1   W1
```
*(M1 ข้ามเพราะ noise สูง และ commission cost สูง — เพิ่มได้ถ้าต้องการ)*

---

## Phase A — Single Strategy Backtest (Validation)

**เป้าหมาย:** ยืนยันว่าแต่ละ strategy ทำงานถูกต้องและมี edge บน best regime ของตัวเอง

### A.1 S07 Mean Reversion (มี Opt EA แล้ว)
```
EA:      Tester/Opt_S07_MeanRev.ex5
Period:  2022-01-01 to 2024-12-31 (3 ปี)
Mode:    Every tick based on real ticks
Deposit: 10,000 USD

Priority runs (Best Regime = RANGING):
  Symbol  × TF     → จำนวน combinations
  -------   -----
  EURUSD  × M15    ← แนะนำ #1
  EURUSD  × H1
  GBPUSD  × M15
  GBPUSD  × H1
  USDJPY  × H1
  XAUUSD  × H1     ← สำคัญ
  AUDUSD  × M15
  NZDUSD  × H1

Criterion: score = PF × WinRate × sqrt(Trades) / MaxDD%
Min bars:  Trades >= 30, PF >= 1.0, MaxDD <= 30%
```

### A.2 S16 Spike Hunter (มี Opt EA แล้ว)
```
EA:      Tester/Opt_S16_Spike.ex5
Period:  2022-01-01 to 2024-12-31
Mode:    Every tick based on real ticks

Priority runs (Best Regime = VOLATILE):
  XAUUSD  × M5     ← แนะนำ #1 (volatile ที่สุด)
  XAUUSD  × M15
  GBPJPY  × M5     ← high volatility pair
  GBPJPY  × M15
  EURJPY  × M5
  USDJPY  × M15
  GBPUSD  × M5
```

### A.3 S15 Grid (ต้องสร้าง Opt EA)
```
File:    Tester/Opt_S15_Grid.mq5  ← ต้องสร้างใหม่ (template จาก Opt_S07)
Regime:  RANGING
Pairs:   EURUSD, AUDCAD, AUDUSD, NZDUSD
TF:      H1, H4 (Grid ทำงานดีบน higher TF)
Period:  2022-01-01 to 2024-12-31
```

---

## Phase B — Full Matrix Backtest

**เป้าหมาย:** ทดสอบ strategy แต่ละตัวบน ทุก pair × ทุก TF เพื่อหา optimal combination

### B.1 Matrix Dimensions
```
7 Strategies × 12 Symbols × 7 TF = 588 combinations
```

### B.2 Priority Matrix (สำคัญที่สุดก่อน)

**Tier 1 — Core Pairs × Best TF per Strategy (56 runs)**
| Strategy | Pairs | TF | Reason |
|----------|-------|----|--------|
| S07_MEAN_REVERSION | EURUSD,GBPUSD,AUDUSD,NZDUSD | M15,H1 | Best ranging pairs |
| S16_SPIKE | XAUUSD,GBPJPY,EURJPY | M5,M15 | Most volatile |
| S06_KAMA | EURUSD,USDJPY,GBPUSD | H1,H4 | Trending pairs |
| S10_TURTLE | XAUUSD,USDJPY,EURUSD | H4,D1 | Turtle = long-term trend |
| S14_BB_SQUEEZE | EURUSD,XAUUSD | H1,H4 | Squeeze breakout |
| S15_GRID | EURUSD,AUDUSD,AUDCAD | H1,H4 | Ranging market |
| S01_STAT_ARB | EURUSD/GBPUSD,AUDUSD/NZDUSD | H1 | Correlated pairs |

**Tier 2 — Full Symbol Sweep per Strategy (84 runs)**
```
Each of 7 strategies × 12 symbols × 1 "home TF"
```

**Tier 3 — Full TF Sweep per Strategy (84 runs)**
```
Each of 7 strategies × 12 symbols × 7 TF = 588 total
```

---

## Phase C — Backtest Settings (Standard)

```
Period:       2022-01-01 to 2024-12-31  (3 ปี = ครอบ COVID recovery + rate hikes)
Deposit:      10,000 USD
Leverage:     1:100
Commission:   7 USD/lot (standard)
Spread:       Symbol spread (real)
Mode:         Every tick based on real ticks (สำคัญที่สุด)
Optimization: Custom max (OnTester score)
```

### Scoring Function (OnTester)
```
score = ProfitFactor × WinRate × sqrt(Trades) / MaxDrawdown_pct

Conditions:
  - Trades >= 30    (statistical significance)
  - PF >= 1.0       (มี edge)
  - MaxDD <= 30%    (ความเสี่ยงรับได้)
  - WinRate >= 0.3  (ไม่ต้องสูงมาก ถ้า RR ดี)
```

---

## Phase D — Performance Metrics Template

สำหรับแต่ละ run ให้บันทึก:

| Metric | Target | Description |
|--------|--------|-------------|
| Net Profit | > 0 | กำไรสุทธิ |
| Profit Factor | ≥ 1.3 | กำไร/ขาดทุน ratio |
| Max Drawdown % | ≤ 20% | Max ที่รับได้ = 20% |
| Win Rate | ≥ 35% | (ต่ำก็ได้ถ้า RR ≥ 2) |
| # Trades | ≥ 30 | สำหรับ statistical significance |
| Recovery Factor | ≥ 2.0 | Net Profit / MaxDD |
| Sharpe-like | ≥ 1.0 | Custom = score function |
| Avg Trade | > commission | ทุก trade ต้องคุ้ม |

---

## Phase E — Backtest Execution Plan (Step by Step)

### Step 1: Setup Opt EAs ที่ยังขาด (Priority)
```
สร้าง:
  Tester/Opt_S06_KAMA.mq5
  Tester/Opt_S10_Turtle.mq5
  Tester/Opt_S14_BBSqueeze.mq5
  Tester/Opt_S15_Grid.mq5
  Tester/Opt_S01_StatArb.mq5

Template: ใช้ Opt_S07_MeanRev.mq5 เป็น base
แค่เปลี่ยน: include path, strategy class name, magic number, TF recommendation
```

### Step 2: Tier 1 Runs (ทำก่อน — 2-3 ชั่วโมง)
```
Priority order:
1. S07 × EURUSD × H1      (baseline ranging)
2. S16 × XAUUSD × M15     (baseline spike)
3. S06 × EURUSD × H4      (baseline trending)
4. S10 × XAUUSD × D1      (baseline turtle)
5. S15 × EURUSD × H4      (baseline grid)
```

### Step 3: Symbol Sweep (Tier 2)
```
ใช้ parameters จาก Tier 1 ที่ดีที่สุด
รัน 12 symbols × H1 ต่อ strategy
```

### Step 4: TF Sweep (Tier 3)
```
ใช้ top 3 symbols จาก Step 3
รัน 7 TF ต่อ symbol × strategy
```

### Step 5: Collect Results
```
Export: strategy tester report (HTML)
Script: tools/generate_test_report.py (มีอยู่แล้ว)
```

---

## Phase F — Backtest Risk Validation

สำหรับทุก configuration ที่ผ่าน Phase D targets:

```
1. Walk-forward test (WFT)
   - Train: 2022-2023 (2 ปี)
   - Test:  2024 (1 ปี out-of-sample)
   - Pass: out-of-sample PF >= 1.0

2. Robustness check
   - เพิ่ม spread 2x → ยัง profit?
   - เปลี่ยน commission +50% → ยัง profit?

3. Worst-case stress
   - ช่วง volatile สุด: Mar 2020, Mar 2022 (rate hike)
   - DD ในช่วง stress <= 30%

4. Monte Carlo (optional)
   - shuffle trade order 1000 ครั้ง
   - 95th percentile DD <= 35%
```

---

## Phase G — Expected Timeline

| Step | Task | เวลาโดยประมาณ |
|------|------|---------------|
| G1 | สร้าง Opt EAs ที่ขาด (5 ตัว) | 1-2 ชั่วโมง |
| G2 | Tier 1: S07+S16 baseline | 2-4 ชั่วโมง |
| G3 | Tier 1: S06+S10+S15 | 3-5 ชั่วโมง |
| G4 | Tier 2: Symbol sweep (7 strats × 12 pairs) | 1-2 วัน |
| G5 | Tier 3: TF sweep (top pairs) | 1-2 วัน |
| G6 | Walk-forward + robustness | 1 วัน |
| G7 | Compile results + report | 2-4 ชั่วโมง |

**Total: ~4-6 วัน** (ขึ้นอยู่กับ PC speed + data availability)

---

## Phase H — Symbols by Category (Priority Score)

### High Priority (Volatility + Liquidity ดีที่สุด)
```
XAUUSD  — Best for S16 Spike, S07 Mean Reversion
EURUSD  — Best for S06 KAMA, S07, S15 Grid
GBPUSD  — Good trending + ranging
USDJPY  — Trending, session breakout
```

### Medium Priority
```
GBPJPY  — High volatility, good for Spike
EURJPY  — Trending + volatile
AUDUSD  — Ranging, correlated with AUD
NZDUSD  — Similar to AUDUSD
```

### Lower Priority (เพิ่มเติม)
```
AUDJPY  — Volatile JPY cross
NZDJPY  — Volatile JPY cross
GBPAUD  — Very volatile, wide spread
AUDCAD  — Ranging, commodity pair
```

---

## Checklist ก่อนเริ่ม Backtest

- [ ] ติดตั้ง FlashEASuite V2 ใน MT5 ถูก directory
- [ ] ดาวน์โหลด historical data ทุก pair (Tools > History Center หรือ auto)
- [ ] ตรวจสอบ broker suffix ใน EA parameters (SYMBOL_SUFFIX = ".tp" ?)
- [ ] ตั้งค่า deposit = 10,000 USD, leverage 1:100
- [ ] เลือก "Every tick based on real ticks" เท่านั้น
- [ ] Export template .set file สำหรับแต่ละ strategy
- [ ] สร้าง Opt EAs ที่ขาด (G1)
- [ ] เตรียม spreadsheet สำหรับบันทึกผล

---

## Files Required

```
Tester/
  Opt_S07_MeanRev.ex5      ✅ มีแล้ว
  Opt_S16_Spike.ex5        ✅ มีแล้ว
  Opt_S06_KAMA.ex5         ❌ ต้องสร้าง
  Opt_S10_Turtle.ex5       ❌ ต้องสร้าง
  Opt_S14_BBSqueeze.ex5    ❌ ต้องสร้าง
  Opt_S15_Grid.ex5         ❌ ต้องสร้าง
  Opt_S01_StatArb.ex5      ❌ ต้องสร้าง (อาจซับซ้อน)
```

---

*Generated by Claude Sonnet 4.6 | FlashEASuite V2 Full System Test 2026-03-03*
