//+------------------------------------------------------------------+
//|                                       Test_P8_1_Components.mq5  |
//|              FlashEASuite V2 — P8-1 Component Test Report        |
//+------------------------------------------------------------------+
//| COVERAGE:                                                        |
//|   Test 1: 16 Strategies × 3 Symbols (Init/Signal/Magic)         |
//|   Test 2: CStandaloneSelector — 5 regime configs                |
//|   Test 3: StrategyConstants — metadata & magic unique           |
//|   Test 4: GetDefaultMM() validity for all 16 strategies         |
//|   Test 5: ConnectionMonitor + ConfigReceiver init               |
//|                                                                  |
//| SAVE TO : 03_Trader\Test_P8_1_Components.mq5                    |
//|           (folder เดียวกับ ProgramC_Trader.mq5)                  |
//| RUN     : Strategy Tester → Symbol=XAUUSD.tp, Open prices only  |
//| ผลดูที่ Expert tab                                                |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.01"
#property strict

#include "../Include/Logic/StrategyManager_V6.mqh"
#include "../Include/Logic/ConnectionMonitor.mqh"
#include "../Include/Logic/ConfigReceiver.mqh"
#include "../Include/Standalone/StandaloneSelector.mqh"

input string SYMBOL_SUFFIX = ".tp";
input bool   VERBOSE_LOG   = true;

int    g_pass = 0;
int    g_fail = 0;
int    g_skip = 0;
string g_fail_list = "";

string Sym(string base) { return base + SYMBOL_SUFFIX; }

void PASS(string label)
{
    g_pass++;
    if(VERBOSE_LOG) PrintFormat("  [PASS] %s", label);
}
void FAIL(string label, string reason = "")
{
    g_fail++;
    string msg = StringFormat("  [FAIL] %s%s", label, reason != "" ? " — " + reason : "");
    Print(msg);
    g_fail_list += "\n" + msg;
}
void SKIP(string label, string reason)
{
    g_skip++;
    PrintFormat("  [SKIP] %s — %s", label, reason);
}
void Sec(string t)
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    PrintFormat("  %s", t);
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

// MQL5 ใช้ SymbolInfoDouble — ไม่ใช่ MarketInfo (MQL4 only)
bool SymbolAvail(string sym)
{
    SymbolSelect(sym, true);
    return (SymbolInfoDouble(sym, SYMBOL_BID) > 0.0);
}

// ====================================================================
//  TEST 1
// ====================================================================
void T1_Strategies()
{
    Sec("TEST 1: 16 Strategies × 3 Symbols");

    string syms[3];
    syms[0] = Sym("XAUUSD");
    syms[1] = Sym("EURUSD");
    syms[2] = Sym("GBPUSD");

    bool sa_spec[16];  // standalone-capable per spec
    sa_spec[0] = true;  sa_spec[1] = false; sa_spec[2] = false; sa_spec[3] = false;
    sa_spec[4] = false; sa_spec[5] = true;  sa_spec[6] = true;  sa_spec[7] = false;
    sa_spec[8] = false; sa_spec[9] = true;  sa_spec[10]= false; sa_spec[11]= false;
    sa_spec[12]= false; sa_spec[13]= true;  sa_spec[14]= true;  sa_spec[15]= true;

    for(int s = 0; s < 3; s++)
    {
        string sym = syms[s];
        if(!SymbolAvail(sym)) { SKIP("T1 " + sym, "Not in Market Watch"); continue; }

        CStrategyManager_V6 sm;
        sm.RegisterAllStrategies(sym, PERIOD_M15);

        // ✅ IsRegistered() — เป็น method จริง (ไม่มี GetRegisteredCount)
        if(sm.IsRegistered())
            PASS(StringFormat("RegisterAllStrategies(%s) IsRegistered=true", sym));
        else
            FAIL(StringFormat("RegisterAllStrategies(%s)", sym), "IsRegistered=false");

        // ✅ FillStatusArray — เพื่อ count
        SStrategyStatusEntry arr[];
        int cnt = 0;
        sm.FillStatusArray(arr, cnt);
        if(cnt == 16) PASS(StringFormat("[%s] FillStatusArray → 16 entries", sym));
        else FAIL(StringFormat("[%s] FillStatusArray", sym),
                  StringFormat("%d entries (expected 16)", cnt));

        for(int i = 0; i < 16; i++)
        {
            ENUM_STRATEGY_ID sid = (ENUM_STRATEGY_ID)i;
            IStrategy* strat = sm.GetStrategyByID(sid);
            if(strat == NULL) { FAIL(StringFormat("[%s] S%02d", sym, i+1), "NULL ptr"); continue; }
            if(!strat.IsInitialized()) { FAIL(StringFormat("[%s] S%02d", sym, i+1), "not init"); continue; }

            bool sa_ok = (strat.IsStandaloneCapable() == sa_spec[i]);
            bool sig_ok = (strat.GetSignal() >= SIGNAL_SELL && strat.GetSignal() <= SIGNAL_BUY);
            double conf = strat.GetConfidence();
            bool conf_ok = (conf >= 0.0 && conf <= 1.0);
            // ✅ GetMagic() — ชื่อจริง ไม่ใช่ GetMagicNumber()
            int magic = strat.GetMagic();
            bool magic_ok = (magic > 0);

            if(sa_ok && sig_ok && conf_ok && magic_ok)
                PASS(StringFormat("[%s] S%02d %s magic=%d", sym, i+1,
                                  strat.GetShortName(), magic));
            else
            {
                if(!sa_ok)    FAIL(StringFormat("[%s] S%02d SA",   sym, i+1), "spec mismatch");
                if(!sig_ok)   FAIL(StringFormat("[%s] S%02d sig",  sym, i+1), "invalid signal");
                if(!conf_ok)  FAIL(StringFormat("[%s] S%02d conf", sym, i+1), StringFormat("%.4f", conf));
                if(!magic_ok) FAIL(StringFormat("[%s] S%02d magic",sym, i+1), StringFormat("%d ≤0", magic));
            }
        }

        // ✅ Deinit() — ชื่อจริง ไม่ใช่ DeinitAll()
        sm.Deinit();
        PASS(StringFormat("[%s] StrategyManager.Deinit() no crash", sym));
    }
}

