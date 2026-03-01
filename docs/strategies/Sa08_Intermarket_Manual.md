# S08 — Intermarket Correlation (DXY/XAUUSD)
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Strategy Overview

| Field | Value |
|-------|-------|
| **Strategy ID** | S08 |
| **Enum Name** | `S08_INTERMARKET` |
| **Enum Index** | 7 (0-based array index in g_strategy_table) |
| **Name** | Intermarket Correlation |
| **Type** | Hybrid (`CAT_HYBRID` — Python DXY computation + MQL5 signal) |
| **Standalone Capable** | No — Server Only |
| **Preferred Regime** | TRENDING (`REGIME_TRENDING`) |
| **Alt Regime** | VOLATILE (`REGIME_VOLATILE`) |
| **Poor Regimes** | RANGING (correlation too weak) |
| **MQL5 Class** | `CIntermarket` |
| **Magic Number** | 1008 (`MAGIC_S08_INTERMARKET`) |
| **Family** | Multi-Asset |
| **Version** | 6.00 |

### สรุปแนวคิด (Thai)

S08 เทรด XAUUSD โดยอาศัย **ความสัมพันธ์ผกผันระหว่าง DXY (Dollar Index) กับ Gold** Python Brain คำนวณ: correlation coefficient, ทิศทาง DXY, momentum ของ DXY และ volatility ของ Gold ส่งมาผ่าน CONFIG_PUSH เมื่อ correlation แข็งแกร่ง (< -0.70) และ DXY กำลังอ่อนตัว → ซื้อ Gold, เมื่อ DXY แข็งตัว → ขาย Gold กลยุทธ์นี้ใช้ Python คำนวณ DXY ที่ MQL5 ไม่สามารถเข้าถึงได้โดยตรง

---

## 2. Core Theory

### 2.1 The DXY-Gold Relationship

```
Gold (XAUUSD) has a historically strong NEGATIVE correlation with USD (DXY):
  DXY strengthens → Gold priced in USD falls
  DXY weakens     → Gold priced in USD rises

Correlation threshold: < -0.70 (strong negative correlation confirmed)

Example signal:
  Correlation = -0.85, DXY direction = DOWN, momentum = 0.75
  → SIGNAL_BUY XAUUSD (Gold expected to rise)
```

### 2.2 Python-Computed Inputs

```
Python Brain computes (rolling 20-bar window):

1. correlation_coefficient (-1.0 to +1.0)
   Rolling Pearson correlation between DXY price changes and XAUUSD price changes

2. dxy_direction (-1, 0, +1)
   -1 = DXY weakening (falling)
    0 = neutral
   +1 = DXY strengthening (rising)

3. dxy_momentum (0.0–1.0)
   Normalized DXY rate-of-change — how fast DXY is moving

4. gold_volatility (0.0–1.0)
   Normalized XAUUSD ATR — how volatile Gold is currently

These are embedded in CONFIG_PUSH as:
  S08_CORRELATION, S08_DXY_DIRECTION, S08_DXY_MOMENTUM, S08_GOLD_VOLATILITY
```

### 2.3 Entry Logic (MQL5 side)

```
All conditions must be true:

1. m_server_data_ready = true   (Config received from Python Brain)
2. correlation < m_corr_threshold (-0.70)   (strong negative corr confirmed)
3. dxy_momentum >= m_min_momentum (0.20)    (DXY is actually moving)
4. gold_volatility >= m_min_volatility (0.10) (Gold is moving too)

Then:
  dxy_direction == -1 → SIGNAL_BUY  (DXY down → Gold up)
  dxy_direction == +1 → SIGNAL_SELL (DXY up → Gold down)
  dxy_direction == 0  → SIGNAL_NONE (neutral — no trade)
```

### 2.4 TP / SL

```
TP = 2 × ATR from entry    (m_tp_atr_mult = 2.0)
SL = 1 × ATR from entry    (m_sl_atr_mult = 1.0)
R:R = 2.0

ATR is computed locally on XAUUSD using iATR(14)
TP and SL are absolute price levels (not virtual/hidden)
```

### 2.5 Confidence

```
Confidence = |correlation| × dxy_momentum × gold_volatility

Example:
  |corr| = 0.85, momentum = 0.75, gold_vol = 0.60
  Confidence = 0.85 × 0.75 × 0.60 = 0.38

Maximum (all factors = 1.0) = 1.0
Typical range: 0.20–0.60
```

---

