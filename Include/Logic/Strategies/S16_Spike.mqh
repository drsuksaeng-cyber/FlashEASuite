//+------------------------------------------------------------------+
//| S16_Spike.mqh                                                    |
//| FlashEASuite V2 — Spike Hunter (Legacy Wrapper → IStrategy)     |
//| Magic: 1016 | Type: Full_MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| P6-3 Enhancements (backward compatible):                         |
//|   + MMManager integration  : SetMMManager() / GetActiveMM()     |
//|   + CHiddenTPSL            : SetHiddenTP/SL per position        |
//|   + CTrailingStop          : Register/Update (real broker SL)   |
//|   + ManagePositions()      : call every tick after Analyze()    |
//|   + Max hold time check    : _CheckMaxHold()                    |
//|   + EmergencyTransferToGrid(): passthrough to TransferToGrid()  |
//+------------------------------------------------------------------+
//| CHiddenTPSL API used (from existing Common/HiddenTPSL.mqh):      |
//|   SetHiddenTP(ticket, price)  SetHiddenSL(ticket, price)        |
//|   ClearHidden(ticket)         CheckAndClose()                   |
//|   GetHiddenTP(ticket)         GetTrackedCount()                  |
//|   SetEnabled(tp_en, sl_en)                                      |
//| CTrailingStop API used (from existing Common/TrailingStop.mqh):  |
//|   Register(ticket)            Unregister(ticket)                |
//|   Update()                    SetMethod() / SetParams()         |
//|   GetTrackedCount()                                              |
//+------------------------------------------------------------------+
//| CStrategySpike API (confirmed):                                  |
//|  Init()           OnTick()          CheckEntry()                 |
//|  CheckExit()      GetScore()        GetATR()                     |
//|  SetDynamicParams(SDynamicParams&)  GetCurrentParams()           |
//+------------------------------------------------------------------+
//| Save: Include/Logic/Strategies/S16_Spike.mqh                    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.05"
#property strict

#ifndef S16_SPIKE_MQH
#define S16_SPIKE_MQH

#include "../IStrategy.mqh"
#include "../Strategy_Spike.mqh"
#include "../MM/MMManager.mqh"
#include "../Common/HiddenTPSL.mqh"
#include "../Common/TrailingStop.mqh"
#include "../Common/TransferToGrid.mqh"

//+------------------------------------------------------------------+
//| CS16Spike — IStrategy Wrapper for Spike Hunter                   |
//+------------------------------------------------------------------+
class CS16Spike : public IStrategy
{
private:
    //--- Legacy core (direct member — MISTAKE 2)
    CStrategySpike    m_spike;

    //--- Direction tracking (no GetSpikeDirection() in legacy API)
    double            m_prev_bid;
    ENUM_TRADE_SIGNAL m_last_direction;

    double            m_risk_multiplier;

    //--- P6-3: MM Manager
    CMMManager*       m_mm_mgr;

    //--- P6-3: Hidden TP/SL + Trailing (direct members)
    CHiddenTPSL       m_htpsl;
    CTrailingStop     m_trail;

    //--- TP/SL config (from StrategyDefaults: TP×0.8, SL×0.4)
    double            m_tp_atr_mult;     // Hidden TP = mult × spike ATR
    double            m_sl_atr_mult;     // Hidden SL = mult × spike ATR
    bool              m_trail_enabled;
    int               m_max_hold_sec;    // Force-close after N seconds

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    double _ParseJsonDouble(const string &json, const string key, double dv)
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return dv;
        int start = pos + StringLen(search);
        while(start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;
        string ns = "";
        for(int i = start; i < MathMin(start+20, StringLen(json)); i++)
        {
            ushort ch = StringGetCharacter(json, i);
            if(ch==',' || ch=='}' || ch==' ' || ch=='\n') break;
            ns += ShortToString(ch);
        }
        return (ns != "") ? StringToDouble(ns) : dv;
    }

