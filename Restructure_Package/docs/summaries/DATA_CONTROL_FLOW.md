# 🔄 FlashEASuite V2 - Data Flow & Control Flow Analysis

**Comprehensive flow diagrams and sequence analysis**

---

## 📊 **Complete Data Flow Diagram**

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                          REAL MARKET (BROKER)                             ║
║         Price Updates, Order Execution, Position Management               ║
╚═══════════════════════════════════╦═══════════════════════════════════════╝
                                    ║
                    ┌───────────────┼───────────────┐
                    ║ Bid/Ask       ║               ║ Order
                    ║ Updates       ║               ║ Execution
                    ▼               ║               ▼
╔════════════════════════════════════════════════════════════════════════════╗
║                           MT5 TERMINAL                                     ║
║  ┌─────────────────────────────────────────────────────────────────────┐  ║
║  │  Market Watch: EURUSD, GBPUSD, USDJPY, XAUUSD                        │  ║
║  │  Charts, Orders, History, Account Info                               │  ║
║  └─────────────────────────────────────────────────────────────────────┘  ║
╚════════════════════════════════════════════════════════════════════════════╝
        │                                                           ▲
        │ ① Tick Data                                              │ ⑤ Orders
        │ SymbolInfoTick()                                         │ OrderSend()
        ▼                                                           │
╔════════════════════════════════════════════════════════════════════════════╗
║               PROGRAM A: FeederEA.mq5 (Data Collector)                    ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  OnTimer() - Every 50ms                                              │ ║
║  │  ├─ For each symbol (4 symbols):                                     │ ║
║  │  │   ├─ Get tick: SymbolInfoTick(symbol, tick)                       │ ║
║  │  │   ├─ Check if NEW: tick.time_msc > last_time                      │ ║
║  │  │   ├─ If NEW:                                                      │ ║
║  │  │   │   ├─ Increment sequence_id                                    │ ║
║  │  │   │   ├─ Pack MessagePack: [type, seq, time, sym, bid, ask, flags]│ ║
║  │  │   │   └─ Send: g_Socket.send_bin(data)                            │ ║
║  │  │   └─ If OLD: Skip                                                 │ ║
║  │  └─ Log every 100 ticks                                              │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                                                                            ║
║  Data Format (MessagePack):                                               ║
║  [1, seq_id, timestamp_ms, "XAUUSD", 4194.43, 4194.71, 6]                ║
║  Size: ~65 bytes                                                          ║
╚════════════════════════════════════════════════════════════════════════════╝
        │
        │ ② MessagePack Binary
        │ tcp://127.0.0.1:7777
        │ ZMQ PUB Socket
        │ Latency: ~0.5ms
        ▼
