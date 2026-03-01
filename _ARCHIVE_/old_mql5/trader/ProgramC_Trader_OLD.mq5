//+------------------------------------------------------------------+
//|                                            ProgramC_Trader.mq5   |
//|                                      FlashEASuite V2 - Program C |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.03"
#property strict

// --- 1. Include Modules ---
#include <Trade/Trade.mqh>
#include "../Include/Zmq/ZmqHub.mqh"
#include "../Include/Logic/DailyStats.mqh"
#include "../Include/Risk/RiskGuardian.mqh"
#include "../Include/Logic/PolicyManager.mqh"
#include "../Include/Logic/StrategyManager.mqh"
#include "../Include/Logic/Strategy_Spike.mqh"
#include "../Include/Logic/Strategy_Grid.mqh"

// --- 2. Inputs ---
input group "=== ZMQ Configuration ==="
input string InpZmqSubAddress = "tcp://127.0.0.1:7778";
input string InpZmqPushAddress = "tcp://127.0.0.1:7779";

input group "=== Trading Configuration ==="
input int    InpMagicNumber   = 999000;
input double InpUserMaxRisk   = 2.0;

input group "=== Grid Strategy Settings ==="
input int    InpGridMaxOrders  = 5;        // Grid: Maximum Orders
input double InpGridBaseStep   = 200.0;    // Grid: Base Step (points)
input double InpGridLotMult    = 1.5;      // Grid: Lot Multiplier
input double InpGridBaseLot    = 0.01;     // Grid: Base Lot Size
input int    InpGridATRPeriod  = 14;       // Grid: ATR Period
input double InpGridATRRef     = 30.0;     // Grid: Reference ATR Value
input double InpGridSL         = 500.0;    // Grid: Stop Loss (points)
input double InpGridTP         = 300.0;    // Grid: Take Profit (points)

// --- 3. Global Instances ---
CZmqHub           g_zmq;
CPolicyManager    g_policy;
CStrategyManager  g_council;
CDailyStats       g_stats;
CRiskGuardian     g_risk;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== FlashEASuite V2: Trader Starting (Council Mode with Grid) ===");
   
   // 1. Init ZMQ
   if(!g_zmq.Initialize(100, 100))
     {
      Print("❌ Failed to initialize ZMQ");
      return INIT_FAILED;
     }
   
   if(!g_zmq.Subscribe(InpZmqSubAddress, ""))
     {
      Print("❌ Failed to subscribe to ZMQ");
      return INIT_FAILED;
     }
   
   Print("✅ ZMQ initialized: ", InpZmqSubAddress);
   
   // 2. Init Risk & Stats
   if(!g_risk.Initialize(InpUserMaxRisk))
     {
      Print("❌ Failed to initialize Risk Guardian");
      return INIT_FAILED;
     }
   
   g_stats.Initialize(InpMagicNumber);
   Print("✅ Risk Guardian and Stats initialized");
   
   // 3. Init Council & Strategies
   g_council.Initialize();
   
   // Add Spike Hunter
   g_council.AddStrategy(new CStrategySpike());
   Print("✅ Added: Spike Hunter Strategy");
   
   // Add Grid Strategy
   CStrategyGrid* grid = new CStrategyGrid();
   grid.UpdateConfig(InpGridMaxOrders, InpGridBaseStep, InpGridLotMult);
   g_council.AddStrategy(grid);
   Print("✅ Added: Elastic Grid Strategy");
   Print("   → Max Orders: ", InpGridMaxOrders);
   Print("   → Base Step: ", InpGridBaseStep, " points");
   Print("   → Lot Mult: ", InpGridLotMult, "x");
   
   Print("========================================");
   Print("✅ System Ready: Waiting for Brain Policy...");
   Print("========================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== FlashEASuite V2: Trader Shutting Down ===");
   Print("Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Simple approach: Just run council logic
   // Policy updates will be handled by PolicyManager internally
   
   // 1. Council Vote & Execution
   g_council.OnTickLogic();
   
   // 2. Daily Stats
   g_stats.OnTickLogic();
}
//+------------------------------------------------------------------+
