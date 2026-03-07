# Handoff Prompt — 2026-03-08
## FlashEASuite V2 — Post-Validation Deploy Session

---

## สถานะ ณ วันนี้ (2026-03-07)

### Validation Backtest เสร็จแล้ว

| Strategy | Symbol | TF | Status | PF | DD% |
|----------|--------|----|--------|----|-----|
| S06 KAMA | USDJPY | H4 | ✅ ผ่าน | 1.99 | 1.94% |
| S14 BBSqueeze | XAUUSD | H1 | ✅ ผ่าน | 1.84 | 2.36% |
| S14 BBSqueeze | GBPUSD | H1 | ✅ ผ่าน 100% | 2.76 | 3.99% |
| S10 Turtle | XAUUSD | H4 | ⏳ รอ Real tick | — | — |

### Code พร้อม deploy แล้ว

- `Include/Logic/Strategies/S06_KAMA.mqh` — defaults + validation comment ✅
- `Include/Logic/Strategies/S10_Turtle.mqh` — defaults + pending note ✅
- `Include/Logic/Strategies/S14_BBSqueeze.mqh` — XAUUSD + GBPUSD params documented ✅
- FINAL.set files ทุกตัวใน `Profiles/Tester/` ✅

---

## งานที่ต้องทำวันนี้ (ลำดับ)

### ลำดับที่ 1 — S10 Real Tick Validation (รันค้างคืน)

รัน backtest ด้วย:
- Expert: `Opt_S10_Turtle`
- Symbol: `XAUUSD.tp` / H4
- Model: **Real tick** (ทุก tick มาจากข้อมูล tick จริง)
- Date: `2022.01.01 – 2024.12.31`
- Optimization: ปิด
- Load: `S10_XAUUSD_H4_FINAL.set`

เป้าหมาย: PF >= 1.38, DD <= 30%, Trades >= 80

---

### ลำดับที่ 2 — Deploy Preparation

ก่อน deploy ตรวจสอบ:

```
1. Brain ทำงานอยู่หรือไม่ → python 02_Brain/main.py
2. Trader (ProgramC_Trader) compile ใหม่ใน MetaEditor หลัง .mqh เปลี่ยน
3. ทดสอบ ZMQ ports 7777/7778/7779 ว่า connect ได้
```

#### EA ที่ต้อง recompile (เพราะ .mqh เปลี่ยน)

| EA | เหตุผล |
|----|--------|
| `ProgramC_Trader.mq5` | ใช้ S06/S10/S14 .mqh ทั้งหมด |
| `Tester/Opt_S06_KAMA.mq5` | include S06_KAMA.mqh |
| `Tester/Opt_S10_Turtle.mq5` | include S10_Turtle.mqh |
| `Tester/Opt_S14_BBSqueeze.mq5` | include S14_BBSqueeze.mqh |

MetaEditor → เปิดแต่ละไฟล์ → Compile (F7)

---

### ลำดับที่ 3 — Brain Config Update

ตรวจสอบว่า Brain ใช้ params ที่ optimize แล้ว:

- `02_Brain/core/optimization/pre_optimizer.py` — constraints TP>=SL, squeeze_min<=8 ✅ อยู่แล้ว
- `02_Brain/core/optimization/setfile_generator.py` — fixed_from_params ✅ อยู่แล้ว

ถ้าต้องการ re-export Brain .set files:
```bash
python 02_Brain/run_preopt.py --export-only
```

---

### ลำดับที่ 4 — Live Connection Test

1. เปิด MT5 + ProgramC_Trader บน demo account
2. เปิด Brain: `python 02_Brain/main.py`
3. ดู log Brain ว่า `[Ingestion] Connected` และ `[Trader] Connected`
4. ตรวจสอบว่า strategy เริ่ม analyze ได้

---

### ลำดับที่ 5 — Git Commit

```
git add Include/Logic/Strategies/S06_KAMA.mqh
git add Include/Logic/Strategies/S10_Turtle.mqh
git add Include/Logic/Strategies/S14_BBSqueeze.mqh
git add docs/OPTIMIZATION_SESSION_2026-03-07.md
git add docs/prompt/2026-03-07_deploy_handoff.md
git commit -m "feat(validate): S06/S14 validation complete + deploy prep

Validation backtest results (2026-03-07, OHLC M1):
- S06 KAMA USDJPY H4: PF=1.99 DD=1.94% Trades=26 — PASS
- S14 BBSqueeze XAUUSD H1: PF=1.84 DD=2.36% Trades=23 — PASS (98% match)
- S14 BBSqueeze GBPUSD H1: PF=2.76 DD=3.99% Trades=25 — PASS (100% match)
- S10 Turtle: OHLC M1 unsuitable for breakout — pending Real tick validation

.mqh comments updated with validation results for all 3 strategies.
S14_BBSqueeze.mqh now documents both XAUUSD and GBPUSD optimized params."
```

---

## ข้อมูลอ้างอิง

### FINAL.set files (Profiles/Tester/)

| File | Symbol | Key params |
|------|--------|-----------|
| `S06_USDJPY_H4_FINAL.set` | USDJPY H4 | Period=13, ER=0.90, TP=4.7, SL=2.3 |
| `S10_XAUUSD_H4_FINAL.set` | XAUUSD H4 | Entry=15, Exit=30, Risk=0.5% |
| `S14_XAUUSD_H1_FINAL.set` | XAUUSD H1 | BB=25, KC=1.15, SqMin=6, SL/TP=3.4 |
| `S14_GBPUSD_H1_FINAL.set` | GBPUSD H1 | BB=48, KC=1.50, SqMin=4, SL=2.5, TP=4.5 |

### ZMQ Ports
- 7777: Feeder → Brain (SUB)
- 7778: Brain → Trader (PUSH)
- 7779: Trader → Brain feedback

### Python
```
/c/Users/drsuk/miniconda3/envs/deepquant_env/python.exe
```

---

## งานในอนาคต (ไม่ด่วน)

- S01 StatArb: แก้ Opt EA ให้ใช้ 2 symbols จริง + ลด EntryZ=1.5-2.5
- S15 Grid: เพิ่ม standalone signal mode ใน GridCore (RSI/MACD fallback)
- Walk-forward test: Train 2022-2023 / Test 2024 สำหรับทุก strategy
- Additional symbols: S10 USDJPY H4, S14 EURUSD H1
