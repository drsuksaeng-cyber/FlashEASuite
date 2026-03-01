//+------------------------------------------------------------------+
//| TrailingStop.mqh                                                 |
//| FlashEASuite V2 V6 — Universal Trailing Stop Module (5 Methods) |
//| ใช้งานได้กับทุก 16 strategies                                    |
//+------------------------------------------------------------------+
//| Methods:                                                         |
//|   1. TS_FIXED       — Fixed Distance (X pips)                   |
//|   2. TS_ATR         — ATR × multiplier                          |
//|   3. TS_PARABOLIC   — Parabolic SAR as trailing level            |
//|   4. TS_CHANDELIER  — Highest High - ATR × multiplier           |
//|   5. TS_BREAKEVEN   — Move to entry first, then Fixed trail      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef TRAILING_STOP_MQH
#define TRAILING_STOP_MQH

//+------------------------------------------------------------------+
//| ENUM: Trailing method — all values >= 0 (MQL5 rule)             |
//+------------------------------------------------------------------+
enum ENUM_TRAIL_METHOD
{
    TS_FIXED      = 0,   // Fixed distance in pips
    TS_ATR        = 1,   // ATR-based
    TS_PARABOLIC  = 2,   // Parabolic SAR
    TS_CHANDELIER = 3,   // Chandelier Exit
    TS_BREAKEVEN  = 4    // Breakeven + Fixed trail
};

//+------------------------------------------------------------------+
//| ENUM: Breakeven state                                            |
//+------------------------------------------------------------------+
enum ENUM_BE_STATE
{
    BE_WAITING  = 0,   // Not yet moved to breakeven
    BE_APPLIED  = 1    // SL already moved to entry (breakeven done)
};

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define TRAIL_MAX_POSITIONS  100     // max concurrent tracked positions
#define TRAIL_ATR_PERIOD     14      // default ATR period
#define TRAIL_ATR_BARS       100     // bars needed for ATR calc

//+------------------------------------------------------------------+
//| STRUCT: Parameters for one trailing stop instance               |
//+------------------------------------------------------------------+
struct STrailParams
{
    ENUM_TRAIL_METHOD   method;

    // TS_FIXED
    double  fixed_pips;         // trail distance in pips

    // TS_ATR
    double  atr_multiplier;     // e.g. 2.0 → trail = ATR×2
    int     atr_period;         // ATR period

    // TS_PARABOLIC (uses built-in iSAR)
    double  sar_step;           // SAR acceleration step (e.g. 0.02)
    double  sar_maximum;        // SAR acceleration max  (e.g. 0.2)

    // TS_CHANDELIER
    double  chandelier_mult;    // e.g. 3.0 → Highest High - ATR×3
    int     chandelier_period;  // lookback for highest high
    int     chandelier_atr;     // ATR period for chandelier

    // TS_BREAKEVEN
    double  be_trigger_pips;    // profit pips to trigger breakeven move
    double  be_trail_pips;      // fixed trail pips AFTER breakeven

    void Reset()
    {
        method            = TS_FIXED;
        fixed_pips        = 20.0;
        atr_multiplier    = 2.0;
        atr_period        = 14;
        sar_step          = 0.02;
        sar_maximum       = 0.20;
        chandelier_mult   = 3.0;
        chandelier_period = 22;
        chandelier_atr    = 14;
        be_trigger_pips   = 15.0;
        be_trail_pips     = 10.0;
    }
};

//+------------------------------------------------------------------+
//| STRUCT: Per-position trailing state                             |
//+------------------------------------------------------------------+
struct STrailRecord
{
    ulong               ticket;
    string              symbol;
    ENUM_POSITION_TYPE  pos_type;     // BUY or SELL
    double              open_price;   // entry price (for breakeven)
    double              current_sl;   // last SL we set
    ENUM_BE_STATE       be_state;     // breakeven state
    bool                active;

    // Indicator handles (per position)
    int     atr_handle;          // iATR handle
    int     sar_handle;          // iSAR handle

