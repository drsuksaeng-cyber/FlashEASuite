# Protocol Testing Guide - FlashEASuite V2

**Version:** 2.0 (Extended Grid Fields)  
**Date:** December 28, 2025

---

## 📋 Overview

This guide explains how to test the extended protocol with 11 new Grid fields.

**Files:**
- `TEST_PROTOCOL.py` - Python test (generates test data)
- `TEST_PROTOCOL.mq5` - MQL5 test (deserializes and verifies)

---

## 🔧 Prerequisites

### **1. Install Extended Files:**

**MQL5 Side:**
```
FlashEASuite_V2/Include/Network/Protocol/
├── Definitions_EXTENDED.mqh     → Rename to Definitions.mqh
└── Serialization_EXTENDED.mqh   → Rename to Serialization.mqh
```

**Python Side:**
```
02_Brain/core/strategy/
└── policy_EXTENDED.py           → Rename to policy.py
```

### **2. Backup Original Files:**
```bash
# Backup MQL5 files
mv Definitions.mqh Definitions_OLD.mqh
mv Serialization.mqh Serialization_OLD.mqh

# Backup Python file
mv policy.py policy_OLD.py
```

---

## 🧪 Testing Procedure

### **Step 1: Run Python Test**

```bash
cd FlashEASuite_V2
python TEST_PROTOCOL.py
```

**Expected Output:**
```
================================================================================
FlashEASuite V2 - Protocol Test (Extended Grid Fields)
================================================================================

Test Data:
  Symbol: XAUUSD
  Action: 1 (BUY)
  Confidence: 0.85
  ...

Grid Extended Fields:
  Risk Multiplier: 0.8
  Is In Cooldown: True
  CSM Data:
    USD: 5.20
    EUR: 4.80
    ...
  Grid Direction: 1 (BUY)

Packing message...
✅ Packed successfully! Size: 205 bytes

Size Breakdown:
  ...
  Expected total:              205 bytes
  Actual total:                205 bytes
  ✅ Size matches!

Hex Dump (first 100 bytes):
  00000002000000065841555553440000...
  ...

Manual Field Verification:
  Message Type: 2 (expected: 2)
  Symbol Length: 6 (expected: 6)
  Symbol: XAUUSD (expected: XAUUSD)
  ...
  --- GRID EXTENDED FIELDS ---
  Risk Multiplier: 0.800000 (expected: 0.8)
  Is In Cooldown: True (expected: True)
  CSM Data:
    USD: 5.200000 (expected: 5.2) ✅
    EUR: 4.800000 (expected: 4.8) ✅
    ...
  Grid Direction: 1 (expected: 1)

================================================================================
✅ Test complete! Copy hex dump to MQL5 test script.
================================================================================

For MQL5 TEST_PROTOCOL.mq5, use this data:
uchar test_data[] = {
    0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x06,
    ...
};
```

**Action:** Copy the hex data from output

---

### **Step 2: Update MQL5 Test Script**

**File:** `Tester/TEST_PROTOCOL.mq5`

**Line 24-26:** Paste hex data from Python output

```cpp
uchar test_data[] = {
    // PASTE HERE (from Python output)
    0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x06,
    0x58, 0x41, 0x55, 0x55, 0x53, 0x44, 0x00, 0x00,
    // ... rest of data
};
```

---

### **Step 3: Compile and Run MQL5 Test**

**In MetaEditor:**
1. Open `Tester/TEST_PROTOCOL.mq5`
2. Compile (F7)
3. Check for errors
4. Run script on any chart

**Expected Output:**
```
════════════════════════════════════════════════════════════════
FlashEASuite V2 - Protocol Test (Extended Grid Fields)
════════════════════════════════════════════════════════════════

Test Data Size: 205 bytes

Deserializing message...
✅ Deserialization SUCCESS!

═══ ORIGINAL FIELDS ═══
Symbol:           XAUUSD
Action:           1 (0=HOLD, 1=BUY, 2=SELL)
Confidence:       0.850000
Entry Price:      2650.50000
...

═══ GRID EXTENDED FIELDS ═══
Risk Multiplier:  0.800000
Is In Cooldown:   TRUE (paused)

CSM Data:
  USD:            5.20
  EUR:            4.80
  GBP:            3.50
  JPY:            -2.10
  AUD:            1.20
  CAD:            0.50
  CHF:            -1.00
  NZD:            2.30

Grid Direction:   1 (BUY)

═══ VERIFICATION ═══
✅ Symbol: XAUUSD
✅ Action: 1
✅ Confidence: 0.850000
✅ Risk Multiplier: 0.800000
✅ Is In Cooldown: TRUE
✅ CSM USD: 5.20
✅ Grid Direction: 1

════════════════════════════════════════════════════════════════
✅✅✅ ALL TESTS PASSED! ✅✅✅
════════════════════════════════════════════════════════════════

Protocol is working correctly!
Ready to proceed to Phase 2 (Grid Integration)
```

