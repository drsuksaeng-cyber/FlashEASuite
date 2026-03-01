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
   
   // Remove common broker suffixes for matching
   string clean_symbol = policy_symbol;
   StringReplace(clean_symbol, ".tp", "");
   StringReplace(clean_symbol, ".m", "");
   StringReplace(clean_symbol, ".i", "");
   StringReplace(clean_symbol, ".ecn", "");
   
   // Check if symbol is in scanner's tradeable list
   if(!g_scanner.IsSymbolTradeable(policy_symbol) && !g_scanner.IsSymbolTradeable(clean_symbol))
   {
      Print("⚠️  Symbol ", policy.symbol, " not tradeable (not found in scanner)");
      Print("   Run symbol scanner to add this symbol to Market Watch");
      return;
   }
   
   Print("✅ Symbol validated: ", policy.symbol, " is tradeable");
   
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
   // Skip HOLD actions
   if(policy.action == 0)
   {
      Print("⏸️  Action is HOLD - Skipping execution");
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
   
   // ===== NEW: Update Grid state with policy data =====
   CStrategyGrid* grid = g_council.GetGridStrategy();
   if(grid != NULL)
   {
      grid.UpdateFromPolicy(policy);
      Print("✅ Grid state updated with policy data");
   }
   else
   {
      Print("⚠️  Grid strategy not found in Council");
   }
   
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
void SendFeedback(bool success, long ticket, double profit, string message)
{
   Print("📨 Sending feedback to Python: ", 
         (success ? "SUCCESS" : "FAILED"), 
         " Ticket: ", ticket,
         " Profit: ", DoubleToString(profit, 2));
   
   // Create MessagePack serializer
   CMsgPack msgpack;
   
   // Simple feedback format: [type=3, success, ticket, profit, message]
   msgpack.PackArray(5);
   msgpack.PackInt(3);                    // Type 3 = Feedback
   msgpack.PackInt(success ? 1 : 0);      // Success flag
   msgpack.PackInt(ticket);               // Order ticket
   msgpack.PackDouble(profit);            // Profit amount
   msgpack.PackString(message);           // Message
   
   // Get binary data
   uchar feedback_data[];
   msgpack.GetData(feedback_data);
   
   // Send via ZMQ PUB
   int sent = g_pub_socket.send_bin(feedback_data, true);
   if(sent > 0)
   {
      Print("✅ Feedback sent (", sent, " bytes)");
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
