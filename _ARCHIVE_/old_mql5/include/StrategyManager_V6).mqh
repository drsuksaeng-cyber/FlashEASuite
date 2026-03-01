//+------------------------------------------------------------------+
//| StrategyManager_V6.mqh                                           |
//| FlashEASuite V2 V6 — Strategy Registry & Lifecycle Manager       |
//| Manages registration, enabling/disabling, and execution of all   |
//| 16 strategies (13 Full MQL5 + 3 Hybrid)                          |
//+------------------------------------------------------------------+
//| NOTE: This is the V6 version with new interface                 |
//| Combines with existing StrategyManager (legacy) functionality    |
//| Merge strategy: Keep old methods, add V6 methods                |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef STRATEGY_MANAGER_V6_MQH
#define STRATEGY_MANAGER_V6_MQH

#include "IStrategy.mqh"
#include "StrategyConstants.mqh"
#include "StrategyBase.mqh"

//+------------------------------------------------------------------+
//| CLASS: CStrategyManager_V6                                       |
//| V6 Version: Manages 16 strategies with IStrategy interface       |
//+------------------------------------------------------------------+
class CStrategyManager_V6
{
private:
    //--- V6 Strategy registry (16 strategies with IStrategy interface)
    IStrategy          *m_strategies_v6[TOTAL_STRATEGIES];
    bool                m_strategy_enabled[TOTAL_STRATEGIES];
    int                 m_enabled_count;
    
    //--- Legacy compatibility (keep existing strategies)
    CStrategyBase      *m_strategies_legacy[];
    int                 m_total_strategies_legacy;
    
    //--- Tracking
    int                 m_total_ticks_processed;
    datetime            m_last_analyze_time;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CStrategyManager_V6() : 
        m_enabled_count(0), 
        m_total_ticks_processed(0), 
        m_last_analyze_time(0),
        m_total_strategies_legacy(0)
    {
        // Initialize all V6 strategy pointers to NULL
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            m_strategies_v6[i] = NULL;
            m_strategy_enabled[i] = false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CStrategyManager_V6()
    {
        // Clean up all V6 strategies
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_strategies_v6[i] != NULL)
            {
                m_strategies_v6[i].Deinit();
                delete m_strategies_v6[i];
                m_strategies_v6[i] = NULL;
            }
        }
        
