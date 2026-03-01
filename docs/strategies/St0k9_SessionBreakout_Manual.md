# S09 — London/NY Session Breakout
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: 2026-02-27 | Phase P9-5

---

## 1. Strategy Overview

| Field | Value |
|-------|-------|
| **Strategy ID** | S09 |
| **Enum Name** | `S09_SESSION_BREAKOUT` |
| **Enum Index** | 8 (0-based array index in g_strategy_table) |
| **Name** | Session Breakout (London/NY) |
| **Type** | Full MQL5 (`CAT_FULL_MQL5`) |
| **Standalone Capable** | No — Server Only |
| **Preferred Regime** | VOLATILE (`REGIME_VOLATILE` — breakouts thrive on session volatility) |
| **Alt Regime** | TRENDING (`REGIME_TRENDING`) |
| **Poor Regimes** | RANGING (Asian range too small; breakout fails; no momentum) |
| **MQL5 Class** | `CSessionBreakout` |
| **Magic Number** | 1009 (`MAGIC_S09_SESSION_BO`) |
| **Family** | Time-based |
| **Version** | 6.00 |

### สรุปแนวคิด (Thai)

S09 เทรด **Session Breakout** — วัด Range ของ Asian Session (00:00-08:00 GMT) จากนั้นรอให้ราคาทะลุออกนอก Range ในช่วง London Open (08:00-12:00 GMT) หรือ NY Open (13:00-17:00 GMT) เมื่อราคาทะลุ Asian High → BUY, ทะลุ Asian Low → SELL TP = 1.5× Asian Range, SL = ด้านในของ Range (risk ต่ำ) ตรรกะ: แต่ละ session มีทิศทางที่ชัดเจนกว่าตอน Asian โดยเฉพาะ London ที่มี liquidity สูงสุด

---

## 2. Core Theory

### 2.1 Session Windows (GMT)

```
Asian Session:  00:00–08:00 GMT  → Collect High/Low to define range
London Session: 08:00–12:00 GMT  → Trade breakout from Asian range
NY Session:     13:00–17:00 GMT  → Trade breakout from London range
Dead Zone:      12:00–13:00 GMT  → No trades (London close / NY gap)
No-Trade:       17:00+  GMT     → Session closed, no new trades

Broker adjustment: All times adjusted by SB_BrokerGMT_Offset (default +3)
```

### 2.2 Asian Range Capture

```
Method 1 (live): Track ask/bid highs and lows during Asian session hours
Method 2 (H1 scan): At London open if no live range, scan recent H1 bars

Filter: asian_range >= m_range_min_pips (default 20 pips)
  If range < 20 pips → skip trading today (too small to trade)

m_asian_high = highest ask seen during Asian session
m_asian_low  = lowest bid seen during Asian session
```

### 2.3 London Breakout Logic

```
Breakout buffer = max(m_breakout_buffer × pip, 0.10 × ATR)
  Default: max(3 pips, 10% of H1 ATR)

Long trigger:  ask >= m_asian_high + buffer
Short trigger: bid <= m_asian_low  - buffer

Rules:
  m_london_broken_up = true  → fires SIGNAL_BUY (once per session day)
  m_london_broken_dn = true  → fires SIGNAL_SELL (once per session day)
  One breakout per direction per day — no second entries
```

### 2.4 NY Breakout Logic

```
NY uses the London session range (built during 08:00-12:00):
  ny_high  = max(London range high) or Asian high if London not captured
  ny_low   = min(London range low)  or Asian low  if not captured

Same trigger logic as London, but:
  Confidence factor = 0.75 (25% lower than London — NY has less volume)
```

### 2.5 TP / SL

```
London BUY:
  TP = ask + asian_range × m_tp_range_mult    = ask + 1.5 × Asian range
  SL = asian_low + asian_range × m_sl_inside_ratio = lower inside range

London SELL:
  TP = bid - asian_range × m_tp_range_mult
  SL = asian_high - asian_range × m_sl_inside_ratio = higher inside range

Default m_tp_range_mult = 1.5, m_sl_inside_ratio = 0.5

R:R calculation:
  Entry at breakout (at range boundary + buffer)
  SL = 50% inside range from opposite side
  TP = 150% of range from entry
  Approximate R:R ≈ 1.5 / 0.5 = 3.0 (variable based on buffer)
```

### 2.6 Confidence

```
range_atr_ratio = (asian_high - asian_low) / ATR_H1
range_factor    = min(1.0, range_atr_ratio / 2.0)
  Optimal: range ≈ 1×ATR → ratio = 0.5 → factor = 0.25
           range ≈ 2×ATR → ratio = 1.0 → factor = 0.5
           range ≈ 4×ATR → ratio = 2.0 → factor = 1.0

session_factor: London = 1.0, NY = 0.75

Confidence = range_factor × session_factor
```

