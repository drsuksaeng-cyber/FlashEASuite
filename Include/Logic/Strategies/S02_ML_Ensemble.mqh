//+------------------------------------------------------------------+
//| S02_ML_Ensemble.mqh                                              |
//| FlashEASuite V2 — ML Ensemble Wrapper (Hybrid)                  |
//| Magic: 1002 | Type: Hybrid | ServerOnly (standalone=false)      |
//+------------------------------------------------------------------+
//| LOGIC (Thin Wrapper):                                            |
//|  - Receives ml_signal and ml_confidence from CONFIG_PUSH        |
//|  - if ml_signal==1 AND ml_confidence>0.70 → BUY                |
//|  - if ml_signal==-1 AND ml_confidence>0.70 → SELL              |
//|  - Signal timeout: 5 minutes (auto-close if no new signal)     |
//|  - MQL5 manages execution + trailing stop                       |
//|  - Confidence = ml_confidence (passed from server, no modify)  |
//+------------------------------------------------------------------+
//| DESIGN NOTE: This file is intentionally thin. All ML analysis   |
//| runs in Python Brain (S02 in core/intelligence/). MQL5 only     |
//| executes what the server decides.                               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S02_ML_ENSEMBLE_MQH
#define S02_ML_ENSEMBLE_MQH

#include "../IStrategy.mqh"

//+------------------------------------------------------------------+
//| CS02MLEnsemble — ML Ensemble Thin Wrapper                       |
//+------------------------------------------------------------------+
class CS02MLEnsemble : public IStrategy
{
private:
    //--- Params received from server via CONFIG_PUSH SetParameters()
    int     m_ml_signal;          // 1=BUY, -1=SELL, 0=NONE (from server)
    double  m_ml_confidence;      // 0.0-1.0 (from server, no MQL5 recalc)
    double  m_conf_threshold;     // Minimum confidence to execute (default 0.70)
    int     m_signal_timeout_sec; // Seconds before stale signal is discarded (default 300)
    double  m_trailing_atr_mult;  // Trailing stop = N × ATR (default 1.5)
    
    //--- Signal tracking
    datetime        m_signal_time;       // When current ml_signal was received
    int             m_atr_handle;        // ATR for trailing stop calc
    double          m_last_atr;          // Most recent ATR value
    
    //--- State
    bool    m_signal_active;             // Is there a valid, non-expired signal?

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| _IsSignalExpired: Check if signal is older than timeout         |
    //+------------------------------------------------------------------+
    bool _IsSignalExpired() const
    {
        if(m_signal_time == 0) return true;
        return (int)(TimeCurrent() - m_signal_time) > m_signal_timeout_sec;
    }
    
