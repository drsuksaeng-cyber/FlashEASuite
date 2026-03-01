# FlashEASuite V2 — Installation Guide

> **Version:** V6 (P9-5 Production) | **Date:** 2026-03-01
> **Estimated time:** 30–45 minutes for first-time install

---

## Prerequisites Checklist

Before starting, confirm all of the following:

### Software

| Software | Required Version | How to Check |
|----------|-----------------|--------------|
| Windows | 10/11 64-bit | System Properties |
| MetaTrader 5 | Build 3770+ | MT5 → Help → About |
| Python | 3.8+ (recommended 3.10) | `python --version` |
| pip | Latest | `pip --version` |

### Broker Account

| Item | Notes |
|------|-------|
| Account type | Demo (required first) / Live (after 1 week Demo) |
| Symbol suffix | Check your broker: `.tp`, `_m`, or empty |
| Algo trading | Must be enabled in account settings |
| Minimum lot | Check broker specs (system uses 0.01 default) |
| Leverage | Check broker specs |

### Hardware Recommendations

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 4 GB | 8 GB+ |
| CPU | 2 cores | 4 cores+ |
| Disk | 10 GB free | 50 GB (for logs + InfluxDB) |
| Internet | Stable broadband | VPS in same city as broker server |

---

## Step 1 — Install Python Dependencies

Open Command Prompt (as regular user):

```cmd
pip install pyzmq msgpack numpy pandas
```

Verify installation:

```cmd
python -c "import zmq, msgpack, numpy, pandas; print('All OK')"
```

Expected output:
```
All OK
```

### Optional (for InfluxDB historical data storage):

```cmd
pip install influxdb-client
```

---

## Step 2 — Copy Project Files

### 2.1 Find your MQL5 Data Folder

In MetaTrader 5:
1. Press **F4** to open MetaEditor
2. In MetaEditor: **File → Open Data Folder**
3. Navigate to: `MQL5\Experts\`

Your path will look like:
```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Experts\
```

### 2.2 Copy FlashEASuite_V2 Folder

Copy the entire `FlashEASuite_V2` folder into `MQL5\Experts\`:

```
MQL5\Experts\FlashEASuite_V2\
```

### 2.3 Verify Required Files Exist

Check that the following key files are present:

```
FlashEASuite_V2/
├── 01_Feeder/
│   └── Src/
│       └── FeederEA.mq5                    ← Program A source
├── 02_Brain/
│   ├── main.py                              ← Brain entry point
│   ├── core/
│   │   ├── ingestion.py                     ← Tick ingestion
│   │   ├── execution_listener.py            ← Trade feedback receiver
│   │   └── strategy/
│   │       ├── engine.py                    ← Strategy engine
│   │       ├── analysis.py                  ← Regime classifier
│   │       └── policy.py                    ← Policy selector
│   └── dashboard.py                         ← Real-time dashboard
├── 03_Trader/
│   └── ProgramC_Trader.mq5                 ← Program C source
├── Include/
│   ├── Logic/
│   │   ├── IStrategy.mqh                    ← Strategy interface
│   │   ├── StrategyConstants.mqh            ← Strategy enums
│   │   ├── StrategyManager_V6.mqh           ← Council orchestration
│   │   ├── Strategy_Spike.mqh               ← S16 Spike Hunter
│   │   ├── StrategyBase.mqh                 ← Base class
│   │   ├── SpreadFilter.mqh                 ← Spread guard
│   │   ├── TickDensity.mqh                  ← Tick density filter
│   │   └── Grid/
│   │       ├── GridConfig.mqh               ← S15 Grid config
│   │       └── GridCore.mqh                 ← S15 Grid core logic
│   ├── Network/
│   │   └── Protocol/
│   │       ├── Definitions.mqh              ← Message types, SDynamicParams
│   │       └── Serialization.mqh            ← MessagePack pack/unpack
│   ├── Risk/
│   │   └── RiskGuardian.mqh                ← Daily loss limit, max DD
│   └── Security/
│       ├── DLLWrapper.mqh                   ← ZMQ DLL wrapper
│       └── ConfigManager.mqh               ← Config security
├── tools/
│   ├── health_monitor.py                    ← System health checker
│   └── validate_live_readiness.py           ← Pre-live validator
├── docs/                                    ← Documentation
├── start_flashea.bat                        ← Main control script
└── requirements.txt                         ← Python dependencies list
```

---

## Step 3 — Install ZMQ DLL Files

### 3.1 Locate DLL files

The DLL files should be in:
```
FlashEASuite_V2\Include\Security\   (or included in release package)
```

Required files:
- `libzmq.dll`
- `libsodium.dll`

### 3.2 Copy DLLs to MQL5 Libraries

Copy both `.dll` files to:
```
MQL5\Libraries\libzmq.dll
MQL5\Libraries\libsodium.dll
```

Full path example:
```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Libraries\
```

> ⚠️ **If DLLs are missing:** EA will show "DLL not found" in Experts tab. Trading will not work.

---

## Step 4 — Configure MetaTrader 5

### 4.1 Enable Algorithmic Trading

In MT5:
1. **Tools → Options** (Ctrl+O)
2. Go to **Expert Advisors** tab
3. Check: **Allow algorithmic trading** ✅
4. Check: **Allow DLL imports** ✅
5. Click **OK**

### 4.2 Enable AutoTrading

In MT5 toolbar:
- Find the **AutoTrading** button
- Click to make it **green** (enabled)

### 4.3 Set Up Market Watch Symbols

1. **View → Market Watch** (Ctrl+M)
2. Right-click in Market Watch → **Symbols**
3. Find and add your symbols (with broker suffix):

| Symbol | With suffix `.tp` |
|--------|--------------------|
| EURUSD | EURUSD.tp |
| GBPUSD | GBPUSD.tp |
| USDJPY | USDJPY.tp |
| XAUUSD | XAUUSD.tp |

> 💡 **Tip:** Check your broker's exact symbol names. They vary: `.tp`, `.r`, `_m`, `_i`, or empty.

### 4.4 Open Required Charts

Open at least 2 charts (one for each EA):
- **Chart 1:** For FeederEA (any symbol, any timeframe — M1 recommended)
- **Chart 2:** For ProgramC_Trader (any symbol — M5 or M15 recommended)

---

## Step 5 — Compile the EA Files

> ⚠️ **Critical:** You MUST compile from within MetaEditor Navigator. Do NOT open `.mq5` files from Windows Explorer — this causes incorrect `#include` resolution.

