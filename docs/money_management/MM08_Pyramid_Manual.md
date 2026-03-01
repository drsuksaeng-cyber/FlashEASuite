# MM08 — Pyramid (Scale-In on Winners)
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM08 |
| **Name** | Pyramid (Scale-In) |
| **MQL5 Class** | `CMM08_Pyramid` |
| **Magic Prefix** | MAGIC_MM08 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM08 คือ **Pyramid Strategy** — เพิ่ม Position เมื่อเทรดกำไรแล้ว (Anti-Martingale ประเภทหนึ่ง) Lot Size ลดลงแบบ Geometric decay ต่อระดับ: Level 0 = 50% ของ Full Lot, Level 1 = 25%, Level 2 = 12.5% สูงสุด 3 ระดับ เงื่อนไขเพิ่ม Position: floating profit ≥ (level+1) × trigger_R × initial_risk เมื่อปิด Trade → Reset pyramid ทั้งหมด

---

## 2. Core Theory

### 2.1 Pyramid Lot Decay

```
Full Lot = calculated from risk% × balance / SL_pips

Level 0 (entry):      Full Lot × 0.50  = 50% of full
Level 1 (add-on 1):   Full Lot × 0.25  = 25% of full
Level 2 (add-on 2):   Full Lot × 0.125 = 12.5% of full

Decay factor: 50% per level
Max levels: 3 (Level 0 → entry; Levels 1, 2 → scale-in)

Total exposure if all 3 filled:
  0.50 + 0.25 + 0.125 = 0.875× Full Lot
  (never exceeds 1× full lot — position-sizing is conservative)
```

### 2.2 Scale-In Trigger

```
ShouldAddPosition() returns true when:
  current_level < m_max_levels (3)
  AND floating_profit >= (current_level + 1) × m_trigger_r × initial_risk_amount

Example (m_trigger_r = 1.0, initial_risk = $100):
  Level 0 entered: add level 1 when floating profit ≥ $100 (1R)
  Level 1 added:   add level 2 when floating profit ≥ $200 (2R)
  Level 2 added:   max reached — no more additions

Logic: Each add-on is triggered at an additional 1R of profit,
       ensuring no add-on is made unless the trade has proven itself.
```

### 2.3 Level Advancement

```
EA Flow:
  1. Enter trade → CalculateLot(level=0) → place Level 0 order
  2. Each tick: mm08.ShouldAddPosition(floating_profit) → true?
  3. Yes → CalculateLot(current_level+1) → place add-on order
  4. mm08.AdvanceLevel() → increment internal level counter
  5. On trade close → mm08.ResetPyramid() / UpdateTradeResult()

Note: AdvanceLevel() must be called by EA after add-on is placed.
      ResetPyramid() resets level counter to 0 for next trade.
```

### 2.4 CalculateLot at Each Level

```
CalculateLot(level):
  full_lot = (balance × risk_pct / 100) / (sl_pips × pip_value)
  decay    = pow(m_decay_factor, level)  // 0.5^0=1.0, 0.5^1=0.5, 0.5^2=0.25
  return full_lot × m_level0_ratio × decay

// m_level0_ratio = 0.50 (Level 0 starts at 50% of full lot)
// m_decay_factor = 0.50 (halves each level)
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PY_RiskPct` | 2.0 | Base risk % for full lot calculation |
| `PY_MaxLevels` | 3 | Maximum pyramid levels (including entry) |
| `PY_Level0Ratio` | 0.50 | Entry lot as fraction of full lot |
| `PY_DecayFactor` | 0.50 | Lot reduction per pyramid level |
| `PY_TriggerR` | 1.0 | Profit trigger per level (in R multiples) |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM08_RISK_PCT` | float | 2.0 | `m_risk_pct` |
| `MM08_MAX_LEVELS` | int | 3 | `m_max_levels` |
| `MM08_TRIGGER_R` | float | 1.0 | `m_trigger_r` |
| `MM08_DECAY` | float | 0.50 | `m_decay_factor` |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Strong trending moves — price runs far after entry |
| **Worst Condition** | Choppy market — add-on trigger never reached |
| **Max Total Exposure** | 0.875× of Full Lot (all 3 levels combined) |
| **Profit Amplification** | ~40–80% more profit vs single-entry on big moves |
| **Risk Profile** | Conservative — each add-on only on confirmed profit |
| **Standalone Ready** | Yes |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM08_Pyramid.mqh` | `CMM08_Pyramid` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm08.GetDiagnostic();
// Output:
//   [MM08] Pyramid | Level=1/3 | FloatingPL=+$124 | Trigger=+$100 (READY for L2)
//   [MM08] Lots: L0=0.05 L1=0.025 L2=pending | TotalOpen=0.075

bool should_add = mm08.ShouldAddPosition(floating_pl);
mm08.AdvanceLevel();   // After placing add-on
mm08.ResetPyramid();   // After trade fully closed
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Add-on never fires | `PY_TriggerR` too high or market too slow | Lower `MM08_TRIGGER_R` to 0.75 |
| Too many small lots | `PY_Level0Ratio` too small | Raise to 0.60 |
| Level not advancing | EA not calling `AdvanceLevel()` | Verify EA logic calls after add-on order placed |
| Pyramid not resetting | EA not calling `ResetPyramid()` on close | Verify EA calls on position close event |

---

*MM08 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
