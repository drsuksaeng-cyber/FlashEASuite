//+------------------------------------------------------------------+
//| Test_P8_2_Integration.mq5                                        |
//| FlashEASuite V2 — P8-2: Full System Integration Tests (MQL5)    |
//| Phase: P8-2                                                      |
//+------------------------------------------------------------------+
//| Save: 03_Trader/Tester/Test_P8_2_Integration.mq5                 |
//| Run:  Script (drag to chart)                                     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "8.03"
#property strict
#property script_show_inputs

#include "../Include/MqlMsgPack.mqh"
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/ConnectionMonitor.mqh"
#include "../Include/Logic/ConfigReceiver.mqh"
#include "../Include/Logic/StrategyManager_V6.mqh"

//--- Global counters
int g_pass = 0;
int g_fail = 0;

//--- V6 Components (global — เหมือน ProgramC_Trader)
CStrategyManager_V6  g_sm;
CConnectionMonitor   g_conn;
CConfigReceiver      g_recv;

//+------------------------------------------------------------------+
//| Test helpers — function-based (ไม่ใช้ macro if/else)             |
//+------------------------------------------------------------------+
void _Pass(string msg)
{
    g_pass++;
    PrintFormat("  [PASS %d] %s", g_pass, msg);
}

void _Fail(string msg)
{
    g_fail++;
    PrintFormat("  [FAIL %d] %s", g_fail, msg);
}

void Check(bool cond, string msg)
{
    if(cond) _Pass(msg);
    else     _Fail(msg);
}

void Section(string name)
{
    PrintFormat("\n=== %s ===", name);
}

string Fmt(string s, int v)           { return StringFormat(s, v); }
string FmtS(string s, string v)       { return StringFormat(s, v); }
string FmtD(string s, double v)       { return StringFormat(s, v); }
string FmtSS(string s, string a, string b) { return StringFormat(s, a, b); }
string FmtII(string s, int a, int b)  { return StringFormat(s, a, b); }

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
    Print(StringRep("=", 60));
    Print("FlashEASuite V2 — P8-2 Integration Tests (MQL5)");
    Print(StringRep("=", 60));

    Test_A_ComponentInit();
    Test_B_ConfigReceiverBasics();
    Test_C_OnlineStandaloneSwitch();
    Test_D_TradeReportBuild();
    Test_E_StrategyLifecycle();
    Test_F_GlobalFunctions();

    Print("\n" + StringRep("=", 60));
    PrintFormat("P8-2 Results: %d PASS | %d FAIL | Total: %d",
                g_pass, g_fail, g_pass + g_fail);
    if(g_fail == 0)
        Print("ALL TESTS PASSED");
    else
        PrintFormat("%d FAILED", g_fail);
    Print(StringRep("=", 60));
}


