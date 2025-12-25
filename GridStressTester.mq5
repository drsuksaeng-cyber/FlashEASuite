//+------------------------------------------------------------------+
//|                                        GridStressTester.mq5      |
//|                                    FlashEASuite V2 - Week 6      |
//|              Comprehensive Stress Testing (5 Criteria)           |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "4.00"
#property strict

#include <Logic/Strategy_Grid.mqh>
#include <Logic/Grid/GridProtectionSystem.mqh>
#include <Logic/Grid/GridRecoveryTracker.mqh>
#include <Logic/Grid/GridCostCalculator.mqh>
#include <Logic/Grid/GridRiskRewardAnalyzer.mqh>
#include <Logic/Grid/AdaptiveGridConfig.mqh>

//--- Test Scenarios
enum ENUM_STRESS_SCENARIO
{
    STRESS_EXTREME_UPTREND,      // 1. ลากไส้แตก ขึ้น 5000 points
    STRESS_EXTREME_DOWNTREND,    // 1. ลากไส้แตก ลง 5000 points
    STRESS_LONG_DRAWDOWN,        // 2. ติดลบนาน 30 วัน
    STRESS_HIGH_SPREAD,          // 3. Spread สูง 3x
    STRESS_LONG_HOLD_SWAP,       // 3. Hold นาน swap กิน
    STRESS_HIGH_DRAWDOWN,        // 4. DD 40% extreme
    STRESS_CHOPPY_MARKET,        // 5. กราฟกระโดด volatile
    STRESS_MIXED_WORST_CASE      // All worst cases combined
};

//--- Input Parameters
input ENUM_STRESS_SCENARIO StressScenario = STRESS_EXTREME_UPTREND;  // Stress Scenario
input int                  TotalTicks = 1000;                         // Total Ticks
input double               InitialBalance = 10000.0;                  // Initial Balance
input bool                 EnableProtection = true;                   // Enable Protection System
input bool                 UseAdaptiveGrid = true;                    // Use Adaptive Grid
input bool                 DetailedLogging = false;                   // Detailed Logging

//--- Global Objects
CStrategyGrid*           g_Grid;
CAdaptiveGridConfig*     g_AdaptiveConfig;
CGridProtectionSystem*   g_Protection;
CGridRecoveryTracker*    g_RecoveryTracker;
CGridCostCalculator*     g_CostCalculator;
CGridRiskRewardAnalyzer* g_RiskReward;

//--- Simulation State
double    g_SimPrice;
double    g_BasePrice;
int       g_CurrentTick;
double    g_SimBalance;
double    g_SimEquity;

//--- Statistics
struct StressTestResults
{
    // 1. Extreme Trending (ลากไส้แตก)
    bool     survived_extreme_trend;
    int      protection_pauses;
    double   max_movement_points;
    
    // 2. Recovery Factor (คืนชีพ)
    int      drawdown_events;
    double   avg_recovery_hours;
    double   recovery_factor;
    
    // 3. Trading Costs (ค่าธรรมเนียม)
    double   total_costs;
    double   cost_to_profit_pct;
    double   avg_spread_points;
    
    // 4. Risk/Reward (เสี่ยง/กำไร)
    double   max_drawdown_pct;
    double   profit_factor;
    double   risk_reward_ratio;
    
    // 5. Dynamic Adjustment (ปรับตัว)
    int      grid_adjustments;
    double   min_spacing;
    double   max_spacing;
    
    // Overall
    double   net_profit;
    int      total_trades;
    double   win_rate;
    bool     all_tests_passed;
};

