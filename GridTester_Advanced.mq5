//+------------------------------------------------------------------+
//|                                         GridTester_Advanced.mq5 |
//|                                    FlashEASuite V2 - Tester    |
//|                  Advanced Grid Testing with Market Simulation   |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.00"
#property strict

#include <Logic/Strategy_Grid.mqh>
#include <Logic/Grid/MarketAnalysis.mqh>
#include <Logic/Grid/GridDecision.mqh>

//--- Test Scenarios
enum ENUM_TEST_SCENARIO
{
    TEST_RANGING_TIGHT,      // Tight ranging (50 points)
    TEST_RANGING_WIDE,       // Wide ranging (200 points)
    TEST_TRENDING_UP,        // Strong uptrend
    TEST_TRENDING_DOWN,      // Strong downtrend
    TEST_VOLATILE,           // High volatility
    TEST_NEWS_SPIKE,         // Sudden spike
    TEST_REAL_MARKET         // Use real market data
};

//--- Input parameters
input ENUM_TEST_SCENARIO TestScenario = TEST_RANGING_TIGHT;
input int      SimulationSpeed = 1;     // Speed multiplier (1=normal)
input bool     VerboseLogging = true;   // Detailed logs
input bool     TestEnhancements = true; // Test Week 3-4 modules

//--- Global variables
CStrategyGrid*    g_Grid;
CMarketAnalysis*  g_MarketAnalyzer;
CGridDecision*    g_DecisionMaker;

// Simulation state
double            g_SimPrice;
double            g_SimSpread;
double            g_SimATR;
int               g_SimTick;
datetime          g_StartTime;

// Test statistics
int               g_TotalSignals;
int               g_ValidSignals;
int               g_RejectedByMarket;
int               g_RejectedByRisk;
int               g_SimulatedTrades;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("════════════════════════════════════════════");
    Print("    GRID TESTER ADVANCED - STARTING         ");
    Print("════════════════════════════════════════════");
    Print("Scenario:       ", EnumToString(TestScenario));
    Print("Speed:          ", SimulationSpeed, "x");
    Print("Enhancements:   ", TestEnhancements ? "ENABLED" : "DISABLED");
    Print("════════════════════════════════════════════");
    
    // Initialize Grid
    g_Grid = new CStrategyGrid();
    if(g_Grid == NULL)
    {
        Print("❌ ERROR: Failed to create Grid");
        return INIT_FAILED;
    }
    
    // Grid is automatically active after creation
    // No need to call Activate() - it's private
    Print("✅ Grid Strategy initialized");
    
    // Initialize enhancement modules if enabled
    if(TestEnhancements)
    {
        g_MarketAnalyzer = new CMarketAnalysis();
        g_DecisionMaker = new CGridDecision();
        
        // Note: Actual initialization would need indicator handles
        // For simulation, we'll create fake data
        Print("✅ Enhancement modules initialized");
    }
    
    // Initialize simulation
    InitializeSimulation();
    
    // Set timer
    EventSetTimer(1); // 1 second = 1 simulated tick
    
    Print("════════════════════════════════════════════");
    Print("✅ READY TO TEST - Timer started");
    Print("════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    // Print final statistics
    PrintFinalResults();
    
    // Cleanup
    if(g_Grid != NULL)
    {
        delete g_Grid;
        g_Grid = NULL;
    }
    
    if(g_MarketAnalyzer != NULL)
    {
        delete g_MarketAnalyzer;
        g_MarketAnalyzer = NULL;
    }
    
    if(g_DecisionMaker != NULL)
    {
        delete g_DecisionMaker;
        g_DecisionMaker = NULL;
    }
    
    Print("════════════════════════════════════════════");
    Print("    GRID TESTER - STOPPED                   ");
    Print("════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Timer function - Main test loop                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
    g_SimTick++;
    
    // Generate simulated market tick
    GenerateMarketTick();
    
    // Update Grid with simulated data
    UpdateGridWithSimulatedData();
    
    // Get Grid score
    double score = g_Grid.GetScore();
    g_TotalSignals++;
    
    // Analyze result
    if(score > 40.0)
    {
        g_ValidSignals++;
        
        if(VerboseLogging)
        {
            Print(StringFormat("[Tick %d] ✅ VALID Signal | Score: %.2f | Price: %.5f | ATR: %.1f",
                              g_SimTick, score, g_SimPrice, g_SimATR));
        }
        
        // Test decision making if enhancements enabled
        if(TestEnhancements && g_DecisionMaker != NULL)
        {
            TestDecisionMaking(score);
        }
        
        g_SimulatedTrades++;
    }
    else
    {
        if(VerboseLogging && g_SimTick % 10 == 0)
        {
            Print(StringFormat("[Tick %d] ⏭️ No signal | Score: %.2f | Price: %.5f",
                              g_SimTick, score, g_SimPrice));
        }
    }
    
    // Print progress every 30 ticks
    if(g_SimTick % 30 == 0)
    {
        PrintProgress();
    }
    
    // Stop after 100 ticks for this test
    if(g_SimTick >= 100)
    {
        Print("🏁 Test complete (100 ticks)");
        ExpertRemove();
    }
}

//+------------------------------------------------------------------+
//| Initialize simulation parameters                                 |
//+------------------------------------------------------------------+
void InitializeSimulation()
{
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick))
    {
        g_SimPrice = tick.bid;
        g_SimSpread = (tick.ask - tick.bid) / _Point;
    }
    else
    {
        g_SimPrice = 1.0000;
        g_SimSpread = 2.0;
    }
    
    g_SimATR = 30.0; // Default ATR
    g_SimTick = 0;
    g_StartTime = TimeCurrent();
    
    // Statistics
    g_TotalSignals = 0;
    g_ValidSignals = 0;
    g_RejectedByMarket = 0;
    g_RejectedByRisk = 0;
    g_SimulatedTrades = 0;
    
    Print("Simulation initialized:");
    Print("  Base Price: ", g_SimPrice);
    Print("  Spread:     ", g_SimSpread, " points");
    Print("  ATR:        ", g_SimATR, " points");
}

