# MM09 — Equity Curve Recovery
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM09 |
| **Name** | Equity Curve Recovery |
| **MQL5 Class** | `CMM09_EquityCurveRecovery` |
| **Magic Prefix** | MAGIC_MM09 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM09 ติดตาม **Equity Curve** โดย track equity ณ จุดปิด Trade ล่าสุด N รายการ คำนวณ MA (SMA หรือ EMA) เมื่อ equity ปัจจุบัน < MA → ลด lot size ลง X% (default 50%) หยุดการซื้อขายชั่วคราวหรือลดความเสี่ยง เมื่อ equity กลับมาเหนือ MA → กลับมาใช้ lot ปกติ ป้องกัน drawdown ซ้ำในช่วงที่ strategy กำลัง underperform

---

## 2. Core Theory

### 2.1 Equity History Buffer

```
Circular buffer of size m_ma_period (default 20):
  m_equity_history[] — stores equity at each trade close
  m_buf_count        — valid entries (0 to m_ma_period)

UpdateTradeResult() appends current equity:
  m_equity_history[m_buf_idx] = AccountEquity()
  m_buf_idx = (m_buf_idx + 1) % m_ma_period

Minimum entries before MA is valid: m_ma_period / 2 (default 10)
```

### 2.2 Moving Average Modes

```
SMA Mode (m_use_ema = false, default):
  equity_ma = Sum(m_equity_history) / m_buf_count

EMA Mode (m_use_ema = true):
  equity_ema = equity_ema × (1 - alpha) + new_equity × alpha
  alpha = 2.0 / (m_ma_period + 1)
  EMA is more responsive to recent equity changes
```

### 2.3 Below-MA Reduction

```
If AccountEquity() < equity_ma:
  reduction_mult = 1.0 - (m_reduce_pct / 100.0)

  Example: m_reduce_pct = 50 → reduction_mult = 0.5
           reduced_lot = base_lot × 0.5

Special case: m_reduce_pct = 100 → reduced_lot = 0
  (complete halt — no new trades until equity recovers)

Above-MA → use full base_lot (no modification)
```

### 2.4 Base Lot Source

```
MM09 wraps around base risk calculation:
  base_lot = (AccountBalance × m_base_risk_pct / 100) / (sl_pips × pip_value)

Then applies equity curve multiplier:
  final_lot = base_lot × reduction_mult
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ECR_MAPeriod` | 20 | Number of trade closes in equity MA |
| `ECR_UseEMA` | false | Use EMA instead of SMA |
| `ECR_ReducePct` | 50.0 | Lot reduction % when below MA (100 = halt) |
| `ECR_BaseRisk` | 1.0 | Base risk % per trade |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM09_MA_PERIOD` | int | 20 | `m_ma_period` |
| `MM09_USE_EMA` | int | 0 | `m_use_ema` (0=SMA, 1=EMA) |
| `MM09_REDUCE_PCT` | float | 50.0 | `m_reduce_pct` |
| `MM09_BASE_RISK` | float | 1.0 | `m_base_risk_pct` |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Strategy with oscillating equity curve — detects bad patches early |
| **Worst Condition** | Long trending drawdown — MA lags behind, recovery may be slow |
| **Reaction Speed** | Moderate — 20-trade window means ~20 trades to detect downturn |
| **EMA Mode** | Faster response (recent trades weighted more) but noisier |
| **Recovery Signal** | Equity must exceed MA to return to full sizing |
| **Standalone Ready** | Yes |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM09_EquityCurveRecovery.mqh` | `CMM09_EquityCurveRecovery` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm09.GetDiagnostic();
// Output:
//   [MM09] EquityCurve | Equity=$9,845 MA=$10,120 | BELOW MA
//   [MM09] Reduction=50% | BaseLot=0.10 → ReducedLot=0.05
//   [MM09] Buffer: 15/20 entries | Mode=SMA

double eq_ma = mm09.GetEquityMA();
bool below_ma = mm09.IsBelowMA();
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Always below MA | Recent bad streak | Normal behavior — wait for recovery |
| Never reduces | Buffer not filling | Ensure `UpdateTradeResult()` called on every close |
| Reduction too aggressive | 50% reduction too harsh | Lower to 25% or 30% |
| MA too slow to react | `ECR_MAPeriod` = 20 too long | Try EMA mode or reduce period to 10 |

---

*MM09 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
