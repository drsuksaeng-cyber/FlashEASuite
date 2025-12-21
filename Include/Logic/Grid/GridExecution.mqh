//+------------------------------------------------------------------+
//|                                     Grid/GridExecution.mqh       |
//|                                   FlashEASuite V2 - Week 3       |
//|                    Advanced Grid Order Execution                  |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Execution Result Structure                                       |
//+------------------------------------------------------------------+
struct ExecutionResult
{
    bool              success;            // Execution successful?
    ulong             ticket;             // Order ticket
    double            executed_price;     // Actual execution price
    double            slippage_points;    // Slippage in points
    string            error_message;      // Error description
    int               retry_count;        // Number of retries
};

//+------------------------------------------------------------------+
//| Class: CGridExecution                                            |
//| Handles advanced order execution with retry logic                |
//+------------------------------------------------------------------+
class CGridExecution
{
private:
    CTrade            m_trade;
    
    // Execution parameters
    int               m_max_retries;      // Max retry attempts (3)
    int               m_retry_delay_ms;   // Delay between retries (500ms)
    double            m_max_slippage;     // Max acceptable slippage (points)
    ulong             m_magic_number;     // EA magic number
    
    // Statistics
    int               m_total_executions;
    int               m_successful_executions;
    int               m_failed_executions;
    double            m_avg_slippage;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridExecution()
    {
        m_max_retries = 3;
        m_retry_delay_ms = 500;
        m_max_slippage = 50.0; // 50 points default
        m_magic_number = 999000;
        
        m_total_executions = 0;
        m_successful_executions = 0;
        m_failed_executions = 0;
        m_avg_slippage = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                       |
    //+------------------------------------------------------------------+
    void Initialize(ulong magic_number, double max_slippage_points = 50.0)
    {
        m_magic_number = magic_number;
        m_max_slippage = max_slippage_points;
        
        m_trade.SetExpertMagicNumber(m_magic_number);
        m_trade.SetDeviationInPoints((ulong)m_max_slippage);
        m_trade.SetAsyncMode(false); // Synchronous execution
    }
    
    //+------------------------------------------------------------------+
    //| Execute Grid Order with Retry Logic                            |
    //+------------------------------------------------------------------+
    ExecutionResult ExecuteGridOrder(ENUM_ORDER_TYPE type, double lot, int level)
    {
        ExecutionResult result;
        result.success = false;
        result.ticket = 0;
        result.executed_price = 0.0;
        result.slippage_points = 0.0;
        result.error_message = "";
        result.retry_count = 0;
        
        m_total_executions++;
        
        // Get current price
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
        {
            result.error_message = "Cannot get tick";
            m_failed_executions++;
            return result;
        }
        
        double intended_price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
        
        // Calculate SL/TP (basic - can be enhanced)
        double sl = 0.0;
        double tp = 0.0;
        
        // Create comment
        string comment = StringFormat("Grid_L%d", level);
        
        // Try to execute with retries
        for(int attempt = 0; attempt <= m_max_retries; attempt++)
        {
            result.retry_count = attempt;
            
            // Execute order
            bool executed = m_trade.PositionOpen(_Symbol, type, lot, intended_price, 
                                                  sl, tp, comment);
            
            if(executed)
            {
                // Get result info
                result.success = true;
                result.ticket = m_trade.ResultOrder();
                result.executed_price = m_trade.ResultPrice();
                result.slippage_points = MathAbs(result.executed_price - intended_price) / _Point;
                
                // Update statistics
                m_successful_executions++;
                UpdateSlippageStats(result.slippage_points);
                
                Print(StringFormat("[GridExec] ✅ Success | Level %d | Type: %s | Lot: %.2f | Price: %.5f | Slippage: %.1f pts",
                                  level,
                                  type == ORDER_TYPE_BUY ? "BUY" : "SELL",
                                  lot,
                                  result.executed_price,
                                  result.slippage_points));
                
                return result;
            }
            else
            {
                // Get error
                uint error_code = GetLastError();
                result.error_message = StringFormat("Error %d: %s", 
                                                    error_code, 
                                                    GetErrorDescription(error_code));
                
                Print(StringFormat("[GridExec] ⚠️ Attempt %d failed: %s", 
                                  attempt + 1, 
                                  result.error_message));
                
                // Check if should retry
                if(!ShouldRetry(error_code))
                {
                    Print("[GridExec] ❌ Non-retryable error - giving up");
                    break;
                }
                
                // Wait before retry
                if(attempt < m_max_retries)
                {
                    Sleep(m_retry_delay_ms);
                }
            }
        }
        
        // All retries failed
        m_failed_executions++;
        Print(StringFormat("[GridExec] ❌ Failed after %d attempts", result.retry_count + 1));
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| Close Grid Position                                             |
    //+------------------------------------------------------------------+
    bool CloseGridPosition(ulong ticket, string reason = "")
    {
        if(!PositionSelectByTicket(ticket))
        {
            Print(StringFormat("[GridExec] Position #%I64u not found", ticket));
            return false;
        }
        
        bool closed = m_trade.PositionClose(ticket);
        
        if(closed)
        {
            Print(StringFormat("[GridExec] ✅ Closed #%I64u | Reason: %s", 
                              ticket, 
                              reason == "" ? "None" : reason));
            return true;
        }
        else
        {
            uint error_code = GetLastError();
            Print(StringFormat("[GridExec] ❌ Failed to close #%I64u | Error: %d", 
                              ticket, 
                              error_code));
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Modify Grid Position (SL/TP)                                   |
    //+------------------------------------------------------------------+
    bool ModifyGridPosition(ulong ticket, double new_sl, double new_tp)
    {
        if(!PositionSelectByTicket(ticket))
            return false;
            
        double current_sl = PositionGetDouble(POSITION_SL);
        double current_tp = PositionGetDouble(POSITION_TP);
        
        // Check if modification needed
        if(MathAbs(current_sl - new_sl) < _Point && MathAbs(current_tp - new_tp) < _Point)
            return true; // No change needed
            
        bool modified = m_trade.PositionModify(ticket, new_sl, new_tp);
        
        if(modified)
        {
            Print(StringFormat("[GridExec] ✅ Modified #%I64u | SL: %.5f | TP: %.5f", 
                              ticket, new_sl, new_tp));
            return true;
        }
        else
        {
            Print(StringFormat("[GridExec] ❌ Failed to modify #%I64u", ticket));
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Execution Statistics                                        |
    //+------------------------------------------------------------------+
    string GetStatistics()
    {
        double success_rate = (m_total_executions > 0) ? 
                              (double)m_successful_executions / m_total_executions * 100.0 : 0.0;
        
        return StringFormat("Executions: %d | Success: %d (%.1f%%) | Failed: %d | Avg Slippage: %.1f pts",
                           m_total_executions,
                           m_successful_executions,
                           success_rate,
                           m_failed_executions,
                           m_avg_slippage);
    }

private:
    //+------------------------------------------------------------------+
    //| Check if Error is Retryable                                     |
    //+------------------------------------------------------------------+
    bool ShouldRetry(uint error_code)
    {
        switch(error_code)
        {
            // Retryable errors
            case 4:    // ERR_SERVER_BUSY
            case 6:    // ERR_NO_CONNECTION
            case 128:  // ERR_TRADE_TIMEOUT
            case 129:  // ERR_INVALID_PRICE
            case 135:  // ERR_PRICE_CHANGED
            case 136:  // ERR_OFF_QUOTES
            case 137:  // ERR_BROKER_BUSY
            case 138:  // ERR_REQUOTE
            case 146:  // ERR_TRADE_CONTEXT_BUSY
                return true;
                
            // Non-retryable errors
            case 131:  // ERR_INVALID_TRADE_VOLUME
            case 134:  // ERR_NOT_ENOUGH_MONEY
            case 139:  // ERR_ORDER_LOCKED
            case 141:  // ERR_TOO_MANY_REQUESTS
            default:
                return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Error Description                                           |
    //+------------------------------------------------------------------+
    string GetErrorDescription(uint error_code)
    {
        switch(error_code)
        {
            case 4:    return "Server busy";
            case 6:    return "No connection";
            case 128:  return "Trade timeout";
            case 129:  return "Invalid price";
            case 131:  return "Invalid volume";
            case 134:  return "Not enough money";
            case 135:  return "Price changed";
            case 136:  return "Off quotes";
            case 137:  return "Broker busy";
            case 138:  return "Requote";
            case 139:  return "Order locked";
            case 141:  return "Too many requests";
            case 146:  return "Trade context busy";
            default:   return "Unknown error";
        }
    }
    
    //+------------------------------------------------------------------+
    //| Update Slippage Statistics                                      |
    //+------------------------------------------------------------------+
    void UpdateSlippageStats(double slippage)
    {
        if(m_successful_executions == 1)
        {
            m_avg_slippage = slippage;
        }
        else
        {
            // Exponential moving average
            m_avg_slippage = m_avg_slippage * 0.8 + slippage * 0.2;
        }
    }
};
//+------------------------------------------------------------------+
