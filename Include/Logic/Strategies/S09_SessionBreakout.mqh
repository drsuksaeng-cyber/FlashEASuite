//+------------------------------------------------------------------+
//| S09_SessionBreakout.mqh                                          |
//| FlashEASuite V2 — London/NY Session Breakout                     |
//| Magic: 1009 | Type: Full MQL5 | Standalone: No (ServerOnly)     |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Asian Range : High/Low of 00:00-08:00 GMT (broker-adjusted)    |
//|  Entry Long  : Break above Asian High + ATR×buffer during London |
//|  Entry Short : Break below Asian Low  - ATR×buffer during London |
//|  NY Extended : 13:00-17:00 — breakout from London range          |
//|  Exit        : TP = 1.5× Asian range, SL = opposite range side  |
//|  Time Filter : No trades after 17:00 GMT                        |
//|  Confidence  : range_size/ATR × session_volume_factor           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S09_SESSIONBREAKOUT_MQH
#define S09_SESSIONBREAKOUT_MQH

#include "../IStrategy.mqh"

//--- Input Parameters (default values)
input int    SB_Asian_Start     = 0;     // Asian session start hour (GMT)
input int    SB_Asian_End       = 7;     // Asian session end hour (GMT)
input int    SB_London_Start    = 8;     // London session start hour (GMT)
input int    SB_London_End      = 12;    // London session end hour (GMT)
input int    SB_NY_Start        = 13;    // NY session start hour (GMT)
input int    SB_NY_End          = 17;    // NY session end hour (GMT)
input int    SB_Range_Min_Pips  = 20;    // Minimum Asian range in pips (skip if smaller)
input double SB_Breakout_Buffer = 3.0;   // Breakout buffer in pips (ATR×factor fallback)
input double SB_SL_Inside_Ratio = 0.5;  // SL as ratio inside range from opposite side
input double SB_TP_Range_Mult   = 1.5;  // TP = N × Asian range
input int    SB_ATR_Period      = 14;    // ATR period for confidence
input int    SB_BrokerGMT_Offset= 3;    // Broker server GMT offset (hours, e.g. +3 = EET)

//+------------------------------------------------------------------+
//| CSessionBreakout — London/NY Session Breakout Strategy           |
//+------------------------------------------------------------------+
class CSessionBreakout : public IStrategy
{
private:
    //--- Dynamic params (hot-reloadable via CONFIG_PUSH)
    int     m_asian_start;       // S09_ASIAN_START  — Asian session start GMT hour
    int     m_asian_end;         // S09_ASIAN_END    — Asian session end   GMT hour
    int     m_london_start;      // S09_LONDON_START — London open GMT hour
    int     m_london_end;        // London close hour (hardcoded 12)
    int     m_ny_start;          // S09_NY_START     — NY open GMT hour
    int     m_ny_end;            // NY trading end hour (hardcoded 17)
    int     m_range_min_pips;    // S09_RANGE_MIN    — min range to trade
    double  m_breakout_buffer;   // S09_BREAKOUT_BUF — pips buffer for false break filter
    double  m_sl_inside_ratio;   // S09_SL_INSIDE    — SL placement inside range
    double  m_tp_range_mult;     // S09_TP_RANGE_MULT — TP multiplier
    int     m_atr_period;        // ATR period
    int     m_broker_gmt_offset; // Broker GMT offset in hours

    //--- Indicator handles
    int     m_atr_handle;

    //--- Session state (reset each day)
    double  m_asian_high;           // Asian session range high
    double  m_asian_low;            // Asian session range low
    double  m_london_high;          // London range high (for NY breakout)
    double  m_london_low;           // London range low
    bool    m_asian_range_valid;    // Have we captured a valid Asian range?
    bool    m_london_broken_up;     // London session already triggered long?
    bool    m_london_broken_dn;     // London session already triggered short?
    bool    m_ny_broken_up;         // NY session already triggered long?
    bool    m_ny_broken_dn;         // NY session already triggered short?
    datetime m_last_range_date;     // Date of last Asian range calculation
    double   m_last_atr;            // Last ATR value
    double   m_point_value;         // Symbol point value (for pip calculation)
    int      m_digits;              // Symbol digits

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    //+------------------------------------------------------------------+
    //| _GetIndicatorValue: Safe single-value read                       |
    //+------------------------------------------------------------------+
    double _GetIndicatorValue(int handle, int buffer, int shift = 0)
    {
        if(handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(handle, buffer, shift, 1, buf) != 1) return 0.0;
        return buf[0];
    }