## 3. Hybrid Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  S08 HYBRID FLOW                                                │
├──────────────────────────┬──────────────────────────────────────┤
│  Python Brain            │  Computes DXY-Gold correlation       │
│  (Intelligence Side)     │  Rolling 20-bar Pearson coefficient  │
│                          │  DXY direction via rate-of-change    │
│                          │  Momentum normalization (0–1)        │
│                          │  Gold ATR normalization (0–1)        │
├──────────────────────────┼──────────────────────────────────────┤
│  CONFIG_PUSH Type 10     │  S08_CORRELATION                     │
│  (ZMQ Port 7778)         │  S08_DXY_DIRECTION                   │
│                          │  S08_DXY_MOMENTUM                    │
│                          │  S08_GOLD_VOLATILITY                 │
│                          │  S08_CORR_THRESHOLD                  │
│                          │  S08_TP_ATR_MULT, S08_SL_ATR_MULT   │
├──────────────────────────┼──────────────────────────────────────┤
│  MQL5 Trader             │  SetServerData() updates m_correlation│
│  (CIntermarket)          │  Analyze() fires on every tick       │
│                          │  Checks all conditions each tick     │
│                          │  ATR handle: iATR(14) local XAUUSD   │
│                          │  GetTP() / GetSL() price calculation │
└──────────────────────────┴──────────────────────────────────────┘
```

### Why Server-Only?

S08 requires DXY price data which is:
1. Not available on all MT5 brokers as a symbol
2. Needs cross-symbol rolling correlation computation
3. Python Brain has access to multiple symbol feeds simultaneously

Without Python Brain: `m_server_data_ready = false` → `SIGNAL_NONE` always.

---

## 4. Parameter Reference

### 4.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `IM_Corr_Threshold` | -0.70 | Minimum correlation magnitude to trigger |
| `IM_ATR_Period` | 14 | ATR period for TP/SL |
| `IM_TP_ATR_Mult` | 2.0 | TP = 2× ATR |
| `IM_SL_ATR_Mult` | 1.0 | SL = 1× ATR |
| `IM_Min_Momentum` | 0.20 | Minimum DXY momentum |
| `IM_Min_Volatility` | 0.10 | Minimum gold volatility |

### 4.2 CONFIG_PUSH Keys

| Key | Type | Description |
|-----|------|-------------|
| `S08_CORRELATION` | float | Python-computed DXY-Gold correlation |
| `S08_DXY_DIRECTION` | int | +1/0/-1 DXY direction |
| `S08_DXY_MOMENTUM` | float | DXY momentum 0–1 |
| `S08_GOLD_VOLATILITY` | float | Gold ATR normalized 0–1 |
| `S08_CORR_THRESHOLD` | float | Correlation entry threshold (default -0.70) |
| `S08_ATR_PERIOD` | int | ATR recalculation period |
| `S08_TP_ATR_MULT` | float | TP multiplier |
| `S08_SL_ATR_MULT` | float | SL multiplier |
| `S08_MIN_MOMENTUM` | float | Min DXY momentum filter |
| `S08_MIN_VOLATILITY` | float | Min Gold volatility filter |

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Fed rate decisions, economic events, sustained DXY trend |
| **Worst Condition** | Risk-off events where correlation breaks (Gold ≠ anti-DXY) |
| **Typical Duration** | Hours (macro trend trades) |
| **R:R Ratio** | 2.0 (2×ATR TP / 1×ATR SL) |
| **Entry Frequency** | Low — requires sustained strong correlation |
| **Server Required** | YES — no trades without CONFIG_PUSH |
| **Standalone** | No |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/Strategies/S08_Intermarket.mqh` | `CIntermarket` MQL5 thin wrapper |
| `02_Brain/core/strategy/engine.py` | Python correlation computation for S08 |

---

## 7. Quick Diagnostics

```
[S08] Init OK | Symbol=XAUUSD TF=PERIOD_M1 | ServerOnly=YES
[S08] Server data received | Corr=-0.821 Dir=DOWN Mom=0.75 Vol=0.42
[S08] BUY signal | Corr=-0.821 DXY=DOWN Conf=0.26
[S08] SELL signal | Corr=-0.793 DXY=UP Conf=0.23
```

### Diagnostic Accessors

```mql5
s08.GetCorrelation()    // Current DXY-Gold correlation
s08.GetDXYDirection()   // +1/0/-1
s08.GetDXYMomentum()    // 0.0–1.0
s08.GetGoldVolatility() // 0.0–1.0
s08.HasServerData()     // false until first CONFIG_PUSH received
s08.GetLastATR()        // Local XAUUSD ATR
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| S08 never fires | `m_server_data_ready=false` | Python Brain not connected |
| No signal despite data | Correlation > -0.70 | Weaken threshold to -0.60 |
| Signals in flat DXY market | `m_min_momentum` too low | Raise to 0.35 |

---

*S08 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
