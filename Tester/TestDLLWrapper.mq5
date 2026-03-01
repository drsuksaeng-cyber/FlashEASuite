//+------------------------------------------------------------------+
//|                                            TestDLLWrapper.mq5    |
//|                          FlashEASuite V2 — DLL Wrapper Test EA   |
//|                          Merged: v1.02 + P9-2                    |
//|                          Location: 03_Trader/                    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.00"
#property strict

// ✅ Comment out เมื่อมี FlashEA_Security.dll วางใน Libraries แล้ว
#define STUB_MODE

#include "../Include/Security/DLLWrapper.mqh"

input double InpRiskPercent = 2.0;  // Risk % (2.0 = 2%)

CDLLWrapper g_Security;
bool        g_initialized = false;
int         g_pass        = 0;
int         g_fail        = 0;
int         g_tick_count  = 0;

void CHECK(bool cond, string name)
{
   if(cond) { Print("  [PASS] ", name); g_pass++; }
   else     { Print("  [FAIL] ", name); g_fail++; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("FlashEASuite V2 - DLL Wrapper Test EA");
   Print("Version: 2.00 (v1.02 + P9-2 merged)");
   Print("========================================");
   Print("");
   g_pass = 0; g_fail = 0;

   //──────────────────────────────────────────────────────────────
   // BLOCK A — Tests เดิม v1.02
   //──────────────────────────────────────────────────────────────

   // Test 1: Initialize
   Print("TEST 1: Initialize Wrapper");
   Print("----------------------------------------");
   if(!g_Security.Initialize())
   {
      Print("[FAIL] Initialization failed");
      Print("   Error: ", g_Security.GetErrorMessage());
      return(INIT_FAILED);
   }
   g_pass++;
   Print("[PASS] Initialize");
   Print("");

   // Test 2: License Status
   Print("TEST 2: License Status");
   Print("----------------------------------------");
   if(g_Security.IsLicenseValid())
   {
      Print("[PASS] License: VALID");
      Print("   HWID: ", StringSubstr(g_Security.GetHWID(), 0, 24), "...");
   }
   else
   {
      Print("[INFO] License: INVALID — Error: ", g_Security.GetErrorMessage());
   }
   CHECK(g_Security.IsInitialized(),  "IsInitialized() = true");
   CHECK(g_Security.IsLicenseValid(), "IsLicenseValid() = true");
   Print("");

   // Test 3: Get HWID
   Print("TEST 3: Get HWID");
   Print("----------------------------------------");
   string hwid = g_Security.GetHWID();
   Print("   Length: ", StringLen(hwid), " chars");
   // LIVE: SHA256 = 64 chars | STUB: >= 20 chars
   CHECK(StringLen(hwid) >= 20, "HWID length >= 20");
   if(StringLen(hwid) == 64)
      Print("   Format: Live SHA256 (64 chars)");
   else
      Print("   Format: Stub (", StringLen(hwid), " chars — ok in STUB_MODE)");
   Print("");

   // Test 4: Get Trading Parameters (v1.02 fraction API)
   Print("TEST 4: Get Trading Parameters");
   Print("----------------------------------------");
   string symbol  = _Symbol;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = InpRiskPercent / 100.0;  // 2.0 → 0.02 fraction

   Print("   Symbol: ", symbol);
   Print("   Balance: ", DoubleToString(balance, 2));
   Print("   Risk: ", DoubleToString(risk * 100.0, 2), "% (fraction=", DoubleToString(risk, 4), ")");

   if(!g_Security.GetTradingParams(symbol, balance, risk))
   {
      Print("[FAIL] Cannot get parameters");
      return(INIT_FAILED);
   }
   g_pass++;

   Print("   Results:");
   Print("     Lot Size: ",    DoubleToString(g_Security.GetLotSize(), 2));
   Print("     Grid Step: ",   DoubleToString(g_Security.GetGridStep(), 0));
   Print("     Max Orders: ",  IntegerToString(g_Security.GetMaxPositions()));
   Print("     TP: ",          DoubleToString(g_Security.GetTakeProfit(), 0), " points");
   Print("     SL: ",          DoubleToString(g_Security.GetStopLoss(), 0), " points");

   CHECK(g_Security.GetLotSize()      >= 0.01,  "LotSize >= 0.01");
   CHECK(g_Security.GetLotSize()      <= 1.00,  "LotSize <= 1.00");
   CHECK(g_Security.GetGridStep()     == 100.0, "GridStep == 100");
   CHECK(g_Security.GetMaxPositions() >= 1,     "MaxPositions >= 1");
   CHECK(g_Security.GetTakeProfit()   > 0,      "TakeProfit > 0");
   CHECK(g_Security.GetStopLoss()     > 0,      "StopLoss > 0");
   Print("");

   // Test 5: Cache Test
   Print("TEST 5: Cache Test (same params)");
   Print("----------------------------------------");
   Print("   Calling GetTradingParams again — expect cache hit...");
   CHECK(g_Security.GetTradingParams(symbol, balance, risk),
         "Second call (cache hit) = true");
   Print("");

   // Test 6: Different Symbol
   Print("TEST 6: Different Symbol (EURUSD)");
   Print("----------------------------------------");
   if(g_Security.GetTradingParams("EURUSD", balance, risk))
   {
      g_pass++;
      Print("[PASS] EURUSD Lot=", DoubleToString(g_Security.GetLotSize(), 2));
   }
   Print("");

   // Test 7: Cache Invalidation
   Print("TEST 7: Cache Invalidation");
   Print("----------------------------------------");
   g_Security.InvalidateCache();
   CHECK(g_Security.GetTradingParams(symbol, balance, risk),
         "Recalculate after invalidate = true");
   Print("");

   //──────────────────────────────────────────────────────────────
   // BLOCK B — P9-2 New Tests
   //──────────────────────────────────────────────────────────────

   Print("TEST 8: ValidatePolicy — basic");
   Print("----------------------------------------");
   string mjson = "{\"symbol\":\"XAUUSD\",\"sequence\":1,\"timestamp\":0}";
   CHECK(g_Security.ValidatePolicy(mjson), "ValidatePolicy basic = true");
   Print("");

   Print("TEST 9: ValidatePolicy — timestamp + sequence");
   Print("----------------------------------------");
   long now_ts = TimeCurrent();
   CHECK(g_Security.ValidatePolicy(mjson, now_ts, 100),
         "ValidatePolicy(now, seq=100) = true");
   CHECK(g_Security.GetLastSequence() == 100, "GetLastSequence() == 100");
   Print("");

   Print("TEST 10: Anti-Replay protection");
   Print("----------------------------------------");
   long old_ts = TimeCurrent() - 400;
   CHECK(!g_Security.ValidatePolicy(mjson, old_ts, 200),
         "REJECT: timestamp too old (400s > 300s)");
   CHECK(!g_Security.ValidatePolicy(mjson, TimeCurrent(), 50),
         "REJECT: sequence replay (50 < 100)");
   CHECK(g_Security.ValidatePolicy(mjson, TimeCurrent(), 200),
         "ACCEPT: next sequence (200 > 100)");
   CHECK(g_Security.GetLastSequence() == 200, "GetLastSequence() == 200");
   Print("");

   Print("TEST 11: VerifyPolicySignature (alias)");
   Print("----------------------------------------");
   CHECK(g_Security.VerifyPolicySignature(mjson),
         "VerifyPolicySignature alias = true");
   Print("");

   Print("TEST 12: ChallengeDLL");
   Print("----------------------------------------");
   CHECK(g_Security.ChallengeDLL(),               "ChallengeDLL() = true");
   CHECK(g_Security.GetChallengeFailures() == 0,  "ChallengeFailures = 0");
   Print("");

   Print("TEST 13: PeriodicVerification");
   Print("----------------------------------------");
   CHECK(g_Security.PeriodicVerification(), "First call = true");
   CHECK(g_Security.PeriodicVerification(), "Second call (skip) = true");
   Print("");

   Print("TEST 14: RecheckLicense");
   Print("----------------------------------------");
   CHECK(g_Security.RecheckLicense(), "RecheckLicense() = true");
   Print("");

   Print("TEST 15: IsStubMode");
   Print("----------------------------------------");
   CHECK(g_Security.IsStubMode(), "IsStubMode() = true (STUB_MODE defined)");
   Print("");

   Print("TEST 16: LogLicenseInfo");
   Print("----------------------------------------");
   g_Security.LogLicenseInfo();
   g_pass++;
   Print("");

   //──────────────────────────────────────────────────────────────
   // Summary
   //──────────────────────────────────────────────────────────────
   Print("========================================");
   Print("RESULTS: ", g_pass, " PASS | ", g_fail, " FAIL");
   if(g_fail == 0)
      Print("ALL TESTS PASSED");
   else
      Print(g_fail, " TEST(S) FAILED — ดู log ด้านบน");
   Print("========================================");
   Print("");

   g_initialized = g_Security.IsLicenseValid();
   return(INIT_SUCCEEDED);
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
   g_tick_count++;
   // ทดสอบ PeriodicVerification ทุก 30 tick
   if(g_tick_count % 30 == 0)
   {
      if(!g_Security.PeriodicVerification())
         Print("[SECURITY] PeriodicVerification FAILED — would stop EA in production");
   }
}
//+------------------------------------------------------------------+
