# S01 StatArb — Pair Settings Research & Backtest Guide
**วันที่**: 2026-03-03 | **จัดทำโดย**: Claude Code Research
**สถานะ**: Ready for testing 2026-03-04

---

## 1. ทำไม EURUSD / GBPUSD ไม่ได้ผลในการ Backtest

### ปัญหาหลัก: ไม่ได้ Cointegrated จริง

```
ADF Test p-value ของ EURUSD / GBPUSD = ~0.28
→ ต้องน้อยกว่า 0.05 จึงจะถือว่า Cointegrated

ผลคือ: Z-score ไม่ mean-revert → สัญญาณ false ตลอด
        → EA เทรดทุก tick → บัญชีแตกทุก pass
```

### ปัญหาเพิ่มเติม: Beta=1.0 ไม่ถูกต้อง
```
Beta จริงของ GBPUSD relative to EURUSD ≈ 1.4 (ไม่ใช่ 1.0)
Spread = EURUSD - (1.4 × GBPUSD)  ← ต้องใช้ค่านี้
แต่ใน Standalone mode ใช้ Beta=1.0 ตายตัว → spread drift
```

---

## 2. คู่เงินที่แนะนำสำหรับ S01 StatArb

### Tier 1 — Cointegration สูงมาก (แนะนำที่สุด)

| Pair A | Pair B | Beta (approx) | Correlation | p-value | หมายเหตุ |
|--------|--------|---------------|-------------|---------|---------|
| **AUDUSD.tp** | **NZDUSD.tp** | ~1.05–1.10 | 0.97+ | ~0.001 | ดีที่สุด — share AUD/commodity bloc |
| **EURUSD.tp** | **EURGBP.tp** | ~0.85–0.95 | 0.92+ | ~0.02 | EUR เป็น common factor |
| **GBPUSD.tp** | **EURUSD.tp** | **1.35–1.45** | 0.88 | ~0.12* | ใช้ได้แต่ต้องใช้ Beta=1.4 |

> \* EURUSD/GBPUSD cointegration ไม่เสถียร ถ้าจะใช้ต้องระบุ Beta ให้ถูก

### Tier 2 — Cointegration ปานกลาง (ใช้ได้)

| Pair A | Pair B | Beta (approx) | Correlation | หมายเหตุ |
|--------|--------|---------------|-------------|---------|
| **EURJPY.tp** | **GBPJPY.tp** | ~0.75–0.85 | 0.91+ | JPY เป็น common factor |
| **AUDCAD.tp** | **NZDCAD.tp** | ~1.00–1.05 | 0.93+ | CAD เป็น common factor |
| **EURCAD.tp** | **GBPCAD.tp** | ~0.80–0.90 | 0.89+ | CAD เป็น common factor |

### Tier 3 — ทดสอบเพิ่มเติม (อาจได้ผล)

| Pair A | Pair B | Beta (approx) | หมายเหตุ |
|--------|--------|---------------|---------|
| **USDCHF.tp** | **USDCAD.tp** | ~0.90–1.10 | USD เป็น common factor |
| **XAUUSD.tp** | **XAGUSD.tp** | ~60–80 | Precious metals — volatile |

---

## 3. ค่าพารามิเตอร์ที่แนะนำแต่ละคู่

### AUDUSD / NZDUSD (แนะนำที่สุด)

```
StatArb_Pair1   = "AUDUSD.tp"
StatArb_Pair2   = "NZDUSD.tp"
StatArb_Period  = 20–30      (ช่วง H1: 20 บาร์ = ~1 สัปดาห์)
StatArb_EntryZ  = 2.0–2.5   (เพราะ spread tight กว่า EUR/GBP)
StatArb_StopZ   = 3.0–3.5
Inp_RiskPct     = 0.5–1.0
Inp_MinConf     = 0.4
```

