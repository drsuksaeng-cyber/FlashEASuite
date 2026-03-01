//+------------------------------------------------------------------+
//| MM17_RegimeBased.mqh                                             |
//| FlashEASuite V2 — Money Management Method 17                     |
//| Regime-Based Scaling: ปรับ Lot ตาม Market Regime                 |
//|   TRENDING  → 1.5× base risk (เทรนด์ชัด เพิ่ม risk)             |
//|   RANGING   → 1.0× base risk (ตลาดปกติ)                         |
//|   VOLATILE  → 0.3× base risk (ตลาดผันผวน ลด risk 70%)           |
//|   CRISIS    → 0.0× base risk (หยุดเทรด)                          |
//| Usage:                                                           |
//|   mm17.Setup("XAUUSD.tp");                                       |
//|   mm17.SetRegime(REGIME_TRENDING);  // update from server/detect |
//|   double lot = mm17.CalculateLot(balance, equity, sl, symbol);   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM17_REGIMEBASED_MQH
#define MM17_REGIMEBASED_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| ENUM: Market Regime (defined here, guarded for reuse)            |
//+------------------------------------------------------------------+
#ifndef ENUM_MARKET_REGIME_DEFINED
#define ENUM_MARKET_REGIME_DEFINED
enum ENUM_MARKET_REGIME
{
    REGIME_UNKNOWN  = 0,    // Not yet classified
    REGIME_TRENDING = 1,    // Clear directional trend
    REGIME_RANGING  = 2,    // Sideways / mean-reverting
    REGIME_VOLATILE = 3,    // High-volatility / choppy
    REGIME_CRISIS   = 4     // Extreme volatility / stop trading
};
#endif

//+------------------------------------------------------------------+
//| CLASS: CMM17_RegimeBased                                         |
//+------------------------------------------------------------------+
class CMM17_RegimeBased : public IMoneyManager
{
private:
    //--- Parameters
    double  m_trending_mult;    // Risk multiplier for TRENDING (default 1.5)
    double  m_ranging_mult;     // Risk multiplier for RANGING (default 1.0)
    double  m_volatile_mult;    // Risk multiplier for VOLATILE (default 0.3)
    double  m_crisis_mult;      // Risk multiplier for CRISIS (default 0.0)
    double  m_base_risk_pct;    // Base risk % (default 1.0%)
    int     m_confirm_bars;     // Bars required to confirm regime change (anti-whipsaw)

    //--- State
    ENUM_MARKET_REGIME  m_current_regime;       // Active regime
    ENUM_MARKET_REGIME  m_pending_regime;        // Regime awaiting confirmation
    int                 m_pending_count;         // Bars seen with pending regime
    double              m_active_multiplier;     // Current risk multiplier