        // Clean up legacy strategies
        for(int i = 0; i < ArraySize(m_strategies_legacy); i++)
        {
            if(CheckPointer(m_strategies_legacy[i]) == POINTER_DYNAMIC)
                delete m_strategies_legacy[i];
        }
        ArrayResize(m_strategies_legacy, 0);
    }
    
    //+------------------------------------------------------------------+
    //| Init: Initialize the strategy manager                            |
    //+------------------------------------------------------------------+
    void Init()
    {
        Print("[StrategyManager_V6] Initializing with ", TOTAL_STRATEGIES, " V6 strategies");
        
        // Initialize strategy table from StrategyConstants
        if(!g_strategy_table_initialized)
        {
            InitStrategyTable();
        }
        
        m_enabled_count = 0;
        m_total_ticks_processed = 0;
        m_last_analyze_time = 0;
        
        Print("[StrategyManager_V6] Ready to register strategies");
    }
    
    //=================================================================
    //  V6 INTERFACE — New methods for IStrategy-based strategies
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| RegisterStrategy_V6: Add a V6 strategy to the manager            |
    //| Called during OnInit() to register all 16 strategies            |
    //| @param strategy_id  Which strategy (S01-S16)                   |
    //| @param strategy     Pointer to IStrategy instance              |
    //| @return true if registered successfully                        |
    //+------------------------------------------------------------------+
    bool RegisterStrategy_V6(ENUM_STRATEGY_ID strategy_id, IStrategy *strategy)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            Print("[StrategyManager_V6] ERROR: Invalid strategy ID ", strategy_id);
            return false;
        }
        
        if(strategy == NULL)
        {
            Print("[StrategyManager_V6] ERROR: NULL strategy pointer for ID ", strategy_id);
            return false;
        }
        
        // If already registered, clean up old one
        if(m_strategies_v6[strategy_id] != NULL)
        {
            m_strategies_v6[strategy_id].Deinit();
            delete m_strategies_v6[strategy_id];
        }
        
        m_strategies_v6[strategy_id] = strategy;
        m_strategy_enabled[strategy_id] = false;  // Start disabled
        
        Print("[StrategyManager_V6] Registered: ", g_strategy_table[strategy_id].name, 
              " (ID: ", g_strategy_table[strategy_id].short_name, ")");
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| EnableStrategy_V6: Activate a V6 strategy                        |
    //| @param strategy_id  Which strategy to enable                    |
    //| @return true if enabled successfully                            |
    //+------------------------------------------------------------------+
    bool EnableStrategy_V6(ENUM_STRATEGY_ID strategy_id)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            Print("[StrategyManager_V6] ERROR: Invalid strategy ID ", strategy_id);
            return false;
        }
        
        if(m_strategies_v6[strategy_id] == NULL)
        {
            Print("[StrategyManager_V6] ERROR: Strategy not registered: ", strategy_id);
            return false;
        }
        
        if(m_strategy_enabled[strategy_id])
        {
            // Already enabled
            return true;
        }
        
        // Initialize strategy if not already done
        if(!m_strategies_v6[strategy_id].IsInitialized())
        {
            if(!m_strategies_v6[strategy_id].Init(_Symbol, _Period))
            {
                Print("[StrategyManager_V6] ERROR: Failed to initialize ", 
                      g_strategy_table[strategy_id].name);
                return false;
            }
        }
        
        m_strategy_enabled[strategy_id] = true;
        m_enabled_count++;
        
        Print("[StrategyManager_V6] ENABLED: ", g_strategy_table[strategy_id].name);
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| DisableStrategy_V6: Deactivate a V6 strategy                     |
    //| @param strategy_id  Which strategy to disable                   |
    //| @return true if disabled successfully                           |
    //+------------------------------------------------------------------+
    bool DisableStrategy_V6(ENUM_STRATEGY_ID strategy_id)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            Print("[StrategyManager_V6] ERROR: Invalid strategy ID ", strategy_id);
            return false;
        }
        
        if(m_strategies_v6[strategy_id] == NULL)
        {
            return true;  // Already not registered
        }
        
        if(!m_strategy_enabled[strategy_id])
        {
            return true;  // Already disabled
        }
        
        m_strategy_enabled[strategy_id] = false;
        m_enabled_count--;
        
        Print("[StrategyManager_V6] DISABLED: ", g_strategy_table[strategy_id].name);
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| OnTick_V6: Process tick for all enabled V6 strategies            |
    //| Called from FlashEA_V6.mq5 OnTick() or OnTimer()                |
    //| @param tick  Current tick data from MT5                         |
    //+------------------------------------------------------------------+
    void OnTick_V6(const MqlTick &tick)
    {
        if(m_enabled_count == 0)
        {
            return;  // No strategies enabled
        }
        
        m_total_ticks_processed++;
        m_last_analyze_time = TimeCurrent();
        
        // Call Analyze() on all enabled V6 strategies
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_strategy_enabled[i] && m_strategies_v6[i] != NULL)
            {
                m_strategies_v6[i].Analyze(tick);
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| ApplyConfig_V6: Apply CONFIG_PUSH to enable/disable strategies  |
    //| Called by FlashEA_V6.mq5 after receiving CONFIG_PUSH           |
    //| @param config  Parsed config data from ConfigReceiver          |
    //+------------------------------------------------------------------+
    void ApplyConfig_V6(const SConfigData &config)
    {
        Print("[StrategyManager_V6] Applying config with ", 
              CountEnabledInConfig(config), " strategies");
        
        // Apply each strategy's enabled state
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(config.strategy_enabled[i])
            {
                EnableStrategy_V6((ENUM_STRATEGY_ID)i);
            }
            else
            {
                DisableStrategy_V6((ENUM_STRATEGY_ID)i);
            }
        }
        
        Print("[StrategyManager_V6] Config applied - ", m_enabled_count, " strategies now active");
    }
    
    //+------------------------------------------------------------------+
    //| GetEnabledCount_V6: How many V6 strategies are currently active? |
    //| @return number of enabled strategies                            |
    //+------------------------------------------------------------------+
    int GetEnabledCount_V6()
    {
        return m_enabled_count;
    }
    
    //+------------------------------------------------------------------+
    //| GetStrategyByID_V6: Get V6 strategy instance by ID               |
    //| @param strategy_id  Which strategy (S01-S16)                   |
    //| @return pointer to IStrategy (NULL if not registered)          |
    //+------------------------------------------------------------------+
    IStrategy *GetStrategyByID_V6(ENUM_STRATEGY_ID strategy_id)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            return NULL;
        }
        return m_strategies_v6[strategy_id];
    }
    
    //+------------------------------------------------------------------+
    //| IsStrategyEnabled_V6: Check if specific V6 strategy is active    |
    //| @param strategy_id  Which strategy (S01-S16)                   |
    //| @return true if enabled                                         |
    //+------------------------------------------------------------------+
    bool IsStrategyEnabled_V6(ENUM_STRATEGY_ID strategy_id)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            return false;
        }
        return m_strategy_enabled[strategy_id];
    }
    
    //+------------------------------------------------------------------+
    //| IsStrategyRegistered_V6: Check if V6 strategy is registered      |
    //| @param strategy_id  Which strategy (S01-S16)                   |
    //| @return true if registered (even if disabled)                  |
    //+------------------------------------------------------------------+
    bool IsStrategyRegistered_V6(ENUM_STRATEGY_ID strategy_id)
    {
        if(strategy_id < 0 || strategy_id >= TOTAL_STRATEGIES)
        {
            return false;
        }
        return m_strategies_v6[strategy_id] != NULL;
    }
    
    //+------------------------------------------------------------------+
    //| DisableAll_V6: Disable all V6 strategies                         |
    //| Used when switching to Standalone mode or disconnect            |
    //+------------------------------------------------------------------+
    void DisableAll_V6()
    {
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(m_strategy_enabled[i])
            {
                DisableStrategy_V6((ENUM_STRATEGY_ID)i);
            }
        }
        Print("[StrategyManager_V6] All V6 strategies disabled");
    }
    
    //+------------------------------------------------------------------+
    //| EnableAllStandalone_V6: Enable 7 standalone V6 strategies        |
    //| Used when switching to Standalone mode (server disconnected)    |
    //+------------------------------------------------------------------+
    void EnableAllStandalone_V6()
    {
        Print("[StrategyManager_V6] Enabling standalone strategies...");
        
        // 7 Standalone strategies from Roadmap V6
        ENUM_STRATEGY_ID standalone_strategies[STANDALONE_STRATEGIES] =
        {
            S01_STAT_ARB,       // S01
            S06_KAMA,           // S06
            S07_MEAN_REVERSION, // S07
            S10_TURTLE,         // S10
            S14_BB_SQUEEZE,     // S14
            S15_GRID,           // S15
            S16_SPIKE           // S16
        };
        
        for(int i = 0; i < STANDALONE_STRATEGIES; i++)
        {
            if(IsStrategyRegistered_V6(standalone_strategies[i]))
            {
                EnableStrategy_V6(standalone_strategies[i]);
            }
        }
        
        Print("[StrategyManager_V6] Standalone mode: ", m_enabled_count, " strategies active");
    }
    
    //+------------------------------------------------------------------+
    //| GetStatus_V6: Get human-readable status string                   |
    //| @return status description                                      |
    //+------------------------------------------------------------------+
    string GetStatus_V6()
    {
        string status = "StrategyManager_V6: " + IntegerToString(m_enabled_count) + 
                        "/" + IntegerToString(TOTAL_STRATEGIES) + " strategies active";
        return status;
    }
    
    //+------------------------------------------------------------------+
    //| GetTotalTicksProcessed_V6: How many ticks analyzed?              |
    //| @return tick count                                              |
    //+------------------------------------------------------------------+
    int GetTotalTicksProcessed_V6()
    {
        return m_total_ticks_processed;
    }
    
    //+------------------------------------------------------------------+
    //| GetLastAnalyzeTime_V6: When was last OnTick_V6() called?         |
    //| @return Unix timestamp                                          |
    //+------------------------------------------------------------------+
    datetime GetLastAnalyzeTime_V6()
    {
        return m_last_analyze_time;
    }
    
    //=================================================================
    //  LEGACY INTERFACE — Keep existing methods for compatibility
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| AddStrategy_Legacy: Add legacy strategy (CStrategyBase)          |
    //| Keep for backward compatibility with existing code              |
    //+------------------------------------------------------------------+
    void AddStrategy_Legacy(CStrategyBase* strat)
    {
        m_total_strategies_legacy = ArraySize(m_strategies_legacy);
        ArrayResize(m_strategies_legacy, m_total_strategies_legacy + 1);
        m_strategies_legacy[m_total_strategies_legacy] = strat;
        Print("[StrategyManager_V6] Added legacy strategy (total: ", m_total_strategies_legacy + 1, ")");
    }
    
    //+------------------------------------------------------------------+
    //| OnTickLogic_Legacy: Process legacy strategies                    |
    //| Keep existing voting/council logic                              |
    //+------------------------------------------------------------------+
    void OnTickLogic_Legacy()
    {
        // This would be the original council voting logic
        // Placeholder for existing implementation
        // Call this from FlashEA_V6.mq5 if legacy strategies are active
        
        if(ArraySize(m_strategies_legacy) == 0) return;
        
        Print("[StrategyManager_V6] OnTickLogic_Legacy called (", 
              ArraySize(m_strategies_legacy), " legacy strategies)");
    }
    
    //+------------------------------------------------------------------+
    //| GetGridStrategy_Legacy: Get legacy Grid strategy                 |
    //| Keep for backward compatibility                                 |
    //+------------------------------------------------------------------+
    CStrategyBase* GetGridStrategy_Legacy()
    {
        for(int i = 0; i < ArraySize(m_strategies_legacy); i++)
        {
            if(m_strategies_legacy[i] != NULL)
            {
                if(m_strategies_legacy[i].GetName() == "ElasticGrid")
                {
                    return m_strategies_legacy[i];
                }
            }
        }
        return NULL;
    }
    
    //+------------------------------------------------------------------+
    //| HELPER: Count enabled strategies in config                       |
    //+------------------------------------------------------------------+
private:
    int CountEnabledInConfig(const SConfigData &config)
    {
        int count = 0;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            if(config.strategy_enabled[i]) count++;
        }
        return count;
    }
};

#endif // STRATEGY_MANAGER_V6_MQH
