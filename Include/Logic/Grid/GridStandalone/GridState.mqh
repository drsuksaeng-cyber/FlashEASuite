//+------------------------------------------------------------------+
//|                                         GridState.mqh            |
//|                                  Grid State Management Class      |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.10"
#property strict

#include "GridConfig_Enhanced.mqh"

// Market state enums
#define MARKET_STATE_RANGING_NORMAL    1
#define MARKET_STATE_TRENDING          2
#define MARKET_STATE_VOLATILE          3

//+------------------------------------------------------------------+
//| Grid State Class                                                  |
//+------------------------------------------------------------------+
class CGridState : public CGridConfig
{
protected:
   // Grid state
   int      m_active_orders;
   double   m_total_exposure;
   double   m_current_profit;
   
public:
   CGridState();
   ~CGridState();
   
   virtual bool Initialize(string symbol);
   
   // State getters
   int      GetActiveOrders() { return m_active_orders; }
   double   GetTotalExposure() { return m_total_exposure; }
   double   GetCurrentProfit() { return m_current_profit; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridState::CGridState() : m_active_orders(0),
                            m_total_exposure(0),
                            m_current_profit(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridState::~CGridState()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CGridState::Initialize(string symbol)
{
   if(!CGridConfig::Initialize(symbol))
      return false;
   
   Print("[GridState] Initialized");
   return true;
}
