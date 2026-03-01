# S03 — Smart Money Concepts (SMC)
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: P9-5 | 2026-02-27 | Jimmi Deep-Dive Edition

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S03 | รหัสอ้างอิงลำดับที่สามในระบบมัลติกลยุทธ์ของ FlashEASuite V2 วางตำแหน่งหลังจาก S01 (Stat Arb) และ S02 (ML Ensemble) ในฐานะกลยุทธ์ Full MQL5 ตัวแรกของระบบ |
| **ชื่อ** | Smart Money Concepts (SMC) | แนวคิดที่วิเคราะห์รอยเท้าพฤติกรรมของนักลงทุนสถาบัน (Institutional Investors) ผ่านโครงสร้างราคา (Price Structure) แทนที่จะพึ่งพาตัวชี้วัดทางเทคนิค (Indicators) ทั่วไป |
| **ประเภท** | Full MQL5 | การประมวลผลสัญญาณเทรดทั้งหมดเกิดขึ้นใน MQL5 โดยตรง Python Brain ทำหน้าที่เพียง Regime Classification และ Confidence Scoring ไม่ได้คำนวณสัญญาณ |
| **Standalone Capable** | ❌ No (Server Only) | ต้องการ CONFIG_PUSH จาก Python Brain ก่อนทำงาน มี ServerOnly Guard ใน Analyze(): `if(m_config.confidence < 0.01) return;` |
| **Preferred Regime** | TRENDING, VOLATILE | สภาวะตลาดที่มีทิศทางชัดเจน (TRENDING) หรือมีการเคลื่อนไหวรุนแรง (VOLATILE) ทำให้เกิด Order Block, FVG และ BOS ได้อย่างชัดเจนและน่าเชื่อถือ |
| **Poor Regimes** | RANGING | ตลาดที่ราคาแกว่งในกรอบแคบ ไม่มีทิศทาง BOS ที่ชัดเจน ทำให้ระบบ Triple Confluence ไม่สามารถยืนยันสัญญาณได้ |
| **MQL5 Class** | `CSMCV6` | คลาสหลักในภาษา MQL5 ที่ประสานงานระบบตรวจจับสามระบบ (OB, FVG, BOS) และตัดสินใจเปิดออเดอร์ |
| **Sub-Detectors** | `COrderBlockDetector`, `CFVGDetector`, `CBOSDetector` | สามคลาสย่อยที่ทำงานร่วมกันเป็น "Triple Confluence Engine" แต่ละตัวทำงานเป็น Direct Member (ไม่ใช้ pointer) เพื่อประสิทธิภาพสูงสุด |

### สรุปแนวคิด (Summary of Concepts)

S03 เป็นกลยุทธ์ที่ตั้งอยู่บนรากฐานของ **Smart Money Concepts (SMC)** — ปรัชญาการวิเคราะห์ตลาดที่มองว่า การเคลื่อนไหวของราคาทุกครั้งนั้นถูกขับเคลื่อนโดย **"เงินสถาบัน" (Smart Money)** ได้แก่ ธนาคารกลาง (Central Banks), กองทุนป้องกันความเสี่ยง (Hedge Funds), ธนาคารพาณิชย์ขนาดใหญ่ (Market Makers) และสถาบันการเงินที่มีปริมาณการซื้อขายมหาศาล

ระบบใช้ **สามตัวตรวจจับ** ที่ทำงานร่วมกันในรูปแบบ Triple Confluence:
- **(1) Order Block (OB)** — ตรวจจับแท่งเทียนที่สถาบันใช้สะสมหรือกระจาย position ก่อนที่จะ "ดัน" ราคาในทิศทางที่ต้องการ
- **(2) Fair Value Gap (FVG)** — ตรวจจับช่องว่างสภาพคล่อง (Liquidity Gap) ที่เกิดจากการเคลื่อนไหวของราคาอย่างรวดเร็ว ทิ้งบริเวณที่ราคา "ข้ามผ่าน" โดยไม่มีการซื้อขายเพียงพอ
- **(3) Break of Structure (BOS)** — ยืนยันทิศทางของตลาดผ่านการทำลาย Swing High หรือ Swing Low เดิม

เป้าหมายของ S03 คือการ **เข้า trade เมื่อราคากลับมาทดสอบโซน OB หรือ FVG หลังจากเกิด BOS** — ซึ่งเป็นจุดที่สถาบันมักจะกลับมาเพิ่ม position อีกครั้ง ทำให้ราคาเด้งกลับอย่างรุนแรง

---

### ทำไมต้องชื่อ "Smart Money Concepts"?

คำว่า **Smart Money** ในโลกการเงินหมายถึงนักลงทุนที่มีข้อมูลและทรัพยากรที่เหนือกว่ามือปลีก (Retail Traders) เช่น ธนาคารพาณิชย์ กองทุนรวม และ Proprietary Trading Desks ที่สามารถเคลื่อนย้ายเงินทุนขนาดใหญ่ (หลักพันล้านดอลลาร์) ในครั้งเดียว

ปัญหาของสถาบันเหล่านี้คือ: **ขนาดของ Order นั้นใหญ่เกินไปสำหรับตลาดที่จะรับได้ในครั้งเดียว** หากธนาคารต้องการซื้อ EURUSD มูลค่า $500 ล้านในราคา 1.0800 ทันที ราคาจะถูกดันขึ้นอย่างรวดเร็วก่อนที่ Order จะถูก Fill ทั้งหมด ทำให้ต้นทุนเฉลี่ยของธนาคารสูงกว่าที่ต้องการ

ดังนั้น สถาบันจึงต้อง **"ซ่อน" การเข้า position** โดยใช้วิธีการหลายรูปแบบ รวมถึงการสะสม (Accumulation) ในช่วงที่ตลาดไม่มีทิศทาง จนกว่าจะได้ปริมาณที่พอใจ แล้วจึง "ดัน" ราคาในทิศทางที่ต้องการ การกระทำเหล่านี้ทิ้ง **"รอยเท้า" ไว้บนกราฟราคา** ในรูปแบบของ Order Block, Fair Value Gap และ Break of Structure ซึ่ง S03 ถูกออกแบบมาเพื่อ ตรวจจับและใช้ประโยชน์จากรอยเท้าเหล่านั้น

---

### ธรรมชาติของเงินสถาบัน (Institutional Behavior)

เพื่อให้เข้าใจว่าเหตุใด OB, FVG และ BOS จึงน่าเชื่อถือ ต้องเข้าใจกระบวนการทำงานของสถาบันก่อน:

**วงจรชีวิตของราคา (Price Delivery Cycle) ตามหลัก SMC:**

