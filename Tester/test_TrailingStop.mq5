//+------------------------------------------------------------------+
//| test_TrailingStop.mq5                                            |
//| FlashEASuite V2 — Unit Test: CTrailingStop                       |
//| วิธีรัน: Drag onto XAUUSD.tp chart → ดู Experts tab             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#include "../Include/Logic/Common/TrailingStop.mqh"

input string  Test_Symbol  = "XAUUSD.tp";
input bool    Test_Verbose = true;

int g_passed = 0;
int g_failed = 0;

void Assert(bool condition, string name)
{
    if(condition)
    {
        if(Test_Verbose) PrintFormat("[PASS] %s", name);
        g_passed++;
    }
    else
    {
        PrintFormat("[FAIL] %s", name);
        g_failed++;
    }
}

//+------------------------------------------------------------------+
void OnStart()
{
    Print("========================================");
    Print("  test_TrailingStop — FlashEASuite V2 V6");
    Print("========================================");

    Test_Enums();
    Test_DefaultParams();
    Test_Config();
    Test_SlotManagement();
    Test_RegisterNoPosition();
    Test_UpdateEmpty();
    Test_BreakevenState();
    Test_ParamsOverride();
    Test_FreeSlotNoCrash();
    Test_PrintStatus();

    PrintFormat("========================================");
    PrintFormat("  RESULT: %d PASSED | %d FAILED", g_passed, g_failed);
    PrintFormat("========================================");
    if(g_failed == 0) Print("  ✅ ALL TESTS PASSED");
    else PrintFormat("  ❌ %d FAILED", g_failed);
}

//+------------------------------------------------------------------+
//| Test 1: Enum values >= 0                                         |
//+------------------------------------------------------------------+
void Test_Enums()
{
    Print("--- Test_Enums ---");
    Assert((int)TS_FIXED      == 0, "TS_FIXED = 0");
    Assert((int)TS_ATR        == 1, "TS_ATR = 1");
    Assert((int)TS_PARABOLIC  == 2, "TS_PARABOLIC = 2");
    Assert((int)TS_CHANDELIER == 3, "TS_CHANDELIER = 3");
    Assert((int)TS_BREAKEVEN  == 4, "TS_BREAKEVEN = 4");
    Assert((int)BE_WAITING    == 0, "BE_WAITING = 0");
    Assert((int)BE_APPLIED    == 1, "BE_APPLIED = 1");
}

//+------------------------------------------------------------------+
//| Test 2: Default params                                           |
//+------------------------------------------------------------------+
void Test_DefaultParams()
{
    Print("--- Test_DefaultParams ---");
    CTrailingStop ts;
    STrailParams p = ts.GetParams();

    Assert(p.method         == TS_FIXED, "Default method = TS_FIXED");
    Assert(p.fixed_pips     == 20.0,     "Default fixed_pips = 20");
    Assert(p.atr_multiplier == 2.0,      "Default atr_mult = 2.0");
    Assert(p.atr_period     == 14,       "Default atr_period = 14");
    Assert(p.sar_step       == 0.02,     "Default sar_step = 0.02");
    Assert(p.sar_maximum    == 0.20,     "Default sar_max = 0.2");
    Assert(p.chandelier_mult == 3.0,     "Default chandelier_mult = 3.0");
    Assert(p.be_trigger_pips == 15.0,    "Default be_trigger = 15");
    Assert(p.be_trail_pips   == 10.0,    "Default be_trail = 10");
}

//+------------------------------------------------------------------+
//| Test 3: Config flags                                             |
//+------------------------------------------------------------------+
void Test_Config()
{
    Print("--- Test_Config ---");
    CTrailingStop ts;

    Assert(ts.IsEnabled() == true, "Default enabled");
    Assert(ts.GetTrackedCount() == 0, "Default count = 0");

    ts.SetEnabled(false);
    Assert(ts.IsEnabled() == false, "SetEnabled(false)");

    ts.SetEnabled(true);
    Assert(ts.IsEnabled() == true, "SetEnabled(true)");

    ts.SetMethod(TS_ATR);
    Assert(ts.GetParams().method == TS_ATR, "SetMethod(TS_ATR)");

    ts.SetMethod(TS_FIXED);
    Assert(ts.GetParams().method == TS_FIXED, "SetMethod back to TS_FIXED");
}

