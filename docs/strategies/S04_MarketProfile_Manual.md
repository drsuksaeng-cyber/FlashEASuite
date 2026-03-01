# S04 — Market Profile + Order Flow
## FlashEASuite V2 | Strategy Deep Dive Manual
### Generated: P9-5 | 2026-02-27 | Jimmi Deep-Dive Edition

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S04 | รหัสอ้างอิงลำดับที่สี่ในระบบมัลติกลยุทธ์ FlashEASuite V2 เป็น Full MQL5 Strategy ตัวที่สองถัดจาก S03 (SMC) โดยเน้น Statistical Volume Distribution แทนการวิเคราะห์ Candlestick Pattern |
| **ชื่อ** | Market Profile + Order Flow | Market Profile คือวิธีการนำเสนอข้อมูลการซื้อขายในรูปแบบ Histogram แนวตั้งที่แสดงปริมาณ Tick Volume ในแต่ละระดับราคา ซึ่งแต่เดิมพัฒนาโดย J. Peter Steidlmayer แห่ง Chicago Board of Trade (CBOT) |
| **ประเภท** | Full MQL5 | การสร้าง Volume Profile, การคำนวณ POC/VAH/VAL, และการตัดสินใจเข้า Trade ทั้งหมดเกิดขึ้นใน MQL5 โดยตรง Python Brain ทำหน้าที่ Regime Scoring และ Parameter Optimization เท่านั้น |
| **Standalone Capable** | ❌ No (Server Only) | ต้องการ CONFIG_PUSH จาก Python Brain ก่อนทำงาน เนื่องจากระบบออกแบบให้ต้องมีการยืนยัน Regime (RANGING หรือ TRENDING ต้น) ก่อนจึงจะ Enable |
| **Preferred Regime** | RANGING, early TRENDING | ตลาด RANGING มีลักษณะการซื้อขายที่ "วนเวียน" อยู่ในบริเวณ Value Area อย่างสม่ำเสมอ ทำให้ระบบ Mean Reversion ทำงานได้แม่นยำ / TRENDING ระยะต้นยังมี Value Area ที่ชัดเจนก่อนที่ราคาจะ Breakout อย่างเต็มรูปแบบ |
| **Poor Regimes** | VOLATILE, extreme TRENDING | ใน VOLATILE ราคาเคลื่อนไหวรุนแรงจน POC เปลี่ยนตำแหน่งอย่างรวดเร็ว ทำให้ Value Area ที่คำนวณได้ Lag ไม่ทันกับความเป็นจริง / TRENDING รุนแรงทำให้ราคาออกนอก Value Area ถาวร ไม่ Revert กลับ |
| **MQL5 Class** | `CMarketProfile` | คลาสหลักที่ประสานงาน `CVolumeProfileBuilder` และ `CPOCCalculator` พร้อมตรรกะการกรองด้วย Session Factor และ Volume Filter |
| **Sub-Components** | `CVolumeProfileBuilder`, `CPOCCalculator` | สองคลาสย่อยที่ทำงานเป็น Pipeline: Builder สร้าง Histogram → Calculator คำนวณ POC/VAH/VAL และ Secondary Nodes |

### สรุปแนวคิด (Summary of Concepts)

S04 เป็นกลยุทธ์ที่ตั้งอยู่บนหลักการ **Market Profile** — วิธีการวิเคราะห์ตลาดที่มองว่าราคาในแต่ละช่วงเวลาหนึ่งจะ "รวมตัว" อยู่ในบริเวณที่มีการซื้อขายมากที่สุด เรียกว่า **Value Area** ซึ่งครอบคลุม 70% ของปริมาณการซื้อขายทั้งหมดในช่วงนั้น

แกนกลางของระบบคือ **3 ระดับราคาสำคัญ:**
- **(1) POC (Point of Control)** — ระดับราคาที่มีปริมาณการซื้อขายสูงที่สุด คือ "ราคากลาง" ที่ตลาดเห็นว่าเป็นธรรมที่สุด (Fair Price)
- **(2) VAH (Value Area High)** — ขอบบนของ Value Area คือ "เพดานราคาที่ยุติธรรม" เมื่อราคาพุ่งสูงกว่านี้ ถือว่า "แพงเกินไป"
- **(3) VAL (Value Area Low)** — ขอบล่างของ Value Area คือ "พื้นราคาที่ยุติธรรม" เมื่อราคาตกต่ำกว่านี้ ถือว่า "ถูกเกินไป"

กลยุทธ์การเทรดของ S04 คือ **Mean Reversion กลับสู่ Value Area**: เข้า Long เมื่อราคาต่ำกว่า VAL (ตลาดมองว่า "ถูกเกินไป") และเข้า Short เมื่อราคาสูงกว่า VAH (ตลาดมองว่า "แพงเกินไป") โดยคาดว่าราคาจะวิ่งกลับเข้าสู่ Value Area และไปถึง POC

---

### ทำไมต้องชื่อ "Market Profile"?

**ต้นกำเนิดจาก Chicago Board of Trade (CBOT):**

Market Profile ถูกคิดค้นโดย **J. Peter Steidlmayer** นักเทรดใน CBOT ในทศวรรษ 1980s เขาสังเกตว่าราคาสินค้าโภคภัณฑ์ในตลาดซื้อขายล่วงหน้า (Futures) ไม่ได้เคลื่อนไหวแบบสุ่ม แต่มีโครงสร้างที่ชัดเจน — ราคามักจะ "ใช้เวลา" อยู่ในบริเวณที่มีการซื้อขายมากที่สุด และเคลื่อนออกนอกบริเวณนั้นอย่างรวดเร็วเมื่อตลาดเปลี่ยนทิศ

คำว่า **"Profile"** (ภาพตัดขวาง) มาจากการที่ Histogram ที่แสดงปริมาณ ณ แต่ละระดับราคา มีลักษณะคล้ายกับ "ภาพตัดขวาง" ของพฤติกรรมการซื้อขาย ซึ่งมักมีรูปร่างคล้าย **Bell Curve (โค้งระฆังคว่ำ)** โดยมีบริเวณที่ "อ้วนที่สุด" (ปริมาณสูงสุด) อยู่กลาง คือ POC

**ทำไมต้องใช้ Tick Volume ไม่ใช่ Real Volume?**

ในตลาด Forex ที่ไม่มีตลาดกลาง (OTC — Over the Counter) ไม่มี "ปริมาณการซื้อขายจริง" ที่สามารถรวบรวมได้ครบถ้วน เราจึงใช้ **Tick Volume** (จำนวนครั้งที่ราคาเปลี่ยนแปลง) เป็นตัวแทนของ Activity ในตลาด ซึ่งงานวิจัยหลายชิ้นยืนยันว่า Tick Volume มี Correlation สูงกับ Real Volume ใน Futures ในช่วงเวลาเดียวกัน

---

### ธรรมชาติของ Value Area (หลักการ 70% Rule)

หัวใจของ Market Profile Theory คือ **กฎ 70%** ซึ่งระบุว่า:

**"ในวันซื้อขายปกติ (Normal Distribution Day) ราคาจะใช้เวลา 70% ของ Session อยู่ภายใน Value Area และมีแนวโน้มจะกลับเข้า Value Area เมื่อออกมาข้างนอก"**

หลักการนี้อิงจากการกระจายตัวแบบ Normal Distribution (Bell Curve) ซึ่งบริเวณ ±1 Standard Deviation ครอบคลุม 68.27% ของข้อมูล — ค่า 70% ใน Market Profile จึงเป็นการประมาณค่าของ ±1 Standard Deviation นั่นเอง

**ทำไมราคาจึงวนอยู่ใน Value Area:**

เมื่อราคาพุ่งขึ้นสูงกว่า VAH จะมีแรงขายจาก:
- ผู้ถือครองสินทรัพย์ที่ต้องการ Realize Profit
- Algo Traders ที่ตั้ง Sell Limit ไว้ที่ระดับนี้
- Market Makers ที่ Hedge ตำแหน่งของตัวเอง

และเมื่อราคาตกต่ำกว่า VAL จะมีแรงซื้อจาก:
- Long-term Investors ที่รอซื้อในราคาต่ำกว่า Fair Value
- Algo Traders ที่ตั้ง Buy Limit ไว้
- ผู้ที่ Short อยู่ที่ต้องการ Take Profit

แรงเหล่านี้รวมกันสร้าง **Mean Reversion Force** ที่ดึงราคากลับสู่ Value Area อยู่เสมอ — จนกว่าจะมีข้อมูลใหม่ (News, ข้อมูลเศรษฐกิจ) ที่เปลี่ยน Fair Value Consensus ของตลาด

---

### ตัวอย่างเหตุการณ์จริง (Case Study)

สมมติเหตุการณ์ ณ วันที่ 27 กุมภาพันธ์ 2026 บนกราฟ EURUSD M15:

**ขั้นที่ 1 — สร้าง Volume Profile (96 แท่ง = 24 ชั่วโมงล่าสุด):**

```
ช่วงราคา 24 ชั่วโมงล่าสุด: Low=1.0783 — High=1.0858
Range = 0.0075 | Bins = 50 | bin_size = 0.0075 / 50 = 0.000150 ต่อ bin
Total Tick Volume สะสม: 185,000 ticks
```

หลังจาก `CVolumeProfileBuilder.Build()` สร้าง Histogram เสร็จ:
```
ปริมาณสูงสุดอยู่ที่ bin กลาง (bin 18 จาก 0-49):
  bin_price = 1.0783 + (18 + 0.5) × 0.000150 = 1.0783 + 0.002775 = 1.0811
  Volume = 14,200 ticks ← POC bin
```

**ขั้นที่ 2 — คำนวณ POC, VAH, VAL (70% Value Area):**
```
POC = 1.0811  (bin 18 — ราคาที่ตลาดซื้อขายมากที่สุด)
target_70% = 185,000 × 0.70 = 129,500 ticks

Greedy Expansion จาก POC bin 18 ออกทั้งสองด้าน:
  lo = 8  (lower boundary bin)
  hi = 28 (upper boundary bin)
  Accumulated Volume = 131,200 ticks ≥ 129,500 ✅

VAL = GetBinPrice(8) - bin_size/2 = 1.0783 + 8.5×0.000150 - 0.000075 = 1.0803
VAH = GetBinPrice(28) + bin_size/2 = 1.0783 + 28.5×0.000150 + 0.000075 = 1.0845
```

**ขั้นที่ 3 — Secondary Volume Nodes (Top 5):**
```
Node 1: 1.0811 (POC)          14,200 ticks
Node 2: 1.0815                12,800 ticks  ← nearest node above VAL
Node 3: 1.0808                11,400 ticks
Node 4: 1.0828                 9,600 ticks
Node 5: 1.0838                 8,200 ticks
```

**ขั้นที่ 4 — Entry Signal ที่เวลา 08:15 UTC (London Open):**
```
ราคาปัจจุบัน (bid): 1.0797 < VAL = 1.0803 ✅  (ออกนอก Value Area ด้านล่าง)
ATR(14)            : 0.0014 (14 pips)
Vol_MA(SMA 20)     : 920 ticks/bar
Current bar volume : 2,350 ticks

Volume Filter: 2,350 ≥ 1.2 × 920 = 1,104 ✅  (London Open มีกิจกรรมสูง)
Range Filter  : 1.0797 ≥ VAL - 2×ATR = 1.0803 - 0.0028 = 1.0775 ✅

→ SIGNAL_BUY เปิดใช้งาน
```

**ขั้นที่ 5 — การคำนวณ Confidence:**
```
Volume Imbalance  = min((2350/920) / 3.0, 1.0) = min(0.851, 1.0) = 0.851
POC Proximity     = 1.0 - min(|1.0797 - 1.0811| / (2 × 0.0014), 1.0)
                  = 1.0 - min(0.0014 / 0.0028, 1.0)
                  = 1.0 - 0.500 = 0.500
Session Factor    = 1.0  (London Open: 07-09 UTC)

Confidence = 0.851 × (0.4 + 0.4 × 0.500) × 1.0
           = 0.851 × (0.4 + 0.200)
           = 0.851 × 0.600 = 0.511
```

**ขั้นที่ 6 — การวางออเดอร์:**
```
Entry Price: 1.0797
SL = POC - SL_ATR_Mult × ATR = 1.0811 - 1.5 × 0.0014 = 1.0811 - 0.0021 = 1.0790
TP = GetNearestNodeAbove(VAL=1.0803) = 1.0815 (Node 2)

SL Distance = 1.0797 - 1.0790 = 7 pips
TP Distance = 1.0815 - 1.0797 = 18 pips
R:R Ratio   = 18 / 7 ≈ 2.57:1
```

**ผลลัพธ์:** ราคา Revert กลับเข้า Value Area ตามคาด แตะ Node 2 ที่ 1.0815 ใน 45 นาที

---

### เหตุผลที่ราคาต้องวิ่งไปหา POC เสมอ

**หลักการ Price Acceptance vs Price Rejection:**

Market Profile Theory แบ่งการเคลื่อนไหวของราคาออกเป็นสองโหมด:

**Price Acceptance** (ราคาได้รับการยอมรับ): เมื่อราคาเคลื่อนไหวไปในบริเวณที่มีปริมาณการซื้อขายสูง หมายความว่าทั้งผู้ซื้อและผู้ขายยอมรับระดับราคานั้น ราคาจะ "นิ่ง" อยู่ในบริเวณนั้น ซึ่งก็คือ Value Area นั่นเอง

**Price Rejection** (ราคาถูกปฏิเสธ): เมื่อราคาเคลื่อนออกนอก Value Area ไปในบริเวณที่มีปริมาณการซื้อขายต่ำ (เช่น เหนือ VAH หรือต่ำกว่า VAL) ฝ่ายใดฝ่ายหนึ่งจะปฏิเสธระดับราคานั้น (ผู้ซื้อคิดว่าแพงเกินไป / ผู้ขายคิดว่าถูกเกินไป) ราคาจึงวิ่งกลับเข้า Value Area อย่างรวดเร็ว

