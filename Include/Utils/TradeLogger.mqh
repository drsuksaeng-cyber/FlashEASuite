//+------------------------------------------------------------------+
//|                                               TradeLogger.mqh     |
//|                               FlashEASuite V2 - Trade Journal     |
//|                        Comprehensive Trade Logging System         |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Entry Reason Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_REASON
{
    ENTRY_RANGING_NORMAL,           // Perfect ranging conditions
    ENTRY_TRENDING_WEAK,            // Conservative in weak trend  
    ENTRY_HIGH_CONFIDENCE,          // 6+ signals aligned
    ENTRY_CSM_STRONG,               // Strong currency strength signal
    ENTRY_PYTHON_SIGNAL,            // Python brain recommendation
    ENTRY_MANUAL_FORCE,             // Manual/test entry
    ENTRY_GRID_LEVEL,               // Grid level triggered
    ENTRY_SPIKE_DETECTED,           // Spike opportunity
    ENTRY_REENTRY,                  // Re-entry after exit
    ENTRY_UNKNOWN                   // Unknown/legacy
};

//+------------------------------------------------------------------+
//| Exit Reason Enumeration                                           |
//+------------------------------------------------------------------+
enum ENUM_EXIT_REASON
{
    EXIT_PROFIT_TARGET,             // Hit profit target
    EXIT_TRAILING_STOP,             // Trailing stop triggered
    EXIT_REVERSAL_DETECTED,         // Market reversal
    EXIT_TIME_LIMIT,                // Max duration reached
    EXIT_EMERGENCY_DD,              // Emergency drawdown protection
    EXIT_NEWS_EVENT,                // News event protection
    EXIT_MANUAL_CLOSE,              // Manual intervention
    EXIT_STOP_LOSS,                 // Stop loss hit
    EXIT_TAKE_PROFIT,               // Take profit hit
    EXIT_MARGIN_CALL,               // Insufficient margin
    EXIT_WEEKEND_CLOSE,             // Weekend protection
    EXIT_RISK_LIMIT,                // Risk limit reached
    EXIT_UNKNOWN                    // Unknown/legacy
};

//+------------------------------------------------------------------+
//| Trade Information Structure                                       |
//+------------------------------------------------------------------+
struct STradeInfo
{
    // Basic info
    datetime          timestamp;
    string            action;                // "ENTRY" or "EXIT"
    string            strategy;              // "Grid", "Spike", etc.
    long              ticket;
    string            symbol;
    ENUM_ORDER_TYPE   type;
    double            lots;
    double            price;
    double            sl;
    double            tp;
    string            comment;
    
    // Entry details
    ENUM_ENTRY_REASON entry_reason;
    string            entry_reason_detail;
    string            market_state;
    int               signal_count;
    double            confidence;
    double            csm_score;
    bool              ma_aligned;
    double            rsi_value;
    double            atr_value;
    double            spread;
    string            additional_signals;
    
    // Exit details
    ENUM_EXIT_REASON  exit_reason;
    string            exit_reason_detail;
    double            profit;
    double            profit_pct;
    double            profit_points;
    double            duration_hours;
    double            max_favorable;
    double            max_adverse;
    double            mae_pct;                // Max Adverse Excursion %
    double            mfe_pct;                // Max Favorable Excursion %
    
    // Account state
    double            balance_before;
    double            balance_after;
    double            equity;
    double            margin;
    double            free_margin;
    double            margin_level;
    double            drawdown;
    double            drawdown_pct;
    
    // Performance
    int               consecutive_wins;
    int               consecutive_losses;
    double            win_rate;
    double            avg_profit;
    double            avg_loss;
    double            profit_factor;
    
    // Notes
    string            notes;
    string            tags;                   // Comma-separated tags
};

//+------------------------------------------------------------------+
//| Trade Logger Class                                                |
//+------------------------------------------------------------------+
class CTradeLogger
{
private:
    string            m_symbol;
    string            m_csv_filename;
    string            m_json_filename;
    bool              m_enabled;
    bool              m_csv_enabled;
    bool              m_json_enabled;
    bool              m_console_enabled;
    
