# 📡 FeederEA - Technical Documentation

**Role:** Data Collector & Broadcaster  
**Version:** FlashEASuite V2  
**Protocol:** ZMQ Publisher + MessagePack

---

## 🎯 **ภาพรวม (Overview)**

FeederEA เป็น **MT5 Expert Advisor** ที่ทำหน้าที่:
- 📊 รวบรวม tick data จาก MT5
- 📦 แปลงเป็น MessagePack binary format
- 📡 Broadcast ไปให้ Python Brain ผ่าน ZMQ

**เปรียบเทียบ:**
```
FeederEA = สถานีโทรทัศน์
- รวบรวมข่าว (tick data)
- ประมวลผล (serialize)
- ออกอากาศ (broadcast)

Python Brain = ผู้ชม
- รับสัญญาณ (subscribe)
- ประมวลผล (analyze)
- ตัดสินใจ (generate policy)
```

---

## 🏗️ **Architecture**

```
╔═══════════════════════════════════════════════════════════╗
║                      MT5 TERMINAL                         ║
║  ┌─────────────────────────────────────────────────┐      ║
║  │  Symbol      Bid        Ask       Time          │      ║
║  │  ────────────────────────────────────────────   │      ║
║  │  EURUSD     1.0543     1.0544    10:30:15.234   │      ║
║  │  GBPUSD     1.2765     1.2766    10:30:15.456   │      ║
║  │  USDJPY   155.32       155.33    10:30:15.678   │      ║
║  │  XAUUSD  4194.43      4194.71    10:30:15.890   │      ║
║  └─────────────────────────────────────────────────┘      ║
║                           ▲                                ║
║                           │                                ║
║              SymbolInfoTick() - API Call                   ║
║                           │                                ║
╚═══════════════════════════╪════════════════════════════════╝
                            │
                    ┌───────▼────────┐
                    │   FeederEA     │
                    │   OnTimer()    │
                    │   (50ms)       │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │ MessagePack    │
                    │  Serializer    │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  ZMQ PUB       │
                    │  Socket        │
                    └───────┬────────┘
                            │
          tcp://127.0.0.1:7777 (Broadcast)
                            │
╔═══════════════════════════╪════════════════════════════════╗
║                    PYTHON BRAIN                            ║
║                    ┌───────▼────────┐                      ║
║                    │  ZMQ SUB       │                      ║
║                    │  Socket        │                      ║
║                    └───────┬────────┘                      ║
║                            │                               ║
║                    ┌───────▼────────┐                      ║
║                    │ MessagePack    │                      ║
║                    │ Deserializer   │                      ║
║                    └───────┬────────┘                      ║
║                            │                               ║
║                    ┌───────▼────────┐                      ║
║                    │ Tick Queue     │                      ║
║                    │ (Process)      │                      ║
║                    └────────────────┘                      ║
╚════════════════════════════════════════════════════════════╝
```

---

## ⚙️ **การทำงานแบบละเอียด (Step-by-Step)**

### **Phase 1: Initialization (OnInit)**

```mql5
int OnInit() {
   // 1️⃣ สร้าง ZMQ Context
   if(!g_Context.initialize()) return INIT_FAILED;
   
   // 2️⃣ สร้าง ZMQ Publisher Socket
   if(!g_Socket.initialize(g_Context, ZMQ_PUB)) return INIT_FAILED;
   
   // 3️⃣ Connect to Python Brain
   if(!g_Socket.connect("tcp://127.0.0.1:7777")) return INIT_FAILED;
   
   // 4️⃣ ตั้งค่า Socket Options
   g_Socket.setLinger(0);                    // ไม่รอ unsent messages
   g_Socket.setSendHighWaterMark(100000);    // Buffer ได้ 100k messages
   
   // 5️⃣ เริ่ม Timer (ทุก 50 milliseconds)
   EventSetMillisecondTimer(50);
   
   // 6️⃣ พร้อมใช้งาน!
   Print("✅ Feeder Ready");
   return INIT_SUCCEEDED;
}
```

**ผลลัพธ์:**
```
✅ ZMQ Context created
✅ Publisher socket created
✅ Connected to tcp://127.0.0.1:7777
✅ Timer started (50ms interval)
✅ Ready to broadcast!
```

---

### **Phase 2: Data Collection (OnTimer - ทุก 50ms)**