**ระยะที่ 1 — Accumulation (การสะสม):**
สถาบันต้องการ Long ตลาด จึงเข้าซื้อแบบค่อยเป็นค่อยไปในบริเวณที่ราคาไม่มีทิศทาง (Range) เพื่อไม่ให้ราคาขยับมากเกินไป การซื้อในระยะนี้จะทิ้งรอยไว้เป็น **Demand Order Block** — แท่งเทียนสีแดง (Bearish) ที่มีปริมาณซื้อขายสูงผิดปกติ เนื่องจากสถาบันซ่อนการซื้อไว้หลังแท่งขาลง เพื่อให้มือปลีกขายมาให้

**ระยะที่ 2 — Markup (การดันราคา):**
เมื่อสถาบันสะสม position เพียงพอแล้ว จะ "ดัน" ราคาขึ้นอย่างรวดเร็ว การดันนี้มักเกิดขึ้นอย่างรวดเร็วจนทิ้ง **Fair Value Gap** — ช่องว่างระหว่างแท่งเทียน 3 แท่งที่ราคาวิ่งผ่านโดยไม่มีการ "เติม" สภาพคล่อง และการดันนี้จะทำลาย Swing High เดิม เกิดเป็น **Break of Structure Bullish**

**ระยะที่ 3 — Retracement to OB/FVG:**
หลัง BOS ราคามักจะ "ดึงกลับ" ไปทดสอบบริเวณ OB หรือ FVG เนื่องจากสถาบันต้องการเพิ่ม position อีกในราคาที่ต่ำกว่า นี่คือ **จุดเข้า Trade ของ S03**

**ระยะที่ 4 — Distribution (การกระจาย):**
สถาบันเริ่มขายทำกำไร ราคาถึงจุดสูงสุด

---

### ตัวอย่างเหตุการณ์จริง (Case Study)

สมมติเหตุการณ์ ณ วันที่ 27 กุมภาพันธ์ 2026 บนกราฟ EURUSD H1:

**สถานการณ์ตลาด:**
- ราคาแกว่งตัวในกรอบ 1.0780–1.0840 มาตลอดช่วงเช้า (Asian Session)
- Swing High ล่าสุดอยู่ที่ **1.0845** (เกิดขึ้น 5 ชั่วโมงก่อน)
- ATR 14 แท่งอยู่ที่ **0.0020** (20 pips)

**เหตุการณ์ที่ 1 — Order Block ก่อตัว (09:00 น.):**
ที่เวลา 09:00 น. เกิดแท่งเทียน Bearish (แท่งแดง) ที่มีปริมาณการซื้อขายสูงผิดปกติ:
- Open: 1.0820 | Close: 1.0800 | High: 1.0825 | Low: 1.0795
- Volume = 2,450 ticks ≫ Average Volume = 1,200 ticks → Volume Ratio = 2.04 ≥ 1.5 ✅
- ระบบบันทึก **Demand OB Zone: [1.0795, 1.0825]**

**เหตุการณ์ที่ 2 — Impulse Move + FVG ก่อตัว (09:00–09:30 น.):**
ราคาพุ่งขึ้นอย่างรวดเร็วในสามแท่งถัดมา:
- แท่ง i+1 (09:00): High=1.0825
- แท่ง i   (09:15): เป็นแท่งพุ่ง (Impulse Candle)
- แท่ง i-1 (09:30): Low=1.0855

FVG ก่อตัว: `bull_gap = next_low(1.0855) - prev_high(1.0825) = 0.0030`
FVG Ratio = 0.0030 / 0.0020 = **1.50** ≥ 0.5 × ATR ✅
FVG Zone: [Bottom=1.0825, Top=1.0855]

สามแท่งหลังจาก OB (bar i-3): `next_close = 1.0855`
`move_up = 1.0855 - 1.0825 = 0.0030 > 0.5 × ATR (0.0010)` ✅ — OB ผ่านการกรอง

**OB Strength = min(1.0, 0.0030 / (0.0020 × 3.0)) = min(1.0, 0.50) = 0.50**

**เหตุการณ์ที่ 3 — Break of Structure (09:30 น.):**
ที่เวลา 09:30 น. แท่งที่ปิดที่ High=1.0858 ทำลาย Swing High เดิมที่ 1.0845:
- `cur_high (1.0858) > sh_price (1.0845)` ✅ → **BOS_BULLISH ยืนยัน**
- ระบบบันทึก `m_bos_dir = BOS_DIR_BULLISH` และ `m_bos_active = true`

**เหตุการณ์ที่ 4 — Retracement และ Entry (10:00 น.):**
ราคาดึงกลับลงมา:
- ราคา bid/ask midpoint = **1.0810** (อยู่ในโซน OB [1.0795, 1.0825]) ✅

**การคำนวณ Confidence:**
```
ob_strength  = 0.50
c = ob_strength × 0.5 = 0.50 × 0.5 = 0.250

fvg_ratio    = 1.50 (จาก FVGDetector)
fvg_contrib  = min(0.3, (1.50 / 3.0) × 0.3) = min(0.3, 0.150) = 0.150
c += 0.150 → c = 0.400

BOS active   → c += 0.2 → c = 0.600
Final conf   = min(1.0, 0.600) = 0.600 ≥ 0.45 ✅
```

**การเปิด Long Order:**
- Entry Price: 1.0810
- SL = ob.low - SL_ATRBuffer × ATR = 1.0795 - 0.3 × 0.0020 = **1.0789** (21 pips)
- TP = entry + TP_ATRMult × ATR = 1.0810 + 2.0 × 0.0020 = **1.0850** (40 pips)
- R:R Ratio = 40 / 21 ≈ **1.90:1**

**ผลลัพธ์:** ราคาสะท้อนกลับจากโซน OB อย่างรุนแรงและวิ่งถึง TP ที่ 1.0850 ภายใน 2 ชั่วโมง

---

### เหตุผลที่ราคาต้องกลับมาทดสอบ OB/FVG เสมอ

มีสองเหตุผลทางเศรษฐศาสตร์ที่รองรับปรากฏการณ์นี้:

**เหตุผลที่ 1 — Unfinished Business ของสถาบัน:**
เมื่อสถาบันเริ่มสะสม position ใน OB แต่ยังไม่ได้ปริมาณที่ต้องการ (เนื่องจากราคาวิ่งขึ้นเร็วเกินไปหลัง Impulse) สถาบันจะ "รอ" ให้ราคากลับลงมา OB เพื่อเพิ่ม position ที่เหลืออีกครั้ง การกระทำของสถาบันในช่วงนี้จะสร้าง Buying Pressure ที่แข็งแกร่งใน OB Zone ทำให้ราคาเด้งกลับ

**เหตุผลที่ 2 — Liquidity Hunt และ FVG Fill:**
FVG แสดงถึงบริเวณที่สภาพคล่องในตลาดมีไม่เพียงพอ (Price moved too fast, leaving an "imbalance") ตลาดโดยธรรมชาติจะ "ดึง" ราคากลับมาเติมช่องว่างนี้เพื่อสร้างความสมดุลของสภาพคล่อง (Liquidity Balance) นี่เป็นเหตุผลว่าทำไม FVG จึงเป็นโซนแรงดึงดูดที่ทรงพลัง