    //+------------------------------------------------------------------+
    //| _UpdateATR: Refresh ATR value for trailing stop                 |
    //+------------------------------------------------------------------+
    void _UpdateATR()
    {
        if(m_atr_handle == INVALID_HANDLE) return;
        double buf[];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_atr_handle, 0, 0, 1, buf) >= 1)
            m_last_atr = buf[0];
    }
    
    //+------------------------------------------------------------------+
    //| _ApplyDynamicParams: Called by SetDynamicParams()               |
    //+------------------------------------------------------------------+
    void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_conf_threshold     = p.GetParam("S02_CONF_THRESHOLD",    m_conf_threshold);
        m_signal_timeout_sec = (int)p.GetParam("S02_TIMEOUT_SEC",  (double)m_signal_timeout_sec);
        m_trailing_atr_mult  = p.GetParam("S02_TRAILING_ATR_MULT", m_trailing_atr_mult);
        
        // *** SetParameters: ml_signal + ml_confidence come through SDynamicParams ***
        // Server packs them as strategy_params with keys "S02_ML_SIGNAL" / "S02_ML_CONFIDENCE"
        if(p.HasParam("S02_ML_SIGNAL"))
        {
            int new_signal = (int)p.GetParam("S02_ML_SIGNAL", 0.0);
            double new_conf = p.GetParam("S02_ML_CONFIDENCE", 0.0);
            
            // Only update signal timestamp if signal changed or confidence refreshed
            if(new_signal != 0 && new_conf > 0.0)
            {
                m_ml_signal      = new_signal;
                m_ml_confidence  = new_conf;
                m_signal_time    = TimeCurrent();
                m_signal_active  = true;
                
                PrintFormat("[S02] New ML signal: %s | Conf:%.3f",
                    m_ml_signal == 1 ? "BUY" : "SELL",
                    m_ml_confidence);
            }
        }
        
        m_config.mm_method = p.mm_method;   // ✅ REQUIRED (Lesson #5)
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CS02MLEnsemble()
    {
        m_strategy_id = S02_ML_ENSEMBLE;
        
        // Default params
        m_ml_signal          = 0;
        m_ml_confidence      = 0.0;
        m_conf_threshold     = 0.70;
        m_signal_timeout_sec = 300;         // 5 minutes
        m_trailing_atr_mult  = 1.5;
        
        m_signal_time   = 0;
        m_signal_active = false;
        m_atr_handle    = INVALID_HANDLE;
        m_last_atr      = 0.0;
        
        // Set identity from StrategyConstants
        InitStrategyTable();
        m_info = g_strategy_table[S02_ML_ENSEMBLE];
    }
    
    //+------------------------------------------------------------------+
    //| Init: Initialize strategy                                        |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        m_symbol    = symbol;
        m_timeframe = tf;
        
        m_atr_handle = iATR(symbol, tf, 14);
        if(m_atr_handle == INVALID_HANDLE)
            Print("[S02] Warning: ATR handle failed — trailing stop ATR unavailable");
        
        m_initialized = true;
        PrintFormat("[S02] Init OK | %s %s | Threshold:%.2f | Timeout:%ds",
                    symbol, EnumToString(tf),
                    m_conf_threshold, m_signal_timeout_sec);
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinit: Release handles                                         |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
        m_atr_handle  = INVALID_HANDLE;
        m_initialized = false;
    }
    
    //+------------------------------------------------------------------+
    //| Analyze: Called every tick                                       |
    //| S02 is thin — only check signal validity and expiry             |
    //+------------------------------------------------------------------+
    virtual void Analyze(MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;
        
        // Update ATR for trailing stop
        _UpdateATR();
        
        // Check signal expiry
        if(m_signal_active && _IsSignalExpired())
        {
            m_signal_active         = false;
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            PrintFormat("[S02] Signal EXPIRED after %ds | Closing position recommended",
                        m_signal_timeout_sec);
            return;
        }
        
        // Apply signal if active and confidence meets threshold
        if(m_signal_active && !_IsSignalExpired())
        {
            if(m_ml_confidence >= m_conf_threshold)
            {
                if(m_ml_signal == 1)
                    m_state.last_signal = SIGNAL_BUY;
                else if(m_ml_signal == -1)
                    m_state.last_signal = SIGNAL_SELL;
                else
                    m_state.last_signal = SIGNAL_NONE;
                    
                m_state.last_confidence = m_ml_confidence;
            }
            else
            {
                // Signal received but below threshold
                m_state.last_signal     = SIGNAL_NONE;
                m_state.last_confidence = 0.0;
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| GetSignal: Return current ML signal                             |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        if(_IsSignalExpired()) return SIGNAL_NONE;
        return m_state.last_signal;
    }
    
    //+------------------------------------------------------------------+
    //| GetConfidence: ML confidence direct from server                 |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        if(_IsSignalExpired()) return 0.0;
        return m_state.last_confidence;
    }
    
    //+------------------------------------------------------------------+
    //| GetTrailingStop: Compute trailing stop distance (in price)      |
    //| Called by Trader EA to set trailing stop on open position       |
    //+------------------------------------------------------------------+
    double GetTrailingStop()
    {
        if(m_last_atr <= 0) return 0.0;
        return m_last_atr * m_trailing_atr_mult;
    }
    
    //+------------------------------------------------------------------+
    //| SetDynamicParams: Called by StrategyManager on CONFIG_PUSH      |
    //| This is the main "SetParameters" entry point for S02           |
    //| Server packs: S02_ML_SIGNAL, S02_ML_CONFIDENCE, S02_CONF_THRESHOLD
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
        p.SetParam("S02_ML_SIGNAL",        (double)m_ml_signal);
        p.SetParam("S02_ML_CONFIDENCE",    m_ml_confidence);
        p.SetParam("S02_CONF_THRESHOLD",   m_conf_threshold);
        p.SetParam("S02_TIMEOUT_SEC",      (double)m_signal_timeout_sec);
        p.SetParam("S02_TRAILING_ATR_MULT",m_trailing_atr_mult);
        p.mm_method = m_config.mm_method;
        return p;
    }
    
    //--- Diagnostics
    bool   IsSignalActive()   const { return m_signal_active && !_IsSignalExpired(); }
    int    GetMLSignalRaw()   const { return m_ml_signal; }
    double GetMLConfidence()  const { return m_ml_confidence; }
    double GetLastATR()       const { return m_last_atr; }
    int    GetSecondsLeft()
    {
        if(!m_signal_active || m_signal_time == 0) return 0;
        int elapsed = (int)(TimeCurrent() - m_signal_time);
        return MathMax(0, m_signal_timeout_sec - elapsed);
    }
};

#endif // S02_ML_ENSEMBLE_MQH
//+------------------------------------------------------------------+
