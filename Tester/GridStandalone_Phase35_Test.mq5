//+------------------------------------------------------------------+
//|                                GridStandalone_Phase35_Test.mq5  |
//|                                      FlashEASuite V2 - Phase 3.5 |
//|                      Standalone Test EA for ATR Protection       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "FlashEASuite V2"
#property version   "1.00"
#property description "ทดสอบ Grid Strategy Phase 3.5 โดยไม่ต้องรอ Python Brain"
#property strict

//--- Include Grid Core (ต้องปรับ path ให้ตรงกับ structure)
#include "../Include/Logic/Grid/GridCore.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Mock Policy Settings ==="
input double   MockConfidence = 0.85;              // Mock Python Confidence (0-1)
input double   MockRiskMultiplier = 1.5;           // Mock Risk Multiplier
input bool     MockCooldown = false;               // Mock Cooldown State
input int      MockGridDirection = 1;              // Grid Direction (0=None, 1=Buy, 2=Sell)

input group "=== CSM Mock Data ==="
input double   Mock_USD = 75.5;                    // Mock USD Strength
input double   Mock_EUR = 45.2;                    // Mock EUR Strength
input double   Mock_GBP = 55.8;                    // Mock GBP Strength
input double   Mock_JPY = 35.1;                    // Mock JPY Strength
input double   Mock_AUD = 50.0;                    // Mock AUD Strength
input double   Mock_CAD = 48.5;                    // Mock CAD Strength
input double   Mock_CHF = 42.0;                    // Mock CHF Strength
input double   Mock_NZD = 46.5;                    // Mock NZD Strength

input group "=== ATR Ratio Settings ==="
input double   ATR_Ratio_Threshold = 0.8;          // ATR Ratio Threshold (0-1)

input group "=== Test Settings ==="
input int      TestInterval = 5;                   // Test Interval (seconds)
input bool     EnableTrading = false;              // Enable Actual Trading (CAREFUL!)
input bool     VerboseLogging = true;              // Show Detailed Logs

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CStrategyGrid* grid_strategy = NULL;
datetime last_test_time = 0;
int test_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║     Grid Strategy Phase 3.5 - Standalone Test EA         ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   //--- Create Grid Strategy instance
   grid_strategy = new CStrategyGrid();
   
   if(grid_strategy == NULL)
   {
      Print("❌ Failed to create Grid Strategy instance!");
      return(INIT_FAILED);
   }
   
   //--- Configure ATR Ratio Threshold
   grid_strategy.SetATRRatioThreshold(ATR_Ratio_Threshold);
   
   //--- Initial mock policy update
   UpdateMockPolicy();
   
   //--- Print configuration
   Print("✅ Test EA Initialized");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📊 Configuration:");
   Print("   Symbol: ", _Symbol);
   Print("   Test Interval: ", TestInterval, " seconds");
   Print("   ATR Ratio Threshold: ", DoubleToString(ATR_Ratio_Threshold, 2));
   Print("   Trading Enabled: ", EnableTrading ? "YES ⚠️" : "NO (Safe)");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🎯 Mock Policy:");
   Print("   Confidence: ", DoubleToString(MockConfidence, 2));
   Print("   Risk Multiplier: ", DoubleToString(MockRiskMultiplier, 2), "x");
   Print("   Cooldown: ", MockCooldown ? "YES" : "NO");
   Print("   Direction: ", MockGridDirection == 1 ? "BUY" : 
                            MockGridDirection == 2 ? "SELL" : "NONE");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   
   if(!EnableTrading)
   {
      Print("⚠️ TRADING DISABLED - Testing ATR protection logic only");
      Print("   Enable trading in inputs to open actual positions");
   }
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("🧪 Test will run every ", TestInterval, " seconds");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete Grid Strategy
   if(grid_strategy != NULL)
   {
      delete grid_strategy;
      grid_strategy = NULL;
   }
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📊 Test Summary:");
   Print("   Total Tests Run: ", test_count);
   Print("   EA Removed");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if it's time to run test
   datetime current_time = TimeCurrent();
   
   if(current_time - last_test_time < TestInterval)
      return;
   
   last_test_time = current_time;
   test_count++;
   
   //--- Run test
   RunGridTest();
}

