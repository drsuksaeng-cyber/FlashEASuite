# FlashEASuite V2 — Money Management Reference

> **Version:** V6 (P9-5) | **Date:** 2026-03-01
> **Total MM Methods:** 19 | **All implemented in MQL5**

---

## Overview

Money Management (MM) ใน FlashEASuite V2 ทำงานผ่าน `IMoneyManager` interface:

```cpp
interface IMoneyManager {
    double CalculateLot(string symbol, double sl_points, double confidence);
    void   UpdateTradeResult(bool win, double pnl, double rr);
    string GetDiagnostic();
}
```

Brain เลือก MM method ที่เหมาะสมกับ regime ปัจจุบัน และส่งมาใน CONFIG_PUSH พร้อมกับ `risk_multiplier` (0.5–2.0×)

---

## MM Method Index

| # | Enum Name | Index | Category | Risk Level | Best Regime |
|---|-----------|-------|----------|------------|-------------|
| 01 | MM01_FIXED_CONSERVATIVE | 0 | Fixed | Conservative | Any |
| 02 | MM02_FIXED_AGGRESSIVE | 1 | Fixed | Aggressive | TRENDING |
| 03 | MM03_ATR_BASED | 2 | Dynamic | Moderate | VOLATILE |
| 04 | MM04_KELLY_CRITERION | 3 | Statistical | Moderate | Any |
| 05 | MM05_MARTINGALE_CONTROLLED | 4 | Martingale | High | RANGING |
| 06 | MM06_ANTI_MARTINGALE | 5 | Anti-Mart | Moderate | TRENDING |
| 07 | MM07_PCT_VOLATILITY | 6 | Dynamic | Moderate | Any |
| 08 | MM08_PYRAMID | 7 | Scale-In | Moderate | TRENDING |
| 09 | MM09_EQUITY_CURVE_RECOVERY | 8 | Adaptive | Conservative | Drawdown |
| 10 | MM10_DRAWDOWN_BASED | 9 | Adaptive | Moderate | Any |
| 11 | MM11_SESSION_BASED | 10 | Time-based | Moderate | Any |
| 12 | MM12_EQUITY_CURVE_FILTER | 11 | Filter | Conservative | Any |
| 13 | MM13_CORRELATION_ADJUSTED | 12 | Portfolio | Moderate | Multi-symbol |
| 14 | MM14_TIERED_RISK | 13 | Tiered | Variable | Any |
| 15 | MM15_ADAPTIVE_WIN_STREAK | 14 | Streak | Moderate | TRENDING |
| 16 | MM16_VOLATILITY_PERCENTILE | 15 | Dynamic | Moderate | VOLATILE |
| 17 | MM17_REGIME_BASED | 16 | Regime-aware | Variable | All |
| 18 | MM18_PORTFOLIO_CAP | 17 | Portfolio | Conservative | Multi-symbol |
| 19 | MM19_DYNAMIC_MULTI | 18 | Combined | Variable | All |

---

## MM Methods — Full Detail

---

### MM01 — Fixed Conservative

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM01_FixedConservative.mqh` |
| Risk Level | Very Low |
| Lot Calculation | Fixed = `base_lot` (constant) |
| Best For | Beginners, Demo, initial testing |

**Formula:**
```
lot = base_lot × risk_multiplier
```

**Parameters:**
```
BASE_LOT        = 0.01    Fixed lot size
```

**Use case:** เริ่มต้นทดสอบระบบ, Demo account, หรือเมื่อต้องการความแน่นอน 100% ว่า lot จะไม่เปลี่ยน

**สรุปแนวคิด:** ง่ายที่สุด — lot เท่าเดิมทุก trade ไม่ว่าตลาดจะเป็นอย่างไร ปลอดภัยสูงสุด แต่ไม่ optimize ผลตอบแทน

---

### MM02 — Fixed Aggressive

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM02_FixedAggressive.mqh` |
| Risk Level | High |
| Lot Calculation | Fixed = `base_lot` (larger than MM01) |
| Best For | Experienced traders, strong trending market |

**Formula:**
```
lot = base_lot × risk_multiplier    (base_lot >> 0.01, e.g., 0.10)
```

**Parameters:**
```
BASE_LOT        = 0.10    Fixed lot size (10× MM01)
MAX_LOT         = 5.00    Hard cap
```

**Warning:** ไม่แนะนำสำหรับผู้เริ่มต้น — lot สูงอาจเสียง margin call เร็ว

