//+------------------------------------------------------------------+
//| StrategyConstants.mqh                                            |
//| FlashEASuite V2 V6 — Strategy Definitions & Constants            |
//| All 16 strategies: IDs, Magic Numbers, Categories, Regimes       |
//+------------------------------------------------------------------+
//| NOTE: This file is part of the V6 "Smart Server, Powerful Client"|
//| architecture. Strategy logic lives in MQL5 (13 Full + 3 Hybrid). |
//| Server selects which strategies to activate via CONFIG_PUSH.     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef STRATEGY_CONSTANTS_MQH
#define STRATEGY_CONSTANTS_MQH

#include "../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| Strategy Count                                                    |
//+------------------------------------------------------------------+
#define TOTAL_STRATEGIES      16
#define STANDALONE_STRATEGIES 7

//+------------------------------------------------------------------+
//| ENUM: Strategy IDs (0-15, maps to array index)                   |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_ID
{
    S01_STAT_ARB        = 0,   // Statistical Arbitrage (Pairs Trading)
    S02_ML_ENSEMBLE     = 1,   // ML Ensemble (RF+LSTM+XGB+KM+HMM)
    S03_SMC             = 2,   // Smart Money Concepts (OB/FVG/BOS)
    S04_MARKET_PROFILE  = 3,   // Market Profile + Order Flow
    S05_SUPPLY_DEMAND   = 4,   // Supply & Demand Zones
    S06_KAMA            = 5,   // Adaptive Trend Following (KAMA)
    S07_MEAN_REVERSION  = 6,   // Mean Reversion (Vol-Filtered)
    S08_INTERMARKET     = 7,   // Intermarket Correlation (DXY)
    S09_SESSION_BREAKOUT= 8,   // London/NY Session Breakout
    S10_TURTLE          = 9,   // Turtle Trading (Modernized)
    S11_ICHIMOKU        = 10,  // Multi-TF Ichimoku
    S12_PRICE_ACTION    = 11,  // Price Action (Pin Bar + Engulfing)
    S13_FIB_STOCH       = 12,  // Fibonacci + Stochastic Reversal
    S14_BB_SQUEEZE      = 13,  // Bollinger Squeeze Breakout
    S15_GRID            = 14,  // Immortal Grid (Legacy, proven)
    S16_SPIKE           = 15   // Spike Hunter (Legacy, proven)
};

// NOTE: ENUM_MARKET_REGIME is defined in Definitions.mqh
// Do not redefine here to avoid duplicate enum errors
// Import from: #include "../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| ENUM: Strategy Category                                          |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_CATEGORY
{
    CAT_FULL_MQL5       = 0,   // All logic in MQL5, no Python dependency
    CAT_HYBRID          = 1    // MQL5 execution + Python analysis (co-integration/ML/DXY)
};

//+------------------------------------------------------------------+
//| ENUM: Trade Signal                                               |
//+------------------------------------------------------------------+
enum ENUM_TRADE_SIGNAL
{
    SIGNAL_NONE         = 0,   // No signal / hold
    SIGNAL_BUY          = 1,   // Buy signal
    SIGNAL_SELL         = -1   // Sell signal
};

//+------------------------------------------------------------------+
//| STRUCT: Strategy Info (static metadata per strategy)             |
//+------------------------------------------------------------------+
struct SStrategyInfo
{
    ENUM_STRATEGY_ID    id;             // Strategy enum ID
    string              name;           // Display name
    string              short_name;     // Short ID string (e.g., "S01")
    int                 magic;          // Magic number for order identification
    ENUM_STRATEGY_CATEGORY category;    // Full_MQL5 or Hybrid
    bool                standalone;     // Can run without server?
    ENUM_MARKET_REGIME  best_regime;    // Primary regime preference
    ENUM_MARKET_REGIME  alt_regime;     // Secondary regime (REGIME_UNKNOWN = none)
    string              family;         // Strategy family for grouping
};

