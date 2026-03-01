# ✅ FlashEASuite V2 — Production Ready Checklist (P9-5)

**Version:** 1.0  
**Date:** 2026-02-26  
**Author:** Dr. Suksaeng Kukanok  
**Save:** `FlashEASuite_V2/docs/PRODUCTION_READY_CHECKLIST.md`

> ⚠️ **ต้อง PASS ทุกข้อก่อน go-live**  
> รัน `python tools/validate_live_readiness.py` เพื่อ automate ข้อที่ทำได้

---

## 📋 Checklist

### 1. Python Brain

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 1.1 | □ Python Brain รันไม่มี error | | `start_flashea.bat` → ดู console ไม่มี traceback |
| 1.2 | □ Ingestion Worker started | | console แสดง "✅ Ingestion Worker started" |
| 1.3 | □ Strategy Engine started | | console แสดง "✅ Strategy Engine started" |
| 1.4 | □ Execution Listener started | | console แสดง "✅ Execution Listener started" |
| 1.5 | □ Memory < 300 MB หลังรัน 10 นาที | | Task Manager → Python process |
| 1.6 | □ CPU < 15% steady-state | | Task Manager → Python process |

### 2. FeederEA (Program A)

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 2.1 | □ FeederEA ส่ง tick data | | MT5 → Experts tab: "Broadcasting on 4 symbols" |
| 2.2 | □ ZMQ PUB bound port 7777 | | Experts tab: "ZMQ PUB bound to tcp://*:7777" |
| 2.3 | □ Brain รับ ticks สำเร็จ | | Brain console: tick count เพิ่มขึ้นเรื่อยๆ |
| 2.4 | □ Symbol mapping ถูกต้อง | | Dashboard: XAUUSD.tp → XAUUSD ฯลฯ |

### 3. ProgramC_Trader (Program C)

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 3.1 | □ ProgramC_Trader รับ config | | Experts tab: "ZMQ Hub created" |
| 3.2 | □ SUB connected port 7778 | | Experts tab: "Subscribed to tcp://127.0.0.1:7778" |
| 3.3 | □ Strategy registered | | Experts tab: "Grid Strategy added", "Spike Hunter added" |
| 3.4 | □ SYMBOL_SUFFIX ตั้งถูก | | Input: ตรงกับ broker suffix (เช่น ".tp") |
| 3.5 | □ Allow DLL imports ✓ | | EA properties → Common tab |
| 3.6 | □ Allow algo trading ✓ | | EA properties → Common tab + AutoTrading button |

### 4. Trade Execution

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 4.1 | □ Trade execute ได้ | | ทดสอบ manual trade ผ่าน MT5 |
| 4.2 | □ Lot size ถูกต้อง | | ดู open position → Volume = ค่าที่ตั้งไว้ |
| 4.3 | □ SL/TP ตั้งถูก | | Hidden TP/SL ทำงาน: ดูจาก EA log |
| 4.4 | □ Account margin เพียงพอ | | MT5 → Trade tab: Free Margin > 50% |

### 5. TRADE_REPORT Feedback Loop

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 5.1 | □ TRADE_REPORT กลับมา Python | | Brain console: "Trade result received" |
| 5.2 | □ Feedback processed | | Brain console: "Feedback processed for S07" ฯลฯ |
| 5.3 | □ Performance tracker อัปเดต | | ดู `02_Brain/data/metrics/performance_metrics.json` |
| 5.4 | □ Port 7779 PUSH/PULL ทำงาน | | `validate_live_readiness.py --zmq` |

### 6. InfluxDB

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 6.1 | □ InfluxDB บันทึกข้อมูล | | `validate_live_readiness.py --influx` |
| 6.2 | □ Port 8086 เปิดอยู่ | | `http://localhost:8086` ใน browser |
| 6.3 | □ Tick data ถูกเขียน | | InfluxDB UI → Data Explorer → flashea_ticks bucket |
| 6.4 | □ Retention policy ถูก | | 7d raw ticks, 180d OHLC |

### 7. Explainable AI & Logging

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 7.1 | □ decision_logger.py บันทึก decisions | | ดู `02_Brain/explainable/` → ไฟล์ใหม่ถูกสร้าง |
| 7.2 | □ Brain log ไม่มี unhandled exceptions | | ดู `02_Brain/logs/flashea_brain.log` |
| 7.3 | □ Trade journal JSON created | | ดู `02_Brain/logs/trades_YYYYMMDD.json` |

### 8. Monitoring & Health

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 8.1 | □ health_monitor.py ทำงาน | | `python tools/health_monitor.py --once` |
| 8.2 | □ Dashboard แสดงข้อมูลถูก | | `python 02_Brain/dashboard.py` หรือ Brain auto-display |
| 8.3 | □ start_flashea.bat status OK | | `start_flashea.bat status` → all GREEN |
| 8.4 | □ start_flashea.bat doctor PASS | | `start_flashea.bat doctor` → ไม่มี FAIL |

