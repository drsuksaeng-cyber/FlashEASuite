# 🧪 Tester - Test Suite

**Purpose:** Comprehensive testing for FlashEASuite V2 modules

---

## 📋 **Available Tests**

### **1. test_position_sizing.mq5**
```
Module:  PositionSizingManager
Tests:   10 scenarios
Purpose: Validate lot size calculations

Scenarios:
✅ Basic calculation (1% risk)
✅ Custom risk percentage
✅ Volatility adjustment
✅ Lot normalization
✅ Min/max lot clamping
✅ Invalid inputs handling
✅ Zero risk handling
✅ Large SL distance
✅ Small SL distance
✅ Different symbols
```

---

### **2. test_daily_loss_limit.mq5**
```
Module:  DailyLossLimit
Tests:   7 scenarios
Purpose: Validate daily loss tracking

Scenarios:
✅ Initial state
✅ Winning trades
✅ Losing trades
✅ Warning threshold (85%)
✅ Limit reached (100%+)
✅ Trading pause
✅ Daily reset
```

---

### **3. test_integration_day1.mq5**
```
Modules: All Day 1 modules
Tests:   6 scenarios
Purpose: Integration testing

Scenarios:
✅ Module initialization
✅ Position sizing with risk limit
✅ Daily loss tracking
✅ Risk guardian validation
✅ Warning system
✅ Emergency stop
```

---

## 🚀 **How to Run Tests**

### **Method 1: MetaEditor (Recommended)**

```
1. Open MetaEditor (F4)

2. File → Open → FlashEASuite_V2\Tester\test_position_sizing.mq5

3. Press F7 (Compile)
   Expected: "0 error(s), 0 warning(s)"

4. Open MT5 → Navigator → Scripts

5. Drag test file to chart

6. View results in Experts tab
```

---

### **Method 2: Batch Compile**

```powershell
# In MetaEditor:
# Tools → Options → Compiler
# Check "Allow DLL imports"

# Compile all:
cd FlashEASuite_V2\Tester
metaeditor64.exe /compile:test_position_sizing.mq5
metaeditor64.exe /compile:test_daily_loss_limit.mq5
metaeditor64.exe /compile:test_integration_day1.mq5
```

---

## ✅ **Expected Results**

### **All Tests Pass:**

```
╔════════════════════════════════════════════╗
║        TEST SUMMARY                        ║
╚════════════════════════════════════════════╝

Total Tests: 23
✅ Passed:   23
❌ Failed:   0

Success Rate: 100.0%

Status: ✅ ALL TESTS PASSED
```

---

## 🐛 **Troubleshooting**

### **Issue: Cannot open PositionSizingManager.mqh**

**Solution:**
```
Check file exists at:
FlashEASuite_V2\Include\Risk\PositionSizingManager.mqh

MQL5 auto-detects Include/ folder in project root.
```

---

### **Issue: Test file not in Navigator**

**Solution:**
```
1. Compile test file (F7)
2. Check .ex5 file created
3. Refresh Navigator (F5)
```

---

### **Issue: Tests fail**

**Solution:**
```
1. Check MT5 Experts tab for error messages
2. Verify Include files present
3. Check symbol exists (EURUSD, XAUUSD)
4. Ensure account has balance (demo OK)
```

---

## 📊 **Test Results Format**

```
Each test outputs:

╔════════════════════════════════════════════╗
║  TEST #X: [Test Name]                      ║
╚════════════════════════════════════════════╝

Input:
  - Parameter1: value
  - Parameter2: value

Expected: [expected result]
Actual:   [actual result]

Result: ✅ PASS / ❌ FAIL
Reason: [explanation if fail]

─────────────────────────────────────────────
```

---

## 🔧 **Adding New Tests**

### **Template:**

```mql5
//+------------------------------------------------------------------+
//|                                            test_my_module.mq5    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include <Risk/MyModule.mqh>

input bool InpRunAllTests = true;

void OnStart()
{
    Print("╔════════════════════════════════════════════╗");
    Print("║  MY MODULE - TESTS                         ║");
    Print("╚════════════════════════════════════════════╝");
    
    int passed = 0;
    int failed = 0;
    
    // Test 1
    if(Test_Scenario1()) passed++; else failed++;
    
    // Test 2
    if(Test_Scenario2()) passed++; else failed++;
    
    // Summary
    PrintSummary(passed, failed);
}

bool Test_Scenario1()
{
    Print("\n╔════════════════════════════════════════════╗");
    Print("║  TEST #1: [Description]                    ║");
    Print("╚════════════════════════════════════════════╝");
    
    // Test logic here
    bool result = true;
    
    if(result)
        Print("Result: ✅ PASS");
    else
        Print("Result: ❌ FAIL");
    
    return result;
}

void PrintSummary(int passed, int failed)
{
    int total = passed + failed;
    double success_rate = (total > 0) ? (passed * 100.0 / total) : 0;
    
    Print("\n╔════════════════════════════════════════════╗");
    Print("║        TEST SUMMARY                        ║");
    Print("╚════════════════════════════════════════════╝");
    Print("Total Tests: ", total);
    Print("✅ Passed: ", passed);
    Print("❌ Failed: ", failed);
    Print("Success Rate: ", DoubleToString(success_rate, 1), "%");
    
    if(failed == 0)
        Print("\nStatus: ✅ ALL TESTS PASSED");
    else
        Print("\nStatus: ⚠️ SOME TESTS FAILED");
}
//+------------------------------------------------------------------+
```

---

## 📈 **Continuous Integration**

```
Future: Automated testing via GitHub Actions

.github/workflows/test.yml:
  - Compile all test files
  - Run tests in MT5 headless
  - Generate test report
  - Upload results as artifact
```

---

## 📚 **References**

- Main README: `../README.md`
- Installation: `../docs/installation/`
- Troubleshooting: `../docs/fixes/`

---

**Test Coverage:** 100% (Day 1 modules)  
**Status:** ✅ All tests passing  
**Last Updated:** December 24, 2025
