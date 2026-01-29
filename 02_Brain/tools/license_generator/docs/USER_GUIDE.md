# 📖 คู่มือการใช้งาน License Generator

**FlashEASuite V2 - License Generator System**  
**สำหรับ: ผู้ดูแลระบบและทีมขาย**

---

## 🎯 **ภาพรวม**

License Generator ช่วยให้คุณสร้าง licenses สำหรับลูกค้า FlashEASuite V2 ได้ง่ายๆ มี 2 วิธี:

1. **CSV Mode** - สร้างหลาย licenses พร้อมกัน (แนะนำ)
2. **Interactive Mode** - สร้างทีละ license

---

## 📋 **เริ่มต้นใช้งาน**

### **ก่อนเริ่ม ให้แน่ใจว่า:**

✅ ติดตั้งระบบเรียบร้อยแล้ว (ดู INSTALLATION_GUIDE.md)  
✅ มี RSA keys แล้ว (server_private.pem, server_public.pem)  
✅ ทดสอบระบบผ่านแล้ว (7/7 tests)

---

## 🎬 **Quick Start (3 นาที)**

### **วิธีที่ 1: สร้างจาก CSV (แนะนำ)**

```bash
# 1. ไปที่ folder
cd 02_Brain/tools/license_generator

# 2. สร้าง licenses
python generate_from_csv.py

# 3. เช็คผลลัพธ์
ls licenses/

# 4. ตรวจสอบ
python verify_license.py licenses/FLASH-*.key
```

✅ เสร็จ! ได้ licenses ใน `licenses/` folder

---

### **วิธีที่ 2: สร้างแบบ Interactive**

```bash
# 1. รันโปรแกรม
python generate_single.py

# 2. ตอบคำถาม
Client Name: Somchai Jaidee
Email: somchai@example.com
...

# 3. เสร็จ!
✅ License generated: FLASH-202601-XXXX.key
```

---

## 📊 **การใช้งานแบบ CSV (แนะนำ)**

### **ขั้นตอน:**

#### **1. เตรียม CSV File**

เปิดไฟล์ `templates/clients_template.csv` ด้วย Excel หรือ Google Sheets:

| client_name | client_email | license_type | max_slots | expiry_date | strategies | ... |
|-------------|--------------|--------------|-----------|-------------|------------|-----|
| Somchai Jaidee | somchai@example.com | reporting | 5 | 2027-01-22 | Grid,Spike,Trend,Range | ... |
| Suda Tanaka | suda@example.com | premium | 3 | 2027-01-22 | Grid,Spike | ... |

#### **2. แก้ไขข้อมูล**

- ใส่ชื่อลูกค้าจริง
- ใส่อีเมลจริง
- เลือก license_type ที่เหมาะสม
- ตั้งวันหมดอายุ

#### **3. บันทึกไฟล์**

บันทึกเป็น UTF-8 CSV:
- Excel: File → Save As → CSV UTF-8
- Google Sheets: File → Download → CSV

#### **4. Generate Licenses**

```bash
python generate_from_csv.py path/to/your_file.csv
```

#### **5. ตรวจสอบผลลัพธ์**

```bash
# ดูจำนวน licenses
ls -l licenses/

# Verify ทั้งหมด
for f in licenses/*.key; do python verify_license.py "$f"; done
```

#### **6. ส่งให้ลูกค้า**

- แนบไฟล์ `.key` ใน email
- แนะนำวิธีติดตั้ง
- บอกวันหมดอายุ

---

## 💬 **การใช้งานแบบ Interactive**

### **เหมาะสำหรับ:**
- สร้าง license ด่วน
- ลูกค้าเพียงคนเดียว
- ไม่ต้องการ CSV

### **ขั้นตอน:**

```bash
python generate_single.py
```

### **จะถามคำถาม:**

#### **1. Client Information:**
```
Client Name: ________________
Client Email: _______________
Client Phone: _______________ (optional)
MT5 Account Number: _________ (optional)
Broker Name: ________________ (optional)
```

#### **2. License Configuration:**
```
License Types:
  1. standalone
  2. trial
  3. reporting
  4. premium
Select license type (1-4) [3]: ___
Max slots [5]: ___
```

#### **3. Validity Period:**
```
Issue Date (YYYY-MM-DD) [2026-01-22]: ___
Expiry Date (YYYY-MM-DD) [2027-01-22]: ___
```

#### **4. Features:**
```
Strategies (comma-separated) [Grid,Spike,Trend,Range]: ___
Hidden TP/SL [Y/n]: ___
Trailing Stop [Y/n]: ___
Multi-Symbol [Y/n]: ___
Max Symbols [10]: ___
Notes (optional): ___
```

#### **5. ผลลัพธ์:**
```
✅ LICENSE GENERATED SUCCESSFULLY!

License ID: FLASH-202601-XXXX
Client: Somchai Jaidee
Type: reporting
Expires: 2027-01-22

Saved to: licenses/FLASH-202601-XXXX.key
```

---

## 🔍 **การตรวจสอบ License**

### **วิธีที่ 1: ตรวจสอบทีละไฟล์**

```bash
python verify_license.py licenses/FLASH-202601-XXXX.key
```