**เหตุผล**: AUD และ NZD เชื่อมโยงกับ commodity bloc เดียวกัน
ราคา iron ore, dairy — spread มักกลับ mean ภายใน 5–15 บาร์ H1

---

### EURUSD / EURGBP

```
StatArb_Pair1   = "EURUSD.tp"
StatArb_Pair2   = "EURGBP.tp"
StatArb_Period  = 25–40      (ช่วง H1: ค่อนข้าง noisy ต้องช่วงยาวกว่า)
StatArb_EntryZ  = 2.0–2.5
StatArb_StopZ   = 3.25–4.0
Inp_RiskPct     = 0.5–1.0
Inp_MinConf     = 0.4
```

**เหตุผล**: EUR เป็น common factor → EURUSD และ EURGBP มี EUR ร่วมกัน
→ spread คือ net GBP exposure ซึ่ง mean-reverts ได้ดี

---

### EURJPY / GBPJPY

```
StatArb_Pair1   = "EURJPY.tp"
StatArb_Pair2   = "GBPJPY.tp"
StatArb_Period  = 20–35
StatArb_EntryZ  = 2.0–2.5
StatArb_StopZ   = 3.0–3.75
Inp_RiskPct     = 0.3–0.75   (JPY pairs volatile กว่า — ลด risk)
Inp_MinConf     = 0.5
```

**เหตุผล**: JPY ทั้งคู่ — risk-on/risk-off drives both → high correlation

---

### AUDCAD / NZDCAD

```
StatArb_Pair1   = "AUDCAD.tp"
StatArb_Pair2   = "NZDCAD.tp"
StatArb_Period  = 20–30
StatArb_EntryZ  = 2.0–2.5
StatArb_StopZ   = 3.0–3.5
Inp_RiskPct     = 0.5–1.0
Inp_MinConf     = 0.4
```

**เหตุผล**: CAD เป็น common factor + AUD/NZD อยู่ใน commodity bloc เดียวกัน

---

### GBPUSD / EURUSD (ถ้าต้องใช้คู่นี้)

```
StatArb_Pair1   = "EURUSD.tp"
StatArb_Pair2   = "GBPUSD.tp"
StatArb_Period  = 30–50      (ยาวกว่าปกติ เพราะ cointegration ไม่เสถียร)
StatArb_EntryZ  = 2.5–3.5   (สูงกว่าปกติ ลด false signals)
StatArb_StopZ   = 3.5–4.5
Inp_RiskPct     = 0.1–0.3   (ลด risk มากๆ เพราะ cointegration ไม่ดี)
Inp_MinConf     = 0.5–0.6   (strict กว่าปกติ)

หมายเหตุ: Beta ควรเป็น 1.35–1.45 ไม่ใช่ 1.0
           แต่ standalone mode บังคับ Beta=1.0
           → ผลลัพธ์ backtest อาจไม่แม่นยำ
```

---

## 4. แผน Backtest วันพรุ่งนี้

### ลำดับที่แนะนำ

```
ลำดับ  Symbol              TF   Period              เป้าหมาย
─────────────────────────────────────────────────────────────
1      AUDUSD.tp/NZDUSD   H1   2022.01.01-2024.12.31  ดีที่สุด ทำก่อน
2      EURUSD.tp/EURGBP   H1   2022.01.01-2024.12.31  EUR common factor
3      EURJPY.tp/GBPJPY   H1   2022.01.01-2024.12.31  JPY common factor
4      AUDCAD.tp/NZDCAD   H1   2022.01.01-2024.12.31  CAD common factor
5      EURUSD.tp/GBPUSD   H1   2022.01.01-2024.12.31  เทียบผล (คาดว่าแย่สุด)
```

### ขั้นตอน: Single Backtest ก่อน แล้วค่อย Optimize

```
Step 1: Single Backtest (ไม่ optimize) — ดูว่า Trade มีไหม และสมเหตุสมผลไหม
Step 2: ถ้า Backtest ดี → ค่อย Optimize parameter ด้วย Genetic
Step 3: เปรียบเทียบผลระหว่าง 5 คู่เงิน
```