**สรุปแนวคิด:** เหมือน MM01 แต่ใช้ lot ใหญ่กว่า เหมาะเมื่อมั่นใจในระบบและต้องการ return สูงขึ้น

---

### MM03 — ATR-Based Dynamic Sizing

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM03_ATRBased.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Based on ATR (volatility-adjusted) |
| Best For | All market conditions (adapts to volatility) |

**Formula:**
```
risk_amount = account_balance × risk_pct / 100
atr_in_currency = ATR(period) × contract_size / pip_value
lot = risk_amount / atr_in_currency
lot = Clamp(lot, min_lot, max_lot)
```

**Logic:** ATR สูง → lot เล็กลง (ตลาดแกว่งแรง), ATR ต่ำ → lot ใหญ่ขึ้น (ตลาดนิ่ง)

**Parameters:**
```
RISK_PCT        = 1.0     % of balance to risk per trade
ATR_PERIOD      = 14      ATR calculation period
MIN_LOT         = 0.01    Minimum lot
MAX_LOT         = 10.0    Maximum lot
```

**สรุปแนวคิด:** ตลาดแกว่งแรง (ATR สูง) → lot เล็กลงอัตโนมัติ ตลาดนิ่ง (ATR ต่ำ) → lot ใหญ่ขึ้น ป้องกัน over-exposure ในช่วงที่ตลาดผันผวน

---

### MM04 — Kelly Criterion

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM04_KellyCriterion.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Kelly formula based on win rate + avg R:R |
| Best For | Systems with consistent win rate + R:R data |

**Formula:**
```
Kelly_pct = win_rate - (1 - win_rate) / avg_rr
Kelly_fraction = Kelly_pct × kelly_fraction_multiplier   // fractional Kelly
risk_amount = account_balance × Kelly_fraction / 100
lot = risk_amount / (sl_points × pip_value)
```

**Note:** Fractional Kelly (0.5× หรือ 0.25×) แนะนำมากกว่า Full Kelly เพื่อลดความเสี่ยง

**Parameters:**
```
KELLY_FRACTION  = 0.25    Fraction of full Kelly (0.25 = quarter-Kelly)
WIN_RATE_INIT   = 0.55    Initial win rate (updated from feedback)
AVG_RR_INIT     = 1.5     Initial R:R ratio (updated from feedback)
MIN_TRADES      = 30      Min trades before using live win rate
```

**สรุปแนวคิด:** Kelly คำนวณ "ขนาด bet ที่เหมาะสมที่สุด" ตาม probability — ชนะบ่อย + R:R ดี → bet ใหญ่ขึ้น ชนะน้อย → bet เล็กลงอัตโนมัติ

---