**ผลลัพธ์ที่ดี:**
```
✅ License FLASH-202601-XXXX is VALID
   Client: Somchai Jaidee
   Type: reporting
   Expiry: 2027-01-22
```

**ผลลัพธ์ที่แย่:**
```
❌ Invalid signature
❌ License is INVALID or TAMPERED
```

---

### **วิธีที่ 2: ตรวจสอบทั้งหมด (Batch)**

#### **Windows:**
```cmd
for %f in (licenses\*.key) do python verify_license.py "%f"
```

#### **macOS / Linux:**
```bash
for f in licenses/*.key; do python verify_license.py "$f"; done
```

---

## 📦 **License Types (เลือกให้เหมาะสม)**

### **1. standalone**
```
ใช้สำหรับ: Offline trading
Grace Days: 0 (ไม่มี online check)
Features: Full
ราคา: แพงที่สุด
```

**เหมาะสำหรับ:**
- ลูกค้าที่ต้องการใช้งาน offline
- ไม่ต้องการ online verification
- Long-term license (5+ years)

**ตัวอย่าง CSV:**
```csv
...,standalone,...,2030-12-31,...
```

---

### **2. trial**
```
ใช้สำหรับ: ทดลองใช้
Grace Days: 3
Features: Limited (Grid only)
ระยะเวลา: 30 days
ราคา: ฟรี
```

**เหมาะสำหรับ:**
- ลูกค้าทดลองใช้
- Demo accounts
- Short-term testing

**ตัวอย่าง CSV:**
```csv
...,trial,Grid,false,false,false,1,...,2026-02-22,...
```

---

### **3. reporting**
```
ใช้สำหรับ: HFT traders (แนะนำ)
Grace Days: 7
Features: Full
Online Check: Monthly
ราคา: Standard
```

**เหมาะสำหรับ:**
- ลูกค้าทั่วไป
- Active traders
- Regular renewals

**ตัวอย่าง CSV:**
```csv
...,reporting,"Grid,Spike,Trend,Range",true,true,true,10,...,2027-01-22,...
```

---

### **4. premium**
```
ใช้สำหรับ: VIP customers
Grace Days: 14
Features: Full + Priority support
Online Check: Monthly
ราคา: Premium
```

**เหมาะสำหรับ:**
- VIP clients
- Large accounts
- Institutional traders

**ตัวอย่าง CSV:**
```csv
...,premium,"Grid,Spike,Trend,Range",true,true,true,10,...,2027-01-22,VIP Customer
```

---

## 🎯 **Strategies (กลยุทธ์)**

### **Grid**
- Grid trading
- ใช้กับตลาด ranging
- แนะนำ: EURUSD, GBPUSD

### **Spike**
- Scalping on spikes
- ใช้กับตลาด volatile
- แนะนำ: XAUUSD, GBPJPY

### **Trend**
- Trend following
- ใช้กับตลาด trending
- แนะนำ: XAUUSD, USDJPY

### **Range**
- Range trading
- ใช้กับตลาด sideways
- แนะนำ: EURUSD, USDCHF

**ตัวอย่างการเลือก:**
- Full package: `Grid,Spike,Trend,Range`
- Basic: `Grid`
- Intermediate: `Grid,Spike`
- Advanced: `Grid,Spike,Trend`

---

## 💡 **Best Practices**

### **1. การตั้งชื่อไฟล์ CSV**
```
✅ ดี:
- clients_2026_january.csv
- vip_customers_q1_2026.csv
- trial_users_week1.csv

❌ ไม่ดี:
- temp.csv
- test.csv
- 123.csv
```

---

### **2. การจัดเก็บ Licenses**
```
licenses/
├── 2026-01/          # แยกตามเดือน
│   ├── FLASH-202601-XXXX.key
│   └── FLASH-202601-YYYY.key
├── 2026-02/
└── archive/          # License เก่า
```

---

### **3. การ Backup**
```bash
# Backup licenses ทุกวัน
cp -r licenses/ backup/licenses_20260122/

# Backup private key (สำคัญมาก!)
cp keys/server_private.pem backup/keys/server_private_20260122.pem
```

---

### **4. การส่งให้ลูกค้า**

**Email Template:**
```
Subject: FlashEASuite V2 - Your License Key

Dear [Client Name],

Thank you for purchasing FlashEASuite V2!

Attached: FLASH-202601-XXXX.key

License Details:
- Type: [reporting/premium/trial]
- Expires: [YYYY-MM-DD]
- Max Installations: [5]
- Strategies: [Grid, Spike, Trend, Range]

Installation:
1. Download FlashEASuite V2
2. Place license file in [path]
3. Start EA

Support: support@example.com

Best regards,
FlashEA Team
```

---

## 🔧 **การแก้ไข License (หลังสร้าง)**

⚠️ **ไม่สามารถแก้ไข license ที่สร้างแล้ว!**

**ถ้าต้องการเปลี่ยน:**
1. สร้าง license ใหม่
2. REVOKE license เก่า (ในระบบ)
3. ส่ง license ใหม่ให้ลูกค้า

