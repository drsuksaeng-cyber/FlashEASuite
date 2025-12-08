//+------------------------------------------------------------------+
//|                                        GridStandalone/GridExit.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                                Exit Management Module                    |
//+------------------------------------------------------------------+
#property strict

#include "GridExecution.mqh"

//+------------------------------------------------------------------+
//| Grid Exit Engine                                                  |
//+------------------------------------------------------------------+
class CGridExitEngine : public CGridExecutionEngine
{
private:
    // Reversal detection
    int               m_reversal_signals_count;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridExitEngine() : CGridExecutionEngine()
    {
        m_reversal_signals_count = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Main Exit Check                                                  |
    //+------------------------------------------------------------------+
    bool ShouldExitGrid()
    {
        if(m_active_grid_count == 0)
            return false;
        
        // Layer 1: Profit Target
        if(CheckProfitTarget())
        {
            m_exit_reason = EXIT_PROFIT_TARGET;
            return true;
        }
        
        // Layer 2: Trailing Stop
        if(CheckTrailingStop())
        {
            m_exit_reason = EXIT_TRAILING_STOP;
            return true;
        }
        
        // Layer 3: Reversal Exit
        if(CheckReversalExit())
        {
            m_exit_reason = EXIT_REVERSAL;
            return true;
        }
        
        // Layer 4: Time Exit
        if(CheckTimeExit())
        {
            m_exit_reason = EXIT_TIME_LIMIT;
            return true;
        }
        
        // Layer 5: Emergency Exits (will be checked by RiskGuardian)
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Layer 1: Check Profit Target                                     |
    //+------------------------------------------------------------------+
    bool CheckProfitTarget()
    {
        double total_pnl = GetTotalFloatingPnL();
        double total_risk = GetTotalRisk();
        
        // Target = Total Risk * Multiplier
        double target = total_risk * m_profit_target_mult;
        
        if(total_pnl >= target)
        {
            Print("[Exit] 🎯 PROFIT TARGET HIT!");
            Print("  Total PnL: $", DoubleToString(total_pnl, 2));
            Print("  Target: $", DoubleToString(target, 2));
            Print("  Risk: $", DoubleToString(total_risk, 2));
            
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Layer 2: Check Trailing Stop                                     |
    //+------------------------------------------------------------------+
    bool CheckTrailingStop()
    {
        double current_pnl = GetTotalFloatingPnL();
        
        // Only trail if we had profit
        if(m_highest_pnl <= 0)
            return false;
        
        // Check retracement
        double retracement_threshold = m_highest_pnl * m_trailing_threshold;
        
        if(current_pnl < retracement_threshold)
        {
            double retracement_percent = ((m_highest_pnl - current_pnl) / m_highest_pnl) * 100;
            
            Print("[Exit] 📉 TRAILING STOP TRIGGERED!");
            Print("  Highest PnL: $", DoubleToString(m_highest_pnl, 2));
            Print("  Current PnL: $", DoubleToString(current_pnl, 2));
            Print("  Retracement: ", DoubleToString(retracement_percent, 1), "%");
            
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Layer 3: Check Reversal Exit                                     |
    //+------------------------------------------------------------------+
    bool CheckReversalExit()
    {
        m_reversal_signals_count = 0;
        
        // For BUY Grid (looking for upward reversal)
        if(m_current_direction == GRID_DIR_BUY)
        {
            // Signal 1: Price crosses above MA(20)
            double ma_fast[2];
            if(CopyBuffer(m_ma_fast_handle, 0, 0, 2, ma_fast) > 0)
            {
                double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                if(price > ma_fast[0])
                    m_reversal_signals_count++;
            }
            
            // Signal 2: RSI above 60
            double rsi[1];
            if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) > 0)
            {
                if(rsi[0] > 60)
                    m_reversal_signals_count++;
            }
            
            // Signal 3: MACD bullish cross
            double macd[2], signal[2];
            if(CopyBuffer(m_macd_handle, 0, 0, 2, macd) > 0 &&
               CopyBuffer(m_macd_handle, 1, 0, 2, signal) > 0)
            {
                if(macd[0] > signal[0] && macd[1] <= signal[1])
                    m_reversal_signals_count++;
            }
            
            // Signal 4: Price breaks above resistance
            double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(price > m_nearest_resistance)
                m_reversal_signals_count++;
        }
        
        // For SELL Grid (looking for downward reversal)
        if(m_current_direction == GRID_DIR_SELL)
        {
            // Signal 1: Price crosses below MA(20)
            double ma_fast[2];
            if(CopyBuffer(m_ma_fast_handle, 0, 0, 2, ma_fast) > 0)
            {
                double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                if(price < ma_fast[0])
                    m_reversal_signals_count++;
            }
            
            // Signal 2: RSI below 40
            double rsi[1];
            if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) > 0)
            {
                if(rsi[0] < 40)
                    m_reversal_signals_count++;
            }
            
            // Signal 3: MACD bearish cross
            double macd[2], signal[2];
            if(CopyBuffer(m_macd_handle, 0, 0, 2, macd) > 0 &&
               CopyBuffer(m_macd_handle, 1, 0, 2, signal) > 0)
            {
                if(macd[0] < signal[0] && macd[1] >= signal[1])
                    m_reversal_signals_count++;
            }
            
            // Signal 4: Price breaks below support
            double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(price < m_nearest_support)
                m_reversal_signals_count++;
        }
        
        // Need 2+ signals for reversal
        if(m_reversal_signals_count >= 2)
        {
            Print("[Exit] 🔄 REVERSAL DETECTED!");
            Print("  Direction: ", EnumToString(m_current_direction));
            Print("  Signals: ", m_reversal_signals_count, "/4");
            
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Layer 4: Check Time Exit                                         |
    //+------------------------------------------------------------------+
    bool CheckTimeExit()
    {
        datetime current = TimeCurrent();
        int hours_active = (int)((current - m_grid_start_time) / 3600);
        
        // Max duration check
        if(hours_active >= m_max_duration_hours)
        {
            double total_pnl = GetTotalFloatingPnL();
            double avg_pnl_per_hour = (hours_active > 0) ? total_pnl / hours_active : 0;
            
            Print("[Exit] ⏰ TIME LIMIT REACHED");
            Print("  Hours active: ", hours_active);
            Print("  Total PnL: $", DoubleToString(total_pnl, 2));
            Print("  Avg PnL/hour: $", DoubleToString(avg_pnl_per_hour, 2));
            
            // Close if profit OR poor performance
            if(total_pnl > 0 || avg_pnl_per_hour < 1.0)
            {
                return true;
            }
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Execute Grid Exit (Close All Positions)                          |
    //+------------------------------------------------------------------+
    bool ExecuteGridExit()
    {
        Print("[Exit] Closing all grid orders...");
        Print("  Reason: ", EnumToString(m_exit_reason));
        
        double total_pnl = 0.0;
        int closed_count = 0;
        
        // Close all positions
        for(int i = 0; i < m_active_grid_count; i++)
        {
            ulong ticket = m_grid_orders[i].ticket;
            
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                total_pnl += profit;
                
                if(m_trade.PositionClose(ticket))
                {
                    closed_count++;
                    Print("  ✅ Closed Level ", i, " Ticket: ", ticket, 
                          " Profit: $", DoubleToString(profit, 2));
                }
                else
                {
                    Print("  ❌ Failed to close Level ", i, " Ticket: ", ticket);
                }
            }
        }
        
        // Calculate statistics
        datetime exit_time = TimeCurrent();
        int duration_hours = (int)((exit_time - m_grid_start_time) / 3600);
        
        Print("[Exit] GRID CLOSED:");
        Print("  Total PnL: $", DoubleToString(total_pnl, 2));
        Print("  Orders closed: ", closed_count);
        Print("  Duration: ", duration_hours, " hours");
        Print("  Exit reason: ", EnumToString(m_exit_reason));
        
        // Reset state
        ResetGridState();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get Exit Reason                                                  |
    //+------------------------------------------------------------------+
    ENUM_EXIT_REASON GetExitReason()
    {
        return m_exit_reason;
    }
    
    //+------------------------------------------------------------------+
    //| Get Reversal Signals Count                                       |
    //+------------------------------------------------------------------+
    int GetReversalSignalsCount()
    {
        return m_reversal_signals_count;
    }
};
//+------------------------------------------------------------------+
