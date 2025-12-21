//+------------------------------------------------------------------+
//|                         GridStandalone/Strategy_Grid_Standalone.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                                Main Strategy Wrapper                     |
//+------------------------------------------------------------------+
#property strict

#include "RiskGuardian.mqh"
#include "ServerComm.mqh"

//+------------------------------------------------------------------+
//| Standalone Grid Strategy                                         |
//+------------------------------------------------------------------+
class CStrategyGridStandalone : public CRiskGuardian
{
private:
    // Communication (optional)
    CServerCommunication m_comm;
    
    // State
    bool              m_initialized;
    datetime          m_last_analysis_time;
    datetime          m_last_update_time;
    int               m_analysis_interval;    // 60 seconds
    int               m_update_interval;      // 5 seconds
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CStrategyGridStandalone() : CRiskGuardian()
    {
        m_initialized = false;
        m_last_analysis_time = 0;
        m_last_update_time = 0;
        m_analysis_interval = 60;      // Analyze every 60 seconds
        m_update_interval = 5;         // Update every 5 seconds
    }
    
    //+------------------------------------------------------------------+
    //| Initialize Strategy                                              |
    //+------------------------------------------------------------------+
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        Print("═══════════════════════════════════════");
        Print("  STANDALONE GRID STRATEGY");
        Print("  Version: 1.0");
        Print("  Mode: 100% Standalone");
        Print("═══════════════════════════════════════");
        
        // Initialize indicators
        if(!InitializeIndicators(symbol, timeframe))
        {
            Print("[Strategy] ❌ Failed to initialize indicators");
            return false;
        }
        
        // Initialize communication (optional)
        m_comm.Disable();  // Start in standalone mode
        
        m_initialized = true;
        
