//+------------------------------------------------------------------+
//|                                 ProgramC_Trader_TEST_ORDERS.mq5  |
//|                      FlashEASuite V2 - Order Execution Test      |
//|                                     Version: 1.0                 |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

// ========== TEST MODE CONFIGURATION ==========
input bool     TEST_MODE = true;              // Enable test mode with extra logging
input double   TEST_LOT_SIZE = 0.01;          // Fixed small lot size for testing
input bool     AUTO_CLOSE_AFTER_SECONDS = true; // Auto-close orders after X seconds
input int      CLOSE_AFTER_SECONDS = 300;     // Close orders after 5 minutes (300 sec)

// ========== INCLUDES ==========
// NOTE: File is in Tester/ subfolder, so use ../ to go up one level
#include "../Include/MqlMsgPack.mqh"
#include "../Include/Zmq/ZmqHub.mqh"
#include "../Include/Zmq/Zmq.mqh"
#include "../Include/Network/Protocol.mqh"
#include "../Include/Logic/StrategyManager.mqh"
#include "../Include/Risk/RiskGuardian.mqh"
#include "../Include/Utils/SymbolScanner.mqh"

// ========== INPUT PARAMETERS ==========
input string   SYMBOL_PREFIX = "";
input string   SYMBOL_SUFFIX = "";

// ========== GLOBAL VARIABLES ==========
CZmqHub g_zmq_hub;
Context g_pub_context;
Socket  g_pub_socket(ZMQ_PUSH);  // ✅ FIXED: Changed from ZMQ_PUB to ZMQ_PUSH for PUSH-PULL pattern

CStrategyManager    g_council;
CRiskGuardian       g_risk_guardian;
CSymbolScanner      g_scanner;

bool g_is_connected = false;
int  g_policies_received = 0;
int  g_orders_executed = 0;
int  g_orders_closed = 0;
datetime g_last_policy_time = 0;

// TEST MODE: Track orders
struct TestOrder {
   long ticket;
   datetime open_time;
   string symbol;
   int type;
   double lots;
   bool auto_closed;
};
TestOrder g_test_orders[];

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(TEST_MODE)
   {
      Print("╔════════════════════════════════════════════════╗");
      Print("║     🧪 ORDER EXECUTION TEST MODE 🧪          ║");
      Print("╚════════════════════════════════════════════════╝");
      Print("⚠️  TEST CONFIGURATION:");
      Print("   • Lot Size: ", TEST_LOT_SIZE);
      Print("   • Auto-close: ", AUTO_CLOSE_AFTER_SECONDS ? "YES" : "NO");
      if(AUTO_CLOSE_AFTER_SECONDS)
         Print("   • Close After: ", CLOSE_AFTER_SECONDS, " seconds");
      Print("");
   }
   
   Print("╔════════════════════════════════════════════════╗");
   Print("║  ProgramC_Trader - Initializing...           ║");
   Print("╚════════════════════════════════════════════════╝");
   
   // 1. Initialize ZMQ Hub
   if(!g_zmq_hub.Initialize(0, 0))
   {
      Print("❌ FAILED: ZMQ Hub initialization");
      return INIT_FAILED;
   }
   Print("✅ ZMQ Hub created");
   
   // 2. Subscribe to Python Brain policies (port 7778)
   if(!g_zmq_hub.Subscribe("tcp://127.0.0.1:7778", ""))
   {
      Print("❌ FAILED: Subscribe to tcp://127.0.0.1:7778");
      return INIT_FAILED;
   }
   Print("✅ Subscribed to tcp://127.0.0.1:7778");
   
   // 3. Initialize PUSH socket for feedback (port 7779)
   // ✅ FIXED: Using PUSH socket instead of PUB for PUSH-PULL pattern
   if(!g_pub_context.initialize())
   {
      Print("❌ FAILED: PUSH Context initialization");
      return INIT_FAILED;
   }
   
   if(!g_pub_socket.initialize(g_pub_context, ZMQ_PUSH))  // ✅ FIXED: ZMQ_PUSH instead of ZMQ_PUB
   {
      Print("❌ FAILED: PUSH Socket initialization");
      return INIT_FAILED;
   }
   
   if(!g_pub_socket.connect("tcp://127.0.0.1:7779"))
   {
      Print("❌ FAILED: Connect to tcp://127.0.0.1:7779");
      return INIT_FAILED;
   }
   
   g_pub_socket.setLinger(0);
   Print("✅ PUSH Socket connected to tcp://127.0.0.1:7779 (PUSH-PULL pattern)");
   
   // 4. Initialize Risk Management (more permissive for testing)
   if(!g_risk_guardian.Initialize(20, 5.0, 20.0, 5.0))  // More permissive for testing
   {
      Print("❌ FAILED: Risk Guardian initialization");
      return INIT_FAILED;
   }
   Print("✅ Risk Guardian initialized (TEST MODE: More permissive)");
   
   // 5. Initialize Council
   g_council.Initialize();
   
   // 6. Initialize Symbol Scanner
   g_scanner.SetMaxSpreadPercent(0.15);
   g_scanner.SetMinVolatility(0.0001);
   g_scanner.SetForexOnly(false);  // Allow all symbols for testing
   
   Print("🔍 Scanning Market Watch...");
   if(g_scanner.ScanMarketWatch())
   {
      Print("✅ Symbol Scanner: ", g_scanner.GetSymbolCount(), " symbols found");
   }
   
   // 7. Start Timer
   EventSetMillisecondTimer(100);
   
   g_is_connected = true;
   
   Print("╔════════════════════════════════════════════════╗");
   Print("║  ✅ SYSTEM READY - Waiting for Policies      ║");
   Print("╚════════════════════════════════════════════════╝");
   if(TEST_MODE)
   {
      Print("");
      Print("🧪 TEST MODE ACTIVE:");
      Print("   📊 Will log all order execution details");
      Print("   📨 Will send feedback to Python via PUSH-PULL pattern");
      Print("   ⏰ Will auto-close orders after ", CLOSE_AFTER_SECONDS, " seconds");
      Print("");
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("🛑 ProgramC_Trader shutting down...");
   Print("   Policies received: ", g_policies_received);
   Print("   Orders executed: ", g_orders_executed);
   Print("   Orders closed: ", g_orders_closed);
   
   // Close all test orders
   if(TEST_MODE && AUTO_CLOSE_AFTER_SECONDS)
   {
      Print("🧹 Closing all test orders...");
      for(int i = 0; i < ArraySize(g_test_orders); i++)
      {
         if(g_test_orders[i].ticket > 0 && !g_test_orders[i].auto_closed)
         {
            CloseTestOrder(i);
         }
      }
   }
   
   EventKillTimer();
   g_zmq_hub.Shutdown();
   g_pub_socket.close();
   g_pub_context.shutdown();
   
   Print("✅ Shutdown complete");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckForPolicies();
   
   // Check for orders that need auto-closing
   if(TEST_MODE && AUTO_CLOSE_AFTER_SECONDS)
   {
      CheckAutoCloseOrders();
   }
}

