//+------------------------------------------------------------------+
//| S14_BBSqueeze.mqh                                                |
//| FlashEASuite V2 - Bollinger Squeeze Breakout                    |
//| Magic: 1014 | Type: Full MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Squeeze: BB Width < Keltner Channel Width (BB inside KC)       |
//|  Entry Long : Squeeze releases (BB > KC) AND LR slope > 0       |
//|  Entry Short: Squeeze releases AND LR slope < 0                 |
//|  TP = tp_atr_mult × ATR | SL = sl_atr_mult × ATR               |
//|  Confidence = min(|LR slope normalized by ATR|, 1.0)           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S14_BBSQUEEZE_MQH
#define S14_BBSQUEEZE_MQH

#include "../IStrategy.mqh"

//--- Input Parameters (standalone defaults — same pattern as S01)
// Optimized XAUUSD.tp H1 2022-2024: BB=25 KC=1.15 SqMin=6 SL/TP=3.4 | Custom=5.19 PF=1.863 DD=2.36% Trades=23/3y
// Validated 2026-03-07 OHLC-M1: PF=1.84 Profit=$635 DD=2.36% Trades=23 (98% match)
// Optimized GBPUSD.tp H1 2022-2024: BB=48 KC=1.50 SqMin=4 SL=2.5 TP=4.5 | PF=2.752 DD=4.01% Trades=25/3y
// Validated 2026-03-07 OHLC-M1: PF=2.76 Profit=$1812 DD=3.99% Trades=25 (100% match) — use S14_GBPUSD_H1_FINAL.set
input int    BS_BB_Period      = 25;    // Bollinger Bands period
input double BS_BB_Deviation   = 2.0;   // BB standard deviation multiplier
input int    BS_KC_Period      = 20;    // Keltner Channel EMA period
input double BS_KC_ATR_Mult    = 1.15;  // Keltner Channel ATR multiplier
input int    BS_Squeeze_Min    = 6;     // Min bars inside squeeze for valid setup
input double BS_Breakout_Mom   = 0.1;   // LR slope threshold (normalized by ATR)
input double BS_SL_ATR_Mult    = 3.4;   // Stop loss: N × ATR
input double BS_TP_ATR_Mult    = 3.4;   // Take profit: N × ATR
input int    BS_ATR_Period     = 14;    // ATR period
input int    BS_LR_Period      = 14;    // Linear regression period for slope

//+------------------------------------------------------------------+
//| CBBSqueeze - Bollinger Squeeze Breakout Strategy                 |
//+------------------------------------------------------------------+
class CBBSqueeze : public IStrategy
{
private:
    //--- Dynamic params
    int     m_bb_period;
    double  m_bb_deviation;
    int     m_kc_period;
    double  m_kc_atr_mult;
    int     m_squeeze_min_bars;
    double  m_breakout_momentum;
    double  m_sl_atr_mult;
    double  m_tp_atr_mult;
    int     m_atr_period;
    int     m_lr_period;

    //--- Indicator handles
    int     m_bb_handle;
    int     m_atr_handle;
    int     m_ema_handle;      // EMA as Keltner Channel midline

    //--- Internal state
    int      m_squeeze_bars;    // Consecutive bars with BB inside KC
    bool     m_was_in_squeeze;  // Did we just exit a valid squeeze?
    double   m_last_atr;
    double   m_lr_slope;        // LR slope normalized by ATR
    datetime m_last_bar_time;   // Bar-close guard: recompute once per bar

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    double _CalcBBWidth()
    {
        double upper[], lower[];
        ArraySetAsSeries(upper, true);
        ArraySetAsSeries(lower, true);
        if(CopyBuffer(m_bb_handle, 1, 0, 1, upper) < 1) return 0.0;
        if(CopyBuffer(m_bb_handle, 2, 0, 1, lower) < 1) return 0.0;
        return upper[0] - lower[0];
    }

