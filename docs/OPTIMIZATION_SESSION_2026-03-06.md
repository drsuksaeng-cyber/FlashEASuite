# Optimization Session — 2026-03-06
## Brain Pre-Optimizer → MT5 Strategy Tester Pipeline

---

## งานที่เสร็จแล้ววันนี้

### 1. Brain Pre-Optimizer — Bug Fixes

| Fix | ไฟล์ | รายละเอียด |
|-----|------|------------|
| `fixed_from_params` pattern | `setfile_generator.py` | ย้าย SL/TP จาก optimised → fixed → S14: 2500→100 passes, S06: 625→25, S15: 1600→100 |
| S14 MinConfidence | `setfile_generator.py` | `Inp_MinConfidence=0.0` (เดิม 0.4 บล็อกทุก trade) |
| S14 Breakout_Mom | `setfile_generator.py` | `BS_Breakout_Mom=0.1` (เดิม 0.5 ต้องการ $175 linear move) |
| TP≥SL constraint | `pre_optimizer.py` | เพิ่ม constraint S06/S14 ป้องกัน Brain แนะนำ TP < SL |

---

### 2. S14 BBSqueeze — XAUUSD H1 ✅ DONE

**3 rounds | 2022–2024 | Deposit $10,000**

| Param | Value |
|-------|-------|
| BS_BB_Period | **25** |
| BS_KC_ATR_Mult | **1.15** |
| BS_Squeeze_Min | **6** |
| BS_SL_ATR_Mult | 3.4 (fixed) |
| BS_TP_ATR_Mult | 3.4 (fixed) |
| BS_Breakout_Mom | 0.1 (fixed) |
| Inp_MinConfidence | 0.0 |

| Metric | Value |
|--------|-------|
| Custom | **5.1855** |
| Profit | $649 |
| PF | 1.863 |
| DD% | 2.36% |
| Trades/3y | 23 |

**Bugs fixed in `S14_BBSqueeze.mqh`:**
- Signal persistence: `m_was_in_squeeze` reset ทุก tick → เพิ่ม `m_last_bar_time` guard
- Breakout_Mom default: 0.5 → 0.1
- MinConfidence=0.4 blocked all trades → 0.0 ใน standalone .set

**Final .set:** `S14_XAUUSD_H1_FINAL.set`

---

### 3. S10 Turtle — XAUUSD H4 ✅ DONE

**5 rounds (H1 failed → switched H4) | 2022–2024**

| Param | Value |
|-------|-------|
| Turtle_EntryPeriod | **15** |
| Turtle_ExitPeriod | **30** |
| Turtle_BreakoutBuf | 0.10 (fixed) |
| Turtle_MaxUnits | 4 (fixed) |
| Inp_RiskPct | **0.5%** (fixed) |

| Metric | Value |
|--------|-------|
| Custom | **0.1027** |
| Profit | $1,184 |
| PF | 1.384 |
| DD% | 23.7% |
| Trades/3y | 84 |

**Key lessons:**
- H1 unsuitable: EntryPeriod=34–40 bars H1 = 1.5 days → DD=78–91%
- MaxUnits=1 kills strategy: pyramid IS the profit mechanism (PF=0.12 without)
- RiskPct=1% → DD=44%, 0.5% → DD=23.7% (passes ≤30% filter)
- ExitPeriod=30 >> Entry period (wide exit channel critical)
- Turtle WR=15–20% by design → removed WinRate filter from `Opt_S10_Turtle.mq5`

**Final .set:** `S10_XAUUSD_H4_FINAL.set`

---

### 4. S06 KAMA — USDJPY H4 ✅ DONE

**3 rounds (XAUUSD H1 failed → switched USDJPY H4) | 2022–2024**

| Param | Value |
|-------|-------|
| KAMA_Period | **13** |
| KAMA_ER_Thresh | **0.90** |
| KAMA_TP_ATR | 4.7 (fixed) |
| KAMA_SL_ATR | 2.3 (fixed) |
| Inp_UseKAMAExit | true |

| Metric | Value |
|--------|-------|
| Custom | **17.2325** |
| Profit | $391 |
| PF | 3.274 |
| DD% | 1.24% |
| Trades/3y | 54 |

**Key lessons:**
- XAUUSD H1: 150–330 trades/yr, PF<1 ทุก pass → overtrade
- ER≥0.90 critical: เลือก trade เฉพาะ trend แข็งแกร่ง 90%+
- USDJPY trends cleanly vs XAUUSD volatile
- Removed WinRate filter from `Opt_S06_KAMA.mq5`

**Final .set:** `S06_USDJPY_H4_FINAL.set`

---

### 5. S14 BBSqueeze — GBPUSD H1 ✅ DONE

**4 rounds | 2022–2024**

| Param | Value |
|-------|-------|
| BS_BB_Period | **48** |
| BS_KC_ATR_Mult | **1.50** |
| BS_Squeeze_Min | **4** |
| BS_SL_ATR_Mult | 2.5 (fixed) |
| BS_TP_ATR_Mult | 4.5 (fixed) |

| Metric | Value |
|--------|-------|
| Custom | **4.3609** |
| Profit | $1,810 |
| PF | 2.752 |
| DD% | 4.01% |
| Trades/3y | 25 |