// ====================================================================
//  TEST 2
// ====================================================================
void T2_StandaloneSelector()
{
    Sec("TEST 2: CStandaloneSelector — 5 Regime Strategy Assignments");

    if(!g_strategy_table_initialized) InitStrategyTable();

    ENUM_MARKET_REGIME regimes[5];
    regimes[0]=REGIME_TRENDING; regimes[1]=REGIME_RANGING;
    regimes[2]=REGIME_VOLATILE; regimes[3]=REGIME_SQUEEZE;
    regimes[4]=REGIME_UNKNOWN;

    int exp_cnt[5]; exp_cnt[0]=3; exp_cnt[1]=3; exp_cnt[2]=2; exp_cnt[3]=2; exp_cnt[4]=2;
    string rnames[5]; rnames[0]="TRENDING"; rnames[1]="RANGING";
    rnames[2]="VOLATILE"; rnames[3]="SQUEEZE"; rnames[4]="UNKNOWN";

    for(int r = 0; r < 5; r++)
    {
        ENUM_STRATEGY_ID ids[];
        int cnt = GetStandaloneStrategiesForRegime(regimes[r], ids);
        if(cnt != exp_cnt[r])
        {
            FAIL(StringFormat("Regime[%s] count", rnames[r]),
                 StringFormat("expected %d got %d", exp_cnt[r], cnt));
            continue;
        }
        bool all_sa = true;
        for(int k = 0; k < cnt; k++)
            if(!IsStandaloneStrategy(ids[k]))
            {
                all_sa = false;
                FAIL(StringFormat("Regime[%s] id[%d]", rnames[r], k), "not SA-capable");
            }
        if(all_sa)
            PASS(StringFormat("Regime[%s] → %d strategies, all SA-capable ✅", rnames[r], cnt));
    }

    // StandaloneSelector.Init
    string sym = Sym("XAUUSD");
    if(!SymbolAvail(sym)) { SKIP("StandaloneSelector.Init", "XAUUSD not in MW"); return; }

    CStrategyManager_V6 sm;
    if(!sm.RegisterAllStrategies(sym, PERIOD_M15))
    {
        FAIL("T2 StrategyManager", "RegisterAllStrategies failed"); return;
    }

    CStandaloneSelector sel;
    if(sel.Init(&sm, sym, PERIOD_M15, "p8_1_test_sel.dat"))
        PASS("CStandaloneSelector.Init() ✅");
    else
        FAIL("CStandaloneSelector.Init()", "returned false");

    double c = sel.GetConfidence();
    if(c >= 0.0 && c <= 1.0) PASS(StringFormat("GetConfidence()=%.3f valid", c));
    else FAIL("GetConfidence()", StringFormat("%.3f out of range", c));

    if(sel.SaveConfig())  PASS("SaveConfig() ✅");
    else FAIL("SaveConfig()", "returned false");
    if(sel.LoadConfig())  PASS("LoadConfig() ✅");
    else FAIL("LoadConfig()", "failed");

    sel.UpdateThresholds(27.0, 23.0, 35.0, 0.60, 0.50, 1.0);
    PASS("UpdateThresholds() no crash");

    sel.PrintStatus();
    PASS("PrintStatus() no crash");

    sel.Deinit();
    PASS("CStandaloneSelector.Deinit() no crash");

    sm.Deinit();
}

