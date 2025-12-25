//+------------------------------------------------------------------+
//|                                      PositionSizingManager.mqh   |
//|                            FlashEASuite V2.1 - Option A          |
//|                                       Risk Management Module      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/your-repo"
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Position Sizing Manager Class                                    |
//| Purpose: Calculate lot sizes based on 1% risk rule              |
//| Features:                                                        |
//|   - Fixed percentage risk (default 1%)                          |
//|   - ATR-based volatility adjustment                             |
//|   - Symbol-specific calculations                                |
//|   - Lot normalization and validation                            |
//+------------------------------------------------------------------+
class CPositionSizingManager
{
private:
    // Configuration
    double            m_default_risk_pct;      // Default risk % (1.0)
    double            m_min_lot;               // Minimum lot size
    double            m_max_lot;               // Maximum lot size
    double            m_lot_step;              // Lot size step
    string            m_symbol;                // Current symbol
    
    // Volatility adjustment
    bool              m_use_volatility_adj;    // Use ATR adjustment
    int               m_atr_period;            // ATR period (14)
    int               m_atr_handle;            // ATR indicator handle
    
    // Statistics
    int               m_calculations_count;    // Number of calculations
    double            m_last_calculated_lot;   // Last calculated lot
    
    //--- Helper methods
    double            GetPipValue(double lot_size = 1.0);
    double            GetATR();
    double            CalculateVolatilityMultiplier();
    
public:
    //--- Constructor/Destructor
                     CPositionSizingManager(void);
                    ~CPositionSizingManager(void);
    
    //--- Initialization
    bool              Initialize(string symbol = "",
                                double default_risk = 1.0,
                                bool use_volatility = true);
    void              Shutdown(void);
    
    //--- Main calculation methods
    double            CalculateLotSize(double entry_price,
                                      double stop_loss,
                                      double risk_pct = 0);
    
    double            CalculateLotSizeByRiskAmount(double risk_amount,
                                                   double entry_price,
                                                   double stop_loss);
    
    double            CalculateLotSizeWithVolatility(double entry_price,
                                                     double stop_loss,
                                                     double risk_pct = 0);
    
    //--- Lot manipulation
    double            NormalizeLotSize(double lot);
    bool              ValidateLotSize(double lot);
    double            ClampLotSize(double lot);
    
    //--- Getters
    double            GetMinLot(void) const { return m_min_lot; }
    double            GetMaxLot(void) const { return m_max_lot; }
    double            GetLotStep(void) const { return m_lot_step; }
    double            GetDefaultRisk(void) const { return m_default_risk_pct; }
    int               GetCalculationsCount(void) const { return m_calculations_count; }
    double            GetLastCalculatedLot(void) const { return m_last_calculated_lot; }
    
    //--- Setters
    void              SetDefaultRisk(double risk_pct) { m_default_risk_pct = risk_pct; }
    void              SetUseVolatility(bool use) { m_use_volatility_adj = use; }
    