---

## 2. ทฤษฎีหลัก (Core Theory)

### 2.1 Order Block (OB) Detection — กลไกตรวจจับรอยเท้าสถาบัน

**นิยามทางคณิตศาสตร์:**

Order Block คือแท่งเทียนที่ผ่านเงื่อนไขสองข้อพร้อมกัน:

```
เงื่อนไขที่ 1 — Volume Filter:
  Volume[i] ≥ MinOBVolume × AvgVolume(lookback bars)
  (ค่าเริ่มต้น: 1.5 × Average)

เงื่อนไขที่ 2 — Impulse Confirmation:
  สำหรับ Demand OB (แท่งขาลงก่อนขาขึ้น):
    close[i] < open[i]  (Bearish Candle)
    AND close[i-3] - high[i] > MinReversal × ATR  (ราคาดันขึ้นจาก High ≥ 0.5 ATR)

  สำหรับ Supply OB (แท่งขาขึ้นก่อนขาลง):
    close[i] > open[i]  (Bullish Candle)
    AND low[i] - close[i-3] > MinReversal × ATR   (ราคาดิ่งจาก Low ≥ 0.5 ATR)
```

**การคำนวณ OB Strength:**

ค่า Strength คือการวัดว่า "แรงดัน" ที่เกิดขึ้นหลัง OB นั้นรุนแรงเพียงใดเมื่อเทียบกับความผันผวนปกติ:

```
Demand OB: strength = min(1.0, move_up  / (ATR × 3.0))
Supply OB: strength = min(1.0, move_down / (ATR × 3.0))

เมื่อ: move_up   = close[i-3] - high[i]   (ระยะที่ราคาวิ่งขึ้นจาก OB high)
       move_down = low[i] - close[i-3]     (ระยะที่ราคาดิ่งลงจาก OB low)
       ATR       = Average True Range 14 แท่ง
```

**การแปลความหมาย OB Strength:**
- strength = 0.33: Impulse Move เท่ากับ ATR หนึ่งเท่า — แรงปานกลาง
- strength = 0.67: Impulse Move เท่ากับ ATR สองเท่า — แรงดี
- strength = 1.00: Impulse Move ≥ ATR สามเท่า — แรงสูงสุด (แรงดันของสถาบันสูงมาก)

**OB Zone และการ Invalidate:**

โซน OB ถูกกำหนดเป็น `[low[i], high[i]]` ของแท่งเทียน OB โดยระบบจะ Mark OB เป็น "Inactive" (ใช้แล้ว) เมื่อราคาเข้ามาใน zone นี้แล้วครั้งหนึ่ง เนื่องจากหลัง OB ถูก "Fill" แล้ว สถาบันมักจะไม่ใช้จุดเดิมอีก

```mql5
// MarkRetested() — เรียกทุก Tick
void MarkRetested(double price) {
    for each block in m_blocks:
        if (block.is_active && price >= block.low && price <= block.high)
            block.is_active = false  // OB ถูก consume แล้ว
}
```

ระบบจัดเก็บ OB สูงสุด **10 โซน** (`MAX_OB_ZONES = 10`) โดยสแกนจาก `m_lookback` แท่ง (เริ่มจากแท่งที่ 50 ย้อนหลัง) และในแต่ละรอบ `Scan()` จะถูกรีเซ็ตและสแกนใหม่ทั้งหมด

---

### 2.2 Fair Value Gap (FVG) Detection — ช่องว่างสภาพคล่อง

**หลักการ 3 แท่งเทียน (3-Candle Imbalance):**

FVG เกิดจากการที่ราคาเคลื่อนไหวเร็วเกินไปจนสร้างช่องว่างระหว่างแท่งเทียนที่ 1 และแท่งเทียนที่ 3:

```
แท่งเทียน i+1 (Previous) | แท่งเทียน i (Center) | แท่งเทียน i-1 (Next)

Bullish FVG (ช่องว่างขาขึ้น):
  next_low (Low[i-1]) > prev_high (High[i+1])
  → ช่องว่าง = [prev_high, next_low]
  → bull_gap = next_low - prev_high

Bearish FVG (ช่องว่างขาลง):
  next_high (High[i-1]) < prev_low (Low[i+1])
  → ช่องว่าง = [next_high, prev_low]
  → bear_gap = prev_low - next_high
```

**เงื่อนไขการยืนยัน:**
```
bull_gap > MinFVGSize × ATR   (ค่าเริ่มต้น: 0.5 × ATR)
bear_gap > MinFVGSize × ATR
```

**FVG Size Ratio:**
```
size_ratio = gap_size / ATR

ยิ่ง size_ratio สูง = ช่องว่างใหญ่กว่าความผันผวนปกติ
                    = แรงดึงดูดของตลาดในการเติม Gap สูงขึ้น
```

**การ Invalidate FVG (MarkFilled):**

FVG จะถูก Mark เป็น Inactive เมื่อราคาผ่านจุดกึ่งกลาง (Midpoint) ของช่องว่าง:
```
mid = (fvg.top + fvg.bottom) / 2

Bullish FVG: inactive เมื่อ price ≤ mid  (ราคาลงมาต่ำกว่ากึ่งกลาง = FVG ถูก Fill ครึ่งหนึ่ง)
Bearish FVG: inactive เมื่อ price ≥ mid
```

เหตุผลที่ใช้จุด Midpoint (ไม่ใช่ Bottom/Top): สถาบันมักจะ "เติม" FVG แค่ครึ่งหนึ่ง (50% Fill) แล้วราคาจะเด้งกลับ ซึ่งสอดคล้องกับหลักการ Partial Fill ของ SMC

---

### 2.3 Break of Structure (BOS) Detection — การยืนยันทิศทางตลาด

**นิยาม Pivot High/Low:**

ระบบค้นหา Pivot High และ Pivot Low ที่ "แท้จริง" (True Pivots) โดยใช้ SwingBars = 5 แท่งแต่ละด้าน:

```
Pivot High[i] = high[i] คือ Pivot ก็ต่อเมื่อ:
  high[i] > high[i+1], high[i+2], ..., high[i+swing_bars]  (แท่งก่อนหน้า)
  high[i] > high[i-1], high[i-2], ..., high[i-swing_bars]  (แท่งถัดไป)

Pivot Low[i] = low[i] คือ Pivot ก็ต่อเมื่อ:
  low[i] < low[i+1], low[i+2], ..., low[i+swing_bars]
  low[i] < low[i-1], low[i-2], ..., low[i-swing_bars]
```

**เงื่อนไข BOS:**
```
BOS_BULLISH: High ของแท่งล่าสุด (bar[1]) > Swing High สูงสุดในช่วง Lookback
             AND Swing High นี้ต้องเป็น Swing High ใหม่ (ไม่ใช่ตัวเดิมที่เคยทำ BOS แล้ว)

BOS_BEARISH: Low ของแท่งล่าสุด (bar[1]) < Swing Low ต่ำสุดในช่วง Lookback
             AND Swing Low นี้ต้องเป็น Swing Low ใหม่
```

