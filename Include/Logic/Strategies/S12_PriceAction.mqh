//+------------------------------------------------------------------+
//| S12_PriceAction.mqh                                              |
//| FlashEASuite V2 — Price Action (Pin Bar + Engulfing)            |
//| Magic: 1012 | Type: Full MQL5 | ServerOnly (standalone=false)  |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Pin Bar : body < 30% range, dominant wick > 60% range         |
//|  Engulfing: current body completely covers previous body        |
//|  Filter  : signal must be at key level (swing H/L, round#, S/R)|
//|  Exit    : TP = 2× candle range | SL = beyond pin bar wick     |
//|  Confidence = wick_ratio × volume_ratio × key_level_proximity  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S12_PRICEACTION_MQH
#define S12_PRICEACTION_MQH

#include "../IStrategy.mqh"
#include "PriceAction/PinBarDetector.mqh"
#include "PriceAction/EngulfingDetector.mqh"
#include "PriceAction/KeyLevelFinder.mqh"

//+------------------------------------------------------------------+
//| CS12PriceAction — Price Action Strategy                         |
//+------------------------------------------------------------------+
class CS12PriceAction : public IStrategy
{
private:
    //--- Sub-detectors: DIRECT MEMBERS (no pointer/new/delete — Lesson #2)
    CPinBarDetector     m_pinbar;
    CEngulfingDetector  m_engulfing;
    CKeyLevelFinder     m_key_levels;
    
    //--- Dynamic params (hot-reloadable via CONFIG_PUSH)
    double  m_body_max_ratio;        // Pin bar: body < X% of range (default 0.30)
    double  m_wick_min_ratio;        // Pin bar: wick > X% of range (default 0.60)
    double  m_min_proximity;         // Min key level proximity to trade (default 0.30)
    double  m_tp_multiplier;         // TP = N× candle range (default 2.0)
    double  m_conf_threshold;        // Min confidence to generate signal (default 0.40)
    int     m_swing_bars;            // Swing pivot detection bars each side (default 5)
    int     m_lookback;              // Bars to scan for key levels (default 100)
    
    //--- Volume indicator handle
    int     m_vol_handle;            // Volume MA handle
    int     m_vol_ma_handle;         // MA of volume for ratio
    
    //--- Diagnostic state (readable for logging)
    SPinBarResult       m_last_pinbar;
    SEngulfingResult    m_last_engulf;
    double              m_last_proximity;
    double              m_last_volume_ratio;
    double              m_last_tp;
    double              m_last_sl;
    
    //--- Bar tracking (process once per bar)
    datetime            m_last_bar_time;

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| _GetVolumeRatio: current bar volume / MA(volume, 20)           |
    //| Used as volume_on_pin multiplier for confidence                 |
    //+------------------------------------------------------------------+
    double _GetVolumeRatio(int bar_index = 1)
    {
        if(m_vol_handle == INVALID_HANDLE || m_vol_ma_handle == INVALID_HANDLE)
            return 1.0;
        
        double vol_buf[], vol_ma_buf[];
        ArraySetAsSeries(vol_buf,    true);
        ArraySetAsSeries(vol_ma_buf, true);
        
        if(CopyBuffer(m_vol_handle,    0, bar_index, 1, vol_buf)    < 1) return 1.0;
        if(CopyBuffer(m_vol_ma_handle, 0, bar_index, 1, vol_ma_buf) < 1) return 1.0;
        if(vol_ma_buf[0] <= 0) return 1.0;
        
        return MathMin(2.0, vol_buf[0] / vol_ma_buf[0]);  // cap at 2× for confidence
    }
    
    //+------------------------------------------------------------------+
    //| _CalcSLTP: Calculate SL/TP based on pin bar wick               |
    //| SL = beyond the wick, TP = 2× candle range                     |
    //+------------------------------------------------------------------+
    void _CalcSLTP(int bar_index, bool is_buy, double &sl, double &tp)
    {
        double high  = iHigh(m_symbol, m_timeframe, bar_index);
        double low   = iLow(m_symbol,  m_timeframe, bar_index);
        double range = high - low;
        double buffer = _Point * 5;   // small buffer beyond wick tip
        
        if(is_buy)
        {
            sl = low  - buffer;                       // beyond lower wick
            tp = iClose(m_symbol, m_timeframe, 0) + (range * m_tp_multiplier);
        }
        else
        {
            sl = high + buffer;                       // beyond upper wick
            tp = iClose(m_symbol, m_timeframe, 0) - (range * m_tp_multiplier);
        }
    }
    
