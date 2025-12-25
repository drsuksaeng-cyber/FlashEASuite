//+------------------------------------------------------------------+
//|                                      Grid/RangeAnalyzer.mqh      |
//|                                    FlashEASuite V2 - Week 5      |
//|                    Sideways Range Analysis by Symbol/TF          |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Range Analysis Result Structure                                  |
//+------------------------------------------------------------------+
struct RangeAnalysisResult
{
    string   symbol;              // Symbol name
    ENUM_TIMEFRAMES timeframe;    // Timeframe
    
    // Range statistics (in points)
    double   avg_sideways_range;  // Average sideways range
    double   min_sideways_range;  // Minimum observed range
    double   max_sideways_range;  // Maximum observed range
    double   typical_range;       // Most common range (mode)
    
    // Volatility metrics
    double   range_std_dev;       // Standard deviation
    double   atr_value;           // Average True Range
    
    // Grid recommendations (in points)
    int      recommended_spacing; // Recommended grid spacing
    int      recommended_levels;  // Recommended number of levels
    double   recommended_tp;      // Recommended take profit
    
    // Analysis metadata
    int      bars_analyzed;       // Number of bars analyzed
    datetime last_update;         // Last analysis time
    bool     is_valid;            // Analysis validity
};

//+------------------------------------------------------------------+
//| Sideways Range Detection                                         |
//+------------------------------------------------------------------+
struct SidewaysSegment
{
    datetime start_time;
    datetime end_time;
    double   high_price;
    double   low_price;
    double   range_points;
    int      duration_bars;
    bool     is_sideways;
};

//+------------------------------------------------------------------+
//| Range Analyzer Class                                             |
//+------------------------------------------------------------------+
class CRangeAnalyzer
{
private:
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    int               m_lookback_bars;
    
    // ATR indicator
    int               m_atr_handle;
    int               m_atr_period;
    
    // Analysis results
    RangeAnalysisResult m_result;
    SidewaysSegment   m_segments[];
    int               m_segment_count;
    