**ทำไมใช้ bar[1] ไม่ใช่ bar[0]?**

ระบบตรวจจับ BOS บนแท่งที่ปิดแล้ว (bar[1]) ไม่ใช่แท่งปัจจุบัน (bar[0]) เพื่อป้องกัน False BOS ที่เกิดจาก Wick หรือราคาที่ยังไม่ปิด หลักการนี้สอดคล้องกับแนวทาง SMC แบบ Professional ที่ยืนยัน BOS เฉพาะเมื่อ **Close** ทะลุผ่าน Swing Level เท่านั้น

**การป้องกัน Duplicate BOS:**

ระบบเก็บค่า `m_last_sh` และ `m_last_sl` เพื่อป้องกันการนับ BOS ซ้ำจาก Swing High/Low เดิม:
```
if (cur_high > sh_price AND sh_price != m_last_sh) → BOS_BULLISH
m_last_sh = sh_price  // บันทึก Swing High ที่ถูก break แล้ว
```

---

### 2.4 Entry Confluence — Triple Confirmation System

S03 จะสร้างสัญญาณเทรดก็ต่อเมื่อ **ทั้งสามเงื่อนไข** ผ่านพร้อมกัน:

**สำหรับ SIGNAL_BUY (Long):**
```
เงื่อนไขที่ 1: m_bos_dir == BOS_DIR_BULLISH        (ยืนยันทิศทางขาขึ้น)
เงื่อนไขที่ 2: price ∈ [ob.low, ob.high]           (ราคาอยู่ใน Demand OB)
            OR  price ∈ [fvg.bottom, fvg.top]       (ราคาอยู่ใน Bullish FVG)
เงื่อนไขที่ 3: confidence ≥ SMC_MinConfidence       (0.45 ค่าเริ่มต้น)

คำนวณ:
  SL = ob.low (หรือ fvg.bottom) - SL_ATRBuffer × ATR
  TP = entry_price + TP_ATRMult × ATR
```

**สำหรับ SIGNAL_SELL (Short):**
```
เงื่อนไขที่ 1: m_bos_dir == BOS_DIR_BEARISH        (ยืนยันทิศทางขาลง)
เงื่อนไขที่ 2: price ∈ [ob.low, ob.high]           (ราคาอยู่ใน Supply OB)
            OR  price ∈ [fvg.bottom, fvg.top]       (ราคาอยู่ใน Bearish FVG)
เงื่อนไขที่ 3: confidence ≥ SMC_MinConfidence

คำนวณ:
  SL = ob.high (หรือ fvg.top) + SL_ATRBuffer × ATR
  TP = entry_price - TP_ATRMult × ATR
```

**เหตุผลที่ต้องการ Triple Confluence (ไม่ใช่ OB อย่างเดียว):**

การใช้เพียง OB เพียงอย่างเดียวมี Win Rate ต่ำเพราะ:
- OB บางส่วนถูกสร้างโดยมือปลีก (False OB) ไม่ใช่สถาบัน
- ไม่มีการยืนยันทิศทาง → อาจเข้า trade สวนทิศทางหลัก
- ไม่มีการยืนยันโมเมนตัม → OB ที่ดีอาจเกิดในตลาด Ranging ซึ่ง SMC ทำงานไม่ดี

การเพิ่ม FVG ยืนยันว่า "ราคาเคลื่อนไหวอย่างมีพลังงาน" (Impulse Confirmed) และ BOS ยืนยันว่า "โครงสร้างตลาดเปลี่ยนทิศทางแล้ว" ทำให้ Triple Confluence ลด False Signal ได้อย่างมีประสิทธิภาพ

---

## 3. ตรรกะการให้คะแนนความเชื่อมั่น (Confidence Scoring)

ระบบใช้สูตรถ่วงน้ำหนักสามองค์ประกอบเพื่อคำนวณ Confidence Score สุดท้าย:

| Component | น้ำหนักสูงสุด | คำอธิบายรายละเอียด |
|-----------|--------------|---------------------|
| **OB Strength** | 0.50 | วัดแรงดันของสถาบันที่อยู่เบื้องหลัง Order Block ยิ่ง Impulse Move หลัง OB ใหญ่ ยิ่งมีความน่าเชื่อถือสูง |
| **FVG Ratio** | สูงสุด 0.30 | วัดขนาดของช่องว่างสภาพคล่องเมื่อเทียบกับ ATR ยิ่งช่องว่างใหญ่ ยิ่งมีแรงดึงดูดให้ราคากลับมาเติม |
| **BOS Bonus** | 0.20 | โบนัสคะแนนเต็มเมื่อ BOS ยืนยันทิศทางในแท่งล่าสุด ยืนยันว่าโครงสร้างตลาดสนับสนุนทิศทาง Trade |

**สูตรการคำนวณจริง (จากซอร์สโค้ด `_CalcConfidence()`):**

```
c = ob_strength × 0.5

c += min(0.30,  (fvg_ratio / 3.0) × 0.30)

if (m_bos_active):
    c += 0.20

confidence = min(1.0, c)
```

**ขยายความ FVG Component:**

FVG Contribution ถูก Cap ไว้ที่ 0.30 โดยสูตร `min(0.30, (fvg_ratio/3.0) × 0.30)`:
- fvg_ratio = 0.50 → contrib = min(0.30, 0.050) = 0.050
- fvg_ratio = 1.00 → contrib = min(0.30, 0.100) = 0.100
- fvg_ratio = 2.00 → contrib = min(0.30, 0.200) = 0.200
- fvg_ratio = 3.00 → contrib = min(0.30, 0.300) = 0.300 ← ถึง Cap
- fvg_ratio = 5.00 → contrib = min(0.30, 0.500) = 0.300 ← ยังคง Cap ที่ 0.30

การ Cap นี้ป้องกันการให้น้ำหนักกับ FVG มากเกินไป เพราะ FVG ขนาดใหญ่มากๆ บางครั้งเกิดจาก News Spike ที่ไม่ได้มี Pattern ที่น่าเชื่อถือ

**ขยายความ BOS Bonus:**

BOS Bonus คือ **0.20 คะแนนเต็ม** — ไม่มีค่ากลางๆ เพราะ BOS เป็น Binary Event (เกิดหรือไม่เกิด) การที่ระบบให้ 0.20 คะแนนกับ BOS สะท้อนความสำคัญของการยืนยันโครงสร้าง — ถ้าไม่มี BOS ค่า Confidence สูงสุดที่เป็นไปได้คือเพียง 0.80 ซึ่งแสดงว่าระบบต้องการ BOS เป็นองค์ประกอบสำคัญ

**ตัวอย่างสถานการณ์ Confidence:**