---

## 5. ค่าตัวแปร Optimization สำหรับแต่ละคู่

### Parameter Ranges (ใช้ได้กับทุกคู่ ปรับ EntryZ ตาม Tier)

| Parameter | Tier 1 (AUDUSD/NZD) | Tier 2 (JPY/CAD pairs) | EURUSD/GBPUSD |
|-----------|---------------------|----------------------|----------------|
| `StatArb_Period` | 15–35, step 5 | 20–40, step 5 | 30–60, step 10 |
| `StatArb_EntryZ` | 2.0–2.5, step 0.25 | 2.0–2.5, step 0.25 | 2.5–3.5, step 0.25 |
| `StatArb_StopZ` | 3.0–3.75, step 0.25 | 3.0–4.0, step 0.25 | 3.75–4.5, step 0.25 |
| `Inp_RiskPct` | 0.25–1.0, step 0.25 | 0.25–0.75, step 0.25 | 0.1–0.3, step 0.1 |
| `Inp_MinConf` | 0.3–0.6, step 0.1 | 0.4–0.6, step 0.1 | 0.5–0.7, step 0.1 |
| **Total Combos** | **~2,000–3,000** | **~2,000–3,000** | **~1,000–2,000** |

---

## 6. สิ่งที่ต้องดูใน Backtest Results

### เกณฑ์ผ่าน (OnTester Hard Filter)
```
✅ Trades    >= 25    (3 ปี ควรได้ 25+ trades)
✅ Profit    > 0      (กำไรสุทธิเป็นบวก)
✅ PF        >= 1.0   (Profit Factor)
✅ MaxDD     <= 20%   (Drawdown ไม่เกิน 20%)
✅ WinRate   >= 50%   (Mean reversion ควร win บ่อย)
```

### เกณฑ์คุณภาพสำหรับ S01 โดยเฉพาะ
```
Ideal:
  WinRate    > 60%    (mean reversion ธรรมชาติควร win บ่อย)
  RR Ratio   > 1.0    (ได้กำไรต่อ trade พอๆ กับที่เสีย)
  Trades     50–200   (สำหรับ 3 ปี บน H1 = สมเหตุสมผล)
  MaxDD      < 15%    (Stat Arb ควร smooth)

Warning signs:
  Trades > 500        → ยัง over-trading อยู่ (เพิ่ม EntryZ)
  WinRate < 45%       → spread ไม่ mean-revert → เปลี่ยนคู่
  MaxDD > 20%         → ลด RiskPct หรือเพิ่ม StopZ
```

---

## 7. ข้อมูลอ้างอิง

- [Python for Statistical Arbitrage in Forex — Medium](https://medium.com/@deepml1818/python-for-statistical-arbitrage-in-forex-markets-cross-currency-pair-strategies-fd8525bd304c)
- [Cointegration in the Forex market — Mechanical Forex](https://mechanicalforex.com/2014/11/cointegration-in-the-forex-market.html)
- [Statistical Arbitrage and Pairs Trading — Forex Factory](https://www.forexfactory.com/thread/1129340-statistical-arbitrage-and-pairs-trading-on-forex)
- [Optimizing Pairs Trading with Z-Index — BJF Trading Group](https://bjftradinggroup.com/optimizing-pair-trading-using-the-z-index-technique/)
- [Definitive Guide to Pairs Trading — Hudson & Thames](https://hudsonthames.org/definitive-guide-to-pairs-trading/)
- [Pairs Trading Basics — QuantInsti](https://blog.quantinsti.com/pairs-trading-basics/)
- [Cointegration-based Pairs Trading — Springer Journal 2025](https://link.springer.com/article/10.1057/s41260-025-00416-0)

---

*สร้างโดย Claude Code | 2026-03-03 | สำหรับทดสอบวันที่ 2026-03-04*
