# 📊 **FlashEASuite V2 - Project Restructure Proposal**

## 📅 **Date:** December 6, 2025
## 🎯 **Purpose:** Reorganize project structure for better maintainability

---

## 📋 **Part 1: Non-Code Files Classification**

### **📚 Type 1.1: Documentation (Move to `/docs` folder)**

**Root Level:**
```
✅ COMPLETE_RUN_GUIDE.md              (12 KB)
✅ DOWNLOAD_CHECKLIST.md               (1.7 KB)
✅ FINAL_FIX_TIMESTAMP.md              (6.7 KB)
✅ FINAL_SOLUTION_COMPLETE.md          (7.8 KB)
✅ FIX_ACCESS_VIOLATION.md             (4.5 KB)
✅ FIX_PROGRAMC_ERRORS.md              (8.4 KB)
✅ FIX_SYNTAX_ERROR.md                 (4.4 KB)
✅ INSTALLATION_README.md              (6.5 KB)
✅ MASTER_SUMMARY.md                   (7.2 KB)
✅ PACKAGE_SUMMARY.md                  (7.2 KB)
✅ QUICK_FIX_SUMMARY.md                (1.7 KB)
✅ QUICK_SUMMARY.md                    (1.9 KB)
✅ READY_TO_TEST.md                    (1.8 KB)
```

**02_ProgramB_Brain_Py/:**
```
✅ FEEDBACK_LOOP_GUIDE.md              (10 KB)
✅ QUICKSTART.md                       (4.5 KB)
✅ QUICK_START.md                      (5.0 KB)
✅ README.md                           (8.5 KB)
✅ TASK1_SUMMARY.md                    (10 KB)
✅ TEST_TRADE_RESULT_GUIDE.md          (7.8 KB)
```

**03_ProgramC_Trader_MQL/:**
```
✅ DELIVERY_SUMMARY.txt                (18 KB)
✅ INSTALLATION_INSTRUCTIONS.txt       (12 KB)
✅ INTEGRATION_GUIDE.txt               (11 KB)
✅ QUICK_FIX_FOR_YOUR_STRUCTURE.txt    (7.5 KB)
✅ README.txt                          (9.1 KB)
✅ START_HERE.txt                      (7.7 KB)
```

**03_ProgramC_Trader_MQL/files/:**
```
✅ DELIVERY_SUMMARY.txt                (18 KB - duplicate)
✅ INSTALLATION_INSTRUCTIONS.txt       (12 KB - duplicate)
✅ INTEGRATION_GUIDE.txt               (11 KB - duplicate)
✅ QUICK_FIX_FOR_YOUR_STRUCTURE.txt    (7.5 KB - duplicate)
✅ START_HERE.txt                      (7.7 KB - duplicate)
```

**00_Common/:**
```
✅ ProtocolSpecs.md                    (803 bytes)
```

**Misc:**
```
✅ new chat4.txt                       (40 KB - temp file)
```

**Total Documentation:** ~35 files, ~250 KB

---

### **🗑️ Type 1.2: Test Files & Trash (DELETE)**

**Test Python Files:**
```
❌ test_brain_server.py                (10 KB)
❌ test_feedback_loop.py               (17 KB)
❌ test_feeder.py                      (1.7 KB)
❌ test_policy_sender.py               (1.8 KB)
❌ test_port_scanner.py                (2.0 KB)
❌ test_receiver.py                    (4.2 KB)
❌ test_trade_receiver.py              (3.5 KB)
❌ test_zmq_receive.py                 (2.2 KB)
❌ simple_server.py                    (1 KB)
❌ spike_simulation.py                 (3.7 KB)
```

**Test MQL Files:**
```
❌ SimpleSender.mq5                    (1.9 KB)
❌ TestNetworkingLayer.mq5             (12 KB)
❌ TestTradeReporter.mq5               (7.3 KB)
❌ TestTradeReporter_fixed.mq5         (7.4 KB)
❌ TestTradeReporter_Standalone.mq5    (8.2 KB)
❌ FeederEA_DEFINE.mq5                 (4.2 KB - old version)
```

**Old Versions (_o1 suffix):**
```
❌ ProgramC_Trader_o1.mq5              (5 KB)
❌ MqlMsgPack_o1.mqh                   (9 KB)
❌ ZmqHub_o1.mqh                       (5.5 KB)
❌ Zmq_o1.mqh                          (2.2 KB)
```

