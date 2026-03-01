# FlashEASuite V2 — Monitoring Guide

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01

---

## 1. Monitoring Stack Overview

FlashEASuite V2 มี 4 layers ของ monitoring:

| Layer | Tool | Frequency | Purpose |
|-------|------|-----------|---------|
| **Real-time dashboard** | `dashboard.py` (auto) | 5 seconds | Active strategy, regime, P&L, tick count |
| **Health monitor** | `health_monitor.py` | Continuous | Process status, port status, resource usage |
| **Validation tool** | `validate_live_readiness.py` | On-demand | Pre-live system integrity check |
| **MT5 Experts tab** | MT5 built-in | Real-time | EA messages, errors, trade confirmations |

---

## 2. Brain Dashboard

### Launch

Brain auto-displays dashboard every 5 seconds in its console.

Manual launch (separate terminal):
```cmd
cd FlashEASuite_V2
python 02_Brain\dashboard.py
```

### Dashboard Panels

```
══════════════════════════════════════════════════════════════════
📊 STRATEGY ENGINE DASHBOARD v2.3       [2026-03-01 14:32:15]
══════════════════════════════════════════════════════════════════

SYSTEM STATUS
─────────────────────────────────────────────────────────────────
  ZMQ Feeder (7777):  ✅ CONNECTED     Ticks: 12,345
  ZMQ Policy (7778):  ✅ BOUND         Policies sent: 48
  ZMQ Feedback (7779):✅ LISTENING     Trades received: 7
  InfluxDB (8086):    ⚠️ OFFLINE       (optional — not blocking)

REGIME & STRATEGY
─────────────────────────────────────────────────────────────────
  Current Regime:     RANGING
  Active Strategies:  S07_MEAN_REV (conf: 0.72)
                      S15_GRID     (conf: 0.65)
  Last Config Push:   2026-03-01 14:31:58 (17s ago)
  Risk Multiplier:    1.00×

PERFORMANCE
─────────────────────────────────────────────────────────────────
  Today Trades:       7W / 2L    (77.8% win rate)
  Today P&L:          +$34.50
  Total Drawdown:     -1.2%
  Best Strategy:      S07 (4W/0L today)

SYMBOL MAP (Top 5 by Spike Score)
─────────────────────────────────────────────────────────────────
  XAUUSD.tp → XAUUSD  │ Ticks: 4,521 │ Spike Score: 52.3  ⏳
  EURUSD.tp → EURUSD  │ Ticks: 3,201 │ Spike Score: 28.1  ✅
  GBPUSD.tp → GBPUSD  │ Ticks: 2,890 │ Spike Score: 31.4  ✅
  USDJPY.tp → USDJPY  │ Ticks: 1,733 │ Spike Score: 19.8  ✅
  AUDUSD.tp → AUDUSD  │ Ticks:   876 │ Spike Score: 12.2  ✅

══════════════════════════════════════════════════════════════════
```

### Understanding Dashboard Fields

| Field | Meaning | Normal Value |
|-------|---------|-------------|
| Ticks | Total ticks received since Brain start | Increasing (never 0) |
| Policies sent | Total CONFIG_PUSH sent | Increases ~1/min |
| Current Regime | Market regime detected by classifier | Any of 4 regimes |
| Active Strategies | Strategies with confidence ≥ 0.50 | 1–4 normally |
| Last Config Push | Time since last policy sent to Trader | < 30 seconds |
| Risk Multiplier | Brain's risk scaling factor | 0.5–2.0× |
| Spike Score | Current spike intensity (0–100) | < 70 is normal |
| Win Rate (today) | Live win/loss from Trader feedback | 45–65% healthy |

---

## 3. Health Monitor

### Launch

```cmd
cd FlashEASuite_V2
python tools\health_monitor.py
```

Continuous mode (default, refreshes every 30s):
```cmd
python tools\health_monitor.py --continuous
```

Single check:
```cmd
python tools\health_monitor.py --once
```

### Health Monitor Output

```
╔══════════════════════════════════════════════════════╗
║     FlashEASuite V2 — Health Monitor v1.0            ║
║     Check time: 2026-03-01 14:32:00                  ║
╠══════════════════════════════════════════════════════╣
║  Process Status                                      ║
║  ──────────────────────────────────────────────────  ║
║  🟢 Python Brain        UP      (PID: 12345)        ║
║  🟢 MetaTrader 5        UP      (PID: 67890)        ║
║                                                      ║
║  Port Status                                         ║
║  ──────────────────────────────────────────────────  ║
║  🟢 Port 7777           LISTENING                   ║
║  🟢 Port 7778           LISTENING                   ║
║  🟡 Port 7779           FREE    (normal — CONNECT)  ║
║  🟡 Port 8086           CLOSED  (InfluxDB optional) ║
║                                                      ║
║  Resource Usage                                      ║
║  ──────────────────────────────────────────────────  ║
║  🟢 Python CPU:         8.3%    (OK < 15%)          ║
║  🟢 Python Memory:      156 MB  (OK < 300 MB)       ║
║  🟢 Disk Free:          45 GB   (OK > 5 GB)         ║
║                                                      ║
║  Overall: ✅ HEALTHY                                 ║
╚══════════════════════════════════════════════════════╝
```

