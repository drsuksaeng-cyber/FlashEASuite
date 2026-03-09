//+------------------------------------------------------------------+
//|                                          ProgramC_Trader.mq5     |
//|                            FlashEASuite V2 - Program C Trader    |
//|                            V2.12 + V6 (Phase0 chat3 merged)      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.13"
#property strict

// ========== INCLUDES ==========
#include "../Include/MqlMsgPack.mqh"
#include "../Include/Zmq/ZmqHub.mqh"
#include "../Include/Zmq/Zmq.mqh"
#include "../Include/Network/Protocol.mqh"
#include "../Include/Logic/StrategyManager.mqh"
// Note: StrategyManager.mqh includes Strategy_Grid.mqh
#include "../Include/Risk/RiskGuardian.mqh"
// Note: RiskGuardian.mqh includes PositionSizingManager.mqh and DailyLossLimit.mqh
#include "../Include/Utils/SymbolScanner.mqh"  // Multi-symbol scanner

// ✅ FIX #1: เพิ่ม includes สำหรับ Spike Strategy
#include "../Include/Logic/TickDensity.mqh"    // Required by Strategy_Spike
#include "../Include/Logic/SpreadFilter.mqh"   // Required by Strategy_Spike
#include "../Include/Logic/Strategy_Spike.mqh" // Spike Hunter Strategy

// ========== V6 PHASE0 CHAT3 INCLUDES ==========
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/ConnectionMonitor.mqh"
#include "../Include/Logic/ConfigReceiver.mqh"
#include "../Include/Logic/StrategyManager_V6.mqh"

// ========== SECURITY LAYER P9-2 ==========
// Remove #define STUB_MODE after deploying FlashEA_Security.dll
// to: %AppData%\MetaQuotes\Terminal\<ID>\MQL5\Libraries\
#define STUB_MODE
#include "../Include/Security/DLLWrapper.mqh"

// ========== INPUT PARAMETERS ==========
//+------------------------------------------------------------------+
//| Symbol Formatting (Broker-specific)                              |
//+------------------------------------------------------------------+
input string   SYMBOL_PREFIX = "";           // Symbol Prefix (e.g., "f" for FXPro, empty for most)
input string   SYMBOL_SUFFIX = ".tp";          // Symbol Suffix (e.g., ".tp", "m", "_i", empty for ICMarkets)

//+------------------------------------------------------------------+
//| V6 Connection Parameters (Phase0 chat3)                          |
//+------------------------------------------------------------------+
input string   V6_ServerIP            = "127.0.0.1";      // Python Server IP (V6 mode)
input int      V6_ServerPort          = 7778;             // ZMQ PUB port for CONFIG_PUSH
input string   V6_ClientID            = "MT5_Client_001"; // Unique client identifier
input bool     V6_EnableMode          = true;             // Enable V6 mode? (default: V6 standalone)
input int      V6_HeartbeatTimeout    = 30;              // Seconds until disconnect
input int      V6_HeartbeatInterval   = 10;              // Seconds between heartbeats

//+------------------------------------------------------------------+
//| V6 Strategy Selection (one EA per chart, pick strategy here)    |
//+------------------------------------------------------------------+
input bool     V6_Enable_S06 = false;  // Enable S06 KAMA (attach on USDJPY H4)
input bool     V6_Enable_S10 = false;  // Enable S10 Turtle (DISABLED — re-optimize pending)
input bool     V6_Enable_S14 = false;  // Enable S14 BBSqueeze (attach on XAUUSD H1 or GBPUSD H1)
input double   V6_MinConfidence = 0.30; // Minimum signal confidence to trade

// ========== GLOBAL VARIABLES ==========
// ZMQ Components (Legacy)
CZmqHub g_zmq_hub;              // Handles SUB socket (receive policies)
Context g_pub_context;          // Separate context for PUB socket
Socket  g_pub_socket(ZMQ_PUB);  // Send feedback to Python (port 7779)

// Strategy & Risk Components (Legacy)
CStrategyManager    g_council;
CRiskGuardian       g_risk_guardian;
CSymbolScanner      g_scanner;  // Multi-symbol scanner
// Note: PositionSizingManager and DailyLossLimit are managed by RiskGuardian

// V6 Components (Phase0 chat3)
CConnectionMonitor      g_connection_monitor_v6;
CConfigReceiver         g_config_receiver_v6;
CStrategyManager_V6     g_strategy_manager_v6;

// Operational State
bool g_is_connected = false;
int  g_policies_received = 0;
int  g_trades_executed = 0;
datetime g_last_policy_time = 0;

// V6 State
bool g_v6_mode_active = false;
bool g_v6_online_mode = false;
bool g_v6_standalone_mode = false;

// Security P9-2
CDLLWrapper g_security;

// Scanner state
datetime g_last_scan_time = 0;
int      g_scan_interval = 300;  // Rescan every 5 minutes

// DEBUG: Counters
int  g_timer_calls = 0;
int  g_poll_attempts = 0;
int  g_poll_success = 0;
int  g_poll_failures = 0;

// ========== INITIALIZATION ==========
int OnInit()
{
   Print("╔════════════════════════════════════════════════╗");
   Print("║  ProgramC_Trader V2.12 + V6 - Initializing...║");
   Print("╚════════════════════════════════════════════════╝");
   
   // Check if V6 mode is enabled
   if(V6_EnableMode)
   {
      Print("[V6] V6 Mode ENABLED - Using Phase0 chat3 components");
      g_v6_mode_active = true;
      return InitializeV6Mode();
   }
   
   // Legacy mode initialization (original code)
   return InitializeLegacyMode();
}

