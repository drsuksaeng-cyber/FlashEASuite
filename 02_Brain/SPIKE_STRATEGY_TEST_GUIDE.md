# 🧪 Spike Strategy - คู่มือการทดสอบ

**Version:** 1.0  
**Date:** 2026-02-06  
**Method:** Option B - Inject Fake Spike

---

## 📋 **ลำดับขั้นตอนการทดสอบ**

### **PHASE 1: เตรียมไฟล์ทดสอบ (5 นาที)**

#### **ขั้นตอนที่ 1.1: Copy ไฟล์ทดสอบ**

```bash
# ไฟล์ที่ต้อง copy:
spike_test_injector.py → 02_Brain/core/strategy/
```

**ตำแหน่งเต็ม:**
```
FlashEASuite_V2/
└── 02_Brain/
    └── core/
        └── strategy/
            └── spike_test_injector.py  ← ไฟล์นี้
```

#### **ขั้นตอนที่ 1.2: ตรวจสอบ Dependencies**

```bash
cd 02_Brain
pip install zmq msgpack --break-system-packages
```

**Expected Output:**
```
Requirement already satisfied: zmq
Requirement already satisfied: msgpack
```

---

### **PHASE 2: Setup ระบบ (3 นาที)**

#### **ขั้นตอนที่ 2.1: เปิด Python Brain**

```bash
# Terminal 1
cd 02_Brain
python main.py
```

**Expected Output:**
```
════════════════════════════════════════════════════════════
FlashEASuite V2 - Program B (The Brain) 🧠
High-Frequency Hybrid Trading System
WITH FEEDBACK LOOP 🔄
MODE: Threading (Windows Safe Mode)
════════════════════════════════════════════════════════════

🚀 Starting FlashEA Brain with Feedback Loop...
Configuration:
  - ZMQ Feeder (Tick Data):    tcp://127.0.0.1:7777
  - ZMQ Execution (Policy):    tcp://127.0.0.1:7778
  - ZMQ Feedback (Results):    tcp://127.0.0.1:7779

✅ Ingestion Worker started
✅ Strategy Engine started
✅ Execution Listener started

🚀 All workers started successfully (3 threads)
════════════════════════════════════════════════════════════
🎯 System is running with FEEDBACK LOOP enabled!
   🔥 Receiving tick data from Feeder
   🧠 Generating trading signals
   📤 Sending policies to Trader
   🔄 Receiving trade results (Feedback Loop)
════════════════════════════════════════════════════════════
```

✅ **ตรวจสอบ:** ต้องเห็นข้อความ "All workers started successfully"

---

#### **ขั้นตอนที่ 2.2: เปิด MT5 Terminal และ Attach ProgramC_Trader**

**2.2.1: เปิด MT5**
```
1. เปิด MetaTrader 5
2. Login เข้า Demo Account
3. เลือก Symbol: XAUUSD (Gold)
4. Timeframe: M1
```

**2.2.2: Attach ProgramC_Trader**
```
1. Navigator → Expert Advisors → ProgramC_Trader
2. Drag & Drop ลงบน XAUUSD M1 chart
3. กด OK (ใช้ค่า default)
```

**Expected Output (ใน Experts Tab):**
```
╔════════════════════════════════════════════════╗
║  ProgramC_Trader V2.12 - Initializing...     ║
╚════════════════════════════════════════════════╝
✅ ZMQ Hub created
✅ Subscribed to tcp://127.0.0.1:7778 (Python policies)
✅ PUB Socket connected to tcp://127.0.0.1:7779 (Feedback)
✅ Risk Guardian initialized
✅ Grid Strategy added to Council
✅ Spike Hunter Strategy added to Council  ← ต้องเห็นบรรทัดนี้!
✅ Symbol Scanner initialized
╔════════════════════════════════════════════════╗
║  ✅ SYSTEM READY - Waiting for Brain Policy  ║
╚════════════════════════════════════════════════╝
```

✅ **ตรวจสอบ:** ต้องเห็น "Spike Hunter Strategy added to Council"

---

### **PHASE 3: เริ่มทดสอบ (2 นาที)**

#### **ขั้นตอนที่ 3.1: เปิด Spike Injector (Interactive Mode)**

```bash
# Terminal 2 (ใหม่)
cd 02_Brain/core/strategy
python spike_test_injector.py interactive
```

**Expected Output:**
```
✅ Connected to tcp://127.0.0.1:7777

══════════════════════════════════════════════════════════════════
🎯 SPIKE TEST INJECTOR - INTERACTIVE MODE
══════════════════════════════════════════════════════════════════

Available Scenarios:
  1. Gold Spike (COVID-19 style)
  2. GBPUSD Flash Crash (Brexit)
  3. Daily News Spike (Random)

  q. Quit

Select scenario (1-3, q):
```

---

#### **ขั้นตอนที่ 3.2: เลือก Scenario ทดสอบ**

**แนะนำเริ่มจาก Scenario 1: Gold Spike**

