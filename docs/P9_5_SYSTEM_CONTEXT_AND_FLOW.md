# FlashEASuite V2 — System Context, Architecture & Flow
## Generated: P9-5 Hierarchical Context Analysis (2026-02-26)

---

## 1. REQUIREMENT HIERARCHY (Rule of Recency Applied)

### Phase Timeline (Newest = Truth)

| Date | Phase | Key Output | Status |
|------|-------|-----------|--------|
| Dec 28-30, 2025 | P0.x–P1.x | Grid core, Protocol (ZMQ + MessagePack), FeederEA | COMPLETE |
| Jan 2026 | P2.x–P3.x | 16 Strategies, 19 MM methods, Standalone mode | COMPLETE |
| Feb 12, 2026 | Roadmap V6 | Architecture merged (Claude+Manus) — **CURRENT TRUTH** | COMPLETE |
| Feb 18, 2026 | P7.x–P8.x | Dashboard v3, Production tests (63+43 = 100% PASS) | COMPLETE |
| Feb 25, 2026 | P8-4 | MQL5 63/63 ✅ Python 43/43 ✅ — Readiness confirmed | COMPLETE |
| **Feb 26, 2026** | **P9-5** | **Monitoring & Validation** | **CURRENT** |

### Expired Features (Superseded — DO NOT USE)

| File | Superseded By |
|------|--------------|
| `engine_OLD.py` | `core/strategy/engine.py` |
| `analysis_OLD.py` | `core/strategy/analysis.py` |
| `policyOLD.py` | `core/strategy/policy.py` |
| `strategy_old_backup.py` | `core/strategy/engine.py` |
| `execution_listener_Backup.py` | `core/execution_listener.py` |
| `spike_test_injector_OLD.py` | `spike_test_injector.py` |
| `s02_ml_ensemble_analyzer01.py` | `s02_ml_ensemble_analyzer.py` |

---

## 2. SYSTEM ARCHITECTURE OVERVIEW

### "Smart Server, Powerful Client" — V6 Design Principle

```
Server (Python Brain) → decides WHICH strategies to run (not signals)
Client (MQL5 Trader)  → computes indicators + entry/exit signals
```

### Component Roles

```
┌─────────────────────────────────────────────────────────────┐
│                  FLASHEASUITE V2 V6                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  FEEDER EA (01_Feeder/Src/FeederEA.mq5)              │   │
│  │  Port 7777 — ZMQ PUB                                  │   │
│  │  28+ symbols → TICK_DATA + OHLC_DATA + INDICATOR_DATA │   │
│  │  Frequency: every 100ms per symbol                    │   │
│  └─────────────────────┬────────────────────────────────┘   │
│                         │ ZMQ PUB/SUB                        │
│  ┌──────────────────────▼────────────────────────────────┐  │
│  │  PYTHON BRAIN (02_Brain/) — Port 7777 SUB / 7778 PUB  │  │
│  │                                                        │  │
│  │  1. INGESTION (core/ingestion.py)                      │  │
│  │     → parse MessagePack tick data                      │  │
│  │     → write to InfluxDB (port 8086)                    │  │
│  │                                                        │  │
│  │  2. REGIME CLASSIFIER (core/intelligence/)             │  │
│  │     → 3-layer: Rule + Random Forest + HMM              │  │
│  │     → output: TRENDING / RANGING / VOLATILE / SQUEEZE  │  │
│  │                                                        │  │
│  │  3. STRATEGY ANALYZERS (strategies/s01–s16)            │  │
│  │     → 16 analyzers vote confidence (0.0–1.0)           │  │
│  │     → Python-side: S01 StatArb, S02 ML, S08 Intermarket│  │
│  │                                                        │  │
│  │  4. AI COUNCIL (core/intelligence/strategy_council.py) │  │
│  │     → weighted_conf = raw × hist_perf × regime_bonus   │  │
│  │                       × calendar_adj × news_adj        │  │
│  │     → R:R Gate: if R:R < 1.5 → SKIP                   │  │
│  │                                                        │  │
│  │  5. CONFIG BUILDER (config_push/config_builder.py)     │  │
│  │     → type=10 CONFIG_PUSH (MessagePack)                │  │
│  │     → includes: regime, symbol_configs, strategies,    │  │
│  │                 mm_method, parameters, standalone_cfg  │  │
│  │                                                        │  │
│  │  6. EXPLAINABLE AI (explainable/)                      │  │
│  │     → decision_logger.py → JSON log                    │  │
│  │     → CSV report, Auto-retrain trigger                 │  │
│  │                                                        │  │
│  │  7. DASHBOARD (dashboard.py) — 5s refresh              │  │
│  │     → Active strategy, Regime, P&L, ZMQ status,        │  │
│  │        Last config push, Trades today                  │  │
│  └─────────────────────┬────────────────────────────────┘  │
│                         │ ZMQ PUB (Port 7778)               │
│  ┌──────────────────────▼────────────────────────────────┐  │
│  │  TRADER EA (03_Trader/Src/ProgramC_Trader.mq5)         │  │
│  │  Port 7778 SUB / 7779 PUSH                             │  │
│  │                                                        │  │
│  │  ONLINE MODE:                                          │  │
│  │  → receives CONFIG_PUSH → activates selected strategies│  │
│  │  → computes indicators locally (latency=0)             │  │
│  │  → 16 strategies ALL in MQL5                           │  │
│  │  → 19 MM methods in MQL5                               │  │
│  │                                                        │  │
│  │  STANDALONE MODE (server disconnected):                │  │
│  │  → CStandaloneSelector detects regime per tick         │  │
│  │  → uses 7 core strategies (S01,S06,S07,S10,S14,S15,S16)│  │
│  │  → loads last standalone_config.dat                    │  │
│  │  → Risk × 0.5 (conservative)                           │  │
│  │                                                        │  │
│  │  TRADE_REPORT → Port 7779 → Brain (feedback loop)      │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. DATAFLOW

### 3.1 Tick Data Flow

```
FeederEA (MT5)
  → ZMQ PUB port 7777
  → MessagePack format: {type, symbol, bid, ask, time, ...}
  → Python Brain SUB (core/ingestion.py)
  → InfluxDB bucket: flashea_ticks (7-day retention for raw, 180-day for OHLC)
  → In-memory tick_buffer (per symbol, rolling window)
