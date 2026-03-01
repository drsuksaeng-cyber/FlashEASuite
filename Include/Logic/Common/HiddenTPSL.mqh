//+------------------------------------------------------------------+
//| HiddenTPSL.mqh                                                   |
//| FlashEASuite V2 V6 — Universal Hidden TP/SL Module              |
//| ซ่อน TP/SL จาก broker — เช็คด้วย MQL5 ไม่ใช่ order parameter    |
//+------------------------------------------------------------------+
//| ใช้งาน: strategies ทั้ง 16 ตัวเรียกผ่าน CHiddenTPSL instance    |
//| broker จะเห็น TP=0, SL=0 เสมอ — ระบบจัดการปิดเองจาก CheckAndClose()
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef HIDDEN_TPSL_MQH
#define HIDDEN_TPSL_MQH

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define HIDDEN_TPSL_MAX_POSITIONS 100     // max concurrent tracked positions
#define HIDDEN_TPSL_INVALID_PRICE 0.0    // sentinel = not set

//+------------------------------------------------------------------+
//| STRUCT: Hidden TP/SL record per ticket                          |
//+------------------------------------------------------------------+
struct SHiddenLevel
{
    ulong   ticket;       // Position ticket
    double  hidden_tp;    // Hidden TP price (0 = not set)
    double  hidden_sl;    // Hidden SL price (0 = not set)
    string  symbol;       // Symbol for this position
    bool    active;       // Is this slot in use?
    
    void Reset()
    {
        ticket     = 0;
        hidden_tp  = HIDDEN_TPSL_INVALID_PRICE;
        hidden_sl  = HIDDEN_TPSL_INVALID_PRICE;
        symbol     = "";
        active     = false;
    }
};

//+------------------------------------------------------------------+
//| CLASS: CHiddenTPSL — Universal Hidden TP/SL Manager             |
//+------------------------------------------------------------------+
class CHiddenTPSL
{
private:
    //--- Storage (direct members — no pointers per lessons learned)
    SHiddenLevel    m_levels[HIDDEN_TPSL_MAX_POSITIONS];
    int             m_count;           // active slot count

    //--- Feature flags (overridable by CONFIG_PUSH)
    bool            m_tp_enabled;      // hidden_tp_enabled
    bool            m_sl_enabled;      // hidden_sl_enabled

    //--- Slippage tolerance when comparing prices
    double          m_tolerance_pips;  // default 1.0 pip

    //--- Internal helpers (defined in private section below)

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                   |
    //+--------------------------------------------------------------+
    CHiddenTPSL()
    {
        m_count          = 0;
        m_tp_enabled     = true;
        m_sl_enabled     = true;
        m_tolerance_pips = 1.0;
        
        // Initialize all slots
        for(int i = 0; i < HIDDEN_TPSL_MAX_POSITIONS; i++)
            m_levels[i].Reset();
    }
    
    //+--------------------------------------------------------------+
    //| Destructor                                                    |
    //+--------------------------------------------------------------+
    ~CHiddenTPSL() {}
    
    //================================================================
    // CONFIG — Called by ConfigReceiver on CONFIG_PUSH
    //================================================================
    
    //+--------------------------------------------------------------+
    //| SetEnabled: Override feature flags from server CONFIG_PUSH   |
    //| @param tp_enabled  hidden_tp_enabled flag from server        |
    //| @param sl_enabled  hidden_sl_enabled flag from server        |
    //+--------------------------------------------------------------+
    void SetEnabled(bool tp_enabled, bool sl_enabled)
    {
        m_tp_enabled = tp_enabled;
        m_sl_enabled = sl_enabled;
        PrintFormat("[HiddenTPSL] Config updated: TP_enabled=%s SL_enabled=%s",
            m_tp_enabled ? "true" : "false",
            m_sl_enabled ? "true" : "false");
    }
    
    //+--------------------------------------------------------------+
    //| SetTolerancePips: Price tolerance for trigger comparison     |
    //+--------------------------------------------------------------+
    void SetTolerancePips(double pips) { m_tolerance_pips = MathMax(0.0, pips); }
    