    void Reset()
    {
        ticket     = 0;
        symbol     = "";
        pos_type   = POSITION_TYPE_BUY;
        open_price = 0.0;
        current_sl = 0.0;
        be_state   = BE_WAITING;
        active     = false;
        atr_handle = INVALID_HANDLE;
        sar_handle = INVALID_HANDLE;
    }
};

//+------------------------------------------------------------------+
//| CLASS: CTrailingStop — Universal Trailing Stop Manager           |
//+------------------------------------------------------------------+
class CTrailingStop
{
private:
    STrailRecord    m_records[TRAIL_MAX_POSITIONS];   // direct array
    int             m_count;
    STrailParams    m_params;        // default params (overridable)
    bool            m_enabled;

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                   |
    //+--------------------------------------------------------------+
    CTrailingStop()
    {
        m_count   = 0;
        m_enabled = true;
        m_params.Reset();
        for(int i = 0; i < TRAIL_MAX_POSITIONS; i++)
            m_records[i].Reset();
    }

    ~CTrailingStop() {}

    //================================================================
    // CONFIG — from CONFIG_PUSH
    //================================================================

    //+--------------------------------------------------------------+
    //| SetEnabled: Turn trailing on/off globally                    |
    //+--------------------------------------------------------------+
    void SetEnabled(bool enabled) { m_enabled = enabled; }
    bool IsEnabled() const        { return m_enabled; }

    //+--------------------------------------------------------------+
    //| SetMethod: Change trailing method (global default)           |
    //+--------------------------------------------------------------+
    void SetMethod(ENUM_TRAIL_METHOD method) { m_params.method = method; }

    //+--------------------------------------------------------------+
    //| SetParams: Full params override from CONFIG_PUSH             |
    //+--------------------------------------------------------------+
    void SetParams(STrailParams &p) { m_params = p; }

    //+--------------------------------------------------------------+
    //| GetParams: Read current params                               |
    //+--------------------------------------------------------------+
    STrailParams GetParams() { return m_params; }

    //================================================================
    // MAIN API
    //================================================================

    //+--------------------------------------------------------------+
    //| Register: Start trailing — use global m_params              |
    //| @return true if registered successfully                      |
    //+--------------------------------------------------------------+
    bool Register(ulong ticket)
    {
        return _RegisterWithParams(ticket, m_params);
    }

    //+--------------------------------------------------------------+
    //| Register: Start trailing — use per-position params override  |
    //+--------------------------------------------------------------+
    bool Register(ulong ticket, STrailParams &params)
    {
        return _RegisterWithParams(ticket, params);
    }

    //+--------------------------------------------------------------+
    //| Unregister: Stop trailing a position (call after close)      |
    //+--------------------------------------------------------------+
    void Unregister(ulong ticket)
    {
        int idx = _FindSlot(ticket);
        if(idx >= 0) _FreeSlot(idx);
    }

    //+--------------------------------------------------------------+
    //| Update: Process all tracked positions — call every tick      |
    //| @return number of SL modifications made                      |
    //+--------------------------------------------------------------+
    int Update()
    {
        if(!m_enabled) return 0;

        int modified = 0;

        for(int i = 0; i < TRAIL_MAX_POSITIONS; i++)
        {
            if(!m_records[i].active) continue;

            ulong ticket = m_records[i].ticket;

            if(!PositionSelectByTicket(ticket))
            {
                _FreeSlot(i);   // position closed externally
                continue;
            }

            double new_sl = _CalcNewSL(i);
            if(new_sl <= 0.0) continue;

            // Only move SL in the favourable direction
            bool should_modify = false;
            if(m_records[i].pos_type == POSITION_TYPE_BUY)
                should_modify = (new_sl > m_records[i].current_sl + _PipSize(m_records[i].symbol) * 0.1);
            else
                should_modify = (new_sl < m_records[i].current_sl - _PipSize(m_records[i].symbol) * 0.1 ||
                                 m_records[i].current_sl == 0.0);

            if(should_modify)
            {
                if(_ModifySL(ticket, m_records[i].symbol, new_sl))
                {
                    m_records[i].current_sl = new_sl;
                    modified++;
                }
            }
        }

        return modified;
    }

