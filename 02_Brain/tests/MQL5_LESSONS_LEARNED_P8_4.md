# MQL5 + Python Lessons Learned — P8-4 (Production Readiness Review)
# FlashEASuite V2 — ห้ามทำผิดซ้ำ!
# วันที่เรียนรู้: 2026-02-25
# ผล: MQL5 63/63 ✅ | Python 43/43 ✅ (100%)

---

## ❌ MISTAKE 1: Include path ผิด — ไม่ดู tree

### สาเหตุ
เขียน include โดยเดาว่าไฟล์อยู่ที่ `Include/` โดยตรง ไม่ดู tree ก่อน

### Error ที่เกิด
```
file 'Include/StandaloneConfig.mqh' not found
file 'Include/StandaloneSelector.mqh' not found
```

### โค้ดที่ผิด
```mql5
#include "../Include/StandaloneConfig.mqh"      // ❌
#include "../Include/StandaloneSelector.mqh"    // ❌
```

### โค้ดที่ถูก (ดูจาก tree line 453-456)
```mql5
#include "../Include/Standalone/StandaloneConfig.mqh"   // ✅
#include "../Include/Standalone/StandaloneSelector.mqh" // ✅
#include "../Include/Standalone/SimpleRegime.mqh"        // ✅
```

### กฎ
**ก่อนเขียน include ทุกครั้ง ต้อง grep tree ก่อนเสมอ — ห้ามเดา path**

---

## ❌ MISTAKE 2: เรียก CStrategyManager_V6.Init() ซึ่งไม่มี

### สาเหตุ
เดาว่ามี `Init()` แบบทั่วไป แต่จริงๆ ชื่อต่างออกไป

### Error ที่เกิด
```
undeclared identifier 'Init'
'STRESS_SYMBOL' - some operator expected
```

### โค้ดที่ผิด
```mql5
CStrategyManager_V6 sm;
sm.Init(STRESS_SYMBOL);   // ❌ ไม่มี method นี้
```

### โค้ดที่ถูก
```mql5
CStrategyManager_V6 sm;
sm.RegisterAllStrategies(STRESS_SYMBOL, PERIOD_M15);  // ✅
```

### กฎ
**CStrategyManager_V6 ไม่มี Init() — ต้องเรียก RegisterAllStrategies(symbol, tf)**

---

## ❌ MISTAKE 3: GetStrategyStatus() ส่ง array param ไม่ได้

### สาเหตุ
คิดว่า `GetStrategyStatus()` รับ array และ return count เหมือน FillStatusArray

### Error ที่เกิด
```
wrong parameters count, 1 passed, but 0 requires
void CStrategyManager_V6::GetStrategyStatus()
```

### โค้ดที่ผิด
```mql5
int count = sm.GetStrategyStatus(status);  // ❌
```

### โค้ดที่ถูก
```mql5
// GetStrategyStatus() = Print เท่านั้น ไม่รับ/return ค่า
sm.GetStrategyStatus();   // ✅ แค่ Print

// ถ้าต้องการ array + count ใช้
int count = 0;
sm.FillStatusArray(status, count);   // ✅
```

### กฎ
```
CStrategyManager_V6 status API:
  GetStrategyStatus()              → Print table เฉยๆ (void, 0 params)
  FillStatusArray(out[], count)    → export ไปยัง array (สำหรับ automated test)
```

---

## ❌ MISTAKE 4: IStrategy::Analyze() ไม่ส่ง MqlTick

### สาเหตุ
เรียก `s.Analyze()` โดยไม่ส่ง tick — มี overload แบบนี้ใน C++ แต่ไม่มีใน MQL5 IStrategy

### Error ที่เกิด
```
wrong parameters count, 0 passed, but 1 requires
void IStrategy::Analyze(const MqlTick&)
```

### โค้ดที่ผิด
```mql5
s.Analyze();   // ❌
```

### โค้ดที่ถูก
```mql5
MqlTick dummy_tick = {};
s.Analyze(dummy_tick);   // ✅ ต้องส่ง MqlTick& เสมอ
```

### กฎ
**IStrategy::Analyze() ต้องส่ง `const MqlTick&` เสมอ — ไม่มี no-param overload**

---

## ❌ MISTAKE 5: ProcessTick() และ GetActiveStrategyCount() ไม่มีอยู่จริง

### Error ที่เกิด
```
undeclared identifier 'ProcessTick'
undeclared identifier 'GetActiveStrategyCount'
```

### โค้ดที่ผิด
```mql5
sm.ProcessTick();                    // ❌
int n = sm.GetActiveStrategyCount(); // ❌
```

### โค้ดที่ถูก
```mql5
MqlTick tick = {};
sm.OnTick(tick);                     // ✅ method จริงคือ OnTick
int n = sm.GetEnabledCount_V6();     // ✅ method จริงคือ GetEnabledCount_V6()
```

### CStrategyManager_V6 API ที่ถูกต้องทั้งหมด
```mql5
sm.RegisterAllStrategies(symbol, tf)   // ✅ ไม่ใช่ Init()
sm.GetStrategyStatus()                 // ✅ void — Print เท่านั้น
sm.FillStatusArray(out[], count)       // ✅ export array
sm.OnTick(tick)                        // ✅ ไม่ใช่ ProcessTick()
sm.GetEnabledCount_V6()                // ✅ ไม่ใช่ GetActiveStrategyCount()
sm.SetServerConnected(bool)            // ✅
sm.IsServerConnected()                 // ✅
sm.EnableAllStandalone()               // ✅
sm.GetStrategyByID(ENUM_STRATEGY_ID)   // ✅
sm.GetEnabledCount_V6()                // ✅
```

