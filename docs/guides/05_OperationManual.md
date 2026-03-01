# FlashEASuite V2 — Operation Manual

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01
> **Author:** Dr. Suksaeng Kukanok | **Motto:** *"Smart Server, Powerful Client"*

---

## Table of Contents

1. [System Architecture Recap](#1-system-architecture-recap)
2. [System Startup](#2-system-startup)
3. [System Shutdown](#3-system-shutdown)
4. [System Monitoring](#4-system-monitoring)
5. [Daily Operations](#5-daily-operations)
6. [Configuration Reference](#6-configuration-reference)
7. [Emergency Procedures](#7-emergency-procedures)
8. [Quick Reference Card](#8-quick-reference-card)

---

## 1. System Architecture Recap

Three programs communicate via ZeroMQ:

```
FeederEA ──port 7777──► Python Brain ──port 7778──► ProgramC_Trader
(MT5, Program A)         (Python, Program B)        (MT5, Program C)
                              ▲                            │
                              └──────port 7779─────────────┘
                                   (TRADE_REPORT feedback)
```

| Port | Role | Data |
|------|------|------|
| 7777 | FeederEA → Brain | TICK_DATA, OHLC_DATA, INDICATOR_DATA |
| 7778 | Brain → Trader | CONFIG_PUSH (strategy + MM configuration) |
| 7779 | Trader → Brain | TRADE_REPORT (feedback loop) |

**Two operating modes:**
- **Online:** Brain connected → 16 strategies, full AI power
- **Standalone:** Brain offline → 7 core strategies, 50% risk, simplified regime

---

## 2. System Startup

### Required Start Order

> ⚠️ Always follow this order: **MT5 → Brain → FeederEA → Trader → Monitor**

---

### Step 1 — Start MetaTrader 5

```
1. Open MetaTrader 5
2. Wait for login (check status bar bottom-right)
3. Verify: Market Watch has required symbols
4. Verify: AutoTrading button = GREEN ✅
```

**Sign of success:** Status bar shows `xx/xx KB` (data flowing)

---

### Step 2 — Start Python Brain

Open Command Prompt from project root:

```cmd
cd C:\...\MQL5\Experts\FlashEASuite_V2\
start_flashea.bat
```

**Expected console output:**
```
================================================================================
FlashEASuite V2 — Python Brain v2.1.0
"Smart Server, Powerful Client"
================================================================================
Configuration:
  ZMQ Feeder (Tick Data):    tcp://127.0.0.1:7777
  ZMQ Execution (Policy):    tcp://127.0.0.1:7778
  ZMQ Feedback (Results):    tcp://127.0.0.1:7779

✅ Ingestion Worker started
✅ Strategy Engine started
✅ Execution Listener started
🚀 All workers started successfully (3 threads)
🎯 System is running with FEEDBACK LOOP enabled!
================================================================================
```

> 💡 Brain will wait for ticks if MT5 not yet connected — it will NOT crash.

---

### Step 3 — Attach FeederEA

> Skip this step if EA was attached in a previous MT5 session (state is remembered).

```
1. Open Chart 1 (any symbol, e.g. EURUSD M1)
2. MetaEditor Navigator (Ctrl+N) → Expert Advisors
   → FlashEASuite_V2 → 01_Feeder → Src → FeederEA
3. Drag FeederEA onto Chart 1
4. Inputs tab:
   - Timer interval: 50 (ms)
5. Common tab:
   - [✅] Allow DLL imports
6. Click OK
```

**Expected (MT5 → Experts tab):**
```
✅ ZMQ PUB bound to tcp://*:7777
✅ Timer started (50ms)
✅ Broadcasting on 4 symbols
```

---

### Step 4 — Attach ProgramC_Trader

> ⚠️ Use a **different chart** from FeederEA. MT5 allows only 1 EA per chart.

```
1. Open Chart 2 (different symbol/chart, e.g. GBPUSD M5)
2. Navigator → 03_Trader → ProgramC_Trader
3. Drag onto Chart 2
4. Inputs tab:
```

| Parameter | Value | Notes |
|-----------|-------|-------|
| `SYMBOL_PREFIX` | (empty) | Depends on broker |
| `SYMBOL_SUFFIX` | `.tp` | Check Market Watch for exact suffix |
| `V6_EnableMode` | `false` | Use legacy mode for stability |
| `InpMagicNumber` | `999000` | Default |
| `InpUserMaxRisk` | `2.0` | % risk per trade |

```
5. Common tab:
   - [✅] Allow DLL imports
   - [✅] Allow algo trading
6. Click OK
```

**Expected (MT5 → Experts tab):**
```
✅ ZMQ Hub created
✅ Subscribed to tcp://127.0.0.1:7778
✅ PUB Socket connected to tcp://127.0.0.1:7779
✅ Grid Strategy added to Council
✅ Spike Hunter Strategy added to Council
ProgramC_Trader V2.12 READY
```

---

### Step 5 — Start Health Monitor (optional)

Open a separate Command Prompt:

```cmd
cd C:\...\FlashEASuite_V2\
python tools\health_monitor.py
```

**Expected:**
```
🟢 Python Brain        UP
🟢 MetaTrader 5        UP
🟢 Port 7777           LISTENING
🟢 Port 7778           LISTENING
```

---

### Step 6 — Verify Data Flow

Check Brain console:
```
✅ Ticks Processed > 0 (and increasing)
✅ Dashboard shows active symbols
✅ No red error messages
```

Quick status check:
```cmd
start_flashea.bat status
```

Expected:
```
Python Brain:     [RUNNING]
MetaTrader 5:     [RUNNING]
Port 7777:        [LISTENING]
Port 7778:        [LISTENING]
Port 7779:        [FREE]        ← OK (Trader uses CONNECT, not BIND)
```

---

### Pre-Live Go Timeline

| Time | Action | Tool |
|------|--------|------|
| T-30 min | Full validation | `python tools\validate_live_readiness.py` |
| T-20 min | Start Brain | `start_flashea.bat` |
| T-15 min | Attach FeederEA | MT5 Navigator → drag EA |
| T-10 min | Attach Trader | MT5 Navigator → drag EA |
| T-5 min | Verify data flow | Brain console + Dashboard |
| T-2 min | Check status | `start_flashea.bat status` |
| T-1 min | Start health monitor | `python tools\health_monitor.py` |
| **T-0** | **🚀 GO LIVE** | **Enable AutoTrading** |

---

## 3. System Shutdown

### Normal Shutdown (Graceful)

Follow this order:

```
1. Remove Trader EA  (MT5: right-click chart → Expert Advisors → Remove)
2. Remove FeederEA   (MT5: same as above)
3. Stop Brain:       start_flashea.bat stop
4. Stop Monitor:     Ctrl+C in monitor window
5. Close MT5:        normal close
```

> ⚠️ **Never stop Brain while open positions exist.** Trader will switch to Standalone Mode which is safe, but Brain should ideally stay alive until all positions are closed.

---

### Emergency Shutdown Levels

#### Level 1 — Stop new trades immediately (5 seconds)
```
MT5 toolbar → click AutoTrading button → make it RED
```
Effect: All EAs stop sending new orders. Existing orders/positions remain open.

#### Level 2 — Remove EAs (30 seconds)
```
MT5 → Chart with Trader → Right-click → Expert Advisors → Remove
MT5 → Chart with Feeder → Right-click → Expert Advisors → Remove
```
Effect: ZMQ connections closed. No more order activity.

#### Level 3 — Full system stop (1 minute)
```cmd
start_flashea.bat stop    ← stops Brain
Ctrl+C                    ← stops Health Monitor
(Close MT5 normally)
```

#### Level 4 — Force kill (emergency only)
```cmd
taskkill /im python.exe /f
taskkill /im terminal64.exe /f
```
> ⚠️ After force kill: must restart entire system from Step 1.

---

### Close Open Positions

```
MT5 → Trade tab (bottom panel)
→ Right-click on position → Close Position
→ Or: Right-click → Close All Positions
```

---

## 4. System Monitoring

### Brain Dashboard (Auto, every 5 seconds)

```
══════════════════════════════════════════════════════
📊 STRATEGY ENGINE DASHBOARD v2.3
══════════════════════════════════════════════════════
Ticks Processed:    1,234
Policies Sent:      5
Risk Multiplier:    1.00×
Feedback Trades:    3W / 1L  (75.0% win rate)
Total P&L:          +23.50

Regime:             RANGING
Active Strategies:  S07_MEAN_REV, S15_GRID

Symbol Mapping:
  XAUUSD.tp        → XAUUSD    (1,234 ticks)
  EURUSD.tp        → EURUSD    (856 ticks)

Top 5 Symbols (Spike Score):
  1. XAUUSD      :  45.30  ⏳ Below threshold
  2. GBPUSD      :  32.10  ⏳ Below threshold
══════════════════════════════════════════════════════
```

---

### Monitoring Commands

| Command | Purpose |
|---------|---------|
| `start_flashea.bat status` | Quick service status check |
| `start_flashea.bat doctor` | Diagnose problems |
| `python tools\health_monitor.py` | Continuous real-time monitor |
| `python 02_Brain\dashboard.py` | Manual dashboard launch |
| `python tools\validate_live_readiness.py` | Full pre-live check |
| `python tools\validate_live_readiness.py --quick` | Fast import+file check |
| `python tools\validate_live_readiness.py --zmq` | ZMQ only |
| `python tools\validate_live_readiness.py --influx` | InfluxDB only |

---

### Key Metrics — Normal vs Warning

| Metric | Normal Range | Warning Signal | Action |
|--------|-------------|----------------|--------|
| Tick count | Increasing | Stopped = lost connection | Restart FeederEA |
| Policies sent | 0–50/hour | > 100/hour = overtrading | Review strategy thresholds |
| Spike score | 0–70 | > 70 = spike detected | Monitor S16 activity |
| Python Memory | 100–200 MB | > 500 MB = possible leak | Restart Brain |
| Python CPU | 5–10% | > 30% = performance issue | Investigate + restart |
| Risk Multiplier | 0.5–2.0× | Outside range = abnormal | Check config.py |
| Win Rate (30d) | 45–65% | < 40% = review selection | Check strategy params |
| Max Drawdown | < 10% | > 20% = emergency stop | Level 1 shutdown |
| Spread | Normal | 3× normal = news/volatile | Pause trading |

---

### Log Files

| File | Contents |
|------|---------|
| `02_Brain/logs/flashea_brain.log` | Brain main log (errors, decisions) |
| `02_Brain/logs/trades_YYYYMMDD.json` | Daily trade journal |
| `02_Brain/explainable/` | AI decision logs (full reasoning chain) |
| `logs/health.log` | Health monitor log (24h rolling) |
| `02_Brain/data/metrics/performance_metrics.json` | Strategy performance tracker |
| MT5 → Experts tab | Real-time EA messages |
| MT5 → Account History | Historical trade records |

---

## 5. Daily Operations

### Morning Routine (5 minutes, before market open)

- [ ] Check MT5 is open and connected (status bar shows data)
- [ ] Verify Brain running: `start_flashea.bat status` → `[RUNNING]`
- [ ] Review `logs/health.log` for overnight issues
- [ ] Check account balance + Free Margin > 50%
- [ ] Check economic calendar for high-impact news events
- [ ] Confirm Brain console shows tick count increasing

---

### Evening Routine (10 minutes, after market close)

- [ ] Review trade journal: MT5 → Account History
- [ ] Check Brain dashboard: tick count, policy count, win/loss stats
- [ ] Check Python memory: Task Manager → Python process < 300 MB
- [ ] Review `logs/health.log` for warnings
- [ ] Record daily P&L in personal trade log
- [ ] No need to shut down (system runs continuously)

---

### Weekly Maintenance (Saturday recommended)

- [ ] **Restart Brain** (clear memory, reload parameters):
  ```cmd
  start_flashea.bat stop
  start_flashea.bat
  ```
- [ ] Review performance: win rate, drawdown, Sharpe ratio
- [ ] **Backup folder:**
  ```cmd
  xcopy FlashEASuite_V2 Backup_%date%\ /E /I
  ```
- [ ] Check disk space: `02_Brain/logs/` folder (limit to 2 GB)
- [ ] Update MT5 if update available
- [ ] Review `02_Brain/data/metrics/performance_metrics.json`

---

### Monthly Review

- [ ] Analyze each strategy's performance individually
- [ ] Compare Spike Score levels vs actual trade outcomes
- [ ] Review and update RiskGuardian parameters if needed
- [ ] Check InfluxDB disk usage (if enabled)
- [ ] Run full Python regression tests:
  ```cmd
  python 02_Brain\tests\test_p9_1_python.py
  ```
- [ ] Consider parameter optimization for underperforming strategies

---

### Trading Session Times (GMT+7 Bangkok)

| Session | Time (Thai) | Active Pairs | Characteristics |
|---------|-------------|-------------|-----------------|
| Sydney | 04:00–13:00 | AUD, NZD | Low volatility, thin liquidity |
| Tokyo | 06:00–15:00 | JPY pairs | Moderate, JPY-specific moves |
| London | 14:00–23:00 | EUR, GBP | High volatility, institutional flow |
| New York | 19:00–04:00 | USD pairs | High volatility, FOMC impact |
| **London+NY Overlap** | **19:00–23:00** | **All major pairs** | **Best: highest liquidity, lowest spread** |

> 💡 **Recommended:** Increase lot size during London+NY overlap (19:00–23:00). Consider reduced position during Sydney and early Tokyo.

---

### Do's and Don'ts

**✅ DO:**
- Start with Demo account for at least 1 week
- Use minimum lot (0.01) until confident
- Keep Health Monitor running at all times
- Set Daily Loss Limit in RiskGuardian (default 2%)
- Keep a personal trade journal every day
- Back up the folder weekly

**❌ DON'T:**
- Start Live trading without passing Demo first
- Increase lot size without reviewing performance data
- Modify code while system is running (remove EA first)
- Stop Brain while open positions exist
- Ignore Health Monitor warnings
- Run optimization passes without verifying S16 memory first

---

## 6. Configuration Reference

### Strategy Quick Reference

| Strategy | Index | Standalone | Best For |
|----------|-------|------------|---------|
| S01_STAT_ARB | 0 | ✅ | Ranging — Pairs correlation |
| S02_ML_ENSEMBLE | 1 | ❌ | All regimes — AI prediction |
| S03_SMC | 2 | ❌ | Trending — Order blocks |
| S04_MARKET_PROFILE | 3 | ❌ | Ranging — Value area |
| S05_SUPPLY_DEMAND | 4 | ❌ | Ranging — Zone trading |
| S06_KAMA | 5 | ✅ | Trending — Adaptive MA |
| S07_MEAN_REVERSION | 6 | ✅ | Ranging — RSI+BB fade |
| S08_INTERMARKET | 7 | ❌ | Trending — DXY correlation |
| S09_SESSION_BREAKOUT | 8 | ❌ | Volatile — London/NY open |
| S10_TURTLE | 9 | ✅ | Trending — Donchian breakout |
| S11_ICHIMOKU | 10 | ❌ | Trending — Multi-TF cloud |
| S12_PRICE_ACTION | 11 | ❌ | Trending — Pin bar/Engulf |
| S13_FIB_STOCH | 12 | ❌ | Ranging — Fib+Stochastic |
| S14_BB_SQUEEZE | 13 | ✅ | Squeeze — Volatility breakout |
| S15_GRID | 14 | ✅ | Ranging — Elastic grid |
| S16_SPIKE | 15 | ✅ | Volatile — Spike fade |

### Key Config Files

| File | Role |
|------|------|
| `02_Brain/config.py` | Brain parameters (risk limits, thresholds) |
| `Include/Logic/StrategyConstants.mqh` | Strategy enums + magic numbers |
| `Include/Network/Protocol/Definitions.mqh` | SDynamicParams, ENUM_MARKET_REGIME |
| `Include/Risk/RiskGuardian.mqh` | Daily loss + max drawdown settings |
| `02_Brain/core/strategy/policy.py` | Policy selection logic |

### RiskGuardian Critical Settings

```cpp
// Include/Risk/RiskGuardian.mqh
double DD_DAILY_LIMIT_PCT = 2.0;    // Stop trading if daily loss > 2%
double MAX_DRAWDOWN_PCT   = 20.0;   // Emergency halt if DD > 20%
int    MAX_OPEN_TRADES    = 10;     // Max simultaneous positions
double MAX_LOT_PER_SYMBOL = 1.0;    // Max lot on any one symbol
```

---

## 7. Emergency Procedures

### Scenario A: Drawdown Exceeds 10%

```
1. MT5 → AutoTrading OFF (red) ← immediately
2. Review all open positions
3. Decide: Close all or hold?
4. Investigate root cause
5. Reduce lot size before resuming
6. Resume with minimum lot
```

### Scenario B: Python Brain Crash Overnight

```
Health Monitor auto-restarts (max 3 attempts)
If auto-restart fails:
  start_flashea.bat stop
  start_flashea.bat
Trader automatically switches to Standalone Mode
Check logs\health.log for crash reason
```

### Scenario C: MT5 Crash

```
1. Restart MT5
2. MT5 auto-reattaches EAs (saved state)
3. Verify: Experts tab shows FeederEA + Trader active
4. If not auto-attached: redo Steps 3+4 from Startup
```

### Scenario D: News Spike / Flash Crash

```
1. MT5 → AutoTrading OFF immediately
2. Wait for spread to normalize (< 2× normal)
3. Close heavily underwater positions if necessary
4. Re-enable AutoTrading after spike ends (usually < 5 min)
Note: S16_Spike has auto-spread check but manual override is safer
```

### Scenario E: Port Already in Use

```cmd
netstat -ano | find "7778"
→ Find PID in last column
taskkill /pid <PID> /f
start_flashea.bat
```

---

## 8. Quick Reference Card

```
╔══════════════════════════════════════════════════════════════╗
║         FlashEASuite V2 Quick Reference — P9-5               ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  STARTUP (in order):                                         ║
║   1. Open MT5 → Login → AutoTrading = GREEN                  ║
║   2. start_flashea.bat              ← Python Brain           ║
║   3. Attach FeederEA to Chart 1    ← Port 7777 PUB          ║
║   4. Attach ProgramC_Trader Chart 2 ← Port 7778 SUB         ║
║   5. python tools\health_monitor.py ← optional monitor      ║
║                                                              ║
║  CONTROL COMMANDS:                                           ║
║   start_flashea.bat           ← Start Brain                  ║
║   start_flashea.bat status    ← Check all services          ║
║   start_flashea.bat stop      ← Stop Brain                  ║
║   start_flashea.bat doctor    ← Diagnose issues             ║
║   validate_live_readiness.py  ← Full pre-live check         ║
║                                                              ║
║  ZMQ PORTS:                                                  ║
║   7777 = FeederEA → Brain  (tick data)                      ║
║   7778 = Brain → Trader    (CONFIG_PUSH)                    ║
║   7779 = Trader → Brain    (TRADE_REPORT feedback)          ║
║                                                              ║
║  EMERGENCY LEVELS:                                           ║
║   L1: AutoTrading OFF (red button)         ← 5 sec          ║
║   L2: Remove EAs from charts               ← 30 sec         ║
║   L3: start_flashea.bat stop + close MT5  ← 1 min          ║
║   L4: taskkill /im python.exe /f           ← instant        ║
║                                                              ║
║  LOG FILES:                                                  ║
║   02_Brain\logs\flashea_brain.log   ← Python errors         ║
║   02_Brain\logs\trades_YYYYMMDD.json ← Trade journal        ║
║   logs\health.log                   ← Health monitor        ║
║   MT5 → Experts tab                 ← EA messages           ║
║                                                              ║
║  NORMAL METRICS:                                             ║
║   Memory  < 300 MB  │  CPU  < 15%                           ║
║   Ticks   increasing │  Policies  0-50/hr                   ║
║   Drawdown  < 10%   │  Win rate  45-65%                     ║
╚══════════════════════════════════════════════════════════════╝
```

---

*FlashEASuite V2 Operation Manual — V6 P9-5 Production | 2026-03-01*
