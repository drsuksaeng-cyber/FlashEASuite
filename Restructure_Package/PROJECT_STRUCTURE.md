# 📁 FlashEASuite V2 - Project Structure

**Version:** 2.1 (Restructured)  
**Date:** December 24, 2025

---

## 🌳 **Complete Directory Tree**

```
FlashEASuite_V2/
│
├── 00_Common/                      # Shared Resources
│   ├── Keys/                       # ZMQ Security Keys
│   │   ├── client.key
│   │   ├── client.key_secret
│   │   ├── server.key
│   │   └── server.key_secret
│   └── ProtocolSpecs.md            # Communication protocol specs
│
├── 01_Feeder/                      # MT5 Data Collector
│   └── Src/
│       ├── FeederEA.mq5            # Source code
│       └── FeederEA.ex5            # Compiled (generated)
│
├── 02_Brain/                       # Python AI Engine
│   ├── main.py                     # Entry point
│   ├── config.py                   # Configuration
│   ├── requirements.txt            # Python dependencies
│   │
│   ├── core/                       # Core Modules
│   │   ├── __init__.py
│   │   ├── ingestion.py           # Tick data receiver
│   │   ├── execution_listener.py  # Trade result receiver
│   │   │
│   │   ├── strategy/              # Trading Strategies
│   │   │   ├── __init__.py
│   │   │   ├── engine.py          # Strategy engine
│   │   │   ├── analysis.py        # Market analysis
│   │   │   ├── policy.py          # Policy generation
│   │   │   └── feedback.py        # Performance tracking
│   │   │
│   │   └── risk_management/       # Risk Management (Day 1) ⭐
│   │       ├── __init__.py
│   │       ├── position_sizing.py # Position size calculator
│   │       └── daily_loss_limit.py# Daily loss limiter
│   │
│   ├── modules/                   # Utility Modules
│   │   ├── __init__.py
│   │   ├── currency_meter.py     # Currency strength
│   │   └── tick_analyzer.py      # Tick analysis
│   │
│   └── logs/                      # System Logs
│       └── flashea_brain.log     # (generated)
│
├── 03_Trader/                     # MT5 Order Executor
│   └── ProgramC_Trader.mq5        # Main trader EA
│
├── Include/                       # Shared MQL5 Libraries ⭐
│   │
│   ├── Risk/                      # Risk Management (Day 1)
│   │   ├── PositionSizingManager.mqh
│   │   ├── DailyLossLimit.mqh
│   │   └── RiskGuardian.mqh
│   │
│   ├── Logic/                     # Trading Logic
│   │   ├── StrategyBase.mqh
│   │   ├── StrategyManager.mqh
│   │   ├── Strategy_Grid.mqh
│   │   ├── Strategy_Spike.mqh
│   │   ├── PolicyManager.mqh
│   │   ├── DailyStats.mqh
│   │   ├── SpreadFilter.mqh
│   │   └── TickDensity.mqh
│   │   │
│   │   └── Grid/                  # Grid Trading System
│   │       ├── GridConfig.mqh
│   │       ├── GridState.mqh
│   │       ├── GridCore.mqh
│   │       ├── GridDecision.mqh
│   │       ├── GridExecution.mqh
│   │       └── ... (more grid modules)
│   │
│   ├── Network/                   # Communication
│   │   ├── Protocol.mqh           # Main wrapper
│   │   ├── ZmqHub.mqh             # ZMQ hub manager
│   │   │
│   │   └── Protocol/              # Protocol Modules
│   │       ├── Definitions.mqh    # Message definitions
│   │       └── Serialization.mqh  # MessagePack
│   │
│   ├── Utils/                     # Utilities
│   │   └── TradeLogger.mqh
│   │
│   └── Zmq/                       # ZeroMQ Wrapper
│       ├── Zmq.mqh
│       └── ZmqHub.mqh
│
├── Tester/                        # Test Suite ⭐ NEW!
│   ├── README.md                  # Testing guide
│   ├── test_position_sizing.mq5  # Position sizing tests (10)
│   ├── test_daily_loss_limit.mq5 # Daily loss tests (7)
│   └── test_integration_day1.mq5 # Integration tests (6)
│
├── docs/                          # Documentation
│   │
│   ├── installation/              # Installation Guides
│   │   ├── INSTALLATION_GUIDE.md # Detailed guide
│   │   └── QUICK_START.md        # 5-minute guide
│   │
│   ├── guides/                    # User Guides
│   │   ├── COMPLETE_RUN_GUIDE.md
│   │   └── ...
│   │
│   ├── fixes/                     # Bug Fixes & Solutions
│   │   ├── FIX_SYNTAX_ERROR.md
│   │   └── ...
│   │
│   ├── summaries/                 # Technical Summaries
│   │   ├── SYSTEM_OVERVIEW.md    # Architecture
│   │   ├── REFACTORING_COMPLETE.md # v2.0 changes
│   │   ├── DATA_CONTROL_FLOW.md  # Data flow
│   │   └── FEEDER_EA_TECHNICAL_DOC.md
│   │
│   └── HANDOFF_PROMPT.md          # Chat session handoff
│
├── .gitignore                     # Git ignore file ⭐ NEW!
├── README.md                      # Main documentation ⭐
├── CHANGELOG.md                   # Version history ⭐ NEW!
└── PROJECT_STRUCTURE.md           # This file ⭐ NEW!
```

---

## 📊 **Statistics**

### **File Count:**
```
Total Files: ~50+ files
- MQL5 Source (.mq5): 6
- MQL5 Include (.mqh): 25+
- Python (.py): 12
- Documentation (.md): 15+
- Config/Data: 5+
```

