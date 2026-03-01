# MM18 — Portfolio Risk Cap
## FlashEASuite V2 | Money Management Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Overview

| Field | Value |
|-------|-------|
| **MM ID** | MM18 |
| **Name** | Portfolio Risk Cap |
| **MQL5 Class** | `CMM18_PortfolioCap` |
| **Magic Prefix** | MAGIC_MM18 |
| **Version** | 6.00 |
| **Standalone Ready** | Yes |

### สรุปแนวคิด (Thai)

MM18 คำนวณ **Total Open Risk %** จากทุก Position ที่เปิดอยู่ รวมกัน เมื่อ Total Risk ถึง Cap (default 10%) → ลด Lot ของ Trade ใหม่ลง หรือ Block ไม่ให้เปิดเพิ่ม ป้องกัน over-exposure ระดับ Portfolio เช่น ถ้า 5 Strategy เปิดพร้อมกัน Risk รวมต้องไม่เกิน 10% Per-trade max = 2%

---

## 2. Core Theory

### 2.1 Open Risk Calculation

```
For each open position (PositionsTotal()):
  Get: lot_size, stop_loss, current_price, symbol
  Calculate SL distance in pips:
    sl_distance_pips = |current_price - stop_loss| / pip_size

  Risk amount = lot_size × sl_distance_pips × pip_value_per_lot
  Risk pct    = risk_amount / AccountBalance × 100

Sum all positions:
  total_open_risk_pct = SUM(position_risk_pct)

Note: Only positions WITH a real SL set are counted.
      Positions without SL are ignored (not counted as capped risk).
```

### 2.2 Cap Enforcement

```
When CalculateLot() is called for a new trade:

  remaining_cap = m_portfolio_cap - total_open_risk_pct

  if remaining_cap <= 0:
    → Return 0 (block new trade — portfolio is fully used)

  if new_trade_risk > remaining_cap:
    → Scale lot down to fit within remaining_cap
    → reduced_lot = (remaining_cap × balance) / (sl_pips × pip_value × 100)

  if new_trade_risk <= remaining_cap:
    → Use normal lot calculation (per-trade cap still applies)
```

### 2.3 Per-Trade Maximum

```
Per-trade max risk: m_max_per_trade_pct (default 2.0%)

A single trade can never exceed 2% of balance regardless of:
  - Portfolio remaining capacity
  - Strategy request

Final lot = min(normal_lot, lot_at_max_per_trade, lot_at_remaining_cap)
```

### 2.4 GetOpenRiskPct()

```
Public accessor for current portfolio utilization:
  GetOpenRiskPct() — returns total_open_risk_pct (0.0 to m_portfolio_cap+)

EA / Python Brain can use this to:
  - Display portfolio gauge on dashboard
  - Suppress low-confidence strategies when near cap
  - Alert when portfolio approaches 80% of cap
```

---

## 3. Parameter Reference

### 3.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PC_PortfolioCap` | 10.0 | Max total open risk % across all positions |
| `PC_MaxPerTrade` | 2.0 | Max risk % for any single new trade |
| `PC_BaseRisk` | 1.0 | Target risk % when portfolio has room |

### 3.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `MM18_PORT_CAP` | float | 10.0 | `m_portfolio_cap` |
| `MM18_MAX_TRADE` | float | 2.0 | `m_max_per_trade_pct` |
| `MM18_BASE_RISK` | float | 1.0 | `m_base_risk_pct` |

---

## 4. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Use Case** | Multi-strategy EA running 5–16 strategies simultaneously |
| **Protection** | Prevents 16 strategies each at 1% = 16% total risk |
| **Interaction** | Works with any base lot calculation; acts as final cap |
| **SL Requirement** | Positions must have real broker SL for accurate count |
| **Standalone Ready** | Yes |
| **CPU Cost** | Scans PositionsTotal() on every CalculateLot() call |

---

## 5. Files Reference

| File | Role |
|------|------|
| `Include/Logic/MM/MM18_PortfolioCap.mqh` | `CMM18_PortfolioCap` full implementation |

---

## 6. Quick Diagnostics

```mql5
mm18.GetDiagnostic();
// Output:
//   [MM18] PortfolioCap | OpenRisk=7.3% | Cap=10.0% | Remaining=2.7%
//   [MM18] Positions=5 | MaxPerTrade=2.0% | BaseLot=0.10 → CapLot=0.08
//   [MM18] Status=OPEN (under cap)

double open_risk = mm18.GetOpenRiskPct();
bool blocked = (mm18.CalculateLot(sl_pips) == 0);
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Always blocked (lot=0) | Portfolio cap reached by existing positions | Close some positions or raise `MM18_PORT_CAP` |
| Risk% always 0 | Open positions have no SL set | Ensure every opened trade has broker SL |
| Cap too restrictive | 10% with 10 strategies = only 1% each | Raise to 15–20% or reduce strategies |
| Lot larger than expected | Per-trade cap not applied | Verify `MM18_MAX_TRADE` is set correctly |

---

*MM18 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
