# Section 3 — Execution & Strategy Policy

> **ภาษา**: ไทย | **ระดับ**: Method/Function Level
> **วันที่**: 2026-03-01 | **Version**: FlashEASuite V2.1.0 (Phase P9-5)
> **ไฟล์หลัก**: `03_Trader/ProgramC_Trader.mq5` (v2.13)

---

## สารบัญ

- [3.1 ภาพรวม ProgramC_Trader — 2 โหมด](#31-ภาพรวม-programc_trader--2-โหมด)
- [3.2 Initialization — OnInit() และ 2 เส้นทาง](#32-initialization--oninit-และ-2-เส้นทาง)
- [3.3 Message Processing — PollMessages_V6()](#33-message-processing--pollmessages_v6)
- [3.4 ProcessMessage_V6() — Switch on msg_type](#34-processmessage_v6--switch-on-msg_type)
- [3.5 ConfigReceiver — รับ Policy จาก Brain](#35-configreceiver--รับ-policy-จาก-brain)
- [3.6 ExecutePolicy() — ขั้นตอนการ Execute Trade](#36-executepolicy--ขั้นตอนการ-execute-trade)
- [3.7 RiskGuardian — 4 Gates Validation](#37-riskguardian--4-gates-validation)
- [3.8 SDynamicParams — Hot-Reload Parameter Bundle](#38-sdynamicparams--hot-reload-parameter-bundle)
- [3.9 SendFeedback() — ส่งผลกลับ Brain](#39-sendfeedback--ส่งผลกลับ-brain)
- [3.10 ConnectionMonitor — Heartbeat Tracking](#310-connectionmonitor--heartbeat-tracking)
- [3.11 Standalone Mode — ทำงานไม่มี Brain](#311-standalone-mode--ทำงานไม่มี-brain)
- [3.12 Strategy Table — g_strategy_table[16]](#312-strategy-table--g_strategy_table16)
- [3.13 Regime Alignment — GetRegimeAlignmentFactor()](#313-regime-alignment--getregimealignmentfactor)
- [3.14 Example Scenario — XAUUSD Spike End-to-End](#314-example-scenario--xauusd-spike-end-to-end)

---

## 3.1 ภาพรวม ProgramC_Trader — 2 โหมด

**ไฟล์**: `03_Trader/ProgramC_Trader.mq5` (Version 2.13)
**บทบาท**: รับ policy จาก Brain → validate → execute → ส่ง feedback กลับ

### 2 โหมดการทำงาน

```
                 OnInit()
                    │
          ┌─────────▼─────────┐
          │  V6_MODE enabled? │
          └─────────┬─────────┘
               yes  │  no
         ┌──────────┴──────────┐
         ▼                     ▼
  InitializeV6Mode()    InitializeLegacyMode()
  (ใช้ใน Production)    (ใช้ใน Testing/Backtest)

V6 Mode:                   Legacy Mode:
- ConnectionMonitor        - ZMQ HUB pattern (SUB+PUB)
- ConfigReceiver           - RiskGuardian
- RegisterAllStrategies    - Council (Grid+Spike)
- Start STANDALONE         - Scanner
- OnTimer 100ms            - Timer 100ms
```

### Global Components (V6 Mode)

```mql5
// Global variables ใน ProgramC_Trader.mq5
CConnectionMonitor  g_connection_monitor;   // heartbeat tracking
CConfigReceiver     g_config_receiver;      // รับ policy จาก 7778
CRiskGuardian       g_risk_guardian;        // 4-gate validation
CStrategyManagerV6  g_strategy_manager_v6;  // manage 16 strategies
```

---

## 3.2 Initialization — OnInit() และ 2 เส้นทาง

### InitializeV6Mode()

```mql5
bool InitializeV6Mode()
{
    // Step 1: Security check
    if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
        Print("Not connected to broker");
        return false;
    }

    // Step 2: Setup ZMQ SUB socket (Port 7778 — รับ policy จาก Brain)
    g_zmq_sub = new CZmqSocket();
    g_zmq_sub.Init(ZMQ_SUB);
    g_zmq_sub.Connect("tcp://127.0.0.1:7778");
    g_zmq_sub.SetSubscribe("");   // รับทุก topic

    // Step 3: Setup ZMQ PUSH socket (Port 7779 — ส่ง feedback)
    g_zmq_push = new CZmqSocket();
    g_zmq_push.Init(ZMQ_PUSH);
    g_zmq_push.Connect("tcp://127.0.0.1:7779");

    // Step 4: ConnectionMonitor
    g_connection_monitor.Init(30, 20);   // timeout=30s, warn=20s

    // Step 5: ConfigReceiver
    g_config_receiver.Init(Symbol(), "tcp://127.0.0.1:7778");

    // Step 6: Register all 16 strategies
    RegisterAllStrategies();

    // Step 7: RiskGuardian
    g_risk_guardian.Initialize(10, 2.0, 15.0, 2.0);
    // max_orders=10, risk_pct=2%, exposure=15%, daily_limit=2%

    // Step 8: Start in Standalone mode (Brain อาจยังไม่ connect)
    SwitchToStandalone();

    // Step 9: Set timer
    EventSetMillisecondTimer(100);

    return true;
}
```

### RegisterAllStrategies()

```mql5
void RegisterAllStrategies()
{
    InitStrategyTable();    // สร้าง g_strategy_table[16]

    // Register แต่ละ strategy กับ manager
    g_strategy_manager_v6.RegisterStrategy(S01_STAT_ARB,       new CStrategy_S01());
    g_strategy_manager_v6.RegisterStrategy(S02_ML_ENSEMBLE,    new CStrategy_S02());
    g_strategy_manager_v6.RegisterStrategy(S03_SMC,            new CStrategy_S03());
    // ... S04 ถึง S16

    // Register Money Managers (1 per strategy, shared some)
    g_strategy_manager_v6.RegisterMM(S01_STAT_ARB,    new CMM_FixedRisk());
    g_strategy_manager_v6.RegisterMM(S15_GRID,        new CMM_GridScaling());
    g_strategy_manager_v6.RegisterMM(S16_SPIKE,       new CMM_FixedLot());
    // ... etc.

    PrintFormat("[Init] Registered %d strategies", 16);
}
```

---

## 3.3 Message Processing — PollMessages_V6()

**OnTimer()** เรียกทุก 100ms — drains message queue ก่อน:

```mql5
void OnTimer()
{
    // 1. Drain message queue (สูงสุด 20 messages per timer call)
    PollMessages_V6();

    // 2. Run strategy tick ด้วย market data ปัจจุบัน
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick))
        g_strategy_manager_v6.OnTick(tick);

    // 3. Check heartbeat (ทุก OnTimer call)
    if(!g_connection_monitor.Check()) {
        // timeout → switch standalone
        if(g_strategy_manager_v6.GetMode() != MODE_STANDALONE)
            SwitchToStandalone();
    }
}

void PollMessages_V6()
{
    int msg_count = 0;
    int max_per_call = 20;   // ป้องกัน timer starve

    while(msg_count < max_per_call)
    {
        uchar raw_data[];
        if(!g_config_receiver.ReceiveRaw(raw_data))
            break;    // ไม่มีข้อความรออยู่

        ProcessMessage_V6(raw_data);
        g_connection_monitor.UpdateHeartbeat();   // ทุก message reset heartbeat
        msg_count++;
    }
}
```

**ทำไม max 20 messages ต่อ OnTimer?**
> ป้องกัน timer starvation — ถ้า Brain ส่งข้อมูลเร็วมาก Trader จะไม่ติดอยู่กับการอ่าน message และยังมีเวลา run strategy + check heartbeat

---

## 3.4 ProcessMessage_V6() — Switch on msg_type

```mql5
void ProcessMessage_V6(const uchar &raw_data[])
{
    // Unpack msgpack → ดู msg_type ที่ index [0]
    int msg_type = MsgpackGetInt(raw_data, 0);

    switch(msg_type)
    {
        case 10:   // CONFIG_PUSH — Policy จาก Brain
            ExecutePolicy(raw_data);
            break;

        case 12:   // INITIAL_CONFIG — Brain reconnect
            SwitchToOnline();
            g_connection_monitor.MarkInitialConnected();
            LoadInitialConfig(raw_data);
            break;

        case 13:   // SWITCH_STANDALONE — Brain สั่งให้ standalone
            g_connection_monitor.ForceDisconnect();
            SwitchToStandalone();
            break;

        case 30:   // HEARTBEAT — periodic ping
            // UpdateHeartbeat() เรียกแล้วใน PollMessages_V6()
            // ไม่ต้องทำอะไรเพิ่ม
            break;

        case 31:   // EMERGENCY_COMMAND — Brain สั่งหยุด
            HandleEmergency(raw_data);
            // ปิด trading ทั้งหมด, ส่ง ACK กลับ
            break;

        case 40:   // STRATEGY_UPDATE — hot-reload strategy params
            LoadStrategyUpdate(raw_data);
            break;

        case 50:   // DIAGNOSTIC_REQUEST
            SendDiagnosticReport();
            break;

        case 99:   // SHUTDOWN
            HandleShutdown();
            ExpertRemove();
            break;

        default:
            PrintFormat("[Trader] Unknown msg_type=%d", msg_type);
    }
}
```

---

## 3.5 ConfigReceiver — รับ Policy จาก Brain

**ไฟล์**: `Include/Logic/ConfigReceiver.mqh` — class `CConfigReceiver`

ConfigReceiver ทำหน้าที่ unpack Array[11] จาก Brain และเก็บเป็น `SDynamicParams`:

```mql5
class CConfigReceiver
{
    CZmqSocket*     m_sub_socket;
    SDynamicParams  m_last_policy;

    bool ReceiveRaw(uchar &out_data[])
    {
        // Non-blocking receive
        return m_sub_socket.RecvRaw(out_data, ZMQ_NOBLOCK);
    }

    bool ParseConfigPush(const uchar &raw[], SDynamicParams &out)
    {
        // Unpack msgpack Array[11]
        // Index:  [0]type [1]ts [2]sym [3]strat [4]entry
        //         [5]lot  [6]max_ord [7]tp [8]sl [9]conf [10]risk_mult

        out.msg_type    = MsgpackGetInt(raw, 0);     // 10
        out.timestamp   = MsgpackGetDouble(raw, 1);
        out.symbol      = MsgpackGetString(raw, 2);  // e.g. "XAUUSD"
        out.strategy    = MsgpackGetString(raw, 3);  // "SPIKE" | "GRID"
        out.entry       = MsgpackGetDouble(raw, 4);
        out.lot         = MsgpackGetDouble(raw, 5);
        out.max_orders  = MsgpackGetInt(raw, 6);
        out.tp          = MsgpackGetDouble(raw, 7);
        out.sl          = MsgpackGetDouble(raw, 8);
        out.confidence  = MsgpackGetDouble(raw, 9);
        out.risk_mult   = MsgpackGetDouble(raw, 10);

        m_last_policy = out;
        return true;
    }
}
```

---

## 3.6 ExecutePolicy() — ขั้นตอนการ Execute Trade

```mql5
void ExecutePolicy(const uchar &raw_data[])
{
    // 1. Parse policy
    SDynamicParams policy;
    if(!g_config_receiver.ParseConfigPush(raw_data, policy)) {
        Print("[ExecutePolicy] Parse failed");
        return;
    }

    // 2. Format symbol (เพิ่ม broker prefix/suffix)
    string local_symbol = FormatSymbol(policy.symbol);
    // FormatSymbol("XAUUSD") → PREFIX + "XAUUSD" + SUFFIX
    // e.g. "" + "XAUUSD" + ".tp" = "XAUUSD.tp"

    // 3. Hot-reload dynamic params ไปยัง strategy
    // ทำแม้ strategy จะ HOLD (update params สำหรับ trade ถัดไป)
    IStrategy* strat = GetStrategyByName(policy.strategy);
    if(strat != NULL)
        strat.SetDynamicParams(policy);

    // 4. บันทึกลง standalone_config.dat (fallback)
    SaveStandaloneConfig(local_symbol, policy);

    // 5. Check signal
    ENUM_SIGNAL signal = strat.GetSignal();
    if(signal == SIGNAL_HOLD) {
        // ไม่เปิด order ใหม่ แต่ params ถูก update แล้ว
        return;
    }

    // 6. RiskGuardian Validation (4 gates)
    double lot_size = policy.lot;
    if(!g_risk_guardian.ValidateNewTrade(local_symbol, policy.entry, policy.sl, lot_size)) {
        PrintFormat("[ExecutePolicy] RiskGuardian blocked trade on %s", local_symbol);
        return;
    }

    // 7. Execute trade
    if(policy.strategy == "SPIKE") {
        ExecuteSpikeEntry(local_symbol, signal, lot_size, policy);
    } else if(policy.strategy == "GRID") {
        ExecuteGridEntry(local_symbol, signal, lot_size, policy);
    }
}

string FormatSymbol(const string base)
{
    // Prepend PREFIX, append SUFFIX (configured in EA inputs)
    // ตัวอย่าง: PREFIX="", SUFFIX=".tp"
    return InpSymbolPrefix + base + InpSymbolSuffix;
}
```

### ExecuteSpikeEntry() vs ExecuteGridEntry()

| ลักษณะ | SPIKE | GRID |
|--------|-------|------|
| max_orders | 1 | 5 |
| Order type | Market Order | Pending (Limit) |
| TP:SL ratio | 2:1 (ATR×0.8 : ATR×0.4) | Grid spacing symmetric |
| Exit logic | SL/TP หรือ time-based | Grid TP each level |
| magic range | 1001–1016 (per strategy) | 1001–1016 (per strategy) |

---

## 3.7 RiskGuardian — 4 Gates Validation

**ไฟล์**: `Include/Risk/RiskGuardian.mqh` — class `CRiskGuardian`

```mql5
class CRiskGuardian
{
    int    m_max_orders;       // 10
    double m_max_risk_pct;     // 2.0%
    double m_max_exposure_pct; // 15.0%
    double m_daily_limit_pct;  // 2.0%

    bool ValidateNewTrade(
        const string symbol,
        const double entry,
        const double sl,
        double &lot_size)       // in/out — อาจถูก clamp
    {
        double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
        double daily_pl  = equity - m_daily_start_balance;

        // --- Gate 1: Daily Loss Limit ---
        double daily_loss_pct = MathAbs(daily_pl) / balance * 100;
        if(daily_pl < 0 && daily_loss_pct >= m_daily_limit_pct) {
            PrintFormat("[RiskGuardian] BLOCKED: daily loss %.2f%% >= %.2f%%",
                daily_loss_pct, m_daily_limit_pct);
            return false;
        }

        // --- Gate 2: Max Open Orders ---
        int open_orders = CountOpenOrders();   // ทุก magic numbers
        if(open_orders >= m_max_orders) {
            PrintFormat("[RiskGuardian] BLOCKED: open_orders=%d >= %d",
                open_orders, m_max_orders);
            return false;
        }

        // --- Gate 3: Total Exposure ---
        double current_exposure = CalculateTotalExposure();  // % of equity
        double new_exposure     = CalculateNewExposure(symbol, lot_size);
        if(current_exposure + new_exposure > m_max_exposure_pct) {
            PrintFormat("[RiskGuardian] BLOCKED: exposure %.2f%% > %.2f%%",
                current_exposure + new_exposure, m_max_exposure_pct);
            return false;
        }

        // --- Gate 4: Lot Size Validation & Clamp ---
        lot_size = CalculateSafeLotSize(symbol, entry, sl);
        if(lot_size <= 0) {
            Print("[RiskGuardian] BLOCKED: lot_size=0");
            return false;
        }

        return true;    // ผ่านทุก gate
    }

    double CalculateSafeLotSize(
        const string symbol,
        const double entry,
        const double sl)
    {
        // 1% rule: risk = equity × risk_pct
        double equity        = AccountInfoDouble(ACCOUNT_EQUITY);
        double risk_amount   = equity * m_max_risk_pct / 100.0;

        // pip distance
        double sl_distance   = MathAbs(entry - sl);
        double pip_value     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

        if(sl_distance == 0 || pip_value == 0) return 0;

        double lot = risk_amount / (sl_distance / tick_size * pip_value);

        // Clamp to broker limits
        double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        lot = MathMax(min_lot, MathMin(max_lot, lot));
        lot = MathRound(lot / lot_step) * lot_step;   // round to step

        return lot;
    }
}
```

### สรุป RiskGuardian Gates

```
Trade Request
     │
     ▼
Gate 1: daily_loss_pct < daily_limit_pct (2%)?
     │ FAIL → block + log
     │ PASS ↓
Gate 2: open_orders < max_orders (10)?
     │ FAIL → block + log
     │ PASS ↓
Gate 3: total_exposure + new_exposure < max_exposure (15%)?
     │ FAIL → block + log
     │ PASS ↓
Gate 4: CalculateSafeLotSize() > 0?
     │ FAIL → block + log
     │ PASS ↓
     ▼
Execute Trade ✅
```

---

## 3.8 SDynamicParams — Hot-Reload Parameter Bundle

**ไฟล์**: `Include/Network/Protocol/Definitions.mqh`

`SDynamicParams` คือ struct ที่รวม parameters ทุกอย่างที่ Brain ส่งมา — strategy จะ `SetDynamicParams()` เพื่อ update โดยไม่ต้อง restart EA:

```mql5
struct SDynamicParams
{
    int    msg_type;      // 10 = CONFIG_PUSH
    double timestamp;     // unix ms
    string symbol;        // normalized "XAUUSD"
    string strategy;      // "SPIKE" | "GRID"
    double entry;         // entry price reference
    double lot;           // suggested lot size
    int    max_orders;    // max concurrent orders
    double tp;            // take profit price
    double sl;            // stop loss price
    double confidence;    // signal confidence 0-1
    double risk_mult;     // risk multiplier from Brain
};

// IStrategy interface รับ params นี้
interface IStrategy
{
    bool   Init();
    void   Analyze(const MqlTick &ticks[]);
    ENUM_SIGNAL GetSignal();
    double GetConfidence();
    void   SetDynamicParams(const SDynamicParams &params);   // ← hot-reload
    bool   ShouldExit(const ulong ticket);
};
```

**ผลของ Hot-Reload**:
- ไม่ต้อง remove/re-add EA บน chart
- Brain สามารถ adjust TP/SL, lot size, max_orders ตาม market condition real-time
- Strategy ใช้ params ใหม่สำหรับ order ถัดไปทันที

---

## 3.9 SendFeedback() — ส่งผลกลับ Brain

เรียกทุกครั้งที่: order ถูก fill, ปิด, หรือ SL/TP hit

```mql5
void SendFeedback(
    const ulong   ticket,
    const string  symbol,
    const int     order_type,    // 0=BUY 1=SELL
    const double  volume,
    const double  open_price,
    const double  sl,
    const double  tp,
    const double  profit,
    const int     magic,
    const string  comment)
{
    // Pack Array[12]
    uchar packed[];

    // Array[12]:
    // [0]  msg_type   = 100 (TRADE_REPORT)
    // [1]  timestamp  = TimeCurrent() * 1000.0  (ms as double)
    // [2]  ticket     = order ticket (long)
    // [3]  symbol     = local symbol e.g. "XAUUSD.tp"
    // [4]  order_type = 0 | 1
    // [5]  volume     = lot size
    // [6]  open_price = fill price
    // [7]  sl
    // [8]  tp
    // [9]  profit     = current P&L (0.0 if still open)
    // [10] magic      = strategy magic number 1001-1016
    // [11] comment    = e.g. "S09_SPIKE_ENTRY"

    MsgpackPackArray(packed, 12);
    MsgpackAppendInt(packed,    100);
    MsgpackAppendDouble(packed, (double)TimeCurrent() * 1000.0);
    MsgpackAppendLong(packed,   (long)ticket);
    MsgpackAppendString(packed, symbol);
    MsgpackAppendInt(packed,    order_type);
    MsgpackAppendDouble(packed, volume);
    MsgpackAppendDouble(packed, open_price);
    MsgpackAppendDouble(packed, sl);
    MsgpackAppendDouble(packed, tp);
    MsgpackAppendDouble(packed, profit);
    MsgpackAppendInt(packed,    magic);
    MsgpackAppendString(packed, comment);

    // Send via ZMQ PUSH (non-blocking)
    g_zmq_push.SendRaw(packed, ZMQ_NOBLOCK);
}
```

**เมื่อไหร่ที่ profit = 0.0?**
- Order เพิ่งถูก fill (เปิดใหม่) — Brain รู้ว่ามี open position
- Brain ใช้ข้อมูลนี้ update EmergencySystem.update_trade_result()

**เมื่อไหร่ที่ profit ≠ 0?**
- Order ปิดแล้ว (SL hit, TP hit, manual close)
- Brain ใช้ update risk_multiplier: win→×1.05, loss→×0.90

---

## 3.10 ConnectionMonitor — Heartbeat Tracking

**ไฟล์**: `Include/Logic/ConnectionMonitor.mqh` — class `CConnectionMonitor`

```mql5
class CConnectionMonitor
{
    int      m_heartbeat_timeout;  // 30s
    int      m_warn_threshold;     // 20s
    bool     m_is_connected;
    datetime m_last_heartbeat;
    int      m_consecutive_timeouts;
    int      m_total_reconnects;
    bool     m_warn_issued;

    // เรียกทุกครั้งที่ได้รับ ANY message จาก Brain
    void UpdateHeartbeat()
    {
        datetime now = TimeCurrent();
        if(!m_is_connected) {
            PrintFormat("[CM] RECONNECTED after %ds offline",
                (int)(now - m_disconnect_time));
            m_connect_time = now;
            m_total_reconnects++;
        }
        m_is_connected       = true;
        m_last_heartbeat     = now;
        m_consecutive_timeouts = 0;
        m_warn_issued        = false;
    }

    // เรียกทุก OnTimer() — ตรวจสอบ timeout
    bool Check()
    {
        if(m_last_heartbeat == 0) return false;   // ยังไม่เคยได้ heartbeat

        datetime now     = TimeCurrent();
        int      elapsed = (int)(now - m_last_heartbeat);

        // Hard timeout → disconnect
        if(elapsed > m_heartbeat_timeout) {
            if(m_is_connected) {
                m_is_connected = false;
                m_consecutive_timeouts++;
                PrintFormat("[CM] TIMEOUT after %ds", elapsed);
            }
            return false;
        }

        // Pre-timeout warning
        if(elapsed > m_warn_threshold && !m_warn_issued) {
            m_warn_issued = true;
            PrintFormat("[CM] WARNING: no heartbeat %ds (timeout in %ds)",
                elapsed, m_heartbeat_timeout - elapsed);
        }

        return true;
    }

    // เรียกเมื่อ Brain ส่ง msg_type=13 (SWITCH_STANDALONE)
    void ForceDisconnect()
    {
        m_is_connected   = false;
        m_disconnect_time = TimeCurrent();
        m_last_heartbeat = 0;   // ป้องกัน auto-reconnect detection
        Print("[CM] FORCE DISCONNECT");
    }

    // true = connected AND หัวใจยังสด (< warn_threshold)
    bool IsHealthy()
    {
        if(!m_is_connected || m_last_heartbeat == 0) return false;
        return ((int)(TimeCurrent() - m_last_heartbeat) <= m_warn_threshold);
    }
}
```

### State Transitions

```
Initial State: m_is_connected=false, m_last_heartbeat=0

ได้รับ message → UpdateHeartbeat()
  → m_is_connected=true, last_heartbeat=now, timeouts=0

OnTimer Check() ทุก 100ms:
  elapsed ≤ 20s → return true (healthy)
  elapsed 20-30s → WARNING log (1 ครั้ง), return true
  elapsed > 30s  → m_is_connected=false, return false
                   → Trader calls SwitchToStandalone()

Brain reconnect → msg_type=12 → MarkInitialConnected()
  → m_is_connected=true ทันที (ไม่รอ heartbeat แรก)
```

---

## 3.11 Standalone Mode — ทำงานไม่มี Brain

### SwitchToStandalone()

```mql5
void SwitchToStandalone()
{
    PrintFormat("[Trader] Switching to STANDALONE mode");

    // 1. Load params จาก backup file
    LoadStandaloneConfig();    // อ่าน standalone_config.dat

    // 2. Enable เฉพาะ SA-capable strategies
    g_strategy_manager_v6.SetMode(MODE_STANDALONE);

    // Standalone-capable strategies:
    // S01 (1001), S06 (1006), S07 (1007), S10 (1010)
    // S14 (1014), S15 (1015), S16 (1016)

    // 3. Disable non-SA strategies
    // S02, S03, S04, S05, S08, S09, S11, S12, S13
    // (ต้องการ Brain สำหรับ ML หรือ external data)
}
```

### standalone_config.dat — Fallback Persistence

```ini
; เขียนทุกครั้งที่ได้รับ CONFIG_PUSH (msg_type=10)
; ไฟล์: <MT5 Data Folder>/MQL5/Files/standalone_config.dat

[XAUUSD]
strategy=SPIKE
entry=2650.60
lot=0.10
max_orders=1
tp=2652.20
sl=2649.90
confidence=0.724
risk_mult=1.0
timestamp=1709251205

[EURUSD]
strategy=GRID
entry=1.08420
lot=0.05
max_orders=5
tp=1.08470
sl=1.08370
confidence=0.650
risk_mult=0.95
timestamp=1709251210
```

### Standalone Strategy Self-Management

ใน Standalone mode แต่ละ SA strategy ทำงานด้วย built-in logic ของตัวเอง:

| Strategy | Standalone Logic |
|----------|-----------------|
| S01_STAT_ARB | คำนวณ spread cointegration จาก price history |
| S06_KAMA | KAMA indicator self-managed, Kaufman Adaptive MA |
| S07_MEAN_REVERSION | Bollinger Band + Z-score ด้วย local data |
| S10_TURTLE | Donchian Channel 20/55 day breakout |
| S14_BB_SQUEEZE | Bollinger + Keltner squeeze detection |
| S15_GRID | Grid levels ตาม ATR (ใช้ stored grid_spacing) |
| S16_SPIKE | Velocity + Pattern score จาก tick data |

RiskGuardian ยังทำงานเหมือนเดิมใน Standalone mode — ไม่มีการ bypass risk controls

---

## 3.12 Strategy Table — g_strategy_table[16]

**ไฟล์**: `Include/Logic/StrategyConstants.mqh`

```mql5
struct SStrategyInfo
{
    ENUM_STRATEGY_ID id;          // enum value (0-based index)
    string           name;        // full name
    string           short_name;  // e.g. "S01"
    int              magic;       // 1001-1016
    ENUM_STRATEGY_CAT category;   // FULL_MQL5 | HYBRID
    bool             standalone;  // can run without Brain
    ENUM_MARKET_REGIME best_regime;
    ENUM_MARKET_REGIME alt_regime;
    string           family;      // "TREND" | "RANGE" | "VOLATILITY" | "HYBRID"
};

SStrategyInfo g_strategy_table[16];   // initialized by InitStrategyTable()

// ตัวอย่าง entries:
// g_strategy_table[0]  = {S01_STAT_ARB,    "Stat Arb",    "S01", 1001, HYBRID,    true,  RANGING,  TRENDING,  "RANGE"}
// g_strategy_table[5]  = {S06_KAMA,        "KAMA",        "S06", 1006, FULL_MQL5, true,  TRENDING, RANGING,   "TREND"}
// g_strategy_table[8]  = {S09_SESSION,     "Session",     "S09", 1009, FULL_MQL5, false, VOLATILE, TRENDING,  "VOLATILITY"}
// g_strategy_table[15] = {S16_SPIKE,       "Spike",       "S16", 1016, FULL_MQL5, true,  VOLATILE, TRENDING,  "VOLATILITY"}
```

**ทำไม Magic Number 1001–1016?**
> Magic number ใช้แยก orders ของแต่ละ strategy — ถ้า S06 เปิด order จะ stamp magic=1006 ทำให้ S06 รู้ว่า order ไหนเป็นของตัวเอง และ RiskGuardian นับ orders แยกตาม magic ได้

---

## 3.13 Regime Alignment — GetRegimeAlignmentFactor()

**ไฟล์**: `Include/Logic/StrategyConstants.mqh`

```mql5
double GetRegimeAlignmentFactor(
    const ENUM_STRATEGY_ID   strategy_id,
    const ENUM_MARKET_REGIME current_regime)
{
    SStrategyInfo info = g_strategy_table[strategy_id];

    if(current_regime == info.best_regime)
        return 1.5;    // Perfect match — เพิ่ม lot/confidence 50%

    if(current_regime == info.alt_regime)
        return 1.2;    // Alternative match — เพิ่ม 20%

    if(current_regime == REGIME_UNKNOWN)
        return 1.0;    // ไม่รู้ regime — neutral

    // Check if diametrically opposed
    bool is_poor = IsPoorRegimeMatch(info.best_regime, current_regime);
    if(is_poor)
        return 0.5;    // Poor match — ลด 50%

    return 0.3;        // Terrible match — ลด 70% (เกือบปิด)
}

// ENUM_MARKET_REGIME values:
// UNKNOWN=0, TRENDING=1, RANGING=2, VOLATILE=3, SQUEEZE=4
```

### ตัวอย่างการใช้งาน

| Strategy | Best Regime | Current | Factor | ผลลัพธ์ |
|----------|-------------|---------|--------|---------|
| S06_KAMA | TRENDING | TRENDING | **1.5** | lot × 1.5 (aggressive) |
| S06_KAMA | TRENDING | RANGING | 0.5 | lot × 0.5 (cautious) |
| S15_GRID | RANGING | RANGING | **1.5** | lot × 1.5 |
| S15_GRID | RANGING | VOLATILE | 0.3 | lot × 0.3 (nearly off) |
| S16_SPIKE | VOLATILE | VOLATILE | **1.5** | lot × 1.5 |

---

## 3.14 Example Scenario — XAUUSD Spike End-to-End

**สถานการณ์**: ข่าว US CPI ทำให้ XAUUSD spike +$3 ใน 2 วินาที

```
T=0ms    FeederEA ส่ง tick XAUUSD.tp bid=2650.50, ask=2650.70
         → Array[7]=[1, 10042, 1709251200000, "XAUUSD.tp", 2650.50, 2650.70, 3]
         → ZMQ PUB 7777

T=5ms    Brain Worker1 (Ingestion) รับ tick
         → parse → {symbol:"XAUUSD.tp", bid:2650.50, ask:2650.70}
         → ingestion_queue.put(tick)

T=8ms    Brain Worker2 (Strategy Engine) รับจาก queue
         → normalize_symbol("XAUUSD.tp") = "XAUUSD"
         → tick_history["XAUUSD"].append(tick)  # ตอนนี้มี 127 ticks

         → calculate_spike_score(last 50 ticks):
              window mids: [2647.60, ... 2650.00, 2650.20, 2650.60] (spike trend)
              price_change = 2650.60 - 2647.60 = 3.00
              volatility   = std_dev = 0.85
              score = min(100, 3.00×2 + 0.85×3) = min(100, 8.55) = 8.55

         → calculate_grid_confidence(last 50 ticks):
              price_move = 3.00, sma = 2649.10, window = 50
              trend_str = 3.00 / (2649.10×50) = 0.0000226
              confidence = max(0, 1 - 0.0000226×100) = 0.9977  ← ranging still high
              [Note: GRID confidence สูงเพราะ spike สั้นใน 50-tick window]

         → select_best_strategy(8.55, 0.9977):
              spike_conf = 8.55/100 = 0.0855 < 0.7  → not SPIKE
              grid_conf  = 0.9977 ≥ 0.6              → GRID ✓
              [Note: spike ยังไม่แรงพอสำหรับ SPIKE threshold]

         → try_generate_policy("XAUUSD", ticks):
              Gate1: "XAUUSD" in allowlist → PASS
              Gate2: strategy="GRID" ≠ NONE → PASS
              Gate3: emergency.can_trade() = true → PASS
              Gate4: now - last_policy = 15.3s > 10s → PASS
              → generate_grid_policy("XAUUSD", ticks, 0.9977)
              → Array[11]=[10, 1709251200008, "XAUUSD", "GRID",
                           2650.60, 0.05, 5, 2650.85, 2650.35, 0.9977, 1.0]
              → msgpack.packb() → ~95 bytes
              → ZMQ PUB 7778 NOBLOCK

T=100ms  ProgramC_Trader OnTimer() → PollMessages_V6()
         → recv msg ~95 bytes
         → UpdateHeartbeat() ← reset ConnectionMonitor
         → ProcessMessage_V6(data) → msg_type=10 → ExecutePolicy()
              → ParseConfigPush() → SDynamicParams{GRID, XAUUSD, lot=0.05, ...}
              → FormatSymbol("XAUUSD") = "XAUUSD.tp"
              → strat.SetDynamicParams(policy) ← hot-reload
              → SaveStandaloneConfig("XAUUSD.tp", policy)
              → strat.GetSignal() → check KAMA/Grid signals → BUY

         → RiskGuardian.ValidateNewTrade("XAUUSD.tp", 2650.60, 2650.35, 0.05):
              Gate1: daily_loss=0.8% < 2% → PASS
              Gate2: open_orders=3 < 10 → PASS
              Gate3: exposure=4% + 0.3% = 4.3% < 15% → PASS
              Gate4: lot=0.05 valid → PASS
              → return true

         → ExecuteGridEntry() → 5 Limit Orders:
              BUY 0.05 @ 2650.60 TP=2650.85 SL=2650.35
              BUY 0.05 @ 2650.35 TP=2650.60 SL=2650.10
              BUY 0.05 @ 2650.10 TP=2650.35 SL=2649.85
              (และอีก 2 levels)

T=110ms  Order ถูก fill @ 2650.71 (ask spread)
         → OnTradeTransaction() trigger
         → SendFeedback(ticket=12346, "XAUUSD.tp", BUY, 0.05, 2650.71,
                        2650.35, 2650.85, 0.0, 1015, "S15_GRID_L1")
         → ZMQ PUSH 7779

T=115ms  Brain Worker3 (Exec Listener) รับ feedback
         → _parse_trade_result() → {is_win=false, is_loss=false, profit=0}
         → feedback_queue.put(result)
         → Worker2 reads → _process_feedback()
              profit=0 → no risk_multiplier change
              emergency.update_trade_result(0, equity=50200)
```

---

*ก่อนหน้า: [Section 2 — Brain Logic](SECTION2_BRAIN_LOGIC.md)*
*ต่อไป: [Section 4 — Philosophy & Design Principles](SECTION4_PHILOSOPHY.md)*
