//+------------------------------------------------------------------+
//| KeyLevelFinder.mqh                                               |
//| FlashEASuite V2 — S12 Price Action: Key Level Detection         |
//| Subfolder: Include/Logic/Strategies/PriceAction/                |
//+------------------------------------------------------------------+
//| Key Level Types:                                                 |
//|  1. Swing High/Low: N-bar fractal pivot                         |
//|  2. Round Numbers: price ending in 00, 50 (e.g., 2000, 1950)   |
//|  3. S/R Zone: area where price has turned multiple times        |
//| Output: proximity score 0.0-1.0 (1.0 = exactly at level)       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef KEYLEVEL_FINDER_MQH
#define KEYLEVEL_FINDER_MQH

//+------------------------------------------------------------------+
//| STRUCT: Key Level                                                |
//+------------------------------------------------------------------+
struct SKeyLevel
{
    double   price;           // Level price
    int      touches;         // How many times price has touched
    double   strength;        // 0.0-1.0
    bool     is_round;        // Is this a round number level?
    bool     is_swing;        // Is this a swing H/L?
};

//+------------------------------------------------------------------+
//| CKeyLevelFinder — Direct member class (no pointer)              |
//+------------------------------------------------------------------+
class CKeyLevelFinder
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_swing_bars;     // Bars each side for swing pivot (e.g., 5)
    int             m_lookback;       // Total bars to scan for S/R
    double          m_zone_pct;       // Zone width as % of ATR (e.g., 0.5)
    int             m_atr_handle;     // ATR indicator handle
    double          m_atr_value;      // Last ATR value
    
    // Key levels array (static size — no dynamic allocation)
    SKeyLevel       m_levels[50];
    int             m_level_count;
    
public:
    //--- Default constructor
    CKeyLevelFinder()
    {
        m_symbol      = "";
        m_tf          = PERIOD_D1;
        m_swing_bars  = 5;
        m_lookback    = 100;
        m_zone_pct    = 0.5;
        m_atr_handle  = INVALID_HANDLE;
        m_atr_value   = 0.0;
        m_level_count = 0;
    }
    
    ~CKeyLevelFinder()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }
    
    //--- Setup() (Lesson #2)
    bool Setup(string symbol, ENUM_TIMEFRAMES tf,
               int swing_bars = 5, int lookback = 100, double zone_pct = 0.5)
    {
        m_symbol     = symbol;
        m_tf         = tf;
        m_swing_bars = swing_bars;
        m_lookback   = lookback;
        m_zone_pct   = zone_pct;
        
        m_atr_handle = iATR(symbol, tf, 14);
        if(m_atr_handle == INVALID_HANDLE)
        {
            PrintFormat("[KeyLevelFinder] ATR handle failed for %s", symbol);
            return false;
        }
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Scan: Build/refresh key level list                              |
    //| Call once per bar change                                        |
    //+------------------------------------------------------------------+
    void Scan()
    {
        if(m_symbol == "" || m_atr_handle == INVALID_HANDLE) return;
        
        // Get current ATR
        double atr_buf[];
        ArraySetAsSeries(atr_buf, true);
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buf) < 1) return;
        m_atr_value = atr_buf[0];
        
        m_level_count = 0;
        
        // --- 1. Swing High/Low pivots
        _ScanSwingLevels();
        
        // --- 2. Round numbers near current price
        _ScanRoundNumbers();
    }
    
    //+------------------------------------------------------------------+
    //| GetProximity: How close is 'price' to any key level?            |
    //| Returns 0.0-1.0 (1.0 = exactly at level)                       |
    //+------------------------------------------------------------------+
    double GetProximity(double price)
    {
        if(m_level_count == 0 || m_atr_value <= 0) return 0.0;
        
        double zone_size = m_atr_value * m_zone_pct;
        double best = 0.0;
        
        for(int i = 0; i < m_level_count; i++)
        {
            double dist = MathAbs(price - m_levels[i].price);
            if(dist < zone_size)
            {
                double proximity = (1.0 - dist / zone_size) * m_levels[i].strength;
                if(proximity > best) best = proximity;
            }
        }
        return MathMin(1.0, best);
    }
    
    //--- Getters
    int    GetLevelCount()  const { return m_level_count; }
    double GetATR()         const { return m_atr_value; }

private:
    //+------------------------------------------------------------------+
    //| Scan swing H/L pivots using fractal-like logic                  |
    //+------------------------------------------------------------------+
    void _ScanSwingLevels()
    {
        int total_bars = iBars(m_symbol, m_tf);
        int max_scan   = MathMin(m_lookback, total_bars - m_swing_bars - 2);
        
        for(int i = m_swing_bars; i < max_scan && m_level_count < 40; i++)
        {
            double hi = iHigh(m_symbol, m_tf, i);
            double lo = iLow(m_symbol,  m_tf, i);
            
            // Check Swing High
            bool is_swing_hi = true;
            for(int j = 1; j <= m_swing_bars; j++)
            {
                if(iHigh(m_symbol, m_tf, i - j) >= hi ||
                   iHigh(m_symbol, m_tf, i + j) >= hi)
                { is_swing_hi = false; break; }
            }
            
            // Check Swing Low
            bool is_swing_lo = true;
            for(int j = 1; j <= m_swing_bars; j++)
            {
                if(iLow(m_symbol, m_tf, i - j) <= lo ||
                   iLow(m_symbol, m_tf, i + j) <= lo)
                { is_swing_lo = false; break; }
            }
            
            if(is_swing_hi)
                _AddLevel(hi, true, false);
            if(is_swing_lo)
                _AddLevel(lo, true, false);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Scan round numbers near current price                           |
    //+------------------------------------------------------------------+
    void _ScanRoundNumbers()
    {
        double curr = iClose(m_symbol, m_tf, 0);
        if(curr <= 0) return;
        
        // Determine round step based on price magnitude
        double step = 100.0 * _Point * 10;   // default pip-based
        if(curr > 1000) step = 50.0;         // Gold-like asset
        else if(curr > 100) step = 1.0;
        else if(curr > 1) step = 0.01;
        
        double search_range = m_atr_value * 10.0;
        double base = MathFloor(curr / step) * step;
        
        for(double lvl = base - step * 5; lvl <= base + step * 5; lvl += step)
        {
            if(MathAbs(lvl - curr) < search_range && m_level_count < 50)
                _AddLevel(lvl, false, true);
        }
    }
    
    //--- Add level to array, merge if close to existing
    void _AddLevel(double price, bool is_swing, bool is_round)
    {
        if(m_level_count >= 50) return;
        
        double zone_size = m_atr_value * m_zone_pct;
        
        // Merge if close to existing level
        for(int i = 0; i < m_level_count; i++)
        {
            if(MathAbs(m_levels[i].price - price) < zone_size)
            {
                m_levels[i].touches++;
                m_levels[i].strength = MathMin(1.0, m_levels[i].strength + 0.2);
                if(is_round) m_levels[i].is_round = true;
                if(is_swing) m_levels[i].is_swing = true;
                return;
            }
        }
        
        // New level
        m_levels[m_level_count].price    = price;
        m_levels[m_level_count].touches  = 1;
        m_levels[m_level_count].is_swing = is_swing;
        m_levels[m_level_count].is_round = is_round;
        // Base strength: round numbers slightly stronger by default
        m_levels[m_level_count].strength = is_round ? 0.7 : 0.5;
        m_level_count++;
    }
};

#endif // KEYLEVEL_FINDER_MQH
//+------------------------------------------------------------------+
