//+------------------------------------------------------------------+
//|                              Grid/GridRecoveryTracker.mqh        |
//|                                    FlashEASuite V2 - Week 6      |
//|              Recovery Factor Tracking (การคืนชีพ)                |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Drawdown Event Structure                                         |
//+------------------------------------------------------------------+
struct DrawdownEvent
{
    datetime start_time;          // เริ่มติดลบ
    datetime end_time;            // กลับมาบวก
    double   max_drawdown_pct;    // Drawdown สูงสุด (%)
    double   max_floating_loss;   // Floating loss สูงสุด ($)
    int      duration_hours;      // ระยะเวลาติดลบ (ชั่วโมง)
    int      duration_days;       // ระยะเวลาติดลบ (วัน)
    bool     recovered;           // กลับมาบวกแล้วหรือยัง
    int      trades_to_recover;   // จำนวน trade ที่ใช้ recover
};

//+------------------------------------------------------------------+
//| Grid Recovery Tracker Class                                      |
//+------------------------------------------------------------------+
class CGridRecoveryTracker
{
private:
    // Current drawdown tracking
    bool     m_in_drawdown;
    datetime m_drawdown_start;
    double   m_peak_balance;
    double   m_max_floating_loss;
    double   m_max_drawdown_pct;
    int      m_trades_since_drawdown;
    
    // Historical drawdown events
    DrawdownEvent m_events[];
    int      m_event_count;
    
    // Recovery statistics
    double   m_avg_recovery_time_hours;
    double   m_avg_recovery_time_days;
    double   m_fastest_recovery_hours;
    double   m_slowest_recovery_hours;
    double   m_total_drawdown_time_hours;
    
    // Recovery factor (profit / max drawdown)
    double   m_recovery_factor;
    
    // Acceptable limits
    int      m_max_acceptable_recovery_days;  // Default: 7 days
    double   m_min_recovery_factor;           // Default: 2.0
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridRecoveryTracker()
    {
        m_in_drawdown = false;
        m_drawdown_start = 0;
        m_peak_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_max_floating_loss = 0;
        m_max_drawdown_pct = 0;
        m_trades_since_drawdown = 0;
        
        m_event_count = 0;
        ArrayResize(m_events, 0);
        
        m_avg_recovery_time_hours = 0;
        m_avg_recovery_time_days = 0;
        m_fastest_recovery_hours = DBL_MAX;
        m_slowest_recovery_hours = 0;
        m_total_drawdown_time_hours = 0;
        
        m_recovery_factor = 0;
        
        m_max_acceptable_recovery_days = 7;
        m_min_recovery_factor = 2.0;
    }
    