    //--- Read config state
    bool IsTPEnabled() const { return m_tp_enabled; }
    bool IsSLEnabled() const { return m_sl_enabled; }
    
    //================================================================
    // MAIN API — Called by strategies
    //================================================================
    
    //+--------------------------------------------------------------+
    //| SetHiddenTP: Register a hidden take-profit level for ticket  |
    //| Broker sees TP=0 on the order — we track it here             |
    //| @param ticket  Position ticket                               |
    //| @param price   Hidden TP price (0 to clear)                 |
    //| @return true if stored successfully                          |
    //+--------------------------------------------------------------+
    bool SetHiddenTP(ulong ticket, double price)
    {
        if(!m_tp_enabled)
        {
            PrintFormat("[HiddenTPSL] TP disabled — ticket=%llu ignored", ticket);
            return false;
        }
        
        // Find position info
        if(!PositionSelectByTicket(ticket))
        {
            PrintFormat("[HiddenTPSL] SetHiddenTP: ticket=%llu not found", ticket);
            return false;
        }
        string sym = PositionGetString(POSITION_SYMBOL);
        
        int idx = _FindSlot(ticket);
        if(idx < 0) idx = _AllocSlot(ticket, sym);
        if(idx < 0)
        {
            Print("[HiddenTPSL] SetHiddenTP: slot table full!");
            return false;
        }
        
        m_levels[idx].hidden_tp = price;
        PrintFormat("[HiddenTPSL] TP set ticket=%llu price=%.5f sym=%s",
            ticket, price, sym);
        return true;
    }
    
    //+--------------------------------------------------------------+
    //| SetHiddenSL: Register a hidden stop-loss level for ticket   |
    //| @param ticket  Position ticket                               |
    //| @param price   Hidden SL price (0 to clear)                 |
    //| @return true if stored successfully                          |
    //+--------------------------------------------------------------+
    bool SetHiddenSL(ulong ticket, double price)
    {
        if(!m_sl_enabled)
        {
            PrintFormat("[HiddenTPSL] SL disabled — ticket=%llu ignored", ticket);
            return false;
        }
        
        if(!PositionSelectByTicket(ticket))
        {
            PrintFormat("[HiddenTPSL] SetHiddenSL: ticket=%llu not found", ticket);
            return false;
        }
        string sym = PositionGetString(POSITION_SYMBOL);
        
        int idx = _FindSlot(ticket);
        if(idx < 0) idx = _AllocSlot(ticket, sym);
        if(idx < 0)
        {
            Print("[HiddenTPSL] SetHiddenSL: slot table full!");
            return false;
        }
        
        m_levels[idx].hidden_sl = price;
        PrintFormat("[HiddenTPSL] SL set ticket=%llu price=%.5f sym=%s",
            ticket, price, sym);
        return true;
    }
    
    //+--------------------------------------------------------------+
    //| ClearHidden: Remove hidden levels for a ticket              |
    //+--------------------------------------------------------------+
    void ClearHidden(ulong ticket)
    {
        int idx = _FindSlot(ticket);
        if(idx >= 0)
        {
            _FreeSlot(idx);
            PrintFormat("[HiddenTPSL] Cleared ticket=%llu", ticket);
        }
    }
    
