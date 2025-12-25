//+------------------------------------------------------------------+
//|                                   test_daily_loss_limit.mq5      |
//|                            FlashEASuite V2.1 - Tests             |
//|                                       Daily Loss Limit Tests      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Risk/DailyLossLimit.mqh"

//--- Input parameters
input double InpDailyLimit = 4.0;              // Daily Loss Limit (%)
input bool   InpRunAllTests = true;            // Run All Tests
input int    InpTestNumber = 1;                // Single Test Number

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("\n");
    Print("╔════════════════════════════════════════════════════════════╗");
    Print("║        DAILY LOSS LIMIT - COMPREHENSIVE TESTS              ║");
    Print("╚════════════════════════════════════════════════════════════╝");
    Print("");
    
    // Create instance
    CDailyLossLimit* dll = new CDailyLossLimit();
    
    // Initialize
    if(!dll.Initialize(InpDailyLimit))
    {
        Print("❌ FATAL: Initialization failed!");
        delete dll;
        return;
    }
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double max_loss = balance * (InpDailyLimit / 100.0);
    
    Print("Account Balance: $", DoubleToString(balance, 2));
    Print("Daily Limit: ", InpDailyLimit, "%");
    Print("Max Daily Loss: $", DoubleToString(max_loss, 2));
    Print("");
    
    // Run tests
    int passed = 0;
    int failed = 0;
    
    if(InpRunAllTests)
    {
        // Run all tests
        if(Test1_InitialState(dll)) passed++; else failed++;
        if(Test2_UpdatePnL(dll)) passed++; else failed++;
        if(Test3_ApproachingLimit(dll)) passed++; else failed++;
        if(Test4_ReachingLimit(dll)) passed++; else failed++;
        if(Test5_LimitRemaining(dll)) passed++; else failed++;
        if(Test6_DailyMetrics(dll)) passed++; else failed++;
        if(Test7_ManualReset(dll)) passed++; else failed++;
    }
    else
    {
        // Run single test
        switch(InpTestNumber)
        {
            case 1: if(Test1_InitialState(dll)) passed++; else failed++; break;
            case 2: if(Test2_UpdatePnL(dll)) passed++; else failed++; break;
            case 3: if(Test3_ApproachingLimit(dll)) passed++; else failed++; break;
            case 4: if(Test4_ReachingLimit(dll)) passed++; else failed++; break;
            case 5: if(Test5_LimitRemaining(dll)) passed++; else failed++; break;
            case 6: if(Test6_DailyMetrics(dll)) passed++; else failed++; break;
            case 7: if(Test7_ManualReset(dll)) passed++; else failed++; break;
            default: Print("❌ Invalid test number: ", InpTestNumber);
        }
    }
    
    // Print summary
    Print("");
    Print("╔════════════════════════════════════════════════════════════╗");
    Print("║                     TEST SUMMARY                            ║");
    Print("╚════════════════════════════════════════════════════════════╝");
    Print("Total Tests: ", passed + failed);
    Print("✅ Passed: ", passed);
    Print("❌ Failed: ", failed);
    Print("Success Rate: ", (passed * 100.0 / (passed + failed)), "%");
    Print("");
    
    // Print current state
    dll.PrintInfo();
    
    // Cleanup
    delete dll;
    
    Print("");
    Print("═══════════════════════════════════════════════════════════");
    Print("                    TESTS COMPLETE");
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Test 1: Initial State                                           |
//+------------------------------------------------------------------+
bool Test1_InitialState(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 1: Initial State ━━━");
    
    bool is_reached = dll.IsDailyLimitReached();
    double pnl = dll.GetDailyPnL();
    int trades = dll.GetDailyTradesCount();
    
    Print("Limit Reached: ", (is_reached ? "YES" : "NO"));
    Print("Daily P&L: $", DoubleToString(pnl, 2));
    Print("Daily Trades: ", trades);
    
    // Initially should not be reached, P&L = 0, trades = 0
    bool passed = (!is_reached && pnl == 0 && trades == 0);
    
    if(passed)
        Print("✅ PASS - Initial state correct");
    else
        Print("❌ FAIL - Initial state incorrect");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 2: Update P&L                                              |
//+------------------------------------------------------------------+
bool Test2_UpdatePnL(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 2: Update P&L ━━━");
    
    // Simulate some trades
    dll.UpdateTrade(50.0, true);   // Win $50
    dll.UpdateTrade(-20.0, false); // Lose $20
    dll.UpdateTrade(30.0, true);   // Win $30
    
    double pnl = dll.GetDailyPnL();
    int trades = dll.GetDailyTradesCount();
    int wins = dll.GetDailyWinsCount();
    int losses = dll.GetDailyLossesCount();
    
    Print("P&L: $", DoubleToString(pnl, 2));
    Print("Trades: ", trades);
    Print("Wins: ", wins);
    Print("Losses: ", losses);
    
    // Should have 3 trades, 2 wins, 1 loss
    bool passed = (trades == 3 && wins == 2 && losses == 1);
    
    if(passed)
        Print("✅ PASS - P&L tracking working");
    else
        Print("❌ FAIL - P&L tracking incorrect");
    
    // Reset for other tests
    dll.ManualReset();
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 3: Approaching Limit (80%)                                 |
//+------------------------------------------------------------------+
bool Test3_ApproachingLimit(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 3: Approaching Limit (80%) ━━━");
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double max_loss = dll.GetMaxDailyLoss();
    
    // Simulate loss approaching 80% of limit
    double test_loss = max_loss * 0.85;  // 85% of limit
    dll.UpdateDailyPnL(-test_loss);
    
    bool is_reached = dll.IsDailyLimitReached();
    double remaining = dll.GetDailyLimitRemaining();
    
    Print("Simulated Loss: $", DoubleToString(test_loss, 2));
    Print("Max Loss: $", DoubleToString(max_loss, 2));
    Print("Limit Reached: ", (is_reached ? "YES" : "NO"));
    Print("Remaining: $", DoubleToString(remaining, 2));
    
    // Should NOT be reached yet (85% < 100%)
    bool passed = !is_reached;
    
    if(passed)
        Print("✅ PASS - Warning triggered, limit not reached");
    else
        Print("❌ FAIL - Limit incorrectly reached");
    
    dll.ManualReset();
    return passed;
}

//+------------------------------------------------------------------+
//| Test 4: Reaching Limit (100%)                                   |
//+------------------------------------------------------------------+
bool Test4_ReachingLimit(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 4: Reaching Limit (100%) ━━━");
    
    double max_loss = dll.GetMaxDailyLoss();
    
    // Simulate loss reaching 110% of limit
    double test_loss = max_loss * 1.1;
    dll.UpdateDailyPnL(-test_loss);
    
    dll.CheckAndUpdateLimit();
    
    bool is_reached = dll.IsDailyLimitReached();
    double remaining = dll.GetDailyLimitRemaining();
    
    Print("Simulated Loss: $", DoubleToString(test_loss, 2));
    Print("Max Loss: $", DoubleToString(max_loss, 2));
    Print("Limit Reached: ", (is_reached ? "YES" : "NO"));
    Print("Remaining: $", DoubleToString(remaining, 2));
    
    // Should be reached (110% > 100%)
    bool passed = is_reached;
    
    if(passed)
        Print("✅ PASS - Limit correctly reached");
    else
        Print("❌ FAIL - Limit not reached when it should be");
    
    dll.ManualReset();
    return passed;
}

//+------------------------------------------------------------------+
//| Test 5: Limit Remaining Calculation                             |
//+------------------------------------------------------------------+
bool Test5_LimitRemaining(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 5: Limit Remaining ━━━");
    
    double max_loss = dll.GetMaxDailyLoss();
    
    // Test 1: No loss
    double remaining1 = dll.GetDailyLimitRemaining();
    Print("Initial Remaining: $", DoubleToString(remaining1, 2));
    
    // Test 2: 50% loss
    dll.UpdateDailyPnL(-max_loss * 0.5);
    double remaining2 = dll.GetDailyLimitRemaining();
    Print("After 50% loss: $", DoubleToString(remaining2, 2));
    
    // Test 3: 90% loss
    dll.ManualReset();
    dll.UpdateDailyPnL(-max_loss * 0.9);
    double remaining3 = dll.GetDailyLimitRemaining();
    Print("After 90% loss: $", DoubleToString(remaining3, 2));
    
    // Remaining should decrease as losses increase
    bool passed = (remaining1 > remaining2) && (remaining2 > remaining3);
    
    if(passed)
        Print("✅ PASS - Remaining calculated correctly");
    else
        Print("❌ FAIL - Remaining calculation incorrect");
    
    dll.ManualReset();
    return passed;
}

//+------------------------------------------------------------------+
//| Test 6: Daily Metrics                                           |
//+------------------------------------------------------------------+
bool Test6_DailyMetrics(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 6: Daily Metrics ━━━");
    
    // Simulate a full day of trading
    dll.UpdateTrade(100.0, true);   // Win
    dll.UpdateTrade(-50.0, false);  // Loss
    dll.UpdateTrade(75.0, true);    // Win
    dll.UpdateTrade(-30.0, false);  // Loss
    dll.UpdateTrade(50.0, true);    // Win
    
    int trades = dll.GetDailyTradesCount();
    int wins = dll.GetDailyWinsCount();
    int losses = dll.GetDailyLossesCount();
    double total_wins = dll.GetDailyWins();
    double total_losses = dll.GetDailyLosses();
    
    Print("Trades: ", trades);
    Print("Wins: ", wins, " ($", DoubleToString(total_wins, 2), ")");
    Print("Losses: ", losses, " ($", DoubleToString(total_losses, 2), ")");
    
    // Check metrics
    bool passed = (trades == 5 && wins == 3 && losses == 2 &&
                   total_wins == 225.0 && total_losses == -80.0);
    
    if(passed)
        Print("✅ PASS - Daily metrics correct");
    else
        Print("❌ FAIL - Daily metrics incorrect");
    
    dll.ManualReset();
    return passed;
}

//+------------------------------------------------------------------+
//| Test 7: Manual Reset                                            |
//+------------------------------------------------------------------+
bool Test7_ManualReset(CDailyLossLimit* dll)
{
    Print("\n━━━ Test 7: Manual Reset ━━━");
    
    // Add some data
    dll.UpdateTrade(50.0, true);
    dll.UpdateTrade(-30.0, false);
    
    Print("Before Reset:");
    Print("  Trades: ", dll.GetDailyTradesCount());
    Print("  P&L: $", DoubleToString(dll.GetDailyPnL(), 2));
    
    // Manual reset
    dll.ManualReset();
    
    Print("After Reset:");
    Print("  Trades: ", dll.GetDailyTradesCount());
    Print("  P&L: $", DoubleToString(dll.GetDailyPnL(), 2));
    
    // Should be back to zero
    bool passed = (dll.GetDailyTradesCount() == 0 && 
                   dll.GetDailyPnL() == 0);
    
    if(passed)
        Print("✅ PASS - Reset working correctly");
    else
        Print("❌ FAIL - Reset not working");
    
    return passed;
}

//+------------------------------------------------------------------+
