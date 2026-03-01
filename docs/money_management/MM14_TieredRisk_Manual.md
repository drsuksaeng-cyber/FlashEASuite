# MM14 — Tiered Risk (Balance-Based)
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM14 |
| **Name** | Tiered Risk (Balance-Based) |
| **MQL5 Class** | `CMM14_TieredRisk` |
| **Magic Prefix** | MAGIC_MM14 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM14 ปรับ Risk % ตาม **ขนาด Account Balance** — Small Account → Risk สูงกว่า (ต้องการ grow เร็วกว่า) Large Account → Risk ต่ำกว่า (อนุรักษ์ capital มากกว่า) 3 ระดับ: < $1,000 → 2%, $1,000–$10,000 → 1.5%, > $10,000 → 1.0% ทุก threshold และ risk% สามารถปรับผ่าน CONFIG_PUSH ได้

---

## 2. Core Theory

### 2.1 Three-Tier Balance System

```
Default Tiers:

Tier 1 (Small):   Balance < $1,000
  Risk % = 2.0%
  Rationale: Small accounts need faster growth; max loss per trade still small in absolute $

Tier 2 (Medium):  $1,000 ≤ Balance < $10,000
  Risk % = 1.5%
  Rationale: Balanced growth with moderate protection

Tier 3 (Large):   Balance ≥ $10,000
  Risk % = 1.0%
  Rationale: Large accounts prioritize capital preservation
             Absolute $ per trade remains large even at 1%
```

### 2.2 Lot Calculation

```
Step 1: Determine tier by AccountBalance()
Step 2: risk_pct = tier_risk_pct

Lot = (AccountBalance × risk_pct / 100) / (sl_pips × pip_value_per_lot)

Example (EURUSD, SL=20 pips, $1 pip/lot):
  Balance $500  → 2.0% → $10 risk → 0.50 lots
  Balance $5000 → 1.5% → $75 risk → 3.75 lots
  Balance $50k  → 1.0% → $500 risk → 25 lots
```

### 2.3 Dynamic Tier Switching

```
Tier check is performed on every CalculateLot() call.
Balance is re-read from AccountBalance() each time.

No hysteresis — tier changes take immediate effect.
(Unlike MM10 which has hysteresis for DD protection)

If account grows from Tier 2 to Tier 3:
  Next trade immediately uses Tier 3 risk % (1.0%)
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TR_Tier1_Max` | 1000.0 | Balance threshold — below this = Tier 1 |
| `TR_Tier2_Max` | 10000.0 | Balance threshold — below this = Tier 2 |
| `TR_Tier1_Risk` | 2.0 | Risk % for small accounts |
| `TR_Tier2_Risk` | 1.5 | Risk % for medium accounts |
| `TR_Tier3_Risk` | 1.0 | Risk % for large accounts |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM14_TIER1_MAX` | float | 1000.0 | `m_tier1_max` |
| `MM14_TIER2_MAX` | float | 10000.0 | `m_tier2_max` |
| `MM14_TIER1_RISK` | float | 2.0 | `m_tier1_risk` |
| `MM14_TIER2_RISK` | float | 1.5 | `m_tier2_risk` |
| `MM14_TIER3_RISK` | float | 1.0 | `m_tier3_risk` |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Use Case** | Multi-account deployment — risk auto-scales with account size |
| **Simplest MM** | No state to maintain; pure balance lookup on each trade |
| **Small Account** | 2% risk allows meaningful growth with limited capital |
| **Large Account** | 1% risk avoids regulatory concerns and broker margin issues |
| **Standalone Ready** | Yes — no dependencies beyond AccountBalance() |
| **Reaction Speed** | Immediate on each trade |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM14_TieredRisk.mqh` | `CMM14_TieredRisk` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm14.GetDiagnostic();
// Output:
//   [MM14] TieredRisk | Balance=$3,450 | Tier=2 (Medium) | Risk=1.5%
//   [MM14] Lot=0.03 | SL=25.0 pips | RiskAmt=$51.75

int tier = mm14.GetCurrentTier();      // 1, 2, or 3
double risk = mm14.GetCurrentRisk();   // Effective risk %
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Tier 1 risk too high for prop firm | Prop firm max risk = 1% | Set `MM14_TIER1_RISK` = 1.0 |
| No lot change at tier boundary | Tier thresholds wrong | Verify `MM14_TIER1_MAX` / `MM14_TIER2_MAX` |
| Different accounts need different tiers | Hardcoded thresholds | Configure via CONFIG_PUSH per-account |

---

*MM14 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
