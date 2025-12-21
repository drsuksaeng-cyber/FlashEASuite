//+------------------------------------------------------------------+
//|                                    Grid/GridRiskManager.mqh      |
//|                                  FlashEASuite V2 - Week 4        |
//|                      Dynamic Grid Risk Management                 |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Risk Assessment Structure                                        |
//+------------------------------------------------------------------+
struct RiskAssessment
{
    bool              allowed;            // Is trade allowed?
    double            max_lot;            // Maximum lot size
    double            risk_percent;       // Current risk %
    double            exposure_percent;   // Current exposure %
    string            warning;            // Risk warning message
};

//+------------------------------------------------------------------+
//| Class: CGridRiskManager                                          |
//| Manages risk dynamically based on account and market conditions  |
//+------------------------------------------------------------------+
class CGridRiskManager
{
private:
    // Risk Limits
    double            m_max_risk_per_trade;   // 2% per trade
    double            m_max_total_exposure;   // 10% total
    double            m_max_drawdown_percent; // 15% max DD
    double            m_daily_loss_limit;     // 3% daily
    
    // Account tracking
    double            m_initial_balance;      // Starting balance
    double            m_daily_start_balance;  // Balance at day start
    double            m_peak_balance;         // Peak balance (for DD calc)
    datetime          m_last_daily_reset;     // Last daily reset time
    
