# FlashEASuite V2 — Strategy Reference

> **Version:** V6 (P9-5) | **Date:** 2026-03-01
> **Total Strategies:** 16 | **Standalone-capable:** 7

---

## Strategy Index Summary

| # | Enum Name | Index | Magic | Short | Category | Standalone | Best Regime |
|---|-----------|-------|-------|-------|----------|------------|-------------|
| 1 | S01_STAT_ARB | 0 | 1001 | S01 | HYBRID | ✅ Yes | RANGING |
| 2 | S02_ML_ENSEMBLE | 1 | 1002 | S02 | HYBRID | ❌ No | ALL (server required) |
| 3 | S03_SMC | 2 | 1003 | S03 | FULL_MQL5 | ❌ No | TRENDING |
| 4 | S04_MARKET_PROFILE | 3 | 1004 | S04 | FULL_MQL5 | ❌ No | RANGING |
| 5 | S05_SUPPLY_DEMAND | 4 | 1005 | S05 | FULL_MQL5 | ❌ No | RANGING |
| 6 | S06_KAMA | 5 | 1006 | S06 | FULL_MQL5 | ✅ Yes | TRENDING |
| 7 | S07_MEAN_REVERSION | 6 | 1007 | S07 | FULL_MQL5 | ✅ Yes | RANGING |
| 8 | S08_INTERMARKET | 7 | 1008 | S08 | HYBRID | ❌ No | TRENDING |
| 9 | S09_SESSION_BREAKOUT | 8 | 1009 | S09 | FULL_MQL5 | ❌ No | VOLATILE |
| 10 | S10_TURTLE | 9 | 1010 | S10 | FULL_MQL5 | ✅ Yes | TRENDING |
| 11 | S11_ICHIMOKU | 10 | 1011 | S11 | FULL_MQL5 | ❌ No | TRENDING |
| 12 | S12_PRICE_ACTION | 11 | 1012 | S12 | FULL_MQL5 | ❌ No | TRENDING |
| 13 | S13_FIB_STOCH | 12 | 1013 | S13 | FULL_MQL5 | ❌ No | RANGING |
| 14 | S14_BB_SQUEEZE | 13 | 1014 | S14 | FULL_MQL5 | ✅ Yes | SQUEEZE |
| 15 | S15_GRID | 14 | 1015 | S15 | FULL_MQL5 | ✅ Yes | RANGING |
| 16 | S16_SPIKE | 15 | 1016 | S16 | FULL_MQL5 | ✅ Yes | VOLATILE |

> **Index** = 0-based array position in `g_strategy_table[]` in `StrategyConstants.mqh`
> **Magic** = base magic number (actual = base + position offset)

---

## Market Regime Guide

| Regime | คำอธิบาย | Indicator signals | Best strategies |
|--------|---------|------------------|-----------------|
| **TRENDING** | ราคาเคลื่อนทิศทางชัดเจน | ADX > 25, MA slope > threshold | S03, S06, S08, S10, S11, S12 |
| **RANGING** | ราคา sideway ไม่มีทิศทาง | ADX < 20, BB Width low | S01, S04, S05, S07, S13, S15 |
| **VOLATILE** | ราคากระโดด/แกว่งแรง | ATR spike, high spread bursts | S09, S16 |
| **SQUEEZE** | Volatility ต่ำก่อน breakout | BB Width very low (< 0.1%) | S14 |

---

## Strategies — Full Detail

---

### S01 — Statistical Arbitrage (Pairs Trading)

| Property | Value |
|----------|-------|
| Enum | `S01_STAT_ARB` |
| Index | 0 (Magic: 1001) |
| Category | HYBRID (Python co-integration analysis + MQL5 execution) |
| Best Regime | RANGING |
| Standalone | ✅ Yes (simplified spread-mean mode) |
| File | `Include/Logic/Strategies/S01_StatArb.mqh` |

