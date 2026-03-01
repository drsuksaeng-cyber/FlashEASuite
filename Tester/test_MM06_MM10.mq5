//+------------------------------------------------------------------+
//| test_MM06_MM10.mq5                                               |
//| FlashEASuite V2 V6 — Unit Test: MM06-MM10                       |
//+------------------------------------------------------------------+
//| HOW TO RUN:                                                      |
//|   MetaEditor → Compile → Script → Attach to any chart           |
//|   Check Journal tab for results                                  |
//+------------------------------------------------------------------+
#property script_show_inputs false

// Include MM files
// Test อยู่ที่: Tester/
// MM อยู่ที่:   Include/Logic/MM/
// → relative: ../Include/Logic/MM/
#include "../Include/Logic/MM/IMoneyManager.mqh"
#include "../Include/Logic/MM/MM06_AntiMartingale.mqh"
#include "../Include/Logic/MM/MM07_PctVolatility.mqh"
#include "../Include/Logic/MM/MM08_Pyramid.mqh"
#include "../Include/Logic/MM/MM09_EquityCurveRecovery.mqh"
#include "../Include/Logic/MM/MM10_DrawdownBased.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    string sym    = "XAUUSD.tp";     // ✅ broker suffix .tp (LESSONS LEARNED #7)
    double bal    = 10000.0;
    double eq     = 10000.0;
    double sl     = 2.0;      // 2 price units SL (e.g. XAUUSD = $2)

    Print("=== FlashEASuite V2 — MM06-MM10 Test ===");
    Print("Symbol: ", sym, " Balance: ", bal, " Equity: ", eq, " SL: ", sl);
    Print("-----------------------------------------------");

    //--- MM06: Anti-Martingale ---
    {
        CMM06_AntiMartingale mm06;
        mm06.Setup(sym);
        mm06.SetParams(1.0, 0.5, 3.0, 1);

        // Simulate win streak
        Print("[MM06] AntiMartingale — win streak test");
        for(int i = 0; i < 5; i++)
        {
            double lot = mm06.CalculateLot(bal, eq, sl, sym);
            Print("  Win #", i, " Lot:", lot, " | ", mm06.GetDiagnostic());
            mm06.UpdateTradeResult(true, 1.5);
        }
        mm06.UpdateTradeResult(false, 0.0); // Loss → reset
        double lot_after_loss = mm06.CalculateLot(bal, eq, sl, sym);
        Print("  After loss: Lot=", lot_after_loss, " | ", mm06.GetDiagnostic());
        Print("  MM06 ID=", mm06.GetID(), " Name=", mm06.GetName());
    }
    Print("-----------------------------------------------");

    //--- MM07: Percent Volatility ---
    {
        CMM07_PctVolatility mm07;
        mm07.Setup(sym);
        mm07.SetParams(1.0, 20);

        double lot = mm07.CalculateLot(bal, eq, sl, sym);
        Print("[MM07] PctVolatility Lot=", lot, " | ", mm07.GetDiagnostic());
        Print("  MM07 ID=", mm07.GetID(), " Name=", mm07.GetName());

        // Test with different balance
        double lot2 = mm07.CalculateLot(20000.0, 20000.0, sl, sym);
        Print("  Double balance Lot=", lot2, " (should be ~2x)");
    }
    Print("-----------------------------------------------");

    //--- MM08: Pyramid ---
    {
        CMM08_Pyramid mm08;
        mm08.Setup(sym);
        mm08.SetParams(50.0, 1.0, 50.0);

        Print("[MM08] Pyramid — 3-level test");
        double lot0 = mm08.CalculateLot(bal, eq, sl, sym);
        Print("  Level 0 (initial): Lot=", lot0);

        mm08.AdvanceLevel();
        double lot1 = mm08.CalculateLot(bal, eq, sl, sym);
        Print("  Level 1 (add): Lot=", lot1, " (should be ~50% of L0)");

        mm08.AdvanceLevel();
        double lot2 = mm08.CalculateLot(bal, eq, sl, sym);
        Print("  Level 2 (add): Lot=", lot2, " (should be ~25% of L0)");

        mm08.AdvanceLevel();
        double lot3 = mm08.CalculateLot(bal, eq, sl, sym);
        Print("  Level 3 (max reached): Lot=", lot3, " (should be 0)");

        // Test ShouldAdd
        bool should_add = mm08.ShouldAddPosition(bal * 0.01 * 1.5);
        Print("  ShouldAdd at 1.5R: ", should_add);

        mm08.UpdateTradeResult(true, 2.0);
        Print("  After close (reset): Level=", mm08.GetPyramidLevel());
        Print("  MM08 ID=", mm08.GetID(), " Name=", mm08.GetName());
    }
    Print("-----------------------------------------------");

    //--- MM09: Equity Curve Recovery ---
    {
        CMM09_EquityCurveRecovery mm09;
        mm09.Setup(sym, 50);
        mm09.SetParams(20, 50.0, 0);

        Print("[MM09] EquityCurveRecovery — simulate drawdown");

        // Fill history with high equity, then drop
        for(int i = 0; i < 20; i++)
        {
            mm09.CalculateLot(bal, 10500.0 - i * 10, sl, sym);
            mm09.UpdateTradeResult(i % 3 != 0, 1.0);
        }

        // Now equity below MA
        double lot_low = mm09.CalculateLot(bal, 9000.0, sl, sym);
        Print("  Equity below MA Lot=", lot_low, " | ", mm09.GetDiagnostic());

        // Equity above MA
        double lot_high = mm09.CalculateLot(bal, 11000.0, sl, sym);
        Print("  Equity above MA Lot=", lot_high, " | ", mm09.GetDiagnostic());
        Print("  MM09 ID=", mm09.GetID(), " Name=", mm09.GetName());
    }
    Print("-----------------------------------------------");

    //--- MM10: Drawdown Based ---
    {
        CMM10_DrawdownBased mm10;
        mm10.Setup(sym);
        mm10.SetParams(10.0, 15.0, 20.0, 50.0, 1.0);

        Print("[MM10] DrawdownBased — tier test");

        // Normal DD
        double lot_normal = mm10.CalculateLot(bal, 10000.0, sl, sym);
        Print("  DD=0%: Lot=", lot_normal, " | ", mm10.GetDiagnostic());

        // Tier1: 10% DD
        double lot_t1 = mm10.CalculateLot(bal, 9000.0, sl, sym);
        Print("  DD=10%: Lot=", lot_t1, " | ", mm10.GetDiagnostic());

        // Tier2: 15% DD
        double lot_t2 = mm10.CalculateLot(bal, 8500.0, sl, sym);
        Print("  DD=15%: Lot=", lot_t2, " | ", mm10.GetDiagnostic());

        // Emergency: 20% DD
        double lot_em = mm10.CalculateLot(bal, 8000.0, sl, sym);
        Print("  DD=20%: Lot=", lot_em, " Emergency=", mm10.IsEmergencyMode(),
              " | ", mm10.GetDiagnostic());

        // Recovery
        double lot_rec = mm10.CalculateLot(bal, 9800.0, sl, sym);
        Print("  Recovery 9800: Lot=", lot_rec, " | ", mm10.GetDiagnostic());
        Print("  MM10 ID=", mm10.GetID(), " Name=", mm10.GetName());
    }

    Print("=== ALL MM06-MM10 TESTS COMPLETE ===");
}
