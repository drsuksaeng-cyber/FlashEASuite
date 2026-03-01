//+------------------------------------------------------------------+
//| MM14_TieredRisk.mqh                                              |
//| FlashEASuite V2 — Money Management Method 14                     |
//| Tiered Risk: ปรับ Risk% ตามขนาด Balance                          |
//|   Balance < $1,000    → 2.0% (High risk for small accounts)      |
//|   $1,000 - $10,000   → 1.5% (Moderate)                          |
//|   > $10,000          → 1.0% (Conservative for large accounts)    |
//| Logic: Account ขนาดเล็กต้องโตเร็ว, ขนาดใหญ่ต้องรักษาทุน         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM14_TIEREDRISK_MQH
#define MM14_TIEREDRISK_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| Enum: Balance tier                                               |
//+------------------------------------------------------------------+
enum ENUM_BALANCE_TIER
{
    BALANCE_TIER_SMALL  = 0,    // < threshold_low (e.g. $1,000)
    BALANCE_TIER_MEDIUM = 1,    // threshold_low to threshold_high
    BALANCE_TIER_LARGE  = 2     // > threshold_high (e.g. $10,000)
};

//+------------------------------------------------------------------+
//| CLASS: CMM14_TieredRisk                                          |
//+------------------------------------------------------------------+
class CMM14_TieredRisk : public IMoneyManager
{
private:
    // Tier thresholds
    double  m_threshold_low;        // Balance below this → small tier
    double  m_threshold_high;       // Balance above this → large tier

    // Risk % per tier
    double  m_risk_pct_small;       // Small account: aggressive (default 2%)
    double  m_risk_pct_medium;      // Medium account: moderate (default 1.5%)
    double  m_risk_pct_large;       // Large account: conservative (default 1%)

    //+--------------------------------------------------------------+
    //| GetTier: Classify balance into tier                          |
    //+--------------------------------------------------------------+
    ENUM_BALANCE_TIER GetTier(double balance)
    {
        if(balance < m_threshold_low)  return BALANCE_TIER_SMALL;
        if(balance < m_threshold_high) return BALANCE_TIER_MEDIUM;
        return BALANCE_TIER_LARGE;
    }

    //+--------------------------------------------------------------+
    //| GetTierRiskPct: Return risk % for current balance            |
    //+--------------------------------------------------------------+
    double GetTierRiskPct(double balance)
    {
        switch(GetTier(balance))
        {
            case BALANCE_TIER_SMALL:  return m_risk_pct_small;
            case BALANCE_TIER_MEDIUM: return m_risk_pct_medium;
            case BALANCE_TIER_LARGE:  return m_risk_pct_large;
            default:                  return m_risk_pct_medium;
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM14_TieredRisk()
    {
        m_threshold_low   = 1000.0;
        m_threshold_high  = 10000.0;
        m_risk_pct_small  = 2.0;
        m_risk_pct_medium = 1.5;
        m_risk_pct_large  = 1.0;
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 14; }
    virtual string GetName() override { return "MM14_TieredRisk"; }

    //+--------------------------------------------------------------+
    //| SetParams: Customize tier thresholds and risk percentages    |
    //+--------------------------------------------------------------+
    void SetParams(double threshold_low, double threshold_high,
                   double risk_small, double risk_medium, double risk_large)
    {
        m_threshold_low   = MathMax(100.0, threshold_low);
        m_threshold_high  = MathMax(m_threshold_low + 100.0, threshold_high);
        m_risk_pct_small  = MathMax(0.1, MathMin(10.0, risk_small));
        m_risk_pct_medium = MathMax(0.1, MathMin(10.0, risk_medium));
        m_risk_pct_large  = MathMax(0.1, MathMin(10.0, risk_large));
    }

    //+--------------------------------------------------------------+
    //| GetCurrentTier: Expose for diagnostics                       |
    //+--------------------------------------------------------------+
    ENUM_BALANCE_TIER GetCurrentTier(double balance) { return GetTier(balance); }

    //+--------------------------------------------------------------+
    //| CalculateLot: Tiered risk sizing                             |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // --- Get risk % for this balance tier
        double risk_pct = GetTierRiskPct(balance);

        // --- Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        // --- SL distance
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        // --- Lot calculation
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
    void PrintDiagnostics(double balance)
    {
        ENUM_BALANCE_TIER tier = GetTier(balance);
        string tier_names[]    = {"SMALL","MEDIUM","LARGE"};
        double risk = GetTierRiskPct(balance);

        PrintFormat("[MM14] Balance=%.2f | Tier=%s | Risk=%.2f%% | Thresholds=[<%.0f / %.0f-%.0f / >%.0f]",
            balance, tier_names[(int)tier], risk,
            m_threshold_low, m_threshold_low, m_threshold_high, m_threshold_high);
    }
};

#endif // MM14_TIEREDRISK_MQH
//+------------------------------------------------------------------+