**ตัวอย่าง:**
```bash
# ลูกค้าขอเพิ่ม strategies จาก Grid → Grid+Spike

# 1. แก้ไข CSV
nano clients.csv
# เปลี่ยน: Grid → Grid,Spike

# 2. Generate ใหม่
python generate_from_csv.py clients.csv

# 3. ส่งไฟล์ใหม่ให้ลูกค้า
```

---

## 📊 **สถิติและรายงาน**

### **นับจำนวน Licenses**

```bash
# Total licenses
ls -1 licenses/*.key | wc -l

# By month
ls -1 licenses/FLASH-202601-*.key | wc -l  # January 2026
ls -1 licenses/FLASH-202602-*.key | wc -l  # February 2026
```

---

### **สร้างรายงาน**

```bash
# List all licenses
for f in licenses/*.key; do
    echo "Checking $f"
    python verify_license.py "$f"
done > report.txt
```

---

## ❓ **คำถามที่พบบ่อย (FAQ)**

### **Q1: ต้องสร้าง keys ใหม่ทุกครั้งหรือไม่?**
A: ไม่! สร้างครั้งเดียวตอนติดตั้ง ถ้าสร้างใหม่ licenses เก่าจะใช้ไม่ได้

---

### **Q2: License หายไป สร้างใหม่ให้เหมือนเดิมได้ไหม?**
A: ไม่ได้! License ID เป็น unique (มี timestamp + UUID)
วิธีแก้: เก็บ backup licenses ไว้ดีๆ

---

### **Q3: ลูกค้าขอเปลี่ยน features ได้ไหม?**
A: ได้! แต่ต้องสร้าง license ใหม่และ REVOKE เก่า

---

### **Q4: จำนวน max_slots คืออะไร?**
A: จำนวนเครื่องที่ติดตั้งได้พร้อมกัน
- 1 slot = 1 เครื่อง
- 5 slots = 5 เครื่อง (แนะนำ)

---

### **Q5: Grace days คืออะไร?**
A: จำนวนวันที่ยังใช้งานได้หลังหมดอายุ
- standalone: 0 days
- trial: 3 days
- reporting: 7 days
- premium: 14 days

---

### **Q6: hwid ในไฟล์ CSV ต้องใส่หรือไม่?**
A: ไม่ต้อง! ปล่อยว่างไว้ EA จะ generate เองตอน activate

---

### **Q7: CSV มี error บรรทัดไหนจะรู้ได้อย่างไร?**
A: ระบบจะแสดง error และบรรทัดที่เป็นปัญหา
```
❌ Error in row 5: Invalid license_type
```

---

### **Q8: ส่ง license ให้ลูกค้าทาง email ปลอดภัยหรือไม่?**
A: ปลอดภัย! License มี HWID binding ใช้ได้แค่เครื่องเดียว

---

### **Q9: License หมดอายุแล้วจะเป็นอย่างไร?**
A: 
1. มี grace period (3-14 days)
2. หลัง grace period → Limited Mode
   - Max lot = 0.01
   - 1 symbol only (EURUSD)
   - Grid strategy only

---

### **Q10: สร้าง 1000 licenses พร้อมกันได้ไหม?**
A: ได้! CSV mode รองรับไม่จำกัดจำนวน
```bash
python generate_from_csv.py clients_1000.csv
# ใช้เวลา ~30 seconds
```

---

## 🆘 **การขอความช่วยเหลือ**

### **เมื่อเจอปัญหา:**

1. ✅ อ่าน INSTALLATION_GUIDE.md
2. ✅ อ่าน FAQ ข้างบน
3. ✅ ตรวจสอบ error messages
4. ✅ รัน test_license_system.py

### **ยังไม่ได้:**
- ดู FILE_EXPLANATIONS.md (อธิบายแต่ละไฟล์)
- ดู logs/ folder
- ติดต่อ support

---

## 📝 **Checklist ก่อนส่งให้ลูกค้า**

```
☐ Generate license สำเร็จ
☐ Verify license (✅ VALID)
☐ ตรวจสอบข้อมูลลูกค้าถูกต้อง
☐ ตรวจสอบ license_type ถูกต้อง
☐ ตรวจสอบวันหมดอายุถูกต้อง
☐ ตรวจสอบ strategies ถูกต้อง
☐ เตรียม email แนบ license
☐ ส่ง installation guide ให้ลูกค้า
☐ บันทึกข้อมูลใน CRM/Database
☐ Backup license file
```

---

## 🎉 **สรุป**

**License Generator ช่วยให้คุณ:**
- ✅ สร้าง licenses ง่ายและรวดเร็ว
- ✅ จัดการลูกค้าจำนวนมาก
- ✅ ป้องกันการปลอมแปลง
- ✅ ควบคุม features ได้ยืดหยุ่น

**สำคัญที่สุด:**
- 🔐 เก็บ `server_private.pem` ไว้ดีๆ
- 💾 Backup licenses เป็นประจำ
- ✅ Verify ก่อนส่งให้ลูกค้าทุกครั้ง

---

**Happy Licensing! 🚀**

---

**Version:** 1.0  
**Updated:** 2026-01-22  
**Author:** FlashEA Team
