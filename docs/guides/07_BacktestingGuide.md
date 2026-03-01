# FlashEASuite V2 — Backtesting Guide

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01

---

## 1. Backtesting Overview

FlashEASuite V2 strategies ทดสอบได้ 2 โหมด:

| Mode | ใช้เมื่อ | Tool |
|------|---------|------|
| **Standalone Backtest** | ทดสอบ strategy เดี่ยวๆ โดยไม่ต้องใช้ Brain | MT5 Strategy Tester |
| **Brain-Integrated (Simulation)** | ทดสอบทั้งระบบ Brain+Trader | Python + MT5 (ซับซ้อนกว่า) |

> ⚠️ **สำหรับ Standalone Backtest ให้ปิด Brain connection ก่อนเสมอ** (`InpEnableServer = false`)
> Brain ไม่สามารถส่ง tick data ให้ Strategy Tester ได้ใน real-time

---

## 2. MT5 Strategy Tester — Quick Start (5 นาที)

### เปิด Strategy Tester

```
Ctrl+R
หรือ: View → Strategy Tester
```

### ตั้งค่าพื้นฐาน

| Field | Value | Notes |
|-------|-------|-------|
| Expert Advisor | `ProgramC_Trader` | หรือ Tester EA เฉพาะ |
| Symbol | `XAUUSD` | เปลี่ยนตาม strategy |
| Period | `M15` | ปรับตาม strategy timeframe |
| Date from | `2024.01.01` | อย่างน้อย 3 เดือน |
| Date to | `2024.12.31` | |
| Model | `Every tick based on real ticks` | แนะนำ (ช้ากว่าแต่แม่นกว่า) |
| Deposit | `5000` | USD |
| Leverage | `1:100` | ตรงกับ broker |

### ตั้งค่า Inputs (Expert Properties)

```
1. คลิก "Expert properties" (หรือ double-click EA ใน Tester)
2. Tab: Inputs

สำหรับ Standalone mode:
  InpEnableServer  = false    ← ต้องปิด! ห้ามลืม
  InpMagicNumber   = 999000   ← ค่า default
  InpUserMaxRisk   = 1.0      ← % risk per trade
  SYMBOL_SUFFIX    = (ว่าง)   ← ไม่มี suffix ใน Tester
```

### Run

```
กดปุ่ม "Start"
รอ progress bar เต็ม (2–30 นาที ขึ้นอยู่กับ date range และ model)
```

---

## 3. Tester Files (ทดสอบเฉพาะ Strategy)

มี Tester EA สำเพาะสำหรับแต่ละชุด strategies:

| File | ทดสอบ | Location |
|------|--------|----------|
| `TestSpikeStrategy.mq5` | S16_SPIKE standalone | `Tester/` |
| `Opt_S07_MeanRev.mq5` | S07 with optimization | `Tester/` |
| `Opt_S16_Spike.mq5` | S16 with optimization | `Tester/` |
| `TestP2_4_AllStrategies.mq5` | All strategies in council | `Tester/` |
| `TestP2_3_GridSpike.mq5` | Grid + Spike combined | `Tester/` |
| `Test_P1_1_Strategies.mq5` | Phase 1 strategy set | `Tester/` |
| `Test_P6_3_GridSpike_Integration.mq5` | Grid+Spike integration | `Tester/` |
| `test_TrailingStop.mq5` | Trailing stop behavior | `Tester/` |
| `test_HiddenTPSL.mq5` | Hidden TP/SL behavior | `Tester/` |

Compile Tester file ก่อนใช้:
```
MetaEditor → Navigator → Tester → [file name] → F7 → 0 errors
```

---

## 4. Interpreting Results

### Tab: Report — Key Metrics

| Metric | Good ✅ | Average ⚠️ | Bad ❌ |
|--------|---------|-----------|-------|
| **Net Profit** | > +10% | +5–10% | < +5% หรือ negative |
| **Profit Factor** | > 2.0 | 1.5–2.0 | < 1.5 |
| **Max Drawdown** | < 12% | 12–15% | > 15% |
| **Win Rate** | > 60% | 55–60% | < 55% |
| **Sharpe Ratio** | > 1.5 | 1.0–1.5 | < 1.0 |
| **Recovery Factor** | > 3.0 | 2.0–3.0 | < 2.0 |
| **Total Trades** | > 100 | 50–100 | < 50 (insufficient data) |

