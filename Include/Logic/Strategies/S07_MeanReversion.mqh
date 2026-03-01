//+------------------------------------------------------------------+
//| S07_MeanReversion.mqh                                            |
//| FlashEASuite V2 — Mean Reversion (Volatility-Filtered)          |
//| Magic: 1007 | Type: Full MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Entry Long : RSI(14) < 30 AND Stochastic(14,3,3) < 20         |
//|  Entry Short: RSI(14) > 70 AND Stochastic(14,3,3) > 80         |
//|  Vol Filter : ATR(14) < VolFilter × MA(ATR,20) — skip if high  |
//|  Take Profit: Middle Bollinger Band (20,2)                      |
//|  Stop Loss  : ±2 × ATR(14)                                      |
//|  Confidence : f(|Z-score of RSI from 50|, vol_factor)           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S07_MEANREVERSION_MQH
#define S07_MEANREVERSION_MQH

#include "../IStrategy.mqh"

//--- Input Parameters
input int    MR_RSI_Period  = 14;    // RSI period
input double MR_RSI_Buy     = 30.0;  // RSI oversold threshold
input double MR_RSI_Sell    = 70.0;  // RSI overbought threshold
input int    MR_Stoch_K     = 14;    // Stochastic %K period
input int    MR_Stoch_D     = 3;     // Stochastic %D smoothing
input int    MR_Stoch_Slow  = 3;     // Stochastic slowing
input double MR_Stoch_Buy   = 20.0;  // Stochastic oversold threshold
input double MR_Stoch_Sell  = 80.0;  // Stochastic overbought threshold
input int    MR_ATR_Period  = 14;    // ATR period
input int    MR_ATR_MA      = 20;    // ATR moving average period (vol reference)
input double MR_VolFilter   = 1.3;   // Max ATR/MA(ATR) ratio (>ratio = skip trade)
input int    MR_BB_Period   = 20;    // Bollinger Band period (for TP)
input double MR_BB_Dev      = 2.0;   // Bollinger Band standard deviation
input double MR_SL_ATRMult  = 2.0;   // Stop loss = N × ATR
input double MR_TP_ATRMult  = 1.5;   // TP multiplier relative to ATR (overrides BB if BB=0)

//+------------------------------------------------------------------+
//| CMeanReversion — Mean Reversion Strategy                         |
//+------------------------------------------------------------------+
class CMeanReversion : public IStrategy
{
private:
    //--- Dynamic params (hot-reloadable via CONFIG_PUSH)
    int     m_rsi_period;
    double  m_rsi_buy;
    double  m_rsi_sell;
    int     m_stoch_k;
    int     m_stoch_d;
    int     m_stoch_slow;
    double  m_stoch_buy;
    double  m_stoch_sell;
    int     m_atr_period;
    int     m_atr_ma;
    double  m_vol_filter;
    int     m_bb_period;
    double  m_bb_dev;
    double  m_sl_atr_mult;
    double  m_tp_atr_mult;

    //--- Indicator handles
    int     m_rsi_handle;
    int     m_stoch_handle;
    int     m_atr_handle;
    int     m_bb_handle;
    int     m_atr_ma_handle;  // MA of ATR for vol filter

    //--- Internal diagnostic state
    double  m_last_rsi;
    double  m_last_stoch_k;
    double  m_last_atr;
    double  m_last_atr_ma;
    double  m_last_bb_mid;
    bool    m_vol_ok;          // Did last tick pass vol filter?

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    //+------------------------------------------------------------------+
    //| _GetIndicatorValue: Safe single-value read from indicator       |
    //+------------------------------------------------------------------+
    double _GetIndicatorValue(int handle, int buffer, int shift = 0)
    {
        if(handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(handle, buffer, shift, 1, buf) != 1) return 0.0;
        return buf[0];
    }