    //+--------------------------------------------------------------+
    //| GetTrackedCount                                               |
    //+--------------------------------------------------------------+
    int GetTrackedCount() const { return m_count; }

    //+--------------------------------------------------------------+
    //| GetCurrentSL: Query last SL we set for a ticket              |
    //+--------------------------------------------------------------+
    double GetCurrentSL(ulong ticket)
    {
        int idx = _FindSlot(ticket);
        return (idx >= 0) ? m_records[idx].current_sl : 0.0;
    }

    //+--------------------------------------------------------------+
    //| PrintStatus: Debug dump                                       |
    //+--------------------------------------------------------------+
    void PrintStatus()
    {
        PrintFormat("[Trail] === Status: %d tracked positions enabled=%s ===",
            m_count, m_enabled ? "true" : "false");
        for(int i = 0; i < TRAIL_MAX_POSITIONS; i++)
        {
            if(!m_records[i].active) continue;
            PrintFormat("[Trail]  [%d] ticket=%llu sym=%s type=%s sl=%.5f be=%d",
                i,
                m_records[i].ticket,
                m_records[i].symbol,
                m_records[i].pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL",
                m_records[i].current_sl,
                (int)m_records[i].be_state);
        }
    }

private:
    //================================================================
    // SL CALCULATION — one method per ENUM_TRAIL_METHOD
    //================================================================

    //+--------------------------------------------------------------+
    //| _CalcNewSL: Route to correct method                          |
    //| @return new SL price, or 0 if cannot calculate               |
    //+--------------------------------------------------------------+
    double _CalcNewSL(int idx)
    {
        string sym = m_records[idx].symbol;
        ENUM_POSITION_TYPE ptype = m_records[idx].pos_type;

        switch(m_params.method)
        {
            case TS_FIXED:      return _CalcFixed(idx);
            case TS_ATR:        return _CalcATR(idx);
            case TS_PARABOLIC:  return _CalcParabolic(idx);
            case TS_CHANDELIER: return _CalcChandelier(idx);
            case TS_BREAKEVEN:  return _CalcBreakeven(idx);
        }
        return 0.0;
    }

    //+--------------------------------------------------------------+
    //| Method 1: Fixed Distance                                     |
    //| Trail SL by fixed_pips below/above current price             |
    //+--------------------------------------------------------------+
    double _CalcFixed(int idx)
    {
        string sym = m_records[idx].symbol;
        double pip = _PipSize(sym);
        double trail_dist = m_params.fixed_pips * pip;

        if(m_records[idx].pos_type == POSITION_TYPE_BUY)
        {
            double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            return bid - trail_dist;
        }
        else
        {
            double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
            return ask + trail_dist;
        }
    }

    //+--------------------------------------------------------------+
    //| Method 2: ATR-Based                                          |
    //| Trail SL by ATR × multiplier from current price              |
    //+--------------------------------------------------------------+
    double _CalcATR(int idx)
    {
        int handle = m_records[idx].atr_handle;
        if(handle == INVALID_HANDLE) return 0.0;

        double atr_buf[];
        ArraySetAsSeries(atr_buf, true);
        if(CopyBuffer(handle, 0, 0, 1, atr_buf) < 1) return 0.0;

        double atr  = atr_buf[0];
        double dist = atr * m_params.atr_multiplier;
        string sym  = m_records[idx].symbol;

        if(m_records[idx].pos_type == POSITION_TYPE_BUY)
            return SymbolInfoDouble(sym, SYMBOL_BID) - dist;
        else
            return SymbolInfoDouble(sym, SYMBOL_ASK) + dist;
    }

    //+--------------------------------------------------------------+
    //| Method 3: Parabolic SAR                                      |
    //| Use SAR value directly as the trailing SL level              |
    //+--------------------------------------------------------------+
    double _CalcParabolic(int idx)
    {
        int handle = m_records[idx].sar_handle;
        if(handle == INVALID_HANDLE) return 0.0;

        double sar_buf[];
        ArraySetAsSeries(sar_buf, true);
        if(CopyBuffer(handle, 0, 0, 1, sar_buf) < 1) return 0.0;

        // SAR is the trailing level — use directly
        return sar_buf[0];
    }

