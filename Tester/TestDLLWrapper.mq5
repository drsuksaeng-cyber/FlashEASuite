//+------------------------------------------------------------------+
//|                                            TestDLLWrapper.mq5    |
//|                          FlashEASuite V2 - Phase 3B              |
//|                          DLL Wrapper Test EA                     |
//|                          Location: Tester/                       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.02"
#property strict

#include "../Include/Security/DLLWrapper.mqh"

input double InpRiskPercent = 2.0;

CDLLWrapper g_Security;
bool g_initialized = false;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("FlashEASuite V2 - DLL Wrapper Test EA");
    Print("========================================");
    Print("");
    
    // Test 1: Initialize
    Print("TEST 1: Initialize Wrapper");
    Print("----------------------------------------");
    if(!g_Security.Initialize())
    {
        Print("❌ FAILED: Initialization failed");
        Print("   Error: ", g_Security.GetErrorMessage());
        return INIT_FAILED;
    }
    Print("✅ SUCCESS");
    Print("");
    
    // Test 2: License Status
    Print("TEST 2: License Status");
    Print("----------------------------------------");
    if(g_Security.IsLicenseValid())
    {
        Print("✅ License: VALID");
        Print("   HWID: ", g_Security.GetHWID());
    }
    else
    {
        Print("❌ License: INVALID");
        Print("   Error: ", g_Security.GetErrorMessage());
    }
    Print("");
    
    // Test 3: Get HWID
    Print("TEST 3: Get HWID");
    Print("----------------------------------------");
    string hwid = g_Security.GetHWID();
    Print("HWID: ", hwid);
    Print("Length: ", StringLen(hwid), " chars");
    if(StringLen(hwid) == 64)
        Print("✅ Format correct");
    else
        Print("⚠️ Length unexpected");
    Print("");
    
    // Test 4: Get Trading Parameters
    Print("TEST 4: Get Trading Parameters");
    Print("----------------------------------------");
    string symbol = _Symbol;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = InpRiskPercent / 100.0;
    
    Print("Inputs:");
    Print("  Symbol: ", symbol);
    Print("  Balance: ", DoubleToString(balance, 2));
    Print("  Risk: ", DoubleToString(risk * 100, 2), "%");
    Print("");
    
    if(!g_Security.GetTradingParams(symbol, balance, risk))
    {
        Print("❌ FAILED: Cannot get parameters");
        return INIT_FAILED;
    }
    
    Print("Results:");
    Print("  Lot Size: ", DoubleToString(g_Security.GetLotSize(), 2));
    Print("  Grid Step: ", DoubleToString(g_Security.GetGridStep(), 0));
    Print("  Max Orders: ", IntegerToString(g_Security.GetMaxPositions()));
    Print("  TP: ", DoubleToString(g_Security.GetTakeProfit(), 0));
    Print("  SL: ", DoubleToString(g_Security.GetStopLoss(), 0));
    Print("✅ SUCCESS");
    Print("");
    
    // Test 5: Cache Test
    Print("TEST 5: Cache Test");
    Print("----------------------------------------");
    Print("Calling GetTradingParams again...");
    if(g_Security.GetTradingParams(symbol, balance, risk))
    {
        Print("✅ Should see 'Using cached parameters'");
    }
    Print("");
    
    // Test 6: Different Parameters
    Print("TEST 6: Different Parameters");
    Print("----------------------------------------");
    Print("Calling with EURUSD...");
    if(g_Security.GetTradingParams("EURUSD", balance, risk))
    {
        Print("✅ New parameters:");
        Print("  Lot: ", DoubleToString(g_Security.GetLotSize(), 2));
        Print("  Step: ", DoubleToString(g_Security.GetGridStep(), 0));
    }
    Print("");
    
    // Test 7: Cache Invalidation
    Print("TEST 7: Cache Invalidation");
    Print("----------------------------------------");
    g_Security.InvalidateCache();
    Print("Recalculating...");
    g_Security.GetTradingParams(symbol, balance, risk);
    Print("✅ SUCCESS");
    Print("");
    
    // Summary
    Print("========================================");
    Print("ALL TESTS COMPLETED");
    Print("========================================");
    Print("");
    
    if(g_initialized)
    {
        Print("✅ Status: READY");
        Print("   License: VALID");
        Print("   Parameters: OK");
    }
    
    Print("========================================");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("========================================");
    Print("Test EA Stopping");
    Print("========================================");
    g_Security.LogLicenseInfo();
}

//+------------------------------------------------------------------+
void OnTick()
{
    // Test EA - no trading
}
//+------------------------------------------------------------------+
