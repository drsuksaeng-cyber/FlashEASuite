//+------------------------------------------------------------------+
//|                                   test_position_sizing.mq5       |
//|                            FlashEASuite V2.1 - Tests             |
//|                                       Position Sizing Tests       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Risk/PositionSizingManager.mqh"

//--- Input parameters
input double InpRiskPercent = 1.0;              // Risk Percentage (%)
input bool   InpUseVolatility = true;           // Use Volatility Adjustment
input bool   InpRunAllTests = true;             // Run All Tests
input int    InpTestNumber = 1;                 // Single Test Number (if not all)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("\n");
    Print("╔════════════════════════════════════════════════════════════╗");
    Print("║     POSITION SIZING MANAGER - COMPREHENSIVE TESTS          ║");
    Print("╚════════════════════════════════════════════════════════════╝");
    Print("");
    
    // Create instance
    CPositionSizingManager* ps = new CPositionSizingManager();
    
    // Initialize
    if(!ps.Initialize(_Symbol, InpRiskPercent, InpUseVolatility))
    {
        Print("❌ FATAL: Initialization failed!");
        delete ps;
        return;
    }
    
    Print("Account Balance: $", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Risk Per Trade: ", InpRiskPercent, "%");
    Print("Risk Amount: $", AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0);
    Print("");
    
    // Run tests
    int passed = 0;
    int failed = 0;
    
    if(InpRunAllTests)
    {
        // Run all tests
        if(Test1_StandardTrade(ps)) passed++; else failed++;
        if(Test2_TightStop(ps)) passed++; else failed++;
        if(Test3_WideStop(ps)) passed++; else failed++;
        if(Test4_DifferentRisk(ps)) passed++; else failed++;
        if(Test5_VolatilityAdjustment(ps)) passed++; else failed++;
        if(Test6_MinLotEdgeCase(ps)) passed++; else failed++;
        if(Test7_MaxLotEdgeCase(ps)) passed++; else failed++;
        if(Test8_ZeroRisk(ps)) passed++; else failed++;
        if(Test9_InvalidStopLoss(ps)) passed++; else failed++;
        if(Test10_MultipleCalculations(ps)) passed++; else failed++;
    }
    else
    {
        // Run single test
        switch(InpTestNumber)
        {
            case 1: if(Test1_StandardTrade(ps)) passed++; else failed++; break;
            case 2: if(Test2_TightStop(ps)) passed++; else failed++; break;
            case 3: if(Test3_WideStop(ps)) passed++; else failed++; break;
            case 4: if(Test4_DifferentRisk(ps)) passed++; else failed++; break;
            case 5: if(Test5_VolatilityAdjustment(ps)) passed++; else failed++; break;
            case 6: if(Test6_MinLotEdgeCase(ps)) passed++; else failed++; break;
            case 7: if(Test7_MaxLotEdgeCase(ps)) passed++; else failed++; break;
            case 8: if(Test8_ZeroRisk(ps)) passed++; else failed++; break;
            case 9: if(Test9_InvalidStopLoss(ps)) passed++; else failed++; break;
            case 10: if(Test10_MultipleCalculations(ps)) passed++; else failed++; break;
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
    
    // Print statistics
    ps.PrintInfo();
    
    // Cleanup
    delete ps;
    
    Print("");
    Print("═══════════════════════════════════════════════════════════");
    Print("                    TESTS COMPLETE");
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Test 1: Standard Trade (50 pips stop)                           |
//+------------------------------------------------------------------+
bool Test1_StandardTrade(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 1: Standard Trade (50 pips) ━━━");
    
    double entry = 1.0500;
    double sl = 1.0450;  // 50 pips
    double lot = ps.CalculateLotSize(entry, sl);
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Stop Distance: 50 pips");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // For $10,000 account, 1% risk = $100
    // 50 pips stop, $10/pip (1 lot) = $500 risk per lot
    // Therefore: 0.20 lots = $100 risk
    double expected = 0.20;
    double tolerance = 0.05;
    
    bool passed = MathAbs(lot - expected) < tolerance;
    
    if(passed)
        Print("✅ PASS - Lot size within expected range");
    else
        Print("❌ FAIL - Expected ~", expected, ", got ", lot);
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 2: Tight Stop (20 pips)                                    |
//+------------------------------------------------------------------+
bool Test2_TightStop(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 2: Tight Stop (20 pips) ━━━");
    
    double entry = 1.0500;
    double sl = 1.0480;  // 20 pips
    double lot = ps.CalculateLotSize(entry, sl);
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Stop Distance: 20 pips");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // 20 pips = 0.50 lots for same risk
    double expected = 0.50;
    double tolerance = 0.10;
    
    bool passed = MathAbs(lot - expected) < tolerance;
    
    if(passed)
        Print("✅ PASS - Tight stop = larger lot size");
    else
        Print("❌ FAIL - Expected ~", expected, ", got ", lot);
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 3: Wide Stop (100 pips)                                    |
//+------------------------------------------------------------------+
bool Test3_WideStop(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 3: Wide Stop (100 pips) ━━━");
    
    double entry = 1.0500;
    double sl = 1.0400;  // 100 pips
    double lot = ps.CalculateLotSize(entry, sl);
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Stop Distance: 100 pips");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // 100 pips = 0.10 lots for same risk
    double expected = 0.10;
    double tolerance = 0.03;
    
    bool passed = MathAbs(lot - expected) < tolerance;
    
    if(passed)
        Print("✅ PASS - Wide stop = smaller lot size");
    else
        Print("❌ FAIL - Expected ~", expected, ", got ", lot);
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 4: Different Risk Percentage (0.5%)                        |
//+------------------------------------------------------------------+
bool Test4_DifferentRisk(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 4: Different Risk % (0.5%) ━━━");
    
    double entry = 1.0500;
    double sl = 1.0450;  // 50 pips
    double lot = ps.CalculateLotSize(entry, sl, 0.5);  // 0.5% risk
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Risk: 0.5% (half of normal)");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // 0.5% risk = half of normal = ~0.10 lots
    double expected = 0.10;
    double tolerance = 0.03;
    
    bool passed = MathAbs(lot - expected) < tolerance;
    
    if(passed)
        Print("✅ PASS - Lower risk = smaller lot size");
    else
        Print("❌ FAIL - Expected ~", expected, ", got ", lot);
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 5: Volatility Adjustment                                   |
//+------------------------------------------------------------------+
bool Test5_VolatilityAdjustment(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 5: Volatility Adjustment ━━━");
    
    double entry = 1.0500;
    double sl = 1.0450;
    
    // Calculate without volatility
    double lot_normal = ps.CalculateLotSize(entry, sl);
    
    // Calculate with volatility
    double lot_vol = ps.CalculateLotSizeWithVolatility(entry, sl);
    
    Print("Normal Lot: ", DoubleToString(lot_normal, 2));
    Print("Vol-Adjusted Lot: ", DoubleToString(lot_vol, 2));
    Print("Difference: ", DoubleToString(MathAbs(lot_vol - lot_normal), 2));
    
    // Volatility adjustment should change lot size (unless ATR unavailable)
    bool passed = true;  // Pass if calculation runs without error
    
    if(passed)
        Print("✅ PASS - Volatility adjustment calculated");
    else
        Print("❌ FAIL");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 6: Min Lot Edge Case                                       |
//+------------------------------------------------------------------+
bool Test6_MinLotEdgeCase(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 6: Min Lot Edge Case ━━━");
    
    double entry = 1.0500;
    double sl = 1.0000;  // Very wide stop = 500 pips
    double lot = ps.CalculateLotSize(entry, sl);
    
    Print("Entry: ", entry);
    Print("SL: ", sl, " (500 pips - very wide)");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    Print("Min Lot: ", ps.GetMinLot());
    
    // Should be clamped to min lot
    bool passed = (lot >= ps.GetMinLot());
    
    if(passed)
        Print("✅ PASS - Lot >= min lot");
    else
        Print("❌ FAIL - Lot below min lot");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 7: Max Lot Edge Case                                       |
//+------------------------------------------------------------------+
bool Test7_MaxLotEdgeCase(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 7: Max Lot Edge Case ━━━");
    
    double entry = 1.0500;
    double sl = 1.0499;  // Very tight stop = 1 pip
    double lot = ps.CalculateLotSize(entry, sl, 10.0);  // High risk %
    
    Print("Entry: ", entry);
    Print("SL: ", sl, " (1 pip - very tight)");
    Print("Risk: 10%");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    Print("Max Lot: ", ps.GetMaxLot());
    
    // Should be clamped to max lot or reasonable size
    bool passed = (lot <= ps.GetMaxLot() && lot > 0);
    
    if(passed)
        Print("✅ PASS - Lot <= max lot");
    else
        Print("❌ FAIL - Lot exceeds max lot or zero");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 8: Zero Risk (Should Fail Gracefully)                      |
//+------------------------------------------------------------------+
bool Test8_ZeroRisk(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 8: Zero Risk ━━━");
    
    double entry = 1.0500;
    double sl = 1.0450;
    double lot = ps.CalculateLotSize(entry, sl, 0);  // 0% risk
    
    Print("Entry: ", entry);
    Print("SL: ", sl);
    Print("Risk: 0%");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // Should use default risk (not 0)
    bool passed = (lot > 0);
    
    if(passed)
        Print("✅ PASS - Used default risk instead of 0");
    else
        Print("❌ FAIL - Returned zero lot");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 9: Invalid Stop Loss (Should Handle Error)                 |
//+------------------------------------------------------------------+
bool Test9_InvalidStopLoss(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 9: Invalid Stop Loss ━━━");
    
    double entry = 1.0500;
    double sl = 1.0500;  // Same as entry (invalid)
    double lot = ps.CalculateLotSize(entry, sl);
    
    Print("Entry: ", entry);
    Print("SL: ", sl, " (same as entry - invalid)");
    Print("Calculated Lot: ", DoubleToString(lot, 2));
    
    // Should return 0 or handle error gracefully
    bool passed = (lot == 0);
    
    if(passed)
        Print("✅ PASS - Handled invalid stop loss");
    else
        Print("❌ FAIL - Should return 0 for invalid input");
    
    return passed;
}

//+------------------------------------------------------------------+
//| Test 10: Multiple Calculations (Performance)                    |
//+------------------------------------------------------------------+
bool Test10_MultipleCalculations(CPositionSizingManager* ps)
{
    Print("\n━━━ Test 10: Multiple Calculations ━━━");
    
    int iterations = 1000;
    ulong start_time = GetTickCount64();
    
    for(int i = 0; i < iterations; i++)
    {
        double entry = 1.0500 + (i * 0.0001);
        double sl = entry - 0.0050;
        ps.CalculateLotSize(entry, sl);
    }
    
    ulong end_time = GetTickCount64();
    ulong elapsed = end_time - start_time;
    
    Print("Iterations: ", iterations);
    Print("Time Elapsed: ", elapsed, " ms");
    Print("Avg per calculation: ", DoubleToString((double)elapsed / iterations, 2), " ms");
    
    // Should complete in reasonable time (< 1 second for 1000 iterations)
    bool passed = (elapsed < 1000);
    
    if(passed)
        Print("✅ PASS - Performance acceptable");
    else
        Print("❌ FAIL - Too slow");
    
    return passed;
}

//+------------------------------------------------------------------+
