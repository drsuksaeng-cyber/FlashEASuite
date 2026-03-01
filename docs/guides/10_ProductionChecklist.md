# FlashEASuite V2 — Production Ready Checklist

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01
> **Author:** Dr. Suksaeng Kukanok
> ⚠️ **ALL items must be PASS before going Live. No exceptions.**

---

## How to Use This Checklist

1. Work through sections 1–10 in order
2. Mark each item: `[✅]` PASS, `[❌]` FAIL (fix before continuing), `[⚠️]` WARN (optional)
3. Run automated validation: `python tools\validate_live_readiness.py`
4. Do not proceed to Live until all required items are `[✅]`
5. Keep a signed/dated copy of this checklist for accountability

---

## Automated Pre-Check (Run First)

```cmd
cd FlashEASuite_V2
python tools\validate_live_readiness.py
```

Expected summary:
```
  ✅ PASS  Imports
  ✅ PASS  Deps
  ✅ PASS  Files
  ✅ PASS  Ports
  ✅ PASS  ZMQ
  ✅ PASS  Config
  ✅ PASS  Receive
  ⚠️ WARN  InfluxDB    (optional — acceptable)

  🚀 SYSTEM READY FOR LIVE TRADING!
```

Zero `❌ FAIL` required before proceeding.

---

## Section 1 — Python Brain

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 1.1 | Brain starts without error | `start_flashea.bat` → no traceback in console | `[ ]` |
| 1.2 | Ingestion Worker started | Console: `✅ Ingestion Worker started` | `[ ]` |
| 1.3 | Strategy Engine started | Console: `✅ Strategy Engine started` | `[ ]` |
| 1.4 | Execution Listener started | Console: `✅ Execution Listener started` | `[ ]` |
| 1.5 | All 3 workers confirmed | Console: `🚀 All workers started successfully (3 threads)` | `[ ]` |
| 1.6 | Feedback loop enabled | Console: `🎯 System is running with FEEDBACK LOOP enabled!` | `[ ]` |
| 1.7 | Memory < 300 MB after 10 min | Task Manager → python.exe → Working Set | `[ ]` |
| 1.8 | CPU < 15% steady-state | Task Manager → python.exe → CPU column | `[ ]` |
| 1.9 | No Python errors in log | `type 02_Brain\logs\flashea_brain.log \| findstr "ERROR"` → empty | `[ ]` |
| 1.10 | Dashboard displays correctly | Console shows dashboard auto-refreshing every 5s | `[ ]` |

---

## Section 2 — FeederEA (Program A)

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 2.1 | FeederEA compiled 0 errors | MetaEditor → Compile → `0 error(s), 0 warning(s)` | `[ ]` |
| 2.2 | EA attaches to chart | Smiley face icon visible in chart top-right | `[ ]` |
| 2.3 | ZMQ PUB bound on port 7777 | Experts tab: `✅ ZMQ PUB bound to tcp://*:7777` | `[ ]` |
| 2.4 | Broadcasting confirmed | Experts tab: `✅ Broadcasting on X symbols` | `[ ]` |
| 2.5 | Brain receives ticks | Brain console: `Ticks Processed` count > 0 and increasing | `[ ]` |
| 2.6 | Symbol mapping correct | Dashboard: XAUUSD.tp → XAUUSD (or your suffix) | `[ ]` |
| 2.7 | All target symbols active | Market Watch has all required symbols | `[ ]` |
| 2.8 | Timer running at 50ms | Inputs: Timer = 50 (not default 0) | `[ ]` |

---