**Empty Files:**
```
❌ Settings.mqh                        (0 bytes)
❌ Strategy_Standalone.mqh             (0 bytes)
❌ Strategy_Trend.mqh                  (0 bytes)
❌ ga_optimizer.py                     (0 bytes)
❌ regime_analyzer.py                  (0 bytes)
❌ __init__.py                         (0 bytes × 4 files)
```

**Duplicate Folder:**
```
❌ python_fixed/                       (entire folder - duplicate of 02_ProgramB_Brain_Py)
```

**Duplicate Files in Root:**
```
❌ main.py                             (4 KB - duplicate)
❌ PolicyManager.mqh                   (1.6 KB - duplicate)
❌ ProgramC_Trader.mq5                 (4.3 KB - duplicate)
❌ Strategy_Grid.mqh                   (17 KB - duplicate)
❌ strategy_threading.py               (18 KB - duplicate)
❌ test_trade_receiver.py              (3.5 KB - duplicate)
❌ test_zmq_receive.py                 (2.2 KB - duplicate)
```

**Git Folder (optional - can keep or remove):**
```
⚠️ .git/                               (~5 MB - version control)
```

**Misc Trash:**
```
❌ generate_keys.py                    (1.2 KB - utility)
❌ czmq_placeholder.txt                (0 bytes)
```

**Total Trash:** ~60 files, ~150 KB (excluding python_fixed/ and .git/)

---

## 📐 **Part 2: Code Files Analysis**

### **🔴 Large Files (>10 KB or >400 lines) - NEED SPLITTING**

**Python Files:**
```
🔴 core/strategy.py                   18,956 bytes  (~549 lines)  
   → Need to split into multiple files

🔴 strategy_threading.py              18,851 bytes  (~545 lines)
   → Duplicate of core/strategy.py - DELETE
```

**MQL5 Include Files:**
```
🔴 Include/Network/Protocol.mqh       19,241 bytes  (~523 lines)
   → Split into: Protocol_Base.mqh + Protocol_Messages.mqh

🔴 Include/Logic/Strategy_Grid.mqh    17,255 bytes  (~468 lines)
   → OK but close to limit - consider splitting later

⚠️ Include/Logic/DailyStats.mqh        9,254 bytes  (~251 lines)
   → OK - under limit

⚠️ Include/Logic/Strategy_Spike.mqh    9,046 bytes  (~245 lines)
   → OK - under limit
```

---

### **🟢 Medium Files (5-10 KB) - ACCEPTABLE**

**Python:**
```
🟢 core/execution_listener.py          8,126 bytes  (~220 lines) ✅
🟢 main.py                             8,291 bytes  (~225 lines) ✅
🟢 generate_report.py                  6,984 bytes  (~190 lines) ✅
🟢 core/ingestion.py                   5,770 bytes  (~156 lines) ✅
```

**MQL5:**
```
🟢 Include/Network/ZmqHub.mqh          7,368 bytes  (~200 lines) ✅
🟢 Include/Logic/TickDensity.mqh       5,826 bytes  (~158 lines) ✅
```

---

### **🟢 Small Files (<5 KB) - GOOD**

**Python:**
```
🟢 config.py                           4,375 bytes  (~118 lines) ✅
🟢 modules/tick_analyzer.py            3,814 bytes  (~103 lines) ✅
🟢 modules/currency_meter.py           3,619 bytes  (~98 lines) ✅
```

**MQL5:**
```
🟢 ProgramC_Trader.mq5                 4,351 bytes  (~118 lines) ✅
🟢 Include/MqlMsgPack.mqh              4,607 bytes  (~125 lines) ✅
🟢 Include/Logic/StrategyManager.mqh   3,961 bytes  (~107 lines) ✅
🟢 Include/Logic/Strategy_Implementation.mqh  3,381 bytes ✅
🟢 Include/Zmq/Zmq.mqh                 2,853 bytes  (~77 lines) ✅
🟢 Include/Zmq/ZmqHub.mqh              2,602 bytes  (~70 lines) ✅
🟢 Include/Logic/SpreadFilter.mqh      2,701 bytes  (~73 lines) ✅
🟢 FeederEA.mq5                        2,643 bytes  (~72 lines) ✅
🟢 Include/Risk/RiskGuardian.mqh       2,321 bytes  (~63 lines) ✅
🟢 Include/Security.mqh                1,994 bytes  (~54 lines) ✅
🟢 Include/Logic/PolicyManager.mqh     1,690 bytes  (~46 lines) ✅
🟢 Include/Logic/StrategyBase.mqh      1,494 bytes  (~40 lines) ✅
```