//=================================================================
// A: Component Initialization
//=================================================================
void Test_A_ComponentInit()
{
    Section("A: V6 Component Init");

    // A1: ก่อน register — IsRegistered() = false
    Check(!g_sm.IsRegistered(),
          "A1: IsRegistered()=false ก่อน RegisterAllStrategies()");

    // A2: RegisterAllStrategies()
    bool ok = g_sm.RegisterAllStrategies(_Symbol, PERIOD_M15);
    Check(ok, FmtS("A2: RegisterAllStrategies(%s,M15)=true", _Symbol));

    // A3: IsRegistered() = true
    Check(g_sm.IsRegistered(),
          "A3: IsRegistered()=true หลัง register");

    // A4: GetEnabledCount_V6 ∈ [0, TOTAL_STRATEGIES]
    int en = g_sm.GetEnabledCount_V6();
    Check(en >= 0 && en <= TOTAL_STRATEGIES,
          Fmt("A4: GetEnabledCount_V6()=%d อยู่ใน range", en));

    // A5: GetStrategyByID() — S01-S16 ทุกตัวไม่ NULL
    bool all_valid = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        if(g_sm.GetStrategyByID((ENUM_STRATEGY_ID)i) == NULL)
        {
            all_valid = false;
            break;
        }
    }
    Check(all_valid, "A5: GetStrategyByID — S01-S16 ทุกตัวไม่ NULL");

    // A6: S01 IsInitialized()
    IStrategy* s01 = g_sm.GetStrategyByID(S01_STAT_ARB);
    Check(s01 != NULL && s01.IsInitialized(),
          "A6: S01 IsInitialized()=true");

    // A7: Magic numbers ไม่ซ้ำ
    IStrategy* s07 = g_sm.GetStrategyByID(S07_MEAN_REVERSION);
    bool magic_ok = (s01 != NULL && s07 != NULL &&
                     s01.GetMagic() != s07.GetMagic() &&
                     s01.GetMagic() > 0);
    Check(magic_ok,
          FmtII("A7: Magic unique S01=%d, S07=%d",
                s01 != NULL ? s01.GetMagic() : 0,
                s07 != NULL ? s07.GetMagic() : 0));

    // A8: ConnectionMonitor Init
    g_conn.Init(30, 20);
    Check(!g_conn.IsConnected(),
          "A8: CConnectionMonitor.Init() — IsConnected()=false");

    // A9: FillStatusArray returns TOTAL_STRATEGIES entries
    SStrategyStatusEntry arr[];
    int cnt = 0;
    g_sm.FillStatusArray(arr, cnt);
    Check(cnt == TOTAL_STRATEGIES,
          FmtII("A9: FillStatusArray cnt=%d (expect %d)",
                cnt, TOTAL_STRATEGIES));

    // A10: S15 Grid IsStandaloneCapable()
    IStrategy* s15 = g_sm.GetStrategyByID(S15_GRID);
    Check(s15 != NULL && s15.IsStandaloneCapable(),
          "A10: S15 Grid IsStandaloneCapable()=true");
}


//=================================================================
// B: ConfigReceiver Basics
//=================================================================
void Test_B_ConfigReceiverBasics()
{
    Section("B: ConfigReceiver Basics");

    // B1: SaveStandaloneConfig() ไม่ crash
    g_recv.SaveStandaloneConfig();
    Check(true, "B1: SaveStandaloneConfig() completed");

    // B2: HasPendingCommand() = false เริ่มต้น
    Check(!g_recv.HasPendingCommand(),
          "B2: HasPendingCommand()=false (no command)");

    // B3: GetLastConfig().regime ∈ valid range
    SConfigData cfg = g_recv.GetLastConfig();
    Check(cfg.regime >= REGIME_UNKNOWN && cfg.regime <= REGIME_SQUEEZE,
          FmtS("B3: GetLastConfig().regime=%s ∈ valid range",
               EnumToString(cfg.regime)));

    // B4: GetDynamicParamsForStrategy() — ทุก strategy ไม่ crash
    bool dp_ok = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        SDynamicParams dp = g_recv.GetDynamicParamsForStrategy((ENUM_STRATEGY_ID)i);
        if(dp.strategy_param_count < 0)
        {
            dp_ok = false;
            break;
        }
    }
    Check(dp_ok, "B4: GetDynamicParamsForStrategy() S01-S16 ไม่ crash");

    // B5: GetLastConfigTime() ≥ 0
    datetime t = g_recv.GetLastConfigTime();
    Check(t >= 0, "B5: GetLastConfigTime() >= 0");

    // B6: ApplyConfig_V6(default_cfg) ไม่ crash
    g_sm.ApplyConfig_V6(cfg);
    Check(true, "B6: ApplyConfig_V6(default_cfg) completed");

    // B7: DistributeAllDynamicParams(empty) ไม่ crash
    SDynamicParams empty;
    empty.strategy_param_count = 0;
    g_sm.DistributeAllDynamicParams(empty);
    Check(true, "B7: DistributeAllDynamicParams(empty) completed");

    // B8: ReceiveMessage ด้วย random bytes — ไม่ crash (return ≠ 10)
    uchar dummy[4];
    dummy[0] = 0x94; dummy[1] = 0x01; dummy[2] = 0xC3; dummy[3] = 0x00;
    int rt = g_recv.ReceiveMessage(dummy, 4);
    Check(rt != 10, Fmt("B8: ReceiveMessage(random) != 10 (got %d)", rt));
}


