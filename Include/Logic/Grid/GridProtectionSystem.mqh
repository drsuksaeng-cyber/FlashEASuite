//+------------------------------------------------------------------+
//|                              Grid/GridProtectionSystem.mqh       |
//|                                    FlashEASuite V2 - Week 6      |
//|                      Grid Protection & Pause Mechanism            |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Protection Status Enum                                           |
//+------------------------------------------------------------------+
enum ENUM_PROTECTION_STATUS
{
    PROTECTION_NORMAL,           // Normal operation
    PROTECTION_CAUTION,          // Caution - approaching limits
    PROTECTION_PAUSED,           // Paused - limits exceeded
    PROTECTION_EMERGENCY_STOP    // Emergency stop - critical levels
};

//+------------------------------------------------------------------+
//| Protection Trigger Reason                                        |
//+------------------------------------------------------------------+
enum ENUM_PROTECTION_TRIGGER
{
    TRIGGER_NONE,
    TRIGGER_TREND_TOO_STRONG,    // Extreme trending detected
    TRIGGER_DRAWDOWN_LIMIT,      // Max drawdown exceeded
    TRIGGER_LOSS_STREAK,         // Too many losses in a row
    TRIGGER_EXPOSURE_LIMIT,      // Too many open positions
    TRIGGER_PROFIT_TARGET        // Daily profit target reached
};

//+------------------------------------------------------------------+
//| Grid Protection System Class                                     |
//+------------------------------------------------------------------+
class CGridProtectionSystem
{
private:
    string   m_symbol;
    
    // Protection status
    ENUM_PROTECTION_STATUS  m_status;
    ENUM_PROTECTION_TRIGGER m_trigger_reason;
    datetime m_pause_start_time;
    int      m_pause_duration_minutes;
    
    // Trend detection
    int      m_trend_atr_handle;
    int      m_trend_ma_handle;
    double   m_trend_strength;          // 0-100
    double   m_max_trend_strength;      // Threshold (default: 75)
    int      m_trend_bars_count;        // Consecutive trending bars
    int      m_max_trend_bars;          // Max allowed (default: 50)
    
    // Drawdown monitoring
    double   m_initial_balance;
    double   m_peak_balance;
    double   m_current_drawdown_pct;
    double   m_max_drawdown_pct;        // Threshold (default: 25%)
    double   m_emergency_drawdown_pct;  // Emergency stop (default: 35%)
    
    // Loss streak detection
    int      m_consecutive_losses;
    int      m_max_consecutive_losses;  // Threshold (default: 5)
    
    // Exposure limits
    int      m_open_positions;
    int      m_max_positions;           // Threshold (default: 15)
    double   m_total_exposure_lots;
    double   m_max_exposure_lots;       // Threshold (default: 1.0)
    
    // Movement detection
    double   m_price_start;
    double   m_price_current;
    double   m_total_movement_points;
    double   m_max_movement_points;     // Threshold (default: 5000)
    
