# S11 — Multi-Timeframe Ichimoku (Kinko Hyo)
## FlashEASuite V2 | คู่มือทางเทคนิคเชิงลึกฉบับสมบูรณ์ (Jimmi Deep-Dive Edition)
### จัดทำ: 2026-02-28 | Phase P9-5 | ฉบับขยายความ 8×

---

## 1. บทนำของกลยุทธ์ (Strategy Overview)

| Field | Value | คำอธิบายเชิงวิชาการเพิ่มเติม |
|-------|-------|-------------------------------|
| **รหัสกลยุทธ์** | S11 | รหัสอ้างอิงลำดับที่สิบเอ็ดในระบบมัลติกลยุทธ์ของ FlashEASuite V2 S11 อยู่ในกลุ่ม "Full MQL5, Server-Only" หมายความว่าตรรกะสัญญาณทั้งหมดอยู่ใน MQL5 แต่ต้องรอรับ CONFIG_PUSH จาก Python Brain ก่อนจึงจะเปิดใช้งาน เป็นกลยุทธ์ที่ต้องการ "สภาวะตลาดที่ใช่" มากที่สุดตัวหนึ่งในระบบ |
| **Enum Name** | `S11_ICHIMOKU` | ชื่อคงที่ใน `ENUM_STRATEGY_ID` (ไฟล์ `StrategyConstants.mqh`) ค่า enum index = 10 (0-based array index) หมายความว่าเป็น element ลำดับที่ 11 ของ `g_strategy_table[16]` |
| **Enum Index** | 10 | ดัชนีอาร์เรย์ระดับ 0 ใน `g_strategy_table[]` ใช้เพื่อเข้าถึง `SStrategyInfo` ผ่านฟังก์ชัน `GetStrategyInfo(S11_ICHIMOKU)` |
| **ชื่อ** | Multi-Timeframe Ichimoku (Kinko Hyo) | กลยุทธ์ Trend Following โดยใช้ระบบ Ichimoku Kinko Hyo ซึ่งแปลว่า "แผนภูมิสมดุลทุกสิ่งในทุกเวลา" ประยุกต์ใช้ใน 3 Timeframe พร้อมกัน (D1, H4, H1) |
| **ประเภท** | Full MQL5 — Server Only (`CAT_FULL_MQL5`, Server-Only flag) | Indicator Logic ทั้งหมดอยู่ใน MQL5 แต่กลยุทธ์ถูก Disable ตั้งแต่เริ่มต้น (`m_enabled = false`) จนกว่าจะได้รับ CONFIG_PUSH ครั้งแรกจาก Python Brain เหตุผล: ต้องรู้ Regime ก่อนว่าเป็น TRENDING จริงหรือไม่ |
| **Standalone Capable** | ❌ No | ไม่รองรับ Standalone — เมื่อ Brain ขาดการเชื่อมต่อ `CStandaloneSelector` จะ Exclude S11 ออกจาก Active Strategies ทันที ระบบจะใช้กลยุทธ์ Standalone อื่นๆ แทน (เช่น S10 Turtle, S16 Spike) |
| **Preferred Regime** | TRENDING (`REGIME_TRENDING`) | Ichimoku ถูกออกแบบมาเพื่อตลาดที่มีทิศทางชัดเจน ในตลาด Trending Kumo Cloud หนาและอยู่ห่างจากราคา ทำให้ทุก Component ส่งสัญญาณชัดเจนและสอดคล้องกัน |
| **Alt Regime** | None (`REGIME_UNKNOWN`) | ไม่มี Regime รอง S11 ใช้ได้ดีในสภาวะ Trending เท่านั้น ในสภาวะอื่นความน่าเชื่อถือต่ำมากเพราะ Cloud บาง Chikou Cross สุ่ม |
| **Poor Regimes** | RANGING, VOLATILE | RANGING: Cloud บาง ราคาเข้า-ออก Cloud ตลอด Tenkan/Kijun Cross บ่อยและผิดทิศทาง / VOLATILE: ราคากระโดดข้าม Cloud ได้ทันที ทำให้สัญญาณเท็จ |
| **Regime Factor** | TRENDING=1.5, SQUEEZE=0.8, RANGING=0.4, VOLATILE=0.3 | ตัวคูณที่สะท้อนความเหมาะสมของแต่ละสภาวะ — S11 ได้โบนัส 1.5× ในสภาวะ TRENDING แต่ถูกลงโทษรุนแรงใน RANGING/VOLATILE |
| **MQL5 Class** | `CIchimoku` | คลาสหลัก ไฟล์: `Include/Logic/Strategies/S11_Ichimoku.mqh` จัดการ Ichimoku Handles 3 ชุด (D1, H4, H1) พร้อม `SIchimokuSnapshot` Struct สำหรับเก็บข้อมูลแต่ละ Timeframe |
| **Helper Struct** | `SIchimokuSnapshot` | Data Container ที่เก็บค่า Tenkan, Kijun, Senkou A/B, Chikou, Cloud Top/Bot ของ Timeframe หนึ่งๆ ช่วยให้ Code อ่านง่ายและส่งต่อข้อมูล TF แต่ละชุดได้สะดวก |
| **Python Analyzer** | ไม่มี — Regime Classifier + Period Optimizer | Python ไม่ได้คำนวณสัญญาณ แต่ทำหน้าที่ (1) จัดประเภท Regime ว่า TRENDING หรือไม่ (2) Optimize Tenkan/Kijun/SenkouB Periods จาก Historical Data (3) ปรับ TF Weights และ Cloud Min Width ตาม Symbol Volatility |
| **Magic Number** | 1011 (`MAGIC_S11_ICHIMOKU`) | หมายเลขเอกลักษณ์ป้องกันการปะปนของออเดอร์ระหว่างกลยุทธ์ |
| **Family** | Trend Following — Japanese Technical Analysis | S11 อยู่ในกลุ่มกลยุทธ์ที่ "ตามกระแส" ของตลาด ซื้อในช่วงขาขึ้น ขายในช่วงขาลง ซึ่งตรงข้ามกับ S07 (Contrarian) |
| **Version** | 6.00 | สถาปัตยกรรม V6 |

---

### 1.1 สรุปแนวคิดหลัก (Executive Summary)

S11 เป็นกลยุทธ์ **Trend Following** โดยใช้ระบบ **Ichimoku Kinko Hyo** ที่พัฒนาโดยนักข่าวชาวญี่ปุ่นชื่อ Goichi Hosoda ในช่วงปลายทศวรรษ 1930 และเผยแพร่ต่อสาธารณะในปี 1969 โดยหลักการของ Ichimoku คือการมองภาพรวมของตลาดในครั้งเดียว — แทนที่จะใช้ Indicator หลายตัวแยกจากกัน Ichimoku รวมทุกอย่างไว้ในแผนภูมิเดียว

S11 ยกระดับ Ichimoku ดั้งเดิมด้วยการใช้ **3 Timeframe พร้อมกัน** — D1 เป็น "เสียงของตลาดระยะยาว", H4 เป็น "ตัวยืนยันทิศทาง", H1 เป็น "จังหวะเข้า Trade ที่แม่นยำ" ทั้ง 3 Timeframe ต้องส่งสัญญาณในทิศทางเดียวกันพร้อมกันทุกเงื่อนไขจาก 6 ข้อ — หากแม้แต่ข้อเดียวไม่ผ่าน S11 จะไม่เข้า Trade

---

### 1.2 ปรัชญาเบื้องหลัง: ทำไมต้องชื่อ "Ichimoku Kinko Hyo"?

**ความหมายของชื่อ:**

- **一目 (Ichimoku)** — "มองครั้งเดียว" (At a Glance)
- **均衡 (Kinko)** — "สมดุล" (Equilibrium)
- **表 (Hyo)** — "แผนภูมิ" (Chart)

รวมกันหมายถึง "แผนภูมิที่มองครั้งเดียวแล้วเห็นสมดุล" — ปรัชญาคือการมองตลาดเป็น "ระบบสมดุล" ที่ราคามีแนวโน้มจะอยู่ใน "โซนสมดุล" (Kumo Cloud) และเมื่อออกนอกโซนนี้ไปในทิศทางใดทิศทางหนึ่งอย่างมีนัยสำคัญ แสดงว่าตลาดมีทิศทางชัดเจน

**ทำไม Ichimoku จึงแตกต่างจาก Indicator ทั่วไป:**

Indicator ส่วนใหญ่ใช้ราคา Close หรือ Close + Open ในการคำนวณ แต่ Ichimoku ใช้ **จุดกึ่งกลางของ High-Low Range** (Midpoint) ในช่วงเวลาต่างๆ ซึ่งสะท้อนถึง "ราคายุติธรรม" ที่แท้จริงมากกว่า Close เพียงอย่างเดียว:

```
ถ้าราคา Close = 1.0850 แต่วันนี้ High = 1.0900 และ Low = 1.0750
  จุดกึ่งกลาง (Midpoint) = (1.0900 + 1.0750) / 2 = 1.0825

Midpoint บอกว่า: "ราคาสมดุลของช่วงเวลานี้คือ 1.0825"
  แม้ตลาดจะปิดที่ 1.0850 แต่จริงๆ แล้วราคาโดยเฉลี่ย "เคลื่อนผ่าน" 1.0825
  การใช้ Midpoint ทำให้ระบบมีความทนทานต่อ Spike และ Fake Breakout มากกว่า
```

**ทำไมต้องใช้ 3 Timeframe:**

