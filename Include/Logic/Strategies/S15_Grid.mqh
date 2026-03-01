//+------------------------------------------------------------------+
//| S15_Grid.mqh                                                     |
//| FlashEASuite V2 — Immortal Grid (Legacy Wrapper → IStrategy)    |
//| Magic: 1015 | Type: Full_MQL5 | Standalone: Yes                 |
//+------------------------------------------------------------------+
//| P6-3 Enhancements (backward compatible):                         |
//|   + MMManager integration  : SetMMManager() / GetActiveMM()     |
//|   + CHiddenTPSL            : SetHiddenTP/SL per position        |
//|   + CTrailingStop          : Register/Update (real broker SL)   |
//|   + ManagePositions()      : call every tick after Analyze()    |
//|   + EmergencyTransferToGrid(): passthrough to TransferToGrid()  |
//+------------------------------------------------------------------+
//| CHiddenTPSL API used (from existing Common/HiddenTPSL.mqh):      |
//|   SetHiddenTP(ticket, price)  SetHiddenSL(ticket, price)        |
//|   ClearHidden(ticket)         CheckAndClose()                   |
//|   GetHiddenTP(ticket)         GetTrackedCount()                  |
//|   SetEnabled(tp_en, sl_en)                                      |
//| CTrailingStop API used (from existing Common/TrailingStop.mqh):  |
//|   Register(ticket)            Register(ticket, params)          |
//|   Unregister(ticket)          Update()                          |
//|   SetMethod(method)           SetParams(params)                  |
//|   GetTrackedCount()                                              |
//+------------------------------------------------------------------+
//| CStrategyGrid API (confirmed from source):                       |
//|  Constructor  : CStrategyGrid() — no params                     |
//|  GetScore()   : double — 0 params                               |
//|  GetCurrentDirection() : ENUM_GRID_DIRECTION                    |
//|  GetActiveGridCount()  : int                                     |
//|  GetMaxGridLevels()    : int                                     |
//|  SetSymbol(string)     : void                                    |
//|  SetDynamicParams(SDynamicParams&) : void                        |
//|  GetCurrentParams()    : SDynamicParams                         |
//+------------------------------------------------------------------+
//| Save: Include/Logic/Strategies/S15_Grid.mqh                     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.03"
#property strict

#ifndef S15_GRID_MQH
#define S15_GRID_MQH

#include "../IStrategy.mqh"
#include "../Grid/GridCore.mqh"
#include "../MM/MMManager.mqh"
#include "../Common/HiddenTPSL.mqh"
#include "../Common/TrailingStop.mqh"
#include "../Common/TransferToGrid.mqh"

//+------------------------------------------------------------------+
//| CS15Grid — IStrategy Wrapper for Immortal Grid                   |
//+------------------------------------------------------------------+
class CS15Grid : public IStrategy
{
private:
    //--- Legacy core (direct member — MISTAKE 2)
    CStrategyGrid   m_grid;

    double          m_risk_multiplier;

    //--- P6-3: MM Manager (pointer — supplied externally, may be NULL)
    CMMManager*     m_mm_mgr;

    //--- P6-3: Hidden TP/SL + Trailing (direct members)
    CHiddenTPSL     m_htpsl;
    CTrailingStop   m_trail;

