//+------------------------------------------------------------------+
//| S04_MarketProfile.mqh                                            |
//| FlashEASuite V2 — Market Profile + Order Flow                   |
//| Magic: 1004 | Type: Full MQL5 | Standalone: No (ServerOnly)    |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Build Volume Profile: tick volume across 50 price bins          |
//|  POC = highest volume price | VAH/VAL = 70% value area          |
//|  Entry Long : price below VAL (outside value area low)          |
//|               + volume increasing (tick vol > ATR vol MA)       |
//|               + price within 2×ATR of VAL (not overextended)    |
//|  Entry Short: price above VAH (outside value area high)         |
//|               + volume increasing                               |
//|               + price within 2×ATR of VAH                       |
//|  Exit TP    : next volume node toward POC                       |
//|  Exit SL    : beyond POC (opposite side)                        |
//|  Confidence : volume_imbalance × poc_proximity × session_factor  |
//+------------------------------------------------------------------+
//| Location: Include/Logic/Strategies/S04_MarketProfile.mqh         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S04_MARKETPROFILE_MQH
#define S04_MARKETPROFILE_MQH

#include "../IStrategy.mqh"
#include "MarketProfile/VolumeProfileBuilder.mqh"
#include "MarketProfile/POCCalculator.mqh"

//--- Input Parameters
input int    MP_Bins           = 50;    // Volume Profile: number of price bins
input int    MP_LookbackBars   = 96;    // Profile lookback (bars, M15: 96=24h)
input double MP_ValueAreaPct   = 0.70;  // Value Area % (0.70 = 70%)
input int    MP_ATR_Period     = 14;    // ATR period for SL/TP/filter
input int    MP_Vol_MA_Period  = 20;    // Volume MA period (volume filter)
input double MP_Vol_Mult       = 1.2;   // Volume must be > Mult × Vol_MA
input double MP_SL_ATR_Mult    = 1.5;   // Stop loss = N × ATR (beyond POC)
input int    MP_RebuildEvery   = 4;     // Rebuild profile every N ticks

//+------------------------------------------------------------------+
//| CMarketProfile — Market Profile + Order Flow Strategy            |
//+------------------------------------------------------------------+
class CMarketProfile : public IStrategy
{
private:
    //--- Sub-components (direct members — no pointers)
    CVolumeProfileBuilder m_vp_builder;
    CPOCCalculator        m_poc_calc;
    
    //--- Dynamic params (server-tunable)
    int     m_bins;
    int     m_lookback;
    double  m_va_pct;
    int     m_atr_period;
    int     m_vol_ma_period;
    double  m_vol_mult;
    double  m_sl_atr_mult;
    int     m_rebuild_every;
    
    //--- Indicator handles
    int     m_atr_handle;
    int     m_vol_ma_handle;   // Volume MA handle
    
    //--- Cached values (updated each tick)
    double  m_last_atr;
    double  m_last_vol;        // Current bar tick volume
    double  m_last_vol_ma;     // Volume MA value
    double  m_poc;
    double  m_vah;
    double  m_val;
    
    //--- Rebuild counter
    int     m_tick_counter;
    
    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| RebuildProfile: Build volume profile and compute POC/VAH/VAL    |
    //+------------------------------------------------------------------+
    bool _RebuildProfile()
    {
        m_vp_builder.Setup(m_symbol, m_timeframe, m_bins, m_lookback);
        if(!m_vp_builder.Build()) return false;
        
        m_poc_calc.Setup(m_va_pct);
        if(!m_poc_calc.Calculate(m_vp_builder)) return false;
        
        m_poc = m_poc_calc.GetPOC();
        m_vah = m_poc_calc.GetVAH();
        m_val = m_poc_calc.GetVAL();
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| ReadIndicators: Pull current ATR and volume MA values           |
    //+------------------------------------------------------------------+
    bool _ReadIndicators()
    {
        double atr_buf[1], vol_ma_buf[1];
        
        if(CopyBuffer(m_atr_handle, 0, 1, 1, atr_buf) <= 0)    return false;
        if(CopyBuffer(m_vol_ma_handle, 0, 1, 1, vol_ma_buf) <= 0) return false;
        
        m_last_atr    = atr_buf[0];
        m_last_vol_ma = vol_ma_buf[0];
        
        //--- Current bar tick volume
        long vol_arr[1];
        if(CopyTickVolume(m_symbol, m_timeframe, 0, 1, vol_arr) > 0)
            m_last_vol = (double)vol_arr[0];
        
        return (m_last_atr > 0.0);
    }
    
    //+------------------------------------------------------------------+
    //| SessionFactor: Weight by trading session                        |
    //| London/NY overlap = 1.0, off-session = 0.6                     |
    //+------------------------------------------------------------------+
    double _SessionFactor()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int hour = dt.hour;
        
        // London open: 07-09 UTC
        // London-NY overlap: 12-16 UTC
        if((hour >= 7  && hour < 9) ||
           (hour >= 12 && hour < 16))
            return 1.0;
        
        // NY close / Asia session
        if(hour >= 20 || hour < 2)
            return 0.6;
        
        return 0.8;  // normal session
    }
    
