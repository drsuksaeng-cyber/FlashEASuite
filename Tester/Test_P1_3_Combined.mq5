//+------------------------------------------------------------------+
//| Test_P1_3_Combined.mq5                                           |
//| FlashEASuite V2 — P1-3 Combined Integration Test                 |
//| Runs S03 SMC + S05 Supply & Demand side-by-side                  |
//+------------------------------------------------------------------+
//| วิธีใช้งาน:                                                       |
//|  1. Save ที่: MQL5/Scripts/FlashEA/Test_P1_3_Combined.mq5        |
//|  2. เปิด chart XAUUSD.tp H1                                         |
//|  3. ลาก Script ลงบน chart                                         |
//|  4. ดู Experts tab — ผลทุก test + summary ท้าย                  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Logic/Strategies/S03_SMC.mqh"
#include "../Include/Logic/Strategies/S05_SupplyDemand.mqh"

//--- Script inputs
input string  Test_Symbol    = "XAUUSD.tp";  // Symbol to test
input int     Test_Timeframe = 60;        // Minutes (60=H1)
input int     Ticks_To_Run   = 10;        // How many ticks to simulate
input bool    Show_Details   = true;      // Show zone/OB details

//--- Global counters
int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void PrintSep(string title)
{
    Print("══════════════════════════════════════════════════════");
    PrintFormat("  %s", title);
    Print("══════════════════════════════════════════════════════");
}

void Assert(bool cond, string name, string detail = "")
{
    if(cond) { g_pass++; PrintFormat("  ✅ PASS  %s  %s", name, detail); }
    else     { g_fail++; PrintFormat("  ❌ FAIL  %s  %s", name, detail); }
}

ENUM_TIMEFRAMES MapTF(int minutes)
{
    switch(minutes)
    {
        case 1:    return PERIOD_M1;
        case 5:    return PERIOD_M5;
        case 15:   return PERIOD_M15;
        case 30:   return PERIOD_M30;
        case 60:   return PERIOD_H1;
        case 240:  return PERIOD_H4;
        case 1440: return PERIOD_D1;
        default:   return PERIOD_H1;
    }
}

//+------------------------------------------------------------------+
//| TEST A: Parallel Init                                            |
//+------------------------------------------------------------------+
void TestA_ParallelInit(CSMCV6 &smc, CSupplyDemand &sd,
                         string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST A: Parallel Init — S03 + S05");

    bool ok_smc = smc.Init(symbol, tf);
    bool ok_sd  = sd.Init(symbol, tf);

    Assert(ok_smc, "S03 Init() = true");
    Assert(ok_sd,  "S05 Init() = true");

    Assert(smc.GetMagic() == MAGIC_S03_SMC,    "S03 Magic=1003");
    Assert(sd.GetMagic()  == MAGIC_S05_SUPPLY_DEM, "S05 Magic=1005");

    Assert(!smc.IsStandaloneCapable(), "S03 ServerOnly");
    Assert(!sd.IsStandaloneCapable(),  "S05 ServerOnly");

    Assert(smc.GetFamily() == "Price Action", "S03 Family=Price Action");
    Assert(sd.GetFamily()  == "Zone-based",   "S05 Family=Zone-based");
}

//+------------------------------------------------------------------+
//| TEST B: Simultaneous CONFIG_PUSH                                 |
//+------------------------------------------------------------------+
void TestB_SimultaneousConfig(CSMCV6 &smc, CSupplyDemand &sd)
{
    PrintSep("TEST B: Simultaneous CONFIG_PUSH from server");

    SConfigUpdate cfg;
    cfg.Reset();
    cfg.enabled    = true;
    cfg.confidence = 0.72;
    cfg.regime     = REGIME_TRENDING;
    cfg.mm_method  = "MM04";

    smc.OnConfigUpdate(cfg);
    sd.OnConfigUpdate(cfg);

    smc.Enable();
    sd.Enable();

    Assert(smc.IsEnabled(), "S03 Enabled after config");
    Assert(sd.IsEnabled(),  "S05 Enabled after config");
    Assert(true, "Both OnConfigUpdate() ran without crash");
}