    //+--------------------------------------------------------------+
    //| CheckAndClose: Main loop — call every tick or timer          |
    //| Scans all tracked positions; closes if price crosses level   |
    //| @return number of positions closed this call                 |
    //+--------------------------------------------------------------+
    int CheckAndClose()
    {
        int closed = 0;
        
        for(int i = 0; i < HIDDEN_TPSL_MAX_POSITIONS; i++)
        {
            if(!m_levels[i].active) continue;
            
            ulong  ticket = m_levels[i].ticket;
            string sym    = m_levels[i].symbol;
            
            // Verify position still exists
            if(!PositionSelectByTicket(ticket))
            {
                // Position closed externally — clean up slot
                _FreeSlot(i);
                continue;
            }
            
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)
                PositionGetInteger(POSITION_TYPE);
            
            double bid     = _GetBid(sym);
            double ask     = _GetAsk(sym);
            double pip     = _PipSize(sym);
            double tol     = m_tolerance_pips * pip;
            
            bool tp_hit = false;
            bool sl_hit = false;
            
            // --- TP check ---
            if(m_tp_enabled && m_levels[i].hidden_tp > HIDDEN_TPSL_INVALID_PRICE)
            {
                double tp = m_levels[i].hidden_tp;
                if(pos_type == POSITION_TYPE_BUY)
                {
                    // BUY closes at bid >= hidden_tp
                    if(bid >= tp - tol) tp_hit = true;
                }
                else
                {
                    // SELL closes at ask <= hidden_tp
                    if(ask <= tp + tol) tp_hit = true;
                }
            }
            
            // --- SL check ---
            if(!tp_hit && m_sl_enabled && m_levels[i].hidden_sl > HIDDEN_TPSL_INVALID_PRICE)
            {
                double sl = m_levels[i].hidden_sl;
                if(pos_type == POSITION_TYPE_BUY)
                {
                    // BUY stops at bid <= hidden_sl
                    if(bid <= sl + tol) sl_hit = true;
                }
                else
                {
                    // SELL stops at ask >= hidden_sl
                    if(ask >= sl - tol) sl_hit = true;
                }
            }
            
            // --- Close if triggered ---
            if(tp_hit || sl_hit)
            {
                string reason = tp_hit ? "HiddenTP" : "HiddenSL";
                if(_ClosePosition(ticket, reason))
                {
                    _FreeSlot(i);
                    closed++;
                }
            }
        }
        
        return closed;
    }
    
    //+--------------------------------------------------------------+
    //| OnPositionClosed: Call when a position is known to be closed |
    //| (optional cleanup — CheckAndClose also cleans automatically) |
    //+--------------------------------------------------------------+
    void OnPositionClosed(ulong ticket)
    {
        ClearHidden(ticket);
    }
    
    //+--------------------------------------------------------------+
    //| GetTrackedCount: Number of positions currently tracked       |
    //+--------------------------------------------------------------+
    int GetTrackedCount() const { return m_count; }
    
    //+--------------------------------------------------------------+
    //| GetHiddenTP: Query stored hidden TP for a ticket            |
    //| @return price or 0 if not set                               |
    //+--------------------------------------------------------------+
    double GetHiddenTP(ulong ticket)
    {
        int idx = _FindSlot(ticket);
        return (idx >= 0) ? m_levels[idx].hidden_tp : HIDDEN_TPSL_INVALID_PRICE;
    }
    
    //+--------------------------------------------------------------+
    //| GetHiddenSL: Query stored hidden SL for a ticket            |
    //+--------------------------------------------------------------+
    double GetHiddenSL(ulong ticket)
    {
        int idx = _FindSlot(ticket);
        return (idx >= 0) ? m_levels[idx].hidden_sl : HIDDEN_TPSL_INVALID_PRICE;
    }
    
    //+--------------------------------------------------------------+
    //| PrintStatus: Debug — print all active hidden levels          |
    //+--------------------------------------------------------------+
    void PrintStatus()
    {
        PrintFormat("[HiddenTPSL] === Status: %d tracked positions ===", m_count);
        for(int i = 0; i < HIDDEN_TPSL_MAX_POSITIONS; i++)
        {
            if(!m_levels[i].active) continue;
            PrintFormat("[HiddenTPSL]  [%d] ticket=%llu sym=%s TP=%.5f SL=%.5f",
                i,
                m_levels[i].ticket,
                m_levels[i].symbol,
                m_levels[i].hidden_tp,
                m_levels[i].hidden_sl);
        }
    }