| สถานการณ์ | OB Str | FVG Ratio | BOS | Confidence | ผล |
|-----------|--------|-----------|-----|-----------|-----|
| อ่อน — ไม่มี BOS | 0.30 | 0.50 | ❌ | 0.150+0.050 = **0.200** | ❌ ต่ำกว่า 0.45 |
| ปานกลาง — มี BOS | 0.40 | 1.00 | ✅ | 0.200+0.100+0.200 = **0.500** | ✅ ผ่าน |
| ดี — FVG ใหญ่ | 0.60 | 2.00 | ✅ | 0.300+0.200+0.200 = **0.700** | ✅ ผ่านดี |
| ยอดเยี่ยม | 1.00 | 3.00+ | ✅ | 0.500+0.300+0.200 = **1.000** | ✅ ผ่านสูงสุด |
| มี OB แต่ไม่มี FVG | 0.80 | 0.00 | ✅ | 0.400+0.000+0.200 = **0.600** | ✅ ผ่าน (OB+BOS พอ) |

**จาก Case Study (ข้างต้น):**
- ob_strength=0.50, fvg_ratio=1.50, BOS active → Confidence = 0.250 + 0.150 + 0.200 = **0.600** ✅

---

## 4. โครงสร้างสถาปัตยกรรมระบบ (System Architecture)

S03 เป็น **Full MQL5 Strategy** ซึ่งแตกต่างจาก S01/S02 ที่เป็น Hybrid อย่างมีนัยสำคัญ:

```
┌─────────────────────────────────────────────────────────────────────┐
│  S03 — FULL MQL5 | การแบ่งหน้าที่ระหว่าง Python Brain และ MQL5    │
├──────────────────────────────────┬──────────────────────────────────┤
│  Python Brain (Server)           │  MQL5 Trader — CSMCV6           │
│  หน้าที่: Regime & Scoring       │  หน้าที่: Pattern Detection      │
├──────────────────────────────────┼──────────────────────────────────┤
│  • Regime Classification         │  • COrderBlockDetector.Scan()   │
│    (TRENDING/VOLATILE/RANGING)   │  • CFVGDetector.Scan()          │
│  • Confidence Scoring            │  • CBOSDetector.Detect()        │
│  • AI Council vote               │  • Triple Confluence check      │
│  • Parameter optimization        │  • _CalcConfidence()            │
│  • CONFIG_PUSH delivery          │  • Order placement              │
│  • Regime bonus adjustment       │  • SL/TP calculation            │
└──────────────────────────────────┴──────────────────────────────────┘
```

**ความแตกต่างสำคัญจาก S01/S02:**

| ด้าน | S01 (Stat Arb) | S02 (ML Ensemble) | S03 (SMC) |
|------|----------------|-------------------|-----------|
| สัญญาณ | Python คำนวณ | Python ML models | **MQL5 คำนวณ** |
| Python หน้าที่ | Beta, Cointegration | LSTM/RF/XGB | Regime เท่านั้น |
| Latency | สูง (Python round-trip) | สูงมาก (ML inference) | **ต่ำ (เฉพาะ Regime)** |
| Standalone | ✅ Yes | ❌ No | ❌ No |
| Pattern Detection | Server-side | Server-side | **Client-side (MQL5)** |

**เหตุผลที่ S03 ประมวลผล Pattern ใน MQL5:**

OB, FVG และ BOS เป็น Pattern ที่ต้องตรวจสอบบนแท่งเทียนทุกแท่ง (bar-by-bar) และต้อง Mark Zone เป็น Active/Inactive ในระดับ Tick ด้วย หากส่งข้อมูลทุก Tick ไปให้ Python คำนวณ จะเกิด Latency สูงและ ZMQ Overhead ไม่จำเป็น การคำนวณ Pattern ใน MQL5 โดยตรงจึงมีประสิทธิภาพกว่ามาก

---

## 5. โครงสร้างการไหลของข้อมูล (Full System Dataflow)

```
A: FeederEA (MQL5 Program)
   ├── รวบรวม OHLCV Data ทุกแท่ง
   ├── Pack ด้วย MessagePack Binary Protocol
   └── ส่งออก ZMQ PUB → Port 7777
                ↓
B: Python Brain — core/ingestion.py
   ├── รับข้อมูลจาก Port 7777 (ZMQ SUB)
   ├── Unpack MessagePack
   ├── บันทึกลง InfluxDB (time-series database)
   └── ส่งต่อ OHLCV ให้ Regime Classifier
                ↓
C: Python Brain — core/strategy/analysis.py
   ├── วิเคราะห์ Regime: TRENDING / VOLATILE / RANGING / SQUEEZE
   ├── คำนวณ Regime Score สำหรับ S03
   │   TRENDING  → bonus × 1.3  (สภาวะดีที่สุด)
   │   VOLATILE  → bonus × 1.2  (สภาวะดี)
   │   RANGING   → bonus × 0.4  (สภาวะแย่ — Score ต่ำมาก)
   └── ส่งผล Regime ให้ Policy Engine
                ↓
D: Python Brain — core/strategy/policy.py
   ├── AI Council: ถ่วงน้ำหนักด้วย hist_perf × regime_bonus
   ├── หาก weighted_conf ≥ 0.50 → อนุมัติ S03
   ├── Optimize Parameters (Lookback, OB Vol, FVG Size)
   └── สร้าง CONFIG_PUSH (type=10)
                ↓
E: ZMQ PUSH → Port 7778
   CONFIG_PUSH Array:
   [10, timestamp, symbol, "S03", entry, lot, max_orders,
    tp, sl, confidence, risk_mult]
   + SDynamicParams: SMC_LOOKBACK, SMC_MIN_OB_VOL, etc.
                ↓
F: MQL5 Trader — CSMCV6::SetDynamicParams()
   ├── รับ CONFIG_PUSH
   ├── อัพเดทพารามิเตอร์ (m_lookback, m_min_ob_vol, ...)
   ├── เรียก _SetupDetectors() — reconfigure ทั้งสาม detectors
   └── m_config.confidence ถูกตั้งค่า (> 0.01 → ServerOnly Guard ผ่าน)
                ↓
G: CSMCV6::Analyze() — ทุก Tick
   ├── ServerOnly Guard: if(m_config.confidence < 0.01) return
   ├── คำนวณ ATR 14 แท่ง
   ├── ตรวจสอบ New Bar:
   │   ├── COrderBlockDetector::Scan()   → สแกน 50 แท่ง หา OB
   │   ├── CFVGDetector::Scan()          → สแกน 50 แท่ง หา FVG
   │   └── CBOSDetector::Detect()        → หา Pivot High/Low + BOS
   ├── ทุก Tick:
   │   ├── COrderBlockDetector::MarkRetested(price)
   │   └── CFVGDetector::MarkFilled(price)
   ├── อ่าน BOS Direction:
   │   ├── BOS_DIR_BULLISH → _EvaluateLong(price)
   │   └── BOS_DIR_BEARISH → _EvaluateShort(price)
   └── หาก Signal ≠ NONE → ส่งสัญญาณให้ Order Manager
                ↓
H: Order Manager — เปิด Position
   ├── SIGNAL_BUY  → Buy Market Order
   ├── SL = ob/fvg edge - ATRBuffer × ATR
   ├── TP = entry + TPMult × ATR
   └── Magic Number = 1003 (MAGIC_S03_SMC)
                ↓
I: ZMQ PUSH → Port 7779
   TRADE_REPORT ส่งผล Trade กลับให้ Python Brain
   (กำไร/ขาดทุน, ราคาเปิด/ปิด, confidence ที่ใช้)
   → Python Brain ใช้ข้อมูลนี้ปรับ hist_perf ของ S03 ในรอบถัดไป
```

