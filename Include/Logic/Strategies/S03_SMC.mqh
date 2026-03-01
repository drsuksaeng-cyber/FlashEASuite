//+------------------------------------------------------------------+
//| S03_SMC.mqh                                                      |
//| FlashEASuite V2 — Smart Money Concepts (SMC)                     |
//| Magic: 1003 | Type: Full MQL5 | ServerOnly (standalone=false)    |
//+------------------------------------------------------------------+
//| Save to: Include/Logic/Strategies/S03_SMC.mqh                    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S03_SMC_MQH
#define S03_SMC_MQH

#include "../IStrategy.mqh"
#include "SMC/OrderBlockDetector.mqh"
#include "SMC/FVGDetector.mqh"
#include "SMC/BOSDetector.mqh"

//--- Input Parameters
input int    SMC_LookbackBars  = 50;
input double SMC_MinOBVolume   = 1.5;
input double SMC_MinFVGSize    = 0.5;
input int    SMC_SwingBars     = 5;
input double SMC_SL_ATRBuffer  = 0.3;
input double SMC_TP_ATRMult    = 2.0;
input double SMC_MinConfidence = 0.45;

//+------------------------------------------------------------------+
//| CSMCV6 — Smart Money Concepts                                    |
//| ใช้ direct member objects (ไม่ใช้ pointer/new/delete)             |
//+------------------------------------------------------------------+
class CSMCV6 : public IStrategy
{
private:
    //--- Dynamic params
    int     m_lookback;
    double  m_min_ob_vol;
    double  m_min_fvg_size;
    int     m_swing_bars;
    double  m_sl_atr_buffer;
    double  m_tp_atr_mult;
    double  m_min_confidence;

    //--- Sub-detectors เป็น direct members (ไม่ต้อง new/delete)
    COrderBlockDetector m_ob_det;
    CFVGDetector        m_fvg_det;
    CBOSDetector        m_bos_det;

    //--- ATR indicator handle
    int    m_atr_handle;

    //--- Diagnostic state
    double       m_last_atr;
    double       m_last_ob_str;
    double       m_last_fvg_r;
    bool         m_bos_active;
    ENUM_BOS_DIR m_bos_dir;

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    double _GetATR()
    {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(m_atr_handle, 0, 1, 1, buf) != 1) return 0.0;
        return buf[0];
    }

    void _SetupDetectors()
    {
        m_ob_det.Setup(m_symbol, m_timeframe, m_lookback, m_min_ob_vol, 0.5);
        m_fvg_det.Setup(m_symbol, m_timeframe, m_lookback, m_min_fvg_size);
        m_bos_det.Setup(m_symbol, m_timeframe, m_swing_bars);
    }

    double _CalcConfidence(double ob_str, double fvg_ratio)
    {
        double c = ob_str * 0.5;
        c += MathMin(0.3, (fvg_ratio / 3.0) * 0.3);
        if(m_bos_active) c += 0.2;
        return MathMin(1.0, c);
    }

    void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_lookback       = (int)p.GetParam("SMC_LOOKBACK",      (double)m_lookback);
        m_min_ob_vol     =      p.GetParam("SMC_MIN_OB_VOL",     m_min_ob_vol);
        m_min_fvg_size   =      p.GetParam("SMC_MIN_FVG_SIZE",   m_min_fvg_size);
        m_swing_bars     = (int)p.GetParam("SMC_SWING_BARS",    (double)m_swing_bars);
        m_sl_atr_buffer  =      p.GetParam("SMC_SL_ATR_BUFFER",  m_sl_atr_buffer);
        m_tp_atr_mult    =      p.GetParam("SMC_TP_ATR_MULT",    m_tp_atr_mult);
        m_min_confidence =      p.GetParam("SMC_MIN_CONFIDENCE", m_min_confidence);
        m_config.mm_method  = p.mm_method;
    }

    void _EvaluateLong(double price)
    {
        SOrderBlock ob;
        SFVG        fvg;
        bool ob_ok  = m_ob_det.GetNearestActive(true, price, ob);
        bool fvg_ok = m_fvg_det.GetNearestActive(true, price, fvg);

        bool in_ob  = (ob_ok  && price >= ob.low    && price <= ob.high);
        bool in_fvg = (fvg_ok && price >= fvg.bottom && price <= fvg.top);
        if(!in_ob && !in_fvg) return;

        m_last_ob_str = ob_ok  ? ob.strength    : 0.3;
        m_last_fvg_r  = fvg_ok ? fvg.size_ratio : 0.0;
        double conf   = _CalcConfidence(m_last_ob_str, m_last_fvg_r);
        if(conf < m_min_confidence) return;

        m_state.last_signal     = SIGNAL_BUY;
        m_state.last_confidence = conf;
        double sl_base  = ob_ok ? ob.low    : fvg.bottom;
        m_state.last_sl = sl_base - m_sl_atr_buffer * m_last_atr;
        m_state.last_tp = price   + m_tp_atr_mult   * m_last_atr;
    }

    void _EvaluateShort(double price)
    {
        SOrderBlock ob;
        SFVG        fvg;
        bool ob_ok  = m_ob_det.GetNearestActive(false, price, ob);
        bool fvg_ok = m_fvg_det.GetNearestActive(false, price, fvg);

        bool in_ob  = (ob_ok  && price >= ob.low    && price <= ob.high);
        bool in_fvg = (fvg_ok && price >= fvg.bottom && price <= fvg.top);
        if(!in_ob && !in_fvg) return;

        m_last_ob_str = ob_ok  ? ob.strength    : 0.3;
        m_last_fvg_r  = fvg_ok ? fvg.size_ratio : 0.0;
        double conf   = _CalcConfidence(m_last_ob_str, m_last_fvg_r);
        if(conf < m_min_confidence) return;

        m_state.last_signal     = SIGNAL_SELL;
        m_state.last_confidence = conf;
        double sl_base  = ob_ok ? ob.high  : fvg.top;
        m_state.last_sl = sl_base + m_sl_atr_buffer * m_last_atr;
        m_state.last_tp = price   - m_tp_atr_mult   * m_last_atr;
    }