การดู Ichimoku เฉพาะ H1 เพียง TF เดียวมีปัญหาคือ H1 อาจส่งสัญญาณ Bullish Cross แต่ภาพใหญ่ (D1) กำลังเป็น Downtrend แรงๆ — การเข้า Long ในกรณีนั้นเปรียบเหมือนว่ายทวนน้ำ S11 แก้ปัญหานี้ด้วยการใช้ D1 และ H4 เป็น "ตัวกรองทิศทาง" ก่อน แล้วจึงใช้ H1 เป็น "จุดเข้า"

---

### 1.3 ประวัติศาสตร์และที่มาของค่า Default 9-26-52

ตัวเลข 9, 26, 52 ที่ Goichi Hosoda เลือกไม่ใช่ค่าสุ่ม — มีที่มาจากปฏิทินธุรกิจของญี่ปุ่นในยุค 1930s:

```
9  = จำนวนวันทำการในสัปดาห์ครึ่ง (1.5 สัปดาห์)
     ญี่ปุ่นมี 6 วันทำการต่อสัปดาห์ในยุคนั้น
     9 วัน = ช่วง "ระยะสั้น" ของ Cycle ตลาด

26 = จำนวนวันทำการในเดือนหนึ่ง (ตลาดญี่ปุ่นเปิด 26 วัน/เดือน)
     26 วัน = ช่วง "ระยะกลาง" หรือหนึ่งรอบธุรกิจรายเดือน

52 = จำนวนวันทำการในสองเดือน (26 × 2)
     52 วัน = ช่วง "ระยะยาว" สองเดือน — ครอบคลุมสองรอบธุรกิจ
```

**ในตลาดปัจจุบัน (5 วันทำการ/สัปดาห์):**

บางนักเทคนิคแนะนำให้ปรับเป็น 7-22-44 (ตาม 5 วันทำการ) แต่ส่วนใหญ่ยังคงใช้ 9-26-52 ตามดั้งเดิมเพราะ:
1. ค่านี้ใช้กันแพร่หลายทั่วโลก → กลไกตลาด "เชื่อ" ในระดับเหล่านี้
2. ตลาด Forex เปิด 24 ชั่วโมง ทำให้ 26 แท่งของ H1 = 26 ชั่วโมง ≈ หนึ่งรอบตลาด London+NY
3. Python Brain สามารถ Optimize ค่าเหล่านี้ได้ผ่าน CONFIG_PUSH ถ้า Backtest บอกว่าควรเปลี่ยน

---

### 1.4 กรณีศึกษาจริง (Case Study — 28 กุมภาพันธ์ 2026)

**สถานการณ์:** EURUSD อยู่ในช่วง Uptrend ที่ชัดเจนหลัง ECB มีท่าที Hawkish ตลาดวิ่งขึ้นต่อเนื่อง 3 วัน

```
==== D1 Timeframe (Trend Direction — น้ำหนัก 40%) ====

  Close_D1     = 1.08520
  Tenkan_D1    = 1.08450  (9-day midpoint)
  Kijun_D1     = 1.08200  (26-day midpoint)
  Cloud_Top_D1 = 1.08100  (Senkou Span A)
  Cloud_Bot_D1 = 1.07800  (Senkou Span B)

  เงื่อนไข:
    Close > Cloud_Top? 1.08520 > 1.08100 ✅ ราคาอยู่เหนือ Cloud
    Tenkan >= Kijun?  1.08450 >= 1.08200 ✅ Tenkan สูงกว่า Kijun

  D1_trend = +1 (Bullish) ✅

==== H4 Timeframe (Trend Confirmation — น้ำหนัก 35%) ====

  Close_H4     = 1.08510
  Tenkan_H4    = 1.08480
  Kijun_H4     = 1.08350
  Cloud_Top_H4 = 1.08400
  Cloud_Bot_H4 = 1.08200

  เงื่อนไข:
    Tenkan > Kijun? 1.08480 > 1.08350 ✅
    Close > Cloud_Top? 1.08510 > 1.08400 ✅

  H4_trend = +1 (Bullish) ✅

==== H1 Timeframe (Entry Trigger — น้ำหนัก 25%) ====

  Close_H1     = 1.08505
  Cloud_Top_H1 = 1.08450  (Senkou Span A)
  Cloud_Bot_H1 = 1.08300  (Senkou Span B)
  Cloud Width  = (1.08450 - 1.08300) / 0.0001 = 15.0 pips

  Tenkan[2] (bar ก่อนหน้า)  = 1.08460
  Kijun[2]  (bar ก่อนหน้า)  = 1.08470
  Tenkan[1] (bar ปิดล่าสุด) = 1.08490  ← ตัดขึ้นเหนือ Kijun!
  Kijun[1]  (bar ปิดล่าสุด) = 1.08465

  Chikou (Close shifted 26 bars back) = 1.08500
  Close 26 bars ago = 1.08120

  เงื่อนไขทั้ง 6 ข้อ:
    1. D1_trend == +1?                              ✅
    2. H4_trend == +1?                              ✅
    3. Cloud Width >= 10 pips? (15.0 >= 10.0)       ✅
    4. Close > Cloud_Top_H1? (1.08505 > 1.08450)   ✅
    5. H1 Bullish Cross? Tenkan[2]<=Kijun[2] AND
                         Tenkan[1]>Kijun[1]         ✅ Cross เพิ่งเกิดขึ้น!
    6. Chikou > Close_26_ago? (1.08500 > 1.08120)  ✅

→ SIGNAL_BUY! ทุกเงื่อนไขผ่าน
```

**การคำนวณ Confidence:**

```
d1_score = 1.0  (D1 aligned)
h4_score = 1.0  (H4 aligned)
h1_score = 1.0  (H1 cross aligned)

tf_align = 1.0×0.40 + 1.0×0.35 + 1.0×0.25 = 1.00

ATR_H1 = 0.00095
cloud_thickness_H1 = Cloud_Top - Cloud_Bot = 1.08450 - 1.08300 = 0.00150

cloud_bonus = min(1.0, 0.00150 / 0.00095) = min(1.0, 1.578) = 1.00

tk_dist = min(1.0, |1.08490 - 1.08465| / 0.00150)
        = min(1.0, 0.00025 / 0.00150)
        = min(1.0, 0.167)
        = 0.167

Confidence = tf_align×0.6 + cloud_bonus×0.2 + tk_dist×0.2
           = 1.00×0.6 + 1.00×0.2 + 0.167×0.2
           = 0.600 + 0.200 + 0.033
           = 0.833

หลัง Regime Multiplier (TRENDING × 1.5):
Confidence = 0.833 × 1.5 = 1.0 (capped at 1.0)
```

**ผลลัพธ์ของ Trade:**

```
Entry (ASK)  = 1.08510
SL (ATR-based, จาก StrategyManager) = 1.08510 - 2.0×ATR_H1
             = 1.08510 - 0.00190 = 1.08320

TP: Dynamic — ปิดเมื่อ Tenkan_H1 < Kijun_H1 (Cross กลับ)

หลังจาก 4 ชั่วโมง เวลา 14:00 GMT:
  EURUSD ขึ้นไปที่ 1.08840
  Tenkan_H1 = 1.08810
  Kijun_H1  = 1.08820
  Tenkan_H1 < Kijun_H1? 1.08810 < 1.08820 ✅ → ShouldExit = true!

  กำไร = 1.08840 - 1.08510 = 33.0 pips × 0.10 lot = +$33.00
```

**บทเรียนจากกรณีนี้:**

- D1 + H4 เป็น "พยาน" ว่าทิศทางใหญ่เป็นขาขึ้น — H1 เป็นแค่ "จังหวะเข้า"
- Cloud ที่หนา (15 pips) ยืนยันว่ามีแนวรับ-แนวต้านที่แข็งแกร่งรองรับ Trade
- Chikou ที่อยู่เหนือราคาเมื่อ 26 แท่งที่แล้วยืนยันว่า Momentum ระยะยาวยังเป็น Bullish
- Exit แบบ Dynamic ผ่าน Tenkan/Kijun Cross ช่วยให้คว้ากำไรได้มากกว่า Fixed TP

---

## 2. ทฤษฎีหลักทางคณิตศาสตร์ (Mathematical Foundations)

### 2.1 Tenkan-sen (Conversion Line / เส้นแปลง)

```
Tenkan(N) = (Highest High ใน N แท่งล่าสุด + Lowest Low ใน N แท่งล่าสุด) / 2

Default: N = 9

สูตรคณิตศาสตร์:
  HH_9 = max(High[0], High[1], ..., High[8])
  LL_9 = min(Low[0],  Low[1],  ..., Low[8])
  Tenkan = (HH_9 + LL_9) / 2
```

**ความหมายทางเศรษฐศาสตร์:**

Tenkan บอกว่า "ราคายุติธรรมเฉลี่ยในช่วง 9 แท่งที่ผ่านมาคือเท่าไหร่" ไม่ใช่ค่าเฉลี่ย Close (SMA) แต่เป็นค่าเฉลี่ยของขอบเขต (Boundary Average) ที่สะท้อน "กลางกรอบราคา" ที่แท้จริง

ตัวอย่าง:
```
แท่งราคา 9 แท่งล่าสุด (High, Low):
  H: 1.0860, 1.0880, 1.0870, 1.0890, 1.0900, 1.0885, 1.0875, 1.0895, 1.0910
  L: 1.0820, 1.0830, 1.0825, 1.0840, 1.0845, 1.0835, 1.0828, 1.0842, 1.0848

  HH_9 = 1.0910
  LL_9 = 1.0820
  Tenkan = (1.0910 + 1.0820) / 2 = 1.0865
```

