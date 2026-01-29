//+------------------------------------------------------------------+
//|                                          ProgramC_Trader.mq5     |
//|                            FlashEASuite V2 - Program C Trader    |
//|                            V2.11 - Connected to Python Brain     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.11"
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

// ========== INPUT PARAMETERS ==========
//+------------------------------------------------------------------+
//| Symbol Formatting (Broker-specific)                              |
//+------------------------------------------------------------------+
input string   SYMBOL_PREFIX = "";           // Symbol Prefix (e.g., "f" for FXPro, empty for most)
input string   SYMBOL_SUFFIX = "";           // Symbol Suffix (e.g., ".tp", "m", "_i", empty for ICMarkets)

// ========== GLOBAL VARIABLES ==========
// ZMQ Components
CZmqHub g_zmq_hub;              // Handles SUB socket (receive policies)
Context g_pub_context;          // Separate context for PUB socket
Socket  g_pub_socket(ZMQ_PUB);  // Send feedback to Python (port 7779)

// Strategy & Risk Components
CStrategyManager    g_council;
CRiskGuardian       g_risk_guardian;
CSymbolScanner      g_scanner;  // Multi-symbol scanner
// Note: PositionSizingManager and DailyLossLimit are managed by RiskGuardian

// Operational State
bool g_is_connected = false;
int  g_policies_received = 0;
int  g_trades_executed = 0;
datetime g_last_policy_time = 0;

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
   Print("║  ProgramC_Trader V2.11 - Initializing...     ║");
   Print("╚════════════════════════════════════════════════╝");
   
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
   
   // Add Grid Strategy
   CStrategyGrid* grid = new CStrategyGrid();
   g_council.AddStrategy(grid);
   Print("✅ Grid Strategy added to Council");
   
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
   g_zmq_hub.Shutdown();
   g_pub_socket.close();
   g_pub_context.shutdown();
   
   Print("✅ Shutdown complete");
}

// ========== TIMER EVENT (Main Loop) ==========
void OnTimer()
{
   g_timer_calls++;
   
   // DEBUG: Log every 100 timer calls (every 10 seconds at 100ms interval)
   if(g_timer_calls % 100 == 0)
   {
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Print("🔍 DEBUG STATUS (every 10 seconds)");
      Print("   Timer calls: ", g_timer_calls);
      Print("   Poll attempts: ", g_poll_attempts);
      Print("   Poll success: ", g_poll_success);
      Print("   Poll failures: ", g_poll_failures);
      Print("   Policies received: ", g_policies_received);
      Print("   Success rate: ", g_poll_attempts > 0 ? DoubleToString(100.0 * g_poll_success / g_poll_attempts, 2) : "0.00", "%");
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   }
   
   // Periodic symbol scanner rescan (every 5 minutes)
   if(TimeCurrent() - g_last_scan_time >= g_scan_interval)
   {
      Print("🔍 Rescanning symbols...");
      g_scanner.ScanMarketWatch();
      g_last_scan_time = TimeCurrent();
   }
   
   // Check for incoming policies from Python Brain
   CheckForPolicies();
   
   // Also let Council do its own tick analysis (backup/standalone mode)
   g_council.OnTickLogic();
}

// ========== CHECK FOR POLICIES FROM PYTHON ==========
void CheckForPolicies()
{
   g_poll_attempts++;
   
   // Try to receive message using ZmqHub (non-blocking)
   uchar recv_data[];
   
   // DEBUG: Log first 10 poll attempts
   if(g_poll_attempts <= 10)
   {
      Print("🔍 DEBUG: Poll attempt #", g_poll_attempts, " calling g_zmq_hub.Poll()...");
   }
   
   if(!g_zmq_hub.Poll(recv_data))
   {
      g_poll_failures++;
      
      // DEBUG: Log first 5 failures
      if(g_poll_failures <= 5)
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
   
   // Skip HOLD actions (AFTER updating Grid)
   if(policy.action == 0)
   {
      Print("⏸️  Action is HOLD - Skipping execution (Grid already updated)");
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
   
   // Send via ZMQ PUB
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

// ========== ON TICK (Backup) ==========
void OnTick()
{
   // Council already handles tick logic in OnTimer
   // This is just a backup
}

//+------------------------------------------------------------------+