**ทฤษฎี:** ค้นหาคู่สกุลเงินที่มี co-integration กัน เมื่อ spread ระหว่างคู่ห่างออกจาก mean มากเกินไป ระบบจะ trade กลับสู่ mean

**Python side:** คำนวณ co-integration (Johansen test), z-score of spread
**MQL5 side:** รับ z-score จาก CONFIG_PUSH → Entry เมื่อ |z| > threshold

**Entry conditions:**
- `z-score > +2.0` → Sell spread (Sell S1, Buy S2)
- `z-score < -2.0` → Buy spread (Buy S1, Sell S2)
- Exit: `|z-score| < 0.5`

**Parameters:**
```
Z_SCORE_ENTRY   = 2.0    Entry threshold
Z_SCORE_EXIT    = 0.5    Exit threshold
LOOKBACK_PERIOD = 60     Bars for co-integration calculation
MAX_SPREAD_PIPS = 3.0    Max allowed spread at entry
```

**สรุปแนวคิด:** กลยุทธ์นี้ใช้ความสัมพันธ์ทางสถิติของคู่สกุลเงิน เมื่อราคาห่างกันมากผิดปกติ มักจะกลับมาหากัน เปรียบเหมือนเชือกผูกสองตัว

---

### S02 — ML Ensemble (LSTM + RF + XGBoost)

| Property | Value |
|----------|-------|
| Enum | `S02_ML_ENSEMBLE` |
| Index | 1 (Magic: 1002) |
| Category | HYBRID (Python ML model required) |
| Best Regime | ALL regimes (model adapts) |
| Standalone | ❌ No (requires Brain ML inference) |
| File | `Include/Logic/Strategies/S02_MLEnsemble.mqh` |

**ทฤษฎี:** ใช้ ensemble ของ 3 ML models: LSTM (sequence patterns), Random Forest (feature-based), XGBoost (gradient boosting) โหวตรวมกันเพื่อลด false signals

**Python side:** Feature engineering → LSTM + RF + XGBoost inference → weighted vote → confidence score
**MQL5 side:** รับ confidence + direction จาก CONFIG_PUSH → execute

**ML Features:**
- Price: Returns, log-returns, OHLC ratios
- Volatility: ATR, realized volatility, BB width
- Momentum: RSI, MACD, Rate of Change
- Volume: Tick density, volume momentum
- Session: Hour-of-day, day-of-week encoding

**Confidence threshold:** 0.65 minimum (higher than other strategies due to model risk)

**สรุปแนวคิด:** "ทีม AI 3 คน" โหวตว่าควรซื้อหรือขาย เหมือนกรรมการ 3 คนตัดสินคะแนน ลดความผิดพลาดได้มากกว่า model เดียว

---

### S03 — Smart Money Concepts (SMC)

| Property | Value |
|----------|-------|
| Enum | `S03_SMC` |
| Index | 2 (Magic: 1003) |
| Category | FULL_MQL5 |
| Best Regime | TRENDING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S03_SMC.mqh` |

**ทฤษฎี:** ติดตาม "smart money" (institutional traders) ผ่าน Order Blocks, Fair Value Gaps (FVG), Break of Structure (BOS), Change of Character (CHoCH)

**Key concepts:**
- **Order Block (OB):** แถวราคาที่ institutional trader เปิด position — ราคามักกลับมา test
- **Fair Value Gap (FVG):** ช่องว่างราคาที่เกิดจาก impulse move — มักถูก fill
- **Break of Structure (BOS):** ยืนยัน trend direction
- **CHoCH:** สัญญาณ trend reversal

**Entry conditions:**
- Price retest valid Order Block + BOS ยืนยัน
- FVG exists in direction of trade
- No major news within 30 minutes

**Parameters:**
```
OB_LOOKBACK     = 20     Bars to scan for Order Blocks
FVG_MIN_SIZE    = 5.0    Minimum FVG size in points
BOS_CONFIRM     = true   Require BOS before entry
```

**สรุปแนวคิด:** เทรดตาม "ร่องรอย" ของเงินสถาบัน เหมือนตามรอยเท้าช้างในป่า — ถ้าเห็น Order Block สำคัญและราคากลับมาทดสอบ มักเป็นโอกาสที่ดี

---

### S04 — Market Profile

| Property | Value |
|----------|-------|
| Enum | `S04_MARKET_PROFILE` |
| Index | 3 (Magic: 1004) |
| Category | FULL_MQL5 |
| Best Regime | RANGING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S04_MarketProfile.mqh` |

