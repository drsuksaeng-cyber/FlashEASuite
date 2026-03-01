//+------------------------------------------------------------------+
//| S08_Intermarket.mqh                                              |
//| FlashEASuite V2 — Intermarket Correlation (DXY/XAUUSD)          |
//| Magic: 1008 | Type: Hybrid | Standalone: No (ServerOnly)        |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Python Brain calculates:                                        |
//|    - correlation_coefficient (XAUUSD vs DXY, rolling 20 bars)  |
//|    - dxy_direction (+1=strengthening, -1=weakening, 0=neutral)  |
//|    - dxy_momentum  (0.0–1.0, normalized DXY rate-of-change)     |
//|    - gold_volatility (0.0–1.0, normalized XAUUSD ATR)           |
//|  These arrive via CONFIG_PUSH → SetServerData()                  |
//|                                                                  |
//|  MQL5 signal logic (Analyze):                                    |
//|   Long  (XAUUSD): corr < -0.7 AND dxy_direction = -1 (DXY down)|
//|   Short (XAUUSD): corr < -0.7 AND dxy_direction = +1 (DXY up)  |
//|                                                                  |
//|  Exit: TP = 2 × ATR, SL = 1 × ATR                              |
//|  Confidence = |correlation| × dxy_momentum × gold_volatility     |
//+------------------------------------------------------------------+
//| Location: Include/Logic/Strategies/S08_Intermarket.mqh           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S08_INTERMARKET_MQH
#define S08_INTERMARKET_MQH

#include "../IStrategy.mqh"

//--- Input Parameters
input double IM_Corr_Threshold  = -0.70;  // Correlation threshold to trigger signal
input int    IM_ATR_Period      = 14;     // ATR period for TP/SL
input double IM_TP_ATR_Mult     = 2.0;   // TP = N × ATR
input double IM_SL_ATR_Mult     = 1.0;   // SL = N × ATR
input double IM_Min_Momentum    = 0.20;  // Minimum DXY momentum to accept signal
input double IM_Min_Volatility  = 0.10;  // Minimum gold volatility to accept signal

//+------------------------------------------------------------------+
//| CIntermarket — Intermarket Correlation Strategy (Thin Wrapper)   |
//| Receives all server data via SetServerData() from ConfigReceiver |
//| MQL5 only handles: signal logic + ATR-based TP/SL               |
//+------------------------------------------------------------------+
class CIntermarket : public IStrategy
{
private:
    //--- Server-supplied data (updated by SetServerData each CONFIG_PUSH)
    double  m_correlation;      // DXY-XAUUSD rolling correlation (-1 to +1)
    int     m_dxy_direction;    // +1=strengthening, -1=weakening, 0=neutral
    double  m_dxy_momentum;     // 0.0–1.0, normalized DXY rate-of-change
    double  m_gold_volatility;  // 0.0–1.0, normalized XAUUSD ATR
    bool    m_server_data_ready; // Have we received valid server data?
    
    //--- Dynamic params (server-tunable via CONFIG_PUSH params)
    double  m_corr_threshold;   // Correlation threshold (default -0.70)
    int     m_atr_period;
    double  m_tp_atr_mult;
    double  m_sl_atr_mult;
    double  m_min_momentum;
    double  m_min_volatility;
    
    //--- Indicator handles
    int     m_atr_handle;
    
    //--- Cached values
    double  m_last_atr;
    
    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| _ReadATR: Pull current ATR value                                |
    //+------------------------------------------------------------------+
    bool _ReadATR()
    {
        double atr_buf[1];
        if(CopyBuffer(m_atr_handle, 0, 1, 1, atr_buf) <= 0) return false;
        m_last_atr = atr_buf[0];
        return (m_last_atr > 0.0);
    }
    
    //+------------------------------------------------------------------+
    //| _ComputeConfidence                                              |
    //| Confidence = |correlation| × dxy_momentum × gold_volatility     |
    //+------------------------------------------------------------------+
    double _ComputeConfidence()
    {
        double corr_strength = MathAbs(m_correlation);
        double conf = corr_strength * m_dxy_momentum * m_gold_volatility;
        return MathMin(MathMax(conf, 0.0), 1.0);
    }
    
