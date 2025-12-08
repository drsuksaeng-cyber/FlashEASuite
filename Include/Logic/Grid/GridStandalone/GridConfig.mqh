//+------------------------------------------------------------------+
//|                                           GridStandalone/GridConfig.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                          Base Configuration & Enums Module               |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STATE
{
    MARKET_STATE_RANGING_NORMAL,      // Ideal for grid - ADX<20, ATR normal
    MARKET_STATE_RANGING_HIGH_VOL,    // Dangerous - ADX<20, ATR>1.5x
    MARKET_STATE_TRENDING_WEAK,       // OK for grid - ADX 20-30
    MARKET_STATE_TRENDING_STRONG,     // Avoid grid - ADX>30
    MARKET_STATE_UNDEFINED            // Skip trading
};

enum ENUM_GRID_DIRECTION
{
    GRID_DIR_NONE = 0,                // No direction set
    GRID_DIR_BUY  = 1,                // Only BUY grids
    GRID_DIR_SELL = -1                // Only SELL grids
};

enum ENUM_EXIT_REASON
{
    EXIT_NONE = 0,
    EXIT_PROFIT_TARGET,               // Total PnL target hit
    EXIT_TRAILING_STOP,               // Trailing from high PnL
    EXIT_REVERSAL,                    // Market reversed
    EXIT_TIME_LIMIT,                  // Max duration reached
    EXIT_MAX_DD,                      // Max drawdown limit
    EXIT_DAILY_LIMIT,                 // Daily loss limit
    EXIT_VOLATILITY_SPIKE,            // ATR spike >3x
    EXIT_SPREAD_WIDENING,             // Spread >5x average
    EXIT_MANUAL                       // Manual/Python emergency
};

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct GridOrder
{
    ulong             ticket;         // Position ticket
    double            open_price;     // Entry price
    double            lot_size;       // Lot size
    datetime          open_time;      // Open time
    int               level;          // Grid level (0, 1, 2, ...)
    double            profit;         // Current profit
};

struct PolicyUpdate
{
    string            symbol;
    double            risk_multiplier;    // 0.5 - 1.5
    bool              is_in_cooldown;
    double            confidence;         // 0.0 - 1.0
    double            csm_usd;
    double            csm_eur;
    double            csm_gbp;
    double            csm_jpy;
    long              timestamp_ms;
    string            model_version;
};

//+------------------------------------------------------------------+
//| Base Configuration Class                                          |
//+------------------------------------------------------------------+
class CGridConfig
{
protected:
    // --- Trading Instruments ---
    CTrade            m_trade;
    
    // --- Indicator Handles ---
    int               m_ma_fast_handle;       // MA(20)
    int               m_ma_slow_handle;       // MA(50)
    int               m_adx_handle;           // ADX(14)
    int               m_rsi_handle;           // RSI(14)
    int               m_macd_handle;          // MACD(12,26,9)
    int               m_atr_handle;           // ATR(14)
    
    // --- Grid Parameters ---
    int               m_max_grid_levels;      // Max 5 orders
    double            m_base_step_points;     // Base grid step (200 for XAUUSD)
    double            m_base_lot;             // Base lot size (0.01)
    double            m_atr_reference;        // Reference ATR (30.0)
    
    // --- Anti-Martingale Progression ---
    double            m_lot_progression[5];   // {1.0, 1.3, 1.5, 1.8, 2.0}
    
    // --- TP/SL Multipliers ---
    double            m_tp_multiplier;        // 2.0 (TP = elastic * 2.0)
    double            m_sl_multiplier;        // 2.5 (SL = elastic * 2.5)
    
    // --- Exit Parameters ---
    double            m_profit_target_mult;   // 1.5 (target = risk * 1.5)
    double            m_trailing_threshold;   // 0.7 (trail at 30% retracement)
    int               m_max_duration_hours;   // 72 hours (3 days)
    
    // --- Risk Limits ---
    double            m_max_dd_percent;       // 15%
    double            m_avg_dd_target;        // 8%
    double            m_daily_loss_limit;     // 3%
    double            m_max_risk_per_grid;    // 2%
    
    // --- Grid State ---
    GridOrder         m_grid_orders[10];
    int               m_active_grid_count;
    double            m_last_grid_price;
    datetime          m_grid_start_time;
    string            m_grid_id;
    
    // --- Current State ---
    ENUM_GRID_DIRECTION m_current_direction;
    ENUM_MARKET_STATE   m_current_market_state;
    ENUM_EXIT_REASON    m_exit_reason;
    
    // --- Elastic Step & ATR ---
    double            m_current_elastic_step;
    double            m_atr_current;
    
    // --- Profit Tracking ---
    double            m_highest_pnl;
    
