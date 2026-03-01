//+------------------------------------------------------------------+
//| S13_FibStoch.mqh                                                 |
//| FlashEASuite V2 - Fibonacci Retracement + Stochastic            |
//| Magic: 1013 | Type: Full MQL5 | ServerOnly                      |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  1. Swing H/L detection over last m_fib_lookback bars           |
//|  2. Fibonacci retracement levels: 38.2%, 50.0%, 61.8%          |
//|  3. Long : Price in [38.2–61.8%] AND Stoch < oversold          |
//|  4. Short: Price in [38.2–61.8%] AND Stoch > overbought        |
//|  5. TP = swing High (Long) or swing Low (Short)                 |
//|  6. SL = 78.6% retracement level                               |
//|  7. Confidence = fib_accuracy × stoch_extremity × trend_str    |
//|                                                                  |
//|  SERVER DEPENDENCY: m_enabled=false until SetDynamicParams()    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S13_FIBSTOCH_MQH
#define S13_FIBSTOCH_MQH

#include "../IStrategy.mqh"

//--- Input Parameters
input int    FS_Fib_Lookback     = 100;   // Swing H/L lookback bars
input double FS_Fib_Inner        = 0.382; // Inner fib boundary (38.2%)
input double FS_Fib_Outer        = 0.618; // Outer fib boundary (61.8%)
input double FS_Fib_SL           = 0.786; // SL fib level (78.6%)
input int    FS_Stoch_K          = 14;    // Stochastic %K
input int    FS_Stoch_D          = 3;     // Stochastic %D
input int    FS_Stoch_Slowing    = 3;     // Stochastic slowing
input int    FS_Stoch_Oversold   = 20;    // Stoch oversold level (Long entry)
input int    FS_Stoch_OB         = 80;    // Stoch overbought level (Short entry)
input int    FS_Swing_Min_Bars   = 5;     // Min bars between swing points

//+------------------------------------------------------------------+
//| CFibStoch - Fibonacci + Stochastic Reversal Strategy             |
//+------------------------------------------------------------------+
class CFibStoch : public IStrategy
{
private:
    //--- Dynamic params
    int     m_fib_lookback;
    double  m_fib_inner;           // 38.2%
    double  m_fib_outer;           // 61.8%
    double  m_fib_sl;              // 78.6%
    int     m_stoch_k;
    int     m_stoch_d;
    int     m_stoch_slowing;
    int     m_stoch_oversold;
    int     m_stoch_overbought;
    int     m_swing_min_bars;

    //--- Server context (required — ServerOnly strategy)
    double  m_server_trend;        // +1=up, -1=down (from SetDynamicParams)

    //--- Indicator handles
    int     m_stoch_handle;

    //--- Swing state (recomputed each bar)
    double  m_swing_high;
    double  m_swing_low;
    bool    m_swing_valid;
    bool    m_is_uptrend;          // true: price moved from low → high

    //--- Fib levels (computed from current swing)
    double  m_fib_382;
    double  m_fib_500;
    double  m_fib_618;
    double  m_fib_786;             // SL reference

