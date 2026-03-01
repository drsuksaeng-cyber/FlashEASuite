# FlashEASuite V2 — Master Development Roadmap V6 (MERGED EDITION)

**Version:** 6.0 (Merged: Claude Intelligence + Manus Implementation)  
**Date:** February 12, 2026  
**Author:** Claude AI for Dr. Suksaeng Kukanok  
**Base Documents:** Claude V5 (52p) + Manus V5 (100p) + Comparison Report  
**Status:** 🔵 READY FOR EXECUTION

---

## 1. EXECUTIVE SUMMARY — V5→V6 CHANGES

### What Changed and Why

V6 เกิดจากการ merge จุดแข็งของ Claude V5 และ Manus V5 หลังจากวิเคราะห์เปรียบเทียบทุกมิติ:

| ด้าน | V5 (Claude) | V6 (Merged) | ที่มา |
|------|------------|-------------|-------|
| Strategy Logic | Python-heavy (9 ServerOnly) | MQL5-heavy (13 full MQL5 + 3 hybrid) | Manus |
| Standalone | Fixed lookup table | CStandaloneSelector + config.dat + confidence | Manus+Claude |
| AI Council | 5-factor formula | 5-factor + R:R gate + gradual regime | Claude+Manus |
| ML Stack | RF + LSTM + XGBoost + KMeans | + HMM (5 models total) | Claude+Manus |
| Explainable AI | 4 destinations + full chain | เหมือนเดิม (Claude ชนะขาด) | Claude |
| Protocol Format | MessagePack (~8 types) | MessagePack + 15 message types | Claude+Manus |
| Database | In-memory | + InfluxDB for time-series | Manus |
| MQL5 Structure | Concept only | Full file tree + EA skeleton | Manus |
| Client Scale | <50 clients | <50 target + Connection Pool design | Claude+Manus |
| Security | RSA-2048 + DLL + anti-replay | เหมือนเดิม (Manus ไม่มี) | Claude |
| Timeline | 26 weeks / 45 chats | ~22 weeks / 42 chats (parallel tracks) | Optimized |
| Phase Order | Core strategies → Extended | All 16 MQL5 strategies upfront | Manus |

### Key Architecture Decision: "Smart Server, Powerful Client"

**หลักการ V6:** Strategy logic ทุกตัวที่ทำได้ ให้อยู่ใน MQL5 (Manus approach)  
**Server ทำ:** วิเคราะห์ตลาด → เลือก strategy → ส่ง CONFIG_PUSH (ไม่คำนวณ signal)  
**Client ทำ:** คำนวณ indicator + signal + execute เอง  
**ยกเว้น 3 Hybrid Strategies** ที่ต้องการ Python: StatArb (co-integration), ML Ensemble (LSTM), Intermarket (DXY data)

### Parallel Work Design

ระบบออกแบบให้ทำงาน 2-3 แชตพร้อมกัน:
- **Track A (MQL5):** Strategies + MM + Universal modules — ไม่ต้องรอ Python
- **Track B (Python):** Brain + Intelligence Engine — ไม่ต้องรอ MQL5
- **Track C (Integration):** รวม A+B เข้าด้วยกัน — รอ A+B เสร็จ

---

## 2. ARCHITECTURE OVERVIEW

### System Diagram

```
╔═══════════════════════════════════════════════════════════════════════╗
║                    FLASHEASUITE V2 V6 ARCHITECTURE                    ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │  PYTHON SERVER (The Brain) — Port 7778                          │  ║
║  │                                                                   │  ║
║  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │  ║
║  │  │  REGIME       │ │  AI COUNCIL  │ │  ML ENSEMBLE             │ │  ║
║  │  │  CLASSIFIER   │ │  16 Voters   │ │  RF+LSTM+XGB+KM+HMM     │ │  ║
║  │  │  Rule+RF+HMM  │ │  5-factor    │ │  (Strategy S02)          │ │  ║
║  │  └──────┬────────┘ │  + R:R gate  │ └─────────┬────────────────┘ │  ║
║  │         │          └──────┬───────┘           │                  │  ║
║  │         └────────┬────────┘───────────────────┘                  │  ║
║  │                  ▼                                                │  ║
║  │  ┌──────────────────────────────────────────────────────────────┐│  ║
║  │  │  EXPLAINABLE ENGINE → 4 Destinations                         ││  ║
║  │  │  (CONFIG_PUSH | JSON Log | CSV Report | Auto-Retrain)        ││  ║
║  │  └──────────────────────┬───────────────────────────────────────┘│  ║
║  │                         │                                         │  ║
║  │  ┌──────────────────────▼───────────────────────────────────────┐│  ║
║  │  │  CONFIG PUSH BUILDER (MessagePack, 15 message types)         ││  ║
║  │  │  + Connection Pool (<50 clients) + InfluxDB                  ││  ║
║  │  └──────────────────────┬───────────────────────────────────────┘│  ║
║  └─────────────────────────┼───────────────────────────────────────┘  ║
║                            │ ZMQ PUB/SUB (3-7ms)                      ║
║  ┌─────────────────────────▼───────────────────────────────────────┐  ║
║  │  FEEDER EA (Data Provider) — Port 7777                          │  ║
║  │  28+ symbols → TICK + OHLC + INDICATOR data every 100ms         │  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │  MQL5 TRADER CLIENT (The Executor) × <50                       │  ║
║  │                                                                   │  ║
║  │  ┌─────────────────────────────────────────────────────────────┐│  ║
║  │  │ 16 STRATEGIES (ALL in MQL5)                                 ││  ║
║  │  │ 13 Full MQL5 + 3 Hybrid (StatArb/ML/Intermarket)           ││  ║
║  │  └─────────────────────────────────────────────────────────────┘│  ║
║  │  ┌─────────────────────────────────────────────────────────────┐│  ║
║  │  │ 19 MM METHODS (ALL in MQL5) + MM Manager                   ││  ║
║  │  └─────────────────────────────────────────────────────────────┘│  ║
║  │  ┌──────────────────────┐ ┌────────────────────────────────────┐│  ║
║  │  │ [ONLINE MODE]        │ │ [STANDALONE MODE]                  ││  ║
║  │  │ Receive CONFIG_PUSH  │ │ CStandaloneSelector               ││  ║
║  │  │ Activate selected    │ │ 7 Core Strategies                 ││  ║
║  │  │ strategies           │ │ DetectRegime() per tick            ││  ║
║  │  │ Full power (16 strat)│ │ standalone_config.dat fallback     ││  ║
║  │  │                      │ │ Confidence > 0.50 threshold        ││  ║
║  │  │                      │ │ Risk × 0.5 conservative            ││  ║
║  │  └──────────────────────┘ └────────────────────────────────────┘│  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════╝
```

### Component Roles (V6)

**Python Server (The Brain) — ทำหน้าที่ "เลือก" ไม่ใช่ "คำนวณ signal"**
- รับ Tick/OHLC/Indicator data จาก Feeder → เก็บใน InfluxDB
- Classify market regime (3-layer: Rule + RF + HMM)
- 16 Strategy Analyzers vote confidence (0.0-1.0)
- AI Council: weighted_conf = raw × hist_perf × regime_bonus × calendar_adj × news_adj
- R:R Gate: if R:R < 1.5 → SKIP
- Explainable reasoning chain → 4 destinations
- CONFIG_PUSH → Client (บอกว่าเปิด strategy ไหน + parameters)
- **ไม่คำนวณ** indicator หรือ entry/exit signal (Client ทำเอง)

**MQL5 Trader Client (The Executor) — "Powerful Client"**
- มี 16 strategies + 19 MM methods implement ครบใน MQL5
- Online Mode: รับ CONFIG_PUSH → เปิด strategy ที่ server เลือก → คำนวณ signal เอง
- Standalone Mode: CStandaloneSelector detect regime → เลือก 7 strategies
- คำนวณ indicator ทุกตัวใน MQL5 (latency = 0)
- Execute orders + manage positions

**MQL5 Feeder (Data Provider)**
- เก็บ Tick Data จาก 28+ symbols
- ส่ง 3 ประเภท: TICK_DATA, OHLC_DATA, INDICATOR_DATA
- ทำงานแยกจาก Trader

---

## 3. STRATEGY ARSENAL (16 STRATEGIES)

### Strategy Table

| # | ID | Strategy Name | Magic | MQL5 Type | Category | Standalone |
|---|-----|--------------|-------|-----------|----------|------------|
| 1 | S01 | Statistical Arbitrage | 1001 | Hybrid (Python co-integration) | Pairs/Neutral | ✅ Yes |
| 2 | S02 | ML Ensemble | 1002 | Hybrid (Python ML models) | AI/ML Predictive | ❌ ServerOnly |
| 3 | S03 | Smart Money Concepts (SMC) | 1003 | Full MQL5 | Price Action | ❌ ServerOnly |
| 4 | S04 | Market Profile + Order Flow | 1004 | Full MQL5 | Volume-based | ❌ ServerOnly |
| 5 | S05 | Supply & Demand | 1005 | Full MQL5 | Zone-based | ❌ ServerOnly |
| 6 | S06 | Adaptive Trend Following (KAMA) | 1006 | Full MQL5 | Trend Following | ✅ Yes |
| 7 | S07 | Mean Reversion (Vol-Filtered) | 1007 | Full MQL5 | Contrarian | ✅ Yes |
| 8 | S08 | Intermarket Correlation | 1008 | Hybrid (Python DXY data) | Multi-Asset | ❌ ServerOnly |
| 9 | S09 | London/NY Session Breakout | 1009 | Full MQL5 | Time-based | ❌ ServerOnly |
| 10 | S10 | Turtle Trading (Modernized) | 1010 | Full MQL5 | Breakout | ✅ Yes |
| 11 | S11 | Multi-TF Ichimoku | 1011 | Full MQL5 | Systematic Trend | ❌ ServerOnly |
| 12 | S12 | Price Action (Pin Bar) | 1012 | Full MQL5 | Candlestick | ❌ ServerOnly |
| 13 | S13 | Fibonacci + Stochastic | 1013 | Full MQL5 | Reversal | ❌ ServerOnly |
| 14 | S14 | Bollinger Squeeze Breakout | 1014 | Full MQL5 | Volatility | ✅ Yes |
| 15 | S15 | Immortal Grid (Legacy) | 1015 | Full MQL5 | Range Grid | ✅ Yes |
| 16 | S16 | Spike Hunter (Legacy) | 1016 | Full MQL5 | Momentum | ✅ Yes |

**Summary:** 13 Full MQL5 + 3 Hybrid | 7 Standalone + 9 ServerOnly

### Strategy Changes from V5

| V5 (Claude) | V6 (Merged) | เหตุผล |
|-------------|-------------|--------|
| London Breakout (separate) | ตัดออก (รวมเข้า Session Breakout) | ซ้ำกัน |
| — | + Intermarket Correlation (S08) | จาก Manus — unique value |
| — | + Price Action Pin Bar (S12) | เปลี่ยนจาก ServerOnly Python → Full MQL5 |
| 9 strategies = Python ServerOnly | 6 strategies = ServerOnly | ลดจำนวน ServerOnly เพราะ MQL5-heavy |

### 7 Standalone Strategies

เมื่อ Server disconnect จะใช้ 7 ตัวนี้:
1. **S01 StatArb** — Pairs trading (simple spread monitoring ใน standalone)
2. **S06 KAMA/TrendFollow** — Adaptive MA + ER calculation
3. **S07 MeanRev** — RSI + BB + Vol filter
4. **S10 Turtle** — Donchian breakout + ATR sizing
5. **S14 BBSqueeze** — BB inside KC detection
6. **S15 Grid** — Immortal Grid (legacy, proven)
7. **S16 Spike** — Spike Hunter (legacy, proven)