**ทำไม Scan() ทำงานเฉพาะ New Bar ไม่ใช่ทุก Tick?**

การสแกน 50 แท่งย้อนหลังทุก Tick จะสิ้นเปลือง CPU อย่างมาก (50 × 3 operations = 150 iterations ต่อ Tick) ระบบจึงใช้ `static datetime s_last_bar` เปรียบเทียบกับ `iTime(m_symbol, m_timeframe, 0)` เพื่อรัน Scan เฉพาะเมื่อเกิดแท่งใหม่ ในขณะที่ `MarkRetested()` และ `MarkFilled()` ยังคงทำงานทุก Tick เพราะต้องตรวจสอบการเข้า Zone แบบ Real-time

---

## 6. ตารางอ้างอิงพารามิเตอร์ (Parameter Reference)

| Parameter | Default | Range | คำอธิบายรายละเอียดเชิงลึก |
|-----------|---------|-------|---------------------------|
| `SMC_LookbackBars` | 50 | 20–200 | จำนวนแท่งย้อนหลังที่สแกนหา OB, FVG และ BOS ค่าต่ำ (20) = ตอบสนองต่อ Pattern ล่าสุดเท่านั้น เหมาะกับ Timeframe ต่ำ / ค่าสูง (200) = รวม Pattern ระยะยาวด้วย เหมาะกับ H4+ |
| `SMC_MinOBVolume` | 1.5 | 1.0–3.0 | ค่าตัวคูณ Volume ขั้นต่ำ OB Volume ต้องมากกว่าค่าเฉลี่ยอย่างน้อยเท่าตัวนี้ ค่า 1.0 = ยอมรับแท่งปริมาณปกติ (เพิ่ม Signal, เพิ่ม Noise) / ค่า 3.0 = เฉพาะแท่งปริมาณสูงมาก (Signal น้อยลงแต่คุณภาพสูง) |
| `SMC_MinFVGSize` | 0.5 | 0.2–2.0 | ขนาดขั้นต่ำของ FVG เมื่อเทียบกับ ATR ค่าน้อย (0.2) = ยอมรับ FVG เล็ก ซึ่งมักเกิดในตลาด Ranging / ค่ามาก (2.0) = เฉพาะ FVG ที่เกิดจาก Impulse Move ขนาดใหญ่จริงๆ |
| `SMC_SwingBars` | 5 | 3–10 | จำนวนแท่งแต่ละด้านในการพิจารณา Pivot High/Low ค่าน้อย (3) = Pivot เล็ก, BOS บ่อย / ค่ามาก (10) = Pivot ใหญ่, BOS นานๆ จะเกิด แต่มีความน่าเชื่อถือสูง |
| `SMC_SL_ATRBuffer` | 0.3 | 0.1–1.0 | ระยะห่างของ SL จากขอบ OB/FVG เป็นทวีคูณของ ATR ค่าน้อย (0.1) = SL แน่น, ถูก Stop Out ง่าย / ค่ามาก (1.0) = SL กว้าง, ลด R:R Ratio |
| `SMC_TP_ATRMult` | 2.0 | 1.5–5.0 | ระยะ Take Profit จาก Entry เป็นทวีคูณของ ATR ค่าต่ำ (1.5) = TP ใกล้, Win Rate สูงขึ้นแต่กำไรต่อไม้น้อย / ค่าสูง (5.0) = TP ไกล, กำไรต่อไม้สูงแต่ Hit Rate ต่ำลง |
| `SMC_MinConfidence` | 0.45 | 0.30–0.70 | คะแนน Confidence ขั้นต่ำในการสร้างสัญญาณ ค่าต่ำ (0.30) = Signal บ่อย, False Signal มาก / ค่าสูง (0.70) = Signal น้อยแต่คุณภาพสูง — Trade-off ระหว่าง Win Rate และ Frequency |

**CONFIG_PUSH Parameter Keys (ชื่อที่ใช้ใน Dynamic Params):**

| CONFIG_PUSH Key | MQL5 Parameter | หมายเหตุ |
|-----------------|---------------|---------|
| `SMC_LOOKBACK` | `SMC_LookbackBars` | int, ส่งเป็น double แล้ว cast กลับ |
| `SMC_MIN_OB_VOL` | `SMC_MinOBVolume` | double |
| `SMC_MIN_FVG_SIZE` | `SMC_MinFVGSize` | double |
| `SMC_SWING_BARS` | `SMC_SwingBars` | int, ส่งเป็น double แล้ว cast กลับ |
| `SMC_SL_ATR_BUFFER` | `SMC_SL_ATRBuffer` | double |
| `SMC_TP_ATR_MULT` | `SMC_TP_ATRMult` | double |
| `SMC_MIN_CONFIDENCE` | `SMC_MinConfidence` | double |

หลังจากรับ CONFIG_PUSH ระบบจะเรียก `_SetupDetectors()` อีกครั้งทันที เพื่อให้ทั้งสามตรวจจับใช้พารามิเตอร์ใหม่ — นี่คือกลไก **Hot-Reload** ที่ไม่ต้อง Restart EA

---

## 7. โหมดเดี่ยว vs โหมดเซิร์ฟเวอร์ (Standalone vs Server Mode)

### 7.1 โหมดเดี่ยว (Standalone Mode) — ไม่รองรับ

S03 **ไม่มี Standalone Mode** เนื่องจากการตัดสินใจที่ชัดเจนในการออกแบบ:

**เหตุผลที่ 1 — ServerOnly Guard:**
ในฟังก์ชัน `Analyze()` มี Guard ป้องกัน:
```mql5
if(m_config.confidence < 0.01) return;
```
ค่า `m_config.confidence` จะเป็น 0.0 จนกว่าจะได้รับ CONFIG_PUSH จาก Python Brain (Port 7778) ดังนั้น S03 จึง **ไม่สามารถสร้างสัญญาณใดๆ** หากไม่มีการเชื่อมต่อกับเซิร์ฟเวอร์

