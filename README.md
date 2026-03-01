# FlashEASuite V2

**Algorithmic Trading System — "Smart Server, Powerful Client"**

Version: 2.1.0 | Phase: P9-5 (Production Ready) | Updated: 2026-03-01
Author: Dr. Suksaeng Kukanok

---

## ภาพรวม

FlashEASuite V2 คือระบบเทรดอัลกอริทึมที่แบ่งความรับผิดชอบระหว่าง **Python Brain** (วิเคราะห์ตลาด) กับ **MQL5 Trader** (execute คำสั่ง) โดยสื่อสารกันผ่าน ZeroMQ บน localhost

```
FeederEA.mq5  ──PUB 7777──▶  main.py (Brain)  ──PUB 7778──▶  ProgramC_Trader.mq5
                                    ▲                                    │
                                    └────────────PUSH 7779───────────────┘
```

| Program | ภาษา | บทบาท |
|---------|------|------|
| **FeederEA.mq5** | MQL5 | ส่ง tick data 4 symbols @ 50ms |
| **main.py** | Python 3 | วิเคราะห์ตลาด, คำนวณ policy, monitor risk |
| **ProgramC_Trader.mq5** | MQL5 | รับ policy, execute trades, ส่ง feedback |

---

## ฟีเจอร์หลัก

- **16 Strategies** ครอบคลุม 4 market regimes (Trending / Ranging / Volatile / Squeeze)
- **19 Money Managers** ปรับ lot size แบบ dynamic
- **Feedback Loop** — `risk_multiplier` ปรับอัตโนมัติตามผลการเทรด
- **Emergency System** — 9 conditions, 4 levels (NORMAL / WARNING / PAUSE / HALT)
- **Standalone Mode** — 7 strategies ทำงานได้แม้ Brain ไม่อยู่
- **Hot-reload parameters** — Brain ส่ง params ใหม่โดยไม่ต้อง restart EA
- **MessagePack protocol** — ~60-80 bytes/message (เร็วกว่า JSON 10×)

---

## โครงสร้าง Project

```
FlashEASuite_V2/
│
├── 01_Feeder/
│   └── Src/FeederEA.mq5              # Program A — ส่ง tick
│
├── 02_Brain/
│   ├── main.py                       # Program B — Orchestrator (6 threads)
│   ├── requirements.txt
│   └── core/
│       ├── ingestion.py              # Worker 1: รับ tick ZMQ SUB :7777
│       ├── execution_listener.py     # Worker 3: รับ feedback ZMQ PULL :7779
│       ├── emergency_system.py       # Worker 4: monitor ทุก 1s
│       ├── system_monitor.py         # Worker 5: CPU/RAM/latency
│       └── strategy/
│           ├── engine.py             # Worker 2: score + policy (v2.3)
│           ├── analysis.py           # Market analysis
│           └── policy.py             # Policy generator
│
├── 03_Trader/
│   └── ProgramC_Trader.mq5           # Program C — Execute (v2.13)
│
├── Include/
│   ├── Logic/
│   │   ├── StrategyConstants.mqh     # 16 strategies table + regime map
│   │   ├── ConnectionMonitor.mqh     # Heartbeat tracking (timeout 30s)
│   │   └── ConfigReceiver.mqh        # รับ policy จาก Brain
│   ├── Network/Protocol/
│   │   └── Definitions.mqh           # SDynamicParams, enums, V6 structs
│   ├── Risk/
│   │   └── RiskGuardian.mqh          # 4-gate trade validation
│   └── Zmq/                          # ZMQ bindings for MQL5
│
└── docs/                             # เอกสารทั้งหมด → ดู docs/README.md
```

---

## เริ่มต้นใช้งาน

### 1. ติดตั้ง Python dependencies

```bash
cd 02_Brain
pip install -r requirements.txt
# หลัก: pyzmq, msgpack, psutil
```

### 2. เปิด MetaTrader 5

- Compile `01_Feeder/Src/FeederEA.mq5`
- Compile `03_Trader/ProgramC_Trader.mq5`

### 3. เปิดระบบ (ลำดับสำคัญ)

```
1. รัน Brain ก่อน:
   cd 02_Brain
   python main.py

2. Attach FeederEA บน chart ใดก็ได้ใน MT5

3. Attach ProgramC_Trader บน chart ใดก็ได้ใน MT5
```

### 4. ตรวจสอบการทำงาน