---

## 🎯 **Part 3: Proposed Splitting Strategy**

### **3.1: Split `core/strategy.py` (~549 lines)**

**Current:** Single large file

**Proposed Structure:**
```
core/
├── strategy/
│   ├── __init__.py                    # Exports
│   ├── strategy_base.py               # ~100 lines - Base class
│   ├── strategy_engine.py             # ~150 lines - Main engine
│   ├── strategy_feedback.py           # ~100 lines - Feedback logic
│   ├── strategy_csm.py                # ~80 lines - CSM integration
│   └── strategy_dashboard.py          # ~80 lines - Dashboard/stats
```

**Benefits:**
- Each file < 150 lines
- Clear separation of concerns
- Easier to maintain
- Better testability

---

### **3.2: Split `Include/Network/Protocol.mqh` (~523 lines)**

**Current:** Single large file

**Proposed Structure:**
```
Include/Network/
├── Protocol_Base.mqh                  # ~100 lines - Constants, enums
├── Protocol_Messages.mqh              # ~150 lines - Message structures
├── Protocol_Serialization.mqh         # ~150 lines - Pack/unpack logic
└── Protocol_Validation.mqh            # ~120 lines - Validation logic
```

**Benefits:**
- Modular design
- Easier to extend
- Each file focused on single responsibility

---

### **3.3: Optional - Split `Include/Logic/Strategy_Grid.mqh` (468 lines)**

**Current:** Close to 400-line limit (468 lines)

**If split later:**
```
Include/Logic/
├── Strategy_Grid_Core.mqh             # ~200 lines - Core logic
├── Strategy_Grid_Risk.mqh             # ~150 lines - Risk management
└── Strategy_Grid_Utils.mqh            # ~120 lines - Utility functions
```

---

## 📂 **Part 4: Proposed New Structure**

### **Current Structure (Messy):**
```
FlashEASuite_V2/
├── .git/                              ← Keep or remove
├── 00_Common/
│   └── ProtocolSpecs.md
├── 01_ProgramA_Feeder_MQL/
│   └── Src/
│       └── FeederEA.mq5
├── 02_ProgramB_Brain_Py/
│   ├── core/
│   │   ├── execution_listener.py
│   │   ├── ingestion.py
│   │   └── strategy.py               ← Too large!
│   ├── modules/
│   │   ├── currency_meter.py
│   │   ├── tick_analyzer.py
│   │   ├── ga_optimizer.py           ← Empty
│   │   └── regime_analyzer.py        ← Empty
│   ├── config.py
│   ├── generate_report.py
│   ├── main.py
│   ├── requirements.txt
│   ├── [10+ test files]              ← Too many
│   └── [6+ .md files]                ← Mixed
├── 03_ProgramC_Trader_MQL/
│   ├── Config/
│   │   └── Settings.mqh              ← Empty
│   ├── files/                        ← Duplicates
│   ├── ProgramC_Trader.mq5
│   ├── ProgramC_Trader_o1.mq5        ← Old version
│   ├── [5+ test .mq5 files]          ← Too many
│   └── [6+ .txt files]               ← Mixed
├── Include/
│   ├── Logic/
│   │   ├── [10 .mqh files]
│   │   ├── Strategy_Standalone.mqh   ← Empty
│   │   └── Strategy_Trend.mqh        ← Empty
│   ├── Network/
│   │   ├── Protocol.mqh              ← Too large!
│   │   └── ZmqHub.mqh
│   ├── Risk/
│   │   └── RiskGuardian.mqh
│   ├── Zmq/
│   │   ├── Zmq.mqh
│   │   ├── ZmqHub.mqh
│   │   ├── Zmq_o1.mqh                ← Old version
│   │   ├── ZmqHub_o1.mqh             ← Old version
│   │   └── czmq_placeholder.txt      ← Empty
│   ├── MqlMsgPack.mqh
│   ├── MqlMsgPack_o1.mqh             ← Old version
│   └── Security.mqh
├── python_fixed/                     ← Entire duplicate folder!
├── [13+ .md files in root]           ← Documentation scattered
├── [7+ duplicate .mqh/.py files]     ← Duplicates
├── [3+ test files in root]           ← Scattered
└── new chat4.txt                     ← Temp file
```

