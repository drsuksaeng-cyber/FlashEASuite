//+------------------------------------------------------------------+
//| IStrategy.mqh                                                    |
//| FlashEASuite V2 V6 — Strategy Interface (Abstract Base Class)    |
//| All 16 strategies must implement this interface.                 |
//+------------------------------------------------------------------+
//| V6 Architecture: "Smart Server, Powerful Client"                 |
//| - Strategy logic lives in MQL5 (client calculates signals)       |
//| - Server sends CONFIG_PUSH (which strategies to enable + params) |
//| - Each strategy: Analyze(tick) → GetSignal() → GetConfidence()   |
//+------------------------------------------------------------------+
//| Compatibility Note:                                              |
//| - S15 Grid and S16 Spike will adapt from legacy CStrategyBase    |
//|   to this interface in Phase P2-3                                |
//| - New strategies (S01-S14) implement this directly               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef ISTRATEGY_MQH
#define ISTRATEGY_MQH

#include "../Network/Protocol/Definitions.mqh"
#include "StrategyConstants.mqh"

//+------------------------------------------------------------------+
//| STRUCT: Single dynamic parameter                                |
//| Represents one key-value pair sent via CONFIG_PUSH V2           |
//+------------------------------------------------------------------+
struct SDynamicParam
{
    string  name;       // Parameter key  e.g. "S15_GRID_SPACING"
    double  value;      // Numeric value
    bool    is_set;     // true = received from server (not default)
    
    void Reset()
    {
        name   = "";
        value  = 0.0;
        is_set = false;
    }
};

//+------------------------------------------------------------------+
//| STRUCT: Dynamic parameter bundle for one strategy               |
//| Sent by Python Brain via CONFIG_PUSH V2                         |
//| Each strategy receives its own SDynamicParams bundle            |
//+------------------------------------------------------------------+
struct SDynamicParams
{
    SDynamicParam   strategy_params[20];    // Max 20 params per strategy
    int             strategy_param_count;   // How many are actually set
    
    SDynamicParam   mm_params[10];          // Max 10 params per MM method
    int             mm_param_count;
    
    string          mm_method;              // e.g. "MM04"
    double          risk_multiplier;        // Regime-based risk scaling
    
    void Reset()
    {
        strategy_param_count = 0;
        mm_param_count       = 0;
        mm_method            = "";
        risk_multiplier      = 1.0;
        for(int i = 0; i < 20; i++) strategy_params[i].Reset();
        for(int i = 0; i < 10; i++) mm_params[i].Reset();
    }
    
    //--- Get param value by name; return default_val if not found
    double GetParam(string name, double default_val)
    {
        for(int i = 0; i < strategy_param_count; i++)
        {
            if(strategy_params[i].name == name && strategy_params[i].is_set)
                return strategy_params[i].value;
        }
        return default_val;
    }
    
    //--- Check if a named param was received from server
    bool HasParam(string name)
    {
        for(int i = 0; i < strategy_param_count; i++)
        {
            if(strategy_params[i].name == name && strategy_params[i].is_set)
                return true;
        }
        return false;
    }
    
    //--- Add/overwrite a param (used by ConfigReceiver when parsing)
    void SetParam(string name, double value)
    {
        // Update existing
        for(int i = 0; i < strategy_param_count; i++)
        {
            if(strategy_params[i].name == name)
            {
                strategy_params[i].value  = value;
                strategy_params[i].is_set = true;
                return;
            }
        }
        // Add new
        if(strategy_param_count < 20)
        {
            strategy_params[strategy_param_count].name   = name;
            strategy_params[strategy_param_count].value  = value;
            strategy_params[strategy_param_count].is_set = true;
            strategy_param_count++;
        }
    }
};

//+------------------------------------------------------------------+
//| STRUCT: Parsed CONFIG_PUSH Data                                 |
//| Used by both ConfigReceiver and StrategyManager_V6              |
//+------------------------------------------------------------------+
struct SConfigData
{
    datetime            timestamp;          // Server timestamp
    ENUM_MARKET_REGIME  regime;             // Current market regime
    ENUM_TIMEFRAMES     recommended_tf;     // Recommended timeframe
    
