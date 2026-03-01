# MM13 — Correlation-Adjusted Position Sizing
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM13 |
| **Name** | Correlation-Adjusted Sizing |
| **MQL5 Class** | `CMM13_CorrelationAdjusted` |
| **Magic Prefix** | MAGIC_MM13 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM13 ลด Lot Size เมื่อมี Position ที่มี **Correlation สูง** เปิดอยู่พร้อมกัน ป้องกันการ Double-Exposure ใน Asset ที่เคลื่อนไหวพร้อมกัน เช่น XAUUSD + XAGUSD (Gold-Silver) หรือ EURUSD + GBPUSD สูตร: ลด 20% ต่อ Correlated Pair ที่เปิดอยู่ (สูงสุด 3 คู่) Python Brain สามารถ Override ด้วย `SetCorrCount()` เมื่อคำนวณ Correlation ได้แม่นยำกว่า

---

## 2. Core Theory

### 2.1 Correlation Detection

```
Auto-detection via Open Positions scan:
  For each open position:
    Extract symbol → check against correlated_symbols[] list
    If match → corr_pairs++

Built-in correlated pairs (Setup() auto-adds):
  Primary symbol (e.g. XAUUSD) ↔ XAGUSD  (Gold-Silver)
  Primary symbol              ↔ XAUEUR  (Gold in EUR)
  Primary symbol              ↔ XPTUSD  (Platinum)
  Primary symbol              ↔ DXY     (Dollar Index inverse)
  Additional pairs can be added via AddCorrelatedSymbol()
```

### 2.2 Lot Reduction Formula

```
corr_pairs = count of correlated open positions detected

reduction = corr_pairs × m_corr_reduction_per_pair
  Default: m_corr_reduction_per_pair = 0.20 (20% per pair)

multiplier = max(m_min_mult, 1.0 - reduction)
  m_min_mult = 0.10 (never go below 10% of base lot)

Examples:
  0 correlated pairs: multiplier = 1.00 (full size)
  1 correlated pair:  multiplier = 0.80 (20% reduction)
  2 correlated pairs: multiplier = 0.60 (40% reduction)
  3 correlated pairs: multiplier = 0.40 (60% reduction)
  4+ pairs:           multiplier = 0.10 (max reduction, min floor)
```

### 2.3 Python Brain Override

```
SetCorrCount(int n):
  m_corr_count_override = n
  m_use_override = true

When override is active:
  corr_pairs = m_corr_count_override (ignores MQL5 auto-scan)

When to use override:
  Python Brain computes rolling Pearson correlation between symbols
  More accurate than simple "same symbol" detection
  Sent via CONFIG_PUSH key MM13_CORR_COUNT
```

### 2.4 Final Lot Calculation

```
base_lot = (balance × base_risk_pct / 100) / (sl_pips × pip_value)
final_lot = base_lot × multiplier

The calculation always returns at least 1 minimum broker lot.
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CA_BaseRisk` | 1.0 | Base risk % per trade |
| `CA_ReductionPerPair` | 0.20 | Lot reduction per correlated open position |
| `CA_MinMultiplier` | 0.10 | Floor multiplier (never below 10% base) |
| `CA_MaxPairs` | 3 | Max pairs to scan (beyond 3 uses max reduction) |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM13_BASE_RISK` | float | 1.0 | `m_base_risk_pct` |
| `MM13_REDUCTION` | float | 0.20 | `m_corr_reduction_per_pair` |
| `MM13_MIN_MULT` | float | 0.10 | `m_min_mult` |
| `MM13_CORR_COUNT` | int | -1 | `SetCorrCount()` override (-1 = auto) |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Use Case** | Multi-symbol systems trading correlated assets simultaneously |
| **Portfolio Protection** | Prevents over-exposure when Gold, Silver, Platinum all open at once |
| **Python Integration** | SetCorrCount() from Python Brain gives true rolling correlation data |
| **Single Symbol** | With only 1 symbol trading, corr_pairs = 0 → no reduction |
| **Standalone Ready** | Yes — auto-scan works without Python Brain |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM13_CorrelationAdjusted.mqh` | `CMM13_CorrelationAdjusted` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm13.GetDiagnostic();
// Output:
//   [MM13] CorrAdjusted | CorrPairs=2 (override=NO) | Mult=0.60
//   [MM13] BaseLot=0.10 → AdjLot=0.06
//   [MM13] Correlated: XAGUSD(1lot) XAUEUR(1lot) — 2 pairs detected

mm13.SetCorrCount(3);   // Python Brain override
mm13.GetMultiplier();   // Current lot multiplier
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Always full size despite correlations | Symbols not in corr list | Call `AddCorrelatedSymbol()` |
| Lot too small on multi-symbol EA | Too many pairs detected | Raise `CA_ReductionPerPair` to 0.15 or `CA_MinMultiplier` to 0.20 |
| Override ignored | `MM13_CORR_COUNT` not sent in CONFIG_PUSH | Verify Python sends the key |
| Auto-scan counting wrong | Broker symbol suffix issues (e.g. XAUUSD.t) | Use Python override instead |

---

*MM13 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