```
Python console ควรแสดง:
  ✅ Ingestion Worker  → tcp://127.0.0.1:7777
  ✅ Strategy Engine   → tcp://127.0.0.1:7778
  ✅ Execution Listener← tcp://127.0.0.1:7779
  ✅ Emergency Monitor (check every 1.0s)
  ✅ All 3 worker threads started

MT5 Experts log ควรแสดง:
  [ConnectionMonitor] Initialized | timeout=30s
  [Trader] Switching to STANDALONE mode   ← รอ Brain connect
  [Trader] RECONNECTED — Online Mode      ← Brain connect แล้ว
```

---

## ZMQ Ports

| Port | Pattern | Direction | ข้อมูล |
|------|---------|-----------|--------|
| **7777** | PUB / SUB | Feeder → Brain | Tick `Array[7]` msgpack |
| **7778** | PUB / SUB | Brain → Trader | Policy `Array[11]` msgpack |
| **7779** | PUSH / PULL | Trader → Brain | Feedback `Array[12]` msgpack |

---

## 16 Strategies

| ID | Magic | ชื่อ | Standalone | Best Regime |
|----|-------|------|------------|-------------|
| S01 | 1001 | Statistical Arbitrage | ✅ | RANGING |
| S02 | 1002 | ML Ensemble | ❌ | ALL |
| S03 | 1003 | Smart Money Concepts | ❌ | TRENDING |
| S04 | 1004 | Market Profile | ❌ | RANGING |
| S05 | 1005 | Supply & Demand | ❌ | RANGING |
| S06 | 1006 | KAMA Adaptive MA | ✅ | TRENDING |
| S07 | 1007 | Mean Reversion | ✅ | RANGING |
| S08 | 1008 | Intermarket Analysis | ❌ | TRENDING |
| S09 | 1009 | Session Breakout | ❌ | VOLATILE |
| S10 | 1010 | Turtle Trading | ✅ | TRENDING |
| S11 | 1011 | Ichimoku Cloud | ❌ | TRENDING |
| S12 | 1012 | Price Action | ❌ | TRENDING |
| S13 | 1013 | Fibonacci + Stochastic | ❌ | RANGING |
| S14 | 1014 | BB Squeeze | ✅ | SQUEEZE |
| S15 | 1015 | Grid Trading | ✅ | RANGING |
| S16 | 1016 | Spike Momentum | ✅ | VOLATILE |

---

## Emergency Thresholds

| Condition | ค่า | ผลลัพธ์ |
|-----------|-----|---------|
| Max Drawdown | > 20% | HALT |
| Daily Loss | > 5% | HALT |
| Consecutive Losses | ≥ 5 trades | PAUSE 60 นาที |
| CPU หรือ RAM | > 90% | WARNING |
| Heartbeat Timeout | > 30s | → Standalone Mode |

---

## เอกสาร

ดู **[docs/README.md](docs/README.md)** สำหรับ index เอกสารทั้งหมด

| เอกสาร | ลิงก์ |
|--------|------|
| ภาพรวมสถาปัตยกรรม | [docs/SECTION1_SYSTEM_ARCHITECTURE.md](docs/SECTION1_SYSTEM_ARCHITECTURE.md) |
| Brain Logic (Python) | [docs/SECTION2_BRAIN_LOGIC.md](docs/SECTION2_BRAIN_LOGIC.md) |
| Execution (MQL5) | [docs/SECTION3_EXECUTION_STRATEGY.md](docs/SECTION3_EXECUTION_STRATEGY.md) |
| ปรัชญาการออกแบบ | [docs/SECTION4_PHILOSOPHY.md](docs/SECTION4_PHILOSOPHY.md) |
| Diagrams (Mermaid) | [docs/SECTION5_DIAGRAM_READY_SUMMARY.md](docs/SECTION5_DIAGRAM_READY_SUMMARY.md) |
| คู่มือติดตั้ง | [docs/INSTALLATION_GUIDE.md](docs/INSTALLATION_GUIDE.md) |
| คู่มือการใช้งาน | [docs/guides/05_OperationManual.md](docs/guides/05_OperationManual.md) |
| แก้ปัญหา | [docs/guides/08_TroubleshootingGuide.md](docs/guides/08_TroubleshootingGuide.md) |
| Emergency Procedures | [docs/guides/09_EmergencyProcedures.md](docs/guides/09_EmergencyProcedures.md) |

---

## Requirements

| ส่วน | Requirement |
|------|------------|
| OS | Windows 10/11 |
| Python | 3.8+ |
| MetaTrader | MetaTrader 5 (build 3000+) |
| Python packages | `pyzmq`, `msgpack`, `psutil` |
| MQL5 libs | ZMQ bindings (`Include/Zmq/`) |

---

## Status

```
Phase P9-5: COMPLETE (2026-02-27)
Validation:  56/57 PASS
Production:  Ready ✅
```