    // Strategy activation array (16 strategies)
    bool                strategy_enabled[TOTAL_STRATEGIES];
    double              strategy_confidence[TOTAL_STRATEGIES];
    string              strategy_params[TOTAL_STRATEGIES];

    // Per-strategy symbol + timeframe (multi-TF multi-symbol support)
    string              strategy_symbol[TOTAL_STRATEGIES];
    ENUM_TIMEFRAMES     strategy_timeframe[TOTAL_STRATEGIES];
    
    // Money management
    string              mm_method;          // Selected MM method (e.g., "MM4")
    double              risk_multiplier;    // Risk adjustment (0.5x - 2.0x)
    
    // News/Calendar events
    bool                has_news_event;     // High-impact news coming?
    string              news_description;   // What event
    
    // Sequence/Security (Phase 2)
    int                 sequence_number;    // For replay attack prevention
    string              nonce;              // One-time use token
    
    void Reset()
    {
        timestamp = 0;
        regime = REGIME_UNKNOWN;
        recommended_tf = PERIOD_M15;
        mm_method = "MM1";
        risk_multiplier = 1.0;
        has_news_event = false;
        news_description = "";
        sequence_number = 0;
        nonce = "";
        
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
        {
            strategy_enabled[i] = false;
            strategy_confidence[i] = 0.0;
            strategy_params[i] = "";
            strategy_symbol[i] = "";
            strategy_timeframe[i] = PERIOD_CURRENT;
        }
    }
};

//+------------------------------------------------------------------+
//| STRUCT: Config Update (received from CONFIG_PUSH or standalone)  |
//| Matches V6 Roadmap Section 7: CONFIG_PUSH format                 |
//+------------------------------------------------------------------+
struct SConfigUpdate
{
    bool                enabled;           // Strategy on/off from server
    double              confidence;        // Server-side confidence (0.0-1.0)
    ENUM_TIMEFRAMES     timeframe;         // Recommended timeframe
    ENUM_MARKET_REGIME  regime;            // Current market regime
    string              mm_method;         // Money management method ID (e.g., "MM4")
    string              json_params;       // Strategy-specific parameters as JSON string
    
    // Constructor with defaults
    void Reset()
    {
        enabled     = false;
        confidence  = 0.0;
        timeframe   = PERIOD_M15;
        regime      = REGIME_UNKNOWN;
        mm_method   = "MM1";
        json_params = "";
    }
};

//+------------------------------------------------------------------+
//| STRUCT: Strategy State (internal tracking)                       |
//+------------------------------------------------------------------+
struct SStrategyState
{
    ENUM_TRADE_SIGNAL   last_signal;       // Last generated signal
    double              last_confidence;   // Last confidence value
    double              last_sl;           // Last calculated SL price
    double              last_tp;           // Last calculated TP price
    datetime            last_signal_time;  // When signal was generated
    int                 consecutive_wins;  // Win streak counter
    int                 consecutive_losses;// Loss streak counter
    int                 total_trades;      // Total trades by this strategy
    double              total_pnl;         // Cumulative PnL in deposit currency
    
    void Reset()
    {
        last_signal       = SIGNAL_NONE;
        last_confidence   = 0.0;
        last_sl           = 0.0;
        last_tp           = 0.0;
        last_signal_time  = 0;
        consecutive_wins  = 0;
        consecutive_losses= 0;
        total_trades      = 0;
        total_pnl         = 0.0;
    }
};

//+------------------------------------------------------------------+
//| CLASS: IStrategy — Abstract Interface                            |
//+------------------------------------------------------------------+
//| All 16 strategies inherit from this class.                       |
//| MQL5 does not support pure virtual (=0), so defaults return      |
//| safe values. Each strategy MUST override the core methods.       |
//+------------------------------------------------------------------+
class IStrategy
{
protected:
    //--- Identity (set in constructor of each strategy)
    ENUM_STRATEGY_ID    m_strategy_id;     // Which strategy (S01-S16)
    SStrategyInfo       m_info;            // Static metadata from StrategyConstants
    
