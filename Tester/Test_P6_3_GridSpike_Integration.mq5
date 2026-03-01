//+------------------------------------------------------------------+
//| Test_P6_3_GridSpike_Integration.mq5                              |
//| FlashEASuite V2 — P6-3 Integration Test (corrected API)         |
//+------------------------------------------------------------------+
//| Tests:                                                           |
//|  1.  S15_Grid Init + Identity                                    |
//|  2.  S15_Grid + MMManager Online (MM3 ATR-based)                |
//|  3.  S15_Grid Standalone → MM1 forced                           |
//|  4.  S16_Spike Init + Identity                                   |
//|  5.  S16_Spike + MMManager (MM1 default)                        |
//|  6.  S16_Spike Hidden TP/SL config + ManagePositions()          |
//|  7.  CHiddenTPSL unit test (existing API)                       |
//|  8.  CTrailingStop unit test (existing API)                     |
//|  9.  TransferToGrid() (no open positions)                       |
//|  10. JSON SetParameters hot-reload                               |
//|  11. MMManager matrix verification                               |
//+------------------------------------------------------------------+
#property script_show_inputs

input string Test_Symbol = "XAUUSD.tp";   // P3-2/P2-3 lesson: broker suffix

//--- Include paths from Tester/ (1 level up → Include/Logic/...)
#include "../Include/Logic/Strategies/S15_Grid.mqh"
#include "../Include/Logic/Strategies/S16_Spike.mqh"
#include "../Include/Logic/MM/MMManager.mqh"
//--- Common modules (already included via S15/S16, but reference here for clarity)
// #include "../Include/Logic/Common/HiddenTPSL.mqh"
// #include "../Include/Logic/Common/TrailingStop.mqh"
// #include "../Include/Logic/Common/TransferToGrid.mqh"

//+------------------------------------------------------------------+
int g_pass = 0;
int g_fail = 0;

void _Check(string name, bool cond)
{
    if(cond) { PrintFormat("   ✅ PASS | %s", name); g_pass++; }
    else      { PrintFormat("   ❌ FAIL | %s", name); g_fail++; }
}

