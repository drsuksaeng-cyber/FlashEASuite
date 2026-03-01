//+------------------------------------------------------------------+
//| MM11_SessionBased.mqh                                            |
//| FlashEASuite V2 — Money Management Method 11                     |
//| Session-Based: ปรับ Risk% ตาม Trading Session                   |
//|   London  08:00-16:00 GMT → 1.5%                                |
//|   New York 13:00-21:00 GMT → 1.2%                               |
//|   London+NY Overlap 13:00-16:00 GMT → 2.0% (highest liquidity)  |
//|   Asian   00:00-08:00 GMT → 0.5%                                |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM11_SESSIONBASED_MQH
#define MM11_SESSIONBASED_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| Enum: Trading Session                                            |
//+------------------------------------------------------------------+
enum ENUM_SESSION_MM11
{
    SESSION_MM11_ASIAN   = 0,   // 00:00-08:00 GMT (low vol)
    SESSION_MM11_LONDON  = 1,   // 08:00-13:00 GMT
    SESSION_MM11_OVERLAP = 2,   // 13:00-16:00 GMT (London+NY)
    SESSION_MM11_NY      = 3,   // 16:00-21:00 GMT
    SESSION_MM11_DEAD    = 4    // 21:00-00:00 GMT (no trade)
};

//+------------------------------------------------------------------+
//| CLASS: CMM11_SessionBased                                        |
//+------------------------------------------------------------------+
class CMM11_SessionBased : public IMoneyManager
{
private:
    // Session risk parameters (%)
    double  m_london_risk_pct;      // Risk% for London session
    double  m_ny_risk_pct;          // Risk% for NY session
    double  m_asian_risk_pct;       // Risk% for Asian session
    double  m_overlap_risk_pct;     // Risk% for London+NY overlap
    bool    m_trade_dead_session;   // Allow trades during dead hours?

    //+--------------------------------------------------------------+
    //| DetectSession: Get current GMT session from server time      |
    //+--------------------------------------------------------------+
    ENUM_SESSION_MM11 DetectSession()
    {
        // Get GMT time from TimeGMT()
        datetime gmt_now = TimeGMT();
        MqlDateTime dt;
        TimeToStruct(gmt_now, dt);

        int hour = dt.hour;

        // Dead session: 21:00-00:00 GMT
        if(hour >= 21)
            return SESSION_MM11_DEAD;

        // Asian: 00:00-08:00 GMT
        if(hour < 8)
            return SESSION_MM11_ASIAN;

        // London only: 08:00-13:00 GMT
        if(hour < 13)
            return SESSION_MM11_LONDON;

        // London+NY Overlap: 13:00-16:00 GMT (highest liquidity)
        if(hour < 16)
            return SESSION_MM11_OVERLAP;

        // NY only: 16:00-21:00 GMT
        return SESSION_MM11_NY;
    }

    //+--------------------------------------------------------------+
    //| GetSessionRiskPct: Return risk% for current session          |
    //+--------------------------------------------------------------+
    double GetSessionRiskPct()
    {
        ENUM_SESSION_MM11 session = DetectSession();

        switch(session)
        {
            case SESSION_MM11_ASIAN:   return m_asian_risk_pct;
            case SESSION_MM11_LONDON:  return m_london_risk_pct;
            case SESSION_MM11_OVERLAP: return m_overlap_risk_pct;
            case SESSION_MM11_NY:      return m_ny_risk_pct;
            case SESSION_MM11_DEAD:    return 0.0; // No trading
            default:                   return m_asian_risk_pct;
        }
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM11_SessionBased()
    {
        m_london_risk_pct    = 1.5;
        m_ny_risk_pct        = 1.2;
        m_asian_risk_pct     = 0.5;
        m_overlap_risk_pct   = 2.0;
        m_trade_dead_session = false;
    }

    //+--------------------------------------------------------------+
    //| Setup: Initialize with symbol and history window             |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 11; }
    virtual string GetName() override { return "MM11_SessionBased"; }

    //+--------------------------------------------------------------+
    //| SetParams: Customize session risk percentages                |
    //+--------------------------------------------------------------+
    void SetParams(double london_pct, double ny_pct, double asian_pct,
                   double overlap_pct, bool trade_dead = false)
    {
        m_london_risk_pct    = MathMax(0.1, london_pct);
        m_ny_risk_pct        = MathMax(0.1, ny_pct);
        m_asian_risk_pct     = MathMax(0.1, asian_pct);
        m_overlap_risk_pct   = MathMax(0.1, overlap_pct);
        m_trade_dead_session = trade_dead;
    }

    //+--------------------------------------------------------------+
    //| GetCurrentSession: Expose for diagnostics                    |
    //+--------------------------------------------------------------+
    ENUM_SESSION_MM11 GetCurrentSession() { return DetectSession(); }

    //+--------------------------------------------------------------+
    //| CalculateLot: Main lot sizing logic                          |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // --- Get session risk %
        double risk_pct = GetSessionRiskPct();

        // Dead session — return 0 (no trading)
        if(risk_pct <= 0.0)
            return 0.0;

        // --- Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0)
            return vol_min;

        // --- Calculate SL in price distance
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100; // fallback

        // --- Risk amount in account currency
        double risk_amount = balance * (risk_pct / 100.0);

        // --- Convert SL distance to ticks, then to currency
        double sl_ticks    = sl_distance / tick_size;
        double sl_currency = sl_ticks * tick_value;
        if(sl_currency <= 0.0) return vol_min;

        // --- Raw lot
        double lot = risk_amount / sl_currency;

        // --- Clamp and normalize
        lot = MathMax(vol_min, MathMin(vol_max, lot));
        lot = MathRound(lot / vol_step) * vol_step;

        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Diagnostics                                                  |
    //+--------------------------------------------------------------+
    void PrintDiagnostics()
    {
        ENUM_SESSION_MM11 s = DetectSession();
        string names[] = {"Asian","London","Overlap","NY","Dead"};
        double risks[]  = {m_asian_risk_pct, m_london_risk_pct,
                           m_overlap_risk_pct, m_ny_risk_pct, 0.0};

        PrintFormat("[MM11] Session=%s | Risk=%.2f%% | London=%.2f%% | NY=%.2f%% | Asian=%.2f%% | Overlap=%.2f%%",
            names[(int)s], risks[(int)s],
            m_london_risk_pct, m_ny_risk_pct,
            m_asian_risk_pct, m_overlap_risk_pct);
    }
};

#endif // MM11_SESSIONBASED_MQH
//+------------------------------------------------------------------+