    //+------------------------------------------------------------------+
    //| _InitIndicators: Create indicator handles                        |
    //+------------------------------------------------------------------+
    bool _InitIndicators()
    {
        _ReleaseIndicators();
        m_atr_handle = iATR(m_symbol, PERIOD_H1, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S09] ERROR: Failed to create ATR indicator");
            return false;
        }
        PrintFormat("[S09] ATR(%d) on H1 initialized | Broker GMT+%d",
                    m_atr_period, m_broker_gmt_offset);
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ReleaseIndicators: Free indicator handles                       |
    //+------------------------------------------------------------------+
    void _ReleaseIndicators()
    {
        if(m_atr_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atr_handle);
            m_atr_handle = INVALID_HANDLE;
        }
    }

    //+------------------------------------------------------------------+
    //| _PipSize: Return 1 pip in price units                            |
    //+------------------------------------------------------------------+
    double _PipSize()
    {
        // For 5-digit brokers: 1 pip = 10 × Point
        return (m_digits == 3 || m_digits == 5) ? m_point_value * 10.0 : m_point_value;
    }

    //+------------------------------------------------------------------+
    //| _BrokerHour: Convert broker server time to GMT hour              |
    //| Subtracts broker GMT offset to get true GMT hour                 |
    //+------------------------------------------------------------------+
    int _BrokerHour(datetime t)
    {
        // Convert broker time → GMT hour
        int gmt_time = (int)t - m_broker_gmt_offset * 3600;
        MqlDateTime dt;
        TimeToStruct((datetime)gmt_time, dt);
        return dt.hour;
    }

    //+------------------------------------------------------------------+
    //| _IsInSession: Check if GMT hour falls in [start, end)            |
    //+------------------------------------------------------------------+
    bool _IsInSession(int gmt_hour, int start, int end)
    {
        return (gmt_hour >= start && gmt_hour < end);
    }

    //+------------------------------------------------------------------+
    //| _ScanAsianRange: Scan H1 bars for today's Asian session range    |
    //| Fills m_asian_high / m_asian_low from OHLC bars                 |
    //+------------------------------------------------------------------+
    bool _ScanAsianRange()
    {
        // Need bars covering 00:00-08:00 GMT today
        // We look back up to 24 H1 bars to find Asian session
        int bars_needed = 24 + m_asian_end - m_asian_start + 2;
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(m_symbol, PERIOD_H1, 0, bars_needed, rates);
        if(copied < 8) return false;

        double hi = -DBL_MAX, lo = DBL_MAX;
        bool found = false;

        // Get today's date in broker time
        MqlDateTime today_dt;
        TimeToStruct(TimeCurrent(), today_dt);
        today_dt.hour = 0; today_dt.min = 0; today_dt.sec = 0;
        datetime today_start = StructToTime(today_dt);

        for(int i = 0; i < copied; i++)
        {
            // Convert bar open time → GMT hour
            int gmt_h = _BrokerHour(rates[i].time);
            // Only bars from today (broker date check)
            if(rates[i].time < today_start) continue;

            // Asian session bars (GMT hour inside [m_asian_start, m_asian_end))
            if(_IsInSession(gmt_h, m_asian_start, m_asian_end))
            {
                hi = MathMax(hi, rates[i].high);
                lo = MathMin(lo, rates[i].low);
                found = true;
            }
        }

        if(!found || hi == -DBL_MAX) return false;

        m_asian_high = hi;
        m_asian_low  = lo;
        return true;
    }

    //+------------------------------------------------------------------+
    //| _UpdateLondonRange: Track intraday London session high/low        |
    //+------------------------------------------------------------------+
    void _UpdateLondonRange(double ask, double bid)
    {
        double mid = (ask + bid) * 0.5;
        if(mid > m_london_high) m_london_high = mid;
        if(mid < m_london_low)  m_london_low  = mid;
    }

    //+------------------------------------------------------------------+
    //| _CalcConfidence: range_size/ATR × session_volume_factor          |
    //| session_volume_factor: London=1.0, NY=0.75 (lower liquidity)    |
    //+------------------------------------------------------------------+
    double _CalcConfidence(bool is_london_session)
    {
        if(!m_asian_range_valid || m_last_atr <= 0.0) return 0.0;

        double range = m_asian_high - m_asian_low;
        double range_atr_ratio = range / m_last_atr;

        // Optimal ratio is ~1.5 (range ~= ATR): higher ratio → more momentum
        double range_factor = MathMin(1.0, range_atr_ratio / 2.0);

        // London session has higher volume → better quality breakouts
        double session_factor = is_london_session ? 1.0 : 0.75;

        double conf = range_factor * session_factor;
        return MathMax(0.0, MathMin(1.0, conf));
    }

    //+------------------------------------------------------------------+
    //| _ParseJsonDouble: Simple JSON key extractor                      |
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

    //+------------------------------------------------------------------+
    //| _ResetDailyState: Called at start of new trading day             |
    //+------------------------------------------------------------------+
    void _ResetDailyState()
    {
        m_asian_high        = 0.0;
        m_asian_low         = 0.0;
        m_london_high       = 0.0;
        m_london_low        = DBL_MAX;
        m_asian_range_valid = false;
        m_london_broken_up  = false;
        m_london_broken_dn  = false;
        m_ny_broken_up      = false;
        m_ny_broken_dn      = false;
        m_last_range_date   = 0;
        PrintFormat("[S09] Daily state reset | %s", TimeToString(TimeCurrent()));
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CSessionBreakout()
    {
        m_strategy_id       = S09_SESSION_BREAKOUT;

        // Defaults from inputs
        m_asian_start       = SB_Asian_Start;
        m_asian_end         = SB_Asian_End;
        m_london_start      = SB_London_Start;
        m_london_end        = SB_London_End;
        m_ny_start          = SB_NY_Start;
        m_ny_end            = SB_NY_End;
        m_range_min_pips    = SB_Range_Min_Pips;
        m_breakout_buffer   = SB_Breakout_Buffer;
        m_sl_inside_ratio   = SB_SL_Inside_Ratio;
        m_tp_range_mult     = SB_TP_Range_Mult;
        m_atr_period        = SB_ATR_Period;
        m_broker_gmt_offset = SB_BrokerGMT_Offset;

        m_atr_handle        = INVALID_HANDLE;

        // Session state
        m_asian_high        = 0.0;
        m_asian_low         = 0.0;
        m_london_high       = 0.0;
        m_london_low        = DBL_MAX;
        m_asian_range_valid = false;
        m_london_broken_up  = false;
        m_london_broken_dn  = false;
        m_ny_broken_up      = false;
        m_ny_broken_dn      = false;
        m_last_range_date   = 0;
        m_last_atr          = 0.0;
        m_point_value       = 0.0;
        m_digits            = 5;
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CSessionBreakout()
    {
        Deinit();
    }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    //+------------------------------------------------------------------+
    //| Init: Initialize strategy for given symbol/timeframe            |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;

        m_strategy_id = S09_SESSION_BREAKOUT;
        m_info = g_strategy_table[S09_SESSION_BREAKOUT];

        m_point_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        m_digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        if(!_InitIndicators()) return false;
        _ResetDailyState();

        PrintFormat("[S09] Init OK | %s %s | Asian %02d:00-%02d:00 GMT | London %02d:00 | NY %02d:00",
                    symbol, EnumToString(tf),
                    m_asian_start, m_asian_end,
                    m_london_start, m_ny_start);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release resources                                        |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        _ReleaseIndicators();
        IStrategy::Deinit();
    }

    //+------------------------------------------------------------------+
    //| UpdateParams: Hot-reload parameters from CONFIG_PUSH V2          |
    //+------------------------------------------------------------------+
    virtual void UpdateParams(SDynamicParams &params)
    {
        double old_asian_start = m_asian_start;

        m_asian_start     = (int)params.GetParam("S09_ASIAN_START",  (double)m_asian_start);
        m_asian_end       = (int)params.GetParam("S09_ASIAN_END",    (double)m_asian_end);
        m_london_start    = (int)params.GetParam("S09_LONDON_START", (double)m_london_start);
        m_ny_start        = (int)params.GetParam("S09_NY_START",     (double)m_ny_start);
        m_range_min_pips  = (int)params.GetParam("S09_RANGE_MIN",    (double)m_range_min_pips);
        m_breakout_buffer = params.GetParam("S09_BREAKOUT_BUF",      m_breakout_buffer);
        m_sl_inside_ratio = params.GetParam("S09_SL_INSIDE",         m_sl_inside_ratio);
        m_tp_range_mult   = params.GetParam("S09_TP_RANGE_MULT",     m_tp_range_mult);

        // If session times changed → invalidate today's range so it re-scans
        if((int)old_asian_start != m_asian_start)
        {
            m_asian_range_valid = false;
            PrintFormat("[S09] Session hours updated — Asian range invalidated for re-scan");
        }

        PrintFormat("[S09] Params updated | Asian %02d-%02d GMT | London %02d | NY %02d | MinRange=%d | Buf=%.1f | SL=%.2f | TP_Mult=%.1f",
                    m_asian_start, m_asian_end, m_london_start, m_ny_start,
                    m_range_min_pips, m_breakout_buffer, m_sl_inside_ratio, m_tp_range_mult);
    }

    //+------------------------------------------------------------------+
    //| Analyze: Process incoming tick — detect session & range          |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_enabled || !m_initialized) return;

        double ask = tick.ask;
        double bid = tick.bid;
        datetime now = tick.time;

        // --- Daily reset check ---
        MqlDateTime now_dt;
        TimeToStruct(now, now_dt);
        now_dt.hour = 0; now_dt.min = 0; now_dt.sec = 0;
        datetime today_start = StructToTime(now_dt);

        if(m_last_range_date != today_start)
        {
            _ResetDailyState();
            m_last_range_date = today_start;
        }

        // Current GMT hour
        int gmt_h = _BrokerHour(now);

        // --- Update ATR ---
        m_last_atr = _GetIndicatorValue(m_atr_handle, 0, 1);

        // --- Asian session: collect range on the fly ---
        if(_IsInSession(gmt_h, m_asian_start, m_asian_end))
        {
            double mid = (ask + bid) * 0.5;
            if(!m_asian_range_valid)
            {
                m_asian_high = mid;
                m_asian_low  = mid;
                m_asian_range_valid = true;
            }
            else
            {
                if(ask > m_asian_high) m_asian_high = ask;
                if(bid < m_asian_low)  m_asian_low  = bid;
            }
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            return;
        }

        // --- After Asian close: try scanning H1 bars if we don't have a valid range ---
        if(!m_asian_range_valid && gmt_h >= m_asian_end)
        {
            m_asian_range_valid = _ScanAsianRange();
            if(!m_asian_range_valid)
            {
                m_state.last_signal = SIGNAL_NONE;
                return;
            }
        }

        // --- Range size check ---
        double range = m_asian_high - m_asian_low;
        double pip   = _PipSize();
        if(range < (double)m_range_min_pips * pip)
        {
            // Range too small → skip today
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            return;
        }

        // --- No-trade window: after NY end ---
        if(gmt_h >= m_ny_end)
        {
            m_state.last_signal = SIGNAL_NONE;
            return;
        }

        // --- Compute breakout trigger levels ---
        double buf_price = m_breakout_buffer * pip;
        // Also consider ATR-based buffer (10% of ATR)
        if(m_last_atr > 0.0)
            buf_price = MathMax(buf_price, m_last_atr * 0.1);

        double long_trigger  = m_asian_high + buf_price;
        double short_trigger = m_asian_low  - buf_price;

        // --- London session: breakout from Asian range ---
        if(_IsInSession(gmt_h, m_london_start, m_london_end))
        {
            _UpdateLondonRange(ask, bid);

            if(!m_london_broken_up && ask >= long_trigger)
            {
                m_london_broken_up = true;
                m_state.last_signal     = SIGNAL_BUY;
                m_state.last_confidence = _CalcConfidence(true);

                // TP/SL stored in state for StrategyManager to use
                double tp = ask + range * m_tp_range_mult;
                double sl = m_asian_low + range * m_sl_inside_ratio;  // inside range
                PrintFormat("[S09] LONDON LONG | Ask=%.5f | Asian H=%.5f L=%.5f | Range=%.5f | TP=%.5f SL=%.5f | Conf=%.2f",
                            ask, m_asian_high, m_asian_low, range, tp, sl, m_state.last_confidence);
            }
            else if(!m_london_broken_dn && bid <= short_trigger)
            {
                m_london_broken_dn = true;
                m_state.last_signal     = SIGNAL_SELL;
                m_state.last_confidence = _CalcConfidence(true);

                double tp = bid - range * m_tp_range_mult;
                double sl = m_asian_high - range * m_sl_inside_ratio;
                PrintFormat("[S09] LONDON SHORT | Bid=%.5f | Asian H=%.5f L=%.5f | Range=%.5f | TP=%.5f SL=%.5f | Conf=%.2f",
                            bid, m_asian_high, m_asian_low, range, tp, sl, m_state.last_confidence);
            }
            else
            {
                // No new breakout this tick → hold last signal or none
                if(!m_london_broken_up && !m_london_broken_dn)
                    m_state.last_signal = SIGNAL_NONE;
            }
            return;
        }

        // --- NY session: breakout from London range ---
        if(_IsInSession(gmt_h, m_ny_start, m_ny_end))
        {
            // Use London range for NY breakout triggers (if London range was built)
            double ny_high  = (m_london_high > 0.0) ? m_london_high : m_asian_high;
            double ny_low   = (m_london_low  < DBL_MAX) ? m_london_low  : m_asian_low;
            double ny_long  = ny_high + buf_price;
            double ny_short = ny_low  - buf_price;

            if(!m_ny_broken_up && ask >= ny_long)
            {
                m_ny_broken_up = true;
                m_state.last_signal     = SIGNAL_BUY;
                m_state.last_confidence = _CalcConfidence(false);  // NY = 0.75 factor

                double ny_range = ny_high - ny_low;
                PrintFormat("[S09] NY LONG | Ask=%.5f | NY H=%.5f L=%.5f | Conf=%.2f",
                            ask, ny_high, ny_low, m_state.last_confidence);
            }
            else if(!m_ny_broken_dn && bid <= ny_short)
            {
                m_ny_broken_dn = true;
                m_state.last_signal     = SIGNAL_SELL;
                m_state.last_confidence = _CalcConfidence(false);

                double ny_range = ny_high - ny_low;
                PrintFormat("[S09] NY SHORT | Bid=%.5f | NY H=%.5f L=%.5f | Conf=%.2f",
                            bid, ny_high, ny_low, m_state.last_confidence);
            }
            else
            {
                if(!m_ny_broken_up && !m_ny_broken_dn)
                    m_state.last_signal = SIGNAL_NONE;
            }
            return;
        }

        // Between London close (12:00) and NY open (13:00) — no trading
        m_state.last_signal = SIGNAL_NONE;
    }

    //+------------------------------------------------------------------+
    //| GetSignal: Return last computed signal                           |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }

    //+------------------------------------------------------------------+
    //| GetConfidence: Return last computed confidence 0.0-1.0           |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }

    //+------------------------------------------------------------------+
    //| GetTP: Calculate TP price for current signal                     |
    //| Called by StrategyManager before placing order                  |
    //+------------------------------------------------------------------+
    double GetTP(double entry_price, ENUM_TRADE_SIGNAL sig)
    {
        double range = m_asian_high - m_asian_low;
        if(sig == SIGNAL_BUY)  return entry_price + range * m_tp_range_mult;
        if(sig == SIGNAL_SELL) return entry_price - range * m_tp_range_mult;
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| GetSL: Calculate SL price for current signal                     |
    //| SL placed at ratio inside range from opposite side               |
    //+------------------------------------------------------------------+
    double GetSL(ENUM_TRADE_SIGNAL sig)
    {
        double range = m_asian_high - m_asian_low;
        if(sig == SIGNAL_BUY)  return m_asian_low  + range * m_sl_inside_ratio;
        if(sig == SIGNAL_SELL) return m_asian_high - range * m_sl_inside_ratio;
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export param values for TRADE_REPORT           |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.SetParam("S09_ASIAN_START",  (double)m_asian_start);
        p.SetParam("S09_ASIAN_END",    (double)m_asian_end);
        p.SetParam("S09_LONDON_START", (double)m_london_start);
        p.SetParam("S09_NY_START",     (double)m_ny_start);
        p.SetParam("S09_RANGE_MIN",    (double)m_range_min_pips);
        p.SetParam("S09_BREAKOUT_BUF", m_breakout_buffer);
        p.SetParam("S09_SL_INSIDE",    m_sl_inside_ratio);
        p.SetParam("S09_TP_RANGE_MULT", m_tp_range_mult);
        return p;
    }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================

    //+------------------------------------------------------------------+
    //| PrintSessionStatus: Debug output for Asian range state           |
    //+------------------------------------------------------------------+
    void PrintSessionStatus()
    {
        if(!m_asian_range_valid)
        {
            PrintFormat("[S09] Asian range NOT captured yet | Time=%s", TimeToString(TimeCurrent()));
            return;
        }
        double range = m_asian_high - m_asian_low;
        double pip   = _PipSize();
        PrintFormat("[S09] Asian Range | H=%.5f L=%.5f Range=%.1f pips | ATR=%.5f | RangeOK=%s",
                    m_asian_high, m_asian_low,
                    range / pip,
                    m_last_atr,
                    (range >= (double)m_range_min_pips * pip) ? "YES" : "NO (too small)");
        PrintFormat("[S09] Breakout state | LondonLong=%s LondonShort=%s NYLong=%s NYShort=%s",
                    m_london_broken_up ? "FIRED" : "ready",
                    m_london_broken_dn ? "FIRED" : "ready",
                    m_ny_broken_up     ? "FIRED" : "ready",
                    m_ny_broken_dn     ? "FIRED" : "ready");
    }
};

#endif // S09_SESSIONBREAKOUT_MQH
//+------------------------------------------------------------------+
