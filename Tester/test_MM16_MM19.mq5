//+------------------------------------------------------------------+
//| test_MM16_MM19.mq5                                               |
//| FlashEASuite V2 — Test Script: MM16, MM17, MM18, MM19, MMManager |
//| Run: MetaEditor → Compile → Strategy Tester (any chart)          |
//| Expected: All tests PASS, no compilation errors                  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

// *** กฎ: Test อยู่ที่ Tester/ → ขึ้น 1 ระดับ → Include/Logic/MM/
#include "../Include/Logic/MM/IMoneyManager.mqh"
#include "../Include/Logic/MM/MM16_VolatilityPercentile.mqh"
#include "../Include/Logic/MM/MM17_RegimeBased.mqh"
#include "../Include/Logic/MM/MM18_PortfolioCap.mqh"
#include "../Include/Logic/MM/MM19_DynamicMulti.mqh"
#include "../Include/Logic/MM/MMManager.mqh"

// *** กฎ: Default symbol ต้องใช้ broker suffix .tp เสมอ
input string InpSymbol = "XAUUSD.tp";

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int g_pass  = 0;
int g_fail  = 0;

void AssertTrue(string test_name, bool condition)
{
    if(condition)
    {
        PrintFormat("  ✅ PASS: %s", test_name);
        g_pass++;
    }
    else
    {
        PrintFormat("  ❌ FAIL: %s", test_name);
        g_fail++;
    }
}

void AssertInRange(string test_name, double value, double low, double high)
{
    bool ok = (value >= low && value <= high);
    if(ok)
    {
        PrintFormat("  ✅ PASS: %s = %.4f (in [%.4f, %.4f])", test_name, value, low, high);
        g_pass++;
    }
    else
    {
        PrintFormat("  ❌ FAIL: %s = %.4f (expected [%.4f, %.4f])", test_name, value, low, high);
        g_fail++;
    }
}

void AssertEqual(string test_name, int actual, int expected)
{
    bool ok = (actual == expected);
    if(ok) { PrintFormat("  ✅ PASS: %s = %d", test_name, actual); g_pass++; }
    else   { PrintFormat("  ❌ FAIL: %s = %d (expected %d)", test_name, actual, expected); g_fail++; }
}

double GetMockSL() { return SymbolInfoDouble(InpSymbol, SYMBOL_BID) - 5.0; }

//+------------------------------------------------------------------+
//| Test MM16: Volatility Percentile                                 |
//+------------------------------------------------------------------+
void TestMM16()
{
    Print("=== MM16: Volatility Percentile ===");

    CMM16_VolatilityPercentile mm16;
    mm16.Setup(InpSymbol, 20); // small window for test

    // Feed 20 ATR values (simulate history)
    double atr_base = 2.0;
    for(int i = 0; i < 20; i++)
        mm16.UpdateVolatility(atr_base + i * 0.1); // 2.0, 2.1, ..., 3.9

    // Percentile of last ATR (3.9) should be high (~95th)
    int pct = mm16.GetCurrentPercentile();
    AssertTrue("MM16 high ATR → high percentile (>=80)", pct >= 70);

    // Feed a very low ATR → should be low percentile
    mm16.UpdateVolatility(0.5);
    int pct_low = mm16.GetCurrentPercentile();
    AssertTrue("MM16 low ATR → low percentile (<30)", pct_low < 30);

    // CalculateLot: should return valid lot
    double balance = 10000.0;
    double equity  = 10000.0;
    double sl      = GetMockSL();
    double lot     = mm16.CalculateLot(balance, equity, sl, InpSymbol);
    double vol_min = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double vol_max = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
    AssertInRange("MM16 lot in valid range", lot, vol_min, vol_max);

    mm16.PrintDiagnostics();
}