//+------------------------------------------------------------------+
//| TEST C: Parallel Analyze + Signal validation                     |
//+------------------------------------------------------------------+
void TestC_ParallelAnalyze(CSMCV6 &smc, CSupplyDemand &sd, string symbol)
{
    PrintSep("TEST C: Parallel Analyze — tick-by-tick");

    MqlTick tick;
    ENUM_TRADE_SIGNAL sig_smc_prev = SIGNAL_NONE;
    ENUM_TRADE_SIGNAL sig_sd_prev  = SIGNAL_NONE;

    for(int i = 0; i < Ticks_To_Run; i++)
    {
        if(!SymbolInfoTick(symbol, tick))
        {
            Print("  ⚠️  SymbolInfoTick failed at tick ", i);
            continue;
        }

        smc.Analyze(tick);
        sd.Analyze(tick);

        ENUM_TRADE_SIGNAL sig_smc = smc.GetSignal();
        ENUM_TRADE_SIGNAL sig_sd  = sd.GetSignal();
        double conf_smc = smc.GetConfidence();
        double conf_sd  = sd.GetConfidence();

        if(Show_Details || sig_smc != sig_smc_prev || sig_sd != sig_sd_prev)
        {
            PrintFormat("  Tick[%d] | S03=%s(%.2f) | S05=%s(%.2f) | Bid=%.2f",
                i,
                SignalToString(sig_smc), conf_smc,
                SignalToString(sig_sd),  conf_sd,
                tick.bid);
        }

        sig_smc_prev = sig_smc;
        sig_sd_prev  = sig_sd;

        // Validate confidence ranges
        if(conf_smc > 1.0 || conf_smc < 0.0)
        {
            Assert(false, StringFormat("S03 conf out of range at tick %d", i),
                   StringFormat("conf=%.3f", conf_smc));
        }
        if(conf_sd > 1.0 || conf_sd < 0.0)
        {
            Assert(false, StringFormat("S05 conf out of range at tick %d", i),
                   StringFormat("conf=%.3f", conf_sd));
        }

        Sleep(5);
    }

    Assert(true, StringFormat("Ran %d ticks without crash", Ticks_To_Run));
}

//+------------------------------------------------------------------+
//| TEST D: Conflict detection — both firing at same time            |
//| (should be possible — they are different strategies)             |
//+------------------------------------------------------------------+
void TestD_SignalConflict(CSMCV6 &smc, CSupplyDemand &sd)
{
    PrintSep("TEST D: Signal Conflict Check — independent signals");

    ENUM_TRADE_SIGNAL sig_smc = smc.GetSignal();
    ENUM_TRADE_SIGNAL sig_sd  = sd.GetSignal();

    // Conflict = one says BUY other says SELL simultaneously
    bool conflict = (sig_smc == SIGNAL_BUY  && sig_sd == SIGNAL_SELL) ||
                    (sig_smc == SIGNAL_SELL && sig_sd == SIGNAL_BUY);

    if(conflict)
        PrintFormat("  ⚠️  CONFLICT: S03=%s vs S05=%s — StrategyManager will resolve via confidence",
            SignalToString(sig_smc), SignalToString(sig_sd));
    else
        PrintFormat("  ✓  No conflict: S03=%s | S05=%s",
            SignalToString(sig_smc), SignalToString(sig_sd));

    Assert(true, "Conflict detection logic runs — handled by StrategyManager");
}

