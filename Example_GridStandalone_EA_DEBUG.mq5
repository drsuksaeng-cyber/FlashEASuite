//+------------------------------------------------------------------+
//|                   Example_GridStandalone_EA_PRINT_DEBUG.mq5      |
//|                              Debug version with Print() only     |
//|                              No file operations, just terminal   |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00 PRINT_DEBUG"
#property strict

// Include the main strategy
#include "Include/Logic/Grid/GridStandalone/Strategy_Grid_Standalone.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int    InpMaxGridLevels      = 3;      // Maximum grid levels
input double InpBaseStepPoints     = 200;    // Base step (points)
input double InpBaseLot            = 0.01;   // Base lot size
input int    InpTimerInterval      = 5000;   // Timer interval (ms)
input bool   InpEnableServer       = false;  // Enable Python server

// Global variables
CStrategyGridStandalone* g_Strategy = NULL;
int g_debug_counter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════════════════════");
    Print("  PRINT DEBUG VERSION - Using Print() only");
    Print("  No CSV files, check Experts tab for all logs");
    Print("═══════════════════════════════════════════════════════");
    
    Print("[INIT] Starting initialization...");
    Print("[INIT] Symbol: ", _Symbol);
    Print("[INIT] Parameters:");
    Print("  - Max Levels: ", InpMaxGridLevels);
    Print("  - Base Step: ", InpBaseStepPoints);
    Print("  - Base Lot: ", InpBaseLot);
    Print("  - Timer: ", InpTimerInterval, " ms");
    Print("  - Server: ", InpEnableServer ? "Enabled" : "Disabled");
    
    // Create strategy instance
    Print("[INIT] Creating strategy instance...");
    g_Strategy = new CStrategyGridStandalone();
    
    if(g_Strategy == NULL)
    {
        Print("[ERROR] Failed to create strategy instance!");
        return INIT_FAILED;
    }
    Print("[INIT] ✅ Strategy instance created");
    
    // Update configuration
    Print("[INIT] Updating configuration...");
    g_Strategy.UpdateConfig(InpMaxGridLevels, InpBaseStepPoints, InpBaseLot);
    Print("[INIT] ✅ Configuration updated");
    
    // Initialize strategy
    Print("[INIT] Initializing strategy...");
    if(!g_Strategy.Initialize(_Symbol, PERIOD_M15))
    {
        Print("[ERROR] Strategy initialization failed!");
        delete g_Strategy;
        return INIT_FAILED;
    }
    Print("[INIT] ✅ Strategy initialized");
    
    // Enable server if requested
    if(InpEnableServer)
    {
        Print("[INIT] Enabling server communication...");
        g_Strategy.EnableServerCommunication();
        Print("[INIT] ✅ Server enabled");
    }
    
    // Start timer
    Print("[INIT] Starting timer (", InpTimerInterval, " ms)...");
    EventSetMillisecondTimer(InpTimerInterval);
    Print("[INIT] ✅ Timer started");
    
    Print("═══════════════════════════════════════════════════════");
    Print("  ✅ INITIALIZATION COMPLETE");
    Print("  Mode: ", InpEnableServer ? "Enhanced" : "Standalone");
    Print("  Ready to trade!");
    Print("═══════════════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("═══════════════════════════════════════════════════════");
    Print("  EA Stopping...");
    Print("  Reason code: ", reason);
    
    string reason_text = "";
    switch(reason)
    {
        case REASON_PROGRAM:     reason_text = "EA terminated"; break;
        case REASON_REMOVE:      reason_text = "EA removed from chart"; break;
        case REASON_RECOMPILE:   reason_text = "EA recompiled"; break;
        case REASON_CHARTCHANGE: reason_text = "Symbol/timeframe changed"; break;
        case REASON_CHARTCLOSE:  reason_text = "Chart closed"; break;
        case REASON_PARAMETERS:  reason_text = "Parameters changed"; break;
        case REASON_ACCOUNT:     reason_text = "Account changed"; break;
        default:                 reason_text = "Unknown"; break;
    }
    Print("  Reason: ", reason_text);
    Print("═══════════════════════════════════════════════════════");
    
    EventKillTimer();
    Print("[DEINIT] Timer stopped");
    
    if(g_Strategy != NULL)
    {
        Print("[DEINIT] Getting final dashboard...");
        string dashboard = g_Strategy.GetDashboard();
        Print("═══════════════════════════════════════════════════════");
        Print(dashboard);
        Print("═══════════════════════════════════════════════════════");
        
        Print("[DEINIT] Deleting strategy instance...");
        delete g_Strategy;
        g_Strategy = NULL;
        Print("[DEINIT] ✅ Strategy deleted");
    }
    
    Print("  ✅ Cleanup complete");
    Print("  Total debug calls: ", g_debug_counter);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    g_debug_counter++;
    
    // Print every 100 ticks
    if(g_debug_counter % 100 == 1)
    {
        Print("[TICK #", g_debug_counter, "] OnTick() called");
        Print("  Current price: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
    }
    
    if(g_Strategy == NULL)
    {
        if(g_debug_counter == 1)
        {
            Print("[ERROR] OnTick() called but g_Strategy is NULL!");
        }
        return;
    }
    
    // Log every 100 ticks
    if(g_debug_counter % 100 == 1)
    {
        Print("[TICK #", g_debug_counter, "] Calling g_Strategy.ProcessTick()");
    }
    
    // Main strategy processing
    g_Strategy.ProcessTick();
    
    // Show dashboard every 500 ticks
    if(g_debug_counter % 500 == 0)
    {
        Print("───────────────────────────────────────────────────────");
        Print("[DASHBOARD] After ", g_debug_counter, " ticks:");
        string dashboard = g_Strategy.GetDashboard();
        Print(dashboard);
        Print("───────────────────────────────────────────────────────");
    }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    static int timer_count = 0;
    timer_count++;
    
    // Print every 50 timer calls
    if(timer_count % 50 == 1)
    {
        Print("[TIMER #", timer_count, "] OnTimer() called");
    }
    
    if(g_Strategy == NULL)
        return;
    
    // Update from server (if connected)
    if(InpEnableServer)
    {
        if(timer_count % 50 == 1)
        {
            Print("[TIMER #", timer_count, "] Calling UpdateFromServer()");
        }
        g_Strategy.UpdateFromServer();
    }
}

//+------------------------------------------------------------------+
//| Trade function (for tester)                                      |
//+------------------------------------------------------------------+
double OnTester()
{
    Print("═══════════════════════════════════════════════════════");
    Print("[TESTER] OnTester() called");
    
    if(g_Strategy == NULL)
    {
        Print("[ERROR] OnTester() called but g_Strategy is NULL!");
        return 0.0;
    }
    
    Print("[TESTER] Getting final metrics...");
    
    double win_rate = g_Strategy.GetWinRate();
    double profit_factor = g_Strategy.GetProfitFactor();
    double max_dd = g_Strategy.GetCurrentDrawdown();
    
    Print("[TESTER] Win Rate: ", win_rate, "%");
    Print("[TESTER] Profit Factor: ", profit_factor);
    Print("[TESTER] Max DD: ", max_dd, "%");
    
    // Combined score
    double score = (win_rate / 100.0) * profit_factor * (1.0 - (max_dd / 100.0));
    
    Print("[TESTER] Calculated Score: ", score);
    Print("═══════════════════════════════════════════════════════");
    
    return score;
}
//+------------------------------------------------------------------+