    //+--------------------------------------------------------------+
    //| UpdateMultiplier: set m_active_multiplier from current regime |
    //+--------------------------------------------------------------+
    void UpdateMultiplier()
    {
        switch(m_current_regime)
        {
            case REGIME_TRENDING: m_active_multiplier = m_trending_mult; break;
            case REGIME_RANGING:  m_active_multiplier = m_ranging_mult;  break;
            case REGIME_VOLATILE: m_active_multiplier = m_volatile_mult; break;
            case REGIME_CRISIS:   m_active_multiplier = m_crisis_mult;   break;
            default:              m_active_multiplier = m_ranging_mult;  break; // UNKNOWN → neutral
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM17_RegimeBased()
    {
        m_trending_mult    = 1.5;
        m_ranging_mult     = 1.0;
        m_volatile_mult    = 0.3;
        m_crisis_mult      = 0.0;
        m_base_risk_pct    = 1.0;
        m_confirm_bars     = 3;
        m_current_regime   = REGIME_RANGING;
        m_pending_regime   = REGIME_RANGING;
        m_pending_count    = 0;
        m_active_multiplier= 1.0;
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        m_current_regime    = REGIME_RANGING;
        m_pending_regime    = REGIME_RANGING;
        m_pending_count     = 0;
        m_active_multiplier = m_ranging_mult;
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 17; }
    virtual string GetName() override { return "MM17_RegimeBased"; }

    //+--------------------------------------------------------------+
    //| SetParams: Override default multipliers                      |
    //+--------------------------------------------------------------+
    void SetParams(double trending_mult = 1.5,
                   double ranging_mult  = 1.0,
                   double volatile_mult = 0.3,
                   double crisis_mult   = 0.0,
                   double base_risk_pct = 1.0,
                   int    confirm_bars  = 3)
    {
        m_trending_mult = MathMax(0.5, MathMin(2.5, trending_mult));
        m_ranging_mult  = MathMax(0.5, MathMin(1.5, ranging_mult));
        m_volatile_mult = MathMax(0.1, MathMin(0.7, volatile_mult));
        m_crisis_mult   = MathMax(0.0, MathMin(0.3, crisis_mult));
        m_base_risk_pct = MathMax(0.1, MathMin(5.0, base_risk_pct));
        m_confirm_bars  = MathMax(1,   MathMin(5,   confirm_bars));
        UpdateMultiplier();
    }

    //+--------------------------------------------------------------+
    //| SetRegime: Update market regime (with anti-whipsaw filter)   |
    //| Call this each bar from server CONFIG_PUSH or local detector |
    //+--------------------------------------------------------------+
    void SetRegime(ENUM_MARKET_REGIME regime)
    {
        if(regime == m_current_regime)
        {
            // Same regime → reset pending
            m_pending_regime = regime;
            m_pending_count  = 0;
            return;
        }

        // Different regime → accumulate confirmation
        if(regime == m_pending_regime)
        {
            m_pending_count++;
            if(m_pending_count >= m_confirm_bars)
            {
                // Confirmed → switch
                m_current_regime = regime;
                m_pending_count  = 0;
                UpdateMultiplier();
            }
        }
        else
        {
            // New different regime → restart confirmation
            m_pending_regime = regime;
            m_pending_count  = 1;
        }
    }

    //+--------------------------------------------------------------+
    //| SetRegimeDirect: Force regime change immediately (no filter) |
    //| Use when CONFIG_PUSH from server overrides local detection   |
    //+--------------------------------------------------------------+
    void SetRegimeDirect(ENUM_MARKET_REGIME regime)
    {
        m_current_regime    = regime;
        m_pending_regime    = regime;
        m_pending_count     = 0;
        UpdateMultiplier();
    }

    //+--------------------------------------------------------------+
    //| GetCurrentRegime / GetActiveMultiplier                       |
    //+--------------------------------------------------------------+
    ENUM_MARKET_REGIME GetCurrentRegime()   { return m_current_regime;   }
    double             GetActiveMultiplier() { return m_active_multiplier; }

    //+--------------------------------------------------------------+
    //| CalculateLot: Regime-scaled lot sizing                       |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // CRISIS: return minimum lot (signal to not trade)
        double vol_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(m_current_regime == REGIME_CRISIS) return vol_min;

        // Apply regime multiplier + server risk multiplier
        double effective_mult = m_active_multiplier * m_risk_multiplier;
        double risk_pct       = m_base_risk_pct * effective_mult;
        risk_pct = MathMax(0.1, MathMin(5.0, risk_pct));

        // Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
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
        string regime_names[] = {"UNKNOWN", "TRENDING", "RANGING", "VOLATILE", "CRISIS"};
        int idx = (int)m_current_regime;
        string rname = (idx >= 0 && idx <= 4) ? regime_names[idx] : "UNKNOWN";

        PrintFormat("[MM17] Regime=%s | Multiplier=%.2f× | BaseRisk=%.2f%% | EffectiveRisk=%.2f%% | PendingBars=%d",
            rname, m_active_multiplier, m_base_risk_pct,
            m_base_risk_pct * m_active_multiplier,
            m_pending_count);
    }
};

#endif // MM17_REGIMEBASED_MQH
//+------------------------------------------------------------------+