```
Select scenario (1-3, q): 1
Include reversal? (y/n, default=y): y
```

**Expected Output:**
```
══════════════════════════════════════════════════════════════════
🚀 INJECTING SPIKE: Gold Spike (COVID-19 style)
══════════════════════════════════════════════════════════════════
Symbol:     XAUUSD
Base Price: 1600.0
Spike Price: 1900.0
Direction:  UP
Intensity:  1.5
══════════════════════════════════════════════════════════════════

📈 Phase 1: SPIKE ENTRY...
  [ENTRY] Sent: 10/42 ticks...
  [ENTRY] Sent: 20/42 ticks...
  [ENTRY] Sent: 30/42 ticks...
  [ENTRY] Sent: 40/42 ticks...
✅ Sent 42 entry ticks

🔄 Phase 2: SPIKE REVERSAL...
  [REVERSAL] Sent: 10/55 ticks...
  [REVERSAL] Sent: 20/55 ticks...
  [REVERSAL] Sent: 30/55 ticks...
  [REVERSAL] Sent: 40/55 ticks...
  [REVERSAL] Sent: 50/55 ticks...
✅ Sent 55 reversal ticks

✅ Scenario injection complete!
══════════════════════════════════════════════════════════════════
```

✅ **ตรวจสอบ:** Spike ticks ถูกส่งครบทั้งหมด

---

### **PHASE 4: ตรวจสอบผลลัพธ์ (5 นาที)**

#### **ขั้นตอนที่ 4.1: ตรวจสอบ Python Brain Log**

**ดูที่ Terminal 1 (Python Brain):**

**ที่ต้องเห็น:**

```
📊 STRATEGY ENGINE DASHBOARD (เวลา)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📥 INGESTION:
   Ticks processed:        42-97  ← เพิ่มขึ้น
   Queue size:            1-2

🧠 STRATEGY:
   Policies sent:         1-2     ← ต้องเพิ่มขึ้น!
   Risk multiplier:       1.00x
   
   Top 5 Symbols (Spike):
      1. XAUUSD: 95.5 ← Score สูงมาก!
      2. GBPUSD: 72.3
      3. EURUSD: 68.1
      ...

📊 FEEDBACK:
   Trades executed:       0-1     ← รอดู
   Win rate:              0.0%    ← รอดู
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

✅ **Success Criteria:**
- `Policies sent` เพิ่มขึ้นจาก 0 → 1-2
- `XAUUSD` มี Spike score > 90
- Log แสดง "📤 Policy generated for XAUUSD"

❌ **Failure:**
- `Policies sent` ยังคงเป็น 0
- ไม่เห็น log "Policy generated"
- XAUUSD score < 70

---

#### **ขั้นตอนที่ 4.2: ตรวจสอบ ProgramC_Trader Log**

**ดูที่ MT5 Experts Tab:**

**ที่ต้องเห็น:**

```
📥 Policy received from Brain
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Symbol: XAUUSD
   Strategy: Spike
   Action: BUY
   Confidence: 0.95
   Position Size: 0.05
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 Routing to Spike Hunter Strategy...

✅ Spike Hunter: Entry conditions met
   Factor scores:
   - ATR Spike:     40/40
   - ROC:           30/30
   - Volume:        10/10
   - Tick Density:  20/20
   - Spread:        OK (bonus +5)
   Total Score:     95/100

📈 EXECUTING SPIKE ENTRY
   Symbol:     XAUUSD
   Direction:  BUY
   Lot Size:   0.05
   Entry:      1750.25
   TP:         1755.00
   SL:         1745.50

✅ Order executed: Ticket #12345678
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

✅ **Success Criteria:**
- Policy received ✅
- Spike score calculated ✅
- Order executed ✅
- Ticket number received ✅

---

#### **ขั้นตอนที่ 4.3: ตรวจสอบ MT5 Trade Tab**

**ดูที่ MT5 Terminal → Trade Tab:**

**ที่ต้องเห็น:**

```
Order  Time        Type    Volume  Symbol   Price      S/L       T/P       Profit
12345  10:15:23    Buy     0.05    XAUUSD   1750.25    1745.50   1755.00   +0.00
```

✅ **Success Criteria:**
- มี order ใหม่เปิดขึ้นมา
- Symbol: XAUUSD
- Type: Buy
- Volume: 0.05
- SL และ TP ถูกตั้งไว้

---

## 📊 **ตาราง Expected Results**

| Component | Expected Behavior | Success Indicator |
|-----------|-------------------|-------------------|
| **Spike Injector** | ส่ง ticks สำเร็จ | "✅ Sent 42 entry ticks" |
| **Python Brain** | ตรวจจับ spike | Policies sent > 0 |
| **Python Brain** | Spike score สูง | XAUUSD score > 90 |
| **Python Brain** | Generate policy | Log: "Policy generated for XAUUSD" |
| **ProgramC_Trader** | รับ policy | "📥 Policy received from Brain" |
| **ProgramC_Trader** | Calculate score | Total Score: 95/100 |
| **ProgramC_Trader** | Execute order | "✅ Order executed: Ticket #..." |
| **MT5 Terminal** | Order ปรากฏ | Trade tab มี order ใหม่ |

