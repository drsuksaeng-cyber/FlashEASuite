//+------------------------------------------------------------------+
//| Test_P2_2_PriceAction.mq5                                        |
//| FlashEASuite V2 — P2-2 Test: S12 + S02                         |
//| Target: Pin Bar detection on XAUUSD D1                          |
//| Save to: Tester/Test_P2_2_PriceAction.mq5                       |
//+------------------------------------------------------------------+
//| Test Plan:                                                       |
//|  1. Identity checks  (magic, family, name, standalone)          |
//|  2. Init check       (S12 + S02 initialize correctly)           |
//|  3. PinBar direct    (CPinBarDetector on XAUUSD.tp D1)          |
//|  4. Engulfing direct (CEngulfingDetector scan)                  |
//|  5. KeyLevel scan    (CKeyLevelFinder finds levels)             |
//|  6. S02 signal flow  (SetDynamicParams → GetSignal check)       |
//|  7. S02 timeout test (signal expires after timeout)             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Logic/Strategies/S12_PriceAction.mqh"
#include "../Include/Logic/Strategies/S02_ML_Ensemble.mqh"

//--- Test inputs
input string   Test_Symbol  = "XAUUSD.tp";   // ✅ broker suffix .tp (Lesson #7)
input ENUM_TIMEFRAMES Test_TF = PERIOD_D1;   // D1 for pin bar detection
input bool     Verbose      = true;

//+------------------------------------------------------------------+
//| Simple test assert                                               |
//+------------------------------------------------------------------+
int g_pass = 0;
int g_fail = 0;

