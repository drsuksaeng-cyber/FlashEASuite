//+------------------------------------------------------------------+
//| ZScoreFilter.mqh                                                 |
//| FlashEASuite V2 - Z-Score Statistical Filter                   |
//| Location: Include/Logic/Spike/ZScoreFilter.mqh                  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Z-Score Filter Class                                             |
//| Statistical significance filter for spike detection             |
//+------------------------------------------------------------------+
class CZScoreFilter
{
private:
    double            m_price_changes[100];  // Price change history
    int               m_index;               // Current index
    int               m_period;              // Period for calculation
    double            m_threshold;           // Z-Score threshold
    bool              m_enabled;             // Filter enabled/disabled
    
public:
    //--- Constructor
    CZScoreFilter()
        : m_index(0)
        , m_period(100)
        , m_threshold(2.0)
        , m_enabled(false)
    {
        ArrayInitialize(m_price_changes, 0);
    }
    
    //--- Destructor
    ~CZScoreFilter() {}
    
    //--- Initialize
    bool Init(int period = 100, double threshold = 2.0, bool enabled = false)
    {
        m_period = period;
        m_threshold = threshold;
        m_enabled = enabled;
        
        if(!m_enabled)
        {
            Print("ℹ️  Z-Score Filter disabled (optional)");
            return true;
        }
        
        Print("✅ Z-Score Filter initialized (period: ", m_period,
              ", threshold: ", DoubleToString(m_threshold, 1), ")");
        
        return true;
    }
    
    //--- Update with new price change
    void UpdateHistory(double price_change)
    {
        m_price_changes[m_index] = price_change;
        m_index = (m_index + 1) % 100;
    }
    
    //--- Calculate mean of price changes
    double CalculateMean()
    {
        double sum = 0;
        
        for(int i = 0; i < m_period; i++)
        {
            sum += m_price_changes[i];
        }
        
        return sum / m_period;
    }
    
    //--- Calculate standard deviation
    double CalculateStdDev(double mean)
    {
        double sum_sq = 0;
        
        for(int i = 0; i < m_period; i++)
        {
            double diff = m_price_changes[i] - mean;
            sum_sq += diff * diff;
        }
        
        return MathSqrt(sum_sq / m_period);
    }
    
    //--- Calculate Z-Score for current value
    double Calculate(double current_value)
    {
        double mean = CalculateMean();
        double std_dev = CalculateStdDev(mean);
        
        if(std_dev == 0) return 0;
        
        double zscore = (current_value - mean) / std_dev;
        
        return zscore;
    }
    
    //--- Check statistical significance
    bool CheckSignificance(double current_value)
    {
        // If filter disabled, always pass
        if(!m_enabled) return true;
        
        double zscore = Calculate(current_value);
        
        bool is_significant = (MathAbs(zscore) >= m_threshold);
        
        if(!is_significant)
        {
            Print("⚠️  Not statistically significant: Z-Score = ",
                  DoubleToString(zscore, 2), " (threshold: ", m_threshold, ")");
        }
        else
        {
            Print("✅ Statistically significant: Z-Score = ",
                  DoubleToString(zscore, 2), " >= ", m_threshold);
        }
        
        return is_significant;
    }
    
    //--- Enable/Disable filter
    void SetEnabled(bool enabled)
    {
        m_enabled = enabled;
        Print(m_enabled ? "✅ Z-Score Filter enabled" : "ℹ️  Z-Score Filter disabled");
    }
    
    //--- Check if enabled
    bool IsEnabled() const { return m_enabled; }
};

//+------------------------------------------------------------------+