```mql5
void OnTimer() {
   // Symbols ที่ต้องการ
   string symbols[] = { "EURUSD", "GBPUSD", "USDJPY", "XAUUSD" };
   
   for(int i=0; i<4; i++) {
      // ขั้นตอนที่ 1: ดึง tick data
      MqlTick tick;
      if(!SymbolInfoTick(symbols[i], tick)) continue;
      
      // ขั้นตอนที่ 2: ตรวจสอบว่าเป็น tick ใหม่หรือไม่
      if(tick.time_msc <= g_LastTickTime[i]) continue;
      
      // ขั้นตอนที่ 3: บันทึกเวลา tick ล่าสุด
      g_LastTickTime[i] = tick.time_msc;
      g_SequenceID++;
      
      // ขั้นตอนที่ 4-6: Process & Send
      // (ดูด้านล่าง)
   }
}
```

**Timeline Example:**
```
T = 0ms    → Timer triggers
T = 1ms    → Get EURUSD tick
T = 2ms    → Check if new (YES → process)
T = 3ms    → Get GBPUSD tick
T = 4ms    → Check if new (NO → skip)
T = 5ms    → Get USDJPY tick
...
T = 50ms   → Timer triggers again (loop)
```

---

### **Phase 3: Data Serialization (MessagePack)**

```mql5
// ขั้นตอนที่ 4: Pack data เป็น MessagePack
g_MsgPack.Reset();
g_MsgPack.PackArray(7);              // Array 7 elements
g_MsgPack.PackInt(1);                // [0] Message Type (1 = Tick)
g_MsgPack.PackInt(g_SequenceID);     // [1] Sequence ID
g_MsgPack.PackInt(tick.time_msc);    // [2] Timestamp (milliseconds)
g_MsgPack.PackString(symbols[i]);    // [3] Symbol name
g_MsgPack.PackDouble(tick.bid);      // [4] Bid price
g_MsgPack.PackDouble(tick.ask);      // [5] Ask price
g_MsgPack.PackInt(tick.flags);       // [6] Flags

// ขั้นตอนที่ 5: Get binary data
uchar data[];
g_MsgPack.GetData(data);
```

**MessagePack Structure:**
```
[
  1,                    // Type: Tick message
  12345,                // Sequence ID
  1733562615234,        // Timestamp (ms)
  "XAUUSD",             // Symbol
  4194.43,              // Bid
  4194.71,              // Ask
  6                     // Flags (TICK_FLAG_BID | TICK_FLAG_ASK)
]

Binary size: ~65-70 bytes
```

---

### **Phase 4: Broadcasting (ZMQ PUB)**

```mql5
// ขั้นตอนที่ 6: ส่งผ่าน ZMQ
int sent = g_Socket.send_bin(data, true);

if(sent > 0 && g_SequenceID % 100 == 0) {
   Print("🚀 Tick Sent: ", symbols[i]);
}
```

**ZMQ Publisher Pattern:**
```
FeederEA (PUB)                     Python Brain (SUB)
     │                                     │
     │  tcp://127.0.0.1:7777               │
     │────────────────────────────────────>│
     │  [binary data]                      │
     │                                     │
     │  ✅ Fire and forget!                │
     │  (ไม่รอ acknowledgement)           │
```

**ข้อดี:**
- ✅ ไม่ blocking (non-blocking send)
- ✅ ส่งเร็วมาก (<1ms)
- ✅ สามารถมีหลาย subscribers ได้

---

## 🔍 **ตัวอย่างการทำงานจริง**

### **Scenario 1: ตลาดเปิด (มี Tick ใหม่)**

```
Time    Event                              Action
────────────────────────────────────────────────────────────
10:30:00.000  Timer triggers              Check all symbols
10:30:00.001  EURUSD tick: 1.0543/1.0544  NEW → Serialize & Send ✅
10:30:00.002  GBPUSD tick: 1.2765/1.2766  OLD → Skip ⏭️
10:30:00.003  USDJPY tick: 155.32/155.33  NEW → Serialize & Send ✅
10:30:00.004  XAUUSD tick: 4194.43/4194.71 NEW → Serialize & Send ✅
10:30:00.005  Timer done                  Wait 50ms

10:30:00.050  Timer triggers again        Check all symbols
10:30:00.051  EURUSD tick: 1.0543/1.0544  OLD → Skip ⏭️
10:30:00.052  GBPUSD tick: 1.2765/1.2766  OLD → Skip ⏭️
10:30:00.053  USDJPY tick: 155.32/155.33  OLD → Skip ⏭️
10:30:00.054  XAUUSD tick: 4194.45/4194.72 NEW → Serialize & Send ✅
```