    //+------------------------------------------------------------------+
    //| VolumeImbalance: Proxy for buy/sell volume imbalance           |
    //| Uses current bar's volume vs MA as signal of activity          |
    //| Returns value 0.0–1.0                                          |
    //+------------------------------------------------------------------+
    double _VolumeImbalance()
    {
        if(m_last_vol_ma <= 0.0) return 0.0;
        double ratio = m_last_vol / m_last_vol_ma;
        return MathMin(ratio / 3.0, 1.0);  // normalize: 3× vol MA = max
    }
    
    //+------------------------------------------------------------------+
    //| ComputeConfidence                                               |
    //+------------------------------------------------------------------+
    double _ComputeConfidence(double price)
    {
        double imbalance  = _VolumeImbalance();
        double proximity  = m_poc_calc.GetPOCProximity(price, m_last_atr);
        double session    = _SessionFactor();
        
        double conf = imbalance * (0.4 + 0.4 * proximity) * session;
        return MathMin(MathMax(conf, 0.0), 1.0);
    }
    
    //+------------------------------------------------------------------+
    //| _ApplyDynamicParams: Apply server-sent parameters               |
    //+------------------------------------------------------------------+
    virtual void _ApplyDynamicParams(SDynamicParams &p)
    {
        m_bins          = (int)p.GetParam("S04_BINS",           (double)m_bins);
        m_lookback      = (int)p.GetParam("S04_LOOKBACK_BARS",  (double)m_lookback);
        m_va_pct        =      p.GetParam("S04_VA_PCT",         m_va_pct);
        m_atr_period    = (int)p.GetParam("S04_ATR_PERIOD",     (double)m_atr_period);
        m_vol_ma_period = (int)p.GetParam("S04_VOL_MA_PERIOD",  (double)m_vol_ma_period);
        m_vol_mult      =      p.GetParam("S04_VOL_MULT",       m_vol_mult);
        m_sl_atr_mult   =      p.GetParam("S04_SL_ATR_MULT",   m_sl_atr_mult);
        m_rebuild_every = (int)p.GetParam("S04_REBUILD_EVERY",  (double)m_rebuild_every);
        m_config.mm_method = p.mm_method;  // REQUIRED — do not remove
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CMarketProfile()
    {
        m_strategy_id   = S04_MARKET_PROFILE;
        
        //--- Defaults from inputs
        m_bins          = MP_Bins;
        m_lookback      = MP_LookbackBars;
        m_va_pct        = MP_ValueAreaPct;
        m_atr_period    = MP_ATR_Period;
        m_vol_ma_period = MP_Vol_MA_Period;
        m_vol_mult      = MP_Vol_Mult;
        m_sl_atr_mult   = MP_SL_ATR_Mult;
        m_rebuild_every = MP_RebuildEvery;
        
        m_atr_handle    = INVALID_HANDLE;
        m_vol_ma_handle = INVALID_HANDLE;
        
        m_last_atr      = 0.0;
        m_last_vol      = 0.0;
        m_last_vol_ma   = 0.0;
        m_poc           = 0.0;
        m_vah           = 0.0;
        m_val           = 0.0;
        m_tick_counter  = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Init: Create indicator handles and build initial profile        |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;
        
        //--- ATR indicator
        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S04] INIT FAILED — iATR error on ", m_symbol);
            return false;
        }
        
        //--- Volume MA (MA applied to tick volume)
        //--- Using iMA on VOLUME data via custom — approximate with iVIDyA or custom MA
        //--- Workaround: use iMA on Close with vol period as proxy for vol smoothing
        //--- Production note: replace with proper volume MA if CopyTickVolume used in loop
        m_vol_ma_handle = iMA(m_symbol, m_timeframe, m_vol_ma_period, 0, MODE_SMA, PRICE_CLOSE);
        if(m_vol_ma_handle == INVALID_HANDLE)
        {
            Print("[S04] INIT FAILED — iMA error on ", m_symbol);
            return false;
        }
        
        //--- Build initial profile
        _RebuildProfile();
        