    //--- Stochastic state
    double  m_stoch_main;          // %K
    double  m_stoch_signal;        // %D

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    // Find dominant Swing High and Swing Low using local extrema detection
    void _FindSwings()
    {
        int total = m_fib_lookback + m_swing_min_bars * 2;
        double highs[], lows[];
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(lows,  true);

        if(CopyHigh(m_symbol, m_timeframe, 0, total, highs) < total ||
           CopyLow (m_symbol, m_timeframe, 0, total, lows)  < total)
        {
            m_swing_valid = false;
            return;
        }

        int    best_hi_bar = -1, best_lo_bar = -1;
        double best_hi = -DBL_MAX, best_lo = DBL_MAX;
        int    n = m_swing_min_bars;

        for(int i = n; i < total - n; i++)
        {
            // Local high check
            bool is_sh = true;
            for(int j = i - n; j <= i + n; j++)
                if(j != i && highs[j] >= highs[i]) { is_sh = false; break; }
            if(is_sh && highs[i] > best_hi) { best_hi = highs[i]; best_hi_bar = i; }

            // Local low check
            bool is_sl = true;
            for(int j = i - n; j <= i + n; j++)
                if(j != i && lows[j] <= lows[i]) { is_sl = false; break; }
            if(is_sl && lows[i] < best_lo) { best_lo = lows[i]; best_lo_bar = i; }
        }

        if(best_hi_bar < 0 || best_lo_bar < 0) { m_swing_valid = false; return; }

        m_swing_high  = best_hi;
        m_swing_low   = best_lo;
        m_swing_valid = true;

        // Dominant direction: if swing low is OLDER (higher bar index = further back),
        // price moved from low → high = uptrend pullback scenario
        m_is_uptrend = (best_lo_bar > best_hi_bar);

        // Compute Fib retracement levels
        double range = m_swing_high - m_swing_low;
        if(m_is_uptrend)
        {
            // Retracement from high downward
            m_fib_382 = m_swing_high - range * 0.382;
            m_fib_500 = m_swing_high - range * 0.500;
            m_fib_618 = m_swing_high - range * 0.618;
            m_fib_786 = m_swing_high - range * 0.786;
        }
        else
        {
            // Retracement from low upward
            m_fib_382 = m_swing_low + range * 0.382;
            m_fib_500 = m_swing_low + range * 0.500;
            m_fib_618 = m_swing_low + range * 0.618;
            m_fib_786 = m_swing_low + range * 0.786;
        }
    }

    // Is current price inside the Fib entry zone [38.2% ↔ 61.8%]?
    bool _PriceInFibZone(double price)
    {
        if(!m_swing_valid) return false;
        double lo = MathMin(m_fib_382, m_fib_618);
        double hi = MathMax(m_fib_382, m_fib_618);
        return (price >= lo && price <= hi);
    }

    // Accuracy 0-1: how close to 61.8% (deeper = more confident)
    double _FibAccuracy(double price)
    {
        if(!m_swing_valid) return 0.0;
        double lo = MathMin(m_fib_382, m_fib_618);
        double hi = MathMax(m_fib_382, m_fib_618);
        double range = hi - lo;
        if(range < 1e-10) return 0.0;
        double dist = MathAbs(price - m_fib_618);
        return 1.0 - MathMin(dist / range, 1.0);
    }

    bool _RefreshStoch()
    {
        double main_buf[], sig_buf[];
        ArraySetAsSeries(main_buf, true);
        ArraySetAsSeries(sig_buf,  true);
        if(CopyBuffer(m_stoch_handle, 0, 0, 1, main_buf) < 1) return false;
        if(CopyBuffer(m_stoch_handle, 1, 0, 1, sig_buf)  < 1) return false;
        m_stoch_main   = main_buf[0];
        m_stoch_signal = sig_buf[0];
        return true;
    }

    void _ReleaseHandles()
    {
        if(m_stoch_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_stoch_handle);
            m_stoch_handle = INVALID_HANDLE;
        }
    }

    bool _CreateHandles()
    {
        _ReleaseHandles();
        m_stoch_handle = iStochastic(m_symbol, m_timeframe,
                                     m_stoch_k, m_stoch_d, m_stoch_slowing,
                                     MODE_SMA, STO_LOWHIGH);
        if(m_stoch_handle == INVALID_HANDLE)
        {
            PrintFormat("[S13] ERROR: iStochastic failed on %s", m_symbol);
            return false;
        }
        return true;
    }