    //--- Runtime state
    string              m_symbol;          // Active trading symbol
    ENUM_TIMEFRAMES     m_timeframe;       // Active timeframe
    bool                m_initialized;     // Init() called successfully?
    bool                m_enabled;         // Activated by server/standalone?
    
    //--- Signal state
    SStrategyState      m_state;           // Current signal + tracking
    
    //--- Config from server
    SConfigUpdate       m_config;          // Last CONFIG_PUSH data

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    IStrategy()
    {
        m_strategy_id = S01_STAT_ARB;  // Override in derived class
        m_symbol      = "";
        m_timeframe   = PERIOD_M15;
        m_initialized = false;
        m_enabled     = false;
        m_state.Reset();
        m_config.Reset();
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    virtual ~IStrategy() {}
    
    //=================================================================
    //  CORE INTERFACE — Override these in each strategy
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| Init: Setup indicators, allocate resources                       |
    //| Called once when strategy is first loaded                        |
    //| @param symbol  Trading symbol (e.g., "XAUUSD")                  |
    //| @param tf      Primary timeframe for analysis                   |
    //| @return true if initialization successful                       |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        m_symbol    = symbol;
        m_timeframe = tf;
        
        // Load strategy metadata from constants table
        if(!g_strategy_table_initialized) InitStrategyTable();
        m_info = g_strategy_table[(int)m_strategy_id];
        
        m_state.Reset();
        m_initialized = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinit: Release indicator handles and resources                  |
    //| Called when EA is removed or strategy is permanently disabled    |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        m_initialized = false;
        m_enabled     = false;
    }
    
