//+------------------------------------------------------------------+
//|                                        SlippageController.mqh    |
//|                                  Grid Standalone Strategy V2     |
//|                    NEW! Adaptive Slippage with Learning           |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Slippage Record Structure                                         |
//+------------------------------------------------------------------+
struct SlippageRecord
{
   double   requested_price;
   double   executed_price;
   double   slippage;           // In points
   datetime time;
   bool     success;
};

//+------------------------------------------------------------------+
//| Adaptive Slippage Controller                                      |
//+------------------------------------------------------------------+
class CSlippageController
{
private:
   // Configuration
   string   m_symbol;
   double   m_base_slippage;            // Base slippage (pips)
   double   m_min_slippage;             // Min limit (pips)
   double   m_max_slippage;             // Max limit (pips)
   bool     m_use_adaptive;             // Use adaptive mode
   
   // ATR-based adjustment
   int      m_atr_handle;
   double   m_current_atr;
   double   m_avg_atr;
   int      m_atr_period;
   
   // Recent slippage tracking
   SlippageRecord m_recent[100];        // Last 100 executions
   int      m_recent_count;
   int      m_recent_index;
   
   // Statistics
   double   m_avg_recent_slippage;
   double   m_max_recent_slippage;
   int      m_total_orders;
   int      m_rejected_orders;          // Orders rejected due to slippage
   
public:
   CSlippageController();
   ~CSlippageController();
   
   // Initialization
   bool     Initialize(string symbol);
   
   // Configuration
   void     SetBaseSlippage(double pips);
   void     SetLimits(double min_pips, double max_pips);
   void     SetUseAdaptive(bool use) { m_use_adaptive = use; }
   
   // Get slippage
   ulong    GetDynamicSlippage();       // Returns deviation in points
   double   GetDynamicSlippagePips() const;   // Returns deviation in pips
   
   // Record execution
   void     RecordSlippage(double requested, double executed, bool success = true);
   
   // Update
   bool     Update();
   
   // Getters
   double   GetBaseSlippage() const { return m_base_slippage; }
   double   GetAverageRecentSlippage() const { return m_avg_recent_slippage; }
   double   GetRejectionRate() const;
   