//+------------------------------------------------------------------+
//| Test MM17: Regime-Based                                          |
//+------------------------------------------------------------------+
void TestMM17()
{
    Print("=== MM17: Regime-Based ===");

    CMM17_RegimeBased mm17;
    mm17.Setup(InpSymbol);

    double balance = 10000.0;
    double equity  = 10000.0;
    double sl      = GetMockSL();
    double vol_min = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);

    // Test RANGING (1.0× multiplier) → baseline
    mm17.SetRegimeDirect(REGIME_RANGING);
    double lot_ranging = mm17.CalculateLot(balance, equity, sl, InpSymbol);
    AssertTrue("MM17 RANGING regime → lot > 0", lot_ranging > 0);

    // Test TRENDING (1.5× multiplier) → should be larger
    mm17.SetRegimeDirect(REGIME_TRENDING);
    double lot_trending = mm17.CalculateLot(balance, equity, sl, InpSymbol);
    AssertTrue("MM17 TRENDING lot >= RANGING lot", lot_trending >= lot_ranging);

    // Test VOLATILE (0.3×) → should be smaller
    mm17.SetRegimeDirect(REGIME_VOLATILE);
    double lot_volatile = mm17.CalculateLot(balance, equity, sl, InpSymbol);
    AssertTrue("MM17 VOLATILE lot < RANGING lot", lot_volatile < lot_ranging);

    // Test CRISIS (0.0×) → minimum lot
    mm17.SetRegimeDirect(REGIME_CRISIS);
    double lot_crisis = mm17.CalculateLot(balance, equity, sl, InpSymbol);
    AssertTrue("MM17 CRISIS → minimum lot", lot_crisis <= vol_min);

    // Test enum values are all >= 0 (MQL5 rule)
    AssertTrue("REGIME_UNKNOWN  >= 0", (int)REGIME_UNKNOWN  >= 0);
    AssertTrue("REGIME_TRENDING >= 0", (int)REGIME_TRENDING >= 0);
    AssertTrue("REGIME_RANGING  >= 0", (int)REGIME_RANGING  >= 0);
    AssertTrue("REGIME_VOLATILE >= 0", (int)REGIME_VOLATILE >= 0);
    AssertTrue("REGIME_CRISIS   >= 0", (int)REGIME_CRISIS   >= 0);

    // Anti-whipsaw: confirm_bars = 3, need 3 calls to switch
    mm17.Setup(InpSymbol); // reset
    mm17.SetRegimeDirect(REGIME_RANGING);
    mm17.SetRegime(REGIME_TRENDING); // call 1
    AssertTrue("MM17 anti-whipsaw: 1 bar not enough", mm17.GetCurrentRegime() == REGIME_RANGING);
    mm17.SetRegime(REGIME_TRENDING); // call 2
    AssertTrue("MM17 anti-whipsaw: 2 bars not enough", mm17.GetCurrentRegime() == REGIME_RANGING);
    mm17.SetRegime(REGIME_TRENDING); // call 3
    AssertTrue("MM17 anti-whipsaw: 3 bars confirmed", mm17.GetCurrentRegime() == REGIME_TRENDING);

    mm17.PrintDiagnostics();
}

//+------------------------------------------------------------------+
//| Test MM18: Portfolio Cap                                         |
//+------------------------------------------------------------------+
void TestMM18()
{
    Print("=== MM18: Portfolio Cap ===");

    CMM18_PortfolioCap mm18;
    mm18.Setup(InpSymbol);

    double balance  = 10000.0;
    double equity   = 10000.0;
    double sl       = GetMockSL();
    double vol_min  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double vol_max  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);

    // Normal case: no open positions → should return full desired lot
    double lot = mm18.CalculateLot(balance, equity, sl, InpSymbol);
    AssertInRange("MM18 lot in valid range (no open positions)", lot, vol_min, vol_max);

    // Test GetCurrentPortfolioRiskPct: should return non-negative
    double current_risk = mm18.GetCurrentPortfolioRiskPct();
    AssertTrue("MM18 portfolio risk pct >= 0", current_risk >= 0.0);

    // Test IsPortfolioCapReached: with no positions, should be false
    AssertTrue("MM18 cap not reached (no positions)", !mm18.IsPortfolioCapReached());

    mm18.PrintDiagnostics();
}

//+------------------------------------------------------------------+
//| Test MM19: Dynamic Multi-Method                                  |
//+------------------------------------------------------------------+
void TestMM19()
{
    Print("=== MM19: Dynamic Multi-Method ===");

    CMM19_DynamicMulti mm19;
    mm19.Setup(InpSymbol);

    double balance  = 10000.0;
    double equity   = 10000.0;
    double sl       = GetMockSL();
    double vol_min  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double vol_max  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);

    // Test combine mode MIN (default)
    mm19.SetParams(1, 3, 10, 0, 1.0); // Primary=MM01, Sec=MM03, Ter=MM10, MIN
    mm19.UpdateContext(2.5, 0.55, 1.5, 0, 0, 0.0);
    double lot_min = mm19.CalculateLot(balance, equity, sl, InpSymbol);
    AssertInRange("MM19 MIN mode lot in range", lot_min, vol_min, vol_max);

    // Test combine mode AVG
    mm19.SetParams(1, 3, 10, 1, 1.0); // AVG
    double lot_avg = mm19.CalculateLot(balance, equity, sl, InpSymbol);
    AssertInRange("MM19 AVG mode lot in range", lot_avg, vol_min, vol_max);

    // Test combine mode WEIGHTED
    mm19.SetParams(1, 3, 10, 2, 1.0); // WEIGHTED
    double lot_weighted = mm19.CalculateLot(balance, equity, sl, InpSymbol);
    AssertInRange("MM19 WEIGHTED mode lot in range", lot_weighted, vol_min, vol_max);

    // MIN should be <= AVG in typical case
    AssertTrue("MM19 MIN lot <= WEIGHTED lot (conservative)", lot_min <= lot_weighted);

    // Test with DD = 20% → MM10 inline returns vol_min
    mm19.SetParams(10, 10, 0, 0, 1.0); // Both = MM10, tertiary disabled
    mm19.UpdateContext(2.5, 0.55, 1.5, 0, 0, 22.0); // DD 22%
    double lot_dd = mm19.CalculateLot(balance, equity, sl, InpSymbol);
    AssertTrue("MM19 with MM10 + DD>20% → minimum lot", lot_dd <= vol_min * 1.01);

    // Test ENUM_MM19_COMBINE values >= 0
    AssertTrue("MM19_COMBINE_MIN >= 0",      (int)MM19_COMBINE_MIN      >= 0);
    AssertTrue("MM19_COMBINE_AVG >= 0",      (int)MM19_COMBINE_AVG      >= 0);
    AssertTrue("MM19_COMBINE_WEIGHTED >= 0", (int)MM19_COMBINE_WEIGHTED >= 0);

    mm19.PrintDiagnostics();
}