**POC คือ "จุดแรงโน้มถ่วง" ของตลาด:**

ทฤษฎี Market Profile อธิบายว่า POC คือราคาที่ตลาดมีความเห็นตรงกันมากที่สุดว่า "Fair" จึงทำหน้าที่เหมือน Gravitational Center ที่ดึงดูดราคาให้กลับมาหาอยู่เสมอ ไม่ว่าราคาจะวิ่งไปทางไหนชั่วคราว ก็มีแนวโน้มที่จะ Test POC อีกครั้งก่อนตัดสินใจทิศทางต่อไป

---

## 2. ทฤษฎีหลัก (Core Theory)

### 2.1 Volume Profile Construction — กลไก CVolumeProfileBuilder

**วิธีการกระจาย Volume ลง Bins (Proportional Distribution):**

ระบบไม่ได้ใส่ Volume ทั้งก้อนลงใน Bin เดียว แต่กระจายตามสัดส่วนที่แท่งเทียนแต่ละแท่งทับซ้อนกับแต่ละ Bin:

```
สำหรับแท่งเทียนแต่ละแท่ง b (จาก bar[1] ถึง bar[lookback]):

  bar_low  = Low[b]
  bar_high = High[b]
  bar_vol  = TickVolume[b]
  bar_range = bar_high - bar_low

  bin_start = floor((bar_low  - period_low) / bin_size)
  bin_end   = floor((bar_high - period_low) / bin_size)

  สำหรับแต่ละ bin i ระหว่าง bin_start ถึง bin_end:
    bin_lo = period_low + i × bin_size
    bin_hi = bin_lo + bin_size

    overlap = max(0, min(bar_high, bin_hi) - max(bar_low, bin_lo))
    fraction = overlap / bar_range

    bin_volume[i] += bar_vol × fraction
```

**ตัวอย่างการกระจาย Volume:**

แท่งเทียน EURUSD M15 ที่ low=1.0800, high=1.0815, TickVolume=1,200, bin_size=0.0005:
```
Bin 0: [1.0800, 1.0805] → overlap = 0.0005, fraction = 0.0005/0.0015 = 0.333
Bin 1: [1.0805, 1.0810] → overlap = 0.0005, fraction = 0.333
Bin 2: [1.0810, 1.0815] → overlap = 0.0005, fraction = 0.333

bin_volume[0] += 1,200 × 0.333 = 400 ticks
bin_volume[1] += 1,200 × 0.333 = 400 ticks
bin_volume[2] += 1,200 × 0.333 = 400 ticks
```

**ทำไมใช้ Proportional Distribution ไม่ใช่ Close-Based:**

วิธี Proportional Distribution จัดสรร Volume ตามช่วงราคาที่แท่งเทียนเคลื่อนที่ผ่านจริงๆ ซึ่งสมมติฐานคือ "Volume ถูกกระจายอย่างสม่ำเสมอตลอด High-Low Range ของแท่ง" แม้จะไม่แม่นยำ 100% แต่ดีกว่าการใส่ Volume ทั้งหมดที่ Close Price เพราะแสดงให้เห็นว่าราคาเคลื่อนผ่านบริเวณใดบ้างในระหว่างการซื้อขาย

**ข้อจำกัด MAX_OB_BINS = 100:**

ระบบรองรับสูงสุด 100 Bins (แม้ default จะตั้งที่ 50) การตั้ง Bins มากขึ้นให้ความละเอียดสูงขึ้น แต่ใช้ Memory และเวลาคำนวณมากขึ้น: O(bins × lookback)

---

### 2.2 POC, VAH, VAL Calculation — กลไก CPOCCalculator

**ขั้นที่ 1 — หา POC (Point of Control):**
```
POC_bin   = bin ที่มี bin_volume[] สูงสุด
POC_price = period_low + (POC_bin + 0.5) × bin_size  [จุดกึ่งกลาง bin]
```
ราคา POC เป็น "กลาง" ของ bin ไม่ใช่ขอบ bin เพราะ bin แต่ละช่องแทนช่วงราคา — การใช้จุดกึ่งกลางให้ค่าที่แม่นยำกว่า

**ขั้นที่ 2 — หา Secondary Volume Nodes (Top 5):**

ระบบระบุ 5 Bin ที่มี Volume สูงสุดรองจาก POC เพื่อใช้เป็น Target TP:
```
วิธี: Selection Sort 5 รอบ
รอบที่ 1: หา bin ที่มี Volume สูงสุด (= POC) → บันทึก → ตัดออก
รอบที่ 2: หา bin ที่มี Volume สูงสุดที่เหลือ → บันทึก → ตัดออก
... (จนครบ 5 หรือหมด bins)
```

**ขั้นที่ 3 — หา Value Area (70%) ด้วย Greedy Algorithm:**

```
เริ่มต้น:
  lo = hi = POC_bin
  accum = volume[POC_bin]
  target = total_volume × 0.70

วนซ้ำจนกว่า accum ≥ target:
  vol_up   = volume[hi + 1]  (bin ถัดขึ้นไป)
  vol_down = volume[lo - 1]  (bin ถัดลงมา)

  ถ้า vol_up ≥ vol_down → hi++, accum += vol_up   (ขยายขึ้น)
  ถ้า vol_down > vol_up → lo--, accum += vol_down  (ขยายลง)

VAL = GetBinPrice(lo) - bin_size/2   [ขอบล่างของ bin ล่างสุด]
VAH = GetBinPrice(hi) + bin_size/2   [ขอบบนของ bin บนสุด]
```

**ทำไมใช้ Greedy ไม่ใช่ Symmetric Expansion?**

Greedy Algorithm เลือก "ด้านที่มี Volume สูงกว่า" ก่อนในทุกขั้น ทำให้ Value Area ขยายตัวไปทางที่ตลาดซื้อขายจริงมากกว่า ต่างจาก Symmetric Expansion ที่ขยายทั้งสองด้านเท่ากันซึ่งอาจรวม Bins ที่มี Volume ต่ำมาก

**ตัวอย่างการทำงาน Greedy (ขนาดเล็กสำหรับความชัดเจน):**
```
Bins: [vol=100, vol=200, vol=800(POC), vol=600, vol=150]
       bin 0     bin 1     bin 2        bin 3    bin 4
total = 1,850 | target_70% = 1,295

รอบ 1: lo=hi=2, accum=800
  vol_up=600 (bin3), vol_down=200 (bin1)
  600 > 200 → hi=3, accum=1400 ≥ 1295 ✓ หยุด

VAL = GetBinPrice(2) - bin_size/2   = ขอบล่าง bin 2
VAH = GetBinPrice(3) + bin_size/2   = ขอบบน bin 3
```