   // Statistics
   void     PrintStatus() const;
   void     ResetStatistics();
   
private:
   // Calculation methods
   double   CalculateATRAdjustment() const;
   double   GetSessionMultiplier() const;
   double   CalculateAverageRecentSlippage();
   bool     UpdateATR();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSlippageController::CSlippageController() : m_symbol(""),
                                              m_base_slippage(2.0),
                                              m_min_slippage(1.0),
                                              m_max_slippage(5.0),
                                              m_use_adaptive(true),
                                              m_atr_handle(INVALID_HANDLE),
                                              m_current_atr(0.0),
                                              m_avg_atr(0.0),
                                              m_atr_period(14),
                                              m_recent_count(0),
                                              m_recent_index(0),
                                              m_avg_recent_slippage(0.0),
                                              m_max_recent_slippage(0.0),
                                              m_total_orders(0),
                                              m_rejected_orders(0)
{
   // Initialize array manually
   for(int i = 0; i < 100; i++)
   {
      m_recent[i].requested_price = 0;
      m_recent[i].executed_price = 0;
      m_recent[i].slippage = 0;
      m_recent[i].time = 0;
      m_recent[i].success = false;
   }
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSlippageController::~CSlippageController()
{
   if(m_atr_handle != INVALID_HANDLE)
      IndicatorRelease(m_atr_handle);
}

//+------------------------------------------------------------------+
//| Initialize slippage controller                                    |
//+------------------------------------------------------------------+
bool CSlippageController::Initialize(string symbol)
{
   m_symbol = symbol;
   
   // Initialize ATR for adaptive mode
   if(m_use_adaptive)
   {
      m_atr_handle = iATR(m_symbol, PERIOD_M15, m_atr_period);
      if(m_atr_handle == INVALID_HANDLE)
      {
         Print("[SlippageCtrl] ⚠️ ATR initialization failed - Using non-adaptive mode");
         m_use_adaptive = false;
      }
      else
      {
         UpdateATR();
      }
   }
   
   Print("[SlippageCtrl] Initialized:");
   Print("  Symbol: ", m_symbol);
   Print("  Base slippage: ", DoubleToString(m_base_slippage, 1), " pips");
   Print("  Limits: ", DoubleToString(m_min_slippage, 1), " - ", 
         DoubleToString(m_max_slippage, 1), " pips");
   Print("  Adaptive mode: ", m_use_adaptive ? "✅ Enabled" : "❌ Disabled");
   
   return true;
}

//+------------------------------------------------------------------+
//| Set base slippage (pips)                                          |
//+------------------------------------------------------------------+
void CSlippageController::SetBaseSlippage(double pips)
{
   if(pips < 0.5) pips = 0.5;
   if(pips > 10.0) pips = 10.0;
   
   m_base_slippage = pips;
   Print("[SlippageCtrl] Base slippage set: ", DoubleToString(pips, 1), " pips");
}

//+------------------------------------------------------------------+
//| Set slippage limits (pips)                                        |
//+------------------------------------------------------------------+
void CSlippageController::SetLimits(double min_pips, double max_pips)
{
   if(min_pips > 0 && min_pips < max_pips)
   {
      m_min_slippage = min_pips;
      m_max_slippage = max_pips;
      
      Print("[SlippageCtrl] Limits set: ", DoubleToString(min_pips, 1), 
            " - ", DoubleToString(max_pips, 1), " pips");
   }
}

//+------------------------------------------------------------------+
//| Update ATR                                                        |
//+------------------------------------------------------------------+
bool CSlippageController::UpdateATR()
{
   if(m_atr_handle == INVALID_HANDLE)
      return false;
   
   double atr[20];
   if(CopyBuffer(m_atr_handle, 0, 0, 20, atr) <= 0)
      return false;
   
   m_current_atr = atr[0];
   
   // Calculate average ATR
   double sum = 0.0;
   for(int i = 0; i < 20; i++)
      sum += atr[i];
   m_avg_atr = sum / 20.0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate ATR adjustment factor                                   |
//+------------------------------------------------------------------+
double CSlippageController::CalculateATRAdjustment() const
{
   if(!m_use_adaptive || m_avg_atr <= 0)
      return 1.0;
   
   // ATR ratio: current / average
   double atr_ratio = m_current_atr / m_avg_atr;
   
   // Adjustment factor: 0.5x to 1.5x based on ATR
   double adjustment = 1.0;
   
   if(atr_ratio > 1.5)
      adjustment = 1.5;      // High volatility → 50% more slippage
   else if(atr_ratio > 1.2)
      adjustment = 1.3;
   else if(atr_ratio < 0.7)
      adjustment = 0.7;      // Low volatility → 30% less slippage
   else if(atr_ratio < 0.9)
      adjustment = 0.9;
   else
      adjustment = 1.0;      // Normal
   
   return adjustment;
}

//+------------------------------------------------------------------+
//| Get session multiplier                                            |
//+------------------------------------------------------------------+
double CSlippageController::GetSessionMultiplier() const
{
   datetime current = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current, dt);
   
   int hour = dt.hour; // GMT hour
   
   // High liquidity = Low slippage tolerance
   if(hour >= 13 && hour < 16)
      return 0.7;  // Overlap session
   
   // Normal liquidity
   if(hour >= 8 && hour < 22)
      return 1.0;
   
   // Low liquidity = Higher slippage tolerance
   return 1.5;
}

//+------------------------------------------------------------------+
//| Calculate average recent slippage                                 |
//+------------------------------------------------------------------+
double CSlippageController::CalculateAverageRecentSlippage()
{
   if(m_recent_count == 0)
      return m_base_slippage;
   
   double sum = 0.0;
   int count = 0;
   
   for(int i = 0; i < m_recent_count; i++)
   {
      if(m_recent[i].success && m_recent[i].time > 0)
      {
         sum += m_recent[i].slippage;
         count++;
      }
   }
   
   if(count == 0)
      return m_base_slippage;
   
   m_avg_recent_slippage = sum / count;
   return m_avg_recent_slippage;
}

//+------------------------------------------------------------------+
//| Get dynamic slippage in points                                    |
//+------------------------------------------------------------------+
ulong CSlippageController::GetDynamicSlippage()
{
   double slippage_pips = GetDynamicSlippagePips();
   
   // Convert pips to points
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double points = slippage_pips * 10 / point; // Rough conversion
   
   return (ulong)MathRound(points);
}

//+------------------------------------------------------------------+
//| Get dynamic slippage in pips                                      |
//+------------------------------------------------------------------+
double CSlippageController::GetDynamicSlippagePips() const
{
   if(!m_use_adaptive)
      return m_base_slippage;
   
   // Start with base
   double slippage = m_base_slippage;
   
   // Apply ATR adjustment
   double atr_adj = CalculateATRAdjustment();
   slippage *= atr_adj;
   
   // Apply session multiplier
   double session_mult = GetSessionMultiplier();
   slippage *= session_mult;
   
   // Check recent slippage
   double avg_recent = CalculateAverageRecentSlippage();
   if(avg_recent > slippage * 1.5)
   {
      // Recent slippage much higher → increase tolerance
      slippage = avg_recent * 1.1;
   }
   
   // Apply limits
   if(slippage < m_min_slippage) slippage = m_min_slippage;
   if(slippage > m_max_slippage) slippage = m_max_slippage;
   
   return slippage;
}

//+------------------------------------------------------------------+
//| Record actual slippage                                            |
//+------------------------------------------------------------------+
void CSlippageController::RecordSlippage(double requested, double executed, bool success = true)
{
   m_total_orders++;
   
   if(!success)
   {
      m_rejected_orders++;
      return;
   }
   
   // Calculate slippage in points
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double slippage = MathAbs(requested - executed) / point;
   
   // Store in circular buffer
   m_recent[m_recent_index].requested_price = requested;
   m_recent[m_recent_index].executed_price = executed;
   m_recent[m_recent_index].slippage = slippage;
   m_recent[m_recent_index].time = TimeCurrent();
   m_recent[m_recent_index].success = success;
   
   // Update max
   if(slippage > m_max_recent_slippage)
      m_max_recent_slippage = slippage;
   
   // Move index
   m_recent_index = (m_recent_index + 1) % 100;
   if(m_recent_count < 100)
      m_recent_count++;
   
   // Log if significant slippage
   if(slippage > GetDynamicSlippagePips() * 1.5)
   {
      Print("[SlippageCtrl] ⚠️ High slippage detected:");
      Print("  Requested: ", DoubleToString(requested, _Digits));
      Print("  Executed: ", DoubleToString(executed, _Digits));
      Print("  Slippage: ", DoubleToString(slippage, 1), " points");
   }
}

//+------------------------------------------------------------------+
//| Update controller                                                 |
//+------------------------------------------------------------------+
bool CSlippageController::Update()
{
   if(m_use_adaptive)
   {
      UpdateATR();
   }
   
   CalculateAverageRecentSlippage();
   
   return true;
}

//+------------------------------------------------------------------+
//| Get rejection rate                                                |
//+------------------------------------------------------------------+
double CSlippageController::GetRejectionRate() const
{
   if(m_total_orders == 0) return 0.0;
   return (double)m_rejected_orders / m_total_orders * 100.0;
}

//+------------------------------------------------------------------+
//| Print status                                                      |
//+------------------------------------------------------------------+
void CSlippageController::PrintStatus() const
{
   Print("═══════════════════════════════════════════");
   Print("SLIPPAGE CONTROLLER STATUS");
   Print("═══════════════════════════════════════════");
   Print("Configuration:");
   Print("  Mode: ", m_use_adaptive ? "Adaptive" : "Fixed");
   Print("  Base: ", DoubleToString(m_base_slippage, 1), " pips");
   Print("  Limits: ", DoubleToString(m_min_slippage, 1), " - ", 
         DoubleToString(m_max_slippage, 1), " pips");
   
   Print("Current:");
   Print("  Dynamic: ", DoubleToString(GetDynamicSlippagePips(), 1), " pips");
   
   if(m_use_adaptive)
   {
      Print("  ATR adjustment: ", DoubleToString(CalculateATRAdjustment(), 2), "x");
      Print("  Session mult: ", DoubleToString(GetSessionMultiplier(), 2), "x");
   }
   
   Print("Statistics:");
   Print("  Avg recent: ", DoubleToString(m_avg_recent_slippage, 1), " points");
   Print("  Max recent: ", DoubleToString(m_max_recent_slippage, 1), " points");
   Print("  Data points: ", m_recent_count);
   Print("  Total orders: ", m_total_orders);
   Print("  Rejected: ", m_rejected_orders, " (", 
         DoubleToString(GetRejectionRate(), 1), "%)");
   Print("═══════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Reset statistics                                                  |
//+------------------------------------------------------------------+
void CSlippageController::ResetStatistics()
{
   m_total_orders = 0;
   m_rejected_orders = 0;
   m_recent_count = 0;
   m_recent_index = 0;
   m_avg_recent_slippage = 0.0;
   m_max_recent_slippage = 0.0;
   
   Print("[SlippageCtrl] Statistics reset");
}