### Tab: Graph — Visual Analysis

```
Balance curve (green):  ควรขึ้น steady ไม่ขึ้น-ลง volatile
Equity curve (blue):    ควรใกล้เคียง balance curve
Drawdown (red):         ควรต่ำ ไม่มี spike ลึก
```

**Red flags:**
- Balance curve ขึ้นแบบ step-function (เทรดน้อยเกิน)
- Drawdown spike ลึกมากแล้วฟื้น (lucky recovery, not stable)
- Last portion ของ equity graph ลงต่อเนื่อง (strategy breaking down)

---

## 5. Target Performance Benchmarks

### Per Strategy Benchmarks

| Strategy | Target Win Rate | Target Profit Factor | Best Timeframe | Best Symbol |
|----------|----------------|---------------------|----------------|-------------|
| S06_KAMA | > 55% | > 1.8 | H1, H4 | EURUSD, GBPUSD |
| S07_MEAN_REV | > 60% | > 2.0 | M15, H1 | XAUUSD, GBPUSD |
| S10_TURTLE | > 45% | > 2.5 | H4, D1 | EURUSD, USDJPY |
| S14_BB_SQUEEZE | > 55% | > 1.8 | H1 | XAUUSD, EURUSD |
| S15_GRID | > 70% | > 1.5 | M15, H1 | XAUUSD, EURUSD |
| S16_SPIKE | > 65% | > 2.0 | M1, M5 | XAUUSD, GBPUSD |

### System-Wide Targets

```
Annual Return:       > 80–150%
Max Drawdown:        < 15%
Sharpe Ratio:        > 1.5
Profit Factor:       > 2.0
Win Rate:            > 55%
Calmar Ratio:        > 3.0 (Return / Max DD)
```

---

## 6. Backtesting Best Practices

### Test Period Guidelines

| Period | Purpose | Min Trades |
|--------|---------|-----------|
| 1 month | Quick sanity check | > 20 |
| 3 months | Seasonal validation | > 60 |
| **1 year** | **Standard test** | **> 200** |
| 3–5 years | Robustness check | > 500 |

### Walk-Forward Testing (WFT)

Walk-forward prevents overfitting — optimize on in-sample, test on out-of-sample:

```
Total period: 24 months
In-sample:    18 months (optimize parameters here)
Out-sample:   6 months  (test on unseen data)

Repeat rolling: shift by 3 months each time
```

**Manual WFT in MT5:**
```
Run 1: Optimize 2022.01–2023.06 → Get best params → Test 2023.07–2023.12
Run 2: Optimize 2022.07–2024.01 → Get best params → Test 2024.01–2024.06
...
```

### Monte Carlo Simulation

After standard backtest, validate robustness:
1. Export trade list from MT5 Report tab
2. Randomly shuffle trade order 1000 times
3. Calculate drawdown distribution
4. If 95th percentile DD < 25% → strategy is robust

---

## 7. Optimization (Strategy Tester)

### Parameter Optimization

```
1. Strategy Tester → ตั้งค่า EA + Symbol + Date
2. Tab: Inputs → ระบุ parameter ranges

Example for S07_MEAN_REVERSION:
  RSI_PERIOD:  Min=10, Max=20, Step=1
  BB_PERIOD:   Min=15, Max=30, Step=5
  ATR_MULT:    Min=1.0, Max=2.5, Step=0.5

3. Optimization:
   Criterion: Max Profit Factor (แนะนำ)
   หรือ: Max Sharpe Ratio (ดีกว่าสำหรับ risk management)

4. Start optimization
```

> ⚠️ **WARNING S16_SPIKE:** ห้าม optimize S16 ใน backtest รัน batch ใหญ่ — memory leak (11,520 bytes/run) จะทำให้ MT5 crash ใน optimization ที่มีหลาย iterations

### Optimization Pitfalls to Avoid

| Pitfall | Risk | Prevention |
|---------|------|-----------|
| Over-optimization ("curve fitting") | Works on past, fails on future | Use WFT validation |
| Too many parameters | Overfit complex surface | Max 3–4 parameters at once |
| Optimize on single symbol | Not robust | Test on multiple symbols |
| Optimize on short period | Period-specific | Minimum 1 year |
| Use optimization results directly | Will fail live | Always out-sample validate |