**Tenkan ใน S11 ทำหน้าที่อะไร:**
- เส้น "เร็ว" — ตอบสนองต่อการเปลี่ยนแปลงราคาได้เร็วกว่า Kijun
- ใช้ตรวจ Tenkan-Kijun Cross เพื่อจับ Entry ใน H1
- ในทิศทาง Bullish: Tenkan ควรอยู่เหนือ Kijun

---

### 2.2 Kijun-sen (Base Line / เส้นฐาน)

```
Kijun(N) = (Highest High ใน N แท่งล่าสุด + Lowest Low ใน N แท่งล่าสุด) / 2

Default: N = 26

สูตร:
  HH_26 = max(High[0], ..., High[25])
  LL_26 = min(Low[0],  ..., Low[25])
  Kijun = (HH_26 + LL_26) / 2
```

**ความหมายทางเศรษฐศาสตร์:**

Kijun บอกว่า "ราคายุติธรรมเฉลี่ยในช่วงหนึ่งเดือน" เป็นเส้น "ช้า" ที่เสถียรกว่า Tenkan ทำหน้าที่เป็น Dynamic Support/Resistance ระยะกลาง

**การใช้ Kijun เป็น Support/Resistance:**
```
ในช่วง Uptrend:
  ราคาที่ Pullback มาหา Kijun → มักพบ Support ที่นี่
  ราคาที่ปิดต่ำกว่า Kijun เป็นเวลานาน → สัญญาณอ่อนแรงของ Trend

ใน S11:
  D1: Close > Kijun_D1 = เงื่อนไขหนึ่งของ Bullish D1 Trend
  H1: Tenkan cross เหนือ Kijun = สัญญาณ Entry ที่ดี
```

---

### 2.3 Senkou Span A (Cloud Boundary A / ขอบเขต Cloud ด้าน A)

```
Senkou_A = (Tenkan + Kijun) / 2
           และถูก Plot ไปข้างหน้า 26 แท่ง (Leading)

สูตร ณ เวลา t:
  Senkou_A(t) = (Tenkan(t) + Kijun(t)) / 2
  แต่ Plot บนกราฟที่ตำแหน่ง t + 26
```

**ความหมาย:** Senkou A เป็น "ค่าเฉลี่ยของ Tenkan และ Kijun" ที่ถูก Project ไปในอนาคต 26 แท่ง ทำให้เห็น "Cloud แห่งอนาคต" — ถ้า Tenkan อยู่เหนือ Kijun Cloud จะขึ้นไปข้างหน้า (Bullish Cloud)

---

### 2.4 Senkou Span B (Cloud Boundary B / ขอบเขต Cloud ด้าน B)

```
Senkou_B = (Highest High ใน 52 แท่ง + Lowest Low ใน 52 แท่ง) / 2
           และถูก Plot ไปข้างหน้า 26 แท่ง

สูตร ณ เวลา t:
  HH_52 = max(High[0], ..., High[51])
  LL_52 = min(Low[0],  ..., Low[51])
  Senkou_B(t) = (HH_52 + LL_52) / 2
  แต่ Plot ที่ตำแหน่ง t + 26
```

**ความหมาย:** Senkou B เป็น "ราคายุติธรรมระยะยาว 2 เดือน" ที่ Project ไปอนาคต เป็นเส้น Cloud ที่เสถียรกว่า Span A มาก ทำหน้าที่เป็น Strong Support/Resistance ระยะยาว

---

### 2.5 Kumo Cloud (เมฆ / โซนสมดุล)

```
Cloud_Top = max(Senkou_A, Senkou_B)
Cloud_Bot = min(Senkou_A, Senkou_B)
Cloud_Width_pips = (Cloud_Top - Cloud_Bot) / pip_size

ตัวอย่าง:
  Senkou_A = 1.08450
  Senkou_B = 1.08300
  Cloud_Top = max(1.08450, 1.08300) = 1.08450
  Cloud_Bot = min(1.08450, 1.08300) = 1.08300
  Cloud_Width = (1.08450 - 1.08300) / 0.0001 = 15.0 pips
```

**ประเภทของ Cloud:**

| สีของ Cloud (แบบ Original) | เงื่อนไข | ความหมาย |
|--------------------------|---------|---------|
| Bullish (สีเขียว/สว่าง) | Senkou_A > Senkou_B | Cloud กำลังขยายขึ้น — Bullish |
| Bearish (สีแดง/มืด) | Senkou_A < Senkou_B | Cloud กำลังขยายลง — Bearish |
| Thin Cloud | Width < 10 pips | Support/Resistance อ่อนแอ — S11 จะ Skip |

**บทบาทของ Cloud ใน S11:**
1. **โซนสมดุล:** ราคาที่อยู่ใน Cloud = "ไม่มีทิศทาง" ห้ามเข้า Trade
2. **Support/Resistance:** Cloud หนา (> 20 pips) = แนวรับ/แนวต้านแข็งแกร่ง
3. **เงื่อนไข Entry:** ราคาต้องอยู่ "เหนือ" Cloud Top (Long) หรือ "ใต้" Cloud Bot (Short)
4. **เงื่อนไข Exit:** ราคากลับเข้า Cloud = สัญญาณออก

---

### 2.6 Chikou Span (Lagging Line / เส้นย้อนหลัง)

```
Chikou = Close ปัจจุบัน Plot ไปข้างหลัง 26 แท่ง

ความหมาย: เปรียบ Close ปัจจุบันกับราคา 26 แท่งที่ผ่านมา

การยืนยัน (Confirmation):
  Long: Chikou > Close_26_bars_ago
        → Momentum ปัจจุบันสูงกว่าเมื่อ 26 แท่งก่อน = ยังเป็น Uptrend
  Short: Chikou < Close_26_bars_ago
         → Momentum ปัจจุบันต่ำกว่าเมื่อ 26 แท่งก่อน = ยังเป็น Downtrend
```

**เหตุผลที่ Chikou สำคัญ:**

Chikou ป้องกันการเข้า Trade ในช่วงที่ราคา "หลอก" ขึ้นไปชั่วคราว:
```
สถานการณ์: วันนี้ EURUSD ขึ้นมา 30 pips จาก Spike
  Close ปัจจุบัน = 1.0880
  Close 26 แท่งก่อน = 1.0910  (ก่อนหน้านี้ราคาสูงกว่า!)

  Chikou = 1.0880 < Close_26_ago = 1.0910 → ไม่ผ่าน Chikou!
  S11 จะ SKIP Trade นี้ เพราะ Momentum ระยะยาวยังเป็น Bearish จริงๆ
```

---

### 2.7 การคำนวณ 3-Tier Alignment

```
==== D1 Trend Score ====
  Bullish (+1): Close_D1 > Cloud_Top_D1  AND  Tenkan_D1 >= Kijun_D1
  Bearish (-1): Close_D1 < Cloud_Bot_D1  AND  Tenkan_D1 <= Kijun_D1
  Neutral (0):  ราคาอยู่ใน Cloud หรือ Signal ขัดแย้ง

==== H4 Trend Score ====
  Bullish (+1): Tenkan_H4 > Kijun_H4  AND  Close_H4 > Cloud_Top_H4
  Bearish (-1): Tenkan_H4 < Kijun_H4  AND  Close_H4 < Cloud_Bot_H4
  Neutral (0):  ไม่ชัดเจน

==== เงื่อนไขผ่านขั้นแรก ====
  D1 != 0 AND D1 == H4  → ทิศทางใหญ่ตรงกัน
  มิฉะนั้น → SIGNAL_NONE ทันที (ไม่ตรวจ H1 เลย)

==== H1 Entry Conditions (ทั้ง 4 ข้อต้องผ่าน) ====
  a. Cloud_Width_H1 >= Cloud_Min (10 pips)
  b. ราคาอยู่ถูกฝั่งของ Cloud H1
  c. Fresh Tenkan/Kijun Cross บน H1 (เกิดขึ้น 1 ครั้งต่อ bar)
  d. Chikou ยืนยัน
```

---

## 3. สถาปัตยกรรมระบบ (System Architecture)

### 3.1 Server-Only Architecture — ทำไมต้องพึ่ง Brain?