**เหตุผลที่ 2 — Regime Dependency:**
Pattern OB, FVG และ BOS เกิดขึ้นในทุก Regime รวมถึง RANGING ซึ่งเป็นสภาวะที่ SMC ทำงานแย่ที่สุด หากไม่มี Python Brain กรอง Regime ออก S03 จะสร้าง False Signal จำนวนมากในตลาด Ranging ระบบจึงต้องพึ่งพา Server-side Regime Filter เป็นกลไกป้องกันหลัก

**เหตุผลที่ 3 — Computational Load:**
การสแกน 50 แท่งสำหรับ OB + FVG + BOS ทุกแท่งมีภาระการคำนวณที่ไม่สมเหตุสมผลหากไม่มีการยืนยันจาก Server ว่าสภาวะตลาดเหมาะสม

### 7.2 โหมดเซิร์ฟเวอร์ (Server Mode) — การทำงานเต็มรูปแบบ

```
Python Brain
   ├── Regime: TRENDING หรือ VOLATILE
   ├── S03 Confidence Score:
   │   hist_perf × regime_bonus
   │   TRENDING  → regime_bonus = 1.30
   │   VOLATILE  → regime_bonus = 1.20
   │   RANGING   → regime_bonus = 0.40 (มักต่ำกว่า threshold)
   │
   ├── AI Council: weighted_conf ≥ 0.50?
   │   YES → อนุมัติ S03
   │
   ├── Parameter Optimization:
   │   Trending Market  → เพิ่ม SwingBars (5→7) หา Pivot ที่ใหญ่ขึ้น
   │                     เพิ่ม LookbackBars (50→80) รวม Pattern ระยะไกล
   │   Volatile Market  → ลด MinOBVolume (1.5→1.2) ยอมรับ OB ที่เล็กลง
   │                     เพิ่ม TP_ATRMult (2.0→3.0) เพราะ ATR สูง
   │
   └── CONFIG_PUSH → Port 7778 → CSMCV6::SetDynamicParams()
```

**ประโยชน์ของ Server Mode:**
- ป้องกันการเทรดใน RANGING (Regime Filter)
- ปรับพารามิเตอร์ให้เหมาะสมกับสภาวะตลาดปัจจุบัน (Dynamic Params)
- ใช้ประวัติประสิทธิภาพ (hist_perf) เพื่อปรับน้ำหนักของ S03 ใน Portfolio
- AI Council ช่วยลด Overtrading ในช่วงที่ Pattern คุณภาพต่ำ

---

## 8. ลำดับขั้นตอนการทำงานต่อหนึ่งแท่งเทียน (Step-by-Step Operational Flow)

ขั้นตอนที่แน่ชัดที่ระบบทำงานในทุกแท่งเทียนใหม่บน Timeframe ที่กำหนด:

**ขั้นที่ 1 — รับ CONFIG_PUSH (เกิดครั้งเดียวหรือทุก N วินาที):**
- Python Brain ส่ง CONFIG_PUSH (type=10) ผ่าน Port 7778
- `SetDynamicParams()` รับพารามิเตอร์ใหม่ และเรียก `_SetupDetectors()`
- `m_config.confidence` ถูกตั้งค่าเป็น > 0.01 → ServerOnly Guard ผ่าน

**ขั้นที่ 2 — New Bar Detection:**
- `Analyze()` เรียกทุก Tick
- เปรียบเทียบ `iTime(symbol, tf, 0)` กับ `s_last_bar`
- หากเกิดแท่งใหม่ → ดำเนินการขั้นที่ 3–5

**ขั้นที่ 3 — Triple Scan (เฉพาะ New Bar):**
```
COrderBlockDetector::Scan()
   ↳ สแกน m_lookback แท่ง (ค่าเริ่มต้น 50)
   ↳ คำนวณ AvgVolume และ ATR
   ↳ เก็บ OB ที่ผ่านเงื่อนไข (สูงสุด 10 โซน)

CFVGDetector::Scan()
   ↳ สแกน m_lookback แท่ง
   ↳ ค้นหา 3-Candle Imbalance ที่ขนาด ≥ MinFVGSize × ATR
   ↳ เก็บ FVG ที่ผ่านเงื่อนไข (สูงสุด 10 โซน)

CBOSDetector::Detect(m_lookback)
   ↳ ค้นหา Pivot High/Low ที่แท้จริงใน Lookback range
   ↳ เปรียบเทียบ High/Low ของ bar[1] กับ Swing High/Low
   ↳ อัพเดท m_bos_dir และ m_bos_active
```

**ขั้นที่ 4 — Zone Invalidation (ทุก Tick):**
```
MarkRetested(mid_price) → OB ที่ราคาเข้ามาใน Zone → is_active = false
MarkFilled(mid_price)   → FVG ที่ราคาข้ามจุด Midpoint → is_active = false
```

**ขั้นที่ 5 — Entry Evaluation (ทุก Tick):**
```
หาก BOS_DIR_BULLISH → _EvaluateLong(price)
   ├── หา Demand OB ที่ Active ใกล้ราคาที่สุด (เบื้องล่างราคาปัจจุบัน)
   ├── หา Bullish FVG ที่ Active ใกล้ราคาที่สุด
   ├── ตรวจสอบ: price ∈ OB zone หรือ price ∈ FVG zone?
   ├── คำนวณ _CalcConfidence(ob_str, fvg_ratio)
   ├── หาก conf ≥ MinConfidence → SIGNAL_BUY
   └── SL = ob/fvg edge - buffer×ATR, TP = entry + mult×ATR

หาก BOS_DIR_BEARISH → _EvaluateShort(price)
   └── (เหมือนกัน แต่ทิศทางตรงข้าม)
```

**ขั้นที่ 6 — Trade Report (Port 7779):**
- เมื่อออเดอร์ถูกเปิดหรือปิด
- EA ส่ง TRADE_REPORT กลับไปยัง Python Brain
- Brain อัพเดท `hist_perf[S03]` สำหรับรอบ AI Council ครั้งถัดไป

---

## 9. ลักษณะประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|------|-----------|
| **สภาวะตลาดที่ดีที่สุด** | ตลาด Trending ที่มีการ Impulse และ Pullback ชัดเจน เช่น ช่วง London/NY Session Open |
| **สภาวะตลาดที่แย่ที่สุด** | ตลาด Ranging แคบ (ATR ต่ำ, ไม่มี BOS ชัดเจน) เช่น Asian Session ที่เงียบ |
| **ความถี่สัญญาณ** | ต่ำ–ปานกลาง: 2–5 สัญญาณต่อวันในตลาด Trending |
| **Win Rate เป้าหมาย** | 55–65% (R:R สูงทดแทน Win Rate ที่ไม่สูงมาก) |
| **R:R Ratio** | TP 2.0 ATR / SL 0.3 ATR ≈ **6.7:1** (ต่อครั้งที่ SL/TP ถูก Touch) |
| **ประเภทสัญญาณ** | Bar-by-bar (Scan ทุกแท่ง) แต่ทดสอบ Zone ทุก Tick |
| **Magic Number** | 1003 |
| **ATR Period** | 14 แท่ง (ใช้ iATR indicator handle) |
| **OB Buffer** | สูงสุด 10 โซน (MAX_OB_ZONES) |
| **FVG Buffer** | สูงสุด 10 โซน (MAX_FVG_ZONES) |