**Problems:**
- ❌ Documentation scattered everywhere
- ❌ Test files mixed with production code
- ❌ Duplicates in root folder
- ❌ Duplicate `python_fixed/` folder
- ❌ Empty files not removed
- ❌ Old versions (_o1) not removed
- ❌ Large files not split

---

### **Proposed New Structure (Clean):**

```
FlashEASuite_V2/
│
├── 📁 src/                            ← All production code
│   │
│   ├── 01_Feeder_MQL/
│   │   └── FeederEA.mq5              (72 lines) ✅
│   │
│   ├── 02_Brain_Python/
│   │   ├── core/
│   │   │   ├── strategy/             ← Split from strategy.py
│   │   │   │   ├── __init__.py
│   │   │   │   ├── engine.py         (~150 lines)
│   │   │   │   ├── feedback.py       (~100 lines)
│   │   │   │   ├── csm.py            (~80 lines)
│   │   │   │   └── dashboard.py      (~80 lines)
│   │   │   ├── execution_listener.py (220 lines) ✅
│   │   │   ├── ingestion.py          (156 lines) ✅
│   │   │   └── __init__.py
│   │   │
│   │   ├── modules/
│   │   │   ├── currency_meter.py     (98 lines) ✅
│   │   │   ├── tick_analyzer.py      (103 lines) ✅
│   │   │   └── __init__.py
│   │   │
│   │   ├── config.py                 (118 lines) ✅
│   │   ├── main.py                   (225 lines) ✅
│   │   └── requirements.txt
│   │
│   ├── 03_Trader_MQL/
│   │   └── ProgramC_Trader.mq5       (118 lines) ✅
│   │
│   └── Include/
│       ├── Logic/
│       │   ├── DailyStats.mqh        (251 lines) ✅
│       │   ├── PolicyManager.mqh     (46 lines) ✅
│       │   ├── SpreadFilter.mqh      (73 lines) ✅
│       │   ├── StrategyBase.mqh      (40 lines) ✅
│       │   ├── StrategyManager.mqh   (107 lines) ✅
│       │   ├── Strategy_Grid.mqh     (468 lines) ⚠️
│       │   ├── Strategy_Implementation.mqh (91 lines) ✅
│       │   ├── Strategy_Spike.mqh    (245 lines) ✅
│       │   └── TickDensity.mqh       (158 lines) ✅
│       │
│       ├── Network/
│       │   ├── Protocol/             ← Split from Protocol.mqh
│       │   │   ├── Base.mqh          (~100 lines)
│       │   │   ├── Messages.mqh      (~150 lines)
│       │   │   ├── Serialization.mqh (~150 lines)
│       │   │   └── Validation.mqh    (~120 lines)
│       │   └── ZmqHub.mqh            (200 lines) ✅
│       │
│       ├── Risk/
│       │   └── RiskGuardian.mqh      (63 lines) ✅
│       │
│       ├── Zmq/
│       │   ├── Zmq.mqh               (77 lines) ✅
│       │   └── ZmqHub.mqh            (70 lines) ✅
│       │
│       ├── MqlMsgPack.mqh            (125 lines) ✅
│       └── Security.mqh              (54 lines) ✅
│
├── 📁 docs/                          ← All documentation
│   ├── installation/
│   │   ├── COMPLETE_RUN_GUIDE.md
│   │   ├── INSTALLATION_README.md
│   │   └── QUICK_START.md
│   │
│   ├── fixes/
│   │   ├── FINAL_FIX_TIMESTAMP.md
│   │   ├── FIX_ACCESS_VIOLATION.md
│   │   ├── FIX_PROGRAMC_ERRORS.md
│   │   └── FIX_SYNTAX_ERROR.md
│   │
│   ├── guides/
│   │   ├── FEEDBACK_LOOP_GUIDE.md
│   │   ├── README.md
│   │   └── TEST_TRADE_RESULT_GUIDE.md
│   │
│   ├── summaries/
│   │   ├── FINAL_SOLUTION_COMPLETE.md
│   │   ├── MASTER_SUMMARY.md
│   │   ├── PACKAGE_SUMMARY.md
│   │   ├── TASK1_SUMMARY.md
│   │   └── DOWNLOAD_CHECKLIST.md
│   │
│   └── archive/                      ← Old documentation
│       └── [Trader .txt files]
│
├── 📁 tools/                         ← Utilities
│   ├── generate_report.py
│   └── generate_keys.py
│
├── .gitignore
├── README.md                         ← Main readme
└── LICENSE
```