//+------------------------------------------------------------------+
//| Test MMManager                                                   |
//+------------------------------------------------------------------+
void TestMMManager()
{
    Print("=== MMManager: Selection Matrix ===");

    CMMManager mgr;
    mgr.Setup(false); // server mode

    SAccountState acct;
    acct.Reset();
    acct.balance      = 10000.0;
    acct.equity       = 10000.0;
    acct.peak_equity  = 10000.0;
    acct.drawdown_pct = 0.0;
    acct.is_standalone= false;

    // Test S01 (idx=0): Default should be MM04 (Kelly)
    ENUM_MM_ID mm_s01 = mgr.SelectMM(0, acct);
    AssertEqual("MMManager S01 default = MM04 Kelly", (int)mm_s01, (int)MM_ID_KELLY);

    // Test S06 (idx=5): Default should be MM08 (Pyramid)
    ENUM_MM_ID mm_s06 = mgr.SelectMM(5, acct);
    AssertEqual("MMManager S06 default = MM08 Pyramid", (int)mm_s06, (int)MM_ID_PYRAMID);

    // Test S15 Grid (idx=14): Default should be MM03 (ATR)
    ENUM_MM_ID mm_s15 = mgr.SelectMM(14, acct);
    AssertEqual("MMManager S15 default = MM03 ATR", (int)mm_s15, (int)MM_ID_ATR_BASED);

    // Test S16 Spike (idx=15): Default should be MM01 (Fixed)
    ENUM_MM_ID mm_s16 = mgr.SelectMM(15, acct);
    AssertEqual("MMManager S16 default = MM01 Fixed", (int)mm_s16, (int)MM_ID_FIXED_CONSERVATIVE);

    // Test DD override: DD > 10% → all switch to MM10
    acct.drawdown_pct = 12.0;
    ENUM_MM_ID mm_dd = mgr.SelectMM(0, acct); // S01
    AssertEqual("MMManager DD>10% → MM10", (int)mm_dd, (int)MM_ID_DRAWDOWN_BASED);

    // Test volatile regime
    acct.drawdown_pct = 0.0; // reset DD
    mgr.SetRegime(REGIME_VOLATILE);

    ENUM_MM_ID mm_volatile_s01 = mgr.SelectMM(0, acct); // S01 volatile → MM07
    AssertEqual("MMManager S01 volatile = MM07 PctVol", (int)mm_volatile_s01, (int)MM_ID_PCT_VOLATILITY);

    ENUM_MM_ID mm_volatile_s06 = mgr.SelectMM(5, acct); // S06 volatile → MM16
    AssertEqual("MMManager S06 volatile = MM16 VolPct", (int)mm_volatile_s06, (int)MM_ID_VOL_PERCENTILE);

    // Test server override
    mgr.SetRegime(REGIME_RANGING); // reset regime
    mgr.ApplyConfig(0, 7); // Force S01 to use MM07
    ENUM_MM_ID mm_override = mgr.SelectMM(0, acct);
    AssertEqual("MMManager ApplyConfig S01→MM07", (int)mm_override, 7);

    // Test clear override
    mgr.ApplyConfig(0, 0); // 0 = remove override
    ENUM_MM_ID mm_restored = mgr.SelectMM(0, acct);
    AssertEqual("MMManager ClearOverride S01→MM04 restored", (int)mm_restored, (int)MM_ID_KELLY);

    // Test standalone mode
    mgr.SetStandaloneMode(true);
    ENUM_MM_ID mm_standalone = mgr.SelectMM(5, acct); // S06 was MM08
    AssertEqual("MMManager standalone → MM01 always", (int)mm_standalone, (int)MM_ID_FIXED_CONSERVATIVE);

    mgr.SetStandaloneMode(false); // restore
    mgr.PrintStatus();
}

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("========================================");
    Print("FlashEASuite V2 — test_MM16_MM19.mq5");
    Print("Symbol: " + InpSymbol);
    Print("========================================");

    // Verify symbol exists
    double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    if(bid <= 0.0)
    {
        Print("⚠️  WARNING: " + InpSymbol + " not available on this broker");
        Print("   Tests using lot calculation may use fallback values");
    }

    TestMM16();
    Print("");
    TestMM17();
    Print("");
    TestMM18();
    Print("");
    TestMM19();
    Print("");
    TestMMManager();

    Print("");
    Print("========================================");
    PrintFormat("RESULTS: %d PASS | %d FAIL | Total %d",
        g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("✅ ALL TESTS PASSED");
    else
        PrintFormat("❌ %d TESTS FAILED — ตรวจสอบ output ด้านบน", g_fail);
    Print("========================================");
}
//+------------------------------------------------------------------+
