# FlashEASuite V2 — Emergency Procedures

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01
> **Read this before going live. Practice every procedure on Demo first.**

---

## Emergency Quick Reference

```
╔══════════════════════════════════════════════════════════╗
║              EMERGENCY QUICK ACTIONS                     ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  🔴 STOP ALL TRADING NOW:                               ║
║     MT5 → AutoTrading button → make RED                 ║
║     Time to execute: 3 seconds                          ║
║                                                          ║
║  🔴 KILL EVERYTHING (nuclear):                          ║
║     taskkill /im python.exe /f                          ║
║     taskkill /im terminal64.exe /f                      ║
║     Time to execute: 5 seconds                          ║
║                                                          ║
║  🔴 CLOSE ALL POSITIONS:                                ║
║     MT5 → Trade tab → Right-click → Close All           ║
║     Time to execute: 10–30 seconds                      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

---

## Emergency Levels

| Level | Trigger | Action | Time |
|-------|---------|--------|------|
| **L1** | Concern / doubt | Stop new trades | 3 sec |
| **L2** | Problem confirmed | Stop + remove EAs | 30 sec |
| **L3** | Serious issue | Full system stop | 1 min |
| **L4** | Critical / unresponsive | Force kill everything | 5 sec |

---

## Level 1 — Stop New Trades (Keep System Running)

**When to use:** Something feels wrong, want to pause and assess without full shutdown.

```
MT5 toolbar → click AutoTrading button → make it RED
```

**Effect:**
- All EAs stop opening new orders
- Existing open positions remain (they will manage themselves to TP/SL)
- Brain continues running and analyzing
- Trader EA remains attached but won't execute

**To resume:**
```
MT5 toolbar → click AutoTrading button → make it GREEN
```

---

## Level 2 — Remove EAs (Stop ZMQ + Trading)

**When to use:** Want to stop both trading and data flow completely, but not restart.

```
1. MT5 → chart with Trader → Right-click → Expert Advisors → Remove
2. MT5 → chart with FeederEA → Right-click → Expert Advisors → Remove
```

**Effect:**
- ZMQ connections closed (no more policy flow)
- No more tick data sent to Brain
- Brain stays running (can reconnect by re-attaching EAs)
- Open positions remain (manage manually or via MT5)

**To restore:**
Re-attach both EAs following startup Steps 3 and 4.

---

## Level 3 — Full System Stop (Clean Shutdown)

**When to use:** Planned shutdown, end of session, or system needs restart.

```cmd
:: 1. Remove Trader EA first
::    (MT5: right-click chart → Expert Advisors → Remove)

:: 2. Remove FeederEA
::    (MT5: right-click chart → Expert Advisors → Remove)

:: 3. Stop Brain
start_flashea.bat stop

:: 4. Stop Health Monitor
Ctrl+C  ← in the Health Monitor terminal window

:: 5. Close MT5 normally
::    (File → Exit, or Alt+F4)
```

**Effect:**
- All components cleanly shut down
- ZMQ sockets properly closed
- Logs flushed and saved
- Open positions remain in MT5 (they will be managed by TP/SL orders)

**To restore:**
Follow complete startup sequence (Steps 1–6 in Operation Manual).

---

## Level 4 — Force Kill (Emergency)

**When to use:** System unresponsive, Level 1–3 impossible, extreme urgency.

```cmd
taskkill /im python.exe /f
taskkill /im terminal64.exe /f
```

**Effect:**
- Python Brain killed immediately
- MetaTrader 5 killed immediately
- All ZMQ connections dropped
- **Open positions remain in broker's system** (not closed by this action)
- **Any in-memory data is lost** (tick buffers, etc.)

> ⚠️ **After force kill:** Must restart entire system from scratch (Step 1).
> Verify all logs are intact. MT5 will reconnect to broker automatically on restart.

---

## Scenario A — Drawdown Exceeds Warning Level

### Thresholds

| Level | Drawdown | Action |
|-------|---------|--------|
| Monitor | > 5% | Watch closely, check logs |
| Caution | > 10% | Reduce lot to 50%, investigate |
| Warning | > 15% | Level 1 stop, no new trades |
| Emergency | > 20% | Level 3 full stop, close positions |

### Response Steps

```
1. Level 1 stop → AutoTrading OFF
2. Look at all open positions
3. Calculate potential max loss if SL hits on all
4. If acceptable: hold positions, wait for SL/TP
5. If not acceptable: close heaviest losers manually
6. Investigate root cause before restarting:
   - Was there a news event?
   - Was strategy selection appropriate for regime?
   - Is the drawdown within historical backtest range?