**เหตุผล:** เลือก strategy ที่ logic ง่าย + ทำงานได้ดีโดยไม่ต้องพึ่ง ML — ตัด SMC/Ichimoku ออกเพราะ complex เกินสำหรับ offline

---

## 4. STANDALONE MODE — CStandaloneSelector (NEW)

### Design (Merged from Manus + Claude improvements)

```
CStandaloneSelector
├── Init()
│   ├── LoadConfig("standalone_config.dat")  // ← Manus: last server config
│   └── Initialize 7 strategies
├── OnTick()
│   ├── DetectRegime()  // ADX + ATR + BB Width (per tick)
│   │   ├── TRENDING: ADX > 27 (enter), exit < 23 (hysteresis) ← Claude
│   │   ├── RANGING: ADX < 20
│   │   ├── VOLATILE: ATR > 1.5× MA(ATR)
│   │   └── SQUEEZE: BB_Width < 0.5× MA(BB_Width) ← Claude (Manus ไม่มี)
│   ├── SelectStrategies(regime)  // Dynamic, not fixed lookup ← Manus
│   │   ├── TRENDING → KAMA + Turtle + BBSqueeze
│   │   ├── RANGING → Grid + StatArb + MeanRev
│   │   ├── VOLATILE → Spike + BBSqueeze
│   │   └── SQUEEZE → BBSqueeze + Turtle (prepare for breakout)
│   ├── CalculateConfidence()  // Simple threshold > 0.50 ← Claude
│   │   └── if conf < 0.50 → skip (don't trade)
│   └── Execute(strategies, MM1, risk × 0.5)
└── SaveConfig() / LoadConfig()
    └── standalone_config.dat = last CONFIG_PUSH from server ← Manus
```

### Key Improvements over V5

1. **Dynamic selection** (Manus) แทน fixed lookup (Claude V5)
2. **SQUEEZE regime** (Claude) ที่ Manus ไม่มี
3. **Hysteresis** (Claude): enter TRENDING@27, exit@23 ป้องกัน flickering
4. **Confidence threshold** (Claude): >0.50 ถึงเทรด
5. **standalone_config.dat** (Manus): เก็บ last server config เป็น fallback

---

## 5. AI COUNCIL VOTING SYSTEM (MERGED)

### Voting Formula (Claude 5-factor + Manus R:R gate)

```
For each symbol, for each of 16 strategy agents:

Step 1: Raw Confidence (0.0-1.0) — จาก strategy logic
Step 2: Historical Performance Weight — EMA(accuracy) per strategy×symbol
Step 3: Regime Alignment Bonus — gradual scale 0.3-1.5 (not binary) ← improved
Step 4: Calendar Adjustment — reduce during high-impact news
Step 5: News Sentiment Adjustment — from NEWS_ALERT messages ← Manus msg type

weighted_conf = raw × hist_perf × regime_bonus × calendar_adj × news_adj

Step 6: R:R Gate ← Manus
   if Expected_R:R < 1.5 → SKIP (regardless of confidence)
   if weighted_conf < 0.55 → SKIP

Step 7: Portfolio Diversification
   - No single strategy > 40% of portfolio
   - No single symbol > 15% exposure
   - Correlation check: if corr(Symbol_A, Symbol_B) > 0.7 → reduce 50%

Step 8: Selection
   - Top 1-3 strategies per symbol where weighted_conf > 0.55
   - Self-tuning: EMA weights adjusted weekly based on accuracy
```

### Regime Factor Scale (V6 — gradual, not binary)

| Regime Match | Factor | Example |
|-------------|--------|---------|
| Perfect match | 1.5 | Grid + RANGING |
| Good match | 1.2 | Turtle + TRENDING |
| Neutral | 1.0 | StatArb + any |
| Poor match | 0.5 | Grid + TRENDING |
| Terrible match | 0.3 | Spike + SQUEEZE |

---

## 6. ML ENSEMBLE STRATEGY (S02) — 5 MODELS

### Model Stack

| Model | Role | Input | Output |
|-------|------|-------|--------|
| Random Forest | Regime classification | ADX, ATR, BB, Volume, 30+ features | TRENDING/RANGING/VOLATILE/SQUEEZE |
| LSTM (2-layer, 64 units) | Price direction prediction | Price sequence (60 bars) | UP/DOWN/NEUTRAL + probability |
| XGBoost | Confidence scoring | All features + model outputs | 0.0-1.0 confidence + feature importance |
| K-Means | Pattern clustering | Price patterns, indicators | Cluster ID (similar profitable states) |
| HMM (Hidden Markov) | Regime shift prediction | State sequence | Transition probability matrix |

### Training Pipeline

- Initial training: 6 months historical data per symbol
- Weekly retrain: last 3 months rolling window
- Auto-retrain trigger: accuracy drops below 60% for 2 consecutive weeks
- Feedback loop: reasoning + actual_outcome → calculate accuracy → adjust model weights

---

## 7. PROTOCOL SPECIFICATION (MERGED)

### Message Format: MessagePack (Claude) + 15 Types (Manus)

| Type ID | Name | Direction | Description |
|---------|------|-----------|-------------|
| 1 | TICK_DATA | Feeder → Server | Tick data (bid, ask, volume) |
| 2 | OHLC_DATA | Feeder → Server | OHLC bars (M1, M5, M15, H1, H4, D1) |
| 3 | INDICATOR_DATA | Feeder → Server | Pre-calculated indicators |
| 10 | CONFIG_PUSH | Server → Clients | Strategy/MM configuration + reasoning |
| 11 | CLIENT_HELLO | Client → Server | Client registration |
| 12 | INITIAL_CONFIG | Server → Client | First-time config + standalone_config |
| 13 | HEARTBEAT | Client ↔ Server | Keep-alive (every 10s, timeout 30s) |
| 20 | TRADE_REPORT | Client → Server | Trade execution report |
| 21 | POSITION_UPDATE | Client → Server | Position status |
| 22 | PERFORMANCE_METRICS | Client → Server | Performance stats |
| 30 | NEWS_ALERT | Server → Clients | Economic calendar alert |
| 31 | REGIME_CHANGE | Server → Clients | Market regime shift notification |
| 40 | COMMAND | Server → Client | Manual command (stop, start, etc.) |
| 50 | POLICY_UPDATE | Server → Clients | Security policy update |
| 99 | ERROR | Any → Any | Error message |

### CONFIG_PUSH Format (V6)

```json
{
  "type": 10,
  "timestamp": "2026-02-12T10:30:00Z",
  "regime": "RANGING",
  "symbol_configs": [
    {
      "symbol": "XAUUSD",
      "strategies": [
        {
          "id": "S01", "name": "StatArb", "enabled": true,
          "confidence": 0.69, "timeframe": "M15",
          "mm_method": "MM4",
          "parameters": {"StatArb_Beta": 1.05, "MM4_WinRate": 0.68}
        }
      ]
    }
  ],
  "reasoning": {
    "XAUUSD": {
      "regime": {"type": "RANGING", "method": "RF_ML", "confidence": 0.85},
      "votes": [
        {"strategy": "S01", "raw": 0.85, "hist": 0.68, "regime": 1.2, "cal": 1.0, "news": 1.0, "final": 0.69, "rr": 2.1},
        {"strategy": "S15", "raw": 0.70, "hist": 0.72, "regime": 1.2, "cal": 1.0, "news": 1.0, "final": 0.60, "rr": 1.8}
      ],
      "selected": [{"rank": 1, "strategy": "S01", "score": 0.69}],
      "summary_th": "เลือก StatArb เพราะ Z-Score=-2.1 สัญญาณแรง ตรงกับ RANGING regime"
    }
  },
  "standalone_config": {
    "enabled_strategies": ["S01", "S06", "S07", "S10", "S14", "S15", "S16"],
    "default_mm": "MM1",
    "risk_multiplier": 0.5
  }
}
```

---

## 8. MQL5 FILE STRUCTURE (NEW — from Manus)

```
03_Trader/
├── FlashEA_V6.mq5                    // Main EA file
├── Include/
│   ├── Core/
│   │   ├── Protocol.mqh              // ZMQ + MessagePack handler
│   │   ├── MessageTypes.mqh          // 15 message type constants
│   │   ├── ConfigReceiver.mqh        // Receive & parse CONFIG_PUSH
│   │   ├── ConnectionMonitor.mqh     // Heartbeat + timeout (30s)
│   │   └── StrategyManager.mqh       // Manage 16 strategies on/off
│   ├── Strategies/
│   │   ├── IStrategy.mqh             // Interface: Analyze(), Execute(), GetConfidence()
│   │   ├── StrategyConstants.mqh     // Magic numbers, names, categories
│   │   ├── S01_StatArb.mqh           // + StatArb/ subfolder
│   │   ├── S02_ML_Ensemble.mqh       // Thin wrapper (receives signal from Python)
│   │   ├── S03_SMC.mqh               // + SMC/ subfolder (OB, FVG detectors)
│   │   ├── S04_MarketProfile.mqh     // + MarketProfile/ subfolder
│   │   ├── S05_SupplyDemand.mqh      // + SupplyDemand/ subfolder
│   │   ├── S06_KAMA.mqh              // Adaptive MA + ER
│   │   ├── S07_MeanReversion.mqh     // RSI + BB + Vol filter
│   │   ├── S08_Intermarket.mqh       // Thin wrapper (receives corr from Python)
│   │   ├── S09_SessionBreakout.mqh   // London/NY session ranges
│   │   ├── S10_Turtle.mqh            // Donchian + ATR + pyramiding
│   │   ├── S11_Ichimoku.mqh          // Multi-TF Ichimoku
│   │   ├── S12_PriceAction.mqh       // Pin Bar + Engulfing
│   │   ├── S13_FibStoch.mqh          // Fibonacci retracement + Stochastic
│   │   ├── S14_BBSqueeze.mqh         // BB inside KC + momentum
│   │   ├── S15_Grid.mqh              // Immortal Grid (adapted from legacy)
│   │   └── S16_Spike.mqh             // Spike Hunter (adapted from legacy)
│   ├── MM/
│   │   ├── IMoneyManager.mqh         // Interface
│   │   ├── MMManager.mqh             // Select & manage MM methods
│   │   ├── MM01_FixedConservative.mqh ... MM19_DynamicMulti.mqh
│   │   └── MMConstants.mqh           // MM selection matrix
│   ├── Standalone/
│   │   ├── StandaloneSelector.mqh    // CStandaloneSelector class
│   │   ├── SimpleRegime.mqh          // Standalone regime detection
│   │   └── StandaloneConfig.mqh      // Load/save standalone_config.dat
│   ├── Risk/
│   │   ├── RiskManager.mqh           // Portfolio-level risk
│   │   └── TransferToGrid.mqh        // Emergency function (shared)
│   └── Utils/
│       ├── HiddenTPSL.mqh            // Hidden TP/SL universal
│       ├── TrailingStop.mqh          // Trailing stop universal
│       ├── OrderManager.mqh          // Order execution
│       └── Logger.mqh                // Logging
```

### Python Server Structure

