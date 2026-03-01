# 📋 Include Files - Dependency Map
**Generated:** December 26, 2025  
**Purpose:** Quick reference สำหรับตัดสินใจ includes ไม่ต้องอ่านทุกไฟล์

---

## 🎯 **Core Files Dependencies (ที่ต้องใช้บ่อย)**

### **1. Logic/StrategyManager.mqh**
```
Includes:
├── StrategyBase.mqh
├── Strategy_Grid.mqh ← มีอยู่แล้ว!
└── <Trade/Trade.mqh>

→ ถ้า include StrategyManager แล้ว ไม่ต้อง include Strategy_Grid อีก!
```

### **2. Logic/Strategy_Grid.mqh**
```
Includes:
├── StrategyBase.mqh
└── Grid/GridCore.mqh

→ ถ้าต้องการ Grid ต้อง include StrategyManager (ที่มี Grid อยู่แล้ว)
   หรือ include Grid โดยตรง (แต่ไม่ทั้ง 2 อย่าง!)
```

### **3. Risk/RiskGuardian.mqh**
```
Includes:
├── PositionSizingManager.mqh ← มีอยู่แล้ว!
└── DailyLossLimit.mqh         ← มีอยู่แล้ว!

→ ถ้า include RiskGuardian แล้ว ไม่ต้อง include PositionSizing/DailyLimit อีก!
```

### **4. Risk/PositionSizingManager.mqh**
```
Includes: (ไม่มี - standalone)

→ ใช้ผ่าน RiskGuardian เท่านั้น อย่า include โดยตรง
```

### **5. Risk/DailyLossLimit.mqh**
```
Includes: (ไม่มี - standalone)

→ ใช้ผ่าน RiskGuardian เท่านั้น อย่า include โดยตรง
```

---

## 📐 **Visual Dependency Tree**

```
ProgramC_Trader.mq5
│
├── Zmq/ZmqHub.mqh
├── Zmq/Zmq.mqh
├── MqlMsgPack.mqh
├── Network/Protocol.mqh
│
├── Logic/StrategyManager.mqh
│   ├── StrategyBase.mqh
│   ├── Strategy_Grid.mqh ← อย่า include ซ้ำ!
│   │   ├── StrategyBase.mqh
│   │   └── Grid/GridCore.mqh
│   └── <Trade/Trade.mqh>
│
└── Risk/RiskGuardian.mqh
    ├── PositionSizingManager.mqh ← อย่า include ซ้ำ!
    └── DailyLossLimit.mqh         ← อย่า include ซ้ำ!
```

---

## ✅ **กฎการ Include (เพื่อหลีกเลี่ยง Duplicate)**

### **Rule #1: Parent มี Child แล้ว → ไม่ต้อง include Child**
```cpp
✅ CORRECT:
#include <Logic/StrategyManager.mqh>  // มี Strategy_Grid อยู่แล้ว

❌ WRONG:
#include <Logic/StrategyManager.mqh>
#include <Logic/Strategy_Grid.mqh>     // ← ซ้ำ!
```

### **Rule #2: Coordinator Class จัดการ Sub-Classes → ใช้ผ่าน Coordinator**
```cpp
✅ CORRECT:
#include <Risk/RiskGuardian.mqh>  // มี PositionSizing + DailyLimit อยู่แล้ว

❌ WRONG:
#include <Risk/RiskGuardian.mqh>
#include <Risk/PositionSizingManager.mqh>  // ← ซ้ำ!
#include <Risk/DailyLossLimit.mqh>         // ← ซ้ำ!
```

### **Rule #3: เมื่อสงสัย → ดูไฟล์ว่า include อะไรอยู่**
```bash
# Quick check:
grep "^#include" Include/Logic/StrategyManager.mqh
```

---

## 🎯 **Recommended Includes สำหรับ ProgramC_Trader.mq5**

```cpp
// ========== INCLUDES (MINIMAL & CORRECT) ==========
#include <Zmq/ZmqHub.mqh>              // ZMQ management
#include <Zmq/Zmq.mqh>                 // ZMQ primitives
#include <MqlMsgPack.mqh>              // Serialization
#include <Network/Protocol.mqh>        // Message protocol
#include <Logic/StrategyManager.mqh>   // Council + Grid (includes Strategy_Grid.mqh)
#include <Risk/RiskGuardian.mqh>       // Risk + Sizing + DailyLimit (includes both)
```

**Total:** 6 includes  
**Covers:** ~10 actual files (จาก dependencies)

---

## 📊 **Summary Table**

| File to Include | Contains (Auto-included) | Don't Include Again |
|-----------------|-------------------------|---------------------|
| StrategyManager.mqh | Strategy_Grid.mqh | ❌ Strategy_Grid.mqh |
| RiskGuardian.mqh | PositionSizingManager.mqh<br>DailyLossLimit.mqh | ❌ PositionSizingManager.mqh<br>❌ DailyLossLimit.mqh |

---

## 💾 **Token Savings**

### **Without Map (อ่านทุกไฟล์):**
```
55 files × 200 lines × 15 tokens/line = ~165,000 tokens ❌ เกิน!
```

### **With Map (ใช้แค่ map นี้):**
```
1 file × ~100 lines × 15 tokens/line = ~1,500 tokens ✅ ประหยัด 99%!
```

---

## 🎓 **How to Use This Map**

### **Before Writing Includes:**
1. ดู Visual Dependency Tree
2. เช็คว่า Parent มี Child อยู่แล้วไหม
3. Include เฉพาะ Parent

### **When Adding New Features:**
1. เช็ค dependency ของไฟล์ใหม่
2. Update map นี้
3. ตรวจสอบ duplicates

---

**Note:** Map นี้ใช้แค่ ~1,500 tokens แต่ให้ข้อมูลครอบคลุม 55 ไฟล์!  
**Result:** ประหยัด tokens 99% + ตัดสินใจได้เร็วขึ้น ✅
