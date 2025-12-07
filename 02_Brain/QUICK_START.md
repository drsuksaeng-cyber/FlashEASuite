# ⚡ Feedback Loop - Quick Start Guide

## 🎯 **สิ่งที่ได้รับ:**

✅ **3 ไฟล์ใหม่:**
1. `core/execution_listener.py` - รับ trade results
2. `main.py` - เพิ่ม worker ที่ 3
3. `core/strategy.py` - เพิ่ม feedback logic

---

## 🚀 **การติดตั้ง (3 Steps):**

### **Step 1: Copy ไฟล์ทั้ง 3**

```bash
# ใน folder: 02_ProgramB_Brain_Py/

# 1. Copy execution_listener.py
cp execution_listener.py core/

# 2. Replace main.py
mv main.py main_old.py        # backup เดิม
cp main.py ./                 # copy ใหม่

# 3. Replace strategy.py
mv core/strategy.py core/strategy_old.py  # backup เดิม
cp strategy.py core/                      # copy ใหม่
```

### **Step 2: Verify Dependencies**

```bash
# ตรวจสอบว่ามี modules ครบ:
ls modules/
# ควรมี:
# - tick_analyzer.py
# - currency_meter.py
```

### **Step 3: Run!**

```bash
python main.py
```

---

## ✅ **ผลลัพธ์ที่คาดหวัง:**

```
🚀 All workers started successfully (3 processes)
✅ Ingestion Worker started (PID: 12345)
✅ Strategy Engine started (PID: 12346)
✅ Execution Listener started (PID: 12347)

📥 EXECUTION LISTENER: Ready to receive trade results on tcp://127.0.0.1:7779
🧠 LOGIC: Starting Engine with FEEDBACK LOOP...
```

---

## 🧪 **การทดสอบ:**

### **Test 1: ระบบ Start ได้หรือไม่**
```bash
python main.py
```
**คาดหวัง:** เห็น 3 workers start สำเร็จ

### **Test 2: รับ Trade Result ได้หรือไม่**
1. เปิด position manual ใน MT5
2. ปิด position → ดูว่า Python แสดงผล

**คาดหวัง:**
```
💚 [Message #1] TRADE RESULT: WIN
   🎫 Ticket: 16373028
   💵 Profit: +15.75

💚 FEEDBACK: WIN | +15.75
📊 Stats: 1W / 0L / +15.75 Total
```

### **Test 3: Cooldown ทำงานหรือไม่**
1. ปิด position ขาดทุน
2. ดูว่ามี cooldown message

**คาดหวัง:**
```
💔 FEEDBACK: LOSS | -12.50
⚠️ COOLDOWN ACTIVATED for 30 seconds
📉 Risk multiplier reduced to 0.90x
```

---

## 🔍 **Troubleshooting:**

### **ปัญหา 1: Import Error**
```
ModuleNotFoundError: No module named 'execution_listener'
```
**วิธีแก้:** ตรวจสอบว่า `execution_listener.py` อยู่ใน `core/` folder

### **ปัญหา 2: Port Already in Use**
```
zmq.error.ZMQError: Address already in use
```
**วิธีแก้:**
```bash
# หา process ที่ใช้ port 7779
netstat -ano | findstr 7779

# Kill process
taskkill /PID <PID> /F
```

### **ปัญหา 3: ไม่ได้รับข้อมูล**
```
........ (จุดวิ่งไปเรื่อยๆ)
```
**วิธีแก้:**
1. ตรวจสอบ MT5 Trader ส่งข้อมูลหรือไม่
2. ตรวจสอบ `InpSendAllTrades = true` ใน MT5
3. ตรวจสอบ port 7779 ถูกต้อง

---

## 📊 **Dashboard Example:**

```
=============== HYBRID CSM DASHBOARD ===============
USD: 7.2 ↑  EUR: 4.8 ↓  JPY: 6.1 ↑  GBP: 5.5 ─
AUD: 3.9 ↓  NZD: 4.2 ↓  CAD: 5.8 ↑  CHF: 5.1 ─
📊 FEEDBACK: 5W/2L (7 trades) | Profit: +125.50 | Risk: 1.2x
=====================================================
```

---

## 🎯 **Key Features:**

### **Adaptive Risk:**
- Win: `risk × 1.1` (max 1.5x)
- Loss: `risk × 0.9` (min 0.5x)

### **Cooldown:**
- Normal: 30 seconds after loss
- Emergency: 5 minutes after 3 losses

### **Statistics:**
- Real-time Win/Loss count
- Total profit tracking
- Consecutive streak monitoring

---

## 🔧 **Configuration:**

### **ใน `strategy.py` ปรับได้:**
```python
LOSS_COOLDOWN_SECONDS = 30.0        # ⏱️ Normal cooldown
MAX_CONSECUTIVE_LOSSES = 3          # 🚨 Emergency trigger
EMERGENCY_COOLDOWN_SECONDS = 300.0  # 🛑 Emergency duration
```

---

## 📝 **Log Files:**

```bash
# ดู log
tail -f logs/flashea_brain.log

# หาคำสำคัญ
grep "FEEDBACK" logs/flashea_brain.log
grep "COOLDOWN" logs/flashea_brain.log
```

---

## ✅ **Checklist:**

- [ ] Copy 3 ไฟล์แล้ว
- [ ] Run `python main.py` ได้
- [ ] เห็น 3 workers start
- [ ] Test ด้วย manual trade
- [ ] เห็น WIN/LOSS message
- [ ] Cooldown ทำงาน

---

## 🎉 **Summary:**

**ก่อน:** Python ส่ง policy ไป MT5 เท่านั้น

**หลัง:** Python ได้รับ feedback + ปรับตัวเอง! 🔄

**Benefits:**
- ✅ Learn from mistakes (Loss → Cooldown)
- ✅ Capitalize on success (Win → More aggressive)
- ✅ Automatic risk management
- ✅ Real-time adaptation

---

**พร้อมใช้งานแล้วครับ!** 🚀

**หากมีปัญหา บอกได้เลย!** 💬