╔════════════════════════════════════════════════════════════════════════════╗
║            PROGRAM B: Python Brain (AI Analysis Engine)                   ║
║                                                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │ WORKER 1: Ingestion (core/ingestion.py)                           │  ║
║  │ ────────────────────────────────────────────                       │  ║
║  │ While True:                                                        │  ║
║  │   ├─ Poll ZMQ SUB 7777 (timeout=10ms)                             │  ║
║  │   ├─ If message received:                                         │  ║
║  │   │   ├─ Deserialize MessagePack → dict                           │  ║
║  │   │   ├─ Validate: type==1, has required fields                   │  ║
║  │   │   └─ Put in tick_queue (multiprocessing.Queue)                │  ║
║  │   └─ Handle errors gracefully                                     │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                              │                                            ║
║                              │ ③ Tick Queue                               ║
║                              │ (Multiprocessing Queue)                    ║
║                              ▼                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │ WORKER 2: Strategy Engine (core/strategy/engine.py)               │  ║
║  │ ──────────────────────────────────────────────────                 │  ║
║  │ While True:                                                        │  ║
║  │   ├─ Get tick from tick_queue (blocking)                          │  ║
║  │   ├─ Update market state:                                         │  ║
║  │   │   ├─ Latest prices (bid/ask)                                  │  ║
║  │   │   ├─ Price history buffer                                     │  ║
║  │   │   └─ Tick counters                                            │  ║
║  │   │                                                                │  ║
║  │   ├─ Call analysis.py:                                            │  ║
║  │   │   └─ analyze_market_condition(tick_data)                      │  ║
║  │   │       ├─ Calculate: spread, volatility, trend                 │  ║
║  │   │       ├─ Detect: patterns, support/resistance                 │  ║
║  │   │       └─ Return: MarketSignal object                          │  ║
║  │   │                                                                │  ║
║  │   ├─ Call policy.py:                                              │  ║
║  │   │   └─ generate_policy(market_signal, risk_params)              │  ║
║  │   │       ├─ Select strategy: Grid or Spike                       │  ║
║  │   │       ├─ Calculate: risk amount, confidence                   │  ║
║  │   │       └─ Return: PolicyMessage object                         │  ║
║  │   │                                                                │  ║
║  │   └─ Put policy in policy_queue                                   │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                              │                                            ║
║                              │ ④ Policy Queue                             ║
║                              │ (Multiprocessing Queue)                    ║
║                              ▼                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │ WORKER 3: Policy Publisher (in engine.py)                         │  ║
║  │ ────────────────────────────────────────────────────────           │  ║
║  │ While True:                                                        │  ║
║  │   ├─ Get policy from policy_queue (blocking)                      │  ║
║  │   ├─ Serialize to MessagePack                                     │  ║
║  │   ├─ Send via ZMQ PUB 7778                                        │  ║
║  │   └─ Increment policies_sent counter                              │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                              │                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │ WORKER 4: Execution Listener (core/execution_listener.py)         │  ║
║  │ ────────────────────────────────────────────────────────────       │  ║
║  │ While True:                                                        │  ║
║  │   ├─ Poll ZMQ SUB 7779 (timeout=10ms)                             │  ║
║  │   ├─ If trade result received:                                    │  ║
║  │   │   ├─ Deserialize MessagePack                                  │  ║
║  │   │   ├─ Call feedback.py:                                        │  ║
║  │   │   │   └─ update_performance(trade_result)                     │  ║
║  │   │   │       ├─ Update: win_count, loss_count, total_profit      │  ║
║  │   │   │       ├─ Calculate: win_rate, profit_factor               │  ║
║  │   │   │       └─ Adjust: risk_multiplier (0.5x - 2.0x)            │  ║
║  │   │   └─ Log result                                               │  ║
║  │   └─ Update dashboard metrics                                     │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                            ║
║  Performance Metrics (Shared Memory):                                     ║
║  ├─ ticks_processed: Counter                                              ║
║  ├─ policies_sent: Counter                                                ║
║  ├─ win_count / loss_count: Counters                                      ║
║  ├─ total_profit: Float                                                   ║
║  └─ risk_multiplier: Float (adaptive)                                     ║
╚════════════════════════════════════════════════════════════════════════════╝
        │                                                           ▲
        │ Policy Messages                                           │ Trade Results
        │ tcp://127.0.0.1:7778                                     │ tcp://127.0.0.1:7779
        │ ZMQ PUB                                                   │ ZMQ PUB
        │ Latency: ~0.5ms                                           │ Latency: ~0.5ms
        ▼                                                           │
╔════════════════════════════════════════════════════════════════════════════╗
║          PROGRAM C: ProgramC_Trader.mq5 (Order Executor)                  ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  OnInit()                                                            │ ║
║  │  ├─ Initialize ZMQ:                                                  │ ║
║  │  │   ├─ SUB socket 7778 (receive policies)                           │ ║
║  │  │   └─ PUB socket 7779 (send results)                               │ ║
║  │  ├─ Initialize components:                                           │ ║
║  │  │   ├─ CStrategyManager (Grid, Spike)                               │ ║
║  │  │   ├─ CRiskGuardian                                                │ ║
║  │  │   └─ CPolicyManager                                               │ ║
║  │  └─ Set state: WAITING_FOR_POLICY                                    │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                              │                                            ║
║                              │ Event Loop                                 ║
║                              ▼                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  OnTimer() - Every 100ms                                             │ ║
║  │  ├─ Poll ZMQ SUB 7778                                                │ ║
║  │  ├─ If policy received:                                              │ ║
║  │  │   │                                                                │ ║
║  │  │   ├─ Deserialize MessagePack → PolicyMessage                      │ ║
║  │  │   │                                                                │ ║
║  │  │   ├─ Validate policy:                                             │ ║
║  │  │   │   ├─ Check symbol match (current chart)                       │ ║
║  │  │   │   ├─ Check strategy available                                 │ ║
║  │  │   │   └─ CRiskGuardian::ValidatePolicy()                          │ ║
║  │  │   │       ├─ Check max exposure                                   │ ║
║  │  │   │       ├─ Check max orders                                     │ ║
║  │  │   │       └─ Check risk limits                                    │ ║
║  │  │   │                                                                │ ║
║  │  │   ├─ If valid:                                                    │ ║
║  │  │   │   └─ Route to strategy:                                       │ ║
║  │  │   │       │                                                        │ ║
║  │  │   │       ├─ Grid Strategy:                                       │ ║
║  │  │   │       │   ├─ Calculate grid levels                            │ ║
║  │  │   │       │   ├─ Open/close orders as needed                      │ ║
║  │  │   │       │   └─ Manage grid state                                │ ║
║  │  │   │       │                                                        │ ║
║  │  │   │       └─ Spike Strategy:                                      │ ║
║  │  │   │           ├─ Detect spike condition                           │ ║
║  │  │   │           ├─ Quick entry/exit                                 │ ║
║  │  │   │           └─ Scalping logic                                   │ ║
║  │  │   │                                                                │ ║
║  │  │   └─ After trade execution:                                       │ ║
║  │  │       ├─ Build TradeResult message                                │ ║
║  │  │       ├─ Serialize to MessagePack                                 │ ║
║  │  │       └─ Send via ZMQ PUB 7779 ───────────────────────────────────┘ ║
║  │  │                                                                    │ ║
║  │  └─ Check existing positions (OnTick backup)                         │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
╚════════════════════════════════════════════════════════════════════════════╝
        │
        │ ⑤ Market Orders
        │ OrderSend(), OrderModify(), OrderClose()
        │
        └───────────────────────────> Back to MT5 Terminal