    void _BuildDynamicParamsFromJson(const string json)
    {
        if(json == "") return;
        SDynamicParams cur = m_spike.GetCurrentParams();
        SDynamicParams p;
        p.Reset();
        p.risk_multiplier = m_risk_multiplier;

        p.SetParam("S16_VELOCITY_THRESH",
            _ParseJsonDouble(json,"S16_VELOCITY_THRESH",
                cur.GetParam("S16_VELOCITY_THRESH",2.5)));
        p.SetParam("S16_SPREAD_THRESH",
            _ParseJsonDouble(json,"S16_SPREAD_THRESH",
                cur.GetParam("S16_SPREAD_THRESH",1.5)));
        p.SetParam("S16_VOLUME_THRESH",
            _ParseJsonDouble(json,"S16_VOLUME_THRESH",
                cur.GetParam("S16_VOLUME_THRESH",2.0)));
        p.SetParam("S16_MOMENTUM_THRESH",
            _ParseJsonDouble(json,"S16_MOMENTUM_THRESH",
                cur.GetParam("S16_MOMENTUM_THRESH",0.5)));
        p.SetParam("S16_VOLATILITY_THRESH",
            _ParseJsonDouble(json,"S16_VOLATILITY_THRESH",
                cur.GetParam("S16_VOLATILITY_THRESH",1.5)));
        p.SetParam("S16_DIRECTION_CONSIST",
            _ParseJsonDouble(json,"S16_DIRECTION_CONSIST",
                cur.GetParam("S16_DIRECTION_CONSIST",0.7)));
        p.SetParam("S16_PATTERN_SCORE_MIN",
            _ParseJsonDouble(json,"S16_PATTERN_SCORE_MIN",
                cur.GetParam("S16_PATTERN_SCORE_MIN",70.0)));
        p.SetParam("S16_ATR_SPIKE_MULT",
            _ParseJsonDouble(json,"S16_ATR_SPIKE_MULT",
                cur.GetParam("S16_ATR_SPIKE_MULT",2.0)));

        // P6-3: hot-reload hidden TPSL config
        m_tp_atr_mult = _ParseJsonDouble(json,"S16_ATR_TP_MULT",  m_tp_atr_mult);
        m_sl_atr_mult = _ParseJsonDouble(json,"S16_ATR_SL_MULT",  m_sl_atr_mult);
        double trail_en = _ParseJsonDouble(json,"S16_TRAIL_ENABLED", m_trail_enabled?1.0:0.0);
        m_trail_enabled = (trail_en > 0.5);
        double max_hold = _ParseJsonDouble(json,"S16_MAX_HOLD_SEC",
                            cur.GetParam("S16_MAX_HOLD_SEC",(double)m_max_hold_sec));
        m_max_hold_sec = (int)max_hold;

        p.SetParam("S16_ATR_TP_MULT",   m_tp_atr_mult);
        p.SetParam("S16_ATR_SL_MULT",   m_sl_atr_mult);
        p.SetParam("S16_MAX_HOLD_SEC",  (double)m_max_hold_sec);
        m_trail.SetEnabled(m_trail_enabled);
        m_htpsl.SetEnabled(m_tp_atr_mult > 0.0, m_sl_atr_mult > 0.0);
        m_spike.SetDynamicParams(p);
    }

    //+------------------------------------------------------------------+
    //| _IsHiddenTracked: True if ticket already has a hidden level set  |
    //+------------------------------------------------------------------+
    bool _IsHiddenTracked(ulong ticket)
    {
        return (m_htpsl.GetHiddenTP(ticket) != 0.0 ||
                m_htpsl.GetHiddenSL(ticket) != 0.0);
    }