    //--- TP/SL config (ATR-based; 0 = disabled)
    double          m_tp_atr_mult;       // Hidden TP = mult × ATR (0=off)
    double          m_sl_atr_mult;       // Hidden SL = mult × ATR (0=off)
    bool            m_trail_enabled;     // Trailing stop on/off
    ENUM_TRAIL_METHOD m_trail_method;    // Default = TS_FIXED

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
        SDynamicParams p;
        p.Reset();
        SDynamicParams cur = m_grid.GetCurrentParams();
        p.risk_multiplier = m_risk_multiplier;
        p.SetParam("S15_MAX_ORDERS",
            _ParseJsonDouble(json,"S15_MAX_ORDERS",
                cur.GetParam("S15_MAX_ORDERS",(double)m_grid.GetMaxGridLevels())));
        p.SetParam("S15_BASE_STEP",
            _ParseJsonDouble(json,"S15_BASE_STEP",
                cur.GetParam("S15_BASE_STEP",200.0)));
        p.SetParam("S15_ELASTIC_FACTOR",
            _ParseJsonDouble(json,"S15_ELASTIC_FACTOR",
                cur.GetParam("S15_ELASTIC_FACTOR",1.5)));
        p.SetParam("S15_CONF_THRESHOLD",
            _ParseJsonDouble(json,"S15_CONF_THRESHOLD",
                cur.GetParam("S15_CONF_THRESHOLD",0.65)));
        p.SetParam("S15_ATR_RATIO",
            _ParseJsonDouble(json,"S15_ATR_RATIO",
                cur.GetParam("S15_ATR_RATIO",0.8)));
        p.SetParam("S15_SWAP_FILTER",
            _ParseJsonDouble(json,"S15_SWAP_FILTER",
                cur.GetParam("S15_SWAP_FILTER",1.0)));
        // P6-3: TP/SL/Trail hot-reload from server
        m_tp_atr_mult   = _ParseJsonDouble(json,"S15_TP_ATR_MULT", m_tp_atr_mult);
        m_sl_atr_mult   = _ParseJsonDouble(json,"S15_SL_ATR_MULT", m_sl_atr_mult);
        double trail_en = _ParseJsonDouble(json,"S15_TRAIL_ENABLED", m_trail_enabled?1.0:0.0);
        m_trail_enabled = (trail_en > 0.5);
        m_trail.SetEnabled(m_trail_enabled);
        m_grid.SetDynamicParams(p);
    }

    //+------------------------------------------------------------------+
    //| _GetATR14: ATR(14) for current symbol/tf                        |
    //+------------------------------------------------------------------+
    double _GetATR14()
    {
        int h = iATR(m_symbol, m_timeframe, 14);
        if(h == INVALID_HANDLE) return 0.0;
        double buf[1];
        int copied = CopyBuffer(h, 0, 1, 1, buf);
        IndicatorRelease(h);
        return (copied == 1) ? buf[0] : 0.0;
    }

    //+------------------------------------------------------------------+
    //| _IsHiddenTracked: Check if ticket has any hidden level set      |
    //+------------------------------------------------------------------+
    bool _IsHiddenTracked(ulong ticket)
    {
        return (m_htpsl.GetHiddenTP(ticket) != 0.0 ||
                m_htpsl.GetHiddenSL(ticket) != 0.0);
    }

    //+------------------------------------------------------------------+
    //| _RegisterNewPositions: Register newly opened grid positions     |
    //| CHiddenTPSL: SetHiddenTP + SetHiddenSL                         |
    //| CTrailingStop: Register(ticket) — uses m_params (TRADE_ACTION_SLTP)
    //+------------------------------------------------------------------+
    void _RegisterNewPositions()
    {
        bool want_hidden = (m_tp_atr_mult > 0.0 || m_sl_atr_mult > 0.0);
        if(!want_hidden && !m_trail_enabled) return;

        double atr = (want_hidden) ? _GetATR14() : 0.0;

        int total = PositionsTotal();
        for(int i = 0; i < total; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S15_GRID) continue;

            // Hidden TP/SL — skip if already set
            if(want_hidden && !_IsHiddenTracked(ticket) && atr > 0.0)
            {
                bool   is_buy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                double open_pr  = PositionGetDouble(POSITION_PRICE_OPEN);

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
            }

            // Trailing — Register only once (CTrailingStop dup-checks internally)
            if(m_trail_enabled)
                m_trail.Register(ticket);
        }
    }

    //+------------------------------------------------------------------+
    //| _CleanupClosedPositions: ClearHidden for tickets no longer open |
    //+------------------------------------------------------------------+
    void _CleanupClosedPositions()
    {
        // Handled automatically by CheckAndClose() / CTrailingStop.Update()
        // Additional cleanup: any ticket where PositionSelectByTicket fails
        // is cleaned by CHiddenTPSL.CheckAndClose internal scan
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CS15Grid()
    {
        m_strategy_id     = S15_GRID;
        m_risk_multiplier = 1.0;
        m_mm_mgr          = NULL;
        m_tp_atr_mult     = 0.0;
        m_sl_atr_mult     = 0.0;
        m_trail_enabled   = false;
        m_trail_method    = TS_FIXED;
    }

    virtual ~CS15Grid() {}

    //=================================================================
    //  CORE INTERFACE
    //=================================================================

    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;
        m_grid.SetSymbol(symbol);
        m_initialized = true;
        PrintFormat("[S15] Grid initialized | Symbol=%s TF=%s MaxLevels=%d",
                    symbol, EnumToString(tf), m_grid.GetMaxGridLevels());
        return true;
    }

    virtual void Deinit()
    {
        m_trail.SetEnabled(false);
        IStrategy::Deinit();
    }

    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;
        double score = m_grid.GetScore();
        if(score > 0.0)
        {
            ENUM_GRID_DIRECTION dir = m_grid.GetCurrentDirection();
            m_state.last_signal =
                (dir == GRID_DIR_BUY)  ? SIGNAL_BUY  :
                (dir == GRID_DIR_SELL) ? SIGNAL_SELL  : SIGNAL_NONE;
            m_state.last_confidence = MathMin(score, 1.0);
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
    //| 1. Register newly opened positions → hidden TP/SL + trailing   |
    //| 2. CTrailingStop.Update() → move real broker SL                |
    //| 3. CHiddenTPSL.CheckAndClose() → close on hidden TP/SL hit    |
    //+------------------------------------------------------------------+
    void ManagePositions(const MqlTick &tick)
    {
        if(!m_initialized) return;
        _RegisterNewPositions();
        if(m_trail_enabled) m_trail.Update();
        m_htpsl.CheckAndClose();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal()     { return m_state.last_signal;     }
    virtual double            GetConfidence() { return m_state.last_confidence; }

    //=================================================================
    //  P6-3: MM MANAGER
    //=================================================================

    //+------------------------------------------------------------------+
    //| SetMMManager: Inject shared MMManager (called by StrategyManager)|
    //+------------------------------------------------------------------+
    void SetMMManager(CMMManager* mgr) { m_mm_mgr = mgr; }

    //+------------------------------------------------------------------+
    //| GetActiveMM: Auto-select MM based on regime + DD + override     |
    //+------------------------------------------------------------------+
    ENUM_MM_ID GetActiveMM()
    {
        if(m_mm_mgr == NULL) return MM_ID_FIXED_CONSERVATIVE;
        SAccountState acct;
        acct.UpdateFromAccount();
        return m_mm_mgr.SelectMM((int)S15_GRID, acct);
    }

    ENUM_MM_ID GetActiveMM_WithRegime(ENUM_MARKET_REGIME regime)
    {
        if(m_mm_mgr == NULL) return MM_ID_FIXED_CONSERVATIVE;
        SAccountState acct;
        acct.UpdateFromAccount();
        return m_mm_mgr.SelectMMByRegime((int)S15_GRID, regime, acct);
    }

    void SetStandaloneMode(bool standalone)
    {
        if(m_mm_mgr != NULL) m_mm_mgr.SetStandaloneMode(standalone);
    }

    //=================================================================
    //  P6-3: HIDDEN TP/SL CONFIG
    //=================================================================

    //+------------------------------------------------------------------+
    //| SetTPSLConfig: Configure hidden TP/SL and trailing stop         |
    //| @param tp_atr_mult   Hidden TP = mult x ATR14 (0 = disabled)   |
    //| @param sl_atr_mult   Hidden SL = mult x ATR14 (0 = disabled)   |
    //| @param trail_enabled Enable CTrailingStop for broker SL trail   |
    //| @param trail_method  TS_FIXED / TS_ATR / TS_PARABOLIC etc.     |
    //+------------------------------------------------------------------+
    void SetTPSLConfig(double tp_atr_mult, double sl_atr_mult,
                       bool trail_enabled = false,
                       ENUM_TRAIL_METHOD trail_method = TS_FIXED)
    {
        m_tp_atr_mult   = tp_atr_mult;
        m_sl_atr_mult   = sl_atr_mult;
        m_trail_enabled = trail_enabled;
        m_trail_method  = trail_method;
        m_trail.SetEnabled(trail_enabled);
        m_trail.SetMethod(trail_method);
        m_htpsl.SetEnabled(tp_atr_mult > 0.0, sl_atr_mult > 0.0);
    }

    //+------------------------------------------------------------------+
    //| SetTPSLConfig (overload): With full STrailParams (by reference) |
    //| MQL5: objects always by reference -- no pointer/NULL default    |
    //+------------------------------------------------------------------+
    void SetTPSLConfig(double tp_atr_mult, double sl_atr_mult,
                       STrailParams &trail_params)
    {
        m_tp_atr_mult   = tp_atr_mult;
        m_sl_atr_mult   = sl_atr_mult;
        m_trail_enabled = true;
        m_trail_method  = trail_params.method;
        m_trail.SetEnabled(true);
        m_trail.SetParams(trail_params);
        m_htpsl.SetEnabled(tp_atr_mult > 0.0, sl_atr_mult > 0.0);
    }

    //=================================================================
    //  P6-3: EMERGENCY TRANSFER
    //=================================================================

    STransferResult EmergencyTransferToGrid(
        ENUM_TRANSFER_REASON reason = TRANSFER_STRATEGY_SIGNAL)
    {
        // Cleanup tracking before positions are closed
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
        m_grid.SetDynamicParams(params);
    }

    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p = m_grid.GetCurrentParams();
        p.mm_method = m_config.mm_method;   // MISTAKE 5
        return p;
    }

    //=================================================================
    //  IDENTITY
    //=================================================================
    virtual string GetName()             { return "Immortal Grid"; }
    virtual int    GetMagic()            { return MAGIC_S15_GRID;  }
    virtual bool   IsStandaloneCapable() { return true;            }
    virtual string GetCategory()         { return "Full_MQL5";     }

    //=================================================================
    //  GRID-SPECIFIC ACCESS
    //=================================================================
    CStrategyGrid*      GetGrid()            { return &m_grid;                        }
    int                 GetActiveGridCount() { return m_grid.GetActiveGridCount();    }
    ENUM_GRID_DIRECTION GetGridDirection()   { return m_grid.GetCurrentDirection();   }
    int                 GetHiddenTPSLCount() { return m_htpsl.GetTrackedCount();      }
    int                 GetTrailCount()      { return m_trail.GetTrackedCount();      }

    void PrintDiagnostics()
    {
        PrintFormat("[S15] Grid | Symbol=%s | MaxLevels=%d | ActiveLevels=%d",
                    m_symbol, m_grid.GetMaxGridLevels(), m_grid.GetActiveGridCount());
        PrintFormat("[S15] Signal=%s | Confidence=%.4f | RiskMult=%.2f",
                    SignalToString(m_state.last_signal),
                    m_state.last_confidence, m_risk_multiplier);
        PrintFormat("[S15] MM=%s | ActiveMM=%s",
                    m_config.mm_method,
                    m_mm_mgr != NULL
                        ? m_mm_mgr.GetMMName((int)GetActiveMM())
                        : "MMManager not set");
        PrintFormat("[S15] HiddenTPSL=%d tracked | Trail=%d tracked | TP×%.1f SL×%.1f",
                    m_htpsl.GetTrackedCount(), m_trail.GetTrackedCount(),
                    m_tp_atr_mult, m_sl_atr_mult);
        m_htpsl.PrintStatus();
    }
};

#endif // S15_GRID_MQH
//+------------------------------------------------------------------+