## Section 3 — ProgramC_Trader (Program C)

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 3.1 | Trader compiled 0 errors | MetaEditor → Compile → `0 error(s)` | `[ ]` |
| 3.2 | EA attaches to chart | Smiley face icon in chart top-right | `[ ]` |
| 3.3 | ZMQ Hub created | Experts tab: `✅ ZMQ Hub created` | `[ ]` |
| 3.4 | SUB connected on 7778 | Experts tab: `✅ Subscribed to tcp://127.0.0.1:7778` | `[ ]` |
| 3.5 | PUSH connected on 7779 | Experts tab: `✅ PUB Socket connected to tcp://127.0.0.1:7779` | `[ ]` |
| 3.6 | Grid Strategy registered | Experts tab: `✅ Grid Strategy added to Council` | `[ ]` |
| 3.7 | Spike Hunter registered | Experts tab: `✅ Spike Hunter Strategy added to Council` | `[ ]` |
| 3.8 | READY confirmation | Experts tab: `ProgramC_Trader V2.12 READY` | `[ ]` |
| 3.9 | SYMBOL_SUFFIX correct | Input SYMBOL_SUFFIX matches broker symbols exactly | `[ ]` |
| 3.10 | Allow DLL imports checked | EA Common tab: Allow DLL imports = ✅ | `[ ]` |
| 3.11 | Allow algo trading checked | EA Common tab: Allow algo trading = ✅ | `[ ]` |

---

## Section 4 — MT5 Global Settings

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 4.1 | Algorithmic trading enabled | Tools → Options → Expert Advisors → Allow algorithmic trading ✅ | `[ ]` |
| 4.2 | DLL imports allowed (global) | Tools → Options → Expert Advisors → Allow DLL imports ✅ | `[ ]` |
| 4.3 | AutoTrading button GREEN | MT5 toolbar → AutoTrading button = green | `[ ]` |
| 4.4 | Broker connection stable | Status bar shows market price + data flow (not "No connection") | `[ ]` |
| 4.5 | Correct trading account | Account number visible in MT5 top-left — verify it's correct | `[ ]` |

---

## Section 5 — Data Flow Verification

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 5.1 | Feeder → Brain tick flow | Brain Ticks Processed > 0 and increasing after 60 seconds | `[ ]` |
| 5.2 | Brain → Trader policy flow | Brain: `Policies Sent` > 0, Trader: `Policy Update received` | `[ ]` |
| 5.3 | Regime detected | Brain Dashboard shows regime: TRENDING / RANGING / etc. | `[ ]` |
| 5.4 | Strategy selected | Brain Dashboard shows Active Strategies (at least 1) | `[ ]` |
| 5.5 | CONFIG_PUSH timing | `Last Config Push` in dashboard < 30 seconds ago | `[ ]` |
| 5.6 | No data flow interruption | Tick count continuously increasing over 5-minute period | `[ ]` |

---

## Section 6 — Trade Execution

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 6.1 | Trade can be executed | Place 1 manual test trade in MT5 → executes successfully | `[ ]` |
| 6.2 | Lot size correct | Check opened position Volume = expected lot | `[ ]` |
| 6.3 | SL/TP set correctly | Position shows SL and TP (or EA manages them internally) | `[ ]` |
| 6.4 | Magic number correct | Position magic number = 999000 (or strategy-specific 100X) | `[ ]` |
| 6.5 | Account free margin sufficient | Trade tab: Free Margin > 50% of balance | `[ ]` |
| 6.6 | No rejected orders | No `Order rejected` messages in Experts tab | `[ ]` |
| 6.7 | Spread within limits | Market Watch → XAUUSD spread < 5 pips (normal market hours) | `[ ]` |

---

## Section 7 — Feedback Loop (TRADE_REPORT)

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 7.1 | Trade closes → TRADE_REPORT sent | Experts tab: `[Trader] TRADE_REPORT sent: ticket=XXXXX` | `[ ]` |
| 7.2 | Brain receives feedback | Brain console: `✅ FEEDBACK: WIN/LOSS \| ticket=XXXXX` | `[ ]` |
| 7.3 | Performance tracker updates | `performance_metrics.json` updated after trade close | `[ ]` |
| 7.4 | Win rate updates | Brain console shows updated W/L count after trade | `[ ]` |
| 7.5 | Port 7779 working | `netstat -an \| find "7779"` shows connection | `[ ]` |

---

