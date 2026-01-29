# 🛡️ FlashEA_Security DLL - Phase 3

**Version:** 1.0  
**Date:** 2026-01-25  
**Status:** Initial Implementation

---

## 📋 Overview

FlashEA_Security.dll เป็น protection layer สำหรับ FlashEASuite V2 ที่ทำหน้าที่:
- ✅ License verification (RSA signature + HWID)
- ✅ Hardware ID generation
- ✅ Trading parameters calculation (critical!)
- ✅ Policy signature verification
- ✅ Anti-mock DLL protection
- ✅ Self-integrity checking

---

## 📦 Files Included

```
FlashEA_Security/
├── TradingParams.h          # Structs definition
├── Security.h               # DLL exports header
├── Security.cpp             # Main DLL implementation
├── SecurityHelpers.cpp      # Helper functions
├── README.md                # This file
└── [After compilation]
    └── FlashEA_Security.dll # Final DLL
```

---

## 🔧 Compilation Requirements

### **Minimum Requirements:**

- **Compiler:** Visual Studio 2019 or later
- **Platform:** Windows 64-bit
- **SDK:** Windows SDK 10.0+
- **Runtime:** C++ Runtime (MSVCRT)

### **Optional (for full features):**

- **OpenSSL:** For real RSA signature verification
  - Download: https://slproweb.com/products/Win32OpenSSL.html
  - Version: 1.1.1 or 3.0+
  
- **RapidJSON:** For proper JSON parsing
  - Download: https://github.com/Tencent/rapidjson
  - Header-only library

---

## 🚀 Compilation Steps

### **Method 1: Visual Studio GUI**

1. **Create New Project:**
   ```
   File → New → Project
   → C++ → Windows → Dynamic-Link Library (DLL)
   Name: FlashEA_Security
   ```

2. **Add Files:**
   ```
   Right-click project → Add → Existing Item
   → Add all .h and .cpp files
   ```

3. **Project Configuration:**
   ```
   Configuration: Release
   Platform: x64
   
   Project Properties:
   → C/C++ → Preprocessor → Definitions:
      FLASHEA_SECURITY_EXPORTS
   
   → Linker → Additional Dependencies:
      wbemuuid.lib
      ole32.lib
      oleaut32.lib
      (Optional) libcrypto.lib (OpenSSL)
   ```

4. **Build:**
   ```
   Build → Build Solution (Ctrl+Shift+B)
   Output: x64/Release/FlashEA_Security.dll
   ```

---

### **Method 2: Command Line (Developer Command Prompt)**

```batch
# Navigate to source directory
cd FlashEA_Security

# Compile
cl /LD /O2 /DFLASHEA_SECURITY_EXPORTS ^
   Security.cpp SecurityHelpers.cpp ^
   /link wbemuuid.lib ole32.lib oleaut32.lib ^
   /OUT:FlashEA_Security.dll

# Output: FlashEA_Security.dll
```

---

### **Method 3: CMake (Cross-platform)**

Create `CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.15)
project(FlashEA_Security)

set(CMAKE_CXX_STANDARD 17)

add_library(FlashEA_Security SHARED
    Security.cpp
    SecurityHelpers.cpp
    TradingParams.h
    Security.h
)

target_compile_definitions(FlashEA_Security PRIVATE 
    FLASHEA_SECURITY_EXPORTS
)

target_link_libraries(FlashEA_Security
    wbemuuid
    ole32
    oleaut32
)

# Optional: Add OpenSSL
# find_package(OpenSSL REQUIRED)
# target_link_libraries(FlashEA_Security OpenSSL::Crypto)
```

Build:
```batch
mkdir build
cd build
cmake .. -G "Visual Studio 16 2019" -A x64
cmake --build . --config Release
```

---

## 📊 Exported Functions

### **1. CheckLicense**
```cpp
int CheckLicense(const wchar_t* license_path);
```
**Returns:**
- `1` = Valid license
- `0` = Invalid
- `-1` = Expired
- `-2` = Revoked
- `-3` = HWID mismatch

**Example:**
```cpp
int status = CheckLicense(L"C:\\License.key");
if (status == 1) {
    Print("License valid!");
}
```

---

### **2. GetHWID**
```cpp
void GetHWID(wchar_t* output, int max_len);
```
**Description:** Generates unique hardware ID (SHA256)

**Example:**
```cpp
wchar_t hwid[256];
GetHWID(hwid, 256);
Print("HWID: ", hwid);
```

---

### **3. CalculateTradingParams** (CRITICAL!)
```cpp
int CalculateTradingParams(
    const wchar_t* license_path,
    const char* symbol,
    double account_balance,
    TradingParams* output
);
```
**Returns:** `1` (success), `0` (invalid license)

**Example:**
```cpp
TradingParams params;
int result = CalculateTradingParams(
    L"C:\\License.key",
    "XAUUSD",
    10000.0,
    &params
);

if (result == 1) {
    Print("Lot size: ", params.lot_size);
    Print("Grid step: ", params.grid_step);
}
```

---

### **4. VerifyPolicy**
```cpp
int VerifyPolicy(const char* policy_json, const char* public_key);
```
**Returns:** `1` (valid), `0` (invalid)

**Note:** Current implementation is stub (always returns 1)
**TODO:** Implement with OpenSSL in production

---

### **5. VerifyChallenge**
```cpp
int VerifyChallenge(Challenge* challenge, Response* response);
```
**Description:** Anti-mock DLL verification

