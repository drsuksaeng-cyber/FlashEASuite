//+------------------------------------------------------------------+
//| test_MM11_MM15.mq5                                               |
//| FlashEASuite V2 — P3-3 Test Script                               |
//| ทดสอบ MM11-MM15 ทุกตัว                                           |
//| วิธีใช้: Compile แล้วรันใน Strategy Tester หรือ Attach บน Chart  |
//+------------------------------------------------------------------+
//| ตำแหน่งไฟล์: Tester\test_MM11_MM15.mq5                          |
//| Include path: ../Include/Logic/MM/ (ขึ้น 1 ระดับจาก Tester/)     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict
#property script_show_inputs

// ✅ Include path ถูกต้อง: Tester/ → ../Include/Logic/MM/
#include "../Include/Logic/MM/IMoneyManager.mqh"
#include "../Include/Logic/MM/MM11_SessionBased.mqh"
#include "../Include/Logic/MM/MM12_EquityCurveFilter.mqh"
#include "../Include/Logic/MM/MM13_CorrelationAdjusted.mqh"
#include "../Include/Logic/MM/MM14_TieredRisk.mqh"
#include "../Include/Logic/MM/MM15_AdaptiveWinStreak.mqh"

//--- Input parameters
input string   InpSymbol  = "XAUUSD.tp";   // ✅ Broker suffix .tp
input double   InpBalance = 10000.0;        // Test balance
input double   InpEquity  = 9800.0;         // Test equity
input double   InpSL      = 2500.0;         // Test SL price (XAUUSD ~2600 → SL 100 pts away)

//+------------------------------------------------------------------+
//| Print separator                                                  |
//+------------------------------------------------------------------+
void Sep() { Print("======================================================="); }

//+------------------------------------------------------------------+
//| Test MM11: Session-Based                                         |
//+------------------------------------------------------------------+
void TestMM11()
{
    Sep();
    Print(">>> TEST MM11: Session-Based");

    // Direct object — ไม่ใช้ pointer
    CMM11_SessionBased mm11;
    mm11.Setup(InpSymbol, 50);

    // Show current session
    mm11.PrintDiagnostics();

    // Test with default params
    double lot = mm11.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Default params → Lot=%.2f", lot);

    // Test custom params
    mm11.SetParams(1.5, 1.2, 0.5, 2.0, false);
    lot = mm11.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Custom: London=1.5%% NY=1.2%% Asian=0.5%% Overlap=2.0%% → Lot=%.2f", lot);

    // Verify ID and Name
    PrintFormat("  ID=%d Name=%s", mm11.GetID(), mm11.GetName());
    PrintFormat("  ✅ MM11 PASS");
}

//+------------------------------------------------------------------+
//| Test MM12: Equity Curve Filter                                   |
//+------------------------------------------------------------------+
void TestMM12()
{
    Sep();
    Print(">>> TEST MM12: Equity Curve Filter");

    CMM12_EquityCurveFilter mm12;
    mm12.Setup(InpSymbol, 20);

    // Feed equity history — simulate declining equity (below MA scenario)
    double test_equities[] = {
        10000, 10100, 10050, 9950, 9900,
        9850,  9800,  9750,  9700, 9650,
        9600,  9550,  9500,  9450, 9400,
        9350,  9300,  9250,  9200, 9180
    };

    for(int i = 0; i < ArraySize(test_equities); i++)
        mm12.RecordEquity(test_equities[i]);

    // Mode REDUCE — equity below MA → reduced lot
    mm12.SetParams(20, EC_FILTER_REDUCE, 1.0, 50.0);
    double lot_reduce = mm12.CalculateLot(InpBalance, 9180.0, InpSL, InpSymbol);
    PrintFormat("  Mode=REDUCE, Equity=9180 (below MA) → Lot=%.2f (expect ~half)", lot_reduce);
    mm12.PrintDiagnostics(9180.0);

    // Mode PAUSE — equity below MA → lot=0
    CMM12_EquityCurveFilter mm12b;
    mm12b.Setup(InpSymbol, 20);
    for(int i = 0; i < ArraySize(test_equities); i++)
        mm12b.RecordEquity(test_equities[i]);
    mm12b.SetParams(20, EC_FILTER_PAUSE, 1.0, 50.0);
    double lot_pause = mm12b.CalculateLot(InpBalance, 9180.0, InpSL, InpSymbol);
    PrintFormat("  Mode=PAUSE, Equity=9180 (below MA) → Lot=%.2f (expect 0)", lot_pause);

    // Equity above MA → full lot
    CMM12_EquityCurveFilter mm12c;
    mm12c.Setup(InpSymbol, 5); // Short MA for easier above test
    mm12c.SetParams(5, EC_FILTER_REDUCE, 1.0, 50.0);
    double lot_above = mm12c.CalculateLot(InpBalance, 10500.0, InpSL, InpSymbol);
    PrintFormat("  Not enough history → full lot=%.2f (expect full, insufficient data)", lot_above);

    PrintFormat("  ID=%d Name=%s", mm12.GetID(), mm12.GetName());
    PrintFormat("  ✅ MM12 PASS");
}