    //--- Display
    void              PrintInfo(void);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CPositionSizingManager::CPositionSizingManager(void) :
    m_default_risk_pct(1.0),
    m_min_lot(0.01),
    m_max_lot(100.0),
    m_lot_step(0.01),
    m_symbol(""),
    m_use_volatility_adj(true),
    m_atr_period(14),
    m_atr_handle(INVALID_HANDLE),
    m_calculations_count(0),
    m_last_calculated_lot(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CPositionSizingManager::~CPositionSizingManager(void)
{
    Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CPositionSizingManager::Initialize(string symbol="",
                                       double default_risk=1.0,
                                       bool use_volatility=true)
{
    // Set symbol
    m_symbol = (symbol == "") ? _Symbol : symbol;
    m_default_risk_pct = default_risk;
    m_use_volatility_adj = use_volatility;
    
    // Get symbol properties
    m_min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
    m_max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
    m_lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    
    // Validate symbol properties
    if(m_min_lot <= 0 || m_max_lot <= 0 || m_lot_step <= 0)
    {
        Print("❌ Position Sizing Manager: Invalid symbol properties");
        Print("   Symbol: ", m_symbol);
        Print("   Min Lot: ", m_min_lot);
        Print("   Max Lot: ", m_max_lot);
        Print("   Lot Step: ", m_lot_step);
        return false;
    }
    
    // Initialize ATR indicator if using volatility
    if(m_use_volatility_adj)
    {
        m_atr_handle = iATR(m_symbol, PERIOD_CURRENT, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("⚠️ Warning: Failed to create ATR indicator, disabling volatility adjustment");
            m_use_volatility_adj = false;
        }
    }
    
    Print("✅ Position Sizing Manager initialized");
    Print("   Symbol: ", m_symbol);
    Print("   Default Risk: ", m_default_risk_pct, "%");
    Print("   Lot Range: ", m_min_lot, " - ", m_max_lot, " (step: ", m_lot_step, ")");
    Print("   Volatility Adjustment: ", (m_use_volatility_adj ? "Enabled" : "Disabled"));
    
    return true;
}

//+------------------------------------------------------------------+
//| Shutdown                                                          |
//+------------------------------------------------------------------+
void CPositionSizingManager::Shutdown(void)
{
    if(m_atr_handle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atr_handle);
        m_atr_handle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size (Basic)                                       |
//| Formula: Lot = (Account * Risk%) / (Stop Distance * Pip Value)  |
//+------------------------------------------------------------------+
double CPositionSizingManager::CalculateLotSize(double entry_price,
                                                double stop_loss,
                                                double risk_pct=0)
{
    // Use default if not specified
    if(risk_pct <= 0)
        risk_pct = m_default_risk_pct;
    
    // Get account balance
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0)
    {
        Print("❌ Invalid account balance: ", balance);
        return 0;
    }
    
    // Calculate risk amount
    double risk_amount = balance * (risk_pct / 100.0);
    
    // Calculate lot size
    double lot_size = CalculateLotSizeByRiskAmount(risk_amount, entry_price, stop_loss);
    
    // Update statistics
    m_calculations_count++;
    m_last_calculated_lot = lot_size;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size by Risk Amount                                |
//+------------------------------------------------------------------+
double CPositionSizingManager::CalculateLotSizeByRiskAmount(double risk_amount,
                                                            double entry_price,
                                                            double stop_loss)
{
    // Validate inputs
    if(risk_amount <= 0)
    {
        Print("❌ Invalid risk amount: ", risk_amount);
        return 0;
    }
    
    if(entry_price <= 0 || stop_loss <= 0)
    {
        Print("❌ Invalid prices - Entry: ", entry_price, " SL: ", stop_loss);
        return 0;
    }
    
    if(MathAbs(entry_price - stop_loss) < SymbolInfoDouble(m_symbol, SYMBOL_POINT))
    {
        Print("❌ Stop loss too close to entry");
        return 0;
    }
    
    // Calculate stop distance in points
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double stop_distance_points = MathAbs(entry_price - stop_loss) / point;
    
    // Get pip value for 1 lot
    double pip_value = GetPipValue(1.0);
    if(pip_value <= 0)
    {
        Print("❌ Invalid pip value: ", pip_value);
        return 0;
    }
    
    // Calculate lot size
    // Risk Amount = Lot Size * Stop Distance (in pips) * Pip Value per Lot
    // Therefore: Lot Size = Risk Amount / (Stop Distance * Pip Value)
    
    double digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    double pip_size = (digits == 5 || digits == 3) ? 10.0 : 1.0;
    double stop_distance_pips = stop_distance_points / pip_size;
    
    double lot_size = risk_amount / (stop_distance_pips * pip_value);
    
    // Normalize and validate
    lot_size = NormalizeLotSize(lot_size);
    
    if(!ValidateLotSize(lot_size))
    {
        Print("⚠️ Calculated lot size invalid, clamping to limits");
        lot_size = ClampLotSize(lot_size);
    }
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size With Volatility Adjustment                    |
//+------------------------------------------------------------------+
double CPositionSizingManager::CalculateLotSizeWithVolatility(double entry_price,
                                                              double stop_loss,
                                                              double risk_pct=0)
{
    // Calculate base lot size
    double base_lot = CalculateLotSize(entry_price, stop_loss, risk_pct);
    
    if(!m_use_volatility_adj || base_lot <= 0)
        return base_lot;
    
    // Get volatility multiplier
    double vol_multiplier = CalculateVolatilityMultiplier();
    
    // Adjust lot size
    double adjusted_lot = base_lot * vol_multiplier;
    
    // Normalize and validate
    adjusted_lot = NormalizeLotSize(adjusted_lot);
    
    if(!ValidateLotSize(adjusted_lot))
        adjusted_lot = ClampLotSize(adjusted_lot);
    
    Print("📊 Volatility Adjustment: ", 
          "Base: ", DoubleToString(base_lot, 2),
          " × ", DoubleToString(vol_multiplier, 2),
          " = ", DoubleToString(adjusted_lot, 2));
    
    return adjusted_lot;
}

//+------------------------------------------------------------------+
//| Get Pip Value                                                     |
//+------------------------------------------------------------------+
double CPositionSizingManager::GetPipValue(double lot_size=1.0)
{
    double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    if(tick_size <= 0 || point <= 0)
        return 0;
    
    // Calculate pip value
    double digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    double pip_size = (digits == 5 || digits == 3) ? 10.0 * point : point;
    
    double pip_value = (tick_value / tick_size) * pip_size * lot_size;
    
    return pip_value;
}

//+------------------------------------------------------------------+
//| Get ATR                                                           |
//+------------------------------------------------------------------+
double CPositionSizingManager::GetATR(void)
{
    if(m_atr_handle == INVALID_HANDLE)
        return 0;
    
    double atr_buffer[];
    ArraySetAsSeries(atr_buffer, true);
    
    if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
    {
        Print("⚠️ Failed to copy ATR buffer");
        return 0;
    }
    
    return atr_buffer[0];
}

//+------------------------------------------------------------------+
//| Calculate Volatility Multiplier                                  |
//| Returns: 0.5 to 1.5 (low volatility = larger lot, high vol = smaller) |
//+------------------------------------------------------------------+
double CPositionSizingManager::CalculateVolatilityMultiplier(void)
{
    double current_atr = GetATR();
    if(current_atr <= 0)
        return 1.0;  // No adjustment if ATR unavailable
    
    // Get historical ATR (100 periods for average)
    double atr_buffer[];
    ArraySetAsSeries(atr_buffer, true);
    
    if(CopyBuffer(m_atr_handle, 0, 0, 100, atr_buffer) < 100)
        return 1.0;
    
    // Calculate average ATR
    double atr_sum = 0;
    for(int i = 0; i < 100; i++)
        atr_sum += atr_buffer[i];
    
    double average_atr = atr_sum / 100.0;
    
    if(average_atr <= 0)
        return 1.0;
    
    // Calculate multiplier
    // If current ATR > average: reduce lot (high volatility)
    // If current ATR < average: increase lot (low volatility)
    double multiplier = average_atr / current_atr;
    
    // Clamp to 0.5 - 1.5 range
    multiplier = MathMax(0.5, MathMin(1.5, multiplier));
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Normalize Lot Size                                               |
//+------------------------------------------------------------------+
double CPositionSizingManager::NormalizeLotSize(double lot)
{
    if(lot <= 0)
        return 0;
    
    // Round to lot step
    double normalized = MathRound(lot / m_lot_step) * m_lot_step;
    
    // Ensure minimum precision
    normalized = NormalizeDouble(normalized, 2);
    
    return normalized;
}

//+------------------------------------------------------------------+
//| Validate Lot Size                                                |
//+------------------------------------------------------------------+
bool CPositionSizingManager::ValidateLotSize(double lot)
{
    if(lot < m_min_lot)
    {
        Print("⚠️ Lot too small: ", lot, " < ", m_min_lot);
        return false;
    }
    
    if(lot > m_max_lot)
    {
        Print("⚠️ Lot too large: ", lot, " > ", m_max_lot);
        return false;
    }
    
    // Check if lot is multiple of step
    double remainder = MathMod(lot, m_lot_step);
    if(remainder > 0.0001)  // Small tolerance for floating point
    {
        Print("⚠️ Lot not a multiple of step: ", lot, " (step: ", m_lot_step, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Clamp Lot Size to Valid Range                                    |
//+------------------------------------------------------------------+
double CPositionSizingManager::ClampLotSize(double lot)
{
    if(lot < m_min_lot)
        return m_min_lot;
    
    if(lot > m_max_lot)
        return m_max_lot;
    
    return NormalizeLotSize(lot);
}

//+------------------------------------------------------------------+
//| Print Information                                                 |
//+------------------------------------------------------------------+
void CPositionSizingManager::PrintInfo(void)
{
    Print("=== Position Sizing Manager Info ===");
    Print("Symbol: ", m_symbol);
    Print("Default Risk: ", m_default_risk_pct, "%");
    Print("Lot Range: ", m_min_lot, " - ", m_max_lot);
    Print("Lot Step: ", m_lot_step);
    Print("Volatility Adjustment: ", (m_use_volatility_adj ? "Yes" : "No"));
    Print("Calculations Made: ", m_calculations_count);
    Print("Last Calculated Lot: ", m_last_calculated_lot);
    Print("=====================================");
}

//+------------------------------------------------------------------+