//=================================================================
// C: Online → Standalone Switching
//=================================================================
void Test_C_OnlineStandaloneSwitch()
{
    Section("C: Online → Standalone Switching");

    // C1: MarkInitialConnected() → IsConnected()=true
    g_conn.MarkInitialConnected();
    Check(g_conn.IsConnected(),
          "C1: MarkInitialConnected() → IsConnected()=true");

    // C2: SetServerConnected(true)
    g_sm.SetServerConnected(true);
    Check(g_sm.IsServerConnected(),
          "C2: SetServerConnected(true) → IsServerConnected()=true");

    // C3: UpdateHeartbeat() → ยัง connected
    g_conn.UpdateHeartbeat();
    Check(g_conn.IsConnected(),
          "C3: UpdateHeartbeat() → ยัง IsConnected()=true");

    // C4: ForceDisconnect()
    g_conn.ForceDisconnect();
    Check(!g_conn.IsConnected(),
          "C4: ForceDisconnect() → IsConnected()=false");

    // C5: SetServerConnected(false)
    g_sm.SetServerConnected(false);
    Check(!g_sm.IsServerConnected(),
          "C5: SetServerConnected(false) → IsServerConnected()=false");

    // C6: EnableAllStandalone() → enabled > 0
    g_sm.EnableAllStandalone();
    int sa_cnt = g_sm.GetEnabledCount_V6();
    Check(sa_cnt > 0,
          Fmt("C6: EnableAllStandalone() → %d strategies enabled", sa_cnt));

    // C7: S15 Grid enabled หลัง EnableAllStandalone
    IStrategy* s15 = g_sm.GetStrategyByID(S15_GRID);
    bool s15_ok = (s15 != NULL && s15.IsStandaloneCapable() && s15.IsEnabled());
    Check(s15_ok, "C7: S15 Grid enabled in standalone mode");

    // C8: S01 ServerOnly → disabled
    IStrategy* s01 = g_sm.GetStrategyByID(S01_STAT_ARB);
    if(s01 != NULL && !s01.IsStandaloneCapable())
    {
        Check(!s01.IsEnabled(),
              "C8: S01 (ServerOnly) disabled in standalone");
    }
    else
    {
        Check(true, "C8: S01 standalone check skipped (IsStandaloneCapable=true)");
    }

    // C9: Reconnect
    g_conn.MarkInitialConnected();
    g_sm.SetServerConnected(true);
    Check(g_conn.IsConnected() && g_sm.IsServerConnected(),
          "C9: Reconnect — conn+SM กลับ online");

    // C10: DisableAllExcept([S07, S15])
    ENUM_STRATEGY_ID allowed[2];
    allowed[0] = S07_MEAN_REVERSION;
    allowed[1] = S15_GRID;
    g_sm.DisableAllExcept(allowed, 2);
    int ex_cnt = g_sm.GetEnabledCount_V6();
    Check(ex_cnt <= 2,
          Fmt("C10: DisableAllExcept([S07,S15]) → enabled=%d (≤2)", ex_cnt));
}