**การคำนวณ POC Proximity:**
```
GetPOCProximity(price, atr):
  dist = |price - POC_price|
  proximity = 1.0 - min(dist / (2 × ATR), 1.0)

  dist = 0.0 → proximity = 1.0   (ราคาอยู่ที่ POC พอดี)
  dist = ATR  → proximity = 0.5  (ราคาห่าง POC หนึ่ง ATR)
  dist ≥ 2×ATR → proximity = 0.0 (ราคาไกลมาก)
```

---

### 2.3 Session Factor — การถ่วงน้ำหนักตามเวลาซื้อขาย

ระบบให้น้ำหนักความน่าเชื่อถือของสัญญาณตามเวลาที่เกิดขึ้น (UTC):

```
ช่วงเวลา (UTC)     Session                    Session Factor
07:00 – 09:00    London Open                   1.0 ← สูงสุด
12:00 – 16:00    London/NY Overlap             1.0 ← สูงสุด
09:00 – 12:00    London Active                 0.8
16:00 – 20:00    NY Active                     0.8
00:00 – 02:00    Late NY / Pre-Asia Crossover  0.6 ← ต่ำสุด
20:00 – 24:00    NY Close / Asia Pre           0.6
02:00 – 07:00    Asian Main Session            0.8
```

**เหตุผลที่ London Open และ Overlap ได้ Factor 1.0:**

ช่วง London Open (07:00–09:00 UTC) เป็นช่วงที่ Market Makers ของยุโรปเปิดบัญชี การที่ราคาออกนอก Value Area ในช่วงนี้มักเป็นสัญญาณ "การทดสอบสภาพคล่อง" ก่อนที่ราคาจะ Revert กลับเมื่อ Market Makers เข้ามา Absorb ออเดอร์

ช่วง London/NY Overlap (12:00–16:00 UTC) คือช่วงที่ Volume สูงสุดของวัน การเคลื่อนไหวของราคาในช่วงนี้มีความน่าเชื่อถือสูงสุดเพราะมีผู้ร่วมตลาดจำนวนมากที่สุด

**เหตุผลที่ Asian Session ได้ Factor ต่ำกว่า:**

Asian Session (โดยเฉพาะ Forex หลัก เช่น EURUSD, GBPUSD) มี Volume ต่ำ การออกนอก Value Area ในช่วงนี้อาจเป็นเพียง "Noise" ที่เกิดจาก Liquidity ต่ำ ไม่ใช่ Rejection จริงๆ

---

### 2.4 เงื่อนไขการเข้า Trade (Entry Confluence)

**สำหรับ SIGNAL_BUY (Long — Price Below VAL):**
```
เงื่อนไขที่ 1: bid_price < VAL
               (ราคาตกออกนอก Value Area ด้านล่าง — "ถูกเกินไป")

เงื่อนไขที่ 2: m_last_vol ≥ m_vol_mult × m_last_vol_ma
               (Volume ปัจจุบัน ≥ 1.2 × Volume MA — มีกิจกรรมสูง)

เงื่อนไขที่ 3: bid_price ≥ VAL - 2.0 × ATR
               (ไม่ห่างจาก VAL มากเกินไป — ไม่ Overextended)

SL = POC - SL_ATR_Mult × ATR   (SL อยู่ต่ำกว่า POC)
TP = GetNearestNodeAbove(VAL)   (Volume Node ถัดไปเหนือ VAL หรือ POC)
```

**สำหรับ SIGNAL_SELL (Short — Price Above VAH):**
```
เงื่อนไขที่ 1: bid_price > VAH
               (ราคาพุ่งออกนอก Value Area ด้านบน — "แพงเกินไป")

เงื่อนไขที่ 2: m_last_vol ≥ m_vol_mult × m_last_vol_ma

เงื่อนไขที่ 3: bid_price ≤ VAH + 2.0 × ATR

SL = POC + SL_ATR_Mult × ATR   (SL อยู่สูงกว่า POC)
TP = GetNearestNodeBelow(VAH)   (Volume Node ถัดไปใต้ VAH หรือ POC)
```

**ทำไมต้องมีเงื่อนไขที่ 3 (2×ATR Filter)?**

หากราคาวิ่งออกนอก Value Area ไกลเกินไป (เกิน 2×ATR จาก VAL/VAH) อาจหมายความว่า:
- กำลังเกิด **Trend Extension** ที่ไม่ใช่ Mean Reversion
- อาจเกิดข่าวสำคัญที่เปลี่ยน Fair Value Consensus
- Value Area เดิมอาจไม่ Valid อีกต่อไป

การ Reject สัญญาณเหล่านี้ช่วยลด False Signal ในสภาวะที่ Breakout จริง

---

## 3. ตรรกะการให้คะแนนความเชื่อมั่น (Confidence Scoring)

ระบบใช้สูตรคูณสามปัจจัยที่แตกต่างจาก S03 (ที่ใช้การบวก):

| Component | บทบาท | ช่วงค่า | คำอธิบาย |
|-----------|--------|---------|----------|
| **Volume Imbalance** | ตัวคูณหลัก | 0.0–1.0 | วัดความ "ผิดปกติ" ของ Volume ณ ขณะนั้น ยิ่งสูง = ตลาดกำลัง Active มาก = สัญญาณน่าเชื่อถือ |
| **POC Proximity** | Weight ภายใน | 0.0–1.0 | วัดว่าราคาใกล้ POC มากแค่ไหน ยิ่งใกล้ = แรงดึงดูดกลับสูง = โอกาสสำเร็จสูง |
| **Session Factor** | ตัวคูณนอก | 0.6–1.0 | ถ่วงน้ำหนักตามช่วงเวลา London/Overlap ให้ค่าเต็ม Asian ให้ค่าต่ำ |

**สูตรการคำนวณจริง (จากซอร์สโค้ด `_ComputeConfidence()`):**

```
Volume Imbalance:
  ratio     = m_last_vol / m_last_vol_ma
  imbalance = min(ratio / 3.0, 1.0)

POC Proximity:
  dist      = |bid_price - POC_price|
  proximity = 1.0 - min(dist / (2 × ATR), 1.0)

Confidence:
  conf = imbalance × (0.4 + 0.4 × proximity) × session_factor
  conf = min(max(conf, 0.0), 1.0)
```

**หมายเหตุสำคัญ:** สูตรนี้เป็นแบบ **Multiplicative** ต่างจากสูตรที่แสดงในเวอร์ชันแรกของ Manual (ที่เป็น Additive: `vol×0.4 + prox×0.4 + session×0.2`) ผลจากโค้ดจริงคือ:
- ค่าสูงสุดที่เป็นไปได้ = 1.0 × (0.4 + 0.4) × 1.0 = **0.80** (ไม่ใช่ 1.0)
- ถ้าไม่มี Volume เลย (imbalance=0) → conf = 0 เสมอ ไม่ว่า proximity จะเท่าไร

**ตารางสถานการณ์ Confidence:**

