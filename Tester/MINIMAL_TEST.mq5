//+------------------------------------------------------------------+
//| MINIMAL_TEST.mq5 - Test if basic includes work                   |
//| Location: Tester/MINIMAL_TEST.mq5                                |
//+------------------------------------------------------------------+
#property strict

// Test 1: Can we include Risk module?
// Use "" with relative path because it's in project Include/
#include "../Include/Risk/RiskGuardian.mqh"

// Global
CRiskGuardian g_test;

void OnInit()
{
   Print("TEST: OnInit started");
   
   // Test 2: Can we initialize?
   if(g_test.Initialize(5, 2.0, 10.0, 2.0))
   {
      Print("SUCCESS: RiskGuardian initialized");
   }
   else
   {
      Print("FAIL: RiskGuardian init failed");
   }
}

void OnDeinit(const int reason)
{
   Print("TEST: OnDeinit");
}

void OnTick()
{
   // Do nothing
}