**ทฤษฎี:** ใช้ Market Profile theory (Peter Steidlmayer) — วิเคราะห์การกระจายตัวของราคาตลอดวัน ค้นหา Point of Control (POC), Value Area High/Low (VAH/VAL)

**Key concepts:**
- **POC:** ราคาที่มีการซื้อขายมากที่สุด (peak volume node)
- **VAH/VAL:** ขอบบน/ล่างของ 70% ของ volume distribution
- **Initial Balance (IB):** ช่วงราคาในชั่วโมงแรกของ session

**Entry conditions:**
- Price ออกจาก Value Area → expect reversion to POC
- Price breakout จาก Initial Balance → trend continuation
- Single prints ทำหน้าที่เป็น magnet

**Parameters:**
```
PROFILE_PERIOD  = DAY    Profile calculation period
VALUE_AREA_PCT  = 70     % of volume for Value Area
TPO_SIZE        = 10     TPO interval in minutes
```

**สรุปแนวคิด:** มองราคาเป็น "แผนที่ volume" ไม่ใช่แค่เส้นราคา POC คือ "ศูนย์กลาง" ของตลาดในวันนั้น ราคามักดึงดูดกลับมาหา POC

---

### S05 — Supply & Demand Zones

| Property | Value |
|----------|-------|
| Enum | `S05_SUPPLY_DEMAND` |
| Index | 4 (Magic: 1005) |
| Category | FULL_MQL5 |
| Best Regime | RANGING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S05_SupplyDemand.mqh` |

**ทฤษฎี:** ระบุ Supply zones (ขาย) และ Demand zones (ซื้อ) จากการเคลื่อนไหวราคาในอดีตที่รุนแรง เทรดเมื่อราคากลับมาทดสอบ zones เหล่านี้

**Zone identification:**
- **Demand Zone:** Base (consolidation) + Rally (sharp up move away from base)
- **Supply Zone:** Base (consolidation) + Drop (sharp down move away from base)
- Zone validity: ยิ่ง zone เก่าและยังไม่ถูก test ยิ่งแข็งแกร่ง

**Entry conditions:**
- Price enters valid zone (minimum 70% overlap)
- Confirmation candle pattern at zone
- Spread < max_spread_pips
- Zone tested ≤ 2 times (fresh zones preferred)

**Parameters:**
```
ZONE_STRENGTH   = STRONG     Require strong base before move
MAX_ZONE_TESTS  = 2          Fresh zones only
ZONE_BUFFER_PCT = 0.2        % buffer around zone boundaries
```

**สรุปแนวคิด:** "จุดที่ผู้ซื้อ/ผู้ขายสถาบันเคยเข้าตลาดไว้" มักยังคงมีนัยสำคัญ ราคาที่กลับมาทดสอบ zone เหล่านี้มักเกิด reaction

---

### S06 — KAMA Trend Following

| Property | Value |
|----------|-------|
| Enum | `S06_KAMA` |
| Index | 5 (Magic: 1006) |
| Category | FULL_MQL5 |
| Best Regime | TRENDING |
| Standalone | ✅ Yes |
| File | `Include/Logic/Strategies/S06_KAMA.mqh` |

**ทฤษฎี:** Kaufman's Adaptive Moving Average (KAMA) ปรับความเร็วของ MA ตาม market noise — เร็วเมื่อ trending, ช้าเมื่อ ranging ลดสัญญาณ false มากกว่า EMA/SMA ธรรมดา

**KAMA formula:**
```
ER = |Price - Price[n]| / Sum(|Price[i] - Price[i-1]|)   // Efficiency Ratio
SC = (ER × (fast_sc - slow_sc) + slow_sc)²               // Smoothing Constant
KAMA[t] = KAMA[t-1] + SC × (Price[t] - KAMA[t-1])
```

**Entry conditions:**
- Price crosses above KAMA → BUY (trend up)
- Price crosses below KAMA → SELL (trend down)
- Filter: ADX > 20 to confirm trend exists
- Filter: Spread < max_spread_pips

**Parameters:**
```
KAMA_PERIOD     = 10     Efficiency ratio lookback
KAMA_FAST       = 2      Fast EMA period
KAMA_SLOW       = 30     Slow EMA period
ADX_MIN         = 20     Minimum ADX for trend confirmation
```

**สรุปแนวคิด:** KAMA "ปรับตัว" ตามความแรงของ trend อัตโนมัติ เมื่อตลาด trending ชัด → ไวขึ้น ตาม signal ได้เร็ว เมื่อตลาด choppy → ช้าลง ป้องกัน whipsaw

---

### S07 — Mean Reversion (Volatility-Filtered)

| Property | Value |
|----------|-------|
| Enum | `S07_MEAN_REVERSION` |
| Index | 6 (Magic: 1007) |
| Category | FULL_MQL5 |
| Best Regime | RANGING |
| Standalone | ✅ Yes |
| File | `Include/Logic/Strategies/S07_MeanReversion.mqh` |

**ทฤษฎี:** ราคาที่เบี่ยงออกจาก mean มากเกินไปมักจะกลับคืน ใช้ RSI + Bollinger Bands + ATR filter เพื่อจับ oversold/overbought ใน ranging market

**Entry conditions:**
- **BUY:** RSI < 30 AND Price < BB_Lower AND ATR < ATR_MA × 1.5
- **SELL:** RSI > 70 AND Price > BB_Upper AND ATR < ATR_MA × 1.5
- ATR filter: ป้องกัน entry ระหว่าง spike/news

**Exit conditions:**
- TP: Price reaches BB_Middle (mean)
- SL: Price extends 1.5× BB_Width beyond entry
- Time-based: Close if holding > 48 bars without reaching TP

**Parameters:**
```
RSI_PERIOD      = 14     RSI lookback
RSI_OB          = 70     Overbought level
RSI_OS          = 30     Oversold level
BB_PERIOD       = 20     Bollinger Band period
BB_DEVIATION    = 2.0    Standard deviations
ATR_PERIOD      = 14     ATR period
ATR_FILTER_MULT = 1.5    Max ATR ratio (vs MA) for entry
```

**สรุปแนวคิด:** "ยางยืด" — ยิ่งดึงออกไปไกล ยิ่งดีดกลับมาแรง แต่ต้องแน่ใจว่าไม่ใช่ช่วง trend หรือ news spike จึงกล้าเข้า

---

### S08 — Intermarket Correlation

| Property | Value |
|----------|-------|
| Enum | `S08_INTERMARKET` |
| Index | 7 (Magic: 1008) |
| Category | HYBRID (Python DXY/correlation analysis) |
| Best Regime | TRENDING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S08_Intermarket.mqh` |