7. Resume at reduced lot (50% of normal)
8. Monitor closely for next 48 hours
```

---

## Scenario B — Flash Crash / News Spike

**Description:** Price moves 50–200+ pips in seconds (NFP, FOMC, geo-political event)

### Immediate Response (first 30 seconds)

```
1. Level 1 stop: AutoTrading OFF immediately
2. Do NOT close positions immediately (spreads are 10–50× normal)
3. Wait 1–3 minutes for spread to normalize
```

### Assessment (30 sec – 5 min)

```
4. Check spread in Market Watch → should return to normal
5. Check open positions: are they at TP or SL?
6. Check if S16_SPIKE triggered (it should have faded the spike)
7. Note: S16 has spread filter — it will NOT open during spike
```

### Recovery

```
8. Once spread normalizes (< 2× normal):
   - If positions profitable: let them reach TP
   - If positions in heavy loss beyond SL: close manually
9. Re-enable AutoTrading after spike fully resolved
10. Note: Flash crashes often reverse — wait before panic-closing
```

### Prevention

- S16_SPIKE MAX_SPREAD_MULT = 3.0 (will not open if spread > 3× normal)
- SpreadFilter.mqh blocks entry during high spread
- S07 ATR_FILTER_MULT blocks entry during high volatility

---

## Scenario C — Python Brain Crash

**Description:** Brain process terminates unexpectedly

### Immediate System Response

```
Health monitor detects crash (within 10 seconds)
→ Logs: WARNING: Brain process died
→ Attempts auto-restart (up to 3 times)
→ On success: INFO: Brain restarted successfully
→ On 3 failures: ERROR: Brain failed to restart — manual action required
```

### During Brain Downtime

```
Trader detects no CONFIG_PUSH for 30+ seconds
→ Switches to Standalone Mode automatically
→ Uses last saved standalone_config.dat
→ Runs with: S01, S06, S07, S10, S14, S15, S16 (7 strategies)
→ Risk multiplier: 0.5× (conservative)
→ Simplified regime detection per tick
```

### Manual Recovery

```cmd
:: If auto-restart failed:
start_flashea.bat stop    ← ensure clean state
start_flashea.bat         ← start fresh

:: Check why it crashed:
type 02_Brain\logs\flashea_brain.log | findstr "CRITICAL ERROR"
```

### Common crash causes

| Cause | Log indicator | Fix |
|-------|--------------|-----|
| Memory exhaustion | `MemoryError` | Reduce symbols, restart |
| Unhandled exception | `Traceback` followed by exit | Fix code bug or update |
| Port conflict | `Address already in use` | Kill conflicting process |
| InfluxDB timeout blocking | `InfluxDB write timeout` | Disable InfluxDB |

---

## Scenario D — MetaTrader 5 Crash

**Description:** MT5 terminates unexpectedly

### System Response

```
FeederEA disconnects → Brain stops receiving ticks
Brain: tick_buffer stops updating
Brain: still running, waits for reconnection
Trader disconnects → Brain loses feedback channel
```

### Recovery

```
1. Restart MT5 (double-click icon)
2. MT5 will auto-login to broker
3. MT5 will auto-reattach EAs (saved state from before crash)
4. FeederEA will restart broadcasting
5. ProgramC_Trader will reconnect to Brain's policy stream
6. Verify: Experts tab shows normal messages
7. Verify: Brain console shows tick count resuming
```

**If EAs don't auto-attach:**
Follow startup Steps 3 and 4 manually.

---

## Scenario E — Broker Connection Lost

**Description:** MT5 disconnects from broker server

### Symptoms

```
MT5: Status bar shows red "No connection"
MT5: Market Watch shows no price updates
FeederEA: stops sending ticks (no prices to send)
Brain: tick count stops increasing
```

### Response

```
1. DO NOT panic-close positions (broker holds your positions safely)
2. Do NOT restart Brain or MT5 — connection will auto-recover
3. Wait for MT5 to reconnect (usually 30 sec – 5 min)
4. If connection recovers: system resumes automatically
5. If no connection for > 30 min: contact broker
6. Check internet connection (ping 8.8.8.8)
7. Check if issue is broker-side (broker status page)
```

### During Disconnection

- Your positions are safe — they exist at the broker
- TP/SL orders are at the broker — they execute even offline
- No new trades will open (no prices = no signals)

---

## Scenario F — Server Overload / High CPU

**Description:** Python CPU > 30%, system becomes sluggish

### Response

```
1. Check Health Monitor for CPU reading
2. Identify the problem source:
   python 02_Brain\debug_policy_format.py --profile

