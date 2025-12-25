//+------------------------------------------------------------------+
//|                                      TestRiskManagement.mq5      |
//|                           Test Risk Management WITHOUT Python    |
//|                           Location: Tester/                      |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

// Include modules with CORRECT paths from Tester/
#include <Trade/Trade.mqh>
#include "../Include/Risk/PositionSizingManager.mqh"
#include "../Include/Risk/DailyLossLimit.mqh"

//--- Input parameters
input double InpRiskPerTrade = 1.0;
input double InpDailyLossLimit = 4.0;
input bool   InpUseRiskBasedLots = true;
input int    InpMagicNumber = 888000;

//--- Grid simulation
input int    InpGridMaxLevels = 3;
input double InpGridStepPoints = 100.0;
input int    InpMAFastPeriod = 10;
input int    InpMASlowPeriod = 50;

//--- Global objects
CPositionSizingManager g_sizer;
CDailyLossLimit        g_limiter;
CTrade                 g_trade;

//--- Grid tracking
int    g_active_levels = 0;
double g_last_grid_price = 0;

//--- MA indicators
int    g_ma_fast_handle = INVALID_HANDLE;
int    g_ma_slow_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("  RISK MANAGEMENT TEST EA");
   Print("========================================");
   
   if(!g_sizer.Initialize(_Symbol, InpRiskPerTrade))
   {
      Print("ERROR: Position Sizing Manager failed");
      return INIT_FAILED;
   }
   Print("Position Sizing: OK (", InpRiskPerTrade, "%)");
   
   if(!g_limiter.Initialize(InpDailyLossLimit))
   {
      Print("ERROR: Daily Loss Limit failed");
      return INIT_FAILED;
   }
   Print("Daily Limit: OK (", InpDailyLossLimit, "%)");
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   
   // Initialize MA indicators
   g_ma_fast_handle = iMA(_Symbol, PERIOD_CURRENT, InpMAFastPeriod, 0, MODE_SMA, PRICE_CLOSE);
   g_ma_slow_handle = iMA(_Symbol, PERIOD_CURRENT, InpMASlowPeriod, 0, MODE_SMA, PRICE_CLOSE);
   
   if(g_ma_fast_handle == INVALID_HANDLE || g_ma_slow_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create MA indicators");
      return INIT_FAILED;
   }
   Print("MA Indicators: OK (", InpMAFastPeriod, ", ", InpMASlowPeriod, ")");
   
   string lots_mode = "NO";
   if(InpUseRiskBasedLots)
   {
      lots_mode = "YES";
   }
   Print("Risk-Based Lots: ", lots_mode);
   Print("Test EA Ready!");
   Print("========================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(g_ma_fast_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_fast_handle);
   if(g_ma_slow_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_slow_handle);
   
   Print("========================================");
   Print("TEST EA STOPPED");
   Print("========================================");
   PrintDailySummary();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check daily limit
   if(g_limiter.IsLimitReached())
   {
      return;
   }
   
   // Update grid state
   UpdateGridState();
   
   // Get MA values (MQL5 syntax)
   double ma_fast_buffer[];
   double ma_slow_buffer[];
   ArraySetAsSeries(ma_fast_buffer, true);
   ArraySetAsSeries(ma_slow_buffer, true);
   
   if(CopyBuffer(g_ma_fast_handle, 0, 0, 2, ma_fast_buffer) < 2)
   {
      return; // Not enough data
   }
   if(CopyBuffer(g_ma_slow_handle, 0, 0, 2, ma_slow_buffer) < 2)
   {
      return; // Not enough data
   }
   
   double ma_fast = ma_fast_buffer[0];
   double ma_slow = ma_slow_buffer[0];
   double ma_fast_prev = ma_fast_buffer[1];
   double ma_slow_prev = ma_slow_buffer[1];
   
   // Crossover signals
   bool buy_signal = false;
   bool sell_signal = false;
   
   if(ma_fast_prev <= ma_slow_prev && ma_fast > ma_slow)
   {
      buy_signal = true;
   }
   
   if(ma_fast_prev >= ma_slow_prev && ma_fast < ma_slow)
   {
      sell_signal = true;
   }
   
   // Execute trades
   if(buy_signal || ShouldOpenGridLevel())
   {
      OpenPosition(ORDER_TYPE_BUY);
   }
   else if(sell_signal)
   {
      OpenPosition(ORDER_TYPE_SELL);
   }
   
   // Check closed positions
   CheckClosedPositions();
}

