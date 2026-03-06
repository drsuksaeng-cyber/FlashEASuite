# SD06 — การดำเนินการฝั่ง Trader: ProgramC_Trader.mq5
## FlashEASuite V2 | คู่มือเทคนิคเชิงลึกฉบับสมบูรณ์
### จัดทำ: 2026-03-02 | Phase P9-5 | Jimmi Deep-Dive Edition

---

## 6.1 ภาพรวมองค์ประกอบ C — ProgramC_Trader

`ProgramC_Trader.mq5` คือ **แขนขาที่สัมผัสตลาดโดยตรง** ของ FlashEASuite V2 หากจะเปรียบเทียบ: ถ้า Brain คือนักวิเคราะห์ที่นั่งอยู่หน้าจอวิเคราะห์ข้อมูล Trader ก็คือเทรดเดอร์ที่นั่งโทรศัพท์กับโบรกเกอร์ Brain คิด — Trader ทำ

Trader รับนโยบาย (CONFIG_PUSH) ที่ Brain สร้างขึ้น ผ่านขั้นตอนการตรวจสอบความเสี่ยง และส่งคำสั่งซื้อขายจริงออกไปยัง broker ผ่าน MT5 API ในเวลาเดียวกันมันยังส่งรายงานผลกลับไปยัง Brain เพื่อให้ระบบเรียนรู้และปรับตัว

**ข้อมูลไฟล์:**

| ฟิลด์ | ค่า |
|-------|-----|
| **ไฟล์** | `03_Trader/ProgramC_Trader.mq5` |
| **เวอร์ชัน** | 2.13 |
| **โหมดการทำงาน** | Legacy (V2.12) หรือ V6 (Phase0) ขึ้นอยู่กับ `V6_EnableMode` |
| **Timer** | 100ms (10 Hz) |
| **ZMQ SUB** | `tcp://127.0.0.1:7778` — รับ CONFIG_PUSH จาก Brain |
| **ZMQ PUB/PUSH** | `tcp://127.0.0.1:7779` — ส่ง Feedback กลับ Brain |
| **ไลบรารีที่ใช้** | ZmqHub, RiskGuardian, StrategyManager, ConfigReceiver, ConnectionMonitor |

---

## 6.2 สองโหมดการทำงาน: Legacy และ V6

ProgramC_Trader ออกแบบให้รองรับสองยุคสมัยพร้อมกัน:

```
V6_EnableMode = false  →  InitializeLegacyMode()  [V2.12 — original architecture]
V6_EnableMode = true   →  InitializeV6Mode()       [V6 Phase0 — full 16-strategy]
```

ความแตกต่างสำคัญระหว่างสองโหมดไม่ได้อยู่ที่ว่าอันไหน "ดีกว่า" แต่อยู่ที่ปรัชญา:

- **Legacy Mode**: ออกแบบสำหรับการทดสอบและ proof-of-concept — ส่ง Feedback ผ่าน ZMQ PUB (port 7779) กลับ Brain, จัดการ Grid + Spike สองกลยุทธ์, ใช้ StrategyManager ง่ายๆ
- **V6 Mode**: ออกแบบสำหรับ production — รองรับ 16 กลยุทธ์เต็มรูปแบบ, ใช้ StrategyManager_V6 + ConfigReceiver + ConnectionMonitor, มี Standalone Mode fallback เต็มระบบ, ประหยัด config ลงไฟล์เพื่อรองรับ Brain restart

**Flowchart การเลือกโหมด:**

```
                    ┌─────────────────────────────┐
                    │  OnInit() — ProgramC_Trader  │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  V6_EnableMode = true?       │
                    └──────┬───────────────┬───────┘
                          YES             NO
                           │               │
            ┌──────────────▼─┐     ┌───────▼──────────────┐
            │ InitializeV6   │     │ InitializeLegacy      │
            │ Mode()         │     │ Mode()                │
            │ - 16 strategies│     │ - Grid + Spike only   │
            │ - Standalone   │     │ - Simple StrategyMgr  │
            │   fallback     │     │ - PUB feedback 7779   │
            └────────────────┘     └───────────────────────┘
```

---

## 6.3 กระบวนการ Initialization

### 6.3.1 Legacy Mode Initialization

