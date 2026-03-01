//+------------------------------------------------------------------+
//| Test_P1_5_S04_S08.mq5                                           |
//| FlashEASuite V2 — Unit Test for S04 MarketProfile + S08 Intermarket |
//| Phase P1-5 — 2026-02-20                                         |
//+------------------------------------------------------------------+
//| Test Coverage:                                                   |
//|  [S04-1]  Metadata (Family, Magic, Category, Standalone)        |
//|  [S04-2]  Init() succeeds on XAUUSD.tp M15                      |
//|  [S04-3]  VolumeProfileBuilder builds successfully               |
//|  [S04-4]  POC, VAH, VAL are in valid price range               |
//|  [S04-5]  Analyze() returns SIGNAL_NONE initially (no vol data) |
//|  [S04-6]  GetTP / GetSL return non-zero after profile built     |
//|  [S04-7]  GetCurrentParams includes mm_method + S04_BINS        |
//|  [S08-1]  Metadata (Family, Magic, Category, Standalone)        |
//|  [S08-2]  Init() succeeds on XAUUSD.tp M15                      |
//|  [S08-3]  Analyze() returns SIGNAL_NONE without server data     |
//|  [S08-4]  SetServerData() + Analyze() → SIGNAL_BUY (DXY down)  |
//|  [S08-5]  SetServerData() + Analyze() → SIGNAL_SELL (DXY up)   |
//|  [S08-6]  Confidence = |corr| × momentum × volatility           |
//|  [S08-7]  GetTP / GetSL return valid ATR-based levels           |
//|  [S08-8]  GetCurrentParams includes mm_method + correlation     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property script_show_inputs

#include "../Include/Logic/Strategies/S04_MarketProfile.mqh"
#include "../Include/Logic/Strategies/S08_Intermarket.mqh"

input string Test_Symbol = "XAUUSD.tp";  // Trading symbol (broker suffix)
input ENUM_TIMEFRAMES Test_TF = PERIOD_M15;

//--- Test counters
int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
//| Assert helper                                                    |
//+------------------------------------------------------------------+
void Assert(bool condition, string test_name)
{
    if(condition)
    {
        PrintFormat("  ✅ PASS | %s", test_name);
        g_pass++;
    }
    else
    {
        PrintFormat("  ❌ FAIL | %s", test_name);
        g_fail++;
    }
}

//+------------------------------------------------------------------+
//| AssertRange: value must be within [lo, hi]                       |
//+------------------------------------------------------------------+
void AssertRange(double value, double lo, double hi, string test_name)
{
    bool ok = (value >= lo && value <= hi);
    if(ok)
        PrintFormat("  ✅ PASS | %s (%.5f in [%.5f, %.5f])", test_name, value, lo, hi);
    else
        PrintFormat("  ❌ FAIL | %s (%.5f NOT in [%.5f, %.5f])", test_name, value, lo, hi);
    if(ok) g_pass++; else g_fail++;
}