3. Quick fix — restart Brain:
   start_flashea.bat stop
   start_flashea.bat

4. If still high after restart:
   Reduce symbols in FeederEA (remove low-priority symbols)
   Disable S02_ML_ENSEMBLE if running (most CPU-intensive)
```

---

## Scenario G — Margin Call Warning

**Description:** Free margin falls below 20% of balance

### Immediate Response

```
1. Level 1 stop: AutoTrading OFF
2. MT5 → Trade tab → review positions
3. Calculate: which positions are largest losers?
4. Options:
   a. Close all positions → guaranteed loss but safe
   b. Close largest losers → reduce exposure
   c. Add funds to broker account → increase margin (risky — only if confident)
5. Do NOT add new positions in margin-call situation
```

### Prevention

RiskGuardian checks:
```cpp
// Free margin > 50% check before each order
if (AccountFreeMarginCheck(symbol, cmd, lots) < MIN_FREE_MARGIN)
    return false;  // Skip this trade
```

Default minimum free margin: 50% of balance (configurable in config.py)

---

## Scenario H — Rogue Trade / Unexpected Position

**Description:** A position opens that you didn't expect, or size is wrong

### Response

```
1. Check MT5 Trade tab → identify the unexpected position
2. Check magic number of position (identifies which EA opened it)
3. Check MT5 Experts tab → find the log entry for this trade
4. Decision:
   - If strategy logic valid: let it manage to TP/SL
   - If clearly wrong: close manually
5. Check Brain logs for unusual confidence or policy
6. Verify RiskGuardian limits are correctly set
```

### Identify trade origin by magic number

```
Magic 999000 = ProgramC_Trader council (general)
Magic 1001   = S01_STAT_ARB
Magic 1002   = S02_ML_ENSEMBLE
Magic 1003   = S03_SMC
...
Magic 1016   = S16_SPIKE
```

---

## Post-Emergency Checklist

After any emergency, before resuming trading:

```
[ ] Document: what happened, when, what triggered it
[ ] Review: Brain logs for clues (logs/flashea_brain.log)
[ ] Review: Health Monitor log (logs/health.log)
[ ] Review: open/closed positions affected
[ ] Calculate: net P&L impact of emergency
[ ] Identify: root cause (strategy? news? system? human error?)
[ ] Fix: if code/config change needed, fix before resuming
[ ] Test: run validate_live_readiness.py
[ ] Demo test: if major issue, test on Demo first before Live resume
[ ] Adjust: parameters if needed (RiskGuardian, lot sizes, thresholds)
[ ] Resume: at reduced lot size initially
[ ] Monitor: closely for first 2 hours after resuming
```

---

## Emergency Contacts & Resources

| Need | Resource |
|------|---------|
| Broker support (margin, positions) | Broker live chat / phone |
| MT5 issues | MetaQuotes support: support.metaquotes.net |
| System diagnosis | `start_flashea.bat doctor` |
| Full validation | `validate_live_readiness.py` |
| Brain logs | `02_Brain/logs/flashea_brain.log` |
| Health logs | `logs/health.log` |

---

## Emergency Decision Tree

```
Something went wrong →

  Is money at risk right now?
  ├── YES → Level 1 STOP immediately (AutoTrading OFF)
  │         Then assess the situation calmly
  └── NO  → Continue monitoring

  Is the system frozen/unresponsive?
  ├── YES → Level 4 Force Kill
  │         Restart from scratch
  └── NO  → Try Level 2 or 3

  Are open positions losing heavily (> 15% DD)?
  ├── YES → Level 1 STOP + review positions
  │         Consider partial close of worst positions
  └── NO  → Normal monitoring

  Is Brain crashed?
  ├── YES → Health monitor auto-restarts
  │         If fails: start_flashea.bat stop + start
  │         Trader runs Standalone meanwhile (safe)
  └── NO  → Continue

  Is MT5 disconnected?
  ├── YES → Wait for auto-reconnect (don't restart)
  │         Positions safe at broker
  │         TP/SL will execute even offline
  └── NO  → Continue normal operations
```

---

*FlashEASuite V2 Emergency Procedures — V6 P9-5 | 2026-03-01*
