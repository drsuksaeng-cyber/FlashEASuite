# 📦 Installation Guide - Phase 2 + Phase 3B

**FlashEASuite V2 - Complete Security Implementation**

---

## 🎯 **Quick Start**

```
1. Extract ZIP file
2. Copy Python files → 02_Brain/core/policy/
3. Copy MQL5 files → Include/Network/ and Include/Security/
4. Copy Test files → Tester/
5. Test with TestIntegration_Phase2_3B.mq5
```

---

## 📁 **File Locations**

### **Python Files (Phase 2)**

```
Source:      Final_Package/Phase2_Python/
Destination: 02_Brain/core/policy/

Files:
├── nonce_manager.py
├── sequence_tracker.py
├── policy_signer.py
└── policy_generator.py
```

### **MQL5 Files (Phase 2)**

```
Source:      Final_Package/Phase2_MQL5/
Destination: Include/Network/

Files:
├── NonceManager.mqh
├── SequenceTracker.mqh
└── PolicyVerifier.mqh
```

### **MQL5 Files (Phase 3B)**

```
Source:      Final_Package/Phase3B_MQL5/
Destination: Include/Security/

Files:
└── DLLWrapper_Enhanced.mqh
```

### **Test Files**

```
Source:      Final_Package/Tests/
Destination: Tester/ (or Experts/)

Files:
├── TestPolicyVerifier.mq5           (Phase 2 only)
├── TestPhase3B_Complete.mq5         (Phase 3B only)
└── TestIntegration_Phase2_3B.mq5    (Combined)
```

---

## ⚙️ **Installation Steps**

### **Step 1: Python Installation**

```bash
# 1. Navigate to Brain directory
cd FlashEASuite_V2/02_Brain/core

# 2. Create policy directory
mkdir -p policy

# 3. Copy Python files
cp [extracted]/Phase2_Python/*.py policy/

# 4. Verify
ls policy/
# Should show: nonce_manager.py, sequence_tracker.py, 
#              policy_signer.py, policy_generator.py

# 5. Test
cd policy
python3 policy_generator.py
# Should show: Test results with ✅
```

### **Step 2: MQL5 Phase 2 Installation**

```
1. Open MetaEditor

2. Navigate to: Include/Network/

3. Copy files:
   - NonceManager.mqh
   - SequenceTracker.mqh
   - PolicyVerifier.mqh

4. Verify structure:
   Include/Network/
   ├── NonceManager.mqh
   ├── SequenceTracker.mqh
   ├── PolicyVerifier.mqh
   └── (other files...)
```

### **Step 3: MQL5 Phase 3B Installation**

```
1. Open MetaEditor

2. Navigate to: Include/Security/

3. Copy file:
   - DLLWrapper_Enhanced.mqh

4. Verify structure:
   Include/Security/
   ├── DLLWrapper_Enhanced.mqh
   └── (other files...)
```

### **Step 4: Test EA Installation**

```
1. Copy test EAs to: Tester/ or Experts/

2. Compile each EA:
   - TestPolicyVerifier.mq5
   - TestPhase3B_Complete.mq5
   - TestIntegration_Phase2_3B.mq5

3. Check for errors:
   - 0 Errors ✅
   - 0 Warnings ✅
```

---

## 🧪 **Testing**

### **Test 1: Phase 2 (Policy Security)**

```
1. Attach TestPolicyVerifier.mq5 to any chart

2. Check Expert log:
   ✅ Test 1: Valid policy accepted
   ✅ Test 2: Old policy rejected
   ✅ Test 3: Replay attack detected
   ✅ Test 4: Out-of-order rejected

3. Expected result: 4/4 PASSED
```

### **Test 2: Phase 3B (DLL Wrapper)**

```
1. Attach TestPhase3B_Complete.mq5 to any chart

2. Check Expert log:
   ✅ Test 1: Policy signature verified
   ✅ Test 2: DLL challenge successful
   ✅ Test 3: Tampered policy rejected
   ✅ Test 4: Multiple challenges (5x)

3. Expected result: 4/4 PASSED
```

### **Test 3: Integration (Phase 2 + 3B)**

```
1. Attach TestIntegration_Phase2_3B.mq5 to any chart

2. Check Expert log:
   ✅ Integration Test 1: Full policy flow
   ✅ Integration Test 2: Replay attack + DLL
   ✅ Integration Test 3: Tampered policy + DLL
   ✅ Integration Test 4: Combined security

3. Expected result: 4/4 PASSED
```

