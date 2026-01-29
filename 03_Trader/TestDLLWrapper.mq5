//+------------------------------------------------------------------+
//|                                TestDLLWrapper.mq5                |
//|                          FlashEASuite V2 - Phase 3               |
//|                          DLL Wrapper Testing (FIXED)             |
//+------------------------------------------------------------------+

#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.01"
#property strict

#include "../Include/Security/DLLWrapper.mqh"

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CDLLWrapper g_dll_wrapper;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("═══════════════════════════════════════════════════════════");
   Print("  FlashEASuite V2 - DLL Wrapper Test");
   Print("  Phase 3: Testing DLL Functions");
   Print("  Version: 1.01 (Fixed License Path)");
   Print("═══════════════════════════════════════════════════════════");
   
   // Get full path to license file
   string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
   string license_filename = "License.key";
   string full_license_path = terminal_path + "\\MQL5\\Files\\" + license_filename;
   
   Print("📂 Paths:");
   Print("   Terminal: ", terminal_path);
   Print("   License:  ", full_license_path);
   
   // Check if license exists (in MQL5/Files/)
   if(!FileIsExist(license_filename))
     {
      Print("⚠️ License file not found in MQL5/Files/");
      Print("   Looking for: ", license_filename);
      Print("   Proceeding with direct DLL tests...\n");
      
      // Run direct DLL tests without license
      RunDirectDLLTests();
      return INIT_SUCCEEDED;
     }
   
   Print("✅ License file found");
   
   // Initialize DLL wrapper with FULL PATH
   if(!g_dll_wrapper.Initialize(full_license_path))
     {
      Print("❌ DLL Wrapper initialization failed!");
      Print("\n═══════════════════════════════════════════════════════════");
      Print("  DLL Wrapper Test completed");
      Print("═══════════════════════════════════════════════════════════");
      return INIT_FAILED;
     }
   
   Print("\n✅ DLL Wrapper initialized successfully!\n");
   
   // Run tests after 2 seconds
   EventSetTimer(2);
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("\n═══════════════════════════════════════════════════════════");
   Print("  DLL Wrapper Test completed");
   Print("═══════════════════════════════════════════════════════════");
  }

//+------------------------------------------------------------------+
//| Timer function - Run tests                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {
   EventKillTimer(); // Run once
   
   RunWrapperTests();
  }

//+------------------------------------------------------------------+
//| Run Direct DLL Tests (without license file)                       |
//+------------------------------------------------------------------+
void RunDirectDLLTests()
  {
   Print("\n🧪 Running Direct DLL Tests...\n");
   
   // Test 1: HWID Generation
   Print("─────────────────────────────────────");
   Print("TEST 1: HWID Generation");
   
   string hwid = "";
   GetHWID(hwid);
   
   if(StringLen(hwid) > 0)
     {
      Print("✅ PASSED - HWID generated");
      Print("   HWID: ", hwid);
      Print("   Length: ", StringLen(hwid), " chars");
     }
   else
     {
      Print("❌ FAILED - HWID empty");
     }
   
   // Test 2: DLL Integrity
   Print("\n─────────────────────────────────────");
   Print("TEST 2: DLL Integrity Check");
   
   int integrity_result = VerifyDLLIntegrity();
   if(integrity_result == 1)
     {
      Print("✅ PASSED - DLL integrity verified");
     }
   else
     {
      Print("❌ FAILED - DLL integrity check failed");
     }
   
   // Test 3: Trading Params (should fail without valid license)
   Print("\n─────────────────────────────────────");
   Print("TEST 3: Trading Params (Expected to REJECT without license)");
   
   // Get full path for testing
   string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
   string fake_license = terminal_path + "\\MQL5\\Files\\License.key";
   
   TradingParams params;
   InitTradingParams(params);
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int result = CalculateTradingParams(fake_license, "XAUUSD", balance, params);
   
   if(result == 0)
     {
      Print("✅ PASSED - Correctly rejected (no valid license)");
     }
   else
     {
      Print("⚠️ WARNING - Accepted without license (security issue!)");
      PrintTradingParams(params);
     }
   
   Print("\n─────────────────────────────────────");
   Print("All direct tests completed");
  }

//+------------------------------------------------------------------+
//| Run Wrapper Tests (with initialized wrapper)                     |
//+------------------------------------------------------------------+
void RunWrapperTests()
  {
   Print("\n🧪 Running Wrapper Tests...\n");
   
   // Test 1: Get HWID
   Print("─────────────────────────────────────");
   Print("TEST 1: Get System HWID");
   
   string hwid = g_dll_wrapper.GetSystemHWID();
   if(StringLen(hwid) > 0)
     {
      Print("✅ PASSED");
      Print("   HWID: ", hwid);
     }
   else
     {
      Print("❌ FAILED - HWID empty");
     }
   
   // Test 2: Get Trading Parameters
   Print("\n─────────────────────────────────────");
   Print("TEST 2: Get Trading Parameters");
   
   TradingParams params;
   if(g_dll_wrapper.GetTradingParams("XAUUSD", params))
     {
      Print("✅ PASSED");
      PrintTradingParams(params);
     }
   else
     {
      Print("❌ FAILED - Could not get trading params");
     }
   
   // Test 3: Verify Policy Signature (stub test)
   Print("\n─────────────────────────────────────");
   Print("TEST 3: Verify Policy Signature");
   
   string test_policy = "{\"symbol\":\"XAUUSD\",\"strategy\":\"Grid\"}";
   string test_pubkey = "test_public_key";
   
   if(g_dll_wrapper.VerifyPolicySignature(test_policy, test_pubkey))
     {
      Print("✅ PASSED (stub)");
     }
   else
     {
      Print("❌ FAILED");
     }
   
   // Test 4: DLL Integrity
   Print("\n─────────────────────────────────────");
   Print("TEST 4: DLL Integrity Check");
   
   if(g_dll_wrapper.CheckDLLIntegrity())
     {
      Print("✅ PASSED");
     }
   else
     {
      Print("❌ FAILED");
     }
   
   // Test 5: Periodic Challenge
   Print("\n─────────────────────────────────────");
   Print("TEST 5: Periodic Challenge (Anti-Mock)");
   
   if(g_dll_wrapper.PeriodicChallenge())
     {
      Print("✅ PASSED - DLL is authentic");
     }
   else
     {
      Print("❌ FAILED - DLL may be fake/mock");
     }
   
   Print("\n─────────────────────────────────────");
   Print("All wrapper tests completed");
  }

//+------------------------------------------------------------------+