//+------------------------------------------------------------------+
//| InitializeLegacyMode: Original ProgramC_Trader initialization    |
//+------------------------------------------------------------------+
int InitializeLegacyMode()
{
   Print("[LEGACY] Initializing Legacy Mode (V2.12)");
   
   // 0. Security (P9-2) — warning-only, non-fatal in development
   g_security.Initialize();
   if(!g_security.IsLicenseValid())
      Print("[SECURITY] WARNING: License not valid (stub/degraded mode)");
   else
      Print("[SECURITY] License OK");
   
   // 1. Initialize ZMQ Hub (for SUB socket)
   if(!g_zmq_hub.Initialize(0, 0))
   {
      Print("❌ FAILED: ZMQ Hub initialization");
      return INIT_FAILED;
   }
   Print("✅ ZMQ Hub created");
   
   // 2. Subscribe to Python Brain policies (port 7778)
   // CRITICAL: Must provide topic parameter (empty string = subscribe to all)
   if(!g_zmq_hub.Subscribe("tcp://127.0.0.1:7778", ""))
   {
      Print("❌ FAILED: Subscribe to tcp://127.0.0.1:7778");
      return INIT_FAILED;
   }
   Print("✅ Subscribed to tcp://127.0.0.1:7778 (Python policies)");
   
   // 3. Initialize PUB socket for feedback (port 7779)
   if(!g_pub_context.initialize())
   {
      Print("❌ FAILED: PUB Context initialization");
      return INIT_FAILED;
   }
   
   if(!g_pub_socket.initialize(g_pub_context, ZMQ_PUB))
   {
      Print("❌ FAILED: PUB Socket initialization");
      return INIT_FAILED;
   }
   
   if(!g_pub_socket.connect("tcp://127.0.0.1:7779"))
   {
      Print("❌ FAILED: Connect to tcp://127.0.0.1:7779");
      return INIT_FAILED;
   }
   
   g_pub_socket.setLinger(0);
   Print("✅ PUB Socket connected to tcp://127.0.0.1:7779 (feedback)");
   
   // 4. Initialize Risk Management
   // RiskGuardian will create and initialize PositionSizingManager and DailyLossLimit
   if(!g_risk_guardian.Initialize(10, 2.0, 15.0, 2.0))  // max_orders, max_risk%, max_exposure%, daily_limit%
   {
      Print("❌ FAILED: Risk Guardian initialization");
      return INIT_FAILED;
   }
   Print("✅ Risk Guardian initialized (Max 10 orders, 2% risk, 2% daily limit)");
   
   // 5. Initialize Council (Strategy Manager)
   g_council.Initialize();
   
   // 5a. Add Grid Strategy
   CStrategyGrid* grid = new CStrategyGrid();
   g_council.AddStrategy(grid);
   Print("✅ Grid Strategy added to Council");
   
   // ✅ FIX #2 & #3: เพิ่ม Spike Strategy ตำแหน่งถูกต้อง + ใช้ g_council
   // 5b. Add Spike Hunter Strategy
   CStrategySpike* spike = new CStrategySpike();
   if(spike.Init())
   {
      g_council.AddStrategy(spike);  // ✅ เปลี่ยนจาก strategy_mgr เป็น g_council
      Print("✅ Spike Hunter Strategy added to Council");
   }
   else
   {
      Print("❌ Failed to initialize Spike Hunter Strategy");
      delete spike;
   }
   
   // 6. Initialize Symbol Scanner
   g_scanner.SetMaxSpreadPercent(0.15);  // Max 0.15% spread
   g_scanner.SetMinVolatility(0.0001);   // Min ATR
   g_scanner.SetForexOnly(true);         // Forex pairs only
   g_scanner.SetMajorPairsOnly(false);   // All forex pairs
   
   Print("🔍 Scanning Market Watch for tradeable symbols...");
   if(g_scanner.ScanMarketWatch())
   {
      Print("✅ Symbol Scanner initialized: ", g_scanner.GetSymbolCount(), " symbols found");
      g_scanner.PrintScanResults();
      g_last_scan_time = TimeCurrent();
   }
   else
   {
      Print("⚠️  No tradeable symbols found in Market Watch");
   }
   
   // 7. Start Timer (check for policies every 100ms)
   EventSetMillisecondTimer(100);
   
   // 8. System Ready
   g_is_connected = true;
   
   // Display Symbol Formatting Configuration
   Print("╔════════════════════════════════════════════════╗");
   Print("║  Symbol Formatting Configuration             ║");
   Print("╚════════════════════════════════════════════════╝");
   Print("📋 Symbol Formatting:");
   Print("   Prefix: '", SYMBOL_PREFIX, "'", (SYMBOL_PREFIX == "" ? " (none)" : ""));
   Print("   Suffix: '", SYMBOL_SUFFIX, "'", (SYMBOL_SUFFIX == "" ? " (none)" : ""));
   Print("   Example: XAUUSD → ", FormatSymbol("XAUUSD"));
   Print("");
   
   Print("╔════════════════════════════════════════════════╗");
   Print("║  ✅ SYSTEM READY - Waiting for Brain Policy  ║");
   Print("╚════════════════════════════════════════════════╝");
   Print("");
   Print("🔍 DEBUG MODE ENABLED:");
   Print("   - Timer: 100ms interval");
   Print("   - Status report: Every 10 seconds");
   Print("   - Detailed logs: First 10 polls");
   Print("   - Watching for messages on port 7778...");
   Print("");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| InitializeV6Mode: V6 Phase0 chat3 initialization                 |
//+------------------------------------------------------------------+
int InitializeV6Mode()
{
   Print("[V6] Initializing V6 Mode (P6-1)...");
   Print("[V6] Server: ", V6_ServerIP, ":", V6_ServerPort);
   Print("[V6] ClientID: ", V6_ClientID);

   // 0. Security (P9-2)
   g_security.Initialize();
   if(!g_security.IsLicenseValid())
      Print("[V6][SECURITY] WARNING: License not valid (stub/degraded mode)");
   else
      Print("[V6][SECURITY] License OK");

   // 1. Symbol สำหรับ V6 (chart symbol หรือ default XAUUSD.tp)
   string v6_symbol = (Symbol() != "") ? Symbol() : FormatSymbol("XAUUSD");

   // 2. Init ConnectionMonitor (30s timeout, warn at 20s)
   g_connection_monitor_v6.Init(V6_HeartbeatTimeout, 20);

   // 3. Init ConfigReceiver (P6-1 full version) — ส่ง symbol เพื่อ filter multi-symbol ConfigPush
   g_config_receiver_v6.Init(v6_symbol);

   // 4. Subscribe ZMQ SUB socket ไปยัง Python Server (port 7778 PUB)
   if(!g_zmq_hub.Initialize(0, 0))
   {
      Print("[V6] ❌ ZMQ Hub init failed");
      return INIT_FAILED;
   }
   string sub_addr = "tcp://" + V6_ServerIP + ":" + IntegerToString(V6_ServerPort);
   if(!g_zmq_hub.Subscribe(sub_addr, ""))
   {
      Print("[V6] ❌ ZMQ Subscribe failed: ", sub_addr);
      return INIT_FAILED;
   }
   Print("[V6] ✅ Subscribed to ", sub_addr);

   // 4b. Init Risk Management (required for ExecuteV6Signals)
   if(!g_risk_guardian.Initialize(10, 2.0, 15.0, 2.0))
   {
      Print("[V6] ❌ Risk Guardian init failed");
      return INIT_FAILED;
   }
   Print("[V6] ✅ Risk Guardian initialized");

   // 5. Register all 16 strategies using CHART timeframe (not hardcoded M15)
   if(!g_strategy_manager_v6.RegisterAllStrategies(v6_symbol, Period()))
      Print("[V6] ⚠️  Some strategies failed Init — continuing with partial set");

   // 6. Start in STANDALONE mode — disable all, then enable only selected
   g_v6_standalone_mode = true;
   g_v6_online_mode     = false;
   g_strategy_manager_v6.SetServerConnected(false);

   // Disable all strategies first
   for(int i = 0; i < TOTAL_STRATEGIES; i++)
   {
      IStrategy* s = g_strategy_manager_v6.GetStrategyByID((ENUM_STRATEGY_ID)i);
      if(s != NULL) s.Disable();
   }

   // Enable only user-selected strategies
   int v6_enabled_count = 0;
   if(V6_Enable_S06) { g_strategy_manager_v6.EnableStrategy_V6(S06_KAMA);       v6_enabled_count++; Print("[V6] ✅ S06 KAMA enabled"); }
   if(V6_Enable_S10) { g_strategy_manager_v6.EnableStrategy_V6(S10_TURTLE);     v6_enabled_count++; Print("[V6] ✅ S10 Turtle enabled (WARNING: validation pending)"); }
   if(V6_Enable_S14) { g_strategy_manager_v6.EnableStrategy_V6(S14_BB_SQUEEZE); v6_enabled_count++; Print("[V6] ✅ S14 BBSqueeze enabled"); }

   if(v6_enabled_count == 0)
      Print("[V6] ⚠️  No strategies selected — set V6_Enable_S06 or V6_Enable_S14 to true");

   // 7. Start timer 100ms สำหรับ poll + strategy tick
   EventSetMillisecondTimer(100);

   Print("[V6] ✅ V6 Mode initialized | symbol=", v6_symbol,
         " | strategies=", g_strategy_manager_v6.GetEnabledCount_V6(), "/16");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Format Symbol with Prefix/Suffix                                 |
//+------------------------------------------------------------------+
string FormatSymbol(string base_symbol)
{
   return SYMBOL_PREFIX + base_symbol + SYMBOL_SUFFIX;
}

//+------------------------------------------------------------------+
//| Strip Symbol to Base (remove prefix/suffix)                      |
//+------------------------------------------------------------------+
string StripSymbol(string formatted_symbol)
{
   string result = formatted_symbol;
   
   // Remove prefix
   if(SYMBOL_PREFIX != "" && StringFind(result, SYMBOL_PREFIX) == 0)
      result = StringSubstr(result, StringLen(SYMBOL_PREFIX));
   
   // Remove suffix
   if(SYMBOL_SUFFIX != "" && StringFind(result, SYMBOL_SUFFIX) >= 0)
   {
      int pos = StringFind(result, SYMBOL_SUFFIX);
      if(pos >= 0)
         result = StringSubstr(result, 0, pos);
   }
   
   return result;
}

// ========== DEINITIALIZATION ==========
void OnDeinit(const int reason)
{
   Print("🛑 ProgramC_Trader shutting down...");
   Print("   Policies received: ", g_policies_received);
   Print("   Trades executed: ", g_trades_executed);
   
   EventKillTimer();
   
   if(g_v6_mode_active)
   {
      Print("[V6] V6 Mode shutdown");
      g_strategy_manager_v6.Deinit();
      g_zmq_hub.Shutdown();  // P6-1: shutdown ZMQ SUB socket
   }
   else
   {
      // Legacy mode cleanup
      g_zmq_hub.Shutdown();
      g_pub_socket.close();
      g_pub_context.shutdown();
   }
   
   Print("✅ Shutdown complete");
}

// ========== TIMER EVENT (Main Loop) ==========
void OnTimer()
{
   if(g_v6_mode_active)
   {
      OnTimer_V6();
   }
   else
   {
      OnTimer_Legacy();
   }
}

//+------------------------------------------------------------------+
//| OnTimer_Legacy: Original timer logic (V2.12)                     |
//+------------------------------------------------------------------+
void OnTimer_Legacy()
{
   g_timer_calls++;
   
   // Display status every 10 seconds (100 timer calls * 100ms = 10 sec)
   if(g_timer_calls % 100 == 0)
   {
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Print("📊 STATUS UPDATE (", g_timer_calls / 100, " x 10 sec)");
      Print("   Timer calls: ", g_timer_calls);
      Print("   Poll attempts: ", g_poll_attempts);
      Print("   Poll success: ", g_poll_success);
      Print("   Poll failures: ", g_poll_failures);
      Print("   Policies received: ", g_policies_received);
      Print("   Trades executed: ", g_trades_executed);
      
      int seconds_since_policy = (g_last_policy_time > 0) ? 
                                  (int)(TimeCurrent() - g_last_policy_time) : -1;
      if(seconds_since_policy >= 0)
         Print("   Last policy: ", seconds_since_policy, " seconds ago");
      else
         Print("   Last policy: Never");
      
      Print("   Connection: ", (g_is_connected ? "✅ Connected" : "❌ Disconnected"));
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   }
   
   // Rescan symbols periodically
   if(TimeCurrent() - g_last_scan_time >= g_scan_interval)
   {
      Print("🔄 Re-scanning Market Watch...");
      g_scanner.ScanMarketWatch();
      g_last_scan_time = TimeCurrent();
   }
   
   // Security: periodic DLL verification P9-2
   if(!g_security.PeriodicVerification())
   {
      Print("[SECURITY] DLL verification failed — stopping EA");
      ExpertRemove();
      return;
   }
   
   // Poll for messages from Python Brain
   g_poll_attempts++;
   
   // Detailed logging for first 10 polls
   if(g_poll_attempts <= 10)
   {
      Print("🔍 Poll attempt #", g_poll_attempts, " (detailed mode)");
   }
   
   uchar recv_data[];
   if(!g_zmq_hub.Poll(recv_data))  // Poll without timeout parameter
   {
      // No message available
      g_poll_failures++;
      
      // Log first 10 failures
      if(g_poll_attempts <= 10)
      {
         Print("   ❌ Poll returned false (no message) - attempt #", g_poll_attempts);
      }
      
      // No message available (normal, not an error)
      return;
   }
   
   // Success! We got a message!
   g_poll_success++;
   g_policies_received++;
   g_last_policy_time = TimeCurrent();
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🔥 POLICY RECEIVED FROM BRAIN #", g_policies_received);
   Print("   Bytes: ", ArraySize(recv_data));
   Print("   Poll attempt #", g_poll_attempts, " succeeded!");
   
   // Deserialize the policy message
   PolicyMessage policy;
   if(!CProtocol::DeserializePolicyMessage(recv_data, policy))
   {
      Print("❌ Failed to deserialize policy");
      return;
   }
   
   // Display policy details
   Print("   Symbol: ", policy.symbol);
   Print("   Action: ", policy.action, " (0=HOLD, 1=BUY, 2=SELL)");
   Print("   Confidence: ", DoubleToString(policy.confidence, 2));
   Print("   Entry Price: ", DoubleToString(policy.entry_price, _Digits));
   Print("   Stop Loss: ", DoubleToString(policy.stop_loss, _Digits));
   Print("   Take Profit: ", DoubleToString(policy.take_profit, _Digits));
   Print("   Position Size: ", DoubleToString(policy.position_size, 2));
   
   // Validate symbol is tradeable using scanner
   string policy_symbol = policy.symbol;
   
   // Format symbol with broker-specific prefix/suffix
   string formatted_symbol = FormatSymbol(policy_symbol);
   
   Print("   Symbol (base): ", policy_symbol);
   Print("   Symbol (formatted): ", formatted_symbol);
   
   // Check if symbol is in scanner's tradeable list
   if(!g_scanner.IsSymbolTradeable(formatted_symbol))
   {
      Print("⚠️  Symbol ", formatted_symbol, " not tradeable (not found in scanner)");
      Print("   Base symbol: ", policy_symbol);
      Print("   Prefix: '", SYMBOL_PREFIX, "' | Suffix: '", SYMBOL_SUFFIX, "'");
      Print("   Tip: Check SYMBOL_SUFFIX input parameter and Market Watch");
      return;
   }
   
   Print("✅ Symbol validated: ", formatted_symbol, " is tradeable");
   
   // Check daily loss limit
   if(!g_risk_guardian.CheckDailyLimit())
   {
      Print("🛑 Daily loss limit reached - Skipping policy");
      return;
   }
   
   // Execute policy
   ExecutePolicy(policy);
}

//+------------------------------------------------------------------+
//| ProcessConfigPushV2: Handle CONFIG_PUSH V2 message              |
//| Parses dynamic params and distributes to all registered         |
//| strategies via StrategyManager_V6.                              |
//| @param data  Raw MessagePack bytes from ZMQ                    |
//| @param size  Byte count                                         |
//+------------------------------------------------------------------+
void ProcessConfigPushV2(uchar &data[], int size)
{
   // Step 1: Parse the incoming CONFIG_PUSH V2 data
   if(!g_config_receiver_v6.ParseDynamicParams(data, size))
   {
      Print("[V6] ❌ CONFIG_PUSH V2 parse failed (", size, " bytes)");
      return;
   }
   
   // Step 2: Distribute parsed params per-strategy
   // ConfigReceiver.GetDynamicParamsForStrategy(id) → each strategy gets its own bundle
   for(int _i = 0; _i < TOTAL_STRATEGIES; _i++)
   {
      ENUM_STRATEGY_ID _id = (ENUM_STRATEGY_ID)_i;
      SDynamicParams _dp = g_config_receiver_v6.GetDynamicParamsForStrategy(_id);
      g_strategy_manager_v6.DistributeDynamicParams(_dp, _id);
   }
   
   // Step 3: Log result
   Print("[V6] ✅ CONFIG_PUSH V2 applied: ", g_config_receiver_v6.GetChangeSummary());
}

//+------------------------------------------------------------------+
//| OnTimer_V6: V6 Mode timer logic (P6-1 Full Implementation)       |
//+------------------------------------------------------------------+
void OnTimer_V6()
{
   g_timer_calls++;

   // Status update every 10 seconds (100 * 100ms = 10s)
   if(g_timer_calls % 100 == 0)
   {
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Print("📊 V6 STATUS (", g_timer_calls / 100, " x 10 sec)");
      Print("   Mode:        ", (g_v6_online_mode ? "ONLINE" : "STANDALONE"));
      Print("   Strategies:  ", g_strategy_manager_v6.GetEnabledCount_V6(), "/", TOTAL_STRATEGIES);
      Print("   Registered:  ", g_strategy_manager_v6.IsRegistered() ? "✅ YES" : "⚠️ NO");
      Print("   Connection:  ", g_connection_monitor_v6.GetStatus());
      Print("   Regime:      ", RegimeToString(g_config_receiver_v6.GetCurrentRegime()));
      Print("   Configs recv:", g_config_receiver_v6.GetConfigCount());
      if(g_config_receiver_v6.HasNewsEvent())
         Print("   📰 NEWS: ", g_config_receiver_v6.GetNewsDescription());
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   }

   // ── P6-1: Poll all pending ZMQ messages ──
   PollMessages_V6();

   // ── Security: periodic DLL verification P9-2 ──
   if(!g_security.PeriodicVerification())
   {
      Print("[V6][SECURITY] DLL verification failed — stopping EA");
      ExpertRemove();
      return;
   }

   // ── Strategy tick ──
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   g_strategy_manager_v6.OnTick(tick);

   // ── Execute signals from V6 strategies ──
   ExecuteV6Signals();
}

// ========== P6-1: V6 MESSAGE POLLING & ROUTING ==========

//+------------------------------------------------------------------+
//| PollMessages_V6: Drain ZMQ SUB socket, route each message        |
//| เรียกจาก OnTimer_V6() ทุก 100ms                                 |
//+------------------------------------------------------------------+
void PollMessages_V6()
{
   int max_per_poll = 20; // safety limit ต่อ timer call
   int count = 0;

   while(count < max_per_poll)
   {
      uchar raw[];
      if(!g_zmq_hub.Poll(raw)) break; // ไม่มีข้อความแล้ว

      int sz = ArraySize(raw);
      if(sz > 0)
      {
         ProcessMessage_V6(raw, sz);
         g_poll_success++;
      }
      count++;
   }

   // ── ตรวจ connection timeout ──────────────────────────────────────
   bool still_connected = g_connection_monitor_v6.Check();

   if(!still_connected && g_v6_online_mode)
   {
      // Timeout → switch to standalone
      g_v6_online_mode     = false;
      g_v6_standalone_mode = true;
      g_strategy_manager_v6.SetServerConnected(false);
      g_strategy_manager_v6.EnableAllStandalone(); // keep SA-capable only

      PrintFormat("[V6] ⚠️  SERVER TIMEOUT (%ds) → STANDALONE MODE | disabled hybrid strategies",
                  g_connection_monitor_v6.GetDisconnectDuration());
   }
   else if(still_connected && !g_v6_online_mode && g_v6_standalone_mode)
   {
      // Reconnected (heartbeat came back, online set inside ProcessMessage_V6)
      // Nothing extra here — online flag set when CONFIG_PUSH/INITIAL_CONFIG received
   }
}

//+------------------------------------------------------------------+
//| ProcessMessage_V6: Route 1 raw message to correct handler        |
//| ใช้ variable names ของไฟล์นี้ (_v6 suffix)                      |
//+------------------------------------------------------------------+
void ProcessMessage_V6(const uchar &data[], int size)
{
   if(size <= 0) return;

   // Route ผ่าน ConfigReceiver (parse + store internally)
   int msg_type = g_config_receiver_v6.ReceiveMessage(data, size);

   // ทุก message จาก server → reset heartbeat timeout
   if(msg_type > 0 && msg_type != MSG_V6_UNKNOWN)
      g_connection_monitor_v6.UpdateHeartbeat();

   switch(msg_type)
   {
      //---------------------------------------------------------------
      // [10] CONFIG_PUSH: apply + distribute params + save standalone
      //---------------------------------------------------------------
      case MSG_CONFIG_PUSH:
      {
         SConfigData cfg = g_config_receiver_v6.GetLastConfig();
         g_strategy_manager_v6.ApplyConfig_V6(cfg);

         // Distribute dynamic params แต่ละ strategy
         for(int i = 0; i < TOTAL_STRATEGIES; i++)
         {
            ENUM_STRATEGY_ID sid = (ENUM_STRATEGY_ID)i;
            SDynamicParams dp = g_config_receiver_v6.GetDynamicParamsForStrategy(sid);
            g_strategy_manager_v6.DistributeDynamicParams(dp, sid);
         }

         // Auto-save ทุกครั้งที่ได้ CONFIG_PUSH
         g_config_receiver_v6.SaveStandaloneConfig();

         // Switch → online ถ้ายังเป็น standalone
         if(!g_v6_online_mode)
         {
            g_v6_online_mode     = true;
            g_v6_standalone_mode = false;
            g_strategy_manager_v6.SetServerConnected(true);
            Print("[V6] ✅ Switched → ONLINE MODE (CONFIG_PUSH received)");
         }

         PrintFormat("[V6] CONFIG_PUSH: regime=%s | enabled=%d/16 | mm=%s",
            RegimeToString(g_config_receiver_v6.GetCurrentRegime()),
            g_strategy_manager_v6.GetEnabledCount_V6(),
            cfg.mm_method);
         break;
      }

      //---------------------------------------------------------------
      // [12] INITIAL_CONFIG: same as CONFIG_PUSH, already saved inside ConfigReceiver
      //---------------------------------------------------------------
      case MSG_INITIAL_CONFIG:
      {
         SConfigData cfg = g_config_receiver_v6.GetLastConfig();
         g_strategy_manager_v6.ApplyConfig_V6(cfg);

         for(int i = 0; i < TOTAL_STRATEGIES; i++)
         {
            ENUM_STRATEGY_ID sid = (ENUM_STRATEGY_ID)i;
            SDynamicParams dp = g_config_receiver_v6.GetDynamicParamsForStrategy(sid);
            g_strategy_manager_v6.DistributeDynamicParams(dp, sid);
         }

         g_v6_online_mode     = true;
         g_v6_standalone_mode = false;
         g_strategy_manager_v6.SetServerConnected(true);
         Print("[V6] ✅ INITIAL_CONFIG: ONLINE MODE | 16 strategies registered");
         break;
      }

      //---------------------------------------------------------------
      // [13] HEARTBEAT: UpdateHeartbeat already called above
      //---------------------------------------------------------------
      case MSG_HEARTBEAT:
         break;

      //---------------------------------------------------------------
      // [30] NEWS_ALERT
      //---------------------------------------------------------------
      case MSG_NEWS_ALERT:
      {
         if(g_config_receiver_v6.HasUnreadNews())
         {
            PrintFormat("[V6] 📰 NEWS [%d★]: %s %s",
               g_config_receiver_v6.GetLastNewsImpact(),
               g_config_receiver_v6.GetLastNewsCurrency(),
               g_config_receiver_v6.GetLastNewsName());
            g_config_receiver_v6.MarkNewsAsRead();
         }
         break;
      }

      //---------------------------------------------------------------
      // [31] REGIME_CHANGE
      //---------------------------------------------------------------
      case MSG_REGIME_CHANGE:
         PrintFormat("[V6] ⚡ REGIME: %s → %s | method=%s",
            RegimeToString(g_config_receiver_v6.GetPreviousRegime()),
            RegimeToString(g_config_receiver_v6.GetCurrentRegime()),
            g_config_receiver_v6.GetRegimeChangeMethod());
         break;

      //---------------------------------------------------------------
      // [40] COMMAND
      //---------------------------------------------------------------
      case MSG_COMMAND:
      {
         if(!g_config_receiver_v6.HasPendingCommand()) break;

         string cmd    = g_config_receiver_v6.GetPendingCommand();
         string target = g_config_receiver_v6.GetCommandTarget();

         // ถ้า target ระบุชื่อ client และไม่ใช่เรา → ไม่ต้องทำ
         if(target != "" && target != V6_ClientID)
         {
            g_config_receiver_v6.ClearPendingCommand();
            break;
         }

         PrintFormat("[V6] 📡 COMMAND: '%s'", cmd);

         if(cmd == "STOP")
            for(int _di=0;_di<TOTAL_STRATEGIES;_di++){IStrategy* _ds=g_strategy_manager_v6.GetStrategyByID((ENUM_STRATEGY_ID)_di);if(_ds!=NULL)_ds.Disable();}  // STOP: disable all
         else if(cmd == "START")
         {
            SConfigData cfg = g_config_receiver_v6.GetLastConfig();
            g_strategy_manager_v6.ApplyConfig_V6(cfg);
         }
         else if(cmd == "SWITCH_STANDALONE")
         {
            g_v6_online_mode     = false;
            g_v6_standalone_mode = true;
            g_strategy_manager_v6.SetServerConnected(false);
            g_connection_monitor_v6.ForceDisconnect();
            g_strategy_manager_v6.EnableAllStandalone(); // keep SA-capable, disable hybrid
            Print("[V6] COMMAND=SWITCH_STANDALONE: standalone mode");
         }
         else if(cmd == "STATUS")
         {
            g_strategy_manager_v6.GetStrategyStatus();
            Print("[V6] Connection: ", g_connection_monitor_v6.GetStatus());
         }
         else if(cmd == "CLOSE_ALL")
         {
            // TODO Phase P1+: close all positions
            Print("[V6] COMMAND=CLOSE_ALL (Phase P1+ implementation)");
         }

         g_config_receiver_v6.ClearPendingCommand();
         break;
      }

      //---------------------------------------------------------------
      // [14] MSG_DYNAMIC_PARAMS — Adaptive param hot-reload from Brain
      //---------------------------------------------------------------
      case MSG_DYNAMIC_PARAMS:
      {
         string  adapt_symbol = "";
         string  adapt_sid    = "";
         SDynamicParams adapt_dp;
         adapt_dp.Reset();

         if(g_config_receiver_v6.ParseAdaptiveParams14(data, size,
                                                        adapt_symbol,
                                                        adapt_sid,
                                                        adapt_dp))
         {
            // Map strategy_id string "SXX" → ENUM_STRATEGY_ID index
            int sid_num = (int)StringToInteger(StringSubstr(adapt_sid, 1));
            ENUM_STRATEGY_ID target_sid = (ENUM_STRATEGY_ID)(sid_num - 1);

            if(sid_num >= 1 && sid_num <= 16)
            {
               g_strategy_manager_v6.DistributeDynamicParams(adapt_dp, target_sid);
               PrintFormat("[BRAIN-ADAPT] %s %s | %d params applied",
                           adapt_symbol, adapt_sid,
                           adapt_dp.strategy_param_count);
            }
            else
            {
               PrintFormat("[BRAIN-ADAPT] Invalid strategy_id: %s", adapt_sid);
            }
         }
         else
         {
            PrintFormat("[BRAIN-ADAPT] Parse failed (%d bytes)", size);
         }
         break;
      }

      //---------------------------------------------------------------
      // [50] POLICY_UPDATE / [99] ERROR / unknown
      //---------------------------------------------------------------
      case MSG_POLICY_UPDATE:
         break;
      case MSG_ERROR:
         break;
      case MSG_V6_UNKNOWN:
      default:
         if(size > 0 && msg_type != 0)
            PrintFormat("[V6] Unknown msg_type=%d (%d bytes)", msg_type, size);
         break;
   }
}

// ========== V6 TRADE EXECUTION ==========

//+------------------------------------------------------------------+
//| HasOpenPositionByMagic: Check for open position (magic+symbol)  |
//+------------------------------------------------------------------+
bool HasOpenPositionByMagic(int magic, string symbol)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByIndex(i))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == magic &&
            PositionGetString(POSITION_SYMBOL) == symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| ExecuteV6Signals: Read signals from V6 strategies and trade     |
//| Called every timer tick from OnTimer_V6()                       |
//+------------------------------------------------------------------+
void ExecuteV6Signals()
{
   if(!g_risk_guardian.CheckDailyLimit())
   {
      return;  // daily limit — silent skip (already logged elsewhere)
   }

   string sym = FormatSymbol(_Symbol);

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
   {
      IStrategy* s = g_strategy_manager_v6.GetStrategyByID((ENUM_STRATEGY_ID)i);
      if(s == NULL || !s.IsEnabled() || !s.IsInitialized()) continue;

      ENUM_TRADE_SIGNAL sig = s.GetSignal();
      if(sig == SIGNAL_NONE) continue;

      int    magic      = s.GetMagic();
      double confidence = s.GetConfidence();
      double sl         = s.GetStopLoss();
      double tp         = s.GetTakeProfit();

      // Confidence filter
      if(confidence < V6_MinConfidence)
         continue;

      // SL/TP must be set
      if(sl <= 0.0 || tp <= 0.0)
      {
         PrintFormat("[V6] %s skip: SL/TP not set (sl=%.5f tp=%.5f)", s.GetShortName(), sl, tp);
         continue;
      }

      // Already in position for this strategy+symbol?
      if(HasOpenPositionByMagic(magic, sym)) continue;

      // Current price
      double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
      double price = (sig == SIGNAL_BUY) ? ask : bid;

      // Lot size
      double lot = g_risk_guardian.CalculateSafeLotSize(sym, price, sl);
      if(lot <= 0.0)
      {
         PrintFormat("[V6] %s skip: lot=0", s.GetShortName());
         continue;
      }

      // Risk validation
      if(!g_risk_guardian.ValidateNewTrade(sym, price, sl, lot))
      {
         PrintFormat("[V6] %s REJECTED by RiskGuardian", s.GetShortName());
         continue;
      }

      // Place trade
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
      req.magic        = magic;
      req.volume       = lot;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = 20;
      req.type_filling = ORDER_FILLING_FOK;
      req.comment      = s.GetShortName() + " V6standalone";
      req.type         = (sig == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
      {
         g_trades_executed++;
         PrintFormat("[V6] ✅ %s | %s | %s | lot=%.2f | sl=%.5f | tp=%.5f | conf=%.2f | deal=%d",
                    s.GetShortName(), sym,
                    (sig == SIGNAL_BUY ? "BUY" : "SELL"),
                    lot, sl, tp, confidence, (int)res.deal);
      }
      else
      {
         PrintFormat("[V6] ❌ %s | OrderSend FAILED | retcode=%d | err=%d",
                    s.GetShortName(), res.retcode, GetLastError());
      }
   }
}

// ========== EXECUTE POLICY FROM PYTHON ==========
void ExecutePolicy(PolicyMessage &policy)
{
   // ===== CRITICAL: Update Grid state FIRST (before checking action) =====
   // Grid needs to receive ALL policies, even HOLD actions
   CStrategyGrid* grid = g_council.GetGridStrategy();
   if(grid != NULL)
   {
      // Create modified policy with formatted symbol
      PolicyMessage formatted_policy = policy;
      formatted_policy.symbol = FormatSymbol(policy.symbol);
      
      grid.UpdateFromPolicy(formatted_policy);
      Print("✅ Grid state updated with policy data");
   }
   else
   {
      Print("⚠️  Grid strategy not found in Council");
   }
   
   // Grid policies arrive as action=0; derive direction from grid_direction (1=BUY,2=SELL)
   if(policy.action == 0 && (policy.grid_direction == 1 || policy.grid_direction == 2))
      policy.action = policy.grid_direction;

   // Skip if still HOLD (no direction)
   if(policy.action == 0)
   {
      Print("⏸️  Action is HOLD (no direction) - Skipping execution");
      return;
   }
   
   // Determine order type
   ENUM_ORDER_TYPE order_type;
   if(policy.action == 1)
   {
      order_type = ORDER_TYPE_BUY;
      Print("📈 Executing BUY policy");
   }
   else if(policy.action == 2)
   {
      order_type = ORDER_TYPE_SELL;
      Print("📉 Executing SELL policy");
   }
   else
   {
      Print("❌ Unknown action: ", policy.action);
      return;
   }
   
   // Calculate position size
   double lot_size = policy.position_size;
   if(lot_size <= 0.0)
   {
      // Use Risk Guardian's safe calculation
      lot_size = g_risk_guardian.CalculateSafeLotSize(
         policy.symbol, 
         policy.entry_price, 
         policy.stop_loss
      );
      Print("   Calculated safe lot size: ", DoubleToString(lot_size, 2));
   }
   
   // Validate with Risk Guardian
   if(!g_risk_guardian.ValidateNewTrade(
      policy.symbol,
      policy.entry_price, 
      policy.stop_loss, 
      lot_size))  // lot_size passed by reference (can be modified)
   {
      Print("🛑 Risk Guardian REJECTED - Risk too high");
      SendFeedback(false, 0, 0.0, "Risk rejected");
      return;
   }
   
   Print("   Validated lot size: ", DoubleToString(lot_size, 2));
   
   // Execute via Council (uses Grid strategy if applicable)
   Print("🎯 Sending to Council for execution...");
   g_council.ExecuteTradeWithGrid(order_type);
   
   g_trades_executed++;
   
   // Send feedback to Python
   SendFeedback(true, 0, 0.0, "Executed by Council");
   
   Print("✅ Policy executed successfully");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

// ========== SEND FEEDBACK TO PYTHON ==========
//+------------------------------------------------------------------+
//| Send feedback to Python Brain (12 fields format)                  |
//+------------------------------------------------------------------+
void SendFeedback(bool success, long ticket, double profit, string message)
{
   // Get position details if ticket exists
   string symbol = "UNKNOWN";
   int type = -1;
   double volume = 0.0;
   double open_price = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   long magic = 0;
   string comment = message;
   
   if(ticket > 0 && PositionSelectByTicket(ticket))
   {
      symbol = PositionGetString(POSITION_SYMBOL);
      type = (int)PositionGetInteger(POSITION_TYPE);
      volume = PositionGetDouble(POSITION_VOLUME);
      open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      magic = PositionGetInteger(POSITION_MAGIC);
      comment = PositionGetString(POSITION_COMMENT);
      if(comment == "") comment = message;
   }
   
   Print("📨 Sending feedback to Python: ", 
         (success ? "SUCCESS" : "FAILED"), 
         " Ticket: #", ticket,
         " Symbol: ", symbol,
         " Type: ", (type == 0 ? "BUY" : (type == 1 ? "SELL" : "UNKNOWN")),
         " Profit: ", DoubleToString(profit, 2));
   
   // Create MessagePack serializer
   CMsgPack msgpack;
   
   // ✅ FIXED: Pack 12 fields as Brain expects (was 5 fields before)
   msgpack.PackArray(12);
   msgpack.PackInt(100);                              // [0] msg_type: 100 (TRADE_RESULT)
   msgpack.PackDouble(TimeCurrent() * 1000.0);        // [1] timestamp (milliseconds as double)
   msgpack.PackDouble((double)ticket);                // [2] ticket (as double - Python converts back to int)
   msgpack.PackString(symbol);                        // [3] symbol
   msgpack.PackInt(type);                             // [4] type (0=BUY, 1=SELL)
   msgpack.PackDouble(volume);                        // [5] volume
   msgpack.PackDouble(open_price);                    // [6] open_price
   msgpack.PackDouble(sl);                            // [7] sl
   msgpack.PackDouble(tp);                            // [8] tp
   msgpack.PackDouble(profit);                        // [9] profit
   msgpack.PackInt((int)magic);                       // [10] magic (cast to int)
   msgpack.PackString(comment);                       // [11] comment
   
   // Get binary data
   uchar feedback_data[];
   msgpack.GetData(feedback_data);
   
   // Send via ZMQ PUB (only in legacy mode)
   if(!g_v6_mode_active)
   {
      int sent = g_pub_socket.send_bin(feedback_data, true);
      if(sent > 0)
      {
         Print("✅ Feedback sent (", sent, " bytes) - 12 fields format");
      }
      else
      {
         Print("⚠️  Failed to send feedback");
      }
   }
}

// ========== ON TICK (Backup) ==========
void OnTick()
{
   // Council already handles tick logic in OnTimer
   // This is just a backup
}

//+------------------------------------------------------------------+