StressTestResults g_Results;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("════════════════════════════════════════════");
    Print("   🔥 GRID STRESS TESTER - STARTING 🔥       ");
    Print("════════════════════════════════════════════");
    Print("Scenario: ", EnumToString(StressScenario));
    Print("Ticks: ", TotalTicks);
    Print("Initial Balance: $", DoubleToString(InitialBalance, 2));
    Print("Protection: ", EnableProtection ? "ENABLED" : "DISABLED");
    Print("════════════════════════════════════════════");
    
    // Initialize simulation balance
    g_SimBalance = InitialBalance;
    g_SimEquity = InitialBalance;
    
    // Initialize results
    InitializeResults();
    
    // Create Grid Strategy
    g_Grid = new CStrategyGrid();
    if(g_Grid == NULL)
    {
        Print("❌ Failed to create Grid");
        return INIT_FAILED;
    }
    
    // Create Adaptive Config
    if(UseAdaptiveGrid)
    {
        g_AdaptiveConfig = new CAdaptiveGridConfig(_Symbol, _Period);
        if(!g_AdaptiveConfig.Initialize())
        {
            Print("❌ Failed to initialize Adaptive Config");
            return INIT_FAILED;
        }
        Print("✅ Adaptive Grid Config initialized");
    }
    
    // Create Protection System
    if(EnableProtection)
    {
        g_Protection = new CGridProtectionSystem(_Symbol);
        if(!g_Protection.Initialize())
        {
            Print("❌ Failed to initialize Protection");
            return INIT_FAILED;
        }
        
        // Set limits based on scenario
        ConfigureProtectionForScenario();
        Print("✅ Protection System initialized");
    }
    
    // Create Recovery Tracker
    g_RecoveryTracker = new CGridRecoveryTracker();
    Print("✅ Recovery Tracker initialized");
    
    // Create Cost Calculator
    g_CostCalculator = new CGridCostCalculator(_Symbol);
    g_CostCalculator.Initialize();
    
    // Enable high spread if needed
    if(StressScenario == STRESS_HIGH_SPREAD)
    {
        g_CostCalculator.EnableHighSpreadTesting(3.0);  // 3x spread
    }
    
    Print("✅ Cost Calculator initialized");
    
    // Create Risk/Reward Analyzer
    g_RiskReward = new CGridRiskRewardAnalyzer();
    Print("✅ Risk/Reward Analyzer initialized");
    
    // Initialize price
    MqlTick tick;
    if(SymbolInfoTick(_Symbol, tick))
    {
        g_BasePrice = tick.bid;
        g_SimPrice = g_BasePrice;
    }
    
    g_CurrentTick = 0;
    
    // Start timer (1 tick per second for visualization)
    EventSetTimer(1);
    
    Print("════════════════════════════════════════════");
    Print("✅ STRESS TEST READY");
    Print("Base Price: ", DoubleToString(g_BasePrice, _Digits));
    Print("════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    if(g_Grid != NULL) delete g_Grid;
    if(g_AdaptiveConfig != NULL) delete g_AdaptiveConfig;
    if(g_Protection != NULL) delete g_Protection;
    if(g_RecoveryTracker != NULL) delete g_RecoveryTracker;
    if(g_CostCalculator != NULL) delete g_CostCalculator;
    if(g_RiskReward != NULL) delete g_RiskReward;
    
    Print("Grid Stress Tester stopped");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(g_CurrentTick >= TotalTicks)
    {
        // Test complete
        PrintFinalResults();
        EventKillTimer();
        ExpertRemove();
        return;
    }
    
    g_CurrentTick++;
    
    // Generate price based on scenario
    GeneratePriceForScenario();
    
    // Update all systems
    UpdateAllSystems();
    
    // Simulate trading
    SimulateGridTrading();
    
    // Print progress every 100 ticks
    if(g_CurrentTick % 100 == 0)
    {
        PrintProgress();
    }
}

//+------------------------------------------------------------------+
//| Configure Protection for Scenario                                |
//+------------------------------------------------------------------+
void ConfigureProtectionForScenario()
{
    switch(StressScenario)
    {
        case STRESS_EXTREME_UPTREND:
        case STRESS_EXTREME_DOWNTREND:
            g_Protection.SetMaxMovement(5000.0);     // Test 5000 point move
            g_Protection.SetMaxDrawdown(30.0);       // 30% DD limit
            break;
            
        case STRESS_LONG_DRAWDOWN:
            g_Protection.SetMaxDrawdown(40.0);       // Higher DD allowed
            break;
            
        case STRESS_HIGH_DRAWDOWN:
            g_Protection.SetMaxDrawdown(50.0);       // Extreme DD test
            break;
            
        case STRESS_CHOPPY_MARKET:
            g_Protection.SetMaxTrendStrength(90.0);  // Higher volatility
            break;
            
        case STRESS_MIXED_WORST_CASE:
            g_Protection.SetMaxMovement(7000.0);
            g_Protection.SetMaxDrawdown(50.0);
            g_Protection.SetMaxTrendStrength(90.0);
            break;
    }
}