**ทฤษฎี:** ใช้ความสัมพันธ์ระหว่างตลาดต่างๆ: USD Index (DXY) กับ EUR/USD/GOLD, Bond yields กับ JPY pairs, Equities กับ risk currencies

**Python side:** คำนวณ rolling correlation (30-day), DXY momentum, lead/lag analysis
**MQL5 side:** รับ correlation signal + direction จาก CONFIG_PUSH

**Correlation pairs:**
- DXY ↑ → EURUSD ↓, GBPUSD ↓, XAUUSD ↓
- DXY ↓ → EURUSD ↑, GBPUSD ↑, XAUUSD ↑
- US10Y ↑ → USDJPY ↑ (yield differential)
- Risk-on (VIX ↓) → AUD ↑, NZD ↑, CAD ↑

**Parameters:**
```
CORRELATION_PERIOD = 30  Days for rolling correlation
DXY_THRESHOLD    = 0.3   Min DXY momentum for signal
MIN_CORRELATION  = 0.6   Minimum correlation coefficient
```

**สรุปแนวคิด:** Forex ไม่ใช่ island — DXY แข็ง → ทองอ่อน, Bond yield ขึ้น → JPY อ่อน ใครมอง intermarket ก็เห็นสัญญาณก่อนคนอื่น

---