    double _CalcKCWidth()
    {
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_atr_handle, 0, 0, 1, atr) < 1) return 0.0;
        return 2.0 * atr[0] * m_kc_atr_mult;
    }

    // Linear Regression slope (oldest→newest), normalized by ATR
    double _CalcLRSlope()
    {
        double closes[];
        ArraySetAsSeries(closes, true);
        int n = m_lr_period;
        if(CopyClose(m_symbol, m_timeframe, 0, n, closes) < n) return 0.0;

        double sx = 0, sy = 0, sxy = 0, sxx = 0;
        for(int i = 0; i < n; i++)
        {
            double x = (double)i;
            double y = closes[n - 1 - i];   // index 0 = oldest
            sx  += x;
            sy  += y;
            sxy += x * y;
            sxx += x * x;
        }
        double denom = n * sxx - sx * sx;
        if(MathAbs(denom) < 1e-10) return 0.0;
        double slope = (n * sxy - sx * sy) / denom;
        return (m_last_atr > 1e-10) ? slope / m_last_atr : 0.0;
    }

    void _RefreshATR()
    {
        double buf[];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_atr_handle, 0, 0, 1, buf) >= 1)
            m_last_atr = buf[0];
    }

    void _ReleaseHandles()
    {
        if(m_bb_handle  != INVALID_HANDLE) { IndicatorRelease(m_bb_handle);  m_bb_handle  = INVALID_HANDLE; }
        if(m_atr_handle != INVALID_HANDLE) { IndicatorRelease(m_atr_handle); m_atr_handle = INVALID_HANDLE; }
        if(m_ema_handle != INVALID_HANDLE) { IndicatorRelease(m_ema_handle); m_ema_handle = INVALID_HANDLE; }
    }

    bool _CreateHandles()
    {
        _ReleaseHandles();

        m_bb_handle = iBands(m_symbol, m_timeframe, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
        if(m_bb_handle == INVALID_HANDLE)
        {
            PrintFormat("[S14] ERROR: iBands failed on %s", m_symbol);
            return false;
        }

        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            PrintFormat("[S14] ERROR: iATR failed on %s", m_symbol);
            return false;
        }

        // EMA used as KC midline (KC = EMA ± ATR×mult)
        m_ema_handle = iMA(m_symbol, m_timeframe, m_kc_period, 0, MODE_EMA, PRICE_CLOSE);
        if(m_ema_handle == INVALID_HANDLE)
        {
            PrintFormat("[S14] ERROR: iMA(EMA) failed on %s", m_symbol);
            return false;
        }

        return true;
    }