    //+------------------------------------------------------------------+
    //| _ApplyDynamicParams: Apply server CONFIG_PUSH parameters        |
    //+------------------------------------------------------------------+
    virtual void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_corr_threshold  =      p.GetParam("S08_CORR_THRESHOLD", m_corr_threshold);
        m_atr_period      = (int)p.GetParam("S08_ATR_PERIOD",     (double)m_atr_period);
        m_tp_atr_mult     =      p.GetParam("S08_TP_ATR_MULT",   m_tp_atr_mult);
        m_sl_atr_mult     =      p.GetParam("S08_SL_ATR_MULT",   m_sl_atr_mult);
        m_min_momentum    =      p.GetParam("S08_MIN_MOMENTUM",   m_min_momentum);
        m_min_volatility  =      p.GetParam("S08_MIN_VOLATILITY", m_min_volatility);
        m_config.mm_method = p.mm_method;  // REQUIRED — do not remove
        
        //--- Also read intermarket data from params if sent by Python
        //--- Python may embed these in CONFIG_PUSH strategy params
        if(p.HasParam("S08_CORRELATION"))
            m_correlation = p.GetParam("S08_CORRELATION", 0.0);
        if(p.HasParam("S08_DXY_DIRECTION"))
            m_dxy_direction = (int)p.GetParam("S08_DXY_DIRECTION", 0.0);
        if(p.HasParam("S08_DXY_MOMENTUM"))
            m_dxy_momentum = p.GetParam("S08_DXY_MOMENTUM", 0.0);
        if(p.HasParam("S08_GOLD_VOLATILITY"))
            m_gold_volatility = p.GetParam("S08_GOLD_VOLATILITY", 0.0);
        
