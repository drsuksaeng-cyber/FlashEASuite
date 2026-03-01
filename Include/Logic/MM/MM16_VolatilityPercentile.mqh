//+------------------------------------------------------------------+
//| MM16_VolatilityPercentile.mqh                                    |
//| FlashEASuite V2 — Money Management Method 16                     |
//| Volatility Percentile: rank current ATR in N-bar history         |
//|   - เก็บ ATR history 100 bars (configurable)                     |
//|   - ถ้า current ATR > HIGH_VOL_PERCENTILE (80th) → ลด lot 50%   |
//|   - ถ้า current ATR < LOW_VOL_PERCENTILE (20th) → เพิ่ม lot 20% |
//|   - ช่วงกลาง (20th-80th) → ใช้ lot ปกติ                         |
//| Usage:                                                           |
//|   mm16.Setup("XAUUSD.tp");                                       |
//|   mm16.UpdateVolatility(atr_value);  // call each bar/tick       |
//|   double lot = mm16.CalculateLot(balance, equity, sl, symbol);   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM16_VOLATILITYPERCENTILE_MQH
#define MM16_VOLATILITYPERCENTILE_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| CLASS: CMM16_VolatilityPercentile                                |
//+------------------------------------------------------------------+
class CMM16_VolatilityPercentile : public IMoneyManager
{
private:
    //--- Parameters
    int     m_vol_lookback;         // ATR history size (default 100)
    int     m_high_vol_percentile;  // High vol threshold (default 80)
    int     m_low_vol_percentile;   // Low vol threshold (default 20)
    double  m_high_vol_reduce_pct;  // Reduce % when high vol (default 50%)
    double  m_low_vol_boost_pct;    // Boost % when low vol (default 20%)
    double  m_base_risk_pct;        // Base risk % (default 1%)

    //--- History buffer (circular)
    double  m_vol_history[];        // ATR history values
    int     m_history_count;        // Items stored so far
    int     m_history_head;         // Circular buffer head index
    double  m_last_atr;             // Most recent ATR fed in

    //--- State
    int     m_current_percentile;   // Last computed percentile (0-100)