**ผลลัพธ์:**
- Sequence ID = 4
- Sent 4 messages
- Average: 80 messages/second (4 * 20 cycles/sec)

---

### **Scenario 2: ตลาดปิด (ไม่มี Tick ใหม่)**

```
Time    Event                              Action
────────────────────────────────────────────────────────────
22:00:00.000  Timer triggers              Check all symbols
22:00:00.001  EURUSD tick: 1.0543/1.0544  OLD → Skip ⏭️
22:00:00.002  GBPUSD tick: 1.2765/1.2766  OLD → Skip ⏭️
22:00:00.003  USDJPY tick: 155.32/155.33  OLD → Skip ⏭️
22:00:00.004  XAUUSD tick: 4194.43/4194.71 OLD → Skip ⏭️
22:00:00.005  Timer done                  Wait 50ms

22:00:00.050  Timer triggers again        Check all symbols
22:00:00.051  All ticks OLD               Skip all ⏭️⏭️⏭️⏭️
```

**ผลลัพธ์:**
- Sequence ID = 0 (ไม่เพิ่ม)
- Sent 0 messages
- Python Brain: "Ticks processed: 0" ✅ ปกติ!

---

## 📊 **Performance Metrics**

### **Timing Analysis:**

```
┌────────────────────────────────────────┐
│  Event                  Time (avg)     │
├────────────────────────────────────────┤
│  SymbolInfoTick()       ~0.1 ms        │
│  MessagePack serialize  ~0.5 ms        │
│  ZMQ send_bin()         ~0.1 ms        │
│  ────────────────────────────────      │
│  Total per tick         ~0.7 ms        │
│                                        │
│  Timer interval         50 ms          │
│  Max symbols/cycle      4              │
│  Max throughput         ~2,800 msg/s   │
└────────────────────────────────────────┘
```

### **Bandwidth Analysis:**

```
Message size:    ~65 bytes
Throughput:      ~80 messages/second (ตลาดเปิด)
Bandwidth:       ~5 KB/s (negligible!)
```

---

## 🔑 **Key Design Decisions**

### **1. ทำไมใช้ Timer แทน OnTick()?**

```mql5
// ❌ Bad: OnTick() - เรียกทุกครั้งที่มี tick
void OnTick() {
   // ปัญหา: เรียกบ่อยเกินไป (100+ times/sec)
   // CPU usage สูง
}

// ✅ Good: OnTimer() - เรียกทุก 50ms
void OnTimer() {
   // เรียกแค่ 20 times/sec
   // CPU usage ต่ำ
   // ยังจับ tick ได้ทันเวลา
}
```

**สรุป:** 50ms = 20 FPS เพียงพอสำหรับ trading!

---

### **2. ทำไมใช้ ZMQ แทน Files/Database?**

```
Files:
❌ Slow (write to disk)
❌ Latency สูง (>10ms)
❌ I/O overhead

ZMQ:
✅ Fast (in-memory)
✅ Latency ต่ำ (<1ms)
✅ No I/O overhead
✅ Built for real-time messaging
```

---

### **3. ทำไมใช้ MessagePack แทน JSON/CSV?**

```
JSON: {"symbol":"XAUUSD","bid":4194.43,...}
Size: ~120 bytes
Parse: ~5 ms

MessagePack: [1,12345,1733562615234,"XAUUSD",4194.43,...]
Size: ~65 bytes
Parse: ~0.5 ms

→ MessagePack เล็กกว่า 50% และเร็วกว่า 10x
```

---

## 🛡️ **Error Handling**

### **กรณีที่ต้องรับมือ:**