        //--- Mark data as ready if correlation received
        if(p.HasParam("S08_CORRELATION"))
            m_server_data_ready = true;
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CIntermarket()
    {
        m_strategy_id       = S08_INTERMARKET;
        
        //--- Server data defaults
        m_correlation       = 0.0;
        m_dxy_direction     = 0;
        m_dxy_momentum      = 0.0;
        m_gold_volatility   = 0.0;
        m_server_data_ready = false;
        
        //--- Params defaults from inputs
        m_corr_threshold    = IM_Corr_Threshold;
        m_atr_period        = IM_ATR_Period;
        m_tp_atr_mult       = IM_TP_ATR_Mult;
        m_sl_atr_mult       = IM_SL_ATR_Mult;
        m_min_momentum      = IM_Min_Momentum;
        m_min_volatility    = IM_Min_Volatility;
        
        m_atr_handle        = INVALID_HANDLE;
        m_last_atr          = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Init: Create ATR handle                                         |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;
        
        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S08] INIT FAILED — iATR error on ", m_symbol);
            return false;
        }
        
        PrintFormat("[S08] Init OK | Symbol=%s TF=%s | ServerOnly=YES",
                    m_symbol, EnumToString(m_timeframe));
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinit: Release handles                                         |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
        m_atr_handle = INVALID_HANDLE;
        IStrategy::Deinit();
    }
    
    //+------------------------------------------------------------------+
    //| SetServerData: Called by ConfigReceiver when CONFIG_PUSH arrives |
    //| This is the primary injection point for Python-computed data    |
    //| @param correlation     Rolling corr coefficient (DXY vs XAUUSD) |
    //| @param dxy_direction   +1=DXY up, -1=DXY down, 0=neutral       |
    //| @param dxy_momentum    Normalized DXY rate-of-change (0–1)      |
    //| @param gold_volatility Normalized XAUUSD ATR (0–1)              |
    //+------------------------------------------------------------------+
    void SetServerData(double correlation,
                       int    dxy_direction,
                       double dxy_momentum,
                       double gold_volatility)
    {
        m_correlation       = correlation;
        m_dxy_direction     = dxy_direction;
        m_dxy_momentum      = MathMax(0.0, MathMin(dxy_momentum,    1.0));
        m_gold_volatility   = MathMax(0.0, MathMin(gold_volatility,  1.0));
        m_server_data_ready = true;
        
        PrintFormat("[S08] Server data received | Corr=%.3f Dir=%s Mom=%.2f Vol=%.2f",
                    m_correlation,
                    (m_dxy_direction > 0) ? "UP" : (m_dxy_direction < 0) ? "DOWN" : "FLAT",
                    m_dxy_momentum,
                    m_gold_volatility);
    }
    
    //+------------------------------------------------------------------+
    //| Analyze: Generate signal from server-supplied intermarket data  |
    //| Called every tick, but actual signal changes only when          |
    //| CONFIG_PUSH arrives (server data refresh rate)                  |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
        
        if(!m_initialized || !m_enabled) return;
        
        //--- S08 is ServerOnly — no signal without server data
        if(!m_server_data_ready)
        {
            // Silent: expected to have no data until server connects
            return;
        }
        
        if(!_ReadATR()) return;
        
        //--- Condition 1: Strong negative correlation (DXY vs Gold)
        //--- Gold moves opposite to DXY — threshold: corr < -0.70
        if(m_correlation >= m_corr_threshold) return;  // Correlation too weak
        
        //--- Condition 2: DXY momentum filter
        if(m_dxy_momentum < m_min_momentum) return;
        
        //--- Condition 3: Gold volatility filter (avoid ultra-low vol)
        if(m_gold_volatility < m_min_volatility) return;
        
        //--- === Entry Logic ===
        //--- Long XAUUSD: corr < threshold AND DXY weakening (DXY goes down → Gold goes up)
        if(m_dxy_direction == -1)
        {
            m_state.last_signal     = SIGNAL_BUY;
            m_state.last_confidence = _ComputeConfidence();
            m_state.last_signal_time = tick.time;
            PrintFormat("[S08] BUY signal | Corr=%.3f DXY=DOWN Conf=%.2f",
                        m_correlation, m_state.last_confidence);
        }
        //--- Short XAUUSD: corr < threshold AND DXY strengthening (DXY goes up → Gold goes down)
        else if(m_dxy_direction == 1)
        {
            m_state.last_signal     = SIGNAL_SELL;
            m_state.last_confidence = _ComputeConfidence();
            m_state.last_signal_time = tick.time;
            PrintFormat("[S08] SELL signal | Corr=%.3f DXY=UP Conf=%.2f",
                        m_correlation, m_state.last_confidence);
        }
        //--- Neutral DXY direction → no signal
    }
    
    //+------------------------------------------------------------------+
    //| GetTP: TP = 2 × ATR from entry                                  |
    //+------------------------------------------------------------------+
    double GetTP(ENUM_TRADE_SIGNAL signal, double entry_price)
    {
        if(m_last_atr <= 0.0) return 0.0;
        double tp_dist = m_tp_atr_mult * m_last_atr;
        if(signal == SIGNAL_BUY)  return entry_price + tp_dist;
        if(signal == SIGNAL_SELL) return entry_price - tp_dist;
        return 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| GetSL: SL = 1 × ATR from entry                                  |
    //+------------------------------------------------------------------+
    double GetSL(ENUM_TRADE_SIGNAL signal, double entry_price)
    {
        if(m_last_atr <= 0.0) return 0.0;
        double sl_dist = m_sl_atr_mult * m_last_atr;
        if(signal == SIGNAL_BUY)  return entry_price - sl_dist;
        if(signal == SIGNAL_SELL) return entry_price + sl_dist;
        return 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| IsStandaloneCapable: S08 requires server DXY data               |
    //+------------------------------------------------------------------+
    virtual bool IsStandaloneCapable() { return false; }
    
    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export params for TRADE_REPORT                |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method       = m_config.mm_method;
        p.risk_multiplier = 1.0;
        p.SetParam("S08_CORR_THRESHOLD", m_corr_threshold);
        p.SetParam("S08_ATR_PERIOD",     (double)m_atr_period);
        p.SetParam("S08_TP_ATR_MULT",   m_tp_atr_mult);
        p.SetParam("S08_SL_ATR_MULT",   m_sl_atr_mult);
        p.SetParam("S08_CORRELATION",    m_correlation);
        p.SetParam("S08_DXY_DIRECTION",  (double)m_dxy_direction);
        return p;
    }
    
    //--- Diagnostic accessors
    double GetCorrelation()    const { return m_correlation; }
    int    GetDXYDirection()   const { return m_dxy_direction; }
    double GetDXYMomentum()    const { return m_dxy_momentum; }
    double GetGoldVolatility() const { return m_gold_volatility; }
    bool   HasServerData()     const { return m_server_data_ready; }
    double GetLastATR()        const { return m_last_atr; }
};

#endif // S08_INTERMARKET_MQH
//+------------------------------------------------------------------+