```
┌──────────────────────────────────────────────────────────────────────────┐
│               S11 SERVER-ONLY ARCHITECTURE — ภาพรวมสถาปัตยกรรม          │
├─────────────────────────────┬────────────────────────────────────────────┤
│   PYTHON BRAIN (Required)   │   MQL5 TRADER (Client Side — CIchimoku)   │
│   ต้องพร้อมก่อน S11 ทำงาน   │   Tick-level Execution                    │
├─────────────────────────────┼────────────────────────────────────────────┤
│  ✅ Regime Classification    │  ✅ 3 iIchimoku Handles (D1, H4, H1)      │
│    (HMM/Random Forest)      │     แต่ละ Handle มี 5 Buffers             │
│    TRENDING? → เปิด S11     │     (Tenkan, Kijun, SpanA, SpanB, Chikou) │
│    RANGING?  → ปิด S11      │                                            │
│                             │  ✅ SIchimokuSnapshot per TF              │
│  ✅ Period Optimization      │     (struct เก็บค่า Tenkan,Kijun,Cloud)   │
│    Scan Tenkan: 7-13        │                                            │
│    Scan Kijun: 21-34        │  ✅ _ReadIchimoku() Buffer Copy per TF     │
│    Scan SenkouB: 42-60      │     เรียกทุก Tick                         │
│    (Backtest on InfluxDB)   │                                            │
│                             │  ✅ D1/H4 Trend Scoring (+1/0/-1)         │
│  ✅ TF Weight Adjustment     │  ✅ H1 Cloud Width Filter                  │
│    Strong Trend: D1 dominant│  ✅ H1 Cross Detection (Bar-Gated)        │
│    Early Trend: H1 dominant │  ✅ Chikou Confirmation                   │
│                             │  ✅ Confidence (tf_align+cloud+tk_dist)   │
│  ✅ Cloud Min Width Tuning   │  ✅ ShouldExit() per Tick                 │
│    ปรับตาม Symbol ATR        │  ✅ Handle Rebuild on Period Change       │
│                             │                                            │
│  ✅ CONFIG_PUSH Port 7778    │  ✅ TRADE_REPORT Port 7779                │
│    S11_TENKAN, S11_KIJUN    │    (ผลกำไร/ขาดทุนกลับ Brain)             │
│    S11_SENKOU_B, CLOUD_MIN  │                                            │
│    S11_TF_D1_W/H4_W/H1_W   │                                            │
└─────────────────────────────┴────────────────────────────────────────────┘
```

**เหตุผลที่ S11 ต้องเป็น Server-Only:**

1. **Regime Gate คือเงื่อนไขจำเป็น** — ถ้าตลาดไม่ใช่ TRENDING การใช้ Ichimoku จะสร้าง False Signal เป็นจำนวนมาก Brain ต้องยืนยัน Regime ก่อน
2. **3 iIchimoku Handles ต้องการ Configuration ที่ถูกต้อง** — การสร้าง Handle 3 ชุดโดยไม่รู้ว่า Symbol มี Volatility แค่ไหน อาจทำให้ Period ไม่เหมาะสม (Cloud บางเกินไปหรือหนาเกินไป)
3. **TF Weights ควรปรับตาม Trend Strength** — ในช่วง Early Trend H1 ควรมีน้ำหนักมากกว่า ในช่วง Mature Trend D1 ควรครอบงำ Brain เป็นผู้ตัดสินใจเรื่องนี้

---

### 3.2 ความสัมพันธ์ระหว่าง S11 กับกลยุทธ์อื่น

```
ใน Portfolio ของ FlashEASuite V2:

TRENDING Regime:
  S11 (Ichimoku, MTF)   ← กลยุทธ์หลักที่ใช้ Trend
  S10 (Turtle)          ← Trend Following แบบ Classic Breakout
  S06 (KAMA)            ← Adaptive MA Trend

RANGING Regime:
  S07 (Mean Reversion)  ← ทำงานแทน S11 ในสภาวะ Ranging
  S01 (Stat Arb)        ← Mean Reversion แบบคู่เงิน

S11 จะ "แข่งขัน" กับ S10 และ S06 ใน TRENDING Regime
Brain จัดสรรน้ำหนักให้แต่ละตัวตาม Historical Performance
```

---

## 4. การไหลของข้อมูลทั้งระบบ (Full System Dataflow)

### 4.1 เส้นทางสมบูรณ์จาก Tick ถึง Order

```
[ตลาด Forex] → [MT5 Platform] → [FeederEA] → Port 7777 → [Python Brain]
                                                              ↓
                                                  [Regime Classifier]
                                                  (HMM / Random Forest)
                                                              ↓
                                              TRENDING? ──YES→ [S11 Included]
                                                   ↓ NO
                                              [S11 Excluded (weight=0)]
                                                              ↓
                                                  [S11 Period Optimizer]
                                                  Scan Tenkan 7-13
                                                  Scan Kijun 21-34
                                                  Backtest on InfluxDB OHLC
                                                              ↓
                                                  [Cloud Min Width Tuning]
                                                  ปรับตาม ATR ของ Symbol
                                                              ↓
                                                  [TF Weight Adjustment]
                                                  D1/H4/H1 สัดส่วนตาม Trend
                                                              ↓
                                                  [AI Council Gate]
                                                  weighted_conf ≥ 0.50?
                                                  R:R ≥ 1.5?
                                                              ↓
                                                  [CONFIG_PUSH] Port 7778
                                                              ↓
                                              [ProgramC_Trader.mq5]
                                              CIchimoku::UpdateParams()
                                                              ↓
                                              [Rebuild 3 iIchimoku Handles]
                                              ถ้า Period เปลี่ยน + iATR H1
                                                              ↓
                                              [m_enabled = true]
                                                              ↓
                                              [OnTick: Analyze() ทุก Tick]
                                              ├─ _ReadIchimoku(D1) → m_d1
                                              ├─ _ReadIchimoku(H4) → m_h4
                                              └─ _ReadIchimoku(H1) → m_h1
                                                              ↓
                                              [_GetD1Trend()] → +1/0/-1
                                              [_GetH4Trend()] → +1/0/-1
                                              D1 == H4? ──NO─→ SIGNAL_NONE
                                                              ↓ YES
                                              [Cloud Width Filter]
                                              < 10 pips? ──YES→ SIGNAL_NONE
                                                              ↓ NO
                                              [Price vs Cloud Check]
                                              Price บนฝั่งที่ถูก?
                                                              ↓
                                              [H1 Cross Detection (Bar-Gated)]
                                              Fresh Cross? ──NO→ SIGNAL_NONE
                                                              ↓ YES
                                              [Chikou Confirmation]
                                              Chikou ยืนยัน? ──NO→ SIGNAL_NONE
                                                              ↓ YES
                                              [SIGNAL_BUY / SIGNAL_SELL]
                                              + _CalcConfidence()
                                                              ↓
                                              [MMManager → Lot Sizing]
                                                              ↓
                                              [OrderSend()] → [ตลาด]
                                                              ↓
                                              [ShouldExit() ทุก Tick]
                                              Tenkan/Kijun Cross กลับ?
                                              Price เข้า Cloud?
                                                              ↓
                                              [TRADE_REPORT] Port 7779 → [Brain]
```

---

## 5. ระบบให้คะแนนความเชื่อมั่น (Confidence Scoring System)

### 5.1 สูตร Composite Confidence

```
Confidence = tf_align × 0.6 + cloud_bonus × 0.2 + tk_dist × 0.2

Clamped ให้อยู่ใน [0.0, 1.0]
```

**สูงสุดที่เป็นไปได้:** 1.0×0.6 + 1.0×0.2 + 1.0×0.2 = **1.00** (ก่อนปรับ Regime)

---

### 5.2 องค์ประกอบที่ 1: TF Alignment Score (น้ำหนัก 60%)

```
d1_score = 1.0 ถ้า D1_trend == entry direction, มิฉะนั้น 0.0
h4_score = 1.0 ถ้า H4_trend == entry direction, มิฉะนั้น 0.0
h1_score = 1.0 ถ้า H1_cross == entry direction, มิฉะนั้น 0.0

tf_align = d1_score × w_d1 + h4_score × w_h4 + h1_score × w_h1

Default weights (normalized):
  w_d1 = 0.40 / (0.40 + 0.35 + 0.25) = 0.40 / 1.00 = 0.40
  w_h4 = 0.35
  w_h1 = 0.25
```

**ตัวอย่างการคำนวณ tf_align ในกรณีต่างๆ:**

| D1 | H4 | H1 | tf_align | ความหมาย |
|----|----|----|----------|---------|
| ✅ | ✅ | ✅ | 1.00 | Perfect Alignment |
| ✅ | ✅ | ❌ | 0.75 | D1+H4 align แต่ยังไม่มี H1 Cross |
| ✅ | ❌ | ✅ | 0.65 | D1+H1 align แต่ H4 ไม่ตรง |
| ❌ | ✅ | ✅ | 0.60 | H4+H1 align แต่ D1 ไม่ตรง |
| ✅ | ❌ | ❌ | 0.40 | D1 เท่านั้น — ต่ำมาก |

**หมายเหตุสำคัญ:** แม้ tf_align = 0.75 แต่ถ้า D1 != H4 ระบบจะ Return SIGNAL_NONE ก่อนที่จะคำนวณ Confidence เลย เพราะ "Gate" ที่ตรวจ D1 == H4 มาก่อน

**เหตุผลที่ TF Alignment มีน้ำหนัก 60%:**

TF Alignment คือเงื่อนไขหลักและเงื่อนไขแรกที่ต้องผ่านก่อนทุกสิ่ง ถ้า D1 และ H4 ไม่ตรงกัน ไม่มีเหตุผลใดที่ S11 ควรเข้า Trade โดยไม่คำนึงว่า Cloud หนาแค่ไหน

---

### 5.3 องค์ประกอบที่ 2: Cloud Bonus (น้ำหนัก 20%)

```
cloud_thickness_H1 = Cloud_Top_H1 - Cloud_Bot_H1
ATR_H1 = iATR(symbol, PERIOD_H1, 14, 0)

cloud_bonus = min(1.0, cloud_thickness_H1 / ATR_H1)

ตัวอย่าง:
  cloud_thickness = 0.00150 (15 pips)
  ATR_H1          = 0.00095 (9.5 pips)
  cloud_bonus = min(1.0, 0.00150/0.00095) = min(1.0, 1.578) = 1.00

ตัวอย่างที่ 2:
  cloud_thickness = 0.00050 (5 pips) — Cloud บางมาก
  ATR_H1          = 0.00095
  cloud_bonus = min(1.0, 0.00050/0.00095) = min(1.0, 0.526) = 0.526
```

