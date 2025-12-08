//+------------------------------------------------------------------+
//|                                    GridStandalone/MarketAnalysis.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                           Market Analysis Engine Module                  |
//+------------------------------------------------------------------+
#property strict

#include "GridConfig.mqh"

//+------------------------------------------------------------------+
//| Internal Currency Strength Meter (Simplified)                    |
//+------------------------------------------------------------------+
class CCurrencyStrengthInternal
{
private:
    double m_strength_usd;
    double m_strength_eur;
    double m_strength_gbp;
    double m_strength_jpy;
    
public:
    CCurrencyStrengthInternal()
    {
        m_strength_usd = 5.0;
        m_strength_eur = 5.0;
        m_strength_gbp = 5.0;
        m_strength_jpy = 5.0;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Currency Strength (Simplified RSI-based)               |
    //+------------------------------------------------------------------+
    void Calculate()
    {
        // For EURUSD: Calculate EUR and USD strength
        // Using RSI as proxy for strength
        
        // EUR strength from EURUSD
        int rsi_eurusd = iRSI("EURUSD", PERIOD_M15, 14, PRICE_CLOSE);
        double rsi_eur[1];
        if(rsi_eurusd != INVALID_HANDLE && CopyBuffer(rsi_eurusd, 0, 0, 1, rsi_eur) > 0)
        {
            m_strength_eur = rsi_eur[0] / 10.0;  // Scale to 0-10
        }
        
        // USD strength (inverse of EUR)
        m_strength_usd = 10.0 - m_strength_eur;
        
        // GBP strength from GBPUSD
        int rsi_gbpusd = iRSI("GBPUSD", PERIOD_M15, 14, PRICE_CLOSE);
        double rsi_gbp[1];
        if(rsi_gbpusd != INVALID_HANDLE && CopyBuffer(rsi_gbpusd, 0, 0, 1, rsi_gbp) > 0)
        {
            m_strength_gbp = rsi_gbp[0] / 10.0;
        }
        
        // JPY strength from USDJPY (inverse)
        int rsi_usdjpy = iRSI("USDJPY", PERIOD_M15, 14, PRICE_CLOSE);
        double rsi_jpy[1];
        if(rsi_usdjpy != INVALID_HANDLE && CopyBuffer(rsi_usdjpy, 0, 0, 1, rsi_jpy) > 0)
        {
            m_strength_jpy = 10.0 - (rsi_jpy[0] / 10.0);
        }
        
        // Release handles
        if(rsi_eurusd != INVALID_HANDLE) IndicatorRelease(rsi_eurusd);
        if(rsi_gbpusd != INVALID_HANDLE) IndicatorRelease(rsi_gbpusd);
        if(rsi_usdjpy != INVALID_HANDLE) IndicatorRelease(rsi_usdjpy);
    }
    
    double GetStrength(string currency)
    {
        if(currency == "USD") return m_strength_usd;
        if(currency == "EUR") return m_strength_eur;
        if(currency == "GBP") return m_strength_gbp;
        if(currency == "JPY") return m_strength_jpy;
        return 5.0;  // Neutral
    }
};

//+------------------------------------------------------------------+
//| Market Analysis Engine                                            |
//+------------------------------------------------------------------+
class CMarketAnalysisEngine : public CGridConfig
{
protected:
    // Made protected so derived classes can access
    CCurrencyStrengthInternal m_csm;
    
    // Analysis results
    bool              m_is_trending;
    bool              m_is_ranging;
    bool              m_is_high_volatility;
    double            m_volatility_ratio;
    double            m_market_confidence;
    
