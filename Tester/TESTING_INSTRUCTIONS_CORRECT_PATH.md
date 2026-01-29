# 🧪 Phase 1 - วิธีทดสอบที่ถูกต้อง

**ตาม Path โครงสร้างของคุณ**

---

## 📂 **โครงสร้างที่มีอยู่แล้ว (จากรูป)**

```
MQL5/
├── Experts/
│   └── FlashEASuite_V2/
│       ├── tools/                          ← Python tools อยู่ที่นี่
│       │   ├── keys/
│       │   ├── example_license.key
│       │   ├── generate_keys.py
│       │   ├── generate_license.py
│       │   ├── license_admin.py
│       │   └── verify_license.py
│       │
│       └── (EA files อื่นๆ)
│
└── Files/                                  ← License runtime files
    ├── license.key           ✅ ถูกต้อง
    ├── server_public.pem     ✅ ถูกต้อง
    └── server_private.pem    ❌ ลบออก! (ไม่ควรอยู่ที่นี่)
```

---

## ⚠️ **สิ่งที่ต้องแก้ก่อนทดสอบ**

### **1. ลบ server_private.pem จาก Files/**

```
⚠️ ไฟล์นี้เป็น SECRET KEY - ห้ามอยู่ที่ Files/!
```

**ทำอย่างนี้:**
```
1. เปิด Windows Explorer
2. ไปที่ MQL5\Files\
3. ลบไฟล์ server_private.pem ออก
4. เก็บ server_private.pem ไว้ที่ tools/keys/ เท่านั้น!
```

**ควรมีแค่ 2 ไฟล์ใน Files/:**
```
MQL5/Files/
├── license.key           ← ถูกต้อง
└── server_public.pem     ← ถูกต้อง
```

---

## 🚀 **ขั้นตอนการทดสอบ**

### **Step 1: วาง Test File**

**วาง TestPhase1_LicenseVerify.mq5 ที่:**
```
MQL5/Experts/FlashEASuite_V2/TestPhase1_LicenseVerify.mq5
```

**วิธีวาง:**
```
1. Copy TestPhase1_LicenseVerify.mq5 
2. Paste ไปที่ MQL5\Experts\FlashEASuite_V2\
3. เปิด MetaEditor
4. เปิดไฟล์ TestPhase1_LicenseVerify.mq5
5. กด Compile (F7)
```

---

### **Step 2: Compile**

**ใน MetaEditor:**
```
1. File → Open → MQL5\Experts\FlashEASuite_V2\TestPhase1_LicenseVerify.mq5
2. กด F7 (Compile)
3. ตรวจสอบ: 0 error(s), 0 warning(s)
```

**Expected:**
```
✅ Compiling 'TestPhase1_LicenseVerify.mq5'
✅ 0 error(s), 0 warning(s)
✅ TestPhase1_LicenseVerify.ex5 created
```

---

### **Step 3: Attach to Chart**

**ใน MT5 Terminal:**
```
1. เปิด chart XAUUSD H1 (หรือ symbol ใดก็ได้)
2. Navigator → Expert Advisors → FlashEASuite_V2 → TestPhase1_LicenseVerify
3. Drag ไปใส่ chart
4. กด OK (ไม่ต้องแก้ settings)
```

---

### **Step 4: ดูผลลัพธ์ใน Experts Tab**

