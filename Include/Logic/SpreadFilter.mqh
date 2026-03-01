//+------------------------------------------------------------------+
//| SpreadFilter.mqh                                                 |
//| Spread quality filter for trade validation                      |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Spread Filter Class                                              |
//+------------------------------------------------------------------+
class CSpreadFilter
{
private:
    double            m_max_spread_points;
    string            m_symbol;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CSpreadFilter()
    {
        m_max_spread_points = 30.0;  // Default 30 points
        m_symbol = _Symbol;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CSpreadFilter() {}
    
    //+------------------------------------------------------------------+
    //| Initialize with symbol and max spread                           |
    //+------------------------------------------------------------------+
    void Init(string symbol, double max_spread_points)
    {
        m_symbol = symbol;
        m_max_spread_points = max_spread_points;
    }
    
    //+------------------------------------------------------------------+
    //| Check if current spread is acceptable                           |
    //+------------------------------------------------------------------+
    bool IsSpreadOK()
    {
        double spread = GetCurrentSpread();
        return (spread <= m_max_spread_points);
    }
    
    //+------------------------------------------------------------------+
    //| Get current spread in points                                    |
    //+------------------------------------------------------------------+
    double GetCurrentSpread()
    {
        MqlTick tick;
        if(!SymbolInfoTick(m_symbol, tick))
            return 999.0;  // Return high value if failed
        
        double spread = tick.ask - tick.bid;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        
        if(point > 0)
            return spread / point;
        
        return 999.0;
    }
    
    //+------------------------------------------------------------------+
    //| Set maximum allowed spread                                      |
    //+------------------------------------------------------------------+
    void SetMaxSpread(double max_points)
    {
        m_max_spread_points = max_points;
    }
    
    //+------------------------------------------------------------------+
    //| Get maximum allowed spread                                      |
    //+------------------------------------------------------------------+
    double GetMaxSpread() const
    {
        return m_max_spread_points;
    }
};