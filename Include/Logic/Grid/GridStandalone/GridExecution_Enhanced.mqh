//+------------------------------------------------------------------+
//|                                              GridExecution.mqh   |
//|                                  Grid Standalone Strategy V2     |
//|                                      Enhanced Risk Management    |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

#include "Include/Logic/Grid/GridStandalone/GridState.mqh"

//+------------------------------------------------------------------+
//| Grid Execution Logic (Enhanced with Risk Management)            |
//+------------------------------------------------------------------+
class CGridExecution : public CGridState
{
private:
   // Execution tracking
   double   m_initial_balance;           // Store initial balance for DD calculation
   datetime m_start_time;                // EA start time
   
   // Drawdown tracking
   double   m_peak_balance;              // Peak balance achieved
   double   m_current_drawdown_percent;  // Current DD%
   
   // Order execution
   CTrade   m_trade;                     // Trade object
   
   // Risk management (NEW!)
   double   GetDrawdownPercent();
   double   GetDrawdownLotMultiplier();
   bool     CheckMarginSufficient(string symbol, double lot, ENUM_ORDER_TYPE type);
   double   CalculateRequiredMargin(string symbol, double lot, ENUM_ORDER_TYPE type);
   
public:
   CGridExecution();
   ~CGridExecution();
   
   // Initialization
   bool     Initialize(string symbol);
   
   // Execution methods
   bool     OpenGridLevel(int level, ENUM_ORDER_TYPE order_type);
   bool     CloseGridLevel(int level);
   bool     CloseAllGridOrders();
   bool     ModifyGridOrder(ulong ticket, double new_sl, double new_tp);
   
   // Lot calculation (Enhanced)
   double   CalculateGridLotSize(int level);
   double   NormalizeLot(double lot);
   
   // Get current state
   double   GetCurrentDrawdownPercent() const { return m_current_drawdown_percent; }
   double   GetInitialBalance() const { return m_initial_balance; }
   double   GetPeakBalance() const { return m_peak_balance; }
   
   // Update methods
   void     UpdateDrawdown();
   void     UpdatePeakBalance();
   