//+------------------------------------------------------------------+
//| Magic Number Range: 1001-1016 (reserved for strategies)          |
//| 999000 = StrategyManager (legacy)                                |
//| 1017+ = reserved for future strategies                           |
//+------------------------------------------------------------------+
#define MAGIC_BASE            1001
#define MAGIC_S01_STAT_ARB    1001
#define MAGIC_S02_ML_ENSEMBLE 1002
#define MAGIC_S03_SMC         1003
#define MAGIC_S04_MARKET_PROF 1004
#define MAGIC_S05_SUPPLY_DEM  1005
#define MAGIC_S06_KAMA        1006
#define MAGIC_S07_MEAN_REV    1007
#define MAGIC_S08_INTERMARKET 1008
#define MAGIC_S09_SESSION_BO  1009
#define MAGIC_S10_TURTLE      1010
#define MAGIC_S11_ICHIMOKU    1011
#define MAGIC_S12_PRICE_ACT   1012
#define MAGIC_S13_FIB_STOCH   1013
#define MAGIC_S14_BB_SQUEEZE  1014
#define MAGIC_S15_GRID        1015
#define MAGIC_S16_SPIKE       1016

//+------------------------------------------------------------------+
//| GLOBAL: Strategy Info Table (all 16 strategies)                  |
//+------------------------------------------------------------------+
//| Usage: SStrategyInfo info = GetStrategyInfo(S06_KAMA);           |
//+------------------------------------------------------------------+

// Forward declaration — initialized by InitStrategyTable()
SStrategyInfo g_strategy_table[TOTAL_STRATEGIES];
bool          g_strategy_table_initialized = false;

