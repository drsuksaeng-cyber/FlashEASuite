//+------------------------------------------------------------------+
//|                                      Grid/SpreadFilter.mqh       |
//|                                  FlashEASuite V2 - Week 4        |
//|                        Dynamic Spread Filtering                   |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Spread Analysis Structure                                        |
//+------------------------------------------------------------------+
struct SpreadInfo
{
    double            current_spread;     // Current spread (points)
    double            avg_spread;         // Average spread
    double            spread_ratio;       // Current / Average
    bool              is_acceptable;      // Within limits?
    string            message;            // Status message
};

//+------------------------------------------------------------------+
//| Class: CSpreadFilter                                             |
//| Filters trades based on spread conditions                        |
//+------------------------------------------------------------------+
class CSpreadFilter
{
private:
    // Spread history
    double            m_avg_spread;           // Running average
    double            m_min_spread;           // Minimum seen
    double            m_max_spread;           // Maximum seen
    int               m_sample_count;         // Number of samples
    
    // Filter parameters
    double            m_max_spread_ratio;     // 2.0x average max
    double            m_absolute_max_spread;  // 50 points absolute max
    
    // Timing
    datetime          m_last_update;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CSpreadFilter()
    {
        m_avg_spread = 0.0;
        m_min_spread = 999999.0;
        m_max_spread = 0.0;
        m_sample_count = 0;
        
        m_max_spread_ratio = 2.0;
        m_absolute_max_spread = 50.0;
        
        m_last_update = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize with Parameters                                       |
    //+------------------------------------------------------------------+
    void Initialize(double max_ratio = 2.0, double absolute_max = 50.0)
    {
        m_max_spread_ratio = max_ratio;
        m_absolute_max_spread = absolute_max;
        
        // Initialize average
        UpdateSpreadStatistics();
    }
    
    //+------------------------------------------------------------------+
    //| Check if Spread is Acceptable                                   |
    //+------------------------------------------------------------------+
    SpreadInfo CheckSpread()
    {
        SpreadInfo info;
        
        // Get current spread
        info.current_spread = GetCurrentSpread();
        
        // Update statistics every 5 seconds
        if(TimeCurrent() - m_last_update >= 5)
        {
            UpdateSpreadStatistics();
            m_last_update = TimeCurrent();
        }
        
        info.avg_spread = m_avg_spread;
        info.spread_ratio = (m_avg_spread > 0) ? info.current_spread / m_avg_spread : 1.0;
        info.is_acceptable = true;
        info.message = "OK";
        
        // Check absolute maximum
        if(info.current_spread > m_absolute_max_spread)
        {
            info.is_acceptable = false;
            info.message = StringFormat("Spread too high: %.1f pts (max: %.1f)", 
                                       info.current_spread, 
                                       m_absolute_max_spread);
            return info;
        }
        
        // Check ratio to average
        if(info.spread_ratio > m_max_spread_ratio)
        {
            info.is_acceptable = false;
            info.message = StringFormat("Spread %.1fx average (%.1f/%.1f pts)", 
                                       info.spread_ratio,
                                       info.current_spread,
                                       info.avg_spread);
            return info;
        }
        
        // Acceptable
        info.message = StringFormat("Spread OK: %.1f pts", info.current_spread);
        return info;
    }
    
    //+------------------------------------------------------------------+
    //| Quick Check (bool only)                                         |
    //+------------------------------------------------------------------+
    bool IsSpreadAcceptable()
    {
        SpreadInfo info = CheckSpread();
        return info.is_acceptable;
    }
    
    //+------------------------------------------------------------------+
    //| Get Spread Statistics                                           |
    //+------------------------------------------------------------------+
    string GetStatistics()
    {
        return StringFormat("Spread | Cur: %.1f | Avg: %.1f | Min: %.1f | Max: %.1f | Samples: %d",
                           GetCurrentSpread(),
                           m_avg_spread,
                           m_min_spread,
                           m_max_spread,
                           m_sample_count);
    }
    
    //+------------------------------------------------------------------+
    //| Reset Statistics                                                |
    //+------------------------------------------------------------------+
    void Reset()
    {
        m_avg_spread = 0.0;
        m_min_spread = 999999.0;
        m_max_spread = 0.0;
        m_sample_count = 0;
    }

private:
    //+------------------------------------------------------------------+
    //| Get Current Spread                                              |
    //+------------------------------------------------------------------+
    double GetCurrentSpread()
    {
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
            return 0.0;
            
        return (tick.ask - tick.bid) / _Point;
    }
    
    //+------------------------------------------------------------------+
    //| Update Spread Statistics                                        |
    //+------------------------------------------------------------------+
    void UpdateSpreadStatistics()
    {
        double current = GetCurrentSpread();
        
        if(current <= 0) return;
        
        // Update min/max
        if(current < m_min_spread) m_min_spread = current;
        if(current > m_max_spread) m_max_spread = current;
        
        // Update average (exponential moving average)
        if(m_sample_count == 0)
        {
            m_avg_spread = current;
            m_sample_count = 1;
        }
        else
        {
            m_avg_spread = m_avg_spread * 0.95 + current * 0.05;
            m_sample_count++;
        }
    }
};
//+------------------------------------------------------------------+
