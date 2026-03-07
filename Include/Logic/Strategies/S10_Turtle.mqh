//+------------------------------------------------------------------+
//| S10_Turtle.mqh                                                   |
//| FlashEASuite V2 — Turtle Trading (Modernized)                   |
//| Magic: 1010 | Type: Full_MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| LOGIC (Modernized Turtle Rules):                                 |
//|  Donchian Entry : 20-bar High/Low channel                       |
//|  Entry Long     : Close > Upper Donchian + ATR*0.1              |
//|  Entry Short    : Close < Lower Donchian - ATR*0.1              |
//|  Pyramiding     : Add up to 4 units, each 0.5*ATR apart         |
//|  Exit           : 20-bar opposite Donchian channel              |
//|  SL             : 2*ATR from entry                              |
//|  Confidence     = (breakout_strength / ATR) * trend_consistency |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S10_TURTLE_MQH
#define S10_TURTLE_MQH

#include "..\IStrategy.mqh"

//--- Input Parameters
// Optimized: XAUUSD.tp H4 2022-2024 | Custom=0.1027 | PF=1.384 DD=23.7% Trades=84/3y
// Validation pending: requires Real tick model (OHLC M1 unsuitable for breakout — PF=0.67 with OHLC)
input int    Turtle_EntryPeriod = 15;   // Entry Donchian channel period
input int    Turtle_ExitPeriod  = 30;   // Exit Donchian channel period
input int    Turtle_ATR_Period  = 20;   // ATR period (classic Turtle = 20)
input double Turtle_BreakoutBuf = 0.1;  // ATR buffer beyond Donchian edge
input int    Turtle_MaxUnits    = 4;    // Max pyramid units
input double Turtle_UnitSpacing = 0.5;  // ATR spacing between pyramid units
input double Turtle_RiskPct     = 0.5;  // Risk % per unit

//+------------------------------------------------------------------+
//| CTurtle — Modernized Turtle Trading Strategy                     |
//+------------------------------------------------------------------+
class CTurtle : public IStrategy
{
private:
    //--- Dynamic params
    int     m_entry_period;
    int     m_exit_period;
    int     m_atr_period;
    double  m_breakout_buf;
    int     m_max_units;
    double  m_unit_spacing;
    double  m_risk_pct;

    //--- Indicator
    int     m_atr_handle;

    //--- Donchian levels
    double  m_entry_high;
    double  m_entry_low;
    double  m_exit_high;
    double  m_exit_low;
    double  m_atr;

    //--- Pyramid state
    int               m_unit_count;
    ENUM_TRADE_SIGNAL m_direction;
    double            m_last_entry_price;

    //--- Confidence components
    double  m_breakout_strength;
    double  m_trend_consistency;

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    bool _UpdateDonchian()
    {
        double highs[], lows[];

        // Entry channel (20-bar) — use bars 1..n (exclude current forming bar)
        if(CopyHigh(m_symbol, m_timeframe, 1, m_entry_period, highs) < m_entry_period) return false;
        if(CopyLow (m_symbol, m_timeframe, 1, m_entry_period, lows)  < m_entry_period) return false;
        m_entry_high = highs[ArrayMaximum(highs)];
        m_entry_low  = lows [ArrayMinimum(lows)];

        // Exit channel (10-bar)
        double exit_highs[], exit_lows[];
        if(CopyHigh(m_symbol, m_timeframe, 1, m_exit_period, exit_highs) < m_exit_period) return false;
        if(CopyLow (m_symbol, m_timeframe, 1, m_exit_period, exit_lows)  < m_exit_period) return false;
        m_exit_high = exit_highs[ArrayMaximum(exit_highs)];
        m_exit_low  = exit_lows [ArrayMinimum(exit_lows)];

        return true;
    }