---

## 3. State Machine

```
Daily State (reset at midnight broker time):
  m_asian_range_valid   → false (no range yet)
  m_london_broken_up/dn → false (no London breakout yet)
  m_ny_broken_up/dn     → false (no NY breakout yet)
  m_london_high/low     → track London range for NY

Transitions:
  00:00 GMT → Asian: collect range tick by tick
  08:00 GMT → London: check breakout each tick
  12:00 GMT → Dead zone: SIGNAL_NONE
  13:00 GMT → NY: check breakout against London range
  17:00 GMT → No-trade: SIGNAL_NONE for rest of day
  Next day midnight → Reset all state
```

---

## 4. Parameter Reference

### 4.1 MQL5 Input Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SB_Asian_Start` | 0 | Asian session start GMT hour |
| `SB_Asian_End` | 7 | Asian session end GMT hour |
| `SB_London_Start` | 8 | London session start GMT hour |
| `SB_London_End` | 12 | London session end |
| `SB_NY_Start` | 13 | NY session start GMT hour |
| `SB_NY_End` | 17 | NY session end (no trades after) |
| `SB_Range_Min_Pips` | 20 | Min Asian range to trade |
| `SB_Breakout_Buffer` | 3.0 | Breakout buffer pips (false break filter) |
| `SB_SL_Inside_Ratio` | 0.5 | SL placement inside range (ratio) |
| `SB_TP_Range_Mult` | 1.5 | TP = N × Asian range |
| `SB_ATR_Period` | 14 | ATR period (H1 timeframe) |
| `SB_BrokerGMT_Offset` | 3 | Broker server GMT offset (+3 = EET) |

### 4.2 CONFIG_PUSH Keys (Server Mode)

| Key | Type | Default | Maps To |
|-----|------|---------|---------|
| `S09_ASIAN_START` | int | 0 | `m_asian_start` |
| `S09_ASIAN_END` | int | 7 | `m_asian_end` |
| `S09_LONDON_START` | int | 8 | `m_london_start` |
| `S09_NY_START` | int | 13 | `m_ny_start` |
| `S09_RANGE_MIN` | int | 20 | `m_range_min_pips` |
| `S09_BREAKOUT_BUF` | float | 3.0 | `m_breakout_buffer` |
| `S09_SL_INSIDE` | float | 0.5 | `m_sl_inside_ratio` |
| `S09_TP_RANGE_MULT` | float | 1.5 | `m_tp_range_mult` |

**Session hour changes** invalidate the Asian range and trigger a re-scan.

---

## 5. Performance Characteristics

| Aspect | Detail |
|--------|--------|
| **Best Condition** | Clear directional breakout from tight Asian range (10–25 pip range) |
| **Worst Condition** | Asian range too wide (>50 pips) — SL becomes large |
| **Typical Duration** | 1–4 hours (momentum trade) |
| **R:R Ratio** | ~3.0 (1.5× range TP / 0.5× range inside SL) |
| **Max Trades/Day** | 2 (1 London + 1 NY, one direction each) |
| **ATR Timeframe** | H1 (better volatility reference for session analysis) |
| **Standalone** | No (listed Server Only in architecture) |

---

## 6. Files Reference

| File | Role |
|------|------|
| `Include/Logic/Strategies/S09_SessionBreakout.mqh` | `CSessionBreakout` full implementation |
| `03_Trader/ProgramC_Trader.mq5` | Routes ticks and manages session state |

---

## 7. Quick Diagnostics

```mql5
s09.PrintSessionStatus();
// Output:
//   [S09] Asian Range | H=1.08620 L=1.08390 Range=23.0 pips | ATR=0.00087 | RangeOK=YES
//   [S09] Breakout state | LondonLong=FIRED LondonShort=ready NYLong=ready NYShort=ready
```

```
[S09] Init OK | EURUSD PERIOD_M1 | Asian 00:00-07:00 GMT | London 08:00 | NY 13:00
[S09] LONDON LONG | Ask=1.08635 | Asian H=1.08620 L=1.08390 | Range=0.00230 | TP=1.08980 SL=1.08505 | Conf=0.42
[S09] NY SHORT | Bid=1.08280 | NY H=1.08650 L=1.08300 | Conf=0.31
[S09] Daily state reset | 2026.02.27 00:00:00
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No trades ever | `SB_BrokerGMT_Offset` wrong | Match broker server timezone |
| Range too small (skipped) | Market quiet / holiday | `SB_Range_Min_Pips` = 10 |
| No London breakout | Range captured in wrong hours | Verify GMT offset; check PrintSessionStatus |
| Breakout fires too early | Buffer too small | Raise `SB_Breakout_Buffer` to 5 pips |

---

*S09 Manual — FlashEASuite V2 | Phase P9-5 | Generated 2026-02-27*
