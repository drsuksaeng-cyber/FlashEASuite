# ❓ คำถามที่พบบ่อย (FAQ)

**FlashEASuite V2 - License Generator System**

---

## 📋 **หมวดหมู่**

1. [การติดตั้งและเริ่มต้น](#การติดตั้งและเริ่มต้น)
2. [การสร้าง License](#การสร้าง-license)
3. [การตรวจสอบ License](#การตรวจสอบ-license)
4. [ความปลอดภัย](#ความปลอดภัย)
5. [การแก้ไขปัญหา](#การแก้ไขปัญหา)
6. [การใช้งานขั้นสูง](#การใช้งานขั้นสูง)

---

## การติดตั้งและเริ่มต้น

### Q1: ต้องติดตั้ง Python version ไหน?
**A:** Python 3.8 หรือสูงกว่า

ตรวจสอบ version:
```bash
python --version
# หรือ
python3 --version
```

ถ้ายังไม่มี: https://www.python.org/downloads/

---

### Q2: ต้องติดตั้ง library อะไรบ้าง?
**A:** แค่ `cryptography` เท่านั้น!

```bash
pip install cryptography
```

---

### Q3: ติดตั้งเสร็จแล้ว ต้องทำอะไรต่อ?
**A:** สร้าง RSA keys:

```bash
cd 02_Brain/tools/license_generator
python generate_keys.py
```

จะได้:
- `keys/server_private.pem` (เก็บเป็นความลับ!)
- `keys/server_public.pem` (แชร์ให้ MQL5)

---

### Q4: จำเป็นต้อง generate keys ทุกครั้งหรือไม่?
**A:** ❌ **ไม่!** สร้างครั้งเดียวตอนติดตั้ง

⚠️ **สำคัญ:** ถ้าสร้าง keys ใหม่ licenses เก่าจะใช้ไม่ได้!

---

### Q5: หาก server_private.pem หายจะทำอย่างไร?
**A:** 😱 **ปัญหาใหญ่!**

ผลกระทบ:
- ❌ สร้าง license ใหม่ไม่ได้
- ❌ Licenses เก่าจะใช้ไม่ได้ (ถ้าสร้าง keys ใหม่)

**วิธีแก้:**
- ใช้ backup (ถ้ามี)
- หรือสร้าง keys ใหม่ (แต่ต้อง re-issue licenses ทั้งหมด)

**การป้องกัน:**
```bash
# Backup หลายที่
cp keys/server_private.pem ~/Backup/
cp keys/server_private.pem /external_drive/
cp keys/server_private.pem /cloud_storage/
```

---

## การสร้าง License

### Q6: มีวิธีสร้าง license กี่แบบ?
**A:** 2 แบบ:

1. **CSV Mode (แนะนำ)** - สร้างหลาย licenses พร้อมกัน
2. **Interactive Mode** - สร้างทีละ license

---

### Q7: แบบไหนดีกว่ากัน?
**A:** ขึ้นอยู่กับสถานการณ์:

| Scenario | แนะนำ | เหตุผล |
|----------|-------|--------|
| สร้าง 10+ licenses | CSV | เร็วกว่า, มีระเบียบ |
| สร้าง 1-2 licenses | Interactive | สะดวก, ไม่ต้อง CSV |
| มีข้อมูลใน Excel | CSV | Copy-paste ได้ |
| สร้างด่วน | Interactive | ไม่ต้องเตรียม CSV |

---

### Q8: CSV file ต้องเป็น format อะไร?
**A:** UTF-8 CSV

**Excel:**
- File → Save As → CSV UTF-8 (Comma delimited)

**Google Sheets:**
- File → Download → Comma Separated Values (.csv)

---

### Q9: Required fields ใน CSV มีอะไรบ้าง?
**A:** Fields ที่ **ต้อง** มี (✅):

```
✅ client_name
✅ client_email
✅ license_type
✅ max_slots
✅ issued_date
✅ expiry_date
✅ strategies
✅ hidden_tpsl
✅ trailing_stop
✅ multi_symbol
✅ max_symbols
```

Fields ที่ **ไม่บังคับ** (⚠️):
```
⚠️ client_phone
⚠️ account_number
⚠️ broker_name
⚠️ notes
```

---

### Q10: hwid field ต้องใส่อะไร?
**A:** **ปล่อยว่างไว้!** (ไม่ต้องใส่)

```csv
...,hwid,...
...,,...      ← ว่างเปล่า
```

HWID จะถูก generate โดย EA ตอน activate ครั้งแรก

---

### Q11: License types มีอะไรบ้าง? แตกต่างกันอย่างไร?
**A:**

| Type | Grace Days | Best For | Price |
|------|-----------|----------|-------|
| **standalone** | 0 | Offline trading | 💰💰💰💰 |
| **trial** | 3 | Testing | ฟรี |
| **reporting** | 7 | Regular customers | 💰💰 |
| **premium** | 14 | VIP customers | 💰💰💰 |

**แนะนำ:** `reporting` สำหรับลูกค้าทั่วไป

---

### Q12: Strategies ควรใส่อย่างไร?
**A:** Comma-separated (ไม่มีช่องว่าง):

```csv
✅ ถูกต้อง:
Grid,Spike,Trend,Range
Grid,Spike
Grid

❌ ผิด:
Grid, Spike, Trend    ← มีช่องว่าง
Grid;Spike            ← ใช้ semicolon
grid,spike            ← lowercase
```

**Strategies ที่มี:**
- Grid
- Spike
- Trend
- Range

---

### Q13: Boolean fields (true/false) ต้องใส่อย่างไร?
**A:** ใช้ได้หลายแบบ:

```csv
✅ ถูกต้องทั้งหมด:
true, True, TRUE, yes, Yes, YES, 1, on, On, ON

false, False, FALSE, no, No, NO, 0, off, Off, OFF
```

**แนะนำ:** ใช้ `true` หรือ `false` (lowercase)

---

### Q14: วันที่ (dates) ต้องเป็น format อะไร?
**A:** `YYYY-MM-DD` เท่านั้น!

```csv
✅ ถูกต้อง:
2026-01-22
2027-12-31

❌ ผิด:
22/01/2026      ← DD/MM/YYYY
01-22-2026      ← MM-DD-YYYY
2026/01/22      ← slash
```

---

### Q15: ต้องการให้ license ไม่หมดอายุจะทำอย่างไร?
**A:** ตั้งวันไกลๆ:

```csv
expiry_date,license_type
2030-12-31,standalone    ← 4+ years
2050-12-31,standalone    ← 24+ years
```

⚠️ **หมายเหตุ:** `standalone` type ไม่มี online check

---

### Q16: สร้าง license แล้ว จะอยู่ที่ไหน?
**A:** `licenses/` folder

```
licenses/
├── FLASH-202601-AE930C51.key
├── FLASH-202601-890C1BCE.key
└── ...
```

---

### Q17: License ID มาจากไหน? สร้างเองได้ไหม?
**A:** **ไม่ได้!** License ID ถูก generate อัตโนมัติ

Format: `FLASH-YYYYMM-XXXXXXXX`

ตัวอย่าง:
```
FLASH-202601-AE930C51
│     │      └─ UUID (random)
│     └─ ปี+เดือน (202601 = Jan 2026)
└─ Prefix
```

---

### Q18: สร้าง 100 licenses พร้อมกันได้ไหม?
**A:** ได้! CSV mode รองรับไม่จำกัด

```bash
# Prepare CSV with 100 rows
nano clients_100.csv

# Generate
python generate_from_csv.py clients_100.csv

# Result: 100 .key files in licenses/
```

เวลาที่ใช้: ~30 seconds สำหรับ 100 licenses

---

## การตรวจสอบ License

### Q19: จะตรวจสอบว่า license ถูกต้องได้อย่างไร?
**A:** ใช้ `verify_license.py`:

```bash
python verify_license.py licenses/FLASH-202601-XXXX.key
```

**ถูกต้อง:**
```
✅ License FLASH-202601-XXXX is VALID
```

**ไม่ถูกต้อง:**
```
❌ Invalid signature
❌ License is INVALID or TAMPERED
```

---

### Q20: ต้อง verify ทุกครั้งก่อนส่งให้ลูกค้าหรือไม่?
**A:** ✅ **แนะนำ!** เพื่อความมั่นใจ

```bash
# Verify all licenses
for f in licenses/*.key; do
    python verify_license.py "$f"
done
```

---

### Q21: Invalid signature หมายความว่าอย่างไร?
**A:** มี 2 สาเหตุ:

1. **License ถูกแก้ไข** (tampered)
2. **ใช้ public key คนละคู่กับ private key**

**วิธีแก้:**
- ถ้าแก้ไข: สร้างใหม่
- ถ้า key ผิด: ใช้ key ที่ถูกต้อง

---

## ความปลอดภัย

### Q22: License ปลอดภัยแค่ไหน?
**A:** **ปลอดภัยมาก!** ด้วย:

1. ✅ RSA 2048-bit signatures
2. ✅ SHA256 hashing
3. ✅ Hardware binding (HWID)
4. ✅ Tamper detection

---

### Q23: ถ้ามีคนแก้ไข license จะเกิดอะไรขึ้น?
**A:** Signature verification จะล้มเหลว:

```bash
# แก้ไข license_type จาก trial → premium
$ nano licenses/FLASH-202601-XXXX.key
# เปลี่ยน "license_type": "trial" → "premium"

# Verify
$ python verify_license.py licenses/FLASH-202601-XXXX.key
❌ Invalid signature ← ตรวจจับได้!
```

---

### Q24: ลูกค้าสามารถคัดลอก license ไปใช้หลายเครื่องได้ไหม?
**A:** **ไม่ได้!** (ถ้า HWID ถูก bind แล้ว)

เมื่อ activate ครั้งแรก:
1. EA สร้าง HWID (unique per machine)
2. HWID ถูกเพิ่มใน `used_slots`
3. License ผูกกับเครื่องนั้น

การใช้งานเครื่องอื่น:
- ถ้ายังมี slots ว่าง → ใช้ได้ (เพิ่ม HWID ใหม่)
- ถ้า slots เต็ม → ใช้ไม่ได้

---

### Q25: max_slots คืออะไร?
**A:** จำนวนเครื่องที่ติดตั้งได้พร้อมกัน

ตัวอย่าง:
```json
"max_slots": 5

"used_slots": [
    {"slot_id": 1, "fingerprint": "HWID_1", ...},
    {"slot_id": 2, "fingerprint": "HWID_2", ...}
]
```

สถานะ: 2/5 slots ใช้งาน, เหลืออีก 3 slots

---

### Q26: ส่ง license ทาง email ปลอดภัยหรือไม่?
**A:** ✅ **ปลอดภัย!**

เหตุผล:
1. License ผูกกับ HWID (ใช้ได้แค่เครื่องที่ activate)
2. มี max_slots (จำกัดจำนวนเครื่อง)
3. มี expiry date (หมดอายุได้)

---

## การแก้ไขปัญหา

### Q27: ModuleNotFoundError: No module named 'cryptography'
**A:** ติดตั้ง cryptography:

```bash
pip install cryptography
```

ถ้ายังไม่ได้:
```bash
pip3 install cryptography
```

---

### Q28: FileNotFoundError: keys/server_private.pem
**A:** ยังไม่ได้สร้าง keys:

```bash
python generate_keys.py
```

---

### Q29: UnicodeDecodeError when reading CSV
**A:** CSV ไม่ใช่ UTF-8:

**วิธีแก้:**
1. เปิด CSV ด้วย Notepad++ หรือ VSCode
2. Encoding → Convert to UTF-8
3. Save

**Excel:**
- File → Save As → CSV UTF-8

---

### Q30: CSV มี error แต่ไม่บอกว่าบรรทัดไหน
**A:** ดูที่ terminal:

```
📋 Processing client #5: ...
❌ Error generating license: Invalid license_type
```

Client #5 = บรรทัดที่ 6 ใน CSV (header = row 1)

---

### Q31: Generate แล้วได้ licenses น้อยกว่าที่คาดหวัง
**A:** เช็ค CSV:

1. มี blank rows หรือไม่?
2. Required fields ครบหรือไม่?
3. มี error ใน terminal หรือไม่?

**วิธีแก้:**
```bash
# ลบ blank rows
# ตรวจสอบ required fields
# แก้ไข errors
# Generate ใหม่
```

---

### Q32: Permission denied (macOS/Linux)
**A:** ให้สิทธิ์ execute:

```bash
chmod +x *.py
```

---

## การใช้งานขั้นสูง

### Q33: จะแก้ไข license ที่สร้างแล้วได้ไหม?
**A:** **ไม่ได้!** ต้องสร้างใหม่

**Workflow:**
1. สร้าง license ใหม่ (แก้ไขข้อมูลที่ต้องการ)
2. REVOKE license เก่า (ในระบบ backend)
3. ส่ง license ใหม่ให้ลูกค้า

---

### Q34: จะ automate license generation ได้ไหม?
**A:** ได้! ใช้ Python script:

```python
from generate_from_csv import generate_licenses_from_csv

# Generate programmatically
licenses = generate_licenses_from_csv(
    "clients.csv",
    "keys/server_private.pem",
    "licenses/"
)

print(f"Generated {len(licenses)} licenses")
```

---

### Q35: จะ integrate กับ payment system ได้ไหม?
**A:** ได้! ตัวอย่าง:

```python
# After payment confirmed
def on_payment_success(customer_data):
    # Create license
    row = {
        'client_name': customer_data['name'],
        'client_email': customer_data['email'],
        'license_type': customer_data['plan'],
        ...
    }
    
    license = create_license_from_row(row)
    signed = create_signed_license(license, "keys/server_private.pem")
    
    # Save
    with open(f"licenses/{signed['license_id']}.key", 'w') as f:
        json.dump(signed, f)
    
    # Email to customer
    send_license_email(customer_data['email'], signed)
```

---

### Q36: จะสร้าง API endpoint สำหรับ generate licenses ได้ไหม?
**A:** ได้! ตัวอย่าง FastAPI:

```python
from fastapi import FastAPI
from generate_from_csv import create_license_from_row
from sign_license import create_signed_license

app = FastAPI()

@app.post("/generate_license")
def generate_license(client_data: dict):
    license = create_license_from_row(client_data)
    signed = create_signed_license(license, "keys/server_private.pem")
    
    # Save
    with open(f"licenses/{signed['license_id']}.key", 'w') as f:
        json.dump(signed, f)
    
    return signed
```

---

### Q37: จะทำ CRM integration ได้ไหม?
**A:** ได้! ตัวอย่าง:

```python
import requests

def sync_license_to_crm(license_data):
    crm_api = "https://your-crm.com/api/licenses"
    
    response = requests.post(crm_api, json={
        'license_id': license_data['license_id'],
        'client_name': license_data['client_info']['name'],
        'client_email': license_data['client_info']['email'],
        'expiry_date': license_data['validity']['expiry_date'],
        'status': 'active'
    })
    
    return response.json()
```

---

### Q38: มีวิธี bulk verify licenses ไหม?
**A:** มี! ใช้ script:

```bash
# Bash
for f in licenses/*.key; do
    python verify_license.py "$f" >> verify_report.txt
done
```

หรือ Python:
```python
import os
from verify_license import verify_license_file

licenses_dir = "licenses/"
results = []

for filename in os.listdir(licenses_dir):
    if filename.endswith('.key'):
        filepath = os.path.join(licenses_dir, filename)
        is_valid = verify_license_file(filepath, "keys/server_public.pem")
        results.append({
            'file': filename,
            'valid': is_valid
        })

# Report
for r in results:
    status = "✅ VALID" if r['valid'] else "❌ INVALID"
    print(f"{r['file']}: {status}")
```

---

### Q39: จะสร้าง dashboard สำหรับดู licenses ได้ไหม?
**A:** ได้! ตัวอย่าง:

```python
import streamlit as st
import json
import os

st.title("License Dashboard")

licenses = []
for f in os.listdir("licenses/"):
    if f.endswith('.key'):
        with open(f"licenses/{f}") as file:
            licenses.append(json.load(file))

# Display
st.write(f"Total Licenses: {len(licenses)}")

for lic in licenses:
    st.write(f"**{lic['license_id']}**")
    st.write(f"- Client: {lic['client_info']['name']}")
    st.write(f"- Type: {lic['license_type']}")
    st.write(f"- Expires: {lic['validity']['expiry_date']}")
    st.write("---")
```

---

### Q40: Grace period คืออะไร? ทำงานอย่างไร?
**A:** วันที่ยังใช้ได้หลังหมดอายุ

**ตัวอย่าง:**
```
Expiry: 2026-01-22
Grace: 7 days (reporting type)

Timeline:
2026-01-22: หมดอายุ (แต่ยังใช้ได้)
2026-01-23: Day 1 of grace
2026-01-24: Day 2 of grace
...
2026-01-29: Day 7 of grace (วันสุดท้าย)
2026-01-30: Limited Mode เริ่มต้น
```

**Limited Mode:**
- Max lot: 0.01
- Symbols: 1 only (EURUSD)
- Strategies: Grid only
- No hidden TP/SL
- No trailing stop

---

## 🎓 **ข้อมูลเพิ่มเติม**

ถ้ายังมีคำถาม:
1. อ่าน [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md)
2. อ่าน [USER_GUIDE.md](USER_GUIDE.md)
3. อ่าน [FILE_EXPLANATIONS.md](FILE_EXPLANATIONS.md)
4. รัน `python test_license_system.py`

---

**Version:** 1.0  
**Updated:** 2026-01-22  
**มีคำถามเพิ่มเติม?** กรุณาติดต่อ support team
