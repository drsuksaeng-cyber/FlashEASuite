# 📋 FlashEASuite V2 — Deployment Checklist (P9-4)

**Version:** 1.0  
**Date:** 2026-02-26  
**Author:** Dr. Suksaeng Kukanok  
**Save:** `FlashEASuite_V2/docs/deployment_checklist.md`

---

## 🔧 สิ่งที่ต้องเตรียมก่อน Deploy

### A. Software Requirements

| Software | Version | ตรวจสอบ | หมายเหตุ |
|----------|---------|---------|----------|
| Windows 10/11 | 64-bit | ☐ | Server หรือ VPS |
| MetaTrader 5 | Build 3770+ | ☐ | `Help → About` ดู build number |
| Python | 3.8+ (แนะนำ 3.10) | ☐ | `python --version` |
| pip | ล่าสุด | ☐ | `pip --version` |

### B. Python Dependencies

```bash
# ติดตั้งทั้งหมดในครั้งเดียว
pip install pyzmq msgpack numpy pandas

# ตรวจสอบ
python -c "import zmq, msgpack; print('OK:', zmq.__version__, msgpack.version)"
```

| Package | ใช้งาน | ตรวจสอบ |
|---------|--------|---------|
| pyzmq | ZeroMQ messaging | ☐ |
| msgpack | MessagePack serialization | ☐ |
| numpy | Numerical computation | ☐ |
| pandas | Data manipulation | ☐ |

### C. Broker Account

| รายการ | ค่า | ตรวจสอบ |
|--------|-----|---------|
| Broker name | _________ | ☐ |
| Account type | Demo / Live | ☐ |
| Symbol suffix | `.tp` / `_m` / (ว่าง) | ☐ |
| Leverage | _________ | ☐ |
| Minimum lot | _________ | ☐ |
| Allow algo trading | ✅ enabled | ☐ |

---

## 📁 ขั้นตอนที่ 1: วาง Files

### 1.1 Copy FlashEASuite_V2 ไปที่ MQL5/Experts/

```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Experts\FlashEASuite_V2\
```

**วิธีหา path:**
1. เปิด MetaEditor (F4 จาก MT5)
2. ดู title bar จะเห็น path เต็ม
3. หรือ `File → Open Data Folder` จาก MT5

☐ **Verify:** ตรวจว่ามีไฟล์เหล่านี้:

```
FlashEASuite_V2/
├── 01_Feeder/Src/FeederEA.mq5       ☐
├── 02_Brain/main.py                   ☐
├── 02_Brain/core/ingestion.py         ☐
├── 02_Brain/core/execution_listener.py ☐
├── 03_Trader/ProgramC_Trader.mq5      ☐
├── Include/Zmq/ZmqHub.mqh            ☐
├── Include/Logic/StrategyManager.mqh  ☐
├── Include/Logic/IStrategy.mqh        ☐
├── Include/Network/Protocol.mqh       ☐
├── Include/Risk/RiskGuardian.mqh      ☐
├── Include/MqlMsgPack.mqh             ☐
├── tools/health_monitor.py            ☐
└── start_flashea.bat                  ☐
```

### 1.2 Copy ZMQ DLLs ไปที่ Libraries/

```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Libraries\
```

ไฟล์ที่ต้องมี:
| File | ตรวจสอบ |
|------|---------|
| libzmq.dll | ☐ |
| libsodium.dll | ☐ |

### 1.3 Copy Include ลง MQL5 system (ถ้าจำเป็น)

```
MQL5/Include/MqlMsgPack.mqh   ☐ (ถ้ายังไม่มี)
```

---

## 🔨 ขั้นตอนที่ 2: Compile EA

### 2.1 Compile FeederEA

1. เปิด MetaEditor
2. Navigator → Experts → FlashEASuite_V2 → 01_Feeder → Src
3. Double-click `FeederEA.mq5`
4. กด **F7** (Compile)

☐ **Verify:** `0 errors, 0 warnings` (warnings อาจมีได้ แต่ต้อง 0 errors)

### 2.2 Compile ProgramC_Trader

1. Navigator → Experts → FlashEASuite_V2 → 03_Trader
2. Double-click `ProgramC_Trader.mq5`
3. กด **F7** (Compile)