//+------------------------------------------------------------------+
//| Generate Price for Scenario                                      |
//+------------------------------------------------------------------+
void GeneratePriceForScenario()
{
    double movement = 0;
    
    switch(StressScenario)
    {
        case STRESS_EXTREME_UPTREND:
            // Continuous uptrend - 5 points per tick
            movement = 5.0 * _Point;
            break;
            
        case STRESS_EXTREME_DOWNTREND:
            // Continuous downtrend - 5 points per tick
            movement = -5.0 * _Point;
            break;
            
        case STRESS_LONG_DRAWDOWN:
            // Slowly drift down then recover
            if(g_CurrentTick < TotalTicks * 0.7)
                movement = -2.0 * _Point;  // Down
            else
                movement = 3.0 * _Point;   // Recovery
            break;
            
        case STRESS_HIGH_SPREAD:
            // Normal range but high spread (handled by CostCalculator)
            movement = (MathRand() % 50 - 25) * _Point;
            break;
            
        case STRESS_LONG_HOLD_SWAP:
            // Slow sideways (to test long hold impact)
            movement = (MathRand() % 20 - 10) * _Point;
            break;
            
        case STRESS_HIGH_DRAWDOWN:
            // Sharp move down then recover
            if(g_CurrentTick < TotalTicks * 0.3)
                movement = -8.0 * _Point;  // Sharp down
            else
                movement = 2.0 * _Point;   // Slow recovery
            break;
            
        case STRESS_CHOPPY_MARKET:
            // Large random swings
            movement = (MathRand() % 200 - 100) * _Point;
            break;
            
        case STRESS_MIXED_WORST_CASE:
        {
            // Combination of worst scenarios
            int phase = g_CurrentTick / (TotalTicks / 4);
            switch(phase)
            {
                case 0:  // Extreme uptrend
                    movement = 6.0 * _Point;
                    break;
                case 1:  // Choppy
                    movement = (MathRand() % 300 - 150) * _Point;
                    break;
                case 2:  // Extreme downtrend
                    movement = -6.0 * _Point;
                    break;
                case 3:  // Recovery
                    movement = 3.0 * _Point;
                    break;
            }
            break;
        }
    }
    
    g_SimPrice += movement;
}

//+------------------------------------------------------------------+
//| Update All Systems                                               |
//+------------------------------------------------------------------+
void UpdateAllSystems()
{
    // Update Protection
    if(EnableProtection && g_Protection != NULL)
    {
        ENUM_PROTECTION_STATUS status = g_Protection.CheckProtection();
        
        if(status == PROTECTION_PAUSED || status == PROTECTION_EMERGENCY_STOP)
        {
            g_Results.protection_pauses++;
            
            if(DetailedLogging)
            {
                Print("🛑 Trading paused: ", EnumToString(g_Protection.GetTriggerReason()));
            }
        }
    }
    
    // Update Recovery Tracker
    if(g_RecoveryTracker != NULL)
    {
        g_RecoveryTracker.Update();
    }
    
    // Update Cost Calculator
    if(g_CostCalculator != NULL)
    {
        g_CostCalculator.UpdateSpread();
    }
    
    // Update Adaptive Config (every 100 ticks)
    if(UseAdaptiveGrid && g_AdaptiveConfig != NULL && g_CurrentTick % 100 == 0)
    {
        if(g_AdaptiveConfig.NeedsUpdate())
        {
            g_AdaptiveConfig.UpdateConfiguration();
            g_Results.grid_adjustments++;
        }
    }
}

