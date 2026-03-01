//+------------------------------------------------------------------+
//| IMoneyManager.mqh                                                |
//| FlashEASuite V2 V6 — Money Manager Interface (Abstract)          |
//| All 19 MM methods must implement this interface.                 |
//+------------------------------------------------------------------+
//| Pattern: Similar to IStrategy — use Setup(), no new/delete       |
//| Usage: CMMxxx mm; mm.Setup(symbol); lot = mm.CalculateLot(...)   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef IMONEYMANAGER_MQH
#define IMONEYMANAGER_MQH

//+------------------------------------------------------------------+
//| ENUM: MM Method IDs (1-19, non-negative — MQL5 enum rule)        |
//+------------------------------------------------------------------+
enum ENUM_MM_ID
{
    MM_ID_NONE              = 0,
    MM_ID_FIXED_CONSERVATIVE= 1,    // MM01: Fixed Fractional 1%
    MM_ID_FIXED_AGGRESSIVE  = 2,    // MM02: Fixed Fractional 2%
    MM_ID_ATR_BASED         = 3,    // MM03: ATR Dynamic
    MM_ID_KELLY             = 4,    // MM04: Kelly Criterion (Half-Kelly)
    MM_ID_MARTINGALE        = 5,    // MM05: Controlled Martingale
    MM_ID_ANTI_MARTINGALE   = 6,    // MM06: Anti-Martingale
    MM_ID_PCT_VOLATILITY    = 7,    // MM07: Percent Volatility
    MM_ID_PYRAMID           = 8,    // MM08: Pyramid Adding
    MM_ID_EQUITY_RECOVERY   = 9,    // MM09: Equity Curve Recovery
    MM_ID_DRAWDOWN_BASED    = 10,   // MM10: Drawdown-Based
    MM_ID_SESSION_BASED     = 11,   // MM11: Session-Based
    MM_ID_EQUITY_FILTER     = 12,   // MM12: Equity Curve Filter
    MM_ID_CORRELATION       = 13,   // MM13: Correlation Adjusted
    MM_ID_TIERED_RISK       = 14,   // MM14: Tiered Risk
    MM_ID_WIN_STREAK        = 15,   // MM15: Adaptive Win-Streak
    MM_ID_VOL_PERCENTILE    = 16,   // MM16: Volatility Percentile
    MM_ID_REGIME_BASED      = 17,   // MM17: Regime-Based
    MM_ID_PORTFOLIO_CAP     = 18,   // MM18: Portfolio Cap
    MM_ID_DYNAMIC_MULTI     = 19    // MM19: Dynamic Multi-Method
};

//+------------------------------------------------------------------+
//| STRUCT: MM State — tracks trade history for adaptive methods      |
//+------------------------------------------------------------------+
struct SMMState
{
    int     consecutive_wins;       // Current win streak
    int     consecutive_losses;     // Current loss streak
    int     total_trades;           // Total trades processed
    double  win_rates[];            // Rolling win history (1=win, 0=loss)
    double  rr_history[];           // Rolling R:R history
    int     history_count;          // Current items in rolling history
    int     history_capacity;       // Max items (rolling window)
    double  peak_equity;            // Highest equity seen (for DD calc)
    double  last_lot;               // Last lot used (for streak methods)
    
    void Init(int capacity = 50)
    {
        consecutive_wins    = 0;
        consecutive_losses  = 0;
        total_trades        = 0;
        history_count       = 0;
        history_capacity    = capacity;
        peak_equity         = 0.0;
        last_lot            = 0.0;
        ArrayResize(win_rates,  capacity);
        ArrayResize(rr_history, capacity);
        ArrayInitialize(win_rates,  0.0);
        ArrayInitialize(rr_history, 0.0);
    }
    
    void Reset()
    {
        consecutive_wins   = 0;
        consecutive_losses = 0;
        total_trades       = 0;
        history_count      = 0;
        peak_equity        = 0.0;
        last_lot           = 0.0;
        ArrayInitialize(win_rates,  0.0);
        ArrayInitialize(rr_history, 0.0);
    }
    
    void AddResult(bool win, double rr)
    {
        // Update streaks
        if(win) { consecutive_wins++;  consecutive_losses = 0; }
        else     { consecutive_losses++; consecutive_wins  = 0; }
        total_trades++;
        
        // Rolling history (circular buffer)
        if(history_capacity > 0)
        {
            int idx = history_count % history_capacity;
            win_rates[idx]  = win ? 1.0 : 0.0;
            rr_history[idx] = rr;
            if(history_count < history_capacity) history_count++;
            else history_count = history_capacity; // keep at max
        }
    }
    
    double GetWinRate() const
    {
        if(history_count == 0) return 0.5; // default 50%
        double sum = 0.0;
        int n = MathMin(history_count, history_capacity);
        for(int i = 0; i < n; i++) sum += win_rates[i];
        return sum / n;
    }
    
    double GetAvgRR() const
    {
        if(history_count == 0) return 1.5; // default R:R
        double sum = 0.0;
        int n = MathMin(history_count, history_capacity);
        for(int i = 0; i < n; i++) sum += rr_history[i];
        return sum / n;
    }
};

//+------------------------------------------------------------------+
//| UTILITY: Pip value per lot in account currency                   |
//| stopLoss = SL distance in price units (e.g. 2.5 for XAUUSD)     |
//| Returns: value per 1 lot for that price distance                 |
//+------------------------------------------------------------------+
double MMCalcPriceValue(string symbol, double price_distance)
{
    double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size <= 0.0) return 0.0;
    return (price_distance / tick_size) * tick_value;
}