    //+------------------------------------------------------------------+
    //| _ApplyDynamicParams: Called by SetDynamicParams()               |
    //+------------------------------------------------------------------+
    void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_body_max_ratio  = p.GetParam("S12_BODY_MAX_RATIO",  m_body_max_ratio);
        m_wick_min_ratio  = p.GetParam("S12_WICK_MIN_RATIO",  m_wick_min_ratio);
        m_min_proximity   = p.GetParam("S12_MIN_PROXIMITY",   m_min_proximity);
        m_tp_multiplier   = p.GetParam("S12_TP_MULT",         m_tp_multiplier);
        m_conf_threshold  = p.GetParam("S12_CONF_THRESHOLD",  m_conf_threshold);
        m_swing_bars      = (int)p.GetParam("S12_SWING_BARS", (double)m_swing_bars);
        m_lookback        = (int)p.GetParam("S12_LOOKBACK",   (double)m_lookback);
        
        m_config.mm_method = p.mm_method;   // ✅ REQUIRED — ห้ามลืม (Lesson #5)
        
        // Re-setup sub-detectors with new params
        m_pinbar.Setup(m_symbol, m_timeframe, m_body_max_ratio, m_wick_min_ratio);
        m_key_levels.Setup(m_symbol, m_timeframe, m_swing_bars, m_lookback);
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CS12PriceAction()
    {
        m_strategy_id = S12_PRICE_ACTION;
        
        // Default params
        m_body_max_ratio = 0.30;
        m_wick_min_ratio = 0.60;
        m_min_proximity  = 0.30;
        m_tp_multiplier  = 2.0;
        m_conf_threshold = 0.40;
        m_swing_bars     = 5;
        m_lookback       = 100;
        
        m_vol_handle     = INVALID_HANDLE;
        m_vol_ma_handle  = INVALID_HANDLE;
        m_last_bar_time  = 0;
        
        m_last_proximity    = 0.0;
        m_last_volume_ratio = 1.0;
        m_last_tp = 0.0;
        m_last_sl = 0.0;
        m_last_pinbar.Reset();
        m_last_engulf.Reset();
        
        // Set identity from StrategyConstants
        InitStrategyTable();
        m_info = g_strategy_table[S12_PRICE_ACTION];
    }
    
    //+------------------------------------------------------------------+
    //| Init: Initialize strategy                                        |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        m_symbol    = symbol;
        m_timeframe = tf;
        
        // Setup sub-detectors (Lesson #2: Setup() pattern)
        m_pinbar.Setup(symbol, tf, m_body_max_ratio, m_wick_min_ratio);
        m_engulfing.Setup(symbol, tf);
        bool kl_ok = m_key_levels.Setup(symbol, tf, m_swing_bars, m_lookback);
        
        // Volume indicators
        m_vol_handle    = iVolumes(symbol, tf, VOLUME_TICK);
        m_vol_ma_handle = iMA(symbol, tf, 20, 0, MODE_SMA, VOLUME_TICK);
        
        if(m_vol_handle == INVALID_HANDLE)
            Print("[S12] Warning: Volume handle failed — volume_ratio will default to 1.0");
        