// ====================================================================
//  TEST 3
// ====================================================================
void T3_Constants()
{
    Sec("TEST 3: StrategyConstants — Metadata & RegimeAlignmentFactor");

    if(!g_strategy_table_initialized) InitStrategyTable();

    int ok = 0;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        SStrategyInfo info = GetStrategyInfo((ENUM_STRATEGY_ID)i);
        bool ok_all = (info.name != "") && (info.short_name != "") &&
                      (info.magic > 0) &&
                      (info.best_regime >= REGIME_UNKNOWN &&
                       info.best_regime <= REGIME_SQUEEZE);  // UNKNOWN=0..SQUEEZE=4
        if(ok_all) { PASS(StringFormat("S%02d %s magic=%d", i+1, info.short_name, info.magic)); ok++; }
        else FAIL(StringFormat("S%02d metadata", i+1), "empty/invalid field");
    }
    if(ok == TOTAL_STRATEGIES)
        PASS(StringFormat("All %d strategy metadata complete ✅", TOTAL_STRATEGIES));

    // ✅ Magic unique using GetMagicNumber() global function
    int magic[TOTAL_STRATEGIES];
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
        magic[i] = GetMagicNumber((ENUM_STRATEGY_ID)i);
    bool uniq = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
        for(int j = i+1; j < TOTAL_STRATEGIES; j++)
            if(magic[i] == magic[j]) { uniq = false; FAIL(StringFormat("Magic S%02d==S%02d", i+1,j+1), "collision"); }
    if(uniq) PASS("All 16 magic numbers unique ✅");

    // RegimeAlignmentFactor [0.3, 1.5]
    ENUM_MARKET_REGIME tr[4];
    tr[0]=REGIME_TRENDING; tr[1]=REGIME_RANGING; tr[2]=REGIME_VOLATILE; tr[3]=REGIME_SQUEEZE;
    bool fok = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
        for(int r = 0; r < 4; r++)
        {
            double f = GetRegimeAlignmentFactor((ENUM_STRATEGY_ID)i, tr[r]);
            if(f < 0.3 || f > 1.5)
            {
                fok = false;
                FAIL(StringFormat("S%02d Factor[%s]", i+1, EnumToString(tr[r])),
                     StringFormat("%.2f out of [0.3,1.5]", f));
            }
        }
    if(fok) PASS("All RegimeAlignmentFactor in [0.3,1.5] ✅");
}

// ====================================================================
//  TEST 4
// ====================================================================
void T4_MMAssignments()
{
    Sec("TEST 4: GetDefaultMM() — MM01-MM19 validity for all strategies");

    string vld[19];
    vld[0]="MM01"; vld[1]="MM02"; vld[2]="MM03"; vld[3]="MM04"; vld[4]="MM05";
    vld[5]="MM06"; vld[6]="MM07"; vld[7]="MM08"; vld[8]="MM09"; vld[9]="MM10";
    vld[10]="MM11"; vld[11]="MM12"; vld[12]="MM13"; vld[13]="MM14"; vld[14]="MM15";
    vld[15]="MM16"; vld[16]="MM17"; vld[17]="MM18"; vld[18]="MM19";

    int ok = 0;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        // ✅ GetDefaultMM() global function (SStrategyInfo ไม่มี field default_mm)
        string mm = GetDefaultMM((ENUM_STRATEGY_ID)i);
        bool valid = false;
        for(int m = 0; m < 19; m++) if(mm == vld[m]) { valid = true; break; }
        if(valid) { PASS(StringFormat("S%02d GetDefaultMM()='%s'", i+1, mm)); ok++; }
        else FAIL(StringFormat("S%02d GetDefaultMM()", i+1), StringFormat("'%s' not in MM01-MM19", mm));
    }
    PrintFormat("  → %d/16 valid MM assignments", ok);

    // coverage check
    string crit[3]; crit[0]="MM01"; crit[1]="MM04"; crit[2]="MM07";
    for(int c = 0; c < 3; c++)
    {
        bool found = false;
        for(int i = 0; i < TOTAL_STRATEGIES; i++)
            if(GetDefaultMM((ENUM_STRATEGY_ID)i) == crit[c]) { found = true; break; }
        if(found) PASS(StringFormat("Critical %s assigned ✅", crit[c]));
        else FAIL(StringFormat("Critical %s", crit[c]), "no strategy uses this");
    }
}