    //+--------------------------------------------------------------+
    //| Method 4: Chandelier Exit                                    |
    //| BUY:  Highest High(period) - ATR(atr_period) × mult         |
    //| SELL: Lowest Low(period)   + ATR(atr_period) × mult         |
    //+--------------------------------------------------------------+
    double _CalcChandelier(int idx)
    {
        int handle = m_records[idx].atr_handle;
        if(handle == INVALID_HANDLE) return 0.0;

        string sym = m_records[idx].symbol;
        ENUM_TIMEFRAMES tf = _GetPositionTimeframe(sym);
        int period = m_params.chandelier_period;

        double atr_buf[];
        ArraySetAsSeries(atr_buf, true);
        if(CopyBuffer(handle, 0, 0, 1, atr_buf) < 1) return 0.0;
        double atr = atr_buf[0];

        if(m_records[idx].pos_type == POSITION_TYPE_BUY)
        {
            double highest_high = 0.0;
            double high_buf[];
            ArraySetAsSeries(high_buf, true);
            if(CopyHigh(sym, tf, 0, period, high_buf) < period) return 0.0;
            highest_high = high_buf[ArrayMaximum(high_buf, 0, period)];
            return highest_high - atr * m_params.chandelier_mult;
        }
        else
        {
            double low_buf[];
            ArraySetAsSeries(low_buf, true);
            if(CopyLow(sym, tf, 0, period, low_buf) < period) return 0.0;
            double lowest_low = low_buf[ArrayMinimum(low_buf, 0, period)];
            return lowest_low + atr * m_params.chandelier_mult;
        }
    }

    //+--------------------------------------------------------------+
    //| Method 5: Breakeven + Fixed Trail                            |
    //| Phase 1: wait until profit >= be_trigger_pips               |
    //|          → move SL to open_price (breakeven)                |
    //| Phase 2: apply fixed trail with be_trail_pips               |
    //+--------------------------------------------------------------+
    double _CalcBreakeven(int idx)
    {
        string sym   = m_records[idx].symbol;
        double pip   = _PipSize(sym);
        double entry = m_records[idx].open_price;

        if(m_records[idx].pos_type == POSITION_TYPE_BUY)
        {
            double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
            double profit_pips = (bid - entry) / pip;

            // Phase 1: not yet at breakeven
            if(m_records[idx].be_state == BE_WAITING)
            {
                if(profit_pips >= m_params.be_trigger_pips)
                {
                    m_records[idx].be_state = BE_APPLIED;
                    PrintFormat("[Trail] BE triggered ticket=%llu entry=%.5f",
                        m_records[idx].ticket, entry);
                    return entry;   // move SL to entry
                }
                return 0.0;   // not ready yet
            }

            // Phase 2: fixed trail from current price
            return bid - m_params.be_trail_pips * pip;
        }
        else // SELL
        {
            double ask         = SymbolInfoDouble(sym, SYMBOL_ASK);
            double profit_pips = (entry - ask) / pip;

            if(m_records[idx].be_state == BE_WAITING)
            {
                if(profit_pips >= m_params.be_trigger_pips)
                {
                    m_records[idx].be_state = BE_APPLIED;
                    PrintFormat("[Trail] BE triggered ticket=%llu entry=%.5f",
                        m_records[idx].ticket, entry);
                    return entry;
                }
                return 0.0;
            }

            return ask + m_params.be_trail_pips * pip;
        }
    }

    //================================================================
    // ORDER MODIFICATION
    //================================================================