## Section 8 — Risk Management

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 8.1 | RiskGuardian compiled with correct limits | `DD_DAILY_LIMIT_PCT = 2.0`, `MAX_DRAWDOWN_PCT = 20.0` | `[ ]` |
| 8.2 | Daily loss limit functional | Verified in backtest/demo: trading stops after 2% loss | `[ ]` |
| 8.3 | Max drawdown configured | config.py: `MAX_DRAWDOWN_PCT = 20` | `[ ]` |
| 8.4 | Emergency stop tested | Level 1: AutoTrading OFF → no new trades (tested on Demo) | `[ ]` |
| 8.5 | Max lot per symbol set | `MAX_LOT_PER_SYMBOL = 1.0` (or your limit) | `[ ]` |
| 8.6 | Initial lot size conservative | First day: using 0.01 lot (minimum) | `[ ]` |

---

## Section 9 — Standalone Mode

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 9.1 | Standalone mode works | Stop Brain → Trader logs `Switched to Standalone Mode` | `[ ]` |
| 9.2 | Fallback config exists | `02_Brain/data/standalone_config.dat` exists | `[ ]` |
| 9.3 | Standalone strategies work | With Brain off: S07/S15/S16 still analyze and signal | `[ ]` |
| 9.4 | Risk reduction in standalone | Standalone mode uses 0.5× risk multiplier | `[ ]` |
| 9.5 | Brain reconnection works | Restart Brain → Trader returns to Online Mode | `[ ]` |

---

## Section 10 — Monitoring & Health

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 10.1 | Health monitor runs | `python tools\health_monitor.py --once` → all GREEN | `[ ]` |
| 10.2 | Health log file created | `logs\health.log` exists and has recent entries | `[ ]` |
| 10.3 | start_flashea.bat status works | `start_flashea.bat status` → all [RUNNING] | `[ ]` |
| 10.4 | start_flashea.bat doctor passes | `start_flashea.bat doctor` → no FAIL | `[ ]` |
| 10.5 | Auto-restart tested | Kill Brain manually → health monitor restarts it | `[ ]` |
| 10.6 | Dashboard updates correctly | Dashboard shows correct regime + strategies + ticks | `[ ]` |
| 10.7 | Explainable AI logging | `02_Brain\explainable\` folder has recent JSON files | `[ ]` |
| 10.8 | Trade journal created | `02_Brain\logs\trades_YYYYMMDD.json` created after first trade | `[ ]` |

---

## Section 11 — Backtest Validation (Demo First)

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 11.1 | Backtest completed for each active strategy | MT5 Strategy Tester → Profit Factor > 2.0 | `[ ]` |
| 11.2 | Backtest max DD < 15% | Report tab: Max Drawdown < 15% | `[ ]` |
| 11.3 | At least 100 trades in backtest | Report tab: Total Trades > 100 | `[ ]` |
| 11.4 | Demo trading completed 1+ weeks | Minimum 1 week on Demo account | `[ ]` |
| 11.5 | Demo results comparable to backtest | Win rate within ±10% of backtest result | `[ ]` |
| 11.6 | No anomalous behavior in Demo | No unexpected spikes, runaway positions, or errors | `[ ]` |

---

## Section 12 — Final Pre-Live Checks

| # | Item | How to Verify | Status |
|---|------|--------------|--------|
| 12.1 | validate_live_readiness.py → 0 FAIL | Run script: no ❌ FAIL | `[ ]` |
| 12.2 | All previous sections complete | Sections 1–11 all items checked | `[ ]` |
| 12.3 | Live account funded correctly | Account balance = planned starting capital | `[ ]` |
| 12.4 | Drawdown tolerance set | Decided maximum acceptable drawdown % before stopping | `[ ]` |
| 12.5 | Emergency procedures practiced | Levels 1–4 tested on Demo | `[ ]` |
| 12.6 | Backup taken | Full FlashEASuite_V2 folder backup before going live | `[ ]` |
| 12.7 | Start time planned | Plan to start during high-liquidity session (London or NY) | `[ ]` |
| 12.8 | Monitoring plan in place | Health monitor running, health.log being reviewed | `[ ]` |
| 12.9 | First week plan: 0.01 lot only | Committed to minimum lot for first week | `[ ]` |
| 12.10 | Daily loss limit agreed | Personal stop: if daily loss > X%, stop for the day | `[ ]` |

---

## Known Issues Register (As of P9-5)

| # | Issue | Severity | Status | Impact on Live |
|---|-------|---------|--------|----------------|
| 1 | S16 memory leak in backtest optimization | ⚠️ CRITICAL for optimization | ✅ Fixed in P9-4b (v2.02) | None for live trading |
| 2 | Feature engineering latency 100–340ms | ℹ️ Medium | Not optimized yet | Acceptable for current tick rate |
| 3 | InfluxDB optional | ℹ️ Low | By design | No impact (system works without) |
| 4 | Standalone uses simplified regime | ℹ️ Low | By design | Expected, reduced performance |
| 5 | Windows cp874 encoding (dashboard) | ℹ️ Low | ✅ Fixed in P9-5 (CF-5) | None |

---

## Pre-Live Timeline

| Time | Action | Tool |
|------|--------|------|
| T-2 days | Complete sections 1–11 | Checklist + Demo testing |
| T-1 day | Final full validation | `validate_live_readiness.py` |
| T-1 day | Take backup | `xcopy FlashEASuite_V2 Backup_LIVE_START\ /E /I` |
| T-30 min | Re-run validation | `validate_live_readiness.py` |
| T-20 min | Start Brain | `start_flashea.bat` |
| T-15 min | Attach FeederEA | MT5 Navigator |
| T-10 min | Attach Trader | MT5 Navigator |
| T-5 min | Verify all systems | Dashboard + status |
| T-2 min | Quick check | `start_flashea.bat status` |
| T-1 min | Start health monitor | `python tools\health_monitor.py` |
| **T-0** | **🚀 GO LIVE** | **Enable AutoTrading** |

---

## Production Rules (Commit to These)

By going live, you commit to following these rules:

```
[ ] I will use 0.01 lot only for the first week
[ ] I will not override RiskGuardian limits without review
[ ] I will check Brain console every morning before trading
[ ] I will run health monitor every trading day
[ ] I will back up the folder every Saturday
[ ] I will restart Brain every Saturday (weekly maintenance)
[ ] I will stop trading if daily loss exceeds my personal limit
[ ] I will not modify code while system is running
[ ] I will investigate any unexpected position before closing
[ ] I will keep a personal trade journal (date, positions, P&L, notes)
```

---

## Validation Test Results

Record your test results here before going live:

```
Date of final validation: _______________
validate_live_readiness.py result: _____ PASS / _____ FAIL / _____ WARN