```mql5
// File: 03_Trader/ProgramC_Trader.mq5 — InitializeLegacyMode()

int InitializeLegacyMode() {
    // ขั้นที่ 0: ตรวจสอบ License (P9-2, non-fatal ในช่วง development)
    g_security.Initialize();

    // ขั้นที่ 1: เชื่อม ZMQ SUB ← Brain policies (port 7778)
    g_zmq_hub.Initialize(0, 0);
    g_zmq_hub.Subscribe("tcp://127.0.0.1:7778", "");  // topic="" = รับทุก message

    // ขั้นที่ 2: เชื่อม ZMQ PUB → Brain feedback (port 7779)
    g_pub_context.initialize();
    g_pub_socket.initialize(g_pub_context, ZMQ_PUB);
    g_pub_socket.connect("tcp://127.0.0.1:7779");
    g_pub_socket.setLinger(0);

    // ขั้นที่ 3: เริ่ม RiskGuardian
    // max_orders=10, max_risk=2.0%, max_exposure=15.0%, daily_limit=2.0%
    g_risk_guardian.Initialize(10, 2.0, 15.0, 2.0);

    // ขั้นที่ 4: สร้างและเพิ่ม Strategies เข้า Council
    CStrategyGrid* grid   = new CStrategyGrid();
    g_council.AddStrategy(grid);

    CStrategySpike* spike = new CStrategySpike();
    if(spike.Init()) g_council.AddStrategy(spike);

    // ขั้นที่ 5: Scan Market Watch เพื่อหา tradeable symbols
    g_scanner.SetMaxSpreadPercent(0.15);
    g_scanner.SetForexOnly(true);
    g_scanner.ScanMarketWatch();

    // ขั้นที่ 6: เริ่ม Timer 100ms
    EventSetMillisecondTimer(100);

    return INIT_SUCCEEDED;
}
```

### 6.3.2 V6 Mode Initialization

```mql5
// File: 03_Trader/ProgramC_Trader.mq5 — InitializeV6Mode()

int InitializeV6Mode() {
    // ขั้นที่ 0: Security check
    g_security.Initialize();

    // ขั้นที่ 1: กำหนด symbol สำหรับ V6
    string v6_symbol = (Symbol() != "") ? Symbol() : FormatSymbol("XAUUSD");

    // ขั้นที่ 2: เริ่ม ConnectionMonitor (timeout=30s, warn=20s)
    g_connection_monitor_v6.Init(V6_HeartbeatTimeout, 20);

    // ขั้นที่ 3: เริ่ม ConfigReceiver (filter by symbol)
    g_config_receiver_v6.Init(v6_symbol);

    // ขั้นที่ 4: เชื่อม ZMQ SUB ← Brain (port 7778)
    g_zmq_hub.Initialize(0, 0);
    g_zmq_hub.Subscribe("tcp://" + V6_ServerIP + ":" + V6_ServerPort, "");

    // ขั้นที่ 5: ลงทะเบียน 16 กลยุทธ์ (PERIOD_M15)
    g_strategy_manager_v6.RegisterAllStrategies(v6_symbol, PERIOD_M15);

    // ขั้นที่ 6: เริ่มใน Standalone Mode
    g_v6_standalone_mode = true;
    g_strategy_manager_v6.SetServerConnected(false);

    // โหลด config ที่บันทึกไว้ หรือใช้ 7 SA strategies เป็น default
    if(!g_config_receiver_v6.LoadStandaloneConfig())
        g_strategy_manager_v6.EnableAllStandalone();
    else {
        SConfigData saved_cfg = g_config_receiver_v6.GetLastConfig();
        g_strategy_manager_v6.ApplyConfig_V6(saved_cfg);
    }

    // ขั้นที่ 7: เริ่ม Timer 100ms
    EventSetMillisecondTimer(100);

    return INIT_SUCCEEDED;
}
```

**ความแตกต่างสำคัญ V6 vs Legacy:**
- V6 ใช้ `StrategyManager_V6` รองรับ 16 strategies ผ่าน `IStrategy` interface
- V6 มี `ConnectionMonitor` คอย heartbeat และ trigger Standalone Mode อัตโนมัติ
- V6 บันทึก config ลงไฟล์ (`.bin`) ทุกครั้งที่ได้รับ CONFIG_PUSH — Brain restart ไม่ทำให้ Trader สูญเสีย state

---

## 6.4 Main Loop — OnTimer() ทุก 100ms

`OnTimer()` คือหัวใจของ Trader ทำงานทุก 100ms (10 ครั้งต่อวินาที):

```mql5
void OnTimer() {
    if(g_v6_mode_active)
        OnTimer_V6();
    else
        OnTimer_Legacy();
}
```