```

### 3.2 Intelligence & Decision Flow

```
tick_buffer
  → RegimeClassifier.classify(ohlc_data)
     → ADX + ATR + BB Width rules
     → + Random Forest model
     → + HMM model
     → → regime ∈ {TRENDING, RANGING, VOLATILE, SQUEEZE}

regime + tick_data
  → 16 Strategy Analyzers → raw_confidence[0..1]
  → AI Council (strategy_council.py):
     weighted = raw × ema_hist_perf × regime_bonus
               × calendar_adj × news_adj
     filter: weighted ≥ 0.50 AND R:R ≥ 1.5
  → selected strategies (subset of 16)
```

### 3.3 CONFIG_PUSH Flow

```
selected strategies
  → ConfigBuilder.build_config_push()
  → type=10 MessagePack:
     {
       "type": 10,
       "regime": "RANGING",
       "symbol_configs": [{symbol, strategies[], mm_method, parameters}],
       "standalone_config": {enabled_strategies, risk_multiplier, regime_hint},
       "reasoning": {summary_th, summary_en, changes[]}
     }
  → config_pusher.py → ZMQ PUB port 7778
  → ProgramC_Trader.mq5 SUB
  → unpack → enable strategies → compute signals locally
```

### 3.4 Feedback Loop (Trade Results)

```
ProgramC_Trader.mq5
  → TRADE_REPORT MessagePack:
     {type=9, ticket, symbol, strategy_id, pnl, direction, rr}
  → ZMQ PUSH port 7779
  → Python Brain PULL (core/execution_listener.py)
  → PerformanceTracker.record_prediction()
     → EMA weight update (alpha=0.1)
     → win_rate update for Kelly MM
  → DecisionLogger → JSON log
  → Auto-retrain trigger (if accuracy < threshold)
