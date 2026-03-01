# MM04 — Kelly Criterion (Half-Kelly)
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM04 |
| **Name** | Kelly Criterion (Half-Kelly) |
| **MQL5 Class** | `CMM04_KellyCriterion` |
| **Magic Prefix** | MAGIC_MM04 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM04 ใช้ **Kelly Criterion** — สูตรคณิตศาสตร์คำนวณขนาด Lot ที่เหมาะสมที่สุด โดยอิงจากสถิติการเทรดจริง ใช้ **Half-Kelly** (50% ของ Full Kelly) เพื่อลด Drawdown ข้อมูลที่ใช้: Win Rate และ Average R:R จาก 50 เทรดล่าสุด หาก trade history < 30 รายการ → ใช้ fallback 1% risk แทน Kelly Cap สูงสุด 5%

---

## 2. Core Theory

### 2.1 Kelly Formula

```
Full Kelly % = (WinRate × AvgRR - LossRate) / AvgRR

Where:
  WinRate  = wins / total_trades  (rolling 50-trade window)
  LossRate = 1 - WinRate
  AvgRR    = average(win_pnl / |loss_pnl|) for all closed trades

Half-Kelly  = Full Kelly × 0.5  (recommended — reduces variance)
```

### 2.2 Why Half-Kelly?

```
Full Kelly maximizes geometric growth but:
  - Drawdowns can reach 50% even with edge
  - Real win rates fluctuate → full Kelly overestimates edge

Half-Kelly provides:
  - ~75% of full Kelly growth rate
  - ~50% less drawdown variance
  - Much more robust to estimation error
```

### 2.3 Fallback Rules

```
If total_trades < m_min_trades (default 30):
  → Use fallback risk % (default 1.0%)
  → Not enough data to estimate Kelly accurately

If Kelly% computes to negative:
  → No edge detected (WinRate too low for given AvgRR)
  → Return 0 or fallback depending on config

Cap: Kelly% capped at m_max_risk_cap (default 5.0%)
  → Protects against extreme edge over-estimation
```

### 2.4 Lot Calculation

```
RiskAmount = AccountBalance × (Kelly% / 100)
Lot        = RiskAmount / (SL_pips × pip_value_per_lot)

If SL not provided or zero:
  → Use default ATR-based SL estimate
```

---

## 3. Rolling Trade Window

```
Window size: m_window_size (default 50 trades)
Updated by:  UpdateTradeResult(profit, lot, sl_pips)

Rolling stats maintained:
  m_total_trades — total in window
  m_wins         — winning trades
  m_sum_rr       — sum of R:R ratios (for averaging)

Win Rate  = m_wins / m_total_trades
Avg R:R   = m_sum_rr / m_wins  (only win trades contribute)
```

---

## 4. Parameter Reference

### 4.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `KC_Window` | 50 | Rolling trade history window size |
| `KC_MinTrades` | 30 | Minimum trades before using Kelly (else fallback) |
| `KC_MaxRiskCap` | 5.0 | Hard cap on Kelly risk % |
| `KC_FallbackRisk` | 1.0 | Fallback risk % when insufficient data |
| `KC_HalfKelly` | true | Use Half-Kelly (0.5×) vs Full Kelly |

### 4.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM04_WINDOW` | int | 50 | `m_window_size` |
| `MM04_MIN_TRADES` | int | 30 | `m_min_trades` |
| `MM04_MAX_CAP` | float | 5.0 | `m_max_risk_cap` |
| `MM04_FALLBACK` | float | 1.0 | `m_fallback_risk` |

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Use Case** | Systems with proven edge over 30+ trades |
| **Worst Use Case** | New strategy with insufficient history — over-estimates edge |
| **Reaction Speed** | Slow (50-trade window) — stable sizing |
| **Drawdown Profile** | Lower than fixed % due to size reduction when win rate drops |
| **Typical Range** | 0.5%–3.0% effective risk per trade |
| **Dependencies** | Requires accurate UpdateTradeResult() calls after each close |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM04_KellyCriterion.mqh` | `CMM04_KellyCriterion` full implementation |

---

## 7. Quick Diagnostics

```mql5
mm04.GetDiagnostic();
// Output:
//   [MM04] Kelly | WinRate=58.3% AvgRR=1.42 | FullKelly=2.3% HalfKelly=1.15%
//   [MM04] Trades=43/50 | Fallback=NO | Cap=5.0% | EffectiveRisk=1.15%
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Always at fallback 1% | `KC_MinTrades` not reached | Lower to 20 or set fallback higher |
| Kelly% very high (>4%) | Very favorable recent stats | Apply cap (`KC_MaxRiskCap` = 3%) |
| Kelly% near zero | Strategy underperforming | Review strategy edge |
| Negative Kelly computed | Win rate too low for R:R | Fallback kicks in automatically |

---

*MM04 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