private:
    //================================================================
    // INTERNAL HELPERS
    //================================================================
    
    //+--------------------------------------------------------------+
    //| _FindSlot: Linear search for ticket in table                 |
    //| @return index or -1 if not found                            |
    //+--------------------------------------------------------------+
    int _FindSlot(ulong ticket)
    {
        for(int i = 0; i < HIDDEN_TPSL_MAX_POSITIONS; i++)
            if(m_levels[i].active && m_levels[i].ticket == ticket)
                return i;
        return -1;
    }
    
    //+--------------------------------------------------------------+
    //| _AllocSlot: Find first free slot and initialize it          |
    //| @return index or -1 if table full                           |
    //+--------------------------------------------------------------+
    int _AllocSlot(ulong ticket, string symbol)
    {
        for(int i = 0; i < HIDDEN_TPSL_MAX_POSITIONS; i++)
        {
            if(!m_levels[i].active)
            {
                m_levels[i].Reset();
                m_levels[i].ticket = ticket;
                m_levels[i].symbol = symbol;
                m_levels[i].active = true;
                m_count++;
                return i;
            }
        }
        return -1;
    }
    
    //+--------------------------------------------------------------+
    //| _FreeSlot: Release a slot                                    |
    //+--------------------------------------------------------------+
    void _FreeSlot(int idx)
    {
        if(idx < 0 || idx >= HIDDEN_TPSL_MAX_POSITIONS) return;
        if(m_levels[idx].active)
        {
            m_levels[idx].Reset();
            m_count = MathMax(0, m_count - 1);
        }
    }
    
    //+--------------------------------------------------------------+
    //| _ClosePosition: Market close a position by ticket            |
    //+--------------------------------------------------------------+
    bool _ClosePosition(ulong ticket, string reason)
    {
        if(!PositionSelectByTicket(ticket))
        {
            PrintFormat("[HiddenTPSL] _ClosePosition: ticket=%llu not found", ticket);
            return false;
        }
        
        string sym    = PositionGetString(POSITION_SYMBOL);
        double volume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)
            PositionGetInteger(POSITION_TYPE);
        
        // Opposite order type to close
        ENUM_ORDER_TYPE close_type = (ptype == POSITION_TYPE_BUY)
            ? ORDER_TYPE_SELL
            : ORDER_TYPE_BUY;
        
        double close_price = (close_type == ORDER_TYPE_SELL)
            ? SymbolInfoDouble(sym, SYMBOL_BID)
            : SymbolInfoDouble(sym, SYMBOL_ASK);
        
        MqlTradeRequest req;
        MqlTradeResult  res;
        ZeroMemory(req);
        ZeroMemory(res);
        
        req.action   = TRADE_ACTION_DEAL;
        req.position = ticket;
        req.symbol   = sym;
        req.volume   = volume;
        req.type     = close_type;
        req.price    = close_price;
        req.deviation= 20;   // 2 pip slippage tolerance
        req.comment  = reason;
        req.magic    = (long)PositionGetInteger(POSITION_MAGIC);
        
        bool ok = OrderSend(req, res);
        if(ok && res.retcode == TRADE_RETCODE_DONE)
        {
            PrintFormat("[HiddenTPSL] CLOSED ticket=%llu reason=%s price=%.5f",
                ticket, reason, close_price);
            return true;
        }
        
        PrintFormat("[HiddenTPSL] Close FAILED ticket=%llu retcode=%u reason=%s",
            ticket, res.retcode, reason);
        return false;
    }
    
    //+--------------------------------------------------------------+
    //| _GetBid / _GetAsk / _PipSize: Price helpers                 |
    //+--------------------------------------------------------------+
    double _GetBid(string symbol)
    {
        return SymbolInfoDouble(symbol, SYMBOL_BID);
    }
    
    double _GetAsk(string symbol)
    {
        return SymbolInfoDouble(symbol, SYMBOL_ASK);
    }
    
    double _PipSize(string symbol)
    {
        // Standard pip = 10 × tick size for 5-digit brokers
        double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        // For JPY pairs (2-digit): 1 pip = tick
        // For 4/5-digit pairs: 1 pip = 10 × tick
        if(digits == 2 || digits == 3)
            return tick;
        return tick * 10.0;
    }
};

#endif // HIDDEN_TPSL_MQH
