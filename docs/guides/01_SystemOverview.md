# FlashEASuite V2 — System Overview

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01 | **Author:** Dr. Suksaeng Kukanok
> **Motto:** *"Smart Server, Powerful Client"*

---

## 1. Executive Summary

FlashEASuite V2 คือระบบเทรด Forex/Gold อัตโนมัติแบบ Hybrid ที่รวมจุดแข็งของ:
- **Python** (AI/ML, Regime Classification, Policy Selection)
- **MQL5** (Zero-latency signal computation, Trade execution)
- **ZeroMQ** (High-speed inter-process messaging)
- **MessagePack** (Compact binary serialization)

ระบบออกแบบตาม V6 Architecture ("Smart Server, Powerful Client"):

| Component | ทำหน้าที่ |
|-----------|-----------|
| Python Brain | วิเคราะห์ตลาด → เลือก strategy → ส่ง CONFIG_PUSH |
| MQL5 Trader | คำนวณ indicator + signal + execute trade (latency = 0) |
| FeederEA | ส่ง tick/OHLC/indicator data จาก MT5 → Brain |

---

## 2. Architecture Diagram

```
╔═══════════════════════════════════════════════════════════════════════╗
║                    FLASHEASUITE V2  V6 ARCHITECTURE                   ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │  PROGRAM A — FeederEA.mq5           Port 7777 ZMQ PUB           │  ║
║  │  28+ Forex/Gold symbols → TICK_DATA + OHLC_DATA + INDICATOR_DATA│  ║
║  │  Frequency: every 100ms per symbol (OnTimer)                     │  ║
║  └──────────────────────────┬──────────────────────────────────────┘  ║
║                              │ ZMQ PUB/SUB (MessagePack binary)        ║
║  ┌───────────────────────────▼─────────────────────────────────────┐  ║
║  │  PROGRAM B — Python Brain           Port 7777 SUB / 7778 PUB    │  ║
║  │                                                                   │  ║
║  │  Thread 1: Ingestion Worker                                       │  ║
║  │    └─ parse tick → InfluxDB (8086) → in-memory tick_buffer       │  ║
║  │                                                                   │  ║
║  │  Thread 2: Strategy Engine                                        │  ║
║  │    └─ RegimeClassifier (Rule + RF + HMM)                         │  ║
║  │    └─ 16 Strategy Analyzers → confidence[0.0..1.0]               │  ║
║  │    └─ AI Council (5-factor + R:R gate)                           │  ║
║  │    └─ ConfigBuilder → type=10 CONFIG_PUSH                        │  ║
║  │    └─ Explainable AI → JSON log + CSV + auto-retrain             │  ║
║  │    └─ Dashboard (5s refresh)                                      │  ║
║  │                                                                   │  ║
║  │  Thread 3: Execution Listener                                     │  ║
║  │    └─ PULL port 7779 → PerformanceTracker → EMA weight update    │  ║
║  └──────────────────────────┬──────────────────────────────────────┘  ║
║                              │ ZMQ PUB (port 7778, MessagePack)        ║
║  ┌───────────────────────────▼─────────────────────────────────────┐  ║
║  │  PROGRAM C — ProgramC_Trader.mq5   Port 7778 SUB / 7779 PUSH    │  ║
║  │                                                                   │  ║
║  │  [ONLINE MODE]                         [STANDALONE MODE]         │  ║
║  │  Receive CONFIG_PUSH                    CStandaloneSelector       │  ║
║  │  Activate selected strategies           7 Core Strategies         │  ║
║  │  Full power: 16 strategies              DetectRegime() per tick   │  ║
║  │  19 MM methods                          Risk × 0.5 (conservative) │  ║
║  │                                                                   │  ║
║  │  TRADE_REPORT → ZMQ PUSH port 7779 → Brain feedback loop         │  ║
║  └──────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════╝
```

---

## 3. ZMQ Communication Ports

| Port | Direction | Protocol | Data Type | Frequency |
|------|-----------|----------|-----------|-----------|
| **7777** | FeederEA → Brain | ZMQ PUB/SUB | TICK_DATA, OHLC_DATA, INDICATOR_DATA | 100ms/symbol |
| **7778** | Brain → Trader | ZMQ PUB/SUB | CONFIG_PUSH (type=10) | ทุก cycle (~5s) |
| **7779** | Trader → Brain | ZMQ PUSH/PULL | TRADE_REPORT (type=9) | ทุก position close |

---

## 4. Message Protocol (MessagePack Types)

| Message Type | ID | Direction | คำอธิบาย |
|-------------|----|-----------|---------|
| TICK_DATA | 1 | FeederEA → Brain | Raw bid/ask/time per tick |
| OHLC_DATA | 2 | FeederEA → Brain | OHLC bar close data |
| INDICATOR_DATA | 3 | FeederEA → Brain | Pre-computed indicators (MA, ATR, etc.) |
| TRADE_REPORT | 9 | Trader → Brain | Trade result: PnL, direction, R:R |
| CONFIG_PUSH | 10 | Brain → Trader | Strategy + MM configuration bundle |
| INITIAL_CONFIG | 12 | Brain → Trader | First-connect full configuration |
| EMERGENCY_STOP | 14 | Brain → Trader | Halt all trading immediately |
| HEARTBEAT | 15 | Brain ↔ Trader | Connection keepalive |

