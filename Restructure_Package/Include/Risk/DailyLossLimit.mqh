//+------------------------------------------------------------------+
//|                                            DailyLossLimit.mqh    |
//|                            FlashEASuite V2.1 - Option A          |
//|                                       Risk Management Module      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/your-repo"
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Daily Loss Limit Manager                                         |
//| Purpose: Enforce daily loss limit (4% default)                  |
//| Features:                                                        |
//|   - Track daily P&L                                             |
//|   - Enforce configurable limit (4% default)                     |
//|   - Auto reset on new day                                       |
//|   - Track daily trades and win/loss                            |
//+------------------------------------------------------------------+
class CDailyLossLimit
{
private:
    // Configuration
    double            m_daily_limit_pct;       // Daily loss limit % (4.0)
    double            m_max_daily_loss;        // Max loss amount ($)
    
    // Daily tracking
    datetime          m_current_day;           // Current trading day
    double            m_daily_pnl;             // Today's P&L
    double            m_daily_wins;            // Today's winning amount
    double            m_daily_losses;          // Today's losing amount
    int               m_daily_trades;          // Today's trade count
    int               m_daily_wins_count;      // Today's winning trades
    int               m_daily_losses_count;    // Today's losing trades
    
    // State
    bool              m_is_limit_reached;      // Limit reached today?
    datetime          m_limit_reached_time;    // When limit was reached
    double            m_starting_balance;      // Balance at day start
    
    // Statistics
    int               m_total_limit_hits;      // Total times limit was hit
    datetime          m_last_reset_time;       // Last reset time
    
    //--- Helper methods
    bool              IsNewDay(void);
    void              ResetDaily(void);
    datetime          GetDayStart(void);
    
public:
    //--- Constructor/Destructor
                     CDailyLossLimit(void);
                    ~CDailyLossLimit(void);
    
    //--- Initialization
    bool              Initialize(double daily_limit_pct = 4.0);
    
    //--- Main methods
    bool              IsDailyLimitReached(void);
    bool              CheckAndUpdateLimit(void);
    void              UpdateDailyPnL(double trade_pnl);
    void              UpdateTrade(double pnl, bool is_win);
    
    //--- Daily metrics
    double            CalculateTodayPnL(void);
    double            GetDailyLimitRemaining(void);
    double            GetDailyPnLPercent(void);
    int               GetDailyTradesCount(void) const { return m_daily_trades; }
    int               GetDailyWinsCount(void) const { return m_daily_wins_count; }
    int               GetDailyLossesCount(void) const { return m_daily_losses_count; }
    
    //--- Getters
    double            GetDailyLimit(void) const { return m_daily_limit_pct; }
    double            GetMaxDailyLoss(void) const { return m_max_daily_loss; }
    double            GetDailyPnL(void) const { return m_daily_pnl; }
    double            GetDailyWins(void) const { return m_daily_wins; }
    double            GetDailyLosses(void) const { return m_daily_losses; }
    bool              IsLimitReached(void) const { return m_is_limit_reached; }
    int               GetTotalLimitHits(void) const { return m_total_limit_hits; }
    
    //--- Setters
    void              SetDailyLimit(double limit_pct);
    void              ManualReset(void);
    