    //+------------------------------------------------------------------+
    //| Update Tracking (Call every tick/timer)                         |
    //+------------------------------------------------------------------+
    void Update()
    {
        double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Update peak balance
        if(current_balance > m_peak_balance)
        {
            m_peak_balance = current_balance;
        }
        
        // Calculate floating P&L
        double floating_pl = current_equity - current_balance;
        
        // Check if in drawdown (equity < balance)
        bool currently_in_loss = (floating_pl < 0);
        
        if(currently_in_loss)
        {
            if(!m_in_drawdown)
            {
                // Start new drawdown event
                StartDrawdownEvent();
            }
            
            // Update current drawdown metrics
            UpdateDrawdownMetrics(floating_pl, current_equity);
        }
        else
        {
            if(m_in_drawdown)
            {
                // End drawdown event
                EndDrawdownEvent();
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| Start Drawdown Event                                            |
    //+------------------------------------------------------------------+
    void StartDrawdownEvent()
    {
        m_in_drawdown = true;
        m_drawdown_start = TimeCurrent();
        m_max_floating_loss = 0;
        m_max_drawdown_pct = 0;
        m_trades_since_drawdown = 0;
        
        Print("📉 Drawdown started at: ", TimeToString(m_drawdown_start));
    }
    
    //+------------------------------------------------------------------+
    //| Update Drawdown Metrics                                         |
    //+------------------------------------------------------------------+
    void UpdateDrawdownMetrics(double floating_pl, double equity)
    {
        // Update max floating loss
        if(floating_pl < m_max_floating_loss)
        {
            m_max_floating_loss = floating_pl;
        }
        
        // Calculate drawdown percentage
        double drawdown = m_peak_balance - equity;
        double drawdown_pct = (drawdown / m_peak_balance) * 100.0;
        
        if(drawdown_pct > m_max_drawdown_pct)
        {
            m_max_drawdown_pct = drawdown_pct;
        }
    }
    
    //+------------------------------------------------------------------+
    //| End Drawdown Event                                              |
    //+------------------------------------------------------------------+
    void EndDrawdownEvent()
    {
        datetime end_time = TimeCurrent();
        int duration_seconds = (int)(end_time - m_drawdown_start);
        int duration_hours = duration_seconds / 3600;
        int duration_days = duration_hours / 24;
        
        // Create event record
        m_event_count++;
        ArrayResize(m_events, m_event_count);
        
        int idx = m_event_count - 1;
        m_events[idx].start_time = m_drawdown_start;
        m_events[idx].end_time = end_time;
        m_events[idx].max_drawdown_pct = m_max_drawdown_pct;
        m_events[idx].max_floating_loss = m_max_floating_loss;
        m_events[idx].duration_hours = duration_hours;
        m_events[idx].duration_days = duration_days;
        m_events[idx].recovered = true;
        m_events[idx].trades_to_recover = m_trades_since_drawdown;
        
        // Update statistics
        UpdateRecoveryStatistics();
        
        Print("✅ Drawdown recovered!");
        Print("   Duration: ", duration_hours, " hours (", duration_days, " days)");
        Print("   Max Drawdown: ", DoubleToString(m_max_drawdown_pct, 2), "%");
        Print("   Max Loss: $", DoubleToString(m_max_floating_loss, 2));
        Print("   Trades to recover: ", m_trades_since_drawdown);
        
        // Reset tracking
        m_in_drawdown = false;
        m_drawdown_start = 0;
        m_max_floating_loss = 0;
        m_max_drawdown_pct = 0;
        m_trades_since_drawdown = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Update Recovery Statistics                                      |
    //+------------------------------------------------------------------+
    void UpdateRecoveryStatistics()
    {
        if(m_event_count == 0) return;
        
        double total_hours = 0;
        m_fastest_recovery_hours = DBL_MAX;
        m_slowest_recovery_hours = 0;
        
        for(int i = 0; i < m_event_count; i++)
        {
            double hours = m_events[i].duration_hours;
            total_hours += hours;
            
            if(hours < m_fastest_recovery_hours)
                m_fastest_recovery_hours = hours;
            
            if(hours > m_slowest_recovery_hours)
                m_slowest_recovery_hours = hours;
        }
        
        m_avg_recovery_time_hours = total_hours / m_event_count;
        m_avg_recovery_time_days = m_avg_recovery_time_hours / 24.0;
        m_total_drawdown_time_hours = total_hours;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Recovery Factor                                       |
    //+------------------------------------------------------------------+
    void CalculateRecoveryFactor(double total_profit)
    {
        if(m_event_count == 0)
        {
            m_recovery_factor = 0;
            return;
        }
        
        // Find max drawdown across all events
        double max_dd = 0;
        for(int i = 0; i < m_event_count; i++)
        {
            if(MathAbs(m_events[i].max_floating_loss) > max_dd)
                max_dd = MathAbs(m_events[i].max_floating_loss);
        }
        
        // Recovery factor = Total Profit / Max Drawdown
        if(max_dd > 0)
        {
            m_recovery_factor = total_profit / max_dd;
        }
        else
        {
            m_recovery_factor = 0;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Increment Trade Counter                                         |
    //+------------------------------------------------------------------+
    void IncrementTradeCounter()
    {
        if(m_in_drawdown)
        {
            m_trades_since_drawdown++;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Print Recovery Report                                           |
    //+------------------------------------------------------------------+
    void PrintRecoveryReport()
    {
        Print("═══════════════════════════════════════════");
        Print("♻️  RECOVERY FACTOR REPORT");
        Print("═══════════════════════════════════════════");
        Print("Total Drawdown Events: ", m_event_count);
        
        if(m_event_count > 0)
        {
            Print("───────────────────────────────────────────");
            Print("Recovery Time Statistics:");
            Print("  Average: ", DoubleToString(m_avg_recovery_time_hours, 1), " hours (", 
                  DoubleToString(m_avg_recovery_time_days, 1), " days)");
            Print("  Fastest: ", DoubleToString(m_fastest_recovery_hours, 1), " hours");
            Print("  Slowest: ", DoubleToString(m_slowest_recovery_hours, 1), " hours");
            Print("  Total Time in Drawdown: ", DoubleToString(m_total_drawdown_time_hours, 1), " hours");
            Print("───────────────────────────────────────────");
            Print("Recovery Factor: ", DoubleToString(m_recovery_factor, 2));
            Print("  (Profit / Max Drawdown)");
            
            // Evaluation
            string verdict = "";
            if(m_recovery_factor >= 3.0)
                verdict = "✅ EXCELLENT - Quick recovery";
            else if(m_recovery_factor >= 2.0)
                verdict = "✅ GOOD - Acceptable recovery";
            else if(m_recovery_factor >= 1.5)
                verdict = "⚠️ FAIR - Slow recovery";
            else
                verdict = "❌ POOR - Very slow recovery";
            
            Print("  Verdict: ", verdict);
            
            // Time evaluation
            if(m_avg_recovery_time_days <= 3)
                Print("  Time Verdict: ✅ EXCELLENT - Quick recovery (≤3 days)");
            else if(m_avg_recovery_time_days <= 7)
                Print("  Time Verdict: ✅ GOOD - Acceptable (≤7 days)");
            else if(m_avg_recovery_time_days <= 14)
                Print("  Time Verdict: ⚠️ FAIR - Slow (≤14 days)");
            else
                Print("  Time Verdict: ❌ POOR - Very slow (>14 days)");
        }
        else
        {
            Print("No drawdown events recorded");
        }
        
        if(m_in_drawdown)
        {
            Print("───────────────────────────────────────────");
            Print("⚠️ CURRENTLY IN DRAWDOWN");
            Print("  Duration so far: ", (int)((TimeCurrent() - m_drawdown_start) / 3600), " hours");
            Print("  Max Drawdown: ", DoubleToString(m_max_drawdown_pct, 2), "%");
            Print("  Max Loss: $", DoubleToString(m_max_floating_loss, 2));
        }
        
        Print("═══════════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Get Detailed Event History                                      |
    //+------------------------------------------------------------------+
    void PrintEventHistory()
    {
        if(m_event_count == 0)
        {
            Print("No drawdown events to display");
            return;
        }
        
        Print("═══════════════════════════════════════════");
        Print("📊 DRAWDOWN EVENT HISTORY");
        Print("═══════════════════════════════════════════");
        
        for(int i = 0; i < m_event_count; i++)
        {
            Print("Event #", i + 1);
            Print("  Start: ", TimeToString(m_events[i].start_time));
            Print("  End: ", TimeToString(m_events[i].end_time));
            Print("  Duration: ", m_events[i].duration_hours, " hours (", m_events[i].duration_days, " days)");
            Print("  Max DD: ", DoubleToString(m_events[i].max_drawdown_pct, 2), "%");
            Print("  Max Loss: $", DoubleToString(m_events[i].max_floating_loss, 2));
            Print("  Trades to Recover: ", m_events[i].trades_to_recover);
            Print("───────────────────────────────────────────");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check if Recovery is Acceptable                                 |
    //+------------------------------------------------------------------+
    bool IsRecoveryAcceptable()
    {
        if(m_event_count == 0) return true;
        
        bool time_ok = (m_avg_recovery_time_days <= m_max_acceptable_recovery_days);
        bool factor_ok = (m_recovery_factor >= m_min_recovery_factor);
        
        return (time_ok && factor_ok);
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    bool IsInDrawdown() { return m_in_drawdown; }
    int GetEventCount() { return m_event_count; }
    double GetAvgRecoveryHours() { return m_avg_recovery_time_hours; }
    double GetAvgRecoveryDays() { return m_avg_recovery_time_days; }
    double GetRecoveryFactor() { return m_recovery_factor; }
    double GetMaxDrawdownPct() { return m_max_drawdown_pct; }
    double GetMaxFloatingLoss() { return m_max_floating_loss; }
    
    //+------------------------------------------------------------------+
    //| Setters                                                          |
    //+------------------------------------------------------------------+
    void SetMaxAcceptableRecoveryDays(int days) { m_max_acceptable_recovery_days = days; }
    void SetMinRecoveryFactor(double factor) { m_min_recovery_factor = factor; }
};

//+------------------------------------------------------------------+