### 9. Strategy Parameters

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 9.1 | □ S07 baseline params โหลดแล้ว | | `strategy_parameters.json` มี S07 entries |
| 9.2 | □ MM01 default params ถูก | | `mm_parameters.json` → MM01_FIXED_LOT |
| 9.3 | □ Standalone config พร้อม | | Trader EA รัน standalone mode ได้ ถ้า Brain ปิด |
| 9.4 | □ ConfigReceiver fallback ทำงาน | | ปิด Brain → Trader switch เป็น standalone mode |

### 10. Emergency & Safety

| # | รายการ | สถานะ | วิธีตรวจ |
|---|--------|--------|----------|
| 10.1 | □ Emergency stop ทำงาน | | MT5 → AutoTrading OFF → EA หยุดเทรด |
| 10.2 | □ DailyLossLimit ตั้งค่าแล้ว | | RiskGuardian.mqh → DD_DAILY_LIMIT_PCT |
| 10.3 | □ Max drawdown < 20% configured | | config.py → MAX_DRAWDOWN_PCT |
| 10.4 | □ Force kill tested | | `taskkill /im python.exe /f` → Brain หยุด |
| 10.5 | □ Recovery restart tested | | หลัง force kill → `start_flashea.bat` → กลับมาปกติ |

---

## 🔧 วิธี Run Validation อัตโนมัติ

### Full Validation (แนะนำก่อน go-live)

```cmd
cd FlashEASuite_V2
python tools\validate_live_readiness.py
```

**ผลที่คาดหวัง:**
```
═══════════════════════════════════════════════════════════
  📊 VALIDATION SUMMARY
═══════════════════════════════════════════════════════════

  ✅ PASS  Imports
  ✅ PASS  Deps
  ✅ PASS  Files
  ✅ PASS  Ports
  ✅ PASS  ZMQ
  ✅ PASS  Config
  ✅ PASS  Receive
  ✅ PASS  InfluxDB

  Total: 25+ passed, 0 failed, 0 warnings

  🚀 SYSTEM READY FOR LIVE TRADING!
```

### Quick Check (ตรวจเฉพาะ import + files)

```cmd
python tools\validate_live_readiness.py --quick
```

### ZMQ Only (ตรวจ connection + config push)

```cmd
python tools\validate_live_readiness.py --zmq
```

### InfluxDB Only

```cmd
python tools\validate_live_readiness.py --influx
```

---

## 📖 ตีความผลลัพธ์

### ✅ PASS = พร้อมใช้
ระบบส่วนนั้นทำงานปกติ

### ❌ FAIL = ต้องแก้ก่อน live
ทุก FAIL มีคำแนะนำวิธีแก้ต่อท้าย — ดู output

### ⚠️ WARN = optional แต่แนะนำ
เช่น InfluxDB ไม่เปิด (ระบบทำงานได้โดยไม่มี) หรือ rich library ไม่ได้ติดตั้ง

### แก้ไข FAIL ที่พบบ่อย

| Error | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| Port 7777 IN USE | Brain เดิมยังรันอยู่ | `start_flashea.bat stop` |
| Port 7778 IN USE | Brain เดิมยังรันอยู่ | `taskkill /im python.exe /f` |
| pyzmq not installed | ไม่ได้ลง dependencies | `pip install pyzmq msgpack` |
| ConfigBuilder import error | path ผิด | `cd FlashEASuite_V2` ก่อน run |
| InfluxDB not reachable | InfluxDB ปิดอยู่ | เปิด influxd.exe หรือ docker |
| File not found | ไม่ได้ copy ไฟล์ | ตรวจ tree ว่า structure ครบ |

---

## ⏱ ตารางตรวจสอบก่อน Go-Live

| เวลา | ทำอะไร | เครื่องมือ |
|------|--------|-----------|
| T-30 min | Run full validation | `validate_live_readiness.py` |
| T-20 min | Start Brain | `start_flashea.bat` |
| T-15 min | Attach FeederEA | MT5 Navigator → drag EA |
| T-10 min | Attach Trader | MT5 Navigator → drag EA |
| T-5 min  | Verify data flow | Brain console + Dashboard |
| T-2 min  | Check status | `start_flashea.bat status` |
| T-1 min  | Start health monitor | `python tools\health_monitor.py` |
| T-0      | **Go Live** 🚀 | Enable AutoTrading |

---

## ⚠️ Known Issues (ควรรู้ก่อน live)

1. **S16_Spike memory leak** — ✅ **แก้แล้ว** ใน P9-4b (Strategy_Spike.mqh v2.02, S16_Spike.mqh v6.05)
2. **Feature engineering latency** — compute() 100-340ms ต่อ inference; ยังไม่ได้ optimize เป็น incremental
3. **InfluxDB optional** — ระบบทำงานได้โดยไม่มี InfluxDB แต่จะไม่มี historical data
4. **Standalone fallback** — ถ้า Brain ปิด → Trader ใช้ StandaloneSelector → HMA+LinReg แทน Kalman

---

*Production Ready Checklist V1.0 — P9-5 FINAL*