**Note:** BB=48 vs XAUUSD BB=25 — GBPUSD volatility ต่ำกว่า ต้องการ BB กว้างกว่ามาก

**Final .set:** `S14_GBPUSD_H1_FINAL.set`

---

### 6. S15 Grid — EURUSD H1 ⛔ SKIP

**สาเหตุ:** `GridCore.GetScore()` depend on Brain signals:
- `m_csm_data_received` (Brain CONFIG_PUSH flag)
- `m_current_direction` (Brain กำหนด direction)
- `m_python_confidence` (Brain confidence)

ไม่มี Brain → score=0 ทุก tick → Trades=0 ทุก 100 passes

**แนวทางแก้ (future):** เพิ่ม standalone signal mode ใน GridCore (ใช้ RSI/MACD เป็น fallback)

---

### 7. .mqh Input Defaults Updated

| File | Before | After |
|------|--------|-------|
| `S06_KAMA.mqh` | Period=25, ER=0.5, TP=3.0, SL=1.5 | Period=13, ER=0.90, TP=4.7, SL=2.3 |
| `S10_Turtle.mqh` | Entry=20, Exit=20, Risk=1.0% | Entry=15, Exit=30, Risk=0.5% |
| `S14_BBSqueeze.mqh` | BB=20, KC=1.5, SL=2.0, TP=3.0 | BB=25, KC=1.15, SL=3.4, TP=3.4 |

---

### Optimization Results Summary

| Strategy | Symbol | TF | Custom | PF | DD% | Trades/3y |
|----------|--------|----|--------|----|-----|-----------|
| S06 KAMA | USDJPY | H4 | 17.23 | 3.274 | 1.24% | 54 |
| S14 BBSqueeze | XAUUSD | H1 | 5.19 | 1.863 | 2.36% | 23 |
| S14 BBSqueeze | GBPUSD | H1 | 4.36 | 2.752 | 4.01% | 25 |
| S10 Turtle | XAUUSD | H4 | 0.103 | 1.384 | 23.7% | 84 |
| S01 StatArb | GBPUSD | H1 | — | — | — | SKIP (HYBRID) |
| S15 Grid | EURUSD | H1 | — | — | — | SKIP (Brain-dep) |

---

## แผนงานพรุ่งนี้ (2026-03-07)

### ลำดับที่ 1 — Validation Backtest (สำคัญที่สุด)

รัน single backtest (ไม่ optimize) ด้วย FINAL.set แต่ละตัว เพื่อยืนยันผลก่อน deploy:

| Strategy | EA | Symbol | TF | .set file |
|----------|----|--------|----|-----------|
| S06 | Opt_S06_KAMA | USDJPY.tp | H4 | `S06_USDJPY_H4_FINAL.set` |
| S10 | Opt_S10_Turtle | XAUUSD.tp | H4 | `S10_XAUUSD_H4_FINAL.set` |
| S14 | Opt_S14_BBSqueeze | XAUUSD.tp | H1 | `S14_XAUUSD_H1_FINAL.set` |
| S14 | Opt_S14_BBSqueeze | GBPUSD.tp | H1 | `S14_GBPUSD_H1_FINAL.set` |

ตรวจสอบ: Profit > 0, PF ≥ expected, DD ≤ threshold, Trades ≥ expected

---

### ลำดับที่ 2 — Walk-Forward Test (optional แต่แนะนำ)

| Train | Test | วัตถุประสงค์ |
|-------|------|------------|
| 2022–2023 | 2024 | Out-of-sample robustness check |

ถ้าผล 2024 ยังเป็นบวก → params robust พอสำหรับ live

---

### ลำดับที่ 3 — Git Commit

Commit งานวันนี้:
- `Include/Logic/Strategies/S06_KAMA.mqh` — new defaults
- `Include/Logic/Strategies/S10_Turtle.mqh` — new defaults
- `Include/Logic/Strategies/S14_BBSqueeze.mqh` — new defaults + bug fix
- `Tester/Opt_S10_Turtle.mq5` — WinRate filter removed
- `Tester/Opt_S06_KAMA.mq5` — WinRate filter removed
- `02_Brain/core/optimization/setfile_generator.py` — fixed_from_params
- `02_Brain/core/optimization/pre_optimizer.py` — TP≥SL constraint

---

### ลำดับที่ 4 — Deploy (ถ้า validation ผ่าน)

- อัปเดต `ProgramC_Trader.mq5` หรือ Brain config ให้ใช้ params ใหม่
- Recompile EA ที่มีการแก้ .mqh
- ทดสอบ Brain + Trader connection ก่อน live

---

### งานในอนาคต (ไม่ด่วน)

- **S01 StatArb**: แก้ Opt EA ให้ใช้ 2 symbols จริง + ลด EntryZ=1.5–2.5
- **S15 Grid**: เพิ่ม standalone signal mode ใน GridCore (RSI/MACD fallback)
- **S06 XAUUSD**: ลอง H4 หลังจาก constraint TP≥SL ถูกแก้แล้ว
- **Additional symbols**: S10 USDJPY H4, S14 EURUSD H1 (ขยาย coverage)
