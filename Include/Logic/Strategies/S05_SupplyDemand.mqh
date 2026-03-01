//+------------------------------------------------------------------+
//| S05_SupplyDemand.mqh                                             |
//| FlashEASuite V2 — Supply & Demand Zone Strategy                  |
//| Magic: 1005 | Type: Full MQL5 | ServerOnly (standalone=false)    |
//+------------------------------------------------------------------+
//| Save to: Include/Logic/Strategies/S05_SupplyDemand.mqh           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S05_SUPPLY_DEMAND_MQH
#define S05_SUPPLY_DEMAND_MQH

#include "../IStrategy.mqh"
#include "SuppyDemand/ZoneDetector.mqh"

//--- Input Parameters
input int    SD_LookbackBars    = 100;
input int    SD_MaxTouches      = 3;
input double SD_BaseRangeMult   = 0.6;
input double SD_DepartureMult   = 1.2;
input double SD_SL_ATRBuffer    = 0.5;
input double SD_TP_ATRMult      = 2.5;
input double SD_MinZoneStrength = 0.25;
input double SD_MinConfidence   = 0.40;

//+------------------------------------------------------------------+
//| CSupplyDemand — Supply & Demand Zone Strategy                    |
//| ใช้ direct member object (ไม่ใช้ pointer/new/delete)              |
//+------------------------------------------------------------------+
class CSupplyDemand : public IStrategy
{
private:
    //--- Dynamic params
    int     m_lookback;
    int     m_max_touches;
    double  m_base_range_mult;
    double  m_departure_mult;
    double  m_sl_atr_buffer;
    double  m_tp_atr_mult;
    double  m_min_zone_strength;
    double  m_min_confidence;

    //--- Zone detector เป็น direct member
    CZoneDetector m_zone_det;

    int    m_atr_handle;

    //--- Diagnostic
    double m_last_atr;
    int    m_demand_count;
    int    m_supply_count;
    double m_last_zone_str;

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

    void _SetupDetector()
    {
        m_zone_det.Setup(m_symbol, m_timeframe,
                         m_lookback, m_max_touches,
                         m_base_range_mult, m_departure_mult);
    }

    double _CalcConfidence(SSDZone &z, double atr)
    {
        double freshness   = MathMax(0.1, 1.0 - z.touches * 0.25);
        double width       = z.top - z.bottom;
        double width_ratio = (atr > 0) ? MathMin(1.0, width / (atr * 1.5)) : 0;
        return MathMin(1.0, freshness * 0.4 + width_ratio * 0.3 + z.strength * 0.3);
    }

    double _FindOppositeTP(bool is_long, double entry_price, double atr)
    {
        ENUM_ZONE_TYPE opp = is_long ? ZONE_SUPPLY : ZONE_DEMAND;
        SSDZone z;
        if(m_zone_det.GetNearestFreshZone(opp, entry_price, z))
            return is_long ? z.bottom : z.top;
        return is_long ? entry_price + m_tp_atr_mult * atr
                       : entry_price - m_tp_atr_mult * atr;
    }

    void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_lookback          = (int)p.GetParam("SD_LOOKBACK",         (double)m_lookback);
        m_max_touches       = (int)p.GetParam("SD_MAX_TOUCHES",      (double)m_max_touches);
        m_base_range_mult   =      p.GetParam("SD_BASE_RANGE_MULT",   m_base_range_mult);
        m_departure_mult    =      p.GetParam("SD_DEPARTURE_MULT",    m_departure_mult);
        m_sl_atr_buffer     =      p.GetParam("SD_SL_ATR_BUFFER",     m_sl_atr_buffer);
        m_tp_atr_mult       =      p.GetParam("SD_TP_ATR_MULT",       m_tp_atr_mult);
        m_min_zone_strength =      p.GetParam("SD_MIN_ZONE_STRENGTH", m_min_zone_strength);
        m_min_confidence    =      p.GetParam("SD_MIN_CONFIDENCE",    m_min_confidence);
        m_config.mm_method  = p.mm_method;
    }

    void _EvaluateEntry(double price)
    {
        SSDZone dz, sz;
        bool found_d = m_zone_det.GetNearestFreshZone(ZONE_DEMAND, price, dz);
        bool found_s = m_zone_det.GetNearestFreshZone(ZONE_SUPPLY, price, sz);

        // --- LONG: price อยู่ใน Demand Zone ---
        if(found_d && dz.strength >= m_min_zone_strength &&
           price >= dz.bottom && price <= dz.top)
        {
            double conf = _CalcConfidence(dz, m_last_atr);
            if(conf >= m_min_confidence)
            {
                m_last_zone_str         = dz.strength;
                m_state.last_signal     = SIGNAL_BUY;
                m_state.last_confidence = conf;
                m_state.last_sl = dz.bottom - m_sl_atr_buffer * m_last_atr;
                m_state.last_tp = _FindOppositeTP(true, price, m_last_atr);
                return;
            }
        }

        // --- SHORT: price อยู่ใน Supply Zone ---
        if(found_s && sz.strength >= m_min_zone_strength &&
           price >= sz.bottom && price <= sz.top)
        {
            double conf = _CalcConfidence(sz, m_last_atr);
            if(conf >= m_min_confidence)
            {
                m_last_zone_str         = sz.strength;
                m_state.last_signal     = SIGNAL_SELL;
                m_state.last_confidence = conf;
                m_state.last_sl = sz.top + m_sl_atr_buffer * m_last_atr;
                m_state.last_tp = _FindOppositeTP(false, price, m_last_atr);
            }
        }
    }

