//+------------------------------------------------------------------+
//| ADXFilter.mqh                                                    |
//| FlashEASuite V2 - ADX Trend Filter                             |
//| Location: Include/Logic/Spike/ADXFilter.mqh                     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| ADX Filter Class                                                 |
//| Filters spikes based on trend strength                          |
//+------------------------------------------------------------------+
class CADXFilter
{
private:
    int               m_handle;              // ADX indicator handle
    double            m_threshold;           // Minimum ADX value
    int               m_period;              // ADX period
    bool              m_enabled;             // Filter enabled/disabled
    
public:
    //--- Constructor
    CADXFilter()
        : m_handle(INVALID_HANDLE)
        , m_threshold(20.0)
        , m_period(14)
        , m_enabled(false)
    {}
    
    //--- Destructor
    ~CADXFilter()
    {
        if(m_handle != INVALID_HANDLE)
            IndicatorRelease(m_handle);
    }
    
    //--- Initialize
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe, int period = 14, 
              double threshold = 20.0, bool enabled = false)
    {
        m_period = period;
        m_threshold = threshold;
        m_enabled = enabled;
        
        if(!m_enabled)
        {
            Print("ℹ️  ADX Filter disabled (optional)");
            return true;
        }
        
        // Create ADX indicator
        m_handle = iADX(symbol, timeframe, m_period);
        
        if(m_handle == INVALID_HANDLE)
        {
            Print("❌ Failed to create ADX indicator (period: ", m_period, ")");
            return false;
        }
        
        Print("✅ ADX Filter initialized (period: ", m_period, 
              ", threshold: ", DoubleToString(m_threshold, 1), ")");
        
        return true;
    }
    
    //--- Check if trend is strong enough
    bool CheckTrend()
    {
        // If filter disabled, always pass
        if(!m_enabled) return true;
        
        if(m_handle == INVALID_HANDLE) return false;
        
        // Get ADX value
        double adx[1];
        if(CopyBuffer(m_handle, 0, 0, 1, adx) != 1)
        {
            Print("⚠️  Failed to get ADX value");
            return false;
        }
        
        bool has_trend = (adx[0] >= m_threshold);
        
        if(!has_trend)
        {
            Print("⚠️  ADX too low: ", DoubleToString(adx[0], 2),
                  " (threshold: ", DoubleToString(m_threshold, 1), ")");
        }
        else
        {
            Print("✅ ADX OK: ", DoubleToString(adx[0], 2), " >= ", m_threshold);
        }
        
        return has_trend;
    }
    
    //--- Get current ADX value
    double GetCurrentADX()
    {
        if(m_handle == INVALID_HANDLE) return 0.0;
        
        double adx[1];
        if(CopyBuffer(m_handle, 0, 0, 1, adx) != 1)
            return 0.0;
        
        return adx[0];
    }
    
    //--- Enable/Disable filter
    void SetEnabled(bool enabled)
    {
        m_enabled = enabled;
        Print(m_enabled ? "✅ ADX Filter enabled" : "ℹ️  ADX Filter disabled");
    }
    
    //--- Check if enabled
    bool IsEnabled() const { return m_enabled; }
};

//+------------------------------------------------------------------+