//+------------------------------------------------------------------+
//| Initialize the strategy info table (call once in OnInit)         |
//+------------------------------------------------------------------+
void InitStrategyTable()
{
    if(g_strategy_table_initialized) return;
    
    //--- S01: Statistical Arbitrage
    g_strategy_table[S01_STAT_ARB].id          = S01_STAT_ARB;
    g_strategy_table[S01_STAT_ARB].name        = "Statistical Arbitrage";
    g_strategy_table[S01_STAT_ARB].short_name  = "S01";
    g_strategy_table[S01_STAT_ARB].magic       = MAGIC_S01_STAT_ARB;
    g_strategy_table[S01_STAT_ARB].category    = CAT_HYBRID;
    g_strategy_table[S01_STAT_ARB].standalone  = true;
    g_strategy_table[S01_STAT_ARB].best_regime = REGIME_RANGING;
    g_strategy_table[S01_STAT_ARB].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S01_STAT_ARB].family      = "Pairs/Neutral";

    //--- S02: ML Ensemble
    g_strategy_table[S02_ML_ENSEMBLE].id          = S02_ML_ENSEMBLE;
    g_strategy_table[S02_ML_ENSEMBLE].name        = "ML Ensemble";
    g_strategy_table[S02_ML_ENSEMBLE].short_name  = "S02";
    g_strategy_table[S02_ML_ENSEMBLE].magic       = MAGIC_S02_ML_ENSEMBLE;
    g_strategy_table[S02_ML_ENSEMBLE].category    = CAT_HYBRID;
    g_strategy_table[S02_ML_ENSEMBLE].standalone  = false;
    g_strategy_table[S02_ML_ENSEMBLE].best_regime = REGIME_UNKNOWN;  // adapts to all regimes
    g_strategy_table[S02_ML_ENSEMBLE].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S02_ML_ENSEMBLE].family      = "AI/ML Predictive";

    //--- S03: Smart Money Concepts
    g_strategy_table[S03_SMC].id          = S03_SMC;
    g_strategy_table[S03_SMC].name        = "Smart Money Concepts";
    g_strategy_table[S03_SMC].short_name  = "S03";
    g_strategy_table[S03_SMC].magic       = MAGIC_S03_SMC;
    g_strategy_table[S03_SMC].category    = CAT_FULL_MQL5;
    g_strategy_table[S03_SMC].standalone  = false;
    g_strategy_table[S03_SMC].best_regime = REGIME_TRENDING;
    g_strategy_table[S03_SMC].alt_regime  = REGIME_VOLATILE;
    g_strategy_table[S03_SMC].family      = "Price Action";

    //--- S04: Market Profile + Order Flow
    g_strategy_table[S04_MARKET_PROFILE].id          = S04_MARKET_PROFILE;
    g_strategy_table[S04_MARKET_PROFILE].name        = "Market Profile";
    g_strategy_table[S04_MARKET_PROFILE].short_name  = "S04";
    g_strategy_table[S04_MARKET_PROFILE].magic       = MAGIC_S04_MARKET_PROF;
    g_strategy_table[S04_MARKET_PROFILE].category    = CAT_FULL_MQL5;
    g_strategy_table[S04_MARKET_PROFILE].standalone  = false;
    g_strategy_table[S04_MARKET_PROFILE].best_regime = REGIME_RANGING;
    g_strategy_table[S04_MARKET_PROFILE].alt_regime  = REGIME_TRENDING;
    g_strategy_table[S04_MARKET_PROFILE].family      = "Volume-based";

    //--- S05: Supply & Demand
    g_strategy_table[S05_SUPPLY_DEMAND].id          = S05_SUPPLY_DEMAND;
    g_strategy_table[S05_SUPPLY_DEMAND].name        = "Supply & Demand";
    g_strategy_table[S05_SUPPLY_DEMAND].short_name  = "S05";
    g_strategy_table[S05_SUPPLY_DEMAND].magic       = MAGIC_S05_SUPPLY_DEM;
    g_strategy_table[S05_SUPPLY_DEMAND].category    = CAT_FULL_MQL5;
    g_strategy_table[S05_SUPPLY_DEMAND].standalone  = false;
    g_strategy_table[S05_SUPPLY_DEMAND].best_regime = REGIME_RANGING;
    g_strategy_table[S05_SUPPLY_DEMAND].alt_regime  = REGIME_TRENDING;
    g_strategy_table[S05_SUPPLY_DEMAND].family      = "Zone-based";

    //--- S06: Adaptive Trend Following (KAMA)
    g_strategy_table[S06_KAMA].id          = S06_KAMA;
    g_strategy_table[S06_KAMA].name        = "Adaptive Trend (KAMA)";
    g_strategy_table[S06_KAMA].short_name  = "S06";
    g_strategy_table[S06_KAMA].magic       = MAGIC_S06_KAMA;
    g_strategy_table[S06_KAMA].category    = CAT_FULL_MQL5;
    g_strategy_table[S06_KAMA].standalone  = true;
    g_strategy_table[S06_KAMA].best_regime = REGIME_TRENDING;
    g_strategy_table[S06_KAMA].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S06_KAMA].family      = "Trend Following";

    //--- S07: Mean Reversion (Vol-Filtered)
    g_strategy_table[S07_MEAN_REVERSION].id          = S07_MEAN_REVERSION;
    g_strategy_table[S07_MEAN_REVERSION].name        = "Mean Reversion";
    g_strategy_table[S07_MEAN_REVERSION].short_name  = "S07";
    g_strategy_table[S07_MEAN_REVERSION].magic       = MAGIC_S07_MEAN_REV;
    g_strategy_table[S07_MEAN_REVERSION].category    = CAT_FULL_MQL5;
    g_strategy_table[S07_MEAN_REVERSION].standalone  = true;
    g_strategy_table[S07_MEAN_REVERSION].best_regime = REGIME_RANGING;
    g_strategy_table[S07_MEAN_REVERSION].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S07_MEAN_REVERSION].family      = "Contrarian";

    //--- S08: Intermarket Correlation
    g_strategy_table[S08_INTERMARKET].id          = S08_INTERMARKET;
    g_strategy_table[S08_INTERMARKET].name        = "Intermarket Correlation";
    g_strategy_table[S08_INTERMARKET].short_name  = "S08";
    g_strategy_table[S08_INTERMARKET].magic       = MAGIC_S08_INTERMARKET;
    g_strategy_table[S08_INTERMARKET].category    = CAT_HYBRID;
    g_strategy_table[S08_INTERMARKET].standalone  = false;
    g_strategy_table[S08_INTERMARKET].best_regime = REGIME_TRENDING;
    g_strategy_table[S08_INTERMARKET].alt_regime  = REGIME_VOLATILE;
    g_strategy_table[S08_INTERMARKET].family      = "Multi-Asset";

    //--- S09: London/NY Session Breakout
    g_strategy_table[S09_SESSION_BREAKOUT].id          = S09_SESSION_BREAKOUT;
    g_strategy_table[S09_SESSION_BREAKOUT].name        = "Session Breakout";
    g_strategy_table[S09_SESSION_BREAKOUT].short_name  = "S09";
    g_strategy_table[S09_SESSION_BREAKOUT].magic       = MAGIC_S09_SESSION_BO;
    g_strategy_table[S09_SESSION_BREAKOUT].category    = CAT_FULL_MQL5;
    g_strategy_table[S09_SESSION_BREAKOUT].standalone  = false;
    g_strategy_table[S09_SESSION_BREAKOUT].best_regime = REGIME_VOLATILE;
    g_strategy_table[S09_SESSION_BREAKOUT].alt_regime  = REGIME_TRENDING;
    g_strategy_table[S09_SESSION_BREAKOUT].family      = "Time-based";

    //--- S10: Turtle Trading (Modernized)
    g_strategy_table[S10_TURTLE].id          = S10_TURTLE;
    g_strategy_table[S10_TURTLE].name        = "Turtle Trading";
    g_strategy_table[S10_TURTLE].short_name  = "S10";
    g_strategy_table[S10_TURTLE].magic       = MAGIC_S10_TURTLE;
    g_strategy_table[S10_TURTLE].category    = CAT_FULL_MQL5;
    g_strategy_table[S10_TURTLE].standalone  = true;
    g_strategy_table[S10_TURTLE].best_regime = REGIME_TRENDING;
    g_strategy_table[S10_TURTLE].alt_regime  = REGIME_SQUEEZE;
    g_strategy_table[S10_TURTLE].family      = "Breakout";

    //--- S11: Multi-TF Ichimoku
    g_strategy_table[S11_ICHIMOKU].id          = S11_ICHIMOKU;
    g_strategy_table[S11_ICHIMOKU].name        = "Multi-TF Ichimoku";
    g_strategy_table[S11_ICHIMOKU].short_name  = "S11";
    g_strategy_table[S11_ICHIMOKU].magic       = MAGIC_S11_ICHIMOKU;
    g_strategy_table[S11_ICHIMOKU].category    = CAT_FULL_MQL5;
    g_strategy_table[S11_ICHIMOKU].standalone  = false;
    g_strategy_table[S11_ICHIMOKU].best_regime = REGIME_TRENDING;
    g_strategy_table[S11_ICHIMOKU].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S11_ICHIMOKU].family      = "Systematic Trend";

    //--- S12: Price Action (Pin Bar + Engulfing)
    g_strategy_table[S12_PRICE_ACTION].id          = S12_PRICE_ACTION;
    g_strategy_table[S12_PRICE_ACTION].name        = "Price Action";
    g_strategy_table[S12_PRICE_ACTION].short_name  = "S12";
    g_strategy_table[S12_PRICE_ACTION].magic       = MAGIC_S12_PRICE_ACT;
    g_strategy_table[S12_PRICE_ACTION].category    = CAT_FULL_MQL5;
    g_strategy_table[S12_PRICE_ACTION].standalone  = false;
    g_strategy_table[S12_PRICE_ACTION].best_regime = REGIME_TRENDING;
    g_strategy_table[S12_PRICE_ACTION].alt_regime  = REGIME_RANGING;
    g_strategy_table[S12_PRICE_ACTION].family      = "Candlestick";

    //--- S13: Fibonacci + Stochastic
    g_strategy_table[S13_FIB_STOCH].id          = S13_FIB_STOCH;
    g_strategy_table[S13_FIB_STOCH].name        = "Fibonacci + Stochastic";
    g_strategy_table[S13_FIB_STOCH].short_name  = "S13";
    g_strategy_table[S13_FIB_STOCH].magic       = MAGIC_S13_FIB_STOCH;
    g_strategy_table[S13_FIB_STOCH].category    = CAT_FULL_MQL5;
    g_strategy_table[S13_FIB_STOCH].standalone  = false;
    g_strategy_table[S13_FIB_STOCH].best_regime = REGIME_RANGING;
    g_strategy_table[S13_FIB_STOCH].alt_regime  = REGIME_TRENDING;
    g_strategy_table[S13_FIB_STOCH].family      = "Reversal";

    //--- S14: Bollinger Squeeze Breakout
    g_strategy_table[S14_BB_SQUEEZE].id          = S14_BB_SQUEEZE;
    g_strategy_table[S14_BB_SQUEEZE].name        = "BB Squeeze Breakout";
    g_strategy_table[S14_BB_SQUEEZE].short_name  = "S14";
    g_strategy_table[S14_BB_SQUEEZE].magic       = MAGIC_S14_BB_SQUEEZE;
    g_strategy_table[S14_BB_SQUEEZE].category    = CAT_FULL_MQL5;
    g_strategy_table[S14_BB_SQUEEZE].standalone  = true;
    g_strategy_table[S14_BB_SQUEEZE].best_regime = REGIME_SQUEEZE;
    g_strategy_table[S14_BB_SQUEEZE].alt_regime  = REGIME_VOLATILE;
    g_strategy_table[S14_BB_SQUEEZE].family      = "Volatility";

    //--- S15: Immortal Grid (Legacy)
    g_strategy_table[S15_GRID].id          = S15_GRID;
    g_strategy_table[S15_GRID].name        = "Immortal Grid";
    g_strategy_table[S15_GRID].short_name  = "S15";
    g_strategy_table[S15_GRID].magic       = MAGIC_S15_GRID;
    g_strategy_table[S15_GRID].category    = CAT_FULL_MQL5;
    g_strategy_table[S15_GRID].standalone  = true;
    g_strategy_table[S15_GRID].best_regime = REGIME_RANGING;
    g_strategy_table[S15_GRID].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S15_GRID].family      = "Range Grid";

    //--- S16: Spike Hunter (Legacy)
    g_strategy_table[S16_SPIKE].id          = S16_SPIKE;
    g_strategy_table[S16_SPIKE].name        = "Spike Hunter";
    g_strategy_table[S16_SPIKE].short_name  = "S16";
    g_strategy_table[S16_SPIKE].magic       = MAGIC_S16_SPIKE;
    g_strategy_table[S16_SPIKE].category    = CAT_FULL_MQL5;
    g_strategy_table[S16_SPIKE].standalone  = true;
    g_strategy_table[S16_SPIKE].best_regime = REGIME_VOLATILE;
    g_strategy_table[S16_SPIKE].alt_regime  = REGIME_UNKNOWN;
    g_strategy_table[S16_SPIKE].family      = "Momentum";

    g_strategy_table_initialized = true;
}