### CONFIG_PUSH Format (type=10 array):
```
[type, ts, symbol, strategy, entry, lot, max_orders, tp, sl, confidence, risk_mult]
```

Full JSON structure:
```json
{
  "type": 10,
  "regime": "RANGING",
  "symbol_configs": [
    {
      "symbol": "XAUUSD",
      "strategies": ["S07_MEAN_REV", "S15_GRID"],
      "mm_method": "MM03_ATR",
      "parameters": {...}
    }
  ],
  "standalone_config": {
    "enabled_strategies": ["S07", "S15"],
    "risk_multiplier": 0.5,
    "regime_hint": "RANGING"
  },
  "reasoning": {
    "summary_th": "ตลาด Ranging — เปิด Mean Reversion",
    "summary_en": "Market in ranging regime — activating S07",
    "changes": ["Disabled S10_TURTLE (low confidence)"]
  }
}
```

---

## 5. Data Flow Detail

### 5.1 Tick Data Flow

```
FeederEA (OnTimer every 100ms)
  → ZMQ PUB port 7777 (MessagePack)
  → Python Brain: core/ingestion.py (Thread 1)
    → Parse: {type=1, symbol, bid, ask, time, spread}
    → Write to InfluxDB bucket: flashea_ticks
      • Raw ticks: 7-day retention
      • OHLC bars: 180-day retention
    → Update in-memory tick_buffer[symbol] (rolling window)
```

### 5.2 Intelligence & Decision Flow

```
tick_buffer[symbol]
  → RegimeClassifier (core/intelligence/regime_classifier.py)
    → Layer 1: Rule-based (ADX > 25 = TRENDING, BB Width, ATR ratio)
    → Layer 2: Random Forest (scikit-learn, trained on labeled regimes)
    → Layer 3: HMM (hmmlearn, hidden state transitions)
    → Output: regime ∈ {TRENDING, RANGING, VOLATILE, SQUEEZE}

regime + tick_buffer
  → 16 Strategy Analyzers → raw_confidence[0.0..1.0] each
  → AI Council (core/intelligence/strategy_council.py):
      weighted_conf = raw × ema_hist_perf × regime_bonus
                      × calendar_adj × news_adj
      Filter: weighted_conf ≥ 0.50 AND R:R ≥ 1.5
  → Selected strategies (subset of 16)

selected strategies
  → ConfigBuilder.build_config_push()
  → ZMQ PUB port 7778 → ProgramC_Trader.mq5
```

### 5.3 Feedback Loop

```
ProgramC_Trader.mq5 (OnTradeTransaction)
  → TRADE_REPORT {type=9, ticket, symbol, strategy_id, pnl, direction, rr}
  → ZMQ PUSH port 7779
  → Python Brain: core/execution_listener.py (Thread 3)
    → PerformanceTracker.record_prediction()
      • EMA weight update (alpha=0.1) per strategy
      • Win rate update (used by Kelly MM)
    → DecisionLogger → JSON log (explainable/)
    → Auto-retrain trigger (if accuracy < threshold)
```

---

## 6. Component Details

### Program A — FeederEA

| Property | Value |
|----------|-------|
| File | `01_Feeder/Src/FeederEA.mq5` |
| Timer interval | 50–100ms (configurable) |
| Symbols | Up to 28+ (all in Market Watch) |
| Port | 7777 ZMQ PUB |
| Message types | 1 (TICK), 2 (OHLC), 3 (INDICATOR) |
| DLL required | `libzmq.dll`, `libsodium.dll` |

### Program B — Python Brain

| Property | Value |
|----------|-------|
| Entry point | `02_Brain/main.py` |
| Python version | 3.8+ (recommended 3.10) |
| Threads | 3: IngestionWorker, StrategyEngine, ExecutionListener |
| Ports | 7777 SUB (receive), 7778 PUB (send), 7779 PULL (feedback) |
| Memory target | < 300 MB |
| CPU target | < 15% steady-state |
| Dashboard | `02_Brain/dashboard.py` (auto, 5s refresh) |

**Python dependencies:**

| Package | Purpose |
|---------|---------|
| pyzmq | ZeroMQ messaging |
| msgpack | MessagePack serialization |
| numpy | Numerical computation |
| pandas | Data manipulation + OHLC processing |
| scikit-learn | Random Forest regime classifier |
| hmmlearn | Hidden Markov Model regime |

### Program C — ProgramC_Trader