### Health Status Colors

| Color | Meaning | Action |
|-------|---------|--------|
| 🟢 GREEN | Normal — no action needed | None |
| 🟡 YELLOW | Warning — monitor closely | Investigate |
| 🔴 RED | Critical — action required | Fix immediately |

---

## 4. Validation Tool

### Full Validation (run before every trading session)

```cmd
python tools\validate_live_readiness.py
```

### Validation Checks

| Check | What it verifies |
|-------|-----------------|
| `Imports` | All Python modules import without error |
| `Deps` | pyzmq, msgpack, numpy, pandas installed |
| `Files` | All required files exist at correct paths |
| `Ports` | Ports 7777/7778/7779 available (not blocked) |
| `ZMQ` | ZMQ sockets can bind/connect |
| `Config` | config.py loads, all required keys present |
| `Receive` | CONFIG_PUSH builds and serializes correctly |
| `InfluxDB` | InfluxDB reachable (WARN if not — optional) |

### Expected Result

```
═══════════════════════════════════════════════════════════
  📊 VALIDATION SUMMARY
═══════════════════════════════════════════════════════════

  ✅ PASS  Imports
  ✅ PASS  Deps
  ✅ PASS  Files
  ✅ PASS  Ports
  ✅ PASS  ZMQ
  ✅ PASS  Config
  ✅ PASS  Receive
  ⚠️ WARN  InfluxDB    Not running (optional)

  Total: 25+ passed, 0 failed, 1 warning

  🚀 SYSTEM READY FOR LIVE TRADING!
```

### Selective Validation Flags

| Flag | Checks only |
|------|------------|
| `--quick` | Imports + file existence |
| `--zmq` | ZMQ socket bind/connect + CONFIG_PUSH format |
| `--influx` | InfluxDB connection + bucket write |
| `--ports` | Port availability only |

### Interpreting Validation Results

| Result | Meaning | Action |
|--------|---------|--------|
| ✅ PASS | Component working correctly | None |
| ❌ FAIL | Component broken — must fix before live | See fix instructions in output |
| ⚠️ WARN | Optional component not available | Optional fix |

---

## 5. MT5 Monitoring

### Experts Tab

Always visible in MT5 Terminal panel (bottom). Shows:
- EA initialization messages
- Trade confirmations
- ZMQ connection status
- Error messages and warnings

**Key messages to watch:**

| Message | Meaning |
|---------|---------|
| `✅ Broadcasting on X symbols` | FeederEA working |
| `[Strategy] Policy Update received` | Trader got CONFIG_PUSH |
| `[Strategy] Signal: BUY/SELL` | Trade signal generated |
| `[RiskGuardian] Daily limit reached` | Stop loss limit hit — no new trades |
| `❌ ZMQ connect failed` | Port issue — Brain may not be running |
| `❌ DLL import failed` | libzmq.dll missing or not allowed |

### Journal Tab

MT5 → Terminal → Journal tab shows system-level events and errors.

### Trade Tab

Active positions and orders. Monitor:
- Open positions (should match strategy)
- Position sizes (check against expected lots)
- Unrealized P&L

### Account History Tab

Closed trades history. Use for daily/weekly review.

---

## 6. InfluxDB Monitoring (Optional)

InfluxDB stores historical tick data and OHLC bars for analytics.

### Check InfluxDB Status

```
http://localhost:8086
```
Open in browser. If InfluxDB is running, you'll see the web UI.

### Key Buckets

| Bucket | Contents | Retention |
|--------|---------|-----------|
| `flashea_ticks` | Raw tick data (bid/ask per symbol) | 7 days |
| `flashea_ohlc` | OHLC bars per timeframe | 180 days |
| `flashea_decisions` | Strategy decisions and confidence | 90 days |

### Start InfluxDB (if installed)

```cmd
:: If installed as Windows service:
net start InfluxDB

:: If running as executable:
influxd.exe

:: If using Docker:
docker start influxdb
```

---

## 7. Log Files Reference

### flashea_brain.log

Location: `02_Brain/logs/flashea_brain.log`

```
[2026-03-01 14:30:00] INFO  Brain started v2.1.0
[2026-03-01 14:30:01] INFO  Ingestion Worker connected to tcp://127.0.0.1:7777
[2026-03-01 14:30:15] INFO  Regime detected: RANGING (confidence: 0.85)
[2026-03-01 14:30:15] INFO  Strategy selected: S07 (conf=0.72), S15 (conf=0.65)
[2026-03-01 14:30:15] INFO  CONFIG_PUSH sent to 1 client(s)
[2026-03-01 14:31:22] INFO  TRADE_REPORT: WIN | S07 | ticket=12345 | PnL=+15.50
[2026-03-01 14:31:22] INFO  PerformanceTracker updated: S07 win_rate=0.68
```

