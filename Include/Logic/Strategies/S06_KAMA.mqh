//+------------------------------------------------------------------+
//| S06_KAMA.mqh                                                     |
//| FlashEASuite V2 — Adaptive Trend Following (KAMA)               |
//| Magic: 1006 | Type: Full_MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  KAMA = Kaufman's Adaptive Moving Average (period=10, fast=2,   |
//|         slow=30) — adjusts speed based on Efficiency Ratio (ER) |
//|  ER   = |Price[0] - Price[n]| / SUM(|Price[i] - Price[i-1]|)   |
//|  Entry Long : Price > KAMA AND slope > 0 AND ER >= threshold    |
//|  Entry Short: Price < KAMA AND slope < 0 AND ER >= threshold    |
//|  Exit       : TP = 3xATR offset, SL = 1xATR offset             |
//|               Soft exit: price crosses back through KAMA        |
//|  Confidence = ER x (distance_from_KAMA / ATR), clamped 0-1     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S06_KAMA_MQH
#define S06_KAMA_MQH

#include "..\IStrategy.mqh"

//--- Input Parameters
// Optimized: USDJPY.tp H4 2022-2024 | Custom=17.23 | PF=3.27 DD=1.24% Trades=54/3y
// Validated 2026-03-07 OHLC-M1: PF=1.99 Profit=$260 DD=1.94% Trades=26 (OHLC M1 undercounts vs real tick)
input int    KAMA_Period     = 13;   // KAMA lookback period
input int    KAMA_Fast       = 2;    // Fast EMA period
input int    KAMA_Slow       = 30;   // Slow EMA period
input double KAMA_ER_Thresh  = 0.90; // Efficiency Ratio threshold for entry
input double KAMA_TP_ATR     = 4.7;  // Take Profit multiplier (x ATR)
input double KAMA_SL_ATR     = 2.3;  // Stop Loss multiplier (x ATR)
input int    KAMA_ATR_Period = 14;   // ATR calculation period

//+------------------------------------------------------------------+
//| CKAMATrend — Adaptive Trend Following Strategy                   |
//+------------------------------------------------------------------+
class CKAMATrend : public IStrategy
{
private:
    //--- Dynamic params
    int     m_kama_period;
    int     m_kama_fast;
    int     m_kama_slow;
    double  m_er_threshold;
    double  m_tp_atr_mult;
    double  m_sl_atr_mult;
    int     m_atr_period;

    //--- KAMA state
    double  m_kama_current;
    double  m_kama_prev;
    double  m_price_buf[];      // Close prices, newest at [0]

    //--- Indicator
    int     m_atr_handle;

    //--- Last computed values
    double   m_er;
    double   m_atr;
    double   m_slope;

    //--- Bar tracking (KAMA must update once per bar, not every tick)
    datetime m_last_bar_time;

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    double _FastSC() { return 2.0 / (m_kama_fast + 1.0); }
    double _SlowSC() { return 2.0 / (m_kama_slow + 1.0); }

    double _CalcER()
    {
        int n = m_kama_period;
        if(ArraySize(m_price_buf) < n + 1) return 0.0;
        double net_change = MathAbs(m_price_buf[0] - m_price_buf[n]);
        double volatility = 0.0;
        for(int i = 0; i < n; i++)
            volatility += MathAbs(m_price_buf[i] - m_price_buf[i + 1]);
        if(volatility < 1e-10) return 0.0;
        return MathMin(net_change / volatility, 1.0);
    }

    void _UpdateKAMA()
    {
        if(m_kama_current == 0.0)
        {
            m_kama_current = m_price_buf[0];
            m_kama_prev    = m_price_buf[0];
            return;
        }
        m_er = _CalcER();
        double sc = m_er * (_FastSC() - _SlowSC()) + _SlowSC();
        sc = sc * sc;
        m_kama_prev    = m_kama_current;
        m_kama_current = m_kama_current + sc * (m_price_buf[0] - m_kama_current);
        m_slope        = m_kama_current - m_kama_prev;
    }