```

---

## 🔄 **Control Flow - Startup Sequence**

```
╔═══════════════════════════════════════════════════════════════╗
║                    SYSTEM STARTUP SEQUENCE                    ║
╚═══════════════════════════════════════════════════════════════╝

Step 1: Start Python Brain
────────────────────────────────────────────────────────────────
Command: cd 02_Brain && python main.py

main.py:
  ├─ Import modules
  ├─ Load configuration (config.py)
  ├─ Create shared memory (multiprocessing.Manager)
  │   ├─ tick_queue
  │   ├─ policy_queue
  │   └─ metrics (ticks_processed, policies_sent, etc.)
  │
  ├─ Spawn Worker 1: Ingestion
  │   └─ core.ingestion.IngestionWorker()
  │       ├─ Connect ZMQ SUB 7777
  │       ├─ Start polling loop
  │       └─ Status: 📥 INGESTION: Bound to tcp://127.0.0.1:7777
  │
  ├─ Spawn Worker 2+3: Strategy Engine
  │   └─ core.strategy.create_strategy_engine_threaded()
  │       ├─ Initialize StrategyEngine
  │       ├─ Connect ZMQ PUB 7778
  │       ├─ Start processing loop
  │       └─ Status: 📤 STRATEGY: Publishing on tcp://127.0.0.1:7778
  │
  ├─ Spawn Worker 4: Execution Listener
  │   └─ core.execution_listener.ExecutionListener()
  │       ├─ Connect ZMQ SUB 7779
  │       ├─ Start polling loop
  │       └─ Status: 📨 EXECUTION: Bound to tcp://127.0.0.1:7779
  │
  └─ Start Dashboard (main thread)
      ├─ Display system status
      ├─ Show metrics every 5 seconds
      └─ Status: ✅ All workers started

Python Brain State: READY (4 workers running)


Step 2: Attach FeederEA to MT5 Chart
────────────────────────────────────────────────────────────────
Action: Drag FeederEA.ex5 to XAUUSD M1 chart

OnInit():
  ├─ g_Context.initialize()
  │   └─ Create ZMQ context
  │
  ├─ g_Socket.initialize(ZMQ_PUB)
  │   └─ Create Publisher socket
  │
  ├─ g_Socket.connect("tcp://127.0.0.1:7777")
  │   └─ Connect to Python Brain (port 7777)
  │
  ├─ g_Socket.setLinger(0)
  ├─ g_Socket.setSendHighWaterMark(100000)
  │
  ├─ ArrayResize(g_LastTickTime, 4)
  ├─ ArrayInitialize(g_LastTickTime, 0)
  │
  ├─ EventSetMillisecondTimer(50)
  │   └─ Start timer (OnTimer every 50ms)
  │
  └─ Print("✅ Feeder Ready")

FeederEA State: BROADCASTING (timer active)


Step 3: Attach Trader to MT5 Chart
────────────────────────────────────────────────────────────────
Action: Drag ProgramC_Trader.ex5 to XAUUSD M1 chart

