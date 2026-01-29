//+------------------------------------------------------------------+
//|                           TestPolicyVerification_Simple.mq5      |
//|                          FlashEASuite V2 - Phase 2               |
//|                          Security Logic Testing                  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include "../Include/Network/PolicyVerifier.mqh"

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CPolicyVerifier g_verifier;

int g_test_count = 0;
int g_passed = 0;
int g_failed = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("═══════════════════════════════════════════════════════════");
   Print("  FlashEASuite V2 - Policy Verification Test");
   Print("  Phase 2: Security Module Testing (Simple Version)");
   Print("═══════════════════════════════════════════════════════════");
   
   // Initialize verifier
   if(!g_verifier.Initialize("server_public.pem"))
     {
      Print("❌ PolicyVerifier initialization failed");
      return INIT_FAILED;
     }
   
   Print("✅ PolicyVerifier initialized");
   
   // Run tests after 2 seconds
   EventSetTimer(2);
   
   Print("\n🎯 Running security tests in 2 seconds...");
   Print("═══════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   
   Print("\n═══════════════════════════════════════════════════════════");
   Print("TEST SUMMARY");
   Print("═══════════════════════════════════════════════════════════");
   Print("Tests Run: ", g_test_count);
   Print("Tests Passed: ", g_passed, " ✅");
   Print("Tests Failed: ", g_failed, " ❌");
   
   if(g_failed == 0 && g_test_count > 0)
      Print("\n🎉 ALL TESTS PASSED!");
   else if(g_test_count == 0)
      Print("\n⚠️  No tests were run");
   else
      Print("\n⚠️  ", g_failed, " TEST(S) FAILED");
   
   Print("═══════════════════════════════════════════════════════════");
  }

//+------------------------------------------------------------------+
//| Timer function - Run tests                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {
   EventKillTimer();  // Run once
   
   Print("\n🧪 Starting Security Tests...\n");
   
   // Test 1: Valid policy (current time)
   Test_ValidPolicy();
   
   // Test 2: Old timestamp (should reject)
   Test_OldTimestamp();
   
   // Test 3: Future timestamp (should reject)
   Test_FutureTimestamp();
   
   // Test 4: Duplicate nonce (should reject)
   Test_DuplicateNonce();
   
   // Test 5: Out-of-order sequence (should reject)
   Test_OutOfOrderSequence();
   
   // Print final summary
   Print("\n─────────────────────────────────────");
   Print("All tests completed");
   Print("Run: ", g_test_count, " | Passed: ", g_passed, " | Failed: ", g_failed);
   Print("─────────────────────────────────────");
  }

//+------------------------------------------------------------------+
//| Test 1: Valid policy                                              |
//+------------------------------------------------------------------+
void Test_ValidPolicy()
  {
   g_test_count++;
   Print("─────────────────────────────────────");
   Print("TEST 1: Valid Policy (should ACCEPT)");
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "test_signature_1";
   string symbol = "XAUUSD";
   long sequence = 1;
   string nonce = "nonce-valid-12345";
   datetime timestamp = TimeCurrent();
   string error_msg;
   
   bool result = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   if(result)
     {
      Print("✅ PASSED - Policy accepted as expected");
      g_passed++;
     }
   else
     {
      Print("❌ FAILED - Policy rejected: ", error_msg);
      g_failed++;
     }
  }

//+------------------------------------------------------------------+
//| Test 2: Old timestamp                                             |
//+------------------------------------------------------------------+
void Test_OldTimestamp()
  {
   g_test_count++;
   Print("\n─────────────────────────────────────");
   Print("TEST 2: Old Timestamp (should REJECT)");
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "test_signature_2";
   string symbol = "XAUUSD";
   long sequence = 2;
   string nonce = "nonce-old-12345";
   datetime timestamp = TimeCurrent() - 600;  // 10 minutes ago
   string error_msg;
   
   bool result = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   if(!result)
     {
      Print("✅ PASSED - Policy rejected as expected");
      Print("   Reason: ", error_msg);
      g_passed++;
     }
   else
     {
      Print("❌ FAILED - Policy accepted (security breach!)");
      g_failed++;
     }
  }

