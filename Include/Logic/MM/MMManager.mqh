//+------------------------------------------------------------------+
//| MMManager.mqh                                                    |
//| FlashEASuite V2 — Money Manager Selector & Manager              |
//| เลือก MM Method ที่เหมาะสมสำหรับแต่ละ Strategy                  |
//|                                                                  |
//| ฟังก์ชันหลัก:                                                    |
//|   SelectMM(strategyID, regime, dd_pct) → ENUM_MM_ID              |
//|   ApplyConfig(strategyID, mm_id) → server override               |
//|   GetActiveMM(strategyID) → MM ID ที่ใช้งานอยู่                 |
//|   IsStandaloneMode() → true = ทุก strategy ใช้ MM01             |
//|                                                                  |
//| MM Selection Matrix (จาก mm_selection_matrix.json):             |
//|   S01 StatArb:  Default=MM04, Volatile=MM07, DD=MM10            |
//|   S06 KAMA:     Default=MM08, Volatile=MM16, DD=MM10            |
//|   S07 MeanRev:  Default=MM01, Volatile=MM07, DD=MM10            |
//|   S10 Turtle:   Default=MM08, Volatile=MM16, DD=MM10            |
//|   S14 BBSqz:    Default=MM03, Volatile=MM07, DD=MM10            |
//|   S15 Grid:     Default=MM03, Volatile=MM17, DD=MM10            |
//|   S16 Spike:    Default=MM01, Volatile=MM01, DD=MM10            |
//|   Others:       Default=MM01, Volatile=MM17, DD=MM10            |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MMMANAGER_MQH
#define MMMANAGER_MQH

#include "IMoneyManager.mqh"
// NOTE: ENUM_MARKET_REGIME comes from Definitions.mqh (included via IStrategy chain)
// DO NOT include MM17_RegimeBased.mqh here — it re-defines ENUM_MARKET_REGIME → duplicate error
// #include "MM17_RegimeBased.mqh"
#include "../../Network/Protocol/Definitions.mqh"    // ENUM_MARKET_REGIME (UNKNOWN/TRENDING/RANGING/VOLATILE/SQUEEZE)

//+------------------------------------------------------------------+
//| STRUCT: Account State (for SelectMM input)                       |
//+------------------------------------------------------------------+
struct SAccountState
{
    double balance;         // Account balance
    double equity;          // Account equity
    double peak_equity;     // Highest equity (for DD calc)
    double drawdown_pct;    // Current drawdown % from peak
    bool   is_standalone;   // True = no server connection

    void Reset()
    {
        balance      = 0.0;
        equity       = 0.0;
        peak_equity  = 0.0;
        drawdown_pct = 0.0;
        is_standalone= false;
    }

    // Helper: update DD from live account
    void UpdateFromAccount()
    {
        balance = AccountInfoDouble(ACCOUNT_BALANCE);
        equity  = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity > peak_equity) peak_equity = equity;
        if(peak_equity > 0.0)
            drawdown_pct = (peak_equity - equity) / peak_equity * 100.0;
        else
            drawdown_pct = 0.0;
    }
};

//+------------------------------------------------------------------+
//| STRUCT: MM Selection Entry per Strategy                          |
//+------------------------------------------------------------------+
struct SMMSelection
{
    int default_mm;         // Default MM method ID
    int volatile_mm;        // MM when market is volatile
    int dd_mm;              // MM when DD > threshold (always 10)
    int active_mm;          // Currently active MM (may be server override)
    bool server_override;   // True = server forced a specific MM
};

//+------------------------------------------------------------------+
//| CONSTANTS: DD thresholds for MM10 switch                         |
//+------------------------------------------------------------------+
#define MMGR_DD_TIER1_PCT   10.0    // DD > 10% → switch to DD MM (MM10)
#define MMGR_DD_TIER2_PCT   15.0    // DD > 15% → additional restriction
#define MMGR_DD_STOP_PCT    20.0    // DD > 20% → stop new trades

//+------------------------------------------------------------------+
//| CLASS: CMMManager                                                |
//+------------------------------------------------------------------+
class CMMManager
{
private:
    SMMSelection    m_selection[16];    // One entry per strategy (S01-S16, index 0-15)
    bool            m_standalone_mode;  // True = all strategies use MM01
    ENUM_MARKET_REGIME m_current_regime;// Current global market regime