    void _ShiftBuffer(double new_price)
    {
        int sz = ArraySize(m_price_buf);
        for(int i = sz - 1; i > 0; i--)
            m_price_buf[i] = m_price_buf[i - 1];
        m_price_buf[0] = new_price;
    }

    double _GetATR()
    {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(m_atr_handle, 0, 0, 1, buf) < 1) return 0.0;
        return buf[0];
    }

    double _CalcConfidence(double price)
    {
        if(m_atr < 1e-10 || m_kama_current == 0.0) return 0.0;
        double dist = MathAbs(price - m_kama_current);
        return MathMin(m_er * (dist / m_atr), 1.0);
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor — IStrategy() takes no params; set id in body       |
    //+------------------------------------------------------------------+
    CKAMATrend()
    {
        m_strategy_id  = S06_KAMA;   // Set strategy enum ID

        m_kama_period  = KAMA_Period;
        m_kama_fast    = KAMA_Fast;
        m_kama_slow    = KAMA_Slow;
        m_er_threshold = KAMA_ER_Thresh;
        m_tp_atr_mult  = KAMA_TP_ATR;
        m_sl_atr_mult  = KAMA_SL_ATR;
        m_atr_period   = KAMA_ATR_Period;

        m_kama_current = 0.0;
        m_kama_prev    = 0.0;
        m_er           = 0.0;
        m_atr          = 0.0;
        m_slope        = 0.0;
        m_atr_handle   = INVALID_HANDLE;
        m_last_bar_time = 0;
    }

    ~CKAMATrend()
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

        m_info.name        = "Adaptive Trend Following (KAMA)";
        m_info.short_name  = "S06";
        m_info.magic       = MAGIC_S06_KAMA;
        m_info.category    = CAT_FULL_MQL5;
        m_info.standalone  = true;
        m_info.best_regime = REGIME_TRENDING;
        m_info.alt_regime  = REGIME_UNKNOWN;
        m_info.family      = "Trend Following";

        ArrayResize(m_price_buf, m_kama_period + 1);
        ArrayInitialize(m_price_buf, 0.0);

        double closes[];
        int copied = CopyClose(symbol, tf, 0, m_kama_period + 2, closes);
        if(copied >= m_kama_period + 1)
        {
            for(int i = 0; i <= m_kama_period; i++)
                m_price_buf[i] = closes[m_kama_period - i];
            m_kama_current = closes[0];
            m_kama_prev    = closes[0];
        }

        m_atr_handle = iATR(symbol, tf, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            PrintFormat("[S06] ERROR: iATR failed on %s %s", symbol, EnumToString(tf));
            return false;
        }

        m_initialized = true;
        PrintFormat("[S06] Init OK | %s %s | KAMA(%d,%d,%d) ER_thresh=%.2f",
                    symbol, EnumToString(tf),
                    m_kama_period, m_kama_fast, m_kama_slow, m_er_threshold);
        return true;
    }

    virtual void Analyze(const MqlTick &tick) override
    {
        if(!m_initialized || !m_enabled) return;

        // ── Update KAMA buffer ONCE PER BAR using previous bar close ────
        // Using tick prices would make KAMA_Period mean "ticks", not "bars"
        datetime current_bar = iTime(m_symbol, m_timeframe, 0);
        if(current_bar != m_last_bar_time && current_bar > 0)
        {
            m_last_bar_time = current_bar;
            double bar_close = iClose(m_symbol, m_timeframe, 1);  // previous completed bar
            if(bar_close > 0)
            {
                _ShiftBuffer(bar_close);
                _UpdateKAMA();
            }
        }

        if(m_kama_current == 0.0) return;  // not yet initialised

        m_atr = _GetATR();
        if(m_atr < 1e-10) return;

        // Signal uses current tick mid-price vs bar-based KAMA
        double price = (tick.bid + tick.ask) * 0.5;

        m_state.last_confidence = _CalcConfidence(price);
        m_state.last_signal_time = TimeCurrent();

        ENUM_TRADE_SIGNAL sig = SIGNAL_NONE;
        if(price > m_kama_current && m_slope > 0.0 && m_er >= m_er_threshold)
            sig = SIGNAL_BUY;
        else if(price < m_kama_current && m_slope < 0.0 && m_er >= m_er_threshold)
            sig = SIGNAL_SELL;

        m_state.last_signal = sig;

        // Store ABSOLUTE SL/TP prices (per IStrategy contract)
        if(sig == SIGNAL_BUY)
        {
            m_state.last_sl = price - m_sl_atr_mult * m_atr;
            m_state.last_tp = price + m_tp_atr_mult * m_atr;
        }
        else if(sig == SIGNAL_SELL)
        {
            m_state.last_sl = price + m_sl_atr_mult * m_atr;
            m_state.last_tp = price - m_tp_atr_mult * m_atr;
        }
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
    //| GetTakeProfit: Returns absolute TP price (set in Analyze)       |
    //+------------------------------------------------------------------+
    virtual double GetTakeProfit() override { return m_state.last_tp; }

    //+------------------------------------------------------------------+
    //| GetStopLoss: Returns absolute SL price (set in Analyze)         |
    //+------------------------------------------------------------------+
    virtual double GetStopLoss() override { return m_state.last_sl; }

    //+------------------------------------------------------------------+
    //| ShouldExit: True when price crosses back through KAMA           |
    //| NOT in IStrategy base — no override keyword                     |
    //+------------------------------------------------------------------+
    bool ShouldExit(ENUM_TRADE_SIGNAL open_direction)
    {
        if(!m_initialized) return false;
        double price = (SymbolInfoDouble(m_symbol, SYMBOL_BID) +
                        SymbolInfoDouble(m_symbol, SYMBOL_ASK)) * 0.5;
        if(open_direction == SIGNAL_BUY  && price < m_kama_current) return true;
        if(open_direction == SIGNAL_SELL && price > m_kama_current) return true;
        return false;
    }

    virtual void OnConfigUpdate(const SConfigUpdate &config) override
    {
        IStrategy::OnConfigUpdate(config);
        if(config.regime == REGIME_TRENDING)     m_er_threshold = 0.25;
        else if(config.regime == REGIME_RANGING) m_er_threshold = 0.45;
        else                                     m_er_threshold = KAMA_ER_Thresh;
    }

    //+------------------------------------------------------------------+
    //| SetDynamicParams: Matches base signature SetDynamicParams(SDynamicParams &)
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &params) override
    {
        IStrategy::SetDynamicParams(params);
        m_kama_period  = (int)params.GetParam("S06_KAMA_PERIOD", m_kama_period);
        m_er_threshold =      params.GetParam("S06_ER_THRESH",   m_er_threshold);
        m_tp_atr_mult  =      params.GetParam("S06_TP_ATR",      m_tp_atr_mult);
        m_sl_atr_mult  =      params.GetParam("S06_SL_ATR",      m_sl_atr_mult);
        PrintFormat("[S06] DynamicParams | period=%d ER=%.2f TP=%.1fx SL=%.1fx",
                    m_kama_period, m_er_threshold, m_tp_atr_mult, m_sl_atr_mult);
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = GetDefaultMM(S06_KAMA);
        p.SetParam("S06_KAMA_PERIOD", m_kama_period);
        p.SetParam("S06_ER_THRESH",   m_er_threshold);
        p.SetParam("S06_TP_ATR",      m_tp_atr_mult);
        p.SetParam("S06_SL_ATR",      m_sl_atr_mult);
        p.SetParam("S06_KAMA_VALUE",  m_kama_current);
        p.SetParam("S06_ER_LAST",     m_er);
        return p;
    }

    virtual string GetName()  override { return "Adaptive Trend Following (KAMA)"; }
    virtual int    GetMagic() override { return MAGIC_S06_KAMA; }

    //--- Expose internals for Trader
    double GetKAMAValue() const { return m_kama_current; }
    double GetER()        const { return m_er; }
    double GetATR()       const { return m_atr; }
    double GetKAMASlope() const { return m_slope; }
};

#endif // S06_KAMA_MQH
//+------------------------------------------------------------------+