   // Hybrid Order Execution (prepared for Week 4)
   enum ENUM_ORDER_MODE {
      ORDER_MODE_MARKET,
      ORDER_MODE_LIMIT,
      ORDER_MODE_STOP,
      ORDER_MODE_HYBRID_AUTO
   };
   
protected:
   ENUM_ORDER_MODE DetermineOrderMode();  // Will implement in Week 4
   bool     ExecuteMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp);
   bool     ExecuteLimitOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp);
   bool     ExecuteStopOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridExecution::CGridExecution() : m_initial_balance(0.0),
                                    m_start_time(0),
                                    m_peak_balance(0.0),
                                    m_current_drawdown_percent(0.0)
{
   m_trade.SetExpertMagicNumber(123456); // Should be configurable
   m_trade.SetDeviationInPoints(20);      // Default, will be enhanced in Week 4
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   m_trade.LogLevel(LOG_LEVEL_ERRORS);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridExecution::~CGridExecution()
{
}

//+------------------------------------------------------------------+
//| Initialize execution module                                       |
//+------------------------------------------------------------------+
bool CGridExecution::Initialize(string symbol)
{
   if(!CGridState::Initialize(symbol))
      return false;
   
   // Store initial balance
   m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_peak_balance = m_initial_balance;
   m_start_time = TimeCurrent();
   
   Print("[Execution] Initialized:");
   Print("  Initial Balance: $", m_initial_balance);
   Print("  Symbol: ", symbol);
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate required margin for order (NEW!)                       |
//+------------------------------------------------------------------+
double CGridExecution::CalculateRequiredMargin(string symbol, double lot, ENUM_ORDER_TYPE type)
{
   double margin = 0.0;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
                                            : SymbolInfoDouble(symbol, SYMBOL_BID);
   
   if(!OrderCalcMargin(type, symbol, lot, price, margin))
   {
      int error = GetLastError();
      Print("[Execution] ❌ Failed to calculate margin: ", error);
      return -1.0;
   }
   
   return margin;
}

//+------------------------------------------------------------------+
//| Check if sufficient margin available (NEW!)                      |
//+------------------------------------------------------------------+
bool CGridExecution::CheckMarginSufficient(string symbol, double lot, ENUM_ORDER_TYPE type)
{
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double required_margin = CalculateRequiredMargin(symbol, lot, type);
   
   if(required_margin < 0)
   {
      Print("[Execution] ❌ Cannot calculate required margin");
      return false;
   }
   
   // Require 150% of calculated margin (50% safety buffer)
   double safety_margin = required_margin * 1.5;
   
   if(free_margin < safety_margin)
   {
      Print("[Execution] ❌ Insufficient margin!");
      Print("  Free Margin: $", DoubleToString(free_margin, 2));
      Print("  Required (with buffer): $", DoubleToString(safety_margin, 2));
      Print("  Shortage: $", DoubleToString(safety_margin - free_margin, 2));
      return false;
   }
   
   Print("[Execution] ✅ Margin check passed:");
   Print("  Free: $", DoubleToString(free_margin, 2));
   Print("  Required: $", DoubleToString(safety_margin, 2));
   Print("  Buffer: ", DoubleToString((free_margin / safety_margin - 1.0) * 100, 1), "%");
   
   return true;
}

//+------------------------------------------------------------------+
//| Get current drawdown percent (NEW!)                              |
//+------------------------------------------------------------------+
double CGridExecution::GetDrawdownPercent()
{
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Use the lower of balance or equity
   double current = MathMin(current_balance, current_equity);
   
   // Calculate DD from peak
   if(m_peak_balance <= 0) m_peak_balance = m_initial_balance;
   
   double dd_from_peak = 0.0;
   if(m_peak_balance > 0)
      dd_from_peak = (m_peak_balance - current) / m_peak_balance * 100.0;
   
   // Calculate DD from initial
   double dd_from_initial = 0.0;
   if(m_initial_balance > 0)
      dd_from_initial = (m_initial_balance - current) / m_initial_balance * 100.0;
   
   // Use the larger DD (more conservative)
   return MathMax(dd_from_peak, dd_from_initial);
}

//+------------------------------------------------------------------+
//| Get drawdown-based lot multiplier (NEW!)                         |
//+------------------------------------------------------------------+
double CGridExecution::GetDrawdownLotMultiplier()
{
   double dd = GetDrawdownPercent();
   double multiplier = 1.0;
   
   // Progressive reduction based on drawdown
   if(dd > 80.0)
      multiplier = 0.1;       // 80%+ DD → 10% lot
   else if(dd > 60.0)
      multiplier = 0.2;       // 60-80% DD → 20% lot
   else if(dd > 40.0)
      multiplier = 0.4;       // 40-60% DD → 40% lot
   else if(dd > 20.0)
      multiplier = 0.7;       // 20-40% DD → 70% lot
   // else multiplier = 1.0   // 0-20% DD → 100% lot
   
   if(dd > 20.0)
   {
      Print("[Risk] Drawdown: ", DoubleToString(dd, 2), "% → Lot multiplier: ", 
            DoubleToString(multiplier, 2), "x");
   }
   
   return multiplier;
}

//+------------------------------------------------------------------+
//| Update drawdown tracking                                          |
//+------------------------------------------------------------------+
void CGridExecution::UpdateDrawdown()
{
   m_current_drawdown_percent = GetDrawdownPercent();
}

//+------------------------------------------------------------------+
//| Update peak balance                                               |
//+------------------------------------------------------------------+
void CGridExecution::UpdatePeakBalance()
{
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(current_balance > m_peak_balance)
   {
      m_peak_balance = current_balance;
      Print("[Risk] 🎉 New peak balance: $", DoubleToString(m_peak_balance, 2));
   }
}

//+------------------------------------------------------------------+
//| Calculate grid lot size (ENHANCED with DD multiplier)            |
//+------------------------------------------------------------------+
double CGridExecution::CalculateGridLotSize(int level)
{
   // Base calculation from GridConfig
   double base_lot = m_base_lot;
   
   // Apply lot progression if configured
   double progression = 1.0;
   if(level > 0 && m_lot_multiplier > 1.0)
   {
      progression = MathPow(m_lot_multiplier, level);
   }
   
   double lot = base_lot * progression;
   
   // Apply risk multiplier (confidence-based, from policy)
   lot = lot * m_risk_multiplier;
   
   // Apply drawdown multiplier (NEW!)
   double dd_multiplier = GetDrawdownLotMultiplier();
   lot = lot * dd_multiplier;
   
   // Normalize to broker requirements
   lot = NormalizeLot(lot);
   
   if(level == 0)
   {
      Print("[Execution] Lot calculation for Level ", level, ":");
      Print("  Base: ", DoubleToString(base_lot, 3));
      Print("  Progression: ", DoubleToString(progression, 3));
      Print("  Risk multiplier: ", DoubleToString(m_risk_multiplier, 2));
      Print("  DD multiplier: ", DoubleToString(dd_multiplier, 2));
      Print("  Final: ", DoubleToString(lot, 3));
   }
   
   return lot;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker requirements                         |
//+------------------------------------------------------------------+
double CGridExecution::NormalizeLot(double lot)
{
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Round to lot step
   lot = MathRound(lot / lot_step) * lot_step;
   
   // Clamp to min/max
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Open grid level (ENHANCED with checks)                           |
//+------------------------------------------------------------------+
bool CGridExecution::OpenGridLevel(int level, ENUM_ORDER_TYPE order_type)
{
   // Calculate lot size
   double lot = CalculateGridLotSize(level);
   
   // CRITICAL CHECK 1: Margin safety (NEW!)
   if(!CheckMarginSufficient(_Symbol, lot, order_type))
   {
      Print("[Execution] ❌ Cannot open Level ", level, ": Insufficient margin");
      return false;
   }
   
   // Calculate entry price
   double entry_price = SymbolInfoDouble(_Symbol, (order_type == ORDER_TYPE_BUY) ? SYMBOL_ASK : SYMBOL_BID);
   
   // Calculate SL/TP
   double sl = 0.0; // Will be managed by grid
   double tp = 0.0;
   
   if(m_elastic_step > 0)
   {
      // TP at next grid level
      double tp_distance = m_elastic_step * _Point;
      if(order_type == ORDER_TYPE_BUY)
         tp = entry_price + tp_distance;
      else
         tp = entry_price - tp_distance;
   }
   
   // Execute order
   bool result = ExecuteMarketOrder(order_type, lot, sl, tp);
   
   if(result)
   {
      Print("[Execution] ✅ Opened Level ", level, ": ", 
            EnumToString(order_type), " ", DoubleToString(lot, 3), " lots @ ", 
            DoubleToString(entry_price, _Digits));
   }
   else
   {
      Print("[Execution] ❌ Failed to open Level ", level, ": ", GetLastError());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Execute market order                                              |
//+------------------------------------------------------------------+
bool CGridExecution::ExecuteMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp)
{
   string type_str = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   
   bool result = false;
   if(type == ORDER_TYPE_BUY)
      result = m_trade.Buy(lot, _Symbol, 0.0, sl, tp, "Grid Level");
   else
      result = m_trade.Sell(lot, _Symbol, 0.0, sl, tp, "Grid Level");
   
   if(!result)
   {
      uint error = GetLastError();
      Print("[Execution] ❌ ", type_str, " order failed: ", error, " - ", m_trade.ResultRetcode());
      
      // Print detailed error info
      if(error == 4756) // TRADE_RETCODE_NO_MONEY
      {
         Print("  Error 4756: Not enough money to execute order");
         Print("  Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
         Print("  Free Margin: $", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Execute limit order (prepared for Week 4)                         |
//+------------------------------------------------------------------+
bool CGridExecution::ExecuteLimitOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
{
   // TODO: Implement in Week 4
   // For now, fall back to market order
   return ExecuteMarketOrder(type, lot, sl, tp);
}

//+------------------------------------------------------------------+
//| Execute stop order (prepared for Week 4)                          |
//+------------------------------------------------------------------+
bool CGridExecution::ExecuteStopOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
{
   // TODO: Implement in Week 4
   // For now, fall back to market order
   return ExecuteMarketOrder(type, lot, sl, tp);
}

//+------------------------------------------------------------------+
//| Determine order mode (prepared for Week 4)                        |
//+------------------------------------------------------------------+
CGridExecution::ENUM_ORDER_MODE CGridExecution::DetermineOrderMode()
{
   // TODO: Implement in Week 4
   // Will use indicators (ATR, ADX) to decide
   // For now, always use market orders
   return ORDER_MODE_MARKET;
}

//+------------------------------------------------------------------+
//| Close grid level                                                  |
//+------------------------------------------------------------------+
bool CGridExecution::CloseGridLevel(int level)
{
   // TODO: Implement proper level closing
   // For now, just placeholder
   return true;
}

//+------------------------------------------------------------------+
//| Close all grid orders                                             |
//+------------------------------------------------------------------+
bool CGridExecution::CloseAllGridOrders()
{
   int total = PositionsTotal();
   int closed = 0;
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               if(m_trade.PositionClose(ticket))
                  closed++;
            }
         }
      }
   }
   
   Print("[Execution] Closed ", closed, " positions");
   return (closed > 0);
}

//+------------------------------------------------------------------+
//| Modify grid order                                                 |
//+------------------------------------------------------------------+
bool CGridExecution::ModifyGridOrder(ulong ticket, double new_sl, double new_tp)
{
   return m_trade.PositionModify(ticket, new_sl, new_tp);
}