//=================================================================
// D: TRADE_REPORT Build (12-field CMsgPack)
//=================================================================
void Test_D_TradeReportBuild()
{
    Section("D: TRADE_REPORT Build (12-field CMsgPack)");

    // D1: Build — เหมือน ProgramC_Trader.mq5 line 887-906
    CMsgPack mp;
    mp.PackArray(12);
    mp.PackInt(100);
    mp.PackDouble(TimeCurrent() * 1000.0);
    mp.PackDouble(12345678.0);
    mp.PackString(_Symbol);
    mp.PackInt(0);
    mp.PackDouble(0.10);
    mp.PackDouble(2650.50);
    mp.PackDouble(2630.00);
    mp.PackDouble(2680.00);
    mp.PackDouble(150.25);
    mp.PackInt(GetMagicNumber(S01_STAT_ARB));
    mp.PackString("S01_P8_2_Test");

    uchar data[];
    mp.GetData(data);
    int sz = ArraySize(data);

    Check(sz > 0,
          Fmt("D1: CMsgPack serialized %d bytes", sz));

    // D2: size สมเหตุสมผล (12-field > 30 bytes)
    Check(sz >= 30,
          Fmt("D2: size=%d bytes >= 30", sz));

    // D3: byte[0] = 0x9C (fixarray 12)
    Check(ArraySize(data) > 0 && data[0] == 0x9C,
          Fmt("D3: byte[0]=0x%X (expect 0x9C=fixarray12)", (int)data[0]));

    // D4: มี non-zero bytes หลัง header
    bool has_content = false;
    for(int i = 1; i < sz; i++)
    {
        if(data[i] != 0x00)
        {
            has_content = true;
            break;
        }
    }
    Check(has_content, "D4: data มี non-zero content");

    // D5: LOSS trade format
    CMsgPack mp2;
    mp2.PackArray(12);
    mp2.PackInt(100);
    mp2.PackDouble(TimeCurrent() * 1000.0);
    mp2.PackDouble(99999.0);
    mp2.PackString(_Symbol);
    mp2.PackInt(1);
    mp2.PackDouble(0.10);
    mp2.PackDouble(2650.50);
    mp2.PackDouble(2670.00);
    mp2.PackDouble(2620.00);
    mp2.PackDouble(-75.50);
    mp2.PackInt(GetMagicNumber(S07_MEAN_REVERSION));
    mp2.PackString("S07_LOSS_Test");

    uchar data2[];
    mp2.GetData(data2);
    Check(ArraySize(data2) > 0,
          Fmt("D5: LOSS trade packed %d bytes", ArraySize(data2)));

    // D6: Magic numbers ต่างกัน
    Check(GetMagicNumber(S01_STAT_ARB) != GetMagicNumber(S07_MEAN_REVERSION),
          FmtII("D6: Magic S01=%d != S07=%d",
                GetMagicNumber(S01_STAT_ARB),
                GetMagicNumber(S07_MEAN_REVERSION)));

    // D7: GetData() คืนขนาดเดิม
    uchar data3[];
    mp.GetData(data3);
    Check(ArraySize(data3) == sz,
          Fmt("D7: GetData() คืนซ้ำได้ size=%d", ArraySize(data3)));

    // D8: ReceiveMessage(trade_data) ต้อง != 10 (ไม่ใช่ CONFIG_PUSH)
    int rt = g_recv.ReceiveMessage(data, sz);
    Check(rt != 10,
          Fmt("D8: ReceiveMessage(trade_data) != 10 (got %d)", rt));
}


//=================================================================
// E: Strategy Enable/Disable Lifecycle
//=================================================================
void Test_E_StrategyLifecycle()
{
    Section("E: Strategy Lifecycle");

    g_sm.SetServerConnected(false);
    g_sm.EnableAllStandalone();

    // E1: EnableStrategy_V6(S07)
    g_sm.EnableStrategy_V6(S07_MEAN_REVERSION);
    IStrategy* s07 = g_sm.GetStrategyByID(S07_MEAN_REVERSION);
    Check(s07 != NULL && s07.IsEnabled(),
          "E1: EnableStrategy_V6(S07) → IsEnabled()=true");

    // E2: DisableStrategy_V6(S07)
    g_sm.DisableStrategy_V6(S07_MEAN_REVERSION);
    Check(s07 != NULL && !s07.IsEnabled(),
          "E2: DisableStrategy_V6(S07) → IsEnabled()=false");

    // E3: Re-enable
    g_sm.EnableStrategy_V6(S07_MEAN_REVERSION);
    Check(s07 != NULL && s07.IsEnabled(),
          "E3: Re-EnableStrategy_V6(S07) → IsEnabled()=true");

    // E4: GetEnabledCount > 0
    int cnt = g_sm.GetEnabledCount_V6();
    Check(cnt > 0, Fmt("E4: GetEnabledCount_V6()=%d (>0)", cnt));

    // E5: FillStatusArray — ทุก entry initialized=true
    SStrategyStatusEntry arr[];
    int arr_cnt = 0;
    g_sm.FillStatusArray(arr, arr_cnt);
    bool all_init = true;
    for(int i = 0; i < arr_cnt; i++)
    {
        if(!arr[i].initialized)
        {
            all_init = false;
            break;
        }
    }
    Check(all_init,
          Fmt("E5: FillStatusArray — %d entries ทุกตัว initialized=true", arr_cnt));

    // E6: Deinit()
    g_sm.Deinit();
    Check(!g_sm.IsRegistered(),
          "E6: Deinit() → IsRegistered()=false");

    // E7: Re-register หลัง Deinit
    bool re_ok = g_sm.RegisterAllStrategies(_Symbol, PERIOD_M15);
    Check(re_ok,
          FmtS("E7: Re-Register หลัง Deinit: %s",
               re_ok ? "OK" : "FAILED"));
}