//+------------------------------------------------------------------+
//| Test 3: Future timestamp                                          |
//+------------------------------------------------------------------+
void Test_FutureTimestamp()
  {
   g_test_count++;
   Print("\n─────────────────────────────────────");
   Print("TEST 3: Future Timestamp (should REJECT)");
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "test_signature_3";
   string symbol = "XAUUSD";
   long sequence = 3;
   string nonce = "nonce-future-12345";
   datetime timestamp = TimeCurrent() + 120;  // 2 minutes future
   string error_msg;
   
   bool result = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   if(!result)
     {
      Print("✅ PASSED - Policy rejected as expected");
      Print("   Reason: ", error_msg);
      g_passed++;
     }
   else
     {
      Print("❌ FAILED - Policy accepted (security breach!)");
      g_failed++;
     }
  }

//+------------------------------------------------------------------+
//| Test 4: Duplicate nonce                                           |
//+------------------------------------------------------------------+
void Test_DuplicateNonce()
  {
   g_test_count++;
   Print("\n─────────────────────────────────────");
   Print("TEST 4: Duplicate Nonce (should REJECT 2nd)");
   
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "test_signature_4";
   string symbol = "XAUUSD";
   long sequence = 4;
   string nonce = "nonce-duplicate-12345";
   datetime timestamp = TimeCurrent();
   string error_msg;
   
   // First attempt (should accept)
   bool result1 = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   Print("   First attempt: ", (result1 ? "ACCEPTED ✅" : "REJECTED ❌"));
   
   // Second attempt with SAME nonce (should reject)
   sequence = 5;  // Different sequence
   bool result2 = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   Print("   Second attempt: ", (result2 ? "ACCEPTED ❌" : "REJECTED ✅"));
   
   if(result1 && !result2)
     {
      Print("✅ PASSED - Duplicate nonce detected");
      Print("   Reason: ", error_msg);
      g_passed++;
     }
   else
     {
      Print("❌ FAILED - Nonce reuse not detected!");
      g_failed++;
     }
  }

//+------------------------------------------------------------------+
//| Test 5: Out-of-order sequence                                     |
//+------------------------------------------------------------------+
void Test_OutOfOrderSequence()
  {
   g_test_count++;
   Print("\n─────────────────────────────────────");
   Print("TEST 5: Out-of-Order Sequence (should REJECT 2nd)");
   
   string policy_json = "{\"symbol\":\"EURUSD\",\"action\":1}";
   string signature = "test_signature_5";
   string symbol = "EURUSD";
   long sequence = 10;
   string nonce = "nonce-seq-first-12345";
   datetime timestamp = TimeCurrent();
   string error_msg;
   
   // First attempt (sequence 10)
   bool result1 = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   Print("   First (seq=10): ", (result1 ? "ACCEPTED ✅" : "REJECTED ❌"));
   
   // Second attempt with LOWER sequence (should reject)
   sequence = 9;  // Out of order!
   nonce = "nonce-seq-second-12345";  // Different nonce
   bool result2 = g_verifier.VerifyPolicy(
      policy_json, signature, symbol, sequence, nonce, timestamp, error_msg
   );
   
   Print("   Second (seq=9): ", (result2 ? "ACCEPTED ❌" : "REJECTED ✅"));
   
   if(result1 && !result2)
     {
      Print("✅ PASSED - Out-of-order sequence detected");
      Print("   Reason: ", error_msg);
      g_passed++;
     }
   else
     {
      Print("❌ FAILED - Sequence manipulation not detected!");
      g_failed++;
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function (not used)                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Not used
  }
//+------------------------------------------------------------------+
