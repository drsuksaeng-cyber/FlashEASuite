# Optimization Session — 2026-03-08
## Deploy Session — S06/S14 Deploy + S10 Re-Opt Plan

---

## สถานะรับช่วงจาก 2026-03-07

| Strategy | Symbol | TF | Validation | หมายเหตุ |
|----------|--------|----|------------|----------|
| S06 KAMA | USDJPY | H4 | ✅ ผ่าน PF=1.99 DD=1.94% | OHLC M1 conservative pass |
| S14 BBSqueeze | XAUUSD | H1 | ✅ ผ่าน PF=1.84 DD=2.36% | 98% match |
| S14 BBSqueeze | GBPUSD | H1 | ✅ ผ่าน PF=2.76 DD=3.99% | 100% match |
| S10 Turtle | XAUUSD | H4 | ❌ **FAIL** Real tick | ดูรายละเอียดด้านล่าง |

---

## S10 Turtle — Real Tick Validation Result (2026-03-08)

รัน: `Opt_S10_Turtle`, XAUUSD.tp H4, Real tick, 2022-2024, `S10_XAUUSD_H4_FINAL.set`

| Metric | Target | Actual | ผล |
|--------|--------|--------|----|
| Profit Factor | ≥ 1.384 | 1.07 | ❌ |
| Net Profit | บวก | $130.85 | ⚠️ แทบเป็นศูนย์ |
| Equity DD Max | ≤ 30% | 48.88% | ❌ |
| Trades | ≥ 80 | 42 | ❌ |
| LR Correlation | บวก | -0.78 | ❌ equity ลงตลอด |

**สรุป: ❌ FAIL — params นี้ใช้ live ไม่ได้ ต้อง re-optimize**

### วิเคราะห์ root cause

| ปัญหา | สาเหตุ | แนวทางแก้ |
|-------|--------|-----------|
| Trades น้อย (42 vs 84) | EntryPeriod=15 สูงเกิน → breakout signal น้อย | ลด EntryPeriod → ลอง 8-12 |
| DD สูง (48.88%) | MaxUnits=4 + Risk=0.5% = เสี่ยงสูงเกิน | ลด MaxUnits=2-3, RiskPct=0.2-0.3% |
| LR=-0.78 | params ไม่ fit XAUUSD H4 ช่วงนี้ | ลอง symbol อื่น หรือ params ใหม่ |
| Brain opt ≠ Real tick | Brain ใช้ OHLC M1 ซึ่งผิดมากสำหรับ breakout | Re-optimize ด้วย Real tick ตั้งแต่ต้น |

### Re-Optimization Plan (ทำหลัง deploy S06/S14 เสร็จ)

**Option A — XAUUSD H4 ใหม่ (optimize ด้วย Real tick)**
```
Symbol: XAUUSD.tp, H4
Model: Real tick (บังคับ — OHLC M1 ใช้ไม่ได้กับ S10)
Date: 2022.01.01 – 2024.12.31
Optimize params:
  Turtle_EntryPeriod: 8–14 (step 1)
  Turtle_MaxUnits: 2–3 (step 1)
  Turtle_RiskPct: 0.2–0.4% (step 0.1)
  Turtle_BreakoutBuf: 0.05–0.20 (step 0.05)
เป้า: PF >= 1.3, DD <= 25%, Trades >= 60
```

**Option B — USDJPY H4 (symbol ใหม่)**
```
Symbol: USDJPY.tp, H4
Model: Real tick
เหตุผล: Turtle เหมาะกับ trending currency มากกว่า commodity
params: ลองเหมือน Option A
```

**สำคัญ:** ต้อง validate ด้วย Real tick เสมอ — OHLC M1 ให้ผลผิดมากสำหรับ breakout strategy

---

## ลำดับที่ 1 — Deploy S06 + S14

### EA ที่ต้อง recompile (MetaEditor → F7)

| EA | เหตุผล | Status |
|----|--------|--------|
| `ProgramC_Trader.mq5` | include S06/S10/S14 .mqh ทั้งหมด | ✅ |
| `Tester/Opt_S06_KAMA.mq5` | include S06_KAMA.mqh | ✅ |
| `Tester/Opt_S10_Turtle.mq5` | include S10_Turtle.mqh | ✅ |
| `Tester/Opt_S14_BBSqueeze.mq5` | include S14_BBSqueeze.mqh | ✅ |

### Bug fix ระหว่าง recompile (2026-03-08)