### 5.1 Compile FeederEA

1. In MT5, press **F4** to open MetaEditor
2. In MetaEditor Navigator panel (left side):
   - Expand **Expert Advisors**
   - Navigate: `FlashEASuite_V2 → 01_Feeder → Src`
   - **Double-click** `FeederEA.mq5`
3. Press **F7** to compile
4. Check bottom panel: ✅ `0 error(s), 0 warning(s)`

### 5.2 Compile ProgramC_Trader

1. In MetaEditor Navigator:
   - Navigate: `FlashEASuite_V2 → 03_Trader`
   - **Double-click** `ProgramC_Trader.mq5`
2. Press **F7** to compile
3. Check bottom panel: ✅ `0 error(s)`

> 💡 **Compile lesson learned:**
> - `#if` compound conditions → use `#ifdef` / `#ifndef` instead
> - Check `#include` paths match actual file tree before compiling
> - If error says file not found: verify path in MetaEditor Navigator before reporting

---

## Step 6 — Run Validation

Before first use, run the full pre-live validator:

```cmd
cd C:\...\MQL5\Experts\FlashEASuite_V2\
python tools\validate_live_readiness.py
```

### Expected output (all PASS):

```
═══════════════════════════════════════════════════════════
  📊 VALIDATION SUMMARY
═══════════════════════════════════════════════════════════

  ✅ PASS  Imports         Python modules importable
  ✅ PASS  Deps            pyzmq, msgpack, numpy, pandas
  ✅ PASS  Files           Required files exist
  ✅ PASS  Ports           7777/7778 available
  ✅ PASS  ZMQ             ZMQ sockets bind/connect OK
  ✅ PASS  Config          config.py loads correctly
  ✅ PASS  Receive         CONFIG_PUSH builds correctly
  ⚠️ WARN  InfluxDB        Not running (optional)

  Total: 25+ passed, 0 failed, 1 warning

  🚀 SYSTEM READY FOR LIVE TRADING!
```

> ℹ️ The `InfluxDB WARN` is **expected and non-blocking** — InfluxDB is optional.

### Quick check only (import + files):

```cmd
python tools\validate_live_readiness.py --quick
```

### ZMQ only:

```cmd
python tools\validate_live_readiness.py --zmq
```