---

## ✅ Success Criteria

### **Python Test:**
- ✅ Message size = 205 bytes
- ✅ All fields serialize correctly
- ✅ Hex dump generated

### **MQL5 Test:**
- ✅ Deserialization success (no errors)
- ✅ All original fields correct
- ✅ All 11 Grid fields correct
- ✅ All verification checks pass

---

## ❌ Troubleshooting

### **Problem: Python import error**
```
ImportError: cannot import name 'pack_custom_protocol' from 'policy'
```

**Solution:**
- Ensure `policy_EXTENDED.py` is renamed to `policy.py`
- Check file is in correct directory: `02_Brain/core/strategy/`

---

### **Problem: MQL5 compilation error**
```
'risk_multiplier' - undeclared identifier
```

**Solution:**
- Ensure `Definitions_EXTENDED.mqh` is renamed to `Definitions.mqh`
- Check PolicyMessage struct has all 11 new fields
- Recompile all dependent files

---

### **Problem: Deserialization fails**
```
❌ DESERIALIZATION FAILED!
```

**Solution:**
1. Check hex data was pasted correctly
2. Verify `Serialization_EXTENDED.mqh` is renamed to `Serialization.mqh`
3. Ensure field order matches between Python and MQL5:
   - Python: `pack_custom_protocol()` field order
   - MQL5: `DeserializePolicyMessage()` read order

---

### **Problem: Field mismatch**
```
❌ CSM USD mismatch: 0.000000 != 5.200000
```

**Solution:**
- Hex data might be truncated - copy full output
- Check big-endian byte order ('>d' in Python, ReadDouble in MQL5)
- Verify no extra fields inserted

---

## 📊 Message Format Reference

### **Binary Layout (205 bytes total):**

```
Offset  Size  Type      Field
------  ----  --------  ---------------------------
0       4     int32     message_type (2)
4       4     int32     symbol_length
8       N     string    symbol (UTF-8)
8+N     4     int32     action
12+N    8     double    confidence
20+N    8     double    entry_price
28+N    8     double    stop_loss
36+N    8     double    take_profit
44+N    8     double    position_size
52+N    8     int64     timestamp_ms
60+N    4     int32     model_version_length
64+N    M     string    model_version (UTF-8)
64+N+M  8     double    risk_multiplier       ← NEW
72+N+M  4     int32     is_in_cooldown        ← NEW
76+N+M  8     double    csm_usd               ← NEW
84+N+M  8     double    csm_eur               ← NEW
92+N+M  8     double    csm_gbp               ← NEW
100+N+M 8     double    csm_jpy               ← NEW
108+N+M 8     double    csm_aud               ← NEW
116+N+M 8     double    csm_cad               ← NEW
124+N+M 8     double    csm_chf               ← NEW
132+N+M 8     double    csm_nzd               ← NEW
140+N+M 4     int32     grid_direction        ← NEW

Total: ~205 bytes (varies by string lengths)
```

### **Data Types:**
- `int32`: 4 bytes, big-endian
- `int64`: 8 bytes, big-endian
- `double`: 8 bytes, big-endian IEEE 754
- `string`: int32 length + UTF-8 bytes (no null terminator)
- `bool`: Stored as int32 (0 or 1)

---

## 🎯 Next Steps

**After all tests pass:**

1. ✅ **Phase 1 Complete** - Protocol extended successfully
2. → **Proceed to Phase 2** - Grid Integration
3. → Create GridCore update methods
4. → Update ProgramC_Trader to pass data to Grid
5. → Test full system integration

---

## 📝 Notes

- Message size increased: 50 bytes → 205 bytes (+310%)
- Breaking change: Old messages incompatible
- All three components must be updated together:
  - MQL5 Definitions.mqh
  - MQL5 Serialization.mqh  
  - Python policy.py

---

**Test Status:** ⏳ Awaiting execution  
**Next Phase:** Phase 2 - Grid Integration