    //+--------------------------------------------------------------+
    //| InitDefaultMatrix: Load default MM selection from matrix     |
    //| Source: mm_selection_matrix.json P0.6-2                     |
    //+--------------------------------------------------------------+
    void InitDefaultMatrix()
    {
        // Default: all strategies → MM01, volatile → MM17, DD → MM10
        for(int i = 0; i < 16; i++)
        {
            m_selection[i].default_mm      = MM_ID_FIXED_CONSERVATIVE; // MM01
            m_selection[i].volatile_mm     = MM_ID_REGIME_BASED;        // MM17
            m_selection[i].dd_mm           = MM_ID_DRAWDOWN_BASED;      // MM10
            m_selection[i].active_mm       = MM_ID_FIXED_CONSERVATIVE;
            m_selection[i].server_override = false;
        }

        // --- S01: StatArb → MM04 Kelly, Volatile → MM07
        m_selection[0].default_mm  = MM_ID_KELLY;           // MM04
        m_selection[0].volatile_mm = MM_ID_PCT_VOLATILITY;  // MM07

        // --- S02-S05: Various → MM01, Volatile → MM17
        // (already set as default above)

        // --- S06: KAMA → MM08 Pyramid, Volatile → MM16 Vol%
        m_selection[5].default_mm  = MM_ID_PYRAMID;         // MM08
        m_selection[5].volatile_mm = MM_ID_VOL_PERCENTILE;  // MM16

        // --- S07: MeanReversion → MM01, Volatile → MM07
        m_selection[6].default_mm  = MM_ID_FIXED_CONSERVATIVE; // MM01
        m_selection[6].volatile_mm = MM_ID_PCT_VOLATILITY;     // MM07

        // --- S08, S09: → MM01, Volatile → MM17 (default already set)

        // --- S10: Turtle → MM08 Pyramid, Volatile → MM16 Vol%
        m_selection[9].default_mm  = MM_ID_PYRAMID;         // MM08
        m_selection[9].volatile_mm = MM_ID_VOL_PERCENTILE;  // MM16

        // --- S11, S12: → MM01, Volatile → MM17 (default already set)

        // --- S13: → MM01, Volatile → MM07
        m_selection[12].volatile_mm = MM_ID_PCT_VOLATILITY; // MM07

        // --- S14: BBSqueeze → MM03 ATR, Volatile → MM07
        m_selection[13].default_mm  = MM_ID_ATR_BASED;      // MM03
        m_selection[13].volatile_mm = MM_ID_PCT_VOLATILITY; // MM07

        // --- S15: Grid → MM03 ATR, Volatile → MM17 Regime
        m_selection[14].default_mm  = MM_ID_ATR_BASED;      // MM03
        m_selection[14].volatile_mm = MM_ID_REGIME_BASED;   // MM17

        // --- S16: Spike → MM01, Volatile → MM01 (no size change)
        m_selection[15].default_mm  = MM_ID_FIXED_CONSERVATIVE; // MM01
        m_selection[15].volatile_mm = MM_ID_FIXED_CONSERVATIVE; // MM01

        // Sync active_mm to default_mm
        for(int i = 0; i < 16; i++)
            m_selection[i].active_mm = m_selection[i].default_mm;
    }