// ====================================================================
//  TEST 5
// ====================================================================
void T5_NetworkComponents()
{
    Sec("TEST 5: ConnectionMonitor + ConfigReceiver");

    CConnectionMonitor cm;
    // ✅ Init(int, int) — 2 params only (ไม่มี string param)
    cm.Init(30, 20);
    if(!cm.IsConnected()) PASS("cm.Init() → OFFLINE ✅");
    else FAIL("cm.Init()", "should start OFFLINE");

    // ✅ UpdateHeartbeat() — ชื่อจริง
    cm.UpdateHeartbeat();
    if(cm.IsConnected()) PASS("cm.UpdateHeartbeat() → ONLINE ✅");
    else FAIL("cm.UpdateHeartbeat()", "still OFFLINE");

    // ✅ ForceDisconnect() — ชื่อจริง
    cm.ForceDisconnect();
    if(!cm.IsConnected()) PASS("cm.ForceDisconnect() → OFFLINE ✅");
    else FAIL("cm.ForceDisconnect()", "still ONLINE");

    string st = cm.GetStatus();
    if(StringLen(st) > 0) PASS(StringFormat("cm.GetStatus() = '%s'", st));
    else FAIL("cm.GetStatus()", "empty");

    cm.MarkInitialConnected();
    if(cm.IsConnected()) PASS("cm.MarkInitialConnected() → ONLINE ✅");
    else FAIL("cm.MarkInitialConnected()", "still OFFLINE");

    cm.Reset();
    PASS("cm.Reset() no crash");

    // ConfigReceiver
    CConfigReceiver cr;
    cr.Init();
    PASS("cr.Init() no crash");

    // ✅ HasPendingCommand() — method จริง (ไม่มี HasPendingConfig)
    if(!cr.HasPendingCommand()) PASS("cr.HasPendingCommand() = false ✅");
    else FAIL("cr.HasPendingCommand()", "should be false on init");

    if(cr.GetConfigCount() == 0) PASS("cr.GetConfigCount() = 0 ✅");
    else FAIL("cr.GetConfigCount()", StringFormat("expected 0 got %d", cr.GetConfigCount()));

    if(!cr.HasDynamicParams()) PASS("cr.HasDynamicParams() = false ✅");
    else FAIL("cr.HasDynamicParams()", "should be false");

    if(!cr.HasNewsEvent()) PASS("cr.HasNewsEvent() = false ✅");
    else FAIL("cr.HasNewsEvent()", "should be false");
}

// ====================================================================
int OnInit()
{
    Print("");
    Print("╔══════════════════════════════════════════════════════════════╗");
    Print("║         FlashEASuite V2 — P8-1 COMPONENT TEST REPORT        ║");
    Print("║                      (MQL5 Side v1.01)                      ║");
    PrintFormat("║  Date: %-52s║", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("╚══════════════════════════════════════════════════════════════╝");
    Print("");

    T1_Strategies();
    T2_StandaloneSelector();
    T3_Constants();
    T4_MMAssignments();
    T5_NetworkComponents();

    Print("");
    Print("╔══════════════════════════════════════════════════════════════╗");
    Print("║                    FINAL SUMMARY REPORT                     ║");
    Print("╠══════════════════════════════════════════════════════════════╣");
    PrintFormat("║  ✅ PASS : %-50d║", g_pass);
    PrintFormat("║  ❌ FAIL : %-50d║", g_fail);
    PrintFormat("║  ⏭ SKIP : %-50d║", g_skip);
    int tot = g_pass + g_fail;
    double pct = tot > 0 ? (100.0 * g_pass / tot) : 0.0;
    PrintFormat("║  Pass Rate : %.1f%% (%d/%d)%-34s║", pct, g_pass, tot, "");
    Print("╠══════════════════════════════════════════════════════════════╣");
    if(g_fail == 0)
        Print("║  🎉 ALL TESTS PASSED — READY FOR P8-2 INTEGRATION TEST      ║");
    else
    {
        Print("║  ⚠  FAILURES FOUND — Fix before P8-2!                       ║");
        Print("╠══════════════════════════════════════════════════════════════╣");
        string lines[]; int n = StringSplit(g_fail_list, '\n', lines);
        for(int i = 0; i < n && i < 20; i++)
            if(StringLen(lines[i]) > 1) PrintFormat("║  %s", lines[i]);
    }
    Print("╚══════════════════════════════════════════════════════════════╝");
    Print("[P8-1 MQL5] Done. EA returns INIT_FAILED to stop Tester.");

    return (g_fail == 0) ? INIT_SUCCEEDED : INIT_FAILED;
}
void OnDeinit(const int reason) {}
void OnTick() {}
//+------------------------------------------------------------------+