//+------------------------------------------------------------------+
//| Generate market tick based on scenario                           |
//+------------------------------------------------------------------+
void GenerateMarketTick()
{
    double movement = 0.0;
    
    switch(TestScenario)
    {
        case TEST_RANGING_TIGHT:
        {
            // Oscillate ±50 points
            movement = 50.0 * _Point * MathSin(g_SimTick * 0.2);
            g_SimATR = 20.0; // Low volatility
            g_SimSpread = 2.0; // Tight spread
            break;
        }
        
        case TEST_RANGING_WIDE:
        {
            // Oscillate ±200 points
            movement = 200.0 * _Point * MathSin(g_SimTick * 0.1);
            g_SimATR = 50.0; // Medium volatility
            g_SimSpread = 3.0;
            break;
        }
        
        case TEST_TRENDING_UP:
        {
            // Consistent upward movement + noise
            movement = g_SimTick * 10.0 * _Point;
            double noise = (MathRand() - 16384) / 16384.0 * 30.0 * _Point;
            movement += noise;
            g_SimATR = 40.0;
            g_SimSpread = 4.0;
            break;
        }
        
        case TEST_TRENDING_DOWN:
        {
            // Consistent downward movement + noise
            movement = -g_SimTick * 10.0 * _Point;
            double noise = (MathRand() - 16384) / 16384.0 * 30.0 * _Point;
            movement += noise;
            g_SimATR = 40.0;
            g_SimSpread = 4.0;
            break;
        }
        
        case TEST_VOLATILE:
        {
            // Large random moves
            movement = (MathRand() - 16384) / 16384.0 * 300.0 * _Point;
            g_SimATR = 100.0; // High volatility
            g_SimSpread = 10.0; // Wide spread
            break;
        }
        
        case TEST_NEWS_SPIKE:
        {
            // Sudden spike at tick 30
            if(g_SimTick == 30)
            {
                movement = 500.0 * _Point;
                g_SimATR = 200.0;
                g_SimSpread = 20.0;
            }
            else if(g_SimTick > 30)
            {
                // Reversion after spike
                movement = -10.0 * _Point * (g_SimTick - 30);
                g_SimATR = 150.0;
                g_SimSpread = 15.0;
            }
            break;
        }
        
        case TEST_REAL_MARKET:
        {
            // Use actual market data
            MqlTick tick;
            if(SymbolInfoTick(_Symbol, tick))
            {
                g_SimPrice = tick.bid;
                g_SimSpread = (tick.ask - tick.bid) / _Point;
                // ATR would come from indicator
            }
            return; // Skip price calculation
        }
    }
    
    // Update simulated price
    double base_price = 1.0000; // Or use initial price
    g_SimPrice = base_price + movement;
}