### S09 — Session Breakout

| Property | Value |
|----------|-------|
| Enum | `S09_SESSION_BREAKOUT` |
| Index | 8 (Magic: 1009) |
| Category | FULL_MQL5 |
| Best Regime | VOLATILE |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S09_SessionBreakout.mqh` |

**ทฤษฎี:** เทรด breakout จากช่วงเปิด session (London/NY) ที่มี volume สูง เป็นช่วงที่ institutional order flow เข้ามากที่สุด

**Session times (GMT+7 Bangkok):**
- London open: **14:00**
- New York open: **19:00**
- London+NY overlap (best): **19:00–23:00**

**Entry conditions:**
- ราคา breakout จาก London Pre-Session range (12:00–14:00)
- Volume spike confirmed (tick density > threshold)
- Breakout candlestick closes outside range
- Time filter: 14:00–16:00 (London) หรือ 19:00–21:00 (NY)

**Parameters:**
```
PREBREAK_START  = "12:00"  Start of range formation
PREBREAK_END    = "14:00"  End of range / breakout trigger time
BREAKOUT_BUFFER = 5.0      Points beyond range for entry
SESSION_END     = "23:00"  Stop new entries after this time
```

**สรุปแนวคิด:** ช่วงที่ London หรือ NY เปิดตลาด ราคามักวิ่งทิศทางเดียวอย่างแรง เพราะ "เงินใหม่" เข้ามาจำนวนมาก — breakout ช่วงนี้ Success rate สูง

---

### S10 — Turtle Trading (Donchian Breakout)

| Property | Value |
|----------|-------|
| Enum | `S10_TURTLE` |
| Index | 9 (Magic: 1010) |
| Category | FULL_MQL5 |
| Best Regime | TRENDING |
| Standalone | ✅ Yes |
| File | `Include/Logic/Strategies/S10_Turtle.mqh` |

**ทฤษฎี:** ตาม "Turtle Trading Rules" ของ Richard Dennis (1983) — เทรด breakout จาก Donchian Channel 20-period สำหรับ entry, 10-period สำหรับ exit

**Entry (System 1):**
- BUY: Close > Donchian(20) High
- SELL: Close < Donchian(20) Low
- Filter: ข้าม signal ถ้า previous trade ชนะ (avoid clustering)

**Exit:**
- Long exit: Close < Donchian(10) Low
- Short exit: Close > Donchian(10) High
- Add units: ทุก 0.5 ATR ที่ trade เดิน (pyramiding)

**Position sizing:** Risk 1% per unit, max 4 units per market

**Parameters:**
```
ENTRY_PERIOD    = 20     Donchian entry channel period
EXIT_PERIOD     = 10     Donchian exit channel period
ATR_PERIOD      = 14     ATR for position sizing and pyramiding
MAX_UNITS       = 4      Maximum pyramid units
UNIT_RISK_PCT   = 1.0    % risk per unit
```

**สรุปแนวคิด:** กลยุทธ์คลาสสิกที่พิสูจน์แล้วกว่า 40 ปี ตาม trend เมื่อ breakout Donchian Channel เหมือนการ "เต่าไต่" — ช้าแต่ชัวร์ เมื่อมี trend

---

### S11 — Multi-TF Ichimoku

| Property | Value |
|----------|-------|
| Enum | `S11_ICHIMOKU` |
| Index | 10 (Magic: 1011) |
| Category | FULL_MQL5 |
| Best Regime | TRENDING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S11_Ichimoku.mqh` |