    double _GetATR()
    {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, buf) < 1) return 0.0;
        return buf[0];
    }

    double _CalcTrendConsistency(ENUM_TRADE_SIGNAL direction)
    {
        double closes[];
        int n = m_entry_period;
        if(CopyClose(m_symbol, m_timeframe, 1, n, closes) < n) return 0.5;
        int same_dir = 0;
        for(int i = 0; i < n - 1; i++)
        {
            bool rising = (closes[i + 1] > closes[i]);
            if(direction == SIGNAL_BUY  &&  rising) same_dir++;
            if(direction == SIGNAL_SELL && !rising) same_dir++;
        }
        return (double)same_dir / (double)(n - 1);
    }

    double _CalcConfidence(double price, ENUM_TRADE_SIGNAL direction)
    {
        if(m_atr < 1e-10) return 0.0;
        if(direction == SIGNAL_BUY)
            m_breakout_strength = price - m_entry_high;
        else if(direction == SIGNAL_SELL)
            m_breakout_strength = m_entry_low - price;
        else
            return 0.0;
        m_trend_consistency = _CalcTrendConsistency(direction);
        double raw = (m_breakout_strength / m_atr) * m_trend_consistency;
        return MathMin(MathMax(raw, 0.0), 1.0);
    }

    bool _CanAddUnit(double price)
    {
        if(m_unit_count >= m_max_units) return false;
        if(m_unit_count == 0)           return true;
        double spacing = m_unit_spacing * m_atr;
        if(m_direction == SIGNAL_BUY)  return (price >= m_last_entry_price + spacing);
        if(m_direction == SIGNAL_SELL) return (price <= m_last_entry_price - spacing);
        return false;
    }

    bool _IsExitTriggered(double price)
    {
        if(m_direction == SIGNAL_BUY)  return (price <= m_exit_low);
        if(m_direction == SIGNAL_SELL) return (price >= m_exit_high);
        return false;
    }

    void _ResetPyramid()
    {
        m_unit_count       = 0;
        m_direction        = SIGNAL_NONE;
        m_last_entry_price = 0.0;
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor — IStrategy() takes no params; set id in body       |
    //+------------------------------------------------------------------+
    CTurtle()
    {
        m_strategy_id  = S10_TURTLE;   // Set strategy enum ID

        m_entry_period = Turtle_EntryPeriod;
        m_exit_period  = Turtle_ExitPeriod;
        m_atr_period   = Turtle_ATR_Period;
        m_breakout_buf = Turtle_BreakoutBuf;
        m_max_units    = Turtle_MaxUnits;
        m_unit_spacing = Turtle_UnitSpacing;
        m_risk_pct     = Turtle_RiskPct;

        m_entry_high   = 0.0;
        m_entry_low    = 0.0;
        m_exit_high    = 0.0;
        m_exit_low     = 0.0;
        m_atr          = 0.0;
        m_atr_handle   = INVALID_HANDLE;

        m_breakout_strength = 0.0;
        m_trend_consistency = 0.5;

        _ResetPyramid();
    }

    ~CTurtle()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }

    //=================================================================
    //  OVERRIDES
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
    {
        if(!IStrategy::Init(symbol, tf)) return false;

        m_info.name        = "Turtle Trading (Modernized)";
        m_info.short_name  = "S10";
        m_info.magic       = MAGIC_S10_TURTLE;
        m_info.category    = CAT_FULL_MQL5;
        m_info.standalone  = true;
        m_info.best_regime = REGIME_TRENDING;
        m_info.alt_regime  = REGIME_SQUEEZE;
        m_info.family      = "Trend Following";

        m_atr_handle = iATR(symbol, tf, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            PrintFormat("[S10] ERROR: iATR failed on %s %s", symbol, EnumToString(tf));
            return false;
        }

        m_atr = _GetATR();
        _UpdateDonchian();

        m_initialized = true;
        PrintFormat("[S10] Init OK | %s %s | Entry:%d Exit:%d MaxUnits:%d",
                    symbol, EnumToString(tf),
                    m_entry_period, m_exit_period, m_max_units);
        return true;
    }

    virtual void Analyze(const MqlTick &tick) override
    {
        if(!m_initialized || !m_enabled) return;

        double price = tick.bid;

        m_atr = _GetATR();
        if(m_atr < 1e-10) return;

        if(!_UpdateDonchian()) return;

        m_state.last_signal_time = TimeCurrent();

        // EXIT takes priority
        if(m_direction != SIGNAL_NONE && _IsExitTriggered(price))
        {
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            _ResetPyramid();
            return;
        }

        // PYRAMID — add unit if in trade
        if(m_direction != SIGNAL_NONE)
        {
            if(_CanAddUnit(price))
            {
                m_last_entry_price      = price;
                m_unit_count++;
                m_state.last_signal     = m_direction;
                m_state.last_confidence = _CalcConfidence(price, m_direction);
            }
            else
            {
                m_state.last_signal = SIGNAL_NONE;
            }
            return;
        }

        // BREAKOUT ENTRY
        ENUM_TRADE_SIGNAL sig = SIGNAL_NONE;
        if(price > m_entry_high + m_breakout_buf * m_atr)
            sig = SIGNAL_BUY;
        else if(price < m_entry_low - m_breakout_buf * m_atr)
            sig = SIGNAL_SELL;

        if(sig != SIGNAL_NONE)
        {
            m_direction        = sig;
            m_unit_count       = 1;
            m_last_entry_price = price;
            m_state.last_confidence = _CalcConfidence(price, sig);
            // Cache SL in state (offset from entry)
            m_state.last_sl = 2.0 * m_atr;
            m_state.last_tp = 0.0;   // Turtle uses Donchian exit, no fixed TP
        }

        m_state.last_signal = sig;
    }

    virtual ENUM_TRADE_SIGNAL GetSignal() override
    {
        if(!m_initialized || !m_enabled) return SIGNAL_NONE;
        return m_state.last_signal;
    }

    virtual double GetConfidence() override
    {
        if(!m_initialized || !m_enabled) return 0.0;
        return m_state.last_confidence;
    }

    //+------------------------------------------------------------------+
    //| GetTakeProfit: Turtle uses Donchian exit, no fixed TP           |
    //| Returns 0.0 — Trader uses ShouldExit() instead                 |
    //+------------------------------------------------------------------+
    virtual double GetTakeProfit() override
    {
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| GetStopLoss: Returns ATR offset (2*ATR, Turtle classic rule)   |
    //| Trader subtracts from entry (buy) or adds (sell)               |
    //+------------------------------------------------------------------+
    virtual double GetStopLoss() override
    {
        return 2.0 * m_atr;
    }

    //+------------------------------------------------------------------+
    //| ShouldExit: Donchian exit rule — NOT in base, no override       |
    //+------------------------------------------------------------------+
    bool ShouldExit()
    {
        if(!m_initialized || m_direction == SIGNAL_NONE) return false;
        double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        return _IsExitTriggered(price);
    }

    virtual void OnConfigUpdate(const SConfigUpdate &config) override
    {
        IStrategy::OnConfigUpdate(config);
        if(config.regime == REGIME_TRENDING)     m_breakout_buf = 0.05;
        else if(config.regime == REGIME_RANGING) m_breakout_buf = 0.20;
        else                                     m_breakout_buf = Turtle_BreakoutBuf;
    }

    //+------------------------------------------------------------------+
    //| SetDynamicParams: Matches base signature (non-const ref)        |
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &params) override
    {
        IStrategy::SetDynamicParams(params);
        m_entry_period = (int)params.GetParam("S10_ENTRY_PERIOD", m_entry_period);
        m_exit_period  = (int)params.GetParam("S10_EXIT_PERIOD",  m_exit_period);
        m_max_units    = (int)params.GetParam("S10_MAX_UNITS",    m_max_units);
        m_unit_spacing =      params.GetParam("S10_UNIT_SPACING", m_unit_spacing);
        m_breakout_buf =      params.GetParam("S10_BREAKOUT_BUF", m_breakout_buf);
        m_risk_pct     =      params.GetParam("S10_RISK_PCT",     m_risk_pct);
        PrintFormat("[S10] DynamicParams | Entry:%d Exit:%d MaxUnits:%d Spacing:%.2f",
                    m_entry_period, m_exit_period, m_max_units, m_unit_spacing);
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = GetDefaultMM(S10_TURTLE);
        p.SetParam("S10_ENTRY_PERIOD", m_entry_period);
        p.SetParam("S10_EXIT_PERIOD",  m_exit_period);
        p.SetParam("S10_MAX_UNITS",    m_max_units);
        p.SetParam("S10_UNIT_SPACING", m_unit_spacing);
        p.SetParam("S10_BREAKOUT_BUF", m_breakout_buf);
        p.SetParam("S10_RISK_PCT",     m_risk_pct);
        p.SetParam("S10_UNITS_ACTIVE", m_unit_count);
        p.SetParam("S10_ENTRY_HIGH",   m_entry_high);
        p.SetParam("S10_ENTRY_LOW",    m_entry_low);
        p.SetParam("S10_ATR",          m_atr);
        return p;
    }

    virtual string GetName()  override { return "Turtle Trading (Modernized)"; }
    virtual int    GetMagic() override { return MAGIC_S10_TURTLE; }

    //--- Expose internals for Trader
    double GetEntryHigh()             const { return m_entry_high; }
    double GetEntryLow()              const { return m_entry_low; }
    double GetExitHigh()              const { return m_exit_high; }
    double GetExitLow()               const { return m_exit_low; }
    double GetATR()                   const { return m_atr; }
    int    GetUnitCount()             const { return m_unit_count; }
    ENUM_TRADE_SIGNAL GetDirection()  const { return m_direction; }
};

#endif // S10_TURTLE_MQH
//+------------------------------------------------------------------+
