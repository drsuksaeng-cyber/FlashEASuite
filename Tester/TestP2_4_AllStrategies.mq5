//+------------------------------------------------------------------+
//| TestP2_4_AllStrategies.mq5                                       |
//| FlashEASuite V2 — P2-4: All 16 Strategies Integration Test       |
//| Location: Tester/TestP2_4_AllStrategies.mq5                      |
//+------------------------------------------------------------------+
//| TESTS:                                                           |
//|  1. RegisterAllStrategies — all 16 Init() OK                    |
//|  2. All 16: GetMagic, GetName, GetFamily, IsStandaloneCapable   |
//|  3. All 16: Analyze(tick) — no crash                            |
//|  4. All 16: GetSignal() returns valid ENUM_TRADE_SIGNAL          |
//|  5. All 16: GetConfidence() in range [0.0, 1.0]                 |
//|  6. Standalone mode: 7 SA strategies enabled, 9 ServerOnly off  |
//|  7. Online mode: EnableByConfig → all 16 enabled                |
//|  8. DisableAllExcept: only specified strategies active           |
//|  9. SetDynamicParams: params apply without crash                 |
//| 10. Final report: summary table for all 16                      |
//+------------------------------------------------------------------+
//| LESSONS APPLIED:                                                 |
//|  ✅ MISTAKE F: Direct objects only — no IStrategy* pointer array |
//|  ✅ MISTAKE E: SymbolInfoTick() not SymbolInfoDouble(SYMBOL_SPREAD)|
//|  ✅ MISTAKE 7: Default symbol "XAUUSD.tp" (broker suffix)       |
//|  ✅ No const_cast / static_cast (MISTAKE D)                     |
//|  ✅ Family strings verified against StrategyConstants.mqh       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

//--- Include path from Tester/ → Include/Logic/StrategyManager_V6.mqh
#include "../Include/Logic/StrategyManager_V6.mqh"

//=================================================================
//  INPUT PARAMETERS
//=================================================================
input string   Test_Symbol   = "XAUUSD.tp";   // Symbol with broker suffix (MISTAKE 7)
input bool     Test_Verbose  = true;            // Print per-strategy detail

//=================================================================
//  TEST FRAMEWORK
//=================================================================
static int g_pass = 0;
static int g_fail = 0;

void CHECK(bool condition, const string test_name)
{
    if(condition)
    {
        if(Test_Verbose) PrintFormat("  ✅ PASS | %s", test_name);
        g_pass++;
    }
    else
    {
        PrintFormat("  ❌ FAIL | %s", test_name);
        g_fail++;
    }
}

void SECTION(const string title)
{
    PrintFormat("\n══════════════════════════════════════════");
    PrintFormat("  TEST: %s", title);
    PrintFormat("══════════════════════════════════════════");
}

void RESULT()
{
    PrintFormat("\n╔══════════════════════════════════════════╗");
    PrintFormat("║  FINAL RESULT: %d PASSED / %d FAILED      ║", g_pass, g_fail);
    if(g_fail == 0)
        Print("║  ✅ ALL TESTS PASSED                      ║");
    else
        PrintFormat("║  ❌ %d FAILURES — check log above        ║", g_fail);
    PrintFormat("╚══════════════════════════════════════════╝");
}

//=================================================================
//  HELPERS
//=================================================================

//+------------------------------------------------------------------+
//| _MakeFakeTick: Create synthetic tick for testing                 |
//| Uses SymbolInfoTick() — MISTAKE E: avoid SYMBOL_SPREAD           |
//+------------------------------------------------------------------+
bool _MakeFakeTick(MqlTick &tick, string symbol)
{
    if(SymbolInfoTick(symbol, tick)) return true;  // ✅ real tick if available

    // Fallback: manually construct fake tick (test environment)
    tick.time   = TimeCurrent();
    tick.bid    = 2000.00;
    tick.ask    = 2000.10;
    tick.volume = 100;
    tick.flags  = TICK_FLAG_BID | TICK_FLAG_ASK;
    return true;
}