    //+------------------------------------------------------------------+
    //| _InitIndicators: Create all indicator handles                   |
    //+------------------------------------------------------------------+
    bool _InitIndicators()
    {
        _ReleaseIndicators();

        m_rsi_handle = iRSI(m_symbol, m_timeframe, m_rsi_period, PRICE_CLOSE);
        if(m_rsi_handle == INVALID_HANDLE)
        {
            Print("[S07] ERROR: Failed to create RSI indicator");
            return false;
        }

        m_stoch_handle = iStochastic(m_symbol, m_timeframe,
                                      m_stoch_k, m_stoch_d, m_stoch_slow,
                                      MODE_SMA, STO_LOWHIGH);
        if(m_stoch_handle == INVALID_HANDLE)
        {
            Print("[S07] ERROR: Failed to create Stochastic indicator");
            return false;
        }

        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S07] ERROR: Failed to create ATR indicator");
            return false;
        }

        // MA of ATR: use iMA applied to ATR buffer
        // MQL5 does not support applying iMA directly to another indicator,
        // so we compute MA of ATR manually in Analyze()
        m_atr_ma_handle = iATR(m_symbol, m_timeframe, m_atr_period);  // Same handle reused

        m_bb_handle = iBands(m_symbol, m_timeframe, m_bb_period, 0, m_bb_dev, PRICE_CLOSE);
        if(m_bb_handle == INVALID_HANDLE)
        {
            Print("[S07] ERROR: Failed to create Bollinger Bands indicator");
            return false;
        }

        PrintFormat("[S07] Indicators initialized | RSI=%d Stoch=%d/%d/%d ATR=%d BB=%d/%.1f",
                    m_rsi_period, m_stoch_k, m_stoch_d, m_stoch_slow,
                    m_atr_period, m_bb_period, m_bb_dev);
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ReleaseIndicators: Free indicator handles                      |
    //+------------------------------------------------------------------+
    void _ReleaseIndicators()
    {
        if(m_rsi_handle    != INVALID_HANDLE) { IndicatorRelease(m_rsi_handle);    m_rsi_handle    = INVALID_HANDLE; }
        if(m_stoch_handle  != INVALID_HANDLE) { IndicatorRelease(m_stoch_handle);  m_stoch_handle  = INVALID_HANDLE; }
        if(m_atr_handle    != INVALID_HANDLE) { IndicatorRelease(m_atr_handle);    m_atr_handle    = INVALID_HANDLE; }
        if(m_bb_handle     != INVALID_HANDLE) { IndicatorRelease(m_bb_handle);     m_bb_handle     = INVALID_HANDLE; }
        // m_atr_ma_handle is the same as m_atr_handle (already released above)
        m_atr_ma_handle = INVALID_HANDLE;
    }

    //+------------------------------------------------------------------+
    //| _CalcATRMovingAvg: Manual MA of ATR over m_atr_ma bars         |
    //+------------------------------------------------------------------+
    double _CalcATRMovingAvg()
    {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_atr_handle, 0, 0, m_atr_ma, buf) < m_atr_ma) return 0.0;
        double sum = 0.0;
        for(int i = 0; i < m_atr_ma; i++) sum += buf[i];
        return sum / m_atr_ma;
    }

    //+------------------------------------------------------------------+
    //| _CalcConfidence: Confidence from RSI deviation + vol factor     |
    //+------------------------------------------------------------------+
    double _CalcConfidence(double rsi, double stoch_k, double atr, double atr_ma)
    {
        // Z-score component: how far RSI deviates from 50
        double rsi_z_raw = MathAbs(rsi - 50.0) / 50.0;  // 0.0 (neutral) → 1.0 (extreme)

        // Stochastic confirmation weight
        double stoch_conf = 0.0;
        if(stoch_k < m_stoch_buy)
            stoch_conf = (m_stoch_buy - stoch_k) / m_stoch_buy;   // 0 → 1 as stoch → 0
        else if(stoch_k > m_stoch_sell)
            stoch_conf = (stoch_k - m_stoch_sell) / (100.0 - m_stoch_sell);

        // Volatility factor: lower vol relative to mean = better for mean reversion
        double vol_factor = 1.0;
        if(atr_ma > 0)
        {
            double ratio = atr / atr_ma;
            if(ratio <= 1.0)
                vol_factor = 1.0;       // ATR below average = best conditions
            else if(ratio <= m_vol_filter)
                vol_factor = 1.0 - (ratio - 1.0) / (m_vol_filter - 1.0) * 0.3;  // Slight penalty
            else
                vol_factor = 0.0;       // Filtered out — should not reach here
        }

        // Combine: weighted average
        double conf = (rsi_z_raw * 0.5 + stoch_conf * 0.5) * vol_factor;
        return MathMax(0.0, MathMin(1.0, conf));
    }

    //+------------------------------------------------------------------+
    //| _ParseJsonDouble: Simple JSON extractor                         |
    //+------------------------------------------------------------------+
    double _ParseJsonDouble(const string &json, const string key, double default_val)
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return default_val;
        int start = pos + StringLen(search);
        while(start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;
        string num_str = "";
        for(int i = start; i < MathMin(start + 20, StringLen(json)); i++)
        {
            ushort ch = StringGetCharacter(json, i);
            if(ch == ',' || ch == '}' || ch == ' ' || ch == '\n') break;
            num_str += ShortToString(ch);
        }
        return (num_str != "") ? StringToDouble(num_str) : default_val;
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CMeanReversion()
    {
        m_strategy_id   = S07_MEAN_REVERSION;

        // Defaults from inputs
        m_rsi_period    = MR_RSI_Period;
        m_rsi_buy       = MR_RSI_Buy;
        m_rsi_sell      = MR_RSI_Sell;
        m_stoch_k       = MR_Stoch_K;
        m_stoch_d       = MR_Stoch_D;
        m_stoch_slow    = MR_Stoch_Slow;
        m_stoch_buy     = MR_Stoch_Buy;
        m_stoch_sell    = MR_Stoch_Sell;
        m_atr_period    = MR_ATR_Period;
        m_atr_ma        = MR_ATR_MA;
        m_vol_filter    = MR_VolFilter;
        m_bb_period     = MR_BB_Period;
        m_bb_dev        = MR_BB_Dev;
        m_sl_atr_mult   = MR_SL_ATRMult;
        m_tp_atr_mult   = MR_TP_ATRMult;

        m_rsi_handle    = INVALID_HANDLE;
        m_stoch_handle  = INVALID_HANDLE;
        m_atr_handle    = INVALID_HANDLE;
        m_bb_handle     = INVALID_HANDLE;
        m_atr_ma_handle = INVALID_HANDLE;

        m_last_rsi      = 50.0;
        m_last_stoch_k  = 50.0;
        m_last_atr      = 0.0;
        m_last_atr_ma   = 0.0;
        m_last_bb_mid   = 0.0;
        m_vol_ok        = false;
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CMeanReversion()
    {
        Deinit();
    }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    //+------------------------------------------------------------------+
    //| Init: Create indicator handles                                  |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;

        m_strategy_id = S07_MEAN_REVERSION;
        m_info = g_strategy_table[S07_MEAN_REVERSION];

        if(!_InitIndicators())
        {
            m_initialized = false;
            return false;
        }

        m_initialized = true;
        PrintFormat("[S07] MeanReversion Init OK | %s %s | RSI<%d  Stoch<%d  Vol×%.1f  BB(%d,%.1f)",
                    symbol, EnumToString(tf),
                    m_rsi_period, m_stoch_k, m_vol_filter, m_bb_period, m_bb_dev);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release indicator handles                               |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        _ReleaseIndicators();
        IStrategy::Deinit();
    }

    //+------------------------------------------------------------------+
    //| Analyze: Process tick, update signal                            |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;

        // --- Read indicator values (shift=1 = last closed bar for stability)
        double rsi     = _GetIndicatorValue(m_rsi_handle,   0, 1);
        double stoch_k = _GetIndicatorValue(m_stoch_handle, 0, 1);  // Buffer 0 = %K
        double atr     = _GetIndicatorValue(m_atr_handle,   0, 1);
        double bb_mid  = _GetIndicatorValue(m_bb_handle,    1, 1);  // Buffer 1 = Middle band

        // Validate (0.0 means data not ready)
        if(rsi <= 0.0 || stoch_k < 0.0 || atr <= 0.0)
        {
            // Indicator not ready yet (insufficient history)
            m_state.last_signal = SIGNAL_NONE;
            return;
        }

        // --- Calculate ATR moving average (manual)
        double atr_ma = _CalcATRMovingAvg();
        if(atr_ma <= 0.0) atr_ma = atr;  // Fallback if not enough bars

        // --- Store diagnostics
        m_last_rsi     = rsi;
        m_last_stoch_k = stoch_k;
        m_last_atr     = atr;
        m_last_atr_ma  = atr_ma;
        m_last_bb_mid  = bb_mid;

        // --- Volatility Filter
        // Block trading if ATR > VolFilter × MA(ATR)
        bool vol_ok = (atr < m_vol_filter * atr_ma);
        m_vol_ok = vol_ok;

        if(!vol_ok)
        {
            // High volatility — stand aside, but don't force exit existing trades
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            m_state.last_sl         = 0.0;
            m_state.last_tp         = 0.0;
            return;
        }

        // --- Entry Conditions
        // Long: RSI oversold AND Stochastic oversold
        bool long_condition  = (rsi < m_rsi_buy  && stoch_k < m_stoch_buy);
        // Short: RSI overbought AND Stochastic overbought
        bool short_condition = (rsi > m_rsi_sell && stoch_k > m_stoch_sell);

        ENUM_TRADE_SIGNAL new_signal = SIGNAL_NONE;

        if(long_condition)
            new_signal = SIGNAL_BUY;
        else if(short_condition)
            new_signal = SIGNAL_SELL;

        // --- Calculate SL / TP
        double ask = tick.ask;
        double bid = tick.bid;
        double sl  = 0.0;
        double tp  = 0.0;

        if(new_signal == SIGNAL_BUY)
        {
            sl = ask - (m_sl_atr_mult * atr);
            // TP = Middle Bollinger Band (if above entry, else use ATR multiplier)
            tp = (bb_mid > ask) ? bb_mid : (ask + m_tp_atr_mult * atr);
        }
        else if(new_signal == SIGNAL_SELL)
        {
            sl = bid + (m_sl_atr_mult * atr);
            tp = (bb_mid < bid) ? bb_mid : (bid - m_tp_atr_mult * atr);
        }

        // --- Confidence
        double conf = 0.0;
        if(new_signal != SIGNAL_NONE)
            conf = _CalcConfidence(rsi, stoch_k, atr, atr_ma);

        // --- Update state
        m_state.last_signal     = new_signal;
        m_state.last_confidence = conf;
        m_state.last_sl         = sl;
        m_state.last_tp         = tp;
        m_state.last_signal_time = TimeCurrent();
    }

    //+------------------------------------------------------------------+
    //| GetSignal: Return current signal                                |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }

    //+------------------------------------------------------------------+
    //| GetConfidence: Return signal confidence                         |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }

    //=================================================================
    //  CONFIG INTERFACE
    //=================================================================

    //+------------------------------------------------------------------+
    //| SetParameters: Parse JSON from CONFIG_PUSH                      |
    //| Keys: MR_RSI_Period, MR_RSI_Buy, MR_RSI_Sell, MR_VolFilter,    |
    //|       MR_BB_Period, MR_SL_ATRMult                               |
    //+------------------------------------------------------------------+
    virtual void SetParameters(const string jsonParams)
    {
        IStrategy::SetParameters(jsonParams);
        if(jsonParams == "") return;

        bool need_reinit = false;

        double v;
        int iv;

        v = _ParseJsonDouble(jsonParams, "MR_RSI_Period", (double)m_rsi_period);
        iv = (int)MathMax(2, v);
        if(iv != m_rsi_period) { OnParamUpdate("MR_RSI_Period", (double)m_rsi_period, v); m_rsi_period = iv; need_reinit = true; }

        v = _ParseJsonDouble(jsonParams, "MR_RSI_Buy", m_rsi_buy);
        if(MathAbs(v - m_rsi_buy) > 0.01) { OnParamUpdate("MR_RSI_Buy", m_rsi_buy, v); m_rsi_buy = v; }

        v = _ParseJsonDouble(jsonParams, "MR_RSI_Sell", m_rsi_sell);
        if(MathAbs(v - m_rsi_sell) > 0.01) { OnParamUpdate("MR_RSI_Sell", m_rsi_sell, v); m_rsi_sell = v; }

        v = _ParseJsonDouble(jsonParams, "MR_VolFilter", m_vol_filter);
        if(MathAbs(v - m_vol_filter) > 0.01) { OnParamUpdate("MR_VolFilter", m_vol_filter, v); m_vol_filter = v; }

        v = _ParseJsonDouble(jsonParams, "MR_BB_Period", (double)m_bb_period);
        iv = (int)MathMax(5, v);
        if(iv != m_bb_period) { OnParamUpdate("MR_BB_Period", (double)m_bb_period, v); m_bb_period = iv; need_reinit = true; }

        v = _ParseJsonDouble(jsonParams, "MR_BB_Dev", m_bb_dev);
        if(MathAbs(v - m_bb_dev) > 0.01) { OnParamUpdate("MR_BB_Dev", m_bb_dev, v); m_bb_dev = v; need_reinit = true; }

        v = _ParseJsonDouble(jsonParams, "MR_SL_ATRMult", m_sl_atr_mult);
        if(MathAbs(v - m_sl_atr_mult) > 0.01) { OnParamUpdate("MR_SL_ATRMult", m_sl_atr_mult, v); m_sl_atr_mult = v; }

        v = _ParseJsonDouble(jsonParams, "MR_TP_ATRMult", m_tp_atr_mult);
        if(MathAbs(v - m_tp_atr_mult) > 0.01) { OnParamUpdate("MR_TP_ATRMult", m_tp_atr_mult, v); m_tp_atr_mult = v; }

        if(need_reinit && m_initialized)
        {
            PrintFormat("[S07] Params changed — reinitializing indicators");
            _InitIndicators();
        }
    }

    //+------------------------------------------------------------------+
    //| SetDynamicParams: Apply CONFIG_PUSH V2 bundle                   |
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &params)
    {
        IStrategy::SetDynamicParams(params);

        bool need_reinit = false;
        double v; int iv;

        v = params.GetParam("S07_RSI_PERIOD",  (double)m_rsi_period); iv = (int)v; if(iv > 0 && iv != m_rsi_period)  { OnParamUpdate("S07_RSI_PERIOD",  (double)m_rsi_period, v);  m_rsi_period  = iv; need_reinit = true; }
        v = params.GetParam("S07_RSI_BUY",     m_rsi_buy);            if(MathAbs(v - m_rsi_buy)    > 0.01) { OnParamUpdate("S07_RSI_BUY",     m_rsi_buy,    v); m_rsi_buy    = v; }
        v = params.GetParam("S07_RSI_SELL",    m_rsi_sell);           if(MathAbs(v - m_rsi_sell)   > 0.01) { OnParamUpdate("S07_RSI_SELL",    m_rsi_sell,   v); m_rsi_sell   = v; }
        v = params.GetParam("S07_VOL_FILTER",  m_vol_filter);         if(MathAbs(v - m_vol_filter)  > 0.01) { OnParamUpdate("S07_VOL_FILTER",  m_vol_filter, v); m_vol_filter = v; }
        v = params.GetParam("S07_SL_ATR_MULT", m_sl_atr_mult);        if(MathAbs(v - m_sl_atr_mult) > 0.01) { OnParamUpdate("S07_SL_ATR_MULT", m_sl_atr_mult,v); m_sl_atr_mult= v; }
        v = params.GetParam("S07_TP_ATR_MULT", m_tp_atr_mult);        if(MathAbs(v - m_tp_atr_mult) > 0.01) { OnParamUpdate("S07_TP_ATR_MULT", m_tp_atr_mult,v); m_tp_atr_mult= v; }

        if(need_reinit && m_initialized)
            _InitIndicators();
    }

    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export params for TRADE_REPORT                |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = m_config.mm_method;
        p.SetParam("S07_RSI_PERIOD",  (double)m_rsi_period);
        p.SetParam("S07_RSI_BUY",     m_rsi_buy);
        p.SetParam("S07_RSI_SELL",    m_rsi_sell);
        p.SetParam("S07_VOL_FILTER",  m_vol_filter);
        p.SetParam("S07_SL_ATR_MULT", m_sl_atr_mult);
        p.SetParam("S07_TP_ATR_MULT", m_tp_atr_mult);
        return p;
    }

    //=================================================================
    //  IDENTITY
    //=================================================================

    virtual string GetName()         { return "Mean Reversion (Vol-Filtered)"; }
    virtual int    GetMagic()        { return MAGIC_S07_MEAN_REV; }
    virtual bool   IsStandaloneCapable() { return true; }
    virtual string GetCategory()     { return "Full_MQL5"; }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================

    //+------------------------------------------------------------------+
    //| PrintDiagnostics: Full state dump                               |
    //+------------------------------------------------------------------+
    void PrintDiagnostics()
    {
        PrintFormat("[S07] MeanRev | RSI=%.2f(<%g/>%g) Stoch=%.2f(<%g/>%g)",
                    m_last_rsi, m_rsi_buy, m_rsi_sell,
                    m_last_stoch_k, m_stoch_buy, m_stoch_sell);
        PrintFormat("[S07] ATR=%.5f ATR_MA=%.5f Ratio=%.2f VolFilter=%.1f VolOK=%s",
                    m_last_atr, m_last_atr_ma,
                    (m_last_atr_ma > 0) ? m_last_atr / m_last_atr_ma : 0.0,
                    m_vol_filter, m_vol_ok ? "YES" : "NO");
        PrintFormat("[S07] BB_Mid=%.5f Signal=%s Conf=%.4f SL=%.5f TP=%.5f",
                    m_last_bb_mid,
                    SignalToString(m_state.last_signal),
                    m_state.last_confidence,
                    m_state.last_sl,
                    m_state.last_tp);
    }

    //+------------------------------------------------------------------+
    //| GetLastRSI / GetLastATR: For external monitoring                |
    //+------------------------------------------------------------------+
    double GetLastRSI()   const { return m_last_rsi;    }
    double GetLastATR()   const { return m_last_atr;    }
    bool   GetVolOK()     const { return m_vol_ok;      }
};

#endif // S07_MEANREVERSION_MQH
//+------------------------------------------------------------------+