**Benefits:**
- ✅ Clear separation: src / docs / tools
- ✅ All production code in `src/`
- ✅ All docs in `docs/` with subcategories
- ✅ No test files in production
- ✅ No duplicates
- ✅ No empty files
- ✅ All files < 400 lines (except Strategy_Grid at 468)
- ✅ Clean, professional structure

---

## 🔄 **Part 5: Data Flow & Control Flow**

### **5.1: System Architecture (3-Component)**

```
┌─────────────────────────────────────────────────────────────┐
│                   FlashEASuite V2                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐                                          │
│  │ Component 1  │  Feeder (MQL5)                           │
│  │──────────────│                                           │
│  │ FeederEA.mq5 │                                           │
│  └──────┬───────┘                                           │
│         │ ZMQ PUB (Port 7777)                               │
│         │ Tick Data                                         │
│         ↓                                                   │
│  ┌──────────────┐                                          │
│  │ Component 2  │  Brain (Python)                          │
│  │──────────────│                                           │
│  │ Ingestion ←──┘  Receives ticks                          │
│  │      ↓                                                   │
│  │ Strategy      Analyzes + generates policies             │
│  │      ↓                                                   │
│  │ Execution ←──┐  Receives feedback                       │
│  └──────┬───────┘                                           │
│         │ ZMQ PUB (Port 7778)                               │
│         │ Policies                                          │
│         ↓                                                   │
│  ┌──────────────┐                                          │
│  │ Component 3  │  Trader (MQL5)                           │
│  │──────────────│                                           │
│  │ Trader.mq5   │  Executes trades                         │
│  └──────┬───────┘                                           │
│         │ ZMQ PUSH (Port 7779)                              │
│         │ Feedback                                          │
│         └──────────────┐                                    │
│                        │                                    │
│                        └→ Back to Component 2               │
│                           (Feedback Loop)                   │
└─────────────────────────────────────────────────────────────┘
```

### **5.2: Data Flow (Detailed)**

```
1. TICK DATA FLOW:
   MT5 Market
      ↓ (Price updates)
   FeederEA.mq5
      ↓ (MessagePack via ZMQ PUB:7777)
   ingestion.py (Ingestion Worker)
      ↓ (Queue)
   strategy.py (Strategy Engine)
      ↓ (Analysis)
   
2. POLICY FLOW:
   strategy.py
      ↓ (Generate policy via ZMQ PUB:7778)
   ProgramC_Trader.mq5
      ↓ (Execute trades)
   MT5 Market

3. FEEDBACK FLOW:
   MT5 Trade Result
      ↓ (Trade execution)
   ProgramC_Trader.mq5
      ↓ (MessagePack via ZMQ PUSH:7779)
   execution_listener.py
      ↓ (Queue)
   strategy.py (Feedback Processing)
      ↓ (Risk adjustment)
   [Loop back to step 2]
```

### **5.3: Control Flow (Module Level)**

**Python Brain:**
```
main.py
   ├→ Start Ingestion Worker (Thread)
   │     ↓
   │  ingestion.py
   │     ├→ Connect to ZMQ SUB:7777
   │     ├→ Receive ticks
   │     └→ Put to queue
   │
   ├→ Start Strategy Engine (Thread)
   │     ↓
   │  strategy/engine.py
   │     ├→ Get ticks from queue
   │     ├→ Process with CSM (strategy/csm.py)
   │     ├→ Generate policies
   │     ├→ Publish via ZMQ PUB:7778
   │     ├→ Process feedback (strategy/feedback.py)
   │     └→ Update dashboard (strategy/dashboard.py)
   │
   └→ Start Execution Listener (Thread)
         ↓
      execution_listener.py
         ├→ Connect to ZMQ PULL:7779
         ├→ Receive trade results
         └→ Put to feedback queue
```