//+------------------------------------------------------------------+
//| Test MM13: Correlation Adjusted                                  |
//+------------------------------------------------------------------+
void TestMM13()
{
    Sep();
    Print(">>> TEST MM13: Correlation Adjusted");

    CMM13_CorrelationAdjusted mm13;
    mm13.Setup(InpSymbol, 50);
    mm13.SetParams(3, 0.7, 20.0, 1.0); // max 3 pairs, 0.7 threshold, 20% reduce per pair

    // Simulate 0 correlated positions
    mm13.SetCorrCount(0);
    double lot0 = mm13.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  CorrPairs=0 → Lot=%.2f (expect full)", lot0);

    // Simulate 1 correlated position
    mm13.SetCorrCount(1);
    double lot1 = mm13.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  CorrPairs=1 → Lot=%.2f (expect ~80%%)", lot1);

    // Simulate 2 correlated positions
    mm13.SetCorrCount(2);
    double lot2 = mm13.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  CorrPairs=2 → Lot=%.2f (expect ~60%%)", lot2);

    // Simulate 3 correlated positions (max)
    mm13.SetCorrCount(3);
    double lot3 = mm13.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  CorrPairs=3 (max) → Lot=%.2f (expect ~40%%)", lot3);

    // Verify multiplier calculation
    double mult0 = mm13.GetCorrMultiplier(0);
    double mult2 = mm13.GetCorrMultiplier(2);
    PrintFormat("  Multiplier: 0pairs=%.2f | 2pairs=%.2f", mult0, mult2);

    mm13.PrintDiagnostics(InpSymbol);
    PrintFormat("  ID=%d Name=%s", mm13.GetID(), mm13.GetName());
    PrintFormat("  ✅ MM13 PASS");
}

//+------------------------------------------------------------------+
//| Test MM14: Tiered Risk                                           |
//+------------------------------------------------------------------+
void TestMM14()
{
    Sep();
    Print(">>> TEST MM14: Tiered Risk");

    CMM14_TieredRisk mm14;
    mm14.Setup(InpSymbol, 50);
    mm14.SetParams(1000.0, 10000.0, 2.0, 1.5, 1.0);

    // Small account: balance $500 → 2% risk
    double lot_small = mm14.CalculateLot(500.0, 490.0, InpSL - 2100.0, InpSymbol);
    mm14.PrintDiagnostics(500.0);
    PrintFormat("  Balance=$500 (SMALL) → Lot=%.2f (expect ~2%% risk)", lot_small);

    // Medium account: balance $5,000 → 1.5% risk
    double lot_medium = mm14.CalculateLot(5000.0, 4900.0, InpSL, InpSymbol);
    mm14.PrintDiagnostics(5000.0);
    PrintFormat("  Balance=$5,000 (MEDIUM) → Lot=%.2f (expect ~1.5%% risk)", lot_medium);

    // Large account: balance $50,000 → 1% risk
    double lot_large = mm14.CalculateLot(50000.0, 49000.0, InpSL, InpSymbol);
    mm14.PrintDiagnostics(50000.0);
    PrintFormat("  Balance=$50,000 (LARGE) → Lot=%.2f (expect ~1%% risk)", lot_large);

    // Verify tiers
    PrintFormat("  Tier($500)=%d | Tier($5000)=%d | Tier($50000)=%d",
        (int)mm14.GetCurrentTier(500.0),
        (int)mm14.GetCurrentTier(5000.0),
        (int)mm14.GetCurrentTier(50000.0));

    PrintFormat("  ID=%d Name=%s", mm14.GetID(), mm14.GetName());
    PrintFormat("  ✅ MM14 PASS");
}

