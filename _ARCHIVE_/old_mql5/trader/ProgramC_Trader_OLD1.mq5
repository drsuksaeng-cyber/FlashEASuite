//+------------------------------------------------------------------+
//|                                          ProgramC_Trader.mq5     |
//|                            FlashEASuite V2 - Program C Trader    |
//|                            V2.11 - Connected to Python Brain     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.11"
#property strict

// ========== INCLUDES ==========
// Use LOCAL include to ensure we use the correct fixed version
#include "Include/MqlMsgPack.mqh"      // LOCAL - defines CMsgPack (no BOM!)
#include <Zmq/ZmqHub.mqh>
#include <Zmq/Zmq.mqh>
#include <Network/Protocol.mqh>
#include <Logic/StrategyManager.mqh>
// Note: StrategyManager.mqh includes Strategy_Grid.mqh
#include <Risk/RiskGuardian.mqh>
// Note: RiskGuardian.mqh includes PositionSizingManager.mqh and DailyLossLimit.mqh

// ========== GLOBAL VARIABLES ==========
// ZMQ Components
CZmqHub g_zmq_hub;              // Handles SUB socket (receive policies)
Context g_pub_context;          // Separate context for PUB socket
Socket  g_pub_socket(ZMQ_PUB);  // Send feedback to Python (port 7779)

// Strategy & Risk Components
CStrategyManager    g_council;
CRiskGuardian       g_risk_guardian;
// Note: PositionSizingManager and DailyLossLimit are managed by RiskGuardian

// Operational State
bool g_is_connected = false;
int  g_policies_received = 0;
int  g_trades_executed = 0;
datetime g_last_policy_time = 0;

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
   if(!g_zmq_hub.Subscribe("tcp://127.0.0.1:7778"))
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
   
   // 6. Start Timer (check for policies every 100ms)
   EventSetMillisecondTimer(100);
   
   g_is_connected = true;
   
   Print("╔════════════════════════════════════════════════╗");
   Print("║  ✅ SYSTEM READY - Waiting for Brain Policy  ║");
   Print("╚════════════════════════════════════════════════╝");
   
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
   // Check for incoming policies from Python Brain
   CheckForPolicies();
   
   // Also let Council do its own tick analysis (backup/standalone mode)
   g_council.OnTickLogic();
}

// ========== CHECK FOR POLICIES FROM PYTHON ==========
void CheckForPolicies()
{
   // Try to receive message using ZmqHub (non-blocking)
   uchar recv_data[];
   
   if(!g_zmq_hub.Poll(recv_data))
   {
      // No message available (normal, not an error)
      return;
   }
   
   // We got a message!
   g_policies_received++;
   g_last_policy_time = TimeCurrent();
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🔥 POLICY RECEIVED FROM BRAIN #", g_policies_received);
   Print("   Bytes: ", ArraySize(recv_data));
   
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
   
   // Validate policy matches current symbol
   if(policy.symbol != _Symbol)
   {
      Print("⚠️  Policy symbol mismatch: ", policy.symbol, " != ", _Symbol);
      return;
   }
   
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