**MQL5 Trader:**
```
ProgramC_Trader.mq5
   ├→ OnInit()
   │     ├→ Initialize ZMQ SUB:7778 (receive policies)
   │     ├→ Initialize ZMQ PUSH:7779 (send feedback)
   │     ├→ Load Strategy_Grid.mqh
   │     └→ Initialize RiskGuardian.mqh
   │
   ├→ OnTimer()
   │     ├→ Check for new policies (ZMQ)
   │     ├→ Update strategy parameters
   │     └→ Execute pending orders
   │
   └→ OnTradeTransaction()
         ├→ Detect trade completion
         ├→ Pack trade result (MqlMsgPack)
         └→ Send feedback (ZMQ PUSH:7779)
```

---

## 📊 **Part 6: File Size Summary**

### **Before Cleanup:**
```
Total Files: ~120 files
Total Size: ~500 KB
Production Code: ~50 files
Documentation: ~35 files
Test/Trash: ~35 files
```

### **After Cleanup:**
```
Total Files: ~45 files
Total Size: ~350 KB
Production Code: ~40 files
Documentation: ~35 files (organized)
Test/Trash: 0 files
```

**Reduction:**
- 📉 -62% file count (120 → 45)
- 📉 -30% total size (500 KB → 350 KB)
- ✅ 0 duplicates
- ✅ 0 empty files
- ✅ 0 test files in production

---

## 🎯 **Part 7: Benefits of Restructure**

### **Code Quality:**
```
✅ All files < 400 lines (except 1 at 468)
✅ Clear module separation
✅ No duplicates
✅ No dead code
```

### **Maintainability:**
```
✅ Easy to find files
✅ Clear responsibility per file
✅ Easier to test
✅ Easier to extend
```

### **Performance:**
```
✅ Faster compilation (fewer #includes)
✅ Better IDE performance
✅ Faster git operations (smaller repo)
```

### **Professional:**
```
✅ Clean structure
✅ Well-organized docs
✅ Industry best practices
✅ Ready for team collaboration
```

---

## 📋 **Part 8: Implementation Plan**

### **Phase 1: Cleanup (Safe)**
```
1. Create /docs folder structure
2. Move all .md/.txt to /docs
3. Delete test files
4. Delete old versions (_o1)
5. Delete empty files
6. Delete python_fixed/ folder
7. Delete duplicates in root
```

### **Phase 2: Split Large Files (Careful)**
```
1. Split strategy.py into strategy/ folder
2. Split Protocol.mqh into Protocol/ folder
3. Update imports
4. Test compilation
5. Test runtime
```

### **Phase 3: Final Organization**
```
1. Rename folders (remove numbers)
2. Create tools/ folder
3. Update README.md
4. Create .gitignore
5. Final verification
```

---

## ⚠️ **Risks & Mitigations**

### **Risk 1: Breaking Changes**
**Mitigation:** 
- Keep backup of original
- Test after each phase
- Update imports carefully

### **Risk 2: Compilation Errors**
**Mitigation:**
- Test MQL5 files immediately after splitting
- Keep #include paths correct
- Verify all dependencies

### **Risk 3: Lost Files**
**Mitigation:**
- Create MOVE_LOG.txt to track all moves
- Don't delete until verified working
- Keep git history (if using .git)

---

## 🎯 **Recommendation:**

**Proceed with:**
1. ✅ Phase 1 (Cleanup) - Low risk, high value
2. ✅ Phase 2 (Split large files) - Medium risk, high value
3. ⚠️ Phase 3 (Rename folders) - Optional, cosmetic

**Priority:**
1. **HIGH:** Delete test files, duplicates, empty files
2. **HIGH:** Move documentation to /docs
3. **MEDIUM:** Split strategy.py and Protocol.mqh
4. **LOW:** Rename folders (can do later)

---

**Status:** ✅ Ready for Review

**Next Steps:** 
1. Review this proposal
2. Approve changes
3. Create batch file for Phase 1
4. Execute cleanup
5. Verify and commit

---

**Total Document:** ~1000 lines
**Analysis Time:** ~30 minutes
**Implementation Time:** ~2 hours (with testing)