- `S01_StatArb.mqh` line 71: `m_tf` undeclared → แก้เป็น `PERIOD_CURRENT`
  (m_tf ไม่ได้ถูก declare ใน class — S01 แค่ต้องการราคาล่าสุด PERIOD_CURRENT เพียงพอ)

---

## ลำดับที่ 2 — ZMQ Connection Test

> ⏳ **รอวันทำการ (2026-03-09)** — วันนี้วันหยุด ตลาดปิด ไม่มี tick data
> Brain start ✅ ได้แล้ว แต่ Feeder ยังไม่ได้ต่อ (ต้องตลาดเปิด)

```bash
# เปิด Brain
/c/Users/drsuk/miniconda3/envs/deepquant_env/python.exe 02_Brain/main.py
```

ดู log ที่ต้องเห็น:
- `[Ingestion] Bound to port 7777`
- `[Trader] Connected to port 7778`
- `[Feedback] Listening on port 7779`

| Test | Status |
|------|--------|
| Brain start ไม่ error | ✅ (dashboard ขึ้น, port bind OK) |
| MT5 Feeder connect → Brain | ⏳ รอพรุ่งนี้ |
| Brain → Trader PUSH connect | ⏳ รอพรุ่งนี้ |
| Strategy analyze ได้ | ⏳ รอพรุ่งนี้ |

---

## ลำดับที่ 3 — Demo Run

- เปิด MT5 บน demo account
- Attach `ProgramC_Trader` บน chart
- ดู Journal ว่า strategies init ได้: S06/S14 active, S10 inactive
- รัน 1 วันทำการก่อน live

---

## ลำดับที่ 4 — Git Commit

```bash
git add docs/OPTIMIZATION_SESSION_2026-03-08.md
git commit -m "docs(session): S10 real tick FAIL + re-opt plan + deploy S06/S14"
```

---

## ผลวันนี้ (2026-03-08)

| งาน | Status | หมายเหตุ |
|-----|--------|----------|
| S10 Real tick validation | ❌ FAIL | PF=1.07, DD=48.88%, Trades=42, LR=-0.78 |
| Recompile EAs (S06/S10/S14/Trader) | ✅ | S01 bug fix: m_tf → PERIOD_CURRENT |
| Brain start | ✅ | Dashboard ขึ้น port bind OK |
| ZMQ Feeder+Trader connect | ⏳ รอพรุ่งนี้ | วันหยุด ไม่มี tick |
| S14 XAUUSD H1 Full period confirm | ✅ | PF=1.84, DD=2.36%, Trades=23, LR=0.92 |
| S14 XAUUSD H1 Train (2022-2023) | ✅ | PF=1.41, DD=2.36%, Trades=17, LR=0.88 |
| S14 XAUUSD H1 Test (2024) | ⏳ | date issue — ยังไม่ได้ผลที่ถูกต้อง |
| S06 KAMA USDJPY H4 (full/WF) | ⏳ | รัน PF=1.30 LR=0.86 — ไม่แน่ใจ period ใด |
| S14 GBPUSD H1 Walk-forward | ⬜ | ยังไม่ได้เริ่ม |
| Demo run | ⏳ รอพรุ่งนี้ | ต้องตลาดเปิด |
| Git commit | ⬜ | |

---

## Walk-Forward Results (บางส่วน)

### S14 BBSqueeze — XAUUSD H1

| Period | Bars | PF | DD% | Trades | LR | ผล |
|--------|------|-----|-----|--------|-----|-----|
| Full 2022-2024 | 18,662 | 1.84 | 2.36% | 23 | 0.92 | ✅ |
| Train 2022-2023 | 12,528 | 1.41 | 2.36% | 17 | 0.88 | ✅ |
| Test 2024 | ⏳ | — | — | — | — | รอ |

### S06 KAMA — USDJPY H4

| Period | PF | DD% | Trades | LR | ผล |
|--------|-----|-----|--------|-----|-----|
| ไม่แน่ใจ period | 1.30 | ~1.94% | 26 | 0.86 | ✅ บวก |

---

## แผนต่อไป (หลัง deploy)

1. **S10 re-optimize** — Option A (XAUUSD Real tick, EntryPeriod=8-12) หรือ Option B (USDJPY H4)
2. **Walk-forward** (optional) — S06/S14: Train 2022-2023 / Test 2024
3. **S01 StatArb** — แก้ Opt EA ให้ใช้ 2 symbols จริง