### MM05 — Martingale Controlled

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM05_MartingaleControlled.mqh` |
| Risk Level | High (controlled by caps) |
| Lot Calculation | Double lot after each loss, reset after win |
| Best For | RANGING market with high win rate strategy |

**Formula:**
```
lot = base_lot × multiplier^consecutive_losses
lot = Min(lot, max_lot_cap)   // MUST have cap
```

**Safety mechanisms:**
- Hard max lot cap (prevents runaway)
- Max consecutive loss limit (stops martingale after N losses)
- Daily loss limit from RiskGuardian overrides

**Parameters:**
```
BASE_LOT        = 0.01    Starting lot
MULTIPLIER      = 2.0     Lot doubling factor
MAX_LEVELS      = 4       Max martingale levels (lot = 0.01×2^4 = 0.16)
MAX_LOT_CAP     = 0.20    Absolute lot cap
```

**Warning:** ❗ Martingale ไม่มีวันสิ้นสุดในทางทฤษฎี — ต้องมี cap เสมอ ไม่แนะนำสำหรับ TRENDING market

**สรุปแนวคิด:** เพิ่ม lot เมื่อแพ้ หวังว่าเมื่อชนะจะกู้คืนได้ — ต้องมี win rate สูงมาก และ cap ที่ชัดเจน ไม่งั้นจะ blow account

---

### MM06 — Anti-Martingale

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM06_AntiMartingale.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Increase lot after wins, reduce after losses |
| Best For | TRENDING market, strong win streaks |

**Formula:**
```
lot = base_lot × multiplier^consecutive_wins
lot = Max(base_lot, lot)    // never go below base
lot = Min(lot, max_lot)     // cap at max
// After loss: reset to base_lot
```

**Philosophy:** ตรงข้ามกับ Martingale — เพิ่มขนาดเมื่อระบบ "on fire" ลดความเสี่ยงเมื่อระบบไม่ดี

**Parameters:**
```
BASE_LOT        = 0.01    Starting/reset lot
MULTIPLIER      = 1.5     Lot increase per win
MAX_LOT         = 0.50    Maximum lot
RESET_ON_LOSS   = true    Reset to base on first loss
```

**สรุปแนวคิด:** "Let profits run, cut losses" ในแง่ position sizing — เมื่อชนะต่อเนื่องให้ bet ใหญ่ขึ้น เมื่อแพ้ให้ลด lot ทันที ลดความเสียหายจาก drawdown

---

### MM07 — Percentage Volatility

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM07_PctVolatility.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Risk % × account / (volatility in currency) |
| Best For | Any market condition |

**Formula:**
```
daily_vol = StdDev(daily_returns, lookback) × sqrt(252) / sqrt(252) × price
risk_amount = account_balance × risk_pct / 100
lot = risk_amount / (daily_vol × sl_mult)
```

**More sophisticated than MM03:** ใช้ realized volatility (standard deviation of returns) แทน ATR เดียว

**Parameters:**
```
RISK_PCT        = 1.0     % of balance to risk
VOL_LOOKBACK    = 20      Days for volatility calculation
SL_MULT         = 2.0     Volatility × this = SL distance
```

**สรุปแนวคิด:** Risk budget คงที่เป็น % ของ balance แต่ขนาด lot ปรับตาม volatility จริงของตลาด — ใกล้เคียงกับ professional fund management

---

### MM08 — Pyramid (Scale-In)

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM08_Pyramid.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Add to winning positions at intervals |
| Best For | Strong TRENDING market |

**Pyramid mechanics:**
```
Unit 1: Entry   → lot = base_lot           (at breakout)
Unit 2: + 0.5×ATR → lot = base_lot × 0.75  (first add)
Unit 3: + 1.0×ATR → lot = base_lot × 0.50  (second add)
Unit 4: + 1.5×ATR → lot = base_lot × 0.25  (third add)
// Smaller lot per unit as price extends (inverted pyramid)
```

**Trail SL:** Move SL up to protect each unit's entry after adding

**Parameters:**
```
BASE_LOT        = 0.01    First unit lot
MAX_PYRAMID_UNITS = 4     Maximum units to add
UNIT_SIZE_DECAY = 0.75    Each unit = previous × this
ATR_STEP_MULT   = 0.5     Add unit every X × ATR
```

**สรุปแนวคิด:** "เพิ่มสินค้าเมื่อราคายืนยัน trend" — ไม่ใช่ averaging down แต่คือ averaging up เข้าสู่ profitable position เมื่อ trend ชัดเจนขึ้น

---

### MM09 — Equity Curve Recovery

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM09_EquityCurveRecovery.mqh` |
| Risk Level | Low (in drawdown), Normal (in profit) |
| Lot Calculation | Reduced lot during drawdown, normal otherwise |
| Best For | Recovery from drawdown periods |

**Logic:**
```
current_equity_ma = EMA(equity, period)
if equity < equity_ma × (1 - drawdown_threshold):
    lot = base_lot × recovery_factor    // e.g., 0.5× during drawdown
else:
    lot = normal_lot_calculation()       // normal sizing
```

**Parameters:**
```
DD_THRESHOLD    = 0.05    5% below EMA triggers recovery mode
RECOVERY_FACTOR = 0.5     Trade at 50% normal size in recovery
MA_PERIOD       = 20      EMA period for equity curve
```

**สรุปแนวคิด:** เมื่อ equity curve หักลง → ลด bet เพื่อป้องกัน "death spiral" เมื่อ equity กลับสู่ MA → กลับ lot ปกติ ใช้ได้ดีกับทุก strategy

---

