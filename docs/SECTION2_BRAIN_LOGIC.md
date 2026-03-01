# Section 2 — The Brain Logic & Multi-Dimensional Matrix

> **ภาษา**: ไทย | **ระดับ**: Method/Function Level
> **วันที่**: 2026-03-01 | **Version**: FlashEASuite V2.1.0 (Phase P9-5)
> **ไฟล์หลัก**: `02_Brain/core/strategy/engine.py` (StrategyEngineThreaded v2.3)

---

## สารบัญ

- [2.1 ภาพรวม Brain — 6 Worker Threads](#21-ภาพรวม-brain--6-worker-threads)
- [2.2 Input Consolidation — รับข้อมูลจาก 2 แหล่ง](#22-input-consolidation--รับข้อมูลจาก-2-แหล่ง)
- [2.3 normalize_symbol() — จัดการ Symbol Variants](#23-normalize_symbol--จัดการ-symbol-variants)
- [2.4 Rolling Tick Buffer — deque(maxlen=500)](#24-rolling-tick-buffer--dequemaxlen500)
- [2.5 Market Analysis — analyze_market_condition()](#25-market-analysis--analyze_market_condition)
- [2.6 Spike Score — calculate_spike_score()](#26-spike-score--calculate_spike_score)
- [2.7 Grid Confidence — calculate_grid_confidence()](#27-grid-confidence--calculate_grid_confidence)
- [2.8 Strategy Selection — select_best_strategy()](#28-strategy-selection--select_best_strategy)
- [2.9 Policy Generation — try_generate_policy()](#29-policy-generation--try_generate_policy)
- [2.10 Policy Packing & Publishing — send_policy()](#210-policy-packing--publishing--send_policy)
- [2.11 State Management — ข้อมูลใน Memory](#211-state-management--ข้อมูลใน-memory)
- [2.12 Emergency System — 9 Conditions, 4 Levels](#212-emergency-system--9-conditions-4-levels)
- [2.13 System Monitor — Performance Metrics](#213-system-monitor--performance-metrics)
- [2.14 วงจรรวม Brain — Full Processing Cycle](#214-วงจรรวม-brain--full-processing-cycle)

---

## 2.1 ภาพรวม Brain — 6 Worker Threads

**ไฟล์**: `02_Brain/main.py` — class `FlashEABrain`

Brain ทำงานแบบ **Multi-threaded pipeline** โดยใช้ Python `threading` + `queue.Queue()` เพื่อ thread-safety ภายใต้ Python GIL:

```
Thread Infrastructure (FlashEABrain.__init__):
  shutdown_event  = threading.Event()    ← สัญญาณหยุดระบบ
  ingestion_queue = queue.Queue()        ← tick จาก FeederEA
  signal_queue    = queue.Queue()        ← policy รอส่ง
  feedback_queue  = queue.Queue()        ← trade results จาก Trader
  threads         = []                   ← รายการ (name, thread)

Worker Threads:
  W1: IngestionWorkerThreaded    → daemon=True, start()
  W2: StrategyEngineThreaded     → daemon=True, start()
  W3: ExecutionListenerThreaded  → daemon=True, start()
  W4: EmergencySystem.start()    → internal thread
  W5: SystemMonitor.start()      → internal thread
  W6: LiveDashboard.start(blocking=False)
```

**Main Thread** (`_monitor_threads()`): loop ทุก 5s ตรวจสอบว่า worker threads ยังมีชีวิตอยู่ + อัปเดต dashboard connection status

### Queue Flow Diagram

```
FeederEA
  │ ZMQ PUB 7777
  ▼
[W1: Ingestion] ──→ ingestion_queue ──→ [W2: Strategy Engine] ──→ signal_queue ──→ ZMQ PUB 7778
                                                ▲                                       │
                                                │ feedback_queue                        ▼
[W3: Execution Listener] ◀── ZMQ PULL 7779     └───────────── [W3: ExecListener]  Trader
```

---

## 2.2 Input Consolidation — รับข้อมูลจาก 2 แหล่ง

Brain รวมข้อมูลจาก **2 แหล่ง** เพื่อตัดสินใจ:

### แหล่งที่ 1: Market Data จาก FeederEA (ingestion_queue)

**ไฟล์**: `02_Brain/core/ingestion.py` — class `IngestionWorkerThreaded`

```python
def _setup_zmq(self):
    ctx = zmq.Context()
    self.sub_socket = ctx.socket(zmq.SUB)
    self.sub_socket.bind("tcp://127.0.0.1:7777")    # Brain เป็น server (bind)
    self.sub_socket.setsockopt(zmq.RCVTIMEO, 1000)  # timeout 1000ms
    self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")  # รับทุก topic

def _parse_tick_data(self, raw_bytes: bytes) -> dict:
    # Input:  bytes (msgpack Array[7])
    # Output: dict with 7 fields
    arr = msgpack.unpackb(raw_bytes)
    return {
        "msg_type":  arr[0],   # int — ควรเป็น 1
        "seq_id":    arr[1],   # int — monotonic counter
        "timestamp": arr[2],   # double — milliseconds
        "symbol":    arr[3],   # str — e.g. "XAUUSD.tp"
        "bid":       arr[4],   # double
        "ask":       arr[5],   # double
        "flags":     arr[6],   # int — bitmask
    }

def run(self):
    while not shutdown_event.is_set():
        try:
            raw = self.sub_socket.recv()           # block ถึง RCVTIMEO
            tick = self._parse_tick_data(raw)
            self.ingestion_queue.put(tick, block=False)  # non-blocking
        except zmq.Again:
            continue  # timeout — loop ใหม่
```

### แหล่งที่ 2: Performance Data จาก Trader (feedback_queue)

**ไฟล์**: `02_Brain/core/execution_listener.py` — class `ExecutionListenerThreaded`

```python
def _setup_zmq(self):
    ctx = zmq.Context()
    self.pull_socket = ctx.socket(zmq.PULL)
    self.pull_socket.bind("tcp://127.0.0.1:7779")   # Brain bind, Trader connect
    self.pull_socket.setsockopt(zmq.RCVTIMEO, 1000)

def _parse_trade_result(self, raw_bytes: bytes) -> dict:
    # Input:  bytes (msgpack Array[12])
    # Output: dict with 14 fields (12 raw + 2 derived)
    arr = msgpack.unpackb(raw_bytes)
    result = {
        "msg_type":   arr[0],   # int — 100 (TRADE_REPORT)
        "timestamp":  arr[1],   # double — ms
        "ticket":     arr[2],   # long — order ticket
        "symbol":     arr[3],   # str — e.g. "XAUUSD.tp"
        "order_type": arr[4],   # int — 0=BUY, 1=SELL
        "volume":     arr[5],   # double — lot size
        "open_price": arr[6],   # double
        "sl":         arr[7],   # double
        "tp":         arr[8],   # double
        "profit":     arr[9],   # double — USD
        "magic":      arr[10],  # int — strategy ID 1001-1016
        "comment":    arr[11],  # str
        # Derived fields:
        "is_win":  arr[9] > 0,
        "is_loss": arr[9] < 0,
    }
    return result
```

### การรวมข้อมูลใน Strategy Engine

**ไฟล์**: `02_Brain/core/strategy/engine.py`

```python
def run(self):
    while not shutdown_event.is_set():
        # --- อ่าน feedback ก่อน (non-blocking) ---
        try:
            feedback = self.feedback_queue.get_nowait()
            self._process_feedback(feedback)   # ปรับ risk_multiplier
        except queue.Empty:
            pass

        # --- อ่าน tick (blocking 100ms) ---
        try:
            tick = self.ingestion_queue.get(timeout=0.1)
            self._process_tick(tick)           # normalize → score → policy
        except queue.Empty:
            continue

def _process_feedback(self, feedback: dict):
    # ปรับ risk_multiplier ตามผลการเทรด
    if feedback["is_win"]:
        self.risk_multiplier = min(1.5, self.risk_multiplier * 1.05)
    elif feedback["is_loss"]:
        self.risk_multiplier = max(0.3, self.risk_multiplier * 0.90)
    # ส่ง trade result ไป EmergencySystem ด้วย
    self.emergency.update_trade_result(
        profit=feedback["profit"],
        equity=self._current_equity
    )
```

---

## 2.3 normalize_symbol() — จัดการ Symbol Variants

**ปัญหา**: Broker แต่ละเจ้าใช้ suffix ต่างกัน:
- ICMarkets: `XAUUSD` (ไม่มี suffix)
- ThinkMarkets: `XAUUSD.tp`
- Pepperstone: `XAUUSD_m`
- IC Markets Raw: `XAUUSDm` หรือ `XAUUSD.raw`

**ผลเสีย**: ถ้าไม่ normalize → `tick_history["XAUUSD.tp"]` และ `tick_history["XAUUSD"]` จะเป็น buffer คนละตัว → ข้อมูลกระจาย → score คำนวณผิดเพราะ sample size น้อยเกินไป

```python
# FIX #1 จาก P9-5 — ใน engine.py
BROKER_SUFFIXES = [".tp", ".raw", "_m", "m", ".eco", ".pro", ".std", ".ECN"]

def normalize_symbol(self, symbol: str) -> str:
    """
    Input:  str  — raw symbol จาก FeederEA e.g. "XAUUSD.tp"
    Output: str  — normalized symbol e.g. "XAUUSD"

    Logic:
      1. uppercase
      2. ลบ suffix ที่รู้จักทั้งหมด
      3. ถ้าไม่มี suffix ที่รู้จัก → return as-is
    """
    sym = symbol.upper()
    for suffix in BROKER_SUFFIXES:
        if sym.endswith(suffix.upper()):
            return sym[:-len(suffix)]
    return sym

# ตัวอย่าง:
# normalize_symbol("XAUUSD.tp")  → "XAUUSD"
# normalize_symbol("EURUSD_m")   → "EURUSD"
# normalize_symbol("GBPUSD")     → "GBPUSD"  (ไม่เปลี่ยน)
```

**เหตุผลที่ fix นี้สำคัญ**: ก่อน FIX #1 ถ้า broker ใช้ `XAUUSD.tp` และ config ระบุ `XAUUSD` จะไม่มี tick ถูก buffer → spike_score = 0 ตลอด → ไม่มี policy ถูกส่งไปเลย

---

## 2.4 Rolling Tick Buffer — deque(maxlen=500)

**ไฟล์**: `02_Brain/core/strategy/engine.py`

```python
from collections import defaultdict, deque

# State: tick history per normalized symbol
self.tick_history = defaultdict(lambda: deque(maxlen=500))

def _process_tick(self, tick: dict):
    sym_raw  = tick["symbol"]           # e.g. "XAUUSD.tp"
    sym_norm = self.normalize_symbol(sym_raw)  # e.g. "XAUUSD"

    # บันทึก tick ลง buffer
    self.tick_history[sym_norm].append({
        "bid": tick["bid"],
        "ask": tick["ask"],
        "timestamp": tick["timestamp"],
        "mid": (tick["bid"] + tick["ask"]) / 2.0,
    })

    # คำนวณ score เฉพาะเมื่อมีข้อมูลเพียงพอ
    ticks = self.tick_history[sym_norm]
    if len(ticks) >= 10:   # minimum sample size
        self.try_generate_policy(sym_norm, ticks)
```

**ทำไม deque(maxlen=500)?**
- 500 ticks @ 20 ticks/sec = ~25 วินาทีของข้อมูล
- เพียงพอสำหรับคำนวณ SMA, std, trend
- ไม่ใช้หน่วยความจำมากเกินไป (~500 × 4 fields × 8 bytes = ~16KB per symbol)
- `deque` auto-drops oldest entry → ไม่ต้อง manage manually

---

## 2.5 Market Analysis — analyze_market_condition()

**ไฟล์**: `02_Brain/core/strategy/analysis.py`

```python
def analyze_market_condition(ticks: deque) -> dict:
    """
    Input:  deque — rolling tick buffer (ต้องมี≥10 ticks)
    Output: dict  — {trend, volatility, confidence, spread}

    Returns:
      trend:      str   — "BUY" | "SELL" | "NEUTRAL"
      volatility: float — price std deviation
      confidence: float — 0.0 - 1.0
      spread:     float — avg ask-bid
    """
    mids = [t["mid"] for t in ticks]

    # --- Trend Detection via SMA ---
    sma = sum(mids) / len(mids)        # Simple Moving Average (all ticks)
    current_mid = mids[-1]             # latest mid price

    if current_mid > sma * 1.001:     # เหนือ SMA 0.1%
        trend = "BUY"
    elif current_mid < sma * 0.999:   # ต่ำกว่า SMA 0.1%
        trend = "SELL"
    else:
        trend = "NEUTRAL"

    # --- Volatility (Price Std Dev) ---
    mean = sma
    variance = sum((m - mean) ** 2 for m in mids) / len(mids)
    volatility = variance ** 0.5      # standard deviation

    # --- Spread ---
    spreads = [t["ask"] - t["bid"] for t in ticks]
    avg_spread = sum(spreads) / len(spreads)

    # --- Confidence ---
    # ใกล้ SMA มากแค่ไหน (normalized)
    deviation_pct = abs(current_mid - sma) / sma
    confidence = min(1.0, deviation_pct / 0.005)   # 0.5% = max confidence

    return {
        "trend":      trend,
        "volatility": volatility,
        "confidence": confidence,
        "spread":     avg_spread,
    }
```

**ข้อสังเกต**: SMA ที่ใช้คือ SMA ของ tick ทั้ง deque ไม่ใช่ OHLC bar — เหมาะกับ high-frequency analysis

---

## 2.6 Spike Score — calculate_spike_score()

**ไฟล์**: `02_Brain/core/strategy/engine.py`
**วัตถุประสงค์**: วัดความรุนแรงของการเคลื่อนไหวราคา "สไปค์" ในช่วงสั้น

```python
# FIX #2 จาก P9-5 — แก้ window จาก len(ticks) เป็น [-50:]
def calculate_spike_score(self, ticks: deque) -> float:
    """
    Input:  deque — tick buffer (ใช้เฉพาะ 50 ticks ล่าสุด)
    Output: float — spike score 0.0 to 100.0

    Formula:
      price_change = abs(newest_mid - oldest_mid_in_window)
      volatility   = std_dev(mids_in_window)
      spike_score  = min(100, price_change × 2 + volatility × 3)

    เหตุผลน้ำหนัก (×2 และ ×3):
      - price_change×2: การเคลื่อนราคาเชิงทิศทาง สำคัญ แต่อาจ noise
      - volatility×3:   ความผันผวนโดยรวม สำคัญกว่าเพราะ predict spike ได้ดีกว่า
    """
    window = list(ticks)[-50:]         # FIX #2: ใช้แค่ 50 ticks ล่าสุด
    if len(window) < 2:
        return 0.0

    mids = [t["mid"] for t in window]

    # Price change ในช่วง window
    price_change = abs(mids[-1] - mids[0])

    # Volatility (std dev)
    mean = sum(mids) / len(mids)
    variance = sum((m - mean) ** 2 for m in mids) / len(mids)
    volatility = variance ** 0.5

    # Spike Score Formula
    score = min(100.0, price_change * 2.0 + volatility * 3.0)
    return score

# ตัวอย่าง:
# price_change=1.2, volatility=0.8 → score = min(100, 2.4+2.4) = 4.8  (ปกติ)
# price_change=5.0, volatility=3.0 → score = min(100, 10.0+9.0) = 19.0 (spike)
# price_change=20.0, volatility=8.0 → score = min(100, 40.0+24.0) = 64.0 (strong spike)
```

**ทำไม window = 50 ticks?**
- 50 ticks @ 20/sec = 2.5 วินาทีล่าสุด
- ถ้าใช้ window ใหญ่เกินไป (500) → dilute effect ของ spike → score ต่ำเกินจริง
- FIX #2 แก้ bug นี้ที่ทำให้ spike score ต่ำผิดปกติใน P9-4

---

## 2.7 Grid Confidence — calculate_grid_confidence()

**ไฟล์**: `02_Brain/core/strategy/engine.py`
**วัตถุประสงค์**: วัดว่าตลาดอยู่ใน "ranging mode" เหมาะกับ Grid strategy แค่ไหน

```python
def calculate_grid_confidence(self, ticks: deque) -> float:
    """
    Input:  deque — tick buffer (ใช้ 50 ticks ล่าสุด)
    Output: float — grid confidence 0.0 to 1.0

    Logic:
      1. คำนวณ trend_strength = |slope of linear regression| / sma
      2. ถ้า trend แรง → grid confidence ต่ำ (ไม่เหมาะ grid ใน trend)
      3. ถ้า trend อ่อน → grid confidence สูง (เหมาะ grid ใน ranging)

    Formula:
      trend_strength = abs(last_mid - first_mid) / (sma × window_size)
      confidence     = max(0.0, 1.0 - trend_strength × 100)
    """
    window = list(ticks)[-50:]
    if len(window) < 2:
        return 0.0

    mids   = [t["mid"] for t in window]
    sma    = sum(mids) / len(mids)

    # Simplified trend strength: linear slope normalized by price level
    price_move  = abs(mids[-1] - mids[0])
    trend_strength = price_move / (sma * len(window)) if sma > 0 else 0

    confidence = max(0.0, 1.0 - trend_strength * 100)
    return confidence

# ตัวอย่าง:
# XAUUSD ranging: price_move=0.50, sma=2650, window=50
#   trend_strength = 0.50 / (2650×50) = 0.0000038
#   confidence = max(0, 1 - 0.0000038×100) = 0.9996  ≈ 1.0 (excellent for grid)
#
# XAUUSD trending: price_move=5.0, sma=2650, window=50
#   trend_strength = 5.0 / (2650×50) = 0.0000377
#   confidence = max(0, 1 - 0.0000377×100) = 0.9962  (ยังสูงอยู่)
#   [Note: scale ขึ้นกับ price level ของแต่ละ symbol]
```

---

## 2.8 Strategy Selection — select_best_strategy()

**ไฟล์**: `02_Brain/core/strategy/policy.py` — class `PolicyPublisher`

```python
def select_best_strategy(self, spike_score: float, grid_confidence: float) -> str:
    """
    Input:  spike_score     float — 0.0 to 100.0
            grid_confidence float — 0.0 to 1.0
    Output: str — "SPIKE" | "GRID" | "NONE"

    Decision Logic:
      1. แปลง spike_score เป็น spike_confidence (0-1 scale)
      2. SPIKE wins ถ้า spike_confidence ≥ 0.7 (threshold สูงกว่า grid)
      3. GRID wins ถ้า grid_confidence ≥ 0.6
      4. NONE ถ้าไม่ผ่าน threshold ใด
    """
    spike_confidence = spike_score / 100.0     # normalize to 0-1

    if spike_confidence >= 0.7:
        return "SPIKE"
    elif grid_confidence >= 0.6:
        return "GRID"
    else:
        return "NONE"

# ทำไม SPIKE threshold สูงกว่า GRID (0.7 vs 0.6)?
# SPIKE strategy ใช้ lot ใหญ่กว่าและ max_orders=1 (all-in)
# ต้องการ confidence สูงกว่าเพื่อป้องกัน false spike signals
```

### Decision Matrix

| spike_conf | grid_conf | ผลลัพธ์ | Scenario |
|------------|-----------|---------|----------|
| ≥ 0.70 | any | SPIKE | ตลาดมี spike แรง |
| < 0.70 | ≥ 0.60 | GRID | ตลาด ranging |
| < 0.70 | < 0.60 | NONE | ตลาดไม่ชัดเจน |
| ≥ 0.70 | ≥ 0.60 | SPIKE | SPIKE มี priority สูงกว่า |

---

## 2.9 Policy Generation — try_generate_policy()

**ไฟล์**: `02_Brain/core/strategy/engine.py`

```python
POLICY_COOLDOWN = 10.0  # วินาที — ป้องกัน policy flood per symbol

def try_generate_policy(self, symbol: str, ticks: deque) -> bool:
    """
    Input:  symbol str   — normalized symbol
            ticks  deque — tick buffer
    Output: bool — True ถ้าส่ง policy ได้, False ถ้าถูก gate

    4 Gates ต้องผ่านทั้งหมด:
    """

    # --- Gate 1: Symbol Allowlist ---
    if symbol not in ALLOWED_SYMBOLS:
        return False    # symbol ไม่อยู่ใน whitelist

    # --- Gate 2: Strategy Selection ---
    spike_score     = self.calculate_spike_score(ticks)
    grid_confidence = self.calculate_grid_confidence(ticks)
    strategy        = self.policy_publisher.select_best_strategy(
                          spike_score, grid_confidence)
    if strategy == "NONE":
        return False    # ไม่มี strategy เหมาะสม

    # --- Gate 3: Emergency Check ---
    if not self.emergency.can_trade():
        return False    # EmergencySystem บล็อกอยู่

    # --- Gate 4: Cooldown Check ---
    now = time.time()
    last_time = self.policy_cooldown.get(symbol, 0.0)
    if (now - last_time) < POLICY_COOLDOWN:
        return False    # ยังอยู่ใน cooldown window

    # --- All Gates Passed — Generate & Send ---
    if strategy == "SPIKE":
        policy = self.policy_publisher.generate_spike_policy(
                     symbol, ticks, spike_score / 100.0)
    else:
        policy = self.policy_publisher.generate_grid_policy(
                     symbol, ticks, grid_confidence)

    success = self.send_policy(symbol, policy)
    if success:
        self.policy_cooldown[symbol] = now    # update cooldown timestamp
    return success
```

---

## 2.10 Policy Packing & Publishing — send_policy()

**ไฟล์**: `02_Brain/core/strategy/engine.py`

```python
def send_policy(self, symbol: str, policy: list) -> bool:
    """
    Input:  symbol str  — normalized symbol
            policy list — Array[11] จาก generate_*_policy()
    Output: bool — True ถ้าส่งสำเร็จ

    Policy Array[11] format:
      [0]  msg_type    int    = 10 (CONFIG_PUSH)
      [1]  timestamp   double = unix ms
      [2]  symbol      str    = normalized symbol
      [3]  strategy    str    = "SPIKE" or "GRID"
      [4]  entry       double = entry price reference
      [5]  lot         double = calculated lot (× risk_multiplier)
      [6]  max_orders  int    = 1 (SPIKE) or 5 (GRID)
      [7]  tp          double = take profit price
      [8]  sl          double = stop loss price
      [9]  confidence  double = 0.0-1.0
      [10] risk_mult   double = current risk_multiplier
    """
    try:
        packed = msgpack.packb(policy, use_bin_type=True)
        self.pub_socket.send(packed, zmq.NOBLOCK)   # non-blocking!
        return True
    except zmq.Again:
        # Trader ไม่ได้ connect หรือ buffer เต็ม
        logger.warning(f"ZMQ send EAGAIN for {symbol}")
        return False

# ทำไม NOBLOCK?
# ถ้า Trader ไม่ได้ connect → Brain จะไม่ block รอ
# Brain ต้องประมวลผล tick ต่อไปได้ ไม่ควรหยุดรอ
```

### generate_spike_policy() และ generate_grid_policy()

**ไฟล์**: `02_Brain/core/strategy/policy.py`

```python
def generate_spike_policy(self, symbol: str, ticks: deque, confidence: float) -> list:
    """สร้าง policy สำหรับ SPIKE strategy"""
    mids = [t["mid"] for t in ticks]
    entry = mids[-1]    # ราคาปัจจุบัน

    # ATR approximation จาก tick range
    atr = max(t["ask"] - t["bid"] for t in list(ticks)[-20:]) * 50

    return [
        10,                          # msg_type = CONFIG_PUSH
        time.time() * 1000,          # timestamp ms
        symbol,                      # normalized symbol
        "SPIKE",                     # strategy name
        entry,                       # entry reference
        self._base_lot * risk_mult,  # lot size (adjusted)
        1,                           # max_orders = 1 (all-in)
        entry + atr * 0.8,           # tp = entry + ATR × 0.8
        entry - atr * 0.4,           # sl = entry - ATR × 0.4  (R:R = 2:1)
        confidence,                  # signal confidence
        self.risk_multiplier,        # current risk multiplier
    ]

def generate_grid_policy(self, symbol: str, ticks: deque, confidence: float) -> list:
    """สร้าง policy สำหรับ GRID strategy"""
    mids = [t["mid"] for t in ticks]
    entry = mids[-1]

    # Grid spacing = ATR-based
    volatility = (max(mids[-20:]) - min(mids[-20:])) / 20
    grid_spacing = volatility * 0.5

    return [
        10,                          # msg_type = CONFIG_PUSH
        time.time() * 1000,          # timestamp ms
        symbol,
        "GRID",
        entry,
        self._base_lot * risk_mult,  # lot size
        5,                           # max_orders = 5 (grid levels)
        entry + grid_spacing,        # tp reference
        entry - grid_spacing,        # sl reference
        confidence,
        self.risk_multiplier,
    ]
```

---

## 2.11 State Management — ข้อมูลใน Memory

Brain เก็บ state ทั้งหมดใน memory (ไม่มี database):

```python
# StrategyEngineThreaded — State Variables

self.tick_history    = defaultdict(lambda: deque(maxlen=500))
# Key:   normalized symbol (str)
# Value: deque ของ tick dicts
# ขนาด: ~16KB per symbol × 4 symbols = ~64KB

self.policy_cooldown = {}
# Key:   normalized symbol (str)
# Value: float — timestamp ของ policy ล่าสุด
# ขนาด: negligible

self.risk_multiplier = 1.0
# float — ปรับตาม feedback loop
# Range: 0.3 (after 5 losses) to 1.5 (after 5 wins)
# ปรับทุกครั้งที่ได้ feedback: ×1.05 (win) หรือ ×0.90 (loss)

# EmergencySystem — RiskMetrics dataclass
@dataclass
class RiskMetrics:
    equity:              float = 0.0
    peak_equity:         float = 0.0
    daily_start_equity:  float = 0.0
    daily_pnl:           float = 0.0
    consecutive_losses:  int   = 0
    current_atr:         float = 0.0
    feeder_connected:    bool  = False
    trader_connected:    bool  = False
    cpu_percent:         float = 0.0
    mem_percent:         float = 0.0
```

**ทำไมไม่บันทึก state ลง disk?**
> Brain ออกแบบมาให้ "stateless by design" — ถ้า Brain restart จะเริ่ม build tick history ใหม่จาก 0 ภายใน ~25 วินาที (500 ticks) ไม่ต้องมี recovery mechanism ที่ซับซ้อน

---

## 2.12 Emergency System — 9 Conditions, 4 Levels

**ไฟล์**: `02_Brain/core/emergency_system.py` — class `EmergencySystem`

### 4 Emergency Levels

```python
class EmergencyLevel(Enum):
    NORMAL  = 0   # ✅ ปกติ — เทรดได้
    WARNING = 1   # ⚡ เตือน — เทรดต่อแต่ระวัง
    PAUSE   = 2   # ⚠️ หยุดชั่วคราว — auto-resume หลัง timeout
    HALT    = 3   # 🚨 หยุดถาวร — ต้อง manual reset
```

### 9 Emergency Conditions

```python
class EmergencyReason(Enum):
    DRAWDOWN_EXCEEDED   = 1   # equity ลดจาก peak > max_drawdown_pct (20%)
    DAILY_LOSS_LIMIT    = 2   # daily_pnl < -daily_loss_pct (5%)
    CONSECUTIVE_LOSSES  = 3   # losses ติดกัน ≥ consecutive_losses_max (5)
    VOLATILITY_SPIKE    = 4   # ATR > normal_atr × volatility_multiplier (3×)
    NEWS_EVENT          = 5   # high-impact news window (manual trigger)
    CONNECTION_LOST     = 6   # feeder หรือ trader ไม่ได้ connect
    CORRELATION_HIGH    = 7   # correlation between positions > threshold (0.80)
    SYSTEM_OVERLOAD     = 8   # CPU > 90% หรือ RAM > 90%
    MANUAL_HALT         = 9   # manual trigger จาก operator
```

### การตรวจสอบทุก 1 วินาที

```python
def _check_all_conditions(self):
    """เรียกทุก 1 วินาที จาก background thread"""
    m = self.metrics

    # 1. Drawdown
    if m.peak_equity > 0:
        drawdown_pct = (m.peak_equity - m.equity) / m.peak_equity * 100
        if drawdown_pct > self.max_drawdown_pct:
            self._trigger_emergency(
                EmergencyReason.DRAWDOWN_EXCEEDED,
                EmergencyLevel.HALT,
                f"Drawdown {drawdown_pct:.1f}% > {self.max_drawdown_pct}%"
            )

    # 2. Daily Loss
    if m.daily_start_equity > 0:
        daily_loss_pct = abs(m.daily_pnl) / m.daily_start_equity * 100
        if m.daily_pnl < 0 and daily_loss_pct > self.daily_loss_pct:
            self._trigger_emergency(
                EmergencyReason.DAILY_LOSS_LIMIT,
                EmergencyLevel.HALT,
                f"Daily loss {daily_loss_pct:.1f}% > {self.daily_loss_pct}%"
            )

    # 3. Consecutive Losses
    if m.consecutive_losses >= self.consecutive_losses_max:
        self._trigger_emergency(
            EmergencyReason.CONSECUTIVE_LOSSES,
            EmergencyLevel.PAUSE,
            f"{m.consecutive_losses} consecutive losses"
        )

    # 4. System Overload
    if m.cpu_percent > self.system_cpu_threshold:
        self._trigger_emergency(
            EmergencyReason.SYSTEM_OVERLOAD,
            EmergencyLevel.WARNING,
            f"CPU {m.cpu_percent:.0f}%"
        )

    # ... และอีก 5 conditions

    # Auto-resolve PAUSEs ที่ timeout แล้ว
    self._auto_resolve_pauses()

def _trigger_emergency(self, reason, level, message):
    """ยิง callback ใน daemon thread ป้องกัน deadlock"""
    event = EmergencyEvent(reason=reason, level=level, message=message)
    t = threading.Thread(
        target=self.on_level_change,
        args=(level, event),
        daemon=True
    )
    t.start()
```

### can_trade() — Gateway สำหรับ Policy Generation

```python
def can_trade(self) -> bool:
    """
    Output: bool — True ถ้า level = NORMAL หรือ WARNING
                   False ถ้า level = PAUSE หรือ HALT
    """
    return self.level in (EmergencyLevel.NORMAL, EmergencyLevel.WARNING)
```

---

## 2.13 System Monitor — Performance Metrics

**ไฟล์**: `02_Brain/core/system_monitor.py` — class `SystemMonitor`

```python
class SystemMonitor:
    def __init__(self, sample_window: int = 200):
        self.latency_history = defaultdict(lambda: deque(maxlen=sample_window))
        self._history = deque(maxlen=300)   # 5 นาที @ 1 snapshot/sec
        self._queues  = {}                  # references to 3 queues

    def tick_start(self, symbol: str) -> float:
        """
        เรียกก่อน process tick
        Output: float — perf_counter() (sub-millisecond precision)
        """
        return time.perf_counter()

    def tick_end(self, symbol: str, start: float) -> float:
        """
        เรียกหลัง process tick เสร็จ
        Input:  start float — จาก tick_start()
        Output: float — elapsed milliseconds
        """
        elapsed_ms = (time.perf_counter() - start) * 1000
        self.latency_history[symbol].append(elapsed_ms)
        return elapsed_ms

    def get_stats(self) -> dict:
        """
        Output: dict — {latency_p95, throughput, queue_depths, cpu, mem}
        """
        # P95 latency across all symbols
        all_latencies = []
        for hist in self.latency_history.values():
            all_latencies.extend(hist)

        if all_latencies:
            sorted_lat = sorted(all_latencies)
            p95_idx = int(len(sorted_lat) * 0.95)
            latency_p95 = sorted_lat[p95_idx]
        else:
            latency_p95 = 0.0

        return {
            "latency_p95": latency_p95,          # ms
            "cpu_percent": psutil.cpu_percent(),
            "mem_percent": psutil.virtual_memory().percent,
            "queue_depths": {
                "ingestion": self._queues.get("ingestion", queue.Queue()).qsize(),
                "signal":    self._queues.get("signal", queue.Queue()).qsize(),
                "feedback":  self._queues.get("feedback", queue.Queue()).qsize(),
            }
        }
```

---

## 2.14 วงจรรวม Brain — Full Processing Cycle

```
FeederEA → ZMQ 7777
    │
    ▼
[Worker 1: Ingestion]
  recv() RCVTIMEO=1000ms
  _parse_tick_data(bytes) → dict{7}
  ingestion_queue.put(tick, block=False)
    │
    ▼
[Worker 2: Strategy Engine] ← feedback_queue (W3 feeds)
  ingestion_queue.get(timeout=0.1)
  normalize_symbol("XAUUSD.tp") → "XAUUSD"
  tick_history["XAUUSD"].append(tick)
    │
    ├── analyze_market_condition(ticks)
    │     → {trend, volatility, confidence, spread}
    │
    ├── calculate_spike_score(ticks[-50:])
    │     price_change×2 + volatility×3 → float 0-100
    │
    ├── calculate_grid_confidence(ticks[-50:])
    │     1 - trend_strength×100 → float 0-1
    │
    ├── select_best_strategy(spike, grid)
    │     spike≥0.7 → "SPIKE"
    │     grid≥0.6  → "GRID"
    │     else      → "NONE"
    │
    └── try_generate_policy(symbol, ticks)
          Gate1: symbol in allowlist?
          Gate2: strategy ≠ "NONE"?
          Gate3: emergency.can_trade()?
          Gate4: cooldown > 10s?
          PASS → generate_*_policy() → Array[11]
                 send_policy() → msgpack.packb() → ZMQ NOBLOCK 7778
                 policy_cooldown[symbol] = now
                 │
                 ▼
         ZMQ 7778 → ProgramC_Trader

[Worker 3: Execution Listener]
  pull_socket.recv() RCVTIMEO=1000ms
  _parse_trade_result(bytes) → dict{14}
  feedback_queue.put(result)
  → W2 reads → _process_feedback()
                risk_multiplier × 1.05 (win) or × 0.90 (loss)
                emergency.update_trade_result(profit, equity)

[Worker 4: Emergency System] — every 1s
  _check_all_conditions()  → 9 checks
  _auto_resolve_pauses()   → timeout check
  _recalculate_level()     → NORMAL/WARNING/PAUSE/HALT
  callback → dashboard.add_alert()

[Worker 5: System Monitor] — every 1s
  psutil.cpu_percent(), virtual_memory()
  calc latency P95 across symbols
  snapshot → _history deque(300)

[Worker 6: Dashboard] — every 1s
  render terminal UI
  show: connection status, queue depths, emergency level, alerts
```

---

*ก่อนหน้า: [Section 1 — System Architecture](SECTION1_SYSTEM_ARCHITECTURE.md)*
*ต่อไป: [Section 3 — Execution & Strategy Policy](SECTION3_EXECUTION_STRATEGY.md)*