### 6.4.1 Legacy Timer Loop

```
OnTimer_Legacy() ทุก 100ms:
│
├─ ทุก 10 วินาที: พิมพ์ STATUS report
│   (timer_calls, poll_attempts, policies_received, trades_executed)
│
├─ ทุก 5 นาที: Rescan Market Watch symbols
│
├─ Security periodic verification (P9-2 DLL check)
│   → ล้มเหลว: ExpertRemove() ทันที
│
└─ Poll ZMQ: g_zmq_hub.Poll(recv_data)
    ├─ ไม่มี message: return (รอรอบหน้า)
    └─ มี message:
        ├─ Deserialize PolicyMessage (MessagePack)
        ├─ FormatSymbol: base_symbol + SYMBOL_SUFFIX
        ├─ ตรวจสอบว่า symbol tradeable (g_scanner.IsSymbolTradeable)
        ├─ CheckDailyLimit (g_risk_guardian)
        └─ ExecutePolicy(policy)
```

### 6.4.2 V6 Timer Loop

```
OnTimer_V6() ทุก 100ms:
│
├─ ทุก 10 วินาที: พิมพ์ V6 STATUS report
│   (Mode, Strategies enabled, Connection status, Current Regime, Configs recv)
│
├─ PollMessages_V6() — ดึง ZMQ สูงสุด 20 message ต่อรอบ
│
├─ Security periodic verification (P9-2 DLL check)
│   → ล้มเหลว: ExpertRemove() ทันที
│
└─ Strategy tick: SymbolInfoTick() → g_strategy_manager_v6.OnTick(tick)
```

---

## 6.5 V6 Message Polling — PollMessages_V6()

```mql5
void PollMessages_V6() {
    int max_per_poll = 20;  // จำกัด 20 messages ต่อ timer call เพื่อป้องกัน blocking
    int count = 0;

    while(count < max_per_poll) {
        uchar raw[];
        if(!g_zmq_hub.Poll(raw)) break;  // ไม่มีข้อความแล้ว → หยุด
        ProcessMessage_V6(raw, ArraySize(raw));
        count++;
    }

    // ตรวจ connection timeout
    bool still_connected = g_connection_monitor_v6.Check();

    if(!still_connected && g_v6_online_mode) {
        // หมดเวลา → สลับ Standalone Mode
        g_v6_online_mode     = false;
        g_v6_standalone_mode = true;
        g_strategy_manager_v6.SetServerConnected(false);
        g_strategy_manager_v6.EnableAllStandalone();
    }
}
```

**ทำไมจำกัด 20 messages ต่อรอบ?**
ในกรณีที่ Brain ส่งข้อมูลมาหนาแน่น (เช่น หลัง reconnect มีข้อความสะสมอยู่ในคิว) การดึงไม่จำกัดอาจทำให้ `OnTimer()` ใช้เวลานานเกินจนกระทบ strategy tick ที่ต้องทำงานทุก 100ms ขีดจำกัด 20 ทำให้แต่ละรอบ timer สมดุลระหว่าง message processing กับ strategy execution

---

## 6.6 V6 Message Routing — ProcessMessage_V6()

`ProcessMessage_V6()` ทำหน้าที่เป็น **router กลาง** — รับ raw bytes จาก ZMQ และส่งต่อไปยัง handler ที่เหมาะสม:

```mql5
void ProcessMessage_V6(const uchar &data[], int size) {
    // 1. Parse ผ่าน ConfigReceiver
    int msg_type = g_config_receiver_v6.ReceiveMessage(data, size);

    // 2. ทุก message จาก server → reset heartbeat timeout
    if(msg_type > 0 && msg_type != MSG_V6_UNKNOWN)
        g_connection_monitor_v6.UpdateHeartbeat();

    // 3. Route ตาม msg_type
    switch(msg_type) { ... }
}
```

**ตาราง Message Types ที่รองรับ:**

| msg_type | ค่า | การกระทำ |
|----------|-----|---------|
| `MSG_CONFIG_PUSH` | 10 | Apply config → distribute params → save standalone → switch ONLINE |
| `MSG_INITIAL_CONFIG` | 12 | เหมือน CONFIG_PUSH + เปลี่ยนเป็น ONLINE MODE |
| `MSG_HEARTBEAT` | 13 | UpdateHeartbeat เท่านั้น (ไม่ทำอะไรพิเศษ) |
| `MSG_NEWS_ALERT` | 30 | Log ข่าว: currency, impact level, event name |
| `MSG_REGIME_CHANGE` | 31 | Log การเปลี่ยน regime: prev → next + method |
| `MSG_COMMAND` | 40 | Execute command: STOP/START/SWITCH_STANDALONE/STATUS/CLOSE_ALL |
| `MSG_POLICY_UPDATE` | 50 | (no-op ปัจจุบัน) |
| `MSG_ERROR` | 99 | (no-op ปัจจุบัน) |