    //+------------------------------------------------------------------+
    //| Analyze: Process new tick data, update internal signal state     |
    //| Called every tick (or timer) when strategy is enabled            |
    //| This is the MAIN LOGIC method — each strategy overrides this    |
    //| @param tick  Current tick data from MT5                         |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        // Override: calculate indicators, detect patterns, set signal
        // Update m_state.last_signal, m_state.last_confidence, etc.
    }
    
    //+------------------------------------------------------------------+
    //| GetSignal: Return current trade signal                          |
    //| @return SIGNAL_BUY(1), SIGNAL_SELL(-1), or SIGNAL_NONE(0)      |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }
    
    //+------------------------------------------------------------------+
    //| GetConfidence: How confident is the signal? (0.0 to 1.0)        |
    //| Used by AI Council for weighted voting                          |
    //| Threshold: standalone > 0.50, online depends on Council         |
    //| @return confidence value, 0.0 = no confidence, 1.0 = max       |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }
    
    //+------------------------------------------------------------------+
    //| GetStopLoss: Calculated SL price for current signal             |
    //| @return stop loss price (0.0 = not set / use default)           |
    //+------------------------------------------------------------------+
    virtual double GetStopLoss()
    {
        return m_state.last_sl;
    }
    
    //+------------------------------------------------------------------+
    //| GetTakeProfit: Calculated TP price for current signal           |
    //| @return take profit price (0.0 = not set / use default)         |
    //+------------------------------------------------------------------+
    virtual double GetTakeProfit()
    {
        return m_state.last_tp;
    }
    
    //=================================================================
    //  CONFIG INTERFACE — Receive parameters from server
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| SetParameters: Receive strategy-specific params from CONFIG_PUSH |
    //| JSON format from server, strategy parses what it needs          |
    //| Example: {"StatArb_Beta": 1.05, "StatArb_Period": 20}          |
    //| @param jsonParams  JSON string with key-value parameters        |
    //+------------------------------------------------------------------+
    virtual void SetParameters(const string jsonParams)
    {
        m_config.json_params = jsonParams;
        // Override: parse JSON and apply to strategy-specific variables
        // Use StringFind() + StringSubstr() for simple parsing
        // Or MqlMsgPack for MessagePack format
    }
    
    //+------------------------------------------------------------------+
    //| OnConfigUpdate: Full config update from server (CONFIG_PUSH)     |
    //| Includes regime, timeframe, confidence, MM method               |
    //| @param config  Parsed CONFIG_PUSH data                          |
    //+------------------------------------------------------------------+
    virtual void OnConfigUpdate(const SConfigUpdate &config)
    {
        m_config = config;
        m_enabled = config.enabled;
        
        // Apply timeframe change if different
        if(config.timeframe != PERIOD_CURRENT && config.timeframe != m_timeframe)
        {
            m_timeframe = config.timeframe;
            // Derived class may need to reinitialize indicators for new TF
        }
        
        // Apply strategy-specific parameters
        if(config.json_params != "")
            SetParameters(config.json_params);
    }
    
    //=================================================================
    //  DYNAMIC PARAMETER INTERFACE — CONFIG_PUSH V2 support
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| SetDynamicParams: Apply a bundle of server-side parameters       |
    //| Called by StrategyManager_V6.DistributeDynamicParams()           |
    //| Strategy overrides this to extract its own param keys            |
    //| @param params  Bundle of key-value params from CONFIG_PUSH V2   |
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &params)
    {
        // Default: store mm_method only (SConfigUpdate has no risk_multiplier field)
        // Derived classes override to parse strategy-specific params
        m_config.mm_method = params.mm_method;
    }
    
    //+------------------------------------------------------------------+
    //| OnParamUpdate: Called when a specific param changes value        |
    //| Useful for logging hot-reloads or triggering indicator reinit   |
    //| @param param_name  Which parameter changed                       |
    //| @param old_val     Previous value                               |
    //| @param new_val     New value from server                        |
    //+------------------------------------------------------------------+
    virtual void OnParamUpdate(string param_name, double old_val, double new_val)
    {
        PrintFormat("[%s] Param updated: %s %.4f → %.4f",
                    m_info.short_name, param_name, old_val, new_val);
    }
    
    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export current param values for TRADE_REPORT   |
    //| StrategyManager_V6 calls this when building feedback messages   |
    //| @return SDynamicParams containing current active values          |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        // Default: return empty bundle — derived classes override
        SDynamicParams p;
        p.Reset();
        p.mm_method       = m_config.mm_method;
        p.risk_multiplier = 1.0;  // base class has no risk storage; derived classes set real value
        return p;
    }
    
    //=================================================================
    //  IDENTITY — Read-only metadata
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| GetName: Strategy display name                                  |
    //+------------------------------------------------------------------+
    virtual string GetName()
    {
        return m_info.name;
    }
    
    //+------------------------------------------------------------------+
    //| GetShortName: Short ID string (e.g., "S01", "S15")             |
    //+------------------------------------------------------------------+
    string GetShortName()
    {
        return m_info.short_name;
    }
    
    //+------------------------------------------------------------------+
    //| GetMagic: Magic number for this strategy's orders               |
    //+------------------------------------------------------------------+
    virtual int GetMagic()
    {
        return m_info.magic;
    }
    
    //+------------------------------------------------------------------+
    //| GetStrategyID: Enum ID (S01_STAT_ARB, S15_GRID, etc.)          |
    //+------------------------------------------------------------------+
    ENUM_STRATEGY_ID GetStrategyID()
    {
        return m_strategy_id;
    }
    
    //+------------------------------------------------------------------+
    //| GetCategory: "Full_MQL5" or "Hybrid"                            |
    //+------------------------------------------------------------------+
    virtual string GetCategory()
    {
        return CategoryToString(m_info.category);
    }
    
    //+------------------------------------------------------------------+
    //| IsStandaloneCapable: Can this strategy run without server?       |
    //| 7 strategies: S01, S06, S07, S10, S14, S15, S16                |
    //+------------------------------------------------------------------+
    virtual bool IsStandaloneCapable()
    {
        return m_info.standalone;
    }
    
    //+------------------------------------------------------------------+
    //| GetRegimePreference: What market regime does this strategy       |
    //| perform best in?                                                |
    //+------------------------------------------------------------------+
    ENUM_MARKET_REGIME GetRegimePreference()
    {
        return m_info.best_regime;
    }
    
    //+------------------------------------------------------------------+
    //| GetFamily: Strategy family for grouping (e.g., "Trend Following")|
    //+------------------------------------------------------------------+
    string GetFamily()
    {
        return m_info.family;
    }
    
    //=================================================================
    //  STATE ACCESS — For StrategyManager / AI Council
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| IsInitialized: Has Init() been called successfully?             |
    //+------------------------------------------------------------------+
    bool IsInitialized() const { return m_initialized; }
    
    //+------------------------------------------------------------------+
    //| IsEnabled: Is strategy currently active (enabled by server)?    |
    //+------------------------------------------------------------------+
    bool IsEnabled() const { return m_enabled; }
    
    //+------------------------------------------------------------------+
    //| Enable/Disable: Toggle strategy on/off                          |
    //+------------------------------------------------------------------+
    void Enable()  { m_enabled = true; }
    void Disable() { m_enabled = false; m_state.last_signal = SIGNAL_NONE; }
    
    //+------------------------------------------------------------------+
    //| GetSymbol: Current trading symbol                               |
    //+------------------------------------------------------------------+
    string GetSymbol() const { return m_symbol; }
    
    //+------------------------------------------------------------------+
    //| GetTimeframe: Current analysis timeframe                        |
    //+------------------------------------------------------------------+
    ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }
    
    //+------------------------------------------------------------------+
    //| GetState: Full internal state (for reporting/logging)           |
    //+------------------------------------------------------------------+
    SStrategyState GetState() const { return m_state; }
    
    //+------------------------------------------------------------------+
    //| GetConfig: Last received config update                          |
    //+------------------------------------------------------------------+
    SConfigUpdate GetConfig() const { return m_config; }
    
    //=================================================================
    //  PERFORMANCE TRACKING — Updated by StrategyManager after trades
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| RecordTradeResult: Called after trade closes                     |
    //| @param pnl  Profit/loss of the closed trade                    |
    //+------------------------------------------------------------------+
    void RecordTradeResult(double pnl)
    {
        m_state.total_trades++;
        m_state.total_pnl += pnl;
        
        if(pnl >= 0)
        {
            m_state.consecutive_wins++;
            m_state.consecutive_losses = 0;
        }
        else
        {
            m_state.consecutive_losses++;
            m_state.consecutive_wins = 0;
        }
    }
    
    //+------------------------------------------------------------------+
    //| GetWinRate: Calculate historical win rate                        |
    //| @return win rate 0.0-1.0 (returns 0.5 if no trades)            |
    //+------------------------------------------------------------------+
    double GetWinRate()
    {
        if(m_state.total_trades == 0) return 0.5;  // neutral default
        int wins = m_state.total_trades - m_state.consecutive_losses;
        // Simplified: actual implementation would track wins separately
        return (double)wins / (double)m_state.total_trades;
    }
    
    //=================================================================
    //  UTILITY — Logging and diagnostics
    //=================================================================
    
    //+------------------------------------------------------------------+
    //| PrintStatus: Log current strategy state                         |
    //+------------------------------------------------------------------+
    void PrintStatus()
    {
        PrintFormat("[%s] %s | %s | %s | Conf:%.2f | Signal:%s | Enabled:%s",
            m_info.short_name,
            m_info.name,
            m_symbol,
            EnumToString(m_timeframe),
            m_state.last_confidence,
            SignalToString(m_state.last_signal),
            m_enabled ? "YES" : "NO");
    }
};

#endif // ISTRATEGY_MQH
//+------------------------------------------------------------------+