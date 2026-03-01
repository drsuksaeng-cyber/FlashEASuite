# 🏁 FlashEASuite V2 — First Day Runbook (P9-4)

**Version:** 1.0  
**Date:** 2026-02-26  
**Author:** Dr. Suksaeng Kukanok  
**Save:** `FlashEASuite_V2/docs/first_day_runbook.md`

---

## 📖 สารบัญ

1. [เปิดระบบ Step-by-Step](#1-เปิดระบบ-step-by-step)
2. [ตรวจสอบว่าระบบทำงาน](#2-ตรวจสอบว่าระบบทำงาน)
3. [ปิดระบบ Emergency](#3-ปิดระบบ-emergency)
4. [Troubleshooting Checklist](#4-troubleshooting-checklist)
5. [Daily Operations](#5-daily-operations)
6. [คำแนะนำสำหรับวันแรก](#6-คำแนะนำสำหรับวันแรก)

---

## 1. เปิดระบบ Step-by-Step

### 🕗 เวลาเริ่มต้น: 5-10 นาทีก่อนตลาดเปิด

> **ลำดับสำคัญ: MT5 → Brain → FeederEA → Trader → Monitor**

### Step 1: เปิด MetaTrader 5 (1 นาที)

```
1. Double-click MT5 icon
2. รอจน login สำเร็จ (ดูขวาล่าง: สถานะ connection)
3. ตรวจ: Market Watch มี symbols ที่ต้องการ
4. ตรวจ: AutoTrading button = สีเขียว (enabled)
```

**✅ เมื่อเห็น:** Status bar แสดง `xx/xx KB` (มี data flow) = MT5 พร้อม

### Step 2: เปิด Python Brain (1 นาที)

```cmd
cd C:\Users\<YOU>\...\MQL5\Experts\FlashEASuite_V2\
start_flashea.bat
```

**✅ เมื่อเห็น:**
```
✅ Ingestion Worker started
✅ Strategy Engine started  
✅ Execution Listener started
🚀 All workers started successfully (3 threads)
🎯 System is running with FEEDBACK LOOP enabled!
```

> 💡 **Tip:** ถ้า Brain เปิดแล้วแต่ MT5 ยังไม่เปิด → Brain จะรอ ticks อยู่ (ไม่ crash)

### Step 3: Attach FeederEA (1 นาที)

> ⚠️ **ข้ามขั้นนี้ถ้า EA ถูก attach ไว้แล้วจาก session ก่อนหน้า**  
> (MT5 จำ EA ที่ attach ไว้ cross-session)

```
1. เปิด chart สำหรับ FeederEA (เช่น EURUSD M1)
2. Navigator (Ctrl+N) → Expert Advisors → FlashEASuite_V2 → ...
3. ลาก FeederEA ไปวางบน chart
4. Dialog box → Inputs tab:
   - Timer: 50 (ms)
5. Common tab: ✅ Allow DLL imports
6. กด OK
```

**✅ เมื่อเห็น (Experts tab):**
```
✅ ZMQ PUB bound to tcp://*:7777
✅ Broadcasting on 4 symbols
```

### Step 4: Attach ProgramC_Trader (1 นาที)

> ⚠️ **ใช้ chart คนละ chart กับ FeederEA** (MT5 รองรับ 1 EA ต่อ 1 chart)

```
1. เปิด chart ใหม่ (เช่น GBPUSD M5)
2. ลาก ProgramC_Trader ไปวางบน chart
3. Inputs tab:
   - SYMBOL_SUFFIX: ใส่ตาม broker (เช่น ".tp")
   - V6_EnableMode: false (ใช้ legacy mode)
4. Common tab: ✅ Allow DLL imports, ✅ Allow algo trading
5. กด OK
```

**✅ เมื่อเห็น (Experts tab):**
```
✅ ZMQ Hub created
✅ Subscribed to tcp://127.0.0.1:7778
✅ Grid Strategy added to Council
✅ Spike Hunter Strategy added to Council
ProgramC_Trader V2.12 READY
```

### Step 5: เปิด Health Monitor (optional, 30 วินาที)

เปิด Command Prompt ใหม่:
```cmd
cd C:\...\FlashEASuite_V2\
python tools\health_monitor.py
```

**✅ เมื่อเห็น:**
```
🟢 Python Brain        UP
🟢 MetaTrader 5        UP
🟢 Port 7777           LISTENING
🟢 Port 7778           LISTENING
```

### Step 6: Verify Data Flow (2 นาที)

ดูที่ Brain console window:
```
✅ ควรเห็น tick count เพิ่มขึ้นเรื่อยๆ
✅ Dashboard แสดง symbols ที่กำลังรับ data
✅ ไม่มี error messages สีแดง
```

---

## 2. ตรวจสอบว่าระบบทำงาน

### Quick Check (30 วินาที)

```cmd
start_flashea.bat status
```

Output ที่คาดหวัง:
```
  Python Brain:     [RUNNING]
  MetaTrader 5:     [RUNNING]
  Port 7777:        [LISTENING]
  Port 7778:        [LISTENING]
  Port 7779:        [FREE]        ← OK ถ้า Trader ใช้ connect ไม่ใช่ bind
```

### Deep Check

| ตรวจอะไร | วิธีตรวจ | ค่าที่คาดหวัง |
|----------|---------|---------------|
| Brain ticks | Brain console → Dashboard | Tick count เพิ่มขึ้น |
| FeederEA | MT5 → Experts tab | "Broadcasting" messages |
| Trader | MT5 → Experts tab | "Waiting for policies" หรือ "Policy received" |
| Memory | Task Manager → Python | < 300 MB |
| CPU | Task Manager → Python | < 15% |
| Latency | Brain console → Dashboard | p50 < 10ms |

### Brain Dashboard (ทุก 10 วินาที)

Brain จะแสดง dashboard อัตโนมัติ:
```
══════════════════════════════════════════════════
📊 STRATEGY ENGINE DASHBOARD v2.3
══════════════════════════════════════════════════
Ticks Processed:    1,234
Policies Sent:      5
Risk Multiplier:    1.00x

Symbol Mapping:
  XAUUSD.tp        → XAUUSD    (1234 ticks)
  EURUSD.tp        → EURUSD    (856 ticks)

Top 5 Symbols (Spike Score):
  1. XAUUSD      :  45.30 ⏳ Below
  2. GBPUSD      :  32.10 ⏳ Below
══════════════════════════════════════════════════
```

---

## 3. ปิดระบบ Emergency

### 🔴 Level 1: ปิด Trading ทันที (5 วินาที)

```
MT5 → กดปุ่ม AutoTrading (ให้เป็นสีแดง)
```
→ EA ทั้งหมดหยุดเทรด แต่ยังทำงานอยู่ (ไม่ส่ง order ใหม่)

### 🔴 Level 2: ปิด EA (30 วินาที)

```
1. MT5 → chart ที่มี Trader → Right-click → Expert Advisors → Remove
2. MT5 → chart ที่มี FeederEA → Right-click → Expert Advisors → Remove
```
→ EA ถูกถอดออก, ZMQ connections ปิด

### 🔴 Level 3: ปิดทั้งระบบ (1 นาที)

```cmd
:: ปิด Brain
start_flashea.bat stop

:: ปิด Health Monitor
Ctrl+C ที่ console window

:: ปิด MT5
ปิด MetaTrader 5 ตามปกติ
```

### 🔴 Level 4: Force Kill ทุกอย่าง (Emergency)

```cmd
:: Kill Python (ทุก process)
taskkill /im python.exe /f

:: Kill MT5
taskkill /im terminal64.exe /f
```

> ⚠️ **หลัง Force Kill:** ต้อง restart ทั้งระบบใหม่ตามลำดับใน Step 1-6

### ปิด Positions ที่เปิดอยู่

```
MT5 → Trade tab (ล่างสุด) → Right-click position → Close Position
หรือ Close All: Right-click → Close All Positions
```

---

## 4. Troubleshooting Checklist

### 🔧 ปัญหา: Brain ไม่เริ่ม

| ตรวจ | คำสั่ง | แก้ไข |
|------|--------|-------|
| Python installed? | `python --version` | ติดตั้ง Python 3.8+ |
| Dependencies? | `pip list \| find "zmq"` | `pip install pyzmq msgpack` |
| Port conflict? | `netstat -ano \| find "7778"` | Kill process ที่ใช้ port |
| Path ถูก? | `dir 02_Brain\main.py` | ตรวจว่ารันจาก root folder |

**Quick fix:**
```cmd
start_flashea.bat doctor
```

### 🔧 ปัญหา: FeederEA ไม่ broadcast ticks

| ตรวจ | สาเหตุ | แก้ไข |
|------|--------|-------|
| EA มี icon? | ไม่ได้ attach | ลาก EA ใหม่ |
| Icon เป็นหน้ายิ้ม? | Algo trading OFF | กดปุ่ม AutoTrading |
| Experts tab มี error? | Compile error | Recompile จาก MetaEditor |
| "DLL not found"? | ไม่มี libzmq.dll | Copy ไป MQL5/Libraries/ |

### 🔧 ปัญหา: Trader ไม่รับ policy

| ตรวจ | สาเหตุ | แก้ไข |
|------|--------|-------|
| Brain running? | Brain ปิดอยู่ | `start_flashea.bat` |
| Port 7778 listening? | Brain ไม่ได้ bind | Restart Brain |
| Symbol suffix ถูก? | SYMBOL_SUFFIX ผิด | แก้ input ของ Trader EA |
| Tick data? | FeederEA ไม่ทำงาน | ตรวจ FeederEA |

### 🔧 ปัญหา: "Access violation" หรือ memory leak

```
⚠️ S16_Spike memory leak (11,520 bytes) ยังไม่ได้แก้
→ ถ้าเกิด: Remove Trader EA → Restart MT5 → Re-attach
→ ห้ามรัน optimization จนกว่าจะแก้ (ดู P9-4 task list)
```

### 🔧 ปัญหา: Port ถูกใช้อยู่แล้ว

```cmd
:: หา process ที่ใช้ port
netstat -ano | find "7778"

:: Output: TCP 0.0.0.0:7778 0.0.0.0:0 LISTENING 12345
::                                                 ^^^^^ PID

:: Kill process
taskkill /pid 12345 /f
```

### 🔧 ปัญหา: Compile error ใน MetaEditor

```
ดู Lessons Learned:
1. MISTAKE 1 (P9-1): ห้ามใช้ #if compound → ใช้ #ifdef/#ifndef
2. MISTAKE 2 (P9-1): Compile จาก MetaEditor Navigator เท่านั้น
3. MISTAKE 1 (P8-4): ดู tree ก่อนเขียน #include ทุกครั้ง
```

---

## 5. Daily Operations

### 🌅 เช้า (ก่อนตลาดเปิด)

```
1. ตรวจว่า MT5 เปิดอยู่ + connected
2. ตรวจว่า Brain running: start_flashea.bat status
3. ตรวจ health.log: ดูว่าคืนมีปัญหาไหม
4. ตรวจ account balance + margin
5. ตรวจข่าว: หลีกเลี่ยงเทรดช่วง high-impact news
```

### 🌆 เย็น (หลังตลาดปิด)

```
1. ตรวจ trade journal: MT5 → Account History
2. ดู Brain dashboard: tick count, policy count
3. ตรวจ memory usage: Task Manager
4. Review health.log สำหรับ warnings
5. ไม่ต้องปิดระบบ (ให้ทำงานต่อเนื่อง)
```

### 📅 Weekly

```
1. Restart Brain สัปดาห์ละครั้ง (clear memory)
   start_flashea.bat stop
   start_flashea.bat
2. Review performance: win rate, drawdown
3. Backup: copy FlashEASuite_V2 folder
4. ตรวจ disk space: logs/ folder
5. Update MT5 ถ้ามี update
```

---

## 6. คำแนะนำสำหรับวันแรก

### 🎯 Do's

- ✅ **เริ่มด้วย Demo account** — ทดสอบอย่างน้อย 1 สัปดาห์
- ✅ **ใช้ lot size เล็ก** — 0.01 lot จนกว่าจะมั่นใจ
- ✅ **เปิด Health Monitor** — ให้ตรวจตลอด
- ✅ **อ่าน Brain console** — ดูว่า tick count เพิ่มปกติ
- ✅ **จด trade journal** — บันทึกทุกวัน
- ✅ **ตั้ง Daily Loss Limit** — RiskGuardian ตั้งไว้ 2% แล้ว

### 🚫 Don'ts

- ❌ **อย่าเริ่ม Live โดยไม่ผ่าน Demo** 
- ❌ **อย่ารัน Optimization** — S16_Spike memory leak ยังไม่แก้
- ❌ **อย่าแก้โค้ดขณะระบบทำงาน** — ปิด EA ก่อน
- ❌ **อย่าเพิ่ม lot size โดยไม่ดู performance** 
- ❌ **อย่าปิด Brain ระหว่างที่มี open positions**
- ❌ **อย่าเพิกเฉย Health Monitor warnings**

### ⏰ เวลาตลาด (GMT+7 Bangkok)

| Session | เวลา (ไทย) | คู่เงินที่ active |
|---------|-----------|------------------|
| Sydney | 04:00-13:00 | AUD, NZD |
| Tokyo | 06:00-15:00 | JPY pairs |
| London | 14:00-23:00 | EUR, GBP (volatile!) |
| New York | 19:00-04:00 | USD (most volatile!) |
| **London+NY overlap** | **19:00-23:00** | **Best time ✅** |

### 📊 สิ่งที่ควรดูใน Dashboard

| Metric | ค่าปกติ | สัญญาณเตือน |
|--------|---------|-------------|
| Tick count | เพิ่มเรื่อยๆ | หยุดนิ่ง = connection lost |
| Policy sent | 0-10 ต่อชม. | >50 ต่อชม. = อาจ overtrade |
| Spike score | 0-100 | >70 = spike detected |
| Memory (Python) | 100-200 MB | >500 MB = possible leak |
| CPU (Python) | 5-10% | >30% = performance issue |

---

## 📋 Quick Reference Card

```
╔══════════════════════════════════════════════════╗
║           FlashEASuite V2 Quick Reference        ║
╠══════════════════════════════════════════════════╣
║                                                  ║
║  START:   start_flashea.bat                      ║
║  STATUS:  start_flashea.bat status               ║
║  STOP:    start_flashea.bat stop                 ║
║  DOCTOR:  start_flashea.bat doctor               ║
║  MONITOR: python tools\health_monitor.py         ║
║                                                  ║
║  EMERGENCY:                                      ║
║  Level 1: MT5 → AutoTrading OFF (red button)     ║
║  Level 2: Remove EA from charts                  ║
║  Level 3: start_flashea.bat stop + close MT5     ║
║  Level 4: taskkill /im python.exe /f             ║
║                                                  ║
║  PORTS:                                          ║
║  7777 = FeederEA → Brain (tick data)             ║
║  7778 = Brain → Trader (policies)                ║
║  7779 = Trader → Brain (feedback)                ║
║                                                  ║
║  LOGS:                                           ║
║  logs/health.log = Health monitor                ║
║  MT5 → Experts tab = EA messages                 ║
║  Brain console = Python output                   ║
║                                                  ║
╚══════════════════════════════════════════════════╝
```

---

*First Day Runbook V1.0 — P9-4*