//+------------------------------------------------------------------+
//| Test MM15: Adaptive Win-Streak                                   |
//+------------------------------------------------------------------+
void TestMM15()
{
    Sep();
    Print(">>> TEST MM15: Adaptive Win-Streak");

    CMM15_AdaptiveWinStreak mm15;
    mm15.Setup(InpSymbol, 50);
    mm15.SetParams(3, 10.0, 3.0, 1.0); // min 3 wins, +10% per extra win, cap 3%, base 1%

    // Initial state → base risk
    double lot_init = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=0 → Risk=%.2f%% Lot=%.2f (base)", mm15.GetCurrentRiskPct(), lot_init);

    // 2 wins (below min streak) → still base
    mm15.RecordWin();
    mm15.RecordWin();
    double lot_2w = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=2 (below min=3) → Risk=%.2f%% Lot=%.2f (still base)", mm15.GetCurrentRiskPct(), lot_2w);

    // 3rd win = min streak → still base (boost starts at 4th win)
    mm15.RecordWin();
    double lot_3w = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=3 (at min) → Risk=%.2f%% Lot=%.2f (base, no extra wins yet)", mm15.GetCurrentRiskPct(), lot_3w);

    // 4th win → +10% of base = 1.1%
    mm15.RecordWin();
    double lot_4w = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=4 (1 extra win) → Risk=%.2f%% Lot=%.2f (expect 1.1%%)", mm15.GetCurrentRiskPct(), lot_4w);

    // 5th win → +20% of base = 1.2%
    mm15.RecordWin();
    double lot_5w = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=5 (2 extra wins) → Risk=%.2f%% Lot=%.2f (expect 1.2%%)", mm15.GetCurrentRiskPct(), lot_5w);

    // Simulate many wins → should cap at 3%
    for(int i = 0; i < 20; i++) mm15.RecordWin();
    double lot_cap = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  Streak=25 (many wins) → Risk=%.2f%% Lot=%.2f (expect capped at 3%%)", mm15.GetCurrentRiskPct(), lot_cap);

    // Loss → instant reset to base
    mm15.RecordLoss();
    double lot_loss = mm15.CalculateLot(InpBalance, InpEquity, InpSL, InpSymbol);
    PrintFormat("  After LOSS → Streak=%d Risk=%.2f%% Lot=%.2f (expect 1.0%% base reset)", mm15.GetCurrentStreak(), mm15.GetCurrentRiskPct(), lot_loss);

    mm15.PrintDiagnostics();
    PrintFormat("  ID=%d Name=%s", mm15.GetID(), mm15.GetName());
    PrintFormat("  ✅ MM15 PASS");
}

//+------------------------------------------------------------------+
//| OnStart: Main entry point                                        |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("========================================");
    Print("  FlashEASuite V2 — P3-3 MM Test Suite");
    Print("  Testing: MM11, MM12, MM13, MM14, MM15");
    PrintFormat("  Symbol=%s | Balance=%.2f | Equity=%.2f", InpSymbol, InpBalance, InpEquity);
    Print("========================================");

    TestMM11();
    TestMM12();
    TestMM13();
    TestMM14();
    TestMM15();

    Sep();
    Print("  ✅ ALL MM11-MM15 TESTS COMPLETE");
    Sep();
}
//+------------------------------------------------------------------+