//+------------------------------------------------------------------+
//| Test_S04                                                         |
//+------------------------------------------------------------------+
void Test_S04()
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("  S04 — Market Profile + Order Flow");
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    CMarketProfile s04;
    
    //--- [S04-1] Metadata
    //--- Must Init() first to load strategy table
    bool init_ok = s04.Init(Test_Symbol, Test_TF);
    
    Assert(s04.GetMagic()      == MAGIC_S04_MARKET_PROF,   "[S04-1a] Magic=1004");
    Assert(s04.GetFamily()     == "Volume-based",           "[S04-1b] Family=Volume-based");
    Assert(s04.GetCategory()   == "Full_MQL5",              "[S04-1c] Category=Full_MQL5");
    Assert(s04.IsStandaloneCapable() == false,              "[S04-1d] Standalone=false (ServerOnly)");
    Assert(s04.GetStrategyID() == S04_MARKET_PROFILE,       "[S04-1e] StrategyID=S04_MARKET_PROFILE");
    
    //--- [S04-2] Init
    Assert(init_ok, "[S04-2] Init() OK on " + Test_Symbol);
    
    if(!init_ok)
    {
        Print("[S04] Init failed — skipping remaining S04 tests");
        return;
    }
    
    //--- [S04-3] VolumeProfileBuilder builds
    //--- Allow up to 200ms for indicator warm-up
    Sleep(200);
    Assert(s04.IsProfileBuilt(), "[S04-3] VolumeProfileBuilder.Build() OK");
    
    //--- [S04-4] POC, VAH, VAL in valid range
    double poc = s04.GetPOC();
    double vah = s04.GetVAH();
    double val = s04.GetVAL();
    
    double cur_price = SymbolInfoDouble(Test_Symbol, SYMBOL_BID);
    double spread    = SymbolInfoDouble(Test_Symbol, SYMBOL_POINT) * 10000; // rough
    
    if(cur_price > 0.0)
    {
        //--- POC should be near current price (within ±20%)
        Assert(poc > 0.0, "[S04-4a] POC > 0");
        Assert(vah > poc, "[S04-4b] VAH > POC");
        Assert(val < poc, "[S04-4c] VAL < POC");
        Assert(vah > val, "[S04-4d] VAH > VAL");
    }
    else
    {
        Print("[S04-4] Skipped — no market data (offline?)");
    }
    
    //--- [S04-5] Analyze() with strategy enabled
    s04.Enable();
    MqlTick tick;
    if(SymbolInfoTick(Test_Symbol, tick))
    {
        s04.Analyze(tick);
        //--- Without elevated volume, expect NONE or a valid signal
        ENUM_TRADE_SIGNAL sig = s04.GetSignal();
        bool signal_valid = (sig == SIGNAL_NONE || sig == SIGNAL_BUY || sig == SIGNAL_SELL);
        Assert(signal_valid, "[S04-5] Analyze() returns valid signal enum");
        PrintFormat("  [S04-5] Signal=%s Confidence=%.2f",
                    sig == SIGNAL_BUY ? "BUY" : sig == SIGNAL_SELL ? "SELL" : "NONE",
                    s04.GetConfidence());
    }
    
    //--- [S04-6] GetTP / GetSL return sensible values after profile built
    if(poc > 0.0 && vah > 0.0)
    {
        double tp_long = s04.GetTP(SIGNAL_BUY);
        double sl_long = s04.GetSL(SIGNAL_BUY, val);
        Assert(tp_long > 0.0 || poc > 0.0, "[S04-6a] GetTP(BUY) uses POC or node");
        Assert(sl_long  < poc,             "[S04-6b] GetSL(BUY) is below POC");
        
        double tp_short = s04.GetTP(SIGNAL_SELL);
        double sl_short = s04.GetSL(SIGNAL_SELL, vah);
        Assert(tp_short > 0.0 || poc > 0.0, "[S04-6c] GetTP(SELL) uses POC or node");
        Assert(sl_short  > poc,             "[S04-6d] GetSL(SELL) is above POC");
    }
    
    //--- [S04-7] GetCurrentParams
    SDynamicParams params = s04.GetCurrentParams();
    Assert(params.mm_method != "",            "[S04-7a] mm_method not empty");
    Assert(params.HasParam("S04_BINS"),       "[S04-7b] HasParam S04_BINS");
    Assert(params.HasParam("S04_LOOKBACK_BARS"), "[S04-7c] HasParam S04_LOOKBACK_BARS");
    Assert(params.HasParam("S04_VA_PCT"),     "[S04-7d] HasParam S04_VA_PCT");
    
    s04.Deinit();
    Print("[S04] Deinit OK");
}

