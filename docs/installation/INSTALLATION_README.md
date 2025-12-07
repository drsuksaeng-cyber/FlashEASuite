# 📦 **FlashEASuite V2 - Installation Guide**

## 📋 **Files Package:**

This package contains 6 essential files:

### **MQL5 Files (4 files):**
1. `FeederEA_DEFINE.mq5` - Tick data feeder (uses #define, no encoding issues)
2. `ProgramC_Trader.mq5` - Trading executor with Grid strategy
3. `Strategy_Grid.mqh` - Elastic Grid strategy implementation
4. `PolicyManager.mqh` - Policy management system

### **Python Files (2 files):**
5. `main.py` - Main entry point (threading version, Windows compatible)
6. `strategy_threading.py` - Strategy engine (full 555 lines with Spike + Grid + Feedback)

---

## 🔧 **Installation Methods:**

### **Method 1: From ZIP File (Recommended)**

**Requirements:**
- `files.zip` containing all 6 files
- `INSTALL_ALL.bat`

**Steps:**
```batch
1. Place files.zip in:
   C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5\Experts\FlashEASuite_V2

2. Place INSTALL_ALL.bat in the same directory

3. Double-click INSTALL_ALL.bat

4. Wait for "Installation Complete!"
```

**What it does:**
- Extracts files.zip
- Copies all files to correct locations
- Overwrites existing files
- Cleans up temp files

---

### **Method 2: From Individual Files**

**Requirements:**
- All 6 files downloaded separately
- `INSTALL_MANUAL.bat`

**Steps:**
```batch
1. Place all 6 files + INSTALL_MANUAL.bat in:
   C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5\Experts\FlashEASuite_V2

2. Double-click INSTALL_MANUAL.bat

3. Confirm when asked (Y/N)

4. Wait for "Installation Complete!"
```

**What it does:**
- Checks all files are present
- Creates necessary directories
- Copies files to correct locations
- Creates Python __init__.py if needed

---

## 📂 **File Installation Map:**

```
FlashEASuite_V2/
├── 01_ProgramA_Feeder_MQL/
│   └── Src/
│       └── FeederEA.mq5           ← from FeederEA_DEFINE.mq5
│
├── 02_ProgramB_Brain_Py/
│   ├── main.py                    ← from main.py
│   └── core/
│       ├── __init__.py            ← auto-created
│       └── strategy.py            ← from strategy_threading.py
│
└── 03_ProgramC_Trader_MQL/
    └── ProgramC_Trader.mq5        ← from ProgramC_Trader.mq5

MQL5/Include/Logic/
├── Strategy_Grid.mqh              ← from Strategy_Grid.mqh
└── PolicyManager.mqh              ← from PolicyManager.mqh
```

---

## ✅ **After Installation:**

### **Step 1: Compile MQL5 Files**

```
1. Open MetaEditor
2. Navigate to FeederEA.mq5
3. Press F7 (Compile)
   Expected: 0 error(s), 0 warning(s) ✅

4. Navigate to ProgramC_Trader.mq5
5. Press F7 (Compile)
   Expected: 0 error(s), 0 warning(s) ✅
```

---

### **Step 2: Test Python Installation**

```batch
cd C:\Users\drsuk\AppData\Roaming\MetaQuotes\Terminal\B2C22A9C2EA0D03B7096C9AF7E852052\MQL5\Experts\FlashEASuite_V2\02_ProgramB_Brain_Py

python -c "from core.strategy import StrategyEngineThreaded; print('OK')"
```

**Expected output:** `OK`

---

### **Step 3: Run System**

**3.1 Start Feeder (MT5):**
```
1. Open XAUUSD M15 chart
2. Drag FeederEA.mq5 onto chart
3. Check Experts tab for:
   "SUCCESS: Feeder bound to tcp://127.0.0.1:7777"
```

**3.2 Start Python Brain:**
```batch
cd 02_ProgramB_Brain_Py
python main.py
```

**Expected output:**
```
FlashEASuite V2 - Program B (The Brain) 🧠
✅ All workers started successfully (3 threads)
Ticks processed: 1, 2, 3... ← increasing!
```

**3.3 Start Trader (MT5):**
```
1. Open another XAUUSD M15 chart
2. Drag ProgramC_Trader.mq5 onto chart
3. Set inputs:
   - InpZmqSubAddress: tcp://127.0.0.1:7778
   - InpZmqPushAddress: tcp://127.0.0.1:7779
   - InpGridMaxOrders: 5
   - InpGridBaseStep: 200.0
   - InpGridLotMult: 1.5
```

**Expected output:**
```
FlashEASuite V2: Trader Starting
✅ Added: Elastic Grid Strategy
✅ System Ready
[Grid] Policy Update: Risk=1.0x
```

---

## 🎯 **Verification:**

### **Check 1: Feeder → Python**
```
Python terminal should show:
"Ticks processed: 10, 20, 30..." ← increasing
```

### **Check 2: Python → Trader**
```
Python: "📤 POLICY (Grid): XAUUSD"
MT5: "[Grid] Policy Update"
```

### **Check 3: Feedback Loop**
```
When trade closes:
Python: "✅ FEEDBACK: WIN | Profit: +15.50"
Python: "Risk multiplier: 1.10x"
```

---

## 🚨 **Troubleshooting:**

### **Problem: Batch file doesn't run**
**Solution:** Right-click → "Run as Administrator"

### **Problem: "Cannot access base directory"**
**Solution:** 
1. Check the path in the batch file
2. Modify BASE_DIR if your MT5 data folder is different
3. Find your MT5 data folder: MT5 → File → Open Data Folder

### **Problem: MQL5 compilation errors**
**Solution:**
1. Make sure you used the batch file (not manual copy)
2. Check that Include/Logic folder exists
3. Try Method 2 (INSTALL_MANUAL.bat)

### **Problem: Python import error**
**Solution:**
```batch
cd 02_ProgramB_Brain_Py
pip install zmq msgpack
python -c "import zmq, msgpack; print('OK')"
```

---

## 📞 **Support Files:**

- `INSTALL_ALL.bat` - Auto installation from ZIP
- `INSTALL_MANUAL.bat` - Manual installation from individual files
- `FINAL_SOLUTION_COMPLETE.md` - Complete technical documentation
- `DOWNLOAD_CHECKLIST.md` - Quick reference for all files

---

## ⚡ **Quick Start (TL;DR):**

```batch
1. Put files.zip + INSTALL_ALL.bat in FlashEASuite_V2 folder
2. Run INSTALL_ALL.bat
3. Compile FeederEA.mq5 (F7)
4. Compile ProgramC_Trader.mq5 (F7)
5. Attach FeederEA → XAUUSD chart
6. Run: python main.py
7. Attach ProgramC_Trader → XAUUSD chart
8. ✅ Done!
```

---

## 🎉 **Success Indicators:**

```
✅ Feeder: "SUCCESS: Feeder bound..."
✅ Python: "Ticks processed: increasing..."
✅ Trader: "[Grid] Policy Update..."
✅ Feedback: "✅ FEEDBACK: WIN/LOSS..."
```

**System is operational!** 🎊

---

## 📊 **System Architecture:**

```
Feeder (7777) → Python Brain → Trader (7778 SUB, 7779 PUSH)
                    ↑_____________________________↓
                         (Feedback Loop)
```

---

## 💡 **Key Features:**

- ✅ Zero compilation errors (uses #define)
- ✅ Windows stable (threading, not multiprocessing)
- ✅ Complete implementation (555 lines strategy)
- ✅ Feedback loop (automatic risk adjustment)
- ✅ Grid + Spike strategies
- ✅ CSM integration
- ✅ Production ready

---

**Last Updated:** December 5, 2025
**Version:** FlashEASuite V2 - Final Release
**Compatibility:** Windows 10/11, MT5, Python 3.8+
