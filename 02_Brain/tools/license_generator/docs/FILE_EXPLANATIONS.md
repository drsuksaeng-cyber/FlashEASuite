# 📚 อธิบายการทำงานของไฟล์แต่ละตัว

**FlashEASuite V2 - License Generator System**

---

## 📋 **สารบัญไฟล์**

1. [generate_keys.py](#1-generate_keyspy) - สร้าง RSA Keys
2. [sign_license.py](#2-sign_licensepy) - Module สำหรับ Sign
3. [verify_license.py](#3-verify_licensepy) - ตรวจสอบ License
4. [generate_from_csv.py](#4-generate_from_csvpy) - Generate จาก CSV (Main)
5. [generate_single.py](#5-generate_singlepy) - Generate แบบ Interactive
6. [test_license_system.py](#6-test_license_systempy) - ทดสอบระบบ
7. [clients_template.csv](#7-clients_templatecsv) - CSV Template

---

## 1. generate_keys.py

### **ไฟล์นี้ทำอะไร:**
สร้าง RSA key pair (2048-bit) สำหรับ sign และ verify licenses

### **เมื่อไหร่ใช้:**
- ⚠️ **ใช้ครั้งเดียวตอนติดตั้ง!**
- สร้าง private key (เก็บเป็นความลับ)
- สร้าง public key (แชร์ให้ EA)

### **วิธีใช้:**
```bash
python generate_keys.py
```

### **Output:**
- `keys/server_private.pem` (344 bytes) - ⚠️ เก็บเป็นความลับ!
- `keys/server_public.pem` (451 bytes) - แชร์ให้ MQL5 team

### **การทำงานภายใน:**

```python
# 1. สร้าง private key
private_key = rsa.generate_private_key(
    public_exponent=65537,    # Standard RSA exponent
    key_size=2048,            # 2048-bit (ปลอดภัย)
    backend=default_backend()
)

# 2. สร้าง public key จาก private key
public_key = private_key.public_key()

# 3. แปลงเป็น PEM format
private_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()  # ไม่เข้ารหัส
)

# 4. บันทึกไฟล์
with open("keys/server_private.pem", "wb") as f:
    f.write(private_pem)
```

### **⚠️ ข้อควรระวัง:**
- สร้างครั้งเดียว! ถ้าสร้างใหม่ licenses เดิมจะใช้ไม่ได้
- Backup `server_private.pem` หลายที่
- อย่าเผยแพร่ private key ให้ใคร

---

## 2. sign_license.py

### **ไฟล์นี้ทำอะไร:**
Module สำหรับ sign license ด้วย RSA private key

### **เมื่อไหร่ใช้:**
- ⚠️ **ไม่ใช้โดยตรง** (เป็น module)
- ถูกเรียกใช้โดย `generate_from_csv.py` และ `generate_single.py`

### **Functions หลัก:**

#### **1. load_private_key(private_key_path)**
```python
def load_private_key(private_key_path):
    """
    โหลด private key จากไฟล์ .pem
    
    Input:  "keys/server_private.pem"
    Output: RSAPrivateKey object
    """
    with open(private_key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(
            f.read(),
            password=None,
            backend=default_backend()
        )
    return private_key
```

#### **2. sign_license(license_dict, private_key_path)**
```python
def sign_license(license_dict, private_key_path):
    """
    Sign license dictionary
    
    Input:  
        license_dict = {
            "license_id": "FLASH-...",
            "product": "FlashEASuite-Pro",
            ...
        }
        private_key_path = "keys/server_private.pem"
    
    Output: "bZWjYDYY..." (Base64 signature)
    """
    # 1. ลบ signature ออก (ถ้ามี)
    license_copy = {k: v for k, v in license_dict.items() if k != 'signature'}
    
    # 2. สร้าง canonical JSON (sorted keys, no spaces)
    canonical_json = json.dumps(license_copy, sort_keys=True, separators=(',', ':'))
    
    # 3. Sign ด้วย RSA-PSS-SHA256
    signature = private_key.sign(
        canonical_json.encode('utf-8'),
        padding.PSS(
            mgf=padding.MGF1(hashes.SHA256()),
            salt_length=padding.PSS.MAX_LENGTH
        ),
        hashes.SHA256()
    )
    
    # 4. Encode เป็น Base64
    signature_b64 = base64.b64encode(signature).decode('utf-8')
    
    return signature_b64
```

### **ตัวอย่างการใช้งาน (ใน code อื่น):**
```python
from sign_license import create_signed_license

license_data = {
    "license_id": "FLASH-202601-TEST",
    "product": "FlashEASuite-Pro",
    "license_type": "trial"
}

signed_license = create_signed_license(license_data, "keys/server_private.pem")
print(signed_license['signature'])  # "bZWjYDYY..."
```

### **Algorithm:**
```
License Data → Canonical JSON → SHA256 Hash → RSA Sign → Base64 Encode
```

---

## 3. verify_license.py

### **ไฟล์นี้ทำอะไร:**
ตรวจสอบความถูกต้องของ license signature

### **เมื่อไหร่ใช้:**
- ✅ **ใช้บ่อย** - ตรวจสอบ licenses ที่สร้าง
- ตรวจสอบก่อนส่งให้ลูกค้า
- Debugging

### **วิธีใช้:**

#### **แบบ Command Line:**
```bash
python verify_license.py licenses/FLASH-202601-XXXX.key
```

#### **แบบ Module (ใน code อื่น):**
```python
from verify_license import verify_license_file

is_valid = verify_license_file(
    "licenses/FLASH-202601-XXXX.key",
    "keys/server_public.pem"
)

if is_valid:
    print("✅ Valid")
else:
    print("❌ Invalid")
```

### **การทำงานภายใน:**

```python
def verify_license(license_dict, public_key_path):
    """
    ตรวจสอบ signature
    
    Process:
    1. Extract signature จาก license
    2. Decode Base64 → binary
    3. สร้าง canonical JSON (without signature)
    4. Load public key
    5. Verify signature with RSA-PSS-SHA256
    
    Return: True (valid) หรือ False (invalid/tampered)
    """
    try:
        # 1. Extract signature
        signature_b64 = license_dict['signature']
        signature = base64.b64decode(signature_b64)
        
        # 2. Load public key
        public_key = load_public_key(public_key_path)
        
        # 3. Create canonical JSON
        license_copy = {k: v for k, v in license_dict.items() if k != 'signature'}
        canonical_json = json.dumps(license_copy, sort_keys=True, separators=(',', ':'))
        
        # 4. Verify
        public_key.verify(
            signature,
            canonical_json.encode('utf-8'),
            padding.PSS(...),
            hashes.SHA256()
        )
        
        return True  # ✅ Valid
        
    except InvalidSignature:
        return False  # ❌ Tampered
```

### **ผลลัพธ์:**

✅ **Valid:**
```
✅ License FLASH-202601-XXXX is VALID
   Client: Somchai Jaidee
   Type: reporting
   Expiry: 2027-01-22
```

❌ **Invalid:**
```
❌ Invalid signature
❌ License is INVALID or TAMPERED
```

---

## 4. generate_from_csv.py

### **ไฟล์นี้ทำอะไร:**
⭐ **ไฟล์หลัก** - สร้าง licenses จำนวนมากจาก CSV file

### **เมื่อไหร่ใช้:**
- ✅ **ใช้บ่อยที่สุด!**
- สร้าง licenses ให้ลูกค้าหลายคนพร้อมกัน
- Batch generation (10, 100, 1000+ clients)

### **วิธีใช้:**

#### **แบบ Default (ใช้ clients_template.csv):**
```bash
python generate_from_csv.py
```

#### **แบบระบุ CSV file:**
```bash
python generate_from_csv.py path/to/your_clients.csv
```

### **การทำงานภายใน:**

```python
def generate_licenses_from_csv(csv_file, private_key_path, output_dir="licenses"):
    """
    Process:
    1. อ่าน CSV file
    2. Loop แต่ละ row (แต่ละลูกค้า)
    3. สร้าง license dictionary
    4. Sign license
    5. บันทึกเป็น .key file
    """
    
    # อ่าน CSV
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for row in reader:
            # 1. สร้าง license structure
            license_dict = create_license_from_row(row)
            
            # 2. Sign license
            signed_license = create_signed_license(license_dict, private_key_path)
            
            # 3. บันทึกไฟล์
            license_id = signed_license['license_id']
            output_file = f"{output_dir}/{license_id}.key"
            
            with open(output_file, 'w', encoding='utf-8') as out:
                json.dump(signed_license, out, indent=2, ensure_ascii=False)
```

### **ฟังก์ชันสำคัญ:**

#### **generate_license_id()**
```python
def generate_license_id():
    """
    สร้าง license ID แบบ unique
    
    Format: FLASH-YYYYMM-XXXXXXXX
    Example: FLASH-202601-AE930C51
    
    YYYYMM = ปี+เดือน (202601 = มกราคม 2026)
    XXXXXXXX = UUID (random 8 chars)
    """
    timestamp = datetime.now().strftime("%Y%m")
    unique_id = str(uuid.uuid4())[:8].upper()
    return f"FLASH-{timestamp}-{unique_id}"
```

#### **create_license_from_row(row)**
```python
def create_license_from_row(row):
    """
    แปลง CSV row → license dictionary
    
    Input: row = {
        'client_name': 'Somchai',
        'client_email': 'somchai@example.com',
        'license_type': 'reporting',
        ...
    }
    
    Output: license_dict ตาม SECURITY_MASTER_SPEC.txt
    """
    # Parse strategies
    strategies = [s.strip() for s in row['strategies'].split(',')]
    
    # Parse booleans
    hidden_tpsl = row['hidden_tpsl'].lower() in ('true', 'yes', '1')
    
    # Create structure
    license_dict = {
        "license_id": generate_license_id(),
        "product": row.get('product', 'FlashEASuite-Pro'),
        "license_type": row['license_type'],
        "client_info": {...},
        "hardware_binding": {...},
        "features": {...},
        "validity": {...},
        "brain_config": {...}
    }
    
    return license_dict
```

### **ผลลัพธ์:**

```
======================================================================
FlashEASuite V2 - License Generator (CSV Mode)
======================================================================

📋 Processing client #1: Somchai Jaidee
   ✅ License generated: FLASH-202601-AE930C51
   📁 Saved to: licenses/FLASH-202601-AE930C51.key
   👤 Client: Somchai Jaidee
   📧 Email: somchai@example.com
   🏷️  Type: reporting
   📅 Expires: 2027-01-22
   🎯 Strategies: Grid, Spike, Trend, Range

[... repeat for all clients ...]

======================================================================
✅ Generated 4 licenses successfully!
======================================================================
```

---

## 5. generate_single.py

### **ไฟล์นี้ทำอะไร:**
สร้าง license เดี่ยวแบบ interactive (ตอบคำถาม)

### **เมื่อไหร่ใช้:**
- ✅ สร้าง license ทีละคน
- ไม่ต้องการสร้าง CSV
- Quick generation

### **วิธีใช้:**
```bash
python generate_single.py
```

### **Process:**

```
1. ถามข้อมูลลูกค้า:
   - Client Name: _____________
   - Client Email: _____________
   - Phone (optional): _____________
   - MT5 Account: _____________
   - Broker: _____________

2. ถาม License Config:
   - License Type: [1-4] ___
     1. standalone
     2. trial
     3. reporting
     4. premium
   - Max Slots: ___

3. ถามวันที่:
   - Issue Date: [2026-01-22] ___
   - Expiry Date: [auto] ___

4. ถาม Features:
   - Strategies: [Grid,Spike,Trend,Range] ___
   - Hidden TP/SL: [Y/n] ___
   - Trailing Stop: [Y/n] ___
   - Multi-Symbol: [Y/n] ___
   - Max Symbols: [10] ___
   - Notes: _____________

5. สร้าง License
6. บันทึก + แสดงผล
```

### **ฟังก์ชันสำคัญ:**

#### **get_input(prompt, default, required)**
```python
def get_input(prompt, default=None, required=True):
    """
    รับ input จาก user พร้อม default value
    
    Example:
    >>> get_input("Client Name", required=True)
    Client Name: Somchai
    >>> return "Somchai"
    
    >>> get_input("Max Slots", default="5")
    Max Slots [5]: ___ (enter)
    >>> return "5"
    """
    if default:
        full_prompt = f"{prompt} [{default}]: "
    else:
        full_prompt = f"{prompt}: "
    
    value = input(full_prompt).strip()
    
    if not value and default:
        return default
    
    if not value and required:
        print("❌ This field is required!")
        return get_input(prompt, default, required)  # ถามใหม่
    
    return value
```

### **ตัวอย่างการใช้งาน:**

```bash
$ python generate_single.py

======================================================================
FlashEASuite V2 - Single License Generator
======================================================================

📝 Please provide client information:

Client Name: Somchai Jaidee
Client Email: somchai@example.com
Client Phone: 081-234-5678
MT5 Account Number: 12345678
Broker Name: Exness

🔧 License Configuration:

License Types:
  1. standalone
  2. trial
  3. reporting
  4. premium
Select license type (1-4) [3]: 3
Max slots [5]: 5

📅 Validity Period:

Issue Date (YYYY-MM-DD) [2026-01-22]: 
Expiry Date (YYYY-MM-DD) [2027-01-22]: 

🎯 Features:

Available strategies: Grid, Spike, Trend, Range
Strategies (comma-separated) [Grid,Spike,Trend,Range]: 
Hidden TP/SL [Y/n]: Y
Trailing Stop [Y/n]: Y
Multi-Symbol [Y/n]: Y
Max Symbols [10]: 10
Notes (optional): VIP Customer

🔐 Generating license...

======================================================================
✅ LICENSE GENERATED SUCCESSFULLY!
======================================================================

📄 License Details:
   License ID: FLASH-202601-AE930C51
   Client: Somchai Jaidee
   Email: somchai@example.com
   Type: reporting
   Expires: 2027-01-22
   Strategies: Grid,Spike,Trend,Range

💾 Saved to: licenses/FLASH-202601-AE930C51.key

✅ Next steps:
   1. Send licenses/FLASH-202601-AE930C51.key to client
   2. Verify: python verify_license.py licenses/FLASH-202601-AE930C51.key
```

---

## 6. test_license_system.py

### **ไฟล์นี้ทำอะไร:**
ทดสอบระบบทั้งหมด (7 tests)

### **เมื่อไหร่ใช้:**
- ✅ หลังติดตั้งใหม่
- ตรวจสอบว่าทุกอย่างทำงาน
- Debugging

### **วิธีใช้:**
```bash
cd 02_Brain
python test_license_system.py
```

### **Tests ทั้งหมด:**

#### **TEST 1: RSA Key Generation**
```python
def test_1_key_generation():
    """
    ตรวจสอบว่า RSA keys ถูกสร้างแล้ว
    
    Check:
    - server_private.pem exists
    - server_public.pem exists
    """
```

#### **TEST 2: License Creation**
```python
def test_2_license_creation():
    """
    สร้าง test license
    
    Check:
    - create_license_from_row() works
    - License structure ถูกต้อง
    """
```

#### **TEST 3: License Signing**
```python
def test_3_license_signing(license_dict):
    """
    Sign test license
    
    Check:
    - Signature สร้างได้
    - Signature length ~344 chars
    """
```

#### **TEST 4: License Verification**
```python
def test_4_license_verification(signed_license):
    """
    Verify valid license
    
    Check:
    - verify_license() returns True
    - Public key ใช้ได้
    """
```

#### **TEST 5: Tamper Detection**
```python
def test_5_tamper_detection(signed_license):
    """
    แก้ไข license และ verify
    
    Check:
    - Modified license → False
    - Security works!
    """
```

#### **TEST 6: CSV Batch Generation**
```python
def test_6_csv_generation():
    """
    ตรวจสอบ licenses ที่สร้างจาก CSV
    
    Check:
    - licenses/ folder exists
    - *.key files exist
    """
```

#### **TEST 7: File-based Verification**
```python
def test_7_file_verification():
    """
    Verify จาก .key file
    
    Check:
    - verify_license_file() works
    - Can read and verify actual files
    """
```

### **ผลลัพธ์:**
```
======================================================================
TEST SUMMARY
======================================================================
key_generation                 ✅ PASSED
license_creation               ✅ PASSED
license_signing                ✅ PASSED
license_verification           ✅ PASSED
tamper_detection               ✅ PASSED
csv_generation                 ✅ PASSED
file_verification              ✅ PASSED

======================================================================
RESULTS: 7/7 tests passed
✅ ALL TESTS PASSED!
======================================================================
```

---

## 7. clients_template.csv

### **ไฟล์นี้ทำอะไร:**
Template สำหรับสร้าง licenses แบบ batch

### **เมื่อไหร่ใช้:**
- ✅ สร้าง licenses หลายคนพร้อมกัน
- Copy และแก้ไขตามต้องการ

### **โครงสร้าง:**

```csv
client_name,client_email,client_phone,account_number,broker_name,license_type,product,hwid,max_slots,issued_date,expiry_date,strategies,hidden_tpsl,trailing_stop,multi_symbol,max_symbols,notes
```

### **Fields อธิบาย:**

| Field | Type | Required | Example | Description |
|-------|------|----------|---------|-------------|
| `client_name` | string | ✅ | "Somchai Jaidee" | ชื่อลูกค้า |
| `client_email` | string | ✅ | "somchai@example.com" | อีเมล |
| `client_phone` | string | ⚠️ | "081-234-5678" | เบอร์โทร |
| `account_number` | string | ⚠️ | "12345678" | เลขบัญชี MT5 |
| `broker_name` | string | ⚠️ | "Exness" | ชื่อโบรค |
| `license_type` | enum | ✅ | "reporting" | standalone/trial/reporting/premium |
| `product` | string | ✅ | "FlashEASuite-Pro" | ชื่อผลิตภัณฑ์ |
| `hwid` | string | ❌ | "" | ปล่อยว่าง (ใส่ตอน activate) |
| `max_slots` | integer | ✅ | 5 | จำนวน installations |
| `issued_date` | date | ✅ | "2026-01-22" | วันที่ออก |
| `expiry_date` | date | ✅ | "2027-01-22" | วันหมดอายุ |
| `strategies` | string | ✅ | "Grid,Spike,Trend,Range" | Comma-separated |
| `hidden_tpsl` | boolean | ✅ | true | Hidden TP/SL |
| `trailing_stop` | boolean | ✅ | true | Trailing Stop |
| `multi_symbol` | boolean | ✅ | true | Multi Symbol |
| `max_symbols` | integer | ✅ | 10 | จำนวน symbols |
| `notes` | string | ❌ | "VIP Customer" | หมายเหตุ |

### **ตัวอย่าง:**

```csv
client_name,client_email,client_phone,account_number,broker_name,license_type,product,hwid,max_slots,issued_date,expiry_date,strategies,hidden_tpsl,trailing_stop,multi_symbol,max_symbols,notes
Somchai Jaidee,somchai@example.com,081-234-5678,12345678,Exness,reporting,FlashEASuite-Pro,,5,2026-01-22,2027-01-22,"Grid,Spike,Trend,Range",true,true,true,10,VIP Customer
Suda Tanaka,suda@example.com,082-345-6789,87654321,ICMarkets,premium,FlashEASuite-Pro,,3,2026-01-22,2027-01-22,"Grid,Spike",true,true,false,5,Premium Client
```

### **วิธีใช้:**

1. Copy `clients_template.csv` → `my_clients.csv`
2. แก้ไข `my_clients.csv` (เพิ่ม/ลบ/แก้ข้อมูล)
3. Run: `python generate_from_csv.py my_clients.csv`

---

## 📊 **สรุป Flow การทำงาน**

```
[CSV File]
    ↓
[generate_from_csv.py]
    ├→ อ่าน CSV
    ├→ Loop each row
    │   ├→ create_license_from_row()
    │   ├→ [sign_license.py] sign_license()
    │   └→ บันทึก .key file
    ↓
[licenses/*.key]
    ↓
[verify_license.py]
    ├→ อ่าน .key file
    ├→ verify_license()
    └→ ✅ Valid / ❌ Invalid
```

---

## 🎯 **แนวทางการใช้งาน**

### **สถานการณ์ 1: สร้าง 100 licenses**
```bash
1. แก้ไข clients_100.csv (100 rows)
2. python generate_from_csv.py clients_100.csv
3. ได้ 100 ไฟล์ .key
```

### **สถานการณ์ 2: สร้าง 1 license ด่วน**
```bash
1. python generate_single.py
2. ตอบคำถาม
3. ได้ 1 ไฟล์ .key
```

### **สถานการณ์ 3: ตรวจสอบ licenses**
```bash
1. python verify_license.py licenses/*.key
2. ดูผลว่า Valid/Invalid
```

---

**Version:** 1.0  
**Updated:** 2026-01-22
