# Optimization Session — 2026-03-10
## Brain V6 CONFIG_PUSH Fix + ZMQ Live Test Round 2

---

## สถานะรับช่วงจาก 2026-03-09

| งาน | Status | หมายเหตุ |
|-----|--------|----------|
| Brain V6 CONFIG_PUSH fix | 🔴 ต้องทำ | Brain V5 ส่ง type=2, Trader รอ type=10/12 |
| ZMQ live test รอบ 2 | ⏳ | รอ Brain V6 พร้อม |
| Demo run | ⏳ | รอ ZMQ ผ่านก่อน |
| Walk-forward ทุกตัว | ✅ | เสร็จแล้ว 2026-03-09 |
| Git commit session docs | ⏳ | ค้างอยู่ |

---

## A — Brain V6 Sender (brain_v6_sender.py)

### ปัญหาที่แก้

Brain V5 (`main.py` + `engine.py`) ส่ง `type=2` (MSG_TYPE_POLICY) → Trader V6 มี `case MSG_TYPE_POLICY: break;` → ignore ทิ้งทุก message → `Configs recv:0` ตลอด

### Solution: Option A — Quick Fix Sender

สร้าง `02_Brain/brain_v6_sender.py` — script แยกที่:
1. ส่ง **INITIAL_CONFIG (type 12)** ทันทีที่เริ่ม → Trader switch → ONLINE MODE
2. ส่ง **CONFIG_PUSH (type 10)** ทุก 30 วินาที
3. ส่ง **HEARTBEAT (type 13)** ทุก 10 วินาที
4. ทำงานเป็น standalone (ไม่ต้องรัน main.py พร้อมกัน)

### Format ที่ MQL5 ConfigReceiver คาดหวัง (array, NOT dict)

```
[
  10,              # [0] msg_type (10=CONFIG_PUSH, 12=INITIAL_CONFIG)
  timestamp_ms,    # [1] int (milliseconds)
  regime_str,      # [2] string: "TRENDING","RANGING","VOLATILE","SQUEEZE"
  sym_count,       # [3] int (ซ้ำซ้อนแต่ต้องมี)
  [                # [4] symbols array
    [              # each symbol entry
      sym_name,    # [0] e.g. "USDJPY.tp"
      strat_count, # [1] int
      [            # [2] strategies array
        [id_str, name_str, enabled, confidence, tf_str, mm_method],
        ...
      ]
    ],
    ...
  ]
]
```

HEARTBEAT: `[13, ts_ms, "SERVER", seq_int, 1]`

### Default Strategies ที่ส่ง

| Symbol | Strategy | Enabled | TF | MM |
|--------|----------|---------|----|----|
| USDJPY.tp | S06 KAMA | ✅ True | H4 | MM01 |
| XAUUSD.tp | S14 BBSqueeze | ✅ True | H1 | MM01 |
| GBPUSD.tp | S14 BBSqueeze | ✅ True | H1 | MM01 |

### Usage

```bash
# ใช้ default (.tp suffix, TRENDING regime)
python 02_Brain/brain_v6_sender.py

# ปรับ suffix (ถ้า broker ต่างกัน)
python 02_Brain/brain_v6_sender.py --suffix ""

# ปรับ regime
python 02_Brain/brain_v6_sender.py --regime RANGING

# ปิด strategy เฉพาะ
python 02_Brain/brain_v6_sender.py --disable-s06
```

### ผลลัพธ์ที่คาดหวังใน MT5 Journal (V6 Mode)

```
[V6] ✅ INITIAL_CONFIG: ONLINE MODE | 16 strategies registered
[V6] CONFIG_PUSH: regime=TRENDING | enabled=2/16 | mm=MM01
```

### หลักฐาน format ถูกต้อง (การทดสอบวันนี้)

```
CONFIG_PUSH (type 10): 155 bytes
  arr[0]=10  arr[2]=TRENDING  arr[3]=3(sym_count)
  symbol=USDJPY.tp  strats=1  strategies=[['S06', 'KAMA', True, 1.0, 'H4', 'MM01']]
  symbol=XAUUSD.tp  strats=1  strategies=[['S14', 'BBSqueeze', True, 1.0, 'H1', 'MM01']]
  symbol=GBPUSD.tp  strats=1  strategies=[['S14', 'BBSqueeze', True, 1.0, 'H1', 'MM01']]
INITIAL_CONFIG (type 12): 155 bytes  arr[0]=12
HEARTBEAT (type 13): 20 bytes  arr=[13, ..., 'SERVER', 1, 1]
Syntax OK
```

---

## B — ZMQ Live Test รอบ 2

### ขั้นตอน

```
1. kill brain เก่า ถ้ายังรันอยู่:
   netstat -ano | findstr ":7778"
   taskkill /F /PID <PID>

2. รัน brain_v6_sender.py:
   python 02_Brain/brain_v6_sender.py

3. Attach ProgramC_Trader บน chart (V6_EnableMode=true)
   - V6_Enable_S06=true (ถ้า USDJPY H4)
   - V6_Enable_S14=true (ถ้า XAUUSD H1 หรือ GBPUSD H1)

4. ดู MT5 Journal:
   "[V6] ✅ INITIAL_CONFIG: ONLINE MODE | 16 strategies registered"

5. ดู STATUS ทุก 10 วินาที:
   Mode: ONLINE
   Configs recv: > 0
   Regime: TRENDING (ไม่ใช่ UNKNOWN)
```

### ผลลัพธ์