```

---

## 4. STRATEGY ARSENAL (16 Strategies)

| # | ID | Name | MQL5 Type | Standalone |
|---|----|------|-----------|-----------|
| 1 | S01 | Statistical Arbitrage | Hybrid (Python co-integration) | ✅ Yes |
| 2 | S02 | ML Ensemble | Hybrid (Python LSTM+RF+XGB) | ❌ Server Only |
| 3 | S03 | Smart Money Concepts | Full MQL5 | ❌ Server Only |
| 4 | S04 | Market Profile | Full MQL5 | ❌ Server Only |
| 5 | S05 | Supply & Demand | Full MQL5 | ❌ Server Only |
| 6 | S06 | KAMA Trend Follow | Full MQL5 | ✅ Yes |
| 7 | S07 | Mean Reversion (Vol-Filtered) | Full MQL5 | ✅ Yes |
| 8 | S08 | Intermarket Correlation | Hybrid (Python DXY) | ❌ Server Only |
| 9 | S09 | Session Breakout | Full MQL5 | ❌ Server Only |
| 10 | S10 | Turtle Trading | Full MQL5 | ✅ Yes |
| 11 | S11 | Multi-TF Ichimoku | Full MQL5 | ❌ Server Only |
| 12 | S12 | Price Action (Pin Bar) | Full MQL5 | ❌ Server Only |
| 13 | S13 | Fibonacci + Stochastic | Full MQL5 | ❌ Server Only |
| 14 | S14 | Bollinger Squeeze | Full MQL5 | ✅ Yes |
| 15 | S15 | Immortal Grid (Legacy) | Full MQL5 | ✅ Yes |
| 16 | S16 | Spike Hunter (Legacy) | Full MQL5 | ✅ Yes |

**7 Standalone:** S01, S06, S07, S10, S14, S15, S16

---

## 5. ML STACK

| Model | Library | Purpose |
|-------|---------|---------|
| Random Forest | scikit-learn | Regime classification + strategy council weights |
| LSTM | TensorFlow/Keras | S02 ML Ensemble price prediction |
| XGBoost | xgboost | S02 feature-based entry signal |
| K-Means | scikit-learn | Market clustering for regime detection |
| HMM | hmmlearn | Hidden state regime transitions |

---

## 6. PROTOCOL SUMMARY (ZMQ MessagePack)

| Message Type | ID | Direction | Description |
|-------------|----|-----------|----|
| TICK_DATA | 1 | FeederEA → Brain | Raw tick (bid/ask/time) |
| OHLC_DATA | 2 | FeederEA → Brain | OHLC bar close data |
| INDICATOR_DATA | 3 | FeederEA → Brain | Pre-computed indicators |
| TRADE_REPORT | 9 | Trader → Brain | Trade result feedback |
| CONFIG_PUSH | 10 | Brain → Trader | Strategy configuration |
| INITIAL_CONFIG | 12 | Brain → Trader | First-connect config |
| EMERGENCY_STOP | 14 | Brain → Trader | Halt all trading |
| HEARTBEAT | 15 | Brain ↔ Trader | Connection keepalive |

---

## 7. P9-5 PHASE OBJECTIVES & STATUS

| Sub-task | Status | Notes |
|---------|--------|-------|
| 4.1 dashboard.py (5s refresh + config push display) | ✅ DONE | v3.1.0 |
| 4.2 validate_live_readiness.py bugs fixed | ✅ DONE | 56/57 PASS (InfluxDB WARN only) |
| 4.3 PRODUCTION_READY_CHECKLIST.md | ✅ EXISTS | docs/PRODUCTION_READY_CHECKLIST.md |
| 5. Project Cleanup → _ARCHIVE_ | ✅ DONE | See _ARCHIVE_/ |

### Bugs Fixed in P9-5

| Bug | File | Fix |
|-----|------|-----|
| CF-1 | validate_live_readiness.py:307 | `builder.build()` → `builder.build_config_push()` |
| CF-2 | validate_live_readiness.py:319 | `builder.serialize()` → `builder.pack()` |
| CF-3 | validate_live_readiness.py:534 | Wrong config_builder.py path (missing `core/`) |
| CF-4 | validate_live_readiness.py:535 | Wrong config_pusher.py path (missing `core/`) |
| CF-5 | validate_live_readiness.py:686 | UnicodeEncodeError on Windows cp874 terminal |
| CF-6 | dashboard.py | Default refresh_rate 1.0 → 5.0 seconds |
| CF-7 | dashboard.py | Missing `last_config_push` display in System panel |

---

## 8. KNOWN ISSUES (Live Deployment)

| # | Issue | Severity | Status |
|---|-------|---------|--------|
| 1 | S16 Spike memory leak | Fixed | ✅ P9-4b: Strategy_Spike.mqh v2.02 |
| 2 | Feature engineering latency (100-340ms) | Medium | Not yet incremental |
| 3 | InfluxDB optional | Low | System works without it |
| 4 | Standalone fallback uses simplified regime | Low | Expected behavior |

---

## 9. PRE-LIVE STARTUP SEQUENCE

```
T-30min  python tools\validate_live_readiness.py --quick    (verify code)
T-20min  start_flashea.bat                                   (start Brain)
T-15min  MT5: attach FeederEA to XAUUSD.tp chart
T-10min  MT5: attach ProgramC_Trader to XAUUSD.tp chart
T-5min   verify dashboard.py shows GREEN status
T-2min   start_flashea.bat status → all GREEN
T-1min   python tools\health_monitor.py
T-0      Enable AutoTrading → GO LIVE 🚀
```

---

*P9-5 Context Document — FlashEASuite V2 | Generated 2026-02-26*