**ทฤษฎี:** ใช้ Ichimoku Kinko Hyo แบบ multi-timeframe (H4 + H1) เพื่อยืนยัน trend direction และหา entry ที่มี confluence สูง

**Components:**
- **Tenkan-sen (9):** Conversion line — short-term momentum
- **Kijun-sen (26):** Base line — medium-term momentum
- **Senkou Span A/B:** Cloud — support/resistance, trend
- **Chikou Span:** Lagging line — confirmation

**Entry conditions (all must align):**
1. Price above/below Kumo cloud (H4 + H1)
2. Tenkan crosses Kijun in trade direction
3. Chikou span free (no obstruction)
4. Cloud twist in trade direction (future cloud)

**Parameters:**
```
TENKAN_PERIOD   = 9      Tenkan-sen calculation period
KIJUN_PERIOD    = 26     Kijun-sen calculation period
SENKOU_PERIOD   = 52     Senkou Span B period
HTF_TIMEFRAME   = H4     Higher timeframe for trend filter
```

**สรุปแนวคิด:** Ichimoku เป็น "ระบบสมบูรณ์" ในตัวเอง แสดง trend, support/resistance, momentum, และ signal ในชาร์ตเดียว Multi-TF เพิ่มความแม่นยำขึ้นอีก

---

### S12 — Price Action (Pin Bar + Engulfing)