### 6.6.1 CONFIG_PUSH Handler — เส้นทางหลักการค้า

เมื่อได้รับ `MSG_CONFIG_PUSH` (type=10):

```
1. GetLastConfig() → ดึง SConfigData ที่ parse แล้วจาก ConfigReceiver
2. ApplyConfig_V6(cfg) → เปิด/ปิด strategy ตาม enabled_strategies bitmask
3. สำหรับ i=0..15:
   ├─ GetDynamicParamsForStrategy(id) → ดึง SDynamicParams ต่อ strategy
   └─ DistributeDynamicParams(dp, id) → ส่ง params เข้า strategy.SetDynamicParams()
4. SaveStandaloneConfig() → บันทึก config ปัจจุบันลงไฟล์ .bin
5. หาก mode เป็น STANDALONE:
   └─ สลับ g_v6_online_mode=true, g_v6_standalone_mode=false
      g_strategy_manager_v6.SetServerConnected(true)
```

### 6.6.2 COMMAND Handler

Brain สามารถส่งคำสั่งตรงมายัง Trader ได้:

| Command | การกระทำ |
|---------|---------|
| `STOP` | Disable กลยุทธ์ทั้ง 16 ตัวทันที |
| `START` | Apply config ล่าสุดจาก ConfigReceiver (เปิดใหม่) |
| `SWITCH_STANDALONE` | บังคับ Standalone Mode + EnableAllStandalone() |
| `STATUS` | Print รายงานสถานะกลยุทธ์และ connection |
| `CLOSE_ALL` | (TODO Phase P1+) ปิด positions ทั้งหมด |

คำสั่งที่ระบุ `target` (V6_ClientID) จะทำงานเฉพาะกับ Trader instance ที่มี ID ตรงกัน — ช่วยให้ Brain ควบคุม Trader หลายตัวพร้อมกันได้ในอนาคต

---

## 6.7 ExecutePolicy() — การแปลง Policy เป็น Order

`ExecutePolicy()` คือ **จุดตัดสินใจสุดท้ายก่อนวางคำสั่ง** ในโหมด Legacy โดยทำงาน 5 ขั้นตอน:

```
ExecutePolicy(policy):
│
├─ ขั้นที่ 1: อัปเดต Grid state (เสมอ — รวมถึง action=HOLD)
│   grid.UpdateFromPolicy(formatted_policy)
│   หมายเหตุ: Grid ต้องรับ policy ทุกชุด แม้ไม่ต้องเปิด order ใหม่
│   เพราะ policy อาจมีข้อมูลความเสี่ยงหรือ SL/TP ที่ต้องอัปเดต
│
├─ ขั้นที่ 2: แปลง GRID direction (ถ้า action=HOLD แต่มี grid_direction)
│   if(policy.action == 0 && grid_direction ≠ 0)
│       policy.action = grid_direction  // 1=BUY, 2=SELL
│
├─ ขั้นที่ 3: ตรวจสอบ action
│   action == 0 (HOLD) → return ทันที
│   action == 1 → ORDER_TYPE_BUY
│   action == 2 → ORDER_TYPE_SELL
│
├─ ขั้นที่ 4: คำนวณ Lot Size
│   ถ้า policy.position_size > 0 → ใช้จาก Python โดยตรง
│   ถ้า = 0 → คำนวณผ่าน RiskGuardian.CalculateSafeLotSize()
│
├─ ขั้นที่ 5: Validate ผ่าน RiskGuardian (4-check validation)
│   ล้มเหลว → SendFeedback(false, ..., "Risk rejected") + return
│
└─ ขั้นที่ 6: Execute ผ่าน Council
    g_council.ExecuteTradeWithGrid(order_type)
    g_trades_executed++
    SendFeedback(true, 0, 0.0, "Executed by Council")
```

**Flowchart:**

