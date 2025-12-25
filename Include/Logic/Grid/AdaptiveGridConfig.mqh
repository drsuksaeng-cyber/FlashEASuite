//+------------------------------------------------------------------+
//|                                  Grid/AdaptiveGridConfig.mqh     |
//|                                    FlashEASuite V2 - Week 5      |
//|                      Auto-Adaptive Grid Configuration             |
//+------------------------------------------------------------------+
#property strict

#include "RangeAnalyzer.mqh"

//+------------------------------------------------------------------+
//| Symbol-Specific Grid Configuration                              |
//+------------------------------------------------------------------+
struct SymbolGridConfig
{
    string   symbol;
    ENUM_TIMEFRAMES timeframe;
    
    // Adaptive parameters
    int      grid_spacing;        // Grid spacing in points
    int      max_grid_levels;     // Maximum grid levels
    double   take_profit;         // Take profit in points
    double   stop_loss;           // Stop loss in points (optional)
    
    // Risk parameters
    double   lot_size;            // Base lot size
    double   lot_multiplier;      // Lot multiplier per level
    double   max_exposure;        // Maximum exposure (lots)
    
    // Market conditions
    double   avg_range;           // Average range
    double   atr_value;           // Current ATR
    double   volatility_factor;   // Volatility adjustment (0.5-2.0)
    
    // Update metadata
    datetime last_update;
    bool     is_valid;
};

//+------------------------------------------------------------------+
//| Adaptive Grid Configuration Manager                             |
//+------------------------------------------------------------------+
class CAdaptiveGridConfig
{
private:
    // Range analyzer
    CRangeAnalyzer* m_range_analyzer;
    
    // Current configuration
    SymbolGridConfig m_config;
    
    // Update parameters
    int      m_update_interval_hours;  // How often to recalculate (default: 24)
    datetime m_last_update;
    
