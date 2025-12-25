//+------------------------------------------------------------------+
//|                                    Grid/MarketAnalysis.mqh       |
//|                                    FlashEASuite V2 - Week 3      |
//|                         Enhanced Market Condition Analysis        |
//+------------------------------------------------------------------+
#property strict

// ENUM_MARKET_STATE is defined in GridConfig.mqh
// This file assumes GridConfig.mqh is included before this file

//+------------------------------------------------------------------+
//| Market Analysis Structure                                        |
//+------------------------------------------------------------------+
struct MarketCondition
{
    ENUM_MARKET_STATE   state;           // Current market state
    double              trend_strength;   // 0.0-1.0 (0=range, 1=strong trend)
    double              volatility;       // Current volatility (ATR-based)
    double              spread_normal;    // Current spread / average spread
    bool                is_tradeable;     // Overall tradeable condition
    string              reason;           // Why tradeable or not
};

//+------------------------------------------------------------------+
//| Class: CMarketAnalysis                                           |
//| Analyzes market conditions for Grid strategy                     |
//+------------------------------------------------------------------+
class CMarketAnalysis
{
private:
    // Indicator handles (assume already in GridConfig)
    int               m_atr_handle;
    int               m_adx_handle;
    int               m_ma_fast_handle;
    int               m_ma_slow_handle;
    
    // Thresholds
    double            m_trend_threshold;      // ADX > 25 = trending
    double            m_volatile_threshold;   // ATR ratio > 1.5 = volatile
    double            m_spread_max_ratio;     // Max spread = 2.0x normal
    
    // Historical data
    double            m_avg_spread;           // Average spread (updated)
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CMarketAnalysis()
    {
        m_atr_handle = INVALID_HANDLE;
        m_adx_handle = INVALID_HANDLE;
        m_ma_fast_handle = INVALID_HANDLE;
        m_ma_slow_handle = INVALID_HANDLE;
        
        m_trend_threshold = 25.0;
        m_volatile_threshold = 1.5;
        m_spread_max_ratio = 2.0;
        m_avg_spread = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize with handles from GridConfig                         |
    //+------------------------------------------------------------------+
    void Initialize(int atr_handle, int adx_handle, int ma_fast, int ma_slow)
    {
        m_atr_handle = atr_handle;
        m_adx_handle = adx_handle;
        m_ma_fast_handle = ma_fast;
        m_ma_slow_handle = ma_slow;
        
        // Calculate initial average spread
        UpdateAverageSpread();
    }
    
    //+------------------------------------------------------------------+
    //| Main Analysis Function                                          |
    //+------------------------------------------------------------------+
    MarketCondition AnalyzeMarket()
    {
        MarketCondition condition;
        condition.is_tradeable = true;
        condition.reason = "OK";
        
        // 1. Get current spread
        double current_spread = GetCurrentSpread();
        condition.spread_normal = (m_avg_spread > 0) ? current_spread / m_avg_spread : 1.0;
        
        // Check spread filter
        if(condition.spread_normal > m_spread_max_ratio)
        {
            condition.is_tradeable = false;
            condition.reason = "Spread too high";
            return condition;
        }
        
        // 2. Analyze trend (ADX + MA)
        double adx_value = GetADXValue();
        double ma_distance = GetMADistance();
        
        // 3. Check volatility
        double atr_ratio = GetATRRatio();
        condition.volatility = atr_ratio;
        
        // Determine market state based on ADX and ATR
        if(adx_value < 20.0)
        {
            // Ranging market
            if(atr_ratio > m_volatile_threshold)
            {
                condition.state = MARKET_STATE_RANGING_HIGH_VOL;
                condition.is_tradeable = false;
                condition.reason = "High volatility ranging";
            }
            else
            {
                condition.state = MARKET_STATE_RANGING_NORMAL;
                condition.is_tradeable = true;
                condition.reason = "Ideal ranging market";
            }
            condition.trend_strength = 0.0;
        }
        else if(adx_value < 30.0)
        {
            // Weak trend - OK for grid
            condition.state = MARKET_STATE_TRENDING_WEAK;
            condition.trend_strength = adx_value / 30.0;
            condition.is_tradeable = true;
            condition.reason = "Weak trend - acceptable";
        }
        else
        {
            // Strong trend - avoid grid
            condition.state = MARKET_STATE_TRENDING_STRONG;
            condition.trend_strength = MathMin(adx_value / 50.0, 1.0);
            condition.is_tradeable = false;
            condition.reason = "Strong trend - avoid grid";
        }
        
        return condition;
    }
    
    //+------------------------------------------------------------------+
    //| Check if market is suitable for Grid                            |
    //+------------------------------------------------------------------+
    bool IsGridFriendly()
    {
        MarketCondition condition = AnalyzeMarket();
        
        // Grid works best in ranging normal markets
        if(condition.state == MARKET_STATE_RANGING_NORMAL && condition.is_tradeable)
            return true;
            
        // Can also work in weak trends
        if(condition.state == MARKET_STATE_TRENDING_WEAK && condition.is_tradeable)
            return true;
            
        return false;
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
    //| Update Average Spread                                           |
    //+------------------------------------------------------------------+
    void UpdateAverageSpread()
    {
        double current = GetCurrentSpread();
        
        if(m_avg_spread == 0.0)
        {
            m_avg_spread = current;
        }
        else
        {
            // Exponential moving average
            m_avg_spread = m_avg_spread * 0.95 + current * 0.05;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get ADX Value                                                   |
    //+------------------------------------------------------------------+
    double GetADXValue()
    {
        if(m_adx_handle == INVALID_HANDLE)
            return 0.0;
            
        double adx_buffer[1];
        if(CopyBuffer(m_adx_handle, 0, 0, 1, adx_buffer) <= 0)
            return 0.0;
            
        return adx_buffer[0];
    }
    
    //+------------------------------------------------------------------+
    //| Get MA Distance (MA_Fast - MA_Slow)                            |
    //+------------------------------------------------------------------+
    double GetMADistance()
    {
        if(m_ma_fast_handle == INVALID_HANDLE || m_ma_slow_handle == INVALID_HANDLE)
            return 0.0;
            
        double ma_fast[1], ma_slow[1];
        
        if(CopyBuffer(m_ma_fast_handle, 0, 0, 1, ma_fast) <= 0)
            return 0.0;
        if(CopyBuffer(m_ma_slow_handle, 0, 0, 1, ma_slow) <= 0)
            return 0.0;
            
        return (ma_fast[0] - ma_slow[0]) / _Point;
    }
    
    //+------------------------------------------------------------------+
    //| Get ATR Ratio (Current / Reference)                            |
    //+------------------------------------------------------------------+
    double GetATRRatio()
    {
        if(m_atr_handle == INVALID_HANDLE)
            return 1.0;
            
        double atr_buffer[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
            return 1.0;
            
        double atr_current = atr_buffer[0] / _Point;
        
        // Assume reference ATR = 30 (from GridConfig)
        double atr_reference = 30.0;
        
        return atr_current / atr_reference;
    }
};
//+------------------------------------------------------------------+
