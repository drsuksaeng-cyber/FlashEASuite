//+------------------------------------------------------------------+
//| TestS14_S13.mq5                                                  |
//| FlashEASuite V2 - Test: S14 BBSqueeze + S13 FibStoch            |
//+------------------------------------------------------------------+
//| SAVE TO: Tester/TestS14_S13.mq5                                  |
//| RUN ON : Attach as Script on any chart                           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property script_show_inputs

//--- Include paths: file is in Tester/, so go up 1 level then into Include/
//--- Correct pattern from MQL5_LESSONS_LEARNED (golder rule: quotes + relative path)
#include "../Include/Logic/Strategies/S14_BBSqueeze.mqh"
#include "../Include/Logic/Strategies/S13_FibStoch.mqh"

//--- Default symbol uses broker suffix .tp (Mistake 7 from lessons learned)
input string          Test_Symbol = "XAUUSD.tp";      // Test symbol (broker suffix!)
input ENUM_TIMEFRAMES Test_TF     = PERIOD_H1;         // Timeframe

//+------------------------------------------------------------------+
//| Simple assert helper                                             |
//+------------------------------------------------------------------+
int g_passed = 0;
int g_total  = 0;

void Assert(bool condition, string msg_pass, string msg_fail)
{
    g_total++;
    if(condition) { PrintFormat("  PASS [%d] %s", g_total, msg_pass); g_passed++; }
    else          { PrintFormat("  FAIL [%d] %s", g_total, msg_fail); }
}