Demo account test period: _____________ to _____________
Demo win rate:            ______%
Demo profit factor:       ______
Demo max drawdown:        ______%
Demo total trades:        ______

Backtest result (1 year):
  Strategy tested:        _______________
  Symbol:                 _______________
  Win rate:               ______%
  Profit factor:          ______
  Max drawdown:           ______%

Live account details:
  Broker:                 _______________
  Account type:           Demo / Live
  Account balance:        $_______________
  Symbol suffix:          _______________
  Starting lot size:      _______________

Signed: ___________________________  Date: _______________
```

---

## Post-Go-Live Monitoring Schedule

| Period | Action |
|--------|--------|
| First hour | Watch every trade. Monitor experts tab continuously. |
| First day | Review all trades at end of day. Note any anomalies. |
| First week | Daily review: win rate, P&L, drawdown, any issues |
| Week 2 | If week 1 results good: consider slight lot increase |
| Month 1 | Full performance review: compare to backtest and Demo |
| Month 2+ | Normal monitoring schedule (morning/evening routines) |

---

## Test Report Summary (P9-5 Final)

| Test Suite | Pass | Fail | Total |
|-----------|------|------|-------|
| MQL5 component tests (P8-4) | 63 | 0 | 63 |
| Python unit tests (P8-4) | 43 | 0 | 43 |
| validate_live_readiness checks (P9-5) | 56 | 0 | 57 (1 WARN — InfluxDB optional) |
| **TOTAL** | **162** | **0** | **163** |

**Validation Status: PRODUCTION READY ✅**

---

*FlashEASuite V2 Production Ready Checklist — V6 P9-5 | 2026-03-01*
*"Smart Server, Powerful Client"*
