//+------------------------------------------------------------------+
//|                                     GridDecision_Enhanced.mqh    |
//|                                  Grid Standalone Strategy V2     |
//|                         Enhanced Decision Logic with Risk Checks  |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

// Project includes
#include "MarketAnalysis_Enhanced.mqh"
#include "GridConfig_Enhanced.mqh"

//+------------------------------------------------------------------+
//| Enhanced Grid Decision Class                                      |
//+------------------------------------------------------------------+
class CGridDecision : public CMarketAnalysis
{
private:
   // Decision parameters
   int      m_min_confirmations;
   double   m_min_confidence;
   
   // Statistics
   int      m_total_decisions;
   int      m_approved_entries;
   int      m_rejected_entries;
   
public:
   CGridDecision();
   ~CGridDecision();
   
   // Initialization
   bool     Initialize(string symbol);
   bool     InitializeIndicators();
   
   // Configuration
   void     SetMinConfirmations(int min) { m_min_confirmations = min; }
   void     SetMinConfidence(double min) { m_min_confidence = min; }
   
   // Decision logic
   bool     ShouldEnterGrid(ENUM_ORDER_TYPE &out_type);
   
   // Risk checks (from GridConfig via MarketAnalysis)
   bool     CheckMinimumBalance();
   bool     CheckCapitalUsage();
   bool     CheckEmergencyState();
   
   // Market analysis (inherited)
   void     UpdateMarketAnalysis();
   
   // Getters
   int      GetTotalDecisions() { return m_total_decisions; }
   int      GetApprovedEntries() { return m_approved_entries; }
   double   GetApprovalRate();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridDecision::CGridDecision() : m_min_confirmations(1),
                                  m_min_confidence(0.5),
                                  m_total_decisions(0),
                                  m_approved_entries(0),
                                  m_rejected_entries(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridDecision::~CGridDecision()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CGridDecision::Initialize(string symbol)
{
   if(!CMarketAnalysis::Initialize(symbol))
      return false;
   
   Print("[GridDecision] Initialized for ", symbol);
   return true;
}

//+------------------------------------------------------------------+
//| Initialize indicators                                             |
//+------------------------------------------------------------------+
bool CGridDecision::InitializeIndicators()
{
   bool success = true;
   
   // Initialize RSI
   if(!InitializeRSI())
   {
      Print("[GridDecision] ⚠️ RSI initialization failed - will use fallback");
      success = false;
   }
   
   // Initialize ADX
   if(!InitializeADX())
   {
      Print("[GridDecision] ⚠️ ADX initialization failed - will use fallback");
      success = false;
   }
   
   return true; // Continue even if some indicators fail
}

//+------------------------------------------------------------------+
//| Check minimum balance                                             |
//+------------------------------------------------------------------+
bool CGridDecision::CheckMinimumBalance()
{
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double min_balance = m_use_percent_stop ?
                        m_initial_balance * m_min_balance_percent / 100.0 :
                        m_minimum_balance;
   
   if(current_balance < min_balance || current_equity < min_balance)
   {
      Print("[GridDecision] ❌ Below minimum balance!");
      Print("  Current Balance: $", DoubleToString(current_balance, 2));
      Print("  Current Equity: $", DoubleToString(current_equity, 2));
      Print("  Minimum Required: $", DoubleToString(min_balance, 2));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check capital usage                                               |
//+------------------------------------------------------------------+
bool CGridDecision::CheckCapitalUsage()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
   
   double usage_percent = (used_margin / balance) * 100.0;
   
   if(usage_percent > m_max_capital_usage)
   {
      Print("[GridDecision] ❌ Capital usage limit reached!");
      Print("  Usage: ", DoubleToString(usage_percent, 1), "%");
      Print("  Limit: ", DoubleToString(m_max_capital_usage, 1), "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check emergency state                                             |
//+------------------------------------------------------------------+
bool CGridDecision::CheckEmergencyState()
{
   if(!m_emergency_exit_triggered)
      return true;
   
   // Check cooldown
   datetime now = TimeCurrent();
   int remaining = (int)(m_emergency_cooldown_sec - (now - m_emergency_exit_time));
   
   if(remaining > 0)
   {
      Print("[GridDecision] ❌ Emergency cooldown active!");
      Print("  Remaining: ", remaining, " seconds");
      return false;
   }
   
   // Cooldown expired
   m_emergency_exit_triggered = false;
   Print("[GridDecision] ✅ Emergency cooldown expired - Trading resumed");
   
   return true;
}

//+------------------------------------------------------------------+
//| Should enter grid                                                 |
//+------------------------------------------------------------------+
bool CGridDecision::ShouldEnterGrid(ENUM_ORDER_TYPE &out_type)
{
   m_total_decisions++;
   
   // Critical risk checks first
   if(!CheckMinimumBalance())
   {
      m_rejected_entries++;
      return false;
   }
   
   if(!CheckCapitalUsage())
   {
      m_rejected_entries++;
      return false;
   }
   
   if(!CheckEmergencyState())
   {
      m_rejected_entries++;
      return false;
   }
   
   // Market state check
   if(m_market_state != MARKET_STATE_RANGING_NORMAL)
   {
      m_rejected_entries++;
      return false;
   }
   
   // Get signals
   int buy_signals = 0;
   int sell_signals = 0;
   
   // RSI signal
   if(m_use_rsi)
   {
      int rsi_signal = GetRSISignal();
      if(rsi_signal > 0) buy_signals++;
      if(rsi_signal < 0) sell_signals++;
   }
   
   // Price position signal
   int price_signal = GetPricePositionSignal();
   if(price_signal > 0) buy_signals++;
   if(price_signal < 0) sell_signals++;
   
   // Calculate confidence
   int total_signals = buy_signals + sell_signals;
   if(total_signals == 0)
   {
      m_rejected_entries++;
      return false;
   }
   
   double confidence = (double)MathMax(buy_signals, sell_signals) / total_signals;
   
   // Check minimum requirements
   if(total_signals < m_min_confirmations || confidence < m_min_confidence)
   {
      m_rejected_entries++;
      return false;
   }
   
   // Determine direction
   if(buy_signals > sell_signals)
   {
      out_type = ORDER_TYPE_BUY;
      m_approved_entries++;
      return true;
   }
   else if(sell_signals > buy_signals)
   {
      out_type = ORDER_TYPE_SELL;
      m_approved_entries++;
      return true;
   }
   
   m_rejected_entries++;
   return false;
}

//+------------------------------------------------------------------+
//| Get approval rate                                                 |
//+------------------------------------------------------------------+
double CGridDecision::GetApprovalRate()
{
   if(m_total_decisions == 0) return 0;
   return (double)m_approved_entries / m_total_decisions * 100.0;
}