void _Header(string title)
{
    Print("─────────────────────────────────────────────────");
    PrintFormat("📋 %s", title);
}

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("╔═════════════════════════════════════════════════╗");
    Print("║  P6-3 Test: Grid + Spike + MM + HiddenTPSL     ║");
    Print("╚═════════════════════════════════════════════════╝");
    PrintFormat("Symbol: %s", Test_Symbol);

    //─── TEST 1: S15_Grid Init + Identity ────────────────────────────
    _Header("TEST 1: S15_Grid Init + Identity");
    {
        CS15Grid grid;
        bool ok = grid.Init(Test_Symbol, PERIOD_M15);
        _Check("Grid Init() returns true",         ok);
        _Check("Grid GetMagic() == 1015",          grid.GetMagic() == MAGIC_S15_GRID);
        _Check("Grid IsStandaloneCapable()",       grid.IsStandaloneCapable());
        _Check("Grid GetName() correct",           grid.GetName() == "Immortal Grid");
        _Check("Grid GetCategory() correct",       grid.GetCategory() == "Full_MQL5");
        _Check("Grid GetActiveGridCount() >= 0",   grid.GetActiveGridCount() >= 0);
        _Check("Grid GetHiddenTPSLCount() == 0",   grid.GetHiddenTPSLCount() == 0);
        _Check("Grid GetTrailCount() == 0",        grid.GetTrailCount() == 0);
        grid.Deinit();
    }

    //─── TEST 2: S15_Grid + MMManager Online (MM3 ATR-based) ─────────
    _Header("TEST 2: S15_Grid + MMManager Online");
    {
        CS15Grid   grid;
        CMMManager mm;
        mm.Setup(false);    // Online mode
        grid.Init(Test_Symbol, PERIOD_M15);
        grid.SetMMManager(&mm);

        // S15 default → MM03 ATR-based (matrix index 14)
        ENUM_MM_ID def = grid.GetActiveMM();
        _Check("Grid online MM == MM03", def == MM_ID_ATR_BASED);

        // Volatile regime → MM17
        ENUM_MM_ID vol = grid.GetActiveMM_WithRegime(REGIME_VOLATILE);
        _Check("Grid volatile MM == MM17", vol == MM_ID_REGIME_BASED);

        // Server override MM05
        mm.ApplyConfig((int)S15_GRID, 5);
        _Check("Grid server override == MM05", grid.GetActiveMM() == 5);

        // Clear override → back to MM03
        mm.ClearAllOverrides();
        // Root cause: SelectMM reads live DD — if DD>10% returns MM10 (correct behavior!)
        // Fix: verify matrix reset via GetDefaultMM, not runtime SelectMM
        _Check("Grid cleared override → matrix default MM03", mm.GetDefaultMM((int)S15_GRID) == MM_ID_ATR_BASED);
        _Check("Grid GetActiveMM (matrix) MM03", mm.GetActiveMM((int)S15_GRID) == MM_ID_ATR_BASED);

        grid.Deinit();
    }

    //─── TEST 3: S15_Grid Standalone → MM1 forced ────────────────────
    _Header("TEST 3: S15_Grid Standalone Mode");
    {
        CS15Grid   grid;
        CMMManager mm;
        mm.Setup(true);     // Standalone → forces MM01
        grid.Init(Test_Symbol, PERIOD_M15);
        grid.SetMMManager(&mm);

        _Check("Grid standalone → MM01 forced",  grid.GetActiveMM() == MM_ID_FIXED_CONSERVATIVE);
        _Check("MMManager IsStandaloneMode()",    mm.IsStandaloneMode());

        grid.SetStandaloneMode(false);
        _Check("SetStandaloneMode(false) propagates", !mm.IsStandaloneMode());
        grid.Deinit();
    }

    //─── TEST 4: S16_Spike Init + Identity ───────────────────────────
    _Header("TEST 4: S16_Spike Init + Identity");
    {
        CS16Spike spike;
        bool ok = spike.Init(Test_Symbol, PERIOD_M1);
        _Check("Spike Init() returns true",          ok);
        _Check("Spike GetMagic() == 1016",           spike.GetMagic() == MAGIC_S16_SPIKE);
        _Check("Spike IsStandaloneCapable()",        spike.IsStandaloneCapable());
        _Check("Spike GetName() correct",            spike.GetName() == "Spike Hunter");
        _Check("Spike GetSpikeATR() >= 0",           spike.GetSpikeATR() >= 0.0);
        _Check("Spike GetHiddenTPSLCount() == 0",    spike.GetHiddenTPSLCount() == 0);
        spike.Deinit();
    }

    //─── TEST 5: S16_Spike + MMManager ───────────────────────────────
    _Header("TEST 5: S16_Spike + MMManager");
    {
        CS16Spike  spike;
        CMMManager mm;
        mm.Setup(false);
        spike.Init(Test_Symbol, PERIOD_M1);
        spike.SetMMManager(&mm);

        // S16 default → MM01, volatile → MM01 (no size change for spike)
        _Check("Spike online MM == MM01",
               spike.GetActiveMM() == MM_ID_FIXED_CONSERVATIVE);
        _Check("Spike volatile MM == MM01",
               spike.GetActiveMM_WithRegime(REGIME_VOLATILE) == MM_ID_FIXED_CONSERVATIVE);

        // DD MM from matrix
        _Check("Spike DD MM == MM10",
               mm.GetDDMM((int)S16_SPIKE) == MM_ID_DRAWDOWN_BASED);
        spike.Deinit();
    }

    //─── TEST 6: S16_Spike Hidden TP/SL (SetTPSLConfig + ManagePositions) ─
    _Header("TEST 6: S16_Spike Hidden TP/SL Config + ManagePositions");
    {
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);

        // Default hidden TP×0.8, SL×0.4 (set in constructor)
        // No open positions → count stays 0
        _Check("Spike default HiddenTPSL count == 0", spike.GetHiddenTPSLCount() == 0);

        // SetTPSLConfig override
        spike.SetTPSLConfig(1.5, 0.5, false, TS_ATR, 600);

        // ManagePositions with no open positions → runs cleanly
        MqlTick tick;
        if(SymbolInfoTick(Test_Symbol, tick))
        {
            spike.Analyze(tick);
            spike.ManagePositions(tick);
        }
        _Check("Spike ManagePositions(no positions) → count stays 0",
               spike.GetHiddenTPSLCount() == 0);

        spike.Deinit();
    }

    //─── TEST 7: CHiddenTPSL Unit Test (real existing API) ────────────
    _Header("TEST 7: CHiddenTPSL Unit Test (real API)");
    {
        CHiddenTPSL htpsl;

        // Initial state
        _Check("HiddenTPSL GetTrackedCount() == 0", htpsl.GetTrackedCount() == 0);
        _Check("HiddenTPSL GetHiddenTP(0) == 0",    htpsl.GetHiddenTP(0) == 0.0);
        _Check("HiddenTPSL GetHiddenSL(0) == 0",    htpsl.GetHiddenSL(0) == 0.0);

        // SetEnabled
        htpsl.SetEnabled(true, true);
        _Check("HiddenTPSL IsTPEnabled()", htpsl.IsTPEnabled());
        _Check("HiddenTPSL IsSLEnabled()", htpsl.IsSLEnabled());

        htpsl.SetEnabled(false, false);
        _Check("HiddenTPSL SetEnabled(false,false) TP off", !htpsl.IsTPEnabled());
        _Check("HiddenTPSL SetEnabled(false,false) SL off", !htpsl.IsSLEnabled());

        // SetTolerancePips
        htpsl.SetTolerancePips(2.0);  // just verify no crash

        // SetHiddenTP/SL with fake ticket (ticket doesn't exist → returns false gracefully)
        // Real SetHiddenTP requires PositionSelectByTicket to succeed
        // → Test that false is returned (no crash) for non-existent ticket
        bool tp_set = htpsl.SetHiddenTP(9999999, 2100.0);
        _Check("HiddenTPSL SetHiddenTP(fake) returns false gracefully", !tp_set);
        bool sl_set = htpsl.SetHiddenSL(9999999, 1900.0);
        _Check("HiddenTPSL SetHiddenSL(fake) returns false gracefully", !sl_set);

        // Count stays 0 (slot not allocated for non-existent ticket)
        _Check("HiddenTPSL count stays 0 after failed sets", htpsl.GetTrackedCount() == 0);

        // ClearHidden of non-existent ticket: no crash
        htpsl.ClearHidden(9999999);
        _Check("HiddenTPSL ClearHidden(fake) no crash", true);

        // CheckAndClose with nothing to close
        int closed = htpsl.CheckAndClose();
        _Check("HiddenTPSL CheckAndClose() returns 0 (no positions)", closed == 0);

        // SetEnabled back
        htpsl.SetEnabled(true, true);
        _Check("HiddenTPSL re-enabled", htpsl.IsTPEnabled());

        htpsl.PrintStatus();
    }

    //─── TEST 8: CTrailingStop Unit Test (real existing API) ──────────
    _Header("TEST 8: CTrailingStop Unit Test (real API)");
    {
        CTrailingStop trail;

        _Check("TrailingStop GetTrackedCount() == 0", trail.GetTrackedCount() == 0);
        _Check("TrailingStop IsEnabled()",            trail.IsEnabled());

        // SetEnabled
        trail.SetEnabled(false);
        _Check("TrailingStop SetEnabled(false)", !trail.IsEnabled());
        trail.SetEnabled(true);
        _Check("TrailingStop SetEnabled(true)", trail.IsEnabled());

        // SetMethod
        trail.SetMethod(TS_ATR);
        _Check("TrailingStop SetMethod(TS_ATR) no crash", true);
        trail.SetMethod(TS_FIXED);

        // SetParams / GetParams round-trip
        STrailParams p;
        p.Reset();
        p.method     = TS_BREAKEVEN;
        p.fixed_pips = 30.0;
        p.atr_multiplier = 2.5;
        trail.SetParams(p);
        STrailParams got = trail.GetParams();
        _Check("TrailingStop SetParams/GetParams method",   got.method == TS_BREAKEVEN);
        _Check("TrailingStop SetParams/GetParams fixed_pips", MathAbs(got.fixed_pips - 30.0) < 0.01);
        _Check("TrailingStop SetParams/GetParams atr_mult",  MathAbs(got.atr_multiplier - 2.5) < 0.01);

        // Register with non-existent ticket → false gracefully
        bool reg = trail.Register(9999999);
        _Check("TrailingStop Register(fake) returns false gracefully", !reg);
        _Check("TrailingStop count stays 0 after failed register", trail.GetTrackedCount() == 0);

        // Unregister non-existent → no crash
        trail.Unregister(9999999);
        _Check("TrailingStop Unregister(fake) no crash", true);

        // Update with empty table → returns 0
        int modified = trail.Update();
        _Check("TrailingStop Update() empty → 0 modified", modified == 0);
    }

    //─── TEST 9: TransferToGrid() ─────────────────────────────────────
    _Header("TEST 9: TransferToGrid()");
    {
        // No non-grid positions open → success with 0 closed
        STransferResult res = TransferToGrid(Test_Symbol, MAGIC_S15_GRID, TRANSFER_MANUAL);
        _Check("TransferToGrid() sets transfer_time",          res.transfer_time > 0);
        // NOTE: account may have open positions → closed_count depends on live state
        // Correct behavior: all non-grid positions get closed, close_failed == 0
        _Check("TransferToGrid() success",          res.success);
        _Check("TransferToGrid() close_failed == 0", res.close_failed == 0);
        _Check("TransferToGrid() P&L logged",        res.realized_pnl >= 0.0 || res.closed_count == 0);
        _Check("TransferToGrid() reason_str == 'MANUAL'",      res.reason_str == "MANUAL");

        // TransferToGridByDD: DD must be < threshold → returns false
        bool triggered = TransferToGridByDD(Test_Symbol, 99.0);
        _Check("TransferToGridByDD(99%) not triggered on healthy account", !triggered);

        // EmergencyTransferToGrid via Grid strategy
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);
        STransferResult gres = grid.EmergencyTransferToGrid(TRANSFER_DRAWDOWN);
        _Check("Grid EmergencyTransferToGrid() succeeds", gres.success);
        _Check("Grid EmergencyTransferToGrid() reason=DRAWDOWN",
               gres.reason_str == "DRAWDOWN");
        grid.Deinit();

        // EmergencyTransferToGrid via Spike strategy
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);
        STransferResult sres = spike.EmergencyTransferToGrid(TRANSFER_NEWS_EVENT);
        _Check("Spike EmergencyTransferToGrid() succeeds", sres.success);
        _Check("Spike EmergencyTransferToGrid() reason=NEWS_EVENT",
               sres.reason_str == "NEWS_EVENT");
        spike.Deinit();
    }

    //─── TEST 10: JSON SetParameters hot-reload ───────────────────────
    _Header("TEST 10: JSON SetParameters Hot-Reload");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);
        string json = "{\"S15_MAX_ORDERS\":8,\"S15_BASE_STEP\":150,"
                      "\"S15_TP_ATR_MULT\":2.0,\"S15_SL_ATR_MULT\":1.0,"
                      "\"S15_TRAIL_ENABLED\":1}";
        grid.SetParameters(json);
        SDynamicParams p = grid.GetCurrentParams();
        _Check("Grid JSON MAX_ORDERS=8",
               MathAbs(p.GetParam("S15_MAX_ORDERS",0.0) - 8.0) < 0.01);
        _Check("Grid JSON BASE_STEP=150",
               MathAbs(p.GetParam("S15_BASE_STEP",0.0) - 150.0) < 0.01);
        grid.Deinit();

        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);
        string sjson = "{\"S16_ATR_TP_MULT\":1.5,\"S16_ATR_SL_MULT\":0.6,"
                       "\"S16_MAX_HOLD_SEC\":600}";
        spike.SetParameters(sjson);
        _Check("Spike JSON SetParameters runs without error", true);
        spike.Deinit();
    }

    //─── TEST 11: MMManager Selection Matrix S15 + S16 ───────────────
    _Header("TEST 11: MMManager Selection Matrix");
    {
        CMMManager mm;
        mm.Setup(false);

        // GetMMName
        _Check("GetMMName(1)  has MM01", StringFind(mm.GetMMName(1),  "MM01") >= 0);
        _Check("GetMMName(3)  has MM03", StringFind(mm.GetMMName(3),  "MM03") >= 0);
        _Check("GetMMName(10) has MM10", StringFind(mm.GetMMName(10), "MM10") >= 0);
        _Check("GetMMName(17) has MM17", StringFind(mm.GetMMName(17), "MM17") >= 0);

        // S15 matrix (index 14)
        _Check("S15 DefaultMM == MM03",  mm.GetDefaultMM(14)  == MM_ID_ATR_BASED);
        _Check("S15 VolatileMM == MM17", mm.GetVolatileMM(14) == MM_ID_REGIME_BASED);
        _Check("S15 DDMM == MM10",       mm.GetDDMM(14)       == MM_ID_DRAWDOWN_BASED);

        // S16 matrix (index 15)
        _Check("S16 DefaultMM == MM01",  mm.GetDefaultMM(15)  == MM_ID_FIXED_CONSERVATIVE);
        _Check("S16 VolatileMM == MM01", mm.GetVolatileMM(15) == MM_ID_FIXED_CONSERVATIVE);
        _Check("S16 DDMM == MM10",       mm.GetDDMM(15)       == MM_ID_DRAWDOWN_BASED);

        // GetActiveMM / IsStandaloneMode
        _Check("MMManager not standalone initially", !mm.IsStandaloneMode());
        _Check("MMManager GetCurrentRegime() == RANGING",
               mm.GetCurrentRegime() == REGIME_RANGING);

        mm.PrintStatus();
    }

    //─── FINAL SUMMARY ───────────────────────────────────────────────
    Print("═════════════════════════════════════════════════");
    PrintFormat("RESULT: %d PASSED | %d FAILED | Total: %d",
                g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("🎉 ALL TESTS PASSED — P6-3 COMPLETE ✅");
    else
        PrintFormat("⚠️  %d tests failed — review log above", g_fail);
    Print("═════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