//+------------------------------------------------------------------+
//| Helper: Get strategy info by ID                                  |
//+------------------------------------------------------------------+
SStrategyInfo GetStrategyInfo(ENUM_STRATEGY_ID id)
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    return g_strategy_table[(int)id];
}

//+------------------------------------------------------------------+
//| Helper: Get magic number by strategy ID                          |
//+------------------------------------------------------------------+
int GetMagicNumber(ENUM_STRATEGY_ID id)
{
    return MAGIC_BASE + (int)id;
}

//+------------------------------------------------------------------+
//| Helper: Get strategy ID from magic number                        |
//+------------------------------------------------------------------+
ENUM_STRATEGY_ID GetStrategyFromMagic(int magic)
{
    int idx = magic - MAGIC_BASE;
    if(idx >= 0 && idx < TOTAL_STRATEGIES)
        return (ENUM_STRATEGY_ID)idx;
    return S01_STAT_ARB;  // fallback
}

//+------------------------------------------------------------------+
//| Helper: Check if strategy is standalone capable                  |
//+------------------------------------------------------------------+
bool IsStandaloneStrategy(ENUM_STRATEGY_ID id)
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    return g_strategy_table[(int)id].standalone;
}

//+------------------------------------------------------------------+
//| Helper: Check if strategy is hybrid (needs Python)               |
//+------------------------------------------------------------------+
bool IsHybridStrategy(ENUM_STRATEGY_ID id)
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    return (g_strategy_table[(int)id].category == CAT_HYBRID);
}