public:
    //+----------------------------------------------------------------+
    //| Constructor                                                     |
    //+----------------------------------------------------------------+
    CSMCV6()
    {
        m_strategy_id    = S03_SMC;
        m_lookback       = SMC_LookbackBars;
        m_min_ob_vol     = SMC_MinOBVolume;
        m_min_fvg_size   = SMC_MinFVGSize;
        m_swing_bars     = SMC_SwingBars;
        m_sl_atr_buffer  = SMC_SL_ATRBuffer;
        m_tp_atr_mult    = SMC_TP_ATRMult;
        m_min_confidence = SMC_MinConfidence;
        m_atr_handle     = INVALID_HANDLE;
        m_last_atr       = 0;
        m_last_ob_str    = 0;
        m_last_fvg_r     = 0;
        m_bos_active     = false;
        m_bos_dir        = BOS_DIR_NONE;
    }

    ~CSMCV6()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
    }

    //=================================================================
    //  IStrategy INTERFACE
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf) override
    {
        if(!IStrategy::Init(symbol, tf)) return false;

        m_atr_handle = iATR(m_symbol, m_timeframe, 14);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S03] ERROR: iATR failed");
            return false;
        }
        _SetupDetectors();
        PrintFormat("[S03] Init OK | %s %s", m_symbol, EnumToString(m_timeframe));
        return true;
    }

    virtual void Deinit() override
    {
        if(m_atr_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atr_handle);
            m_atr_handle = INVALID_HANDLE;
        }
        IStrategy::Deinit();
    }

    virtual void Analyze(const MqlTick &tick) override
    {
        if(!m_enabled || !m_initialized) return;
        if(m_config.confidence < 0.01) return;  // ServerOnly guard

        double price = (tick.bid + tick.ask) * 0.5;
        m_last_atr   = _GetATR();
        if(m_last_atr <= 0) return;

        // Refresh detectors on new bar only
        static datetime s_last_bar = 0;
        datetime cur_bar = iTime(m_symbol, m_timeframe, 0);
        if(cur_bar != s_last_bar)
        {
            s_last_bar = cur_bar;
            m_ob_det.Scan();
            m_fvg_det.Scan();
            m_bos_det.Detect(m_lookback);
        }

        m_ob_det.MarkRetested(price);
        m_fvg_det.MarkFilled(price);
        m_bos_active = m_bos_det.HasBOS();
        m_bos_dir    = m_bos_det.GetDirection();

        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;

        if(m_bos_dir == BOS_DIR_BULLISH) _EvaluateLong(price);
        if(m_bos_dir == BOS_DIR_BEARISH) _EvaluateShort(price);
    }

    virtual ENUM_TRADE_SIGNAL GetSignal()     override { return m_state.last_signal; }
    virtual double            GetConfidence() override { return m_state.last_confidence; }
    virtual double            GetStopLoss()   override { return m_state.last_sl; }
    virtual double            GetTakeProfit() override { return m_state.last_tp; }

    virtual void OnConfigUpdate(const SConfigUpdate &cfg) override
    {
        IStrategy::OnConfigUpdate(cfg);
    }

    virtual void SetDynamicParams(SDynamicParams &params) override
    {
        _ApplyDynamicParams(params);
        _SetupDetectors();  // re-apply params to detectors
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.SetParam("SMC_LOOKBACK",       (double)m_lookback);
        p.SetParam("SMC_MIN_OB_VOL",     m_min_ob_vol);
        p.SetParam("SMC_MIN_FVG_SIZE",   m_min_fvg_size);
        p.SetParam("SMC_SWING_BARS",     (double)m_swing_bars);
        p.SetParam("SMC_SL_ATR_BUFFER",  m_sl_atr_buffer);
        p.SetParam("SMC_TP_ATR_MULT",    m_tp_atr_mult);
        p.SetParam("SMC_MIN_CONFIDENCE", m_min_confidence);
        p.mm_method = m_config.mm_method;
        return p;
    }

    virtual string GetName()             override { return "Smart Money Concepts"; }
    virtual int    GetMagic()            override { return MAGIC_S03_SMC; }
    virtual bool   IsStandaloneCapable() override { return false; }

    string GetDiagnostics()
    {
        string bos_str = "none";
        if(m_bos_active)
            bos_str = (m_bos_dir == BOS_DIR_BULLISH) ? "BULL" : "BEAR";
        return StringFormat("[S03] ATR:%.4f OB:%.2f FVG:%.2f BOS:%s Sig:%s Conf:%.2f",
            m_last_atr, m_last_ob_str, m_last_fvg_r, bos_str,
            SignalToString(m_state.last_signal), m_state.last_confidence);
    }
};

#endif // S03_SMC_MQH
//+------------------------------------------------------------------+
