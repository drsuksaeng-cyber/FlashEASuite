//+------------------------------------------------------------------+
//|                          Grid/GridRiskRewardAnalyzer.mqh         |
//|                                    FlashEASuite V2 - Week 6      |
//|            Risk/Reward Analysis (Drawdown vs Profit)             |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Risk/Reward Metrics Structure                                    |
//+------------------------------------------------------------------+
struct RiskRewardMetrics
{
    double   total_profit;
    double   total_loss;
    double   net_profit;
    
    double   max_drawdown_pct;
    double   max_drawdown_amount;
    double   avg_drawdown_pct;
    
    double   profit_factor;        // Total Profit / Total Loss
    double   risk_reward_ratio;    // Net Profit / Max Drawdown
    double   return_to_dd_ratio;   // Return% / Max DD%
    
    int      winning_trades;
    int      losing_trades;
    double   win_rate_pct;
    
    double   avg_win;
    double   avg_loss;
    double   largest_win;
    double   largest_loss;
    
    bool     is_acceptable;        // Overall verdict
};

//+------------------------------------------------------------------+
//| Grid Risk/Reward Analyzer Class                                  |
//+------------------------------------------------------------------+
class CGridRiskRewardAnalyzer
{
private:
    // Profit tracking
    double   m_total_profit;
    double   m_total_loss;
    int      m_winning_trades;
    int      m_losing_trades;
    double   m_largest_win;
    double   m_largest_loss;
    
    // Drawdown tracking
    double   m_initial_balance;
    double   m_peak_balance;
    double   m_current_balance;
    double   m_max_drawdown_pct;
    double   m_max_drawdown_amount;
    
    double   m_drawdown_history[];
    int      m_dd_count;
    
    // Acceptable limits
    double   m_max_acceptable_dd_pct;      // Default: 25%
    double   m_min_profit_factor;          // Default: 1.5
    double   m_min_risk_reward_ratio;      // Default: 2.0
    double   m_min_win_rate_pct;           // Default: 50%
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridRiskRewardAnalyzer()
    {
        m_total_profit = 0;
        m_total_loss = 0;
        m_winning_trades = 0;
        m_losing_trades = 0;
        m_largest_win = 0;
        m_largest_loss = 0;
        
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_peak_balance = m_initial_balance;
        m_current_balance = m_initial_balance;
        m_max_drawdown_pct = 0;
        m_max_drawdown_amount = 0;
        
        m_dd_count = 0;
        ArrayResize(m_drawdown_history, 0);
        
        m_max_acceptable_dd_pct = 25.0;
        m_min_profit_factor = 1.5;
        m_min_risk_reward_ratio = 2.0;
        m_min_win_rate_pct = 50.0;
    }
    
    //+------------------------------------------------------------------+
    //| Update After Trade                                              |
    //+------------------------------------------------------------------+
    void UpdateAfterTrade(double profit)
    {
        if(profit > 0)
        {
            m_total_profit += profit;
            m_winning_trades++;
            
            if(profit > m_largest_win)
                m_largest_win = profit;
        }
        else if(profit < 0)
        {
            m_total_loss += MathAbs(profit);
            m_losing_trades++;
            
            if(MathAbs(profit) > m_largest_loss)
                m_largest_loss = MathAbs(profit);
        }
        
        // Update balance
        m_current_balance += profit;
        
        // Update peak
        if(m_current_balance > m_peak_balance)
        {
            m_peak_balance = m_current_balance;
        }
        
        // Update drawdown
        UpdateDrawdown();
    }
    
