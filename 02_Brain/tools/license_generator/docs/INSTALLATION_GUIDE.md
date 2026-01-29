# 📦 คู่มือการติดตั้งและทดสอบ License Generator System

**FlashEASuite V2 - License Generator**  
**สำหรับ: ผู้ดูแลระบบและนักพัฒนา**

---

## 📋 **สารบัญ**

1. [ข้อกำหนดระบบ](#ข้อกำหนดระบบ)
2. [การติดตั้ง Python และ Libraries](#การติดตั้ง-python-และ-libraries)
3. [การติดตั้ง License Generator](#การติดตั้ง-license-generator)
4. [การสร้าง RSA Keys](#การสร้าง-rsa-keys)
5. [การทดสอบระบบ](#การทดสอบระบบ)
6. [การแก้ไขปัญหา](#การแก้ไขปัญหา)

---

## ข้อกำหนดระบบ

### **ระบบปฏิบัติการ:**
- ✅ Windows 10/11
- ✅ macOS 10.15+
- ✅ Linux (Ubuntu 20.04+, CentOS 8+)

### **ซอฟต์แวร์ที่ต้องมี:**
- ✅ Python 3.8 หรือสูงกว่า
- ✅ pip (Python package manager)
- ✅ Text editor (VSCode, Notepad++, หรืออื่นๆ)

### **พื้นที่ฮาร์ดดิสก์:**
- ขั้นต่ำ: 50 MB
- แนะนำ: 200 MB (สำหรับ licenses จำนวนมาก)

---

## การติดตั้ง Python และ Libraries

### **Step 1: ตรวจสอบ Python**

#### **Windows:**
```cmd
python --version
```

#### **macOS / Linux:**
```bash
python3 --version
```

**ผลลัพธ์ที่ต้องการ:**
```
Python 3.8.x หรือสูงกว่า
```

**ถ้ายังไม่มี Python:**
- Windows: ดาวน์โหลดจาก https://www.python.org/downloads/
- macOS: `brew install python3`
- Linux: `sudo apt install python3 python3-pip`

---

### **Step 2: ติดตั้ง cryptography library**

นี่คือ library เดียวที่ต้องการ!

#### **Windows:**
```cmd
pip install cryptography
```

#### **macOS / Linux:**
```bash
pip3 install cryptography
```

**ตรวจสอบการติดตั้ง:**
```python
python -c "from cryptography.hazmat.primitives.asymmetric import rsa; print('✅ OK')"
```

ถ้าขึ้น `✅ OK` แสดงว่าติดตั้งสำเร็จ!

---

## การติดตั้ง License Generator

### **Step 1: วางไฟล์**

คัดลอกโฟลเดอร์ทั้งหมดไปยัง FlashEASuite V2:

```
FlashEASuite_V2/
└── 02_Brain/
    └── tools/
        └── license_generator/    ← คัดลอกโฟลเดอร์นี้มาทั้งหมด
            ├── generate_keys.py
            ├── generate_from_csv.py
            ├── generate_single.py
            ├── sign_license.py
            ├── verify_license.py
            ├── keys/              (สร้างใหม่)
            ├── templates/
            │   └── clients_template.csv
            ├── licenses/          (สร้างใหม่)
            └── logs/              (สร้างใหม่)
```

---

### **Step 2: สร้างโฟลเดอร์ที่จำเป็น**

#### **Windows:**
```cmd
cd FlashEASuite_V2\02_Brain\tools\license_generator
mkdir keys licenses logs
```

#### **macOS / Linux:**
```bash
cd FlashEASuite_V2/02_Brain/tools/license_generator
mkdir -p keys licenses logs
```

---

### **Step 3: ตรวจสอบโครงสร้าง**

```cmd
dir /B     # Windows
ls -1      # macOS/Linux
```

**ต้องเห็น:**
```
generate_from_csv.py
generate_keys.py
generate_single.py
keys/
licenses/
logs/
sign_license.py
templates/
verify_license.py
```

✅ ถ้าครบแล้ว พร้อมใช้งาน!

---

## การสร้าง RSA Keys

### **Step 1: เปิด Terminal / Command Prompt**

#### **Windows:**
```cmd
cd FlashEASuite_V2\02_Brain\tools\license_generator
```

#### **macOS / Linux:**
```bash
cd FlashEASuite_V2/02_Brain/tools/license_generator
```

---

### **Step 2: รัน Key Generator**

```bash
python generate_keys.py
```

**ผลลัพธ์:**
```
============================================================
FlashEASuite V2 - RSA Key Generator
============================================================

🔑 Generating 2048-bit RSA key pair...
✅ Private key saved: keys/server_private.pem
   ⚠️  KEEP THIS SECRET! Do not share!
✅ Public key saved: keys/server_public.pem
   📤 Share this with EA (embed in code)

============================================================
✅ RSA Key Pair Generation Complete!
============================================================
```

---

### **Step 3: ตรวจสอบไฟล์ Key**

```bash
ls keys/              # macOS/Linux
dir keys\             # Windows
```

**ต้องเห็น:**
```
server_private.pem    (344 bytes)
server_public.pem     (451 bytes)
```

---

### **Step 4: ⚠️ Backup Private Key**

**สำคัญมาก!** ให้ backup `server_private.pem` ไว้หลายที่:

```bash
# ตัวอย่าง Backup
cp keys/server_private.pem ~/Backup/license_private_key_backup_20260122.pem

# สำหรับ Windows
copy keys\server_private.pem C:\Backup\license_private_key_backup_20260122.pem
```

**อย่าลืม:** ถ้า private key หาย จะสร้าง license ใหม่ไม่ได้!

---

## การทดสอบระบบ

### **Test 1: ทดสอบ Sign/Verify (พื้นฐาน)**

```bash
python sign_license.py
```

**ผลลัพธ์ที่ต้องการ:**
```
Testing license signing...
✅ Signature generated: bZWjYDYYmOy...
   Signature length: 344 chars
```

---

### **Test 2: ทดสอบ CSV Generation**

```bash
python generate_from_csv.py
```

**ผลลัพธ์ที่ต้องการ:**
```
======================================================================
FlashEASuite V2 - License Generator (CSV Mode)
======================================================================

📋 Processing client #1: Somchai Jaidee
   ✅ License generated: FLASH-202601-AE930C51
   📁 Saved to: licenses/FLASH-202601-AE930C51.key
   ...

======================================================================
✅ Generated 4 licenses successfully!
======================================================================
```

---

### **Test 3: ทดสอบ Verification**

```bash
python verify_license.py licenses/FLASH-202601-AE930C51.key
```

**ผลลัพธ์ที่ต้องการ:**
```
============================================================
FlashEASuite V2 - License Verifier
============================================================
✅ License FLASH-202601-AE930C51 is VALID
   Client: N/A
   Type: reporting
   Expiry: 2027-01-22
```

---

### **Test 4: ทดสอบครบวงจร (Comprehensive)**

กลับไปที่ `02_Brain/`:

```bash
cd ../..
python test_license_system.py
```

**ผลลัพธ์ที่ต้องการ:**
```
======================================================================
FlashEASuite V2 - License System Test Suite
======================================================================

TEST 1: RSA Key Generation         ✅ PASSED
TEST 2: License Creation            ✅ PASSED
TEST 3: License Signing             ✅ PASSED
TEST 4: License Verification        ✅ PASSED
TEST 5: Tamper Detection            ✅ PASSED
TEST 6: CSV Batch Generation        ✅ PASSED
TEST 7: File-based Verification     ✅ PASSED

======================================================================
RESULTS: 7/7 tests passed
✅ ALL TESTS PASSED!
======================================================================
```

---

### **Test 5: ทดสอบ Tamper Detection (ความปลอดภัย)**

#### **Step 1: สร้าง license**
```bash
cd tools/license_generator
python generate_from_csv.py
```

#### **Step 2: คัดลอก license**
```bash
cp licenses/FLASH-202601-AE930C51.key licenses/TEST_TAMPER.key
```

#### **Step 3: แก้ไขไฟล์** (เปลี่ยน license_type)
เปิดไฟล์ `licenses/TEST_TAMPER.key` ด้วย text editor:

แก้ไข:
```json
"license_type": "reporting"
```
เป็น:
```json
"license_type": "premium"
```

บันทึกไฟล์

#### **Step 4: ทดสอบ verify**
```bash
python verify_license.py licenses/TEST_TAMPER.key
```

**ผลลัพธ์ที่ต้องการ:**
```
❌ Invalid signature
❌ License is INVALID or TAMPERED
```

✅ **ถ้าขึ้น Invalid แสดงว่าระบบตรวจจับการแก้ไขได้!**

---

## การแก้ไขปัญหา

### **ปัญหา 1: ModuleNotFoundError: No module named 'cryptography'**

**สาเหตุ:** ไม่มี cryptography library

**แก้ไข:**
```bash
pip install cryptography

# หรือ
pip3 install cryptography
```

---

### **ปัญหา 2: FileNotFoundError: keys/server_private.pem**

**สาเหตุ:** ยังไม่ได้สร้าง RSA keys

**แก้ไข:**
```bash
cd tools/license_generator
python generate_keys.py
```

---

### **ปัญหา 3: Permission denied (macOS/Linux)**

**สาเหตุ:** ไม่มีสิทธิ์ execute

**แก้ไข:**
```bash
chmod +x *.py
```

---

### **ปัญหา 4: UnicodeDecodeError (Windows)**

**สาเหตุ:** CSV encoding ไม่ถูกต้อง

**แก้ไข:**
- เปิด CSV ด้วย Notepad++
- Encoding → Convert to UTF-8
- บันทึกไฟล์

---

### **ปัญหา 5: จำนวน licenses น้อยกว่าที่คาดหวัง**

**สาเหตุ:** CSV มี blank rows หรือ invalid data

**แก้ไข:**
- เปิด CSV
- ลบ blank rows
- ตรวจสอบว่าทุก required field มีข้อมูล
- บันทึกและ generate ใหม่

---

### **ปัญหา 6: Signature verification failed (แม้ไม่ได้แก้ไข)**

**สาเหตุ:** ใช้ private/public key คนละคู่กัน

**ตรวจสอบ:**
```bash
# ดูวันที่สร้างไฟล์
ls -lh keys/

# ถ้าเวลาไม่ตรงกัน แสดงว่าสร้างคนละครั้ง
# วิธีแก้: ลบและสร้างใหม่ทั้งหมด
rm keys/*.pem
python generate_keys.py
```

---

## ✅ Checklist การติดตั้ง

ก่อนใช้งาน Production ให้ตรวจสอบ:

```
☐ Python 3.8+ ติดตั้งแล้ว
☐ cryptography library ติดตั้งแล้ว
☐ โฟลเดอร์ครบ (keys, licenses, logs, templates)
☐ RSA keys สร้างแล้ว (server_private.pem, server_public.pem)
☐ Backup private key แล้ว
☐ Test suite ผ่านทั้งหมด (7/7)
☐ Tamper detection ทำงาน
☐ CSV template พร้อมใช้งาน
```

---

## 📊 เวลาที่ใช้ในการติดตั้ง

```
การติดตั้ง Python:           5-10 นาที (ถ้ายังไม่มี)
การติดตั้ง cryptography:    1-2 นาที
การวางไฟล์และสร้างโฟลเดอร์:  2-3 นาที
การสร้าง RSA keys:          < 1 นาที
การทดสอบระบบ:               5-10 นาที
────────────────────────────────────────
รวม:                        15-25 นาที
```

---

## 🎯 หลังจากติดตั้งเสร็จ

ทำอะไรต่อ?

1. ✅ อ่าน [USER_GUIDE.md](USER_GUIDE.md) - คู่มือการใช้งาน
2. ✅ อ่าน [FILE_EXPLANATIONS.md](FILE_EXPLANATIONS.md) - อธิบายไฟล์แต่ละตัว
3. ✅ ทดลองสร้าง license จาก CSV
4. ✅ ทดลองสร้าง license แบบ interactive
5. ✅ ส่ง `server_public.pem` ให้ MQL5 team

---

## 📞 ติดต่อและสนับสนุน

- 📖 เอกสาร: README.md, USER_GUIDE.md
- 🐛 ปัญหา: ดู FAQ.md
- 💬 คำถาม: ดู FILE_EXPLANATIONS.md

---

**สุดท้าย:** ถ้าทุกอย่างผ่าน ระบบพร้อมใช้งาน Production แล้ว! 🎉

---

**Version:** 1.0  
**Updated:** 2026-01-22  
**Status:** ✅ Production Ready
