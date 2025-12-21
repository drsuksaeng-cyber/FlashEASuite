//+------------------------------------------------------------------+
//|                                              GridTester.mq5      |
//|                                    FlashEASuite V2 - Tester     |
//|                        Test Grid Strategy Without Live Market    |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

#include <Logic/Strategy_Grid.mqh>

//--- Input parameters
input int      TestScenario = 1;        // 1=Ranging, 2=Trending, 3=Volatile
input bool     EnableAutoTrade = true;  // Enable auto trading simulation
input int      TestDuration = 60;       // Test duration (seconds)

//--- Global variables
CStrategyGrid* g_Grid;
datetime       g_StartTime;
int            g_TestCycle;
double         g_SimulatedPrice;
double         g_BasePrice;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== GridTester Starting ===");
    Print("Test Scenario: ", GetScenarioName(TestScenario));
    
    // Create Grid strategy
    g_Grid = new CStrategyGrid();
    if(g_Grid == NULL)
    {
        Print("ERROR: Failed to create Grid strategy");
        return INIT_FAILED;
    }
    
    // Activate Grid
    g_Grid.Activate();
    
    // Initialize test
    g_StartTime = TimeCurrent();
    g_TestCycle = 0;
    
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick))
    {
        g_BasePrice = tick.bid;
        g_SimulatedPrice = g_BasePrice;
    }
    
    // Set timer (1 second intervals)
    EventSetTimer(1);
    
    Print("✅ GridTester initialized");
    Print("Base Price: ", g_BasePrice);
    Print("Test will run for ", TestDuration, " seconds");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    if(g_Grid != NULL)
    {
        delete g_Grid;
        g_Grid = NULL;
    }
    
    Print("=== GridTester Stopped ===");
    Print("Test Cycles: ", g_TestCycle);
}

//+------------------------------------------------------------------+
//| Timer function - Simulate market                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
    g_TestCycle++;
    
    // Check if test duration exceeded
    if(TimeCurrent() - g_StartTime >= TestDuration)
    {
        Print("=== Test Duration Complete ===");
        PrintTestResults();
        ExpertRemove();
        return;
    }
    
    // Simulate price movement based on scenario
    SimulatePriceMovement();
    
    // Simulate policy update (CSM data)
    SimulatePolicyUpdate();
    
    // Calculate Grid score
    double score = g_Grid.GetScore();
    
    Print(StringFormat("[Cycle %d] Price: %.5f | Score: %.2f", 
                      g_TestCycle, g_SimulatedPrice, score));
    
    // If score high enough and auto-trade enabled
    if(score > 40.0 && EnableAutoTrade)
    {
        SimulateGridExecution();
    }
    
    // Print progress every 10 cycles
    if(g_TestCycle % 10 == 0)
    {
        PrintProgress();
    }
}

//+------------------------------------------------------------------+
//| Simulate price movement based on test scenario                  |
//+------------------------------------------------------------------+
void SimulatePriceMovement()
{
    double movement = 0.0;
    
    switch(TestScenario)
    {
        case 1: // Ranging market
        {
            // Oscillate around base price
            double amplitude = 100.0 * _Point; // ±100 points
            double frequency = 0.1;  // Slow oscillation
            movement = amplitude * MathSin(g_TestCycle * frequency);
            g_SimulatedPrice = g_BasePrice + movement;
            break;
        }
        
        case 2: // Trending market (up)
        {
            // Gradual upward trend
            movement = g_TestCycle * 5.0 * _Point;  // 5 points per cycle
            double noise = (MathRand() - 16384) / 16384.0 * 20.0 * _Point;
            g_SimulatedPrice = g_BasePrice + movement + noise;
            break;
        }
        
        case 3: // Volatile market
        {
            // Random large moves
            double volatility = 200.0 * _Point;
            movement = (MathRand() - 16384) / 16384.0 * volatility;
            g_SimulatedPrice += movement;
            break;
        }
        
        default:
            g_SimulatedPrice = g_BasePrice;
    }
}

//+------------------------------------------------------------------+
//| Simulate policy update (CSM data, confidence, etc.)            |
//+------------------------------------------------------------------+
void SimulatePolicyUpdate()
{
    // This simulates Python Brain sending policy
    // In real system, this comes from ZMQ
    
    // For testing, we'll update Grid's internal state directly
    // (This is a hack for testing purposes only!)
    
    // Simulate CSM data (ranging market = buy bias)
    switch(TestScenario)
    {
        case 1: // Ranging - both directions possible
            // Grid should activate
            break;
            
        case 2: // Trending up - buy bias
            // Grid might work but trending market
            break;
            
        case 3: // Volatile - Grid should be careful
            // High volatility
            break;
    }
    
    // Note: In production, Grid receives this via UpdatePolicyData()
    // Here we're just testing Grid's scoring logic
}

//+------------------------------------------------------------------+
//| Simulate Grid execution                                         |
//+------------------------------------------------------------------+
void SimulateGridExecution()
{
    // In real system, Grid would call OrderSend()
    // Here we just log what would happen
    
    Print(StringFormat("🎯 [SIMULATED] Grid would open order at %.5f", g_SimulatedPrice));
    
    // Could add:
    // - Track simulated positions
    // - Calculate simulated P&L
    // - Test grid level management
}

//+------------------------------------------------------------------+
//| Print test progress                                             |
//+------------------------------------------------------------------+
void PrintProgress()
{
    int elapsed = (int)(TimeCurrent() - g_StartTime);
    int remaining = TestDuration - elapsed;
    
    Print(StringFormat("⏱️ Progress: %d/%d seconds | Cycle: %d | Remaining: %d sec",
                      elapsed, TestDuration, g_TestCycle, remaining));
}

//+------------------------------------------------------------------+
//| Print final test results                                        |
//+------------------------------------------------------------------+
void PrintTestResults()
{
    Print("════════════════════════════════════");
    Print("       GRID TESTER RESULTS          ");
    Print("════════════════════════════════════");
    Print("Scenario:     ", GetScenarioName(TestScenario));
    Print("Test Cycles:  ", g_TestCycle);
    Print("Duration:     ", TestDuration, " seconds");
    Print("Base Price:   ", g_BasePrice);
    Print("Final Price:  ", g_SimulatedPrice);
    Print("Price Change: ", (g_SimulatedPrice - g_BasePrice) / _Point, " points");
    Print("════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Get scenario name                                               |
//+------------------------------------------------------------------+
string GetScenarioName(int scenario)
{
    switch(scenario)
    {
        case 1: return "Ranging Market";
        case 2: return "Trending Market";
        case 3: return "Volatile Market";
        default: return "Unknown";
    }
}
//+------------------------------------------------------------------+