//+------------------------------------------------------------------+
//| Check for policies from Python Brain                             |
//+------------------------------------------------------------------+
void CheckForPolicies()
{
   uchar recv_data[];
   
   if(!g_zmq_hub.Poll(recv_data))
      return;
   
   g_policies_received++;
   g_last_policy_time = TimeCurrent();
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🔥 POLICY RECEIVED #", g_policies_received);
   Print("   Bytes: ", ArraySize(recv_data));
   
   // Deserialize policy
   PolicyMessage policy;
   if(!CProtocol::DeserializePolicyMessage(recv_data, policy))
   {
      Print("❌ Failed to deserialize policy");
      return;
   }
   
   // Display policy details
   Print("📋 POLICY DETAILS:");
   Print("   Symbol: ", policy.symbol);
   Print("   Action: ", policy.action, " (0=HOLD, 1=BUY, 2=SELL)");
   Print("   Confidence: ", DoubleToString(policy.confidence, 2));
   Print("   Entry Price: ", DoubleToString(policy.entry_price, _Digits));
   Print("   Stop Loss: ", DoubleToString(policy.stop_loss, _Digits));
   Print("   Take Profit: ", DoubleToString(policy.take_profit, _Digits));
   
   // Validate symbol
   if(!g_scanner.IsSymbolTradeable(policy.symbol))
   {
      Print("⚠️  Symbol ", policy.symbol, " not tradeable");
      return;
   }
   
   Print("✅ Symbol validated: ", policy.symbol);
   
   // Execute policy
   ExecutePolicy(policy);
}

