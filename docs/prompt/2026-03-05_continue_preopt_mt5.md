# FlashEASuite V2 — Continuation Prompt
## Date: 2026-03-05 | Topic: Brain Pre-Optimizer → MT5 Optimization

---

## Context

เรากำลังพัฒนา Brain Pre-Optimizer ซึ่งเป็น Python script ที่รันก่อน MT5 Strategy Tester
เพื่อหา parameter ที่ดีที่สุดจาก yfinance data แล้วสร้าง .set file แบบ narrow range
ให้ MT5 validate เฉพาะ neighborhood ที่ดีที่สุด (~20-50 passes แทน 400-1200)

Working directory: `02_Brain/`
Entry point: `python run_preopt.py`

---

## สิ่งที่ทำเสร็จแล้ว (2026-03-05)

### Brain Pre-Optimizer (Python)
- `core/optimization/pre_optimizer.py` — fix constraint:
  - S06: `if tp_atr < sl_atr: return empty_metrics()` ← ป้องกัน TP < SL
  - S14: `if squeeze_min > 8: return empty_metrics()` ← ป้องกัน squeeze ที่ไม่เคยเกิด
  - `PARAM_BOUNDS["S14_SQUEEZE_MIN"]` แก้จาก `(3,15,1)` → `(3,8,1)`
- Re-run preopt S06 + S14 ทั้ง EURUSD, GBPUSD, XAUUSD (400 trials each)
- .set files ใหม่อยู่ใน `MQL5\Profiles\Tester\`

### Best Params จาก Pre-Optimizer (ล่าสุด)

| Strategy | Symbol | Score | Key Params |
|----------|--------|-------|------------|
| S06 | EURUSD | 0.876 | Period=12, ER=0.60, TP=3.0, SL=2.9 |
| S06 | GBPUSD | 0.645 | Period=29, ER=0.35, TP=4.2, SL=2.2 |
| S06 | XAUUSD | 0.852 | Period=22, ER=0.45, TP=1.3, SL=0.7 |
| S14 | EURUSD | 1.411 | BB=30, KC=1.5, SqMin=8, SL=4.0, TP=4.5 |
| S14 | GBPUSD | 3.055 | BB=36, KC=1.4, SqMin=4, SL=2.5, TP=4.5 |
| S14 | XAUUSD | 4.448 | BB=30, KC=1.2, SqMin=7, SL=3.4, TP=3.4 |

---

## สถานะ MT5 Optimization

| Strategy | Symbol | .set file | ผล MT5 | หมายเหตุ |
|----------|--------|-----------|---------|---------|
| S01 | GBPUSD | — | ❌ Custom=0 | SKIP: HYBRID ต้องการ Brain ZMQ |
| S06 | XAUUSD | `Opt_S06_XAUUSD_H1_brain.set` | ยังไม่รัน | รอทดสอบ |
| S14 | GBPUSD | `Opt_S14_GBPUSD_H1_brain.set` | ❌ โหลดไฟล์เก่าผิด | ต้องรันใหม่ด้วยไฟล์ใหม่ |
| S14 | XAUUSD | `Opt_S14_XAUUSD_H1_brain.set` | ยังไม่รัน | |
| S10 | ทุก | `Opt_S10_*_H1_brain.set` | ยังไม่รัน | S10 ไม่มี TP/SL fixed — Donchian exit |
| S15 | ทุก | `Opt_S15_*_H1_brain.set` | ยังไม่รัน | |

---

## งานที่ต้องทำต่อ

### 1. รัน MT5 Optimization (ทำก่อน)
ลำดับแนะนำ — เรียงตาม Brain score:

1. **S14 XAUUSD H1** — `Opt_S14_BBSqueeze` + `Opt_S14_XAUUSD_H1_brain.set`
2. **S14 GBPUSD H1** — `Opt_S14_BBSqueeze` + `Opt_S14_GBPUSD_H1_brain.set`
   ⚠️ ครั้งก่อนโหลดไฟล์เก่า — ต้องยืนยันใน tab Inputs ว่า Squeeze_Min range = **3–6** (ไม่ใช่ 9–13)
3. **S10 XAUUSD H1** — `Opt_S10_Turtle` + `Opt_S10_XAUUSD_H1_brain.set`
4. **S06 XAUUSD H1** — `Opt_S06_KAMA` + `Opt_S06_XAUUSD_H1_brain.set`
5. **S15 EURUSD H1** — `Opt_S15_Grid` + `Opt_S15_EURUSD_H1_brain.set`

### 2. ถ้า Custom = 0 อีก
- อ่าน XML result ส่งมาวิเคราะห์ (ดู Squeeze_Min range, TP/SL range ใน XML)
- ถ้า Brain แนะนำ params ผิดอีก → ดู simulate logic ของ strategy นั้นใน `pre_optimizer.py`

### 3. ถ้า Custom > 0
- บันทึก best params จาก MT5
- เปรียบเทียบกับ Brain best params
- Update MEMORY.md

---

## ไฟล์สำคัญ

| ไฟล์ | บทบาท |
|------|--------|
| `02_Brain/core/optimization/pre_optimizer.py` | simulation + random search |
| `02_Brain/core/optimization/setfile_generator.py` | สร้าง .set file |
| `02_Brain/core/strategy/adaptive_params.py` | PARAM_BOUNDS, STRATEGY_DEFAULTS |
| `02_Brain/run_preopt.py` | CLI entry point |
| `02_Brain/core/optimization/preopt_results.json` | ผล preopt ล่าสุด |
| `MQL5\Profiles\Tester\Opt_S14_GBPUSD_H1_brain.set` | .set file ใหม่ (ถูกต้อง) |

---

## คำสั่ง Re-run preopt ถ้าต้องการ

```bash
# Re-run S14 only
python run_preopt.py --strategies S14 --symbols GBPUSD XAUUSD --trials 400

# Re-run ทุก strategy
python run_preopt.py --strategies S06 S10 S14 S15 --symbols EURUSD GBPUSD XAUUSD --trials 400

# Export .set files จาก JSON ที่มีอยู่ (ไม่ต้อง re-run)
python run_preopt.py --export-only
```