**เหตุผลที่ใช้ ATR เป็น Normalizer:**

Cloud ที่หนา 15 pips มีนัยสำคัญต่างกันระหว่าง EURUSD (ATR ~9 pips/H1) กับ GBPJPY (ATR ~20 pips/H1) การ Normalize ด้วย ATR ทำให้ Cloud Bonus สะท้อนความหนาสัมพัทธ์ที่เป็นจริง

---

### 5.4 องค์ประกอบที่ 3: Tenkan-Kijun Distance Score (น้ำหนัก 20%)

```
tk_dist = min(1.0, |Tenkan_H1 - Kijun_H1| / (Cloud_Top_H1 - Cloud_Bot_H1))

ตัวอย่าง:
  |Tenkan - Kijun| = 0.00025 (2.5 pips)
  Cloud_Width       = 0.00150 (15 pips)
  tk_dist = min(1.0, 0.00025/0.00150) = 0.167

ตัวอย่างที่ 2 (Strong Cross):
  |Tenkan - Kijun| = 0.00120 (12 pips) — ห่างมาก
  Cloud_Width       = 0.00150
  tk_dist = min(1.0, 0.00120/0.00150) = 0.80
```

**เหตุผล:** ระยะห่างระหว่าง Tenkan และ Kijun บอกถึงความ "แน่วแน่" ของสัญญาณ Cross ที่เพิ่งเกิดขึ้น ถ้า Tenkan พึ่งตัดผ่าน Kijun มาเล็กน้อย (0.5 pips) อาจเป็นแค่ "False Cross" ที่กลับมาได้ แต่ถ้าห่างกัน 10 pips แสดงว่า Momentum แข็งแกร่งจริง

---

### 5.5 ตัวอย่างการคำนวณ Confidence สมบูรณ์

```
ข้อมูล: D1=+1, H4=+1, H1_cross=+1
  Cloud_Top  = 1.08450, Cloud_Bot = 1.08300 (Width = 15 pips)
  Tenkan_H1  = 1.08490, Kijun_H1  = 1.08465 (Gap = 2.5 pips)
  ATR_H1     = 0.00095

tf_align   = 1.0×0.40 + 1.0×0.35 + 1.0×0.25 = 1.000
cloud_bonus = min(1.0, 0.00150/0.00095) = 1.000
tk_dist     = min(1.0, 0.00025/0.00150) = 0.167

Confidence = 1.000×0.6 + 1.000×0.2 + 0.167×0.2
           = 0.600 + 0.200 + 0.033
           = 0.833

─────────────────────────────────────────
Insight: แม้ D1+H4+H1 จะ Align สมบูรณ์
แต่ tk_dist ต่ำ (0.167) ทำให้ Confidence
ไม่ถึง 1.0 เต็ม — สะท้อนว่า Cross ยัง
"เพิ่งเกิด" และอาจย้อนกลับได้ถ้า Gap เล็ก
─────────────────────────────────────────
```

---

### 5.6 ตัวคูณปรับตาม Market Regime

| Regime | ตัวคูณ | เหตุผลทางวิชาการ |
|--------|--------|----------------|
| **TRENDING** | **×1.5** | สภาวะที่ Ichimoku ทำงานดีที่สุด — Cloud หนา ราคาอยู่ห่าง Cloud Tenkan/Kijun Cross ชัดเจน |
| **SQUEEZE** | **×0.8** | ช่วงก่อน Breakout — Ichimoku อาจส่งสัญญาณล่าช้าเพราะ Tenkan/Kijun ยังซ้อนกันใน Narrow Range |
| **RANGING** | **×0.4** | อันตราย — Tenkan/Kijun Cross สุ่มมาก Cloud บาง ราคาเข้าออก Cloud ตลอด |
| **VOLATILE** | **×0.3** | อันตรายที่สุด — ราคาอาจกระโดดข้าม Cloud ในครั้งเดียว ทุก Component ส่งสัญญาณเท็จ |

ตัวอย่าง: ถ้า Confidence ดิบ = 0.75 แต่ Brain ประเมินว่า Regime เป็น RANGING → Confidence = 0.75 × 0.4 = **0.30** ซึ่งต่ำกว่า AI Council Threshold 0.50 → S11 จะไม่ถูกเปิดใช้งาน

---

## 6. MQL5: การทำงานภายในของ CIchimoku

### 6.1 SIchimokuSnapshot — โครงสร้างข้อมูล TF

```mql5
// Data Container สำหรับเก็บค่า Ichimoku ของ TF หนึ่งๆ
struct SIchimokuSnapshot
{
    bool    valid;       // true = อ่านค่าจาก Buffer สำเร็จ
    double  tenkan;      // Tenkan-sen (Buffer 0)
    double  kijun;       // Kijun-sen  (Buffer 1)
    double  senkou_a;    // Senkou Span A (Buffer 2)
    double  senkou_b;    // Senkou Span B (Buffer 3)
    double  chikou;      // Chikou Span (Buffer 4)
    double  cloud_top;   // max(senkou_a, senkou_b)
    double  cloud_bot;   // min(senkou_a, senkou_b)
    double  close;       // Close ล่าสุดของ TF นั้น
};

// ตัวแปร State ใน CIchimoku
SIchimokuSnapshot m_d1;   // D1 Snapshot
SIchimokuSnapshot m_h4;   // H4 Snapshot
SIchimokuSnapshot m_h1;   // H1 Snapshot (ใช้หลัก)
```

### 6.2 _ReadIchimoku — อ่าน Buffer ทุก Tick

```mql5
void _ReadIchimoku(int handle, ENUM_TIMEFRAMES tf,
                   SIchimokuSnapshot &snap)
{
    double buf[1];
    snap.valid = false;

    // อ่าน Tenkan (Buffer 0) ที่แท่ง shift=0 (ปัจจุบัน)
    if(CopyBuffer(handle, 0, 0, 1, buf) != 1) return;
    snap.tenkan  = buf[0];

    if(CopyBuffer(handle, 1, 0, 1, buf) != 1) return;
    snap.kijun   = buf[0];

    if(CopyBuffer(handle, 2, 0, 1, buf) != 1) return;
    snap.senkou_a = buf[0];

    if(CopyBuffer(handle, 3, 0, 1, buf) != 1) return;
    snap.senkou_b = buf[0];

    if(CopyBuffer(handle, 4, 0, 1, buf) != 1) return;
    snap.chikou  = buf[0];

    // คำนวณ Cloud
    snap.cloud_top = MathMax(snap.senkou_a, snap.senkou_b);
    snap.cloud_bot = MathMin(snap.senkou_a, snap.senkou_b);

    // อ่าน Close ของ TF นั้น
    double close_arr[1];
    if(CopyClose(m_symbol, tf, 0, 1, close_arr) != 1) return;
    snap.close = close_arr[0];

    snap.valid = true;
}
```

### 6.3 D1 Trend Detection

```mql5
int _GetD1Trend(const SIchimokuSnapshot &s)
{
    if(!s.valid) return 0;

    bool price_above_cloud = (s.close > s.cloud_top);
    bool price_below_cloud = (s.close < s.cloud_bot);

    // Bullish: ราคาอยู่เหนือ Cloud AND Tenkan ≥ Kijun
    if(price_above_cloud && s.tenkan >= s.kijun) return +1;

    // Bearish: ราคาอยู่ใต้ Cloud AND Tenkan ≤ Kijun
    if(price_below_cloud && s.tenkan <= s.kijun) return -1;

    // Neutral: ราคาอยู่ใน Cloud หรือ Signal ขัดแย้ง
    return 0;
}
```

### 6.4 H1 Cross Detection — Bar-Gated

```mql5
// อ่าน 2 แท่ง (bar 1=ปิดล่าสุด, bar 2=ก่อนนั้น)
// ตรวจ "เพิ่งเกิด" Cross — ไม่ใช่ Cross ที่เกิดแล้วหลายแท่ง
int _GetH1CrossSignal(int handle)
{
    double tenkan[2], kijun[2];
    if(CopyBuffer(handle, 0, 1, 2, tenkan) != 2) return 0;  // shift 1,2
    if(CopyBuffer(handle, 1, 1, 2, kijun)  != 2) return 0;

    // tenkan[0] = แท่งที่ปิดล่าสุด (shift=1)
    // tenkan[1] = แท่งก่อนนั้น (shift=2)

    bool bullish_cross = (tenkan[1] <= kijun[1]) && (tenkan[0] > kijun[0]);
    bool bearish_cross = (tenkan[1] >= kijun[1]) && (tenkan[0] < kijun[0]);

    if(bullish_cross) return +1;
    if(bearish_cross) return -1;
    return 0;
}

// Bar Gate — ป้องกัน Re-trigger บน Bar เดิม
datetime current_h1_bar = iTime(m_symbol, PERIOD_H1, 1);
if(current_h1_bar != m_last_h1_cross_bar)
{
    int cross = _GetH1CrossSignal(m_iku_h1_handle);
    if(cross != 0)
    {
        m_last_h1_cross_bar = current_h1_bar;
        m_h1_signal = cross;
    }
    else
        m_h1_signal = 0;  // ไม่มี Fresh Cross — Reset
}
```

**เหตุผลที่ต้อง Bar-Gate:**

