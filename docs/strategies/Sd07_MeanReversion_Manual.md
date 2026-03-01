# S07 — Mean Reversion (Volatility-Filtered)
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Strategy Overview

| Field | Value |
|-------|-------|
| **Strategy ID** | S07 |
| **Enum Name** | `S07_MEAN_REVERSION` |
| **Enum Index** | 6 (0-based array index in g_strategy_table) |
| **Name** | Mean Reversion (Vol-Filtered) |
| **Type** | Full MQL5 (`CAT_FULL_MQL5`) |
| **Standalone Capable** | Yes |
| **Preferred Regime** | RANGING (`REGIME_RANGING`) |
| **Alt Regime** | None (`REGIME_UNKNOWN`) |
| **Poor Regimes** | VOLATILE → regime factor = 0.5; TRENDING (RSI stays extreme) |
| **MQL5 Class** | `CMeanReversion` |
| **Magic Number** | 1007 (`MAGIC_S07_MEAN_REV`) |
| **Family** | Contrarian |
| **Version** | 6.00 |

### สรุปแนวคิด (Thai)

S07 เป็น **Mean Reversion** — เทรดเมื่อราคาเบี่ยงเบนมากเกินไปจากค่าเฉลี่ย โดยใช้ RSI และ Stochastic ยืนยันร่วมกัน พร้อม Volatility Filter (ATR ต้องต่ำกว่า N×MA(ATR)) เพื่อกรองสถานการณ์ที่ volatility สูงเกินไปออก TP ตั้งที่ Bollinger Band Middle (20,2) — คาดว่าราคาจะวนกลับมาที่ค่าเฉลี่ย SL = 2×ATR

---

## 2. Core Theory

### 2.1 Entry Conditions

```
Long (SIGNAL_BUY):
  RSI(14) < 30      (oversold)
  AND Stoch%K(14,3,3) < 20  (also oversold)
  AND vol_ok = true  (ATR volatility filter passes)

Short (SIGNAL_SELL):
  RSI(14) > 70      (overbought)
  AND Stoch%K > 80  (also overbought)
  AND vol_ok = true
```

### 2.2 Volatility Filter

```
ATR_MA = manual SMA of ATR(14) over last 20 bars
vol_ok = ATR(14) < m_vol_filter × ATR_MA

Default m_vol_filter = 1.3:
  ATR < 1.3 × MA(ATR) → allowed to trade
  ATR ≥ 1.3 × MA(ATR) → BLOCKED (too volatile for mean reversion)

Purpose: Mean reversion fails in trending/spiking conditions.
         This filter automatically pauses S07 during high-volatility events.
```

### 2.3 TP / SL Calculation

```
BUY entry at ask:
  SL = ask - (m_sl_atr_mult × ATR) = ask - 2×ATR
  TP = BB_middle if BB_middle > ask else ask + (m_tp_atr_mult × ATR)
       (prefer Bollinger mean; fall back to ATR-based TP)

SELL entry at bid:
  SL = bid + (m_sl_atr_mult × ATR) = bid + 2×ATR
  TP = BB_middle if BB_middle < bid else bid - (m_tp_atr_mult × ATR)

Default TP fallback: m_tp_atr_mult = 1.5
R:R (ATR fallback) = 1.5 / 2.0 = 0.75
R:R (BB-based) = variable — depends on distance to BB middle
```

### 2.4 Confidence Calculation

```
rsi_z  = |RSI - 50| / 50          (0=neutral, 1=extreme)
stoch_conf:
  if stoch_k < stoch_buy:  (stoch_buy - stoch_k) / stoch_buy
  if stoch_k > stoch_sell: (stoch_k - stoch_sell) / (100 - stoch_sell)

vol_factor:
  if ATR/ATR_MA <= 1.0:  1.0   (best — below average vol)
  if ATR/ATR_MA <= 1.3:  slight penalty (1.0 → 0.7)
  if ATR/ATR_MA > 1.3:   0.0   (filtered out)

Confidence = (rsi_z × 0.5 + stoch_conf × 0.5) × vol_factor
```

---

## 3. Indicators Used

