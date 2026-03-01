# FlashEASuite V2 — Troubleshooting Guide

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01

---

## Quick Diagnosis Command

Always run this first when something seems wrong:

```cmd
cd FlashEASuite_V2
start_flashea.bat doctor
```

Then run:
```cmd
python tools\validate_live_readiness.py
```

Both commands produce actionable fix instructions for each failure.

---

## Problem Index

| # | Problem | Section |
|---|---------|---------|
| 1 | Python Brain won't start | [→ Section 1](#1-python-brain-wont-start) |
| 2 | Brain crashes after starting | [→ Section 2](#2-brain-crashes-after-starting) |
| 3 | FeederEA not broadcasting ticks | [→ Section 3](#3-feederea-not-broadcasting-ticks) |
| 4 | Trader not receiving policies | [→ Section 4](#4-trader-not-receiving-policies) |
| 5 | No trades being opened | [→ Section 5](#5-no-trades-being-opened) |
| 6 | Port already in use | [→ Section 6](#6-port-already-in-use) |
| 7 | Compile errors in MetaEditor | [→ Section 7](#7-compile-errors-in-metaeditor) |
| 8 | DLL not found error | [→ Section 8](#8-dll-not-found-error) |
| 9 | High memory usage / memory leak | [→ Section 9](#9-high-memory-usage--memory-leak) |
| 10 | High CPU usage | [→ Section 10](#10-high-cpu-usage) |
| 11 | Symbol not found / wrong suffix | [→ Section 11](#11-symbol-not-found--wrong-suffix) |
| 12 | Standalone Mode not activating | [→ Section 12](#12-standalone-mode-not-activating) |
| 13 | InfluxDB not working | [→ Section 13](#13-influxdb-not-working) |
| 14 | Validation failures | [→ Section 14](#14-validation-failures) |
| 15 | Trade results not feeding back | [→ Section 15](#15-trade-results-not-feeding-back) |
| 16 | MT5 EA icon shows sad face | [→ Section 16](#16-mt5-ea-icon-shows-sad-face) |
| 17 | Wrong lot size being used | [→ Section 17](#17-wrong-lot-size-being-used) |
| 18 | RiskGuardian blocking trades | [→ Section 18](#18-riskguardian-blocking-trades) |

---

## 1. Python Brain Won't Start

**Symptoms:** `start_flashea.bat` immediately closes, or shows error and exits

### Diagnosis

```cmd
cd FlashEASuite_V2
python 02_Brain\main.py
```

Check the error output.

### Common Causes and Fixes

| Error Message | Cause | Fix |
|--------------|-------|-----|
| `ModuleNotFoundError: zmq` | pyzmq not installed | `pip install pyzmq` |
| `ModuleNotFoundError: msgpack` | msgpack not installed | `pip install msgpack` |
| `ModuleNotFoundError: numpy` | numpy not installed | `pip install numpy pandas` |
| `Python was not found` | Python not in PATH | Reinstall Python with "Add to PATH" checked |
| `Address already in use` | Port 7778 occupied | See Section 6 |
| `SyntaxError` | Python version < 3.8 | `python --version` → upgrade if < 3.8 |
| `ImportError: config` | Wrong working directory | `cd FlashEASuite_V2` first |

### Full dependency install

```cmd
pip install pyzmq msgpack numpy pandas scikit-learn
```

### Verify Python and path

```cmd
python --version          ← must be 3.8+
python -c "import zmq"   ← must return no error
where python              ← check PATH
```

---

## 2. Brain Crashes After Starting

**Symptoms:** Brain starts (shows 3 workers) then crashes minutes/hours later

### Diagnosis

```cmd
type 02_Brain\logs\flashea_brain.log | findstr /i "error critical"
```

### Common Causes

| Cause | Symptom in log | Fix |
|-------|---------------|-----|
| Unhandled exception in strategy analyzer | `ERROR: Exception in S02` | Update strategy analyzer code |
| Memory exhaustion | `CRITICAL: MemoryError` | Reduce symbols in FeederEA, restart Brain |
| ZMQ socket error | `ERROR: zmq.ZMQError` | Check port availability, restart |
| Config import error | `ERROR: config.py missing key` | Check config.py for required keys |

### Recovery

```cmd
:: Check what killed it
type logs\health.log | findstr "WARNING ERROR"

:: Restart
start_flashea.bat stop
start_flashea.bat
```

Health monitor auto-restarts Brain (max 3 attempts). If it keeps crashing, investigate the log before restarting again.

---

## 3. FeederEA Not Broadcasting Ticks

**Symptoms:** Brain console shows `Ticks Processed: 0` (not increasing)

### Check List

```
1. Is FeederEA actually attached to a chart?
   → Look for EA icon in chart top-right corner

2. Is the icon a smiley face (yellow) or sad face (grey)?
   → Smiley = running, Sad = disabled

3. Does MT5 Experts tab show FeederEA messages?
   → If no messages: EA is not running

4. Is AutoTrading button GREEN?
   → Red = all EAs disabled, including FeederEA
```

### Fixes

| Problem | Fix |
|---------|-----|
| EA not attached | Drag FeederEA from Navigator onto chart |
| Sad face icon | Click AutoTrading button to make it green |
| No Experts tab output | Check Tools → Options → Allow DLL imports |
| "DLL not found" in Experts | See Section 8 |
| Compile error | Recompile from MetaEditor Navigator (not Explorer) |
| "Timer not started" | EA timed out, remove and re-attach |
| No symbols broadcasting | Right-click Market Watch → add symbols |

---

## 4. Trader Not Receiving Policies

**Symptoms:** MT5 Experts tab shows "Waiting for Brain policy..." continuously

### Diagnosis

```cmd
:: Check Brain is sending
python 02_Brain\debug_policy_format.py

:: Check port 7778
netstat -an | find "7778"
```

### Check List

```
1. Is Brain running?
   start_flashea.bat status → [RUNNING]?

2. Does Brain console show "CONFIG_PUSH sent"?
   → If not: check FeederEA is sending ticks to Brain first

3. Is port 7778 listening?
   netstat -an | find "7778"
   → Must show: 0.0.0.0:7778  LISTENING

4. Is Trader connected to correct address?
   EA Input: InpZmqSubAddress = tcp://127.0.0.1:7778
   → Must match Brain's published address

5. Is SYMBOL_SUFFIX correct?
   Trader input SYMBOL_SUFFIX must match broker symbols
   → E.g., ".tp" if symbols are "EURUSD.tp"

6. V6_EnableMode = false?
   → If true, may use different communication path
```

### Fixes

| Problem | Fix |
|---------|-----|
| Brain not running | `start_flashea.bat` |
| Port 7778 not listening | Restart Brain |
| Wrong address | Verify `InpZmqSubAddress` in Trader inputs |
| Wrong SYMBOL_SUFFIX | Check Market Watch symbol names, update input |
| No ticks to Brain | Fix FeederEA first (Section 3) |

---

## 5. No Trades Being Opened

**Symptoms:** System running, receiving policies, but no trades opened

### Diagnosis

Check MT5 Experts tab for clues:
```
[RiskGuardian] Daily limit reached    ← hit daily loss limit
[Strategy] Confidence below threshold ← no strategy above 0.50
[Strategy] Spread too high: 5.2 pips  ← spread filter blocking
[Grid] Waiting for CSM data           ← Grid needs direction
[Spike] Score below threshold: 45.3   ← Spike not triggered
```

### Check List

```
1. Is confidence threshold being met?
   Brain sends policies only when confidence ≥ 0.50

2. Is spread too high?
   During news events, spread can be 10× normal
   SpreadFilter.mqh blocks entry if spread > threshold

3. Has daily loss limit been hit?
   RiskGuardian.mqh: DD_DAILY_LIMIT_PCT = 2.0%
   Check balance vs start-of-day balance

4. Is trading session active?
   S09_SessionBreakout only trades at specific times
   Other strategies respect max_trades per session

5. Is Regime matching strategy?
   S07 only trades in RANGING
   S10 only trades in TRENDING
   If wrong regime → strategy skips entry

6. AutoTrading enabled?
   MT5 toolbar → AutoTrading button must be GREEN
```

---

## 6. Port Already in Use

**Symptoms:** Brain fails with `Address already in use` or `OSError: [Errno 98]`

### Identify what's using the port

```cmd
netstat -ano | find "7778"
```

Output example:
```
TCP    0.0.0.0:7778    0.0.0.0:0    LISTENING    12345
                                                   ^^^^ PID
```

### Kill the conflicting process

```cmd
taskkill /pid 12345 /f
```

### If it's an old Brain instance

```cmd
start_flashea.bat stop
:: Wait 3 seconds
start_flashea.bat
```

### Check all 3 ports at once

```cmd
netstat -ano | find "777"
```

Port 7779 should be FREE (Trader uses CONNECT, not BIND — only Brain BINDs 7777 and 7778).

---

## 7. Compile Errors in MetaEditor

**Symptoms:** Pressing F7 shows errors in the Errors tab

### Critical Rules

> ❌ **NEVER** compile by opening `.mq5` files from Windows Explorer
> ✅ **ALWAYS** open from MetaEditor Navigator panel → F7 compile

Opening from Explorer causes wrong `#include` path resolution.

### Common Compile Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `'xxx' - identifier undefined` | Misspelled variable or missing include | Check spelling + includes |
| `'#include' - file not found` | Wrong include path | Open file from Navigator, verify tree |
| `'#if' - bad expression` | Compound `#if` condition | Change to `#ifdef` / `#ifndef` |
| `'function' - wrong parameters count` | Interface mismatch | Check IStrategy/IMoneyManager interface |
| `array out of range` | Array index error | Check array bounds in code |
| `'class' - declaration without body` | Missing closing brace | Check brace matching |

### Lesson: #if vs #ifdef

```cpp
// WRONG (compound conditions cause issues in MQL5):
#if defined(STRATEGY_GRID) && USE_BRAIN_MODE

// CORRECT:
#ifdef STRATEGY_GRID
  #ifdef USE_BRAIN_MODE
    // code here
  #endif
#endif
```

### Check include path

```
MQL5 include paths that must exist:
  Include/Logic/IStrategy.mqh                ← IStrategy interface
  Include/Logic/StrategyConstants.mqh        ← enums
  Include/Network/Protocol/Definitions.mqh  ← message types
  Include/Risk/RiskGuardian.mqh             ← risk management
  Include/Security/DLLWrapper.mqh           ← ZMQ DLL
```

---

## 8. DLL Not Found Error

**Symptoms:** MT5 Experts tab shows `libzmq.dll not found` or similar

### Verify DLL location

DLLs must be in:
```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Libraries\
```

Required files:
- `libzmq.dll`
- `libsodium.dll`

### Fix

```cmd
:: Find your MQL5 data folder
:: In MT5: File → Open Data Folder → navigate to MQL5\Libraries\
:: Copy DLL files there

copy libzmq.dll "C:\Users\<YOU>\AppData\...\MQL5\Libraries\"
copy libsodium.dll "C:\Users\<YOU>\AppData\...\MQL5\Libraries\"
```

### Verify DLL imports allowed

MT5 → Tools → Options → Expert Advisors:
- [✅] Allow DLL imports

Also in EA Common tab (per-EA setting):
- [✅] Allow DLL imports

---

## 9. High Memory Usage / Memory Leak

**Symptoms:** Python process memory > 400 MB (growing over time)

### Check current memory

```cmd
:: Task Manager → Details tab → python.exe → Memory column
:: Or in PowerShell:
Get-Process python | Select-Object ProcessName, @{N='Mem(MB)';E={[int]($_.WorkingSet / 1MB)}}
```

### Common Causes

| Cause | Symptom | Fix |
|-------|---------|-----|
| Long runtime (12h+) | Gradual increase | Weekly Brain restart |
| tick_buffer unbounded | Fast increase with many symbols | Reduce symbols in FeederEA |
| InfluxDB write backlog | Memory grows when InfluxDB offline | Disable InfluxDB or start it |
| Large explainable/ logs | Disk fills → memory pressure | Delete old logs from explainable/ |

### Fix (restart Brain)

```cmd
start_flashea.bat stop
:: Wait 5 seconds
start_flashea.bat
```

### MQL5 Memory Leak (S16 Spike)

**Known issue (P9-4b fixed):** S16_Spike.mqh had 11,520 bytes leak per backtest run.
- Live trading: Fixed in `Strategy_Spike.mqh v2.02`
- Backtest optimization: Avoid running many iterations with S16 (see Section 17 above)
- If MT5 runs slowly after S16 tests: restart MT5

---

## 10. High CPU Usage

**Symptoms:** Python CPU > 25% consistently

### Diagnosis

```cmd
:: See which thread is hot:
python 02_Brain\debug_policy_format.py --profile
```

### Common Causes

| Cause | Fix |
|-------|-----|
| Too many symbols (28+) | Reduce active symbols in FeederEA |
| S02 ML inference too slow | ML model optimization needed |
| Feature engineering loop | Normal if < 340ms per tick; otherwise optimize |
| Infinite retry loop | Check logs for repeating errors |
| InfluxDB write timeout | Fix or disable InfluxDB |

### Normal CPU Baseline

```
5–10%: Normal operation
10–15%: Acceptable during high tick-rate periods
15–25%: Monitor — may need optimization
>25%: Investigate immediately
```

---

## 11. Symbol Not Found / Wrong Suffix

**Symptoms:** `SYMBOL_SUFFIX mismatch`, no ticks for certain symbols

### Check broker suffix

```
1. Open MT5 → Market Watch
2. Find the symbol you want to trade
3. Note exact name: EURUSD, EURUSD.tp, EURUSD_m, etc.
```

### Fix Trader input

```
In ProgramC_Trader Inputs:
  SYMBOL_PREFIX = (empty usually)
  SYMBOL_SUFFIX = .tp    ← match exactly what you see in Market Watch
```

### Fix FeederEA

FeederEA reads from Market Watch automatically. Add missing symbols:
```
MT5 → Market Watch → Right-click → Symbols
→ Search and add: EURUSD.tp, GBPUSD.tp, etc.
```

---

## 12. Standalone Mode Not Activating

**Symptoms:** Brain offline but Trader not switching to Standalone Mode

### How Standalone triggers

```
ProgramC_Trader detects no CONFIG_PUSH for X seconds
→ Calls CStandaloneSelector.Activate()
→ Loads standalone_config.dat (last saved config)
→ Uses simplified DetectRegime() per tick
→ Enables: S01, S06, S07, S10, S14, S15, S16
→ Risk × 0.5
```

### Troubleshooting

| Check | Fix |
|-------|-----|
| `standalone_config.dat` exists? | Check `02_Brain/data/` folder |
| Was Brain ever connected? | Need at least 1 successful CONFIG_PUSH to save .dat |
| V6_EnableMode = false? | Check Trader inputs |
| Timeout threshold met? | Default is 30 seconds — wait a bit longer |

---

## 13. InfluxDB Not Working

**Symptoms:** `⚠️ WARN InfluxDB` in validation, no historical data

> ℹ️ **InfluxDB is OPTIONAL.** System trades normally without it.

### Check InfluxDB status

```
Open browser: http://localhost:8086
```

If page loads → running. If not → InfluxDB is down.

### Start InfluxDB

```cmd
:: Windows service:
net start influxdb

:: Or start manually:
influxd.exe

:: Docker:
docker start influxdb
```

### Verify from Python

```cmd
python tools\validate_live_readiness.py --influx
```

### Disable InfluxDB logging (if not needed)

In `02_Brain/config.py`:
```python
INFLUXDB_ENABLED = False
```

---

## 14. Validation Failures

**Symptoms:** `validate_live_readiness.py` shows ❌ FAIL

Each FAIL includes instructions. But here are common ones:

| FAIL message | Cause | Fix |
|-------------|-------|-----|
| `Imports FAIL` | Python module not importable | `pip install` missing module |
| `Files FAIL: main.py` | Not in FlashEASuite_V2 directory | `cd FlashEASuite_V2` |
| `Ports FAIL: 7778 in use` | Old process using port | Kill old process (Section 6) |
| `ZMQ FAIL: bind error` | Port unavailable or permission | Run as normal user; check firewalls |
| `Config FAIL: missing key` | config.py incomplete | Check config.py against config template |
| `Receive FAIL: build_config_push` | config_builder.py path issue | Verify `core/config_push/` folder exists |

---

## 15. Trade Results Not Feeding Back

**Symptoms:** Brain shows `Feedback Trades: 0` after positions close

### Check Trader push

MT5 Experts tab should show:
```
[Trader] TRADE_REPORT sent: ticket=12345 pnl=+15.50
```

### Check Brain receiver

Brain console should show:
```
✅ FEEDBACK: WIN | ticket=12345 | PnL=+15.50
```

### Troubleshooting

| Check | Fix |
|-------|-----|
| Port 7779 check | Trader connects to brain's PULL on 7779 |
| Trader push address | `InpZmqPushAddress = tcp://127.0.0.1:7779` |
| Brain execution listener | Must show `✅ Execution Listener started` |
| Trade was closed by Trader? | Trades closed manually (by user) don't trigger TRADE_REPORT |

---

## 16. MT5 EA Icon Shows Sad Face

**Symptoms:** EA icon in chart top-right is grey/sad face

### Causes and Fixes

| Cause | Fix |
|-------|-----|
| AutoTrading disabled | Click AutoTrading button → make green |
| DLL imports disabled | Tools → Options → Expert Advisors → Allow DLL imports |
| Account algo trading blocked | Contact broker to enable algorithmic trading |
| EA has unhandled runtime error | Check Experts tab for error message |
| EA was manually disabled | Right-click chart → Expert Advisors → Enable |

---

## 17. Wrong Lot Size Being Used

**Symptoms:** Lots opened are different from expected

### Lot size hierarchy (all apply simultaneously)

```
1. Brain risk_multiplier (from CONFIG_PUSH)
2. MM method calculation (CalculateLot)
3. RiskGuardian MAX_LOT_PER_SYMBOL cap
4. Broker min/max lot constraints
Final lot = Min(MM_lot × risk_mult, max_lot_cap, broker_max)
```

### Check which MM is active

```
Brain console → Dashboard → shows "MM Method: MM03_ATR"
Or check 02_Brain/config.py → DEFAULT_MM_METHOD
```

### Common lot issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Lot always 0.01 | MM01 active (fixed conservative) | Change MM method |
| Lot too large | High risk_mult + high confidence | Lower risk_pct in config.py |
| Lot growing unexpectedly | MM05 Martingale active | Check MM selection |
| Lot below minimum | MM calculation result < broker min | Brain auto-adjusts to broker min |

---

## 18. RiskGuardian Blocking Trades

**Symptoms:** `[RiskGuardian] Daily limit reached — no new trades`

### What triggers RiskGuardian

```cpp
// Include/Risk/RiskGuardian.mqh
DD_DAILY_LIMIT_PCT  = 2.0   // 2% daily loss → stops all trading
MAX_DRAWDOWN_PCT    = 20.0  // 20% total DD → emergency halt
MAX_OPEN_TRADES     = 10    // 10 concurrent positions → no new opens
MAX_LOT_PER_SYMBOL  = 1.0   // 1.0 lot on any symbol → skip order
```

### Fixes

| Blocked by | Fix |
|-----------|-----|
| Daily loss limit (2%) | Wait for next trading day (resets at midnight) |
| Max drawdown (20%) | Emergency — review strategy before resuming |
| Max open trades | Close some positions, or increase `MAX_OPEN_TRADES` |
| Max lot per symbol | Reduce MM lot size |

### Adjust limits (if appropriate)

In `Include/Risk/RiskGuardian.mqh`, modify and recompile:
```cpp
double DD_DAILY_LIMIT_PCT = 3.0;   // Changed from 2.0 to 3.0
```

> ⚠️ Only increase limits after careful consideration — they exist to protect capital.

---

## Diagnostic Commands Summary

```cmd
:: Full diagnosis
start_flashea.bat doctor
python tools\validate_live_readiness.py

:: Brain status
start_flashea.bat status

:: Check ports
netstat -ano | find "777"

:: Kill conflicting process
taskkill /pid <PID> /f

:: Check Python memory
Get-Process python | Select-Object Name, WorkingSet

:: Check recent errors
type 02_Brain\logs\flashea_brain.log | findstr "ERROR CRITICAL"

:: Check health log
type logs\health.log | findstr "WARNING ERROR"

:: Restart Brain
start_flashea.bat stop
start_flashea.bat
```

---

## Known Issues Reference

| Issue | Version Fixed | Notes |
|-------|--------------|-------|
| S16 memory leak in backtest | P9-4b (v2.02) | Live trading fixed; avoid batch optimization |
| Feature engineering latency 100–340ms | Not yet | Acceptable for current tick rate |
| Standalone uses simplified regime | By design | Expected behavior |
| InfluxDB optional | By design | System works without it |
| Windows cp874 encoding in dashboard | P9-5 (CF-5) | Fixed — use latest dashboard.py |
| validate_live_readiness path bugs | P9-5 (CF-1..CF-4) | Fixed in current version |

---

*FlashEASuite V2 Troubleshooting Guide — V6 P9-5 | 2026-03-01*