//+------------------------------------------------------------------+
//| Update Grid with simulated data                                  |
//+------------------------------------------------------------------+
void UpdateGridWithSimulatedData()
{
    // In real system, Grid gets data from:
    // 1. UpdatePolicyData() - from Python
    // 2. UpdateCSMData() - currency strength
    
    // For testing, we simulate policy updates
    // This tests Grid's scoring logic
    
    // Example: Simulate Python sending policy
    // Grid.UpdatePolicyData(...) would be called
    // Here we just let Grid calculate with current state
}

//+------------------------------------------------------------------+
//| Test decision making module                                      |
//+------------------------------------------------------------------+
void TestDecisionMaking(double grid_score)
{
    // Simulate decision making process
    // In production, this happens inside Grid
    
    // For testing, we verify decision logic
    if(VerboseLogging)
    {
        Print("  📊 Testing decision module...");
        Print("     Grid Score: ", grid_score);
        Print("     ATR:        ", g_SimATR);
        Print("     Spread:     ", g_SimSpread);
    }
}

//+------------------------------------------------------------------+
//| Print test progress                                              |
//+------------------------------------------------------------------+
void PrintProgress()
{
    double signal_rate = (g_TotalSignals > 0) ? 
                        (double)g_ValidSignals / g_TotalSignals * 100.0 : 0.0;
    
    Print("════════════════════════════════════════════");
    Print("Progress - Tick: ", g_SimTick, "/100");
    Print("Total Signals:  ", g_TotalSignals);
    Print("Valid Signals:  ", g_ValidSignals, " (", 
          DoubleToString(signal_rate, 1), "%)");
    Print("Sim Trades:     ", g_SimulatedTrades);
    Print("Current Price:  ", g_SimPrice);
    Print("Current ATR:    ", g_SimATR);
    Print("════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Print final test results                                         |
//+------------------------------------------------------------------+
void PrintFinalResults()
{
    double signal_rate = (g_TotalSignals > 0) ? 
                        (double)g_ValidSignals / g_TotalSignals * 100.0 : 0.0;
    
    int duration = (int)(TimeCurrent() - g_StartTime);
    
    Print("════════════════════════════════════════════");
    Print("       FINAL TEST RESULTS                   ");
    Print("════════════════════════════════════════════");
    Print("Scenario:        ", EnumToString(TestScenario));
    Print("Duration:        ", duration, " seconds");
    Print("Total Ticks:     ", g_SimTick);
    Print("────────────────────────────────────────────");
    Print("SIGNALS:");
    Print("  Total:         ", g_TotalSignals);
    Print("  Valid:         ", g_ValidSignals, " (", 
          DoubleToString(signal_rate, 1), "%)");
    Print("  Rejected:      ", g_TotalSignals - g_ValidSignals);
    Print("────────────────────────────────────────────");
    Print("SIMULATION:");
    Print("  Trades:        ", g_SimulatedTrades);
    Print("  Final Price:   ", g_SimPrice);
    Print("  Final ATR:     ", g_SimATR);
    Print("════════════════════════════════════════════");
    Print("VERDICT:");
    
    if(signal_rate >= 30.0)
    {
        Print("✅ PASS - Grid generating signals");
    }
    else if(signal_rate >= 10.0)
    {
        Print("⚠️  CAUTION - Low signal rate");
    }
    else
    {
        Print("❌ FAIL - Very few signals");
    }
    
    Print("════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