ถ้าไม่มี Gate ใน 1 H1 Bar (60 นาที) จะมี Tick หลายร้อยครั้ง ทุก Tick จะ "เห็น" Cross เดิมซ้ำๆ และอาจสร้างออเดอร์หลายรายการจาก Cross ครั้งเดียว Bar Gate ตรวจว่า Cross ที่เห็นอยู่บน Bar ใหม่หรือ Bar เดิม ถ้า Bar เดิมจะไม่นับซ้ำ

### 6.5 Chikou Confirmation

```mql5
bool _ChikouConfirmed(int handle, int direction)
{
    double chikou_buf[1], price_ago[1];

    // Buffer 4 = Chikou Span, shift=1 (แท่งที่ปิดล่าสุด)
    if(CopyBuffer(handle, 4, 1, 1, chikou_buf) != 1) return false;

    // Close ที่ตำแหน่ง (m_chikou_shift + 1) แท่งก่อนหน้า
    if(CopyClose(m_symbol, PERIOD_H1,
                 m_chikou_shift + 1, 1, price_ago) != 1) return false;

    if(direction > 0) return chikou_buf[0] > price_ago[0];
    if(direction < 0) return chikou_buf[0] < price_ago[0];
    return false;
}
```

### 6.6 Exit Logic — Dynamic Exit

```mql5
// เรียกทุก Tick เพื่อตรวจสอบว่าควรออก
bool ShouldExit(int position_direction)
{
    if(!m_h1.valid) return false;

    // Tenkan/Kijun Cross กลับทิศ = สัญญาณ Trend อ่อนแรง
    if(position_direction > 0 && m_h1.tenkan < m_h1.kijun) return true;
    if(position_direction < 0 && m_h1.tenkan > m_h1.kijun) return true;
    return false;
}

// ราคากลับเข้า Cloud = สัญญาณ Trend สิ้นสุด
bool ShouldExitPrice(double current_price, int position_direction)
{
    if(position_direction > 0 && current_price < m_h1.cloud_top) return true;
    if(position_direction < 0 && current_price > m_h1.cloud_bot) return true;
    return false;
}
```

**ความสำคัญของ Dynamic Exit:**

S11 ไม่มี Fixed TP — Exit จะเกิดขึ้นเมื่อ Ichimoku เองบอกว่า "Trend สิ้นสุดแล้ว" ทำให้:
- ออกได้เร็วถ้า Trend อ่อนลง (ป้องกันการคืนกำไร)
- สามารถถือได้นานหาก Trend ยังแข็งแกร่ง (คว้ากำไรมาก)
- Adaptive ตามสภาวะตลาดจริง ไม่ใช่ Fixed 30 pips

### 6.7 Handle Rebuild เมื่อ Period เปลี่ยน

```mql5
void UpdateParams(const SDynamicParams &params)
{
    bool needs_reinit = false;

    int new_tenkan = params.GetInt("S11_TENKAN", m_tenkan_period);
    int new_kijun  = params.GetInt("S11_KIJUN",  m_kijun_period);
    int new_senb   = params.GetInt("S11_SENKOU_B", m_senkou_b_period);

    // ตรวจว่า Period เปลี่ยนจริงหรือไม่
    if(new_tenkan != m_tenkan_period ||
       new_kijun  != m_kijun_period  ||
       new_senb   != m_senkou_b_period)
    {
        m_tenkan_period   = new_tenkan;
        m_kijun_period    = new_kijun;
        m_senkou_b_period = new_senb;
        needs_reinit = true;
    }

    // พารามิเตอร์ที่อัปเดตได้ทันที (ไม่ต้อง Reinit)
    m_chikou_shift  = params.GetInt("S11_CHIKOU_SHIFT", m_chikou_shift);
    m_cloud_min_width = params.GetDouble("S11_CLOUD_MIN", m_cloud_min_width);

    // TF Weights — ต้อง Normalize
    m_tf_d1_weight = params.GetDouble("S11_TF_D1_W", m_tf_d1_weight);
    m_tf_h4_weight = params.GetDouble("S11_TF_H4_W", m_tf_h4_weight);
    m_tf_h1_weight = params.GetDouble("S11_TF_H1_W", m_tf_h1_weight);

    double w_sum = m_tf_d1_weight + m_tf_h4_weight + m_tf_h1_weight;
    if(w_sum > 0.0)
    {
        m_tf_d1_weight /= w_sum;
        m_tf_h4_weight /= w_sum;
        m_tf_h1_weight /= w_sum;
    }

    // Rebuild 3 Handles ถ้า Period เปลี่ยน
    if(needs_reinit) _InitIndicators();

    m_enabled = true;  // Enable หลังได้รับ CONFIG_PUSH ครั้งแรก
}
```

---

## 7. ตารางพารามิเตอร์อ้างอิงฉบับสมบูรณ์ (Parameter Reference)

### 7.1 พารามิเตอร์ MQL5 Input

| Parameter | Default | ช่วงที่แนะนำ | คำอธิบายเชิงลึก |
|-----------|---------|------------|----------------|
| `IKU_Tenkan_Period` | 9 | 5–20 | Period ของ Tenkan-sen (เส้นเร็ว) ค่าน้อย (5) → ตอบสนองเร็วแต่ Noisy มาก ค่ามาก (15) → ช้าแต่แม่นยำในตลาดช้า |
| `IKU_Kijun_Period` | 26 | 13–52 | Period ของ Kijun-sen (เส้นช้า) ควรรักษา Ratio Kijun/Tenkan ≈ 3:1 เสมอ เช่น 9:26, 7:21, 12:36 |
| `IKU_Senkou_B_Period` | 52 | 26–104 | Period ของ Senkou B (Cloud ด้านไกล) ควรรักษา Ratio SenkouB/Kijun ≈ 2:1 เช่น 52:26, 42:21 |
| `IKU_Chikou_Shift` | 26 | 13–52 | จำนวนแท่งที่ใช้ย้อนหลังสำหรับ Chikou Comparison ปกติใช้ค่าเดียวกับ Kijun Period |
| `IKU_Cloud_Min_Width` | 10.0 | 5–30 | ความหนาขั้นต่ำของ Cloud (pips) ก่อนจะถือว่ามี Support/Resistance ที่น่าเชื่อถือ ค่าน้อย (5) → เข้าได้บ่อยขึ้นแต่ Cloud บาง / ค่ามาก (20) → เข้าน้อยแต่แต่ละ Trade มี S/R แน่นกว่า |
| `IKU_TF_D1_Weight` | 0.40 | 0.1–0.8 | น้ำหนัก D1 ใน tf_align ค่าสูง → ให้ D1 มีอิทธิพลมากขึ้น เหมาะกับ Mature Trend |
| `IKU_TF_H4_Weight` | 0.35 | 0.1–0.7 | น้ำหนัก H4 ใน tf_align |
| `IKU_TF_H1_Weight` | 0.25 | 0.1–0.5 | น้ำหนัก H1 ใน tf_align ค่าสูง → ให้ H1 Cross มีความสำคัญมากขึ้น เหมาะกับ Early Trend ที่ D1 ยังไม่ชัดเจน |

**กฎ Golden Ratio ของ Ichimoku:**
```
Tenkan : Kijun : SenkouB = 1 : 3 : 6  (โดยประมาณ)
Default: 9 : 26 : 52 ≈ 1 : 2.9 : 5.8  ✅
ถ้าปรับ Tenkan = 7 ควรปรับ Kijun = 21, SenkouB = 42 ด้วย
```

### 7.2 CONFIG_PUSH Keys (Server Mode)

| Key | ประเภท | Default | ผลกระทบทันที |
|-----|--------|---------|-------------|
| `S11_TENKAN` | int | 9 | ต้อง Rebuild Handles ทั้ง 3 ชุด |
| `S11_KIJUN` | int | 26 | ต้อง Rebuild Handles ทั้ง 3 ชุด |
| `S11_SENKOU_B` | int | 52 | ต้อง Rebuild Handles ทั้ง 3 ชุด |
| `S11_CHIKOU_SHIFT` | int | 26 | อัปเดตทันที — ไม่ต้อง Rebuild |
| `S11_CLOUD_MIN` | float | 10.0 | อัปเดตทันที — ผล: Filter เข้ม/หลวมขึ้น |
| `S11_TF_D1_W` | float | 0.40 | อัปเดต + Normalize ทันที |
| `S11_TF_H4_W` | float | 0.35 | อัปเดต + Normalize ทันที |
| `S11_TF_H1_W` | float | 0.25 | อัปเดต + Normalize ทันที |

### 7.3 MQL5 Buffer Index Map (iIchimoku)

| Buffer Index | Content | ใช้งานใน S11 |
|-------------|---------|-------------|
| 0 | Tenkan-sen | `_ReadIchimoku()`, Cross Detection |
| 1 | Kijun-sen | `_ReadIchimoku()`, Cross Detection, D1/H4 Trend |
| 2 | Senkou Span A | `_ReadIchimoku()`, Cloud Top/Bot |
| 3 | Senkou Span B | `_ReadIchimoku()`, Cloud Top/Bot |
| 4 | Chikou Span | `_ChikouConfirmed()` |

---

## 8. โหมดการทำงาน (Operating Modes)

### 8.1 Disabled Mode (ก่อนได้รับ CONFIG_PUSH)