### MM10 — Drawdown-Based Sizing

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM10_DrawdownBased.mqh` |
| Risk Level | Adaptive |
| Lot Calculation | Reduces proportionally to current drawdown % |
| Best For | Capital preservation focus |

**Formula:**
```
current_dd = (peak_equity - current_equity) / peak_equity
reduction = 1.0 - (current_dd / max_allowed_dd)
lot = normal_lot × reduction
lot = Max(lot, min_lot)
```

**Parameters:**
```
MAX_ALLOWED_DD  = 0.20    20% max drawdown threshold
MIN_LOT_FACTOR  = 0.25    Never go below 25% of normal lot
```

**สรุปแนวคิด:** ยิ่ง drawdown มาก ยิ่งลด lot มาก — เหมือนการ "ลดความเร็ว" เมื่อถนนลื่น ป้องกันการเสียทุนทั้งหมดขณะที่ระบบอยู่ในช่วงแย่

---

### MM11 — Session-Based

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM11_SessionBased.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Different lot sizes for different trading sessions |
| Best For | Session-aware trading |

**Session lots:**
```
Sydney  session (04:00-13:00 GMT+7): lot × 0.5    (low liquidity)
Tokyo   session (06:00-15:00 GMT+7): lot × 0.7    (moderate)
London  session (14:00-23:00 GMT+7): lot × 1.0    (full)
New York session (19:00-04:00 GMT+7): lot × 1.2   (full + USD active)
NY+London overlap (19:00-23:00):     lot × 1.5    (peak liquidity)
```

**Parameters:**
```
BASE_LOT        = 0.01    Base lot (full session)
SYDNEY_MULT     = 0.50    Sydney session multiplier
TOKYO_MULT      = 0.70    Tokyo session multiplier
LONDON_MULT     = 1.00    London session multiplier
NY_MULT         = 1.20    New York session multiplier
OVERLAP_MULT    = 1.50    London-NY overlap multiplier
```

**สรุปแนวคิด:** ไม่ใช่ทุก session เท่ากัน — London-NY overlap มี liquidity สูงที่สุด spread ต่ำสุด → ใช้ lot ใหญ่ขึ้น Tokyo/Sydney → lot เล็กลง

---

### MM12 — Equity Curve Filter

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM12_EquityCurveFilter.mqh` |
| Risk Level | Conservative |
| Lot Calculation | Binary: Trade full size OR pause (stop trading) |
| Best For | Strategy performance gating |

**Logic:**
```
equity_above_ma = current_equity > EMA(equity_history, period)
if equity_above_ma:
    TRADE (normal lot)
else:
    PAUSE (no new trades, or minimal lot)
```

**Philosophy:** หยุด trade เมื่อระบบ "underperforming" (equity ต่ำกว่า MA) กลับมาเมื่อ equity ฟื้นขึ้นเหนือ MA

**Parameters:**
```
MA_PERIOD       = 20      EMA period for equity curve
PAUSE_LOT       = 0.0     0 = full pause, >0 = reduced lot when below MA
```

**สรุปแนวคิด:** เหมือน circuit breaker — เมื่อระบบอยู่ใน "bad period" ให้หยุดก่อน อย่าฝืน เพราะอาจเสียมากกว่า ถ้า equity กลับมาดี ค่อย trade ใหม่

---

### MM13 — Correlation-Adjusted

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM13_CorrelationAdjusted.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Reduce lot for correlated positions |
| Best For | Multi-symbol trading |

**Logic:**
```
open_positions_correlation = calc_correlation(all_open_symbols)
if high_correlation (> threshold):
    reduce lot to avoid double-exposure
    combined_risk = target_risk_per_trade
else:
    normal lot
```

**Example:** ถ้าเปิด EURUSD Long + GBPUSD Long พร้อมกัน (correlation ~0.85) → ลด lot ทั้งคู่ เพราะจริงๆ คือ Short USD เท่านั้น

**Parameters:**
```
CORRELATION_THRESHOLD = 0.7    High correlation threshold
LOT_REDUCTION_FACTOR  = 0.6    Reduce to 60% when correlated
LOOKBACK_PERIOD       = 20     Days for correlation calculation
```

**สรุปแนวคิด:** เมื่อเปิด position หลายตัวที่ move ไปด้วยกัน จริงๆ คือ risk เดียว — ลด lot เพื่อให้ total exposure ต่อ "risk factor" ไม่เกิน target

---