    //+--------------------------------------------------------------+
    //| ComputePercentile: rank m_last_atr in history                |
    //| Returns 0-100 where 100 = highest vol in history            |
    //+--------------------------------------------------------------+
    int ComputePercentile()
    {
        if(m_history_count < 2) return 50; // not enough data → neutral

        int n = MathMin(m_history_count, m_vol_lookback);
        int count_below = 0;
        for(int i = 0; i < n; i++)
        {
            if(m_vol_history[i] < m_last_atr)
                count_below++;
        }
        return (int)MathRound((double)count_below / (double)n * 100.0);
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM16_VolatilityPercentile()
    {
        m_vol_lookback         = 100;
        m_high_vol_percentile  = 80;
        m_low_vol_percentile   = 20;
        m_high_vol_reduce_pct  = 50.0;
        m_low_vol_boost_pct    = 20.0;
        m_base_risk_pct        = 1.0;
        m_history_count        = 0;
        m_history_head         = 0;
        m_last_atr             = 0.0;
        m_current_percentile   = 50;
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 100) override
    {
        IMoneyManager::Setup(symbol, history_window);
        m_vol_lookback  = (history_window > 0) ? history_window : 100;
        ArrayResize(m_vol_history, m_vol_lookback);
        // Initialize array with loop (string[] rule — also for safety)
        for(int i = 0; i < m_vol_lookback; i++)
            m_vol_history[i] = 0.0;
        m_history_count      = 0;
        m_history_head       = 0;
        m_last_atr           = 0.0;
        m_current_percentile = 50;
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 16; }
    virtual string GetName() override { return "MM16_VolatilityPercentile"; }

    //+--------------------------------------------------------------+
    //| SetParams: Configure thresholds and risk levels              |
    //+--------------------------------------------------------------+
    void SetParams(int  lookback           = 100,
                   int  high_percentile    = 80,
                   int  low_percentile     = 20,
                   double high_reduce_pct  = 50.0,
                   double low_boost_pct    = 20.0,
                   double base_risk_pct    = 1.0)
    {
        m_vol_lookback        = MathMax(10, MathMin(500, lookback));
        m_high_vol_percentile = MathMax(50, MathMin(99, high_percentile));
        m_low_vol_percentile  = MathMax(1,  MathMin(49, low_percentile));
        m_high_vol_reduce_pct = MathMax(10.0, MathMin(90.0, high_reduce_pct));
        m_low_vol_boost_pct   = MathMax(0.0,  MathMin(50.0, low_boost_pct));
        m_base_risk_pct       = MathMax(0.1,  MathMin(5.0,  base_risk_pct));

        // Resize history buffer if lookback changed
        ArrayResize(m_vol_history, m_vol_lookback);
        for(int i = 0; i < m_vol_lookback; i++)
            m_vol_history[i] = 0.0;
        m_history_count = 0;
        m_history_head  = 0;
    }

    //+--------------------------------------------------------------+
    //| UpdateVolatility: Feed new ATR value (call each bar/tick)   |
    //| @param atr_value  Current ATR in price units                 |
    //+--------------------------------------------------------------+
    void UpdateVolatility(double atr_value)
    {
        if(atr_value <= 0.0) return;
        m_last_atr = atr_value;

        // Circular buffer insert
        m_vol_history[m_history_head] = atr_value;
        m_history_head = (m_history_head + 1) % m_vol_lookback;
        if(m_history_count < m_vol_lookback) m_history_count++;

        // Update percentile rank
        m_current_percentile = ComputePercentile();
    }

    //+--------------------------------------------------------------+
    //| GetCurrentPercentile: 0-100 percentile rank of last ATR     |
    //+--------------------------------------------------------------+
    int GetCurrentPercentile() { return m_current_percentile; }

    //+--------------------------------------------------------------+
    //| CalculateLot: Percentile-adjusted lot sizing                 |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // Determine risk adjustment based on percentile
        double risk_pct = m_base_risk_pct * m_risk_multiplier;

        if(m_current_percentile >= m_high_vol_percentile)
        {
            // High volatility → reduce lot
            double reduce_factor = 1.0 - (m_high_vol_reduce_pct / 100.0);
            risk_pct *= reduce_factor;
        }
        else if(m_current_percentile <= m_low_vol_percentile)
        {
            // Low volatility → slight boost
            double boost_factor = 1.0 + (m_low_vol_boost_pct / 100.0);
            risk_pct *= boost_factor;
        }
        // else: mid range → no adjustment

        // Clamp risk
        risk_pct = MathMax(0.1, MathMin(5.0, risk_pct));

        // Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        double risk_amount = balance * (risk_pct / 100.0);
        double sl_ticks    = sl_distance / tick_size;
        double sl_currency = sl_ticks * tick_value;
        if(sl_currency <= 0.0) return vol_min;

        double lot = risk_amount / sl_currency;
        lot = MathMax(vol_min, MathMin(vol_max, lot));
        lot = MathRound(lot / vol_step) * vol_step;
        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Diagnostics                                                  |
    //+--------------------------------------------------------------+
    void PrintDiagnostics()
    {
        string zone = "NORMAL";
        if(m_current_percentile >= m_high_vol_percentile) zone = "HIGH_VOL(REDUCE)";
        else if(m_current_percentile <= m_low_vol_percentile) zone = "LOW_VOL(BOOST)";

        PrintFormat("[MM16] Percentile=%d | Zone=%s | History=%d/%d | LastATR=%.5f | BaseRisk=%.2f%%",
            m_current_percentile, zone, m_history_count, m_vol_lookback,
            m_last_atr, m_base_risk_pct);
    }
};

#endif // MM16_VOLATILITYPERCENTILE_MQH
//+------------------------------------------------------------------+