//+------------------------------------------------------------------+
//| Update grid state                                                |
//+------------------------------------------------------------------+
void UpdateGridState()
{
   g_active_levels = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      g_active_levels++;
   }
}

//+------------------------------------------------------------------+
//| Check if should open grid level                                  |
//+------------------------------------------------------------------+
bool ShouldOpenGridLevel()
{
   if(g_active_levels >= InpGridMaxLevels) return false;
   if(g_active_levels == 0) return false;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double distance = MathAbs(price - g_last_grid_price);
   double required = InpGridStepPoints * point;
   
   if(distance >= required)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Open position with risk management                               |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type)
{
   if(g_limiter.IsLimitReached())
   {
      return;
   }
   
   double price = 0;
   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = 0;
   double tp = 0;
   
   if(type == ORDER_TYPE_BUY)
   {
      sl = price - 100 * point;
      tp = price + 200 * point;
   }
   else
   {
      sl = price + 100 * point;
      tp = price - 200 * point;
   }
   
   // Calculate lot size
   double lot = CalculateLotSize(price, sl);
   
   if(lot <= 0)
   {
      return;
   }
   
   // Open position
   bool result = g_trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "Test");
   
   if(result)
   {
      string type_str = "BUY";
      if(type == ORDER_TYPE_SELL)
      {
         type_str = "SELL";
      }
      
      Print("POSITION OPENED: ", type_str);
      Print("  Lot: ", DoubleToString(lot, 2), " (CALCULATED)");
      Print("  Entry: ", DoubleToString(price, 5));
      Print("  SL: ", DoubleToString(sl, 5));
      
      g_last_grid_price = price;
      g_limiter.UpdateTrade(0.0, true);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double sl)
{
   if(!InpUseRiskBasedLots)
   {
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   double lot = g_sizer.CalculateLotSize(entry, sl, InpRiskPerTrade);
   
   return lot;
}

//+------------------------------------------------------------------+
//| Check closed positions                                           |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
   static datetime last_check = 0;
   
   if(TimeCurrent() - last_check < 1) return;
   last_check = TimeCurrent();
   
   HistorySelect(TimeCurrent() - 60, TimeCurrent());
   
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      
      double total_pnl = profit + swap + commission;
      bool is_win = false;
      if(total_pnl > 0)
      {
         is_win = true;
      }
      
      g_limiter.UpdateTrade(total_pnl, is_win);
      
      Print("POSITION CLOSED:");
      Print("  P&L: $", DoubleToString(total_pnl, 2));
      Print("  Daily P&L: $", DoubleToString(g_limiter.GetDailyPnL(), 2));
   }
}

//+------------------------------------------------------------------+
//| Print daily summary                                              |
//+------------------------------------------------------------------+
void PrintDailySummary()
{
   Print("========================================");
   Print("DAILY SUMMARY");
   Print("========================================");
   Print("Daily P&L: $", DoubleToString(g_limiter.GetDailyPnL(), 2));
   Print("Trades: ", g_limiter.GetDailyTradesCount());
   Print("Wins: ", g_limiter.GetDailyWinsCount());
   Print("Losses: ", g_limiter.GetDailyLossesCount());
   
   double win_rate = 0.0;
   if(g_limiter.GetDailyTradesCount() > 0)
   {
      win_rate = (g_limiter.GetDailyWinsCount() * 100.0) / g_limiter.GetDailyTradesCount();
   }
   Print("Win Rate: ", DoubleToString(win_rate, 1), "%");
   
   bool limit_reached = g_limiter.IsLimitReached();
   if(limit_reached)
   {
      Print("Status: LIMIT REACHED");
   }
   else
   {
      Print("Status: OK");
   }
   
   Print("========================================");
}
//+------------------------------------------------------------------+
