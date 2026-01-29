# 🚀 Option 2: Quick Install (1 ชั่วโมง)

**Status:** ✅ vcpkg + OpenSSL + RapidJSON installed  
**Next:** Build DLL with real implementation

---

## 📂 **ไฟล์ที่ต้อง Copy:**

### **Copy ทั้งหมดไปที่:**
```
C:\Users\drsuk\...\04_DLL\FlashEA_Security\
```

### **ไฟล์:**
```
✅ Security.h
✅ Security_Real.cpp (มี public key แล้ว!)
✅ RSAVerifier.h
✅ RSAVerifier.cpp
✅ LicenseVerifier.h
✅ LicenseVerifier.cpp
✅ HWIDGenerator.h
✅ HWIDGenerator.cpp
✅ TradingParams.h
✅ build_option2.bat
```

---

## 🔧 **Build Steps:**

```cmd
# 1. เปิด x64 Native Tools Command Prompt for VS 2019/2022

# 2. ไปที่ DLL directory
cd C:\Users\drsuk\...\04_DLL\FlashEA_Security

# 3. Clean
del *.obj *.dll *.lib *.exp

# 4. Build
build_option2.bat

# Expected output:
# ===================================
# BUILD SUCCESSFUL! (64-BIT)
# With OpenSSL + RapidJSON
# ===================================
```

---

## 📦 **Deploy:**

```
Copy ไฟล์นี้ไปที่ MT5\Libraries\:

1. FlashEA_Security.dll (DLL ใหม่)
2. libssl-3-x64.dll (จาก build)
3. libcrypto-3-x64.dll (จาก build)

Path:
C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\...\MQL5\Libraries\
```

---

## ✅ **Test:**

```
1. Restart MT5
2. Run TestDLLWrapper.mq5
3. Expected:
   ✅ TEST 1: Real HWID (64-char)
   ✅ TEST 2: Real params from license
   ✅ All 5 tests PASSED
```

---

## 🎯 **Status:**

```
✅ vcpkg installed
✅ OpenSSL 3.6.0 installed
✅ RapidJSON installed
✅ Public key embedded
✅ All source files ready
→ Ready to build! 🚀
```

---

**Copy files → Build → Test** 💪