| Indicator | Period | Purpose |
|-----------|--------|---------|
| `iRSI` | 14 | Oversold/overbought detection |
| `iStochastic` | 14,3,3 (STO_LOWHIGH) | Confirmation of extreme reading |
| `iATR` | 14 | Volatility measurement + SL sizing |
| `iBands` | 20, 2σ | Bollinger Band middle for TP target |
| Manual MA of ATR | 20 bars | Reference for volatility filter |

**Note:** ATR MA is computed manually via `_CalcATRMovingAvg()` by averaging the last 20 ATR values. MQL5 does not support applying `iMA` directly to another indicator buffer.

---

## 4. Parameter Reference

### 4.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MR_RSI_Period` | 14 | RSI period |
| `MR_RSI_Buy` | 30.0 | RSI oversold threshold |
| `MR_RSI_Sell` | 70.0 | RSI overbought threshold |
| `MR_Stoch_K` | 14 | Stochastic %K period |
| `MR_Stoch_D` | 3 | Stochastic %D smoothing |
| `MR_Stoch_Slow` | 3 | Stochastic slowing |
| `MR_Stoch_Buy` | 20.0 | Stochastic oversold threshold |
| `MR_Stoch_Sell` | 80.0 | Stochastic overbought threshold |
| `MR_ATR_Period` | 14 | ATR period |
| `MR_ATR_MA` | 20 | ATR moving average period |
| `MR_VolFilter` | 1.3 | Max ATR/MA(ATR) ratio |
| `MR_BB_Period` | 20 | Bollinger Band period |
| `MR_BB_Dev` | 2.0 | Bollinger Band standard deviation |
| `MR_SL_ATRMult` | 2.0 | SL = N × ATR |
| `MR_TP_ATRMult` | 1.5 | Fallback TP multiplier |

### 4.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `S07_RSI_PERIOD` | int | 14 | `m_rsi_period` (triggers reinit) |
| `S07_RSI_BUY` | float | 30.0 | `m_rsi_buy` |
| `S07_RSI_SELL` | float | 70.0 | `m_rsi_sell` |
| `S07_VOL_FILTER` | float | 1.3 | `m_vol_filter` |
| `S07_SL_ATR_MULT` | float | 2.0 | `m_sl_atr_mult` |
| `S07_TP_ATR_MULT` | float | 1.5 | `m_tp_atr_mult` |

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | RANGING market with stable ATR |
| **Worst Condition** | TRENDING — RSI stays oversold/overbought for extended periods |
| **Typical Duration** | Minutes to hours (mean reversion is quick) |
| **R:R (BB-based)** | Variable — depends on BB middle distance |
| **R:R (ATR fallback)** | 0.75 (1.5 TP / 2.0 SL) — compensated by high win rate |
| **Standalone Ready** | Yes |
| **Reinit on Param Change** | Yes — RSI period or BB period change triggers `_InitIndicators()` |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/Strategies/S07_MeanReversion.mqh` | `CMeanReversion` full implementation |
| `Tester/Opt_S07_MeanRev.mq5` | Parameter optimization script for S07 |

---

## 7. Quick Diagnostics

```
EA Experts Journal — search "[S07]":
  [S07] MeanReversion Init OK | EURUSD PERIOD_M1 | RSI<14 Stoch<14 Vol×1.3 BB(20,2.0)
```

```mql5
CMeanReversion* s07 = GetStrategy(S07_MEAN_REVERSION);
s07.PrintDiagnostics();
// Output:
//   [S07] MeanRev | RSI=28.5(<30/>70) Stoch=18.2(<20/>80)
//   [S07] ATR=0.00089 ATR_MA=0.00072 Ratio=1.24 VolFilter=1.3 VolOK=YES
//   [S07] BB_Mid=1.08550 Signal=BUY Conf=0.6500 SL=1.08370 TP=1.08550
s07.GetLastRSI()   // Current RSI value
s07.GetLastATR()   // Current ATR
s07.GetVolOK()     // Volatility filter state
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| S07 never enters | Vol filter blocking | Lower `S07_VOL_FILTER` to 1.5 |
| Too many bad entries | RSI/Stoch thresholds too loose | Tighten RSI to 25/75 |
| BB_Mid TP never reached | BB middle too far from entry | Set fallback `S07_TP_ATR_MULT` = 1.0 |
| Reinit loop | RSI period changes each tick | Verify CONFIG_PUSH only sends on change |

---

*S07 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