        m_initialized = true;
        PrintFormat("[S12] Init OK | %s %s | KeyLevels:%s",
                    symbol, EnumToString(tf), kl_ok ? "OK" : "WARN");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinit: Release indicator handles                               |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        if(m_vol_handle    != INVALID_HANDLE) IndicatorRelease(m_vol_handle);
        if(m_vol_ma_handle != INVALID_HANDLE) IndicatorRelease(m_vol_ma_handle);
        m_vol_handle    = INVALID_HANDLE;
        m_vol_ma_handle = INVALID_HANDLE;
        m_initialized   = false;
    }
    
    //+------------------------------------------------------------------+
    //| Analyze: Main tick processing                                    |
    //| Only recalculate on new bar (bar_index=1 is fully closed)      |
    //+------------------------------------------------------------------+
    virtual void Analyze(MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;
        
        // Process once per bar (use bar open time as gate)
        datetime bar_time = iTime(m_symbol, m_timeframe, 1);
        if(bar_time == m_last_bar_time) return;
        m_last_bar_time = bar_time;
        
        // Refresh key levels
        m_key_levels.Scan();
        
        // Reset last signal
        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
        m_last_pinbar.Reset();
        m_last_engulf.Reset();
        
        // --- 1. Detect patterns on bar[1] (last closed)
        SPinBarResult    pb  = m_pinbar.Detect(1);
        SEngulfingResult eng = m_engulfing.Detect(1);
        
        double  curr_price    = tick.bid;
        double  proximity     = m_key_levels.GetProximity(iLow(m_symbol, m_timeframe, 1));
        double  volume_ratio  = _GetVolumeRatio(1);
        
        m_last_proximity    = proximity;
        m_last_volume_ratio = volume_ratio;
        
        // --- 2. Apply key-level filter
        if(proximity < m_min_proximity)
        {
            // No signal — not at key level
            return;
        }
        
        // --- 3. Pin Bar signal
        if(pb.type != PINBAR_NONE)
        {
            m_last_pinbar = pb;
            double confidence = pb.wick_ratio * MathMin(volume_ratio, 1.5) * proximity;
            confidence = MathMin(1.0, confidence);
            
            if(confidence >= m_conf_threshold)
            {
                m_state.last_confidence = confidence;
                
                if(pb.type == PINBAR_BULLISH)
                {
                    m_state.last_signal = SIGNAL_BUY;
                    _CalcSLTP(1, true, m_last_sl, m_last_tp);
                }
                else  // PINBAR_BEARISH
                {
                    m_state.last_signal = SIGNAL_SELL;
                    _CalcSLTP(1, false, m_last_sl, m_last_tp);
                }
                
                PrintFormat("[S12] PinBar %s | Conf:%.3f | Prox:%.2f | Vol:%.2f | SL:%.5f TP:%.5f",
                    pb.type == PINBAR_BULLISH ? "BULL" : "BEAR",
                    confidence, proximity, volume_ratio,
                    m_last_sl, m_last_tp);
                return;
            }
        }
        
        // --- 4. Engulfing signal (only if no pin bar signal)
        if(eng.type != ENGULF_NONE)
        {
            m_last_engulf = eng;
            double confidence = eng.size_ratio * 0.4 * proximity * MathMin(volume_ratio, 1.5);
            confidence = MathMin(1.0, confidence);
            
            if(confidence >= m_conf_threshold)
            {
                m_state.last_confidence = confidence;
                
                if(eng.type == ENGULF_BULLISH)
                {
                    m_state.last_signal = SIGNAL_BUY;
                    _CalcSLTP(1, true, m_last_sl, m_last_tp);
                }
                else  // ENGULF_BEARISH
                {
                    m_state.last_signal = SIGNAL_SELL;
                    _CalcSLTP(1, false, m_last_sl, m_last_tp);
                }
                
                PrintFormat("[S12] Engulfing %s | Conf:%.3f | SizeR:%.2f | Prox:%.2f | SL:%.5f TP:%.5f",
                    eng.type == ENGULF_BULLISH ? "BULL" : "BEAR",
                    confidence, eng.size_ratio, proximity,
                    m_last_sl, m_last_tp);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| GetSignal: Return last computed signal                          |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }
    
    //+------------------------------------------------------------------+
    //| GetConfidence: Return last confidence (0.0-1.0)                 |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }
    
    //+------------------------------------------------------------------+
    //| GetTP: Last computed take-profit price                          |
    //+------------------------------------------------------------------+
    double GetTP() const { return m_last_tp; }
    
    //+------------------------------------------------------------------+
    //| GetSL: Last computed stop-loss price                            |
    //+------------------------------------------------------------------+
    double GetSL() const { return m_last_sl; }
    
    //+------------------------------------------------------------------+
    //| SetDynamicParams: Called by StrategyManager on CONFIG_PUSH      |
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &p)
    {
        _ApplyDynamicParams(p);
    }
    
    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export current params for TRADE_REPORT        |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.SetParam("S12_BODY_MAX_RATIO", m_body_max_ratio);
        p.SetParam("S12_WICK_MIN_RATIO", m_wick_min_ratio);
        p.SetParam("S12_MIN_PROXIMITY",  m_min_proximity);
        p.SetParam("S12_TP_MULT",        m_tp_multiplier);
        p.SetParam("S12_CONF_THRESHOLD", m_conf_threshold);
        p.SetParam("S12_SWING_BARS",     (double)m_swing_bars);
        p.SetParam("S12_LOOKBACK",       (double)m_lookback);
        p.mm_method = m_config.mm_method;
        return p;
    }
    
    //--- Diagnostics
    double GetLastProximity()   const { return m_last_proximity; }
    double GetLastVolumeRatio() const { return m_last_volume_ratio; }
    int    GetKeyLevelCount()   const { return m_key_levels.GetLevelCount(); }
    SPinBarResult    GetLastPinBar()   const { return m_last_pinbar; }
    SEngulfingResult GetLastEngulfing() const { return m_last_engulf; }
};

#endif // S12_PRICEACTION_MQH
//+------------------------------------------------------------------+
