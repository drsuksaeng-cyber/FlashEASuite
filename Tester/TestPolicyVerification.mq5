//+------------------------------------------------------------------+
//|                                     TestPolicyVerification.mq5   |
//|                          FlashEASuite V2 - Phase 2 Testing       |
//|                          Test Policy Verification Modules        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include "../Include/Network/PolicyVerifier.mqh"
#include "../Include/Logic/PolicyManager.mqh"

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CPolicyVerifier g_verifier;
CPolicyManager g_policy_mgr;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("═══════════════════════════════════════════════════════════");
   Print("  FlashEASuite V2 - Policy Verification Test");
   Print("  Phase 2: Security Module Testing");
   Print("═══════════════════════════════════════════════════════════");
   
   // Initialize PolicyManager (which includes PolicyVerifier)
   if(!g_policy_mgr.Initialize())
     {
      Print("❌ PolicyManager initialization failed");
      return INIT_FAILED;
     }
   
   Print("✅ PolicyManager initialized");
   
   // Run tests
   Print("\n🧪 Starting Policy Verification Tests...\n");
   
   RunAllTests();
   
   Print("\n═══════════════════════════════════════════════════════════");
   Print("  Test Complete - Check logs above");
   Print("═══════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Test EA stopped");
  }

//+------------------------------------------------------------------+
//| Run all verification tests                                        |
//+------------------------------------------------------------------+
void RunAllTests()
  {
   int passed = 0;
   int failed = 0;
   
   // Test 1: Valid policy
   Print("─────────────────────────────────────");
   Print("TEST 1: Valid Policy (should PASS)");
   if(TestValidPolicy())
     {
      Print("✅ TEST 1 PASSED");
      passed++;
     }
   else
     {
      Print("❌ TEST 1 FAILED");
      failed++;
     }
   
   // Test 2: Old timestamp (> 5 min)
   Print("\n─────────────────────────────────────");
   Print("TEST 2: Old Timestamp (should REJECT)");
   if(TestOldTimestamp())
     {
      Print("✅ TEST 2 PASSED");
      passed++;
     }
   else
     {
      Print("❌ TEST 2 FAILED");
      failed++;
     }
   
   // Test 3: Future timestamp (> 1 min)
   Print("\n─────────────────────────────────────");
   Print("TEST 3: Future Timestamp (should REJECT)");
   if(TestFutureTimestamp())
     {
      Print("✅ TEST 3 PASSED");
      passed++;
     }
   else
     {
      Print("❌ TEST 3 FAILED");
      failed++;
     }
   
   // Test 4: Duplicate nonce
   Print("\n─────────────────────────────────────");
   Print("TEST 4: Duplicate Nonce (should REJECT)");
   if(TestDuplicateNonce())
     {
      Print("✅ TEST 4 PASSED");
      passed++;
     }
   else
     {
      Print("❌ TEST 4 FAILED");
      failed++;
     }
   
   // Test 5: Out-of-order sequence
   Print("\n─────────────────────────────────────");
   Print("TEST 5: Out-of-Order Sequence (should REJECT)");
   if(TestOutOfOrderSequence())
     {
      Print("✅ TEST 5 PASSED");
      passed++;
     }
   else
     {
      Print("❌ TEST 5 FAILED");
      failed++;
     }
   
   // Summary
   Print("\n═══════════════════════════════════════");
   Print("TEST SUMMARY");
   Print("═══════════════════════════════════════");
   Print("Tests Passed: ", passed, " / ", (passed + failed));
   Print("Tests Failed: ", failed, " / ", (passed + failed));
   
   if(failed == 0)
      Print("🎉 ALL TESTS PASSED!");
   else
      Print("⚠️ SOME TESTS FAILED - Review logs above");
  }

//+------------------------------------------------------------------+
//| Test 1: Valid policy should be accepted                          |
//+------------------------------------------------------------------+
bool TestValidPolicy()
  {
   CPolicyVerifier verifier;
   if(!verifier.Initialize("server_public.pem"))
      return false;
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "valid_sig_base64";
   string symbol = "XAUUSD";
   long sequence = 1;
   string nonce = "550e8400-e29b-41d4-a716-446655440000";
   datetime timestamp = TimeCurrent();
   string error;
   
   bool result = verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error
   );
   
   return result;  // Should return true
  }

//+------------------------------------------------------------------+
//| Test 2: Old timestamp should be rejected                         |
//+------------------------------------------------------------------+
bool TestOldTimestamp()
  {
   CPolicyVerifier verifier;
   if(!verifier.Initialize("server_public.pem"))
      return false;
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "valid_sig_base64";
   string symbol = "XAUUSD";
   long sequence = 2;
   string nonce = "550e8400-e29b-41d4-a716-446655440001";
   datetime timestamp = TimeCurrent() - 400;  // 400 seconds old (> 5 min)
   string error;
   
   bool result = verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error
   );
   
   return !result;  // Should return false (rejected)
  }

//+------------------------------------------------------------------+
//| Test 3: Future timestamp should be rejected                      |
//+------------------------------------------------------------------+
bool TestFutureTimestamp()
  {
   CPolicyVerifier verifier;
   if(!verifier.Initialize("server_public.pem"))
      return false;
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "valid_sig_base64";
   string symbol = "XAUUSD";
   long sequence = 3;
   string nonce = "550e8400-e29b-41d4-a716-446655440002";
   datetime timestamp = TimeCurrent() + 120;  // 120 seconds in future
   string error;
   
   bool result = verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error
   );
   
   return !result;  // Should return false (rejected)
  }

//+------------------------------------------------------------------+
//| Test 4: Duplicate nonce should be rejected                       |
//+------------------------------------------------------------------+
bool TestDuplicateNonce()
  {
   CPolicyVerifier verifier;
   if(!verifier.Initialize("server_public.pem"))
      return false;
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "valid_sig_base64";
   string symbol = "XAUUSD";
   string nonce = "550e8400-DUPLICATE-TEST";
   datetime timestamp = TimeCurrent();
   string error;
   
   // First policy - should pass
   bool first = verifier.VerifyPolicy(
      policy_json, signature, symbol, 4, nonce, timestamp, error
   );
   
   // Second policy with SAME nonce - should fail
   bool second = verifier.VerifyPolicy(
      policy_json, signature, symbol, 5, nonce, timestamp, error
   );
   
   return (first && !second);  // First pass, second fail
  }

//+------------------------------------------------------------------+
//| Test 5: Out-of-order sequence should be rejected                 |
//+------------------------------------------------------------------+
bool TestOutOfOrderSequence()
  {
   CPolicyVerifier verifier;
   if(!verifier.Initialize("server_public.pem"))
      return false;
   
   string policy_json = "{\"symbol\":\"GBPUSD\",\"action\":1}";
   string signature = "valid_sig_base64";
   string symbol = "GBPUSD";
   datetime timestamp = TimeCurrent();
   string error;
   
   // First policy - sequence 100
   bool first = verifier.VerifyPolicy(
      policy_json, signature, symbol, 100, 
      "550e8400-SEQ-TEST-100", timestamp, error
   );
   
   // Second policy - sequence 99 (out of order)
   bool second = verifier.VerifyPolicy(
      policy_json, signature, symbol, 99, 
      "550e8400-SEQ-TEST-99", timestamp, error
   );
   
   return (first && !second);  // First pass, second fail
  }

//+------------------------------------------------------------------+
//| Expert tick function (not used for tests)                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Tests run in OnInit only
  }
//+------------------------------------------------------------------+