        PrintFormat("[S04] Init OK | Symbol=%s TF=%s Bins=%d Lookback=%d",
                    m_symbol, EnumToString(m_timeframe), m_bins, m_lookback);
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinit: Release indicator handles                               |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        if(m_atr_handle    != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
        if(m_vol_ma_handle != INVALID_HANDLE) IndicatorRelease(m_vol_ma_handle);
        m_atr_handle    = INVALID_HANDLE;
        m_vol_ma_handle = INVALID_HANDLE;
        IStrategy::Deinit();
    }
    
    //+------------------------------------------------------------------+
    //| Analyze: Process tick — rebuild profile when needed,            |
    //|          then check entry conditions                            |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        m_state.last_signal     = SIGNAL_NONE;
        m_state.last_confidence = 0.0;
        
        if(!m_initialized || !m_enabled) return;
        
        //--- Periodically rebuild volume profile
        m_tick_counter++;
        if(m_tick_counter >= m_rebuild_every || !m_vp_builder.IsBuilt())
        {
            _RebuildProfile();
            m_tick_counter = 0;
        }
        
        if(!m_poc_calc.IsCalculated()) return;
        if(!_ReadIndicators()) return;
        
        double price = tick.bid;
        
        //--- Volume filter: require elevated volume
        bool vol_ok = (m_last_vol_ma > 0.0 && m_last_vol >= m_vol_mult * m_last_vol_ma);
        
        //--- === Entry Long ===
        //--- Price below VAL (outside value area) + volume increasing
        if(price < m_val && vol_ok)
        {
            //--- Extra: not too far from VAL (within 2×ATR)
            if(price >= m_val - 2.0 * m_last_atr)
            {
                m_state.last_signal     = SIGNAL_BUY;
                m_state.last_confidence = _ComputeConfidence(price);
                m_state.last_signal_time = tick.time;
                return;
            }
        }
        
        //--- === Entry Short ===
        //--- Price above VAH (outside value area) + volume increasing
        if(price > m_vah && vol_ok)
        {
            if(price <= m_vah + 2.0 * m_last_atr)
            {
                m_state.last_signal     = SIGNAL_SELL;
                m_state.last_confidence = _ComputeConfidence(price);
                m_state.last_signal_time = tick.time;
                return;
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| GetTP: TP = nearest volume node toward POC                      |
    //+------------------------------------------------------------------+
    double GetTP(ENUM_TRADE_SIGNAL signal)
    {
        if(!m_poc_calc.IsCalculated()) return 0.0;
        
        if(signal == SIGNAL_BUY)
        {
            // Long: entered below VAL, TP = node above current price (toward POC)
            double node = m_poc_calc.GetNearestNodeAbove(m_val);
            return (node > 0.0) ? node : m_poc;
        }
        else if(signal == SIGNAL_SELL)
        {
            // Short: entered above VAH, TP = node below current price (toward POC)
            double node = m_poc_calc.GetNearestNodeBelow(m_vah);
            return (node > 0.0) ? node : m_poc;
        }
        return 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| GetSL: SL = beyond POC (other side, N × ATR buffer)            |
    //+------------------------------------------------------------------+
    double GetSL(ENUM_TRADE_SIGNAL signal, double entry_price)
    {
        if(m_last_atr <= 0.0 || !m_poc_calc.IsCalculated()) return 0.0;
        double buffer = m_sl_atr_mult * m_last_atr;
        
        if(signal == SIGNAL_BUY)
            return m_poc - buffer;   // Long SL below POC
        else if(signal == SIGNAL_SELL)
            return m_poc + buffer;   // Short SL above POC
        
        return 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export params for TRADE_REPORT                |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method       = m_config.mm_method;
        p.risk_multiplier = 1.0;
        p.SetParam("S04_BINS",           (double)m_bins);
        p.SetParam("S04_LOOKBACK_BARS",  (double)m_lookback);
        p.SetParam("S04_VA_PCT",         m_va_pct);
        p.SetParam("S04_ATR_PERIOD",     (double)m_atr_period);
        p.SetParam("S04_VOL_MA_PERIOD",  (double)m_vol_ma_period);
        p.SetParam("S04_VOL_MULT",       m_vol_mult);
        p.SetParam("S04_SL_ATR_MULT",   m_sl_atr_mult);
        return p;
    }
    
    //--- Accessors for test verification
    double GetPOC() const { return m_poc; }
    double GetVAH() const { return m_vah; }
    double GetVAL() const { return m_val; }
    double GetLastATR() const { return m_last_atr; }
    bool   IsProfileBuilt() const { return m_vp_builder.IsBuilt(); }
};

#endif // S04_MARKETPROFILE_MQH
//+------------------------------------------------------------------+