### MM14 — Tiered Risk

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM14_TieredRisk.mqh` |
| Risk Level | Variable (confidence-based) |
| Lot Calculation | Higher confidence = larger lot |
| Best For | AI-driven strategy selection |

**Tiers:**
```
Confidence 0.50–0.60: lot = base_lot × 0.5     (low confidence)
Confidence 0.60–0.70: lot = base_lot × 0.75    (moderate)
Confidence 0.70–0.80: lot = base_lot × 1.0     (normal)
Confidence 0.80–0.90: lot = base_lot × 1.25    (high)
Confidence 0.90–1.00: lot = base_lot × 1.5     (very high)
```

**Parameters:**
```
BASE_LOT        = 0.01    Lot at 0.70–0.80 confidence tier
TIER_THRESHOLDS = [0.50, 0.60, 0.70, 0.80, 0.90]
TIER_MULTIPLIERS = [0.5, 0.75, 1.0, 1.25, 1.5]
```

**สรุปแนวคิด:** Brain ให้ confidence score ต่อ signal — ยิ่งมั่นใจมาก ยิ่ง bet ใหญ่ ยิ่งไม่แน่ใจ ยิ่ง bet เล็ก สอดคล้องกับ Kelly principle

---

### MM15 — Adaptive Win Streak

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM15_AdaptiveWinStreak.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Adjust based on recent win/loss streak |
| Best For | TRENDING market with strategy momentum |

**Formula:**
```
streak_factor = 1.0 + (win_streak × increment_per_win)
streak_factor = 1.0 - (loss_streak × decrement_per_loss)
streak_factor = Clamp(streak_factor, min_factor, max_factor)
lot = base_lot × streak_factor
```

**Parameters:**
```
BASE_LOT        = 0.01    Base lot
INCREMENT_WIN   = 0.10    +10% per consecutive win
DECREMENT_LOSS  = 0.15    -15% per consecutive loss (asymmetric)
MAX_FACTOR      = 2.0     Maximum multiplier (2× base)
MIN_FACTOR      = 0.5     Minimum multiplier (50% base)
```

**สรุปแนวคิด:** ใช้ "momentum ของระบบ" — ชนะต่อเนื่อง → เพิ่ม lot (ระบบ on fire), แพ้ต่อเนื่อง → ลด lot (ระบบมีปัญหา) ไม่สมมาตร (ลดเร็วกว่าเพิ่ม) เพื่อความปลอดภัย

---

### MM16 — Volatility Percentile

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM16_VolatilityPercentile.mqh` |
| Risk Level | Moderate |
| Lot Calculation | Inverse of volatility percentile |
| Best For | VOLATILE market condition |

**Formula:**
```
current_atr = ATR(period)
atr_percentile = percentile_rank(current_atr, atr_history, lookback)
// high percentile = high volatility = reduce lot
lot_factor = 1 - (atr_percentile / 100)
lot = base_lot × lot_factor × 2    // scaled so avg lot ≈ base_lot
lot = Clamp(lot, min_lot, max_lot)
```

**Example:** ATR at 80th percentile (high vol) → lot = base × 0.4; ATR at 20th percentile (low vol) → lot = base × 1.6

**Parameters:**
```
ATR_PERIOD      = 14      ATR period
PERCENTILE_LOOKBACK = 100 Historical bars for percentile calculation
BASE_LOT        = 0.01    Reference lot
```

**สรุปแนวคิด:** ไม่ใช่แค่ดู ATR ตัวเลข แต่เปรียบเทียบ ATR กับประวัติ — ATR สูงที่สุดในรอบ 100 bars → lot เล็กมาก, ATR ต่ำผิดปกติ → lot ใหญ่ขึ้น

---

### MM17 — Regime-Based

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM17_RegimeBased.mqh` |
| Risk Level | Variable |
| Lot Calculation | Different lot per regime type |
| Best For | Multi-regime adaptive trading |

**Regime lots:**
```
TRENDING  regime: lot × 1.2    (trend = higher confidence)
RANGING   regime: lot × 1.0    (normal)
VOLATILE  regime: lot × 0.7    (volatile = lower size)
SQUEEZE   regime: lot × 0.5    (pre-breakout = cautious)
UNKNOWN   regime: lot × 0.5    (uncertain = minimal)
```

**Parameters:**
```
BASE_LOT        = 0.01    Base lot at RANGING regime
TRENDING_MULT   = 1.20    Multiplier for TRENDING
RANGING_MULT    = 1.00    Multiplier for RANGING
VOLATILE_MULT   = 0.70    Multiplier for VOLATILE
SQUEEZE_MULT    = 0.50    Multiplier for SQUEEZE
```

**สรุปแนวคิด:** ปรับ lot ตาม "บรรยากาศของตลาด" — ตลาด TRENDING มี momentum → ใช้ lot ใหญ่ขึ้น ตลาด VOLATILE อันตราย → ลด lot ป้องกันตัว

---

### MM18 — Portfolio Cap

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM18_PortfolioCap.mqh` |
| Risk Level | Conservative |
| Lot Calculation | Cap total portfolio exposure |
| Best For | Multi-symbol trading, risk budget management |