//+------------------------------------------------------------------+
//| Helper: Get regime alignment factor for AI Council voting        |
//| Returns: 0.3 (terrible) to 1.5 (perfect match)                  |
//| Based on V6 Roadmap Section 5: Regime Factor Scale               |
//+------------------------------------------------------------------+
double GetRegimeAlignmentFactor(ENUM_STRATEGY_ID id, ENUM_MARKET_REGIME current_regime)
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    
    ENUM_MARKET_REGIME best = g_strategy_table[(int)id].best_regime;
    ENUM_MARKET_REGIME alt  = g_strategy_table[(int)id].alt_regime;
    
    // S02 ML Ensemble adapts to all regimes → always neutral
    if(best == REGIME_UNKNOWN) return 1.0;
    
    // Perfect match with primary regime
    if(current_regime == best) return 1.5;
    
    // Good match with secondary regime
    if(alt != REGIME_UNKNOWN && current_regime == alt) return 1.2;
    
    // Neutral: no specific conflict
    // Terrible: known bad combinations
    // Grid in TRENDING, Spike in SQUEEZE, Trend in RANGING
    if(id == S15_GRID && current_regime == REGIME_TRENDING)       return 0.5;
    if(id == S16_SPIKE && current_regime == REGIME_SQUEEZE)       return 0.3;
    if(id == S06_KAMA && current_regime == REGIME_RANGING)        return 0.5;
    if(id == S10_TURTLE && current_regime == REGIME_RANGING)      return 0.5;
    if(id == S07_MEAN_REVERSION && current_regime == REGIME_VOLATILE) return 0.5;
    if(id == S11_ICHIMOKU && current_regime == REGIME_RANGING)    return 0.5;
    
    // Default: neutral
    return 1.0;
}