public:
    //+----------------------------------------------------------------+
    //| Constructor                                                     |
    //+----------------------------------------------------------------+
    CSupplyDemand()
    {
        m_strategy_id       = S05_SUPPLY_DEMAND;
        m_lookback          = SD_LookbackBars;
        m_max_touches       = SD_MaxTouches;
        m_base_range_mult   = SD_BaseRangeMult;
        m_departure_mult    = SD_DepartureMult;
        m_sl_atr_buffer     = SD_SL_ATRBuffer;
        m_tp_atr_mult       = SD_TP_ATRMult;
        m_min_zone_strength = SD_MinZoneStrength;
        m_min_confidence    = SD_MinConfidence;
        m_atr_handle        = INVALID_HANDLE;
        m_last_atr          = 0;
        m_demand_count      = 0;
        m_supply_count      = 0;
        m_last_zone_str     = 0;
    }

    ~CSupplyDemand()
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
            Print("[S05] ERROR: iATR failed");
            return false;
        }
        _SetupDetector();
        PrintFormat("[S05] Init OK | %s %s", m_symbol, EnumToString(m_timeframe));
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

        // Refresh zones on new bar only
        static datetime s_last_bar = 0;
        datetime cur_bar = iTime(m_symbol, m_timeframe, 0);
        if(cur_bar != s_last_bar)
        {
            s_last_bar = cur_bar;
            m_zone_det.Scan();

            m_demand_count = 0;
            m_supply_count = 0;
            for(int i = 0; i < m_zone_det.Count(); i++)
            {
                SSDZone z = m_zone_det.GetZone(i);
                if(!z.is_active) continue;
                if(z.zone_type == ZONE_DEMAND) m_demand_count++;
                else                           m_supply_count++;
            }
        }

        m_zone_det.UpdateTouches(price, m_last_atr);

        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
        _EvaluateEntry(price);
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
        _SetupDetector();
    }

    virtual SDynamicParams GetCurrentParams() override
    {
        SDynamicParams p;
        p.Reset();
        p.SetParam("SD_LOOKBACK",          (double)m_lookback);
        p.SetParam("SD_MAX_TOUCHES",       (double)m_max_touches);
        p.SetParam("SD_BASE_RANGE_MULT",   m_base_range_mult);
        p.SetParam("SD_DEPARTURE_MULT",    m_departure_mult);
        p.SetParam("SD_SL_ATR_BUFFER",     m_sl_atr_buffer);
        p.SetParam("SD_TP_ATR_MULT",       m_tp_atr_mult);
        p.SetParam("SD_MIN_ZONE_STRENGTH", m_min_zone_strength);
        p.SetParam("SD_MIN_CONFIDENCE",    m_min_confidence);
        p.mm_method = m_config.mm_method;
        return p;
    }

    virtual string GetName()             override { return "Supply & Demand"; }
    virtual int    GetMagic()            override { return MAGIC_S05_SUPPLY_DEM; }
    virtual bool   IsStandaloneCapable() override { return false; }

    string GetDiagnostics()
    {
        return StringFormat("[S05] ATR:%.4f D:%d S:%d Str:%.2f Sig:%s Conf:%.2f",
            m_last_atr, m_demand_count, m_supply_count, m_last_zone_str,
            SignalToString(m_state.last_signal), m_state.last_confidence);
    }
};

#endif // S05_SUPPLY_DEMAND_MQH
//+------------------------------------------------------------------+
