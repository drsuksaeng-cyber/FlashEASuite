//+------------------------------------------------------------------+
//|                                              SpreadFilter.mqh    |
//|                                  Grid Standalone Strategy V2     |
//|                    NEW! Dynamic Spread Filter with Volume Weight  |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Spread Tick Data Structure                                        |
//+------------------------------------------------------------------+
struct SpreadTick
{
   double   spread;        // Spread in points
   long     volume;        // Tick volume
   datetime time;          // Timestamp
};

//+------------------------------------------------------------------+
//| Dynamic Spread Filter - Volume-Weighted + Session-Based          |
//+------------------------------------------------------------------+
class CSpreadFilter
{
private:
   // History tracking
   SpreadTick m_history[3600];           // 1 hour rolling window (1 per second)
   int      m_history_count;             // Current count
   int      m_history_index;             // Current index (circular buffer)
   
   // Configuration
   string   m_symbol;
   double   m_formula_factor;            // Formula factor (default 0.1 = 10%)
   double   m_min_allowed;               // Min spread limit (pips)
   double   m_max_allowed;               // Max spread limit (pips)
   
   // Statistics
   double   m_current_spread;
   double   m_vw_average;                // Volume-weighted average
   double   m_min_spread;
   double   m_max_spread;
   double   m_dynamic_threshold;
   
   // Rejection tracking
   int      m_total_checks;
   int      m_total_rejections;
   datetime m_last_check_time;
   
public:
   CSpreadFilter();
   ~CSpreadFilter();
   
   // Initialization
   bool     Initialize(string symbol);
   
   // Configuration
   void     SetFormulaFactor(double factor) { m_formula_factor = factor; }
   void     SetLimits(double min_pips, double max_pips);
   
   // Update
   void     OnTick();
   void     AddSpread(double spread_points, long volume);
   
   // Calculation
   double   CalculateVolumeWeightedAverage();
   double   CalculateMinSpread();
   double   CalculateMaxSpread();
   double   GetSessionMultiplier() const;
   double   GetDynamicThreshold();
   
   // Check
   bool     IsSpreadAcceptable();
   bool     IsSpreadAcceptable(double spread_points);
   
   // Getters
   double   GetCurrentSpread() const { return m_current_spread; }
   double   GetVWAverage() const { return m_vw_average; }
   double   GetDynamicThreshold() const { return m_dynamic_threshold; }
   double   GetRejectionRate() const;
   