### **Lines of Code:**
```
MQL5:   ~8,000 lines
Python: ~4,000 lines
Docs:   ~6,000 lines
Total:  ~18,000 lines
```

### **Directory Count:**
```
Total Directories: 26
- Core: 9
- Include: 8
- Docs: 5
- Tests: 1
- Other: 3
```

---

## 🎯 **Key Directories**

### **⭐ Include/**
```
Purpose: Shared MQL5 libraries
Access:  #include <Risk/PositionSizingManager.mqh>
Status:  Auto-detected by MT5 (in project root)

Contains:
- Risk management modules (Day 1 ✅)
- Trading logic
- Communication protocol
- Utilities
```

### **⭐ Tester/**
```
Purpose: Test suite
Files:   3 test scripts (23 total tests)
Status:  100% pass rate

Contains:
- Position sizing tests (10)
- Daily loss limit tests (7)
- Integration tests (6)
```

### **02_Brain/core/risk_management/**
```
Purpose: Python risk management
Status:  Working

Contains:
- position_sizing.py
- daily_loss_limit.py
- Integration with strategy engine
```

---

## 🔄 **Data Flow Through Structure**

```
Market
  ↓
01_Feeder/FeederEA.mq5
  ↓ (ZMQ port 7777)
02_Brain/core/ingestion.py
  ↓
02_Brain/core/strategy/engine.py
  ↓ (uses)
02_Brain/core/risk_management/
  ↓ (ZMQ port 7778)
03_Trader/ProgramC_Trader.mq5
  ↓ (uses)
Include/Risk/RiskGuardian.mqh
  ↓
Market (order execution)
  ↓ (ZMQ port 7779)
02_Brain/core/execution_listener.py
  ↓
02_Brain/core/strategy/feedback.py
```

---

## 📦 **Include Path Resolution**

### **How MT5 Finds Include Files:**

```
When you write:
#include <Risk/PositionSizingManager.mqh>

MT5 searches in order:
1. [PROJECT_ROOT]/Include/Risk/PositionSizingManager.mqh  ← FOUND! ✅
2. [MT5_DATA]/MQL5/Include/Risk/PositionSizingManager.mqh
3. [MT5_INSTALL]/Include/Risk/PositionSizingManager.mqh

Since Include/ is in project root, it finds it first!
```

### **Advantages:**

```
✅ No manual copying needed
✅ Self-contained project
✅ Version control friendly
✅ Easy deployment
✅ No conflicts with other projects
```

---

## 🎯 **What's Different from v2.0**

### **Added:**
```
+ Tester/               # Centralized test suite
+ .gitignore            # Git ignore file
+ CHANGELOG.md          # Version history
+ PROJECT_STRUCTURE.md  # This file
+ docs/installation/    # Installation guides
```

### **Reorganized:**
```
~ Include/              # Now in project root (was scattered)
~ Test files            # Now in Tester/ (was in Scripts/)
~ Documentation         # Better organized in docs/
```

### **Removed:**
```
- Duplicate .zip files  # 20+ archives
- Old .bat versions     # v2, v3, FIXED versions
- Scattered test files  # Consolidated to Tester/
- Redundant docs        # Merged or archived
```

---

## 🚀 **For Developers**

### **Adding New Modules:**

**MQL5 Include:**
```
1. Create file in appropriate Include/ subfolder
2. Follow naming: CamelCase.mqh
3. Add to git
4. Document in README
```

**Python Module:**
```
1. Create file in 02_Brain/core/ or modules/
2. Add __init__.py if new package
3. Update requirements.txt if needed
4. Add tests
```

**Test Files:**
```
1. Create in Tester/
2. Follow naming: test_[module].mq5
3. Use template from Tester/README.md
4. Document expected results
```

---

## 📝 **File Naming Conventions**

### **MQL5:**
```
Include files:   CamelCase.mqh     (e.g., PositionSizingManager.mqh)
Source files:    CamelCase.mq5     (e.g., FeederEA.mq5)
Test files:      test_snake_case.mq5 (e.g., test_position_sizing.mq5)
```

### **Python:**
```
Modules:         snake_case.py     (e.g., position_sizing.py)
Classes:         CamelCase         (e.g., DailyLossLimit)
Functions:       snake_case        (e.g., calculate_lot_size)
```

### **Documentation:**
```
Guides:          SCREAMING_SNAKE.md  (e.g., QUICK_START.md)
Technical:       SCREAMING_SNAKE.md  (e.g., SYSTEM_OVERVIEW.md)
```

---

## ✅ **Verification Commands**

### **Check Structure:**
```bash
# Linux/Mac
find . -type d -name "Include" -o -name "Tester"

# Windows PowerShell
Get-ChildItem -Directory -Recurse | Where-Object {$_.Name -in @("Include","Tester")}
```

### **Count Files:**
```bash
# MQL5 files
find . -name "*.mq5" -o -name "*.mqh" | wc -l

# Python files
find . -name "*.py" | wc -l

# Documentation
find . -name "*.md" | wc -l
```

### **Verify Tests:**
```bash
# Should have 3 test files
ls Tester/test_*.mq5
```

---

## 🎯 **Next Steps**

After understanding the structure:

1. **Read:** `README.md`
2. **Install:** `docs/installation/QUICK_START.md`
3. **Test:** `Tester/README.md`
4. **Develop:** Start adding features!

---

**Structure Version:** 2.1  
**Status:** ✅ Clean & Organized  
**Last Updated:** December 24, 2025