//+------------------------------------------------------------------+
//| Test 4: Slot management — no real positions                      |
//+------------------------------------------------------------------+
void Test_SlotManagement()
{
    Print("--- Test_SlotManagement ---");
    CTrailingStop ts;

    Assert(ts.GetTrackedCount() == 0, "Initial tracked = 0");
    Assert(ts.GetCurrentSL(99999) == 0.0, "Unknown ticket SL = 0");
}

//+------------------------------------------------------------------+
//| Test 5: Register without real position → returns false           |
//+------------------------------------------------------------------+
void Test_RegisterNoPosition()
{
    Print("--- Test_RegisterNoPosition ---");
    CTrailingStop ts;

    bool result = ts.Register(99999);
    Assert(result == false, "Register fake ticket → false");
    Assert(ts.GetTrackedCount() == 0, "Count still 0 after failed register");
}

//+------------------------------------------------------------------+
//| Test 6: Disabled → Register returns false                        |
//+------------------------------------------------------------------+
void Test_UpdateEmpty()
{
    Print("--- Test_UpdateEmpty ---");
    CTrailingStop ts;

    // Update on empty table
    int mod = ts.Update();
    Assert(mod == 0, "Update empty = 0");

    // Disabled → Update returns 0
    ts.SetEnabled(false);
    mod = ts.Update();
    Assert(mod == 0, "Update when disabled = 0");
    ts.SetEnabled(true);

    // Disabled → Register returns false
    ts.SetEnabled(false);
    bool r = ts.Register(11111);
    Assert(r == false, "Register when disabled → false");
    ts.SetEnabled(true);
}

//+------------------------------------------------------------------+
//| Test 7: BE state enum transitions (unit)                         |
//+------------------------------------------------------------------+
void Test_BreakevenState()
{
    Print("--- Test_BreakevenState ---");

    // Verify BE_WAITING is 0 (initial state on Reset)
    STrailRecord rec;
    rec.Reset();
    Assert(rec.be_state == BE_WAITING, "Record.Reset() → BE_WAITING");
    Assert(rec.active   == false,      "Record.Reset() → active=false");
    Assert(rec.ticket   == 0,          "Record.Reset() → ticket=0");
}

//+------------------------------------------------------------------+
//| Test 8: SetParams override                                       |
//+------------------------------------------------------------------+
void Test_ParamsOverride()
{
    Print("--- Test_ParamsOverride ---");

    CTrailingStop ts;
    STrailParams custom;
    custom.Reset();
    custom.method       = TS_CHANDELIER;
    custom.chandelier_mult = 4.5;
    custom.atr_period   = 21;

    ts.SetParams(custom);
    STrailParams p = ts.GetParams();

    Assert(p.method           == TS_CHANDELIER, "SetParams: method=TS_CHANDELIER");
    Assert(p.chandelier_mult  == 4.5,           "SetParams: chandelier_mult=4.5");
    Assert(p.atr_period       == 21,            "SetParams: atr_period=21");
}

//+------------------------------------------------------------------+
//| Test 9: Unregister unknown ticket — no crash                     |
//+------------------------------------------------------------------+
void Test_FreeSlotNoCrash()
{
    Print("--- Test_FreeSlotNoCrash ---");
    CTrailingStop ts;

    ts.Unregister(99999);   // should not crash
    Assert(ts.GetTrackedCount() == 0, "Unregister unknown no crash");

    // Multiple unregisters
    ts.Unregister(0);
    ts.Unregister(0);
    Assert(true, "Duplicate Unregister(0) no crash");
}

//+------------------------------------------------------------------+
//| Test 10: PrintStatus — no crash                                  |
//+------------------------------------------------------------------+
void Test_PrintStatus()
{
    Print("--- Test_PrintStatus ---");
    CTrailingStop ts;
    ts.PrintStatus();
    Assert(true, "PrintStatus no crash");
}