    // Cooldown
    bool     m_in_cooldown;
    datetime m_cooldown_end_time;
    int      m_default_cooldown_minutes; // Default: 30 min
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridProtectionSystem(string symbol = "")
    {
        m_symbol = (symbol == "") ? _Symbol : symbol;
        
        m_status = PROTECTION_NORMAL;
        m_trigger_reason = TRIGGER_NONE;
        m_pause_start_time = 0;
        m_pause_duration_minutes = 30;
        
        m_trend_atr_handle = INVALID_HANDLE;
        m_trend_ma_handle = INVALID_HANDLE;
        m_trend_strength = 0;
        m_max_trend_strength = 75.0;
        m_trend_bars_count = 0;
        m_max_trend_bars = 50;
        
        m_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_peak_balance = m_initial_balance;
        m_current_drawdown_pct = 0;
        m_max_drawdown_pct = 25.0;
        m_emergency_drawdown_pct = 35.0;
        
        m_consecutive_losses = 0;
        m_max_consecutive_losses = 5;
        
        m_open_positions = 0;
        m_max_positions = 15;
        m_total_exposure_lots = 0;
        m_max_exposure_lots = 1.0;
        
        m_price_start = 0;
        m_price_current = 0;
        m_total_movement_points = 0;
        m_max_movement_points = 5000.0;
        
        m_in_cooldown = false;
        m_cooldown_end_time = 0;
        m_default_cooldown_minutes = 30;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CGridProtectionSystem()
    {
        if(m_trend_atr_handle != INVALID_HANDLE) IndicatorRelease(m_trend_atr_handle);
        if(m_trend_ma_handle != INVALID_HANDLE) IndicatorRelease(m_trend_ma_handle);
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                       |
    //+------------------------------------------------------------------+
    bool Initialize()
    {
        // Create ATR for trend detection
        m_trend_atr_handle = iATR(m_symbol, PERIOD_CURRENT, 14);
        if(m_trend_atr_handle == INVALID_HANDLE)
        {
            Print("❌ Failed to create ATR indicator");
            return false;
        }
        
        // Create MA for trend direction
        m_trend_ma_handle = iMA(m_symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
        if(m_trend_ma_handle == INVALID_HANDLE)
        {
            Print("❌ Failed to create MA indicator");
            return false;
        }
        
        // Initialize price tracking
        MqlTick tick;
        if(SymbolInfoTick(m_symbol, tick))
        {
            m_price_start = tick.bid;
            m_price_current = tick.bid;
        }
        
        Print("✅ Grid Protection System initialized");
        Print("   Max Drawdown: ", m_max_drawdown_pct, "%");
        Print("   Max Trend Strength: ", m_max_trend_strength);
        Print("   Max Movement: ", m_max_movement_points, " points");
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check Protection Status (Main Function)                         |
    //+------------------------------------------------------------------+
    ENUM_PROTECTION_STATUS CheckProtection()
    {
        // Check if in cooldown
        if(m_in_cooldown)
        {
            if(TimeCurrent() >= m_cooldown_end_time)
            {
                EndCooldown();
            }
            else
            {
                return PROTECTION_PAUSED;
            }
        }
        
        // Check if paused and can resume
        if(m_status == PROTECTION_PAUSED)
        {
            if(CanResume())
            {
                ResumeTrading();
            }
        }
        
        // Run all protection checks
        bool emergency = false;
        
        // 1. Check extreme trending
        if(CheckExtremeTrending())
        {
            PauseTradingWith(TRIGGER_TREND_TOO_STRONG, 60); // 60 min pause
            return m_status;
        }
        
        // 2. Check drawdown (CRITICAL)
        if(CheckDrawdownLimit())
        {
            if(m_current_drawdown_pct >= m_emergency_drawdown_pct)
            {
                EmergencyStop(TRIGGER_DRAWDOWN_LIMIT);
                return m_status;
            }
            else
            {
                PauseTradingWith(TRIGGER_DRAWDOWN_LIMIT, 120); // 120 min pause
                return m_status;
            }
        }
        
        // 3. Check loss streak
        if(CheckLossStreak())
        {
            PauseTradingWith(TRIGGER_LOSS_STREAK, 30);
            return m_status;
        }
        
        // 4. Check exposure limits
        if(CheckExposureLimits())
        {
            PauseTradingWith(TRIGGER_EXPOSURE_LIMIT, 15);
            return m_status;
        }
        
        // 5. Check total movement
        if(CheckTotalMovement())
        {
            PauseTradingWith(TRIGGER_TREND_TOO_STRONG, 90);
            return m_status;
        }
        
        // All checks passed
        if(m_status != PROTECTION_NORMAL)
        {
            m_status = PROTECTION_NORMAL;
            m_trigger_reason = TRIGGER_NONE;
        }
        
        return m_status;
    }
    
    //+------------------------------------------------------------------+
    //| Check Extreme Trending                                          |
    //+------------------------------------------------------------------+
    bool CheckExtremeTrending()
    {
        // Get ATR
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_trend_atr_handle, 0, 0, 3, atr) < 3)
            return false;
        
        // Get MA
        double ma[];
        ArraySetAsSeries(ma, true);
        if(CopyBuffer(m_trend_ma_handle, 0, 0, 3, ma) < 3)
            return false;
        
        // Get current price
        MqlTick tick;
        if(!SymbolInfoTick(m_symbol, tick))
            return false;
        
        double price = tick.bid;
        
        // Calculate trend strength (distance from MA in ATR units)
        double distance_from_ma = MathAbs(price - ma[0]);
        m_trend_strength = (distance_from_ma / atr[0]) * 100.0;
        
        // Count consecutive trending bars
        if(m_trend_strength > 50.0)
        {
            m_trend_bars_count++;
        }
        else
        {
            m_trend_bars_count = 0;
        }
        
        // Check limits
        bool too_strong = (m_trend_strength > m_max_trend_strength);
        bool too_long = (m_trend_bars_count > m_max_trend_bars);
        
        if(too_strong || too_long)
        {
            Print("⚠️ EXTREME TRENDING DETECTED!");
            Print("   Trend Strength: ", DoubleToString(m_trend_strength, 2));
            Print("   Consecutive Bars: ", m_trend_bars_count);
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Drawdown Limit                                            |
    //+------------------------------------------------------------------+
    bool CheckDrawdownLimit()
    {
        double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Update peak balance
        if(current_balance > m_peak_balance)
        {
            m_peak_balance = current_balance;
        }
        
        // Calculate drawdown from peak
        double drawdown = m_peak_balance - current_equity;
        m_current_drawdown_pct = (drawdown / m_peak_balance) * 100.0;
        
        if(m_current_drawdown_pct >= m_max_drawdown_pct)
        {
            Print("⚠️ DRAWDOWN LIMIT EXCEEDED!");
            Print("   Current Drawdown: ", DoubleToString(m_current_drawdown_pct, 2), "%");
            Print("   Peak Balance: ", m_peak_balance);
            Print("   Current Equity: ", current_equity);
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Loss Streak                                               |
    //+------------------------------------------------------------------+
    bool CheckLossStreak()
    {
        if(m_consecutive_losses >= m_max_consecutive_losses)
        {
            Print("⚠️ LOSS STREAK DETECTED!");
            Print("   Consecutive Losses: ", m_consecutive_losses);
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Exposure Limits                                           |
    //+------------------------------------------------------------------+
    bool CheckExposureLimits()
    {
        // Count current positions
        int positions = 0;
        double total_lots = 0;
        
        for(int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            
            if(PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
                positions++;
                total_lots += PositionGetDouble(POSITION_VOLUME);
            }
        }
        
        m_open_positions = positions;
        m_total_exposure_lots = total_lots;
        
        bool too_many_positions = (m_open_positions >= m_max_positions);
        bool too_much_exposure = (m_total_exposure_lots >= m_max_exposure_lots);
        
        if(too_many_positions || too_much_exposure)
        {
            Print("⚠️ EXPOSURE LIMIT EXCEEDED!");
            Print("   Open Positions: ", m_open_positions, "/", m_max_positions);
            Print("   Total Exposure: ", DoubleToString(m_total_exposure_lots, 2), "/", 
                  DoubleToString(m_max_exposure_lots, 2), " lots");
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Total Movement (ลากไส้แตก)                                |
    //+------------------------------------------------------------------+
    bool CheckTotalMovement()
    {
        MqlTick tick;
        if(!SymbolInfoTick(m_symbol, tick))
            return false;
        
        m_price_current = tick.bid;
        
        // Calculate total movement from start
        double movement = MathAbs(m_price_current - m_price_start);
        m_total_movement_points = movement / _Point;
        
        if(m_total_movement_points >= m_max_movement_points)
        {
            Print("⚠️ EXTREME MOVEMENT DETECTED (ลากไส้แตก)!");
            Print("   Total Movement: ", DoubleToString(m_total_movement_points, 1), " points");
            Print("   Start Price: ", DoubleToString(m_price_start, _Digits));
            Print("   Current Price: ", DoubleToString(m_price_current, _Digits));
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Pause Trading                                                   |
    //+------------------------------------------------------------------+
    void PauseTradingWith(ENUM_PROTECTION_TRIGGER reason, int duration_minutes)
    {
        m_status = PROTECTION_PAUSED;
        m_trigger_reason = reason;
        m_pause_start_time = TimeCurrent();
        m_pause_duration_minutes = duration_minutes;
        
        Print("🛑 TRADING PAUSED!");
        Print("   Reason: ", EnumToString(reason));
        Print("   Duration: ", duration_minutes, " minutes");
        Print("   Resume at: ", TimeToString(m_pause_start_time + duration_minutes * 60));
    }
    
    //+------------------------------------------------------------------+
    //| Emergency Stop                                                   |
    //+------------------------------------------------------------------+
    void EmergencyStop(ENUM_PROTECTION_TRIGGER reason)
    {
        m_status = PROTECTION_EMERGENCY_STOP;
        m_trigger_reason = reason;
        
        Print("🚨 EMERGENCY STOP ACTIVATED!");
        Print("   Reason: ", EnumToString(reason));
        Print("   Drawdown: ", DoubleToString(m_current_drawdown_pct, 2), "%");
        Print("   Manual intervention required!");
    }
    
    //+------------------------------------------------------------------+
    //| Can Resume Trading                                              |
    //+------------------------------------------------------------------+
    bool CanResume()
    {
        if(m_status == PROTECTION_EMERGENCY_STOP)
        {
            return false; // Need manual reset
        }
        
        if(TimeCurrent() < m_pause_start_time + m_pause_duration_minutes * 60)
        {
            return false; // Still in pause period
        }
        
        // Check if conditions improved
        switch(m_trigger_reason)
        {
            case TRIGGER_TREND_TOO_STRONG:
                return (m_trend_strength < m_max_trend_strength * 0.7); // 30% improvement
                
            case TRIGGER_DRAWDOWN_LIMIT:
                return (m_current_drawdown_pct < m_max_drawdown_pct * 0.8); // 20% improvement
                
            case TRIGGER_LOSS_STREAK:
                return true; // After time pause
                
            case TRIGGER_EXPOSURE_LIMIT:
                return (m_open_positions < m_max_positions * 0.8);
                
            default:
                return true;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Resume Trading                                                   |
    //+------------------------------------------------------------------+
    void ResumeTrading()
    {
        Print("✅ TRADING RESUMED");
        Print("   Was paused for: ", EnumToString(m_trigger_reason));
        
        m_status = PROTECTION_NORMAL;
        m_trigger_reason = TRIGGER_NONE;
        m_pause_start_time = 0;
        
        // Reset movement tracking if resumed from movement trigger
        MqlTick tick;
        if(SymbolInfoTick(m_symbol, tick))
        {
            m_price_start = tick.bid;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Start Cooldown                                                  |
    //+------------------------------------------------------------------+
    void StartCooldown(int minutes = 0)
    {
        int duration = (minutes > 0) ? minutes : m_default_cooldown_minutes;
        m_in_cooldown = true;
        m_cooldown_end_time = TimeCurrent() + duration * 60;
        
        Print("⏸️ Cooldown started: ", duration, " minutes");
    }
    
    //+------------------------------------------------------------------+
    //| End Cooldown                                                    |
    //+------------------------------------------------------------------+
    void EndCooldown()
    {
        m_in_cooldown = false;
        m_cooldown_end_time = 0;
        Print("▶️ Cooldown ended");
    }
    
    //+------------------------------------------------------------------+
    //| Update After Trade Result                                       |
    //+------------------------------------------------------------------+
    void UpdateAfterTrade(bool is_win, double profit)
    {
        if(is_win)
        {
            m_consecutive_losses = 0;
        }
        else
        {
            m_consecutive_losses++;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    ENUM_PROTECTION_STATUS GetStatus() { return m_status; }
    ENUM_PROTECTION_TRIGGER GetTriggerReason() { return m_trigger_reason; }
    double GetCurrentDrawdown() { return m_current_drawdown_pct; }
    double GetTrendStrength() { return m_trend_strength; }
    int GetConsecutiveLosses() { return m_consecutive_losses; }
    bool IsTrading() { return (m_status == PROTECTION_NORMAL); }
    
    //+------------------------------------------------------------------+
    //| Setters (for configuration)                                     |
    //+------------------------------------------------------------------+
    void SetMaxDrawdown(double pct) { m_max_drawdown_pct = pct; }
    void SetMaxTrendStrength(double strength) { m_max_trend_strength = strength; }
    void SetMaxMovement(double points) { m_max_movement_points = points; }
    void SetMaxPositions(int count) { m_max_positions = count; }
    void SetMaxExposure(double lots) { m_max_exposure_lots = lots; }
};

//+------------------------------------------------------------------+