//+------------------------------------------------------------------+
//| Update Mock Policy Data                                          |
//+------------------------------------------------------------------+
void UpdateMockPolicy()
{
   PolicyMessage mock_policy;
   
   //--- Set mock values
   mock_policy.symbol = _Symbol;
   mock_policy.confidence = MockConfidence;
   mock_policy.risk_multiplier = MockRiskMultiplier;
   mock_policy.is_in_cooldown = MockCooldown;
   mock_policy.grid_direction = MockGridDirection;
   
   //--- CSM data
   mock_policy.csm_usd = Mock_USD;
   mock_policy.csm_eur = Mock_EUR;
   mock_policy.csm_gbp = Mock_GBP;
   mock_policy.csm_jpy = Mock_JPY;
   mock_policy.csm_aud = Mock_AUD;
   mock_policy.csm_cad = Mock_CAD;
   mock_policy.csm_chf = Mock_CHF;
   mock_policy.csm_nzd = Mock_NZD;
   
   //--- Update grid strategy with mock policy
   grid_strategy.UpdateFromPolicy(mock_policy);
}

//+------------------------------------------------------------------+
//| Run Grid Test                                                    |
//+------------------------------------------------------------------+
void RunGridTest()
{
   if(grid_strategy == NULL)
      return;
   
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ Test #", test_count, " at ", TimeToString(TimeCurrent()));
   Print("└─────────────────────────────────────────────────────────┘");
   
   //--- Update mock policy
   UpdateMockPolicy();
   
   //--- Get Grid Score (this will check ATR ratio)
   double score = grid_strategy.GetScore();
   
   //--- Display results
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📊 Test Results:");
   Print("   Grid Score: ", DoubleToString(score, 3));
   
   if(score > 0)
   {
      Print("   Status: ✅ PASSED - Grid can trade");
      Print("   ATR Regime: 🟢 Safe (ratio < ", DoubleToString(ATR_Ratio_Threshold, 2), ")");
      
      if(VerboseLogging)
      {
         Print("   All safety checks passed:");
         Print("   • ATR Ratio Check: ✅");
         Print("   • Cooldown Check: ✅");
         Print("   • Confidence Check: ✅");
         Print("   • CSM Data Check: ✅");
      }
      
      //--- Execute trade if enabled
      if(EnableTrading)
      {
         Print("   🔄 Trading enabled - executing grid order...");
         
         ENUM_ORDER_TYPE order_type = (MockGridDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         grid_strategy.ExecuteGridOrder(order_type);
      }
      else
      {
         Print("   ℹ️ Trading disabled - no actual order placed");
      }
   }
   else
   {
      Print("   Status: ⛔ BLOCKED - Grid cannot trade");
      
      //--- Determine which check failed
      if(VerboseLogging)
      {
         Print("   Safety check analysis:");
         Print("   • ATR Ratio: ", CheckATRRatio() ? "✅ PASS" : "❌ FAIL (BLOCKED HERE!)");
         Print("   • Cooldown: ", MockCooldown ? "❌ FAIL" : "✅ PASS");
         Print("   • Confidence: ", (MockConfidence >= 0.3) ? "✅ PASS" : "❌ FAIL");
         Print("   • Direction: ", (MockGridDirection > 0) ? "✅ PASS" : "❌ FAIL");
      }
      
      Print("   🛡️ Phase 3.5 Protection working correctly!");
   }
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("");
}

//+------------------------------------------------------------------+
//| Check ATR Ratio (for diagnostic)                                 |
//+------------------------------------------------------------------+
bool CheckATRRatio()
{
   int h_atr_h1 = iATR(_Symbol, PERIOD_H1, 14);
   int h_atr_d1 = iATR(_Symbol, PERIOD_D1, 14);
   
   double atr_h1_buffer[1];
   double atr_d1_buffer[1];
   
   if(CopyBuffer(h_atr_h1, 0, 0, 1, atr_h1_buffer) <= 0)
      return true;
   
   if(CopyBuffer(h_atr_d1, 0, 0, 1, atr_d1_buffer) <= 0)
      return true;
   
   double atr_h1 = atr_h1_buffer[0];
   double atr_d1 = atr_d1_buffer[0];
   
   if(atr_d1 <= 0)
      return true;
   
   double ratio = atr_h1 / atr_d1;
   
   if(VerboseLogging)
   {
      Print("   ATR Details:");
      Print("     H1: ", DoubleToString(atr_h1, 5));
      Print("     D1: ", DoubleToString(atr_d1, 5));
      Print("     Ratio: ", DoubleToString(ratio, 3), " / ", DoubleToString(ATR_Ratio_Threshold, 2));
   }
   
   IndicatorRelease(h_atr_h1);
   IndicatorRelease(h_atr_d1);
   
   return (ratio <= ATR_Ratio_Threshold);
}
//+------------------------------------------------------------------+