    //--- Display
    void              PrintInfo(void);
    void              PrintDailySummary(void);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CDailyLossLimit::CDailyLossLimit(void) :
    m_daily_limit_pct(4.0),
    m_max_daily_loss(0),
    m_current_day(0),
    m_daily_pnl(0),
    m_daily_wins(0),
    m_daily_losses(0),
    m_daily_trades(0),
    m_daily_wins_count(0),
    m_daily_losses_count(0),
    m_is_limit_reached(false),
    m_limit_reached_time(0),
    m_starting_balance(0),
    m_total_limit_hits(0),
    m_last_reset_time(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CDailyLossLimit::~CDailyLossLimit(void)
{
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CDailyLossLimit::Initialize(double daily_limit_pct=4.0)
{
    m_daily_limit_pct = daily_limit_pct;
    m_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    m_max_daily_loss = m_starting_balance * (m_daily_limit_pct / 100.0);
    m_current_day = GetDayStart();
    m_last_reset_time = TimeCurrent();
    
    // Reset daily tracking
    ResetDaily();
    
    Print("✅ Daily Loss Limit initialized");
    Print("   Limit: ", m_daily_limit_pct, "%");
    Print("   Max Loss: $", DoubleToString(m_max_daily_loss, 2));
    Print("   Starting Balance: $", DoubleToString(m_starting_balance, 2));
    
    return true;
}

//+------------------------------------------------------------------+
//| Is Daily Limit Reached                                           |
//+------------------------------------------------------------------+
bool CDailyLossLimit::IsDailyLimitReached(void)
{
    // Check for new day first
    if(IsNewDay())
    {
        ResetDaily();
        return false;
    }
    
    return m_is_limit_reached;
}

//+------------------------------------------------------------------+
//| Check and Update Limit                                           |
//+------------------------------------------------------------------+
bool CDailyLossLimit::CheckAndUpdateLimit(void)
{
    // Check for new day
    if(IsNewDay())
    {
        ResetDaily();
    }
    
    // Already reached?
    if(m_is_limit_reached)
        return true;
    
    // Calculate current P&L
    double current_pnl = CalculateTodayPnL();
    m_daily_pnl = current_pnl;
    
    // Check if limit reached
    if(current_pnl <= -m_max_daily_loss)
    {
        m_is_limit_reached = true;
        m_limit_reached_time = TimeCurrent();
        m_total_limit_hits++;
        
        Print("🚨 DAILY LOSS LIMIT REACHED!");
        Print("   Daily P&L: $", DoubleToString(current_pnl, 2));
        Print("   Limit: $", DoubleToString(-m_max_daily_loss, 2));
        Print("   Time: ", TimeToString(m_limit_reached_time));
        Print("   Trading STOPPED for today!");
        
        return true;
    }
    
    // Check if approaching limit (80%)
    double limit_used_pct = (-current_pnl / m_max_daily_loss) * 100.0;
    if(limit_used_pct >= 80.0)
    {
        Print("⚠️ WARNING: Daily limit ", DoubleToString(limit_used_pct, 1), "% used");
        Print("   P&L: $", DoubleToString(current_pnl, 2), 
              " / $", DoubleToString(-m_max_daily_loss, 2));
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update Daily P&L                                                  |
//+------------------------------------------------------------------+
void CDailyLossLimit::UpdateDailyPnL(double trade_pnl)
{
    // Check for new day
    if(IsNewDay())
    {
        ResetDaily();
    }
    
    m_daily_pnl += trade_pnl;
    
    if(trade_pnl > 0)
    {
        m_daily_wins += trade_pnl;
        m_daily_wins_count++;
    }
    else
    {
        m_daily_losses += trade_pnl;  // Already negative
        m_daily_losses_count++;
    }
    
    m_daily_trades++;
}

//+------------------------------------------------------------------+
//| Update Trade                                                      |
//+------------------------------------------------------------------+
void CDailyLossLimit::UpdateTrade(double pnl, bool is_win)
{
    UpdateDailyPnL(pnl);
    CheckAndUpdateLimit();
}

//+------------------------------------------------------------------+
//| Calculate Today's P&L                                            |
//+------------------------------------------------------------------+
double CDailyLossLimit::CalculateTodayPnL(void)
{
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // P&L = (Current Equity - Starting Balance)
    // Use equity to include floating P&L
    double pnl = current_equity - m_starting_balance;
    
    return pnl;
}

//+------------------------------------------------------------------+
//| Get Daily Limit Remaining                                        |
//+------------------------------------------------------------------+
double CDailyLossLimit::GetDailyLimitRemaining(void)
{
    if(IsNewDay())
        ResetDaily();
    
    double current_pnl = CalculateTodayPnL();
    double remaining = m_max_daily_loss + current_pnl;  // current_pnl is negative
    
    return MathMax(0, remaining);
}

//+------------------------------------------------------------------+
//| Get Daily P&L Percent                                            |
//+------------------------------------------------------------------+
double CDailyLossLimit::GetDailyPnLPercent(void)
{
    if(m_starting_balance <= 0)
        return 0;
    
    double current_pnl = CalculateTodayPnL();
    return (current_pnl / m_starting_balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Is New Day                                                        |
//+------------------------------------------------------------------+
bool CDailyLossLimit::IsNewDay(void)
{
    datetime current = GetDayStart();
    return (current > m_current_day);
}

//+------------------------------------------------------------------+
//| Get Day Start                                                     |
//+------------------------------------------------------------------+
datetime CDailyLossLimit::GetDayStart(void)
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Set to start of day (00:00:00)
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Reset Daily                                                       |
//+------------------------------------------------------------------+
void CDailyLossLimit::ResetDaily(void)
{
    Print("🔄 Daily Loss Limit Reset");
    
    // Print yesterday's summary if there was activity
    if(m_daily_trades > 0)
    {
        PrintDailySummary();
    }
    
    // Update day
    m_current_day = GetDayStart();
    
    // Update starting balance
    m_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    m_max_daily_loss = m_starting_balance * (m_daily_limit_pct / 100.0);
    
    // Reset tracking
    m_daily_pnl = 0;
    m_daily_wins = 0;
    m_daily_losses = 0;
    m_daily_trades = 0;
    m_daily_wins_count = 0;
    m_daily_losses_count = 0;
    m_is_limit_reached = false;
    m_limit_reached_time = 0;
    m_last_reset_time = TimeCurrent();
    
    Print("   New Day: ", TimeToString(m_current_day, TIME_DATE));
    Print("   Starting Balance: $", DoubleToString(m_starting_balance, 2));
    Print("   Max Loss Allowed: $", DoubleToString(m_max_daily_loss, 2));
}

//+------------------------------------------------------------------+
//| Set Daily Limit                                                   |
//+------------------------------------------------------------------+
void CDailyLossLimit::SetDailyLimit(double limit_pct)
{
    m_daily_limit_pct = limit_pct;
    m_max_daily_loss = m_starting_balance * (m_daily_limit_pct / 100.0);
    
    Print("✅ Daily limit updated to ", m_daily_limit_pct, "%");
    Print("   Max Loss: $", DoubleToString(m_max_daily_loss, 2));
}

//+------------------------------------------------------------------+
//| Manual Reset                                                      |
//+------------------------------------------------------------------+
void CDailyLossLimit::ManualReset(void)
{
    Print("🔄 Manual Reset Requested");
    ResetDaily();
}

//+------------------------------------------------------------------+
//| Print Information                                                 |
//+------------------------------------------------------------------+
void CDailyLossLimit::PrintInfo(void)
{
    Print("=== Daily Loss Limit Info ===");
    Print("Limit: ", m_daily_limit_pct, "%");
    Print("Max Loss: $", DoubleToString(m_max_daily_loss, 2));
    Print("Starting Balance: $", DoubleToString(m_starting_balance, 2));
    Print("");
    Print("Current Day: ", TimeToString(m_current_day, TIME_DATE));
    Print("Daily P&L: $", DoubleToString(m_daily_pnl, 2), 
          " (", DoubleToString(GetDailyPnLPercent(), 2), "%)");
    Print("Remaining: $", DoubleToString(GetDailyLimitRemaining(), 2));
    Print("");
    Print("Daily Trades: ", m_daily_trades);
    Print("Wins: ", m_daily_wins_count, " ($", DoubleToString(m_daily_wins, 2), ")");
    Print("Losses: ", m_daily_losses_count, " ($", DoubleToString(m_daily_losses, 2), ")");
    Print("");
    Print("Limit Reached: ", (m_is_limit_reached ? "YES" : "NO"));
    if(m_is_limit_reached)
        Print("Reached At: ", TimeToString(m_limit_reached_time));
    Print("Total Limit Hits: ", m_total_limit_hits);
    Print("Last Reset: ", TimeToString(m_last_reset_time));
    Print("=================================");
}

//+------------------------------------------------------------------+
//| Print Daily Summary                                              |
//+------------------------------------------------------------------+
void CDailyLossLimit::PrintDailySummary(void)
{
    Print("╔════════════════════════════════════════╗");
    Print("║        DAILY SUMMARY                    ║");
    Print("╚════════════════════════════════════════╝");
    Print("Date: ", TimeToString(m_current_day, TIME_DATE));
    Print("");
    Print("Trades: ", m_daily_trades);
    Print("  Wins: ", m_daily_wins_count, " ($", DoubleToString(m_daily_wins, 2), ")");
    Print("  Losses: ", m_daily_losses_count, " ($", DoubleToString(m_daily_losses, 2), ")");
    Print("");
    Print("Total P&L: $", DoubleToString(m_daily_pnl, 2));
    Print("P&L %: ", DoubleToString(GetDailyPnLPercent(), 2), "%");
    Print("");
    
    if(m_daily_trades > 0)
    {
        double win_rate = (double)m_daily_wins_count / m_daily_trades * 100.0;
        Print("Win Rate: ", DoubleToString(win_rate, 1), "%");
        
        double avg_win = (m_daily_wins_count > 0) ? m_daily_wins / m_daily_wins_count : 0;
        double avg_loss = (m_daily_losses_count > 0) ? m_daily_losses / m_daily_losses_count : 0;
        Print("Avg Win: $", DoubleToString(avg_win, 2));
        Print("Avg Loss: $", DoubleToString(avg_loss, 2));
    }
    
    Print("");
    Print("Limit Used: ", DoubleToString((MathAbs(m_daily_pnl) / m_max_daily_loss) * 100.0, 1), "%");
    Print("Limit Reached: ", (m_is_limit_reached ? "YES ⚠️" : "NO ✅"));
    Print("════════════════════════════════════════");
}

//+------------------------------------------------------------------+
