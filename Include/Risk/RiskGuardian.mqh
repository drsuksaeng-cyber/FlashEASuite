//+------------------------------------------------------------------+
//|                                              RiskGuardian.mqh    |
//|                            FlashEASuite V2.1 - Option A          |
//|                                       Risk Management Module      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/your-repo"
#property version   "2.10"
#property strict

#include "PositionSizingManager.mqh"
#include "DailyLossLimit.mqh"

//+------------------------------------------------------------------+
//| Risk Guardian - Central Risk Management                          |
//| Purpose: Coordinate all risk management components              |
//| Features:                                                        |
//|   - Position sizing (1% risk rule)                             |
//|   - Daily loss limit (4% default)                              |
//|   - Max orders control                                          |
//|   - Max exposure control                                        |
//|   - Comprehensive validation                                    |
//+------------------------------------------------------------------+
class CRiskGuardian
{
private:
    // Configuration
    int               m_max_orders;            // Max concurrent orders
    double            m_max_risk_percent;      // Max risk per trade
    double            m_max_exposure_percent;  // Max total exposure
    
    // Risk Management Components
    CPositionSizingManager* m_position_sizing; // Position sizing
    CDailyLossLimit*  m_daily_limit;          // Daily loss limit
    
    // State tracking
    bool              m_is_initialized;        // Initialization status
    datetime          m_last_check_time;       // Last validation time
    int               m_validation_count;      // Number of validations
    int               m_rejections_count;      // Number of rejections
    
    // Statistics
    struct RejectionStats
    {
        int daily_limit;                       // Rejected by daily limit
        int max_orders;                        // Rejected by max orders
        int max_exposure;                      // Rejected by exposure
        int lot_size;                          // Rejected by lot size
        int other;                             // Other rejections
    } m_rejection_stats;
    
    //--- Helper methods
    double            CalculateCurrentExposure(void);
    int               CountOpenPositions(void);
    bool              ValidateLotSize(double lot);
    
public:
    //--- Constructor/Destructor
                     CRiskGuardian(void);
                    ~CRiskGuardian(void);
    
    //--- Initialization
    bool              Initialize(int max_orders = 5,
                                double max_risk = 2.0,
                                double max_exposure = 15.0,
                                double daily_limit = 4.0);
    void              Shutdown(void);
    
    //--- Main validation methods
    bool              ValidateNewTrade(string symbol,
                                      double entry_price,
                                      double stop_loss,
                                      double &lot_size);
    
    bool              CanOpenNewPosition(void);
    bool              CheckDailyLimit(void);
    bool              CheckExposure(double additional_lot);
    
    //--- Position sizing
    double            CalculateSafeLotSize(string symbol,
                                          double entry_price,
                                          double stop_loss,
                                          double risk_pct = 0);
    
    //--- Trade updates
    void              OnTradeOpened(ulong ticket, double lot);
    void              OnTradeClosed(ulong ticket, double profit);
    
    //--- Getters
    bool              IsInitialized(void) const { return m_is_initialized; }
    int               GetMaxOrders(void) const { return m_max_orders; }
    double            GetMaxRisk(void) const { return m_max_risk_percent; }
    double            GetMaxExposure(void) const { return m_max_exposure_percent; }
    int               GetValidationCount(void) const { return m_validation_count; }
    int               GetRejectionsCount(void) const { return m_rejections_count; }
    
    CPositionSizingManager* GetPositionSizing(void) { return m_position_sizing; }
    CDailyLossLimit*  GetDailyLimit(void) { return m_daily_limit; }
    
    //--- Setters
    void              SetMaxOrders(int max) { m_max_orders = max; }
    void              SetMaxRisk(double risk) { m_max_risk_percent = risk; }
    void              SetMaxExposure(double exp) { m_max_exposure_percent = exp; }
    