public:
    //=================================================================
    //  CONSTRUCTOR — set m_strategy_id + defaults from input vars
    //=================================================================
    CFibStoch()
    {
        m_strategy_id      = S13_FIB_STOCH;

        m_fib_lookback     = FS_Fib_Lookback;
        m_fib_inner        = FS_Fib_Inner;
        m_fib_outer        = FS_Fib_Outer;
        m_fib_sl           = FS_Fib_SL;
        m_stoch_k          = FS_Stoch_K;
        m_stoch_d          = FS_Stoch_D;
        m_stoch_slowing    = FS_Stoch_Slowing;
        m_stoch_oversold   = FS_Stoch_Oversold;
        m_stoch_overbought = FS_Stoch_OB;
        m_swing_min_bars   = FS_Swing_Min_Bars;

        m_stoch_handle     = INVALID_HANDLE;
        m_server_trend     = 0.0;

        m_swing_high       = 0.0;
        m_swing_low        = 0.0;
        m_swing_valid      = false;
        m_is_uptrend       = false;
        m_fib_382          = 0.0;
        m_fib_500          = 0.0;
        m_fib_618          = 0.0;
        m_fib_786          = 0.0;
        m_stoch_main       = 50.0;
        m_stoch_signal     = 50.0;
    }

    ~CFibStoch() { Deinit(); }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
    {
        // REQUIRED: call base class first
        if(!IStrategy::Init(symbol, tf)) return false;

        m_strategy_id = S13_FIB_STOCH;
        m_info        = g_strategy_table[S13_FIB_STOCH];

        // ServerOnly: start disabled, enable only when SetDynamicParams() called
        m_enabled     = false;

        m_swing_valid = false;
        m_server_trend= 0.0;

        if(!_CreateHandles()) return false;

        PrintFormat("[S13] Init OK (DISABLED - ServerOnly) | %s %s | Lookback=%d Stoch(%d,%d,%d) OB/OS=%d/%d",
                    m_symbol, EnumToString(m_timeframe),
                    m_fib_lookback,
                    m_stoch_k, m_stoch_d, m_stoch_slowing,
                    m_stoch_overbought, m_stoch_oversold);
        return true;
    }

    virtual void Deinit() override
    {
        _ReleaseHandles();
        IStrategy::Deinit();   // REQUIRED: call base
    }

    virtual void Analyze(const MqlTick &tick) override
    {
        if(!m_initialized || !m_enabled) return;

        // Re-detect swings once per bar
        static datetime last_bar = 0;
        datetime bar_time = iTime(m_symbol, m_timeframe, 0);
        if(bar_time != last_bar)
        {
            _FindSwings();
            last_bar = bar_time;
        }

        _RefreshStoch();

        // Default: no signal
        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
        m_state.last_sl         = 0.0;
        m_state.last_tp         = 0.0;

        if(!m_swing_valid) return;

        double price = tick.bid;
        if(!_PriceInFibZone(price)) return;

        // Compute confidence = fib_accuracy × stoch_extremity × trend_strength
        double fib_acc  = _FibAccuracy(price);
        double stoch_ext = 0.0;
        if(m_stoch_main <= (double)m_stoch_oversold)
            stoch_ext = 1.0 - (m_stoch_main / (double)m_stoch_oversold);
        else if(m_stoch_main >= (double)m_stoch_overbought)
            stoch_ext = (m_stoch_main - m_stoch_overbought) / (100.0 - m_stoch_overbought);

        double trend_str = MathAbs(m_server_trend);   // 0-1 (or ±1)
        double conf = MathMin(fib_acc * stoch_ext * trend_str, 1.0);

        // Long: uptrend pullback to fib zone + stoch oversold + server confirms up
        if(m_is_uptrend && m_stoch_main < (double)m_stoch_oversold && m_server_trend >= 0)
        {
            m_state.last_signal     = SIGNAL_BUY;
            m_state.last_confidence = conf;
            m_state.last_sl         = m_fib_786;     // SL beyond 78.6%
            m_state.last_tp         = m_swing_high;  // TP = swing High
        }
        // Short: downtrend pullback to fib zone + stoch overbought + server confirms down
        else if(!m_is_uptrend && m_stoch_main > (double)m_stoch_overbought && m_server_trend <= 0)
        {
            m_state.last_signal     = SIGNAL_SELL;
            m_state.last_confidence = conf;
            m_state.last_sl         = m_fib_786;     // SL beyond 78.6%
            m_state.last_tp         = m_swing_low;   // TP = swing Low
        }

        m_state.last_signal_time = TimeCurrent();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal()    override { return m_state.last_signal; }
    virtual double            GetConfidence()override { return m_state.last_confidence; }
    virtual double            GetStopLoss()  override { return m_state.last_sl; }
    virtual double            GetTakeProfit()override { return m_state.last_tp; }

    //=================================================================
    //  CONFIG INTERFACE
    //=================================================================

    virtual void SetParameters(const string jsonParams) override
    {
        IStrategy::SetParameters(jsonParams);
        // S13 uses SetDynamicParams (V2) — JSON path optional
    }

    virtual void SetDynamicParams(SDynamicParams &params) override
    {
        // REQUIRED: copies m_config.mm_method (Mistake 5 from lessons)
        IStrategy::SetDynamicParams(params);

        bool rebuild = false;

        int new_sk = (int)params.GetParam("S13_STOCH_K", (double)m_stoch_k);
        int new_sd = (int)params.GetParam("S13_STOCH_D", (double)m_stoch_d);
        if(new_sk != m_stoch_k || new_sd != m_stoch_d) rebuild = true;

        m_fib_lookback     = (int)params.GetParam("S13_FIB_LOOKBACK", (double)m_fib_lookback);
        m_stoch_k          = new_sk;
        m_stoch_d          = new_sd;
        m_stoch_oversold   = (int)params.GetParam("S13_STOCH_OB",     (double)m_stoch_oversold);
        m_stoch_overbought = (int)params.GetParam("S13_STOCH_OS",     (double)m_stoch_overbought);
        m_swing_min_bars   = (int)params.GetParam("S13_SWING_MIN",    (double)m_swing_min_bars);

        // Server trend context key
        if(params.HasParam("S13_TREND_DIR"))
            m_server_trend = params.GetParam("S13_TREND_DIR", 0.0);

        if(rebuild) _CreateHandles();

        // Activate strategy (ServerOnly: enable only after server connects)
        m_enabled     = true;
        m_swing_valid = false;   // Re-detect swings with new params
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = m_config.mm_method;   // REQUIRED (Mistake 5)
        p.SetParam("S13_FIB_LOOKBACK", (double)m_fib_lookback);
        p.SetParam("S13_STOCH_K",      (double)m_stoch_k);
        p.SetParam("S13_STOCH_D",      (double)m_stoch_d);
        p.SetParam("S13_STOCH_OB",     (double)m_stoch_oversold);
        p.SetParam("S13_STOCH_OS",     (double)m_stoch_overbought);
        p.SetParam("S13_SWING_MIN",    (double)m_swing_min_bars);
        return p;
    }

    //--- Identity overrides (correct method names from IStrategy)
    virtual int    GetMagic()            override { return MAGIC_S13_FIB_STOCH; }
    virtual string GetName()             override { return "Fibonacci + Stochastic"; }
    virtual bool   IsStandaloneCapable() override { return false; }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================
    bool   IsSwingValid()       const { return m_swing_valid; }
    bool   IsUptrend()          const { return m_is_uptrend; }
    double GetSwingHigh()       const { return m_swing_high; }
    double GetSwingLow()        const { return m_swing_low; }
    double GetFib382()          const { return m_fib_382; }
    double GetFib618()          const { return m_fib_618; }
    double GetFib786()          const { return m_fib_786; }
    double GetStochMain()       const { return m_stoch_main; }
};

#endif // S13_FIBSTOCH_MQH
