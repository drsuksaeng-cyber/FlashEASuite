# ⚡ Backtest ใน 5 นาที - Quick Guide

**เวลา:** 5 นาที  
**ค่าใช้จ่าย:** ฟรี  
**Risk:** 0%

---

## 🚀 **5 ขั้นตอน:**

### **1. เปิด Strategy Tester (30 วินาที)**
```
กด Ctrl+R
หรือ
View → Strategy Tester
```

---

### **2. ตั้งค่าพื้นฐาน (1 นาที)**
```
Expert Advisor:  Example_GridStandalone_EA_FIXED
Symbol:          XAUUSD
Period:          M15
Date:            2024.01.01 - 2024.12.08
Execution:       Every tick based on real ticks
```

---

### **3. ตั้งค่า Parameters (1 นาที)**
```
คลิก "Expert properties"

Tab: Testing
- Deposit: 5000
- Currency: USD
- Leverage: 1:100

Tab: Inputs
- InpMaxGridLevels = 5
- InpBaseStepPoints = 200
- InpBaseLot = 0.01
- InpEnableServer = false ❌ สำคัญ!

กด OK
```

---

### **4. Run Test (2-10 นาที)**
```
กดปุ่ม "Start"

รอ progress bar เต็ม...
```

---

### **5. ดูผลลัพธ์ (2 นาที)**

**Tab: Report - ดูเลข:**
```
✅ Total Net Profit > 0
✅ Profit Factor > 2.0
✅ Max Drawdown < 12%
✅ Win Rate > 60%
```

**Tab: Graph - ดูกราฟ:**
```
✅ Balance (เส้นเขียว) ขึ้นเรื่อยๆ
✅ Drawdown (เส้นแดง) ไม่เกิน 15%
```

---

## 📊 **อ่านผลลัพธ์:**

### **ผลลัพธ์ดี ✅:**
```
Net Profit:      +$500-700 (10-14%)
Profit Factor:   > 2.0
Max DD:          < 12%
Win Rate:        > 60%

→ ผ่าน! ไปต่อ demo test
```

### **ผลลัพธ์พอใช้ ⚠️:**
```
Net Profit:      +$300-500 (6-10%)
Profit Factor:   1.5-2.0
Max DD:          12-15%
Win Rate:        55-60%

→ ต้อง optimize parameters
```

### **ผลลัพธ์แย่ ❌:**
```
Net Profit:      < $300 หรือ ติดลบ
Profit Factor:   < 1.5
Max DD:          > 15%
Win Rate:        < 55%

→ ปรับ strategy หรือ settings
```

---

## 🎯 **เป้าหมาย:**

```
1 เดือน:   +8-12%
3 เดือน:   +25-35%
1 ปี:      +100-150%

Max DD:    < 15%
Profit Factor: > 2.0
Win Rate:  > 60%
```

---

## ⚠️ **ข้อควรระวัง:**

```
⚠️  Backtest ≠ การันตี future
⚠️  ต้อง demo test หลัง backtest
⚠️  อย่า live ทันที
⚠️  InpEnableServer ต้องปิด!
```

---

## 💡 **Tips:**

### **Test หลายช่วง:**
```
- 1 เดือน (quick test)
- 3 เดือน (better)
- 1 ปี (recommended)
- 3-5 ปี (best)
```

### **Save Report:**
```
Tab: Report
Right-click → Save as Report
→ ได้ HTML file
```

---

## 📋 **Checklist:**

```
□ Ctrl+R (เปิด Strategy Tester)
□ เลือก EA
□ เลือก XAUUSD M15
□ ตั้ง Date Range
□ Expert properties → ตั้งค่า
□ InpEnableServer = false ❌
□ กด Start
□ รอผลลัพธ์
□ ดู Report
□ ดู Graph
□ Export report
□ ✅ วิเคราะห์เสร็จ!
```

---

## 🎉 **สรุป:**

```
╔════════════════════════════════════╗
║    BACKTEST IN 5 MINUTES          ║
╚════════════════════════════════════╝

1. Ctrl+R
2. เลือก EA + Symbol + Date
3. ตั้งค่า Parameters
4. Start
5. ดูผล

ง่าย เร็ว ฟรี!

Next: Demo Test → Live Deploy
════════════════════════════════════
```

---

**ลองได้เลย! 📊✨**