    //+--------------------------------------------------------------+
    //| _ModifySL: Send TRADE_ACTION_SLTP to update SL              |
    //+--------------------------------------------------------------+
    bool _ModifySL(ulong ticket, string sym, double new_sl)
    {
        if(!PositionSelectByTicket(ticket)) return false;

        double cur_tp = PositionGetDouble(POSITION_TP);

        MqlTradeRequest req;
        MqlTradeResult  res;
        ZeroMemory(req);
        ZeroMemory(res);

        req.action   = TRADE_ACTION_SLTP;
        req.position = ticket;
        req.symbol   = sym;
        req.sl       = NormalizeDouble(new_sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
        req.tp       = cur_tp;   // keep existing TP unchanged

        bool ok = OrderSend(req, res);
        if(ok && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL))
        {
            PrintFormat("[Trail] SL moved ticket=%llu new_sl=%.5f", ticket, new_sl);
            return true;
        }

        PrintFormat("[Trail] SL modify FAILED ticket=%llu retcode=%u sl=%.5f",
            ticket, res.retcode, new_sl);
        return false;
    }

    //================================================================
    // INTERNAL HELPERS
    //================================================================

    bool _RegisterWithParams(ulong ticket, STrailParams &p)
    {
        if(!m_enabled) return false;

        if(!PositionSelectByTicket(ticket))
        {
            PrintFormat("[Trail] Register: ticket=%llu not found", ticket);
            return false;
        }

        // Duplicate check
        if(_FindSlot(ticket) >= 0)
        {
            PrintFormat("[Trail] Register: ticket=%llu already registered", ticket);
            return true;
        }

        int idx = _AllocSlot();
        if(idx < 0)
        {
            Print("[Trail] Register: slot table full!");
            return false;
        }

        string sym             = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE pt  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double open_price      = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur_sl          = PositionGetDouble(POSITION_SL);

        m_records[idx].ticket     = ticket;
        m_records[idx].symbol     = sym;
        m_records[idx].pos_type   = pt;
        m_records[idx].open_price = open_price;
        m_records[idx].current_sl = cur_sl;
        m_records[idx].be_state   = BE_WAITING;
        m_records[idx].active     = true;

        ENUM_TIMEFRAMES tf = _GetPositionTimeframe(sym);

        if(p.method == TS_ATR || p.method == TS_BREAKEVEN || p.method == TS_CHANDELIER)
            m_records[idx].atr_handle = iATR(sym, tf, p.atr_period);
        if(p.method == TS_PARABOLIC)
            m_records[idx].sar_handle = iSAR(sym, tf, p.sar_step, p.sar_maximum);

        PrintFormat("[Trail] Registered ticket=%llu sym=%s method=%d open=%.5f",
            ticket, sym, (int)p.method, open_price);
        return true;
    }

    int _FindSlot(ulong ticket)
    {
        for(int i = 0; i < TRAIL_MAX_POSITIONS; i++)
            if(m_records[i].active && m_records[i].ticket == ticket)
                return i;
        return -1;
    }

    int _AllocSlot()
    {
        for(int i = 0; i < TRAIL_MAX_POSITIONS; i++)
        {
            if(!m_records[i].active)
            {
                m_records[i].Reset();
                m_count++;
                return i;
            }
        }
        return -1;
    }

    void _FreeSlot(int idx)
    {
        if(idx < 0 || idx >= TRAIL_MAX_POSITIONS) return;
        if(!m_records[idx].active) return;

        // Release indicator handles
        if(m_records[idx].atr_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_records[idx].atr_handle);
            m_records[idx].atr_handle = INVALID_HANDLE;
        }
        if(m_records[idx].sar_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_records[idx].sar_handle);
            m_records[idx].sar_handle = INVALID_HANDLE;
        }

        m_records[idx].Reset();
        m_count = MathMax(0, m_count - 1);
    }

    double _PipSize(string symbol)
    {
        double tick   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        if(digits == 2 || digits == 3) return tick;
        return tick * 10.0;
    }

    //+--------------------------------------------------------------+
    //| _GetPositionTimeframe: Return chart TF for indicator init    |
    //| Uses PERIOD_M15 as default (sufficient for trailing calcs)   |
    //+--------------------------------------------------------------+
    ENUM_TIMEFRAMES _GetPositionTimeframe(string symbol)
    {
        // For trailing, M15 is appropriate for all strategies
        return PERIOD_M15;
    }
};

#endif // TRAILING_STOP_MQH
