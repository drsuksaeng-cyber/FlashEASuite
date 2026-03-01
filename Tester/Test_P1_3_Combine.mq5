//+------------------------------------------------------------------+
//| Test_S03_SMC.mq5                                                 |
//| FlashEASuite V2 — Unit Test for S03 Smart Money Concepts         |
//+------------------------------------------------------------------+
//| วิธีใช้งาน:                                                       |
//|  1. Save ไฟล์นี้ที่: MQL5/Scripts/FlashEA/Test_S03_SMC.mq5       |
//|  2. เปิด MetaTrader 5 → ไปที่ chart XAUUSD H1                    |
//|  3. ลาก Script นี้ลงบน chart                                      |
//|  4. ดู Output ใน Experts tab (View → Experts)                    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Logic/Strategies/S03_SMC.mqh"

//--- Script inputs
input string  Test_Symbol    = "XAUUSD";   // Symbol to test on
input int     Test_Timeframe = 60;         // Timeframe in minutes (60 = H1)
input bool    Verbose        = true;       // Print all detector results

//+------------------------------------------------------------------+
//| Helper: Print section separator                                  |
//+------------------------------------------------------------------+
void PrintSep(string title)
{
    Print("══════════════════════════════════════════════════════");
    PrintFormat("  %s", title);
    Print("══════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Helper: PASS/FAIL printer                                        |
//+------------------------------------------------------------------+
void Assert(bool condition, string test_name, string detail = "")
{
    if(condition)
        PrintFormat("  ✅ PASS  %s  %s", test_name, detail);
    else
        PrintFormat("  ❌ FAIL  %s  %s", test_name, detail);
}

//+------------------------------------------------------------------+
//| TEST 1: OrderBlockDetector — scan and find OBs                   |
//+------------------------------------------------------------------+
void Test_OrderBlockDetector(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 1: OrderBlockDetector");

    COrderBlockDetector ob_det(symbol, tf, 50, 1.5, 0.5);
    ob_det.Scan();

    int count = ob_det.Count();
    PrintFormat("  → Found %d Order Block(s) on %s %s", count, symbol, EnumToString(tf));

    Assert(count >= 0, "OB Scan runs without crash",
           StringFormat("count=%d", count));

    if(Verbose)
    {
        for(int i = 0; i < count; i++)
        {
            SOrderBlock ob = ob_det.GetBlock(i);
            PrintFormat("     OB[%d] | %s | High:%.2f Low:%.2f | Strength:%.2f | Time:%s",
                i,
                ob.is_bullish ? "BULLISH" : "BEARISH",
                ob.high, ob.low,
                ob.strength,
                TimeToString(ob.time, TIME_DATE | TIME_MINUTES));
        }
    }

    // Test GetNearestActive
    double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
    SOrderBlock nearest_bull, nearest_bear;
    bool found_bull = ob_det.GetNearestActive(true,  current_price, nearest_bull);
    bool found_bear = ob_det.GetNearestActive(false, current_price, nearest_bear);

    PrintFormat("  → Nearest Bullish OB: %s | High:%.2f Low:%.2f",
        found_bull ? "FOUND" : "NONE",
        found_bull ? nearest_bull.high : 0,
        found_bull ? nearest_bull.low  : 0);

    PrintFormat("  → Nearest Bearish OB: %s | High:%.2f Low:%.2f",
        found_bear ? "FOUND" : "NONE",
        found_bear ? nearest_bear.high : 0,
        found_bear ? nearest_bear.low  : 0);

    Assert(true, "GetNearestActive did not crash");
}

//+------------------------------------------------------------------+
//| TEST 2: FVGDetector — scan and find FVGs                         |
//+------------------------------------------------------------------+
void Test_FVGDetector(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 2: FVGDetector (Fair Value Gaps)");

    CFVGDetector fvg_det(symbol, tf, 50, 0.5);
    fvg_det.Scan();

    int count = fvg_det.Count();
    PrintFormat("  → Found %d FVG(s) on %s %s", count, symbol, EnumToString(tf));

    Assert(count >= 0, "FVG Scan runs without crash",
           StringFormat("count=%d", count));

    if(Verbose)
    {
        for(int i = 0; i < count; i++)
        {
            SFVG fvg = fvg_det.GetFVG(i);
            PrintFormat("     FVG[%d] | %s | Top:%.2f Bot:%.2f | SizeRatio:%.2f | Time:%s",
                i,
                fvg.is_bullish ? "BULLISH" : "BEARISH",
                fvg.top, fvg.bottom,
                fvg.size_ratio,
                TimeToString(fvg.time, TIME_DATE | TIME_MINUTES));
        }
    }

    // Test MarkFilled (should not crash)
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    fvg_det.MarkFilled(price);
    Assert(true, "MarkFilled does not crash");

    // Test GetNearestActive
    SFVG nearest_bull, nearest_bear;
    bool fb = fvg_det.GetNearestActive(true,  price, nearest_bull);
    bool fs = fvg_det.GetNearestActive(false, price, nearest_bear);
    PrintFormat("  → Nearest Bullish FVG: %s  | Nearest Bearish FVG: %s",
        fb ? StringFormat("Top:%.2f Bot:%.2f", nearest_bull.top, nearest_bull.bottom) : "NONE",
        fs ? StringFormat("Top:%.2f Bot:%.2f", nearest_bear.top, nearest_bear.bottom) : "NONE");

    Assert(true, "GetNearestActive FVG does not crash");
}

//+------------------------------------------------------------------+
//| TEST 3: BOSDetector — detect Break of Structure                  |
//+------------------------------------------------------------------+
void Test_BOSDetector(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 3: BOSDetector (Break of Structure)");

    CBOSDetector bos_det(symbol, tf, 5);
    bos_det.Detect(50);

    bool has_bos = bos_det.HasBOS();
    SBOS last    = bos_det.GetLastBOS();

    PrintFormat("  → BOS Detected: %s", has_bos ? "YES" : "NO");
    if(has_bos)
    {
        PrintFormat("     Direction: %s | BreakLevel: %.2f | Time: %s",
            last.direction == BOS_BULLISH ? "BULLISH" : "BEARISH",
            last.break_level,
            TimeToString(last.time, TIME_DATE | TIME_MINUTES));
    }

    PrintFormat("  → Last Swing High: %.2f | Last Swing Low: %.2f",
        bos_det.GetSwingHigh(), bos_det.GetSwingLow());

    Assert(true, "BOSDetector Detect() runs without crash");
    Assert(bos_det.GetSwingHigh() >= 0, "SwingHigh is non-negative");
    Assert(bos_det.GetSwingLow() >= 0,  "SwingLow is non-negative");
}

//+------------------------------------------------------------------+
//| TEST 4: CSMCV6 — Full strategy Init + Analyze cycle              |
//+------------------------------------------------------------------+
void Test_CSMCV6_Init(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 4: CSMCV6 Strategy — Init & Metadata");

    CSMCV6 smc;

    Assert(!smc.IsInitialized(),  "Before Init: IsInitialized=false");
    Assert(!smc.IsEnabled(),      "Before Init: IsEnabled=false");

    bool ok = smc.Init(symbol, tf);
    Assert(ok,                    "Init() returns true");
    Assert(smc.IsInitialized(),   "After Init: IsInitialized=true");
    Assert(smc.GetMagic() == MAGIC_S03_SMC, StringFormat("Magic = %d", MAGIC_S03_SMC));
    Assert(smc.GetName() == "Smart Money Concepts", "GetName correct");
    Assert(!smc.IsStandaloneCapable(), "IsStandaloneCapable = false (ServerOnly)");

    PrintFormat("  → Symbol: %s | TF: %s | Family: %s",
        smc.GetSymbol(), EnumToString(smc.GetTimeframe()), smc.GetFamily());

    smc.Deinit();
    Assert(!smc.IsInitialized(), "After Deinit: IsInitialized=false");
}

//+------------------------------------------------------------------+
//| TEST 5: CSMCV6 — Analyze without server config (should skip)     |
//+------------------------------------------------------------------+
void Test_CSMCV6_NoServer(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 5: CSMCV6 — Analyze with NO server config (ServerOnly check)");

    CSMCV6 smc;
    smc.Init(symbol, tf);
    smc.Enable();

    // Confidence = 0 (no CONFIG_PUSH) → strategy should NOT generate signals
    MqlTick tick;
    SymbolInfoTick(symbol, tick);
    smc.Analyze(tick);

    ENUM_TRADE_SIGNAL sig = smc.GetSignal();
    Assert(sig == SIGNAL_NONE,
           "With confidence=0, signal must be SIGNAL_NONE",
           StringFormat("Got: %s", SignalToString(sig)));

    smc.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 6: CSMCV6 — Analyze WITH server config (confidence = 0.7)  |
//+------------------------------------------------------------------+
void Test_CSMCV6_WithServer(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 6: CSMCV6 — Analyze WITH server config (confidence=0.70)");

    CSMCV6 smc;
    smc.Init(symbol, tf);
    smc.Enable();

    // Simulate CONFIG_PUSH from server
    SConfigUpdate cfg;
    cfg.Reset();
    cfg.enabled    = true;
    cfg.confidence = 0.70;
    cfg.timeframe  = tf;
    cfg.regime     = REGIME_TRENDING;
    cfg.mm_method  = "MM04";
    smc.OnConfigUpdate(cfg);

    // Run 3 ticks
    MqlTick tick;
    for(int i = 0; i < 3; i++)
    {
        SymbolInfoTick(symbol, tick);
        smc.Analyze(tick);
        Sleep(10);
    }

    ENUM_TRADE_SIGNAL sig  = smc.GetSignal();
    double            conf = smc.GetConfidence();
    PrintFormat("  → Signal: %s | Confidence: %.3f", SignalToString(sig), conf);

    Assert(conf >= 0.0 && conf <= 1.0, "Confidence in range [0,1]",
           StringFormat("conf=%.3f", conf));
    Assert(sig == SIGNAL_BUY || sig == SIGNAL_SELL || sig == SIGNAL_NONE,
           "Signal is valid enum value");

    Print(smc.GetDiagnostics());
    smc.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 7: SetDynamicParams — hot-reload parameters                 |
//+------------------------------------------------------------------+
void Test_CSMCV6_DynamicParams(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 7: CSMCV6 — SetDynamicParams (CONFIG_PUSH V2)");

    CSMCV6 smc;
    smc.Init(symbol, tf);
    smc.Enable();

    // Inject params as server would
    SDynamicParams p;
    p.Reset();
    p.SetParam("SMC_LOOKBACK",      60.0);
    p.SetParam("SMC_MIN_OB_VOL",    2.0);
    p.SetParam("SMC_MIN_FVG_SIZE",  0.8);
    p.SetParam("SMC_SWING_BARS",    7.0);
    p.SetParam("SMC_SL_ATR_BUFFER", 0.4);
    p.SetParam("SMC_TP_ATR_MULT",   3.0);
    p.SetParam("SMC_MIN_CONFIDENCE",0.50);
    p.mm_method = "MM04";

    smc.SetDynamicParams(p);
    Assert(true, "SetDynamicParams does not crash");

    // Verify GetCurrentParams echoes back
    SDynamicParams out = smc.GetCurrentParams();
    Assert(out.GetParam("SMC_LOOKBACK", 0) == 60.0,
           "GetCurrentParams: SMC_LOOKBACK = 60",
           StringFormat("Got: %.0f", out.GetParam("SMC_LOOKBACK", 0)));
    Assert(out.GetParam("SMC_TP_ATR_MULT", 0) == 3.0,
           "GetCurrentParams: SMC_TP_ATR_MULT = 3.0",
           StringFormat("Got: %.1f", out.GetParam("SMC_TP_ATR_MULT", 0)));
    Assert(out.mm_method == "MM04",
           "GetCurrentParams: mm_method = MM04",
           StringFormat("Got: %s", out.mm_method));

    smc.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 8: GetCurrentParams — export param table                    |
//+------------------------------------------------------------------+
void Test_CSMCV6_ExportParams(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 8: CSMCV6 — GetCurrentParams export");

    CSMCV6 smc;
    smc.Init(symbol, tf);

    SDynamicParams p = smc.GetCurrentParams();
    PrintFormat("  → Param count: %d", p.strategy_param_count);
    Assert(p.strategy_param_count == 7, "Exports exactly 7 params",
           StringFormat("Got: %d", p.strategy_param_count));

    if(Verbose)
    {
        for(int i = 0; i < p.strategy_param_count; i++)
            PrintFormat("     Param[%d]: %s = %.4f",
                i, p.strategy_params[i].name, p.strategy_params[i].value);
    }

    smc.Deinit();
}

//+------------------------------------------------------------------+
//| OnStart — Main test runner                                       |
//+------------------------------------------------------------------+
void OnStart()
{
    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)(Test_Timeframe * 60 / 60);
    // Map input minutes to proper enum
    switch(Test_Timeframe)
    {
        case 1:   tf = PERIOD_M1;  break;
        case 5:   tf = PERIOD_M5;  break;
        case 15:  tf = PERIOD_M15; break;
        case 30:  tf = PERIOD_M30; break;
        case 60:  tf = PERIOD_H1;  break;
        case 240: tf = PERIOD_H4;  break;
        case 1440:tf = PERIOD_D1;  break;
        default:  tf = PERIOD_H1;
    }

    string symbol = Test_Symbol;
    if(SymbolInfoDouble(symbol, SYMBOL_BID) == 0)
    {
        Print("⚠️  Symbol '", symbol, "' not found — check broker suffix");
        Print("   Trying chart symbol: ", Symbol());
        symbol = Symbol();
    }

    Print("");
    PrintSep("FlashEASuite V2 — S03 SMC UNIT TESTS");
    PrintFormat("  Symbol: %s | Timeframe: %s | Bars: %d",
        symbol, EnumToString(tf), Bars(symbol, tf));
    Print("");

    int pass_count = 0;
    int fail_count = 0;  // tracked via Assert output visually

    Test_OrderBlockDetector(symbol, tf);
    Test_FVGDetector(symbol, tf);
    Test_BOSDetector(symbol, tf);
    Test_CSMCV6_Init(symbol, tf);
    Test_CSMCV6_NoServer(symbol, tf);
    Test_CSMCV6_WithServer(symbol, tf);
    Test_CSMCV6_DynamicParams(symbol, tf);
    Test_CSMCV6_ExportParams(symbol, tf);

    Print("");
    PrintSep("S03 SMC TEST COMPLETE — ตรวจสอบ ✅/❌ ด้านบน");
    Print("");
}
//+------------------------------------------------------------------+