**Expected Output:**
```
============================================================
  FlashEASuite V2 - Phase 1 License Test
  Testing: License File Reading & Parsing
============================================================

[TEST 1] Checking license file...
[PASS] License file found

[TEST 2] Reading license file...
[PASS] License file read successfully

[TEST 3] License Information:
  License ID:    FLASH-2026-0001-DEMO
  Product:       FlashEASuite-Pro
  Type:          reporting
  Client:        Dr. Suksaeng Kukanok
  Email:         dr.suksaeng@example.com
  HWID:          test-hwid-sha256-hash-here
  Max Slots:     5
  Issued:        2026.01.28
  Expires:       2031.01.27
  Grace Days:    7
  Signature:     En3Ha6NbjkR7bgyP+5dl65Vl...

[TEST 4] Checking expiry date...
  License valid: 1824 days remaining
[PASS] License is valid

[TEST 5] Checking public key...
[PASS] Public key found

============================================================
  ✅ Phase 1 Basic Tests: PASSED
============================================================

NOTE: Signature verification requires DLL (Phase 3)
For now, we've verified:
  ✓ License file exists
  ✓ License file is readable
  ✓ License data is valid JSON
  ✓ Public key exists
```

---

## ✅ **เห็น Output นี้ = Phase 1 สำเร็จ!**

### **Test Checklist:**
```
✅ [PASS] License file found
✅ [PASS] License file read successfully
✅ [PASS] License data parsed
✅ [PASS] License is valid (not expired)
✅ [PASS] Public key found
```

---

## 🐛 **ถ้าเจอปัญหา**

### **Error: License file not found**
```
[FAIL] License file not found!
Expected location: C:\...\MQL5\Files\license.key
```

**แก้:**
```
1. เช็คว่ามีไฟล์ license.key ใน MQL5\Files\ หรือไม่
2. ถ้าไม่มี: copy จาก tools\example_license.key
   → Rename เป็น license.key
   → วางใน Files\
```

---

### **Error: Public key not found**
```
[FAIL] Public key not found!
Expected location: C:\...\MQL5\Files\server_public.pem
```

**แก้:**
```
1. เช็คว่ามีไฟล์ server_public.pem ใน Files\
2. ถ้าไม่มี: copy จาก tools\keys\server_public.pem
   → วางใน Files\
```

---

### **Error: Could not read license file**
```
[FAIL] Could not read license file
```

**แก้:**
```
1. ไฟล์ license.key อาจ corrupt
2. สร้างใหม่:
   cd MQL5\Experts\FlashEASuite_V2\tools
   python generate_license.py
3. Copy example_license.key → Files\license.key
```

---

## 📊 **สรุป Path ที่ถูกต้อง**

### **Python Tools (Admin use):**
```
MQL5/Experts/FlashEASuite_V2/tools/
├── generate_license.py      ← สร้าง license ใหม่
├── verify_license.py         ← ตรวจสอบ license
└── keys/
    ├── server_private.pem    ← SECRET! เก็บไว้ที่นี่
    └── server_public.pem     ← Copy to Files/
```

### **MT5 Runtime Files:**
```
MQL5/Files/
├── license.key               ← EA อ่านจากที่นี่
└── server_public.pem         ← EA ใช้ verify signature
```

### **Test EA:**
```
MQL5/Experts/FlashEASuite_V2/
└── TestPhase1_LicenseVerify.mq5  ← ทดสอบ license
```

---

## 🔄 **ถ้าต้องการสร้าง License ใหม่**

```powershell
# ไปที่ tools
cd "C:\...\MQL5\Experts\FlashEASuite_V2\tools"

# สร้าง license ใหม่
python generate_license.py

# Copy ไป Files
copy example_license.key "..\..\Files\license.key" -Force

# Verify
python verify_license.py

# Test ใน MT5 อีกครั้ง
```

---

## ✅ **Next Steps**

**หลังจาก Phase 1 ผ่าน:**
1. ✅ License system ทำงาน
2. ⏭️ Phase 2: Policy Security (Anti-Replay)
3. ⏭️ Phase 3: DLL Development

---

**Phase 1 เสร็จสมบูรณ์เมื่อ:**
```
✅ Test EA compile สำเร็จ
✅ Test EA อ่าน license ได้
✅ Test EA แสดงข้อมูล license ถูกต้อง
✅ Test EA ตรวจสอบวันหมดอายุได้
✅ Test EA หา public key เจอ
```

**เห็น "Phase 1 Basic Tests: PASSED" = สำเร็จ!**