        Print("[Strategy] ✅ Initialized successfully");
        Print("  Symbol: ", symbol);
        Print("  Timeframe: ", EnumToString(timeframe));
        Print("  Max Grid Levels: ", m_max_grid_levels);
        Print("  Base Step: ", m_base_step_points, " points");
        Print("  Base Lot: ", m_base_lot);
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Main Strategy Loop (Call from OnTimer or OnTick)                 |
    //+------------------------------------------------------------------+
    void ProcessTick()
    {
        if(!m_initialized)
            return;
        
        datetime current = TimeCurrent();
        
        // Update grid state (every tick)
        if(m_active_grid_count > 0)
        {
            UpdateGridState();
            
            // Apply trailing stops
            for(int i = 0; i < m_active_grid_count; i++)
            {
                TrailingStop(i);
            }
        }
        
        // Check for exits (every tick if grid active)
        if(m_active_grid_count > 0)
        {
            // Check emergency exits first
            if(CheckEmergencyExit())
            {
                ExecuteGridExit();
                return;
            }
            
            // Check normal exits
            if(ShouldExitGrid())
            {
                double pnl = GetTotalFloatingPnL();
                ExecuteGridExit();
                RecordGridClose(pnl);
                return;
            }
            
            // Check if should open next level
            if(ShouldOpenNextLevel())
            {
                int next_level = m_active_grid_count;
                if(OpenGridLevel(next_level))
                {
                    Print("[Strategy] Level ", next_level, " opened");
                }
            }
        }
        
        // Market analysis (every 60 seconds)
        if((current - m_last_analysis_time) >= m_analysis_interval)
        {
            AnalyzeMarket();
            m_last_analysis_time = current;
        }
        
        // Entry check (only if no active grid)
        if(m_active_grid_count == 0)
        {
            if(ShouldEnterGrid())
            {
                // Calculate elastic step before opening
                CalculateElasticStep();
                
                // Open first level
                if(OpenGridLevel(0))
                {
                    m_total_grids_opened++;
                    Print("[Strategy] 🚀 New grid started: ", m_grid_id);
                    
                    // Send report to server (if connected)
                    m_comm.SendGridOpenReport(m_grid_id, 0, 
                                            m_grid_orders[0].ticket,
                                            m_grid_orders[0].open_price,
                                            m_grid_orders[0].lot_size);
                }
            }
        }
        
        // Status update (every 5 seconds)
        if((current - m_last_update_time) >= m_update_interval)
        {
            PrintStatus();
            m_last_update_time = current;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Print Status                                                     |
    //+------------------------------------------------------------------+
    void PrintStatus()
    {
        if(m_active_grid_count > 0)
        {
            double total_pnl = GetTotalFloatingPnL();
            int duration = (int)((TimeCurrent() - m_grid_start_time) / 60);
            
            Print("┌────────────────────────────────────┐");
            Print("│  GRID ACTIVE: ", m_grid_id);
            Print("├────────────────────────────────────┤");
            Print("│  Direction: ", EnumToString(m_current_direction));
            Print("│  Levels: ", m_active_grid_count, "/", m_max_grid_levels);
            Print("│  Floating PnL: $", DoubleToString(total_pnl, 2));
            Print("│  Highest: $", DoubleToString(m_highest_pnl, 2));
            Print("│  Duration: ", duration, " min");
            Print("│  Elastic: ", DoubleToString(m_current_elastic_step, 1), " pts");
            Print("└────────────────────────────────────┘");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Dashboard Data                                               |
    //+------------------------------------------------------------------+
    string GetDashboard()
    {
        string dashboard = "\n";
        dashboard += "╔═══════════════════════════════════════╗\n";
        dashboard += "║  STANDALONE GRID STRATEGY DASHBOARD   ║\n";
        dashboard += "╚═══════════════════════════════════════╝\n";
        dashboard += "\n";
        
        // Market State
        dashboard += "MARKET STATE:\n";
        dashboard += "─────────────────────────────────────\n";
        dashboard += "State: " + EnumToString(m_current_market_state) + "\n";
        dashboard += StringFormat("ATR: %.1f (%.1fx ref)\n", 
                                m_atr_current, m_volatility_ratio);
        
        if(m_is_ranging)
            dashboard += "Trend: Ranging ✅\n";
        else if(m_is_trending)
            dashboard += "Trend: Trending ⚠️\n";
        
        dashboard += "\n";
        
        // Grid Status
        if(m_active_grid_count > 0)
        {
            double total_pnl = GetTotalFloatingPnL();
            int duration = (int)((TimeCurrent() - m_grid_start_time) / 60);
            
            dashboard += "ACTIVE GRID:\n";
            dashboard += "─────────────────────────────────────\n";
            dashboard += "ID: " + m_grid_id + "\n";
            dashboard += "Direction: " + EnumToString(m_current_direction) + "\n";
            dashboard += StringFormat("Levels: %d/%d\n", 
                                    m_active_grid_count, m_max_grid_levels);
            dashboard += StringFormat("Floating PnL: $%.2f\n", total_pnl);
            dashboard += StringFormat("Highest: $%.2f\n", m_highest_pnl);
            dashboard += StringFormat("Duration: %d min\n", duration);
            dashboard += StringFormat("Elastic Step: %.1f pts\n", 
                                    m_current_elastic_step);
        }
        else
        {
            dashboard += "GRID STATUS: Waiting for entry\n";
        }
        
        dashboard += "\n";
        
        // Risk Status
        dashboard += GetRiskStatus();
        
        // Server Status
        dashboard += "SERVER: " + m_comm.GetStatus() + "\n";
        dashboard += "\n";
        
        return dashboard;
    }
    
    //+------------------------------------------------------------------+
    //| Enable Server Communication                                      |
    //+------------------------------------------------------------------+
    void EnableServerCommunication()
    {
        m_comm.Enable();
        Print("[Strategy] Server communication enabled");
    }
    
    //+------------------------------------------------------------------+
    //| Update From Server (Python Policy)                               |
    //+------------------------------------------------------------------+
    void UpdateFromServer()
    {
        if(!m_comm.IsConnected())
            return;
        
        double risk_mult, confidence;
        bool cooldown;
        
        if(m_comm.ReceivePolicyUpdate(risk_mult, cooldown, confidence))
        {
            SetPythonData(risk_mult, cooldown, confidence);
            Print("[Strategy] Policy update from server: Risk=", risk_mult, 
                  " Cooldown=", cooldown, " Confidence=", confidence);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Score (For compatibility with StrategyManager)               |
    //+------------------------------------------------------------------+
    double GetScore()
    {
        // If no grid active, check if should enter
        if(m_active_grid_count == 0)
        {
            if(ShouldEnterGrid())
            {
                return m_market_confidence;  // 0.0 - 1.0
            }
            return 0.0;
        }
        
        // If grid is active, return active signal
        return 0.5;  // Medium score to indicate grid is running
    }
    
    //+------------------------------------------------------------------+
    //| Manual Close (For emergency)                                     |
    //+------------------------------------------------------------------+
    void ManualClose()
    {
        if(m_active_grid_count > 0)
        {
            m_exit_reason = EXIT_MANUAL;
            double pnl = GetTotalFloatingPnL();
            ExecuteGridExit();
            RecordGridClose(pnl);
            
            Print("[Strategy] Manual close executed");
        }
    }
};
//+------------------------------------------------------------------+