```
                    ┌─────────────────────────────────┐
                    │   ExecutePolicy(policy)          │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │  UpdateFromPolicy() [เสมอ]       │
                    │  อัปเดต Grid internal state      │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │  action == HOLD?                  │
                    │  (และไม่มี grid_direction)       │
                    └──────┬───────────────────┬───────┘
                          YES                 NO
                           │                   │
                    ┌──────▼──────┐   ┌────────▼────────┐
                    │  return     │   │  Determine      │
                    │  (skip)     │   │  ORDER_TYPE     │
                    └─────────────┘   └────────┬────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Calculate Lot      │
                                    │  (Policy or Risk)   │
                                    └──────────┬──────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  RiskGuardian       │
                                    │  ValidateNewTrade() │
                                    └──────┬──────────────┘
                                          PASS         FAIL
                                           │             │
                               ┌───────────▼─┐  ┌───────▼──────────┐
                               │ ExecuteTrade│  │ SendFeedback     │
                               │ WithGrid()  │  │ (false, rejected)│
                               └─────────────┘  └──────────────────┘
```

---

## 6.8 RiskGuardian — ประตูตรวจสอบความเสี่ยง 4 ชั้น

`CRiskGuardian` (v2.10) คือ **ระบบป้องกันความเสี่ยงหลัก** ของ Trader ทำหน้าที่เป็น gatekeeper ที่ทุก order ต้องผ่าน ก่อนส่ง `OrderSend()` ใดๆ

### 6.8.1 โครงสร้าง

```mql5
// Include/Risk/RiskGuardian.mqh
class CRiskGuardian {
private:
    int               m_max_orders;             // ขีดจำกัด orders พร้อมกัน
    double            m_max_risk_percent;       // ความเสี่ยงสูงสุดต่อ trade
    double            m_max_exposure_percent;   // exposure รวมสูงสุด

    CPositionSizingManager* m_position_sizing;  // คำนวณ lot size ตาม 1% rule
    CDailyLossLimit*  m_daily_limit;            // คุม daily drawdown

    // สถิติการ reject
    struct RejectionStats {
        int daily_limit, max_orders, max_exposure, lot_size, other;
    } m_rejection_stats;
};
```

### 6.8.2 การตรวจสอบ 4 ชั้น (ValidateNewTrade)

`ValidateNewTrade(symbol, entry, sl, &lot)` รัน 4 การตรวจสอบตามลำดับ — ล้มเหลวชั้นใดก็ return false ทันที:

```
ValidateNewTrade():
│
├─ Check 1: Daily Loss Limit
│   CDailyLossLimit.IsDailyLimitReached()
│   → true: "Trade rejected: Daily loss limit reached"
│   ค่า default: 2% ต่อวัน (Legacy), ปรับได้ผ่าน Initialize()
│
├─ Check 2: Max Orders
│   CountOpenPositions() ≥ m_max_orders
│   → true: "Trade rejected: Max orders reached"
│   นับเฉพาะ positions ที่: magic=999000 AND comment starts "Grid_L"
│   (ป้องกันการนับ positions เก่าจาก GridStandalone/GridTester)
│
├─ Check 3: Lot Size Validation
│   ถ้า lot_size > 0 (จาก Python) → ValidateLotSize + NormalizeLotSize
│   ถ้า lot_size = 0 → CalculateSafeLotSize() (ใช้ risk % ตาม 1% rule)
│   → lot_size ≤ 0 หลังคำนวณ: "Trade rejected: Invalid lot size"
│
└─ Check 4: Exposure Limit
    CalculateCurrentExposure() + estimated_additional > m_max_exposure_percent
    → true: "Trade rejected: Exposure limit exceeded"
    นับ exposure เฉพาะ positions ของ EA นี้ (magic=999000)

ผ่านทั้ง 4 → lot_size อัปเดต (by reference) + return true
```

**ตัวอย่างค่า parameter ที่ใช้ใน production:**

| Parameter | Legacy | หมายเหตุ |
|-----------|--------|---------|
| `max_orders` | 10 | orders สูงสุดพร้อมกัน |
| `max_risk` | 2.0% | ความเสี่ยงสูงสุดต่อ trade |
| `max_exposure` | 15.0% | exposure รวมสูงสุดของ balance |
| `daily_limit` | 2.0% | drawdown สูงสุดต่อวัน |

### 6.8.3 PositionSizingManager — สูตร 1% Rule

เมื่อ Brain ไม่ระบุ lot_size (ส่งเป็น 0) RiskGuardian จะคำนวณเองด้วยสูตร:

```
lot = (Account_Balance × risk%) / (|entry - sl| × pip_value)
```