| สถานการณ์ | Vol Ratio | Imbalance | Proximity | Session | Confidence |
|-----------|-----------|-----------|-----------|---------|------------|
| Vol ต่ำ, Asian | 1.1 | 0.367 | 0.50 | 0.8 | 0.367×0.60×0.8 = **0.176** |
| Vol ปานกลาง, London | 1.5 | 0.500 | 0.50 | 1.0 | 0.500×0.60×1.0 = **0.300** |
| Vol สูง, London Open | 2.5 | 0.833 | 0.50 | 1.0 | 0.833×0.60×1.0 = **0.500** |
| Vol สูง + ใกล้ POC | 3.0 | 1.000 | 0.70 | 1.0 | 1.000×0.68×1.0 = **0.680** |
| ดีที่สุด (ทุกอย่างสูง) | 3.0+ | 1.000 | 1.00 | 1.0 | 1.000×0.80×1.0 = **0.800** |

**จาก Case Study (ข้างต้น):**
`imbalance=0.851, proximity=0.500, session=1.0`
`conf = 0.851 × 0.600 × 1.0 = 0.511`

**ข้อสังเกต:** Confidence สูงที่สุดเกิดเมื่อ POC อยู่ใกล้ VAL/VAH ซึ่งหมายความว่า Profile มีลักษณะ **Bimodal** หรือ **POC อยู่ชิดขอบ Value Area** ในกรณีนี้ เมื่อราคาออกนอก VAL ก็ยังใกล้ POC อยู่ ทำให้ proximity สูงพร้อมกัน

---

## 4. โครงสร้างสถาปัตยกรรมระบบ (System Architecture)

S04 เป็น **Full MQL5 Strategy** เช่นเดียวกับ S03 โดยแบ่งหน้าที่ชัดเจน:

```
┌───────────────────────────────────────────────────────────────────────┐
│  S04 — FULL MQL5 | การแบ่งหน้าที่ระหว่าง Python Brain และ MQL5      │
├────────────────────────────┬──────────────────────────────────────────┤
│  Python Brain (Server)     │  MQL5 Trader — CMarketProfile           │
│  หน้าที่: Regime & Params  │  หน้าที่: Profile Construction          │
├────────────────────────────┼──────────────────────────────────────────┤
│  • Regime Classification   │  • CVolumeProfileBuilder.Build()        │
│    (RANGING/TRENDING)      │    50 bins × 96 bars OHLCV              │
│  • Confidence Scoring      │  • CPOCCalculator.Calculate()           │
│  • AI Council vote         │    POC, VAH, VAL + Secondary Nodes      │
│  • Parameter optimization  │  • _SessionFactor() time weighting      │
│  • CONFIG_PUSH delivery    │  • _VolumeImbalance() Vol/MA ratio      │
│                            │  • Entry gating (price, vol, distance)  │
│                            │  • GetSL() / GetTP() calculation        │
└────────────────────────────┴──────────────────────────────────────────┘
```

**Pipeline ภายใน (เรียกทุก N Tick):**
```
CVolumeProfileBuilder.Setup() → Build()
         ↓
CPOCCalculator.Setup() → Calculate(vp_builder)
         ↓
m_poc = GetPOC()
m_vah = GetVAH()
m_val = GetVAL()
         ↓
_ReadIndicators()  → m_last_atr, m_last_vol, m_last_vol_ma
         ↓
Entry check (price vs VAL/VAH + vol_ok + range_ok)
         ↓
_ComputeConfidence(price)  → Confidence Score
```

**ประเภทของ Indicators ที่ใช้:**

| Indicator | Handle | วัตถุประสงค์ |
|-----------|--------|-------------|
| `iATR(symbol, tf, 14)` | m_atr_handle | วัด Volatility สำหรับ SL calculation และ Range Filter |
| `iMA(symbol, tf, 20, SMA, PRICE_CLOSE)` | m_vol_ma_handle | ประมาณค่า Volume MA (Proxy — ดูหมายเหตุ) |

**หมายเหตุ Volume MA:** ในโค้ดปัจจุบัน `m_vol_ma_handle` ใช้ `iMA` บน `PRICE_CLOSE` เป็น Proxy สำหรับ Volume MA ไม่ใช่ MA ของ Tick Volume โดยตรง นี่เป็น Implementation Note ที่บันทึกไว้ใน Comment: _"Production note: replace with proper volume MA if CopyTickVolume used in loop"_

---

## 5. โครงสร้างการไหลของข้อมูล (Full System Dataflow)

```
A: FeederEA (MQL5 Program)
   ├── รวบรวม OHLCV Data + Tick Volume ทุกแท่ง
   ├── Pack ด้วย MessagePack Binary Protocol
   └── ส่งออก ZMQ PUB → Port 7777
                ↓
B: Python Brain — core/ingestion.py
   ├── รับข้อมูลจาก Port 7777 (ZMQ SUB)
   ├── Unpack MessagePack
   ├── บันทึกลง InfluxDB (time-series database)
   └── ส่งต่อให้ Regime Classifier
                ↓
C: Python Brain — core/strategy/analysis.py
   ├── วิเคราะห์ Regime: TRENDING / VOLATILE / RANGING / SQUEEZE
   ├── คำนวณ Regime Score สำหรับ S04:
   │   RANGING   → bonus × 1.4  (สภาวะดีที่สุด สำหรับ Mean Reversion)
   │   TRENDING  → bonus × 1.1  (สภาวะดีในช่วงต้น Trend)
   │   VOLATILE  → bonus × 0.3  (สภาวะแย่ — Value Area เปลี่ยนเร็ว)
   └── ส่งผล Regime ให้ Policy Engine
                ↓
D: Python Brain — core/strategy/policy.py
   ├── AI Council: ถ่วงน้ำหนักด้วย hist_perf × regime_bonus
   ├── หาก weighted_conf ≥ 0.50 → อนุมัติ S04
   ├── Optimize Parameters:
   │   RANGING:  เพิ่ม Lookback (96→120), ลด Vol_Mult (1.2→1.0)
   │   TRENDING: ลด Lookback (96→60), เพิ่ม SL_ATR_Mult (1.5→2.0)
   └── สร้าง CONFIG_PUSH (type=10)
                ↓
E: ZMQ PUSH → Port 7778
   CONFIG_PUSH Array:
   [10, timestamp, symbol, "S04", entry, lot, max_orders,
    tp, sl, confidence, risk_mult]
   + SDynamicParams: S04_BINS, S04_LOOKBACK_BARS, S04_VA_PCT, ...
                ↓
F: MQL5 Trader — CMarketProfile::_ApplyDynamicParams()
   ├── รับ CONFIG_PUSH
   ├── อัพเดทพารามิเตอร์ทั้งหมด (m_bins, m_lookback, m_va_pct, ...)
   └── m_config.mm_method อัพเดท (REQUIRED — ดู comment ในโค้ด)
                ↓
G: CMarketProfile::Analyze() — ทุก Tick
   ├── m_tick_counter++
   ├── ถ้า tick_counter ≥ RebuildEvery (4) หรือ Profile ยังไม่ถูกสร้าง:
   │   ├── _RebuildProfile():
   │   │   ├── m_vp_builder.Setup(symbol, tf, bins, lookback)
   │   │   ├── m_vp_builder.Build()  ← สแกน 96 แท่ง (12KB computation)
   │   │   ├── m_poc_calc.Setup(va_pct)
   │   │   └── m_poc_calc.Calculate(m_vp_builder) → POC, VAH, VAL
   │   └── m_tick_counter = 0
   │
   ├── _ReadIndicators() → ATR, VolMA, CurrentVol
   ├── vol_ok = (m_last_vol ≥ m_vol_mult × m_last_vol_ma)
   │
   ├── ถ้า price < VAL AND vol_ok AND price ≥ VAL - 2×ATR:
   │   └── SIGNAL_BUY + _ComputeConfidence(price)
   │
   └── ถ้า price > VAH AND vol_ok AND price ≤ VAH + 2×ATR:
       └── SIGNAL_SELL + _ComputeConfidence(price)
                ↓
H: Order Manager — เปิด Position
   ├── GetSL(signal, entry) → POC ± SL_ATR_Mult × ATR
   ├── GetTP(signal) → GetNearestNodeAbove/Below หรือ POC
   └── Magic Number = 1004 (MAGIC_S04)
                ↓
I: ZMQ PUSH → Port 7779
   TRADE_REPORT ส่งผล Trade กลับให้ Python Brain
   → Python Brain อัพเดท hist_perf[S04] สำหรับ AI Council รอบถัดไป
```