**Log levels:**
- `INFO` — normal operation
- `WARNING` — unusual but non-critical (monitor)
- `ERROR` — problem occurred (investigate)
- `CRITICAL` — system failure (immediate action)

### trades_YYYYMMDD.json

Location: `02_Brain/logs/trades_YYYYMMDD.json`

```json
{
  "date": "2026-03-01",
  "trades": [
    {
      "ticket": 12345,
      "symbol": "XAUUSD",
      "strategy": "S07_MEAN_REVERSION",
      "direction": "BUY",
      "lot": 0.01,
      "open_price": 2650.50,
      "close_price": 2652.30,
      "pnl": +18.00,
      "rr": 2.1,
      "result": "WIN",
      "timestamp": "2026-03-01T14:31:22"
    }
  ],
  "summary": {
    "total_trades": 7,
    "wins": 5,
    "losses": 2,
    "win_rate": 0.714,
    "total_pnl": +34.50
  }
}
```

### explainable/ Folder

Location: `02_Brain/explainable/`

Contains full AI decision chain logs for every CONFIG_PUSH:

```json
{
  "timestamp": "2026-03-01T14:30:15",
  "regime": "RANGING",
  "regime_confidence": 0.85,
  "strategies_evaluated": [
    {
      "id": "S07",
      "raw_confidence": 0.68,
      "hist_perf": 0.95,
      "regime_bonus": 1.2,
      "weighted": 0.775,
      "selected": true
    },
    {
      "id": "S10",
      "raw_confidence": 0.45,
      "hist_perf": 0.88,
      "regime_bonus": 0.7,
      "weighted": 0.277,
      "selected": false,
      "reason": "Below confidence threshold"
    }
  ],
  "config_push_sent": true,
  "reasoning_th": "ตลาด RANGING — เลือก S07 Mean Reversion, S15 Grid",
  "reasoning_en": "RANGING regime — activated S07 + S15"
}
```

---

## 8. Performance Metrics File

Location: `02_Brain/data/metrics/performance_metrics.json`

```json
{
  "updated": "2026-03-01T14:31:22",
  "strategies": {
    "S07_MEAN_REVERSION": {
      "total_trades": 42,
      "wins": 29,
      "losses": 13,
      "win_rate": 0.690,
      "avg_rr": 1.82,
      "ema_perf": 0.95,
      "kelly_recommended": 0.27
    },
    "S15_GRID": {
      "total_trades": 18,
      "wins": 12,
      "losses": 6,
      "win_rate": 0.667,
      "avg_rr": 1.45,
      "ema_perf": 0.88,
      "kelly_recommended": 0.21
    }
  }
}
```

---

## 9. Automated Alerts (Health Monitor)

Health monitor writes to `logs/health.log` and can trigger alerts:

### Auto-restart on Brain crash

Health monitor detects Brain crash → attempts restart (max 3 times):
```
[2026-03-01 03:15:00] WARNING  Brain process died
[2026-03-01 03:15:01] INFO     Attempting restart (1/3)
[2026-03-01 03:15:05] INFO     Brain restarted successfully
```

### Alert thresholds (logged as WARNING)

| Condition | Log message |
|-----------|------------|
| Memory > 400 MB | `WARNING: Python memory high: 412 MB` |
| CPU > 25% | `WARNING: Python CPU high: 27.3%` |
| Tick count stopped for 60s | `WARNING: No ticks received for 60 seconds` |
| Disk space < 2 GB | `WARNING: Low disk space: 1.8 GB remaining` |
| Brain not reachable | `ERROR: Brain process not found` |

---

## 10. Monitoring Checklist

### Before Each Trading Session

```
[ ] validate_live_readiness.py → 0 FAIL
[ ] start_flashea.bat status → all [RUNNING]
[ ] Dashboard shows ticks increasing
[ ] No errors in logs/health.log (last 24h)
[ ] Account margin > 50%
[ ] Market Watch symbols correct
```

### During Trading Session (every 30 min)

```
[ ] Dashboard tick count still increasing
[ ] No WARNING or ERROR in Brain console
[ ] Drawdown < 10%
[ ] Python memory < 300 MB
[ ] Health Monitor all GREEN
```

### After Trading Session

```
[ ] Review trades_YYYYMMDD.json for trade summary
[ ] Check explainable/ for unusual decision patterns
[ ] Review performance_metrics.json for strategy win rates
[ ] Check health.log for overnight warnings
[ ] Back up logs folder if space is tight
```

---

*FlashEASuite V2 Monitoring Guide — V6 P9-5 | 2026-03-01*