//=================================================================
// F: Global Helper Functions
//=================================================================
void Test_F_GlobalFunctions()
{
    Section("F: Global Helper Functions");

    // F1: GetMagicNumber() — ทุก strategy unique และ > 0
    int mag[16];
    bool unique = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        mag[i] = GetMagicNumber((ENUM_STRATEGY_ID)i);
        if(mag[i] <= 0) { unique = false; break; }
        for(int j = 0; j < i; j++)
        {
            if(mag[j] == mag[i]) { unique = false; break; }
        }
        if(!unique) break;
    }
    Check(unique, "F1: GetMagicNumber() — S01-S16 unique และ > 0");

    // F2: GetDefaultMM() ≥ 4 chars
    bool mm_ok = true;
    for(int i = 0; i < TOTAL_STRATEGIES; i++)
    {
        if(StringLen(GetDefaultMM((ENUM_STRATEGY_ID)i)) < 4)
        {
            mm_ok = false;
            break;
        }
    }
    Check(mm_ok, "F2: GetDefaultMM() — ทุก strategy คืน string ≥ 4 chars");

    // F3: GetRegimeAlignmentFactor() ∈ [0.3, 1.5]
    ENUM_MARKET_REGIME regs[5];
    regs[0] = REGIME_UNKNOWN;
    regs[1] = REGIME_RANGING;
    regs[2] = REGIME_TRENDING;
    regs[3] = REGIME_VOLATILE;
    regs[4] = REGIME_SQUEEZE;
    bool fac_ok = true;
    for(int i = 0; i < TOTAL_STRATEGIES && fac_ok; i++)
    {
        for(int r = 0; r < 5 && fac_ok; r++)
        {
            double f = GetRegimeAlignmentFactor((ENUM_STRATEGY_ID)i, regs[r]);
            if(f < 0.3 || f > 1.5) fac_ok = false;
        }
    }
    Check(fac_ok, "F3: GetRegimeAlignmentFactor() ∈ [0.3,1.5] ทุก strategy×regime");

    // F4: IsStandaloneStrategy — S15, S07
    Check(IsStandaloneStrategy(S15_GRID),
          "F4a: IsStandaloneStrategy(S15_GRID)=true");
    Check(IsStandaloneStrategy(S07_MEAN_REVERSION),
          "F4b: IsStandaloneStrategy(S07_MEAN_REVERSION)=true");

    // F5: GetStandaloneStrategiesForRegime(RANGING) ≥ 1
    ENUM_STRATEGY_ID sa_ids[];
    GetStandaloneStrategiesForRegime(REGIME_RANGING, sa_ids);
    Check(ArraySize(sa_ids) >= 1,
          Fmt("F5: GetStandaloneStrategiesForRegime(RANGING)=%d", ArraySize(sa_ids)));

    // F6: GetStrategyInfo(S01) — short_name ไม่ว่าง
    SStrategyInfo info = GetStrategyInfo(S01_STAT_ARB);
    Check(StringLen(info.short_name) > 0,
          FmtS("F6: GetStrategyInfo(S01).short_name='%s'", info.short_name));

    // F7: REGIME enum values (P8-1 lesson)
    Check(REGIME_UNKNOWN  == 0, "F7a: REGIME_UNKNOWN=0");
    Check(REGIME_TRENDING == 1, "F7b: REGIME_TRENDING=1");
    Check(REGIME_RANGING  == 2, "F7c: REGIME_RANGING=2");
    Check(REGIME_VOLATILE == 3, "F7d: REGIME_VOLATILE=3");
    Check(REGIME_SQUEEZE  == 4, "F7e: REGIME_SQUEEZE=4");

    // F8: TOTAL_STRATEGIES == 16
    Check(TOTAL_STRATEGIES == 16,
          Fmt("F8: TOTAL_STRATEGIES=%d (expect 16)", TOTAL_STRATEGIES));
}


//+------------------------------------------------------------------+
//| StringRep helper                                                 |
//+------------------------------------------------------------------+
string StringRep(string s, int n)
{
    string r = "";
    for(int i = 0; i < n; i++) r += s;
    return r;
}
//+------------------------------------------------------------------+