    //+------------------------------------------------------------------+
    //| _RegisterNewPositions: Set hidden TP/SL for new spike positions |
    //+------------------------------------------------------------------+
    void _RegisterNewPositions()
    {
        bool want_hidden = (m_tp_atr_mult > 0.0 || m_sl_atr_mult > 0.0);
        if(!want_hidden && !m_trail_enabled) return;

        double atr = (want_hidden) ? m_spike.GetATR() : 0.0;

        int total = PositionsTotal();
        for(int i = 0; i < total; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S16_SPIKE) continue;

            // Hidden TP/SL
            if(want_hidden && !_IsHiddenTracked(ticket) && atr > 0.0)
            {
                bool   is_buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                double open_pr = PositionGetDouble(POSITION_PRICE_OPEN);

                if(m_tp_atr_mult > 0.0)
                {
                    double tp = is_buy ? open_pr + m_tp_atr_mult * atr
                                       : open_pr - m_tp_atr_mult * atr;
                    m_htpsl.SetHiddenTP(ticket, tp);
                }
                if(m_sl_atr_mult > 0.0)
                {
                    double sl = is_buy ? open_pr - m_sl_atr_mult * atr
                                       : open_pr + m_sl_atr_mult * atr;
                    m_htpsl.SetHiddenSL(ticket, sl);
                }

                PrintFormat("[S16] Registered hidden TP/SL #%d | %s | ATR=%.5f",
                            ticket, is_buy ? "BUY" : "SELL", atr);
            }

            // Trailing stop
            if(m_trail_enabled)
                m_trail.Register(ticket);
        }
    }

    //+------------------------------------------------------------------+
    //| _CheckMaxHold: Force-close spike positions held too long        |
    //+------------------------------------------------------------------+
    void _CheckMaxHold()
    {
        if(m_max_hold_sec <= 0) return;
        datetime now = TimeCurrent();
        int total = PositionsTotal();
        for(int i = total-1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S16_SPIKE) continue;

            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            if((int)(now - open_time) < m_max_hold_sec) continue;

            PrintFormat("[S16] MaxHold %ds exceeded for #%d — closing",
                        m_max_hold_sec, ticket);
            long   pos_type = PositionGetInteger(POSITION_TYPE);
            string sym      = PositionGetString(POSITION_SYMBOL);
            double volume   = PositionGetDouble(POSITION_VOLUME);
            double price    = (pos_type == POSITION_TYPE_BUY)
                              ? SymbolInfoDouble(sym, SYMBOL_BID)
                              : SymbolInfoDouble(sym, SYMBOL_ASK);
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action       = TRADE_ACTION_DEAL;
            req.position     = ticket;
            req.symbol       = sym;
            req.volume       = volume;
            req.type         = (pos_type==POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price        = price;
            req.deviation    = 10;
            req.magic        = MAGIC_S16_SPIKE;
            req.comment      = "S16_MaxHold";
            req.type_filling = ORDER_FILLING_IOC;
            if(OrderSend(req, res))
            {
                m_htpsl.ClearHidden(ticket);
                m_trail.Unregister(ticket);
            }
        }
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CS16Spike()
    {
        m_strategy_id     = S16_SPIKE;
        m_prev_bid        = 0.0;
        m_last_direction  = SIGNAL_NONE;
        m_risk_multiplier = 1.0;
        m_mm_mgr          = NULL;
        // Defaults from StrategyDefaults (TP×0.8, SL×0.4 ATR)
        m_tp_atr_mult     = 0.8;
        m_sl_atr_mult     = 0.4;
        m_trail_enabled   = false;
        m_max_hold_sec    = 900;    // 15 minutes
    }

    virtual ~CS16Spike() {}

    //=================================================================
    //  CORE INTERFACE
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;
        if(!m_spike.Init())
        {
            Print("[S16] ERROR: CStrategySpike.Init() failed");
            return false;
        }
        m_prev_bid = 0.0;
        // Enable hidden TP/SL by default (TP×0.8, SL×0.4)
        m_htpsl.SetEnabled(true, true);
        m_initialized = true;
        PrintFormat("[S16] Spike initialized | Symbol=%s TF=%s | TP×%.1f SL×%.1f ATR",
                    symbol, EnumToString(tf), m_tp_atr_mult, m_sl_atr_mult);
        return true;
    }

    virtual void Deinit() override
    {
        m_htpsl.SetEnabled(false, false);
        m_trail.SetEnabled(false);
        // ★ BUG-001 FIX: explicit call — m_spike เป็น direct member
        // destructor ไม่รันตอน Deinit() ต้อง explicit เรียกเอง
        m_spike.Deinit();
        m_initialized    = false;
        m_prev_bid       = 0.0;
        m_last_direction = SIGNAL_NONE;
        IStrategy::Deinit();
    }

    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;

        m_spike.OnTick();

        // Infer direction from bid movement (P2-3 lesson: no GetSpikeDirection())
        if(m_prev_bid > 0.0)
        {
            if(tick.bid > m_prev_bid)       m_last_direction = SIGNAL_BUY;
            else if(tick.bid < m_prev_bid)  m_last_direction = SIGNAL_SELL;
        }
        m_prev_bid = tick.bid;

        bool entry = m_spike.CheckEntry();
        if(entry && m_last_direction != SIGNAL_NONE)
        {
            m_state.last_signal     = m_last_direction;
            m_state.last_confidence = MathMin(m_spike.GetScore() / 100.0, 1.0);
        }
        else
        {
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
        }
        m_state.last_signal_time = tick.time;
    }

    //+------------------------------------------------------------------+
    //| ManagePositions: Call every tick AFTER Analyze()                |
    //| 1. Register new positions → hidden TP/SL (SetHiddenTP/SL)     |
    //| 2. CTrailingStop.Update() → adjust real broker SL              |
    //| 3. CHiddenTPSL.CheckAndClose() → close on hidden TP/SL hit    |
    //| 4. _CheckMaxHold() → force-close if held too long              |
    //+------------------------------------------------------------------+
    void ManagePositions(const MqlTick &tick)
    {
        if(!m_initialized) return;
        _RegisterNewPositions();
        if(m_trail_enabled) m_trail.Update();
        m_htpsl.CheckAndClose();
        _CheckMaxHold();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal()     { return m_state.last_signal;     }
    virtual double            GetConfidence() { return m_state.last_confidence; }

    //=================================================================
    //  P6-3: MM MANAGER
    //=================================================================

    void SetMMManager(CMMManager* mgr) { m_mm_mgr = mgr; }

    ENUM_MM_ID GetActiveMM()
    {
        if(m_mm_mgr == NULL) return MM_ID_FIXED_CONSERVATIVE;
        SAccountState acct;
        acct.UpdateFromAccount();
        return m_mm_mgr.SelectMM((int)S16_SPIKE, acct);
    }

    ENUM_MM_ID GetActiveMM_WithRegime(ENUM_MARKET_REGIME regime)
    {
        if(m_mm_mgr == NULL) return MM_ID_FIXED_CONSERVATIVE;
        SAccountState acct;
        acct.UpdateFromAccount();
        return m_mm_mgr.SelectMMByRegime((int)S16_SPIKE, regime, acct);
    }

    void SetStandaloneMode(bool standalone)
    {
        if(m_mm_mgr != NULL) m_mm_mgr.SetStandaloneMode(standalone);
    }

    //=================================================================
    //  P6-3: HIDDEN TP/SL CONFIG
    //=================================================================

    //+------------------------------------------------------------------+
    //| SetTPSLConfig: Configure hidden TP/SL + trailing + max hold     |
    //+------------------------------------------------------------------+
    void SetTPSLConfig(double tp_atr_mult, double sl_atr_mult,
                       bool trail_enabled = false,
                       ENUM_TRAIL_METHOD trail_method = TS_ATR,
                       int max_hold_sec = 900)
    {
        m_tp_atr_mult   = tp_atr_mult;
        m_sl_atr_mult   = sl_atr_mult;
        m_trail_enabled = trail_enabled;
        m_max_hold_sec  = max_hold_sec;
        m_htpsl.SetEnabled(tp_atr_mult > 0.0, sl_atr_mult > 0.0);
        m_trail.SetEnabled(trail_enabled);
        m_trail.SetMethod(trail_method);
    }

    //=================================================================
    //  P6-3: EMERGENCY TRANSFER
    //=================================================================

    STransferResult EmergencyTransferToGrid(
        ENUM_TRANSFER_REASON reason = TRANSFER_STRATEGY_SIGNAL)
    {
        // Clean up tracking for non-grid positions before closing them
        int total = PositionsTotal();
        for(int i = total-1; i >= 0; i--)
        {
            ulong t = PositionGetTicket(i);
            if(t == 0) continue;
            if(!PositionSelectByTicket(t)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) == MAGIC_S15_GRID) continue;
            m_htpsl.ClearHidden(t);
            m_trail.Unregister(t);
        }
        return TransferToGrid(m_symbol, MAGIC_S15_GRID, reason);
    }

    //=================================================================
    //  CONFIG INTERFACE
    //=================================================================

    virtual void SetParameters(const string jsonParams)
    {
        IStrategy::SetParameters(jsonParams);
        _BuildDynamicParamsFromJson(jsonParams);
    }

    virtual void SetDynamicParams(SDynamicParams &params)
    {
        IStrategy::SetDynamicParams(params);
        m_risk_multiplier = params.risk_multiplier;
        m_spike.SetDynamicParams(params);
    }

    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p = m_spike.GetCurrentParams();
        p.mm_method = m_config.mm_method;   // MISTAKE 5
        return p;
    }

    //=================================================================
    //  IDENTITY
    //=================================================================
    virtual string GetName()             { return "Spike Hunter";  }
    virtual int    GetMagic()            { return MAGIC_S16_SPIKE; }
    virtual bool   IsStandaloneCapable() { return true;            }
    virtual string GetCategory()         { return "Full_MQL5";     }

    //=================================================================
    //  SPIKE-SPECIFIC ACCESS
    //=================================================================
    double GetRawScore()        { return m_spike.GetScore();        }
    double GetSpikeATR()        { return m_spike.GetATR();          }
    bool   CheckExit()          { return m_spike.CheckExit();       }
    int    GetHiddenTPSLCount() { return m_htpsl.GetTrackedCount(); }
    int    GetTrailCount()      { return m_trail.GetTrackedCount(); }

    void PrintDiagnostics()
    {
        PrintFormat("[S16] Spike | Symbol=%s | ATR=%.5f | RawScore=%.1f",
                    m_symbol, m_spike.GetATR(), m_spike.GetScore());
        PrintFormat("[S16] Signal=%s | Confidence=%.4f | Direction=%s | RiskMult=%.2f",
                    SignalToString(m_state.last_signal),
                    m_state.last_confidence,
                    m_last_direction == SIGNAL_BUY ? "BUY":
                    m_last_direction == SIGNAL_SELL? "SELL":"NONE",
                    m_risk_multiplier);
        PrintFormat("[S16] MM=%s | ActiveMM=%s",
                    m_config.mm_method,
                    m_mm_mgr != NULL
                        ? m_mm_mgr.GetMMName((int)GetActiveMM())
                        : "MMManager not set");
        PrintFormat("[S16] HiddenTPSL=%d tracked | Trail=%d tracked | MaxHold=%ds",
                    m_htpsl.GetTrackedCount(), m_trail.GetTrackedCount(), m_max_hold_sec);
        PrintFormat("[S16] TPSL config: TP×%.1f ATR | SL×%.1f ATR",
                    m_tp_atr_mult, m_sl_atr_mult);
        m_htpsl.PrintStatus();
    }
};

#endif // S16_SPIKE_MQH
//+------------------------------------------------------------------+
