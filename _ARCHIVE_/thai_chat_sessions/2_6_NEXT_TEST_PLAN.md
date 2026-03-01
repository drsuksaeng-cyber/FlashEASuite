# 🧪 Next Testing Phase Plan

**Phase:** Stress Testing & Extended Validation  
**Estimated Duration:** 30-60 minutes  
**Goal:** Verify system stability over extended period

---

## 🎯 **Test Objectives**

### **Primary Objectives:**
1. ✅ Validate system stability over 30+ minutes
2. ✅ Confirm zero packet loss at scale
3. ✅ Verify memory management (no leaks)
4. ✅ Monitor performance consistency
5. ✅ Test edge cases and error handling

### **Success Criteria:**
```
✅ Zero crashes (Python or MT5)
✅ Zero memory leaks (<500MB Python, <100MB MT5)
✅ Consistent latency (<10ms Python processing)
✅ 100% policy reception rate
✅ 100% symbol matching rate
✅ 100% data validation pass rate
```

---

## 📋 **Test Plan**

### **Test 1: Extended Integration Test (30 minutes)**

**Duration:** 30 minutes  
**Configuration:**
```
Chart: XAUUSD.tp M1
Test EA: IntegrationTest_Trader.mq5
Test Duration: 1800 seconds (30 min)
Timer: 100ms
```

**Steps:**
```
1. Start Python Brain
   cd D:\MQL5\FlashEASuite_V2\02_Brain
   python main.py

2. Verify startup
   ✓ All 4 workers running
   ✓ ZMQ ports bound (7777, 7778, 7779)
   ✓ No errors in console

3. Attach IntegrationTest_Trader to XAUUSD.tp
   - Set TEST_DURATION_SEC = 1800
   - Verify initialization
   - Check Test #1 and #2 PASSED

4. Monitor for 30 minutes
   - Watch Python console
   - Watch MT5 Expert tab
   - Check for errors

5. Let test complete naturally
   - EA will auto-stop at 1800 seconds
   - Check final statistics

6. Analyze results
   - Check log file in MQL5/Files/
   - Verify 100% pass rate
```

**Expected Results:**
```
Policies Expected: ~360 (1 per 5 seconds)
Tests Expected: ~362 (2 initial + 360 policies)
Pass Rate: 100%
Failures: 0
```

**Monitoring Checklist:**
- [ ] Python CPU usage stable (<10%)
- [ ] Python memory stable (<200MB)
- [ ] MT5 CPU usage stable (<1%)
- [ ] No error messages
- [ ] Tick rate consistent (~400-500/min)
- [ ] Policy rate consistent (~12/min)

---

### **Test 2: Performance Metrics Collection**

**Duration:** During Test 1  
**Tools:** Windows Task Manager + Custom logging

**Metrics to Collect:**

**Python Brain:**
```
Every 5 minutes:
- CPU Usage: ____%
- Memory Usage: ____MB
- Ticks/minute: ____
- Policies/minute: ____
- Worker status: All running Y/N
```

**MT5 Terminal:**
```
Every 5 minutes:
- CPU Usage: ____%
- Memory Usage: ____MB
- Policies received: ____
- Test pass rate: ____%
```

**ZMQ Network:**
```
Check:
- Packet loss: Should be 0%
- Average latency: Should be <2ms
- Max latency: Should be <10ms
```

---

### **Test 3: Error Handling**

**Duration:** 5 minutes  
**Purpose:** Test system recovery from errors

**Scenarios to Test:**

**Scenario 1: Network Interruption**
```
1. System running normally
2. Stop Python Brain (Ctrl+C)
3. Observe MT5 behavior:
   ✓ Should continue running
   ✓ Should log "no policy received"
   ✓ Should not crash
4. Restart Python Brain
5. Verify reconnection:
   ✓ Policies resume
   ✓ No data corruption
```

**Scenario 2: Invalid Data**
```
(Already tested - policy validation working)
Skip for now, test later with malformed data
```

**Scenario 3: Market Close**
```
1. Run test during market close
2. Verify:
   ✓ FeederEA continues (no ticks sent)
   ✓ Python Brain continues (no ticks processed)
   ✓ MT5 Trader continues (no policies received)
   ✓ No errors logged
   ✓ System resumes when market opens
```

