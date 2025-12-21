//+------------------------------------------------------------------+
//|                                  Grid/SlippageController.mqh     |
//|                                FlashEASuite V2 - Week 4          |
//|                      ATR-Based Slippage Control                   |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Slippage Configuration Structure                                |
//+------------------------------------------------------------------+
struct SlippageConfig
{
    double            max_slippage_points;    // Maximum allowed slippage
    double            atr_multiplier;         // ATR multiplier for dynamic
    bool              use_dynamic;            // Use dynamic (ATR-based)?
    string            message;                // Configuration message
};

//+------------------------------------------------------------------+
//| Class: CSlippageController                                       |
//| Controls acceptable slippage based on market volatility (ATR)    |
//+------------------------------------------------------------------+
class CSlippageController
{
private:
    int               m_atr_handle;           // ATR indicator handle
    
    // Slippage parameters
    double            m_base_slippage;        // Base slippage (points)
    double            m_atr_multiplier;       // Multiplier (0.5 = half ATR)
    double            m_min_slippage;         // Minimum (10 points)
    double            m_max_slippage;         // Maximum (100 points)
    
    // Dynamic calculation
    bool              m_use_dynamic;          // Use ATR-based?
    double            m_current_slippage;     // Current calculated value
    
    // Statistics
    double            m_total_slippage;       // Total slippage seen
    int               m_execution_count;      // Number of executions
    double            m_avg_slippage;         // Average slippage
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CSlippageController()
    {
        m_atr_handle = INVALID_HANDLE;
        
        m_base_slippage = 20.0;
        m_atr_multiplier = 0.5;
        m_min_slippage = 10.0;
        m_max_slippage = 100.0;
        
        m_use_dynamic = true;
        m_current_slippage = m_base_slippage;
        
        m_total_slippage = 0.0;
        m_execution_count = 0;
        m_avg_slippage = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize with ATR Handle                                      |
    //+------------------------------------------------------------------+
    void Initialize(int atr_handle, bool use_dynamic = true, double atr_mult = 0.5)
    {
        m_atr_handle = atr_handle;
        m_use_dynamic = use_dynamic;
        m_atr_multiplier = atr_mult;
        
        // Calculate initial slippage
        UpdateSlippage();
    }
    
    //+------------------------------------------------------------------+
    //| Get Current Slippage Configuration                             |
    //+------------------------------------------------------------------+
    SlippageConfig GetSlippageConfig()
    {
        SlippageConfig config;
        
        // Update before returning
        if(m_use_dynamic)
        {
            UpdateSlippage();
        }
        
        config.max_slippage_points = m_current_slippage;
        config.atr_multiplier = m_atr_multiplier;
        config.use_dynamic = m_use_dynamic;
        
        if(m_use_dynamic)
        {
            config.message = StringFormat("Dynamic: %.1f pts (ATR-based)", m_current_slippage);
        }
        else
        {
            config.message = StringFormat("Fixed: %.1f pts", m_base_slippage);
        }
        
        return config;
    }
    
    //+------------------------------------------------------------------+
    //| Get Maximum Acceptable Slippage (points)                       |
    //+------------------------------------------------------------------+
    double GetMaxSlippage()
    {
        if(m_use_dynamic)
        {
            UpdateSlippage();
        }
        
        return m_current_slippage;
    }
    
    //+------------------------------------------------------------------+
    //| Check if Slippage is Acceptable                                |
    //+------------------------------------------------------------------+
    bool IsSlippageAcceptable(double actual_slippage)
    {
        // Update max
        if(m_use_dynamic)
        {
            UpdateSlippage();
        }
        
        // Record slippage
        RecordSlippage(actual_slippage);
        
        // Check
        if(actual_slippage <= m_current_slippage)
        {
            return true;
        }
        else
        {
            Print(StringFormat("[Slippage] ⚠️ Exceeded: %.1f/%.1f pts", 
                              actual_slippage, 
                              m_current_slippage));
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Set Fixed Slippage (disable dynamic)                           |
    //+------------------------------------------------------------------+
    void SetFixedSlippage(double points)
    {
        m_use_dynamic = false;
        m_base_slippage = points;
        m_current_slippage = points;
        
        Print(StringFormat("[Slippage] Fixed mode: %.1f pts", points));
    }
    
    //+------------------------------------------------------------------+
    //| Enable Dynamic Slippage (ATR-based)                            |
    //+------------------------------------------------------------------+
    void EnableDynamic(double atr_multiplier = 0.5)
    {
        m_use_dynamic = true;
        m_atr_multiplier = atr_multiplier;
        
        UpdateSlippage();
        
        Print(StringFormat("[Slippage] Dynamic mode: %.1f x ATR", atr_multiplier));
    }
    
    //+------------------------------------------------------------------+
    //| Get Statistics                                                  |
    //+------------------------------------------------------------------+
    string GetStatistics()
    {
        return StringFormat("Slippage | Max: %.1f pts | Avg: %.1f pts | Executions: %d | Mode: %s",
                           m_current_slippage,
                           m_avg_slippage,
                           m_execution_count,
                           m_use_dynamic ? "Dynamic" : "Fixed");
    }

private:
    //+------------------------------------------------------------------+
    //| Update Dynamic Slippage Based on ATR                           |
    //+------------------------------------------------------------------+
    void UpdateSlippage()
    {
        if(!m_use_dynamic)
        {
            m_current_slippage = m_base_slippage;
            return;
        }
        
        if(m_atr_handle == INVALID_HANDLE)
        {
            m_current_slippage = m_base_slippage;
            return;
        }
        
        // Get current ATR
        double atr_buffer[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
        {
            m_current_slippage = m_base_slippage;
            return;
        }
        
        double atr_points = atr_buffer[0] / _Point;
        
        // Calculate: ATR * multiplier
        double calculated = atr_points * m_atr_multiplier;
        
        // Apply limits
        if(calculated < m_min_slippage) calculated = m_min_slippage;
        if(calculated > m_max_slippage) calculated = m_max_slippage;
        
        m_current_slippage = calculated;
    }
    
    //+------------------------------------------------------------------+
    //| Record Actual Slippage for Statistics                          |
    //+------------------------------------------------------------------+
    void RecordSlippage(double slippage)
    {
        m_execution_count++;
        m_total_slippage += slippage;
        
        // Calculate average
        m_avg_slippage = m_total_slippage / m_execution_count;
    }
};
//+------------------------------------------------------------------+