```
02_Brain/
├── main.py                            // Main server application
├── config.py                          // Configuration
├── core/
│   ├── protocol_handler.py            // ZMQ + MessagePack
│   ├── message_types.py               // 15 message type definitions
│   ├── connection_pool.py             // Multi-client manager (<50)
│   └── logger.py                      // Logging
├── data/
│   ├── data_ingestion.py              // Receive from Feeder
│   ├── influxdb_client.py             // InfluxDB interface
│   └── feature_engineering.py         // 30+ features for ML
├── intelligence/
│   ├── intelligence_engine.py         // Main orchestrator
│   ├── regime_classifier.py           // 3-layer (Rule + RF + HMM)
│   ├── strategy_council.py            // AI Council (16 voters)
│   ├── portfolio_diversifier.py       // Concentration + correlation
│   ├── mm_optimizer.py                // MM selection per strategy
│   ├── performance_tracker.py         // Track accuracy per strategy
│   └── symbol_optimizer.py            // Symbol selection
├── explainable/
│   ├── reasoning_builder.py           // Build full reasoning chain
│   ├── decision_logger.py             // JSON audit trail
│   └── retrain_feedback.py            // Reasoning → accuracy → weights
├── strategies/
│   ├── base_analyzer.py               // Base class
│   ├── s01_stat_arb_analyzer.py       // Co-integration + Z-Score
│   ├── s02_ml_ensemble_analyzer.py    // RF + LSTM + XGBoost + KMeans + HMM
│   ├── s03_smc_analyzer.py ... s16_spike_analyzer.py
│   └── ml_models/
│       ├── random_forest_model.py
│       ├── lstm_model.py
│       ├── xgboost_model.py
│       ├── kmeans_model.py
│       ├── hmm_model.py
│       └── model_trainer.py           // Training pipeline
├── config_push/
│   ├── config_builder.py              // Build CONFIG_PUSH message
│   └── config_pusher.py               // Send via ZMQ PUB
└── reports/
    ├── csv_reporter.py                // Daily/weekly/monthly
    ├── decision_analytics.py          // Reasoning quality
    └── retrain_reporter.py            // ML model performance
```

---

## 9. PHASE BREAKDOWN (10 Phases, ~42 Chats, ~22 Weeks)

### Phase Overview Table

| Phase | Description | Duration | Chats | Track | Can Parallel With |
|-------|------------|----------|-------|-------|-------------------|
| **P0** | Foundation & Core Bridge | 2 wk | 5 | Both | — (ต้องทำก่อน) |
| **P1** | MQL5 Strategy Suite A (S01-S08) | 2 wk | 5 | Track A | P3 (MM) |
| **P2** | MQL5 Strategy Suite B (S09-S16) | 2 wk | 4 | Track A | P4 (Python Brain) |
| **P3** | Money Management (19 MM) | 2 wk | 4 | Track A | P1, P4 |
| **P4** | Python Brain — Intelligence Engine | 4 wk | 8 | Track B | P1, P2, P3 |
| **P5** | Universal Modules | 1 wk | 2 | Track A | P4 |
| **P6** | Client Intelligence & Standalone | 2 wk | 4 | Track C | P7 (Reports) |
| **P7** | Reports & Analytics | 1 wk | 3 | Track B | P6 |
| **P8** | Testing & Integration | 2 wk | 4 | Track C | — |
| **P9** | Production & Polish | 1 wk | 1 | Both | — |
| | **TOTAL** | **~22 wk** | **~42** | | |

### Parallel Execution Timeline

```
Week:  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22
       ▓▓▓▓▓▓▓▓                                                          P0 Foundation
             ▓▓▓▓▓▓▓▓                                                    P1 MQL5 Suite A
                   ▓▓▓▓▓▓▓▓                                              P2 MQL5 Suite B
             ▓▓▓▓▓▓▓▓                                                    P3 MM Library ←parallel P1
                   ░░░░░░░░░░░░░░░░░░░░                                  P4 Python Brain ←parallel P2,P3
                         ▓▓▓▓                                            P5 Universal ←parallel P4
                                           ▓▓▓▓▓▓▓▓                     P6 Client Intelligence
                                           ░░░░░░                        P7 Reports ←parallel P6
                                                     ▓▓▓▓▓▓▓▓           P8 Testing
                                                               ▓▓▓▓     P9 Production

▓ = active work, ░ = parallel track
```

### How to Parallel: Multi-Chat Guide

**Chat A (MQL5):** ทำ P1, P2, P3, P5 ตามลำดับ — ไม่ต้องรอ Python เลย
**Chat B (Python):** ทำ P4 ตามลำดับ — ไม่ต้องรอ MQL5 เลย
**Chat C (Integration):** ทำ P6, P7 เมื่อ A+B เสร็จส่วนที่ต้องใช้

**ตัวอย่าง Week 3-4:**
- เปิด Chat 1: ทำ P1-1 (StatArb + MeanRev MQL5)
- เปิด Chat 2: ทำ P3-1 (MM1-MM5) ← ทำพร้อมกันได้
- เปิด Chat 3: ทำ P1-2 (KAMA + Turtle MQL5) ← ทำพร้อมกันได้

**ตัวอย่าง Week 5-8:**
- เปิด Chat 1: ทำ P2-1 (Session Breakout + Ichimoku MQL5)
- เปิด Chat 2: ทำ P4-1 (Regime Classifier Python) ← ทำพร้อมกันได้

---

## 10. DETAILED PHASE SPECIFICATIONS & CHAT PROMPTS

---

### 📋 PHASE 0: FOUNDATION & CORE BRIDGE (Week 1-2, 5 Chats)

ต้องทำก่อนทุก Phase — สร้าง skeleton ทั้งระบบ

---

#### CHAT P0-1: IStrategy Interface + StrategyConstants

**PROMPT:**
```
## FlashEASuite V2 — P0-1: IStrategy Interface + StrategyConstants

### CONTEXT
เรากำลังสร้าง FlashEASuite V2 V6 — ระบบเทรดอัตโนมัติ 16 strategies
Architecture: "Smart Server, Powerful Client" — strategy logic ทุกตัวอยู่ MQL5
Server เลือกว่าเปิด strategy ไหน, Client คำนวณ signal เอง

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน Section: MQL5 Implementation Details, Strategy Interface)
- FlashEASuite_V2_Roadmap_V5_FULL.docx (อ่าน Section: Phase 0)
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.1: Strategy Implementation)
- SYSTEM_OVERVIEW.md
- REFACTORING_COMPLETE.md

### DELIVERABLES
สร้าง 2 ไฟล์:

**1. IStrategy.mqh** — Strategy Interface
- virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
- virtual void Analyze(MqlTick &tick) → update internal signals
- virtual int GetSignal() → BUY=1, SELL=-1, NONE=0
- virtual double GetConfidence() → 0.0-1.0
- virtual double GetStopLoss() / GetTakeProfit()
- virtual string GetName() / int GetMagic()
- virtual string GetCategory() → "Full_MQL5" or "Hybrid"
- virtual bool IsStandaloneCapable() → true/false
- virtual void SetParameters(string jsonParams) → receive from CONFIG_PUSH
- virtual void OnConfigUpdate(/* config struct */)

**2. StrategyConstants.mqh** — All 16 strategies defined
- enum ENUM_STRATEGY_ID { S01_STAT_ARB=0, S02_ML_ENSEMBLE=1, ..., S16_SPIKE=15 }
- Magic numbers: 1001-1016
- Strategy names, categories, standalone capable flags
- Default parameters per strategy
- Regime preference mapping: S01→RANGING, S06→TRENDING, etc.

### CODING ORDER
1. IStrategy.mqh interface first
2. StrategyConstants.mqh with full 16-strategy enum
3. Test: compile both files, no errors

### OUTPUT
ไฟล์ทั้งหมดใน: 03_Trader/Include/Strategies/
ภาษา: Code comments = English, อธิบายเพิ่ม = Thai
```

---

#### CHAT P0-2: ZMQ Protocol + MessagePack + 15 Message Types

**PROMPT:**
```
## FlashEASuite V2 — P0-2: ZMQ Protocol + MessagePack Handler

### CONTEXT
ระบบ FlashEASuite V2 V6 ใช้ ZeroMQ + MessagePack สื่อสารระหว่าง 3 components:
- Feeder → Server: PUSH/PULL (Port 7777)
- Server → Clients: PUB/SUB (Port 7778)
- Clients → Server: PUSH/PULL (Port 7779)

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน Section: Protocol Specification — 15 message types)
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.5: Protocol)
- DLL_TOOLS_GUIDE.md / DLL_TOOLS_GUIDE.txt
- SYSTEM_OVERVIEW.md

### DELIVERABLES

**Python Side (02_Brain/core/):**
1. message_types.py — 15 message type constants + dataclasses
2. protocol_handler.py — ZMQ PUB/SUB/PUSH/PULL + MessagePack encode/decode
   - send_config_push(), send_initial_config(), send_news_alert()
   - send_regime_change(), send_command()
   - receive_tick(), receive_trade_report(), receive_heartbeat()

**MQL5 Side (03_Trader/Include/Core/):**
1. MessageTypes.mqh — 15 message type constants
2. Protocol.mqh — ZMQ wrapper + MessagePack decode
   - Init(serverIP, port, clientID)
   - SendClientHello(), SendHeartbeat(), SendTradeReport()
   - ReceiveMessage() → parse MessagePack → route by type
   - Shutdown()

### 15 MESSAGE TYPES
| ID | Name | Direction |
|----|------|-----------|
| 1 | TICK_DATA | Feeder→Server |
| 2 | OHLC_DATA | Feeder→Server |
| 3 | INDICATOR_DATA | Feeder→Server |
| 10 | CONFIG_PUSH | Server→Clients |
| 11 | CLIENT_HELLO | Client→Server |
| 12 | INITIAL_CONFIG | Server→Client |
| 13 | HEARTBEAT | Client↔Server |
| 20 | TRADE_REPORT | Client→Server |
| 21 | POSITION_UPDATE | Client→Server |
| 22 | PERFORMANCE_METRICS | Client→Server |
| 30 | NEWS_ALERT | Server→Clients |
| 31 | REGIME_CHANGE | Server→Clients |
| 40 | COMMAND | Server→Client |
| 50 | POLICY_UPDATE | Server→Clients |
| 99 | ERROR | Any→Any |

### CODING ORDER
1. Python message_types.py first (shared definitions)
2. Python protocol_handler.py
3. MQL5 MessageTypes.mqh (mirror Python definitions)
4. MQL5 Protocol.mqh
5. Test: Python sends CONFIG_PUSH → MQL5 receives and parses correctly

### OUTPUT
Python: 02_Brain/core/
MQL5: 03_Trader/Include/Core/
```

---

#### CHAT P0-3: Main EA Skeleton + File Structure

**PROMPT:**
```
## FlashEASuite V2 — P0-3: Main EA Skeleton (FlashEA_V6.mq5)

### CONTEXT
สร้าง main EA file ที่เป็น skeleton — ยังไม่มี strategy logic แต่มีโครงสร้างครบ:
Online Mode + Standalone Mode + StrategyManager + ConfigReceiver

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน Section: MQL5 Implementation Details — Main EA Structure code)
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 6: MQL5 Code Detail)
- SYSTEM_OVERVIEW.md
- REFACTORING_COMPLETE.md (ดู code ที่ refactor แล้ว)

### DELIVERABLES
สร้าง 4 ไฟล์:

**1. FlashEA_V6.mq5** — Main EA (ตาม Manus skeleton pattern)
- Input parameters: ServerIP, ServerPort, ClientID, EnableStandalone
- Global objects: Protocol, ConfigReceiver, ConnectionMonitor, StrategyManager, StandaloneSelector
- OnInit(): Initialize all components + send CLIENT_HELLO
- OnDeinit(): Shutdown ZMQ
- OnTick(): Check connection → Online/Standalone mode switch
- OnTimer(): Heartbeat every 10s + connection timeout 30s
- ProcessMessage(): Route by message type

**2. StrategyManager.mqh**
- RegisterStrategy(IStrategy*)
- EnableStrategy(strategyID) / DisableStrategy(strategyID)
- OnTick() → call enabled strategies
- ApplyConfig(configData) → parse CONFIG_PUSH and enable/disable
- GetEnabledCount(), GetStrategyByID()

**3. ConfigReceiver.mqh**
- ReceiveConfig(raw message) → parse → apply to StrategyManager
- SaveStandaloneConfig() → write standalone_config.dat
- GetLastConfigTime()

**4. ConnectionMonitor.mqh**
- IsConnected() → check heartbeat timeout (30s)
- UpdateHeartbeat() → reset timer
- GetDisconnectDuration()

### IMPORTANT
- StrategyManager จะ register 16 strategies แต่ยังไม่มี implementation (placeholder)
- ใช้ IStrategy.mqh จาก P0-1
- ใช้ Protocol.mqh จาก P0-2
- Online/Standalone switch logic ต้องทำงาน

### CODING ORDER
1. ConnectionMonitor.mqh (simplest)
2. ConfigReceiver.mqh
3. StrategyManager.mqh
4. FlashEA_V6.mq5 (main, depends on all above)
5. Test: compile main EA (will have warnings about missing strategies — OK)
```