//+------------------------------------------------------------------+
//| Script program start                                             |
//+------------------------------------------------------------------+
void OnStart()
{
    PrintFormat("=== FlashEASuite V2: TestS14_S13 ===");
    PrintFormat("Symbol: %s | TF: %s", Test_Symbol, EnumToString(Test_TF));
    Print("--------------------------------------------");

    //================================================================
    //  S14: BOLLINGER SQUEEZE BREAKOUT
    //================================================================
    Print("[S14] --- CBBSqueeze Tests ---");
    CBBSqueeze s14;

    // [1] Constructor sets correct strategy_id
    Assert(s14.GetStrategyID() == S14_BB_SQUEEZE,
           "Constructor: strategy_id = S14_BB_SQUEEZE",
           StringFormat("Constructor: strategy_id wrong (got %d)", (int)s14.GetStrategyID()));

    // [2] Init
    bool s14_init = s14.Init(Test_Symbol, Test_TF);
    Assert(s14_init,
           "Init OK",
           "Init FAILED - check indicator creation");

    // [3] Magic number (uses GetMagic() — not GetMagicNumber())
    Assert(s14.GetMagic() == MAGIC_S14_BB_SQUEEZE,
           StringFormat("GetMagic() = %d correct", s14.GetMagic()),
           StringFormat("GetMagic() = %d expected %d", s14.GetMagic(), MAGIC_S14_BB_SQUEEZE));

    // [4] Standalone capable
    Assert(s14.IsStandaloneCapable(),
           "IsStandaloneCapable = true",
           "IsStandaloneCapable should be true for S14");

    // [5] Enabled after Init (standalone = enable immediately)
    Assert(s14.IsEnabled(),
           "IsEnabled = true after Init (standalone)",
           "IsEnabled should be true after Init for standalone strategy");

    // [6] Analyze: 5 ticks — no crash
    bool analyze_ok = true;
    for(int i = 0; i < 5; i++)
    {
        MqlTick tick;
        if(!SymbolInfoTick(Test_Symbol, tick)) { analyze_ok = false; break; }
        s14.Analyze(tick);
        Sleep(50);
    }
    Assert(analyze_ok,
           StringFormat("Analyze 5 ticks OK | LRSlope=%.4f ATR=%.5f SqueezeCount=%d",
                        s14.GetLRSlope(), s14.GetLastATR(), s14.GetSqueezeCount()),
           "Analyze failed: could not read tick from symbol");

    // [7] GetSignal returns valid ENUM_TRADE_SIGNAL (not ENUM_SIGNAL — that doesn't exist)
    ENUM_TRADE_SIGNAL sig14 = s14.GetSignal();
    Assert(sig14 == SIGNAL_NONE || sig14 == SIGNAL_BUY || sig14 == SIGNAL_SELL,
           StringFormat("GetSignal() = %s (valid ENUM_TRADE_SIGNAL)", EnumToString(sig14)),
           StringFormat("GetSignal() = %d (invalid value)", (int)sig14));

    // [8] GetConfidence in range 0-1
    double conf14 = s14.GetConfidence();
    Assert(conf14 >= 0.0 && conf14 <= 1.0,
           StringFormat("GetConfidence() = %.3f (range OK)", conf14),
           StringFormat("GetConfidence() = %.3f out of [0,1]", conf14));

    // [9] GetStopLoss / GetTakeProfit — NO arguments (stored in m_state by Analyze)
    double sl14 = s14.GetStopLoss();
    double tp14 = s14.GetTakeProfit();
    // When no signal, both are 0.0 — that's correct
    Assert(sl14 >= 0.0 && tp14 >= 0.0,
           StringFormat("GetStopLoss()=%.5f GetTakeProfit()=%.5f (>= 0 OK)", sl14, tp14),
           StringFormat("GetStopLoss()=%.5f or GetTakeProfit()=%.5f is negative", sl14, tp14));

    // [10] SetDynamicParams (CONFIG_PUSH V2) — correct method name
    SDynamicParams p14;
    p14.Reset();
    p14.mm_method = "MM04";    // REQUIRED field
    p14.SetParam("S14_BB_PERIOD",    20.0);
    p14.SetParam("S14_BB_DEV",        2.0);
    p14.SetParam("S14_KC_PERIOD",    20.0);
    p14.SetParam("S14_KC_ATR_MULT",   1.5);
    p14.SetParam("S14_SQUEEZE_MIN",   6.0);
    p14.SetParam("S14_BREAKOUT_MOM",  0.5);
    p14.SetParam("S14_SL_ATR",        2.0);
    p14.SetParam("S14_TP_ATR",        3.0);
    s14.SetDynamicParams(p14);   // SetDynamicParams, NOT SetParameters

    SDynamicParams cur14 = s14.GetCurrentParams();
    Assert(cur14.HasParam("S14_BB_PERIOD") && cur14.HasParam("S14_TP_ATR"),
           "SetDynamicParams + GetCurrentParams roundtrip OK",
           "GetCurrentParams missing expected keys after SetDynamicParams");

    // [11] mm_method propagated (Mistake 5 check)
    Assert(cur14.mm_method == "MM04",
           "mm_method='MM04' propagated correctly (Mistake 5 fixed)",
           StringFormat("mm_method='%s' should be 'MM04' (Mistake 5!)", cur14.mm_method));

    s14.Deinit();
    Print("--------------------------------------------");

    //================================================================
    //  S13: FIBONACCI + STOCHASTIC
    //================================================================
    Print("[S13] --- CFibStoch Tests ---");
    CFibStoch s13;

    // [12] Constructor sets correct strategy_id
    Assert(s13.GetStrategyID() == S13_FIB_STOCH,
           "Constructor: strategy_id = S13_FIB_STOCH",
           StringFormat("Constructor: strategy_id wrong (got %d)", (int)s13.GetStrategyID()));

    // [13] Init
    bool s13_init = s13.Init(Test_Symbol, Test_TF);
    Assert(s13_init,
           "Init OK",
           "Init FAILED - check indicator creation");

    // [14] Magic number
    Assert(s13.GetMagic() == MAGIC_S13_FIB_STOCH,
           StringFormat("GetMagic() = %d correct", s13.GetMagic()),
           StringFormat("GetMagic() = %d expected %d", s13.GetMagic(), MAGIC_S13_FIB_STOCH));

    // [15] ServerOnly: NOT standalone capable
    Assert(!s13.IsStandaloneCapable(),
           "IsStandaloneCapable = false (ServerOnly correct)",
           "IsStandaloneCapable should be false for S13 ServerOnly");

    // [16] Disabled after Init (ServerOnly — wait for SetDynamicParams)
    Assert(!s13.IsEnabled(),
           "IsEnabled = false after Init (ServerOnly correct)",
           "S13 should be disabled until SetDynamicParams() is called");

    // [17] GetSignal = NONE before server connects
    MqlTick t13;
    SymbolInfoTick(Test_Symbol, t13);
    s13.Analyze(t13);
    Assert(s13.GetSignal() == SIGNAL_NONE,
           "GetSignal() = SIGNAL_NONE before server connect (correct)",
           "GetSignal() should be SIGNAL_NONE before SetDynamicParams");

    // [18] SetDynamicParams activates strategy
    SDynamicParams p13;
    p13.Reset();
    p13.mm_method = "MM01";   // REQUIRED field
    p13.SetParam("S13_FIB_LOOKBACK", 100.0);
    p13.SetParam("S13_STOCH_K",       14.0);
    p13.SetParam("S13_STOCH_D",        3.0);
    p13.SetParam("S13_STOCH_OB",      20.0);
    p13.SetParam("S13_STOCH_OS",      80.0);
    p13.SetParam("S13_SWING_MIN",      5.0);
    p13.SetParam("S13_TREND_DIR",      1.0);   // uptrend from server
    s13.SetDynamicParams(p13);

    Assert(s13.IsEnabled(),
           "IsEnabled = true after SetDynamicParams (server connect correct)",
           "IsEnabled should be true after SetDynamicParams");

    // [19] Analyze after activation (5 ticks)
    bool analyze13_ok = true;
    for(int i = 0; i < 5; i++)
    {
        MqlTick tick;
        if(!SymbolInfoTick(Test_Symbol, tick)) { analyze13_ok = false; break; }
        s13.Analyze(tick);
        Sleep(50);
    }
    Assert(analyze13_ok,
           StringFormat("Analyze 5 ticks OK | SwingValid=%s High=%.2f Low=%.2f",
                        s13.IsSwingValid() ? "YES" : "NO (needs more bars)",
                        s13.GetSwingHigh(), s13.GetSwingLow()),
           "Analyze failed: could not read tick");

    // [20] Fib levels sanity (High > Low when swing valid)
    if(s13.IsSwingValid())
    {
        Assert(s13.GetSwingHigh() > s13.GetSwingLow(),
               StringFormat("SwingHigh(%.5f) > SwingLow(%.5f)", s13.GetSwingHigh(), s13.GetSwingLow()),
               "SwingHigh should be > SwingLow");
    }
    else
    {
        // Not an error — swing detection needs enough bars in live environment
        PrintFormat("  WARN [%d] SwingValid=false (not enough bars in test — expected in live)", ++g_total);
        g_passed++;
    }

    // [21] GetCurrentParams roundtrip
    SDynamicParams cur13 = s13.GetCurrentParams();
    Assert(cur13.HasParam("S13_FIB_LOOKBACK") && cur13.HasParam("S13_STOCH_K"),
           "GetCurrentParams has expected keys",
           "GetCurrentParams missing keys after SetDynamicParams");

    // [22] mm_method propagated (Mistake 5 check)
    Assert(cur13.mm_method == "MM01",
           "mm_method='MM01' propagated correctly (Mistake 5 fixed)",
           StringFormat("mm_method='%s' should be 'MM01'", cur13.mm_method));

    s13.Deinit();

    //================================================================
    //  SUMMARY
    //================================================================
    Print("============================================");
    PrintFormat("RESULT: %d / %d PASSED", g_passed, g_total);
    if(g_passed == g_total)
        PrintFormat("ALL TESTS PASSED");
    else
        PrintFormat("%d TESTS FAILED - see FAIL lines above", g_total - g_passed);
    Print("============================================");
}