//+------------------------------------------------------------------+
//| Execute policy from Python                                        |
//+------------------------------------------------------------------+
void ExecutePolicy(PolicyMessage &policy)
{
   // Skip HOLD actions
   if(policy.action == 0)
   {
      Print("⏸️  Action is HOLD - Skipping");
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return;
   }
   
   // Determine order type
   ENUM_ORDER_TYPE order_type;
   string action_name;
   
   if(policy.action == 1)
   {
      order_type = ORDER_TYPE_BUY;
      action_name = "BUY";
      Print("📈 Preparing BUY order");
   }
   else if(policy.action == 2)
   {
      order_type = ORDER_TYPE_SELL;
      action_name = "SELL";
      Print("📉 Preparing SELL order");
   }
   else
   {
      Print("❌ Unknown action: ", policy.action);
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return;
   }
   
   // Use test lot size
   double lot_size = TEST_LOT_SIZE;
   Print("   Lot Size: ", DoubleToString(lot_size, 2), " (TEST MODE)");
   
   // Get current price
   MqlTick tick;
   if(!SymbolInfoTick(policy.symbol, tick))
   {
      Print("❌ Failed to get tick for ", policy.symbol);
      SendFeedback(false, 0, 0.0, "Failed to get tick");
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return;
   }
   
   double price = (order_type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   Print("   Current Price: ", DoubleToString(price, _Digits));
   
   // Calculate SL/TP distances
   double sl_distance = MathAbs(price - policy.stop_loss);
   double tp_distance = MathAbs(policy.take_profit - price);
   Print("   SL Distance: ", DoubleToString(sl_distance, _Digits));
   Print("   TP Distance: ", DoubleToString(tp_distance, _Digits));
   
   // Execute order
   Print("🎯 EXECUTING ORDER...");
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = policy.symbol;
   request.volume = lot_size;
   request.type = order_type;
   request.price = price;
   request.sl = policy.stop_loss;
   request.tp = policy.take_profit;
   request.deviation = 10;
   request.magic = 12345;
   request.comment = "FlashEA_Test";
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      Print("❌ ORDER FAILED!");
      Print("   Error: ", result.retcode, " - ", result.comment);
      SendFeedback(false, 0, 0.0, "Order failed: " + result.comment);
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return;
   }
   
   // Success!
   g_orders_executed++;
   
   Print("✅ ORDER EXECUTED SUCCESSFULLY!");
   Print("   Ticket: #", result.order);
   Print("   Symbol: ", policy.symbol);
   Print("   Type: ", action_name);
   Print("   Volume: ", DoubleToString(lot_size, 2));
   Print("   Price: ", DoubleToString(result.price, _Digits));
   Print("   SL: ", DoubleToString(policy.stop_loss, _Digits));
   Print("   TP: ", DoubleToString(policy.take_profit, _Digits));
   
   // Track order for auto-close
   if(TEST_MODE && AUTO_CLOSE_AFTER_SECONDS)
   {
      int size = ArraySize(g_test_orders);
      ArrayResize(g_test_orders, size + 1);
      
      g_test_orders[size].ticket = result.order;
      g_test_orders[size].open_time = TimeCurrent();
      g_test_orders[size].symbol = policy.symbol;
      g_test_orders[size].type = order_type;
      g_test_orders[size].lots = lot_size;
      g_test_orders[size].auto_closed = false;
      
      Print("⏰ Order tracked for auto-close after ", CLOSE_AFTER_SECONDS, " seconds");
   }
   
   // Send feedback to Python
   SendFeedback(true, result.order, 0.0, "Order executed: " + action_name);
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

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
   
   Print("📨 Sending feedback to Python...");
   Print("   Success: ", (success ? "TRUE" : "FALSE"));
   Print("   Ticket: #", ticket);
   Print("   Symbol: ", symbol);
   Print("   Type: ", (type == 0 ? "BUY" : (type == 1 ? "SELL" : "UNKNOWN")));
   Print("   Volume: ", DoubleToString(volume, 2));
   Print("   Profit: ", DoubleToString(profit, 2));
   Print("   Message: ", message);
   
   CMsgPack msgpack;
   
   // ✅ FIXED: Pack 12 fields as Brain expects
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
   
   uchar feedback_data[];
   msgpack.GetData(feedback_data);
   
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

//+------------------------------------------------------------------+
//| Check and auto-close orders                                       |
//+------------------------------------------------------------------+
void CheckAutoCloseOrders()
{
   datetime now = TimeCurrent();
   
   for(int i = 0; i < ArraySize(g_test_orders); i++)
   {
      if(g_test_orders[i].ticket > 0 && !g_test_orders[i].auto_closed)
      {
         int elapsed = (int)(now - g_test_orders[i].open_time);
         
         if(elapsed >= CLOSE_AFTER_SECONDS)
         {
            Print("⏰ Auto-closing order #", g_test_orders[i].ticket, " (open for ", elapsed, " sec)");
            CloseTestOrder(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close a test order                                                |
//+------------------------------------------------------------------+
void CloseTestOrder(int index)
{
   long ticket = g_test_orders[index].ticket;
   
   if(!PositionSelectByTicket(ticket))
   {
      Print("⚠️  Position #", ticket, " already closed");
      g_test_orders[index].auto_closed = true;
      return;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_test_orders[index].symbol;
   request.volume = g_test_orders[index].lots;
   request.type = (g_test_orders[index].type == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.deviation = 10;
   request.magic = 12345;
   
   MqlTick tick;
   SymbolInfoTick(g_test_orders[index].symbol, tick);
   request.price = (request.type == ORDER_TYPE_SELL) ? tick.bid : tick.ask;
   
   if(OrderSend(request, result))
   {
      g_orders_closed++;
      g_test_orders[index].auto_closed = true;
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      
      Print("✅ Order #", ticket, " closed");
      Print("   Profit: ", DoubleToString(profit, 2));
      
      SendFeedback(true, ticket, profit, "Auto-closed by test");
   }
   else
   {
      Print("❌ Failed to close order #", ticket);
      Print("   Error: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| OnTick function                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   // Backup - main logic in OnTimer
}
//+------------------------------------------------------------------+
