# MM05 — Controlled Martingale
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM05 |
| **Name** | Controlled Martingale |
| **MQL5 Class** | `CMM05_MartingaleControlled` |
| **Magic Prefix** | MAGIC_MM05 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM05 คือ **Martingale แบบควบคุม** — เพิ่ม Lot หลังขาดทุน แต่มี Hard Cap เพื่อจำกัดความเสี่ยง BaseLot = 1% risk จากนั้น ×2 ต่อ consecutive loss สูงสุด 4 ระดับ (ไม่เกิน 4× total multiplier) เมื่อ P/L รวมถึง break-even → ปิดทุก Position และ Reset sequence ใช้กับ Strategy ที่มี Win Rate สูง (>60%) เท่านั้น

---

## 2. Core Theory

### 2.1 Martingale Sequence

```
Level 0 (first trade):   BaseLot × 1.0   = 1× base
Level 1 (after 1 loss):  BaseLot × 2.0   = 2× base
Level 2 (after 2 losses): BaseLot × 4.0  = 4× base (cap reached)
Level 3 (would be 8×):   capped at 4.0   = 4× base

Hard Rules:
  multiplier = min(lot_multiplier ^ consecutive_losses, m_max_total_mult)
  m_max_total_mult = 4.0  (never go above 4× base)
  m_max_levels     = 4    (no more than 4 consecutive entries)
```

### 2.2 Base Lot Calculation

```
BaseLot = (AccountBalance × 0.01) / (DefaultSL_pips × pip_value_per_lot)
  Default risk per sequence start: 1% of balance

Safety hard cap: never exceed 5% of equity on any single trade
```

### 2.3 Break-Even Close (ShouldCloseAll)

```
Condition: sum of all open positions P/L >= 0 AND sequence_active = true

When triggered:
  → EA should close ALL open positions in this sequence
  → Reset: consecutive_losses = 0, sequence_active = false
  → Goal: escape Martingale sequence at break-even or small profit

This is the key safety mechanism — prevents unlimited sequence length.
```

### 2.4 Loss Counter Logic

```
UpdateTradeResult(profit):
  if profit < 0:
    consecutive_losses++
    sequence_active = true
  else:
    consecutive_losses = 0
    sequence_active = false
    (win resets everything)

If consecutive_losses >= m_max_levels:
  → CalculateLot() returns 0 (EA must stop adding)
  → EA should evaluate ShouldCloseAll() and cut losses if needed
```

---

## 3. Risk Warning

```
⚠️  MARTINGALE IS HIGH RISK:
    - A 4-loss streak requires 4× the base lot
    - Back-to-back losses can deplete account if base lot is too large
    - Only suitable for strategies with demonstrated win rate > 60%
    - Set BaseLot conservatively (0.5–1% risk per level-0 trade)

Recommended use:
  - High-frequency scalping strategies (S07 Mean Reversion, S16 Spike)
  - Markets with mean-reverting characteristics
  - NOT suitable for trending markets where losses can run
```

---

## 4. Parameter Reference

### 4.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CM_BaseRisk` | 1.0 | Base risk % per level-0 trade |
| `CM_Multiplier` | 2.0 | Lot multiplier per loss level |
| `CM_MaxTotalMult` | 4.0 | Hard cap on total multiplier (never exceed) |
| `CM_MaxLevels` | 4 | Maximum consecutive loss entries |
| `CM_SafetyCap` | 5.0 | Hard cap: never exceed this % of equity |

### 4.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM05_BASE_RISK` | float | 1.0 | `m_base_risk` |
| `MM05_MULTIPLIER` | float | 2.0 | `m_lot_multiplier` |
| `MM05_MAX_MULT` | float | 4.0 | `m_max_total_mult` |
| `MM05_MAX_LEVELS` | int | 4 | `m_max_levels` |

---

## 5. State Machine

```
States:
  IDLE        → No active sequence; use BaseLot × 1.0
  SEQUENCE    → Active Martingale; use BaseLot × multiplier^level
  CAPPED      → Max levels reached; CalculateLot() = 0 (force close)

Transitions:
  IDLE    + Loss  → SEQUENCE (level 1)
  SEQUENCE + Loss → SEQUENCE (level++) until level >= max_levels
  SEQUENCE + Win  → IDLE (reset)
  SEQUENCE + BE   → IDLE (ShouldCloseAll triggered and executed)
  SEQUENCE + Max  → CAPPED
  CAPPED   + Close → IDLE
```

---

## 6. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Mean-reverting market with high win rate (>65%) |
| **Worst Condition** | Trending loss streaks — sequence can cascade |
| **Max Risk Exposure** | 4× base risk (Level 2+, capped) |
| **Expected Wins** | Strategy must win before max_levels to be sustainable |
| **Break-Even Target** | Close all when cumulative P/L ≥ 0 |
| **Standalone Ready** | Yes |

---

## 7. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM05_MartingaleControlled.mqh` | `CMM05_MartingaleControlled` full implementation |

---

## 8. Quick Diagnostics

```mql5
mm05.GetDiagnostic();
// Output:
//   [MM05] Martingale | Level=2 | ConsecLoss=2 | Multiplier=4.0x (CAPPED)
//   [MM05] BaseLot=0.01 | CurrentLot=0.04 | SequenceActive=YES
//   [MM05] ShouldCloseAll=NO (OpenPL=-23.50)

bool should_close = mm05.ShouldCloseAll();
int current_level = mm05.GetCurrentLevel();
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Lot too large after losses | `CM_BaseRisk` too high | Reduce to 0.5% |
| Never breaks even | SL too tight — losses exceed recovery | Widen SL or reduce multiplier |
| Hits max level too fast | `CM_MaxLevels` = 4 default | Reduce to 3; ensure strategy win rate is high |
| Loop: close then re-enter | EA not checking `ShouldCloseAll()` properly | Verify EA logic calls `ShouldCloseAll()` each tick |

---

*MM05 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