---

#### CHAT P0-4: InfluxDB Setup + Data Ingestion (Python)

**PROMPT:**
```
## FlashEASuite V2 — P0-4: InfluxDB Setup + Data Ingestion

### CONTEXT
V6 ใช้ InfluxDB เก็บ time-series data สำหรับ ML training (จาก Manus recommendation)
แทนที่ in-memory ของ V5 ที่ไม่พอสำหรับ historical analysis

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: Data Ingestion, TimescaleDB mentions)
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.5: Database)
- SYSTEM_OVERVIEW.md
- main.py (existing Brain code)

### DELIVERABLES

**1. influxdb_client.py** (02_Brain/data/)
- InfluxDBClient class
- write_tick(symbol, bid, ask, volume, timestamp)
- write_ohlc(symbol, tf, o, h, l, c, vol, timestamp)
- write_indicators(symbol, tf, indicators_dict, timestamp)
- query_range(symbol, start, end, measurement) → DataFrame
- query_latest(symbol, measurement, n_points) → DataFrame
- health_check() → bool

**2. data_ingestion.py** (02_Brain/data/)
- DataIngestion class
- receive_from_feeder() → parse TICK_DATA, OHLC_DATA, INDICATOR_DATA
- store_to_influxdb()
- calculate_derived_indicators() → ADX, ATR, RSI, BB from raw OHLC
- get_feature_dataframe(symbol, lookback_bars) → ready for ML

**3. config.py** updates
- INFLUXDB_URL, INFLUXDB_TOKEN, INFLUXDB_ORG, INFLUXDB_BUCKET
- DATA_RETENTION_DAYS = 180

### CODING ORDER
1. config.py (add InfluxDB settings)
2. influxdb_client.py
3. data_ingestion.py
4. Test: write 1000 fake ticks → query back → verify
```

---

#### CHAT P0-5: Foundation Integration Test

**PROMPT:**
```
## FlashEASuite V2 — P0-5: Foundation Integration Test

### CONTEXT
ทดสอบว่า Foundation ทั้งหมด (P0-1 ถึง P0-4) ทำงานร่วมกันได้

### ATTACHED FILES
- Code จาก P0-1 ถึง P0-4 ทั้งหมด
- SYSTEM_OVERVIEW.md

### TEST SCENARIOS
1. **ZMQ Round-trip:** Python sends CONFIG_PUSH → MQL5 receives → parses → applies to StrategyManager → MQL5 sends TRADE_REPORT back → Python receives
2. **15 Message Types:** ทดสอบ send/receive ทุก message type
3. **InfluxDB Pipeline:** Feeder sends TICK → Python stores in InfluxDB → query back → verify
4. **Heartbeat:** MQL5 sends HEARTBEAT every 10s → Python responds → test timeout (kill Python → MQL5 detects disconnect within 30s)
5. **Main EA Boot:** FlashEA_V6.mq5 starts → sends CLIENT_HELLO → receives INITIAL_CONFIG → switches to Online mode

### DELIVERABLES
1. test_foundation.py — Python integration test script
2. test_foundation_ea.mq5 — MQL5 test script
3. Fix any issues found

### SUCCESS CRITERIA
- All 5 scenarios pass
- Zero packet loss
- Latency < 10ms for all messages
- InfluxDB write/query works
```

---

### 📋 PHASE 1: MQL5 STRATEGY SUITE A — S01-S08 (Week 3-4, 5 Chats)

**Track A — สามารถทำ parallel กับ P3 (MM) ได้**

---

#### CHAT P1-1: S01 StatArb + S07 MeanRev (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P1-1: S01 Statistical Arbitrage + S07 Mean Reversion

### CONTEXT
ทั้ง 2 strategies เป็น contrarian/mean-reversion family ทำพร้อมกันเพราะ logic คล้ายกัน
S01 = Hybrid (co-integration จาก Python, execution ใน MQL5)
S07 = Full MQL5 (RSI + BB + Vol filter)

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S01 StatArb, S09 MeanRev — logic + parameters)
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Statistical Arbitrage, Mean Reversion sections)
- IStrategy.mqh, StrategyConstants.mqh (จาก P0-1)

### S01: STATISTICAL ARBITRAGE
**Type:** Hybrid (Python calculates co-integration + Beta, MQL5 executes)
**Magic:** 1001 | **Standalone:** Yes (simple spread monitoring)
**Logic:**
1. Online Mode: receive Beta + pair selection from CONFIG_PUSH
2. Calculate Spread = Price_A - (Beta × Price_B)
3. Z-Score = (Spread - MA(Spread, 20)) / StdDev(Spread, 20)
4. Entry: Long spread @ Z < -2.0, Short spread @ Z > +2.0
5. Exit: Z returns to 0 or exceeds ±3.0
6. Standalone: use fixed Beta=1.0, monitor EURUSD vs GBPUSD

**MQL5 Parameters:**
input int StatArb_Period = 20;
input double StatArb_EntryZ = 2.0;
input double StatArb_StopZ = 3.0;
input string StatArb_Pair1 = "EURUSD";
input string StatArb_Pair2 = "GBPUSD";

### S07: MEAN REVERSION (VOL-FILTERED)
**Type:** Full MQL5 | **Magic:** 1007 | **Standalone:** Yes
**Logic:**
1. Entry Long: RSI(14) < 30 AND Stochastic(14,3,3) < 20
2. Entry Short: RSI(14) > 70 AND Stochastic(14,3,3) > 80
3. Vol Filter: ATR(14) < 1.3× MA(ATR, 20) — ห้ามเทรดถ้า vol สูงเกินไป
4. Exit: TP = Middle BB, SL = ±2× ATR
5. Confidence = (|Z-score of RSI from 50| / 50) × vol_factor

**MQL5 Parameters:**
input int MR_RSI_Period = 14;
input double MR_RSI_Buy = 30.0;
input double MR_RSI_Sell = 70.0;
input double MR_VolFilter = 1.3;

### CODING ORDER
1. S01_StatArb.mqh (implement IStrategy interface)
2. S07_MeanReversion.mqh (implement IStrategy interface)
3. Register both in StrategyManager
4. Test: compile + verify Analyze()/GetSignal()/GetConfidence() return valid values

### OUTPUT
03_Trader/Include/Strategies/S01_StatArb.mqh
03_Trader/Include/Strategies/S07_MeanReversion.mqh
```

---

#### CHAT P1-2: S06 KAMA/TrendFollow + S10 Turtle (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P1-2: S06 Adaptive Trend Following (KAMA) + S10 Turtle Trading

### CONTEXT
ทั้ง 2 strategies เป็น trend-following family
S06 = adaptive (KAMA adjusts speed), S10 = classic (Donchian breakout)
ทั้งคู่เป็น Standalone capable

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S07 KAMA, S11 Turtle — logic + parameters)
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Adaptive Trend Following, Turtle Trading)
- IStrategy.mqh, StrategyConstants.mqh

### S06: ADAPTIVE TREND FOLLOWING (KAMA)
**Type:** Full MQL5 | **Magic:** 1006 | **Standalone:** Yes
**Logic:**
1. Calculate KAMA(10, fast=2, slow=30) — Kaufman's Adaptive Moving Average
2. Calculate ER = Efficiency Ratio = |Direction| / Volatility
3. Entry Long: Price > KAMA AND KAMA slope > 0 AND ER > 0.3
4. Entry Short: Price < KAMA AND KAMA slope < 0 AND ER > 0.3
5. Exit: TP = 3× ATR, SL = 1× ATR or Price crosses KAMA back
6. Confidence = ER × (distance from KAMA / ATR)

### S10: TURTLE TRADING (MODERNIZED)
**Type:** Full MQL5 | **Magic:** 1010 | **Standalone:** Yes
**Logic:**
1. Donchian Channel: High(20) / Low(20)
2. Entry Long: Close > Upper Donchian + ATR×0.1
3. Entry Short: Close < Lower Donchian - ATR×0.1
4. Position sizing: 1% risk per ATR unit
5. Pyramiding: add up to 4 units, each 0.5× ATR apart
6. Exit: 10-period Donchian opposite side
7. Confidence = (breakout_strength / ATR) × trend_consistency

### CODING ORDER
1. S06_KAMA.mqh
2. S10_Turtle.mqh
3. Test: both return valid signals on trending pairs (XAUUSD on H1)
```

---

#### CHAT P1-3: S03 SMC + S05 Supply & Demand (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P1-3: S03 Smart Money Concepts + S05 Supply & Demand

### CONTEXT
ทั้ง 2 strategies เป็น price action / zone-based family
S03 = institutional (Order Blocks, FVG, BOS)
S05 = classic (RBD/DBR patterns, zone detection)
ทั้งคู่เป็น ServerOnly (complex, need server guidance)

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S04 SMC, S10 Supply & Demand)
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Smart Money Concepts, Supply & Demand)
- IStrategy.mqh, StrategyConstants.mqh

### S03: SMART MONEY CONCEPTS (SMC)
**Type:** Full MQL5 | **Magic:** 1003 | **ServerOnly**
**Logic:**
1. Detect Order Blocks (OB): high-volume candle before reversal
2. Detect Fair Value Gaps (FVG): gap between candle 1 and candle 3
3. Detect Break of Structure (BOS): Higher High / Lower Low break
4. Entry Long: Price returns to Bullish OB or FVG after BOS up
5. Entry Short: Price returns to Bearish OB or FVG after BOS down
6. Exit: TP = next swing H/L, SL = beyond OB
7. Confidence = (OB_strength × FVG_size / ATR) × volume_factor

**MQL5 Parameters:**
input int SMC_LookbackBars = 50;
input double SMC_MinOBVolume = 1.5; // × average volume
input double SMC_MinFVGSize = 0.5; // × ATR

### S05: SUPPLY & DEMAND
**Type:** Full MQL5 | **Magic:** 1005 | **ServerOnly**
**Logic:**
1. Detect RBD (Rally-Base-Drop) = Supply Zone
2. Detect DBR (Drop-Base-Rally) = Demand Zone
3. Zone strength = number of touches + time since creation
4. Entry Long: Price enters fresh Demand Zone (< 3 touches)
5. Entry Short: Price enters fresh Supply Zone (< 3 touches)
6. Exit: TP = opposite zone, SL = beyond zone
7. Confidence = freshness × zone_width_ratio × historical_bounce_rate

