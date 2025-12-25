# 🚀 FlashEASuite V2 - High-Frequency Trading System

**Version:** 2.1 (Restructured)  
**Status:** ✅ Production Ready  
**Date:** December 24, 2025

---

## 📁 **Project Structure**

```
FlashEASuite_V2/
│
├── 00_Common/              # Shared resources (keys, specs)
├── 01_Feeder/              # MT5 Data Collector (FeederEA)
├── 02_Brain/               # Python AI Analysis Engine
│   ├── core/
│   │   ├── strategy/       # Trading strategies
│   │   └── risk_management/# Risk management modules
│   ├── modules/            # Utility modules
│   └── logs/               # System logs
│
├── 03_Trader/              # MT5 Order Executor (Trader)
│
├── Include/                # Shared MQL5 Libraries
│   ├── Risk/               # Risk management (Day 1 Complete)
│   ├── Logic/              # Trading logic
│   ├── Network/            # Communication protocol
│   ├── Utils/              # Utilities
│   └── Zmq/                # ZeroMQ wrapper
│
├── Tester/                 # Test Suite (NEW!)
│   ├── test_position_sizing.mq5
│   ├── test_daily_loss_limit.mq5
│   └── test_integration_day1.mq5
│
└── docs/                   # Documentation
    ├── guides/             # User guides
    ├── installation/       # Installation instructions
    ├── fixes/              # Bug fixes & solutions
    └── summaries/          # Technical summaries
```

---

## 🎯 **Quick Start**

### **1. System Requirements**
```
MT5:     Build 3770+ (64-bit)
Python:  3.8+
ZMQ:     libzmq 4.3+
OS:      Windows 10/11
```

### **2. Installation**

**Option A: Use MT5 Data Folder**
```powershell
# Copy entire project to:
C:\Users\[USERNAME]\AppData\Roaming\MetaQuotes\Terminal\[TERMINAL_ID]\MQL5\Experts\FlashEASuite_V2\

# MT5 will auto-detect Include/ folder
```

**Option B: Manual Installation**
```
See: docs/installation/INSTALLATION_GUIDE.md
```

### **3. Run Tests**

```
1. Open MetaEditor
2. Open: FlashEASuite_V2\Tester\test_integration_day1.mq5
3. Press F7 (Compile)
4. Drag to chart
5. Check results
```

---

## ✅ **Day 1: Risk Management (COMPLETE)**

### **Modules:**
```
✅ PositionSizingManager    - 1% risk rule calculator
✅ DailyLossLimit          - 4% max daily loss limiter
✅ RiskGuardian            - Master risk validator
```

### **Features:**
```
✅ ATR-based volatility adjustment
✅ Real-time P&L tracking
✅ Auto trading pause at limit
✅ Daily reset functionality
✅ Comprehensive testing (23 tests)
```

### **Tests:**
```
Location: Tester/
Status:   100% Pass (23/23 tests)

Test 1: Position Sizing      (10 tests)
Test 2: Daily Loss Limit     (7 tests)
Test 3: Integration          (6 tests)
```

---

## 🔧 **Development**

### **Adding New Features:**
```
1. Add .mqh files → Include/[Category]/
2. Add test files → Tester/
3. Update documentation
4. Run tests
5. Git commit
```

### **Include Paths:**
```mql5
// From any MQL5 file in project:
#include <Risk/PositionSizingManager.mqh>
#include <Logic/Strategy_Grid.mqh>
#include <Network/Protocol.mqh>
```

---

## 📊 **System Architecture**

```
Market → MT5 → FeederEA → Python Brain → Trader → MT5 → Market
                 (7777)      (7778)        (7779)
```

**Communication:**
- ZeroMQ (PUB/SUB pattern)
- MessagePack serialization
- Localhost TCP (ports 7777, 7778, 7779)

**Latency:**
- Python processing: ~3-7ms
- End-to-end: ~25-160ms

---

## 📚 **Documentation**

### **Must Read:**
```
docs/installation/QUICK_START.md     - Get started in 5 minutes
docs/guides/COMPLETE_RUN_GUIDE.md    - Full system guide
Tester/README.md                     - Testing guide
```

### **Technical:**
```
docs/summaries/SYSTEM_OVERVIEW.md    - Architecture overview
docs/summaries/REFACTORING_COMPLETE.md - Code structure
```

---

## 🐛 **Troubleshooting**

### **Common Issues:**

**"Cannot open [file].mqh"**
```
→ Check Include/ folder exists in project
→ Verify file path: Include/Risk/PositionSizingManager.mqh
```

**Test files not visible in Navigator**
```
→ Compile test files (F7 in MetaEditor)
→ Check .ex5 files created in Tester/
```

**Python import errors**
```
→ Check 02_Brain/core/risk_management/
→ Run: python -c "from core.risk_management import DailyLossLimit"
```

---

## 🔄 **Version History**

### **v2.1 (Dec 24, 2025)** ← Current
```
✅ Restructured project (self-contained)
✅ Added Tester/ directory
✅ Cleaned up duplicate files
✅ Updated documentation
✅ Added .gitignore
```

### **v2.0 (Dec 6, 2025)**
```
✅ Major refactoring complete
✅ Modular code structure
✅ Day 1 Risk Management complete
```

---

## 🚀 **Next Steps**

- [ ] Day 2: Grid Trading System
- [ ] Day 3: Market Analysis
- [ ] Day 4: Signal Generation
- [ ] Day 5: Integration & Testing

---

## 📞 **Support**

**Documentation:** See `docs/` folder  
**Issues:** Check `docs/fixes/`  
**Updates:** Git commit history

---

## ⚖️ **License**

Copyright (c) 2025 Dr. Suksaeng Kukanok  
All rights reserved.

---

**Status:** 🟢 Production Ready  
**Last Updated:** December 24, 2025