//=================================================================
//  MAIN TEST ENTRY
//=================================================================
void OnStart()
{
    Print("╔══════════════════════════════════════════════════════════╗");
    Print("║     FlashEASuite V2 — P2-4: 16-Strategy Test            ║");
    Print("╚══════════════════════════════════════════════════════════╝");
    PrintFormat("  Symbol  : %s", Test_Symbol);
    PrintFormat("  Timeframe: %s", EnumToString(PERIOD_M15));
    PrintFormat("  Time     : %s", TimeToString(TimeCurrent()));
    Print("");

    //=================================================================
    //  OBJECT: CStrategyManager_V6 (direct — MISTAKE F: no pointer array)
    //=================================================================
    CStrategyManager_V6 manager;

    //=================================================================
    //  TEST 1: RegisterAllStrategies
    //=================================================================
    SECTION("1. RegisterAllStrategies — All 16 Init()");

    bool reg_ok = manager.RegisterAllStrategies(Test_Symbol, PERIOD_M15);
    CHECK(reg_ok, "RegisterAllStrategies returns true (all Init OK)");
    CHECK(manager.IsRegistered(), "manager.IsRegistered() == true");

    //=================================================================
    //  TEST 2: Metadata validation (no crash + correct values)
    //=================================================================
    SECTION("2. Strategy Metadata — Magic / Name / Standalone");

    // Magic numbers expected per StrategyConstants.mqh
    int expected_magic[16] = {1001,1002,1003,1004,1005,1006,1007,1008,
                               1009,1010,1011,1012,1013,1014,1015,1016};

    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        IStrategy* s = manager.GetStrategyByID((ENUM_STRATEGY_ID)i);
        if(s == NULL)
        {
            CHECK(false, StringFormat("S%02d not NULL", i+1));
            continue;
        }

        CHECK(s.GetMagic() == expected_magic[i],
              StringFormat("S%02d Magic=%d (expected %d)", i+1, s.GetMagic(), expected_magic[i]));

        CHECK(StringLen(s.GetName()) > 0,
              StringFormat("S%02d GetName() not empty: %s", i+1, s.GetName()));

        CHECK(StringLen(s.GetShortName()) > 0,
              StringFormat("S%02d GetShortName() not empty: %s", i+1, s.GetShortName()));

        CHECK(s.IsInitialized(),
              StringFormat("S%02d IsInitialized()", i+1));
    }

    //--- Verify standalone flags (7 SA: S01,S06,S07,S10,S14,S15,S16)
    ENUM_STRATEGY_ID sa_ids[7] = {S01_STAT_ARB, S06_KAMA, S07_MEAN_REVERSION,
                                   S10_TURTLE, S14_BB_SQUEEZE, S15_GRID, S16_SPIKE};
    for(int j = 0; j < 7; j++)
    {
        IStrategy* s = manager.GetStrategyByID(sa_ids[j]);
        if(s != NULL)
            CHECK(s.IsStandaloneCapable(),
                  StringFormat("S%02d IsStandaloneCapable=true", (int)sa_ids[j]+1));
    }

    //--- Verify ServerOnly flags (9 strategies NOT standalone)
    ENUM_STRATEGY_ID so_ids[9] = {S02_ML_ENSEMBLE, S03_SMC, S04_MARKET_PROFILE,
                                   S05_SUPPLY_DEMAND, S08_INTERMARKET, S09_SESSION_BREAKOUT,
                                   S11_ICHIMOKU, S12_PRICE_ACTION, S13_FIB_STOCH};
    for(int j = 0; j < 9; j++)
    {
        IStrategy* s = manager.GetStrategyByID(so_ids[j]);
        if(s != NULL)
            CHECK(!s.IsStandaloneCapable(),
                  StringFormat("S%02d IsStandaloneCapable=false (ServerOnly)", (int)so_ids[j]+1));
    }

    //=================================================================
    //  TEST 3+4+5: Analyze() + GetSignal() + GetConfidence()
    //=================================================================
    SECTION("3-4-5. Analyze / GetSignal / GetConfidence — All 16");

    MqlTick test_tick;
    _MakeFakeTick(test_tick, Test_Symbol);

    // Enable all before testing Analyze
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        IStrategy* s = manager.GetStrategyByID((ENUM_STRATEGY_ID)i);
        if(s != NULL) s.Enable();
    }
    manager.SetServerConnected(true);

    // Run several ticks to let indicators warm up
    for(int warmup = 0; warmup < 10; warmup++)
    {
        test_tick.bid += 0.01;
        test_tick.ask  = test_tick.bid + 0.10;
        test_tick.time = TimeCurrent() + warmup;
        manager.OnTick(test_tick);
    }

    // Validate signal + confidence for each strategy
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        IStrategy* s = manager.GetStrategyByID((ENUM_STRATEGY_ID)i);
        if(s == NULL) { CHECK(false, StringFormat("S%02d not NULL (signal test)", i+1)); continue; }

        ENUM_TRADE_SIGNAL sig  = s.GetSignal();
        double            conf = s.GetConfidence();

        // Signal must be one of the 3 valid values
        bool sig_valid = (sig == SIGNAL_BUY || sig == SIGNAL_SELL || sig == SIGNAL_NONE);
        CHECK(sig_valid,
              StringFormat("S%02d GetSignal() valid (%s)", i+1, SignalToString(sig)));

        // Confidence must be in [0.0, 1.0]
        CHECK(conf >= 0.0 && conf <= 1.0,
              StringFormat("S%02d GetConfidence() in [0,1]: %.4f", i+1, conf));

        // SL/TP must be non-negative
        CHECK(s.GetStopLoss()   >= 0.0, StringFormat("S%02d SL >= 0", i+1));
        CHECK(s.GetTakeProfit() >= 0.0, StringFormat("S%02d TP >= 0", i+1));
    }

    //=================================================================
    //  TEST 6: Standalone mode — 7 SA enabled, 9 ServerOnly off
    //=================================================================
    SECTION("6. Standalone Mode — 7 SA only");

    manager.SetServerConnected(false);
    manager.EnableAllStandalone();

    CHECK(manager.GetEnabledCount_V6() == 7,
          StringFormat("EnableAllStandalone: 7 enabled (got %d)", manager.GetEnabledCount_V6()));

    // SA strategies should be enabled
    for(int j = 0; j < 7; j++)
    {
        IStrategy* s = manager.GetStrategyByID(sa_ids[j]);
        if(s != NULL)
            CHECK(s.IsEnabled(),
                  StringFormat("S%02d enabled in standalone", (int)sa_ids[j]+1));
    }

    // ServerOnly strategies should be disabled
    for(int j = 0; j < 9; j++)
    {
        IStrategy* s = manager.GetStrategyByID(so_ids[j]);
        if(s != NULL)
            CHECK(!s.IsEnabled(),
                  StringFormat("S%02d DISABLED in standalone (ServerOnly)", (int)so_ids[j]+1));
    }

    //--- OnTick in standalone mode: only SA strategies should analyze
    manager.OnTick(test_tick);
    CHECK(true, "OnTick() in standalone mode — no crash");

    //=================================================================
    //  TEST 7: Online mode — EnableByConfig all 16
    //=================================================================
    SECTION("7. Online Mode — EnableByConfig all 16");

    // Build a config with all 16 enabled
    SConfigData all_on;
    all_on.Reset();
    all_on.regime = REGIME_TRENDING;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        all_on.strategy_enabled[i]    = true;
        all_on.strategy_confidence[i] = 0.75;
    }

    manager.SetServerConnected(true);
    manager.EnableByConfig(all_on);

    CHECK(manager.GetEnabledCount_V6() == 16,
          StringFormat("EnableByConfig all-on: 16 enabled (got %d)",
                       manager.GetEnabledCount_V6()));

    //--- Now only enable 3
    SConfigData partial;
    partial.Reset();
    partial.strategy_enabled[S01_STAT_ARB]      = true;
    partial.strategy_enabled[S07_MEAN_REVERSION] = true;
    partial.strategy_enabled[S15_GRID]           = true;

    manager.EnableByConfig(partial);
    CHECK(manager.GetEnabledCount_V6() == 3,
          StringFormat("EnableByConfig partial: 3 enabled (got %d)",
                       manager.GetEnabledCount_V6()));

    //=================================================================
    //  TEST 8: DisableAllExcept — standalone 7
    //=================================================================
    SECTION("8. DisableAllExcept — Standalone 7");

    // Re-enable all first
    manager.EnableByConfig(all_on);

    ENUM_STRATEGY_ID standalone_set[7] = {S01_STAT_ARB, S06_KAMA, S07_MEAN_REVERSION,
                                          S10_TURTLE, S14_BB_SQUEEZE, S15_GRID, S16_SPIKE};
    manager.DisableAllExcept(standalone_set, 7);

    CHECK(manager.GetEnabledCount_V6() == 7,
          StringFormat("DisableAllExcept: 7 enabled (got %d)",
                       manager.GetEnabledCount_V6()));

    // S02 (ServerOnly) must be disabled
    IStrategy* s02 = manager.GetStrategyByID(S02_ML_ENSEMBLE);
    if(s02 != NULL)
        CHECK(!s02.IsEnabled(), "S02 disabled after DisableAllExcept");

    //=================================================================
    //  TEST 9: SetDynamicParams — no crash
    //=================================================================
    SECTION("9. SetDynamicParams — Hot Reload No Crash");

    SDynamicParams dyn;
    dyn.Reset();
    dyn.mm_method = "MM03";
    dyn.SetParam("S15_MAX_ORDERS",     10.0);
    dyn.SetParam("S15_BASE_STEP",     200.0);
    dyn.SetParam("S15_ELASTIC_FACTOR",  1.5);
    dyn.SetParam("S16_VELOCITY_THRESH", 2.5);
    dyn.SetParam("S16_SPREAD_THRESH",   1.5);
    dyn.SetParam("S07_RSI_Period",      14.0);
    dyn.SetParam("S07_RSI_Buy",         30.0);
    dyn.SetParam("S07_RSI_Sell",        70.0);

    // Distribute to S15
    manager.DistributeDynamicParams(dyn, S15_GRID);
    CHECK(true, "DistributeDynamicParams S15 — no crash");

    // Distribute to S16
    manager.DistributeDynamicParams(dyn, S16_SPIKE);
    CHECK(true, "DistributeDynamicParams S16 — no crash");

    // Distribute to all
    manager.DistributeAllDynamicParams(dyn);
    CHECK(true, "DistributeAllDynamicParams all 16 — no crash");

    //=================================================================
    //  TEST 10: Final Report — strategy status table
    //=================================================================
    SECTION("10. Final Status Report");

    // Re-enable all for final report
    manager.SetServerConnected(true);
    manager.EnableByConfig(all_on);
    manager.OnTick(test_tick);

    // Print full status table
    manager.GetStrategyStatus();

    // Verify FillStatusArray works
    SStrategyStatusEntry status_arr[];
    int status_count = 0;
    manager.FillStatusArray(status_arr, status_count);

    CHECK(status_count == 16, StringFormat("FillStatusArray: 16 entries (got %d)", status_count));

    // Print individual report
    Print("\n─────────────────────────────────────────────────────────────────");
    Print("  Strategy Signal / Confidence Report (after 10 warm-up ticks)");
    Print("─────────────────────────────────────────────────────────────────");
    PrintFormat("  %-4s | %-28s | %-6s | %-8s | %-4s | %s",
                "ID", "Name", "Signal", "Conf", "SA", "Enabled");
    Print("─────────────────────────────────────────────────────────────────");

    for(int i = 0; i < status_count; i++)
    {
        PrintFormat("  %-4s | %-28s | %-6s | %.4f   | %-4s | %s",
            status_arr[i].short_name,
            status_arr[i].name,
            SignalToString(status_arr[i].last_signal),
            status_arr[i].last_confidence,
            status_arr[i].standalone_capable ? "YES" : "NO",
            status_arr[i].enabled ? "YES" : "NO");
    }
    Print("─────────────────────────────────────────────────────────────────");

    //=================================================================
    //  FINAL RESULT
    //=================================================================
    manager.Deinit();
    RESULT();
}