    // Support/Resistance (simplified)
    double            m_nearest_support;
    double            m_nearest_resistance;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CMarketAnalysisEngine() : CGridConfig()
    {
        m_is_trending = false;
        m_is_ranging = false;
        m_is_high_volatility = false;
        m_volatility_ratio = 1.0;
        m_market_confidence = 0.0;
        m_nearest_support = 0.0;
        m_nearest_resistance = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Main Analysis Function                                           |
    //+------------------------------------------------------------------+
    bool AnalyzeMarket()
    {
        // Update ATR
        UpdateATR();
        
        // Determine market state
        DetermineMarketState();
        
        // Calculate support/resistance
        CalculateSupportResistance();
        
        // Update CSM
        m_csm.Calculate();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update ATR                                                        |
    //+------------------------------------------------------------------+
    void UpdateATR()
    {
        double atr[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr) > 0)
        {
            m_atr_current = atr[0] / _Point;
            m_volatility_ratio = m_atr_current / m_atr_reference;
        }
        else
        {
            m_atr_current = m_atr_reference;
            m_volatility_ratio = 1.0;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Determine Market State                                           |
    //+------------------------------------------------------------------+
    void DetermineMarketState()
    {
        double adx[1];
        if(CopyBuffer(m_adx_handle, 0, 0, 1, adx) <= 0)
        {
            m_current_market_state = MARKET_STATE_UNDEFINED;
            return;
        }
        
        double adx_value = adx[0];
        
        // Check volatility
        if(m_volatility_ratio > 1.5)
        {
            m_is_high_volatility = true;
        }
        else
        {
            m_is_high_volatility = false;
        }
        
        // Determine state based on ADX and volatility
        if(adx_value < 20)
        {
            // Ranging market
            m_is_ranging = true;
            m_is_trending = false;
            
            if(m_is_high_volatility)
            {
                m_current_market_state = MARKET_STATE_RANGING_HIGH_VOL;
            }
            else
            {
                m_current_market_state = MARKET_STATE_RANGING_NORMAL;
            }
        }
        else if(adx_value >= 20 && adx_value < 30)
        {
            // Weak trend
            m_is_trending = true;
            m_is_ranging = false;
            m_current_market_state = MARKET_STATE_TRENDING_WEAK;
        }
        else  // ADX >= 30
        {
            // Strong trend
            m_is_trending = true;
            m_is_ranging = false;
            m_current_market_state = MARKET_STATE_TRENDING_STRONG;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Support/Resistance (Simplified)                        |
    //+------------------------------------------------------------------+
    void CalculateSupportResistance()
    {
        // Get recent high/low
        double high[], low[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        
        if(CopyHigh(_Symbol, PERIOD_M15, 0, 20, high) > 0 &&
           CopyLow(_Symbol, PERIOD_M15, 0, 20, low) > 0)
        {
            // Find recent swing high (resistance)
            m_nearest_resistance = high[ArrayMaximum(high, 0, 20)];
            
            // Find recent swing low (support)
            m_nearest_support = low[ArrayMinimum(low, 0, 20)];
        }
    }
    
    //+------------------------------------------------------------------+
    //| Count BUY Signals                                                 |
    //+------------------------------------------------------------------+
    int CountBuySignals()
    {
        int signals = 0;
        
        // Signal 1: MA Trend
        double ma_fast[1], ma_slow[1];
        if(CopyBuffer(m_ma_fast_handle, 0, 0, 1, ma_fast) > 0 &&
           CopyBuffer(m_ma_slow_handle, 0, 0, 1, ma_slow) > 0)
        {
            if(ma_fast[0] > ma_slow[0])
                signals++;  // Uptrend
        }
        
        // Signal 2: RSI
        double rsi[1];
        if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) > 0)
        {
            if(rsi[0] > 25 && rsi[0] < 45)
                signals++;  // Good zone for BUY
        }
        
        // Signal 3: Price near support
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double distance = (current_price - m_nearest_support) / _Point;
        
        if(distance < 200)
            signals++;
        
        // Signal 4: Internal CSM
        string base_currency = StringSubstr(_Symbol, 0, 3);
        string quote_currency = StringSubstr(_Symbol, 3, 3);
        
        double base_strength = m_csm.GetStrength(base_currency);
        double quote_strength = m_csm.GetStrength(quote_currency);
        
        if(base_strength > quote_strength + 0.5)
            signals++;
        
        // Signal 5: Volatility normal
        if(m_volatility_ratio > 0.8 && m_volatility_ratio < 1.3)
            signals++;
        
        // Signal 6: Python CSM (if available)
        if(m_python_connected)
        {
            // This will be set by Python policy update
            // For now, just check if Python agrees
            signals++;  // Bonus signal
        }
        
        return signals;
    }
    
    //+------------------------------------------------------------------+
    //| Count SELL Signals                                                |
    //+------------------------------------------------------------------+
    int CountSellSignals()
    {
        int signals = 0;
        
        // Signal 1: MA Trend
        double ma_fast[1], ma_slow[1];
        if(CopyBuffer(m_ma_fast_handle, 0, 0, 1, ma_fast) > 0 &&
           CopyBuffer(m_ma_slow_handle, 0, 0, 1, ma_slow) > 0)
        {
            if(ma_fast[0] < ma_slow[0])
                signals++;  // Downtrend
        }
        
        // Signal 2: RSI
        double rsi[1];
        if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) > 0)
        {
            if(rsi[0] > 55 && rsi[0] < 75)
                signals++;  // Good zone for SELL
        }
        
        // Signal 3: Price near resistance
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double distance = (m_nearest_resistance - current_price) / _Point;
        
        if(distance < 200)
            signals++;
        
        // Signal 4: Internal CSM
        string base_currency = StringSubstr(_Symbol, 0, 3);
        string quote_currency = StringSubstr(_Symbol, 3, 3);
        
        double base_strength = m_csm.GetStrength(base_currency);
        double quote_strength = m_csm.GetStrength(quote_currency);
        
        if(quote_strength > base_strength + 0.5)
            signals++;
        
        // Signal 5: Volatility normal
        if(m_volatility_ratio > 0.8 && m_volatility_ratio < 1.3)
            signals++;
        
        // Signal 6: Python CSM (if available)
        if(m_python_connected)
        {
            signals++;  // Bonus signal
        }
        
        return signals;
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    bool IsTrending() { return m_is_trending; }
    bool IsRanging() { return m_is_ranging; }
    bool IsHighVolatility() { return m_is_high_volatility; }
    double GetVolatilityRatio() { return m_volatility_ratio; }
    double GetNearestSupport() { return m_nearest_support; }
    double GetNearestResistance() { return m_nearest_resistance; }
    double GetMarketConfidence() { return m_market_confidence; }
};
//+------------------------------------------------------------------+
