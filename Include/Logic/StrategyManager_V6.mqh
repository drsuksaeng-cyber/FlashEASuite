//+------------------------------------------------------------------+
//| StrategyManager_V6.mqh                                           |
//| FlashEASuite V2 V6 — Strategy Manager (Full 16-Strategy Version) |
//| Updated: P2-4 — RegisterAllStrategies() + Full Integration       |
//+------------------------------------------------------------------+
//| Architecture: CStrategyManager_V6 owns 16 direct strategy objects |
//| (no pointer members in class → MISTAKE 2 safe)                   |
//| Internal IStrategy* registry[] points to those owned members.    |
//|                                                                  |
//| Include chain (all flow downward, no circular deps):             |
//|   StrategyManager_V6.mqh                                         |
//|     → Strategies/SXX.mqh (each)                                 |
//|         → IStrategy.mqh                                          |
//|             → StrategyConstants.mqh                              |
//|             → Network/Protocol/Definitions.mqh                   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef STRATEGYMANAGER_V6_MQH
#define STRATEGYMANAGER_V6_MQH

//--- NOTE: IStrategy.mqh included transitively through each SXX.mqh
//--- Include all 16 strategy headers
//--- Path relative to Include/Logic/ (this file's location)
#include "Strategies/S01_StatArb.mqh"
#include "Strategies/S02_ML_Ensemble.mqh"
#include "Strategies/S03_SMC.mqh"
#include "Strategies/S04_MarketProfile.mqh"
#include "Strategies/S05_SupplyDemand.mqh"
#include "Strategies/S06_KAMA.mqh"
#include "Strategies/S07_MeanReversion.mqh"
#include "Strategies/S08_Intermarket.mqh"
#include "Strategies/S09_SessionBreakout.mqh"
#include "Strategies/S10_Turtle.mqh"
#include "Strategies/S11_Ichimoku.mqh"
#include "Strategies/S12_PriceAction.mqh"
#include "Strategies/S13_FibStoch.mqh"
#include "Strategies/S14_BBSqueeze.mqh"
#include "Strategies/S15_Grid.mqh"
#include "Strategies/S16_Spike.mqh"

//+------------------------------------------------------------------+
//| STRUCT: Strategy Status Snapshot (for GetStrategyStatus())       |
//+------------------------------------------------------------------+
struct SStrategyStatusEntry
{
    string              short_name;
    string              name;
    bool                enabled;
    bool                initialized;
    bool                standalone_capable;
    ENUM_TRADE_SIGNAL   last_signal;
    double              last_confidence;
};

//+------------------------------------------------------------------+
//| CLASS: CStrategyManager_V6                                        |
//| Manages registration, enable/disable, and tick processing        |
//| for all 16 V6 strategies.                                        |
//+------------------------------------------------------------------+
class CStrategyManager_V6
{
private:
    //=================================================================
    //  16 DIRECT STRATEGY OBJECTS — No pointers (MISTAKE 2 lesson)
    //  Objects live here → safe from cascade errors
    //=================================================================
    CStatArb         m_s01;   // S01 Statistical Arbitrage
    CS02MLEnsemble   m_s02;   // S02 ML Ensemble
    CSMCV6           m_s03;   // S03 Smart Money Concepts
    CMarketProfile   m_s04;   // S04 Market Profile
    CSupplyDemand    m_s05;   // S05 Supply & Demand
    CKAMATrend       m_s06;   // S06 KAMA Trend
    CMeanReversion   m_s07;   // S07 Mean Reversion
    CIntermarket     m_s08;   // S08 Intermarket Correlation
    CSessionBreakout m_s09;   // S09 Session Breakout
    CTurtle          m_s10;   // S10 Turtle Trading
    CIchimoku        m_s11;   // S11 Multi-TF Ichimoku
    CS12PriceAction  m_s12;   // S12 Price Action (Pin Bar)
    CFibStoch        m_s13;   // S13 Fibonacci + Stochastic
    CBBSqueeze       m_s14;   // S14 BB Squeeze Breakout
    CS15Grid         m_s15;   // S15 Immortal Grid (Legacy)
    CS16Spike        m_s16;   // S16 Spike Hunter (Legacy)

    //--- Internal pointer registry — points to above members (safe)
    IStrategy*  m_registry[TOTAL_STRATEGIES];
    bool        m_registered;
    bool        m_server_connected;