OnInit():
  ├─ Initialize ZMQ Hub:
  │   ├─ zmq_hub.Connect(ZMQ_SUB, "tcp://127.0.0.1:7778")
  │   │   └─ Receive policies from Python
  │   └─ zmq_hub.Connect(ZMQ_PUB, "tcp://127.0.0.1:7779")
  │       └─ Send results to Python
  │
  ├─ Initialize Strategy Manager:
  │   ├─ strategy_mgr.AddStrategy(new CStrategyGrid())
  │   │   └─ Status: ✅ Added: Elastic Grid Strategy
  │   └─ strategy_mgr.AddStrategy(new CStrategySpikeHunter())
  │       └─ Status: ✅ Added: Spike Hunter Strategy
  │
  ├─ Initialize Risk Guardian:
  │   └─ risk_guard.Initialize(5, 0.02)
  │       ├─ Max orders: 5
  │       ├─ Max risk: 2%
  │       └─ Status: ✅ Risk Guardian initialized
  │
  ├─ Initialize Policy Manager:
  │   └─ policy_mgr.Initialize()
  │       └─ Status: ✅ Policy Manager ready
  │
  ├─ EventSetMillisecondTimer(100)
  │   └─ Start timer (OnTimer every 100ms)
  │
  └─ Print("✅ System Ready. Waiting for Brain Policy...")

Trader State: WAITING_FOR_POLICY


═══════════════════════════════════════════════════════════════
SYSTEM STATUS: FULLY OPERATIONAL
═══════════════════════════════════════════════════════════════
```

---

## 🔄 **Control Flow - Runtime Loop**

```
╔═══════════════════════════════════════════════════════════════╗
║                  RUNTIME EXECUTION LOOP                       ║
╚═══════════════════════════════════════════════════════════════╝

TICK GENERATION (Market → MT5)
═══════════════════════════════════════════════════════════════
Market Event: Price change
  ↓
MT5 Terminal receives tick
  ├─ Symbol: XAUUSD
  ├─ Bid: 4194.43
  ├─ Ask: 4194.71
  └─ Time: 2025-12-06 10:30:15.234


FEEDER LOOP (Every 50ms)
═══════════════════════════════════════════════════════════════
OnTimer() triggered (FeederEA)
  │
  ├─ Loop: i = 0 to 3
  │   │
  │   ├─ Symbol = g_StandardSymbols[i]  // "EURUSD"
  │   │
  │   ├─ SymbolInfoTick(Symbol, tick)
  │   │   └─ Result: Success, tick populated
  │   │
  │   ├─ Compare: tick.time_msc vs g_LastTickTime[i]
  │   │   ├─ If tick.time_msc <= g_LastTickTime[i]
  │   │   │   └─ OLD tick → continue (skip)
  │   │   │
  │   │   └─ If tick.time_msc > g_LastTickTime[i]
  │   │       └─ NEW tick → Process
  │   │
  │   ├─ Update: g_LastTickTime[i] = tick.time_msc
  │   ├─ Increment: g_SequenceID++
  │   │
  │   ├─ Serialize MessagePack:
  │   │   g_MsgPack.Reset()
  │   │   g_MsgPack.PackArray(7)
  │   │   g_MsgPack.PackInt(1)              // Type: Tick
  │   │   g_MsgPack.PackInt(g_SequenceID)   // 12345
  │   │   g_MsgPack.PackInt(tick.time_msc)  // 1733562615234
  │   │   g_MsgPack.PackString(Symbol)      // "EURUSD"
  │   │   g_MsgPack.PackDouble(tick.bid)    // 1.0543
  │   │   g_MsgPack.PackDouble(tick.ask)    // 1.0544
  │   │   g_MsgPack.PackInt(tick.flags)     // 6
  │   │   g_MsgPack.GetData(data)
  │   │
  │   ├─ Send ZMQ:
  │   │   sent = g_Socket.send_bin(data, true)
  │   │   └─ Result: 65 bytes sent
  │   │
  │   └─ Log (if g_SequenceID % 100 == 0):
  │       Print("🚀 Tick Sent: EURUSD")
  │
  └─ Next symbol...

Timer sleeps until next 50ms cycle