**ทำไม Rebuild ทุก 4 Tick ไม่ใช่ทุก Tick?**

การสร้าง Volume Profile ต้องวนซ้ำ `bins × lookback = 50 × 96 = 4,800` iterations ต่อครั้ง การรันทุก Tick จะทำให้ CPU Load สูงมาก ระบบจึงตั้ง `m_rebuild_every = 4` (default) หมายความว่า Profile จะอัพเดททุก 4 Tick ซึ่งเพียงพอสำหรับ Timeframe M15 ที่ไม่ต้องการ Precision ระดับ Microsecond

ข้อยกเว้น: ถ้า `m_vp_builder.IsBuilt() == false` (เช่น ตอน Init) จะ Force Rebuild ทันที

---

## 6. ตารางอ้างอิงพารามิเตอร์ (Parameter Reference)

| Parameter | Default | Range | คำอธิบายรายละเอียดเชิงลึก |
|-----------|---------|-------|---------------------------|
| `MP_Bins` | 50 | 20–100 | จำนวน Bin ของ Histogram ค่าน้อย (20) = ความละเอียดต่ำ แต่คำนวณเร็ว POC/VAH/VAL ชัดเจนขึ้น / ค่ามาก (100) = ละเอียดสูง แต่แต่ละ Bin มี Volume น้อย ทำให้ POC ไม่ชัดเจน |
| `MP_LookbackBars` | 96 | 48–240 | จำนวนแท่งย้อนหลัง บน M15: 96 = 24 ชั่วโมง (1 วัน), 192 = 48 ชั่วโมง (2 วัน) ค่ายิ่งมาก Profile สะท้อน Consensus ระยะยาว แต่ฉับไวต่อการเปลี่ยนแปลงน้อยลง |
| `MP_ValueAreaPct` | 0.70 | 0.60–0.80 | เปอร์เซ็นต์ Volume ที่นับรวมใน Value Area ค่า 0.60 = VA แคบลง, VAH/VAL อยู่ใกล้ POC มากขึ้น / ค่า 0.80 = VA กว้างขึ้น, Signal น้อยลงเพราะต้องออกนอกไกลขึ้น |
| `MP_ATR_Period` | 14 | 7–21 | Period สำหรับคำนวณ ATR ที่ใช้ใน SL calculation และ 2×ATR Range Filter ค่าต่ำ = ATR ฉับไว ค่าสูง = ATR เรียบกว่า |
| `MP_Vol_MA_Period` | 20 | 10–50 | Period ของ Volume Moving Average ที่ใช้เป็น Baseline ค่าต่ำ = MA ปรับตามปริมาณล่าสุดเร็ว / ค่าสูง = MA เรียบกว่า ทำให้ Volume Filter เข้มงวดขึ้น |
| `MP_Vol_Mult` | 1.2 | 1.0–2.0 | ตัวคูณ Volume ขั้นต่ำ ค่า 1.0 = ยอมรับ Volume ปกติ / ค่า 2.0 = เฉพาะ Volume สูงกว่าปกติ 2 เท่าขึ้นไป (Signal น้อยแต่คุณภาพสูง) |
| `MP_SL_ATR_Mult` | 1.5 | 1.0–3.0 | ตัวคูณ ATR สำหรับ SL ที่วางไว้เลย POC อีกด้านหนึ่ง ค่า 1.5 = SL ห่างจาก POC ไป 1.5×ATR ซึ่งถ้าราคาข้าม POC ไปอีก ถือว่า Mean Reversion ล้มเหลว |
| `MP_RebuildEvery` | 4 | 1–20 | ความถี่ในการ Rebuild Profile (จำนวน Tick) ค่า 1 = Rebuild ทุก Tick (แม่นยำสูงสุดแต่ CPU สูง) / ค่า 20 = Rebuild บ่อยน้อย CPU ต่ำแต่ Profile อาจ Stale |

**CONFIG_PUSH Parameter Keys (ชื่อที่ใช้ใน Dynamic Params):**

| CONFIG_PUSH Key | MQL5 Parameter | ประเภท |
|-----------------|---------------|---------|
| `S04_BINS` | `MP_Bins` | int (ส่งเป็น double → cast) |
| `S04_LOOKBACK_BARS` | `MP_LookbackBars` | int (ส่งเป็น double → cast) |
| `S04_VA_PCT` | `MP_ValueAreaPct` | double |
| `S04_ATR_PERIOD` | `MP_ATR_Period` | int (ส่งเป็น double → cast) |
| `S04_VOL_MA_PERIOD` | `MP_Vol_MA_Period` | int (ส่งเป็น double → cast) |
| `S04_VOL_MULT` | `MP_Vol_Mult` | double |
| `S04_SL_ATR_MULT` | `MP_SL_ATR_Mult` | double |
| `S04_REBUILD_EVERY` | `MP_RebuildEvery` | int (ส่งเป็น double → cast) |

หลังรับ CONFIG_PUSH ระบบ **ไม่** เรียก Force Rebuild ทันที (ต่างจาก S03 ที่เรียก `_SetupDetectors()` ทันที) แต่รอให้ `m_tick_counter ≥ m_rebuild_every` ในรอบถัดไป เพราะ Profile Rebuild ใช้เวลามากกว่า Detector Setup

---

## 7. โหมดเดี่ยว vs โหมดเซิร์ฟเวอร์ (Standalone vs Server Mode)

### 7.1 โหมดเดี่ยว (Standalone Mode) — ไม่รองรับ

S04 **ไม่มี Standalone Mode** ด้วยเหตุผลสามประการ:

**เหตุผลที่ 1 — Regime Sensitivity:**
Market Profile ทำงานได้ดีในเฉพาะบาง Regime เท่านั้น โดยเฉพาะ RANGING หากทำงานในโหมด VOLATILE โดยไม่มีการตรวจสอบ Regime S04 จะสร้างสัญญาณ Mean Reversion ในขณะที่ตลาดกำลัง Trend อย่างรุนแรง ซึ่งเป็นอันตรายต่อพอร์ต

**เหตุผลที่ 2 — Profile ต้องการ Context:**
POC และ Value Area ที่ถูกคำนวณ ณ เวลาหนึ่งๆ อาจ "หมดอายุ" อย่างรวดเร็วในตลาดที่เคลื่อนไหวเร็ว Python Brain ทำหน้าที่ตรวจสอบว่า Profile ที่คำนวณไว้ยังสอดคล้องกับสภาวะตลาดปัจจุบันหรือไม่ ก่อนที่จะส่ง CONFIG_PUSH อนุมัติ

**เหตุผลที่ 3 — Parameter Optimization:**
ค่า Lookback ที่เหมาะสมแตกต่างกันมากระหว่าง RANGING (ต้องการ Lookback ยาวเพื่อให้ Profile Stable) กับ TRENDING ต้น (ต้องการ Lookback สั้นเพื่อให้ Profile ฉับไว) Python Brain ปรับค่าเหล่านี้แบบ Dynamic ตาม Regime

### 7.2 โหมดเซิร์ฟเวอร์ (Server Mode) — การทำงานเต็มรูปแบบ

```
Python Brain
   ├── Regime: RANGING หรือ early TRENDING
   ├── S04 Confidence Score:
   │   hist_perf × regime_bonus
   │   RANGING   → regime_bonus = 1.40  (ดีที่สุด)
   │   TRENDING  → regime_bonus = 1.10  (ดีในช่วงต้น)
   │   VOLATILE  → regime_bonus = 0.30  (แย่มาก — มักต่ำกว่า threshold)
   │
   ├── AI Council: weighted_conf ≥ 0.50 → อนุมัติ S04
   │
   ├── Parameter Optimization ตาม Regime:
   │   RANGING   → Lookback = 120 (Profile กว้าง, Stable)
   │              Vol_Mult = 1.0 (ยอมรับ Volume ปกติ, RANGING มี Volume ต่ำ)
   │              SL_ATR_Mult = 1.5 (SL ปกติ)
   │   TRENDING  → Lookback = 60  (Profile สั้น, ฉับไว)
   │              Vol_Mult = 1.5 (ต้องการ Volume สูงกว่าปกติเพื่อยืนยัน Rejection)
   │              SL_ATR_Mult = 2.0 (SL กว้างขึ้น เพราะ ATR อาจสูงขึ้น)
   │
   └── CONFIG_PUSH → Port 7778 → CMarketProfile::_ApplyDynamicParams()
```

---

## 8. ลำดับขั้นตอนการทำงานต่อหนึ่ง Trade Cycle (Step-by-Step)

**ขั้นที่ 1 — Initialization (เรียกครั้งเดียวเมื่อ EA เริ่ม):**
- `Init()` สร้าง `m_atr_handle` (iATR 14) และ `m_vol_ma_handle` (iMA 20)
- `_RebuildProfile()` สร้าง Profile เริ่มต้นทันที
- พิมพ์: `[S04] Init OK | Symbol=EURUSD TF=PERIOD_M15 Bins=50 Lookback=96`

**ขั้นที่ 2 — รับ CONFIG_PUSH (เมื่อ Python Brain อนุมัติ):**
- `_ApplyDynamicParams()` อัพเดท m_bins, m_lookback, m_va_pct, ...
- ผลทันที: Parameter ใหม่จะมีผลในรอบ Rebuild ถัดไป

**ขั้นที่ 3 — ทุก Tick: Rebuild Check:**
```
m_tick_counter++
ถ้า (m_tick_counter ≥ m_rebuild_every) หรือ (!m_vp_builder.IsBuilt()):
    _RebuildProfile() → อัพเดท POC, VAH, VAL
    m_tick_counter = 0
```

**ขั้นที่ 4 — ทุก Tick: อ่าน Indicators:**
```
_ReadIndicators():
  CopyBuffer(m_atr_handle, ...) → m_last_atr
  CopyBuffer(m_vol_ma_handle, ...) → m_last_vol_ma
  CopyTickVolume(..., 0, 1, ...) → m_last_vol  (current bar, bar[0])
```

**ขั้นที่ 5 — ทุก Tick: ตรวจสอบเงื่อนไข Entry:**
```
vol_ok = (m_last_vol_ma > 0 && m_last_vol ≥ m_vol_mult × m_last_vol_ma)

ถ้า (price < m_val && vol_ok && price ≥ m_val - 2×m_last_atr):
    SIGNAL_BUY
    last_confidence = _ComputeConfidence(price)
    return  ← ออกทันที ไม่ตรวจสอบ Short อีก

ถ้า (price > m_vah && vol_ok && price ≤ m_vah + 2×m_last_atr):
    SIGNAL_SELL
    last_confidence = _ComputeConfidence(price)
    return
```

**ขั้นที่ 6 — คำนวณ SL/TP (เรียกโดย Order Manager):**
```
GetSL(SIGNAL_BUY, entry_price):
    return m_poc - m_sl_atr_mult × m_last_atr   [SL อยู่ใต้ POC]

GetTP(SIGNAL_BUY):
    node = m_poc_calc.GetNearestNodeAbove(m_val)
    return (node > 0) ? node : m_poc             [Volume Node ถัดไป หรือ POC]
```

**ขั้นที่ 7 — TRADE_REPORT (Port 7779):**
- ส่งผล Trade กลับ Python Brain
- Brain อัพเดท hist_perf[S04]

---

## 9. ลักษณะประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|------|-----------|
| **สภาวะตลาดที่ดีที่สุด** | ตลาด RANGING ที่ราคาวนเวียนใน Value Area — เกิดบ่อยใน Asian Session หรือช่วงรอข่าว |
| **สภาวะตลาดที่แย่ที่สุด** | ตลาด VOLATILE หลังข่าวใหญ่ — POC เปลี่ยนตำแหน่งทุกไม่กี่แท่ง ทำให้ Profile ล้าสมัยเสมอ |
| **ความถี่สัญญาณ** | ต่ำ–ปานกลาง: 1–4 สัญญาณต่อวัน (ขึ้นอยู่กับ Lookback และ Vol_Mult) |
| **Win Rate เป้าหมาย** | 55–65% (POC ทำหน้าที่เป็น "แม่เหล็ก" ดึงราคากลับ) |
| **R:R Ratio** | Variable — ขึ้นกับระยะ entry→VAL และ VAL→Nearest Node ปกติ 1.5:1 ถึง 3:1 |
| **Magic Number** | 1004 (MAGIC_S04) |
| **ATR Period** | 14 แท่ง |
| **Rebuild Frequency** | ทุก 4 Tick (ค่าเริ่มต้น) |
| **Secondary Nodes** | 5 Nodes สูงสุด (ใช้เป็น TP Target) |