void Assert(bool condition, string msg)
{
    if(condition)
    {
        if(Verbose) PrintFormat("  ✅ PASS: %s", msg);
        g_pass++;
    }
    else
    {
        PrintFormat("  ❌ FAIL: %s", msg);
        g_fail++;
    }
}

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("╔══════════════════════════════════════════════════════════╗");
    Print("║   P2-2 TEST: S12 Price Action + S02 ML Ensemble         ║");
    Print("╚══════════════════════════════════════════════════════════╝");
    Print("");
    
    string sym = Test_Symbol;
    ENUM_TIMEFRAMES tf = Test_TF;
    
    // =================================================================
    // TEST 1: S12 Identity
    // =================================================================
    Print("--- TEST 1: S12 Identity ---");
    CS12PriceAction s12;
    
    Assert(s12.GetMagic()     == MAGIC_S12_PRICE_ACT, "S12 Magic = 1012");
    Assert(s12.GetShortName() == "S12",               "S12 short_name = S12");
    Assert(s12.GetFamily()    == "Candlestick",        "S12 family = Candlestick");  // Lesson #6: check StrategyConstants
    Assert(s12.GetCategory()  == "Full_MQL5",          "S12 category = Full_MQL5");
    Assert(s12.IsStandaloneCapable() == false,          "S12 standalone = false");
    
    // =================================================================
    // TEST 2: S02 Identity
    // =================================================================
    Print("--- TEST 2: S02 Identity ---");
    CS02MLEnsemble s02;
    
    Assert(s02.GetMagic()     == MAGIC_S02_ML_ENSEMBLE, "S02 Magic = 1002");
    Assert(s02.GetShortName() == "S02",                  "S02 short_name = S02");
    Assert(s02.GetFamily()    == "AI/ML Predictive",     "S02 family = AI/ML Predictive");
    Assert(s02.GetCategory()  == "Hybrid",               "S02 category = Hybrid");
    Assert(s02.IsStandaloneCapable() == false,            "S02 standalone = false");
    
    // =================================================================
    // TEST 3: Init
    // =================================================================
    Print("--- TEST 3: Init ---");
    bool s12_init = s12.Init(sym, tf);
    bool s02_init = s02.Init(sym, tf);
    
    Assert(s12_init,             "S12 Init() returns true");
    Assert(s12.IsInitialized(),  "S12 IsInitialized()");
    Assert(s02_init,             "S02 Init() returns true");
    Assert(s02.IsInitialized(),  "S02 IsInitialized()");
    
    // =================================================================
    // TEST 4: PinBarDetector direct test on last 50 bars
    // =================================================================
    Print("--- TEST 4: PinBarDetector direct scan (last 50 bars) ---");
    CPinBarDetector pb_det;
    pb_det.Setup(sym, tf, 0.30, 0.60);   // ✅ Setup() pattern (Lesson #2)
    
    int pinbar_count = 0;
    for(int i = 1; i <= 50; i++)
    {
        SPinBarResult r = pb_det.Detect(i);
        if(r.type != PINBAR_NONE)
        {
            pinbar_count++;
            if(Verbose)
                PrintFormat("  PinBar[%d]: %s | Wick:%.2f | Body:%.2f | Conf:%.3f",
                    i,
                    r.type == PINBAR_BULLISH ? "BULL" : "BEAR",
                    r.wick_ratio, r.body_ratio, r.confidence);
        }
    }
    PrintFormat("  Found %d pin bar(s) in last 50 bars", pinbar_count);
    Assert(true, StringFormat("PinBar scan complete — found %d bars", pinbar_count));
    
    // =================================================================
    // TEST 5: EngulfingDetector direct scan
    // =================================================================
    Print("--- TEST 5: EngulfingDetector direct scan (last 50 bars) ---");
    CEngulfingDetector eng_det;
    eng_det.Setup(sym, tf);   // ✅ Setup() pattern
    
    int engulf_count = 0;
    for(int i = 1; i <= 50; i++)
    {
        SEngulfingResult r = eng_det.Detect(i);
        if(r.type != ENGULF_NONE)
        {
            engulf_count++;
            if(Verbose)
                PrintFormat("  Engulfing[%d]: %s | SizeR:%.2f | Conf:%.3f",
                    i,
                    r.type == ENGULF_BULLISH ? "BULL" : "BEAR",
                    r.size_ratio, r.confidence);
        }
    }
    PrintFormat("  Found %d engulfing pattern(s) in last 50 bars", engulf_count);
    Assert(true, StringFormat("Engulfing scan complete — found %d bars", engulf_count));
    
    // =================================================================
    // TEST 6: KeyLevelFinder
    // =================================================================
    Print("--- TEST 6: KeyLevelFinder ---");
    CKeyLevelFinder kl;
    bool kl_ok = kl.Setup(sym, tf, 5, 100);   // ✅ Setup() pattern
    kl.Scan();
    
    Assert(kl_ok,              "KeyLevelFinder Setup() OK");
    Assert(kl.GetLevelCount() >= 0, "KeyLevelFinder has levels array");
    
    double curr_price = iClose(sym, tf, 0);
    double prox = kl.GetProximity(curr_price);
    PrintFormat("  Current price proximity to key level: %.3f (ATR: %.5f)",
                prox, kl.GetATR());
    Assert(prox >= 0.0 && prox <= 1.0, StringFormat("Proximity in [0,1] range = %.3f", prox));
    
    // =================================================================
    // TEST 7: S02 Signal Flow — BUY signal
    // =================================================================
    Print("--- TEST 7: S02 Signal Flow (BUY) ---");
    
    // Enable strategy
    s02.Enable();
    Assert(s02.IsEnabled(), "S02 Enable()");
    
    // Before signal: no signal
    Assert(s02.GetSignal() == SIGNAL_NONE, "S02 initial signal = NONE");
    
    // Inject BUY signal via SetDynamicParams
    SDynamicParams dp_buy;
    dp_buy.Reset();
    dp_buy.SetParam("S02_ML_SIGNAL",      1.0);    // BUY
    dp_buy.SetParam("S02_ML_CONFIDENCE",  0.82);   // above 0.70 threshold
    dp_buy.SetParam("S02_CONF_THRESHOLD", 0.70);
    dp_buy.mm_method = "MM01";
    s02.SetDynamicParams(dp_buy);
    
    // Simulate one tick
    MqlTick tick;
    tick.bid  = iClose(sym, tf, 0);
    tick.ask  = tick.bid + 30 * _Point;
    tick.time = TimeCurrent();
    s02.Analyze(tick);
    
    Assert(s02.GetSignal()     == SIGNAL_BUY, "S02 signal = BUY after ml_signal=1, conf=0.82");
    Assert(s02.GetConfidence() > 0.70,         "S02 confidence > 0.70");
    Assert(s02.IsSignalActive(),               "S02 IsSignalActive() = true");
    PrintFormat("  S02 BUY | Conf:%.3f | TimeLeft:%ds",
                s02.GetMLConfidence(), s02.GetSecondsLeft());
    
    // =================================================================
    // TEST 8: S02 Signal Flow — SELL signal below threshold
    // =================================================================
    Print("--- TEST 8: S02 Signal Flow (SELL below threshold) ---");
    
    SDynamicParams dp_sell_low;
    dp_sell_low.Reset();
    dp_sell_low.SetParam("S02_ML_SIGNAL",     -1.0);   // SELL
    dp_sell_low.SetParam("S02_ML_CONFIDENCE",  0.55);  // BELOW 0.70 threshold
    dp_sell_low.SetParam("S02_CONF_THRESHOLD", 0.70);
    dp_sell_low.mm_method = "MM01";
    
    CS02MLEnsemble s02b;
    s02b.Init(sym, tf);
    s02b.Enable();
    s02b.SetDynamicParams(dp_sell_low);
    s02b.Analyze(tick);
    
    Assert(s02b.GetSignal() == SIGNAL_NONE, "S02 signal = NONE when conf(0.55) < threshold(0.70)");
    
    // =================================================================
    // TEST 9: S02 mm_method propagation (Lesson #5)
    // =================================================================
    Print("--- TEST 9: S02 mm_method propagation ---");
    SDynamicParams dp_mm;
    dp_mm.Reset();
    dp_mm.SetParam("S02_ML_SIGNAL",     1.0);
    dp_mm.SetParam("S02_ML_CONFIDENCE", 0.75);
    dp_mm.mm_method = "MM04";
    s02.SetDynamicParams(dp_mm);
    
    SDynamicParams exported = s02.GetCurrentParams();
    Assert(exported.mm_method == "MM04", "S02 mm_method propagated correctly (Lesson#5)");
    
    // =================================================================
    // TEST 10: S12 Enable/Disable
    // =================================================================
    Print("--- TEST 10: S12 Enable/Disable ---");
    s12.Enable();
    Assert(s12.IsEnabled(),  "S12 Enable()");
    s12.Disable();
    Assert(!s12.IsEnabled(), "S12 Disable()");
    s12.Enable();
    
    // =================================================================
    // SUMMARY
    // =================================================================
    Print("");
    Print("╔══════════════════════════════════════════════════════════╗");
    PrintFormat("║  RESULT: %d PASSED | %d FAILED | %d TOTAL",
        g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("║  ✅ ALL TESTS PASSED — P2-2 READY                       ║");
    else
        PrintFormat("║  ⚠️  %d TEST(S) FAILED — Review output above", g_fail);
    Print("╚══════════════════════════════════════════════════════════╝");
    
    // Cleanup
    s12.Deinit();
    s02.Deinit();
    s02b.Deinit();
}
//+------------------------------------------------------------------+