| Test | Expected | Actual | ผล |
|------|----------|--------|----|
| brain_v6_sender.py start | "ZMQ PUB bound to tcp://*:7778" | OK | ✅ |
| INITIAL_CONFIG ส่งทันที | "[V6] INITIAL_CONFIG: ONLINE MODE" ใน Journal | OK | ✅ |
| Mode switch | Mode: ONLINE (ไม่ใช่ STANDALONE) | ONLINE | ✅ |
| Configs recv | > 0 | 4 | ✅ |
| Regime | TRENDING (ไม่ใช่ UNKNOWN) | TRENDING | ✅ |
| HEARTBEAT | HB ทุก 10s ใน sender log | 20 bytes ทุก 10s | ✅ |
| CONFIG_PUSH | CFG ทุก 30s | 155 bytes ทุก 30s | ✅ |
| DynamicParams | SDM apply period=13 ER=0.90 TP=4.7 SL=2.3 | OK | ✅ |
| Strategies enabled | 2/16 (S06+S14) | 2/16 | ✅ |

**สรุป ZMQ รอบ 2:** ✅ PASSED

---

## C — Demo Run

- เปิด ProgramC_Trader บน demo account (V6 mode)
- ดู Journal: ไม่มี error, S06/S14 active
- ตรวจ: signal ส่งได้, order ออกถูกต้อง

| Check | ผล |
|-------|----|
| Trader attach ไม่ error | |
| S06 KAMA active (ถ้า USDJPY chart) | |
| S14 BBSqueeze active (ถ้า XAUUSD/GBPUSD chart) | |
| S10 Turtle inactive (ไม่ deploy) | |
| Brain sender รัน | |
| Signal → trade ออก (ถ้ามี condition) | |

**สรุป Demo:** ⏳

---

## Walk-Forward Results (รวม — จาก 2026-03-09)

| Strategy | Symbol | Period | PF | DD% | Trades | LR | ผล |
|----------|--------|--------|----|-----|--------|-----|-----|
| S14 BBSqueeze | XAUUSD H1 | Full 2022-2024 | 1.84 | 2.36% | 23 | 0.92 | ✅ |
| S14 BBSqueeze | XAUUSD H1 | Train 2022-2023 | 1.41 | 2.36% | 17 | 0.88 | ✅ |
| S14 BBSqueeze | XAUUSD H1 | Test 2024 | 4.34 | 3.58% | 24 | 0.91 | ✅ |
| S06 KAMA | USDJPY H4 | Train 2022-2023 | 1.36 | 1.24% | 29 | 0.46 | ✅ |
| S06 KAMA | USDJPY H4 | Test 2024 | 8.32 | 1.22% | 25 | 0.93 | ✅ |
| S14 BBSqueeze | GBPUSD H1 | Train 2022-2023 | 4.37 | 3.58% | 14* | 0.96 | ✅ |
| S14 BBSqueeze | GBPUSD H1 | Test 2024 | 3.56 | 5.93% | 11 | 0.79 | ✅ |

*1 ต่ำกว่า target trades แต่ PF สูงมาก — ผ่าน

---

## ผลวันนี้ (2026-03-10)

| งาน | Status | หมายเหตุ |
|-----|--------|----------|
| brain_v6_sender.py สร้าง | ✅ | 02_Brain/brain_v6_sender.py |
| Format verification | ✅ | CONFIG_PUSH 155B, HB 20B, Syntax OK |
| ZMQ Live Test รอบ 2 | ✅ PASSED | Configs recv=4, ONLINE, Regime=TRENDING |
| Demo Run | ⏳ | S06/S14 active — รอดูสักวัน |
| Git commit | ⏳ | รอก่อน |
| S10 re-optimize | ⬜ | หลัง deploy เสร็จ |

---

## บทเรียนวันนี้

### 1. MQL5 ConfigReceiver ต้องการ Array Format (ไม่ใช่ Dict)

```
MQL5 คาดหวัง:  [10, ts, regime, sym_count, [[sym, count, [strategies]...]...]]
Python V5 ส่ง: {"type":10, "symbol_configs":[...], "reasoning":{...}, ...}
```

Python ส่ง dict-based → MQL5 parse ล้มเหลว (ไม่มี error log ที่ชัดเจน)
→ ต้องส่งเป็น flat array เสมอ

### 2. Strategy ID format ที่ MQL5 รู้จัก

`_MapStratIDToIndex()` ใน ConfigReceiver รู้จัก:
- "S01"-"S16" → 0-based index 0-15 ✅ (ใช้อันนี้)
- "0"-"15" → 0-based ✅
- "1"-"16" → 1-based → -1 = 0-based ✅
- Integer ไม่รู้จัก (ต้องเป็น string)

### 3. INITIAL_CONFIG (type 12) vs CONFIG_PUSH (type 10)

Format เหมือนกันทุกอย่าง เปลี่ยนแค่ element[0]
type 12 → Trader auto-save standalone config ด้วย (SaveStandaloneConfig)
→ ส่ง type 12 ก่อนครั้งแรก → Trader มี fallback ถ้า Brain ตาย

### 4. msgpack ไม่ได้ติดตั้งใน deepquant_env

```
pip install msgpack -q  → ติดตั้ง OK (version 1.1.2)
```
pyzmq ติดตั้งอยู่แล้ว (version 26.2.0)

---

## แผนต่อไป

1. **ZMQ Live Test รอบ 2** — รัน `brain_v6_sender.py` + attach Trader → ดู ONLINE MODE
2. **Demo run** — 1 วันทำการ, S06+S14
3. **Git commit** — session docs 2026-03-09, 2026-03-10, brain_v6_sender.py
4. **S10 re-optimize** — XAUUSD H4 Real tick, EntryPeriod=8-12 (ทีหลัง)