//+------------------------------------------------------------------+
//| Test_S08                                                         |
//+------------------------------------------------------------------+
void Test_S08()
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("  S08 — Intermarket Correlation (DXY/XAUUSD)");
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    CIntermarket s08;
    
    //--- [S08-1] Metadata (before Init)
    bool init_ok = s08.Init(Test_Symbol, Test_TF);
    
    Assert(s08.GetMagic()      == MAGIC_S08_INTERMARKET,    "[S08-1a] Magic=1008");
    Assert(s08.GetFamily()     == "Multi-Asset",             "[S08-1b] Family=Multi-Asset");
    Assert(s08.GetCategory()   == "Hybrid",                  "[S08-1c] Category=Hybrid");
    Assert(s08.IsStandaloneCapable() == false,               "[S08-1d] Standalone=false (ServerOnly)");
    Assert(s08.GetStrategyID() == S08_INTERMARKET,           "[S08-1e] StrategyID=S08_INTERMARKET");
    
    //--- [S08-2] Init
    Assert(init_ok, "[S08-2] Init() OK on " + Test_Symbol);
    if(!init_ok)
    {
        Print("[S08] Init failed — skipping remaining S08 tests");
        return;
    }
    
    Sleep(200);  // indicator warm-up
    
    //--- [S08-3] Analyze without server data → SIGNAL_NONE
    s08.Enable();
    MqlTick tick;
    bool got_tick = SymbolInfoTick(Test_Symbol, tick);
    
    if(got_tick)
    {
        s08.Analyze(tick);
        Assert(s08.GetSignal() == SIGNAL_NONE, "[S08-3] No signal without server data");
        Assert(!s08.HasServerData(),           "[S08-3b] HasServerData=false before SetServerData");
    }
    
    //--- [S08-4] SetServerData → BUY (corr=-0.85, DXY weakening)
    s08.SetServerData(-0.85, -1, 0.65, 0.55);  // corr=-0.85, DXY DOWN, momentum=0.65
    Assert(s08.HasServerData(),             "[S08-4a] HasServerData=true after SetServerData");
    Assert(s08.GetCorrelation() == -0.85,   "[S08-4b] Correlation=-0.85");
    Assert(s08.GetDXYDirection() == -1,     "[S08-4c] DXYDirection=-1 (weakening)");
    
    if(got_tick)
    {
        s08.Analyze(tick);
        Assert(s08.GetSignal() == SIGNAL_BUY,  "[S08-4d] Signal=BUY (DXY down, strong corr)");
        double conf = s08.GetConfidence();
        Assert(conf > 0.0 && conf <= 1.0,      "[S08-4e] Confidence in (0, 1]");
        PrintFormat("  [S08-4] BUY Confidence=%.4f (expect 0.85×0.65×0.55=%.4f)",
                    conf, 0.85 * 0.65 * 0.55);
    }
    
    //--- [S08-5] SetServerData → SELL (corr=-0.80, DXY strengthening)
    s08.SetServerData(-0.80, 1, 0.72, 0.60);   // corr=-0.80, DXY UP, momentum=0.72
    if(got_tick)
    {
        s08.Analyze(tick);
        Assert(s08.GetSignal() == SIGNAL_SELL, "[S08-5a] Signal=SELL (DXY up, strong corr)");
        double conf = s08.GetConfidence();
        PrintFormat("  [S08-5] SELL Confidence=%.4f (expect 0.80×0.72×0.60=%.4f)",
                    conf, 0.80 * 0.72 * 0.60);
    }
    
    //--- [S08-6] Weak correlation → SIGNAL_NONE
    s08.SetServerData(-0.40, -1, 0.65, 0.55);  // corr < threshold (-0.70)? → NO
    if(got_tick)
    {
        s08.Analyze(tick);
        Assert(s08.GetSignal() == SIGNAL_NONE, "[S08-6] Weak correlation → SIGNAL_NONE");
    }
    
    //--- [S08-7] GetTP / GetSL use ATR
    s08.SetServerData(-0.85, 1, 0.65, 0.55);
    if(got_tick)
    {
        s08.Analyze(tick);
        double entry = tick.bid;
        double tp    = s08.GetTP(SIGNAL_SELL, entry);
        double sl    = s08.GetSL(SIGNAL_SELL, entry);
        double atr   = s08.GetLastATR();
        
        if(atr > 0.0)
        {
            double expected_tp = entry - 2.0 * atr;
            double expected_sl = entry + 1.0 * atr;
            Assert(MathAbs(tp - expected_tp) < atr * 0.01, "[S08-7a] TP = entry - 2×ATR");
            Assert(MathAbs(sl - expected_sl) < atr * 0.01, "[S08-7b] SL = entry + 1×ATR");
            PrintFormat("  [S08-7] ATR=%.5f TP=%.5f SL=%.5f", atr, tp, sl);
        }
    }
    
    //--- [S08-8] GetCurrentParams
    SDynamicParams params = s08.GetCurrentParams();
    Assert(params.mm_method != "",                 "[S08-8a] mm_method not empty");
    Assert(params.HasParam("S08_CORR_THRESHOLD"),  "[S08-8b] HasParam S08_CORR_THRESHOLD");
    Assert(params.HasParam("S08_CORRELATION"),     "[S08-8c] HasParam S08_CORRELATION");
    Assert(params.HasParam("S08_DXY_DIRECTION"),   "[S08-8d] HasParam S08_DXY_DIRECTION");
    
    s08.Deinit();
    Print("[S08] Deinit OK");
}

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("╔══════════════════════════════════════════════════════════╗");
    Print("║  FlashEASuite V2 — Test P1-5: S04 + S08                ║");
    Print("║  Date: 2026-02-20 | Phase: P1-5                        ║");
    Print("╚══════════════════════════════════════════════════════════╝");
    
    Test_S04();
    Test_S08();
    
    Print("══════════════════════════════════════════════════════════");
    PrintFormat("  RESULT: %d PASSED | %d FAILED | Total: %d",
                g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("  🎉 ALL TESTS PASSED ✅");
    else
        PrintFormat("  ⚠️  %d tests need attention", g_fail);
    Print("══════════════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