    // Statistics
    int               m_total_entries;
    int               m_total_exits;
    int               m_wins;
    int               m_losses;
    double            m_total_profit;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CTradeLogger(string symbol = "")
    {
        if(symbol == "")
            m_symbol = _Symbol;
        else
            m_symbol = symbol;
            
        // Create filenames with date
        string date_str = TimeToString(TimeCurrent(), TIME_DATE);
        StringReplace(date_str, ".", "_");
        
        m_csv_filename = StringFormat("TradeJournal_%s_%s.csv", 
                                     m_symbol, 
                                     date_str);
        m_json_filename = StringFormat("TradeJournal_%s_%s.ndjson", 
                                      m_symbol, 
                                      date_str);
        
        m_enabled = true;
        m_csv_enabled = true;
        m_json_enabled = true;
        m_console_enabled = true;
        
        // Initialize statistics
        m_total_entries = 0;
        m_total_exits = 0;
        m_wins = 0;
        m_losses = 0;
        m_total_profit = 0.0;
        
        InitializeCSVFile();
        
        Print("═══════════════════════════════════════");
        Print("  📝 TRADE LOGGER INITIALIZED");
        Print("═══════════════════════════════════════");
        Print("Symbol:    ", m_symbol);
        Print("CSV File:  ", m_csv_filename);
        Print("JSON File: ", m_json_filename);
        Print("═══════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CTradeLogger()
    {
        PrintStatistics();
    }
    
    //+------------------------------------------------------------------+
    //| Log Entry                                                         |
    //+------------------------------------------------------------------+
    void LogEntry(STradeInfo& info)
    {
        if(!m_enabled) return;
        
        info.action = "ENTRY";
        info.timestamp = TimeCurrent();
        
        // Capture account state
        info.balance_before = AccountInfoDouble(ACCOUNT_BALANCE);
        info.equity = AccountInfoDouble(ACCOUNT_EQUITY);
        info.margin = AccountInfoDouble(ACCOUNT_MARGIN);
        info.free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        info.margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        
        // Calculate spread
        MqlTick tick;
        if(SymbolInfoTick(m_symbol, tick))
        {
            info.spread = (tick.ask - tick.bid) / _Point;
        }
        
        // Write logs
        if(m_csv_enabled)
            WriteToCSV(info);
            
        if(m_json_enabled)
            WriteToJSON(info);
            
        if(m_console_enabled)
            PrintEntryInfo(info);
        
        m_total_entries++;
    }
    
    //+------------------------------------------------------------------+
    //| Log Exit                                                          |
    //+------------------------------------------------------------------+
    void LogExit(STradeInfo& info)
    {
        if(!m_enabled) return;
        
        info.action = "EXIT";
        info.timestamp = TimeCurrent();
        
        // Capture account state
        info.balance_after = AccountInfoDouble(ACCOUNT_BALANCE);
        info.equity = AccountInfoDouble(ACCOUNT_EQUITY);
        info.margin = AccountInfoDouble(ACCOUNT_MARGIN);
        info.free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        info.margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        
        // Calculate profit
        if(info.balance_before > 0)
        {
            info.profit = info.balance_after - info.balance_before;
            info.profit_pct = (info.profit / info.balance_before) * 100.0;
        }
        
        // Update statistics
        if(info.profit > 0)
        {
            m_wins++;
            info.consecutive_wins++;
            info.consecutive_losses = 0;
        }
        else if(info.profit < 0)
        {
            m_losses++;
            info.consecutive_losses++;
            info.consecutive_wins = 0;
        }
        
        m_total_profit += info.profit;
        
        // Calculate performance metrics
        if(m_total_exits > 0)
        {
            info.win_rate = (double)m_wins / (double)m_total_exits * 100.0;
        }
        
        // Write logs
        if(m_csv_enabled)
            WriteToCSV(info);
            
        if(m_json_enabled)
            WriteToJSON(info);
            
        if(m_console_enabled)
            PrintExitInfo(info);
        
        m_total_exits++;
    }
    
    //+------------------------------------------------------------------+
    //| Enable/Disable Logging                                           |
    //+------------------------------------------------------------------+
    void SetEnabled(bool enabled) { m_enabled = enabled; }
    void SetCSVEnabled(bool enabled) { m_csv_enabled = enabled; }
    void SetJSONEnabled(bool enabled) { m_json_enabled = enabled; }
    void SetConsoleEnabled(bool enabled) { m_console_enabled = enabled; }
    
    //+------------------------------------------------------------------+
    //| Get Statistics                                                    |
    //+------------------------------------------------------------------+
    int GetTotalEntries() { return m_total_entries; }
    int GetTotalExits() { return m_total_exits; }
    int GetWins() { return m_wins; }
    int GetLosses() { return m_losses; }
    double GetTotalProfit() { return m_total_profit; }
    double GetWinRate() 
    { 
        if(m_total_exits == 0) return 0.0;
        return (double)m_wins / (double)m_total_exits * 100.0;
    }
    
private:
    //+------------------------------------------------------------------+
    //| Initialize CSV File                                               |
    //+------------------------------------------------------------------+
    void InitializeCSVFile()
    {
        int handle = FileOpen(m_csv_filename, FILE_CSV|FILE_WRITE, ',');
        if(handle != INVALID_HANDLE)
        {
            // Write header
            FileWrite(handle,
                // Basic
                "Timestamp", "Action", "Strategy", "Ticket", "Symbol",
                "Type", "Lots", "Price", "SL", "TP", "Comment",
                // Entry
                "EntryReason", "EntryDetail", "MarketState", "SignalCount", "Confidence",
                "CSM_Score", "MA_Aligned", "RSI", "ATR", "Spread", "AdditionalSignals",
                // Exit
                "ExitReason", "ExitDetail", "Profit", "ProfitPct", "ProfitPoints",
                "DurationHrs", "MaxFavorable", "MaxAdverse", "MAE_Pct", "MFE_Pct",
                // Account
                "BalanceBefore", "BalanceAfter", "Equity", "Margin", "FreeMargin",
                "MarginLevel", "Drawdown", "DrawdownPct",
                // Performance
                "ConsecWins", "ConsecLosses", "WinRate", "AvgProfit", "AvgLoss", "ProfitFactor",
                // Notes
                "Notes", "Tags"
            );
            FileClose(handle);
            
            Print("[TradeLogger] ✅ CSV file initialized: ", m_csv_filename);
        }
        else
        {
            Print("[TradeLogger] ❌ Failed to initialize CSV file");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Write to CSV                                                      |
    //+------------------------------------------------------------------+
    void WriteToCSV(STradeInfo& info)
    {
        int handle = FileOpen(m_csv_filename, FILE_CSV|FILE_READ|FILE_WRITE, ',');
        if(handle != INVALID_HANDLE)
        {
            FileSeek(handle, 0, SEEK_END);
            
            FileWrite(handle,
                // Basic
                TimeToString(info.timestamp),
                info.action,
                info.strategy,
                info.ticket,
                info.symbol,
                EnumToString(info.type),
                DoubleToString(info.lots, 2),
                DoubleToString(info.price, _Digits),
                DoubleToString(info.sl, _Digits),
                DoubleToString(info.tp, _Digits),
                info.comment,
                // Entry
                EnumToString(info.entry_reason),
                info.entry_reason_detail,
                info.market_state,
                IntegerToString(info.signal_count),
                DoubleToString(info.confidence, 2),
                DoubleToString(info.csm_score, 2),
                info.ma_aligned ? "TRUE" : "FALSE",
                DoubleToString(info.rsi_value, 1),
                DoubleToString(info.atr_value, _Digits),
                DoubleToString(info.spread, 1),
                info.additional_signals,
                // Exit
                EnumToString(info.exit_reason),
                info.exit_reason_detail,
                DoubleToString(info.profit, 2),
                DoubleToString(info.profit_pct, 2),
                DoubleToString(info.profit_points, 1),
                DoubleToString(info.duration_hours, 1),
                DoubleToString(info.max_favorable, _Digits),
                DoubleToString(info.max_adverse, _Digits),
                DoubleToString(info.mae_pct, 2),
                DoubleToString(info.mfe_pct, 2),
                // Account
                DoubleToString(info.balance_before, 2),
                DoubleToString(info.balance_after, 2),
                DoubleToString(info.equity, 2),
                DoubleToString(info.margin, 2),
                DoubleToString(info.free_margin, 2),
                DoubleToString(info.margin_level, 2),
                DoubleToString(info.drawdown, 2),
                DoubleToString(info.drawdown_pct, 2),
                // Performance
                IntegerToString(info.consecutive_wins),
                IntegerToString(info.consecutive_losses),
                DoubleToString(info.win_rate, 2),
                DoubleToString(info.avg_profit, 2),
                DoubleToString(info.avg_loss, 2),
                DoubleToString(info.profit_factor, 2),
                // Notes
                info.notes,
                info.tags
            );
            
            FileClose(handle);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Write to JSON                                                     |
    //+------------------------------------------------------------------+
    void WriteToJSON(STradeInfo& info)
    {
        int handle = FileOpen(m_json_filename, FILE_TXT|FILE_READ|FILE_WRITE);
        if(handle != INVALID_HANDLE)
        {
            FileSeek(handle, 0, SEEK_END);
            
            string json = StringFormat(
                "{\"timestamp\":\"%s\",\"action\":\"%s\",\"strategy\":\"%s\","
                "\"ticket\":%d,\"symbol\":\"%s\",\"type\":\"%s\","
                "\"lots\":%.2f,\"price\":%.5f,\"sl\":%.5f,\"tp\":%.5f,"
                "\"entry_reason\":\"%s\",\"market_state\":\"%s\","
                "\"signal_count\":%d,\"confidence\":%.2f,\"csm_score\":%.2f,"
                "\"exit_reason\":\"%s\",\"profit\":%.2f,\"profit_pct\":%.2f,"
                "\"balance_after\":%.2f,\"win_rate\":%.2f}",
                TimeToString(info.timestamp),
                info.action,
                info.strategy,
                info.ticket,
                info.symbol,
                EnumToString(info.type),
                info.lots,
                info.price,
                info.sl,
                info.tp,
                EnumToString(info.entry_reason),
                info.market_state,
                info.signal_count,
                info.confidence,
                info.csm_score,
                EnumToString(info.exit_reason),
                info.profit,
                info.profit_pct,
                info.balance_after,
                info.win_rate
            );
            
            FileWriteString(handle, json + "\n");
            FileClose(handle);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Print Entry Info                                                  |
    //+------------------------------------------------------------------+
    void PrintEntryInfo(STradeInfo& info)
    {
        Print("═══════════════════════════════════════");
        Print("  📝 ENTRY LOGGED");
        Print("═══════════════════════════════════════");
        Print("Time:     ", TimeToString(info.timestamp));
        Print("Strategy: ", info.strategy);
        Print("Ticket:   #", info.ticket);
        Print("Type:     ", EnumToString(info.type));
        Print("Lots:     ", DoubleToString(info.lots, 2));
        Print("Price:    ", DoubleToString(info.price, _Digits));
        Print("───────────────────────────────────────");
        Print("ENTRY REASON:");
        Print("  Main:       ", EnumToString(info.entry_reason));
        Print("  Detail:     ", info.entry_reason_detail);
        Print("  Market:     ", info.market_state);
        Print("  Signals:    ", info.signal_count);
        Print("  Confidence: ", DoubleToString(info.confidence * 100, 0), "%");
        Print("  CSM Score:  ", DoubleToString(info.csm_score, 2));
        Print("───────────────────────────────────────");
        Print("Balance:  $", DoubleToString(info.balance_before, 2));
        Print("Equity:   $", DoubleToString(info.equity, 2));
        Print("═══════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Print Exit Info                                                   |
    //+------------------------------------------------------------------+
    void PrintExitInfo(STradeInfo& info)
    {
        Print("═══════════════════════════════════════");
        Print("  📝 EXIT LOGGED");
        Print("═══════════════════════════════════════");
        Print("Time:     ", TimeToString(info.timestamp));
        Print("Strategy: ", info.strategy);
        Print("Ticket:   #", info.ticket);
        Print("Duration: ", DoubleToString(info.duration_hours, 1), " hrs");
        Print("───────────────────────────────────────");
        Print("EXIT REASON:");
        Print("  Main:   ", EnumToString(info.exit_reason));
        Print("  Detail: ", info.exit_reason_detail);
        Print("───────────────────────────────────────");
        Print("PROFIT:");
        Print("  Amount:  $", DoubleToString(info.profit, 2));
        Print("  Percent: ", DoubleToString(info.profit_pct, 2), "%");
        Print("  Points:  ", DoubleToString(info.profit_points, 1));
        Print("───────────────────────────────────────");
        Print("Balance:  $", DoubleToString(info.balance_after, 2));
        Print("Win Rate: ", DoubleToString(info.win_rate, 1), "%");
        Print("═══════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Print Statistics                                                  |
    //+------------------------------------------------------------------+
    void PrintStatistics()
    {
        Print("═══════════════════════════════════════");
        Print("  📊 TRADE LOGGER STATISTICS");
        Print("═══════════════════════════════════════");
        Print("Total Entries: ", m_total_entries);
        Print("Total Exits:   ", m_total_exits);
        Print("Wins:          ", m_wins);
        Print("Losses:        ", m_losses);
        Print("Total Profit:  $", DoubleToString(m_total_profit, 2));
        if(m_total_exits > 0)
        {
            Print("Win Rate:      ", DoubleToString(GetWinRate(), 1), "%");
        }
        Print("═══════════════════════════════════════");
    }
};

//+------------------------------------------------------------------+
//| Helper function to get entry reason string                        |
//+------------------------------------------------------------------+
string GetEntryReasonString(ENUM_ENTRY_REASON reason)
{
    switch(reason)
    {
        case ENTRY_RANGING_NORMAL:    return "RANGING_NORMAL";
        case ENTRY_TRENDING_WEAK:     return "TRENDING_WEAK";
        case ENTRY_HIGH_CONFIDENCE:   return "HIGH_CONFIDENCE";
        case ENTRY_CSM_STRONG:        return "CSM_STRONG";
        case ENTRY_PYTHON_SIGNAL:     return "PYTHON_SIGNAL";
        case ENTRY_MANUAL_FORCE:      return "MANUAL_FORCE";
        case ENTRY_GRID_LEVEL:        return "GRID_LEVEL";
        case ENTRY_SPIKE_DETECTED:    return "SPIKE_DETECTED";
        case ENTRY_REENTRY:           return "REENTRY";
        default:                      return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Helper function to get exit reason string                         |
//+------------------------------------------------------------------+
string GetExitReasonString(ENUM_EXIT_REASON reason)
{
    switch(reason)
    {
        case EXIT_PROFIT_TARGET:      return "PROFIT_TARGET";
        case EXIT_TRAILING_STOP:      return "TRAILING_STOP";
        case EXIT_REVERSAL_DETECTED:  return "REVERSAL";
        case EXIT_TIME_LIMIT:         return "TIME_LIMIT";
        case EXIT_EMERGENCY_DD:       return "EMERGENCY_DD";
        case EXIT_NEWS_EVENT:         return "NEWS_EVENT";
        case EXIT_MANUAL_CLOSE:       return "MANUAL_CLOSE";
        case EXIT_STOP_LOSS:          return "STOP_LOSS";
        case EXIT_TAKE_PROFIT:        return "TAKE_PROFIT";
        case EXIT_MARGIN_CALL:        return "MARGIN_CALL";
        case EXIT_WEEKEND_CLOSE:      return "WEEKEND_CLOSE";
        case EXIT_RISK_LIMIT:         return "RISK_LIMIT";
        default:                      return "UNKNOWN";
    }
}
//+------------------------------------------------------------------+
