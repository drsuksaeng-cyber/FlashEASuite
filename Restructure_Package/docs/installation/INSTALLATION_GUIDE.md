# 📦 Installation Guide - FlashEASuite V2

**Version:** 2.1 (Restructured)  
**Date:** December 24, 2025

---

## 🎯 **Installation Methods**

Choose the method that works best for you:

---

## ⚡ **Method 1: Project Copy (Recommended)**

### **Why this method?**
```
✅ Easiest - one copy operation
✅ Self-contained - everything in one place
✅ MT5 auto-detects Include/ folder
✅ Git-friendly - version control ready
```

### **Steps:**

**1. Locate MT5 Data Folder:**
```
Windows: Press Win+R, type:
%APPDATA%\MetaQuotes\Terminal

You'll see folders like:
B2C22A9C2EA0D03B7096C9AF7E852052\
```

**2. Copy Project:**
```
Extract FlashEASuite_V2.zip

Copy entire folder to:
[MT5_DATA]\MQL5\Experts\FlashEASuite_V2\

Final structure:
C:\Users\[USER]\AppData\Roaming\MetaQuotes\Terminal\
  [TERMINAL_ID]\
    MQL5\
      Experts\
        FlashEASuite_V2\    ← Here!
          ├── 00_Common/
          ├── 01_Feeder/
          ├── 02_Brain/
          ├── 03_Trader/
          ├── Include/      ← Auto-detected by MT5
          ├── Tester/
          └── docs/
```

**3. Verify:**
```
MetaEditor → Navigator → Experts → FlashEASuite_V2

You should see:
✅ All folders visible
✅ Include/ folder accessible
✅ Tester/ folder with test files
```

**4. Compile Tests:**
```
MetaEditor → Open → FlashEASuite_V2\Tester\test_integration_day1.mq5
Press F7

Expected: "0 error(s), 0 warning(s)" ✅
```

---

## 🔧 **Method 2: Manual Installation**

### **When to use?**
```
- Want to keep project separate
- Already have custom MQL5 structure
- Need granular control
```

### **Steps:**

**1. Copy Include Files:**
```
From: FlashEASuite_V2\Include\
To:   [MT5_DATA]\MQL5\Include\

Copy:
- Risk/ → Include\Risk\
- Logic/ → Include\Logic\
- Network/ → Include\Network\
- Utils/ → Include\Utils\
- Zmq/ → Include\Zmq\
```

**2. Copy Test Files:**
```
From: FlashEASuite_V2\Tester\
To:   [MT5_DATA]\MQL5\Scripts\Tests\

Copy all .mq5 files
```

**3. Copy Python Files:**
```
From: FlashEASuite_V2\02_Brain\
To:   [YOUR_PYTHON_PROJECT]\

Maintain structure:
- core/risk_management/
- core/strategy/
- modules/
```

**4. Compile & Test:**
```
Same as Method 1
```

---

## 🐍 **Python Setup**

### **1. Install Dependencies:**

```bash
cd FlashEASuite_V2/02_Brain
pip install -r requirements.txt
```

### **2. Verify Installation:**

```bash
python -c "from core.risk_management import DailyLossLimit; print('✅ OK')"
```

### **3. Run Brain:**

```bash
cd 02_Brain
python main.py
```

Expected output:
```
✅ Ingestion Worker started
✅ Strategy Engine started
✅ Policy Publisher started
✅ Execution Listener started

System ready!
```

---

## 🧪 **Verify Installation**

### **Test 1: Include Paths**

Open MetaEditor, create new script:

```mql5
#include <Risk/PositionSizingManager.mqh>

void OnStart()
{
    Print("Include test: OK");
}
```

Compile (F7) → Should succeed ✅

---

### **Test 2: Run Integration Test**

```
1. MetaEditor → Open → Tester\test_integration_day1.mq5
2. Compile (F7)
3. MT5 → Navigator → Scripts → test_integration_day1
4. Drag to chart
5. Check results (should be 6/6 pass)
```

---

## 🔍 **Troubleshooting**

### **Issue: "Cannot open PositionSizingManager.mqh"**

**Cause:** Include path not found

**Solution A (Project Copy):**
```
Verify structure:
FlashEASuite_V2\
  Include\
    Risk\
      PositionSizingManager.mqh  ← Must exist

MT5 auto-detects Include/ in project root
```

**Solution B (Manual):**
```
Check files at:
[MT5_DATA]\MQL5\Include\Risk\PositionSizingManager.mqh

If missing, copy from project
```

---

### **Issue: Test files not in Navigator**

**Cause:** Not compiled or wrong location

**Solution:**
```
1. Check location:
   - Project Copy: FlashEASuite_V2\Tester\
   - Manual: MQL5\Scripts\Tests\

2. Compile all test files (F7)

3. Refresh Navigator (F5)

4. Look for .ex5 files (compiled)
```

---

### **Issue: Python import error**

**Cause:** Wrong directory or missing files

**Solution:**
```bash
# Check current directory
pwd
# Should be in: FlashEASuite_V2/02_Brain/

# Check files exist
ls core/risk_management/
# Should see:
# - __init__.py
# - position_sizing.py
# - daily_loss_limit.py

# Test import
python -c "import sys; sys.path.insert(0, '.'); from core.risk_management import DailyLossLimit"
```

---

## 📁 **Directory Structure Check**

After installation, verify:

```
FlashEASuite_V2/
├── Include/
│   └── Risk/
│       ├── PositionSizingManager.mqh  ✅
│       ├── DailyLossLimit.mqh         ✅
│       └── RiskGuardian.mqh           ✅
│
├── Tester/
│   ├── test_position_sizing.mq5       ✅
│   ├── test_position_sizing.ex5       ✅ (after compile)
│   ├── test_daily_loss_limit.mq5      ✅
│   ├── test_daily_loss_limit.ex5      ✅ (after compile)
│   ├── test_integration_day1.mq5      ✅
│   └── test_integration_day1.ex5      ✅ (after compile)
│
└── 02_Brain/
    └── core/
        └── risk_management/
            ├── __init__.py             ✅
            ├── position_sizing.py      ✅
            └── daily_loss_limit.py     ✅
```

---

## ✅ **Success Checklist**

```
☑ FlashEASuite_V2 folder in correct location
☑ Include/ folder accessible
☑ All .mqh files present in Include/Risk/
☑ Test files in Tester/
☑ All tests compile (0 errors)
☑ Python imports work
☑ Integration test passes (6/6)
```

---

## 🚀 **Next Steps**

After successful installation:

1. **Read:** `../README.md`
2. **Run Tests:** `Tester/README.md`
3. **Start Trading:** `docs/guides/COMPLETE_RUN_GUIDE.md`

---

## 📞 **Support**

**Issues:** See `docs/fixes/`  
**Questions:** Check main README.md  
**Updates:** Git commit log

---

**Installation Time:** ~5 minutes  
**Difficulty:** Easy  
**Success Rate:** 99%+ 

✅ **You're ready to go!**