---

## ⚠️ **Prerequisites**

### **Python:**

```
1. Python 3.8+
2. cryptography library:
   pip install cryptography

3. RSA keys:
   - server_private.pem (for signing)
   - server_public.pem (for verification)
   
   Generate with:
   python3 -c "
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
public_key = private_key.public_key()

with open('server_private.pem', 'wb') as f:
    f.write(private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ))

with open('server_public.pem', 'wb') as f:
    f.write(public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ))

print('✅ Keys generated')
"
```

### **MQL5:**

```
1. MetaTrader 5 (Build 3770+)

2. FlashEA_Security.dll with functions:
   - CheckLicense()
   - GetHWID()
   - VerifyPolicy()          (Phase 3B)
   - VerifyChallenge()       (Phase 3B)

3. License file:
   - MT5/Files/License.key
   
4. Public key:
   - MT5/Files/server_public.pem
```

---

## 🔧 **Integration with Existing Code**

### **Python Integration**

**Modify:** `02_Brain/core/strategy/policy.py`

```python
# Add at top:
from policy_generator import SecurePolicyGenerator

# Replace policy creation:
# Old:
policy = {"symbol": symbol, "strategy": strategy, "params": params}

# New:
generator = SecurePolicyGenerator("keys/server_private.pem")
policy = generator.create_policy(client_id, symbol, strategy, params)
```

### **MQL5 Integration**

**Modify:** `Include/Logic/PolicyManager.mqh`

```cpp
// Add at top:
#include "../Network/PolicyVerifier.mqh"
#include "../Security/DLLWrapper_Enhanced.mqh"

// Add to class:
CPolicyVerifier m_policy_verifier;
CDLLSecurityWrapper m_dll_wrapper;

// In Initialize():
if(!m_policy_verifier.Initialize())
    return false;

if(!m_dll_wrapper.Initialize())
    return false;

// Before executing policy:
string error;
if(!m_policy_verifier.VerifyPolicy(policy_json, error))
{
    Print("❌ Policy rejected: ", error);
    return false;
}

if(!m_dll_wrapper.VerifyPolicySignature(policy_json))
{
    Print("❌ Signature invalid");
    return false;
}
```

---

## 📊 **Verification Checklist**

```
Installation:
□ Python files copied correctly
□ MQL5 files copied correctly
□ Test EAs compile without errors
□ All paths use relative includes (../)

Testing:
□ Phase 2 tests: 4/4 PASSED
□ Phase 3B tests: 4/4 PASSED
□ Integration tests: 4/4 PASSED
□ No errors in logs

Integration:
□ PolicyManager modified
□ Python policy.py modified
□ Keys generated (private + public)
□ License file present
□ DLL has required functions

Production:
□ All tests passed
□ No compilation errors
□ No runtime errors
□ Performance acceptable (<15ms overhead)
```

---

## 🐛 **Troubleshooting**

### **Python Errors:**

```
Error: "ModuleNotFoundError: No module named 'cryptography'"
Solution: pip install cryptography

Error: "FileNotFoundError: server_private.pem"
Solution: Generate RSA keys (see Prerequisites)
```

### **MQL5 Errors:**

```
Error: "Cannot open include file"
Solution: Use relative paths with "../"
Example: #include "../Include/Network/PolicyVerifier.mqh"

Error: "Function 'VerifyPolicy' not found in DLL"
Solution: DLL must be updated with Phase 3B functions
```

### **Test Failures:**

```
Test fails: "Signature verification failed"
Solution: 
1. Check server_public.pem in MT5/Files/
2. Check DLL has VerifyPolicy() function
3. May be expected if DLL not updated yet
```

---

## ✅ **Success Indicators**

```
✅ All Python modules import successfully
✅ All MQL5 files compile without errors
✅ Test EAs show 12/12 tests PASSED
✅ No "Failed to initialize" errors
✅ Policy verification working
✅ DLL challenge working
✅ Integration tests passing
```

---

## 📞 **Support**

If you encounter issues:

1. Check COMPLETE_SUMMARY.md for overview
2. Check test EA logs for detailed errors
3. Verify all prerequisites installed
4. Check file locations match guide

---

**Installation Complete!** 🎉

System is ready for production deployment.

---

**Version:** 1.0  
**Date:** January 27, 2026  
**Author:** Dr. Suksaeng Kukanok Team