| Property | Value |
|----------|-------|
| Enum | `S12_PRICE_ACTION` |
| Index | 11 (Magic: 1012) |
| Category | FULL_MQL5 |
| Best Regime | TRENDING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S12_PriceAction.mqh` |

**ทฤษฎี:** ระบุ high-probability candlestick patterns ที่ key support/resistance levels: Pin Bar (rejection), Engulfing (momentum shift), Inside Bar (breakout setup)

**Pattern types:**
- **Pin Bar (Hammer/Shooting Star):** Wick > 2× body, small body at one end
- **Bullish/Bearish Engulfing:** Second candle completely engulfs first
- **Inside Bar:** Full candle within previous candle range (breakout setup)

**Entry conditions:**
- Pattern forms at significant S/R level (swing high/low, round numbers, MA)
- Daily trend alignment (pattern must be with higher TF trend)
- Minimum pattern quality score ≥ 70%

**Parameters:**
```
PIN_WICK_RATIO  = 2.0    Min wick-to-body ratio for Pin Bar
ENGULF_OVERLAP  = 0.95   Min overlap for engulfing candle
SR_LOOKBACK     = 50     Bars for S/R level detection
PATTERN_MIN_SCORE = 70   Min quality score (0-100)
```

**สรุปแนวคิด:** แท่งเทียนพิเศษที่ key levels บ่งบอกว่า "ผู้ซื้อ/ผู้ขายกลับมาแล้ว" Pin bar ที่ support แสดงว่า seller ล้มเหลว — มักตามด้วยการ bounce

---

### S13 — Fibonacci + Stochastic

| Property | Value |
|----------|-------|
| Enum | `S13_FIB_STOCH` |
| Index | 12 (Magic: 1013) |
| Category | FULL_MQL5 |
| Best Regime | RANGING |
| Standalone | ❌ No |
| File | `Include/Logic/Strategies/S13_FibStoch.mqh` |

**ทฤษฎี:** รวม Fibonacci retracement (โครงสร้างราคา) กับ Stochastic (momentum timing) เทรด retracement ใน trending move ที่ Fibonacci levels สำคัญ

**Key Fibonacci levels:**
- 38.2% — ใน strong trend
- 50.0% — ระดับกลาง
- 61.8% — "Golden ratio" — confluence ที่แข็งแกร่งที่สุด
- 78.6% — Deep retracement ใน tight trends

**Entry conditions:**
- Fibonacci retracement ถึง key level (38.2, 50, 61.8, 78.6%)
- Stochastic: %K crosses %D ในทิศทางที่ถูก + exit oversold/overbought zone
- Candlestick confirmation at level (Pin Bar หรือ Engulfing)

**Parameters:**
```
SWING_LOOKBACK  = 20     Bars for swing high/low detection
FIB_LEVELS      = [38.2, 50.0, 61.8, 78.6]   Active Fib levels
STOCH_K         = 5      Stochastic %K period
STOCH_D         = 3      Stochastic %D period
STOCH_SLOW      = 3      Stochastic slowing
```

**สรุปแนวคิด:** Fibonacci บอก "ราคาน่าจะหยุดตรงไหน" Stochastic บอก "momentum พลิกแล้วหรือยัง" รวมกันให้ entry ที่มี confluence สูง

---

### S14 — Bollinger Band Squeeze

| Property | Value |
|----------|-------|
| Enum | `S14_BB_SQUEEZE` |
| Index | 13 (Magic: 1014) |
| Category | FULL_MQL5 |
| Best Regime | SQUEEZE (→ breakout) |
| Standalone | ✅ Yes |
| File | `Include/Logic/Strategies/S14_BBSqueeze.mqh` |

**ทฤษฎี:** Bollinger Band Squeeze (John Carter) — เมื่อ BB Width แคบผิดปกติ (< historical low) หมายถึงตลาดกำลังสะสมพลัง ก่อนจะเกิด explosive breakout

**Squeeze detection:**
- BB Width = (Upper - Lower) / Middle × 100
- Squeeze = BB Width < percentile(20, lookback=125)
- Squeeze ends when BB Width expands

**Entry conditions:**
- Squeeze detected (BB Width at 20th percentile or lower)
- Squeeze releases (BB starts expanding)
- Momentum confirms direction: Histogram (linear regression of close) turns positive/negative
- Entry on squeeze release candle

**Parameters:**
```
BB_PERIOD       = 20     Bollinger Band period
BB_DEVIATION    = 2.0    Standard deviations
SQUEEZE_THRESH  = 20     Percentile threshold for squeeze detection
KC_MULT         = 1.5    Keltner Channel multiplier (for TTM Squeeze variant)
HISTOGRAM_LEN   = 12     Momentum histogram period
```

**สรุปแนวคิด:** ตลาดเหมือน "สปริงที่ถูกกด" เมื่อ BB คับแคบผิดปกติ พลังงานสะสมไว้ พอ release จะวิ่งแรง — ไม่รู้ทิศทาง แต่รู้ว่าจะแรง

---

### S15 — Immortal Grid (Elastic Grid)

| Property | Value |
|----------|-------|
| Enum | `S15_GRID` |
| Index | 14 (Magic: 1015) |
| Category | FULL_MQL5 |
| Best Regime | RANGING |
| Standalone | ✅ Yes |
| File | `Include/Logic/Grid/GridCore.mqh`, `GridConfig.mqh` |

**ทฤษฎี:** Elastic Grid Strategy — วาง order grid ในทิศทางที่ Brain/CSM (Currency Strength Meter) ชี้ ระยะห่างระหว่าง grid levels ปรับตาม ATR (elastic) ไม่ใช่ fixed distance

**Grid mechanics:**
- Direction: กำหนดโดย Brain (LONG/SHORT bias)
- Level spacing: Base step × ATR multiplier (elastic)
- Max levels: จำกัดตาม config (ป้องกัน over-exposure)
- TP per level: กำหนดเป็น points (ปิดทุก level แยกกัน)
- No global SL: ปิดด้วย time limit หรือ max loss ต่าง

**Parameters:**
```
GRID_MAX_ORDERS = 5       Maximum concurrent grid levels
GRID_BASE_STEP  = 200.0   Base grid step in points
GRID_LOT_MULT   = 1.5     Lot multiplier per level
GRID_TP_POINTS  = 150.0   Take profit per level in points
ELASTIC_ATR_MULT= 1.0     ATR multiplier for elastic step
```

**สรุปแนวคิด:** ตาข่าย Grid ไม่เคยสิ้นสุด — ถ้าราคากลับมาจะกำไร แต่ต้องควบคุม level สูงสุดอย่างเคร่งครัด ใช้ได้ดีใน ranging market

---

### S16 — Spike Hunter

| Property | Value |
|----------|-------|
| Enum | `S16_SPIKE` |
| Index | 15 (Magic: 1016) |
| Category | FULL_MQL5 |
| Best Regime | VOLATILE |
| Standalone | ✅ Yes |
| File | `Include/Logic/Strategy_Spike.mqh` (v2.02) |

**ทฤษฎี:** ตรวจจับ price spike ที่เกินปกติ (จาก tick velocity + spread + ATR) แล้วเทรด fade (ตรงข้าม spike) — สมมติว่า spike จะกลับสู่ระดับปกติ

**Spike detection (multi-condition):**
- Tick velocity: ticks per second > threshold
- Price change: > ATR × spike_multiplier ใน spike_window
- Spread: spike in spread width (บ่งบอก liquidity vacuum)
- Score: รวม 3 conditions เป็น spike_score (0–100)

**Entry conditions:**
- spike_score > 70 (VOLATILE territory)
- Direction: Fade the spike (Sell if spike up, Buy if spike down)
- Max spread at entry: 3× normal spread
- Hold time: max 5 minutes (short-term)

**Exit conditions:**
- TP: Return 50% of spike amplitude
- SL: Spike extends another 30% (trend instead of spike)
- Time: Close after hold_minutes regardless

**Parameters:**
```
SPIKE_THRESHOLD = 70.0   Minimum spike score for entry
SPIKE_WINDOW    = 5.0    Seconds to measure spike velocity
ATR_MULT        = 2.0    Min price change vs ATR for spike
HOLD_MINUTES    = 5      Max hold time in minutes
FADE_PCT        = 0.5    TP as % of spike amplitude
MAX_SPREAD_MULT = 3.0    Max spread multiplier at entry
```

> ⚠️ **Known issue:** Memory leak ใน backtest ยาวๆ (11,520 bytes per run) — แก้แล้วใน v2.02 สำหรับ live trading แต่ยังต้องระวัง optimization runs

**สรุปแนวคิด:** Spike เกิดจาก "over-reaction" ของตลาด — ราคาวิ่งเร็วเกินไปในเสี้ยววินาที มักกลับมาหลัง spike จบ เหมือนลูกบอลที่ถูกโยนขึ้นจะตกลงมา

---

## Strategy Selection Guide

### By Market Condition

```
ตลาดกำลัง TREND ชัดเจน:
  → S06_KAMA (standalone OK)
  → S10_TURTLE (standalone OK)
  → S03_SMC (server required)
  → S11_ICHIMOKU (server required)

ตลาด RANGING / Sideways:
  → S07_MEAN_REVERSION (standalone OK)
  → S15_GRID (standalone OK)
  → S04_MARKET_PROFILE (server required)
  → S05_SUPPLY_DEMAND (server required)

ตลาด VOLATILE (high ATR):
  → S16_SPIKE (standalone OK)
  → S09_SESSION_BREAKOUT (server required)

ตลาด SQUEEZE (low volatility, pre-breakout):
  → S14_BB_SQUEEZE (standalone OK)

ต้องการ AI-powered:
  → S02_ML_ENSEMBLE (server required, best overall)
  → S01_STAT_ARB (standalone simplified version OK)
```

### By Trading Style

| Style | Recommended Strategies |
|-------|----------------------|
| Conservative (low risk) | S07, S06, S10 |
| Moderate | S14, S12, S03, S05 |
| Aggressive | S16, S09, S15 |
| Fully automated AI | S02 (Brain required) |
| Server-independent | S01, S06, S07, S10, S14, S15, S16 |

---

*FlashEASuite V2 Strategy Reference — V6 P9-5 | 2026-03-01*