---

## 🔄 **ทดสอบ Scenario อื่นๆ (Optional)**

หลังจากทดสอบ Gold Spike สำเร็จแล้ว สามารถทดสอบ scenario อื่นได้:

### **Scenario 2: GBPUSD Flash Crash**
```
Select scenario (1-3, q): 2
Include reversal? (y/n, default=y): y
```

**Expected:**
- Policy: SELL GBPUSD
- Score: > 90
- Order: Sell GBPUSD

### **Scenario 3: Daily News Spike (Random Symbol)**
```
Select scenario (1-3, q): 3
Include reversal? (y/n, default=y): y
```

**Expected:**
- Random symbol (EURUSD, GBPUSD, USDJPY, หรือ XAUUSD)
- Policy: BUY หรือ SELL (random)
- Score: 70-90
- Order: ตาม policy

---

## ⚠️ **Troubleshooting**

### **ปัญหาที่ 1: Policies Sent = 0 (ไม่ส่ง policy)**

**สาเหตุเป็นได้:**
1. Spike score < 70 (threshold)
2. Python Brain ไม่ได้รับ ticks
3. Strategy Engine หยุดทำงาน

**วิธีแก้:**
```bash
# ตรวจสอบ Ingestion Worker
# ดู log ว่า "Ticks processed" เพิ่มขึ้นหรือไม่

# ถ้าไม่เพิ่ม:
1. ตรวจสอบ spike_test_injector.py ว่า connect สำเร็จหรือไม่
2. ตรวจสอบ port 7777 ว่าเปิดอยู่หรือไม่

# ถ้าเพิ่มแต่ไม่ส่ง policy:
1. ลด threshold ใน spike_analyzer.py (70 → 50)
2. หรือเพิ่ม intensity (1.5 → 2.0)
```

---

### **ปัญหาที่ 2: ProgramC_Trader ไม่รับ policy**

**สาเหตุเป็นได้:**
1. ZMQ port 7778 ไม่ได้เชื่อมต่อ
2. ProgramC_Trader หยุดทำงาน (EA disabled)

**วิธีแก้:**
```
1. ตรวจสอบ MT5 Experts Tab → ต้องเห็น "SYSTEM READY"
2. ตรวจสอบ AutoTrading เปิดอยู่ (ปุ่มสีเขียว)
3. Restart ProgramC_Trader (Remove → Attach ใหม่)
```

---

### **ปัญหาที่ 3: Order ไม่ execute**

**สาเหตุเป็นได้:**
1. Spike score < 70 (threshold ของ Trader)
2. Risk Guardian block order
3. Account balance ไม่พอ

**วิธีแก้:**
```
1. ดู log ใน Experts Tab ว่า "Spike score" เท่าไหร่
2. ถ้า < 70 → ต้องส่ง spike ที่แรงกว่า
3. ตรวจสอบ Risk Guardian settings
4. ตรวจสอบ Account balance และ Free Margin
```

---

## 📝 **บันทึกผลการทดสอบ**

| Test Run | Scenario | Symbol | Spike Score | Policy Sent? | Order Executed? | Ticket # | Result |
|----------|----------|--------|-------------|--------------|-----------------|----------|--------|
| 1 | Gold Spike | XAUUSD | 95.5 | ✅ Yes | ✅ Yes | 12345678 | ✅ PASS |
| 2 | Flash Crash | GBPUSD | 92.3 | ✅ Yes | ✅ Yes | 12345679 | ✅ PASS |
| 3 | Daily Spike | EURUSD | 85.7 | ✅ Yes | ✅ Yes | 12345680 | ✅ PASS |

---

## ✅ **Success Criteria Summary**

ระบบถือว่า **PASS** เมื่อ:

```
✅ 1. Spike Injector ส่ง ticks สำเร็จ (100%)
✅ 2. Python Brain รับ ticks (Ticks processed เพิ่มขึ้น)
✅ 3. Spike Analyzer ตรวจจับ spike (Score > 90)
✅ 4. Policy Generator สร้าง policy (Policies sent > 0)
✅ 5. ProgramC_Trader รับ policy
✅ 6. Spike Strategy คำนวณ score ถูกต้อง
✅ 7. Order execute สำเร็จ (มี ticket number)
✅ 8. Order ปรากฏใน MT5 Trade Tab
```

---

## 🎯 **Next Steps หลังทดสอบสำเร็จ**

1. ✅ ปิด Spike Injector (กด q)
2. ✅ ทดสอบ scenario อื่นๆ (optional)
3. ✅ ทดสอบ real spike (รอ spike จริงจากตลาด)
4. ✅ Document ผลการทดสอบ
5. ✅ Deploy to production (ถ้าพร้อม)

---

**Status:** 🟢 READY TO TEST

**Estimated Time:** 15-20 นาที (รวมทุก phase)