    // Detection parameters
    double            m_sideways_threshold;  // ADX threshold for sideways (default: 25)
    int               m_min_sideways_bars;   // Minimum bars for sideways (default: 20)
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CRangeAnalyzer(string symbol = "", ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
    {
        m_symbol = (symbol == "") ? _Symbol : symbol;
        m_timeframe = (timeframe == PERIOD_CURRENT) ? _Period : timeframe;
        m_lookback_bars = 1000;  // Default: analyze last 1000 bars
        
        m_atr_period = 14;
        m_atr_handle = INVALID_HANDLE;
        
        m_segment_count = 0;
        m_sideways_threshold = 25.0;
        m_min_sideways_bars = 20;
        
        // Initialize result
        m_result.symbol = m_symbol;
        m_result.timeframe = m_timeframe;
        m_result.is_valid = false;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CRangeAnalyzer()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }
    
    //+------------------------------------------------------------------+
    //| Initialize Analyzer                                             |
    //+------------------------------------------------------------------+
    bool Initialize(int lookback_bars = 1000, int atr_period = 14)
    {
        m_lookback_bars = lookback_bars;
        m_atr_period = atr_period;
        
        // Create ATR indicator
        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("❌ Failed to create ATR indicator for ", m_symbol);
            return false;
        }
        
        Print("✅ RangeAnalyzer initialized: ", m_symbol, " ", EnumToString(m_timeframe));
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Run Complete Analysis                                           |
    //+------------------------------------------------------------------+
    bool AnalyzeRange()
    {
        Print("📊 Starting range analysis: ", m_symbol, " ", EnumToString(m_timeframe));
        
        // Step 1: Detect sideways segments
        if(!DetectSidewaysSegments())
        {
            Print("❌ Failed to detect sideways segments");
            return false;
        }
        
        // Step 2: Calculate range statistics
        if(!CalculateRangeStatistics())
        {
            Print("❌ Failed to calculate range statistics");
            return false;
        }
        
        // Step 3: Get ATR value
        if(!GetATRValue())
        {
            Print("❌ Failed to get ATR value");
            return false;
        }
        
        // Step 4: Generate grid recommendations
        GenerateGridRecommendations();
        
        m_result.last_update = TimeCurrent();
        m_result.is_valid = true;
        
        PrintAnalysisResults();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Detect Sideways Segments                                        |
    //+------------------------------------------------------------------+
    bool DetectSidewaysSegments()
    {
        ArrayResize(m_segments, 0);
        m_segment_count = 0;
        
        MqlRates rates[];
        int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookback_bars, rates);
        
        if(copied < m_min_sideways_bars)
        {
            Print("❌ Not enough bars copied: ", copied);
            return false;
        }
        
        // Simple sideways detection: look for periods with small range
        double avg_range = 0;
        for(int i = 0; i < copied; i++)
        {
            avg_range += (rates[i].high - rates[i].low);
        }
        avg_range /= copied;
        
        // Detect segments with range < 1.5x average
        int segment_start = 0;
        bool in_sideways = false;
        
        for(int i = 0; i < copied; i++)
        {
            double bar_range = rates[i].high - rates[i].low;
            bool is_small_range = (bar_range < avg_range * 1.5);
            
            if(!in_sideways && is_small_range)
            {
                // Start new sideways segment
                segment_start = i;
                in_sideways = true;
            }
            else if(in_sideways && !is_small_range)
            {
                // End sideways segment
                int segment_length = i - segment_start;
                if(segment_length >= m_min_sideways_bars)
                {
                    AddSidewaysSegment(rates, segment_start, i - 1);
                }
                in_sideways = false;
            }
        }
        
        // Check if still in sideways at end
        if(in_sideways)
        {
            int segment_length = copied - segment_start;
            if(segment_length >= m_min_sideways_bars)
            {
                AddSidewaysSegment(rates, segment_start, copied - 1);
            }
        }
        
        Print("✅ Detected ", m_segment_count, " sideways segments");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Add Sideways Segment                                            |
    //+------------------------------------------------------------------+
    void AddSidewaysSegment(const MqlRates &rates[], int start_idx, int end_idx)
    {
        m_segment_count++;
        ArrayResize(m_segments, m_segment_count);
        
        int idx = m_segment_count - 1;
        
        m_segments[idx].start_time = rates[start_idx].time;
        m_segments[idx].end_time = rates[end_idx].time;
        m_segments[idx].duration_bars = end_idx - start_idx + 1;
        
        // Find high and low in segment
        m_segments[idx].high_price = rates[start_idx].high;
        m_segments[idx].low_price = rates[start_idx].low;
        
        for(int i = start_idx; i <= end_idx; i++)
        {
            if(rates[i].high > m_segments[idx].high_price) m_segments[idx].high_price = rates[i].high;
            if(rates[i].low < m_segments[idx].low_price) m_segments[idx].low_price = rates[i].low;
        }
        
        m_segments[idx].range_points = (m_segments[idx].high_price - m_segments[idx].low_price) / _Point;
        m_segments[idx].is_sideways = true;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Range Statistics                                      |
    //+------------------------------------------------------------------+
    bool CalculateRangeStatistics()
    {
        if(m_segment_count == 0)
        {
            Print("⚠️ No sideways segments detected");
            return false;
        }
        
        // Calculate average, min, max
        double sum = 0;
        double sum_sq = 0;
        m_result.min_sideways_range = DBL_MAX;
        m_result.max_sideways_range = 0;
        
        for(int i = 0; i < m_segment_count; i++)
        {
            double range = m_segments[i].range_points;
            sum += range;
            sum_sq += range * range;
            
            if(range < m_result.min_sideways_range)
                m_result.min_sideways_range = range;
            if(range > m_result.max_sideways_range)
                m_result.max_sideways_range = range;
        }
        
        m_result.avg_sideways_range = sum / m_segment_count;
        
        // Calculate standard deviation
        double variance = (sum_sq / m_segment_count) - (m_result.avg_sideways_range * m_result.avg_sideways_range);
        m_result.range_std_dev = MathSqrt(variance);
        
        // Typical range = median (approximate with average for simplicity)
        m_result.typical_range = m_result.avg_sideways_range;
        
        m_result.bars_analyzed = m_lookback_bars;
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get ATR Value                                                   |
    //+------------------------------------------------------------------+
    bool GetATRValue()
    {
        double atr[];
        ArraySetAsSeries(atr, true);
        
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr) <= 0)
        {
            Print("❌ Failed to copy ATR buffer");
            return false;
        }
        
        m_result.atr_value = atr[0] / _Point;  // Convert to points
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Generate Grid Recommendations                                   |
    //+------------------------------------------------------------------+
    void GenerateGridRecommendations()
    {
        // Grid spacing = typical_range / recommended_levels
        // Aim for 5-10 levels within typical range
        
        int target_levels = 7;  // Target 7 grid levels
        
        m_result.recommended_spacing = (int)(m_result.typical_range / target_levels);
        
        // Round to nearest 10 points for cleaner values
        m_result.recommended_spacing = (int)MathRound(m_result.recommended_spacing / 10.0) * 10;
        
        // Minimum spacing based on ATR
        int min_spacing = (int)(m_result.atr_value * 0.5);  // At least 50% of ATR
        if(m_result.recommended_spacing < min_spacing)
            m_result.recommended_spacing = min_spacing;
        
        // Calculate number of levels that fit in typical range
        m_result.recommended_levels = (int)(m_result.typical_range / m_result.recommended_spacing);
        
        // Take profit = 1.5x grid spacing (conservative)
        m_result.recommended_tp = m_result.recommended_spacing * 1.5;
        
        Print("📊 Grid Recommendations:");
        Print("   Spacing: ", m_result.recommended_spacing, " points");
        Print("   Levels: ", m_result.recommended_levels);
        Print("   Take Profit: ", m_result.recommended_tp, " points");
    }
    
    //+------------------------------------------------------------------+
    //| Print Analysis Results                                          |
    //+------------------------------------------------------------------+
    void PrintAnalysisResults()
    {
        Print("═══════════════════════════════════════════");
        Print("📊 RANGE ANALYSIS RESULTS");
        Print("═══════════════════════════════════════════");
        Print("Symbol: ", m_result.symbol);
        Print("Timeframe: ", EnumToString(m_result.timeframe));
        Print("Bars Analyzed: ", m_result.bars_analyzed);
        Print("Sideways Segments: ", m_segment_count);
        Print("───────────────────────────────────────────");
        Print("Range Statistics (points):");
        Print("  Average: ", DoubleToString(m_result.avg_sideways_range, 1));
        Print("  Typical: ", DoubleToString(m_result.typical_range, 1));
        Print("  Min: ", DoubleToString(m_result.min_sideways_range, 1));
        Print("  Max: ", DoubleToString(m_result.max_sideways_range, 1));
        Print("  Std Dev: ", DoubleToString(m_result.range_std_dev, 1));
        Print("  ATR: ", DoubleToString(m_result.atr_value, 1));
        Print("───────────────────────────────────────────");
        Print("Grid Recommendations:");
        Print("  Spacing: ", m_result.recommended_spacing, " points");
        Print("  Levels: ", m_result.recommended_levels);
        Print("  Take Profit: ", DoubleToString(m_result.recommended_tp, 1), " points");
        Print("═══════════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Get Analysis Result                                             |
    //+------------------------------------------------------------------+
    RangeAnalysisResult GetResult() { return m_result; }
    
    //+------------------------------------------------------------------+
    //| Get Recommended Grid Spacing                                    |
    //+------------------------------------------------------------------+
    int GetRecommendedSpacing() { return m_result.recommended_spacing; }
    
    //+------------------------------------------------------------------+
    //| Get Recommended Grid Levels                                     |
    //+------------------------------------------------------------------+
    int GetRecommendedLevels() { return m_result.recommended_levels; }
};

//+------------------------------------------------------------------+