```
CIchimoku::Init() เรียกตอน EA เริ่มต้น:
  → m_enabled = false
  → Handles สร้างด้วยค่า Default (Tenkan=9, Kijun=26, SenkouB=52)
  → ยังไม่ทำงาน — รอ CONFIG_PUSH

ทุก OnTick():
  → StrategyManager ตรวจ m_enabled ก่อน
  → ถ้า false → ข้าม S11 ไปเลย

ทันทีที่ได้รับ CONFIG_PUSH แรก:
  → UpdateParams() เรียก
  → m_enabled = true
  → S11 เริ่มวิเคราะห์ Tick ถัดไป
```

### 8.2 Server Mode (Full Operation)

```
Brain ทำงาน 24 ชั่วโมงต่อวัน ทุกรอบ Optimization Cycle:

1. Regime Classifier ประเมินสภาวะตลาด
   TRENDING → S11 เข้ารอบ
   RANGING/VOLATILE → S11 ถูก Exclude

2. ถ้า S11 ถูก Include:
   a. ดึง OHLC ล่าสุดจาก InfluxDB
   b. Backtest Ichimoku ด้วย Tenkan 7-13, Kijun 21-34
   c. เลือก Period ที่ให้ Risk-Adjusted Return สูงสุด
   d. ปรับ Cloud_Min_Width ตาม ATR เฉลี่ยของ Symbol
   e. ปรับ TF Weights ตาม Trend Maturity

3. AI Council ตัดสิน:
   weighted_confidence ≥ 0.50?
   ประวัติ Win Rate ของ S11 ≥ Threshold?

4. ถ้าผ่าน: ส่ง CONFIG_PUSH Port 7778
5. S11 อัปเดต Params + เริ่มส่งสัญญาณ

6. Trade Report กลับมาผ่าน Port 7779
7. PerformanceTracker อัปเดต S11 EMA Weight
8. Weight ใหม่ส่งผลต่อการจัดสรรของ AI Council รอบต่อไป
```

### 8.3 Failsafe เมื่อ Brain ขาดการเชื่อมต่อ

```
ขั้นตอนที่ 1: CConnectionMonitor ตรวจจับว่า Brain หายไป
ขั้นตอนที่ 2: CStandaloneSelector ทำงาน
ขั้นตอนที่ 3: S11 ถูก Exclude ทันที (m_enabled = false)
ขั้นตอนที่ 4: ออเดอร์ที่เปิดอยู่ของ S11?
  → ไม่ปิดอัตโนมัติ — ยังคงถือต่อและตรวจ ShouldExit ทุก Tick
  → เพราะ ShouldExit ทำงานได้ด้วยข้อมูล Indicator ที่มีอยู่แล้ว
ขั้นตอนที่ 5: เมื่อ Brain กลับมา → CONFIG_PUSH ใหม่ → m_enabled = true
```

---

## 9. ตรรกะการเข้า-ออกสถานะ (Entry/Exit Logic Summary)

| ขั้นตอน | เงื่อนไข | ผลลัพธ์ |
|---------|---------|--------|
| **1. Regime Gate (Brain)** | TRENDING ไหม? | ไม่ผ่าน → S11 Excluded |
| **2. D1 + H4 Alignment** | D1 != 0 AND D1 == H4 | ไม่ผ่าน → SIGNAL_NONE ทันที |
| **3. H1 Cloud Width** | Width ≥ 10 pips | ไม่ผ่าน → SIGNAL_NONE |
| **4. Price vs H1 Cloud** | Long: Close > Cloud_Top / Short: Close < Cloud_Bot | ไม่ผ่าน → SIGNAL_NONE |
| **5. H1 Tenkan/Kijun Cross** | Fresh Cross (Bar-Gated) ตรงทิศทาง | ไม่ผ่าน → SIGNAL_NONE |
| **6. Chikou Confirmation** | Chikou ยืนยันทิศทาง | ไม่ผ่าน → SIGNAL_NONE |
| **ทั้ง 6 ผ่าน** | — | SIGNAL_BUY / SIGNAL_SELL + Confidence |
| **Exit — TK Cross** | Tenkan/Kijun กลับทิศ (H1) | ShouldExit = true → ปิดสถานะ |
| **Exit — Cloud Re-entry** | ราคากลับเข้า Cloud H1 | ShouldExitPrice = true → ปิดสถานะ |

---

## 10. การบูรณาการกับ Money Manager (MM Integration)

### 10.1 SMMSelection สำหรับ S11

```mql5
// ใน MMManager.mqh: S11 Default MM Selection
SMMSelection s11_mm_sel;
s11_mm_sel.default_mm  = MM02;  // Percent Risk — เหมาะกับ Trade ระยะยาวของ S11
s11_mm_sel.volatile_mm = MM07;  // Percent Volatility — ลด Lot เมื่อ ATR สูง
s11_mm_sel.dd_mm       = MM10;  // DrawdownBased — ป้องกัน Drawdown ฉุกเฉิน
```

**เหตุผลที่ S11 ใช้ MM02 (Percent Risk) เป็น Default:**

S11 มักถือสถานะนานหลายชั่วโมงถึงหลายวัน SL ที่กว้าง (ATR-based) ทำให้ Fixed Lot จะเสี่ยงมากเกินไป MM02 คำนวณ Lot ตาม % Risk ของ Account Balance ทำให้ Risk ต่อ Trade คงที่ไม่ว่า SL จะกว้างแค่ไหน

### 10.2 ลำดับความสำคัญในการเลือก MM

```
Priority 1 (สูงสุด): Drawdown Emergency (DD ≥ 10%)
  → MM10 (DrawdownBased) ทันที
  → ลด Lot 50-75% เพื่อป้องกัน Blowup

Priority 2: Server Override
  → Brain ส่ง mm_method ใน CONFIG_PUSH
  → ใช้ mm_method ที่ Brain กำหนด

Priority 3: Regime Volatile/Squeeze
  → MM07 (Percent Volatility)
  → ATR สูง → Lot ต่ำลง

Priority 4 (ต่ำสุด): Default
  → S11 ใช้ MM02 (Percent Risk)
```

---

## 11. คุณสมบัติเชิงประสิทธิภาพ (Performance Characteristics)

| ด้าน | รายละเอียด |
|-----|-----------|
| **สภาวะตลาดที่ดีที่สุด** | Trending แรงและต่อเนื่อง D1+H4+H1 ชี้ทิศทางเดียวกัน Cloud หนา > 15 pips |
| **สภาวะตลาดที่แย่ที่สุด** | Ranging — Cloud บาง Tenkan/Kijun Cross สุ่ม ราคาเข้าออก Cloud ตลอด |
| **ความถี่สัญญาณ** | ต่ำถึงปานกลาง — 6 เงื่อนไขกรองไว้เข้มงวดมาก (ดีในแง่ Signal Quality) |
| **ระยะเวลาถือสถานะทั่วไป** | 4–48 ชั่วโมง (H1 Trigger แต่ D1 Context ทำให้อยู่นาน) |
| **เป้าหมาย Win Rate** | 55–65% (คุณภาพสูงแต่ไม่สูงมากเพราะ Market ไม่ได้ Trend ตลอด) |
| **R:R Profile** | Dynamic ผ่าน TK Cross Exit — มักได้ R:R > 2.0 ในช่วง Strong Trend |
| **SL Type** | ATR-based จาก StrategyManager (ไม่ใช่ตัว CIchimoku เอง) |
| **TP Type** | Dynamic — TK Cross หรือ Cloud Re-entry (ไม่มี Fixed TP) |
| **Indicator Handles** | 4 ตัว: iIchimoku(D1) + iIchimoku(H4) + iIchimoku(H1) + iATR(H1) |
| **Server Dependency** | Required — Disabled จนกว่าจะได้รับ CONFIG_PUSH |
| **Standalone** | ❌ ไม่รองรับ |

---

## 12. ไฟล์อ้างอิงในระบบ (Files Reference)

| ไฟล์ | หน้าที่ |
|-----|-------|
| `Include/Logic/Strategies/S11_Ichimoku.mqh` | `CIchimoku` class + `SIchimokuSnapshot` struct — ตรรกะ 3-TF ทั้งหมด |
| `Include/Logic/IStrategy.mqh` | Abstract base class: `IStrategy`, `SDynamicParams` |
| `Include/Logic/StrategyConstants.mqh` | `S11_ICHIMOKU` enum, `MAGIC_S11_ICHIMOKU = 1011`, g_strategy_table[10] |
| `Include/Logic/MM/MMManager.mqh` | `CMMManager` — SMMSelection สำหรับ S11 (MM02 default) |
| `03_Trader/ProgramC_Trader.mq5` | Main EA — สร้าง CIchimoku, Route CONFIG_PUSH, ตรวจ ShouldExit |
| `02_Brain/core/intelligence/strategy_council.py` | AI Council — TRENDING Regime Gate, Weight × Confidence |
| `02_Brain/config_push/config_builder.py` | สร้าง CONFIG_PUSH สำหรับ S11 (Periods + Weights) |
| `02_Brain/core/execution_listener.py` | รับ TRADE_REPORT จาก S11 ผ่าน Port 7779 |
| `02_Brain/core/performance_tracker.py` | ติดตาม Win Rate ของ S11 แยกตาม Regime |

---

## 13. ข้อวิพากษ์และแนวทางการปรับปรุง (Critique & Optimization)

### 13.1 ปัญหาเชิงโครงสร้าง

**ปัญหาที่ 1: Lagging ของ Ichimoku ใน Fast Market**