- `risk%` default = 1.0%, จำกัดสูงสุดที่ `m_max_risk_percent`
- ผล lot ถูก normalize ตาม broker's min/max/step ก่อน return

### 6.8.4 การติดตามสถิติ Rejection

RiskGuardian บันทึกสถิติการ reject ไว้ใน `m_rejection_stats`:

```mql5
// เรียก PrintRejectionStats() เพื่อดู
void CRiskGuardian::PrintRejectionStats() {
    Print("=== REJECTION STATS ===");
    Print("Daily Limit: ", m_rejection_stats.daily_limit);
    Print("Max Orders:  ", m_rejection_stats.max_orders);
    Print("Exposure:    ", m_rejection_stats.max_exposure);
    Print("Lot Size:    ", m_rejection_stats.lot_size);
    Print("Other:       ", m_rejection_stats.other);
}
```

สถิตินี้มีประโยชน์สำหรับ tuning: ถ้า `max_orders` สูง แสดงว่า max_orders ตั้งต่ำเกิน ถ้า `exposure` สูง แสดงว่า lot_size จาก Python ใหญ่เกินสำหรับ balance ปัจจุบัน

---

## 6.9 SendFeedback() — รายงานผลกลับ Brain

หลัง order ถูก execute (หรือถูก reject) Trader ส่ง feedback กลับ Brain ผ่าน port 7779:

```mql5
void SendFeedback(bool success, long ticket, double profit, string message) {
    // Pack 12-field MessagePack array
    CMsgPack msgpack;
    msgpack.PackArray(12);
    msgpack.PackInt(100);                        // [0] msg_type: TRADE_RESULT
    msgpack.PackDouble(TimeCurrent() * 1000.0);  // [1] timestamp (ms)
    msgpack.PackDouble((double)ticket);          // [2] ticket
    msgpack.PackString(symbol);                  // [3] symbol
    msgpack.PackInt(type);                       // [4] 0=BUY, 1=SELL
    msgpack.PackDouble(volume);                  // [5] lot size
    msgpack.PackDouble(open_price);              // [6] entry price
    msgpack.PackDouble(sl);                      // [7] SL
    msgpack.PackDouble(tp);                      // [8] TP
    msgpack.PackDouble(profit);                  // [9] P&L
    msgpack.PackInt((int)magic);                 // [10] magic number
    msgpack.PackString(comment);                 // [11] comment

    // ส่งผ่าน ZMQ PUB (Legacy mode เท่านั้น)
    if(!g_v6_mode_active)
        g_pub_socket.send_bin(feedback_data, true);
}
```

**12-Field Feedback Message Format (msg_type=100):**

| Index | ฟิลด์ | ประเภท | ตัวอย่าง |
|-------|-------|--------|---------|
| [0] | msg_type | int | 100 |
| [1] | timestamp | double | 1740950400000.0 |
| [2] | ticket | double | 123456789.0 |
| [3] | symbol | string | "XAUUSD" |
| [4] | type | int | 0 (BUY) / 1 (SELL) |
| [5] | volume | double | 0.10 |
| [6] | open_price | double | 2650.50 |
| [7] | sl | double | 2640.00 |
| [8] | tp | double | 2670.00 |
| [9] | profit | double | 125.50 |
| [10] | magic | int | 999000 |
| [11] | comment | string | "Grid_L_001" |

Brain รับ feedback นี้ผ่าน `ExecutionListenerThreaded` (Thread 3) และป้อนเข้า `PerformanceTracker` เพื่อปรับ confidence scores ของกลยุทธ์ในรอบถัดไป

---

## 6.10 Standalone Mode — ทำงานได้โดยไม่ต้องมี Brain

Standalone Mode คือ **ระบบป้องกันความล้มเหลวชั้นสุดท้าย** หาก Brain ไม่ตอบสนองเกิน 30 วินาที Trader จะ fallback ไปทำงานด้วยกลยุทธ์ที่พิสูจน์แล้วว่าไม่ต้องอาศัย market intelligence จาก Python

### 6.10.1 กลยุทธ์ Standalone-capable (7 ตัว)

กลยุทธ์ที่มี `Standalone=Yes` ในตาราง strategy index:

| กลยุทธ์ | เหตุผลที่ทำงานได้เดี่ยว |
|---------|----------------------|
| S01_STAT_ARB | Rule-based statistical arbitrage ไม่ต้องใช้ ML |
| S06_KAMA | Adaptive Moving Average — pure indicator |
| S07_MEAN_REVERSION | Mean reversion ผ่าน Bollinger Bands |
| S10_TURTLE | Donchian breakout — classic rule-based |
| S14_BB_SQUEEZE | Volatility squeeze — pure indicator |
| S15_GRID | Grid trading — deterministic logic |
| S16_SPIKE | Spike hunter — uses local tick density |

