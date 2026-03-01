//+------------------------------------------------------------------+
//| TestP2_3_GridSpike.mq5                                          |
//| FlashEASuite V2 — P2-3 Integration Test: S15 Grid + S16 Spike  |
//| Tests: IStrategy interface compliance, API correctness           |
//+------------------------------------------------------------------+
//| วิธีทดสอบ:                                                       |
//| 1. Save ไฟล์นี้ที่ Tester/TestP2_3_GridSpike.mq5              |
//| 2. Compile ใน MetaEditor (F7)                                    |
//| 3. Attach เป็น Script บน Chart ใดก็ได้ (Live หรือ Demo)        |
//| 4. ดู Journal tab ใน MT5 — ทุก [PASS] ต้องผ่าน 0 FAIL         |
//+------------------------------------------------------------------+
//| Include path checklist (MISTAKE 3 lesson):                       |
//|  ไฟล์นี้อยู่ที่  Tester/                                        |
//|  S15_Grid.mqh    → Include/Logic/Strategies/S15_Grid.mqh       |
//|  S16_Spike.mqh   → Include/Logic/Strategies/S16_Spike.mqh      |
//|  ใช้ "../Include/Logic/Strategies/" (relative จาก Tester/)      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict
#property script_show_inputs

//--- Paths relative to Tester/ folder (MISTAKE 3 lesson: ตรงกับ folder จริง)
#include "../Include/Logic/Strategies/S15_Grid.mqh"
#include "../Include/Logic/Strategies/S16_Spike.mqh"

//--- Default symbol ต้องมี broker suffix .tp (MISTAKE 7 lesson)
input string Test_Symbol   = "XAUUSD.tp";
input bool   Verbose       = false;   // Print extra detail

//--- Test counters (global)
int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
//| Test helpers                                                     |
//+------------------------------------------------------------------+
void CHECK(bool cond, const string label)
{
    if(cond)
    {
        g_pass++;
        if(Verbose) PrintFormat("  [PASS] %s", label);
    }
    else
    {
        g_fail++;
        PrintFormat("  [FAIL] %s", label);
    }
}

void SECTION(const string title)
{
    PrintFormat("\n[TEST GROUP] %s", title);
}

//+------------------------------------------------------------------+
//| Check float equality with tolerance                              |
//+------------------------------------------------------------------+
bool Near(double a, double b, double tol = 0.001)
{
    return (MathAbs(a - b) <= tol);
}

