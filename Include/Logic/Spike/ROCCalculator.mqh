//+------------------------------------------------------------------+
//| ROCCalculator.mqh                                                |
//| FlashEASuite V2 - Rate of Change Calculator                     |
//| Location: Include/Logic/Spike/ROCCalculator.mqh                 |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| ROC Calculator Class                                             |
//| Calculates Rate of Change for momentum detection                |
//+------------------------------------------------------------------+
class CROCCalculator
{
private:
    double            m_price_history[1000]; // Price buffer
    int               m_index;               // Current index
    int               m_period;              // ROC period
    double            m_threshold;           // ROC threshold (%)
    
public:
    //--- Constructor
    CROCCalculator()
        : m_index(0)
        , m_period(10)
        , m_threshold(0.5)
    {
        ArrayInitialize(m_price_history, 0);
    }
    
    //--- Destructor
    ~CROCCalculator() {}
    
    //--- Initialize
    bool Init(int period = 10, double threshold = 0.5)
    {
        m_period = period;
        m_threshold = threshold;
        
        Print("✅ ROC Calculator initialized (period: ", m_period,
              ", threshold: ", DoubleToString(m_threshold, 2), "%)");
        
        return true;
    }
    
    //--- Update with new price
    void UpdatePrice(double price)
    {
        m_price_history[m_index] = price;
        m_index = (m_index + 1) % 1000;
    }
    
    //--- Calculate ROC
    double Calculate(int period = 0)
    {
        if(period == 0) period = m_period;
        
        // Get current price
        int current_idx = (m_index - 1 + 1000) % 1000;
        double current_price = m_price_history[current_idx];
        
        // Get old price
        int old_idx = (m_index - period - 1 + 1000) % 1000;
        double old_price = m_price_history[old_idx];
        
        if(old_price == 0) return 0;
        
        // ROC formula: ((Current - Old) / Old) * 100
        double roc = ((current_price - old_price) / old_price) * 100.0;
        
        return roc;
    }
    
    //--- Check if ROC exceeds threshold
    bool CheckThreshold(double threshold = 0)
    {
        if(threshold == 0) threshold = m_threshold;
        
        double roc = Calculate();
        
        bool exceeds = (MathAbs(roc) >= threshold);
        
        if(exceeds)
        {
            Print("🚀 ROC Spike: ", DoubleToString(roc, 4), "% (threshold: ",
                  DoubleToString(threshold, 2), "%)");
        }
        
        return exceeds;
    }
    
    //--- Get direction
    int GetDirection()
    {
        double roc = Calculate();
        
        if(roc > 0.1) return 1;   // BUY
        if(roc < -0.1) return -1; // SELL
        
        return 0; // NEUTRAL
    }
    
    //--- Get price move (absolute)
    double GetPriceMove(int period = 0)
    {
        if(period == 0) period = m_period;
        
        int current_idx = (m_index - 1 + 1000) % 1000;
        double current_price = m_price_history[current_idx];
        
        int old_idx = (m_index - period - 1 + 1000) % 1000;
        double old_price = m_price_history[old_idx];
        
        return MathAbs(current_price - old_price);
    }
};

//+------------------------------------------------------------------+
