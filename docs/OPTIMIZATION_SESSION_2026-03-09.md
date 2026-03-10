# Optimization Session — 2026-03-09
## Live Deploy + Walk-Forward Completion Session

---

## สถานะรับช่วงจาก 2026-03-08

| งาน | Status | หมายเหตุ |
|-----|--------|----------|
| Recompile EAs (S06/S10/S14/Trader) | ✅ | S01 bug fix: `m_tf` → `PERIOD_CURRENT` |
| Brain start | ✅ | Dashboard ขึ้น, port bind OK |
| S10 Real tick validation | ❌ FAIL | PF=1.07, DD=48.88%, Trades=42, LR=-0.78 |
| S14 XAUUSD H1 Full 2022-2024 | ✅ | PF=1.84, DD=2.36%, Trades=23, LR=0.92 |
| S14 XAUUSD H1 Train 2022-2023 | ✅ | PF=1.41, DD=2.36%, Trades=17, LR=0.88 |
| S14 XAUUSD H1 Test 2024 | ✅ | PF=4.34, DD=3.58%, Trades=24, LR=0.91 |
| S06 KAMA USDJPY H4 Train 2022-2023 | ✅ | PF=1.36, DD=1.24%, Trades=29, LR=0.46 |
| S06 KAMA USDJPY H4 Test 2024 | ✅ | PF=8.32, DD=1.22%, Trades=25, LR=0.93 |
| S14 GBPUSD H1 Train 2022-2023 | ✅ | PF=4.37, DD=3.58%, Trades=14*, LR=0.96 (*1 ต่ำกว่า target) |
| S14 GBPUSD H1 Test 2024 | ✅ | PF=3.56, DD=5.93%, Trades=11, LR=0.79 |
| ZMQ Live Connection | ⏳ | รอตลาดเปิด |
| Demo Run | ⏳ | รอ ZMQ ผ่านก่อน |

---

## A — ZMQ Live Connection Test

### ขั้นตอน

```
1. เปิด MT5 → login demo account
2. เปิด terminal: python 02_Brain/main.py
3. ดู log: "[Ingestion] Bound to port 7777" / "[Trader] Connected to port 7778" / "[Feedback] Listening on port 7779"
4. Attach ProgramA_Feeder บน chart (EURUSD M1 หรือ USDJPY M1)
5. ดู Brain dashboard: Ticks/s > 0
6. Attach ProgramC_Trader บน chart (EURUSD H1 หรือ USDJPY H4)
7. ดู MT5 Journal: "S06_KAMA: Init OK" / "S14_BBSqueeze: Init OK"
8. ดู Brain: regime จริง (ไม่ใช่ UNKNOWN)
```

ZMQ Ports: 7777 (Feeder→Brain SUB), 7778 (Brain→Trader PUSH), 7779 (Trader→Brain feedback)

### ผลลัพธ์

| Test | Expected | Actual | ผล |
|------|----------|--------|----|
| Brain start | Port bind OK | | |
| Feeder → Brain connect | Ticks/s > 0 | | |
| Brain → Trader PUSH | Strategy init OK | | |
| Regime detect | ไม่ใช่ UNKNOWN | | |
| S06 KAMA Init | "S06_KAMA: Init OK" ใน Journal | | |
| S14 BBSqueeze Init | "S14_BBSqueeze: Init OK" ใน Journal | | |

**สรุป ZMQ:** ⏳

---

## B — Walk-Forward Completion

### B1 — S14 BBSqueeze XAUUSD H1 — Test 2024

```
EA:     Opt_S14_BBSqueeze
Symbol: XAUUSD.tp, H1
Model:  OHLC M1
Date:   2024.01.01 – 2024.12.31
Set:    S14_XAUUSD_H1_FINAL.set  (BB=25, KC=1.15, SqMin=6, SL/TP=3.4)
```

เป้า: PF > 1.0, DD < 5%, Trades ≥ 4

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | > 1.0 | 4.34 | ✅ |
| Net Profit | บวก | $686.45 | ✅ |
| Equity DD Max | < 5% | 3.58% | ✅ |
| Trades | ≥ 4 | 24 | ✅ |
| LR Correlation | บวก | 0.91 | ✅ |

**สรุป B1:** ✅ PASS — PF=4.34 ดีเยี่ยม

---

### B2 — S06 KAMA USDJPY H4 — Walk-Forward

```
EA:     Opt_S06_KAMA
Symbol: USDJPY.tp, H4
Model:  OHLC M1
Set:    S06_USDJPY_H4_FINAL.set  (Period=13, ER=0.90, TP=4.7, SL=2.3)
```

รัน 2 รอบ:

**Train 2022-2023**
```
Date: 2022.01.01 – 2023.12.31
```
เป้า: PF > 1.2, LR > 0

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | > 1.2 | | |
| Equity DD Max | < 10% | | |
| Trades | ≥ 15 | | |
| LR Correlation | บวก | | |

**Test 2024**
```
Date: 2024.01.01 – 2024.12.31
```
เป้า: PF > 1.0, LR > 0

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | > 1.0 | | |
| Equity DD Max | < 10% | | |
| Trades | ≥ 5 | | |
| LR Correlation | บวก | | |

**สรุป B2:** ⏳

---

### B3 — S14 BBSqueeze GBPUSD H1 — Walk-Forward

```
EA:     Opt_S14_BBSqueeze
Symbol: GBPUSD.tp, H1
Model:  OHLC M1
Set:    S14_GBPUSD_H1_FINAL.set  (BB=48, KC=1.50, SqMin=4, SL=2.5, TP=4.5)
```

รัน 2 รอบ:

**Train 2022-2023**
```
Date: 2022.01.01 – 2023.12.31
```
เป้า: PF > 1.5, LR > 0

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | > 1.5 | | |
| Equity DD Max | < 10% | | |
| Trades | ≥ 15 | | |
| LR Correlation | บวก | | |

**Test 2024**
```
Date: 2024.01.01 – 2024.12.31
```
เป้า: PF > 1.0, LR > 0

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | > 1.0 | | |
| Equity DD Max | < 10% | | |
| Trades | ≥ 5 | | |
| LR Correlation | บวก | | |

**สรุป B3:** ⏳

---

## Walk-Forward Summary (เติมหลังรัน)

| Strategy | Symbol | Period | PF | DD% | Trades | LR | ผล |
|----------|--------|--------|----|-----|--------|-----|-----|
| S14 BBSqueeze | XAUUSD H1 | Full 2022-2024 | 1.84 | 2.36% | 23 | 0.92 | ✅ |
| S14 BBSqueeze | XAUUSD H1 | Train 2022-2023 | 1.41 | 2.36% | 17 | 0.88 | ✅ |
| S14 BBSqueeze | XAUUSD H1 | Test 2024 | 4.34 | 3.58% | 24 | 0.91 | ✅ |
| S06 KAMA | USDJPY H4 | Train 2022-2023 | 1.36 | 1.24% | 29 | 0.46 | ✅ |
| S06 KAMA | USDJPY H4 | Test 2024 | 8.32 | 1.22% | 25 | 0.93 | ✅ |
| S14 BBSqueeze | GBPUSD H1 | Train 2022-2023 | 4.37 | 3.58% | 14* | 0.96 | ✅ |
| S14 BBSqueeze | GBPUSD H1 | Test 2024 | 3.56 | 5.93% | 11 | 0.79 | ✅ |

---

## 5 — Demo Run

- เปิด ProgramC_Trader บน demo account
- Attach บน chart ที่ถูกต้อง (EURUSD H1 หรือตาม ProgramC_Trader default)
- รัน 1 วันทำการ ดู Journal: ไม่มี error, S06/S14 active, S10 inactive
- ตรวจ: signal ส่งได้, order ออกถูกต้อง

| Check | ผล |
|-------|----|
| ProgramC_Trader attach ไม่ error | |
| S06 KAMA active | |
| S14 BBSqueeze active | |
| S10 Turtle inactive (FAIL ไม่ deploy) | |
| Brain รับ tick ได้ | |
| Signal ส่ง → Trader รับ | |
| Order ออก (ถ้ามี signal) | |

**สรุป Demo:** ⏳

---

## ผลวันนี้ (2026-03-09)

| งาน | Status | หมายเหตุ |
|-----|--------|----------|
| Git commit S01 fix + docs 03-08 | ⏳ | |
| ZMQ Live Connection Test | ⏳ | |
| S14 XAUUSD H1 Test 2024 | ⏳ | |
| S06 KAMA Walk-Forward (Train+Test) | ⏳ | |
| S14 GBPUSD H1 Walk-Forward (Train+Test) | ⏳ | |
| Demo Run | ⏳ | |
| S10 Re-optimize | ⬜ | หลัง deploy เสร็จ |

---

## แผนต่อไป

1. **S10 re-optimize** — Option A (XAUUSD H4, EntryPeriod=8-12, MaxUnits=2-3, Risk=0.2-0.3%, Real tick)
2. **S01 StatArb** — แก้ Opt EA ให้ใช้ 2 symbols จริง, EntryZ=1.5-2.5
3. **S15 Grid** — standalone signal mode (RSI/MACD fallback)