    // Current state
    double            m_current_exposure;     // Current $ exposed
    double            m_current_drawdown;     // Current DD %
    double            m_daily_pnl;            // Daily P&L
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridRiskManager()
    {
        m_max_risk_per_trade = 2.0;
        m_max_total_exposure = 10.0;
        m_max_drawdown_percent = 15.0;
        m_daily_loss_limit = 3.0;
        
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_daily_start_balance = m_initial_balance;
        m_peak_balance = m_initial_balance;
        m_last_daily_reset = TimeCurrent();
        
        m_current_exposure = 0.0;
        m_current_drawdown = 0.0;
        m_daily_pnl = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize Risk Manager                                         |
    //+------------------------------------------------------------------+
    void Initialize(double max_risk = 2.0, double max_exposure = 10.0, 
                    double max_dd = 15.0, double daily_limit = 3.0)
    {
        m_max_risk_per_trade = max_risk;
        m_max_total_exposure = max_exposure;
        m_max_drawdown_percent = max_dd;
        m_daily_loss_limit = daily_limit;
        
        ResetDaily();
    }
    
    //+------------------------------------------------------------------+
    //| Assess Risk Before Opening Trade                               |
    //+------------------------------------------------------------------+
    RiskAssessment AssessRisk(double proposed_lot, ENUM_ORDER_TYPE type)
    {
        RiskAssessment assessment;
        assessment.allowed = true;
        assessment.max_lot = proposed_lot;
        assessment.risk_percent = 0.0;
        assessment.exposure_percent = 0.0;
        assessment.warning = "";
        
        // Update daily tracking
        CheckDailyReset();
        UpdateExposure();
        UpdateDrawdown();
        
        // Check 1: Daily loss limit
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double daily_loss = m_daily_start_balance - balance;
        double daily_loss_percent = (daily_loss / m_daily_start_balance) * 100.0;
        
        if(daily_loss_percent >= m_daily_loss_limit)
        {
            assessment.allowed = false;
            assessment.warning = StringFormat("Daily loss limit reached: %.2f%%", daily_loss_percent);
            return assessment;
        }
        
        // Check 2: Maximum drawdown
        if(m_current_drawdown >= m_max_drawdown_percent)
        {
            assessment.allowed = false;
            assessment.warning = StringFormat("Max drawdown reached: %.2f%%", m_current_drawdown);
            return assessment;
        }
        
        // Check 3: Total exposure
        double proposed_value = CalculatePositionValue(proposed_lot, type);
        double new_exposure = m_current_exposure + proposed_value;
        double new_exposure_percent = (new_exposure / balance) * 100.0;
        
        assessment.exposure_percent = new_exposure_percent;
        
        if(new_exposure_percent > m_max_total_exposure)
        {
            // Calculate maximum allowed lot
            double max_additional_exposure = (balance * m_max_total_exposure / 100.0) - m_current_exposure;
            assessment.max_lot = CalculateMaxLot(max_additional_exposure, type);
            
            if(assessment.max_lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
                assessment.allowed = false;
                assessment.warning = StringFormat("Max exposure reached: %.2f%%", new_exposure_percent);
                return assessment;
            }
            
            assessment.warning = StringFormat("Lot reduced: %.2f -> %.2f (exposure limit)", 
                                             proposed_lot, assessment.max_lot);
        }
        
        // Check 4: Risk per trade
        double risk_value = CalculateRiskValue(proposed_lot, type);
        double risk_percent = (risk_value / balance) * 100.0;
        assessment.risk_percent = risk_percent;
        
        if(risk_percent > m_max_risk_per_trade)
        {
            assessment.warning = StringFormat("High risk: %.2f%%", risk_percent);
        }
        
        return assessment;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Adaptive Lot Size Based on Risk                      |
    //+------------------------------------------------------------------+
    double CalculateAdaptiveLot(double base_lot, double confidence)
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        
        // Adjust lot based on:
        // 1. Current drawdown (reduce if in DD)
        // 2. Confidence level
        // 3. Recent performance
        
        double dd_factor = 1.0;
        if(m_current_drawdown > 5.0)
        {
            dd_factor = 1.0 - (m_current_drawdown / m_max_drawdown_percent) * 0.5;
        }
        
        double confidence_factor = confidence; // 0.3-1.0
        
        double adaptive_lot = base_lot * dd_factor * confidence_factor;
        
        // Normalize
        double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        adaptive_lot = MathFloor(adaptive_lot / lot_step) * lot_step;
        
        // Safety limits
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        
        if(adaptive_lot < min_lot) adaptive_lot = min_lot;
        if(adaptive_lot > max_lot) adaptive_lot = max_lot;
        
        return adaptive_lot;
    }
    
    //+------------------------------------------------------------------+
    //| Update Risk State                                               |
    //+------------------------------------------------------------------+
    void Update()
    {
        CheckDailyReset();
        UpdateExposure();
        UpdateDrawdown();
    }
    
    //+------------------------------------------------------------------+
    //| Get Risk Statistics                                             |
    //+------------------------------------------------------------------+
    string GetStatistics()
    {
        return StringFormat("Exposure: %.2f%% | DD: %.2f%% | Daily P&L: %.2f%%",
                           (m_current_exposure / AccountInfoDouble(ACCOUNT_BALANCE)) * 100.0,
                           m_current_drawdown,
                           (m_daily_pnl / m_daily_start_balance) * 100.0);
    }

private:
    //+------------------------------------------------------------------+
    //| Check and Reset Daily Limits                                    |
    //+------------------------------------------------------------------+
    void CheckDailyReset()
    {
        MqlDateTime now;
        TimeToStruct(TimeCurrent(), now);
        
        MqlDateTime last;
        TimeToStruct(m_last_daily_reset, last);
        
        // Reset at midnight
        if(now.day != last.day)
        {
            ResetDaily();
        }
    }
    
    //+------------------------------------------------------------------+
    //| Reset Daily Tracking                                            |
    //+------------------------------------------------------------------+
    void ResetDaily()
    {
        m_daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_last_daily_reset = TimeCurrent();
        m_daily_pnl = 0.0;
        
        Print("[RiskMgr] Daily reset | Balance: ", m_daily_start_balance);
    }
    
    //+------------------------------------------------------------------+
    //| Update Current Exposure                                         |
    //+------------------------------------------------------------------+
    void UpdateExposure()
    {
        m_current_exposure = 0.0;
        
        for(int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != 999000) continue;
            
            double volume = PositionGetDouble(POSITION_VOLUME);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            m_current_exposure += volume * open_price * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Update Current Drawdown                                         |
    //+------------------------------------------------------------------+
    void UpdateDrawdown()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Update peak
        if(balance > m_peak_balance)
        {
            m_peak_balance = balance;
        }
        
        // Calculate drawdown from peak
        double dd = m_peak_balance - equity;
        m_current_drawdown = (dd / m_peak_balance) * 100.0;
        
        // Calculate daily P&L
        m_daily_pnl = balance - m_daily_start_balance;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Position Value                                        |
    //+------------------------------------------------------------------+
    double CalculatePositionValue(double lot, ENUM_ORDER_TYPE type)
    {
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
            return 0.0;
            
        double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
        double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        return lot * price * contract_size;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Maximum Lot for Given Exposure                       |
    //+------------------------------------------------------------------+
    double CalculateMaxLot(double max_value, ENUM_ORDER_TYPE type)
    {
        if(max_value <= 0) return 0.0;
        
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
            return 0.0;
            
        double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
        double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        
        return max_value / (price * contract_size);
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Risk Value (simplified - assumes SL)                 |
    //+------------------------------------------------------------------+
    double CalculateRiskValue(double lot, ENUM_ORDER_TYPE type)
    {
        // Simplified: Assume 100 points SL
        double sl_points = 100.0;
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        return lot * (sl_points * _Point / tick_size) * tick_value;
    }
};
//+------------------------------------------------------------------+
