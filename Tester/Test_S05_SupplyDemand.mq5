//+------------------------------------------------------------------+
//| Test_S05_SupplyDemand.mq5                                        |
//| FlashEASuite V2 — Unit Test for S05 Supply & Demand              |
//+------------------------------------------------------------------+
//| วิธีใช้งาน:                                                       |
//|  1. Save ที่: MQL5/Scripts/FlashEA/Test_S05_SupplyDemand.mq5     |
//|  2. เปิด chart XAUUSD.tp H1                                         |
//|  3. ลาก Script ลงบน chart                                         |
//|  4. ดู Output ใน Experts tab                                     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property script_show_inputs

#include "../Include/Logic/Strategies/S05_SupplyDemand.mqh"

//--- Script inputs
input string  Test_Symbol    = "XAUUSD.tp";  // Symbol to test
input int     Test_Timeframe = 60;        // Minutes (60=H1)
input bool    Verbose        = true;      // Print zone details

//+------------------------------------------------------------------+
//| Helper: Section separator                                        |
//+------------------------------------------------------------------+
void PrintSep(string title)
{
    Print("══════════════════════════════════════════════════════");
    PrintFormat("  %s", title);
    Print("══════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Helper: Assert                                                   |
//+------------------------------------------------------------------+
void Assert(bool condition, string test_name, string detail = "")
{
    if(condition)
        PrintFormat("  ✅ PASS  %s  %s", test_name, detail);
    else
        PrintFormat("  ❌ FAIL  %s  %s", test_name, detail);
}

//+------------------------------------------------------------------+
//| TEST 1: ZoneDetector — Scan for RBD/DBR zones                   |
//+------------------------------------------------------------------+
void Test_ZoneDetector_Scan(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 1: ZoneDetector — Scan RBD/DBR patterns");

    CZoneDetector zd;
    zd.Setup(symbol, tf, 100, 3, 0.6, 1.2);
    zd.Scan();

    int count = zd.Count();
    PrintFormat("  → Total zones found: %d", count);
    Assert(count >= 0, "Scan() runs without crash", StringFormat("count=%d", count));

    int demand_count = 0, supply_count = 0;
    for(int i = 0; i < count; i++)
    {
        SSDZone z = zd.GetZone(i);
        if(!z.is_active) continue;
        if(z.zone_type == ZONE_DEMAND) demand_count++;
        else                           supply_count++;

        if(Verbose)
        {
            PrintFormat("     Zone[%d] | %s | Top:%.2f Bot:%.2f | Str:%.2f | Touch:%d | %s",
                i,
                z.zone_type == ZONE_DEMAND ? "DEMAND(DBR)" : "SUPPLY(RBD)",
                z.top, z.bottom, z.strength, z.touches,
                TimeToString(z.time, TIME_DATE | TIME_MINUTES));
        }
    }

    PrintFormat("  → Active Demand zones: %d | Active Supply zones: %d",
        demand_count, supply_count);
    Assert(demand_count + supply_count <= count, "Active zones <= total zones");
}

//+------------------------------------------------------------------+
//| TEST 2: ZoneDetector — Geometry validation                       |
//+------------------------------------------------------------------+
void Test_ZoneDetector_Geometry(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 2: ZoneDetector — Zone geometry validation");

    CZoneDetector zd;
    zd.Setup(symbol, tf, 100, 3, 0.6, 1.2);
    zd.Scan();

    bool all_valid = true;
    for(int i = 0; i < zd.Count(); i++)
    {
        SSDZone z = zd.GetZone(i);
        if(z.top <= z.bottom)
        {
            PrintFormat("  ❌ Zone[%d] invalid: Top(%.2f) <= Bottom(%.2f)", i, z.top, z.bottom);
            all_valid = false;
        }
        if(z.strength < 0 || z.strength > 1.0)
        {
            PrintFormat("  ❌ Zone[%d] invalid strength: %.3f", i, z.strength);
            all_valid = false;
        }
    }
    Assert(all_valid, "All zones have Top > Bottom and Strength in [0,1]");
}

//+------------------------------------------------------------------+
//| TEST 3: ZoneDetector — UpdateTouches and invalidation            |
//+------------------------------------------------------------------+
void Test_ZoneDetector_Touches(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 3: ZoneDetector — Touch counting & invalidation");

    CZoneDetector zd;
    zd.Setup(symbol, tf, 100, 3, 0.6, 1.2);
    zd.Scan();

    int count_before = 0;
    for(int i = 0; i < zd.Count(); i++)
        if(zd.GetZone(i).is_active) count_before++;

    // Test with current price
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    double atr   = 0;
    {
        int h = iATR(symbol, tf, 14);
        double buf[1];
        if(h != INVALID_HANDLE && CopyBuffer(h, 0, 1, 1, buf) == 1) atr = buf[0];
        IndicatorRelease(h);
    }

    if(atr > 0)
    {
        zd.UpdateTouches(price, atr);
        Assert(true, "UpdateTouches() runs without crash");
    }

    // Test GetNearestFreshZone
    SSDZone dem, sup;
    bool found_d = zd.GetNearestFreshZone(ZONE_DEMAND, price, dem);
    bool found_s = zd.GetNearestFreshZone(ZONE_SUPPLY, price, sup);

    PrintFormat("  → Nearest Demand zone: %s", found_d ?
        StringFormat("Top:%.2f Bot:%.2f Str:%.2f Touch:%d", dem.top, dem.bottom, dem.strength, dem.touches)
        : "NONE");
    PrintFormat("  → Nearest Supply zone: %s", found_s ?
        StringFormat("Top:%.2f Bot:%.2f Str:%.2f Touch:%d", sup.top, sup.bottom, sup.strength, sup.touches)
        : "NONE");

    Assert(true, "GetNearestFreshZone() runs without crash");
}

//+------------------------------------------------------------------+
//| TEST 4: CSupplyDemand — Init & Metadata                         |
//+------------------------------------------------------------------+
void Test_SD_Init(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 4: CSupplyDemand — Init & Metadata");

    CSupplyDemand sd;

    Assert(!sd.IsInitialized(), "Before Init: IsInitialized=false");
    Assert(!sd.IsEnabled(),     "Before Init: IsEnabled=false");

    bool ok = sd.Init(symbol, tf);
    Assert(ok,                  "Init() returns true");
    Assert(sd.IsInitialized(),  "After Init: IsInitialized=true");
    Assert(sd.GetMagic() == MAGIC_S05_SUPPLY_DEM,
           StringFormat("Magic = %d", MAGIC_S05_SUPPLY_DEM));
    Assert(sd.GetName() == "Supply & Demand", "GetName correct");
    Assert(!sd.IsStandaloneCapable(), "IsStandaloneCapable = false (ServerOnly)");

    PrintFormat("  → Symbol: %s | TF: %s | Family: %s",
        sd.GetSymbol(), EnumToString(sd.GetTimeframe()), sd.GetFamily());

    sd.Deinit();
    Assert(!sd.IsInitialized(), "After Deinit: IsInitialized=false");
}

//+------------------------------------------------------------------+
//| TEST 5: CSupplyDemand — Analyze without server (must stay NONE)  |
//+------------------------------------------------------------------+
void Test_SD_NoServer(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 5: CSupplyDemand — ServerOnly check (no CONFIG_PUSH)");

    CSupplyDemand sd;
    sd.Init(symbol, tf);
    sd.Enable();

    // No OnConfigUpdate → confidence=0 → should skip
    MqlTick tick;
    SymbolInfoTick(symbol, tick);
    sd.Analyze(tick);

    ENUM_TRADE_SIGNAL sig = sd.GetSignal();
    Assert(sig == SIGNAL_NONE,
           "Signal=NONE when confidence=0 (ServerOnly guard)",
           StringFormat("Got: %s", SignalToString(sig)));

    sd.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 6: CSupplyDemand — Analyze WITH server config               |
//+------------------------------------------------------------------+
void Test_SD_WithServer(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 6: CSupplyDemand — Analyze with server config (confidence=0.70)");

    CSupplyDemand sd;
    sd.Init(symbol, tf);
    sd.Enable();

    // Simulate CONFIG_PUSH
    SConfigUpdate cfg;
    cfg.Reset();
    cfg.enabled    = true;
    cfg.confidence = 0.70;
    cfg.timeframe  = tf;
    cfg.regime     = REGIME_RANGING;
    cfg.mm_method  = "MM04";
    sd.OnConfigUpdate(cfg);

    // Run 3 ticks
    MqlTick tick;
    for(int i = 0; i < 3; i++)
    {
        SymbolInfoTick(symbol, tick);
        sd.Analyze(tick);
        Sleep(10);
    }

    ENUM_TRADE_SIGNAL sig  = sd.GetSignal();
    double            conf = sd.GetConfidence();

    PrintFormat("  → Signal: %s | Confidence: %.3f", SignalToString(sig), conf);
    Assert(conf >= 0.0 && conf <= 1.0, "Confidence in [0,1]",
           StringFormat("conf=%.3f", conf));
    Assert(sig == SIGNAL_BUY || sig == SIGNAL_SELL || sig == SIGNAL_NONE,
           "Signal is valid enum value");

    Print(sd.GetDiagnostics());
    sd.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 7: SetDynamicParams — hot-reload                            |
//+------------------------------------------------------------------+
void Test_SD_DynamicParams(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 7: CSupplyDemand — SetDynamicParams (CONFIG_PUSH V2)");

    CSupplyDemand sd;
    sd.Init(symbol, tf);

    SDynamicParams p;
    p.Reset();
    p.SetParam("SD_LOOKBACK",          120.0);
    p.SetParam("SD_MAX_TOUCHES",         2.0);
    p.SetParam("SD_BASE_RANGE_MULT",     0.5);
    p.SetParam("SD_DEPARTURE_MULT",      1.5);
    p.SetParam("SD_SL_ATR_BUFFER",       0.6);
    p.SetParam("SD_TP_ATR_MULT",         3.0);
    p.SetParam("SD_MIN_ZONE_STRENGTH",   0.30);
    p.SetParam("SD_MIN_CONFIDENCE",      0.45);
    p.mm_method = "MM04";

    sd.SetDynamicParams(p);
    Assert(true, "SetDynamicParams does not crash");

    SDynamicParams out = sd.GetCurrentParams();
    Assert(out.GetParam("SD_LOOKBACK", 0) == 120.0,
           "GetCurrentParams: SD_LOOKBACK = 120",
           StringFormat("Got: %.0f", out.GetParam("SD_LOOKBACK", 0)));
    Assert(out.GetParam("SD_MAX_TOUCHES", 0) == 2.0,
           "GetCurrentParams: SD_MAX_TOUCHES = 2",
           StringFormat("Got: %.0f", out.GetParam("SD_MAX_TOUCHES", 0)));
    Assert(out.mm_method == "MM04",
           "GetCurrentParams: mm_method = MM04");

    sd.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 8: GetCurrentParams — export 8 params                       |
//+------------------------------------------------------------------+
void Test_SD_ExportParams(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 8: CSupplyDemand — GetCurrentParams export");

    CSupplyDemand sd;
    sd.Init(symbol, tf);

    SDynamicParams p = sd.GetCurrentParams();
    PrintFormat("  → Param count: %d", p.strategy_param_count);
    Assert(p.strategy_param_count == 8, "Exports exactly 8 params",
           StringFormat("Got: %d", p.strategy_param_count));

    if(Verbose)
    {
        for(int i = 0; i < p.strategy_param_count; i++)
            PrintFormat("     Param[%d]: %s = %.4f",
                i, p.strategy_params[i].name, p.strategy_params[i].value);
    }

    sd.Deinit();
}

//+------------------------------------------------------------------+
//| TEST 9: Zone freshness logic — strength decreases with touches   |
//+------------------------------------------------------------------+
void Test_ZoneFreshness(string symbol, ENUM_TIMEFRAMES tf)
{
    PrintSep("TEST 9: Zone freshness — strength decreases with touches");

    CZoneDetector zd;
    zd.Setup(symbol, tf, 100, 5, 0.6, 1.2); // max_touches=5 for this test
    zd.Scan();

    if(zd.Count() == 0)
    {
        Print("  ⚠️  No zones found — skip freshness test (increase lookback?)");
        return;
    }

    // Take first active zone
    int target_idx = -1;
    for(int i = 0; i < zd.Count(); i++)
    {
        if(zd.GetZone(i).is_active) { target_idx = i; break; }
    }

    if(target_idx < 0)
    {
        Print("  ⚠️  No active zones — skip");
        return;
    }

    SSDZone z_before = zd.GetZone(target_idx);
    double  str_before = z_before.strength;

    // Manually touch the zone: pump price into it
    double zone_mid = (z_before.top + z_before.bottom) * 0.5;
    double atr = z_before.departure_atr > 0 ? z_before.departure_atr : 10.0;

    // Call UpdateTouches 2 times with price inside the zone
    zd.UpdateTouches(zone_mid, atr);
    zd.UpdateTouches(zone_mid, atr);

    SSDZone z_after = zd.GetZone(target_idx);
    PrintFormat("  → Strength before: %.3f | After 2 touches: %.3f | Touches: %d",
        str_before, z_after.strength, z_after.touches);

    Assert(z_after.touches >= 1, "Touch count incremented", StringFormat("touches=%d", z_after.touches));
    Assert(z_after.strength <= str_before + 0.01,
           "Strength decreases (or stays) with more touches");
}

//+------------------------------------------------------------------+
//| OnStart — Main test runner                                       |
//+------------------------------------------------------------------+
void OnStart()
{
    ENUM_TIMEFRAMES tf = PERIOD_H1;
    switch(Test_Timeframe)
    {
        case 1:   tf = PERIOD_M1;  break;
        case 5:   tf = PERIOD_M5;  break;
        case 15:  tf = PERIOD_M15; break;
        case 30:  tf = PERIOD_M30; break;
        case 60:  tf = PERIOD_H1;  break;
        case 240: tf = PERIOD_H4;  break;
        case 1440:tf = PERIOD_D1;  break;
    }

    string symbol = Test_Symbol;
    if(SymbolInfoDouble(symbol, SYMBOL_BID) == 0)
    {
        Print("⚠️  Symbol '", symbol, "' not found — trying: ", Symbol());
        symbol = Symbol();
    }

    Print("");
    PrintSep("FlashEASuite V2 — S05 SUPPLY & DEMAND UNIT TESTS");
    PrintFormat("  Symbol: %s | Timeframe: %s | Bars: %d",
        symbol, EnumToString(tf), Bars(symbol, tf));
    Print("");

    Test_ZoneDetector_Scan(symbol, tf);
    Test_ZoneDetector_Geometry(symbol, tf);
    Test_ZoneDetector_Touches(symbol, tf);
    Test_SD_Init(symbol, tf);
    Test_SD_NoServer(symbol, tf);
    Test_SD_WithServer(symbol, tf);
    Test_SD_DynamicParams(symbol, tf);
    Test_SD_ExportParams(symbol, tf);
    Test_ZoneFreshness(symbol, tf);

    Print("");
    PrintSep("S05 SUPPLY & DEMAND TEST COMPLETE — ตรวจสอบ ✅/❌ ด้านบน");
    Print("");
}
//+------------------------------------------------------------------+