---

## ❌ MISTAKE 6: S09_SESSION_BO ชื่อ enum ผิด

### Error ที่เกิด
```
undeclared identifier 'S09_SESSION_BO'
```

### โค้ดที่ผิด
```mql5
S09_SESSION_BO   // ❌
```

### โค้ดที่ถูก
```mql5
S09_SESSION_BREAKOUT   // ✅ (จาก StrategyConstants.mqh line 38)
```

---

## ❌ MISTAKE 7: EMA recovery test logic ผิดหลักการ

### สาเหตุ
EMA converges TOWARD target — ถ้า target < current weight จะลงต่อ ไม่ recovery

### ตัวอย่าง (alpha=0.1)
```
weight=0.955, acc=0.90 → EMA = 0.1×0.90 + 0.9×0.955 = 0.9495  ← ลงต่อ!
weight=0.955, acc=0.99 → EMA = 0.1×0.99 + 0.9×0.955 = 0.9585  ← ขึ้น ✅
```

### Test ที่ถูก: ต้อง DROP ก่อน แล้วค่อย RECOVER ด้วย acc > current
```python
# Drop phase
wt_low = 1.0
for _ in range(10):
    wt_low = 0.1*0.55 + 0.9*wt_low   # → 0.707

# Recovery phase (acc > wt_low เพื่อให้ขึ้น)
wt_rec = wt_low
for _ in range(10):
    wt_rec = 0.1*0.95 + 0.9*wt_rec   # → 0.865

assert wt_rec > wt_low  # ✅
```

### กฎ
**EMA recovery: recovery target ต้องสูงกว่า current weight — 1 step เดียวไม่พอ ต้อง loop**

---

## ❌ MISTAKE 8: เปิด JSON บน Windows ไม่ระบุ encoding

### Error ที่เกิด
```python
UnicodeDecodeError: 'charmap' codec can't decode byte 0x9b
```

### โค้ดที่ผิด
```python
with open(path) as f:        # ❌ Windows default = cp1252
    data = json.load(f)
```

### โค้ดที่ถูก
```python
with open(path, encoding="utf-8") as f:   # ✅ ระบุ encoding เสมอ
    data = json.load(f)
```

### กฎ
**บน Windows ทุก file open ที่เป็น text/JSON ต้องระบุ `encoding="utf-8"` เสมอ**

---

## ❌ MISTAKE 9: PerformanceTracker.record_prediction() param ชื่อผิด

### Error ที่เกิด
```python
TypeError: record_prediction() got an unexpected keyword argument 'strategy_id'
```

### โค้ดที่ผิด
```python
tracker.record_prediction(
    strategy_id=1,        # ❌ ไม่มี param นี้
    was_correct=True,     # ❌ ไม่มี param นี้
)
```

### โค้ดที่ถูก (จาก performance_tracker.py line 204)
```python
tracker.record_prediction(
    strategy=1,           # ✅ ชื่อจริง
    symbol="XAUUSD",
    prediction=1,         # 1=BUY, -1=SELL, 0=SKIP
    actual_outcome=1.0,   # บวก=กำไร, ลบ=ขาดทุน (was_correct คำนวณ internally)
    rr_achieved=0.0,      # optional
)

tracker.get_accuracy(strategy=1, symbol="XAUUSD")   # ✅ ไม่ใช่ strategy_id=
```

### API ครบของ PerformanceTracker
```python
# record
tracker.record_prediction(strategy, symbol, prediction, actual_outcome, rr_achieved=0.0)

# query
tracker.get_accuracy(strategy, symbol, lookback_days=30)  → float 0.0-1.0
tracker.get_ema_weight(strategy, symbol)                  → float
tracker.get_win_rate(strategy, symbol)                    → float

# persistence
tracker.save_metrics()   → bool
tracker.load_metrics()   → bool
```

---

## 📊 สถิติ P8-4

| | จำนวน |
|---|---|
| MQL5 compile errors ที่แก้ | 15 errors (3 sessions) |
| Python runtime errors ที่แก้ | 3 errors (2 sessions) |
| MQL5 PASS | 63/63 (100%) |
| Python PASS | 43/43 (100%) |

---

## ⚠️ WARN ที่ยังค้างอยู่ (ต้องแก้ใน P9)

```
1. S16_Spike memory leak: +11,520 bytes (6 objects ไม่ถูก delete ใน Deinit)
   → FIX BEFORE BACKTESTING หรือ optimization จะ crash

2. DLLWrapper.mqh: ไม่มีใน 03_Trader/ tree
   → สร้างหรือ deploy ก่อน live

3. decision_logger.py: ยังไม่มี
   → สร้างใน P9 (Logging Destination 2)

4. retrain_feedback.py: ยังไม่มี
   → สร้างใน P9 (Logging Destination 4)
```

---

## 📁 ไฟล์ที่เกี่ยวข้อง

```
03_Trader/Tester/Test_P8_4_Readiness.mq5     ← PASSED 63/63
02_Brain/tests/test_p8_4_readiness.py         ← PASSED 43/43
```

---

## ➡️ Next: P9-1 — Final Review + Production Deployment

```
Priority:
1. FIX S16_Spike memory leak (critical — blocks backtesting)
2. Create decision_logger.py + retrain_feedback.py
3. Deploy DLLWrapper.mqh
4. Code cleanup + final documentation
5. Deployment checklist + monitoring setup
6. First-day operation plan
```