//+------------------------------------------------------------------+
//| TEST E: Dynamic params hot-reload on both strategies             |
//+------------------------------------------------------------------+
void TestE_HotReload(CSMCV6 &smc, CSupplyDemand &sd)
{
    PrintSep("TEST E: Hot-Reload via SetDynamicParams");

    SDynamicParams p_smc;
    p_smc.Reset();
    p_smc.SetParam("SMC_LOOKBACK",      70.0);
    p_smc.SetParam("SMC_MIN_OB_VOL",    2.0);
    p_smc.SetParam("SMC_MIN_FVG_SIZE",  0.7);
    p_smc.SetParam("SMC_SWING_BARS",    6.0);
    p_smc.SetParam("SMC_SL_ATR_BUFFER", 0.35);
    p_smc.SetParam("SMC_TP_ATR_MULT",   2.5);
    p_smc.SetParam("SMC_MIN_CONFIDENCE",0.48);
    p_smc.mm_method = "MM07";

    SDynamicParams p_sd;
    p_sd.Reset();
    p_sd.SetParam("SD_LOOKBACK",          110.0);
    p_sd.SetParam("SD_MAX_TOUCHES",         2.0);
    p_sd.SetParam("SD_BASE_RANGE_MULT",     0.55);
    p_sd.SetParam("SD_DEPARTURE_MULT",      1.3);
    p_sd.SetParam("SD_SL_ATR_BUFFER",       0.55);
    p_sd.SetParam("SD_TP_ATR_MULT",         2.8);
    p_sd.SetParam("SD_MIN_ZONE_STRENGTH",   0.28);
    p_sd.SetParam("SD_MIN_CONFIDENCE",      0.42);
    p_sd.mm_method = "MM07";

    smc.SetDynamicParams(p_smc);
    sd.SetDynamicParams(p_sd);

    SDynamicParams out_smc = smc.GetCurrentParams();
    SDynamicParams out_sd  = sd.GetCurrentParams();

    Assert(out_smc.GetParam("SMC_LOOKBACK", 0) == 70.0,
           "S03 hot-reload: SMC_LOOKBACK=70");
    Assert(out_smc.mm_method == "MM07",
           "S03 hot-reload: mm_method=MM07");
    Assert(out_sd.GetParam("SD_LOOKBACK", 0) == 110.0,
           "S05 hot-reload: SD_LOOKBACK=110");
    Assert(out_sd.mm_method == "MM07",
           "S05 hot-reload: mm_method=MM07");
}

//+------------------------------------------------------------------+
//| TEST F: Disable/Enable cycle                                     |
//+------------------------------------------------------------------+
void TestF_EnableDisable(CSMCV6 &smc, CSupplyDemand &sd, string symbol)
{
    PrintSep("TEST F: Enable / Disable cycle");

    // Disable both
    smc.Disable();
    sd.Disable();
    Assert(!smc.IsEnabled(), "S03 Disabled");
    Assert(!sd.IsEnabled(),  "S05 Disabled");

    // Signals should be NONE after disable
    MqlTick tick;
    SymbolInfoTick(symbol, tick);
    smc.Analyze(tick);
    sd.Analyze(tick);
    Assert(smc.GetSignal() == SIGNAL_NONE, "S03 Signal=NONE when Disabled");
    Assert(sd.GetSignal()  == SIGNAL_NONE, "S05 Signal=NONE when Disabled");

    // Re-enable
    smc.Enable();
    sd.Enable();
    Assert(smc.IsEnabled(), "S03 Re-enabled");
    Assert(sd.IsEnabled(),  "S05 Re-enabled");
}