//+------------------------------------------------------------------+
//| UTILITY: Normalize lot to broker rules                           |
//+------------------------------------------------------------------+
double MMNormalizeLot(string symbol, double lot)
{
    double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double step_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if(step_lot <= 0.0) step_lot = 0.01;
    if(min_lot  <= 0.0) min_lot  = 0.01;
    if(max_lot  <= 0.0) max_lot  = 100.0;
    
    lot = MathFloor(lot / step_lot) * step_lot;
    lot = MathMax(min_lot, MathMin(max_lot, lot));
    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| UTILITY: Calculate lot from risk amount and SL distance           |
//| lot = risk_amount / value_per_lot(sl_distance)                  |
//+------------------------------------------------------------------+
double MMCalcLotFromRisk(string symbol, double risk_amount, double sl_distance)
{
    if(sl_distance <= 0.0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double value_per_lot = MMCalcPriceValue(symbol, sl_distance);
    if(value_per_lot <= 0.0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double lot = risk_amount / value_per_lot;
    return MMNormalizeLot(symbol, lot);
}

//+------------------------------------------------------------------+
//| CLASS: IMoneyManager — Abstract Base Interface                   |
//+------------------------------------------------------------------+
//| All 19 MM methods inherit from this class.                       |
//| MQL5 has no pure virtual, so defaults are safe fallbacks.        |
//+------------------------------------------------------------------+
class IMoneyManager
{
protected:
    string      m_symbol;           // Trading symbol
    bool        m_initialized;      // Setup() called?
    SMMState    m_state;            // Trade history state
    double      m_base_lot;         // Minimum/base lot size
    double      m_risk_multiplier;  // Regime-based scaling (from CONFIG_PUSH)

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    IMoneyManager()
    {
        m_symbol          = "";
        m_initialized     = false;
        m_base_lot        = 0.01;
        m_risk_multiplier = 1.0;
        m_state.Init(50);
    }
    
    virtual ~IMoneyManager() {}
    
    //+------------------------------------------------------------------+
    //| Setup: Initialize with symbol — call before CalculateLot         |
    //+------------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50)
    {
        m_symbol      = symbol;
        m_base_lot    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(m_base_lot <= 0.0) m_base_lot = 0.01;
        m_state.Init(history_window);
        m_initialized = true;
    }
    
    //=================================================================
    //  CORE INTERFACE — Override these in each MM method
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| CalculateLot: Main position sizing calculation                   |
    //| @param balance   Account balance                                 |
    //| @param equity    Account equity                                  |
    //| @param stopLoss  SL distance in PRICE units (not pips)           |
    //|                  e.g. 2.5 means price moves 2.5 against us       |
    //| @param symbol    Trading symbol                                   |
    //| @return          Normalized lot size                             |
    //+------------------------------------------------------------------+
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol)
    {
        // Default: fixed 0.01 lot (safe fallback)
        return MMNormalizeLot(symbol, m_base_lot);
    }
    
    //+------------------------------------------------------------------+
    //| UpdateTradeResult: Called after each trade closes                |
    //| @param win     true=profit, false=loss                           |
    //| @param rr      Actual R:R achieved (profit / initial_risk)       |
    //+------------------------------------------------------------------+
    virtual void UpdateTradeResult(bool win, double rr = 1.0)
    {
        m_state.AddResult(win, rr);
        // Track peak equity for DD methods
        double eq = AccountInfoDouble(ACCOUNT_EQUITY);
        if(eq > m_state.peak_equity) m_state.peak_equity = eq;
    }
    
    //+------------------------------------------------------------------+
    //| GetName: Human-readable method name                              |
    //+------------------------------------------------------------------+
    virtual string GetName() { return "BaseMoneyManager"; }
    
    //+------------------------------------------------------------------+
    //| GetID: MM method ID                                              |
    //+------------------------------------------------------------------+
    virtual int GetID() { return (int)MM_ID_NONE; }
    
    //+------------------------------------------------------------------+
    //| SetDynamicParams: Apply CONFIG_PUSH V2 parameters                |
    //+------------------------------------------------------------------+
    virtual void SetRiskMultiplier(double multiplier)
    {
        m_risk_multiplier = MathMax(0.1, MathMin(2.0, multiplier));
    }
    
    //+------------------------------------------------------------------+
    //| Reset: Clear trade history state                                 |
    //+------------------------------------------------------------------+
    virtual void Reset()
    {
        m_state.Reset();
        m_risk_multiplier = 1.0;
    }
    
    //+------------------------------------------------------------------+
    //| GetState: Access to internal state (for diagnostics)            |
    //+------------------------------------------------------------------+
    SMMState GetState() { return m_state; }
    
    //+------------------------------------------------------------------+
    //| GetDiagnostic: Human-readable status string                     |
    //+------------------------------------------------------------------+
    virtual string GetDiagnostic()
    {
        return StringFormat("[%s] Trades:%d Wins:%.0f%% Streak:W%d/L%d",
            GetName(), m_state.total_trades,
            m_state.GetWinRate() * 100.0,
            m_state.consecutive_wins,
            m_state.consecutive_losses);
    }
};

#endif // IMONEYMANAGER_MQH
