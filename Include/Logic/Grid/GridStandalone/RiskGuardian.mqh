//+------------------------------------------------------------------+
//|                                    GridStandalone/RiskGuardian.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                            Risk Management Module                        |
//+------------------------------------------------------------------+
#property strict

#include "GridExit.mqh"

//+------------------------------------------------------------------+
//| Risk Guardian                                                     |
//+------------------------------------------------------------------+
class CRiskGuardian : public CGridExitEngine
{
protected:
    // Made protected so Strategy_Grid_Standalone can access
    
    // Account monitoring
    double            m_starting_balance;
    double            m_session_start_equity;
    double            m_daily_start_equity;
    
    // Current state
    double            m_current_equity;
    double            m_current_dd;
    double            m_daily_pnl;
    double            m_session_pnl;
    
    // Trading control
    bool              m_trading_paused;
    datetime          m_pause_until;
    datetime          m_daily_reset_time;
    
    // Statistics
    int               m_total_grids_opened;
    int               m_total_grids_closed;
    double            m_total_profit;
    double            m_total_loss;
    int               m_winning_grids;
    int               m_losing_grids;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CRiskGuardian() : CGridExitEngine()
    {
        m_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_session_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        m_current_equity = m_session_start_equity;
        m_current_dd = 0.0;
        m_daily_pnl = 0.0;
        m_session_pnl = 0.0;
        
        m_trading_paused = false;
        m_pause_until = 0;
        m_daily_reset_time = TimeCurrent();
        
        // Statistics
        m_total_grids_opened = 0;
        m_total_grids_closed = 0;
        m_total_profit = 0.0;
        m_total_loss = 0.0;
        m_winning_grids = 0;
        m_losing_grids = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Update Risk Metrics                                              |
    //+------------------------------------------------------------------+
    void UpdateRiskMetrics()
    {
        m_current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Calculate drawdown
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(m_current_equity < balance)
        {
            m_current_dd = ((balance - m_current_equity) / balance) * 100.0;
        }
        else
        {
            m_current_dd = 0.0;
        }
        
        // Calculate daily PnL
        m_daily_pnl = m_current_equity - m_daily_start_equity;
        
        // Calculate session PnL
        m_session_pnl = m_current_equity - m_session_start_equity;
        
        // Check for daily reset
        CheckDailyReset();
    }
    
    //+------------------------------------------------------------------+
    //| Check Daily Reset                                                |
    //+------------------------------------------------------------------+
    void CheckDailyReset()
    {
        datetime current = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(current, dt);
        
        MqlDateTime reset_dt;
        TimeToStruct(m_daily_reset_time, reset_dt);
        
        // Reset at midnight
        if(dt.day != reset_dt.day)
        {
            Print("[Risk] Daily reset - New trading day");
            m_daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            m_daily_pnl = 0.0;
            m_daily_reset_time = current;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check Emergency Exits                                            |
    //+------------------------------------------------------------------+
    bool CheckEmergencyExit()
    {
        UpdateRiskMetrics();
        
        // Emergency 1: Max Drawdown
        if(m_current_dd > m_max_dd_percent)
        {
            Print("[Risk] 🚨 EMERGENCY: MAX DRAWDOWN EXCEEDED!");
            Print("  Current DD: ", DoubleToString(m_current_dd, 2), "%");
            Print("  Limit: ", DoubleToString(m_max_dd_percent, 2), "%");
            
            m_exit_reason = EXIT_MAX_DD;
            EmergencyStop();
            return true;
        }
        
        // Emergency 2: Daily Loss Limit
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double daily_loss_percent = (m_daily_pnl / balance) * 100;
        
        if(daily_loss_percent < -m_daily_loss_limit)
        {
            Print("[Risk] 🚨 EMERGENCY: DAILY LOSS LIMIT!");
            Print("  Daily loss: ", DoubleToString(daily_loss_percent, 2), "%");
            Print("  Limit: -", DoubleToString(m_daily_loss_limit, 2), "%");
            
            m_exit_reason = EXIT_DAILY_LIMIT;
            PauseTrading(24);
            return true;
        }
        
        // Emergency 3: Volatility Spike
        double atr_ratio = m_atr_current / m_atr_reference;
        if(atr_ratio > 3.0)
        {
            Print("[Risk] 🚨 EMERGENCY: VOLATILITY SPIKE!");
            Print("  ATR Ratio: ", DoubleToString(atr_ratio, 2));
            
            m_exit_reason = EXIT_VOLATILITY_SPIKE;
            return true;
        }
        
        // Emergency 4: Spread Widening
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double current_spread = (ask - bid) / _Point;
        double avg_spread = CalculateAverageSpread();
        
        if(current_spread > avg_spread * 5.0)
        {
            Print("[Risk] 🚨 EMERGENCY: SPREAD WIDENING!");
            Print("  Current spread: ", DoubleToString(current_spread, 1));
            Print("  Average: ", DoubleToString(avg_spread, 1));
            
            m_exit_reason = EXIT_SPREAD_WIDENING;
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Pause Trading                                                    |
    //+------------------------------------------------------------------+
    void PauseTrading(int hours)
    {
        m_trading_paused = true;
        m_pause_until = TimeCurrent() + (hours * 3600);
        
        Print("[Risk] ⏸️ Trading paused for ", hours, " hours");
        Print("  Resume at: ", TimeToString(m_pause_until));
    }
    
    //+------------------------------------------------------------------+
    //| Emergency Stop                                                   |
    //+------------------------------------------------------------------+
    void EmergencyStop()
    {
        Print("[Risk] 🛑 EMERGENCY STOP ACTIVATED");
        
        // Pause for 24 hours
        PauseTrading(24);
        
        // Log critical event
        Print("[Risk] System will resume at: ", TimeToString(m_pause_until));
    }
    
    //+------------------------------------------------------------------+
    //| Can Resume Trading                                               |
    //+------------------------------------------------------------------+
    bool CanResume()
    {
        if(!m_trading_paused)
            return true;
        
        datetime current = TimeCurrent();
        if(current >= m_pause_until)
        {
            m_trading_paused = false;
            Print("[Risk] ✅ Trading resumed");
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Is Risk Approved                                                 |
    //+------------------------------------------------------------------+
    bool IsRiskApproved()
    {
        UpdateRiskMetrics();
        
        // Check if trading is paused
        if(m_trading_paused && !CanResume())
        {
            return false;
        }
        
        // Check drawdown warning level
        if(m_current_dd > m_avg_dd_target)
        {
            Print("[Risk] ⚠️ WARNING: Drawdown above target");
            Print("  Current DD: ", DoubleToString(m_current_dd, 2), "%");
            Print("  Target: ", DoubleToString(m_avg_dd_target, 2), "%");
        }
        
        // Check daily loss
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double daily_loss_percent = (m_daily_pnl / balance) * 100;
        
        if(daily_loss_percent < -m_daily_loss_limit)
        {
            Print("[Risk] ❌ Daily loss limit reached");
            PauseTrading(24);
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Record Grid Close                                                |
    //+------------------------------------------------------------------+
    void RecordGridClose(double pnl)
    {
        m_total_grids_closed++;
        
        if(pnl > 0)
        {
            m_winning_grids++;
            m_total_profit += pnl;
        }
        else if(pnl < 0)
        {
            m_losing_grids++;
            m_total_loss += MathAbs(pnl);
        }
        
        Print("[Risk] Grid closed - Total: ", m_total_grids_closed, 
              " W:", m_winning_grids, " L:", m_losing_grids);
    }
    
    //+------------------------------------------------------------------+
    //| Get Statistics                                                   |
    //+------------------------------------------------------------------+
    string GetRiskStatus()
    {
        UpdateRiskMetrics();
        
        string status = "\n";
        status += "═══════════════════════════════════════\n";
        status += "  RISK GUARDIAN STATUS\n";
        status += "═══════════════════════════════════════\n";
        status += StringFormat("Equity: $%.2f\n", m_current_equity);
        status += StringFormat("Current DD: %.2f%% (Target: %.2f%%)\n", 
                             m_current_dd, m_avg_dd_target);
        status += StringFormat("Daily PnL: $%.2f (%.2f%%)\n", 
                             m_daily_pnl, (m_daily_pnl / m_starting_balance) * 100);
        status += StringFormat("Session PnL: $%.2f\n", m_session_pnl);
        status += "───────────────────────────────────────\n";
        status += StringFormat("Grids Opened: %d\n", m_total_grids_opened);
        status += StringFormat("Grids Closed: %d (W:%d L:%d)\n", 
                             m_total_grids_closed, m_winning_grids, m_losing_grids);
        
        if(m_total_grids_closed > 0)
        {
            double win_rate = ((double)m_winning_grids / m_total_grids_closed) * 100;
            status += StringFormat("Win Rate: %.1f%%\n", win_rate);
            
            double profit_factor = (m_total_loss > 0) ? 
                                  (m_total_profit / m_total_loss) : 0;
            status += StringFormat("Profit Factor: %.2f\n", profit_factor);
        }
        
        status += "───────────────────────────────────────\n";
        
        if(m_trading_paused)
        {
            status += "Status: ⏸️ PAUSED\n";
            status += StringFormat("Resume: %s\n", TimeToString(m_pause_until));
        }
        else
        {
            status += "Status: ✅ ACTIVE\n";
        }
        
        status += "═══════════════════════════════════════\n";
        
        return status;
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetCurrentDrawdown() { return m_current_dd; }
    double GetDailyPnL() { return m_daily_pnl; }
    bool IsTradingPaused() { return m_trading_paused; }
    int GetTotalGridsClosed() { return m_total_grids_closed; }
    double GetWinRate() 
    { 
        if(m_total_grids_closed == 0) return 0.0;
        return ((double)m_winning_grids / m_total_grids_closed) * 100;
    }
    double GetProfitFactor()
    {
        if(m_total_loss == 0) return 0.0;
        return m_total_profit / m_total_loss;
    }
};
//+------------------------------------------------------------------+
