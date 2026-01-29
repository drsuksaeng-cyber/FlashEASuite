# ⚡ Quick Reference Guide

**FlashEASuite V2 - License Generator**  
**คำสั่งที่ใช้บ่อย - ดูอย่างรวดเร็ว**

---

## 🚀 **เริ่มต้นใช้งาน (First Time)**

```bash
# 1. ไปที่ directory
cd FlashEASuite_V2/02_Brain/tools/license_generator

# 2. สร้าง RSA keys (ครั้งเดียว!)
python generate_keys.py

# 3. ทดสอบระบบ
cd ../..
python test_license_system.py
```

---

## 📊 **สร้าง Licenses (CSV Mode)**

```bash
cd tools/license_generator

# แบบ default (ใช้ clients_template.csv)
python generate_from_csv.py

# แบบระบุไฟล์
python generate_from_csv.py path/to/clients.csv
```

---

## 💬 **สร้าง License (Interactive Mode)**

```bash
cd tools/license_generator
python generate_single.py
# ตอบคำถามตามที่ระบบถาม
```

---

## ✅ **ตรวจสอบ License**

```bash
cd tools/license_generator

# ตรวจสอบทีละไฟล์
python verify_license.py licenses/FLASH-202601-XXXX.key

# ตรวจสอบทั้งหมด (Windows)
for %f in (licenses\*.key) do python verify_license.py "%f"

# ตรวจสอบทั้งหมด (macOS/Linux)
for f in licenses/*.key; do python verify_license.py "$f"; done
```

---

## 🧪 **ทดสอบระบบ**

```bash
cd 02_Brain
python test_license_system.py
# ควรได้ 7/7 tests passed
```

---

## 📁 **จัดการไฟล์**

```bash
# ดูจำนวน licenses
ls licenses/*.key | wc -l

# Copy license
cp licenses/FLASH-202601-XXXX.key /path/to/send/

# Backup
cp -r licenses/ backup/licenses_$(date +%Y%m%d)/

# Backup private key (สำคัญมาก!)
cp keys/server_private.pem backup/private_key_$(date +%Y%m%d).pem
```

---

## 🔍 **ดูข้อมูล License**

```bash
# ดูเนื้อหา license
cat licenses/FLASH-202601-XXXX.key

# ดูแบบสวย (ถ้ามี jq)
cat licenses/FLASH-202601-XXXX.key | jq .

# ดูเฉพาะ license_id
cat licenses/FLASH-202601-XXXX.key | grep "license_id"

# ดูเฉพาะ expiry_date
cat licenses/FLASH-202601-XXXX.key | grep "expiry_date"
```

---

## 📊 **CSV Template ด่วน**

```csv
client_name,client_email,license_type,max_slots,expiry_date,strategies,hidden_tpsl,trailing_stop,multi_symbol,max_symbols
John Doe,john@example.com,reporting,5,2027-12-31,"Grid,Spike,Trend,Range",true,true,true,10
Jane Smith,jane@example.com,premium,10,2027-12-31,"Grid,Spike,Trend,Range",true,true,true,10
Test User,test@example.com,trial,1,2026-02-22,Grid,false,false,false,1
```

---

## 🔐 **License Types (เลือกอย่างรวดเร็ว)**

| Type | Grace | Use For | CSV Value |
|------|-------|---------|-----------|
| Standalone | 0 days | Offline | `standalone` |
| Trial | 3 days | Testing | `trial` |
| Reporting | 7 days | Regular | `reporting` |
| Premium | 14 days | VIP | `premium` |

---

## 🎯 **Strategies (เลือกอย่างรวดเร็ว)**

```csv
# Full package
Grid,Spike,Trend,Range

# Basic
Grid

# Intermediate
Grid,Spike

# Advanced
Grid,Spike,Trend
```

---

## ⚙️ **Common Settings**

```csv
# VIP Customer
...,premium,10,2028-12-31,"Grid,Spike,Trend,Range",true,true,true,10,...

# Standard Customer
...,reporting,5,2027-12-31,"Grid,Spike,Trend,Range",true,true,true,10,...

# Trial User
...,trial,1,2026-02-22,Grid,false,false,false,1,...

# Offline User
...,standalone,1,2030-12-31,"Grid,Spike,Trend,Range",true,true,true,10,...
```