**การคำนวณ R:R จริง (ตาม Case Study):**
- SL Distance = entry(1.0810) - SL(1.0789) = **21 pips**
- TP Distance = TP(1.0850) - entry(1.0810) = **40 pips**
- R:R = 40 / 21 ≈ **1.90:1**

หมายเหตุ: R:R ที่คำนวณด้านบน (6.7:1) เป็น Theoretical Maximum เมื่อ SL อยู่ที่ ATR × 0.3 พอดี ค่าจริงขึ้นอยู่กับตำแหน่งของ OB/FVG edge

---

## 10. ไฟล์อ้างอิง (Files Reference)

| ไฟล์ | บทบาท |
|------|--------|
| `Include/Logic/Strategies/S03_SMC.mqh` | คลาสหลัก CSMCV6 — ประสานงาน 3 Detectors |
| `Include/Logic/Strategies/SMC/OrderBlockDetector.mqh` | `COrderBlockDetector` — ตรวจจับ OB (Demand/Supply) |
| `Include/Logic/Strategies/SMC/FVGDetector.mqh` | `CFVGDetector` — ตรวจจับ Fair Value Gap |
| `Include/Logic/Strategies/SMC/BOSDetector.mqh` | `CBOSDetector` — ตรวจจับ Break of Structure |
| `02_Brain/strategies/s03_smc_analyzer.py` | Python Regime Scoring สำหรับ S03 |
| `Include/Logic/StrategyConstants.mqh` | ค่าคงที่: `S03_SMC` enum, `MAGIC_S03_SMC = 1003` |
| `Include/Network/Protocol/Definitions.mqh` | `SDynamicParams`, CONFIG_PUSH structure |

---

## 11. Quick Diagnostics

### ตรวจสอบว่า S03 Active
```
dashboard.py → Active Strategies → "S03" ปรากฏพร้อม confidence > 0.45
```

### อ่าน Diagnostic String จาก GetDiagnostics()
```
[S03] ATR:0.0020 OB:0.50 FVG:1.50 BOS:BULL Sig:BUY Conf:0.60
         ↑ATR         ↑OB Str  ↑FVG ratio ↑ทิศทาง ↑สัญญาณ ↑confidence
```

### Log ที่ควรเห็นใน MT5 Experts Tab
```
[S03] Init OK | EURUSD PERIOD_H1
[S03] BOS BULLISH: swing high broken at 1.08450
[S03] SIGNAL_BUY conf=0.600 entry=1.08100 sl=1.07890 tp=1.08500
```

### กรณี S03 ไม่สร้างสัญญาณ
```
สาเหตุที่ 1: m_config.confidence < 0.01 → ยังไม่ได้รับ CONFIG_PUSH
             แก้ไข: ตรวจสอบ Python Brain เชื่อมต่ออยู่ที่ Port 7778

สาเหตุที่ 2: Regime = RANGING → Brain ไม่ส่ง CONFIG_PUSH ให้ S03
             แก้ไข: รอสภาวะตลาดเปลี่ยน หรือตรวจสอบ dashboard.py Regime

สาเหตุที่ 3: ไม่มี BOS (m_bos_dir = BOS_DIR_NONE)
             แก้ไข: ลด SMC_SwingBars เพื่อให้ Pivot เล็กลง (BOS บ่อยขึ้น)

สาเหตุที่ 4: Confidence < MinConfidence
             แก้ไข: ลด SMC_MinOBVolume เพื่อยอมรับ OB ที่ Volume น้อยลง
                    หรือลด SMC_MinFVGSize เพื่อยอมรับ FVG ที่เล็กลง
```

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critiques & Optimizations)

**ข้อจำกัดที่ 1 — False OB ในตลาด Choppy:**
Order Block ที่ระบบตรวจจับได้ไม่ใช่ทุกตัวที่สร้างโดยสถาบัน แท่งเทียนที่มีปริมาณสูงอาจเกิดจากมือปลีกจำนวนมาก (Retail Cluster) ไม่ใช่สถาบัน วิธีบรรเทา: ใช้ Server-side Regime Filter เพื่อยืนยันว่าตลาดอยู่ใน TRENDING ก่อน และเพิ่ม `SMC_MinOBVolume` ขึ้น (เช่น 2.0) เพื่อกรองเฉพาะ OB ที่ปริมาณสูงมากจริงๆ

**ข้อจำกัดที่ 2 — BOS ที่เกิดจาก News Spike:**
ข่าวเศรษฐกิจสำคัญ (เช่น NFP, FOMC) อาจทำให้เกิด BOS พร้อม OB และ FVG ขนาดใหญ่อย่างเทียม Pattern เหล่านี้มักไม่เกิด Mean Reversion ปกติ แต่กลับ Run Away ต่อ วิธีบรรเทา: Python Brain ควรลด Regime Score ของ S03 ในช่วง High-Impact News เพื่อป้องกันการส่ง CONFIG_PUSH

**ข้อจำกัดที่ 3 — Fixed TP ด้วย ATR:**
TP ที่คำนวณเป็น `entry + TP_ATRMult × ATR` อาจพลาดจุด Swing High/Low สำคัญถัดไป ซึ่งเป็น TP Target ที่ "ธรรมชาติ" กว่า วิธีบรรเทา: ปรับ `SMC_TP_ATRMult` ตาม Regime — TRENDING อาจใช้ 3.0–4.0, VOLATILE อาจลดเหลือ 1.5

**ข้อจำกัดที่ 4 — OB Invalidation ใช้ Zone Touch (ไม่ใช่ Close):**
`MarkRetested()` จะ Mark OB เป็น Inactive เมื่อ Mid Price เข้า Zone ซึ่งอาจทำให้ OB ถูก Invalidate จาก Wick โดยไม่ได้รับ Fill ที่แท้จริง วิธีบรรเทา: พิจารณาเพิ่มเงื่อนไข "Close must enter OB zone" แทนเพียง Tick Price สำหรับ Invalidation

**แนวทางการ Tune พารามิเตอร์ตามสภาวะตลาด:**

| สภาวะ | SMC_LookbackBars | SMC_MinOBVolume | SMC_SwingBars | SMC_TP_ATRMult |
|--------|-----------------|-----------------|---------------|----------------|
| Strong Trend (TRENDING) | 80 | 2.0 | 7 | 3.0 |
| Volatile (VOLATILE) | 30 | 1.2 | 3 | 1.5 |
| Default | 50 | 1.5 | 5 | 2.0 |

---

*S03 SMC Manual — FlashEASuite V2 | Phase P9-5 | Jimmi Deep-Dive Edition | 2026-02-27*