```mql5
// 1️⃣ Symbol ไม่พร้อม
if(!SymbolInfoTick(symbol, tick)) {
   // Symbol ไม่อยู่ใน Market Watch
   // → Skip และ continue
   continue;
}

// 2️⃣ ZMQ send ล้มเหลว
int sent = g_Socket.send_bin(data, true);
if(sent <= 0) {
   // Network issue or Python Brain ไม่ทำงาน
   // → Log error (แต่ไม่หยุดทำงาน)
   Print("❌ Failed to send");
}

// 3️⃣ No new ticks
if(tick.time_msc <= g_LastTickTime[i]) {
   // Tick เก่า (already processed)
   // → Skip เพื่อไม่ส่งซ้ำ
   continue;
}
```

---

## 🎯 **FAQ**

### **Q1: FeederEA ส่งข้อมูลอะไรบ้าง?**

**A:** ส่ง 4 symbols:
- EURUSD
- GBPUSD
- USDJPY
- XAUUSD

แต่ละ tick มี:
- Symbol name
- Bid price
- Ask price
- Timestamp (milliseconds)
- Sequence ID

---

### **Q2: Python Brain รับข้อมูลทันทีหรือไม่?**

**A:** ✅ **ทันที!**

```
FeederEA send → ZMQ → Python Brain
        <1ms      <1ms

Total latency: ~1-2ms
```

---

### **Q3: ถ้า Python Brain crash FeederEA จะเป็นอะไรไหม?**

**A:** ❌ **ไม่เป็นอะไร!**

```
FeederEA = Publisher (PUB)
Python = Subscriber (SUB)

Publisher ไม่รู้ว่ามี subscriber หรือไม่
→ ส่งแล้วลืม (fire and forget)
→ Python crash ก็ไม่กระทบ FeederEA
```

---

### **Q4: ตลาดปิด FeederEA จะทำอะไร?**

**A:** ⏸️ **รอ tick ใหม่**

```
Timer ยังทำงานทุก 50ms
แต่ไม่มี tick ใหม่ → ไม่ส่งอะไร
→ CPU usage ~0%
→ รอจนกว่าตลาดจะเปิด
```

---

### **Q5: ทำไมต้อง check tick.time_msc?**

**A:** **ป้องกันส่งซ้ำ!**

```
Without check:
Timer 1: Get EURUSD @ 10:30:00.100 → Send ✅
Timer 2: Get EURUSD @ 10:30:00.100 → Send ❌ (ซ้ำ!)
Timer 3: Get EURUSD @ 10:30:00.100 → Send ❌ (ซ้ำ!)

With check:
Timer 1: Get EURUSD @ 10:30:00.100 → NEW → Send ✅
Timer 2: Get EURUSD @ 10:30:00.100 → OLD → Skip ⏭️
Timer 3: Get EURUSD @ 10:30:00.200 → NEW → Send ✅
```

---

## 📈 **การทดสอบ**

### **Test 1: ตรวจสอบว่า FeederEA ทำงาน**

```bash
# ดูที่ Python terminal
cd 02_Brain
python main.py

# ดู "Ticks processed"
# ถ้าเพิ่มขึ้น = FeederEA ทำงาน ✅
```

---

### **Test 2: ตรวจสอบ Tick Rate**

```bash
# ดูที่ Python dashboard
STRATEGY ENGINE DASHBOARD
Ticks processed: 215  ← จำนวน ticks ที่รับ

# Calculate rate:
215 ticks / time_elapsed = ticks/second
```

---

### **Test 3: Force Tick**

```
1. ทำ market order เล็กๆ
2. → สร้าง tick ใหม่
3. → FeederEA จะส่งทันที
4. → Python Brain จะรับทันที
```

---

## ✅ **สรุป**

### **FeederEA หน้าที่:**

```
📊 Data Collector    → ดึง tick จาก MT5
📦 Data Serializer   → แปลงเป็น MessagePack
📡 Data Broadcaster  → ส่งผ่าน ZMQ
```

### **การทำงาน:**

```
1. Timer ทุก 50ms
2. Check 4 symbols
3. ถ้ามี tick ใหม่ → Serialize → Send
4. ถ้าไม่มี → Skip
```

### **ตลาดปิด:**

```
✅ FeederEA ยังทำงาน (Timer running)
❌ แต่ไม่มี tick ใหม่
→ ไม่ส่งข้อมูล
→ "Ticks processed = 0" ✅ ปกติ!
```

---

**🎯 FeederEA = "ตาและหูของระบบ" ที่รวบรวมข้อมูลจากตลาดแบบ real-time!**