Ichimoku ทั้งหมดใช้ Midpoint ของ High-Low Range ซึ่งเป็น Lagging Indicator โดยธรรมชาติ ในตลาดที่เปลี่ยนทิศทางเร็ว (เช่นช่วงข่าว NFP) สัญญาณ Ichimoku มักมาช้า 1-3 แท่ง ทำให้ Entry ที่ราคาแพงขึ้นหรือถูกลงแล้ว ลด R:R ลงจากที่ควรจะได้

**แนวทางแก้ไข:** ลด Tenkan Period เมื่อตลาดมีสัญญาณ News Event เพื่อให้ Tenkan ตอบสนองเร็วขึ้น Brain สามารถปรับผ่าน CONFIG_PUSH ก่อนช่วง High-Impact News

**ปัญหาที่ 2: 6 เงื่อนไขเข้มงวดเกินไปในบางสภาวะ**

การที่ Chikou ต้องผ่านทุกครั้ง ทำให้ในช่วง Range-to-Trend Transition (ช่วงที่ตลาดเพิ่งเปลี่ยนจาก Ranging ไป Trending) Chikou มักยังไม่ยืนยัน เพราะราคา 26 แท่งที่แล้วยังอยู่ในโซน Range ทำให้พลาด Entry จุดที่ดีที่สุด (ต้น Trend)

**แนวทางแก้ไข:** ใน Early Trend Regime ควรลดน้ำหนัก Chikou หรือ Allow Partial Pass โดยให้ Confidence Penalty แทนการ Reject ทันที

**ปัญหาที่ 3: Thin Cloud = Skip แต่ไม่มี Signal คุณภาพสูงทดแทน**

เมื่อ Cloud Width < 10 pips S11 จะไม่เข้า Trade ซึ่งถูกต้อง แต่บางครั้งในช่วงที่ตลาด Compress ก่อน Breakout (Squeeze) Cloud อาจบางได้นาน 2-3 วัน ทำให้ S11 ไม่ทำงานเลยในช่วงนั้น

**แนวทางแก้ไข:** เพิ่ม Mode "Cloud Expanding" — ถ้า Cloud กำลังขยายตัวจาก Thin ไป Thick ให้ลด Threshold ชั่วคราวเพื่อจับ Early Entry ของ Breakout

**ปัญหาที่ 4: D1 Signal ช้ามาก ใน Intraday Context**

D1 Ichimoku ใช้ Data หลายวัน ทำให้ D1 Trend เปลี่ยนแปลงช้ามาก บางครั้ง H4 + H1 บอก Bullish แต่ D1 ยังบอก Bearish จาก Trend เดือนที่แล้ว ทำให้ S11 พลาด Trade ที่ดีจำนวนมากในสัปดาห์ที่ตลาดกำลัง "เปลี่ยนทิศ"

**แนวทางแก้ไข:** Brain ควรปรับ TF Weights ตาม Trend Age — ถ้า Trend อ่อนแอหรือกำลังเริ่มใหม่ ลด D1 Weight จาก 0.40 เป็น 0.20 แล้วเพิ่ม H4 Weight เป็น 0.50 เพื่อให้ responsive ขึ้น

### 13.2 เปรียบเทียบ S11 กับ S10 Turtle ใน TRENDING Regime

| ด้าน | S11 (Ichimoku) | S10 (Turtle) |
|-----|---------------|-------------|
| Entry Style | 6-condition filter (Conservative) | Donchian Channel Breakout |
| Signal Frequency | ต่ำ | สูงกว่า (Breakout บ่อยกว่า) |
| False Signal | น้อย (6 gates) | ปานกลาง (Whipsaw ได้) |
| Lag | สูง (Midpoint-based) | ต่ำ (ตาม High/Low เลย) |
| Exit | Dynamic (TK Cross) | Trailing (Donchian 10-bar) |
| Best For | Mature, Clean Trend | Early Breakout Detection |

**แนะนำ:** ใช้ทั้ง S10 และ S11 ร่วมกันใน TRENDING Regime — S10 จับ Early Breakout ก่อน แล้ว S11 เป็น "Confirmation Trade" ตามมาหลัง Trend Confirm

### 13.3 ความถี่การ Optimize ที่แนะนำ

| พารามิเตอร์ | ความถี่ที่แนะนำ | เหตุผล |
|------------|--------------|-------|
| Tenkan Period | ทุก 1-2 สัปดาห์ | Tenkan ไม่เปลี่ยนบ่อย — ปรับเฉพาะถ้า Market Cycle เปลี่ยน |
| Kijun/SenkouB | ทุกเดือน | Period ยาว — เปลี่ยนน้อยมาก |
| Cloud Min Width | ทุกวัน | ปรับตาม ATR เฉลี่ยของวัน Symbol |
| TF Weights | ทุก 4-8 ชั่วโมง | ปรับตาม Trend Maturity/Strength |
| Chikou Shift | แทบไม่เปลี่ยน | ควรเท่ากับ Kijun Period เสมอ |

---

## 14. การวินิจฉัยระบบอย่างรวดเร็ว (Quick Diagnostics)

### ตรวจสอบสถานะการเริ่มต้น

```bash
# MetaTrader 5 → Experts log → filter "[S11]"

# ก่อนได้รับ CONFIG_PUSH:
[S11] Init OK (DISABLED) | EURUSD | D1/H4/H1 Ichimoku | Tenkan=9 Kijun=26

# หลังได้รับ CONFIG_PUSH:
[S11] Params updated | Tenkan=9 Kijun=26 SenkouB=52 Chikou=26
      CloudMin=10.0 | D1w=0.40 H4w=0.35 H1w=0.25 (normalized)
[S11] ENABLED — ready to analyze
```

### ตรวจสอบ Multi-TF Status แบบสมบูรณ์

```mql5
// เรียก PrintIchimokuStatus() ใน MQL5:
ichimoku_strategy.PrintIchimokuStatus();

// Expected Output:
[S11] ===== Ichimoku Multi-TF Status =====
[S11] D1  | Trend=+1 | Close=1.08520 vs Cloud [1.07800 - 1.08100]
           | Tenkan=1.08450 Kijun=1.08200 | Above Cloud ✅
[S11] H4  | Trend=+1 | Close=1.08510 vs Cloud [1.08200 - 1.08400]
           | Tenkan=1.08480 Kijun=1.08350 | Above Cloud ✅
[S11] H1  | Signal=+1 | Close=1.08505 vs Cloud [1.08300 - 1.08450]
           | Width=15.0 pips (>= 10.0 ✅)
           | Tenkan=1.08490 Kijun=1.08465 | TK_dist=2.5 pips
           | Cross: BarTime=2026.02.28 10:00 ✅ (Fresh)
           | Chikou=1.08500 vs Past_Close=1.08120 → Above ✅
[S11] Alignment: D1=+1 H4=+1 H1_entry=+1 | ALL PASS
[S11] Confidence: tf_align=1.000 cloud_bonus=1.000 tk_dist=0.167
[S11] Confidence = 0.833 | Signal=BUY
```

### ตรวจสอบ CONFIG_PUSH มี S11 หรือไม่

```bash
python tools/validate_live_readiness.py --zmq
# ดูที่ TEST 5: CONFIG_PUSH dry-run
# ควรเห็น S11_TENKAN, S11_KIJUN, S11_SENKOU_B,
#           S11_CLOUD_MIN, S11_TF_D1_W ใน Output
```

### ตรวจสอบ Brain ว่า S11 ถูก Include หรือ Exclude

```bash
python 02_Brain/dashboard.py
# ดูที่ "Strategy Weights" panel
# S11 ควรมี Weight > 0 เฉพาะเมื่อ Regime = TRENDING
# ถ้า S11 Weight = 0 ตรวจสอบ Regime ว่า Brain ประเมินเป็น RANGING หรือไม่
```

### ปัญหาที่พบบ่อยและวิธีแก้

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-----------------|--------|
| S11 ไม่เคยเปิด Trade เลย | ไม่ได้รับ CONFIG_PUSH (m_enabled=false) | ตรวจ PORT 7778 Connection, ตรวจ Brain Log |
| S11 Enabled แต่ SIGNAL_NONE ตลอด | D1 != H4 (Trend ไม่ตรงกัน) หรือ Regime ไม่ Trending | ดู PrintIchimokuStatus ว่า D1/H4 Trend เท่าไหร่ |
| Cloud Width ไม่ผ่าน (< 10 pips) | ตลาดอยู่ใน Squeeze/Ranging | รอ Trend ชัดขึ้น หรือลด IKU_Cloud_Min_Width ชั่วคราว |
| Chikou ไม่ผ่านทุกครั้ง | ตลาดเพิ่งเปลี่ยน Trend จาก Ranging | รอ 26 แท่งให้ Chikou ผ่านพ้นโซน Range เดิม |
| Trade เปิดแล้วปิดเร็วมาก | TK Cross กลับทิศเร็ว — Trend อ่อนแอ | ตรวจว่า Regime เป็น TRENDING จริงหรือไม่ใน Brain |
| Handle Rebuild บ่อยผิดปกติ | Brain ส่ง Period เปลี่ยนทุก Cycle | ตรวจ config_builder.py — ส่งเฉพาะเมื่อ Period เปลี่ยนจริง |
| Confidence ต่ำเสมอ | tk_dist ต่ำ (TK Gap เล็ก) | ปกติในช่วง Early Cross — รอ TK Gap ขยายออก |

---

*S11 Multi-Timeframe Ichimoku — FlashEASuite V2 | Jimmi Deep-Dive Edition | Phase P9-5 | 2026-02-28*
*ผู้จัดทำ: Lead System Architect & Quant Developer | Dr. Suksaeng Kunanok*