**Example:**
```cpp
Challenge c;
c.random_value = 12345;
c.timestamp = GetTickCount64();
strcpy(c.license_id, "FLASH-2026-XXXX");

Response r;
r.computed_hash = CalculateExpectedHash(&c);

if (VerifyChallenge(&c, &r) == 1) {
    Print("DLL authentic!");
}
```

---

### **6. VerifyDLLIntegrity**
```cpp
int VerifyDLLIntegrity();
```
**Returns:** `1` (intact), `0` (modified)

**Note:** Current implementation always returns 1
**TODO:** Set correct checksum after compilation

---

## 🔒 Security Features

### **Current Implementation:**

✅ **Implemented:**
- HWID generation (CPU + Disk + Machine GUID)
- License file reading
- Trading params calculation
- Challenge-response framework
- DLL integrity framework

⚠️ **Stub (needs production implementation):**
- RSA signature verification (requires OpenSSL)
- SHA256 hashing (simple hash for now)
- JSON parsing (string search for now)
- DLL checksum validation (disabled for testing)

---

## 🎯 Production Checklist

Before production deployment:

- [ ] Add OpenSSL for real RSA verification
- [ ] Replace SHA256 stub with OpenSSL implementation
- [ ] Add RapidJSON for proper JSON parsing
- [ ] Calculate and set DLL checksum
- [ ] Enable integrity check in VerifyDLLIntegrity()
- [ ] Add date parsing for expiry check
- [ ] Test with real License.key files
- [ ] Protect DLL with Enigma Protector ($199)

---

## 🧪 Testing

### **Test 1: HWID Generation**
```cpp
wchar_t hwid[256];
GetHWID(hwid, 256);
// Expected: 64-char hex string
```

### **Test 2: License Check**
```cpp
// Create test license file first
int status = CheckLicense(L"test_license.key");
// Expected: 1 (valid) or -3 (HWID mismatch)
```

### **Test 3: Trading Params**
```cpp
TradingParams params;
int result = CalculateTradingParams(
    L"test_license.key",
    "XAUUSD",
    10000.0,
    &params
);
// Expected: lot_size > 0, grid_step > 0
```

---

## 📝 Integration with MQL5

### **Step 1: Copy DLL**
```
Copy FlashEA_Security.dll to:
MQL5/Libraries/FlashEA_Security.dll
```

### **Step 2: Import in MQL5**
```cpp
#import "FlashEA_Security.dll"
   int CheckLicense(string license_path);
   void GetHWID(string &output);
   int CalculateTradingParams(string license, string symbol, 
                              double balance, TradingParams &output);
   int VerifyPolicy(string policy_json, string public_key);
   int VerifyChallenge(Challenge &challenge, Response &response);
   int VerifyDLLIntegrity();
#import

// Define TradingParams struct in MQL5 (must match C++)
struct TradingParams {
   double lot_size;
   double grid_step;
   int max_orders;
   double tp_points;
   double sl_points;
   uint checksum;
};
```

### **Step 3: Use in EA**
```cpp
int OnInit() {
   // Check license
   int status = CheckLicense("License.key");
   if (status != 1) {
      Print("Invalid license!");
      return INIT_FAILED;
   }
   
   // Get trading params
   TradingParams params;
   if (CalculateTradingParams("License.key", _Symbol, 
                              AccountInfoDouble(ACCOUNT_BALANCE), 
                              params) == 1) {
      Print("Lot size: ", params.lot_size);
   }
   
   return INIT_SUCCEEDED;
}
```

---

## ⚠️ Known Limitations

**Phase 3 Initial Version:**

1. **RSA Verification:** Stub implementation (always returns true)
   - **Impact:** No signature validation yet
   - **Fix:** Add OpenSSL in next iteration

2. **SHA256 Hash:** Simple hash instead of real SHA256
   - **Impact:** HWID less secure
   - **Fix:** Use OpenSSL SHA256

3. **JSON Parsing:** String search instead of proper parser
   - **Impact:** May fail on complex JSON
   - **Fix:** Add RapidJSON

4. **DLL Integrity:** Checksum disabled
   - **Impact:** No tamper detection
   - **Fix:** Calculate checksum and enable check

---

## 🚀 Next Steps (Phase 3 Track B)

After DLL compilation:

1. **Create MQL5 Wrapper** (DLLWrapper.mqh)
2. **Create Struct Definitions** (TradingParamsStruct.mqh)
3. **Integration Testing**
4. **Performance Testing**

---

## 📞 Support

**Compilation Issues:**
- Check Visual Studio version (2019+)
- Verify Windows SDK installed
- Check linker dependencies

**Runtime Issues:**
- Ensure DLL in MQL5/Libraries/
- Check DLL architecture (x64 for MT5 x64)
- Verify MT5 allows DLL imports

---

## ✅ Status

**Phase 3 Track C:** 🟡 **In Progress**

**Completed:**
- [x] DLL structure
- [x] HWID generation (WMI + Registry)
- [x] Trading params calculation
- [x] Challenge-response framework
- [x] Basic license validation

**TODO:**
- [ ] Add OpenSSL integration
- [ ] Real RSA verification
- [ ] Production-ready JSON parsing
- [ ] DLL checksum calculation
- [ ] Protection with Enigma

---

**Ready for MQL5 integration testing!** 🚀