---

## Step 7 — Auto-Start Configuration (Optional)

Configure the system to start automatically when you log into Windows.

### 7.1 Python Brain Auto-Start

1. Open **Task Scheduler** (`Win+R` → `taskschd.msc`)
2. **Create Task** (not "Create Basic Task")
3. **General tab:**
   - Name: `FlashEA_Brain_AutoStart`
   - Check: **Run only when user is logged on**
   - Check: **Run with highest privileges**
4. **Triggers tab:**
   - New → **At log on** → Your user account
   - Delay task for: **30 seconds** (wait for MT5 to open)
5. **Actions tab:**
   - Program: `C:\...\FlashEASuite_V2\start_flashea.bat`
   - Arguments: `brain`
   - Start in: `C:\...\FlashEASuite_V2\`
6. **Conditions tab:**
   - Uncheck "Start only if on AC power" (for laptops)
7. Click **OK**

### 7.2 Health Monitor Auto-Start

1. Create another Task
2. Name: `FlashEA_HealthMonitor`
3. Trigger: At log on + Delay **60 seconds**
4. Action:
   - Program: `python`
   - Arguments: `tools\health_monitor.py`
   - Start in: `C:\...\FlashEASuite_V2\`

### 7.3 MT5 Auto-Start

Option A (MT5 setting):
- MT5 → **Tools → Options → Server**
- Check: **Start on system startup** (if available)

Option B (Windows Startup):
- Add MT5 shortcut to: `C:\Users\<YOU>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\`

> 💡 **MT5 remembers:** After restart, MT5 will auto-attach EAs that were previously on charts.

---

## Step 8 — First System Start (Test)

Follow this sequence to verify everything works:

```
1. Start MT5 → Login → AutoTrading = GREEN
2. cd FlashEASuite_V2
   start_flashea.bat
3. Attach FeederEA to Chart 1
4. Attach ProgramC_Trader to Chart 2
5. Check MT5 Experts tab
6. Check Brain console output
```

### Expected Brain console:
```
✅ Ingestion Worker started
✅ Strategy Engine started
✅ Execution Listener started
🚀 All workers started successfully (3 threads)
🎯 System is running with FEEDBACK LOOP enabled!
```

### Expected MT5 Experts tab (FeederEA):
```
✅ ZMQ PUB bound to tcp://*:7777
✅ Timer started (50ms)
✅ Broadcasting on 4 symbols
```

### Expected MT5 Experts tab (Trader):
```
✅ ZMQ Hub created
✅ Subscribed to tcp://127.0.0.1:7778
✅ Grid Strategy added to Council
✅ Spike Hunter Strategy added to Council
ProgramC_Trader V2.12 READY
```

---

## Common Installation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `ModuleNotFoundError: zmq` | pyzmq not installed | `pip install pyzmq` |
| `DLL not found` in MT5 | libzmq.dll missing | Copy DLL to `MQL5\Libraries\` |
| `0 errors` but EA won't load | DLL import not allowed | MT5 → Tools → Options → Allow DLL imports |
| Port 7778 already in use | Old Brain still running | `start_flashea.bat stop` then restart |
| Config import error | Wrong working directory | Always `cd FlashEASuite_V2` first |
| Compile error: file not found | Wrong compile method | Open from MetaEditor Navigator only |
| `Access denied` on DLL copy | Admin rights needed | Run as Administrator |

---

## Post-Installation Checklist

Before going to Demo trading:

- [ ] Python 3.8+ installed and verified
- [ ] `pip install pyzmq msgpack numpy pandas` — no errors
- [ ] `FlashEASuite_V2\` folder in `MQL5\Experts\`
- [ ] `libzmq.dll` and `libsodium.dll` in `MQL5\Libraries\`
- [ ] MT5: **Allow algorithmic trading** checked
- [ ] MT5: **Allow DLL imports** checked
- [ ] MT5: **AutoTrading** button = green
- [ ] Market Watch: All symbols added (with correct suffix)
- [ ] FeederEA compiled: **0 errors**
- [ ] ProgramC_Trader compiled: **0 errors**
- [ ] `validate_live_readiness.py` → 0 FAIL
- [ ] First test start: Brain console shows 3 workers started
- [ ] MT5 Experts tab: FeederEA broadcasting + Trader READY

---

*FlashEASuite V2 Installation Guide — V6 P9-5 | 2026-03-01*