    // Adjustment factors
    double   m_conservative_factor;    // Make grid wider/narrower (default: 1.0)
    double   m_min_spacing_pips;       // Minimum spacing (default: 10 pips)
    double   m_max_spacing_pips;       // Maximum spacing (default: 500 pips)
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CAdaptiveGridConfig(string symbol = "", ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
    {
        string sym = (symbol == "") ? _Symbol : symbol;
        ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? _Period : timeframe;
        
        m_range_analyzer = new CRangeAnalyzer(sym, tf);
        
        m_config.symbol = sym;
        m_config.timeframe = tf;
        m_config.is_valid = false;
        
        m_update_interval_hours = 24;  // Update daily
        m_last_update = 0;
        
        m_conservative_factor = 1.0;
        m_min_spacing_pips = 10.0;
        m_max_spacing_pips = 500.0;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CAdaptiveGridConfig()
    {
        if(m_range_analyzer != NULL)
            delete m_range_analyzer;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                       |
    //+------------------------------------------------------------------+
    bool Initialize()
    {
        Print("🔧 Initializing Adaptive Grid Config: ", m_config.symbol);
        
        if(!m_range_analyzer.Initialize(1000, 14))
        {
            Print("❌ Failed to initialize RangeAnalyzer");
            return false;
        }
        
        // Run initial analysis
        if(!UpdateConfiguration())
        {
            Print("❌ Failed initial configuration update");
            return false;
        }
        
        Print("✅ Adaptive Grid Config initialized");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update Configuration (Run Analysis)                             |
    //+------------------------------------------------------------------+
    bool UpdateConfiguration()
    {
        Print("📊 Updating adaptive grid configuration...");
        
        // Run range analysis
        if(!m_range_analyzer.AnalyzeRange())
        {
            Print("❌ Range analysis failed");
            return false;
        }
        
        // Get analysis results
        RangeAnalysisResult analysis = m_range_analyzer.GetResult();
        
        if(!analysis.is_valid)
        {
            Print("❌ Invalid analysis result");
            return false;
        }
        
        // Apply analysis to configuration
        ApplyAnalysisToConfig(analysis);
        
        // Apply volatility adjustments
        ApplyVolatilityAdjustments();
        
        // Apply conservative factor
        ApplyConservativeFactor();
        
        // Validate and enforce limits
        EnforceLimits();
        
        m_config.last_update = TimeCurrent();
        m_config.is_valid = true;
        m_last_update = TimeCurrent();
        
        PrintConfiguration();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Apply Analysis Results to Configuration                         |
    //+------------------------------------------------------------------+
    void ApplyAnalysisToConfig(const RangeAnalysisResult &analysis)
    {
        // Use recommended spacing
        m_config.grid_spacing = analysis.recommended_spacing;
        m_config.max_grid_levels = analysis.recommended_levels;
        m_config.take_profit = analysis.recommended_tp;
        
        // Store market metrics
        m_config.avg_range = analysis.avg_sideways_range;
        m_config.atr_value = analysis.atr_value;
        
        // Calculate stop loss (2x typical range as safety)
        m_config.stop_loss = analysis.typical_range * 2.0;
        
        Print("📊 Applied analysis results:");
        Print("   Grid Spacing: ", m_config.grid_spacing, " points");
        Print("   Max Levels: ", m_config.max_grid_levels);
        Print("   Take Profit: ", m_config.take_profit, " points");
    }
    
    //+------------------------------------------------------------------+
    //| Apply Volatility Adjustments                                    |
    //+------------------------------------------------------------------+
    void ApplyVolatilityAdjustments()
    {
        // Calculate volatility factor (ATR / avg_range)
        if(m_config.avg_range > 0)
        {
            m_config.volatility_factor = m_config.atr_value / m_config.avg_range;
        }
        else
        {
            m_config.volatility_factor = 1.0;
        }
        
        // Clamp volatility factor
        if(m_config.volatility_factor < 0.5) m_config.volatility_factor = 0.5;
        if(m_config.volatility_factor > 2.0) m_config.volatility_factor = 2.0;
        
        // Adjust grid spacing based on volatility
        // High volatility → wider spacing
        m_config.grid_spacing = (int)(m_config.grid_spacing * m_config.volatility_factor);
        
        Print("📊 Volatility adjustment:");
        Print("   Factor: ", DoubleToString(m_config.volatility_factor, 2));
        Print("   Adjusted Spacing: ", m_config.grid_spacing, " points");
    }
    
    //+------------------------------------------------------------------+
    //| Apply Conservative Factor                                       |
    //+------------------------------------------------------------------+
    void ApplyConservativeFactor()
    {
        // Apply user-defined conservative factor
        // >1.0 = wider grid (more conservative)
        // <1.0 = tighter grid (more aggressive)
        
        m_config.grid_spacing = (int)(m_config.grid_spacing * m_conservative_factor);
        m_config.take_profit = m_config.take_profit * m_conservative_factor;
        
        // Recalculate max levels
        if(m_config.grid_spacing > 0)
        {
            m_config.max_grid_levels = (int)(m_config.avg_range / m_config.grid_spacing);
            if(m_config.max_grid_levels < 3) m_config.max_grid_levels = 3;
            if(m_config.max_grid_levels > 15) m_config.max_grid_levels = 15;
        }
        
        if(m_conservative_factor != 1.0)
        {
            Print("📊 Conservative factor applied: ", DoubleToString(m_conservative_factor, 2));
            Print("   Final Spacing: ", m_config.grid_spacing, " points");
            Print("   Max Levels: ", m_config.max_grid_levels);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Enforce Limits                                                  |
    //+------------------------------------------------------------------+
    void EnforceLimits()
    {
        double point_value = SymbolInfoDouble(m_config.symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(m_config.symbol, SYMBOL_DIGITS);
        
        // Convert pip limits to points
        int min_points = (int)(m_min_spacing_pips * 10);  // 10 points per pip for 5-digit
        int max_points = (int)(m_max_spacing_pips * 10);
        
        if(digits == 3 || digits == 2)
        {
            min_points = (int)m_min_spacing_pips;  // 1 point per pip for 3-digit
            max_points = (int)m_max_spacing_pips;
        }
        
        // Enforce spacing limits
        if(m_config.grid_spacing < min_points)
        {
            Print("⚠️ Spacing too small, enforcing minimum: ", min_points);
            m_config.grid_spacing = min_points;
        }
        
        if(m_config.grid_spacing > max_points)
        {
            Print("⚠️ Spacing too large, enforcing maximum: ", max_points);
            m_config.grid_spacing = max_points;
        }
        
        // Enforce level limits
        if(m_config.max_grid_levels < 3) m_config.max_grid_levels = 3;
        if(m_config.max_grid_levels > 20) m_config.max_grid_levels = 20;
        
        // Ensure TP > spacing
        if(m_config.take_profit < m_config.grid_spacing)
        {
            m_config.take_profit = m_config.grid_spacing * 1.5;
            Print("⚠️ Adjusted TP to 1.5x spacing: ", m_config.take_profit);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check if Update Needed                                          |
    //+------------------------------------------------------------------+
    bool NeedsUpdate()
    {
        if(m_last_update == 0) return true;
        
        int hours_since_update = (int)((TimeCurrent() - m_last_update) / 3600);
        return (hours_since_update >= m_update_interval_hours);
    }
    
    //+------------------------------------------------------------------+
    //| Auto-Update if Needed                                           |
    //+------------------------------------------------------------------+
    bool AutoUpdate()
    {
        if(NeedsUpdate())
        {
            Print("⏰ Auto-update triggered (", m_update_interval_hours, " hours elapsed)");
            return UpdateConfiguration();
        }
        return true;  // No update needed
    }
    
    //+------------------------------------------------------------------+
    //| Print Current Configuration                                     |
    //+------------------------------------------------------------------+
    void PrintConfiguration()
    {
        Print("═══════════════════════════════════════════");
        Print("⚙️  ADAPTIVE GRID CONFIGURATION");
        Print("═══════════════════════════════════════════");
        Print("Symbol: ", m_config.symbol);
        Print("Timeframe: ", EnumToString(m_config.timeframe));
        Print("Last Update: ", TimeToString(m_config.last_update));
        Print("───────────────────────────────────────────");
        Print("Grid Parameters:");
        Print("  Spacing: ", m_config.grid_spacing, " points (", 
              DoubleToString(m_config.grid_spacing * _Point, _Digits), " price)");
        Print("  Max Levels: ", m_config.max_grid_levels);
        Print("  Take Profit: ", DoubleToString(m_config.take_profit, 1), " points");
        Print("  Stop Loss: ", DoubleToString(m_config.stop_loss, 1), " points");
        Print("───────────────────────────────────────────");
        Print("Market Metrics:");
        Print("  Avg Range: ", DoubleToString(m_config.avg_range, 1), " points");
        Print("  ATR: ", DoubleToString(m_config.atr_value, 1), " points");
        Print("  Volatility Factor: ", DoubleToString(m_config.volatility_factor, 2));
        Print("═══════════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    int GetGridSpacing() { return m_config.grid_spacing; }
    int GetMaxLevels() { return m_config.max_grid_levels; }
    double GetTakeProfit() { return m_config.take_profit; }
    double GetStopLoss() { return m_config.stop_loss; }
    SymbolGridConfig GetConfiguration() { return m_config; }
    
    //+------------------------------------------------------------------+
    //| Setters for Adjustment                                          |
    //+------------------------------------------------------------------+
    void SetConservativeFactor(double factor)
    {
        m_conservative_factor = factor;
        if(m_conservative_factor < 0.5) m_conservative_factor = 0.5;
        if(m_conservative_factor > 3.0) m_conservative_factor = 3.0;
        Print("📊 Conservative factor set to: ", DoubleToString(m_conservative_factor, 2));
    }
    
    void SetUpdateInterval(int hours)
    {
        m_update_interval_hours = hours;
        if(m_update_interval_hours < 1) m_update_interval_hours = 1;
        Print("⏰ Update interval set to: ", m_update_interval_hours, " hours");
    }
    
    void SetSpacingLimits(double min_pips, double max_pips)
    {
        m_min_spacing_pips = min_pips;
        m_max_spacing_pips = max_pips;
        Print("📏 Spacing limits: ", DoubleToString(min_pips, 1), " - ", 
              DoubleToString(max_pips, 1), " pips");
    }
};

//+------------------------------------------------------------------+