    //+------------------------------------------------------------------+
    //| Update Drawdown                                                 |
    //+------------------------------------------------------------------+
    void UpdateDrawdown()
    {
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Calculate drawdown from peak
        double drawdown_amount = m_peak_balance - current_equity;
        double drawdown_pct = (drawdown_amount / m_peak_balance) * 100.0;
        
        if(drawdown_pct > m_max_drawdown_pct)
        {
            m_max_drawdown_pct = drawdown_pct;
            m_max_drawdown_amount = drawdown_amount;
        }
        
        // Record in history
        m_dd_count++;
        ArrayResize(m_drawdown_history, m_dd_count);
        m_drawdown_history[m_dd_count - 1] = drawdown_pct;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate All Metrics                                           |
    //+------------------------------------------------------------------+
    RiskRewardMetrics CalculateMetrics()
    {
        RiskRewardMetrics metrics;
        
        // Profit metrics
        metrics.total_profit = m_total_profit;
        metrics.total_loss = m_total_loss;
        metrics.net_profit = m_total_profit - m_total_loss;
        
        // Drawdown metrics
        metrics.max_drawdown_pct = m_max_drawdown_pct;
        metrics.max_drawdown_amount = m_max_drawdown_amount;
        metrics.avg_drawdown_pct = CalculateAvgDrawdown();
        
        // Profit factor
        if(m_total_loss > 0)
        {
            metrics.profit_factor = m_total_profit / m_total_loss;
        }
        else
        {
            metrics.profit_factor = (m_total_profit > 0) ? 999.0 : 0.0;
        }
        
        // Risk/Reward ratio
        if(m_max_drawdown_amount > 0)
        {
            metrics.risk_reward_ratio = metrics.net_profit / m_max_drawdown_amount;
        }
        else
        {
            metrics.risk_reward_ratio = (metrics.net_profit > 0) ? 999.0 : 0.0;
        }
        
        // Return to DD ratio
        double return_pct = ((m_current_balance - m_initial_balance) / m_initial_balance) * 100.0;
        if(m_max_drawdown_pct > 0)
        {
            metrics.return_to_dd_ratio = return_pct / m_max_drawdown_pct;
        }
        else
        {
            metrics.return_to_dd_ratio = (return_pct > 0) ? 999.0 : 0.0;
        }
        
        // Trade statistics
        metrics.winning_trades = m_winning_trades;
        metrics.losing_trades = m_losing_trades;
        
        int total_trades = m_winning_trades + m_losing_trades;
        if(total_trades > 0)
        {
            metrics.win_rate_pct = ((double)m_winning_trades / total_trades) * 100.0;
        }
        else
        {
            metrics.win_rate_pct = 0;
        }
        
        // Average win/loss
        if(m_winning_trades > 0)
            metrics.avg_win = m_total_profit / m_winning_trades;
        else
            metrics.avg_win = 0;
        
        if(m_losing_trades > 0)
            metrics.avg_loss = m_total_loss / m_losing_trades;
        else
            metrics.avg_loss = 0;
        
        metrics.largest_win = m_largest_win;
        metrics.largest_loss = m_largest_loss;
        
        // Overall evaluation
        metrics.is_acceptable = IsAcceptable(metrics);
        
        return metrics;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Average Drawdown                                      |
    //+------------------------------------------------------------------+
    double CalculateAvgDrawdown()
    {
        if(m_dd_count == 0) return 0;
        
        double sum = 0;
        for(int i = 0; i < m_dd_count; i++)
        {
            sum += m_drawdown_history[i];
        }
        
        return sum / m_dd_count;
    }
    
    //+------------------------------------------------------------------+
    //| Check if Metrics are Acceptable                                 |
    //+------------------------------------------------------------------+
    bool IsAcceptable(const RiskRewardMetrics &metrics)
    {
        bool dd_ok = (metrics.max_drawdown_pct <= m_max_acceptable_dd_pct);
        bool pf_ok = (metrics.profit_factor >= m_min_profit_factor);
        bool rr_ok = (metrics.risk_reward_ratio >= m_min_risk_reward_ratio);
        bool wr_ok = (metrics.win_rate_pct >= m_min_win_rate_pct);
        
        return (dd_ok && pf_ok && rr_ok && wr_ok);
    }
    
    //+------------------------------------------------------------------+
    //| Print Risk/Reward Report                                        |
    //+------------------------------------------------------------------+
    void PrintRiskRewardReport()
    {
        RiskRewardMetrics metrics = CalculateMetrics();
        
        Print("═══════════════════════════════════════════");
        Print("⚖️  RISK/REWARD ANALYSIS REPORT");
        Print("═══════════════════════════════════════════");
        
        // Profit Summary
        Print("PROFIT SUMMARY:");
        Print("  Total Profit: +$", DoubleToString(metrics.total_profit, 2));
        Print("  Total Loss: -$", DoubleToString(metrics.total_loss, 2));
        Print("  Net Profit: $", DoubleToString(metrics.net_profit, 2));
        Print("  ─────────────────────");
        Print("  Largest Win: +$", DoubleToString(metrics.largest_win, 2));
        Print("  Largest Loss: -$", DoubleToString(metrics.largest_loss, 2));
        
        Print("───────────────────────────────────────────");
        
        // Drawdown Summary
        Print("DRAWDOWN SUMMARY:");
        Print("  Max Drawdown: ", DoubleToString(metrics.max_drawdown_pct, 2), "%");
        Print("  Max DD Amount: $", DoubleToString(metrics.max_drawdown_amount, 2));
        Print("  Avg Drawdown: ", DoubleToString(metrics.avg_drawdown_pct, 2), "%");
        
        // Drawdown evaluation
        string dd_verdict = "";
        if(metrics.max_drawdown_pct <= 15)
            dd_verdict = "✅ EXCELLENT - Very safe";
        else if(metrics.max_drawdown_pct <= 25)
            dd_verdict = "✅ GOOD - Acceptable";
        else if(metrics.max_drawdown_pct <= 35)
            dd_verdict = "⚠️ FAIR - High risk";
        else
            dd_verdict = "❌ POOR - Dangerous!";
        
        Print("  Verdict: ", dd_verdict);
        
        Print("───────────────────────────────────────────");
        
        // Key Ratios
        Print("KEY RATIOS:");
        Print("  Profit Factor: ", DoubleToString(metrics.profit_factor, 2));
        
        string pf_verdict = "";
        if(metrics.profit_factor >= 2.0)
            pf_verdict = "✅ EXCELLENT";
        else if(metrics.profit_factor >= 1.5)
            pf_verdict = "✅ GOOD";
        else if(metrics.profit_factor >= 1.2)
            pf_verdict = "⚠️ FAIR";
        else
            pf_verdict = "❌ POOR";
        Print("    ", pf_verdict);
        
        Print("  Risk/Reward Ratio: ", DoubleToString(metrics.risk_reward_ratio, 2));
        
        string rr_verdict = "";
        if(metrics.risk_reward_ratio >= 3.0)
            rr_verdict = "✅ EXCELLENT";
        else if(metrics.risk_reward_ratio >= 2.0)
            rr_verdict = "✅ GOOD";
        else if(metrics.risk_reward_ratio >= 1.5)
            rr_verdict = "⚠️ FAIR";
        else
            rr_verdict = "❌ POOR";
        Print("    ", rr_verdict);
        
        Print("  Return/DD Ratio: ", DoubleToString(metrics.return_to_dd_ratio, 2));
        
        Print("───────────────────────────────────────────");
        
        // Trade Statistics
        Print("TRADE STATISTICS:");
        Print("  Total Trades: ", metrics.winning_trades + metrics.losing_trades);
        Print("  Winning: ", metrics.winning_trades, " (", 
              DoubleToString(metrics.win_rate_pct, 1), "%)");
        Print("  Losing: ", metrics.losing_trades, " (", 
              DoubleToString(100 - metrics.win_rate_pct, 1), "%)");
        Print("  ─────────────────────");
        Print("  Avg Win: +$", DoubleToString(metrics.avg_win, 2));
        Print("  Avg Loss: -$", DoubleToString(metrics.avg_loss, 2));
        
        if(metrics.avg_loss > 0)
        {
            double avg_wr = metrics.avg_win / metrics.avg_loss;
            Print("  Avg W/L Ratio: ", DoubleToString(avg_wr, 2));
        }
        
        Print("───────────────────────────────────────────");
        
        // Overall Verdict
        Print("OVERALL VERDICT:");
        
        if(metrics.is_acceptable)
        {
            Print("  ✅ ACCEPTABLE FOR TRADING");
            Print("  All metrics within limits:");
            Print("    ✅ Drawdown ≤ ", m_max_acceptable_dd_pct, "%");
            Print("    ✅ Profit Factor ≥ ", DoubleToString(m_min_profit_factor, 1));
            Print("    ✅ Risk/Reward ≥ ", DoubleToString(m_min_risk_reward_ratio, 1));
            Print("    ✅ Win Rate ≥ ", m_min_win_rate_pct, "%");
        }
        else
        {
            Print("  ❌ NOT ACCEPTABLE - NEEDS IMPROVEMENT");
            Print("  Issues detected:");
            
            if(metrics.max_drawdown_pct > m_max_acceptable_dd_pct)
                Print("    ❌ Drawdown too high: ", DoubleToString(metrics.max_drawdown_pct, 2), 
                      "% > ", m_max_acceptable_dd_pct, "%");
            
            if(metrics.profit_factor < m_min_profit_factor)
                Print("    ❌ Profit Factor too low: ", DoubleToString(metrics.profit_factor, 2),
                      " < ", DoubleToString(m_min_profit_factor, 1));
            
            if(metrics.risk_reward_ratio < m_min_risk_reward_ratio)
                Print("    ❌ Risk/Reward too low: ", DoubleToString(metrics.risk_reward_ratio, 2),
                      " < ", DoubleToString(m_min_risk_reward_ratio, 1));
            
            if(metrics.win_rate_pct < m_min_win_rate_pct)
                Print("    ❌ Win Rate too low: ", DoubleToString(metrics.win_rate_pct, 1),
                      "% < ", m_min_win_rate_pct, "%");
        }
        
        Print("═══════════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Get Current Metrics                                             |
    //+------------------------------------------------------------------+
    RiskRewardMetrics GetMetrics() { return CalculateMetrics(); }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetMaxDrawdownPct() { return m_max_drawdown_pct; }
    double GetProfitFactor() 
    { 
        return (m_total_loss > 0) ? (m_total_profit / m_total_loss) : 0; 
    }
    double GetWinRate() 
    { 
        int total = m_winning_trades + m_losing_trades;
        return (total > 0) ? ((double)m_winning_trades / total * 100.0) : 0; 
    }
    
    //+------------------------------------------------------------------+
    //| Setters (Configuration)                                         |
    //+------------------------------------------------------------------+
    void SetMaxAcceptableDD(double pct) { m_max_acceptable_dd_pct = pct; }
    void SetMinProfitFactor(double factor) { m_min_profit_factor = factor; }
    void SetMinRiskReward(double ratio) { m_min_risk_reward_ratio = ratio; }
    void SetMinWinRate(double pct) { m_min_win_rate_pct = pct; }
};

//+------------------------------------------------------------------+
