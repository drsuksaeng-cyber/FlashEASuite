# ⚡ Quick Start - 5 นาที!

**เริ่มใช้ FlashEASuite V2 ใน 5 นาที**

---

## 🚀 **3 ขั้นตอน:**

### **1️⃣ Copy Project (1 นาที)**

```
Extract FlashEASuite_V2.zip

Copy ทั้งโฟลเดอร์ไปที่:
C:\Users\[USER]\AppData\Roaming\MetaQuotes\Terminal\[TERMINAL_ID]\MQL5\Experts\

ผลลัพธ์:
MQL5\Experts\FlashEASuite_V2\  ← ได้โฟลเดอร์นี้
```

---

### **2️⃣ Compile Tests (2 นาที)**

```
1. เปิด MetaEditor (กด F4 ใน MT5)

2. File → Open → FlashEASuite_V2\Tester\test_integration_day1.mq5

3. กด F7 (Compile)

Expected: "0 error(s), 0 warning(s)" ✅

4. ปิด MetaEditor
```

---

### **3️⃣ Run Test (2 นาที)**

```
1. MT5 → Navigator → Scripts → test_integration_day1

2. ลากไปวางบน chart (symbol ไหนก็ได้)

3. ดูผลใน Experts tab (ล่างสุด)

Expected:
╔════════════════════════════════════════════╗
║        TEST SUMMARY                        ║
╚════════════════════════════════════════════╝
Total Tests: 6
✅ Passed: 6
❌ Failed: 0
Success Rate: 100.0%
Status: ✅ ALL TESTS PASSED
```

---

## ✅ **เสร็จแล้ว!**

หาก test ผ่านทั้งหมด = ระบบพร้อมใช้งาน!

---

## 🐛 **มีปัญหา?**

### **Error: Cannot open PositionSizingManager.mqh**

```
→ ตรวจสอบว่า copy โฟลเดอร์ครบ
→ ต้องมี: FlashEASuite_V2\Include\Risk\PositionSizingManager.mqh
```

### **Test ไม่ปรากฏใน Navigator**

```
→ Compile test file ใหม่ (F7)
→ Refresh Navigator (F5)
```

### **Test fail**

```
→ ดู error message ใน Experts tab
→ อ่าน: docs/fixes/
```

---

## 📚 **อ่านต่อ:**

- **ทดสอบเพิ่ม:** `Tester/README.md`
- **ติดตั้งแบบละเอียด:** `docs/installation/INSTALLATION_GUIDE.md`
- **เริ่มเทรด:** `docs/guides/COMPLETE_RUN_GUIDE.md`

---

**เวลาทั้งหมด:** 5 นาที  
**ความยาก:** ง่าย  
**อัตราสำเร็จ:** 99%+

🎉 **สนุกกับการเทรด!**
