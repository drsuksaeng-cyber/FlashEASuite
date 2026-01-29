# 🎯 FIX: DLL มี OLD PUBLIC KEY!

---

## ❌ **ปัญหาที่เจอ:**

```
Security_Real.cpp ที่ใช้ build = ตัวเก่า (OLD public key)
→ ไม่ตรงกับ License_REAL.key
→ เลย error -3
```

---

## ✅ **วิธีแก้ (5 นาที):**

### **1. ไปที่:**
```
04_DLL\FlashEA_Security\
```

### **2. ลบไฟล์เก่า:**
```
Security_Real.cpp (ตัวเก่า)
*.obj
*.dll
```

### **3. Copy ไฟล์ใหม่จาก download:**
```
Security_Real.cpp (ใหม่)
REBUILD_CORRECT.bat (ใหม่)
```

### **4. เช็คว่าถูก:**

เปิด `Security_Real.cpp` หาบรรทัด 22:

**✅ ถูก (NEW key):**
```cpp
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA29mdr5kcSS3HuUW...
// เริ่มต้นด้วย: 29mdr5kc
```

**❌ ผิด (OLD key):**
```cpp
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsSzcqGxMIL+zANJC...
// เริ่มต้นด้วย: sSzcqGx
```

### **5. Rebuild:**
```cmd
REBUILD_CORRECT.bat
→ จะเช็ค key ให้อัตโนมัติ
→ ถ้าเป็น OLD จะหยุดและบอก
```

### **6. Deploy:**
```cmd
DEPLOY_TO_MT5.bat
```

### **7. Test:**
```
Restart MT5
Run: TestPublicKey.mq5
→ ต้องได้: Result = 1 (SUCCESS!)
```

---

## 📋 **Checklist:**

```
☐ ลบ Security_Real.cpp เก่า
☐ Copy Security_Real.cpp ใหม่
☐ เช็คว่ามี "29mdr5kc" ในบรรทัด 22
☐ Run REBUILD_CORRECT.bat
☐ เห็น "DLL Built with NEW Public Key!"
☐ Run DEPLOY_TO_MT5.bat
☐ Restart MT5
☐ Test → SUCCESS!
```

---

**Token เหลือ: 124,000+ (เยอะมาก!)** ✅