    //--- Display
    void              PrintInfo(void);
    void              PrintRejectionStats(void);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CRiskGuardian::CRiskGuardian(void) :
    m_max_orders(5),
    m_max_risk_percent(2.0),
    m_max_exposure_percent(15.0),
    m_position_sizing(NULL),
    m_daily_limit(NULL),
    m_is_initialized(false),
    m_last_check_time(0),
    m_validation_count(0),
    m_rejections_count(0)
{
    // Initialize stats
    m_rejection_stats.daily_limit = 0;
    m_rejection_stats.max_orders = 0;
    m_rejection_stats.max_exposure = 0;
    m_rejection_stats.lot_size = 0;
    m_rejection_stats.other = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CRiskGuardian::~CRiskGuardian(void)
{
    Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CRiskGuardian::Initialize(int max_orders=5,
                               double max_risk=2.0,
                               double max_exposure=15.0,
                               double daily_limit=4.0)
{
    Print("🛡️ Initializing Risk Guardian...");
    
    // Set parameters
    m_max_orders = max_orders;
    m_max_risk_percent = max_risk;
    m_max_exposure_percent = max_exposure;
    
    // Create Position Sizing Manager
    m_position_sizing = new CPositionSizingManager();
    if(m_position_sizing == NULL)
    {
        Print("❌ Failed to create Position Sizing Manager");
        return false;
    }
    
    if(!m_position_sizing.Initialize(_Symbol, 1.0, true))
    {
        Print("❌ Failed to initialize Position Sizing Manager");
        delete m_position_sizing;
        m_position_sizing = NULL;
        return false;
    }
    
    // Create Daily Loss Limit
    m_daily_limit = new CDailyLossLimit();
    if(m_daily_limit == NULL)
    {
        Print("❌ Failed to create Daily Loss Limit");
        delete m_position_sizing;
        m_position_sizing = NULL;
        return false;
    }
    
    if(!m_daily_limit.Initialize(daily_limit))
    {
        Print("❌ Failed to initialize Daily Loss Limit");
        delete m_position_sizing;
        delete m_daily_limit;
        m_position_sizing = NULL;
        m_daily_limit = NULL;
        return false;
    }
    
    m_is_initialized = true;
    m_last_check_time = TimeCurrent();
    
    Print("✅ Risk Guardian initialized successfully");
    Print("   Max Orders: ", m_max_orders);
    Print("   Max Risk: ", m_max_risk_percent, "%");
    Print("   Max Exposure: ", m_max_exposure_percent, "%");
    Print("   Daily Limit: ", daily_limit, "%");
    
    return true;
}

//+------------------------------------------------------------------+
//| Shutdown                                                          |
//+------------------------------------------------------------------+
void CRiskGuardian::Shutdown(void)
{
    if(m_position_sizing != NULL)
    {
        delete m_position_sizing;
        m_position_sizing = NULL;
    }
    
    if(m_daily_limit != NULL)
    {
        delete m_daily_limit;
        m_daily_limit = NULL;
    }
    
    m_is_initialized = false;
}

//+------------------------------------------------------------------+
//| Validate New Trade                                               |
//| Main entry point for all trade validation                       |
//+------------------------------------------------------------------+
bool CRiskGuardian::ValidateNewTrade(string symbol,
                                     double entry_price,
                                     double stop_loss,
                                     double &lot_size)
{
    m_validation_count++;
    m_last_check_time = TimeCurrent();
    
    if(!m_is_initialized)
    {
        Print("❌ Risk Guardian not initialized");
        m_rejections_count++;
        m_rejection_stats.other++;
        return false;
    }
    
    // Check 1: Daily Loss Limit
    if(m_daily_limit.IsDailyLimitReached())
    {
        Print("❌ Trade rejected: Daily loss limit reached");
        m_rejections_count++;
        m_rejection_stats.daily_limit++;
        return false;
    }
    
    // Check 2: Max Orders
    if(!CanOpenNewPosition())
    {
        Print("❌ Trade rejected: Max orders reached (", m_max_orders, ")");
        m_rejections_count++;
        m_rejection_stats.max_orders++;
        return false;
    }
    
    // Check 3: Determine Final Lot Size
    double final_lot;
    
    // 🎯 SPIKE STRATEGY: Use lot from Python (if provided)
    // 📊 GRID STRATEGY: Calculate based on risk (standalone)
    if(lot_size > 0)
    {
        // Lot provided by Python (Spike Strategy)
        Print("🎯 Using lot size from policy: ", DoubleToString(lot_size, 2));
        final_lot = lot_size;
        
        // Validate it's within broker limits
        if(!m_position_sizing.ValidateLotSize(final_lot))
        {
            // Normalize to broker requirements
            final_lot = m_position_sizing.NormalizeLotSize(final_lot);
            Print("   Normalized to: ", DoubleToString(final_lot, 2));
        }
    }
    else
    {
        // No lot provided - calculate based on risk (Grid/Standalone)
        Print("📊 Calculating lot size based on risk...");
        final_lot = CalculateSafeLotSize(symbol, entry_price, stop_loss);
        
        if(final_lot <= 0)
        {
            Print("❌ Trade rejected: Invalid lot size calculation");
            m_rejections_count++;
            m_rejection_stats.lot_size++;
            return false;
        }
        Print("   Calculated lot: ", DoubleToString(final_lot, 2));
    }
    
    // Check 4: Exposure Limit
    if(!CheckExposure(final_lot))
    {
        Print("❌ Trade rejected: Exposure limit exceeded");
        m_rejections_count++;
        m_rejection_stats.max_exposure++;
        return false;
    }
    
    // All checks passed
    lot_size = final_lot;
    
    Print("✅ Trade validated");
    Print("   Symbol: ", symbol);
    Print("   Lot Size: ", DoubleToString(lot_size, 2));
    Print("   Entry: ", entry_price);
    Print("   SL: ", stop_loss);
    
    return true;
}

//+------------------------------------------------------------------+
//| Can Open New Position                                            |
//+------------------------------------------------------------------+
bool CRiskGuardian::CanOpenNewPosition(void)
{
    int open_positions = CountOpenPositions();
    return (open_positions < m_max_orders);
}

//+------------------------------------------------------------------+
//| Check Daily Limit                                                |
//+------------------------------------------------------------------+
bool CRiskGuardian::CheckDailyLimit(void)
{
    if(m_daily_limit == NULL)
        return true;
    
    return !m_daily_limit.IsDailyLimitReached();
}

//+------------------------------------------------------------------+
//| Check Exposure                                                    |
//+------------------------------------------------------------------+
bool CRiskGuardian::CheckExposure(double additional_lot)
{
    double current_exposure = CalculateCurrentExposure();
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance <= 0)
        return false;
    
    // Calculate exposure percentage
    double current_pct = (current_exposure / balance) * 100.0;
    
    // Estimate additional exposure (rough calculation)
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double additional_exposure = additional_lot * tick_value * 100;  // Rough estimate
    double additional_pct = (additional_exposure / balance) * 100.0;
    
    double total_pct = current_pct + additional_pct;
    
    if(total_pct > m_max_exposure_percent)
    {
        Print("⚠️ Exposure check:");
        Print("   Current: ", DoubleToString(current_pct, 2), "%");
        Print("   Additional: ", DoubleToString(additional_pct, 2), "%");
        Print("   Total: ", DoubleToString(total_pct, 2), "%");
        Print("   Limit: ", m_max_exposure_percent, "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Safe Lot Size                                          |
//+------------------------------------------------------------------+
double CRiskGuardian::CalculateSafeLotSize(string symbol,
                                           double entry_price,
                                           double stop_loss,
                                           double risk_pct=0)
{
    if(m_position_sizing == NULL)
        return 0;
    
    // Use default risk if not specified
    if(risk_pct <= 0)
        risk_pct = 1.0;  // Default 1%
    
    // Clamp to max risk
    if(risk_pct > m_max_risk_percent)
        risk_pct = m_max_risk_percent;
    
    // Calculate lot size
    double lot = m_position_sizing.CalculateLotSize(entry_price, stop_loss, risk_pct);
    
    return lot;
}

//+------------------------------------------------------------------+
//| Calculate Current Exposure                                       |
//+------------------------------------------------------------------+
double CRiskGuardian::CalculateCurrentExposure(void)
{
    double total_exposure = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            double lots = PositionGetDouble(POSITION_VOLUME);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            // Simple exposure calculation
            total_exposure += lots * open_price;
        }
    }
    
    return total_exposure;
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CRiskGuardian::CountOpenPositions(void)
{
    return PositionsTotal();
}

//+------------------------------------------------------------------+
//| Validate Lot Size                                                |
//+------------------------------------------------------------------+
bool CRiskGuardian::ValidateLotSize(double lot)
{
    if(m_position_sizing == NULL)
        return false;
    
    return m_position_sizing.ValidateLotSize(lot);
}

//+------------------------------------------------------------------+
//| On Trade Opened                                                   |
//+------------------------------------------------------------------+
void CRiskGuardian::OnTradeOpened(ulong ticket, double lot)
{
    Print("📊 Trade Opened: #", ticket, " Lot: ", DoubleToString(lot, 2));
    
    // Update daily limit check
    if(m_daily_limit != NULL)
        m_daily_limit.CheckAndUpdateLimit();
}

//+------------------------------------------------------------------+
//| On Trade Closed                                                   |
//+------------------------------------------------------------------+
void CRiskGuardian::OnTradeClosed(ulong ticket, double profit)
{
    Print("📊 Trade Closed: #", ticket, " P&L: $", DoubleToString(profit, 2));
    
    // Update daily loss limit
    if(m_daily_limit != NULL)
    {
        bool is_win = (profit > 0);
        m_daily_limit.UpdateTrade(profit, is_win);
    }
}

//+------------------------------------------------------------------+
//| Print Information                                                 |
//+------------------------------------------------------------------+
void CRiskGuardian::PrintInfo(void)
{
    Print("=== RISK GUARDIAN STATUS ===");
    Print("Status: ", (m_is_initialized ? "ACTIVE" : "INACTIVE"));
    Print("Config: Orders=", m_max_orders, " Risk=", m_max_risk_percent, "% Exp=", m_max_exposure_percent, "%");
    Print("Positions: ", CountOpenPositions(), "/", m_max_orders);
    double exp_pct = (CalculateCurrentExposure() / AccountInfoDouble(ACCOUNT_BALANCE)) * 100.0;
    Print("Exposure: ", DoubleToString(exp_pct, 2), "%");
    Print("Validations: ", m_validation_count, " Rejections: ", m_rejections_count);
    if(m_validation_count > 0)
        Print("Rejection Rate: ", DoubleToString(((double)m_rejections_count / m_validation_count) * 100.0, 1), "%");
    Print("Components: PosSizing=", (m_position_sizing != NULL ? "OK" : "FAIL"), 
          " DailyLimit=", (m_daily_limit != NULL ? "OK" : "FAIL"));
    Print("============================");
}

//+------------------------------------------------------------------+
//| Print Rejection Statistics                                        |
//+------------------------------------------------------------------+
void CRiskGuardian::PrintRejectionStats(void)
{
    Print("=== REJECTION STATISTICS ===");
    Print("Total: ", m_rejections_count);
    if(m_rejections_count > 0)
    {
        Print("Daily Limit: ", m_rejection_stats.daily_limit, " (", DoubleToString((double)m_rejection_stats.daily_limit / m_rejections_count * 100.0, 1), "%)");
        Print("Max Orders: ", m_rejection_stats.max_orders, " (", DoubleToString((double)m_rejection_stats.max_orders / m_rejections_count * 100.0, 1), "%)");
        Print("Max Exposure: ", m_rejection_stats.max_exposure, " (", DoubleToString((double)m_rejection_stats.max_exposure / m_rejections_count * 100.0, 1), "%)");
        Print("Lot Size: ", m_rejection_stats.lot_size, " (", DoubleToString((double)m_rejection_stats.lot_size / m_rejections_count * 100.0, 1), "%)");
        Print("Other: ", m_rejection_stats.other, " (", DoubleToString((double)m_rejection_stats.other / m_rejections_count * 100.0, 1), "%)");
    }
    Print("============================");
}

//+------------------------------------------------------------------+