☐ **Verify:** `0 errors`

> ⚠️ **สำคัญ:** ห้าม compile จากการเปิดไฟล์ผ่าน Windows Explorer  
> ต้องเปิดจาก Navigator ใน MetaEditor เท่านั้น (ดู Lesson P9-1 MISTAKE 2)

---

## ⚙️ ขั้นตอนที่ 3: ตั้งค่า MT5

### 3.1 Enable Algo Trading

1. MT5 → `Tools → Options → Expert Advisors`
2. ☐ Check: **Allow algorithmic trading**
3. ☐ Check: **Allow DLL imports**
4. กด OK

### 3.2 Enable AutoTrading

1. ดูที่ toolbar ว่ามีปุ่ม **AutoTrading** อยู่
2. ☐ กดให้เป็น **สีเขียว** (enabled)

### 3.3 ตั้งค่า Symbol ใน Market Watch

1. `View → Market Watch` (Ctrl+M)
2. Right-click → `Symbols`
3. เพิ่ม symbols ที่ต้องการ:

| Symbol | ตรวจสอบ |
|--------|---------|
| EURUSD (+ suffix) | ☐ |
| GBPUSD (+ suffix) | ☐ |
| USDJPY (+ suffix) | ☐ |
| XAUUSD (+ suffix) | ☐ |

### 3.4 เปิด Chart

1. เปิดอย่างน้อย 1 chart สำหรับ FeederEA
2. เปิดอย่างน้อย 1 chart สำหรับ ProgramC_Trader
3. ☐ Timeframe: M1 หรือ M5 (FeederEA ใช้ OnTimer ไม่ขึ้นกับ TF)

---

## 🚀 ขั้นตอนที่ 4: Start System

### ลำดับการเปิดที่ถูกต้อง:

```
1. เปิด MetaTrader 5                          ☐
2. เปิด Python Brain (start_flashea.bat)       ☐
3. Attach FeederEA ลง chart                    ☐
4. Attach ProgramC_Trader ลง chart              ☐
5. เปิด Health Monitor (optional)              ☐
```

### 4.1 Start Python Brain

```cmd
cd C:\...\FlashEASuite_V2\
start_flashea.bat
```

☐ **Verify:** เห็น output:
```
✅ Ingestion Worker started
✅ Strategy Engine started
✅ Execution Listener started
🚀 All workers started successfully (3 threads)
```

### 4.2 Attach FeederEA

1. Navigator → Expert Advisors → FlashEASuite_V2 → 01_Feeder → Src → FeederEA
2. ลากไปวางบน chart ที่เปิดไว้
3. ใน Input tab:
   - Timer interval: `50` (ms)
4. กด OK

☐ **Verify:** Tab "Experts" ใน Terminal แสดง:
```
✅ ZMQ PUB bound to tcp://*:7777
✅ Timer started (50ms)
```

### 4.3 Attach ProgramC_Trader

1. Navigator → Expert Advisors → FlashEASuite_V2 → 03_Trader → ProgramC_Trader
2. ลากไปวางบน chart **อีก chart หนึ่ง** (ไม่ใช่ chart เดียวกับ FeederEA)
3. ใน Input tab:

| Parameter | ค่า | หมายเหตุ |
|-----------|-----|----------|
| SYMBOL_PREFIX | (ว่าง) | ขึ้นกับ broker |
| SYMBOL_SUFFIX | `.tp` | ขึ้นกับ broker |
| V6_EnableMode | `false` | ใช้ legacy mode ก่อน |

4. กด OK

☐ **Verify:** Tab "Experts" แสดง:
```
✅ ZMQ Hub created
✅ Subscribed to tcp://127.0.0.1:7778
✅ PUB Socket connected to tcp://127.0.0.1:7779
✅ Grid Strategy added to Council
✅ Spike Hunter Strategy added to Council
```

### 4.4 Start Health Monitor (optional)

```cmd
cd C:\...\FlashEASuite_V2\
python tools\health_monitor.py
```

☐ **Verify:** Dashboard แสดง:
```
🟢 Python Brain        UP
🟢 MetaTrader 5        UP
🟢 Port 7777           LISTENING
🟢 Port 7778           LISTENING
```