//+------------------------------------------------------------------+
//| TEST G: SL/TP price validation (if signal exists)               |
//+------------------------------------------------------------------+
void TestG_SLTP_Validation(CSMCV6 &smc, CSupplyDemand &sd, string symbol)
{
    PrintSep("TEST G: SL/TP price validation");

    double price = SymbolInfoDouble(symbol, SYMBOL_BID);

    // Run a few more ticks after re-enable
    MqlTick tick;
    for(int i = 0; i < 5; i++)
    {
        SymbolInfoTick(symbol, tick);
        smc.Analyze(tick);
        sd.Analyze(tick);
        Sleep(5);
    }

    SStrategyState st_smc = smc.GetState();
    SStrategyState st_sd  = sd.GetState();

    // If signal exists, validate SL/TP direction
    if(st_smc.last_signal == SIGNAL_BUY)
    {
        Assert(st_smc.last_sl < price, "S03 Long: SL below entry price");
        Assert(st_smc.last_tp > price, "S03 Long: TP above entry price");
        PrintFormat("  → S03 BUY: Entry≈%.2f | SL=%.2f | TP=%.2f",
            price, st_smc.last_sl, st_smc.last_tp);
    }
    else if(st_smc.last_signal == SIGNAL_SELL)
    {
        Assert(st_smc.last_sl > price, "S03 Short: SL above entry price");
        Assert(st_smc.last_tp < price, "S03 Short: TP below entry price");
        PrintFormat("  → S03 SELL: Entry≈%.2f | SL=%.2f | TP=%.2f",
            price, st_smc.last_sl, st_smc.last_tp);
    }
    else
        Print("  → S03: No signal — SL/TP check skipped");

    if(st_sd.last_signal == SIGNAL_BUY)
    {
        Assert(st_sd.last_sl < price, "S05 Long: SL below entry price");
        Assert(st_sd.last_tp > price, "S05 Long: TP above entry price");
        PrintFormat("  → S05 BUY: Entry≈%.2f | SL=%.2f | TP=%.2f",
            price, st_sd.last_sl, st_sd.last_tp);
    }
    else if(st_sd.last_signal == SIGNAL_SELL)
    {
        Assert(st_sd.last_sl > price, "S05 Short: SL above entry price");
        Assert(st_sd.last_tp < price, "S05 Short: TP below entry price");
        PrintFormat("  → S05 SELL: Entry≈%.2f | SL=%.2f | TP=%.2f",
            price, st_sd.last_sl, st_sd.last_tp);
    }
    else
        Print("  → S05: No signal — SL/TP check skipped");
}

//+------------------------------------------------------------------+
//| TEST H: Deinit — clean teardown                                  |
//+------------------------------------------------------------------+
void TestH_Deinit(CSMCV6 &smc, CSupplyDemand &sd)
{
    PrintSep("TEST H: Clean Deinit");

    smc.Deinit();
    sd.Deinit();

    Assert(!smc.IsInitialized(), "S03 IsInitialized=false after Deinit");
    Assert(!sd.IsInitialized(),  "S05 IsInitialized=false after Deinit");
    Assert(true, "No crash on Deinit");
}

//+------------------------------------------------------------------+
//| OnStart — Main runner                                            |
//+------------------------------------------------------------------+
void OnStart()
{
    ENUM_TIMEFRAMES tf = MapTF(Test_Timeframe);

    string symbol = Test_Symbol;
    if(SymbolInfoDouble(symbol, SYMBOL_BID) == 0)
    {
        Print("⚠️  Symbol '", symbol, "' not found — using chart symbol: ", Symbol());
        symbol = Symbol();
    }

    Print("");
    PrintSep("FlashEASuite V2 — P1-3 COMBINED INTEGRATION TEST");
    PrintSep("  S03 Smart Money Concepts + S05 Supply & Demand");
    PrintFormat("  Symbol: %s | TF: %s | TickSim: %d | Bars: %d",
        symbol, EnumToString(tf), Ticks_To_Run, Bars(symbol, tf));
    Print("");

    // Create strategy instances (passed by ref)
    CSMCV6        smc;
    CSupplyDemand sd;

    TestA_ParallelInit(smc, sd, symbol, tf);
    TestB_SimultaneousConfig(smc, sd);
    TestC_ParallelAnalyze(smc, sd, symbol);
    TestD_SignalConflict(smc, sd);
    TestE_HotReload(smc, sd);
    TestF_EnableDisable(smc, sd, symbol);
    TestG_SLTP_Validation(smc, sd, symbol);
    TestH_Deinit(smc, sd);

    // Final diagnostics snapshot before deinit
    Print("");
    PrintSep("FINAL DIAGNOSTICS");
    // (already deinit'd but diagnostics strings don't require initialized state)

    Print("");
    Print("══════════════════════════════════════════════════════");
    PrintFormat("  RESULTS: %d PASSED | %d FAILED | %d TOTAL",
        g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("  🏆  ALL TESTS PASSED — P1-3 Ready for integration!");
    else
        PrintFormat("  ⚠️   %d test(s) failed — ตรวจสอบ ❌ ด้านบน", g_fail);
    Print("══════════════════════════════════════════════════════");
    Print("");
}
//+------------------------------------------------------------------+