### CODING ORDER
1. SMC subfolder: OrderBlockDetector.mqh, FVGDetector.mqh, BOSDetector.mqh
2. S03_SMC.mqh (uses detectors)
3. SupplyDemand subfolder: ZoneDetector.mqh
4. S05_SupplyDemand.mqh
5. Test: detect OB and zones on XAUUSD H1 historical data
```

---

#### CHAT P1-4: S14 BBSqueeze + S13 FibStoch (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P1-4: S14 Bollinger Squeeze Breakout + S13 Fibonacci + Stochastic

### CONTEXT
S14 = volatility breakout (Standalone capable)
S13 = reversal/retracement (ServerOnly)

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S14 BB Squeeze, S13 Fibonacci+Stochastic)
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Bollinger Squeeze, Fibonacci + Stochastic)
- IStrategy.mqh, StrategyConstants.mqh

### S14: BOLLINGER SQUEEZE BREAKOUT
**Type:** Full MQL5 | **Magic:** 1014 | **Standalone:** Yes
**Logic:**
1. Squeeze detection: BB Width < Keltner Channel Width (BB inside KC)
2. Squeeze duration: count consecutive squeeze bars (min 6 bars)
3. Momentum: Linear Regression slope of Close
4. Entry Long: Squeeze releases (BB > KC) AND momentum > 0
5. Entry Short: Squeeze releases AND momentum < 0
6. Exit: TP = 2× ATR from entry, SL = opposite BB band
7. Confidence = squeeze_duration × momentum_strength / ATR

### S13: FIBONACCI + STOCHASTIC
**Type:** Full MQL5 | **Magic:** 1013 | **ServerOnly**
**Logic:**
1. Identify swing H/L (last 50 bars)
2. Draw Fibonacci retracement levels (23.6%, 38.2%, 50%, 61.8%)
3. Entry Long: Price at 38.2%-61.8% retracement + Stochastic < 20 (oversold)
4. Entry Short: Price at 38.2%-61.8% retracement + Stochastic > 80 (overbought)
5. Exit: TP = swing H/L, SL = beyond 78.6% retracement
6. Confidence = fib_level_accuracy × stoch_extremity × trend_strength

### CODING ORDER
1. S14_BBSqueeze.mqh
2. S13_FibStoch.mqh
3. Test: S14 detects squeeze on ranging pairs, S13 detects fib setups
```

---

#### CHAT P1-5: S04 Market Profile + S08 Intermarket (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P1-5: S04 Market Profile/OrderFlow + S08 Intermarket Correlation

### CONTEXT
S04 = Volume Profile / POC (Full MQL5) — ServerOnly
S08 = Intermarket Correlation (Hybrid — needs DXY from Python) — ServerOnly

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S06 Order Flow, S08 Intermarket)
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Market Profile, Currency Strength)
- IStrategy.mqh, StrategyConstants.mqh

### S04: MARKET PROFILE + ORDER FLOW
**Type:** Full MQL5 | **Magic:** 1004 | **ServerOnly**
**Logic:**
1. Build Volume Profile: tick volume at each price bin (50 bins)
2. Identify POC (Point of Control) = highest volume price
3. Identify VAH/VAL (Value Area High/Low) = 70% of total volume
4. Entry Long: Price below POC + increasing buy volume (tick volume + uptick)
5. Entry Short: Price above POC + increasing sell volume
6. Exit: TP = next volume node, SL = beyond POC
7. Confidence = volume_imbalance × poc_proximity × session_factor

### S08: INTERMARKET CORRELATION
**Type:** Hybrid | **Magic:** 1008 | **ServerOnly**
**Logic:**
1. Server calculates correlation: XAUUSD vs DXY (or USDX proxy)
2. Server sends correlation_coefficient + dxy_direction in CONFIG_PUSH
3. MQL5 receives: if corr < -0.7 AND DXY weakening → Long XAUUSD
4. if corr < -0.7 AND DXY strengthening → Short XAUUSD
5. Exit: TP = 2× ATR, SL = 1× ATR
6. Confidence = |correlation| × dxy_momentum × gold_volatility

**Standalone:** Not available (needs DXY data from server)

### CODING ORDER
1. MarketProfile subfolder: VolumeProfileBuilder.mqh, POCCalculator.mqh
2. S04_MarketProfile.mqh
3. S08_Intermarket.mqh (thin wrapper — receive signal from CONFIG_PUSH)
4. Test: Volume Profile builds correctly on XAUUSD M15
```

---

### 📋 PHASE 2: MQL5 STRATEGY SUITE B — S09-S16 (Week 5-6, 4 Chats)

---

#### CHAT P2-1: S09 Session Breakout + S11 Ichimoku (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P2-1: S09 London/NY Session Breakout + S11 Multi-TF Ichimoku

### ATTACHED FILES
- THE_ULTIMATE_20_FOREX_STRATEGIES_2026.docx (อ่าน: Session Breakout, Ichimoku sections)
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: S12 Ichimoku)
- IStrategy.mqh, StrategyConstants.mqh

### S09: LONDON/NY SESSION BREAKOUT
**Type:** Full MQL5 | **Magic:** 1009 | **ServerOnly**
**Logic:**
1. Define Asian session range: 00:00-08:00 GMT (broker time adjusted)
2. Calculate range: High - Low of Asian session
3. Entry Long: Price breaks above Asian High + filter (ATR×0.1) during London (08:00-12:00)
4. Entry Short: Price breaks below Asian Low - filter during London
5. Extended: NY session breakout (13:00-17:00) from London range
6. Exit: TP = 1.5× Asian range, SL = opposite side of range
7. Time filter: no trades after 17:00 GMT
8. Confidence = range_size / ATR × session_volume_factor

### S11: MULTI-TIMEFRAME ICHIMOKU
**Type:** Full MQL5 | **Magic:** 1011 | **ServerOnly**
**Logic:**
1. D1 Ichimoku: determine major trend direction (above/below cloud)
2. H4 Ichimoku: confirm trend (Tenkan/Kijun cross)
3. H1/M30 Entry: Tenkan crosses Kijun in trend direction + price above cloud
4. Chikou Span confirmation: must be above/below price 26 periods ago
5. Exit: Tenkan/Kijun cross against position or price enters cloud
6. Confidence = cloud_thickness × tenkan_kijun_distance × multi_tf_alignment

### CODING ORDER
1. S09_SessionBreakout.mqh (session time calculation + range detection)
2. S11_Ichimoku.mqh (multi-TF implementation: D1, H4, H1 coordination)
3. Test: S09 detects Asian range correctly, S11 generates aligned signals
```

---

#### CHAT P2-2: S12 Price Action + S02 ML Wrapper (MQL5)

**PROMPT:**
```
## FlashEASuite V2 — P2-2: S12 Price Action (Pin Bar) + S02 ML Ensemble Wrapper

### S12: PRICE ACTION (PIN BAR + ENGULFING)
**Type:** Full MQL5 | **Magic:** 1012 | **ServerOnly**
**Logic:**
1. Pin Bar: body < 30% of total range, wick > 60%, wick opposite to expected direction
2. Bullish Pin Bar: long lower wick at support → Entry Long
3. Bearish Pin Bar: long upper wick at resistance → Entry Short
4. Engulfing: current candle body completely covers previous body
5. Filter: must be at key level (swing H/L, round number, S/R zone)
6. Exit: TP = 2× candle range, SL = beyond pin bar wick
7. Confidence = wick_ratio × volume_on_pin × key_level_proximity

### S02: ML ENSEMBLE (MQL5 WRAPPER)
**Type:** Hybrid | **Magic:** 1002 | **ServerOnly**
**Logic:**
1. Thin wrapper — receives ml_signal and ml_confidence from CONFIG_PUSH
2. Execute: if ml_signal == 1 AND ml_confidence > 0.70 → BUY
3. if ml_signal == -1 AND ml_confidence > 0.70 → SELL
4. Signal timeout: 5 minutes (if no new signal, close position)
5. MQL5 manages execution + trailing stop
6. Confidence = ml_confidence (passed from server)

### CODING ORDER
1. PriceAction subfolder: PinBarDetector.mqh, EngulfingDetector.mqh, KeyLevelFinder.mqh
2. S12_PriceAction.mqh
3. S02_ML_Ensemble.mqh (thin wrapper — SetParameters receives ml_signal/ml_confidence)
4. Test: Pin Bar detection on XAUUSD D1
```

---

#### CHAT P2-3: S15 Grid + S16 Spike Adaptation

**PROMPT:**
```
## FlashEASuite V2 — P2-3: Grid + Spike Adaptation to IStrategy Framework

### CONTEXT
Grid (S15) และ Spike (S16) มี code อยู่แล้ว (legacy) — ต้อง adapt เข้า IStrategy interface
ไม่ต้องเขียนใหม่ทั้งหมด แค่ wrap ให้ compatible

### ATTACHED FILES
- REFACTORING_COMPLETE.md (ดู existing Grid + Spike code)
- main.py (existing code)
- IStrategy.mqh (interface from P0-1)

### DELIVERABLES
1. S15_Grid.mqh — wrap existing Grid logic into IStrategy
   - Init() → set grid parameters (spacing, levels)
   - Analyze() → update grid state
   - GetSignal() → return grid entry signals
   - GetConfidence() → based on ATR vs grid spacing
   - SetParameters() → receive grid config from CONFIG_PUSH
   - TransferToGrid() emergency function preserved

2. S16_Spike.mqh — wrap existing Spike logic into IStrategy
   - Init() → set spike detection parameters
   - Analyze() → monitor for spikes
   - GetSignal() → spike entry signals
   - GetConfidence() → based on spike magnitude / ATR
   - SetParameters() → receive config from CONFIG_PUSH

### IMPORTANT
- BACKWARD COMPATIBLE: existing Grid/Spike behavior must not change
- IStrategy wrapper adds new capabilities without breaking existing logic
- Magic numbers preserved: 1015, 1016

### CODING ORDER
1. S15_Grid.mqh (wrap existing)
2. S16_Spike.mqh (wrap existing)
3. Test: existing Grid + Spike behavior unchanged + new interface works
```

---

#### CHAT P2-4: StrategyManager Integration + 16-Strategy Registration Test

**PROMPT:**
```
## FlashEASuite V2 — P2-4: StrategyManager Full Integration

### CONTEXT
ทุก 16 strategies ถูกสร้างแล้ว (P1-1 → P2-3) — ตอนนี้ต้อง register ทั้งหมดเข้า StrategyManager
และทดสอบว่าทุกตัว compile + ทำงานได้

### DELIVERABLES

1. **Update StrategyManager.mqh** — register all 16 strategies
   - RegisterAllStrategies() → create instances of S01-S16
   - EnableByConfig(configData) → parse CONFIG_PUSH → enable selected strategies
   - DisableAllExcept(strategyIDs[]) → for standalone mode
   - GetStrategyStatus() → report enabled/disabled per strategy

2. **Update FlashEA_V6.mq5** — include all 16 strategy headers

3. **Test Script: test_all_strategies.mq5**
   - Initialize all 16 strategies on XAUUSD M15
   - Call Analyze() + GetSignal() + GetConfidence() for each
   - Verify: no crashes, all return valid values
   - Print report: strategy name, signal, confidence for each
   - Verify standalone capable strategies work in standalone mode

### SUCCESS CRITERIA
- All 16 strategies compile without errors
- All 16 return valid signals (BUY/SELL/NONE)
- All 16 return valid confidence (0.0-1.0)
- Standalone 7 strategies work when server disconnected
- ServerOnly 9 strategies return NONE when server disconnected
```

---

### 📋 PHASE 3: MONEY MANAGEMENT (Week 5-6, 4 Chats)

**Track A — สามารถทำ parallel กับ P1 ได้**

---

#### CHAT P3-1: MM1-MM5