---

## 🔄 ขั้นตอนที่ 5: ตั้งค่า Auto-Start (Task Scheduler)

### 5.1 Task: Start Python Brain on Login

1. เปิด Task Scheduler (`taskschd.msc`)
2. Create Task (ไม่ใช่ Basic Task)
3. **General tab:**
   - Name: `FlashEA_Brain_AutoStart`
   - ☐ Run only when user is logged on
   - ☐ Run with highest privileges
4. **Triggers tab:**
   - New → At log on → Your user account
   - Delay task for: `30 seconds` (รอ MT5 เปิดก่อน)
5. **Actions tab:**
   - Action: Start a program
   - Program: `C:\...\FlashEASuite_V2\start_flashea.bat`
   - Arguments: `brain`
   - Start in: `C:\...\FlashEASuite_V2\`
6. **Conditions tab:**
   - ☐ Uncheck "Start only if on AC power" (สำหรับ laptop)
7. กด OK

☐ **Verify:** Restart เครื่อง แล้วตรวจว่า Brain เริ่มอัตโนมัติ

### 5.2 Task: Health Monitor on Login

1. Create Task
2. Name: `FlashEA_HealthMonitor`
3. Trigger: At log on + Delay 60 seconds
4. Action:
   - Program: `python`
   - Arguments: `tools\health_monitor.py`
   - Start in: `C:\...\FlashEASuite_V2\`

### 5.3 MT5 Auto-Start

1. MT5 → `Tools → Options → Server`
2. ☐ Check: **Start on system startup** (ถ้ามี option นี้)
3. หรือ ใส่ shortcut ของ MT5 ไปที่:
   ```
   C:\Users\<YOU>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\
   ```

☐ **Verify:** Restart เครื่อง → MT5 เปิดอัตโนมัติ + EA ถูก attach อัตโนมัติ

> 💡 **Tip:** MT5 จะ auto-attach EA ที่ถูกวางไว้ก่อน restart (เก็บ state ไว้)

---

## ✅ Final Verification Checklist

| # | รายการ | วิธีตรวจ | ตรวจสอบ |
|---|--------|----------|---------|
| 1 | Python Brain running | `start_flashea.bat status` | ☐ |
| 2 | MT5 running | Task Manager | ☐ |
| 3 | FeederEA attached | MT5 → Experts tab | ☐ |
| 4 | Trader attached | MT5 → Experts tab | ☐ |
| 5 | Port 7777 listening | `netstat -an \| find "7777"` | ☐ |
| 6 | Port 7778 listening | `netstat -an \| find "7778"` | ☐ |
| 7 | Ticks flowing | Brain console shows tick count | ☐ |
| 8 | No compile errors | MetaEditor → 0 errors | ☐ |
| 9 | AutoTrading ON | MT5 toolbar → green button | ☐ |
| 10 | Health monitor logs | `logs/health.log` exists | ☐ |

---

## ⚠️ Known Issues ก่อน Deploy

| Issue | ความร้ายแรง | Status |
|-------|------------|--------|
| S16_Spike memory leak (11,520 bytes) | ⚠️ CRITICAL สำหรับ backtest | ยังไม่แก้ |
| DLLWrapper.mqh ใน STUB_MODE | ℹ️ ไม่มีผลต่อ trading | OK for now |

> ⚠️ **ห้ามรัน optimization หรือ backtest จนกว่าจะแก้ S16_Spike memory leak**  
> (ดู HANDOFF_P9_3.md สำหรับ P9-4 fix plan)

---

## 📞 Emergency Contacts

| สถานการณ์ | Action |
|-----------|--------|
| Brain crash | Health monitor auto-restart (max 3 ครั้ง) |
| Brain ไม่ restart | `start_flashea.bat stop` แล้ว `start_flashea.bat` |
| MT5 crash | Restart MT5 → EA จะ re-attach อัตโนมัติ |
| ปิดทุกอย่าง | `start_flashea.bat stop` → ปิด MT5 |
| Port conflict | `netstat -ano \| find "777"` หา PID แล้ว `taskkill /pid <PID> /f` |

---

*Deployment Checklist V1.0 — P9-4*
