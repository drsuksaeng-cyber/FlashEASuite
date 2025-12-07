# ⚡ แก้ปัญหาด่วน: Target folder NOT FOUND

## ❌ ปัญหา:
```
[ERROR] Target folder 02_ProgramB_Brain_Py\core\strategy\ NOT FOUND
```

## ✅ วิธีแก้ (เลือก 1 วิธี):

---

### **🚀 วิธีที่ 1: ใช้ Script ใหม่ (แนะนำ!)**

```batch
# ลบไฟล์เก่า
del cleanup_project_v2.bat
del install_modules.bat

# ใช้ไฟล์ใหม่
cleanup_project_v2.1_FIXED.bat
install_modules_v2.1_FIXED.bat
```

**เสร็จแล้ว!** ✅

---

### **🔧 วิธีที่ 2: สร้างโฟลเดอร์เอง**

```batch
# สร้างโฟลเดอร์
mkdir 02_ProgramB_Brain_Py\core\strategy
mkdir Include\Network\Protocol
mkdir Include\Logic\Grid

# แล้วรัน install
install_modules.bat
```

**เสร็จแล้ว!** ✅

---

### **✋ วิธีที่ 3: ติดตั้งด้วยมือ**

```batch
# Python
xcopy /s /y python_strategy\* 02_ProgramB_Brain_Py\core\strategy\

# Protocol
copy /y mql_protocol\Definitions.mqh Include\Network\Protocol\
copy /y mql_protocol\Serialization.mqh Include\Network\Protocol\
copy /y mql_protocol\Protocol.mqh Include\Network\

# Grid
copy /y mql_grid\GridConfig.mqh Include\Logic\Grid\
copy /y mql_grid\GridState.mqh Include\Logic\Grid\
copy /y mql_grid\GridCore.mqh Include\Logic\Grid\
copy /y mql_grid\Strategy_Grid.mqh Include\Logic\
```

**เสร็จแล้ว!** ✅

---

## 🎯 สาเหตุ:

Script เก่า (`cleanup_project_v2.bat`) ใช้ชื่อโฟลเดอร์ผิด

**แก้:** ใช้ `cleanup_project_v2.1_FIXED.bat` แทน

---

## 📦 ดาวน์โหลด:

**FlashEA_Refactored_Complete_v2.1_FIXED.zip** (45 KB)

มี:
- ✅ cleanup_project_v2.1_FIXED.bat (แก้แล้ว)
- ✅ install_modules_v2.1_FIXED.bat (แก้แล้ว)
- ✅ FIX_TARGET_FOLDER_ERROR.md (คู่มือเต็ม)

---

## ✅ เช็คว่าสำเร็จ:

```batch
# ต้องเห็นไฟล์เหล่านี้
dir 02_ProgramB_Brain_Py\core\strategy\__init__.py
dir Include\Network\Protocol\Definitions.mqh
dir Include\Logic\Grid\GridConfig.mqh
```

ถ้าเห็น = **สำเร็จ!** ✅

---

**อ่านเพิ่มเติม:** FIX_TARGET_FOLDER_ERROR.md