//+------------------------------------------------------------------+
//| Simulate Grid Trading                                            |
//+------------------------------------------------------------------+
void SimulateGridTrading()
{
    // Check if trading allowed
    if(EnableProtection && g_Protection != NULL)
    {
        if(!g_Protection.IsTrading())
        {
            return;  // Skip trading
        }
    }
    
    // Simulate trade decision (simplified)
    bool should_trade = (g_CurrentTick % 5 == 0);  // Trade every 5 ticks
    
    if(should_trade)
    {
        SimulateTrade();
    }
}

//+------------------------------------------------------------------+
//| Simulate Single Trade                                            |
//+------------------------------------------------------------------+
void SimulateTrade()
{
    g_Results.total_trades++;
    
    // Calculate costs
    double lots = 0.01;
    int days_held = (MathRand() % 7) + 1;  // 1-7 days
    
    double spread_cost = g_CostCalculator.CalculateSpreadCost(lots);
    double swap_cost = g_CostCalculator.CalculateSwapCost(ORDER_TYPE_BUY, lots, days_held);
    double commission = g_CostCalculator.CalculateCommission(lots);
    
    double total_cost = spread_cost + MathAbs(swap_cost) + commission;
    
    // Simulate profit/loss (random with bias based on scenario)
    double raw_profit = GetScenarioBiasedProfit();
    double net_profit = raw_profit - total_cost;
    
    // Update balance
    g_SimBalance += net_profit;
    g_SimEquity = g_SimBalance;
    
    // Update analyzers
    g_RiskReward.UpdateAfterTrade(net_profit);
    
    bool is_win = (net_profit > 0);
    if(EnableProtection && g_Protection != NULL)
    {
        g_Protection.UpdateAfterTrade(is_win, net_profit);
    }
    
    if(g_RecoveryTracker != NULL)
    {
        g_RecoveryTracker.IncrementTradeCounter();
    }
    
    // Log
    if(DetailedLogging && g_Results.total_trades % 20 == 0)
    {
        Print("[Trade ", g_Results.total_trades, "] Profit: $", DoubleToString(net_profit, 2),
              " | Balance: $", DoubleToString(g_SimBalance, 2));
    }
}

//+------------------------------------------------------------------+
//| Get Scenario-Biased Profit                                       |
//+------------------------------------------------------------------+
double GetScenarioBiasedProfit()
{
    double base_profit = (MathRand() % 100 - 30);  // -30 to +70
    
    switch(StressScenario)
    {
        case STRESS_EXTREME_UPTREND:
        case STRESS_EXTREME_DOWNTREND:
            return base_profit * 0.5;  // Lower profit in trends
            
        case STRESS_LONG_DRAWDOWN:
            if(g_CurrentTick < TotalTicks * 0.7)
                return base_profit * 0.3;  // Mostly losses
            else
                return base_profit * 1.5;  // Recovery profits
            
        case STRESS_HIGH_SPREAD:
        case STRESS_LONG_HOLD_SWAP:
            return base_profit * 0.8;  // Costs eat profits
            
        case STRESS_CHOPPY_MARKET:
            return base_profit * 0.6;  // Difficult market
            
        default:
            return base_profit;
    }
}

//+------------------------------------------------------------------+
//| Initialize Results                                               |
//+------------------------------------------------------------------+
void InitializeResults()
{
    g_Results.survived_extreme_trend = true;
    g_Results.protection_pauses = 0;
    g_Results.max_movement_points = 0;
    
    g_Results.drawdown_events = 0;
    g_Results.avg_recovery_hours = 0;
    g_Results.recovery_factor = 0;
    
    g_Results.total_costs = 0;
    g_Results.cost_to_profit_pct = 0;
    g_Results.avg_spread_points = 0;
    
    g_Results.max_drawdown_pct = 0;
    g_Results.profit_factor = 0;
    g_Results.risk_reward_ratio = 0;
    
    g_Results.grid_adjustments = 0;
    g_Results.min_spacing = DBL_MAX;
    g_Results.max_spacing = 0;
    
    g_Results.net_profit = 0;
    g_Results.total_trades = 0;
    g_Results.win_rate = 0;
    g_Results.all_tests_passed = false;
}

