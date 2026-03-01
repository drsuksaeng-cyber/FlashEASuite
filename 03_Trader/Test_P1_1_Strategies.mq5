//+------------------------------------------------------------------+
//| Test_P1_1_Strategies.mq5                                         |
//| FlashEASuite V2 — P1-1 Verification Test                        |
//| Tests: S01_StatArb + S07_MeanReversion                          |
//| Run in MetaEditor Script mode — check Journal for results        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs false

#include "../Strategies/S01_StatArb.mqh"
#include "../Strategies/S07_MeanReversion.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("╔══════════════════════════════════════════════════╗");
    Print("║     FlashEASuite V2 — P1-1 Strategy Test        ║");
    Print("╠══════════════════════════════════════════════════╣");
    
    // -------------------------------------------------------
    // TEST 1: Strategy Table Initialization
    // -------------------------------------------------------
    Print(">>> TEST 1: InitStrategyTable()");
    InitStrategyTable();
    
    SStrategyInfo info01 = g_strategy_table[S01_STAT_ARB];
    SStrategyInfo info07 = g_strategy_table[S07_MEAN_REVERSION];
    
    bool t1a = (info01.magic == MAGIC_S01_STAT_ARB && info01.standalone == true  && info01.category == CAT_HYBRID);
    bool t1b = (info07.magic == MAGIC_S07_MEAN_REV && info07.standalone == true  && info07.category == CAT_FULL_MQL5);
    
    PrintFormat("  S01: magic=%d stand=%s cat=%s → %s",
                info01.magic, info01.standalone?"YES":"NO", CategoryToString(info01.category),
                t1a ? "PASS ✓" : "FAIL ✗");
    PrintFormat("  S07: magic=%d stand=%s cat=%s → %s",
                info07.magic, info07.standalone?"YES":"NO", CategoryToString(info07.category),
                t1b ? "PASS ✓" : "FAIL ✗");

    // -------------------------------------------------------
    // TEST 2: S01 StatArb — Init
    // -------------------------------------------------------
    Print(">>> TEST 2: S01 StatArb Init");
    CStatArb s01;
    bool init01 = s01.Init(Symbol(), PERIOD_M15);
    PrintFormat("  Init(%s, M15) → %s | Magic=%d | Name=%s",
                Symbol(), init01 ? "PASS ✓" : "FAIL ✗",
                s01.GetMagic(), s01.GetName());

    // -------------------------------------------------------
    // TEST 3: S01 — Enable + GetSignal before Analyze
    // -------------------------------------------------------
    Print(">>> TEST 3: S01 default signal (before Enable)");
    ENUM_TRADE_SIGNAL sig_before = s01.GetSignal();
    double conf_before = s01.GetConfidence();
    bool t3 = (sig_before == SIGNAL_NONE && conf_before == 0.0);
    PrintFormat("  Signal=%s Conf=%.4f → %s", SignalToString(sig_before), conf_before, t3?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 4: S01 — Enable + Analyze (simulate ticks)
    // -------------------------------------------------------
    Print(">>> TEST 4: S01 Analyze() with current tick");
    s01.Enable();
    
    MqlTick current_tick;
    SymbolInfoTick(Symbol(), current_tick);
    
    // Feed enough ticks to fill the spread buffer
    for(int i = 0; i < 25; i++)
    {
        s01.Analyze(current_tick);
    }
    
    ENUM_TRADE_SIGNAL sig01 = s01.GetSignal();
    double conf01 = s01.GetConfidence();
    double z01    = s01.GetLastZScore();
    double beta01 = s01.GetBeta();
    
    bool t4 = (conf01 >= 0.0 && conf01 <= 1.0);  // Valid confidence range
    PrintFormat("  Signal=%s Conf=%.4f Z=%.4f Beta=%.4f → %s",
                SignalToString(sig01), conf01, z01, beta01, t4?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 5: S01 SetParameters (JSON hot-reload)
    // -------------------------------------------------------
    Print(">>> TEST 5: S01 SetParameters() JSON hot-reload");
    double old_beta = s01.GetBeta();
    s01.SetParameters("{\"StatArb_Beta\": 1.05, \"StatArb_EntryZ\": 1.8, \"StatArb_Period\": 20}");
    double new_beta = s01.GetBeta();
    bool t5 = (MathAbs(new_beta - 1.05) < 0.0001);
    PrintFormat("  Beta: %.4f → %.4f → %s", old_beta, new_beta, t5?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 6: S01 GetCurrentParams (for TRADE_REPORT)
    // -------------------------------------------------------
    Print(">>> TEST 6: S01 GetCurrentParams()");
    SDynamicParams p01 = s01.GetCurrentParams();
    bool t6 = (p01.HasParam("S01_BETA") && p01.HasParam("S01_PERIOD") &&
               p01.HasParam("S01_ENTRY_Z") && p01.HasParam("S01_STOP_Z"));
    PrintFormat("  HasParam Beta=%s Period=%s EntryZ=%s StopZ=%s → %s",
                p01.HasParam("S01_BETA")?"YES":"NO",
                p01.HasParam("S01_PERIOD")?"YES":"NO",
                p01.HasParam("S01_ENTRY_Z")?"YES":"NO",
                p01.HasParam("S01_STOP_Z")?"YES":"NO",
                t6?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 7: S07 MeanReversion — Init
    // -------------------------------------------------------
    Print(">>> TEST 7: S07 MeanReversion Init");
    CMeanReversion s07;
    bool init07 = s07.Init(Symbol(), PERIOD_M15);
    PrintFormat("  Init(%s, M15) → %s | Magic=%d | Name=%s",
                Symbol(), init07 ? "PASS ✓" : "FAIL ✗",
                s07.GetMagic(), s07.GetName());

    // -------------------------------------------------------
    // TEST 8: S07 — Analyze returns valid values
    // -------------------------------------------------------
    Print(">>> TEST 8: S07 Analyze() with current tick");
    s07.Enable();
    
    // Give indicators time to compute (feed 30 ticks)
    for(int i = 0; i < 30; i++)
        s07.Analyze(current_tick);
    
    ENUM_TRADE_SIGNAL sig07 = s07.GetSignal();
    double conf07 = s07.GetConfidence();
    double sl07   = s07.GetStopLoss();
    double tp07   = s07.GetTakeProfit();
    
    bool t8a = (conf07 >= 0.0 && conf07 <= 1.0);
    bool t8b = (sl07 == 0.0 || sl07 > 0.0);   // SL = 0 or positive price
    bool t8c = (tp07 == 0.0 || tp07 > 0.0);
    bool t8  = t8a && t8b && t8c;
    
    PrintFormat("  Signal=%s Conf=%.4f SL=%.5f TP=%.5f RSI=%.2f ATR=%.5f VolOK=%s → %s",
                SignalToString(sig07), conf07, sl07, tp07,
                s07.GetLastRSI(), s07.GetLastATR(),
                s07.GetVolOK()?"YES":"NO",
                t8?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 9: S07 SetDynamicParams (CONFIG_PUSH V2 style)
    // -------------------------------------------------------
    Print(">>> TEST 9: S07 SetDynamicParams()");
    SDynamicParams dp07;
    dp07.Reset();
    dp07.mm_method = "MM07";
    dp07.SetParam("S07_RSI_BUY",    28.0);
    dp07.SetParam("S07_RSI_SELL",   72.0);
    dp07.SetParam("S07_VOL_FILTER", 1.5);
    s07.SetDynamicParams(dp07);
    
    SDynamicParams out07 = s07.GetCurrentParams();
    bool t9a = (MathAbs(out07.GetParam("S07_RSI_BUY",  99) - 28.0) < 0.01);
    bool t9b = (MathAbs(out07.GetParam("S07_RSI_SELL", 99) - 72.0) < 0.01);
    bool t9c = (out07.mm_method == "MM07");
    bool t9  = t9a && t9b && t9c;
    PrintFormat("  RSI_BUY=%.1f RSI_SELL=%.1f MM=%s → %s",
                out07.GetParam("S07_RSI_BUY", 99),
                out07.GetParam("S07_RSI_SELL",99),
                out07.mm_method,
                t9?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // TEST 10: IsStandaloneCapable
    // -------------------------------------------------------
    Print(">>> TEST 10: IsStandaloneCapable()");
    bool t10a = s01.IsStandaloneCapable();
    bool t10b = s07.IsStandaloneCapable();
    PrintFormat("  S01 standalone=%s  S07 standalone=%s → %s",
                t10a?"YES":"NO", t10b?"YES":"NO",
                (t10a && t10b)?"PASS ✓":"FAIL ✗");

    // -------------------------------------------------------
    // SUMMARY
    // -------------------------------------------------------
    bool all_pass = t1a && t1b && t3 && t4 && t5 && t6 && t8 && t9 && t10a && t10b;
    
    Print("╠══════════════════════════════════════════════════╣");
    PrintFormat("║  RESULT: %s  ║", all_pass ? "ALL TESTS PASSED ✓✓✓" : "SOME TESTS FAILED ✗✗✗");
    Print("╚══════════════════════════════════════════════════╝");
    
    // Diagnostics
    Print("--- S01 Diagnostics ---");
    s01.PrintDiagnostics();
    Print("--- S07 Diagnostics ---");
    s07.PrintDiagnostics();
    Print("--- S01 Status ---");
    s01.PrintStatus();
    Print("--- S07 Status ---");
    s07.PrintStatus();
    
    // Cleanup
    s01.Deinit();
    s07.Deinit();
}
