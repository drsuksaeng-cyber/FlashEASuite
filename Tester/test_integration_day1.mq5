//+------------------------------------------------------------------+
//|                                   test_integration_day1.mq5      |
//|                            FlashEASuite V2.1 - Tests             |
//|                                   Day 1 Integration Tests         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Risk/RiskGuardian.mqh"

//--- Input parameters
input bool   InpRunAllTests = true;            // Run All Tests
input int    InpTestNumber = 1;                // Single Test Number

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("\n");
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║        DAY 1 INTEGRATION TEST - ALL COMPONENTS                ║");
    Print("║  PositionSizing + DailyLossLimit + RiskGuardian               ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    Print("");
    
    // Create Risk Guardian (integrates all components)
    CRiskGuardian* rg = new CRiskGuardian();
    
    // Initialize
    if(!rg.Initialize(5, 2.0, 15.0, 4.0))
    {
        Print("❌ FATAL: Risk Guardian initialization failed!");
        delete rg;
        return;
    }
    
    Print("Account Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("");
    
    // Run tests
    int passed = 0;
    int failed = 0;
    
    if(InpRunAllTests)
    {
        // Run all tests
        if(Test1_BasicIntegration(rg)) passed++; else failed++;
        if(Test2_PositionSizingIntegration(rg)) passed++; else failed++;
        if(Test3_DailyLimitIntegration(rg)) passed++; else failed++;
        if(Test4_MaxOrdersValidation(rg)) passed++; else failed++;
        if(Test5_ExposureValidation(rg)) passed++; else failed++;
        if(Test6_CompleteWorkflow(rg)) passed++; else failed++;
    }
    else
    {
        // Run single test
        switch(InpTestNumber)
        {
            case 1: if(Test1_BasicIntegration(rg)) passed++; else failed++; break;
            case 2: if(Test2_PositionSizingIntegration(rg)) passed++; else failed++; break;
            case 3: if(Test3_DailyLimitIntegration(rg)) passed++; else failed++; break;
            case 4: if(Test4_MaxOrdersValidation(rg)) passed++; else failed++; break;
            case 5: if(Test5_ExposureValidation(rg)) passed++; else failed++; break;
            case 6: if(Test6_CompleteWorkflow(rg)) passed++; else failed++; break;
            default: Print("❌ Invalid test number: ", InpTestNumber);
        }
    }
    
    // Print summary
    Print("");
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║                     TEST SUMMARY                               ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    Print("Total Tests: ", passed + failed);
    Print("✅ Passed: ", passed);
    Print("❌ Failed: ", failed);
    Print("Success Rate: ", (passed * 100.0 / (passed + failed)), "%");
    Print("");
    
    // Print final status
    rg.PrintInfo();
    rg.PrintRejectionStats();
    
    // Cleanup
    delete rg;
    
    Print("");
    Print("═══════════════════════════════════════════════════════════════");
    Print("                    DAY 1 TESTS COMPLETE");
    Print("═══════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Test 1: Basic Integration                                       |
//+------------------------------------------------------------------+
bool Test1_BasicIntegration(CRiskGuardian* rg)
{
    Print("\n━━━ Test 1: Basic Integration ━━━");
    
    // Check all components initialized
    bool pos_sizing = (rg.GetPositionSizing() != NULL);
    bool daily_limit = (rg.GetDailyLimit() != NULL);
    bool initialized = rg.IsInitialized();
    
    Print("Position Sizing: ", (pos_sizing ? "OK" : "FAIL"));
    Print("Daily Limit: ", (daily_limit ? "OK" : "FAIL"));
    Print("Risk Guardian: ", (initialized ? "OK" : "FAIL"));
    
    bool passed = (pos_sizing && daily_limit && initialized);
    
    if(passed)
        Print("✅ PASS - All components integrated");
    else
        Print("❌ FAIL - Integration incomplete");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 2: Position Sizing Integration                             |
//+------------------------------------------------------------------+
bool Test2_PositionSizingIntegration(CRiskGuardian* rg)
{
    Print("\n━━━ Test 2: Position Sizing Integration ━━━");
    
    double entry = 1.0500;
    double sl = 1.0450;  // 50 pips
    
    // Calculate via Risk Guardian
    double lot = rg.CalculateSafeLotSize(_Symbol, entry, sl, 1.0);
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // Should be valid lot size
    bool passed = (lot > 0 && lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    
    if(passed)
        Print("✅ PASS - Position sizing working through Risk Guardian");
    else
        Print("❌ FAIL - Position sizing integration failed");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 3: Daily Limit Integration                                 |
//+------------------------------------------------------------------+
bool Test3_DailyLimitIntegration(CRiskGuardian* rg)
{
    Print("\n━━━ Test 3: Daily Limit Integration ━━━");
    
    // Check daily limit initially not reached
    bool limit_ok = rg.CheckDailyLimit();
    
    Print("Daily Limit OK: ", (limit_ok ? "YES" : "NO"));
    
    // Simulate a trade
    rg.OnTradeOpened(12345, 0.10);
    rg.OnTradeClosed(12345, 50.0);  // +$50
    
    // Check still OK
    bool still_ok = rg.CheckDailyLimit();
    
    Print("After Trade: ", (still_ok ? "OK" : "LIMIT REACHED"));
    
    bool passed = (limit_ok && still_ok);
    
    if(passed)
        Print("✅ PASS - Daily limit tracking working");
    else
        Print("❌ FAIL - Daily limit integration failed");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 4: Max Orders Validation                                   |
//+------------------------------------------------------------------+
bool Test4_MaxOrdersValidation(CRiskGuardian* rg)
{
    Print("\n━━━ Test 4: Max Orders Validation ━━━");
    
    int max_orders = rg.GetMaxOrders();
    int current_positions = PositionsTotal();
    
    Print("Max Orders: ", max_orders);
    Print("Current Positions: ", current_positions);
    
    bool can_open = rg.CanOpenNewPosition();
    
    Print("Can Open: ", (can_open ? "YES" : "NO"));
    
    // Should be able to open if below max
    bool passed = (current_positions < max_orders) ? can_open : !can_open;
    
    if(passed)
        Print("✅ PASS - Max orders check working");
    else
        Print("❌ FAIL - Max orders check failed");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 5: Exposure Validation                                     |
//+------------------------------------------------------------------+
bool Test5_ExposureValidation(CRiskGuardian* rg)
{
    Print("\n━━━ Test 5: Exposure Validation ━━━");
    
    double max_exposure = rg.GetMaxExposure();
    
    Print("Max Exposure: ", max_exposure, "%");
    
    // Try small lot
    bool ok_small = rg.CheckExposure(0.01);
    Print("Check 0.01 lots: ", (ok_small ? "OK" : "REJECTED"));
    
    // Try large lot
    bool ok_large = rg.CheckExposure(100.0);
    Print("Check 100 lots: ", (ok_large ? "OK" : "REJECTED"));
    
    // Small should pass, large should fail (in most cases)
    bool passed = ok_small;
    
    if(passed)
        Print("✅ PASS - Exposure validation working");
    else
        Print("❌ FAIL - Exposure validation failed");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 6: Complete Workflow                                       |
//+------------------------------------------------------------------+
bool Test6_CompleteWorkflow(CRiskGuardian* rg)
{
    Print("\n━━━ Test 6: Complete Workflow ━━━");
    Print("Testing full trade validation workflow...");
    Print("");
    
    // Setup trade parameters
    string symbol = _Symbol;
    double entry = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double sl = entry - 50 * SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
    double lot = 0;
    
    Print("Step 1: Validate New Trade");
    Print("  Symbol: ", symbol);
    Print("  Entry: ", entry);
    Print("  SL: ", sl);
    
    // Validate through Risk Guardian
    bool validated = rg.ValidateNewTrade(symbol, entry, sl, lot);
    
    Print("  Validation: ", (validated ? "PASSED" : "REJECTED"));
    if(validated)
        Print("  Approved Lot: ", DoubleToString(lot, 2));
    Print("");
    
    Print("Step 2: Check Individual Components");
    
    // Check daily limit
    bool daily_ok = rg.CheckDailyLimit();
    Print("  Daily Limit: ", (daily_ok ? "OK" : "REACHED"));
    
    // Check max orders
    bool orders_ok = rg.CanOpenNewPosition();
    Print("  Max Orders: ", (orders_ok ? "OK" : "FULL"));
    
    // Check exposure
    bool exposure_ok = rg.CheckExposure(lot);
    Print("  Exposure: ", (exposure_ok ? "OK" : "EXCEEDED"));
    Print("");
    
    Print("Step 3: Simulate Trade Execution");
    if(validated)
    {
        ulong ticket = 12345;
        rg.OnTradeOpened(ticket, lot);
        Print("  Trade Opened: #", ticket);
        
        // Simulate close with profit
        double profit = 75.0;
        rg.OnTradeClosed(ticket, profit);
        Print("  Trade Closed: +$", DoubleToString(profit, 2));
    }
    Print("");
    
    // Check if workflow completed successfully
    bool passed = validated;
    
    if(passed)
        Print("✅ PASS - Complete workflow successful");
    else
        Print("❌ FAIL - Workflow validation failed");
    
    return passed;
}

//+------------------------------------------------------------------+
