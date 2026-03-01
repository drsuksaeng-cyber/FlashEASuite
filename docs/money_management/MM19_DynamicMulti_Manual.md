# MM19 — Dynamic Multi-Method
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM19 |
| **Name** | Dynamic Multi-Method |
| **MQL5 Class** | `CMM19_DynamicMulti` |
| **Magic Prefix** | MAGIC_MM19 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM19 คือ **Meta MM** — รวมผลลัพธ์จาก 2–3 MM Method เข้าด้วยกัน ไม่ต้องใช้ Pointer ทำให้เป็น Self-Contained (ไม่ขึ้นกับ MM object ภายนอก) คำนวณ lot จาก Primary, Secondary, Tertiary Method ภายในตัวเอง แล้ว Combine ด้วย 3 Mode: MIN_LOT (อนุรักษ์นิยม), AVG_LOT (สมดุล), WEIGHTED (ถ่วงน้ำหนัก 50/30/20%) Default: Primary=MM01 (Fixed Conservative), Secondary=MM03 (ATR-Based), Tertiary=MM10 (Drawdown)

---

## 2. Core Theory

### 2.1 Inline Method Computation

```
MM19 does NOT hold pointers to other MM objects.
Instead, it replicates key logic inline for each method:

Primary   method (default MM01): Fixed conservative 1% risk lot
Secondary method (default MM03): ATR-scaled lot from ATR context
Tertiary  method (default MM10): Drawdown-reduced lot

Context data is fed via UpdateContext() — see Section 2.4
```

### 2.2 Three Combine Modes

```
ENUM_COMBINE_MODE:

MIN_LOT  (0) — Most conservative
  result_lot = min(primary_lot, secondary_lot, tertiary_lot)
  Use: Risk-averse — take the smallest recommendation from all methods

AVG_LOT  (1) — Balanced
  result_lot = (primary_lot + secondary_lot + tertiary_lot) / 3
  Use: Average opinion of all three methods

WEIGHTED (2) — Default recommended
  result_lot = (primary_lot × 0.50) +
               (secondary_lot × 0.30) +
               (tertiary_lot  × 0.20)
  Use: Primary method dominates (50%); secondary and tertiary add nuance
```

### 2.3 Method Enum

```
ENUM_MM_METHOD:
  MM_METHOD_01 = 1   (Fixed Conservative, 1% risk)
  MM_METHOD_03 = 3   (ATR-Based scaling)
  MM_METHOD_07 = 7   (Percent Volatility)
  MM_METHOD_10 = 10  (Drawdown-Based)
  MM_METHOD_14 = 14  (Tiered Risk)

The methods available as Primary/Secondary/Tertiary are a subset
of all 19 MM methods — specifically those that can be replicated
inline without external state dependencies.
```

### 2.4 UpdateContext()

```
Must be called before CalculateLot() to provide current market context:

mm19.UpdateContext(
  atr_value,        // Current ATR (for MM03/MM07 calculations)
  win_rate,         // Rolling win rate 0.0–1.0 (for Kelly-like methods)
  current_streak,   // Consecutive wins (for streak-based methods)
  current_dd_pct    // Current drawdown % (for MM10 component)
);

Without UpdateContext(): methods use last known values (stale)
```

### 2.5 Final Lot Flow

```
1. UpdateContext(atr, win_rate, streak, dd_pct)
2. primary_lot   = _CalcPrimaryLot(sl_pips)
3. secondary_lot = _CalcSecondaryLot(sl_pips)
4. tertiary_lot  = _CalcTertiaryLot(sl_pips)
5. result = CombineLots(primary, secondary, tertiary, m_combine_mode)
6. Return max(result, min_lot)
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DM_PrimaryMethod` | 1 (MM01) | Primary MM method enum value |
| `DM_SecondaryMethod` | 3 (MM03) | Secondary MM method enum value |
| `DM_TertiaryMethod` | 10 (MM10) | Tertiary MM method enum value |
| `DM_CombineMode` | 2 (WEIGHTED) | Combine mode: 0=MIN, 1=AVG, 2=WEIGHTED |
| `DM_W_Primary` | 0.50 | Primary weight (WEIGHTED mode only) |
| `DM_W_Secondary` | 0.30 | Secondary weight (WEIGHTED mode only) |
| `DM_W_Tertiary` | 0.20 | Tertiary weight (WEIGHTED mode only) |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM19_PRIMARY` | int | 1 | `m_primary_method` |
| `MM19_SECONDARY` | int | 3 | `m_secondary_method` |
| `MM19_TERTIARY` | int | 10 | `m_tertiary_method` |
| `MM19_MODE` | int | 2 | `m_combine_mode` |
| `MM19_W1` | float | 0.50 | Primary weight |
| `MM19_W2` | float | 0.30 | Secondary weight |
| `MM19_W3` | float | 0.20 | Tertiary weight |

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  MM19 DynamicMulti                                      │
├─────────────────────────────────────────────────────────┤
│  UpdateContext(atr, win_rate, streak, dd_pct)           │
├──────────────────┬──────────────────┬───────────────────┤
│  Primary (MM01)  │ Secondary (MM03) │ Tertiary (MM10)   │
│  Fixed 1% risk   │ ATR-scaled lot   │ DD-reduced lot    │
│  →  lot_A        │ →  lot_B         │ →  lot_C          │
└──────────────────┴──────────────────┴───────────────────┘
                            ↓
               CombineLots(A, B, C, mode)
                            ↓
                    WEIGHTED: A×0.5 + B×0.3 + C×0.2
```

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Use Case** | When no single MM method is sufficient alone |
| **Flexibility** | Swap any 3 methods via CONFIG_PUSH without code change |
| **No Pointer Deps** | Fully self-contained — no MM object instantiation needed |
| **Adaptability** | Python Brain can switch combine mode based on regime |
| **Standalone Ready** | Yes |
| **CPU Cost** | 3× inline calculations per lot request |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM19_DynamicMulti.mqh` | `CMM19_DynamicMulti` full implementation |

---

## 7. Quick Diagnostics

```mql5
// Must call UpdateContext before CalculateLot:
mm19.UpdateContext(atr, win_rate, streak, dd_pct);
double lot = mm19.CalculateLot(sl_pips);

mm19.GetDiagnostic();
// Output:
//   [MM19] DynamicMulti | Mode=WEIGHTED (50/30/20)
//   [MM19] Primary(MM01)=0.10 Secondary(MM03)=0.08 Tertiary(MM10)=0.05
//   [MM19] Weighted Result: 0.10×0.5 + 0.08×0.3 + 0.05×0.2 = 0.084
//   [MM19] Context: ATR=0.00082 WinRate=62% Streak=3 DD=4.2%
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Tertiary lot too small (pulling result down) | DD component very restrictive | Reduce tertiary weight (`MM19_W3` to 0.10) |
| Result lot identical every trade | Context not being updated | Ensure `UpdateContext()` called each tick |
| Weights don't sum to 1.0 | CONFIG_PUSH values incorrect | Verify W1+W2+W3 = 1.0 |
| Wrong method behavior | Method enum set incorrectly | Check `MM19_PRIMARY/SECONDARY/TERTIARY` values |

---

*MM19 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
