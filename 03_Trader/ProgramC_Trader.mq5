//+------------------------------------------------------------------+
//|                                            ProgramC_Trader.mq5   |
//|                                SKN V 2.10 - Risk Enhanced 251225 13:30 |
//+------------------------------------------------------------------+
#property copyright "SKN V 2.10"
#property version   "2.10"
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

// --- NEW: Risk Management Modules ---
#include "../Include/Risk/PositionSizingManager.mqh"
#include "../Include/Risk/DailyLossLimit.mqh"

// --- 2. Inputs ---
input group "=== ZMQ Configuration ==="
input string InpZmqSubAddress = "tcp://127.0.0.1:7778";
input string InpZmqPushAddress = "tcp://127.0.0.1:7779";

input group "=== Trading Configuration ==="
input int    InpMagicNumber   = 999000;
input double InpUserMaxRisk   = 2.0;

input group "=== NEW: Advanced Risk Management ==="
input bool   InpUseRiskBasedLots = true;      // Use Risk-Based Position Sizing
input double InpRiskPerTrade     = 1.0;       // Risk per trade (%)
input double InpDailyLossLimit   = 4.0;       // Daily loss limit (%)

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

// --- NEW: Risk Management Instances ---
CPositionSizingManager g_position_sizer;
CDailyLossLimit        g_daily_limiter;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("  SKN V 2.10 - Risk Enhanced");
   Print("  25 December 2025, 13:30");
   Print("========================================");
   
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
   
   // 2. Init Risk Guardian (existing)
   if(!g_risk.Initialize(InpUserMaxRisk))
     {
      Print("❌ Failed to initialize Risk Guardian");
      return INIT_FAILED;
     }
   Print("✅ Risk Guardian initialized (", InpUserMaxRisk, "%)");
   
   // 3. NEW: Init Position Sizing Manager
   if(!g_position_sizer.Initialize(_Symbol, InpRiskPerTrade))
     {
      Print("❌ Failed to initialize Position Sizing Manager");
      return INIT_FAILED;
     }
   Print("✅ Position Sizing Manager initialized");
   Print("   → Default Risk: ", InpRiskPerTrade, "%");
   Print("   → Risk-Based Lots: ", (InpUseRiskBasedLots ? "ENABLED" : "DISABLED"));
   
   // 4. NEW: Init Daily Loss Limit
   if(!g_daily_limiter.Initialize(InpDailyLossLimit))
     {
      Print("❌ Failed to initialize Daily Loss Limit");
      return INIT_FAILED;
     }
   Print("✅ Daily Loss Limit initialized");
   Print("   → Limit: ", InpDailyLossLimit, "%");
   Print("   → Max Loss: $", DoubleToString(g_daily_limiter.GetDailyLimitRemaining(), 2));
   
   // 5. Init Stats
   g_stats.Initialize(InpMagicNumber);
   Print("✅ Daily Stats initialized");
   
   // 6. Init Council & Strategies
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
   Print("========================================");
   Print("  SKN V 2.10 - Shutting Down");
   Print("========================================");
   
   // Print final daily summary
   Print("📊 Daily Summary:");
   Print("   Daily P&L: $", DoubleToString(g_daily_limiter.GetDailyPnL(), 2));
   Print("   Trades: ", g_daily_limiter.GetDailyTradesCount());
   Print("   Wins: ", g_daily_limiter.GetDailyWinsCount());
   Print("   Losses: ", g_daily_limiter.GetDailyLossesCount());
   
   double win_rate = 0.0;
   if(g_daily_limiter.GetDailyTradesCount() > 0)
   {
      win_rate = (g_daily_limiter.GetDailyWinsCount() * 100.0) / g_daily_limiter.GetDailyTradesCount();
   }
   Print("   Win Rate: ", DoubleToString(win_rate, 1), "%");
   
   if(g_daily_limiter.IsLimitReached())
   {
      Print("   Status: ⚠️ LIMIT REACHED");
   }
   else
   {
      Print("   Status: ✅ OK");
   }
   
   Print("========================================");
   Print("Shutdown Reason: ", reason);
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Check Daily Loss Limit FIRST
   if(g_daily_limiter.IsLimitReached())
   {
      // Don't open new trades, but let council manage existing positions
      static datetime last_warning = 0;
      if(TimeCurrent() - last_warning > 300)  // Warn every 5 minutes
      {
         Print("⚠️ Daily Loss Limit Reached - No new trades");
         Print("   Daily P&L: $", DoubleToString(g_daily_limiter.GetDailyPnL(), 2));
         last_warning = TimeCurrent();
      }
      
      // Still allow council to manage existing positions
      g_council.OnTickLogic();
      g_stats.OnTickLogic();
      return;
   }
   
   // 2. Council Vote & Execution
   g_council.OnTickLogic();
   
   // 3. Daily Stats
   g_stats.OnTickLogic();
   
   // 4. Update Daily Limiter with closed positions
   UpdateDailyLimiter();
}

//+------------------------------------------------------------------+
//| Update Daily Limiter with closed positions                       |
//+------------------------------------------------------------------+
void UpdateDailyLimiter()
{
   static datetime last_check = 0;
   
   // Check every second
   if(TimeCurrent() - last_check < 1) return;
   last_check = TimeCurrent();
   
   // Check history for closed positions
   HistorySelect(TimeCurrent() - 60, TimeCurrent());
   
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      // Check magic number
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      
      // Only count exit deals
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      // Get P&L
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      
      double total_pnl = profit + swap + commission;
      bool is_win = (total_pnl > 0);
      
      // Update daily limiter
      g_daily_limiter.UpdateTrade(total_pnl, is_win);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size with risk management                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double sl, double risk_percent)
{
   // If risk-based lots disabled, use base lot
   if(!InpUseRiskBasedLots)
   {
      return InpGridBaseLot;
   }
   
   // Use Position Sizing Manager
   double lot = g_position_sizer.CalculateLotSize(entry, sl, risk_percent);
   
   return lot;
}

//+------------------------------------------------------------------+
//| Get risk-based lot size (for StrategyManager compatibility)      |
//+------------------------------------------------------------------+
double GetRiskBasedLotSize(double entry, double sl, double risk_percent)
{
   return CalculateLotSize(entry, sl, risk_percent);
}

//+------------------------------------------------------------------+
//| Check if can open new trade (Daily Limit check)                  |
//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
   // Check daily loss limit
   if(g_daily_limiter.IsLimitReached())
   {
      return false;
   }
   
   // Add other checks here if needed
   
   return true;
}
//+------------------------------------------------------------------+
