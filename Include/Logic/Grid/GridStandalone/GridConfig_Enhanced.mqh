//+------------------------------------------------------------------+
//|                                    GridConfig_Enhanced.mqh       |
//|                                  Grid Configuration Base Class    |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Grid Configuration Class (Base)                                   |
//+------------------------------------------------------------------+
class CGridConfig
{
protected:
   // Symbol
   string   m_symbol;
   
   // Grid parameters
   double   m_base_lot;
   double   m_lot_multiplier;
   int      m_grid_max_orders;
   double   m_base_step_points;
   bool     m_use_elastic_step;
   
   // ATR parameters
   int      m_atr_handle;
   int      m_atr_period;
   double   m_atr_multiplier;
   double   m_current_atr;
   double   m_avg_atr;
   
   // Risk parameters
   double   m_initial_balance;
   double   m_minimum_balance;
   double   m_min_balance_percent;
   bool     m_use_percent_stop;
   
   // Cash buffer
   double   m_cash_buffer_percent;
   double   m_max_capital_usage;
   
   // Emergency exit
   double   m_emergency_exit_dd;
   bool     m_emergency_exit_triggered;
   datetime m_emergency_exit_time;
   int      m_emergency_cooldown_sec;
   
   // Market state
   int      m_market_state;
   
   // RSI parameters
   bool     m_use_rsi;
   int      m_rsi_handle;
   int      m_rsi_period;
   double   m_rsi_overbought;
   double   m_rsi_oversold;
   
   // ADX parameters
   bool     m_use_adx;
   int      m_adx_handle;
   int      m_adx_period;
   double   m_adx_threshold;
   
public:
   CGridConfig();
   ~CGridConfig();
   
   virtual bool Initialize(string symbol);
   
   // Getters
   string   GetSymbol() { return m_symbol; }
   double   GetBaseLot() { return m_base_lot; }
   double   GetCurrentATR() { return m_current_atr; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridConfig::CGridConfig() : m_symbol(""),
                              m_base_lot(0.01),
                              m_lot_multiplier(1.0),
                              m_grid_max_orders(10),
                              m_base_step_points(100),
                              m_use_elastic_step(true),
                              m_atr_handle(INVALID_HANDLE),
                              m_atr_period(14),
                              m_atr_multiplier(2.0),
                              m_current_atr(0),
                              m_avg_atr(0),
                              m_initial_balance(0),
                              m_minimum_balance(100),
                              m_min_balance_percent(1.0),
                              m_use_percent_stop(false),
                              m_cash_buffer_percent(30.0),
                              m_max_capital_usage(70.0),
                              m_emergency_exit_dd(20.0),
                              m_emergency_exit_triggered(false),
                              m_emergency_exit_time(0),
                              m_emergency_cooldown_sec(300),
                              m_market_state(0),
                              m_use_rsi(true),
                              m_rsi_handle(INVALID_HANDLE),
                              m_rsi_period(14),
                              m_rsi_overbought(70.0),
                              m_rsi_oversold(30.0),
                              m_use_adx(true),
                              m_adx_handle(INVALID_HANDLE),
                              m_adx_period(14),
                              m_adx_threshold(25.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridConfig::~CGridConfig()
{
   if(m_atr_handle != INVALID_HANDLE)
      IndicatorRelease(m_atr_handle);
   if(m_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(m_rsi_handle);
   if(m_adx_handle != INVALID_HANDLE)
      IndicatorRelease(m_adx_handle);
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CGridConfig::Initialize(string symbol)
{
   m_symbol = symbol;
   m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("[GridConfig] Initialized for ", symbol);
   return true;
}