**PROMPT:**
```
## FlashEASuite V2 — P3-1: Money Management Methods MM1-MM5

### ATTACHED FILES
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: MM1-MM5 ทั้งหมด + MQL5 code)
- 19_Dynamic_Money_Management_Methods_Comprehensive.docx
- IStrategy.mqh (for IMoneyManager interface pattern)

### DELIVERABLES
สร้าง IMoneyManager.mqh + MM1-MM5:

**IMoneyManager.mqh** — Interface
- virtual double CalculateLot(double balance, double equity, double stopLoss, string symbol)
- virtual string GetName()
- virtual int GetID()

**MM1:** Fixed Fractional Conservative (1% risk)
**MM2:** Fixed Fractional Aggressive (2% risk)
**MM3:** ATR-Based Dynamic (lot adjusted by ATR)
**MM4:** Kelly Criterion (win_rate × R:R formula, capped 25%)
**MM5:** Martingale Controlled (2× after loss, max multiplier = 4)

### FORMULAS (ให้ตรงกับที่ Manus ระบุ)
MM1: Lot = (Balance × 0.01) / (SL_pips × pip_value)
MM3: Lot = (Balance × Risk%) / (ATR × ATR_mult × pip_value)
MM4: Kelly% = (WinRate × RR - LossRate) / RR, capped at 25%
MM5: Lot = BaseLot × 2^(consecutive_losses), max 4

### CODING ORDER
1. IMoneyManager.mqh
2. MM01-MM05 each as separate .mqh file
3. Test: verify lot calculations with known inputs
```

---

#### CHAT P3-2: MM6-MM10

**PROMPT:**
```
## FlashEASuite V2 — P3-2: MM6-MM10

### ATTACHED FILES
- 19_Dynamic_Money_Management_Methods_Comprehensive.docx
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: MM6-MM10)

### DELIVERABLES
**MM6:** Anti-Martingale (increase after win)
**MM7:** Percent Volatility (vol-target sizing)
**MM8:** Pyramid Adding (add to winners, max 3 levels)
**MM9:** Equity Curve Recovery (reduce after equity dip)
**MM10:** Drawdown-Based (DD>10% → reduce 50%, DD>15% → reduce 75%, DD>20% → emergency)
```

---

#### CHAT P3-3: MM11-MM15

**PROMPT:**
```
## FlashEASuite V2 — P3-3: MM11-MM15

### DELIVERABLES
**MM11:** Session-Based (London 1.5%, NY 1.2%, Asian 0.5%)
**MM12:** Equity Curve Filter (only trade if equity > MA(equity))
**MM13:** Correlation Adjusted (reduce if correlated positions open)
**MM14:** Tiered Risk (balance <$1K → 2%, $1K-$10K → 1.5%, >$10K → 1%)
**MM15:** Adaptive Win-Streak (increase slowly after 3+ wins, reset on loss)
```

---

#### CHAT P3-4: MM16-MM19 + MMManager

**PROMPT:**
```
## FlashEASuite V2 — P3-4: MM16-MM19 + MMManager

### DELIVERABLES
**MM16:** Volatility Percentile (rank current vol in 100-bar history)
**MM17:** Regime-Based (TRENDING→1.5×, RANGING→1.0×, VOLATILE→0.3×)
**MM18:** Portfolio Cap (total exposure < 10% of equity)
**MM19:** Dynamic Multi-Method (combine 2-3 MM methods, take minimum lot)

**MMManager.mqh:**
- SelectMM(strategyID, regime, accountState) → choose best MM method
- MM Selection Matrix (which MM for which strategy)
- ApplyConfig(mm_method from CONFIG_PUSH) → override default selection
- GetActiveMM() → current MM for each strategy
- Default: standalone → MM1 always

### MM SELECTION MATRIX (Default)
| Strategy | Default MM | DD>10% MM | Volatile MM |
|----------|-----------|-----------|-------------|
| Grid | MM3 (ATR) | MM10 (DD) | MM17 (Regime) |
| Spike | MM1 (Fixed) | MM10 (DD) | MM1 (Fixed) |
| StatArb | MM4 (Kelly) | MM10 (DD) | MM7 (Vol) |
| KAMA | MM8 (Pyramid) | MM10 (DD) | MM16 (Vol%) |
| MeanRev | MM1 (Fixed) | MM10 (DD) | MM7 (Vol) |
| Turtle | MM8 (Pyramid) | MM10 (DD) | MM16 (Vol%) |
| BBSqueeze | MM3 (ATR) | MM10 (DD) | MM7 (Vol) |
| Others | MM1 (Fixed) | MM10 (DD) | MM17 (Regime) |
```

---

### 📋 PHASE 4: PYTHON BRAIN — INTELLIGENCE ENGINE (Week 7-10, 8 Chats)

**Track B — สามารถเริ่มได้ตั้งแต่ Week 5 parallel กับ P2, P3**

---

#### CHAT P4-1: Regime Classifier (3-Layer)

**PROMPT:**
```
## FlashEASuite V2 — P4-1: Regime Classifier (3-Layer: Rule + RF + HMM)

### CONTEXT
V6 ใช้ 3-layer regime classification (merged from Claude + Manus):
Layer 1: Rule-based (fast, shared with MQL5 standalone)
Layer 2: Random Forest ML (accuracy > 80%)
Layer 3: HMM for regime shift prediction (from Manus)

### ATTACHED FILES
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.4: ML & Regime)
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: Regime Classifier, HMM)
- FlashEASuite_V2_Roadmap_V5_FULL.docx (อ่าน: Regime Classifier section)

### DELIVERABLES
**regime_classifier.py** (02_Brain/intelligence/)

Layer 1 — Rule-Based:
- TRENDING: ADX > 25
- RANGING: ADX < 20
- VOLATILE: ATR > 1.5× MA(ATR)
- SQUEEZE: BB_Width < 0.5× MA(BB_Width)
- Hysteresis: enter TRENDING@27, exit@23

Layer 2 — Random Forest:
- Features: ADX, ATR, BB_Width, Volume, RSI, Stochastic, Price_Change, Session
- Labels: TRENDING, RANGING, VOLATILE, SQUEEZE
- Train on 6 months data per symbol
- Decision: RF confidence > 0.75 → use RF result

Layer 3 — Hidden Markov Model:
- States: 4 regimes
- Transition matrix: probability of switching between regimes
- Predict: next regime shift probability
- Decision: HMM shift probability > 0.80 → early warning

**Combined Logic:**
if RF_confidence > 0.75: use RF regime
elif HMM_shift_prob > 0.80: use HMM predicted regime
else: use Rule-based regime

### CODING ORDER
1. Rule-based classifier (fast, reliable)
2. Random Forest classifier + training pipeline
3. HMM model + fitting
4. Combined decision logic
5. Test: classify 100 historical periods, compare with labeled data
```

---

#### CHAT P4-2: 16 Strategy Analyzers (Python)

**PROMPT:**
```
## FlashEASuite V2 — P4-2: 16 Strategy Analyzers (Python Confidence Calculators)

### CONTEXT
Server ใช้ 16 Python analyzers เพื่อคำนวณ raw confidence (0.0-1.0) สำหรับ AI Council
แต่ละ analyzer ไม่ได้คำนวณ entry signal (MQL5 ทำ) — แค่ประเมินว่าตลาดเหมาะกับ strategy นี้แค่ไหน

### DELIVERABLES
**base_analyzer.py** — Base class
- analyze(symbol, regime, indicators, history) → {"confidence": 0.0-1.0, "reasoning": "..."}
- get_preferred_regimes() → list
- get_name(), get_id()

**16 analyzers** (s01_stat_arb_analyzer.py → s16_spike_analyzer.py):
แต่ละตัวคำนวณ confidence จาก current market conditions vs strategy preference
ตัวอย่าง:
- s01_stat_arb: Z-Score ยิ่งสุดขั้ว confidence ยิ่งสูง, regime=RANGING bonus
- s06_kama: ER ยิ่งสูง confidence ยิ่งสูง, regime=TRENDING bonus
- s15_grid: ATR ยิ่ง normal confidence ยิ่งสูง, regime=RANGING bonus

### IMPORTANT
Hybrid strategies (S01, S02, S08) ทำมากกว่า confidence:
- S01: คำนวณ co-integration + Beta + pair selection → ส่งใน CONFIG_PUSH parameters
- S02: รัน ML models → ส่ง ml_signal + ml_confidence
- S08: คำนวณ DXY correlation → ส่ง correlation + dxy_direction

### CODING ORDER
1. base_analyzer.py
2. 13 simple analyzers (confidence only)
3. 3 hybrid analyzers (confidence + parameters/signals)
4. Test: all 16 return valid confidence for XAUUSD
```

---

#### CHAT P4-3: AI Council Voting (5-Factor + R:R Gate)

**PROMPT:**
```
## FlashEASuite V2 — P4-3: AI Council Voting System

### CONTEXT
ระบบ Voting ของ V6 (merged):
- 5-factor weighted confidence (Claude)
- R:R gate (Manus)
- Gradual regime factor (improved from binary)
- Portfolio diversification
- Self-tuning weights

### ATTACHED FILES
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.3: AI Council comparison)

### DELIVERABLES
**strategy_council.py** (02_Brain/intelligence/)

Step 1: Collect votes from 16 analyzers
Step 2: Apply 5 factors:
   weighted = raw × hist_perf × regime_bonus × calendar × news
Step 3: R:R Gate — if expected R:R < 1.5 → SKIP
Step 4: Filter — if weighted < 0.55 → SKIP
Step 5: Portfolio diversification:
   - Strategy concentration < 40%
   - Symbol exposure < 15%
   - Correlation > 0.7 → reduce 50%
Step 6: Select top 1-3 per symbol
Step 7: Self-tuning — EMA(accuracy) per strategy×symbol, adjust weekly

**confidence_scorer.py** — Calculate weighted scores
**portfolio_diversifier.py** — Concentration + correlation checks

Regime Factor Scale (gradual):
Perfect match → 1.5, Good → 1.2, Neutral → 1.0, Poor → 0.5, Terrible → 0.3

### CODING ORDER
1. confidence_scorer.py (5-factor formula)
2. portfolio_diversifier.py
3. strategy_council.py (orchestrator)
4. Test: simulate 16 votes → verify selection logic + R:R gate
```

---

#### CHAT P4-4: Symbol Optimizer + Performance Tracker

**PROMPT:**
```
## FlashEASuite V2 — P4-4: Symbol Optimizer + Performance Tracker

### DELIVERABLES
**symbol_optimizer.py** — Select best symbols for each strategy
- analyze_all_symbols(symbols_list) → rank by recent performance
- get_best_symbols(strategy_id, n=5) → top symbols for this strategy
- update_rankings() → called daily

**performance_tracker.py** — Track accuracy per strategy×symbol
- record_prediction(strategy, symbol, prediction, actual_outcome)
- get_accuracy(strategy, symbol, lookback_days=30) → accuracy %
- get_ema_weight(strategy, symbol) → EMA(accuracy) for self-tuning
- get_win_rate(strategy, symbol) → for Kelly Criterion MM4
- save_metrics() / load_metrics() → persistent storage
```

---

#### CHAT P4-5: MM Optimizer + Config Push Builder

**PROMPT:**
```
## FlashEASuite V2 — P4-5: MM Optimizer + Config Push Builder

### DELIVERABLES
**mm_optimizer.py** — Select best MM per strategy + account state
- select_mm(strategy_id, regime, account_state) → MM method ID
- Use MM Selection Matrix from P3-4
- Override: DD>10% → MM10, DD>15% → reduce 75%, DD>20% → emergency
- Send MM assignment in CONFIG_PUSH

**config_builder.py** — Build complete CONFIG_PUSH message
- build_config_push(symbol_configs, regime, reasoning, standalone_config)
- Include: strategy assignments, MM methods, parameters, reasoning
- Format: MessagePack encoded
- Include standalone_config for client to save

**config_pusher.py** — Send via ZMQ PUB
- push_to_all(config_message) → broadcast
- push_to_client(client_id, config_message) → targeted
- push_initial_config(client_id) → Type 12 INITIAL_CONFIG
```