//+------------------------------------------------------------------+
//| Helper: Get standalone strategies for a given regime             |
//| Used by CStandaloneSelector (V6 Roadmap Section 4)               |
//+------------------------------------------------------------------+
//| TRENDING  → KAMA + Turtle + BBSqueeze                           |
//| RANGING   → Grid + StatArb + MeanRev                            |
//| VOLATILE  → Spike + BBSqueeze                                   |
//| SQUEEZE   → BBSqueeze + Turtle (prepare for breakout)           |
//+------------------------------------------------------------------+
int GetStandaloneStrategiesForRegime(ENUM_MARKET_REGIME regime, 
                                     ENUM_STRATEGY_ID &out_ids[])
{
    ArrayResize(out_ids, 0);
    int count = 0;
    
    switch(regime)
    {
        case REGIME_TRENDING:
            ArrayResize(out_ids, 3);
            out_ids[0] = S06_KAMA;
            out_ids[1] = S10_TURTLE;
            out_ids[2] = S14_BB_SQUEEZE;
            count = 3;
            break;
            
        case REGIME_RANGING:
            ArrayResize(out_ids, 3);
            out_ids[0] = S15_GRID;
            out_ids[1] = S01_STAT_ARB;
            out_ids[2] = S07_MEAN_REVERSION;
            count = 3;
            break;
            
        case REGIME_VOLATILE:
            ArrayResize(out_ids, 2);
            out_ids[0] = S16_SPIKE;
            out_ids[1] = S14_BB_SQUEEZE;
            count = 2;
            break;
            
        case REGIME_SQUEEZE:
            ArrayResize(out_ids, 2);
            out_ids[0] = S14_BB_SQUEEZE;
            out_ids[1] = S10_TURTLE;
            count = 2;
            break;
            
        default:  // UNKNOWN → use conservative set
            ArrayResize(out_ids, 2);
            out_ids[0] = S15_GRID;
            out_ids[1] = S07_MEAN_REVERSION;
            count = 2;
            break;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Helper: Convert enum to string (for logging)                     |
//+------------------------------------------------------------------+
string StrategyIDToString(ENUM_STRATEGY_ID id)
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    return g_strategy_table[(int)id].short_name + "_" + g_strategy_table[(int)id].name;
}

// NOTE: RegimeToString is defined in Definitions.mqh
// Do not redefine here to avoid duplicate function errors
// Use the one from: #include "../Network/Protocol/Definitions.mqh"

string CategoryToString(ENUM_STRATEGY_CATEGORY cat)
{
    switch(cat)
    {
        case CAT_FULL_MQL5: return "Full_MQL5";
        case CAT_HYBRID:    return "Hybrid";
        default:            return "Unknown";
    }
}

string SignalToString(ENUM_TRADE_SIGNAL sig)
{
    switch(sig)
    {
        case SIGNAL_BUY:  return "BUY";
        case SIGNAL_SELL: return "SELL";
        default:          return "NONE";
    }
}

//+------------------------------------------------------------------+
//| Helper: Print all strategy info (for debugging)                  |
//+------------------------------------------------------------------+
void PrintStrategyTable()
{
    if(!g_strategy_table_initialized) InitStrategyTable();
    
    Print("╔══════════════════════════════════════════════════════════════╗");
    Print("║          FLASHEASUITE V6 — 16 STRATEGY ARSENAL             ║");
    Print("╠══════════════════════════════════════════════════════════════╣");
    
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        SStrategyInfo info = g_strategy_table[i];
        string standalone_flag = info.standalone ? "SA" : "--";
        string cat_flag = (info.category == CAT_HYBRID) ? "HYB" : "MQL";
        
        PrintFormat("║ %s | Magic:%d | %s | %s | %s | Best:%s",
            info.short_name,
            info.magic,
            info.name,
            cat_flag,
            standalone_flag,
            RegimeToString(info.best_regime));
    }
    
    Print("╠══════════════════════════════════════════════════════════════╣");
    PrintFormat("║ Total: %d strategies | %d standalone | 3 hybrid          ║",
        TOTAL_STRATEGIES, STANDALONE_STRATEGIES);
    Print("╚══════════════════════════════════════════════════════════════╝");
}