กลยุทธ์ HYBRID (S02, S08) และที่ต้องใช้ regime context (S03, S04, S05, S09, S11, S12, S13) จะถูก disable อัตโนมัติใน Standalone Mode

### 6.10.2 Transition Flowchart

```
                    ┌─────────────────────────────────────┐
                    │  V6 Startup                          │
                    │  g_v6_standalone_mode = true         │
                    │  LoadStandaloneConfig() หรือ         │
                    │  EnableAllStandalone() (7 strategies) │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  CONFIG_PUSH หรือ INITIAL_CONFIG     │
                    │  ได้รับจาก Brain                     │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  g_v6_online_mode = true             │
                    │  16 strategies ทำงานเต็มรูปแบบ       │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  Brain ไม่ตอบสนอง > 30 วินาที        │
                    │  ConnectionMonitor.Check() = false   │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  สลับกลับ Standalone Mode            │
                    │  EnableAllStandalone() (7 strategies)│
                    │  Hybrid strategies ถูก disable       │
                    └─────────────────────────────────────┘
```

**Config Persistence:** ทุกครั้งที่ได้รับ CONFIG_PUSH สำเร็จ Trader จะ `SaveStandaloneConfig()` ลงไฟล์ `.bin` ดังนั้นแม้ Brain restart ค้าง Trader ก็ยังเริ่มด้วย config ล่าสุดจาก Brain ที่บันทึกไว้ (แทนที่จะ fallback ไปใช้ default ทุกครั้ง)

---

## 6.11 Symbol Formatting — การจัดการ Broker Suffix

Broker แต่ละเจ้าตั้งชื่อ instrument ต่างกัน:
- ICMarkets: `EURUSD`, `XAUUSD`
- TP Trades: `EURUSD.tp`, `XAUUSD.tp`
- FXPro: `fEURUSD`, `fXAUUSD`

ProgramC_Trader แก้ปัญหานี้ผ่าน `SYMBOL_PREFIX` + `SYMBOL_SUFFIX` inputs:

```mql5
string FormatSymbol(string base_symbol) {
    return SYMBOL_PREFIX + base_symbol + SYMBOL_SUFFIX;
}

string StripSymbol(string formatted_symbol) {
    // ตัด prefix และ suffix ออก → ได้ base symbol
}
```

**ขั้นตอนการไหลของ Symbol ตลอดระบบ:**

```
Brain ส่ง:      "XAUUSD"          (ตัด .tp แล้ว — normalize ใน engine.py)
         ↓
Trader รับ:     "XAUUSD"          (base symbol ในฟิลด์ symbol ของ PolicyMessage)
         ↓
FormatSymbol(): "XAUUSD.tp"       (เพิ่ม suffix สำหรับ broker)
         ↓
OrderSend():    "XAUUSD.tp"       (ชื่อ instrument ของ broker สำหรับ MT5 API)
```

กระบวนการนี้ทำให้ Brain ทำงานกับ symbol ชื่อ standard (ไม่มี suffix) ในขณะที่ Trader จัดการ broker-specific formatting ทั้งหมดเอง

---

## 6.12 Diagnostics และการ Monitor

### 6.12.1 Global Variables ที่สำคัญ

| ตัวแปร | ความหมาย | การดูผล |
|--------|---------|--------|
| `g_timer_calls` | รอบ timer ทั้งหมด | status report ทุก 10 วินาที |
| `g_poll_attempts` | ครั้งที่ poll ZMQ | status report |
| `g_poll_success` | poll ที่ได้รับ message | ratio = receive rate |
| `g_policies_received` | CONFIG_PUSH ที่ได้รับ | รวมตลอด session |
| `g_trades_executed` | คำสั่งที่ส่งออก | ตรวจสอบ execution rate |
| `g_last_policy_time` | เวลา policy ล่าสุด | ตรวจว่า Brain active |
| `g_v6_online_mode` | V6 ONLINE หรือ STANDALONE | สถานะการเชื่อมต่อ |

### 6.12.2 ข้อความ Log ที่ควรสังเกต

