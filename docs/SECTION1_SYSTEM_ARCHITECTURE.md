# Section 1 — System Architecture & Component Mapping

> **ภาษา**: ไทย | **ระดับ**: Method/Function Level
> **วันที่**: 2026-03-01 | **Version**: FlashEASuite V2.1.0 (Phase P9-5)
> **สถาปัตยกรรม**: "Smart Server, Powerful Client" — V6 Architecture

---

## สารบัญ

- [1.1 ภาพรวมระบบ (Block Diagram)](#11-ภาพรวมระบบ-block-diagram)
- [1.2 สามโปรแกรมหลักและบทบาท](#12-สามโปรแกรมหลักและบทบาท)
- [1.3 ZMQ Communication Layer](#13-zmq-communication-layer)
- [1.4 Data Flow Diagram Level 0](#14-data-flow-diagram-level-0)
- [1.5 Timing Logic — ความถี่การแลกเปลี่ยนข้อมูล](#15-timing-logic--ความถี่การแลกเปลี่ยนข้อมูล)
- [1.6 Protocol — MessagePack Binary Serialization](#16-protocol--messagepack-binary-serialization)
- [1.7 ไฟล์และโครงสร้าง Directory](#17-ไฟล์และโครงสร้าง-directory)

---

## 1.1 ภาพรวมระบบ (Block Diagram)

FlashEASuite V2 ประกอบด้วย **3 โปรแกรมหลัก** ที่สื่อสารกันผ่าน ZeroMQ (ZMQ) บนเครื่องเดียวกัน (localhost):

```
┌─────────────────────────────────────────────────────────────────────┐
│                      VPS / Local Machine                             │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                  MetaTrader 5 Process                          │  │
│  │                                                                │  │
│  │  ┌─────────────────────┐      ┌────────────────────────────┐  │  │
│  │  │   Program A          │      │   Program C                │  │  │
│  │  │   FeederEA.mq5       │      │   ProgramC_Trader.mq5      │  │  │
│  │  │                      │      │                            │  │  │
│  │  │  "นักสังเกตการณ์"    │      │  "นักเทรด"                │  │  │
│  │  │  ส่ง tick data        │      │  รับ policy + execute      │  │  │
│  │  │  4 symbols @ 50ms    │      │  16 strategies             │  │  │
│  │  │                      │      │  OnTimer 100ms             │  │  │
│  │  └──────────┬───────────┘      └────────────┬───────────────┘  │  │
│  │             │ ZMQ PUB                        │ ZMQ SUB          │  │
│  └─────────────┼────────────────────────────────┼──────────────────┘  │
│                │ Port 7777                       │ Port 7778           │
│                ▼                                 ▲                    │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │                  Program B — Python Brain                    │     │
│  │                  main.py (FlashEABrain)                      │     │
│  │                                                              │     │
│  │  "นักวิเคราะห์"                                              │     │
│  │  รับ tick → วิเคราะห์ตลาด → สร้าง policy → ส่งออก          │     │
│  │  6 Worker Threads                                            │     │
│  │                                      ZMQ PULL Port 7779 ◀──────┐  │
│  └─────────────────────────────────────────────────────────────┘  │  │
│                                                              PUSH  │  │
│                                          ProgramC_Trader ──────────┘  │
└──────────────────────────────────────────────────────────────────────┘
                          │
               [Broker Server — Internet]
                          │
                 ┌────────▼────────┐
                 │   Live Market   │
                 │  XAUUSD/EURUSD  │
                 │  GBPUSD/USDJPY  │
                 └─────────────────┘
```

---

## 1.2 สามโปรแกรมหลักและบทบาท

### Program A — FeederEA.mq5 ("นักสังเกตการณ์")

**ไฟล์**: `01_Feeder/Src/FeederEA.mq5`
**ภาษา**: MQL5 (ทำงานใน MetaTrader 5)
**บทบาท**: ส่ง real-time tick data ไปยัง Brain

| ส่วน | รายละเอียด |
|------|-----------|
| Timer | `InpTimerMs = 50ms` → `EventSetMillisecondTimer(50)` |
| Symbols | 4 symbols: XAUUSD, EURUSD, GBPUSD, USDJPY (configurable) |
| ZMQ Socket | `ZMQ_PUB` → `connect("tcp://127.0.0.1:7777")` |
| Format | `msgpack Array[7]` → `[type, seq_id, ts_ms, symbol, bid, ask, flags]` |
| Dedup | `skip if tick.time_msc <= g_LastTickTime[i]` (ป้องกัน duplicate) |

**วงจรหลัก** (`OnTimer()`):
```
OnTimer() [50ms]
  └── for i in [0..3]:  // 4 symbols
        SymbolInfoTick(symbol, tick)
        if tick.time_msc <= g_LastTickTime[i]: continue  // ข้าม duplicate
        g_LastTickTime[i] = tick.time_msc
        PackArray([1, seq++, tick.time_msc, symbol, bid, ask, flags])
        zmq_pub.send(msgpack(array))
```

---

### Program B — main.py ("สมอง" / The Brain)

**ไฟล์**: `02_Brain/main.py`
**ภาษา**: Python 3.x
**บทบาท**: วิเคราะห์ตลาด คำนวณ policy ส่งคำสั่งไป Trader

**6 Worker Threads**:

| Worker | Class | Port | Direction |
|--------|-------|------|-----------|
| W1: Ingestion | `IngestionWorkerThreaded` | 7777 SUB | รับ tick จาก FeederEA |
| W2: Strategy Engine | `StrategyEngineThreaded` | 7778 PUB | วิเคราะห์ + ส่ง policy |
| W3: Execution Listener | `ExecutionListenerThreaded` | 7779 PULL | รับ feedback จาก Trader |
| W4: Emergency System | `EmergencySystem` | — | monitor ความเสี่ยงทุก 1s |
| W5: System Monitor | `SystemMonitor` | — | CPU/RAM/latency ทุก 1s |
| W6: Live Dashboard | `LiveDashboard` | — | Terminal UI ทุก 1s |

**Queue Pipeline**:
```
FeederEA → [W1 Ingestion] → ingestion_queue → [W2 Strategy] → signal_queue → ZMQ PUB 7778
Trader   → [W3 Exec List] → feedback_queue → [W2 Strategy] → (risk adjustment)
```

---

### Program C — ProgramC_Trader.mq5 ("นักเทรด")

**ไฟล์**: `03_Trader/ProgramC_Trader.mq5`
**ภาษา**: MQL5 (Version 2.13)
**บทบาท**: รับ policy จาก Brain → validate → execute trades

**2 โหมดการทำงาน**:

| โหมด | เงื่อนไข | Strategies Active |
|------|----------|-------------------|
| **ONLINE** | Brain connected, heartbeat OK | ทั้ง 16 strategies |
| **STANDALONE** | Brain disconnect (timeout 30s) | เฉพาะ 7 SA strategies |

**7 Standalone-capable strategies**:
- S01_STAT_ARB (magic 1001)
- S06_KAMA (magic 1006)
- S07_MEAN_REVERSION (magic 1007)
- S10_TURTLE (magic 1010)
- S14_BB_SQUEEZE (magic 1014)
- S15_GRID (magic 1015)
- S16_SPIKE (magic 1016)

---

## 1.3 ZMQ Communication Layer

### Port 7777 — Tick Data Channel

```
FeederEA (MQL5)                    Brain (Python)
     │                                  │
     │  ZMQ_PUB connect()               │  ZMQ_SUB bind()
     │  "tcp://127.0.0.1:7777"          │  "tcp://127.0.0.1:7777"
     │                                  │
     │──── msgpack Array[7] ──────────▶│
     │  [1, seq, ts_ms, sym, bid, ask, flags]
     │                                  │
     │  ~60-80 bytes per tick           │
     │  ~80 ticks/sec (4 sym × 50ms)   │
```

**ทำไม FeederEA `connect()` ไม่ใช่ `bind()`?**
> Brain เป็น server ที่รับ connection หลายตัว (`bind`) ส่วน FeederEA เป็น client ที่ส่งข้อมูลเข้ามา (`connect`) — Pattern นี้ทำให้สามารถมีหลาย Feeder ส่งข้อมูลมาที่ Brain เดียวได้

---

### Port 7778 — Policy Channel

```
Brain (Python)                     ProgramC_Trader (MQL5)
     │                                  │
     │  ZMQ_PUB bind()                  │  ZMQ_SUB connect()
     │  "tcp://127.0.0.1:7778"          │  "tcp://127.0.0.1:7778"
     │                                  │
     │──── msgpack Array[11] ─────────▶│
     │  [10, ts, sym, strategy, entry,  │
     │   lot, max_orders, tp, sl,       │
     │   confidence, risk_mult]         │
     │                                  │
     │  msg_type ที่ส่งผ่าน 7778:       │
     │  10 = CONFIG_PUSH (policy)       │
     │  12 = INITIAL_CONFIG (reconnect) │
     │  13 = SWITCH_STANDALONE          │
     │  30 = HEARTBEAT                  │
     │  31 = EMERGENCY_COMMAND          │
     │  40 = STRATEGY_UPDATE            │
     │  50 = DIAGNOSTIC_REQUEST         │
     │  99 = SHUTDOWN                   │
```

---

### Port 7779 — Feedback Channel

```
ProgramC_Trader (MQL5)             Brain (Python)
     │                                  │
     │  ZMQ_PUSH connect()              │  ZMQ_PULL bind()
     │  "tcp://127.0.0.1:7779"          │  "tcp://127.0.0.1:7779"
     │                                  │
     │──── msgpack Array[12] ─────────▶│
     │  [100, ts, ticket, sym, type,    │
     │   volume, open_price, sl, tp,    │
     │   profit, magic, comment]        │
     │                                  │
     │  msg_type 100 = TRADE_REPORT     │
     │  ส่งทุกครั้งที่: order filled,  │
     │  order closed, SL/TP hit         │
```

**ทำไมใช้ PUSH/PULL แทน PUB/SUB สำหรับ feedback?**
> PUSH/PULL มี **guaranteed delivery** และ **load balancing** — ข้อมูล feedback ไม่ควรหาย เพราะใช้ adjust `risk_multiplier` ใน Brain

---

## 1.4 Data Flow Diagram Level 0

```
                    ┌──────────────────────────────────────────────┐
                    │                                              │
  [Broker]          │  ┌──────────┐    7777     ┌─────────────┐  │
     │              │  │ FeederEA │────PUB──────▶│             │  │
     │ Tick stream  │  │          │             │   Brain     │  │
     └─────────────▶│  │ 50ms     │             │             │  │
                    │  │ 4 symbols│             │  Analyze    │  │
                    │  └──────────┘             │  + Policy   │  │
                    │                           │             │  │
                    │  ┌──────────┐    7778     │             │  │
                    │  │          │◀────SUB──────│             │  │
  [Broker]          │  │ Trader   │             └─────────────┘  │
     ▲              │  │          │                    ▲          │
     │ Orders       │  │ 100ms    │      7779          │          │
     └──────────────│  │ 16 Strat │────PUSH────────────┘          │
                    │  └──────────┘   Feedback                    │
                    │                                              │
                    └──────────────────────────────────────────────┘
                                   Single Machine
```

### Data Stores (In-Memory)

| Data Store | Location | ชนิดข้อมูล | Purpose |
|------------|----------|------------|---------|
| `tick_history` | Brain / engine.py | `defaultdict(deque(500))` | rolling tick buffer per symbol |
| `policy_cooldown` | Brain / engine.py | `dict[str, float]` | timestamp ส่ง policy ล่าสุด |
| `risk_multiplier` | Brain / engine.py | `float` | ปรับ lot ตาม feedback |
| `g_strategy_table` | Trader | `SStrategyInfo[16]` | metadata ทุก strategy |
| `standalone_config.dat` | Trader / disk | INI text | backup params เมื่อ Brain หาย |

---

## 1.5 Timing Logic — ความถี่การแลกเปลี่ยนข้อมูล

### ตาราง Timing ทุก Component

| Component | File | Trigger | ความถี่ | Action |
|-----------|------|---------|---------|--------|
| FeederEA | FeederEA.mq5 | `OnTimer()` | **50ms** | ส่ง tick 4 symbols → port 7777 |
| Ingestion Worker | ingestion.py | recv loop | **~1ms** (RCVTIMEO=1000ms) | parse tick → ingestion_queue |
| Strategy Engine | engine.py | queue.get | **per tick** | normalize → score → policy |
| Policy Cooldown | engine.py | per symbol | **min 10s** | ป้องกัน policy flood |
| ProgramC_Trader | Trader.mq5 | `OnTimer()` | **100ms** | poll 20 msg + OnTick + check heartbeat |
| Execution Listener | execution_listener.py | recv loop | **~1ms** | parse feedback → feedback_queue |
| Emergency System | emergency_system.py | background | **1s** | check 9 conditions |
| System Monitor | system_monitor.py | background | **1s** | snapshot CPU/RAM/latency |
| Live Dashboard | dashboard.py | background | **1s** | refresh terminal UI |
| ConnectionMonitor | ConnectionMonitor.mqh | per OnTimer | **100ms** | check heartbeat elapsed |
| Heartbeat Warn | ConnectionMonitor.mqh | threshold | **@20s** | log warning |
| Heartbeat Timeout | ConnectionMonitor.mqh | threshold | **@30s** | switch Standalone |

### Timeline ใน 1 วินาที (1000ms)

```
ms:   0    100   200   300   400   500   600   700   800   900  1000
      │    │     │     │     │     │     │     │     │     │    │
FDR:  ●────●─────●─────●─────●─────●─────●─────●─────●─────●───●  20 OnTimer/sec
ING:  ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●  continuous
ENG:  ●    ●     ●     ●     ●     ●     ●     ●     ●     ●    ●  per tick
TDR:  ●    ●     ●     ●     ●     ●     ●     ●     ●     ●    ●  10 OnTimer/sec
EXL:  ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●  continuous
EMG:  │                                                        ●  1×/sec
MON:  │                                                        ●  1×/sec
DASH: │                                                        ●  1×/sec
```

**ปริมาณข้อมูล (throughput ประมาณ)**:
- Tick messages: 4 symbols × 20/sec = **~80 ticks/sec**
- Policy messages: สูงสุด 4 symbols ÷ 10s cooldown = **~0.4 policies/sec**
- Feedback messages: ขึ้นกับ trade frequency (**1–10/min โดยปกติ**)

---

## 1.6 Protocol — MessagePack Binary Serialization

### ทำไมใช้ MessagePack แทน JSON?

| ข้อเปรียบเทียบ | JSON | MessagePack |
|----------------|------|-------------|
| ขนาด tick message | ~180 bytes | ~60-80 bytes |
| ขนาด policy message | ~200 bytes | ~80-120 bytes |
| Parse speed | ~5-10µs | ~0.5-1µs |
| Human-readable | ✅ Yes | ❌ No |
| Schema-free | ✅ Yes | ✅ Yes |
| Cross-language | ✅ Yes | ✅ Yes |

> **ผลลัพธ์**: ประหยัดแบนด์วิดธ์ ~55% และ parse เร็วกว่า ~10× — สำคัญมากเมื่อรับ 80 ticks/sec ตลอดเวลา

### Message Type Registry (V6 Protocol)

| msg_type | ชื่อ | Direction | ขนาด (bytes) |
|----------|------|-----------|--------------|
| 1 | TICK_V6 | Feeder→Brain | 60-80 |
| 10 | CONFIG_PUSH | Brain→Trader | 80-120 |
| 12 | INITIAL_CONFIG | Brain→Trader | ~100 |
| 13 | SWITCH_STANDALONE | Brain→Trader | ~20 |
| 30 | HEARTBEAT | Brain→Trader | ~30 |
| 31 | EMERGENCY_COMMAND | Brain→Trader | ~50 |
| 40 | STRATEGY_UPDATE | Brain→Trader | ~150 |
| 50 | DIAGNOSTIC_REQUEST | Brain→Trader | ~20 |
| 99 | SHUTDOWN | Brain→Trader | ~10 |
| 100 | TRADE_REPORT | Trader→Brain | 100-130 |

---

## 1.7 ไฟล์และโครงสร้าง Directory

```
FlashEASuite_V2/
│
├── 01_Feeder/
│   └── Src/
│       └── FeederEA.mq5               ← Program A: ส่ง tick
│
├── 02_Brain/
│   ├── main.py                        ← Program B: Orchestrator
│   └── core/
│       ├── ingestion.py               ← Worker 1: รับ tick
│       ├── execution_listener.py      ← Worker 3: รับ feedback
│       ├── emergency_system.py        ← Worker 4: ตรวจ risk
│       ├── system_monitor.py          ← Worker 5: CPU/RAM
│       └── strategy/
│           ├── engine.py              ← Worker 2: คำนวณ + ส่ง policy
│           ├── analysis.py            ← วิเคราะห์ตลาด
│           └── policy.py              ← สร้าง policy Array[11]
│
├── 03_Trader/
│   └── ProgramC_Trader.mq5            ← Program C: Execute trades
│
└── Include/
    ├── Logic/
    │   ├── StrategyConstants.mqh      ← ตาราง 16 strategies + regime
    │   ├── ConnectionMonitor.mqh      ← Heartbeat tracker
    │   └── ConfigReceiver.mqh         ← รับ policy จาก Brain
    ├── Network/Protocol/
    │   └── Definitions.mqh            ← SDynamicParams, enums, structs
    └── Risk/
        └── RiskGuardian.mqh           ← 4-gate trade validation
```

---

*ต่อไป: [Section 2 — Brain Logic & Multi-Dimensional Matrix](SECTION2_BRAIN_LOGIC.md)*