---

#### CHAT P4-6: Explainable Reasoning Engine

**PROMPT:**
```
## FlashEASuite V2 — P4-6: Explainable Reasoning Engine (4 Destinations)

### CONTEXT
V6 Explainable AI — ตอบโจทย์ Comparison Report Section 3.3 Recommendation #3
ทุก decision ต้องมี reasoning chain ที่อธิบายได้

### DELIVERABLES
**reasoning_builder.py** — Build full reasoning chain per symbol per cycle
Output structure:
{
  "regime": {"type", "method", "confidence", "detail"},
  "votes": [{"strategy", "raw", "hist", "regime_bonus", "cal", "news", "final", "rr", "reasoning"}] × 16,
  "selected": [{"rank", "strategy", "score", "allocation"}],
  "mm": {"method", "reasoning"},
  "risk": {"multiplier", "reasoning"},
  "summary_th": "...", "summary_en": "..."
}

**decision_logger.py** — Destination 2: JSON audit trail
- save to 02_Brain/logs/decisions/{date}_{HH}.json
- rotate: keep 30 days

**retrain_feedback.py** — Destination 4: Feedback to auto-retrain
- compare reasoning prediction vs actual outcome
- calculate accuracy per strategy×symbol
- trigger weight adjustment when accuracy drops

4 Destinations:
1. CONFIG_PUSH → Client (reasoning field)
2. Decision Log → JSON files
3. Performance Report → CSV (daily/weekly)
4. Auto-Retrain → accuracy → adjust council weights
```

---

#### CHAT P4-7: ML Ensemble Strategy (S02 Server-Side)

**PROMPT:**
```
## FlashEASuite V2 — P4-7: ML Ensemble Strategy — 5 Models

### CONTEXT
S02 ML Ensemble = strategy ที่ใช้ 5 ML models ทำนาย
(RF + LSTM + XGBoost + KMeans + HMM — merged Claude + Manus)

### ATTACHED FILES
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.4: ML Ensemble)
- FlashEASuite_V2_Roadmap_V5_FULL.docx (อ่าน: ML Ensemble Strategy section)

### DELIVERABLES
**feature_engineering.py** — 30+ features
- Price features: returns, momentum, acceleration
- Technical: ADX, ATR, RSI, Stochastic, BB, MACD
- Volatility: realized vol, vol ratio, vol percentile
- Volume: tick volume, volume MA ratio
- Multi-TF: H1, H4, D1 indicators
- Calendar: session, day of week, hour

**ml_models/ folder:**
- random_forest_model.py — regime classification (4 classes)
- lstm_model.py — price direction (UP/DOWN/NEUTRAL), 2-layer 64 units
- xgboost_model.py — confidence scoring (0.0-1.0) + feature importance
- kmeans_model.py — pattern clustering (identify profitable states)
- hmm_model.py — regime shift prediction (transition probabilities)
- model_trainer.py — training pipeline (6 months data, weekly retrain)

**s02_ml_ensemble_analyzer.py** — Orchestrator
- Run all 5 models → ensemble vote → final signal + confidence
- Send ml_signal (1/0/-1) + ml_confidence (0.0-1.0) to MQL5 via CONFIG_PUSH
- Feature importance for explainability

### CODING ORDER
1. feature_engineering.py
2. Random Forest + XGBoost (simpler, faster)
3. LSTM (needs tensorflow/pytorch — verify available)
4. KMeans + HMM
5. Ensemble orchestrator
6. Test: train on XAUUSD 6 months → predict next 1 month → measure accuracy
```

---

#### CHAT P4-8: Auto-Retrain System + Host CLI

**PROMPT:**
```
## FlashEASuite V2 — P4-8: Auto-Retrain System + Server CLI

### DELIVERABLES
**auto_retrain.py** — Automatic model retraining
- Weekly retrain: RF, XGBoost, LSTM on rolling 3-month window
- Trigger retrain: accuracy < 60% for 2 consecutive weeks
- Weight adjustment: EMA(accuracy) per strategy×symbol → update council weights
- Log all retrain events

**host_cli.py** — Server command line interface
- status: show connected clients, active strategies, current regime
- force_config: manually push specific strategy config
- retrain: trigger immediate model retrain
- report: generate performance summary
- stop/start: control intelligence engine
```

---

### 📋 PHASE 5: UNIVERSAL MODULES (Week 7, 2 Chats)

**Track A — parallel กับ P4**

---

#### CHAT P5-1: Hidden TP/SL Universal

**PROMPT:**
```
## FlashEASuite V2 — P5-1: Hidden TP/SL Universal Module

### DELIVERABLES
**HiddenTPSL.mqh** — Universal hidden TP/SL for all 16 strategies
- SetHiddenTP(ticket, price) / SetHiddenSL(ticket, price)
- CheckAndClose() → close if price reaches hidden level
- Broker cannot see real TP/SL levels
- Works with all strategies via IStrategy interface
- CONFIG_PUSH can override: hidden_tp_enabled, hidden_sl_enabled
```

---

#### CHAT P5-2: Trailing Stop Universal

**PROMPT:**
```
## FlashEASuite V2 — P5-2: Trailing Stop Universal Module

### DELIVERABLES
**TrailingStop.mqh** — 5 trailing stop methods:
1. Fixed Distance: trail by X pips
2. ATR-Based: trail by ATR × multiplier
3. Parabolic SAR: use SAR as trailing level
4. Chandelier Exit: highest high - ATR × multiplier
5. Breakeven + Trail: move SL to entry after X pips profit, then trail

Universal: works with all 16 strategies
CONFIG_PUSH can specify: trailing_method, trailing_params per strategy
```

---

### 📋 PHASE 6: CLIENT INTELLIGENCE & STANDALONE (Week 11-12, 4 Chats)

---

#### CHAT P6-1: ConfigReceiver + ConnectionMonitor (Full Implementation)

**PROMPT:**
```
## FlashEASuite V2 — P6-1: Full ConfigReceiver + ConnectionMonitor

### CONTEXT
Update the skeleton from P0-3 with full implementation:
- Parse all 15 message types
- Handle CONFIG_PUSH → apply to StrategyManager + save standalone_config.dat
- Handle INITIAL_CONFIG → first-time setup
- Handle NEWS_ALERT, REGIME_CHANGE, COMMAND
- Connection monitoring with 30s timeout

### DELIVERABLES
1. ConfigReceiver.mqh (full implementation)
2. ConnectionMonitor.mqh (full implementation)
3. Update FlashEA_V6.mq5 ProcessMessage() to handle all 15 types
4. standalone_config.dat save/load logic
```

---

#### CHAT P6-2: CStandaloneSelector (Full Implementation)

**PROMPT:**
```
## FlashEASuite V2 — P6-2: CStandaloneSelector — Full Implementation

### CONTEXT
V6 Standalone = Manus CStandaloneSelector + Claude improvements
Dynamic regime selection + config.dat fallback + confidence threshold + SQUEEZE

### ATTACHED FILES
- Claude_vs_Manus_V5_Comparison.docx (อ่าน Section 4.2: Standalone Mode — ทั้งหมด)
- FLASHEASUITE_V2_MASTER_ROADMAP_V5_FINAL_manus.docx (อ่าน: StandaloneSelector.mqh code)

### DELIVERABLES
**StandaloneSelector.mqh** (03_Trader/Include/Standalone/)
- CStandaloneSelector class
- Init(): load standalone_config.dat if exists, initialize 7 strategies
- OnTick(): DetectRegime() → SelectStrategies() → CalculateConfidence() → Execute()
- DetectRegime(): ADX + ATR + BB_Width, hysteresis (TRENDING@27/exit@23), SQUEEZE detection
- SelectStrategies(regime):
  TRENDING → KAMA + Turtle + BBSqueeze
  RANGING → Grid + StatArb + MeanRev
  VOLATILE → Spike + BBSqueeze
  SQUEEZE → BBSqueeze + Turtle
- CalculateConfidence(): simple threshold > 0.50
- All trades: MM1, risk × 0.5
- SaveConfig() / LoadConfig(): standalone_config.dat

**SimpleRegime.mqh** — Standalone regime detection (shared with Server Rule-based)
**StandaloneConfig.mqh** — Config file read/write

### CODING ORDER
1. SimpleRegime.mqh
2. StandaloneConfig.mqh
3. StandaloneSelector.mqh (main class)
4. Test: regime detection accuracy on XAUUSD M15 (compare with known regimes)
```

---

#### CHAT P6-3: Grid + Spike Full IStrategy Integration

**PROMPT:**
```
## FlashEASuite V2 — P6-3: Grid + Spike Full Adaptation + MMManager Integration

### CONTEXT
Final adaptation: Grid + Spike must work with:
- MMManager (all 19 MM methods)
- Hidden TP/SL
- Trailing Stop
- ConfigReceiver (online parameter updates)
- StandaloneSelector (offline mode)
- TransferToGrid() emergency function preserved

### DELIVERABLES
1. S15_Grid.mqh — full integration with MMManager + HiddenTPSL + TrailingStop
2. S16_Spike.mqh — full integration
3. TransferToGrid emergency function: shared across all strategies
4. Backward compatibility verified

### TEST
- Grid trades with MM3 (ATR-based) online
- Grid trades with MM1 (Fixed) standalone
- Spike trades with Hidden TP/SL
- Emergency TransferToGrid from any strategy
```

---

#### CHAT P6-4: Standalone + Online Integration Test

**PROMPT:**
```
## FlashEASuite V2 — P6-4: Standalone + Online Integration Test

### TEST SCENARIOS (5)
1. **Cold Start (no server):** EA starts → no standalone_config.dat → use hardcoded defaults → 7 strategies with default regime detection
2. **First Connect:** EA starts standalone → Server comes online → CLIENT_HELLO → INITIAL_CONFIG → switch to Online (16 strategies) → save standalone_config.dat
3. **Normal Operation:** Online mode → receive CONFIG_PUSH every 1-5 min → strategies enabled/disabled → reasoning displayed in Expert tab
4. **Server Disconnect:** Kill Server → client detects timeout (30s) → switch to Standalone → load standalone_config.dat → 7 strategies, risk × 0.5 → ServerOnly positions closed within 5 min
5. **Reconnect:** Server comes back → CLIENT_HELLO → INITIAL_CONFIG → switch back to Online → full 16 strategies restored

### SUCCESS CRITERIA
- All 5 scenarios work without crashes
- Transition Online↔Standalone takes < 5 seconds
- No orphaned positions (all ServerOnly positions properly closed)
- standalone_config.dat saves/loads correctly
- Regime detection matches between standalone and server (Rule-based layer)
```

---

### 📋 PHASE 7: REPORTS & ANALYTICS (Week 13, 3 Chats)

---

#### CHAT P7-1: CSV Reports

**PROMPT:**
```
## FlashEASuite V2 — P7-1: CSV Reports (Daily/Weekly/Monthly)

### DELIVERABLES
**csv_reporter.py** (02_Brain/reports/)
- Daily report: trades, P/L, strategy attribution, regime accuracy
- Weekly report: strategy performance ranking, MM effectiveness, AI Council accuracy
- Monthly report: overall P/L, drawdown analysis, model accuracy, regime distribution
- 16-strategy attribution: which strategy contributed how much profit
- Reasoning quality: how often did the AI Council's reasoning match actual outcome

Columns per trade:
timestamp, symbol, strategy, mm_method, direction, lot, entry, exit, pnl, confidence, regime, reasoning_correct
```

---

#### CHAT P7-2: Decision Analytics + P7-3: Retrain Reports