   // Statistics
   void     PrintStatus() const;
   void     ResetStatistics();
   
private:
   // Internal
   void     CleanOldData();
   double   GetCurrentSpreadPoints();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSpreadFilter::CSpreadFilter() : m_history_count(0),
                                  m_history_index(0),
                                  m_symbol(""),
                                  m_formula_factor(0.1),
                                  m_min_allowed(0.5),
                                  m_max_allowed(5.0),
                                  m_current_spread(0.0),
                                  m_vw_average(0.0),
                                  m_min_spread(0.0),
                                  m_max_spread(0.0),
                                  m_dynamic_threshold(0.0),
                                  m_total_checks(0),
                                  m_total_rejections(0),
                                  m_last_check_time(0)
{
   // Initialize array manually
   for(int i = 0; i < 3600; i++)
   {
      m_history[i].spread = 0;
      m_history[i].volume = 0;
      m_history[i].time = 0;
   }
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSpreadFilter::~CSpreadFilter()
{
}

//+------------------------------------------------------------------+
//| Initialize spread filter                                          |
//+------------------------------------------------------------------+
bool CSpreadFilter::Initialize(string symbol)
{
   m_symbol = symbol;
   
   // Set default limits based on symbol
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
   {
      m_min_allowed = 0.5;
      m_max_allowed = 5.0;
   }
   else if(StringFind(symbol, "EUR") >= 0 || StringFind(symbol, "GBP") >= 0)
   {
      m_min_allowed = 0.3;
      m_max_allowed = 2.0;
   }
   else
   {
      m_min_allowed = 0.3;
      m_max_allowed = 3.0;
   }
   
   Print("[SpreadFilter] Initialized for ", m_symbol);
   Print("  Formula factor: ", DoubleToString(m_formula_factor, 2));
   Print("  Min allowed: ", DoubleToString(m_min_allowed, 1), " pips");
   Print("  Max allowed: ", DoubleToString(m_max_allowed, 1), " pips");
   
   return true;
}

//+------------------------------------------------------------------+
//| Set spread limits (pips)                                          |
//+------------------------------------------------------------------+
void CSpreadFilter::SetLimits(double min_pips, double max_pips)
{
   if(min_pips > 0) m_min_allowed = min_pips;
   if(max_pips > min_pips) m_max_allowed = max_pips;
   
   Print("[SpreadFilter] Limits set: ", DoubleToString(m_min_allowed, 1), 
         " - ", DoubleToString(m_max_allowed, 1), " pips");
}

//+------------------------------------------------------------------+
//| Get current spread in points                                      |
//+------------------------------------------------------------------+
double CSpreadFilter::GetCurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   return spread;
}

//+------------------------------------------------------------------+
//| Update on tick                                                    |
//+------------------------------------------------------------------+
void CSpreadFilter::OnTick()
{
   double spread = GetCurrentSpreadPoints();
   long volume = (long)SymbolInfoInteger(m_symbol, SYMBOL_VOLUME);
   
   AddSpread(spread, volume);
   
   m_current_spread = spread;
}

//+------------------------------------------------------------------+
//| Add spread data point                                             |
//+------------------------------------------------------------------+
void CSpreadFilter::AddSpread(double spread_points, long volume)
{
   // Clean old data first (>1 hour)
   CleanOldData();
   
   // Add new data
   m_history[m_history_index].spread = spread_points;
   m_history[m_history_index].volume = volume;
   m_history[m_history_index].time = TimeCurrent();
   
   // Move to next index (circular)
   m_history_index = (m_history_index + 1) % 3600;
   
   // Update count
   if(m_history_count < 3600)
      m_history_count++;
}

//+------------------------------------------------------------------+
//| Clean old data (>1 hour)                                          |
//+------------------------------------------------------------------+
void CSpreadFilter::CleanOldData()
{
   datetime cutoff = TimeCurrent() - 3600; // 1 hour ago
   
   for(int i = 0; i < m_history_count; i++)
   {
      if(m_history[i].time < cutoff)
      {
         // Mark as invalid
         m_history[i].time = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate volume-weighted average spread                          |
//+------------------------------------------------------------------+
double CSpreadFilter::CalculateVolumeWeightedAverage()
{
   double total_weighted = 0.0;
   long total_volume = 0;
   
   for(int i = 0; i < m_history_count; i++)
   {
      if(m_history[i].time > 0) // Valid data
      {
         total_weighted += m_history[i].spread * m_history[i].volume;
         total_volume += m_history[i].volume;
      }
   }
   
   if(total_volume == 0)
      return m_current_spread; // Fallback to current
   
   m_vw_average = total_weighted / total_volume;
   return m_vw_average;
}

//+------------------------------------------------------------------+
//| Calculate minimum spread in window                                |
//+------------------------------------------------------------------+
double CSpreadFilter::CalculateMinSpread()
{
   double min = 999999.0;
   
   for(int i = 0; i < m_history_count; i++)
   {
      if(m_history[i].time > 0 && m_history[i].spread < min)
      {
         min = m_history[i].spread;
      }
   }
   
   if(min == 999999.0)
      min = m_current_spread;
   
   m_min_spread = min;
   return min;
}

//+------------------------------------------------------------------+
//| Calculate maximum spread in window                                |
//+------------------------------------------------------------------+
double CSpreadFilter::CalculateMaxSpread()
{
   double max = 0.0;
   
   for(int i = 0; i < m_history_count; i++)
   {
      if(m_history[i].time > 0 && m_history[i].spread > max)
      {
         max = m_history[i].spread;
      }
   }
   
   m_max_spread = max;
   return max;
}

//+------------------------------------------------------------------+
//| Get session multiplier based on time                              |
//+------------------------------------------------------------------+
double CSpreadFilter::GetSessionMultiplier() const
{
   datetime current = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current, dt);
   
   int hour = dt.hour; // GMT hour
   
   // Asian Session (00:00-08:00 GMT) - Low liquidity
   if(hour >= 0 && hour < 8)
      return 1.5;
   
   // European Session (08:00-13:00 GMT) - Medium liquidity
   if(hour >= 8 && hour < 13)
      return 1.2;
   
   // Overlap Session (13:00-16:00 GMT) - High liquidity
   if(hour >= 13 && hour < 16)
      return 0.8;
   
   // US Session (16:00-22:00 GMT) - High liquidity
   if(hour >= 16 && hour < 22)
      return 1.0;
   
   // Late US (22:00-24:00 GMT) - Medium liquidity
   return 1.3;
}

//+------------------------------------------------------------------+
//| Get dynamic threshold using formula                               |
//+------------------------------------------------------------------+
double CSpreadFilter::GetDynamicThreshold()
{
   // Calculate components
   double avg = CalculateVolumeWeightedAverage();
   double min = CalculateMinSpread();
   
   // Your formula: avg + (avg - min) × 0.1
   double base = avg + (avg - min) * m_formula_factor;
   
   // Apply session multiplier
   double session_mult = GetSessionMultiplier();
   double adjusted = base * session_mult;
   
   // Apply safety bounds (convert pips to points)
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double min_points = m_min_allowed * 10 / point; // Rough conversion
   double max_points = m_max_allowed * 10 / point;
   
   if(adjusted < min_points) adjusted = min_points;
   if(adjusted > max_points) adjusted = max_points;
   
   m_dynamic_threshold = adjusted;
   return adjusted;
}

//+------------------------------------------------------------------+
//| Check if current spread is acceptable                             |
//+------------------------------------------------------------------+
bool CSpreadFilter::IsSpreadAcceptable()
{
   m_total_checks++;
   m_last_check_time = TimeCurrent();
   
   double current = GetCurrentSpreadPoints();
   double threshold = GetDynamicThreshold();
   
   bool acceptable = (current <= threshold);
   
   if(!acceptable)
   {
      m_total_rejections++;
      Print("[SpreadFilter] ❌ Spread too high!");
      Print("  Current: ", DoubleToString(current, 1), " points");
      Print("  Threshold: ", DoubleToString(threshold, 1), " points");
      Print("  VW Average: ", DoubleToString(m_vw_average, 1), " points");
      Print("  Min: ", DoubleToString(m_min_spread, 1), " points");
      Print("  Session mult: ", DoubleToString(GetSessionMultiplier(), 2), "x");
   }
   
   return acceptable;
}

//+------------------------------------------------------------------+
//| Check if specific spread is acceptable                            |
//+------------------------------------------------------------------+
bool CSpreadFilter::IsSpreadAcceptable(double spread_points)
{
   double threshold = GetDynamicThreshold();
   return (spread_points <= threshold);
}

//+------------------------------------------------------------------+
//| Get rejection rate                                                |
//+------------------------------------------------------------------+
double CSpreadFilter::GetRejectionRate() const
{
   if(m_total_checks == 0) return 0.0;
   return (double)m_total_rejections / m_total_checks * 100.0;
}

//+------------------------------------------------------------------+
//| Print status                                                      |
//+------------------------------------------------------------------+
void CSpreadFilter::PrintStatus() const
{
   Print("═══════════════════════════════════════════");
   Print("SPREAD FILTER STATUS");
   Print("═══════════════════════════════════════════");
   Print("Current:");
   Print("  Spread: ", DoubleToString(m_current_spread, 1), " points");
   Print("  Threshold: ", DoubleToString(m_dynamic_threshold, 1), " points");
   Print("  Status: ", (m_current_spread <= m_dynamic_threshold) ? "✅ OK" : "❌ HIGH");
   
   Print("Statistics (1 hour):");
   Print("  VW Average: ", DoubleToString(m_vw_average, 1), " points");
   Print("  Min: ", DoubleToString(m_min_spread, 1), " points");
   Print("  Max: ", DoubleToString(m_max_spread, 1), " points");
   Print("  Data points: ", m_history_count);
   
   Print("Session:");
   Print("  Multiplier: ", DoubleToString(GetSessionMultiplier(), 2), "x");
   
   Print("Rejections:");
   Print("  Total checks: ", m_total_checks);
   Print("  Rejections: ", m_total_rejections);
   Print("  Rate: ", DoubleToString(GetRejectionRate(), 1), "%");
   Print("═══════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Reset statistics                                                  |
//+------------------------------------------------------------------+
void CSpreadFilter::ResetStatistics()
{
   m_total_checks = 0;
   m_total_rejections = 0;
   Print("[SpreadFilter] Statistics reset");
}
