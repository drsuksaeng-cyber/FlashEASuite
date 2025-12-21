//+------------------------------------------------------------------+
//|                               MarketAnalysis_Enhanced.mqh        |
//|                                  Market Analysis Module           |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.10"
#property strict

#include "GridConfig_Enhanced.mqh"

//+------------------------------------------------------------------+
//| Market Analysis Class                                             |
//+------------------------------------------------------------------+
class CMarketAnalysis : public CGridConfig
{
protected:
   // Market data
   double   m_current_price;
   double   m_price_ma;
   double   m_current_rsi;
   double   m_current_adx;
   
public:
   CMarketAnalysis();
   ~CMarketAnalysis();
   
   virtual bool Initialize(string symbol);
   
   // Indicator initialization
   bool     InitializeRSI();
   bool     InitializeADX();
   
   // Configuration
   void     SetRSIPeriod(int period) { m_rsi_period = period; }
   void     SetRSILevels(double overbought, double oversold);
   void     SetADXPeriod(int period) { m_adx_period = period; }
   void     SetADXThreshold(double threshold) { m_adx_threshold = threshold; }
   
   // Market analysis
   void     UpdateMarketAnalysis();
   int      GetRSISignal();
   int      GetPricePositionSignal();
   
   // Getters
   double   GetCurrentRSI() { return m_current_rsi; }
   double   GetCurrentADX() { return m_current_adx; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CMarketAnalysis::CMarketAnalysis() : m_current_price(0),
                                      m_price_ma(0),
                                      m_current_rsi(0),
                                      m_current_adx(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CMarketAnalysis::~CMarketAnalysis()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CMarketAnalysis::Initialize(string symbol)
{
   if(!CGridConfig::Initialize(symbol))
      return false;
   
   Print("[MarketAnalysis] Initialized");
   return true;
}

//+------------------------------------------------------------------+
//| Initialize RSI                                                    |
//+------------------------------------------------------------------+
bool CMarketAnalysis::InitializeRSI()
{
   m_rsi_handle = iRSI(m_symbol, PERIOD_CURRENT, m_rsi_period, PRICE_CLOSE);
   
   if(m_rsi_handle == INVALID_HANDLE)
   {
      Print("[MarketAnalysis] ❌ RSI initialization failed!");
      m_use_rsi = false;
      return false;
   }
   
   m_use_rsi = true;
   Print("[MarketAnalysis] ✅ RSI initialized");
   return true;
}

//+------------------------------------------------------------------+
//| Initialize ADX                                                    |
//+------------------------------------------------------------------+
bool CMarketAnalysis::InitializeADX()
{
   m_adx_handle = iADX(m_symbol, PERIOD_CURRENT, m_adx_period);
   
   if(m_adx_handle == INVALID_HANDLE)
   {
      Print("[MarketAnalysis] ❌ ADX initialization failed!");
      m_use_adx = false;
      return false;
   }
   
   m_use_adx = true;
   Print("[MarketAnalysis] ✅ ADX initialized");
   return true;
}

//+------------------------------------------------------------------+
//| Set RSI levels                                                    |
//+------------------------------------------------------------------+
void CMarketAnalysis::SetRSILevels(double overbought, double oversold)
{
   m_rsi_overbought = overbought;
   m_rsi_oversold = oversold;
}

//+------------------------------------------------------------------+
//| Update market analysis                                            |
//+------------------------------------------------------------------+
void CMarketAnalysis::UpdateMarketAnalysis()
{
   // Update current price
   MqlTick tick;
   if(SymbolInfoTick(m_symbol, tick))
   {
      m_current_price = (tick.bid + tick.ask) / 2.0;
   }
   
   // Update RSI
   if(m_use_rsi && m_rsi_handle != INVALID_HANDLE)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) > 0)
      {
         m_current_rsi = rsi[0];
      }
   }
   
   // Update ADX
   if(m_use_adx && m_adx_handle != INVALID_HANDLE)
   {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(m_adx_handle, 0, 0, 1, adx) > 0)
      {
         m_current_adx = adx[0];
      }
   }
   
   // Determine market state
   if(m_current_adx < 20.0)
      m_market_state = MARKET_STATE_RANGING_NORMAL;
   else if(m_current_adx < 40.0)
      m_market_state = MARKET_STATE_TRENDING;
   else
      m_market_state = MARKET_STATE_VOLATILE;
}

//+------------------------------------------------------------------+
//| Get RSI signal                                                    |
//+------------------------------------------------------------------+
int CMarketAnalysis::GetRSISignal()
{
   if(!m_use_rsi) return 0;
   
   if(m_current_rsi < m_rsi_oversold)
      return 1;  // Buy signal
   
   if(m_current_rsi > m_rsi_overbought)
      return -1; // Sell signal
   
   return 0;  // No signal
}

//+------------------------------------------------------------------+
//| Get price position signal                                         |
//+------------------------------------------------------------------+
int CMarketAnalysis::GetPricePositionSignal()
{
   // Simple price position check
   // You can enhance this with more sophisticated logic
   
   if(m_current_price < m_price_ma * 0.99)
      return 1;  // Below MA - Buy
   
   if(m_current_price > m_price_ma * 1.01)
      return -1; // Above MA - Sell
   
   return 0;  // Neutral
}