//+------------------------------------------------------------------+
//| STRUCT: Default parameters per strategy                          |
//| Used when no CONFIG_PUSH received (standalone mode fallback)     |
//+------------------------------------------------------------------+
struct SStrategyDefaults
{
    string  param_names[20];
    double  param_values[20];
    int     param_count;
};

//+------------------------------------------------------------------+
//| GetStrategyDefaults: Return hardcoded default params per strategy |
//| Called by strategies in constructor to seed member variables     |
//+------------------------------------------------------------------+
SStrategyDefaults GetStrategyDefaults(ENUM_STRATEGY_ID id)
{
    SStrategyDefaults d;
    d.param_count = 0;
    
    switch(id)
    {
        case S15_GRID:
            d.param_names[0]  = "S15_MAX_ORDERS";     d.param_values[0]  = 10;
            d.param_names[1]  = "S15_BASE_STEP";      d.param_values[1]  = 200;
            d.param_names[2]  = "S15_ELASTIC_FACTOR"; d.param_values[2]  = 1.5;
            d.param_names[3]  = "S15_CONF_THRESHOLD"; d.param_values[3]  = 0.65;
            d.param_names[4]  = "S15_ATR_RATIO";      d.param_values[4]  = 0.8;
            d.param_names[5]  = "S15_SWAP_FILTER";    d.param_values[5]  = 1.0;  // 1=enabled
            d.param_count = 6;
            break;
            
        case S16_SPIKE:
            d.param_names[0]  = "S16_VELOCITY_THRESH";  d.param_values[0]  = 2.5;
            d.param_names[1]  = "S16_SPREAD_THRESH";    d.param_values[1]  = 1.5;
            d.param_names[2]  = "S16_VOLUME_THRESH";    d.param_values[2]  = 2.0;
            d.param_names[3]  = "S16_MOMENTUM_THRESH";  d.param_values[3]  = 0.5;
            d.param_names[4]  = "S16_VOLATILITY_THRESH";d.param_values[4]  = 1.5;
            d.param_names[5]  = "S16_DIRECTION_CONSIST";d.param_values[5]  = 0.7;
            d.param_names[6]  = "S16_PATTERN_SCORE_MIN";d.param_values[6]  = 70.0;
            d.param_names[7]  = "S16_ATR_SPIKE_MULT";   d.param_values[7]  = 2.0;
            d.param_names[8]  = "S16_ATR_TP_MULT";      d.param_values[8]  = 0.8;
            d.param_names[9]  = "S16_ATR_SL_MULT";      d.param_values[9]  = 0.4;
            d.param_names[10] = "S16_MAX_HOLD_SEC";     d.param_values[10] = 900;
            d.param_count = 11;
            break;
            
        default:
            // Other strategies: empty defaults (will use hardcoded values)
            d.param_count = 0;
            break;
    }
    
    return d;
}

//+------------------------------------------------------------------+
//| GetDefaultMM: Return default MM method per strategy              |
//| Used when CONFIG_PUSH has not specified mm_method                |
//+------------------------------------------------------------------+
string GetDefaultMM(ENUM_STRATEGY_ID id)
{
    switch(id)
    {
        case S15_GRID:           return "MM04";  // Fixed Fractional
        case S16_SPIKE:          return "MM01";  // Fixed Lot
        case S06_KAMA:           return "MM04";
        case S07_MEAN_REVERSION: return "MM07";  // Volatility-based
        case S10_TURTLE:         return "MM04";
        case S14_BB_SQUEEZE:     return "MM04";
        case S01_STAT_ARB:       return "MM04";
        default:                 return "MM01";
    }
}

#endif // STRATEGY_CONSTANTS_MQH
//+------------------------------------------------------------------+