    //+--------------------------------------------------------------+
    //| ValidateStrategyIdx: ensure 0-15                             |
    //+--------------------------------------------------------------+
    bool ValidateIdx(int idx)
    {
        return (idx >= 0 && idx <= 15);
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMMManager()
    {
        m_standalone_mode = false;
        m_current_regime  = REGIME_RANGING;
        InitDefaultMatrix();
    }

    //+--------------------------------------------------------------+
    //| Setup: call once at EA startup                               |
    //+--------------------------------------------------------------+
    void Setup(bool standalone_mode = false)
    {
        m_standalone_mode = standalone_mode;
        InitDefaultMatrix();
    }

    //+--------------------------------------------------------------+
    //| SetStandaloneMode: toggle standalone (true = all use MM01)  |
    //+--------------------------------------------------------------+
    void SetStandaloneMode(bool standalone)
    {
        m_standalone_mode = standalone;
        if(standalone)
        {
            // In standalone: clear all server overrides, use MM01
            for(int i = 0; i < 16; i++)
            {
                m_selection[i].server_override = false;
                m_selection[i].active_mm       = MM_ID_FIXED_CONSERVATIVE; // MM01
            }
        }
    }

    //+--------------------------------------------------------------+
    //| SetRegime: Update global market regime                       |
    //+--------------------------------------------------------------+
    void SetRegime(ENUM_MARKET_REGIME regime)
    {
        m_current_regime = regime;
    }

    //+--------------------------------------------------------------+
    //| SelectMM: Choose best MM for a strategy given current state  |
    //| @param strategy_idx  Strategy index 0-15 (S01=0 … S16=15)  |
    //| @param acct          Current account state with DD info      |
    //| @return ENUM_MM_ID   Best MM method for this strategy now    |
    //+--------------------------------------------------------------+
    ENUM_MM_ID SelectMM(int strategy_idx, const SAccountState &acct)
    {
        // Standalone mode → MM01 always
        if(m_standalone_mode || acct.is_standalone)
            return MM_ID_FIXED_CONSERVATIVE;

        if(!ValidateIdx(strategy_idx))
            return MM_ID_FIXED_CONSERVATIVE;

        // Server override takes priority
        if(m_selection[strategy_idx].server_override)
            return (ENUM_MM_ID)m_selection[strategy_idx].active_mm;

        // DD emergency check (highest priority after standalone/override)
        if(acct.drawdown_pct >= MMGR_DD_TIER1_PCT)
            return (ENUM_MM_ID)m_selection[strategy_idx].dd_mm;

        // Volatile/Squeeze regime check (REGIME_CRISIS not in Definitions.mqh — use REGIME_SQUEEZE)
        if(m_current_regime == REGIME_VOLATILE || m_current_regime == REGIME_SQUEEZE)
            return (ENUM_MM_ID)m_selection[strategy_idx].volatile_mm;

        // Normal → use default for this strategy
        return (ENUM_MM_ID)m_selection[strategy_idx].default_mm;
    }

    //+--------------------------------------------------------------+
    //| SelectMMByRegime: Overload with explicit regime parameter    |
    //+--------------------------------------------------------------+
    ENUM_MM_ID SelectMMByRegime(int strategy_idx,
                                 ENUM_MARKET_REGIME regime,
                                 const SAccountState &acct)
    {
        m_current_regime = regime;
        return SelectMM(strategy_idx, acct);
    }

    //+--------------------------------------------------------------+
    //| ApplyConfig: Server CONFIG_PUSH overrides MM for a strategy  |
    //| @param strategy_idx  0-15                                    |
    //| @param mm_id         1-19 (0 = remove override)             |
    //+--------------------------------------------------------------+
    void ApplyConfig(int strategy_idx, int mm_id)
    {
        if(!ValidateIdx(strategy_idx)) return;

        if(mm_id <= 0)
        {
            // Remove server override → revert to auto-select
            m_selection[strategy_idx].server_override = false;
            m_selection[strategy_idx].active_mm = m_selection[strategy_idx].default_mm;
            return;
        }

        if(mm_id < 1 || mm_id > 19) return; // Invalid ID

        m_selection[strategy_idx].server_override = true;
        m_selection[strategy_idx].active_mm       = mm_id;
    }

    //+--------------------------------------------------------------+
    //| ApplyConfigAll: Apply same MM override to all strategies     |
    //| Used for emergency global MM change from server              |
    //+--------------------------------------------------------------+
    void ApplyConfigAll(int mm_id)
    {
        for(int i = 0; i < 16; i++)
            ApplyConfig(i, mm_id);
    }

    //+--------------------------------------------------------------+
    //| ClearAllOverrides: Remove all server overrides               |
    //+--------------------------------------------------------------+
    void ClearAllOverrides()
    {
        for(int i = 0; i < 16; i++)
        {
            m_selection[i].server_override = false;
            m_selection[i].active_mm = m_selection[i].default_mm;
        }
    }

    //+--------------------------------------------------------------+
    //| GetActiveMM: Return currently configured MM for a strategy  |
    //| Note: this is the CONFIGURED value, not runtime-selected    |
    //| For runtime selection, call SelectMM() instead              |
    //+--------------------------------------------------------------+
    ENUM_MM_ID GetActiveMM(int strategy_idx)
    {
        if(!ValidateIdx(strategy_idx))
            return MM_ID_FIXED_CONSERVATIVE;

        if(m_standalone_mode)
            return MM_ID_FIXED_CONSERVATIVE;

        return (ENUM_MM_ID)m_selection[strategy_idx].active_mm;
    }

    //+--------------------------------------------------------------+
    //| GetDefaultMM / GetVolatileMM / GetDDMM: Matrix accessors    |
    //+--------------------------------------------------------------+
    ENUM_MM_ID GetDefaultMM(int strategy_idx)
    {
        if(!ValidateIdx(strategy_idx)) return MM_ID_FIXED_CONSERVATIVE;
        return (ENUM_MM_ID)m_selection[strategy_idx].default_mm;
    }

    ENUM_MM_ID GetVolatileMM(int strategy_idx)
    {
        if(!ValidateIdx(strategy_idx)) return MM_ID_REGIME_BASED;
        return (ENUM_MM_ID)m_selection[strategy_idx].volatile_mm;
    }

    ENUM_MM_ID GetDDMM(int strategy_idx)
    {
        if(!ValidateIdx(strategy_idx)) return MM_ID_DRAWDOWN_BASED;
        return (ENUM_MM_ID)m_selection[strategy_idx].dd_mm;
    }

    //+--------------------------------------------------------------+
    //| IsStandaloneMode                                             |
    //+--------------------------------------------------------------+
    bool IsStandaloneMode() { return m_standalone_mode; }

    //+--------------------------------------------------------------+
    //| GetCurrentRegime                                             |
    //+--------------------------------------------------------------+
    ENUM_MARKET_REGIME GetCurrentRegime() { return m_current_regime; }

    //+--------------------------------------------------------------+
    //| GetMMName: human-readable name for a MM ID                  |
    //+--------------------------------------------------------------+
    string GetMMName(int mm_id)
    {
        switch(mm_id)
        {
            case 1:  return "MM01_FixedConservative";
            case 2:  return "MM02_FixedAggressive";
            case 3:  return "MM03_ATRBased";
            case 4:  return "MM04_KellyCriterion";
            case 5:  return "MM05_Martingale";
            case 6:  return "MM06_AntiMartingale";
            case 7:  return "MM07_PctVolatility";
            case 8:  return "MM08_Pyramid";
            case 9:  return "MM09_EquityRecovery";
            case 10: return "MM10_DrawdownBased";
            case 11: return "MM11_SessionBased";
            case 12: return "MM12_EquityFilter";
            case 13: return "MM13_CorrelationAdj";
            case 14: return "MM14_TieredRisk";
            case 15: return "MM15_AdaptiveStreak";
            case 16: return "MM16_VolPercentile";
            case 17: return "MM17_RegimeBased";
            case 18: return "MM18_PortfolioCap";
            case 19: return "MM19_DynamicMulti";
            default: return "MM_UNKNOWN";
        }
    }

    //+--------------------------------------------------------------+
    //| PrintStatus: Print full MM selection matrix status           |
    //+--------------------------------------------------------------+
    void PrintStatus()
    {
        string mode = m_standalone_mode ? "STANDALONE (MM01 forced)" : "SERVER-CONNECTED";

        string regime_names[] = {"UNKNOWN","TRENDING","RANGING","VOLATILE","CRISIS"};
        int ridx = (int)m_current_regime;
        string rname = (ridx >= 0 && ridx <= 4) ? regime_names[ridx] : "UNKNOWN";

        PrintFormat("[MMManager] Mode=%s | Regime=%s", mode, rname);

        string strategy_names[] = {
            "S01_StatArb","S02_MLEns","S03_SMC","S04_MarketProf",
            "S05_SupplyDem","S06_KAMA","S07_MeanRev","S08_Intermarket",
            "S09_SessBrk","S10_Turtle","S11_Ichimoku","S12_PriceAct",
            "S13_FibStoch","S14_BBSqueeze","S15_Grid","S16_Spike"
        };

        for(int i = 0; i < 16; i++)
        {
            string override_flag = m_selection[i].server_override ? " [OVERRIDE]" : "";
            PrintFormat("  [%s] Default=%-22s Volatile=%-22s DD=%-22s Active=%-22s%s",
                strategy_names[i],
                GetMMName(m_selection[i].default_mm),
                GetMMName(m_selection[i].volatile_mm),
                GetMMName(m_selection[i].dd_mm),
                GetMMName(m_selection[i].active_mm),
                override_flag);
        }
    }
};

#endif // MMMANAGER_MQH
//+------------------------------------------------------------------+