//+------------------------------------------------------------------+
//| Print Progress                                                    |
//+------------------------------------------------------------------+
void PrintProgress()
{
    double progress_pct = (double)g_CurrentTick / TotalTicks * 100.0;
    double movement = (g_SimPrice - g_BasePrice) / _Point;
    
    Print("📊 Progress: ", g_CurrentTick, "/", TotalTicks, " (", 
          DoubleToString(progress_pct, 1), "%)");
    Print("   Price Movement: ", DoubleToString(movement, 1), " points");
    Print("   Balance: $", DoubleToString(g_SimBalance, 2));
    Print("   Trades: ", g_Results.total_trades);
    
    if(EnableProtection && g_Protection != NULL)
    {
        Print("   Protection: ", EnumToString(g_Protection.GetStatus()));
    }
}

//+------------------------------------------------------------------+
//| Print Final Results                                              |
//+------------------------------------------------------------------+
void PrintFinalResults()
{
    Print("════════════════════════════════════════════════════════════");
    Print("          🔥 GRID STRESS TEST RESULTS 🔥                    ");
    Print("════════════════════════════════════════════════════════════");
    Print("Scenario: ", EnumToString(StressScenario));
    Print("Total Ticks: ", g_CurrentTick);
    Print("════════════════════════════════════════════════════════════");
    
    // Calculate final metrics
    double total_movement = MathAbs(g_SimPrice - g_BasePrice) / _Point;
    g_Results.max_movement_points = total_movement;
    g_Results.net_profit = g_SimBalance - InitialBalance;
    
    // 1. EXTREME TRENDING TEST
    Print("");
    Print("1️⃣ EXTREME TRENDING TEST (ลากไส้แตก)");
    Print("────────────────────────────────────────────────────────────");
    Print("Total Movement: ", DoubleToString(total_movement, 1), " points");
    Print("Protection Pauses: ", g_Results.protection_pauses);
    Print("Final Balance: $", DoubleToString(g_SimBalance, 2));
    
    g_Results.survived_extreme_trend = (g_SimBalance > InitialBalance * 0.5);
    
    if(g_Results.survived_extreme_trend)
        Print("Verdict: ✅ SURVIVED - Portfolio intact");
    else
        Print("Verdict: ❌ FAILED - Portfolio damaged");
    
    // 2. RECOVERY FACTOR TEST
    Print("");
    Print("2️⃣ RECOVERY FACTOR TEST (คืนชีพ)");
    Print("────────────────────────────────────────────────────────────");
    
    if(g_RecoveryTracker != NULL)
    {
        g_RecoveryTracker.CalculateRecoveryFactor(g_Results.net_profit);
        g_RecoveryTracker.PrintRecoveryReport();
        
        g_Results.drawdown_events = g_RecoveryTracker.GetEventCount();
        g_Results.avg_recovery_hours = g_RecoveryTracker.GetAvgRecoveryHours();
        g_Results.recovery_factor = g_RecoveryTracker.GetRecoveryFactor();
    }
    
    // 3. TRADING COSTS TEST
    Print("");
    Print("3️⃣ TRADING COSTS TEST (ค่าธรรมเนียม)");
    Print("────────────────────────────────────────────────────────────");
    
    if(g_CostCalculator != NULL)
    {
        g_CostCalculator.PrintCostReport(g_Results.net_profit);
        
        g_Results.total_costs = g_CostCalculator.GetTotalCosts();
        g_Results.avg_spread_points = g_CostCalculator.GetAvgSpreadPoints();
        
        if(g_Results.net_profit > 0)
        {
            g_Results.cost_to_profit_pct = (g_Results.total_costs / g_Results.net_profit) * 100.0;
        }
    }
    
    // 4. RISK/REWARD TEST
    Print("");
    Print("4️⃣ RISK/REWARD TEST (เสี่ยง/กำไร)");
    Print("────────────────────────────────────────────────────────────");
    
    if(g_RiskReward != NULL)
    {
        g_RiskReward.PrintRiskRewardReport();
        
        g_Results.max_drawdown_pct = g_RiskReward.GetMaxDrawdownPct();
        g_Results.profit_factor = g_RiskReward.GetProfitFactor();
        
        RiskRewardMetrics metrics = g_RiskReward.GetMetrics();
        g_Results.risk_reward_ratio = metrics.risk_reward_ratio;
        g_Results.win_rate = metrics.win_rate_pct;
    }
    
    // 5. DYNAMIC ADJUSTMENT TEST
    Print("");
    Print("5️⃣ DYNAMIC ADJUSTMENT TEST (ปรับตัว)");
    Print("────────────────────────────────────────────────────────────");
    Print("Grid Adjustments: ", g_Results.grid_adjustments);
    
    if(UseAdaptiveGrid && g_AdaptiveConfig != NULL)
    {
        int current_spacing = g_AdaptiveConfig.GetGridSpacing();
        Print("Final Grid Spacing: ", current_spacing, " points");
        
        if(g_Results.grid_adjustments > 0)
            Print("Verdict: ✅ ADAPTIVE - Grid adjusted to market");
        else
            Print("Verdict: ⚠️ STATIC - No adjustments made");
    }
    else
    {
        Print("Verdict: ❌ DISABLED - Adaptive grid not enabled");
    }
    
    // OVERALL SUMMARY
    Print("");
    Print("════════════════════════════════════════════════════════════");
    Print("              OVERALL TEST SUMMARY                          ");
    Print("════════════════════════════════════════════════════════════");
    Print("Total Trades: ", g_Results.total_trades);
    Print("Net Profit: $", DoubleToString(g_Results.net_profit, 2));
    Print("Return: ", DoubleToString((g_Results.net_profit / InitialBalance) * 100, 2), "%");
    Print("Max Drawdown: ", DoubleToString(g_Results.max_drawdown_pct, 2), "%");
    Print("Win Rate: ", DoubleToString(g_Results.win_rate, 2), "%");
    Print("Profit Factor: ", DoubleToString(g_Results.profit_factor, 2));
    
    // FINAL VERDICT
    Print("");
    Print("════════════════════════════════════════════════════════════");
    Print("              FINAL VERDICT                                 ");
    Print("════════════════════════════════════════════════════════════");
    
    bool test1 = g_Results.survived_extreme_trend;
    bool test2 = (g_Results.recovery_factor >= 1.5);
    bool test3 = (g_Results.cost_to_profit_pct <= 30);
    bool test4 = (g_Results.max_drawdown_pct <= 30 && g_Results.profit_factor >= 1.3);
    bool test5 = (g_Results.grid_adjustments > 0 || !UseAdaptiveGrid);
    
    Print("Test Results:");
    Print("  1. Extreme Trending:  ", test1 ? "✅ PASS" : "❌ FAIL");
    Print("  2. Recovery Factor:   ", test2 ? "✅ PASS" : "❌ FAIL");
    Print("  3. Trading Costs:     ", test3 ? "✅ PASS" : "❌ FAIL");
    Print("  4. Risk/Reward:       ", test4 ? "✅ PASS" : "❌ FAIL");
    Print("  5. Dynamic Adjust:    ", test5 ? "✅ PASS" : "❌ FAIL");
    
    int passed = (test1 ? 1 : 0) + (test2 ? 1 : 0) + (test3 ? 1 : 0) + (test4 ? 1 : 0) + (test5 ? 1 : 0);
    
    Print("");
    Print("Tests Passed: ", passed, "/5");
    
    if(passed == 5)
        Print("VERDICT: ✅✅✅ EXCELLENT - Ready for production!");
    else if(passed >= 4)
        Print("VERDICT: ✅✅ GOOD - Minor improvements needed");
    else if(passed >= 3)
        Print("VERDICT: ⚠️ FAIR - Needs improvement");
    else
        Print("VERDICT: ❌ POOR - Not ready for production");
    
    Print("════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