PYTHON INGESTION (Worker 1)
═══════════════════════════════════════════════════════════════
IngestionWorker.run() loop
  │
  ├─ zmq_sub.poll(timeout=10)
  │   └─ Message available: True
  │
  ├─ data = zmq_sub.recv()
  │   └─ Received: 65 bytes
  │
  ├─ Deserialize:
  │   tick = msgpack.unpackb(data)
  │   └─ tick = [1, 12345, 1733562615234, "EURUSD", 1.0543, 1.0544, 6]
  │
  ├─ Validate:
  │   ├─ Check type == 1
  │   ├─ Check has required fields
  │   └─ Result: Valid
  │
  ├─ Put in queue:
  │   tick_queue.put(tick)
  │   └─ Queue size: 1
  │
  └─ Increment: metrics.ticks_processed += 1

Loop continues (poll next message)


PYTHON STRATEGY ENGINE (Worker 2)
═══════════════════════════════════════════════════════════════
StrategyEngine.run() loop
  │
  ├─ tick = tick_queue.get()  // Blocking
  │   └─ Got tick: [1, 12345, ..., "EURUSD", 1.0543, 1.0544, 6]
  │
  ├─ Update market state:
  │   self.latest_prices["EURUSD"] = {"bid": 1.0543, "ask": 1.0544}
  │   self.price_history["EURUSD"].append(1.0543)
  │   self.tick_count += 1
  │
  ├─ Analysis:
  │   signal = analysis.analyze_market_condition(tick)
  │   │
  │   │ analyze_market_condition():
  │   │   ├─ Calculate spread: 0.0001
  │   │   ├─ Calculate volatility: 0.0015
  │   │   ├─ Detect trend: SIDEWAYS
  │   │   ├─ Find patterns: None
  │   │   └─ Return: MarketSignal(
  │   │         symbol="EURUSD",
  │   │         trend="SIDEWAYS",
  │   │         volatility=0.0015,
  │   │         confidence=0.65
  │   │       )
  │   │
  │   └─ signal received
  │
  ├─ Policy Generation:
  │   policy = policy.generate_policy(signal, risk_params)
  │   │
  │   │ generate_policy():
  │   │   ├─ Select strategy: "Grid" (sideways market)
  │   │   ├─ Calculate risk: 1.0x (default)
  │   │   ├─ Set confidence: 0.65
  │   │   └─ Return: PolicyMessage(
  │   │         symbol="EURUSD",
  │   │         strategy="Grid",
  │   │         risk=1.0,
  │   │         confidence=0.65,
  │   │         params={...}
  │   │       )
  │   │
  │   └─ policy received
  │
  └─ Put in queue:
      policy_queue.put(policy)
      └─ Queue size: 1

Loop continues (get next tick)


PYTHON POLICY PUBLISHER (Worker 3)
═══════════════════════════════════════════════════════════════
PolicyPublisher.run() loop (in StrategyEngine)
  │
  ├─ policy = policy_queue.get()  // Blocking
  │   └─ Got policy: PolicyMessage(...)
  │
  ├─ Serialize:
  │   data = msgpack.packb(policy.to_dict())
  │   └─ Packed: ~80 bytes
  │
  ├─ Send ZMQ:
  │   zmq_pub.send(data)
  │   └─ Published to port 7778
  │
  └─ Increment: metrics.policies_sent += 1

Loop continues (get next policy)


TRADER EXECUTION (Worker C)
═══════════════════════════════════════════════════════════════
OnTimer() triggered (Trader) - Every 100ms
  │
  ├─ Poll ZMQ SUB 7778:
  │   result = zmq_hub.Poll(10)
  │   └─ Message available: True
  │
  ├─ Receive:
  │   data = zmq_hub.Receive()
  │   └─ Received: ~80 bytes
  │
  ├─ Deserialize:
  │   policy_msg = CProtocol::DeserializePolicy(data)
  │   └─ PolicyMessage {
  │         symbol: "EURUSD",
  │         strategy: "Grid",
  │         risk: 1.0,
  │         confidence: 0.65,
  │         params: {...}
  │       }
  │
  ├─ Validate:
  │   ├─ Check symbol == _Symbol
  │   │   └─ "EURUSD" == "EURUSD" → Match ✅
  │   │
  │   ├─ Check strategy available
  │   │   └─ strategy_mgr.HasStrategy("Grid") → True ✅
  │   │
  │   └─ Risk Guardian:
  │       risk_guard.ValidatePolicy(policy_msg)
  │       ├─ Check current exposure: 0%
  │       ├─ Check max orders: 0 / 5
  │       └─ Result: APPROVED ✅
  │
  ├─ Execute:
  │   strategy_mgr.ExecutePolicy(policy_msg)
  │   │
  │   │ Grid Strategy:
  │   │   ├─ Calculate grid levels
  │   │   ├─ Check existing orders
  │   │   ├─ Place new order:
  │   │   │   OrderSend(
  │   │   │     symbol: "EURUSD",
  │   │   │     type: OP_BUY,
  │   │   │     lots: 0.01,
  │   │   │     price: 1.0543,
  │   │   │     sl: 1.0523,
  │   │   │     tp: 1.0563
  │   │   │   )
  │   │   │   └─ Result: ticket = 123456
  │   │   │
  │   │   └─ Update grid state
  │   │
  │   └─ Build trade result:
  │       TradeResult {
  │         ticket: 123456,
  │         symbol: "EURUSD",
  │         type: "BUY",
  │         lots: 0.01,
  │         profit: 0.0,  // New order
  │         status: "OPENED"
  │       }
  │
  ├─ Serialize result:
  │   data = CProtocol::SerializeTradeResult(result)
  │   └─ Packed: ~70 bytes
  │
  ├─ Send to Python:
  │   zmq_hub.Send(data, 7779)
  │   └─ Published to port 7779
  │
  └─ Log:
      Print("✅ Order opened: #123456 EURUSD BUY 0.01")