### Recommended Optimization Objective

```
Best: Profit Factor (Gross Profit / Gross Loss)
  → Balances wins vs losses

Alternative: Custom (Sharpe Ratio)
  → Better for risk-adjusted return

Avoid: Max Profit only
  → Ignores drawdown
```

---

## 8. Strategy-Specific Backtest Settings

### S07 — Mean Reversion

```
Symbol:   XAUUSD, GBPUSD
Period:   M15 or H1
Date:     At least 1 year of RANGING periods
Input settings:
  InpEnableServer = false
  RSI_PERIOD      = 14
  BB_PERIOD       = 20
  BB_DEVIATION    = 2.0
  ATR_MULT        = 1.5

Expect: Win rate 60–70%, trades only in ranging conditions
```

### S15 — Grid

```
Symbol:   XAUUSD, EURUSD
Period:   M15
Date:     Include volatile periods (2024 good)
Input settings:
  InpEnableServer   = false
  GRID_MAX_ORDERS   = 5
  GRID_BASE_STEP    = 200
  GRID_LOT_MULT     = 1.5
  GRID_TP_POINTS    = 150

Expect: High win rate (70%+), but large drawdowns during trends
```

### S16 — Spike

```
Symbol:   XAUUSD, GBPUSD (most spiky)
Period:   M1 or M5
Date:     Include news event periods (FOMC, NFP)
Input settings:
  InpEnableServer   = false
  SPIKE_THRESHOLD   = 70.0
  HOLD_MINUTES      = 5

⚠️ Single backtest only — NO optimization loops!
Expect: Short hold time, high win rate during volatile days
```

### S10 — Turtle

```
Symbol:   EURUSD, USDJPY, XAUUSD
Period:   H4 or D1
Date:     3–5 years (needs full trend cycles)
Input settings:
  InpEnableServer   = false
  ENTRY_PERIOD      = 20
  EXIT_PERIOD       = 10
  ATR_PERIOD        = 14
  MAX_UNITS         = 4

Expect: Low win rate (40–50%) but high avg R:R (2.5–5.0)
```

---

## 9. Backtest → Demo → Live Progression

### Stage 1: Backtest (MT5 Strategy Tester)

- **Goal:** Verify strategy logic + parameter ranges
- **Period:** 1 year minimum
- **Pass criteria:** PF > 2.0, Max DD < 15%, Win Rate > 55%
- **Duration:** 1–2 days of testing

### Stage 2: Demo Trading

- **Goal:** Verify real-time behavior with live feeds
- **Period:** 1–4 weeks
- **What to watch:** Slippage, spread impact, overnight swaps
- **Pass criteria:** Results similar to backtest (within ±20%)
- **Duration:** Minimum 1 week (recommended 2–4 weeks)

### Stage 3: Live Trading (small lot)

- **Goal:** Verify execution with real money behavior
- **Start:** Minimum lot (0.01)
- **Period:** 1–2 months
- **What to watch:** Execution fills, psychological stability
- **Escalation:** Increase lot only after 1+ month consistent results

---

## 10. Common Backtest Problems

| Problem | Likely Cause | Solution |
|---------|-------------|---------|
| All trades WIN with huge profit | `InpEnableServer` not set to false | Set it to false, re-run |
| No trades at all | Wrong symbol or `InpMagicNumber` conflict | Check params, verify symbol |
| Excellent backtest, poor live | Overfitting or spread not accounted | Add spread in properties, use WFT |
| MT5 crash during optimization | S16 memory leak | Don't optimize S16, test single run |
| Compile error on Tester file | #include path issue | Open from Navigator, not Explorer |
| Very few trades (< 20) | Test period too short | Extend to 1 year minimum |
| Profit Factor exactly 1.0 | Strategy never losses but never profits | Check TP/SL logic |

---

## 11. Saving and Exporting Results

### Save Backtest Report

```
Strategy Tester → Report tab
Right-click → Save as Report
→ Saves as .html file
```

### Export Trade List

```
Report tab → Right-click → Print
→ Use PDF printer to save as PDF
```

### Compare Multiple Tests

Keep a spreadsheet tracking:
```
Date | Strategy | Symbol | TF | Period | Trades | WinRate | PF | MaxDD | Notes
```

---

*FlashEASuite V2 Backtesting Guide — V6 P9-5 | 2026-03-01*