//+------------------------------------------------------------------+
//| OnStart: Script entry point                                      |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("╔══════════════════════════════════════════════════╗");
    Print("║   FlashEASuite V2 — TestP2_3_GridSpike          ║");
    Print("║   Testing: S15 Immortal Grid + S16 Spike Hunter ║");
    Print("╚══════════════════════════════════════════════════╝");
    Print("Symbol: ", Test_Symbol);

    //--- Build a mock tick using SymbolInfoTick (no SymbolInfoDouble for SPREAD)
    MqlTick tick = {};
    if(!SymbolInfoTick(Test_Symbol, tick))
    {
        //--- Fallback if symbol not available (for compile-time test)
        tick.bid  = 1800.00;
        tick.ask  = 1800.10;
        tick.time = TimeCurrent();
        PrintFormat("[WARN] SymbolInfoTick(%s) failed — using mock tick", Test_Symbol);
    }

    //=================================================================
    //  SECTION 1: CS15Grid — Identity + IStrategy interface
    //=================================================================
    SECTION("S15 Grid — Identity + IStrategy");
    {
        CS15Grid grid;

        // StrategyConstants.mqh ยืนยัน: family="Range Grid", short_name="S15"
        // ต้องดู GetName/GetMagic/IsStandaloneCapable ก่อน Init()
        CHECK(grid.GetMagic()            == MAGIC_S15_GRID, "S15: GetMagic() == 1015");
        CHECK(grid.GetStrategyID()       == S15_GRID,       "S15: GetStrategyID() == S15_GRID");
        CHECK(grid.IsStandaloneCapable() == true,           "S15: IsStandaloneCapable() == true");

        // IStrategy.Init() sets m_info from g_strategy_table — so GetShortName/GetFamily
        // ใช้งานได้หลัง Init() เท่านั้น (ตรงกับ MQL5 Lessons MISTAKE 6)
        bool init_ok = grid.Init(Test_Symbol, PERIOD_M15);
        CHECK(init_ok,                                      "S15: Init(XAUUSD.tp, M15) returns true");

        // หลัง Init() — metadata จาก StrategyConstants
        CHECK(grid.GetShortName()  == "S15",                "S15: GetShortName() == S15");
        CHECK(grid.GetFamily()     == "Range Grid",         "S15: GetFamily() == Range Grid");
        CHECK(grid.IsInitialized() == true,                 "S15: IsInitialized() == true");

        grid.Deinit();
        CHECK(!grid.IsInitialized(),                        "S15: IsInitialized() == false after Deinit()");
    }

    //=================================================================
    //  SECTION 2: CS15Grid — Enable/Disable + Analyze
    //=================================================================
    SECTION("S15 Grid — Enable / Analyze");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);

        // Before Enable: signal must be NONE
        grid.Analyze(tick);
        // GetScore() ใน CStrategyGrid ต้องการ m_csm_data_received=true ถึงจะมี signal
        // ใน standalone test จะได้ SIGNAL_NONE (CSM not set) — ถูกต้อง
        // เราตรวจแค่ว่า Analyze() ไม่ crash
        CHECK(true, "S15: Analyze() does not crash");

        grid.Enable();
        CHECK(grid.IsEnabled(), "S15: IsEnabled() == true after Enable()");

        grid.Analyze(tick);
        CHECK(true, "S15: Analyze() after Enable() does not crash");

        // Signal ต้องอยู่ใน valid range (SIGNAL_NONE, BUY, SELL)
        ENUM_TRADE_SIGNAL sig = grid.GetSignal();
        CHECK(sig == SIGNAL_NONE || sig == SIGNAL_BUY || sig == SIGNAL_SELL,
              "S15: GetSignal() returns valid ENUM_TRADE_SIGNAL");

        double conf = grid.GetConfidence();
        CHECK(conf >= 0.0 && conf <= 1.0, "S15: GetConfidence() in [0.0, 1.0]");

        grid.Disable();
        CHECK(!grid.IsEnabled(), "S15: IsEnabled() == false after Disable()");
        grid.Deinit();
    }

    //=================================================================
    //  SECTION 3: CS15Grid — SetDynamicParams (CONFIG_PUSH V2)
    //=================================================================
    SECTION("S15 Grid — SetDynamicParams");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);

        SDynamicParams p;
        p.Reset();
        p.mm_method       = "MM5";
        p.risk_multiplier = 1.2;
        p.SetParam("S15_MAX_ORDERS",     8.0);
        p.SetParam("S15_BASE_STEP",      150.0);
        p.SetParam("S15_ELASTIC_FACTOR", 1.8);
        p.SetParam("S15_CONF_THRESHOLD", 0.7);
        p.SetParam("S15_ATR_RATIO",      0.9);
        p.SetParam("S15_SWAP_FILTER",    1.0);

        grid.SetDynamicParams(p);

        // Export and verify
        SDynamicParams out = grid.GetCurrentParams();
        CHECK(out.mm_method == "MM5",                       "S15: GetCurrentParams() mm_method == MM5");
        CHECK(Near(out.GetParam("S15_MAX_ORDERS", 0), 8),   "S15: GetCurrentParams() MAX_ORDERS==8");
        CHECK(Near(out.GetParam("S15_BASE_STEP",  0), 150), "S15: GetCurrentParams() BASE_STEP==150");
        CHECK(Near(out.GetParam("S15_ELASTIC_FACTOR",0),1.8),"S15: GetCurrentParams() ELASTIC_FACTOR==1.8");

        grid.Deinit();
    }

    //=================================================================
    //  SECTION 4: CS15Grid — SetParameters (JSON, CONFIG_PUSH V1)
    //=================================================================
    SECTION("S15 Grid — SetParameters JSON");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);

        string json = "{\"S15_MAX_ORDERS\":6, \"S15_BASE_STEP\":180.0, \"S15_ELASTIC_FACTOR\":2.0}";
        grid.SetParameters(json);

        SDynamicParams out = grid.GetCurrentParams();
        CHECK(Near(out.GetParam("S15_MAX_ORDERS",  0), 6),  "S15 JSON: MAX_ORDERS==6");
        CHECK(Near(out.GetParam("S15_BASE_STEP",   0), 180),"S15 JSON: BASE_STEP==180");
        CHECK(Near(out.GetParam("S15_ELASTIC_FACTOR",0),2.0),"S15 JSON: ELASTIC_FACTOR==2.0");

        grid.Deinit();
    }

    //=================================================================
    //  SECTION 5: CS15Grid — GetGrid() integration accessor
    //=================================================================
    SECTION("S15 Grid — GetGrid() accessor");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);

        CStrategyGrid* ptr = grid.GetGrid();
        CHECK(ptr != NULL,                      "S15: GetGrid() returns non-NULL pointer");
        CHECK(ptr.GetMaxGridLevels() > 0,       "S15: GetGrid().GetMaxGridLevels() > 0");
        CHECK(ptr.GetActiveGridCount() >= 0,    "S15: GetGrid().GetActiveGridCount() >= 0");

        // Direction accessible without crashing
        ENUM_GRID_DIRECTION dir = grid.GetGridDirection();
        CHECK(dir == GRID_DIR_NONE || dir == GRID_DIR_BUY || dir == GRID_DIR_SELL,
              "S15: GetGridDirection() returns valid ENUM_GRID_DIRECTION");

        grid.Deinit();
    }

    //=================================================================
    //  SECTION 6: CS15Grid — RecordTradeResult
    //=================================================================
    SECTION("S15 Grid — RecordTradeResult");
    {
        CS15Grid grid;
        grid.Init(Test_Symbol, PERIOD_M15);

        grid.RecordTradeResult(100.0);
        grid.RecordTradeResult(-50.0);
        grid.RecordTradeResult(75.0);

        CHECK(grid.GetWinRate() >= 0.0 && grid.GetWinRate() <= 1.0,
              "S15: GetWinRate() in [0, 1]");

        grid.Deinit();
    }

    //=================================================================
    //  SECTION 7: CS16Spike — Identity + IStrategy interface
    //=================================================================
    SECTION("S16 Spike — Identity + IStrategy");
    {
        CS16Spike spike;

        CHECK(spike.GetMagic()            == MAGIC_S16_SPIKE, "S16: GetMagic() == 1016");
        CHECK(spike.GetStrategyID()       == S16_SPIKE,       "S16: GetStrategyID() == S16_SPIKE");
        CHECK(spike.IsStandaloneCapable() == true,            "S16: IsStandaloneCapable() == true");

        // Init calls CStrategySpike.Init() (0 params) — creates sub-detectors
        bool init_ok = spike.Init(Test_Symbol, PERIOD_M1);
        CHECK(init_ok,                                        "S16: Init(XAUUSD.tp, M1) returns true");

        CHECK(spike.GetShortName() == "S16",                  "S16: GetShortName() == S16");
        CHECK(spike.GetFamily()    == "Momentum",             "S16: GetFamily() == Momentum");
        CHECK(spike.IsInitialized() == true,                  "S16: IsInitialized() == true");

        spike.Deinit();
        CHECK(!spike.IsInitialized(),                         "S16: IsInitialized() false after Deinit()");
    }

    //=================================================================
    //  SECTION 8: CS16Spike — Analyze multiple ticks
    //=================================================================
    SECTION("S16 Spike — Analyze multiple ticks");
    {
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);
        spike.Enable();

        // Feed 5 ticks to build sub-detector history
        MqlTick t = tick;
        double point = SymbolInfoDouble(Test_Symbol, SYMBOL_POINT);
        if(point == 0.0) point = 0.00001;

        for(int i = 0; i < 5; i++)
        {
            t.bid = tick.bid + i * point * 5;
            t.ask = t.bid  + point * 2;
            t.time = tick.time + i;
            spike.Analyze(t);
        }

        CHECK(true, "S16: Analyze() 5 ticks does not crash");

        ENUM_TRADE_SIGNAL sig = spike.GetSignal();
        CHECK(sig == SIGNAL_NONE || sig == SIGNAL_BUY || sig == SIGNAL_SELL,
              "S16: GetSignal() returns valid ENUM_TRADE_SIGNAL");

        double conf = spike.GetConfidence();
        CHECK(conf >= 0.0 && conf <= 1.0, "S16: GetConfidence() in [0.0, 1.0]");

        // Raw score 0-100
        double raw = spike.GetRawScore();
        CHECK(raw >= 0.0 && raw <= 100.0, "S16: GetRawScore() in [0, 100]");

        // ATR value
        double atr = spike.GetSpikeATR();
        CHECK(atr >= 0.0, "S16: GetSpikeATR() >= 0");

        spike.Deinit();
    }

    //=================================================================
    //  SECTION 9: CS16Spike — SetDynamicParams (CONFIG_PUSH V2)
    //=================================================================
    SECTION("S16 Spike — SetDynamicParams");
    {
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);

        SDynamicParams p;
        p.Reset();
        p.mm_method       = "MM3";
        p.risk_multiplier = 0.8;
        p.SetParam("S16_VELOCITY_THRESH",   3.0);
        p.SetParam("S16_SPREAD_THRESH",     1.2);
        p.SetParam("S16_VOLUME_THRESH",     2.5);
        p.SetParam("S16_MOMENTUM_THRESH",   0.6);
        p.SetParam("S16_VOLATILITY_THRESH", 1.8);
        p.SetParam("S16_DIRECTION_CONSIST", 0.75);
        p.SetParam("S16_PATTERN_SCORE_MIN", 60.0);
        p.SetParam("S16_ATR_TP_MULT",       1.0);
        p.SetParam("S16_ATR_SL_MULT",       0.5);
        p.SetParam("S16_MAX_HOLD_SEC",      600.0);

        spike.SetDynamicParams(p);

        SDynamicParams out = spike.GetCurrentParams();
        CHECK(out.mm_method == "MM3",                               "S16: mm_method == MM3");
        CHECK(Near(out.GetParam("S16_VELOCITY_THRESH",  0), 3.0),   "S16: VELOCITY_THRESH==3.0");
        CHECK(Near(out.GetParam("S16_PATTERN_SCORE_MIN",0), 60.0),  "S16: PATTERN_SCORE_MIN==60.0");
        CHECK(Near(out.GetParam("S16_ATR_TP_MULT",      0), 1.0),   "S16: ATR_TP_MULT==1.0");
        CHECK(Near(out.GetParam("S16_MAX_HOLD_SEC",     0), 600.0), "S16: MAX_HOLD_SEC==600");

        spike.Deinit();
    }

    //=================================================================
    //  SECTION 10: CS16Spike — SetParameters JSON
    //=================================================================
    SECTION("S16 Spike — SetParameters JSON");
    {
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);

        string json = "{\"S16_PATTERN_SCORE_MIN\":65.0, \"S16_MOMENTUM_THRESH\":0.4, \"S16_MAX_HOLD_SEC\":720.0}";
        spike.SetParameters(json);

        SDynamicParams out = spike.GetCurrentParams();
        CHECK(Near(out.GetParam("S16_PATTERN_SCORE_MIN", 0), 65.0), "S16 JSON: PATTERN_SCORE_MIN==65");
        CHECK(Near(out.GetParam("S16_MOMENTUM_THRESH",   0), 0.4),  "S16 JSON: MOMENTUM_THRESH==0.4");
        CHECK(Near(out.GetParam("S16_MAX_HOLD_SEC",      0), 720.0),"S16 JSON: MAX_HOLD_SEC==720");

        spike.Deinit();
    }

    //=================================================================
    //  SECTION 11: CS16Spike — CheckExit (no crash)
    //=================================================================
    SECTION("S16 Spike — CheckExit");
    {
        CS16Spike spike;
        spike.Init(Test_Symbol, PERIOD_M1);
        spike.Enable();
        spike.Analyze(tick);

        // CheckExit without open position → must return false (no ticket)
        bool should_exit = spike.CheckExit();
        CHECK(!should_exit, "S16: CheckExit() returns false when no position open");

        spike.Deinit();
    }

    //=================================================================
    //  SECTION 12: S15 + S16 — PrintDiagnostics (no crash)
    //=================================================================
    SECTION("S15 + S16 — PrintDiagnostics");
    {
        CS15Grid  grid;
        CS16Spike spike;

        grid.Init(Test_Symbol,  PERIOD_M15);
        spike.Init(Test_Symbol, PERIOD_M1);

        grid.Enable();
        spike.Enable();
        grid.Analyze(tick);
        spike.Analyze(tick);

        grid.PrintDiagnostics();   // Must not crash
        spike.PrintDiagnostics();  // Must not crash
        CHECK(true, "PrintDiagnostics() does not crash for both S15 and S16");

        grid.Deinit();
        spike.Deinit();
    }

    //=================================================================
    //  SECTION 13: S15 + S16 — mm_method กรณี default (MISTAKE 5)
    //=================================================================
    SECTION("mm_method default value (MISTAKE 5 check)");
    {
        CS15Grid  grid;
        CS16Spike spike;

        grid.Init(Test_Symbol,  PERIOD_M15);
        spike.Init(Test_Symbol, PERIOD_M1);

        // ก่อน SetDynamicParams — GetCurrentParams() ต้องไม่ crash
        // mm_method จะเป็น "" (default จาก SDynamicParams.Reset())
        SDynamicParams g_out  = grid.GetCurrentParams();
        SDynamicParams sp_out = spike.GetCurrentParams();

        CHECK(true, "S15: GetCurrentParams() before SetDynamicParams does not crash");
        CHECK(true, "S16: GetCurrentParams() before SetDynamicParams does not crash");

        // หลัง SetDynamicParams ด้วย mm_method — ต้อง export ถูกต้อง
        SDynamicParams p;
        p.Reset();
        p.mm_method = "MM7";
        grid.SetDynamicParams(p);
        spike.SetDynamicParams(p);

        CHECK(grid.GetCurrentParams().mm_method  == "MM7", "S15: mm_method propagates to GetCurrentParams()");
        CHECK(spike.GetCurrentParams().mm_method == "MM7", "S16: mm_method propagates to GetCurrentParams()");

        grid.Deinit();
        spike.Deinit();
    }

    //=================================================================
    //  SUMMARY
    //=================================================================
    Print("\n╔══════════════════════════════════════════════╗");
    PrintFormat("║  RESULT: %d PASS, %d FAIL                      ║", g_pass, g_fail);
    Print("╚══════════════════════════════════════════════╝");

    if(g_fail == 0)
        Print("✅ ALL TESTS PASSED — P2-3 S15+S16 ready!");
    else
        PrintFormat("❌ %d TEST(S) FAILED — check above for [FAIL] lines", g_fail);
}
//+------------------------------------------------------------------+