---

## 📊 **Data Collection Template**

### **30-Minute Test Log:**

```
Test Start Time: __________
Test End Time: __________

=== 5-Minute Intervals ===

Interval 1 (0-5 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

Interval 2 (5-10 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

Interval 3 (10-15 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

Interval 4 (15-20 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

Interval 5 (20-25 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

Interval 6 (25-30 min):
  Python: CPU ___%, Mem ___MB, Ticks ____, Policies ____
  MT5: CPU ___%, Mem ___MB, Tests Passed ____/____
  Status: ____________

=== Final Summary ===
Total Ticks: ________
Total Policies: ________
Total Tests: ________
Pass Rate: ________%
Errors: ________
```

---

## 🚨 **Abort Conditions**

**Stop test immediately if:**
- [ ] Python crashes
- [ ] MT5 crashes
- [ ] Memory usage >1GB (Python) or >500MB (MT5)
- [ ] CPU usage >50% sustained
- [ ] Test failure rate >1%
- [ ] System becomes unresponsive

**Recovery Actions:**
1. Stop all processes
2. Save logs
3. Analyze error
4. Fix and retry

---

## ✅ **Post-Test Actions**

### **After 30-Minute Test:**

1. **Collect Logs:**
   ```
   - integration_test_YYYYMMDD_HHMM.log
   - Python console output (screenshot)
   - MT5 Expert log (screenshot)
   ```

2. **Analyze Results:**
   ```
   - Calculate total tests run
   - Calculate pass rate
   - Check for any patterns in timing
   - Verify no degradation over time
   ```

3. **Document Findings:**
   ```
   - Create STRESS_TEST_RESULTS.md
   - Include all metrics
   - Note any anomalies
   - Update system status
   ```

4. **Update Documentation:**
   ```
   - Update SYSTEM_OVERVIEW.md
   - Add to LOGBOOK.md
   - Update test statistics
   ```

---

## 🎯 **Next Phase After Stress Test**

### **If Stress Test Passes:**
```
✅ Proceed to ProgramC_Trader integration
   - Test real order execution
   - Verify trade result feedback
   - Validate risk management
```

### **If Stress Test Fails:**
```
❌ Debug and fix issues
   - Analyze failure logs
   - Identify root cause
   - Implement fix
   - Re-run test
```

---

## 📁 **Required Files**

**Already Prepared:**
- [x] IntegrationTest_Trader.mq5 (fixed version)
- [x] engine.py (fixed version)
- [x] policy.py (fixed version)
- [x] ingestion.py (verified)

**To Prepare:**
- [ ] Data collection spreadsheet
- [ ] Screen recording setup (optional)
- [ ] System monitoring dashboard

---

## 🔧 **Pre-Test Checklist**

Before starting 30-minute test:

**System:**
- [ ] Windows Task Manager open
- [ ] No other heavy processes running
- [ ] Sufficient disk space (>5GB free)
- [ ] Network stable

**Software:**
- [ ] Python Brain code updated
- [ ] MT5 EA compiled
- [ ] All previous tests closed
- [ ] Fresh MT5 terminal

**Configuration:**
- [ ] TEST_DURATION_SEC = 1800
- [ ] Timer = 100ms
- [ ] Correct symbol (XAUUSD.tp)
- [ ] Correct timeframe (M1)

**Documentation:**
- [ ] Notepad ready for observations
- [ ] Screenshot tool ready
- [ ] Log collection plan ready

---

## 🎬 **Ready to Start?**

**Checklist before execution:**
```
✅ All fixes deployed
✅ Previous test passed (100%)
✅ System stable
✅ Documentation ready
✅ Monitoring tools ready
```

**Start command:**
```bash
# Terminal 1: Start Python Brain
cd D:\MQL5\FlashEASuite_V2\02_Brain
python main.py

# MT5: Attach IntegrationTest_Trader
# Chart: XAUUSD.tp M1
# Duration: 1800 seconds
```

**Start time:** __________  
**Expected end:** __________ (30 min later)

---

**Good luck! 🚀**
