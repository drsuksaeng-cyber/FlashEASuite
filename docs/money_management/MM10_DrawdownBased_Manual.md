# MM10 — Drawdown-Based Position Sizing
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM10 |
| **Name** | Drawdown-Based Position Sizing |
| **MQL5 Class** | `CMM10_DrawdownBased` |
| **Magic Prefix** | MAGIC_MM10 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM10 ใช้ **Drawdown %** จาก Peak Equity เพื่อปรับ Lot Size แบบ 3 ระดับ TIER1 (DD > 10%) → ลดเหลือ 50%, TIER2 (DD > 15%) → ลดเหลือ 25%, EMERGENCY (DD > 20%) → ใช้แค่ minimum lot มี **Recovery Hysteresis**: ต้องฟื้นกลับมา 2% จากระดับ threshold ก่อนถึงจะ upgrade tier กลับขึ้น ป้องกัน flickering ระหว่าง tier ที่ขอบเขต

---

## 2. Core Theory

### 2.1 Drawdown Calculation

```
Peak equity tracking:
  m_peak_equity = max(m_peak_equity, AccountEquity())
  Updated continuously on every CalculateLot() call

Current drawdown:
  dd_pct = (m_peak_equity - AccountEquity()) / m_peak_equity × 100
```

### 2.2 Three-Tier System

```
ENUM_DD_STATE:
  DD_NORMAL     (0): DD < tier1_threshold  → Full lot (100%)
  DD_TIER1      (1): DD ≥ 10%             → 50% of full lot
  DD_TIER2      (2): DD ≥ 15%             → 25% of full lot
  DD_EMERGENCY  (3): DD ≥ 20%             → Min lot only (broker minimum)

Sizing multipliers:
  NORMAL:    lot × 1.00
  TIER1:     lot × 0.50
  TIER2:     lot × 0.25
  EMERGENCY: m_min_lot (fixed, e.g. 0.01)
```

### 2.3 Recovery Hysteresis

```
Purpose: Prevent rapid tier switching when equity fluctuates at a boundary

Rules (step-up is immediate, step-down requires hysteresis):
  Step DOWN (tier upgrade = worse):
    NORMAL → TIER1:    when DD ≥ 10.0%  (immediate)
    TIER1  → TIER2:    when DD ≥ 15.0%  (immediate)
    TIER2  → EMERG:    when DD ≥ 20.0%  (immediate)

  Step UP (tier downgrade = better):
    EMERG → TIER2:     when DD < 18.0%  (20% - 2% hysteresis)
    TIER2 → TIER1:     when DD < 13.0%  (15% - 2% hysteresis)
    TIER1 → NORMAL:    when DD <  8.0%  (10% - 2% hysteresis)

m_hysteresis_pct = 2.0 (default) — both directions
```

### 2.4 Emergency Mode

```
IsEmergencyMode() returns true when dd_pct >= m_emergency_threshold (20%)

EA should:
  - Only place minimum-lot trades (or stop entirely)
  - Consider disabling new position entries
  - Alert user/Brain via status message

CalculateLot() in EMERGENCY state:
  → Returns m_min_lot (e.g. 0.01) regardless of balance or SL
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DD_Tier1Threshold` | 10.0 | DD% to enter Tier1 (50% size) |
| `DD_Tier2Threshold` | 15.0 | DD% to enter Tier2 (25% size) |
| `DD_EmergThreshold` | 20.0 | DD% for Emergency (min lot only) |
| `DD_Hysteresis` | 2.0 | % recovery needed to upgrade tier |
| `DD_BaseRisk` | 1.0 | Base risk % for full-size lot |
| `DD_MinLot` | 0.01 | Minimum lot in Emergency mode |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM10_TIER1` | float | 10.0 | `m_tier1_threshold` |
| `MM10_TIER2` | float | 15.0 | `m_tier2_threshold` |
| `MM10_EMERG` | float | 20.0 | `m_emergency_threshold` |
| `MM10_HYST` | float | 2.0 | `m_hysteresis_pct` |
| `MM10_BASE_RISK` | float | 1.0 | `m_base_risk` |

---

## 4. State Machine

```
             DD < 8%           DD < 13%          DD < 18%
NORMAL ←─────────── TIER1 ←──────────── TIER2 ←───────────── EMERGENCY
       ──────────→       ──────────────→       ──────────────→
       DD ≥ 10%          DD ≥ 15%               DD ≥ 20%

Step-down (worsening): immediate
Step-up   (improving): requires hysteresis (2% below threshold)
```

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Gradual drawdown — tiers activate and reduce exposure progressively |
| **Worst Condition** | Flash crash — drops to emergency immediately (as intended) |
| **Recovery Time** | 2% above threshold before upgrading — prevents premature size increase |
| **Peak Tracking** | Never resets — always tracks all-time equity peak |
| **Standalone Ready** | Yes |
| **Used in MM19** | Default Tertiary component in Dynamic Multi MM |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM10_DrawdownBased.mqh` | `CMM10_DrawdownBased` full implementation |

---

## 7. Quick Diagnostics

```mql5
mm10.GetDiagnostic();
// Output:
//   [MM10] DrawdownBased | Peak=$11,250 Equity=$9,630 | DD=14.4%
//   [MM10] State=TIER1 | Mult=0.50 | BaseLot=0.10 → Lot=0.05
//   [MM10] NextUpgrade: DD < 8.0% | NextDowngrade: DD >= 15.0%

bool emergency = mm10.IsEmergencyMode();
double current_dd = mm10.GetCurrentDD();
ENUM_DD_STATE state = mm10.GetTierState();
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Tier flickering at boundary | `DD_Hysteresis` too small | Raise to 3.0% |
| Stuck in Tier1 forever | Strategy underperforming long-term | Investigate strategy edge |
| Emergency never clears | Peak too high — need large recovery | Consider manual peak reset |
| Lot = 0 in normal conditions | `DD_BaseRisk` or SL configuration issue | Check CalculateLot() inputs |

---

*MM10 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