**R:R จาก Case Study:**
- SL Distance = entry(1.0797) - SL(1.0790) = **7 pips**
- TP Distance = TP(1.0815) - entry(1.0797) = **18 pips**
- R:R = 18/7 ≈ **2.57:1**

---

## 10. ไฟล์อ้างอิง (Files Reference)

| ไฟล์ | บทบาท |
|------|--------|
| `Include/Logic/Strategies/S04_MarketProfile.mqh` | คลาสหลัก `CMarketProfile` — Entry logic, Confidence, SL/TP |
| `Include/Logic/Strategies/MarketProfile/VolumeProfileBuilder.mqh` | `CVolumeProfileBuilder` — Proportional Volume Distribution |
| `Include/Logic/Strategies/MarketProfile/POCCalculator.mqh` | `CPOCCalculator` — POC, VAH, VAL, Secondary Nodes |
| `02_Brain/strategies/s04_market_profile_analyzer.py` | Python Regime Scoring สำหรับ S04 |
| `Include/Logic/StrategyConstants.mqh` | ค่าคงที่: `S04_MARKET_PROFILE` enum, `MAGIC_S04 = 1004` |
| `Include/Network/Protocol/Definitions.mqh` | `SDynamicParams`, CONFIG_PUSH structure |

---

## 11. Quick Diagnostics

### ตรวจสอบว่า S04 Active และ Profile พร้อม
```
dashboard.py → Active Strategies → "S04" ปรากฏพร้อม confidence > 0.0
```

### ตรวจสอบค่า POC/VAH/VAL ใน MT5
```mql5
// เรียกใช้ตอน Debug หรือ Unit Test:
CMarketProfile mp;
mp.Init("EURUSD", PERIOD_M15);
PrintFormat("POC=%.5f VAH=%.5f VAL=%.5f ATR=%.5f",
    mp.GetPOC(), mp.GetVAH(), mp.GetVAL(), mp.GetLastATR());
```

### Log ที่ควรเห็นใน MT5 Experts Tab
```
[S04] Init OK | Symbol=EURUSD TF=PERIOD_M15 Bins=50 Lookback=96
[S04] SIGNAL_BUY  price=1.07970 < VAL=1.08030  vol=2350 vol_ma=920  conf=0.511
[S04] SIGNAL_SELL price=1.08520 > VAH=1.08450  vol=1800 vol_ma=920  conf=0.423
```

### กรณี S04 ไม่สร้างสัญญาณ
```
สาเหตุที่ 1: Profile ยังไม่ Build — รอ Tick แรกให้ครบ
             ตรวจสอบ: mp.IsProfileBuilt() → ถ้า false = ปัญหา Data

สาเหตุที่ 2: Regime ≠ RANGING → Brain ไม่ส่ง CONFIG_PUSH
             ตรวจสอบ: dashboard.py → Current Regime

สาเหตุที่ 3: Volume ต่ำกว่า Threshold
             แก้ไข: ลด MP_Vol_Mult (เช่น 1.2 → 1.0)
             ระวัง: จะเพิ่ม False Signal ในตลาด Low Volume

สาเหตุที่ 4: ราคาไม่ออกนอก Value Area เลย (ตลาด Tight Range)
             แก้ไข: ลด MP_ValueAreaPct (0.70 → 0.60) → VA แคบลง,
                    ราคาออกนอก VA ได้ง่ายขึ้น
```

### เปรียบเทียบ VAH/VAL ที่คาดหวัง
```
Profile (96 M15 bars = 24h) ควรแสดง:
  Value Area Width ≈ 60-80% ของ Daily Range
  POC อยู่ใกล้กึ่งกลางของ Value Area (Bell Curve)
  ถ้า POC อยู่ชิดขอบ = ตลาดมีทิศทาง (ไม่ใช่ RANGING อย่างแท้จริง)
```

---

## 12. ข้อวิพากษ์และแนวทางการปรับปรุง (Critiques & Optimizations)

**ข้อจำกัดที่ 1 — Profile Lag (ความล่าช้าของ Profile):**

Profile ที่สร้างจากข้อมูล 24 ชั่วโมงล่าสุดอาจ Lag ไม่ทันกับตลาดที่เปลี่ยนทิศทางอย่างรวดเร็ว โดยเฉพาะหลังข่าวใหญ่ที่ทำให้ POC เปลี่ยนตำแหน่งทันที วิธีบรรเทา: ลด `MP_LookbackBars` (เช่น 48 แทน 96 = 12 ชั่วโมง) และเพิ่ม `MP_RebuildEvery = 1` (Rebuild ทุก Tick) สำหรับตลาดที่ Volatile

**ข้อจำกัดที่ 2 — Volume MA Proxy:**

การใช้ `iMA(PRICE_CLOSE)` เป็น Proxy สำหรับ Volume MA ไม่ใช่ Volume MA ที่แท้จริง ทำให้ `m_last_vol_ma` ไม่ใช่ค่าเฉลี่ย Tick Volume จริงๆ วิธีบรรเทา: ใช้ `CopyTickVolume()` ใน Loop เพื่อคำนวณ Volume MA โดยตรงตามที่ระบุใน Production Note ของโค้ด

**ข้อจำกัดที่ 3 — Fixed TP ที่ Nearest Node:**

TP ที่ตั้งไว้ที่ Volume Node ที่ใกล้ที่สุดอาจสั้นเกินไปหากตลาดมีโมเมนตัมแรงพอที่จะไปถึง POC โดยตรง วิธีบรรเทา: เพิ่มตัวเลือก "TP = POC เสมอ" สำหรับสภาวะ Confidence สูง (เช่น > 0.65)

**ข้อจำกัดที่ 4 — SL อยู่ที่ POC (ไม่ใช่ VAH/VAL):**

SL ถูกวางไว้เลย POC ไปอีกด้านหนึ่ง (`m_poc - SL_ATR_Mult × ATR`) ซึ่งหมายความว่าถ้าราคาข้าม POC ไป SL จะถูก Touch หลักการนี้สมเหตุสมผลเพราะ POC Broken = Profile ล้มเหลว แต่ถ้า POC อยู่ใกล้ VAL ระยะ SL จาก Entry อาจสั้นมาก วิธีบรรเทา: เพิ่ม Minimum SL Distance เช่น `SL ≥ 1.0 × ATR จาก Entry`

**แนวทางการ Tune พารามิเตอร์ตามสภาวะตลาด:**

| สภาวะ | MP_LookbackBars | MP_Vol_Mult | MP_ValueAreaPct | MP_SL_ATR_Mult |
|--------|-----------------|-------------|-----------------|----------------|
| RANGING ลึก | 120 | 1.0 | 0.70 | 1.5 |
| Early TRENDING | 60 | 1.5 | 0.65 | 2.0 |
| Choppy/Low Vol | 96 | 1.0 | 0.60 | 1.5 |
| Default | 96 | 1.2 | 0.70 | 1.5 |

---

*S04 Market Profile Manual — FlashEASuite V2 | Phase P9-5 | Jimmi Deep-Dive Edition | 2026-02-27*