---

## 🆘 **แก้ไขปัญหาด่วน**

```bash
# Problem: ModuleNotFoundError
pip install cryptography

# Problem: FileNotFoundError (keys)
python generate_keys.py

# Problem: Invalid signature
# ใช้ public key ที่ถูกต้อง (คู่กับ private key)

# Problem: CSV encoding
# เปิดด้วย Notepad++ → Encoding → UTF-8 → Save

# Problem: Permission denied
chmod +x *.py
```

---

## 📧 **Email Template (ส่ง License)**

```
Subject: FlashEASuite V2 - Your License Key

Dear [Name],

Attached: Your FlashEASuite V2 license

Details:
- License ID: FLASH-202601-XXXX
- Type: reporting
- Expires: 2027-01-22
- Max Devices: 5

Installation:
1. Download EA
2. Place license in [path]
3. Start trading

Support: support@example.com

Best regards,
FlashEA Team
```

---

## 🎓 **Python API (Advanced)**

```python
# Create license programmatically
from generate_from_csv import create_license_from_row
from sign_license import create_signed_license

row = {
    'client_name': 'John Doe',
    'client_email': 'john@example.com',
    'license_type': 'reporting',
    'max_slots': '5',
    'expiry_date': '2027-12-31',
    'strategies': 'Grid,Spike',
    # ... other fields ...
}

license = create_license_from_row(row)
signed = create_signed_license(license, 'keys/server_private.pem')

# Save
import json
with open(f"licenses/{signed['license_id']}.key", 'w') as f:
    json.dump(signed, f, indent=2)
```

---

```python
# Verify license
from verify_license import verify_license_file

is_valid = verify_license_file(
    'licenses/FLASH-202601-XXXX.key',
    'keys/server_public.pem'
)

print("✅ Valid" if is_valid else "❌ Invalid")
```

---

## 📂 **Directory Structure (ด่วน)**

```
02_Brain/tools/license_generator/
├── generate_keys.py           # สร้าง RSA keys (ครั้งเดียว)
├── generate_from_csv.py       # สร้างจาก CSV ⭐ ใช้บ่อย
├── generate_single.py         # สร้างแบบ interactive ⭐ ใช้บ่อย
├── verify_license.py          # ตรวจสอบ ⭐ ใช้บ่อย
├── sign_license.py            # Module (ใช้ภายใน)
├── keys/
│   ├── server_private.pem     # ⚠️ SECRET
│   └── server_public.pem      # Share to MQL5
├── templates/
│   └── clients_template.csv   # Template
├── licenses/                  # Output folder
└── logs/                      # Logs
```

---

## ⏱️ **Estimated Time**

```
Task                          Time
─────────────────────────────────────
First-time setup              10-15 min
Generate keys                 < 1 min
Create 1 license (CSV)        < 10 sec
Create 1 license (Interactive) 2-3 min
Create 100 licenses (CSV)     ~30 sec
Verify 1 license              < 1 sec
Verify 100 licenses           ~10 sec
```

---

## ✅ **Checklist ก่อนส่งลูกค้า**

```
☐ Generate license สำเร็จ
☐ Verify license (✅ VALID)
☐ ตรวจข้อมูลลูกค้า
☐ ตรวจ license_type
☐ ตรวจวันหมดอายุ
☐ ตรวจ strategies
☐ Backup license
☐ Send email + attachment
```

---

## 📖 **ดูเอกสารเพิ่มเติม**

| Document | Purpose |
|----------|---------|
| INSTALLATION_GUIDE.md | ติดตั้งและเริ่มต้น |
| USER_GUIDE.md | วิธีใช้งานแบบละเอียด |
| FILE_EXPLANATIONS.md | อธิบายไฟล์แต่ละตัว |
| FAQ.md | คำถามที่พบบ่อย |
| HANDOFF_PACKAGE.md | Integration กับ MQL5 |

---

**Quick Tip:** บันทึกหน้านี้ไว้สำหรับดูคำสั่งอย่างรวดเร็ว! 🚀

---

**Version:** 1.0  
**Updated:** 2026-01-22