| ข้อความ | ความหมาย | การแก้ไข |
|--------|---------|---------|
| `❌ ZMQ Hub init failed` | ZMQ library ไม่พร้อม | ตรวจ DLL ใน Libraries folder |
| `⚠️  Symbol not tradeable` | Suffix ไม่ตรง | ตรวจ SYMBOL_SUFFIX input |
| `❌ Trade rejected: Daily loss limit` | ถึง drawdown limit | รอวันถัดไป |
| `❌ Trade rejected: Max orders` | positions เต็ม | รอปิด position เก่า |
| `[V6] ⚠️  SERVER TIMEOUT → STANDALONE` | Brain หยุด >30s | ตรวจ main.py |
| `[V6] ✅ Switched → ONLINE MODE` | Brain reconnect | ปกติ |
| `[SECURITY] DLL verification failed` | License ปัญหา | ตรวจ DLLWrapper |

### 6.12.3 V6 Status Report (ทุก 10 วินาที)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 V6 STATUS (5 x 10 sec)
   Mode:        ONLINE
   Strategies:  8/16
   Registered:  ✅ YES
   Connection:  Connected (last: 3s ago)
   Regime:      TRENDING
   Configs recv: 12
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 6.13 ลำดับการ Shutdown — OnDeinit()

```mql5
void OnDeinit(const int reason) {
    EventKillTimer();

    if(g_v6_mode_active) {
        g_strategy_manager_v6.Deinit();  // ปิด 16 strategies
        g_zmq_hub.Shutdown();            // ปิด ZMQ SUB socket
    } else {
        g_zmq_hub.Shutdown();
        g_pub_socket.close();
        g_pub_context.shutdown();
    }

    Print("Policies received: ", g_policies_received);
    Print("Trades executed:   ", g_trades_executed);
}
```

การ shutdown พิมพ์สรุป session statistics เสมอ ซึ่งมีประโยชน์สำหรับ post-session analysis ว่า Brain ส่ง policy มากี่ครั้ง และ Trader execute ได้กี่ครั้ง (อัตราส่วนสองตัวนี้บอกถึงประสิทธิภาพของ RiskGuardian)

---

## 6.14 ผังสรุปสถาปัตยกรรมฝั่ง Trader

```
┌─────────────────────────────────────────────────────────────────────┐
│                  ProgramC_Trader.mq5 (v2.13)                        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ ZMQ SUB ← tcp://127.0.0.1:7778 (CONFIG_PUSH from Brain)    │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │ poll ทุก 100ms                        │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  OnTimer()                                                    │ │
│  │  ├─ V6 mode → PollMessages_V6() → ProcessMessage_V6()        │ │
│  │  │           → Strategy.OnTick() (16 strategies)             │ │
│  │  └─ Legacy  → Poll() → ExecutePolicy()                       │ │
│  └───────────────────────────┬───────────────────────────────────┘ │
│                              │                                      │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  RiskGuardian.ValidateNewTrade()                              │ │
│  │  Check 1: Daily Loss Limit (CDailyLossLimit)                  │ │
│  │  Check 2: Max Orders      (CountOpenPositions, magic=999000) │ │
│  │  Check 3: Lot Validation  (CPositionSizingManager)           │ │
│  │  Check 4: Exposure Limit  (CalculateCurrentExposure)         │ │
│  └───────────────────────────┬───────────────────────────────────┘ │
│                              │ PASS                                 │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  g_council.ExecuteTradeWithGrid(ORDER_TYPE_BUY/SELL)          │ │
│  │  MT5 OrderSend() → Broker                                     │ │
│  └───────────────────────────┬───────────────────────────────────┘ │
│                              │                                      │
│                              ▼                                      │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  SendFeedback() → 12-field MessagePack [msg_type=100]         │ │
│  │  ZMQ PUB → tcp://127.0.0.1:7779 → Brain ExecutionListener    │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

> **สรุปแนวคิด — SD06**
>
> ProgramC_Trader คือจุดสัมผัสสุดท้ายระหว่าง algorithm กับตลาดจริง มันไม่ "คิด" — แต่ "ทำ" อย่างชาญฉลาด ด้วยการตรวจสอบความเสี่ยง 4 ชั้น ก่อนที่คำสั่งใดจะออกไปยัง broker ระบบ Standalone Mode ทำให้ Trader ยังคงทำงานได้แม้ไม่มี Brain Feedback loop ผ่าน port 7779 ทำให้ Brain เรียนรู้จากผลการซื้อขายจริง — ทำให้ระบบดีขึ้นเองโดยอัตโนมัติ