public:
    //=================================================================
    //  CONSTRUCTOR — set m_strategy_id + defaults from input vars (S01 pattern)
    //=================================================================
    CBBSqueeze()
    {
        m_strategy_id       = S14_BB_SQUEEZE;

        m_bb_period         = BS_BB_Period;
        m_bb_deviation      = BS_BB_Deviation;
        m_kc_period         = BS_KC_Period;
        m_kc_atr_mult       = BS_KC_ATR_Mult;
        m_squeeze_min_bars  = BS_Squeeze_Min;
        m_breakout_momentum = BS_Breakout_Mom;
        m_sl_atr_mult       = BS_SL_ATR_Mult;
        m_tp_atr_mult       = BS_TP_ATR_Mult;
        m_atr_period        = BS_ATR_Period;
        m_lr_period         = BS_LR_Period;

        m_bb_handle         = INVALID_HANDLE;
        m_atr_handle        = INVALID_HANDLE;
        m_ema_handle        = INVALID_HANDLE;

        m_squeeze_bars      = 0;
        m_was_in_squeeze    = false;
        m_last_atr          = 0.0;
        m_lr_slope          = 0.0;
        m_last_bar_time     = 0;
    }

    ~CBBSqueeze() { Deinit(); }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
    {
        // REQUIRED: call base class first
        if(!IStrategy::Init(symbol, tf)) return false;

        // Override strategy identity (base defaults to S01)
        m_strategy_id = S14_BB_SQUEEZE;
        m_info        = g_strategy_table[S14_BB_SQUEEZE];

        m_squeeze_bars   = 0;
        m_was_in_squeeze = false;
        m_last_atr       = 0.0;
        m_last_bar_time  = 0;

        // S14 is standalone: enable immediately
        m_enabled = true;

        if(!_CreateHandles()) return false;

        PrintFormat("[S14] Init OK | %s %s | BB(%d,%.1f) KC(%d,%.1f) SqueezeMin=%d",
                    m_symbol, EnumToString(m_timeframe),
                    m_bb_period, m_bb_deviation,
                    m_kc_period, m_kc_atr_mult,
                    m_squeeze_min_bars);
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

        // ── Bar-close guard: recompute squeeze state once per bar ────────
        // Prevents m_was_in_squeeze from resetting on every tick of the
        // same release bar (which would kill the signal after tick #1).
        datetime cur_bar_time = iTime(m_symbol, m_timeframe, 0);
        if(cur_bar_time != m_last_bar_time)
        {
            m_last_bar_time = cur_bar_time;

            _RefreshATR();

            double bb_w = _CalcBBWidth();
            double kc_w = _CalcKCWidth();
            bool   in_squeeze = (kc_w > 1e-10) && (bb_w < kc_w);

            if(in_squeeze)
            {
                m_squeeze_bars++;
                m_was_in_squeeze = false;   // still building, not released yet
            }
            else
            {
                // Squeeze released this bar — was it long enough?
                m_was_in_squeeze = (m_squeeze_bars >= m_squeeze_min_bars);
                m_squeeze_bars   = 0;       // reset counter
            }

            m_lr_slope = _CalcLRSlope();
        }

        // Default: no signal
        ENUM_TRADE_SIGNAL sig  = SIGNAL_NONE;
        double            conf = 0.0;
        double            sl   = 0.0;
        double            tp   = 0.0;

        if(m_was_in_squeeze && MathAbs(m_lr_slope) >= m_breakout_momentum)
        {
            sig  = (m_lr_slope > 0) ? SIGNAL_BUY : SIGNAL_SELL;
            conf = MathMin(MathAbs(m_lr_slope), 1.0);   // slope/ATR as confidence

            double price = tick.bid;
            if(sig == SIGNAL_BUY)
            {
                sl = price - m_sl_atr_mult * m_last_atr;
                tp = price + m_tp_atr_mult * m_last_atr;
            }
            else
            {
                sl = price + m_sl_atr_mult * m_last_atr;
                tp = price - m_tp_atr_mult * m_last_atr;
            }
        }

        // Store in m_state — GetSignal/GetStopLoss/GetTakeProfit read from here
        m_state.last_signal      = sig;
        m_state.last_confidence  = conf;
        m_state.last_sl          = sl;
        m_state.last_tp          = tp;
        m_state.last_signal_time = TimeCurrent();
    }

    // GetSignal, GetConfidence, GetStopLoss, GetTakeProfit — read m_state
    // (base class implementations already return m_state fields — but override for clarity)
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
        // V1 JSON — S14 primarily uses SetDynamicParams (V2)
    }

    virtual void SetDynamicParams(SDynamicParams &params) override
    {
        // REQUIRED: copies m_config.mm_method (Mistake 5 from lessons)
        IStrategy::SetDynamicParams(params);

        bool rebuild = false;

        int    new_bb_p   = (int)params.GetParam("S14_BB_PERIOD",   (double)m_bb_period);
        double new_bb_dev =      params.GetParam("S14_BB_DEV",      m_bb_deviation);
        int    new_kc_p   = (int)params.GetParam("S14_KC_PERIOD",   (double)m_kc_period);
        double new_kc_m   =      params.GetParam("S14_KC_ATR_MULT", m_kc_atr_mult);

        if(new_bb_p != m_bb_period || MathAbs(new_bb_dev - m_bb_deviation) > 0.001 ||
           new_kc_p != m_kc_period || MathAbs(new_kc_m   - m_kc_atr_mult)  > 0.001)
            rebuild = true;

        m_bb_period         = new_bb_p;
        m_bb_deviation      = new_bb_dev;
        m_kc_period         = new_kc_p;
        m_kc_atr_mult       = new_kc_m;
        m_squeeze_min_bars  = (int)params.GetParam("S14_SQUEEZE_MIN",   (double)m_squeeze_min_bars);
        m_breakout_momentum =      params.GetParam("S14_BREAKOUT_MOM",  m_breakout_momentum);
        m_sl_atr_mult       =      params.GetParam("S14_SL_ATR",        m_sl_atr_mult);
        m_tp_atr_mult       =      params.GetParam("S14_TP_ATR",        m_tp_atr_mult);

        if(rebuild) _CreateHandles();
        m_enabled = true;
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = m_config.mm_method;   // REQUIRED (Mistake 5)
        p.SetParam("S14_BB_PERIOD",    (double)m_bb_period);
        p.SetParam("S14_BB_DEV",       m_bb_deviation);
        p.SetParam("S14_KC_PERIOD",    (double)m_kc_period);
        p.SetParam("S14_KC_ATR_MULT",  m_kc_atr_mult);
        p.SetParam("S14_SQUEEZE_MIN",  (double)m_squeeze_min_bars);
        p.SetParam("S14_BREAKOUT_MOM", m_breakout_momentum);
        p.SetParam("S14_SL_ATR",       m_sl_atr_mult);
        p.SetParam("S14_TP_ATR",       m_tp_atr_mult);
        return p;
    }

    //--- Identity overrides (correct method names from IStrategy)
    virtual int    GetMagic()             override { return MAGIC_S14_BB_SQUEEZE; }
    virtual string GetName()              override { return "BB Squeeze Breakout"; }
    virtual bool   IsStandaloneCapable()  override { return true; }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================
    bool   IsInSqueezeState() const { return m_was_in_squeeze; }
    int    GetSqueezeCount()  const { return m_squeeze_bars; }
    double GetLRSlope()       const { return m_lr_slope; }
    double GetLastATR()       const { return m_last_atr; }
};

#endif // S14_BBSQUEEZE_MQH