**PROMPT:**
```
## FlashEASuite V2 — P7-2+P7-3: Decision Analytics + Retrain Reports

### DELIVERABLES
**decision_analytics.py:**
- AI Council accuracy per strategy×symbol
- Regime prediction accuracy (Rule vs RF vs HMM)
- Reasoning chain quality: was the explanation consistent with outcome?
- False positive/negative rates per strategy

**retrain_reporter.py:**
- ML model performance over time (accuracy curves)
- Feature importance changes (which features became more/less important)
- Weight adjustment history (council weights evolution)
- Retrain event log (when, why, what changed)
```

---

### 📋 PHASE 8: TESTING & INTEGRATION (Week 14-15, 4 Chats)

---

#### CHAT P8-1 to P8-4

**PROMPT P8-1: Component Tests**
```
Test all components individually:
- 16 strategies × 3 symbols (XAUUSD, EURUSD, GBPUSD)
- 19 MM methods with edge cases
- ML Ensemble (all 5 models)
- Regime Classifier (all 3 layers)
- AI Council (voting logic, R:R gate, portfolio diversification)
- CStandaloneSelector (all 4 regimes)
```

**PROMPT P8-2: Full System Integration**
```
16 end-to-end scenarios:
- Each strategy: signal generation → AI Council approval → CONFIG_PUSH → MQL5 execution → TRADE_REPORT → performance tracking → reasoning log
- Multi-symbol: 5 symbols simultaneously
- Multi-strategy: 3 strategies active per symbol
```

**PROMPT P8-3: Performance & Stress Test**
```
8-hour continuous test:
- Benchmarks: Intelligence cycle < 2000ms, ML Ensemble < 5000ms, CONFIG_PUSH < 100ms
- InfluxDB write: > 1000 points/second
- Memory: stable (no leaks)
- CPU: < 50% average
- Zero crashes, zero packet loss
```

**PROMPT P8-4: Production Readiness Review**
```
Checklist:
- All 16 strategies verified
- All 19 MM methods verified
- Online/Standalone transition tested
- Security: RSA-2048 + anti-replay + DLL protection active
- Logging: all 4 explainable destinations working
- Auto-retrain: tested with simulated accuracy drop
- Backup: standalone_config.dat recovery tested
```

---

### 📋 PHASE 9: PRODUCTION & POLISH (Week 16, 1 Chat)

**PROMPT P9-1:**
```
Final review:
- Code cleanup
- Documentation update
- Deployment checklist
- Monitoring setup
- First-day operation plan
```

---

## 11. CODING ORDER & DEPENDENCIES (CRITICAL PATH)

### Dependency Layers

```
Layer 1 (Foundation) — ต้องเสร็จก่อน
  P0-1 → P0-2 → P0-3 → P0-4 → P0-5 (sequential)

Layer 2 (MQL5 Strategies) — Track A, after Layer 1
  P1-1, P1-2, P1-3, P1-4, P1-5 → P2-1, P2-2, P2-3 → P2-4
  [can parallel within P1-x, P2-x pairs]

Layer 3 (MM Library) — Track A, after P0-1, parallel with Layer 2
  P3-1 → P3-2 → P3-3 → P3-4

Layer 4 (Python Brain) — Track B, after P0-2 + P0-4
  P4-1 → P4-2 → P4-3 → P4-4 → P4-5 → P4-6 → P4-7 → P4-8
  [P4-7 can start after P4-2]

Layer 5 (Universal) — Track A, after P0-1
  P5-1, P5-2 [independent, parallel with anything]

Layer 6 (Client Integration) — Track C, after Layer 2 + P4-5
  P6-1 → P6-2 → P6-3 → P6-4

Layer 7 (Reports) — Track B, after P4-6
  P7-1 → P7-2/P7-3 [parallel with P6]

Layer 8 (Testing) — after Layers 2-7
  P8-1 → P8-2 → P8-3 → P8-4

Layer 9 (Production) — after Layer 8
  P9-1
```

### Parallel Tracks Map

```
TRACK A (MQL5):     P0→ P1-1|P1-2|P1-3|P1-4|P1-5 → P2-1|P2-2|P2-3 → P2-4 → P5-1|P5-2
TRACK A (MM):       P0→ P3-1 → P3-2 → P3-3 → P3-4   (parallel with P1)
TRACK B (Python):   P0→ P4-1 → P4-2 → P4-3 → P4-4 → P4-5 → P4-6 → P4-7 → P4-8
TRACK C (Integrate):     wait for A+B → P6-1 → P6-2 → P6-3 → P6-4
TRACK B (Reports):       wait for P4-6 → P7-1 → P7-2/P7-3 (parallel with P6)
TRACK C (Testing):       wait for all → P8-1 → P8-2 → P8-3 → P8-4 → P9-1
```

---

## 12. PROMPTS QUICK REFERENCE TABLE

| Phase | Chat | Name | Track | Parallel With | Status |
|-------|------|------|-------|---------------|--------|
| P0 | P0-1 | IStrategy + StrategyConstants | Both | — | 🔲 |
| P0 | P0-2 | ZMQ Protocol + MessagePack | Both | — | 🔲 |
| P0 | P0-3 | Main EA Skeleton | Both | — | 🔲 |
| P0 | P0-4 | InfluxDB + Data Ingestion | Python | — | 🔲 |
| P0 | P0-5 | Foundation Integration Test | Both | — | 🔲 |
| P1 | P1-1 | S01 StatArb + S07 MeanRev | MQL5 | P3-1 | 🔲 |
| P1 | P1-2 | S06 KAMA + S10 Turtle | MQL5 | P3-1, P3-2 | 🔲 |
| P1 | P1-3 | S03 SMC + S05 Supply&Demand | MQL5 | P3-2 | 🔲 |
| P1 | P1-4 | S14 BBSqueeze + S13 FibStoch | MQL5 | P3-3 | 🔲 |
| P1 | P1-5 | S04 MarketProfile + S08 Intermarket | MQL5 | P3-3 | 🔲 |
| P2 | P2-1 | S09 Session Breakout + S11 Ichimoku | MQL5 | P4-1 | 🔲 |
| P2 | P2-2 | S12 PriceAction + S02 ML Wrapper | MQL5 | P4-1, P4-2 | 🔲 |
| P2 | P2-3 | S15 Grid + S16 Spike Adaptation | MQL5 | P4-2 | 🔲 |
| P2 | P2-4 | StrategyManager + 16-Strategy Test | MQL5 | P4-3 | 🔲 |
| P3 | P3-1 | MM1-MM5 | MQL5 | P1-1, P1-2 | 🔲 |
| P3 | P3-2 | MM6-MM10 | MQL5 | P1-3, P1-4 | 🔲 |
| P3 | P3-3 | MM11-MM15 | MQL5 | P1-5 | 🔲 |
| P3 | P3-4 | MM16-MM19 + MMManager | MQL5 | P2-1 | 🔲 |
| P4 | P4-1 | Regime Classifier (3-Layer) | Python | P2-1 | 🔲 |
| P4 | P4-2 | 16 Strategy Analyzers | Python | P2-2 | 🔲 |
| P4 | P4-3 | AI Council Voting | Python | P2-4 | 🔲 |
| P4 | P4-4 | Symbol Optimizer + Performance Tracker | Python | P5-1 | 🔲 |
| P4 | P4-5 | MM Optimizer + Config Push Builder | Python | P5-2 | 🔲 |
| P4 | P4-6 | Explainable Reasoning Engine | Python | P6-1 | 🔲 |
| P4 | P4-7 | ML Ensemble (5 Models) | Python | P6-2 | 🔲 |
| P4 | P4-8 | Auto-Retrain + Host CLI | Python | P6-3 | 🔲 |
| P5 | P5-1 | Hidden TP/SL Universal | MQL5 | P4-4 | 🔲 |
| P5 | P5-2 | Trailing Stop Universal | MQL5 | P4-5 | 🔲 |
| P6 | P6-1 | ConfigReceiver + ConnectionMonitor | MQL5 | P7-1 | 🔲 |
| P6 | P6-2 | CStandaloneSelector | MQL5 | P7-1 | 🔲 |
| P6 | P6-3 | Grid + Spike Full Integration | MQL5 | P7-2 | 🔲 |
| P6 | P6-4 | Standalone Integration Test | Both | P7-3 | 🔲 |
| P7 | P7-1 | CSV Reports | Python | P6-1, P6-2 | 🔲 |
| P7 | P7-2 | Decision Analytics | Python | P6-3 | 🔲 |
| P7 | P7-3 | Retrain Reports | Python | P6-4 | 🔲 |
| P8 | P8-1 | Component Tests | Both | — | 🔲 |
| P8 | P8-2 | Full System Integration | Both | — | 🔲 |
| P8 | P8-3 | Performance & Stress Test | Both | — | 🔲 |
| P8 | P8-4 | Production Readiness | Both | — | 🔲 |
| P9 | P9-1 | Final Review & Deploy | Both | — | 🔲 |

**Total: 10 Phases, 42 Chats, ~22 Weeks**

---

## 13. RISK MITIGATION

| Risk | Impact | Mitigation |
|------|--------|------------|
| ML overfit | False signals → losses | Walk-forward validation, min 6-month training, weekly retrain |
| MQL5 indicator accuracy | Wrong signals | Cross-validate with Python calculations during P8 testing |
| Standalone too conservative | Miss profits offline | Gradual risk increase: start 0.5×, increase to 0.7× after 1 month if profitable |
| Strategy conflict | Contradicting signals | AI Council handles: top 1-3 per symbol, R:R gate filters |
| InfluxDB disk space | Server crash | 180-day retention, auto-purge old data |
| Network latency spike | Delayed CONFIG_PUSH | Client uses last config, standalone takes over after 30s |
| 16 strategies = complexity | Hard to debug | Phase-by-phase testing, each strategy tested independently first |
| HMM training instability | Bad regime predictions | HMM is Layer 3 (optional), Rule + RF as fallback |

---

## 14. V6 vs V5 vs MURAMASA COMPARISON

| Feature 		| FlashEASuite V6 					| FlashEASuite V5 (Claude) 		| Muramasa 	|
|---------		|-----------------					|-------------------------			|----------	|
| Strategies	| 16 (13 MQL5 + 3 Hybrid) 			| 16 (7 MQL5 + 9 Python) 		| 10 			|
| MM Methods| 19 (all MQL5) 					| 19 							| 1 			|
| Latency 		| 0ms (MQL5 local) + 3-7ms (config) 	| 3-7ms (all signals) 			| 10-100ms 	|
| AI Decision 	| 5-factor Council + R:R gate 			| 5-factor Council 				| LLM-based 	|
| ML Models 	| 5 (RF+LSTM+XGB+KM+HMM) 		| 4 (RF+LSTM+XGB+KM) 		| Unknown 	|
| Regime 		| 3-layer (Rule+RF+HMM) 			| 2-laye	r (Rule+RF) 			| Unknown 	|
| Standalone 	| 7 strategies + dynamic selector 		| 7 strategies + fixed lookup 		| None 		|
| Explainable 	| 4 destinations + full chain 			| 4 destinations + full chain 		| LLM text 	|
| Database 	| InfluxDB (persistent) 				| In-memory | Unknown 			|
| Protocol 	| MessagePack + 15 types 			| MessagePack + 8 types 		| HTTP/JSON 	|
| Security 	| RSA-2048 + DLL + anti-replay 		| RSA-2048 + DLL + anti-replay 	| None 		|
| Self-tuning 	| EMA weights + auto-retrain 		| EMA weights + auto-retrain 	| None 		|

**FlashEASuite V6 ชนะ Muramasa: 11-0 (with draws)**

---

*END OF ROADMAP V6 — MERGED EDITION*
*Total: ~42 chats, ~22 weeks, estimated ~30,000 lines of code*
*Document: ~2,200 lines of specification*