    // --- Python Enhancement (Optional) ---
    double            m_python_risk_multiplier;
    double            m_python_confidence;
    bool              m_python_connected;
    
protected:
    // Made protected so derived classes can access
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridConfig()
    {
        // Default Parameters
        m_max_grid_levels = 5;
        m_base_step_points = 200.0;        // 20 pips for XAUUSD
        m_base_lot = 0.01;
        m_atr_reference = 30.0;
        
        // Lot progression (Anti-Martingale)
        m_lot_progression[0] = 1.0;
        m_lot_progression[1] = 1.3;
        m_lot_progression[2] = 1.5;
        m_lot_progression[3] = 1.8;
        m_lot_progression[4] = 2.0;
        
        // TP/SL
        m_tp_multiplier = 2.0;
        m_sl_multiplier = 2.5;
        
        // Exit
        m_profit_target_mult = 1.5;
        m_trailing_threshold = 0.7;
        m_max_duration_hours = 72;
        
        // Risk Limits
        m_max_dd_percent = 15.0;
        m_avg_dd_target = 8.0;
        m_daily_loss_limit = 3.0;
        m_max_risk_per_grid = 2.0;
        
        // Initialize State
        m_active_grid_count = 0;
        m_last_grid_price = 0.0;
        m_grid_start_time = 0;
        m_current_direction = GRID_DIR_NONE;
        m_current_market_state = MARKET_STATE_UNDEFINED;
        m_exit_reason = EXIT_NONE;
        m_current_elastic_step = 0.0;
        m_atr_current = 0.0;
        m_highest_pnl = 0.0;
        
        // Python
        m_python_risk_multiplier = 1.0;
        m_python_confidence = 0.5;
        m_python_connected = false;
        
        // Initialize grid orders array
        for(int i = 0; i < 10; i++)
        {
            m_grid_orders[i].ticket = 0;
            m_grid_orders[i].open_price = 0.0;
            m_grid_orders[i].lot_size = 0.0;
            m_grid_orders[i].open_time = 0;
            m_grid_orders[i].level = 0;
            m_grid_orders[i].profit = 0.0;
        }
        
        // Initialize Trade
        m_trade.SetExpertMagicNumber(999000);
        
        // Create indicators (will be initialized in derived class)
        m_ma_fast_handle = INVALID_HANDLE;
        m_ma_slow_handle = INVALID_HANDLE;
        m_adx_handle = INVALID_HANDLE;
        m_rsi_handle = INVALID_HANDLE;
        m_macd_handle = INVALID_HANDLE;
        m_atr_handle = INVALID_HANDLE;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CGridConfig()
    {
        // Release indicator handles
        if(m_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(m_ma_fast_handle);
        if(m_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(m_ma_slow_handle);
        if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
        if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
        if(m_macd_handle != INVALID_HANDLE) IndicatorRelease(m_macd_handle);
        if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
    }
    
    //+------------------------------------------------------------------+
    //| Initialize Indicators                                            |
    //+------------------------------------------------------------------+
    bool InitializeIndicators(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        // MA Fast (20)
        m_ma_fast_handle = iMA(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
        if(m_ma_fast_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create MA(20)");
            return false;
        }
        
        // MA Slow (50)
        m_ma_slow_handle = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
        if(m_ma_slow_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create MA(50)");
            return false;
        }
        
        // ADX (14)
        m_adx_handle = iADX(symbol, timeframe, 14);
        if(m_adx_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create ADX(14)");
            return false;
        }
        
        // RSI (14)
        m_rsi_handle = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
        if(m_rsi_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create RSI(14)");
            return false;
        }
        
        // MACD (12, 26, 9)
        m_macd_handle = iMACD(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
        if(m_macd_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create MACD");
            return false;
        }
        
        // ATR (14)
        m_atr_handle = iATR(symbol, timeframe, 14);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[GridConfig] ERROR: Failed to create ATR(14)");
            return false;
        }
        
        Print("[GridConfig] ✅ All indicators initialized successfully");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update Configuration                                             |
    //+------------------------------------------------------------------+
    void UpdateConfig(int max_levels, double base_step, double base_lot)
    {
        m_max_grid_levels = max_levels;
        m_base_step_points = base_step;
        m_base_lot = base_lot;
        
        Print("[GridConfig] Configuration updated:");
        Print("  Max levels: ", m_max_grid_levels);
        Print("  Base step: ", m_base_step_points, " points");
        Print("  Base lot: ", m_base_lot);
    }
    
    //+------------------------------------------------------------------+
    //| Set Python Enhancement Data                                      |
    //+------------------------------------------------------------------+
    void SetPythonData(double risk_mult, bool cooldown, double confidence)
    {
        m_python_risk_multiplier = risk_mult;
        m_python_confidence = confidence;
        m_python_connected = true;
        
        if(cooldown)
        {
            Print("[GridConfig] ⚠️ Python COOLDOWN active - Grid paused");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    int GetActiveGridCount() { return m_active_grid_count; }
    ENUM_GRID_DIRECTION GetCurrentDirection() { return m_current_direction; }
    ENUM_MARKET_STATE GetMarketState() { return m_current_market_state; }
    double GetCurrentElasticStep() { return m_current_elastic_step; }
    double GetCurrentATR() { return m_atr_current; }
    double GetHighestPnL() { return m_highest_pnl; }
    string GetGridID() { return m_grid_id; }
    
    //+------------------------------------------------------------------+
    //| Reset Grid State                                                 |
    //+------------------------------------------------------------------+
    void ResetGridState()
    {
        m_active_grid_count = 0;
        m_last_grid_price = 0.0;
        m_grid_start_time = 0;
        m_grid_id = "";
        m_current_direction = GRID_DIR_NONE;
        m_exit_reason = EXIT_NONE;
        m_highest_pnl = 0.0;
        
        for(int i = 0; i < 10; i++)
        {
            m_grid_orders[i].ticket = 0;
            m_grid_orders[i].open_price = 0.0;
            m_grid_orders[i].lot_size = 0.0;
            m_grid_orders[i].open_time = 0;
            m_grid_orders[i].level = 0;
            m_grid_orders[i].profit = 0.0;
        }
        
        Print("[GridConfig] Grid state reset");
    }
    
    //+------------------------------------------------------------------+
    //| Generate Grid ID                                                 |
    //+------------------------------------------------------------------+
    string GenerateGridID()
    {
        return StringFormat("%s_%s_%d",
                          _Symbol,
                          TimeToString(TimeCurrent(), TIME_DATE),
                          GetTickCount());
    }
};
//+------------------------------------------------------------------+
