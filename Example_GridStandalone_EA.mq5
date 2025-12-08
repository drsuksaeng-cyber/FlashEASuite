//+------------------------------------------------------------------+
//|                                   Example_GridStandalone_EA.mq5   |
//|                                      FlashEASuite V2 - Example EA  |
//|                        Demonstrates Standalone Grid Strategy Usage |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

// ✅ CORRECTED: Include from Include folder using angle brackets
#include "Include/Logic/Grid/GridStandalone/Strategy_Grid_Standalone.mqh"
//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Grid Parameters ==="
input int      InpMaxGridLevels = 5;              // Max Grid Levels
input double   InpBaseStepPoints = 200.0;         // Base Step (points)
input double   InpBaseLot = 0.01;                 // Base Lot Size
input double   InpATRReference = 30.0;            // ATR Reference

input group "=== Risk Management ==="
input double   InpMaxDD = 15.0;                   // Max Drawdown %
input double   InpAvgDDTarget = 8.0;              // Avg DD Target %
input double   InpDailyLossLimit = 3.0;           // Daily Loss Limit %
input double   InpMaxRiskPerGrid = 2.0;           // Max Risk Per Grid %

input group "=== Exit Parameters ==="
input double   InpProfitTargetMult = 1.5;         // Profit Target Multiplier
input double   InpTrailingThreshold = 0.7;        // Trailing Threshold (70%)
input int      InpMaxDurationHours = 72;          // Max Duration (hours)

input group "=== Server Communication ==="
input bool     InpEnableServer = false;           // Enable Python Server

input group "=== Update Intervals ==="
input int      InpTimerInterval = 100;            // Timer Interval (ms)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CStrategyGridStandalone* g_Strategy;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════");
    Print("  STANDALONE GRID STRATEGY EA");
    Print("  Starting initialization...");
    Print("═══════════════════════════════════════");
    
    // Create strategy instance
    g_Strategy = new CStrategyGridStandalone();
    if(g_Strategy == NULL)
    {
        Print("ERROR: Failed to create strategy instance");
        return INIT_FAILED;
    }
    
    // Update configuration
    g_Strategy.UpdateConfig(InpMaxGridLevels, InpBaseStepPoints, InpBaseLot);
    
    // Initialize strategy
    if(!g_Strategy.Initialize(_Symbol, PERIOD_M15))
    {
        Print("ERROR: Strategy initialization failed");
        delete g_Strategy;
        return INIT_FAILED;
    }
    
    // Enable server communication if requested
    if(InpEnableServer)
    {
        g_Strategy.EnableServerCommunication();
    }
    
    // Start timer
    EventSetMillisecondTimer(InpTimerInterval);
    
    Print("═══════════════════════════════════════");
    Print("  ✅ INITIALIZATION COMPLETE");
    Print("  Symbol: ", _Symbol);
    Print("  Timeframe: M15");
    Print("  Mode: ", InpEnableServer ? "Enhanced (with Python)" : "Standalone");
    Print("═══════════════════════════════════════");
    
    // Print initial dashboard
    Print(g_Strategy.GetDashboard());
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    Print("═══════════════════════════════════════");
    Print("  EA Stopping...");
    Print("  Reason: ", reason);
    Print("═══════════════════════════════════════");
    
    // Print final statistics
    if(g_Strategy != NULL)
    {
        Print(g_Strategy.GetDashboard());
        delete g_Strategy;
        g_Strategy = NULL;
    }
    
    Print("  ✅ Cleanup complete");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(g_Strategy == NULL)
        return;
    
    // Main strategy processing
    g_Strategy.ProcessTick();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(g_Strategy == NULL)
        return;
    
    // Update from server (if connected)
    if(InpEnableServer)
    {
        g_Strategy.UpdateFromServer();
    }
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // Handle chart events (e.g., manual close button)
    if(id == CHARTEVENT_KEYDOWN)
    {
        // Press 'C' to manually close grid
        if(lparam == 67)  // 'C' key
        {
            if(g_Strategy != NULL)
            {
                Print("Manual close triggered by user");
                g_Strategy.ManualClose();
            }
        }
        
        // Press 'S' to show status
        if(lparam == 83)  // 'S' key
        {
            if(g_Strategy != NULL)
            {
                Print(g_Strategy.GetDashboard());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade function (for tester)                                      |
//+------------------------------------------------------------------+
double OnTester()
{
    if(g_Strategy == NULL)
        return 0.0;
    
    // Calculate custom metric for optimization
    double win_rate = g_Strategy.GetWinRate();
    double profit_factor = g_Strategy.GetProfitFactor();
    double max_dd = g_Strategy.GetCurrentDrawdown();
    
    // Combined score
    double score = (win_rate / 100.0) * profit_factor * (1.0 - (max_dd / 100.0));
    
    return score;
}
//+------------------------------------------------------------------+