    //--- Runtime context
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    //=================================================================
    //  PRIVATE: Wire pointers to direct members
    //  Called once in RegisterAllStrategies()
    //=================================================================
    void _BuildRegistry()
    {
        m_registry[S01_STAT_ARB]         = &m_s01;
        m_registry[S02_ML_ENSEMBLE]      = &m_s02;
        m_registry[S03_SMC]              = &m_s03;
        m_registry[S04_MARKET_PROFILE]   = &m_s04;
        m_registry[S05_SUPPLY_DEMAND]    = &m_s05;
        m_registry[S06_KAMA]             = &m_s06;
        m_registry[S07_MEAN_REVERSION]   = &m_s07;
        m_registry[S08_INTERMARKET]      = &m_s08;
        m_registry[S09_SESSION_BREAKOUT] = &m_s09;
        m_registry[S10_TURTLE]           = &m_s10;
        m_registry[S11_ICHIMOKU]         = &m_s11;
        m_registry[S12_PRICE_ACTION]     = &m_s12;
        m_registry[S13_FIB_STOCH]        = &m_s13;
        m_registry[S14_BB_SQUEEZE]       = &m_s14;
        m_registry[S15_GRID]             = &m_s15;
        m_registry[S16_SPIKE]            = &m_s16;
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CStrategyManager_V6()
    {
        m_registered       = false;
        m_server_connected = false;
        m_symbol           = "";
        m_timeframe        = PERIOD_M15;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            m_registry[i] = NULL;
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CStrategyManager_V6() {}

    //=================================================================
    //  REGISTRATION
    //=================================================================

    //+------------------------------------------------------------------+
    //| RegisterAllStrategies: Init all 16 strategies on given symbol/TF |
    //| @return true if ALL 16 Init() succeed                            |
    //+------------------------------------------------------------------+
    bool RegisterAllStrategies(string symbol, ENUM_TIMEFRAMES tf)
    {
        m_symbol    = symbol;
        m_timeframe = tf;
        _BuildRegistry();

        int ok_count  = 0;
        int fail_count = 0;

        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL) { fail_count++; continue; }

            if(m_registry[i].Init(symbol, tf))
            {
                ok_count++;
                PrintFormat("[StrategyManager] S%02d %-24s Init OK", i + 1,
                            m_registry[i].GetName());
            }
            else
            {
                fail_count++;
                PrintFormat("[StrategyManager] S%02d %-24s Init FAILED ⚠", i + 1,
                            m_registry[i].GetName());
            }
        }

        m_registered = (fail_count == 0);
        PrintFormat("[StrategyManager] Registration complete: %d OK / %d FAILED",
                    ok_count, fail_count);
        return m_registered;
    }

    //=================================================================
    //  ENABLE / DISABLE
    //=================================================================