Timer sleeps until next 100ms cycle


PYTHON EXECUTION LISTENER (Worker 4)
═══════════════════════════════════════════════════════════════
ExecutionListener.run() loop
  │
  ├─ zmq_sub.poll(timeout=10)
  │   └─ Message available: True
  │
  ├─ data = zmq_sub.recv()
  │   └─ Received: ~70 bytes
  │
  ├─ Deserialize:
  │   result = msgpack.unpackb(data)
  │   └─ TradeResult {...}
  │
  ├─ Update performance:
  │   feedback.update_performance(result)
  │   │
  │   │ update_performance():
  │   │   ├─ If profit > 0:
  │   │   │   ├─ win_count += 1
  │   │   │   └─ Increase risk: risk_mult *= 1.1
  │   │   ├─ If profit < 0:
  │   │   │   ├─ loss_count += 1
  │   │   │   └─ Decrease risk: risk_mult *= 0.9
  │   │   └─ Update total_profit
  │   │
  │   └─ metrics updated
  │
  └─ Log:
      print(f"📊 Trade result: #{result.ticket} P&L={result.profit}")

Loop continues (poll next message)


═══════════════════════════════════════════════════════════════
CYCLE COMPLETE - FEEDBACK LOOP CLOSED
═══════════════════════════════════════════════════════════════

Next tick arrives → Loop repeats
```

---

## 📊 **Timing Analysis**

```
╔═══════════════════════════════════════════════════════════════╗
║              END-TO-END LATENCY BREAKDOWN                     ║
╚═══════════════════════════════════════════════════════════════╝

T=0ms       Market tick arrives at MT5
              │
T=0.7ms     FeederEA processes & sends
              ├─ SymbolInfoTick: 0.1ms
              ├─ Serialize MsgPack: 0.5ms
              └─ ZMQ send: 0.1ms
              │
T=1.2ms     Python receives (ZMQ latency: 0.5ms)
              │
T=1.5ms     Ingestion deserializes & queues
              └─ Deserialize + Queue: 0.3ms
              │
T=3.5ms     Strategy Engine processes
              ├─ Get from queue: 0ms (blocking)
              ├─ Analysis: 1.5ms
              └─ Policy gen: 0.5ms
              │
T=4.0ms     Policy queued & published
              └─ Serialize + Send: 0.5ms
              │
T=4.5ms     Trader receives (ZMQ latency: 0.5ms)
              │
T=5.0ms     Trader processes & executes
              ├─ Deserialize: 0.1ms
              ├─ Validate: 0.1ms
              └─ Strategy exec: 0.3ms
              │
T=5.0-100ms Order sent to broker (variable)
              └─ Network + Broker processing
              │
T=105ms     Trade result sent back
              │
T=105.5ms   Python receives & updates
              └─ Feedback loop complete

═══════════════════════════════════════════════════════════════
SUMMARY:
  Python Processing:    4ms (T=1.2ms → T=5.0ms)
  End-to-End (Python):  ~4ms ✅ Excellent!
  End-to-End (Total):   ~105ms (includes broker)
═══════════════════════════════════════════════════════════════
```

---

**These diagrams provide complete understanding of:**
1. How data flows through the system
2. How control is transferred between components
3. Timing and performance characteristics
4. Worker coordination and queuing
5. Feedback loop closure

**For code-level details, see individual module documentation.**