**Logic:**
```
total_open_risk = Sum(open_position_lot × sl_points × pip_value)
remaining_budget = max_portfolio_risk - total_open_risk
lot = normal_calculated_lot
if (lot × sl_points × pip_value > remaining_budget):
    lot = remaining_budget / (sl_points × pip_value)
lot = Max(lot, min_lot_or_skip)
```

**Parameters:**
```
MAX_PORTFOLIO_RISK_PCT = 5.0    Max % of balance at risk across ALL positions
MIN_LOT              = 0.01    Minimum lot (if below → skip trade)
```

**สรุปแนวคิด:** "Total risk budget" สำหรับทั้ง portfolio — ถ้า positions ที่เปิดอยู่รวมกันใช้ risk ครบแล้ว → ไม่เปิด position ใหม่จนกว่าจะปิด position เก่า

---

### MM19 — Dynamic Multi (Combined)

| Property | Value |
|----------|-------|
| File | `Include/Logic/MM/MM19_DynamicMulti.mqh` |
| Risk Level | Variable |
| Lot Calculation | Weighted combination of multiple MM methods |
| Best For | Production trading (best overall method) |

**Formula:**
```
lot_kelly = MM04_KellyCriterion.CalculateLot(...)
lot_atr   = MM03_ATRBased.CalculateLot(...)
lot_regime = MM17_RegimeBased.CalculateLot(...)

lot = (w_kelly × lot_kelly + w_atr × lot_atr + w_regime × lot_regime)
    / (w_kelly + w_atr + w_regime)

// Apply portfolio cap (MM18)
lot = MM18_PortfolioCap.Apply(lot)

// Apply equity curve filter (MM12)
if MM12_EquityCurveFilter.IsPaused(): lot = 0
```

**Default weights:**
```
W_KELLY         = 0.3     30% Kelly Criterion
W_ATR           = 0.4     40% ATR-based (most stable)
W_REGIME        = 0.3     30% Regime-based
```

**สรุปแนวคิด:** รวมจุดแข็งของหลาย MM methods — Kelly สำหรับ probability optimization, ATR สำหรับ volatility adaptation, Regime สำหรับ market context awareness แล้ว cap ด้วย portfolio limit

---

## MM Selection Guide

### By Experience Level

| Level | Recommended MM |
|-------|---------------|
| Beginner | MM01 (Fixed Conservative) |
| Intermediate | MM03 (ATR-Based) or MM07 (% Volatility) |
| Advanced | MM04 (Kelly) or MM17 (Regime-Based) |
| Expert / Production | MM19 (Dynamic Multi) |

### By Strategy Type

| Strategy Type | Best MM Methods |
|--------------|-----------------|
| Single-direction trend | MM06 (Anti-Mart), MM08 (Pyramid) |
| Mean reversion | MM03 (ATR), MM12 (Equity Filter) |
| Grid | MM01 (Fixed) or MM18 (Portfolio Cap) |
| Spike | MM16 (Volatility Percentile), MM03 (ATR) |
| AI-driven (Brain active) | MM14 (Tiered Risk), MM19 (Dynamic Multi) |
| Multi-symbol | MM13 (Correlation), MM18 (Portfolio Cap) |

### Brain-Recommended Defaults

| Regime | Default MM | Reasoning |
|--------|-----------|-----------|
| TRENDING | MM06 + MM17 | Let profits grow with trend |
| RANGING | MM03 + MM12 | ATR-sized, pause when equity drops |
| VOLATILE | MM16 + MM18 | Low lot, portfolio cap |
| SQUEEZE | MM01 + MM18 | Fixed small lot, wait for breakout |

---

## RiskGuardian Integration

All MM methods are subject to RiskGuardian overrides:

```cpp
// Include/Risk/RiskGuardian.mqh
DD_DAILY_LIMIT_PCT  = 2.0    // Daily loss limit (% of balance)
MAX_DRAWDOWN_PCT    = 20.0   // Max total drawdown before halt
MAX_OPEN_TRADES     = 10     // Maximum simultaneous positions
MAX_LOT_PER_SYMBOL  = 1.0    // Max lot on any single symbol
```

**Override hierarchy:**
1. Brain `risk_multiplier` (0.5×–2.0×) from CONFIG_PUSH
2. MM method lot calculation
3. RiskGuardian hard caps (CANNOT be overridden)
4. Broker minimum/maximum lot constraints

---

*FlashEASuite V2 Money Management Reference — V6 P9-5 | 2026-03-01*