    //+------------------------------------------------------------------+
    //| EnableByConfig: Parse SConfigData → enable/disable each strategy  |
    //| Called after receiving CONFIG_PUSH from server                   |
    //+------------------------------------------------------------------+
    void EnableByConfig(const SConfigData &config)
    {
        int enabled_count = 0;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL) continue;
            if(config.strategy_enabled[i])
            {
                m_registry[i].Enable();
                enabled_count++;
            }
            else
            {
                m_registry[i].Disable();
            }
        }
        PrintFormat("[StrategyManager] EnableByConfig: %d strategies enabled (regime=%s)",
                    enabled_count, EnumToString(config.regime));
    }

    //+------------------------------------------------------------------+
    //| DisableAllExcept: Enable only specified IDs — for standalone mode |
    //| @param ids[]  Array of ENUM_STRATEGY_ID to keep enabled          |
    //| @param count  Number of elements in ids[]                        |
    //+------------------------------------------------------------------+
    void DisableAllExcept(ENUM_STRATEGY_ID &ids[], int count)
    {
        // Step 1: Disable all
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(m_registry[i] != NULL) m_registry[i].Disable();

        // Step 2: Enable only specified standalone strategies
        for(int j = 0; j < count; j++)
        {
            int idx = (int)ids[j];
            if(idx >= 0 && idx < TOTAL_STRATEGIES && m_registry[idx] != NULL)
            {
                // Only enable if standalone-capable (safety check)
                if(m_registry[idx].IsStandaloneCapable())
                {
                    m_registry[idx].Enable();
                    PrintFormat("[StrategyManager] Standalone enable: %s",
                                m_registry[idx].GetShortName());
                }
                else
                {
                    PrintFormat("[StrategyManager] WARNING: %s is ServerOnly — skip standalone enable",
                                m_registry[idx].GetShortName());
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| EnableAllStandalone: Quick helper for cold start / server offline |
    //| Enables the 7 standalone strategies; disables ServerOnly 9       |
    //+------------------------------------------------------------------+
    void EnableAllStandalone()
    {
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL) continue;
            if(m_registry[i].IsStandaloneCapable())
                m_registry[i].Enable();
            else
                m_registry[i].Disable();
        }
        PrintFormat("[StrategyManager] Standalone mode: 7 strategies enabled");
    }

    //+------------------------------------------------------------------+
    //| EnableStrategy_V6 / DisableStrategy_V6: Per-strategy toggle      |
    //+------------------------------------------------------------------+
    void EnableStrategy_V6(ENUM_STRATEGY_ID id)
    {
        int idx = (int)id;
        if(idx >= 0 && idx < TOTAL_STRATEGIES && m_registry[idx] != NULL)
            m_registry[idx].Enable();
    }

    void DisableStrategy_V6(ENUM_STRATEGY_ID id)
    {
        int idx = (int)id;
        if(idx >= 0 && idx < TOTAL_STRATEGIES && m_registry[idx] != NULL)
            m_registry[idx].Disable();
    }

    //+------------------------------------------------------------------+
    //| SetServerConnected: Toggle server online/offline flag             |
    //| When offline → ServerOnly strategies are skipped in OnTick()    |
    //+------------------------------------------------------------------+
    void SetServerConnected(bool connected)
    {
        m_server_connected = connected;
    }

    //=================================================================
    //  TICK PROCESSING
    //=================================================================

    //+------------------------------------------------------------------+
    //| OnTick: Call Analyze() on all enabled strategies                 |
    //| ServerOnly strategies are skipped when server is disconnected    |
    //+------------------------------------------------------------------+
    void OnTick(const MqlTick &tick)
    {
        if(!m_registered) return;

        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL)        continue;
            if(!m_registry[i].IsEnabled())   continue;
            if(!m_registry[i].IsInitialized()) continue;

            // ServerOnly check: skip if disconnected AND not standalone capable
            if(!m_server_connected && !m_registry[i].IsStandaloneCapable())
                continue;

            m_registry[i].Analyze(tick);
        }
    }

    //=================================================================
    //  CONFIG & PARAMS
    //=================================================================

    //+------------------------------------------------------------------+
    //| ApplyConfig_V6: Apply full SConfigData (from CONFIG_PUSH)        |
    //| Wrapper around EnableByConfig for naming consistency with P0-3   |
    //+------------------------------------------------------------------+
    void ApplyConfig_V6(const SConfigData &config)
    {
        EnableByConfig(config);
    }

    //+------------------------------------------------------------------+
    //| DistributeDynamicParams: Send parameter bundle to one strategy    |
    //| Called by ConfigReceiver after parsing CONFIG_PUSH V2            |
    //+------------------------------------------------------------------+
    void DistributeDynamicParams(SDynamicParams &params, ENUM_STRATEGY_ID target_id)
    {
        int idx = (int)target_id;
        if(idx < 0 || idx >= TOTAL_STRATEGIES || m_registry[idx] == NULL)
            return;
        m_registry[idx].SetDynamicParams(params);
    }

    //+------------------------------------------------------------------+
    //| DistributeAllDynamicParams: Broadcast params to all strategies    |
    //| Each strategy extracts only keys relevant to it                  |
    //+------------------------------------------------------------------+
    void DistributeAllDynamicParams(SDynamicParams &params)
    {
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(m_registry[i] != NULL)
                m_registry[i].SetDynamicParams(params);
    }

    //=================================================================
    //  STATUS & REPORTING
    //=================================================================

    //+------------------------------------------------------------------+
    //| GetStrategyStatus: Print formatted status table for all 16       |
    //| Logs to MT5 Expert tab — shows enabled/disabled, signal, conf   |
    //+------------------------------------------------------------------+
    void GetStrategyStatus()
    {
        Print("╔══════════════════════════════════════════════════════════════════╗");
        Print("║          FlashEASuite V2 — Strategy Status Report               ║");
        Print("╠══════════════════════════════════════════════════════════════════╣");

        int enabled_count  = 0;
        int disabled_count = 0;

        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL)
            {
                PrintFormat("║ S%02d | NULL ║", i + 1);
                continue;
            }

            bool    en   = m_registry[i].IsEnabled();
            bool    sa   = m_registry[i].IsStandaloneCapable();
            string  sig  = SignalToString(m_registry[i].GetSignal());
            double  conf = m_registry[i].GetConfidence();

            if(en) enabled_count++; else disabled_count++;

            PrintFormat("║ %s | %-28s | %-8s | %s | Conf:%.2f | %s ║",
                m_registry[i].GetShortName(),
                m_registry[i].GetName(),
                en ? "ENABLED" : "DISABLED",
                sa ? "SA" : "  ",
                conf,
                sig);
        }

        Print("╠══════════════════════════════════════════════════════════════════╣");
        PrintFormat("║  Enabled: %-2d  |  Disabled: %-2d  |  Server: %-3s  |  Symbol: %-12s ║",
            enabled_count, disabled_count,
            m_server_connected ? "ON " : "OFF",
            m_symbol);
        Print("╚══════════════════════════════════════════════════════════════════╝");
    }

    //+------------------------------------------------------------------+
    //| FillStatusArray: Export status to array for automated testing    |
    //+------------------------------------------------------------------+
    void FillStatusArray(SStrategyStatusEntry &out[], int &count)
    {
        count = 0;
        ArrayResize(out, TOTAL_STRATEGIES);

        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_registry[i] == NULL) continue;

            out[count].short_name        = m_registry[i].GetShortName();
            out[count].name              = m_registry[i].GetName();
            out[count].enabled           = m_registry[i].IsEnabled();
            out[count].initialized       = m_registry[i].IsInitialized();
            out[count].standalone_capable= m_registry[i].IsStandaloneCapable();
            out[count].last_signal       = m_registry[i].GetSignal();
            out[count].last_confidence   = m_registry[i].GetConfidence();
            count++;
        }
    }

    //=================================================================
    //  GETTERS
    //=================================================================

    //+------------------------------------------------------------------+
    //| GetEnabledCount_V6: Count currently enabled strategies           |
    //+------------------------------------------------------------------+
    int GetEnabledCount_V6()
    {
        int n = 0;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(m_registry[i] != NULL && m_registry[i].IsEnabled()) n++;
        return n;
    }

    //+------------------------------------------------------------------+
    //| GetStrategyByID: Get pointer to strategy (for advanced use)      |
    //| Returns NULL if id out of range                                  |
    //+------------------------------------------------------------------+
    IStrategy* GetStrategyByID(ENUM_STRATEGY_ID id)
    {
        int idx = (int)id;
        if(idx < 0 || idx >= TOTAL_STRATEGIES) return NULL;
        return m_registry[idx];
    }

    //+------------------------------------------------------------------+
    //| IsRegistered: Returns true if RegisterAllStrategies() succeeded  |
    //+------------------------------------------------------------------+
    bool IsRegistered() { return m_registered; }

    //+------------------------------------------------------------------+
    //| IsServerConnected: Current server connection state               |
    //+------------------------------------------------------------------+
    bool IsServerConnected() { return m_server_connected; }

    //=================================================================
    //  CLEANUP
    //=================================================================

    //+------------------------------------------------------------------+
    //| Deinit: Release all strategy resources (call in OnDeinit)        |
    //+------------------------------------------------------------------+
    void Deinit()
    {
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(m_registry[i] != NULL) m_registry[i].Deinit();
        m_registered = false;
        Print("[StrategyManager] Deinit complete — all 16 strategies released");
    }

    //=================================================================
    //  LEGACY COMPAT — Preserved from P0-3 interface
    //=================================================================
    //| RegisterStrategy_V6: Legacy method — kept for backward compat    |
    //| In V2-4 we use RegisterAllStrategies() instead                  |
    //+------------------------------------------------------------------+
    void RegisterStrategy_V6(ENUM_STRATEGY_ID id, IStrategy* ext_ptr)
    {
        // No-op in P2-4 — strategies are owned internally
        // Kept to avoid breaking any code that calls this from P0-3
        // Parameters intentionally unused — no-op stub for backward compat
    }
};

//+------------------------------------------------------------------+
//| GLOBAL INSTANCE (optional — FlashEA_V6.mq5 can declare its own)  |
//+------------------------------------------------------------------+
// CStrategyManager_V6 g_strategy_manager;  // uncomment if needed globally

#endif // STRATEGYMANAGER_V6_MQH
//+------------------------------------------------------------------+