| Property | Value |
|----------|-------|
| File | `03_Trader/ProgramC_Trader.mq5` |
| Version | V2.12 |
| Ports | 7778 SUB (receive), 7779 PUSH (feedback) |
| Strategies | 16 (all in MQL5) |
| MM Methods | 19 (all in MQL5) |
| Modes | Online (Brain connected), Standalone (Brain offline) |
| DLL required | `libzmq.dll`, `libsodium.dll` |

---

## 7. Online Mode vs Standalone Mode

| Feature | Online Mode | Standalone Mode |
|---------|------------|-----------------|
| Trigger | Brain connected | Brain offline / timeout |
| Strategy selection | Brain's AI Council | CStandaloneSelector per tick |
| Regime detection | Brain (RF + HMM) | Simplified rule-based |
| Available strategies | All 16 | 7 core (S01,S06,S07,S10,S14,S15,S16) |
| Risk multiplier | Brain-defined | × 0.5 (conservative) |
| Config source | Live CONFIG_PUSH | Last saved `standalone_config.dat` |
| Performance | Full power | Reduced but safe |

---

## 8. ML Stack (Python Brain Intelligence)

| Model | Library | Purpose |
|-------|---------|---------|
| Random Forest | scikit-learn | Regime classification + strategy council weights |
| LSTM | TensorFlow/Keras | S02 ML Ensemble price prediction |
| XGBoost | xgboost | S02 feature-based entry signal |
| K-Means | scikit-learn | Market clustering for regime detection |
| HMM | hmmlearn | Hidden state regime transitions |

---

## 9. AI Council — 5-Factor Formula

```
weighted_conf = raw_conf
              × ema_hist_perf    (exponential moving average of past performance)
              × regime_bonus     (bonus for strategies matching current regime)
              × calendar_adj     (reduce before high-impact news events)
              × news_adj         (real-time news sentiment adjustment)

Filter gates:
  1. weighted_conf ≥ 0.50 (minimum confidence threshold)
  2. R:R ≥ 1.5            (minimum risk-reward ratio gate)
```

---

## 10. Key File Map

| File | Role |
|------|------|
| `Include/Logic/StrategyConstants.mqh` | Strategy enum, magic numbers, regime table |
| `Include/Network/Protocol/Definitions.mqh` | SDynamicParams, ENUM_MARKET_REGIME, message types |
| `Include/Network/Protocol/Serialization.mqh` | MessagePack serialize/deserialize |
| `Include/Risk/RiskGuardian.mqh` | Daily loss limit, max drawdown protection |
| `Include/Security/DLLWrapper.mqh` | ZMQ DLL import wrapper |
| `Include/Logic/IStrategy.mqh` | IStrategy interface definition |
| `Include/Logic/StrategyManager_V6.mqh` | Council + strategy orchestration |
| `02_Brain/main.py` | Python Brain entry point (v2.1.0) |
| `02_Brain/core/strategy/engine.py` | StrategyEngineThreaded (v2.3) |
| `02_Brain/core/strategy/analysis.py` | Regime classification + spike scoring |
| `02_Brain/core/strategy/policy.py` | Policy selection + CONFIG_PUSH generation |
| `02_Brain/dashboard.py` | Real-time Brain dashboard (5s refresh) |
| `tools/health_monitor.py` | System health monitor |
| `tools/validate_live_readiness.py` | Pre-live readiness validator |
| `start_flashea.bat` | Main start/stop/status/doctor script |

---

## 11. Development Phase Timeline

| Date | Phase | Key Deliverables | Status |
|------|-------|-----------------|--------|
| Dec 28–30, 2025 | P0.x–P1.x | Grid core, ZMQ+MessagePack Protocol, FeederEA | ✅ COMPLETE |
| Jan 2026 | P2.x–P3.x | 16 Strategies, 19 MM methods, Standalone mode | ✅ COMPLETE |
| Feb 12, 2026 | Roadmap V6 | Architecture merge (Claude+Manus) — current truth | ✅ COMPLETE |
| Feb 18, 2026 | P7.x–P8.x | Dashboard v3, Production tests (63+43 = 100% PASS) | ✅ COMPLETE |
| Feb 25, 2026 | P8-4 | MQL5 63/63 ✅ Python 43/43 ✅ — Readiness confirmed | ✅ COMPLETE |
| Feb 26–27, 2026 | **P9-5** | **Monitoring, Validation, Documentation** | ✅ **COMPLETE** |

**Test Results:** 56/57 PASS (1 minor known issue — InfluxDB optional, non-blocking)

---

## 12. Design Principles

1. **Zero-latency execution** — All indicator computation happens in MQL5, never in Python
2. **Resilience** — Standalone mode ensures trading continues even when Brain is offline
3. **Explainability** — Every decision logged with full reasoning chain (Thai + English)
4. **Feedback loop** — Every trade result feeds back to improve future strategy weights
5. **Risk-first** — RiskGuardian enforces daily loss limit and max drawdown at all times
6. **Protocol integrity** — MessagePack binary ensures no parsing ambiguity or injection

---

*FlashEASuite V2 System Overview — V6 P9-5 Production | 2026-03-01*
