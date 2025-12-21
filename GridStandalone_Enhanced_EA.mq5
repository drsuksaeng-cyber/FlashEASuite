//+------------------------------------------------------------------+
//|                                    GridStandalone_Enhanced_EA.mq5|
//|                                  Grid Standalone Strategy V2     |
//|                         Complete Integration - Production Ready   |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

// Include enhanced modules - Use actual file names in folder
#include "Include/Logic/Grid/GridStandalone/GridExecution_Enhanced.mqh"
#include "Include/Logic/Grid/GridStandalone/GridDecision_Enhanced.mqh"
#include "Include/Logic/Grid/GridStandalone/GridRiskManager.mqh"
#include "Include/Logic/Grid/GridStandalone/SpreadFilter.mqh"
#include "Include/Logic/Grid/GridStandalone/SlippageController.mqh"

//--- Input Parameters

//+------------------------------------------------------------------+
//| PHASE 1: Critical Risk Management                                |
//+------------------------------------------------------------------+
input group "═══ Phase 1: Critical Risk Management ═══"
input double InpMinimumBalance = 100.0;        // Minimum Balance ($)
input bool   InpUseMinBalancePercent = false;  // Use Percent Mode
input double InpMinBalancePercent = 1.0;       // Min Balance (% of initial)

//+------------------------------------------------------------------+
//| PHASE 2: Loss Management                                         |
//+------------------------------------------------------------------+
input group "═══ Phase 2: Loss Management ═══"
input double InpCashBufferPercent = 30.0;      // Cash Buffer Reserve (%)
input double InpEmergencyExitDD = 20.0;        // Emergency Exit DD (%)
input int    InpEmergencyCooldown = 300;       // Emergency Cooldown (seconds)

//+------------------------------------------------------------------+
//| PHASE 3: Spread Filter                                           |
//+------------------------------------------------------------------+
input group "═══ Phase 3: Dynamic Spread Filter ═══"
input bool   InpUseSpreadFilter = true;        // Use Spread Filter
input double InpSpreadFormulaFactor = 0.1;     // Formula Factor (0.1 = 10%)
input double InpSpreadMinPips = 0.5;           // Min Spread (pips)
input double InpSpreadMaxPips = 5.0;           // Max Spread (pips)

//+------------------------------------------------------------------+
//| PHASE 4: Slippage Control                                        |
//+------------------------------------------------------------------+
input group "═══ Phase 4: Adaptive Slippage ═══"
input bool   InpUseAdaptiveSlippage = true;    // Use Adaptive Slippage
input double InpBaseSlippage = 2.0;            // Base Slippage (pips)
input double InpMinSlippage = 1.0;             // Min Slippage (pips)
input double InpMaxSlippage = 5.0;             // Max Slippage (pips)

//+------------------------------------------------------------------+
//| Grid Configuration                                               |
//+------------------------------------------------------------------+
input group "═══ Grid Configuration ═══"
input double InpBaseLot = 0.01;                // Base Lot Size
input double InpLotMultiplier = 1.0;           // Lot Multiplier (1.0 = no progression)
input int    InpMaxOrders = 10;                // Max Concurrent Orders
input double InpBaseStepPoints = 100;          // Base Step (points)
input bool   InpUseElasticStep = true;         // Use Elastic (ATR-based) Step
input int    InpATRPeriod = 14;                // ATR Period
input double InpATRMultiplier = 2.0;           // ATR Multiplier

//+------------------------------------------------------------------+
//| Entry Conditions                                                 |
//+------------------------------------------------------------------+
input group "═══ Entry Conditions ═══"
input int    InpMinConfirmations = 1;          // Min Signal Confirmations
input double InpMinConfidence = 0.5;           // Min Confidence (0-1)
input int    InpRSIPeriod = 14;                // RSI Period
input double InpRSIOverbought = 70.0;          // RSI Overbought Level
input double InpRSIOversold = 30.0;            // RSI Oversold Level
input int    InpADXPeriod = 14;                // ADX Period
input double InpADXThreshold = 25.0;           // ADX Trend Threshold

//+------------------------------------------------------------------+
//| System Settings                                                  |
//+------------------------------------------------------------------+
input group "═══ System Settings ═══"
input int    InpMagicNumber = 123456;          // Magic Number
input bool   InpPrintDashboard = true;         // Print Dashboard
input int    InpDashboardInterval = 60;        // Dashboard Interval (seconds)

//--- Global Objects
CGridExecution    *g_execution = NULL;
CGridDecision     *g_decision = NULL;
CGridRiskManager  *g_risk_mgr = NULL;
CSpreadFilter     *g_spread_filter = NULL;
CSlippageController *g_slippage_ctrl = NULL;

//--- State
bool g_initialized = false;
datetime g_last_dashboard_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("════════════════════════════════════════════════════════════");
   Print("  GridStandalone EA V2 - Enhanced");
   Print("  Production Ready with Advanced Risk Management");
   Print("════════════════════════════════════════════════════════════");
   
   // Create objects
   g_execution = new CGridExecution();
   g_decision = new CGridDecision();
   g_risk_mgr = new CGridRiskManager();
   g_spread_filter = new CSpreadFilter();
   g_slippage_ctrl = new CSlippageController();
   
   if(g_execution == NULL || g_decision == NULL || g_risk_mgr == NULL ||
      g_spread_filter == NULL || g_slippage_ctrl == NULL)
   {
      Print("❌ Failed to create objects!");
      return INIT_FAILED;
   }
   
   // Initialize Risk Manager (FIRST!)
   if(!g_risk_mgr.Initialize(_Symbol, InpMagicNumber))
   {
      Print("❌ Risk Manager initialization failed!");
      return INIT_FAILED;
   }
   g_risk_mgr.SetCashBuffer(InpCashBufferPercent);
   g_risk_mgr.SetEmergencyDD(InpEmergencyExitDD);
   g_risk_mgr.SetEmergencyCooldown(InpEmergencyCooldown);
   
   // Initialize Spread Filter
   if(!g_spread_filter.Initialize(_Symbol))
   {
      Print("❌ Spread Filter initialization failed!");
      return INIT_FAILED;
   }
   g_spread_filter.SetFormulaFactor(InpSpreadFormulaFactor);
   g_spread_filter.SetLimits(InpSpreadMinPips, InpSpreadMaxPips);
   
   // Initialize Slippage Controller
   if(!g_slippage_ctrl.Initialize(_Symbol))
   {
      Print("❌ Slippage Controller initialization failed!");
      return INIT_FAILED;
   }
   g_slippage_ctrl.SetBaseSlippage(InpBaseSlippage);
   g_slippage_ctrl.SetLimits(InpMinSlippage, InpMaxSlippage);
   g_slippage_ctrl.SetUseAdaptive(InpUseAdaptiveSlippage);
   
   // Initialize Grid Configuration
   g_execution.SetBaseLot(InpBaseLot);
   g_execution.SetLotMultiplier(InpLotMultiplier);
   g_execution.SetMaxOrders(InpMaxOrders);
   g_execution.SetBaseStep(InpBaseStepPoints);
   g_execution.SetUseElasticStep(InpUseElasticStep);
   g_execution.SetATRPeriod(InpATRPeriod);
   g_execution.SetATRMultiplier(InpATRMultiplier);
   
   // Set minimum balance
   if(InpUseMinBalancePercent)
      g_execution.SetMinimumBalancePercent(InpMinBalancePercent);
   else
      g_execution.SetMinimumBalance(InpMinimumBalance);
   
   // Set cash buffer
   g_execution.SetCashBufferPercent(InpCashBufferPercent);
   g_execution.SetEmergencyExitDD(InpEmergencyExitDD);
   g_execution.SetEmergencyCooldown(InpEmergencyCooldown);
   
   // Initialize Execution
   if(!g_execution.Initialize(_Symbol))
   {
      Print("❌ Execution initialization failed!");
      return INIT_FAILED;
   }
   
   // Initialize Decision (includes MarketAnalysis)
   g_decision.SetMinConfirmations(InpMinConfirmations);
   g_decision.SetMinConfidence(InpMinConfidence);
   g_decision.SetRSIPeriod(InpRSIPeriod);
   g_decision.SetRSILevels(InpRSIOverbought, InpRSIOversold);
   g_decision.SetADXPeriod(InpADXPeriod);
   g_decision.SetADXThreshold(InpADXThreshold);
   
   if(!g_decision.InitializeIndicators())
   {
      Print("⚠️ Some indicators failed - Will use fallback methods");
   }
   
   if(!g_decision.Initialize(_Symbol))
   {
      Print("❌ Decision initialization failed!");
      return INIT_FAILED;
   }
   
   g_initialized = true;
   
   Print("════════════════════════════════════════════════════════════");
   Print("✅ EA Initialized Successfully!");
   Print("════════════════════════════════════════════════════════════");
   
   // Print initial status
   if(InpPrintDashboard)
   {
      PrintDashboard();
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("════════════════════════════════════════════════════════════");
   Print("EA Deinitialization - Reason: ", reason);
   Print("════════════════════════════════════════════════════════════");
   
   // Print final statistics
   if(g_risk_mgr != NULL)
      g_risk_mgr.PrintStatus();
   
   if(g_spread_filter != NULL)
      g_spread_filter.PrintStatus();
   
   if(g_slippage_ctrl != NULL)
      g_slippage_ctrl.PrintStatus();
   
   // Delete objects
   if(g_execution != NULL)
      delete g_execution;
   if(g_decision != NULL)
      delete g_decision;
   if(g_risk_mgr != NULL)
      delete g_risk_mgr;
   if(g_spread_filter != NULL)
      delete g_spread_filter;
   if(g_slippage_ctrl != NULL)
      delete g_slippage_ctrl;
   
   Print("════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;
   
   // Update all modules
   g_spread_filter.OnTick();
   g_slippage_ctrl.Update();
   g_risk_mgr.Update();
   g_execution.UpdateDrawdown();
   g_execution.UpdatePeakBalance();
   g_decision.UpdateMarketAnalysis();
   
   // Check emergency state
   if(g_risk_mgr.IsEmergencyActive())
   {
      if(!g_risk_mgr.IsCooldownActive())
      {
         // Cooldown expired - Can resume
         Print("[EA] Emergency cooldown expired - Resuming trading");
      }
      return; // Don't trade during emergency
   }
   
   // Check if should enter new grid
   ENUM_ORDER_TYPE order_type;
   if(g_decision.ShouldEnterGrid(order_type))
   {
      // Additional checks before entry
      
      // 1. Spread check
      if(InpUseSpreadFilter && !g_spread_filter.IsSpreadAcceptable())
      {
         Print("[EA] ❌ Entry rejected: Spread too high");
         return;
      }
      
      // 2. Capital usage check (done in ShouldEnterGrid but double-check)
      if(!g_risk_mgr.CanUseCapital(0.0)) // Will check properly in execution
      {
         Print("[EA] ❌ Entry rejected: Capital limit reached");
         return;
      }
      
      // 3. Try to open Level 0
      bool success = g_execution.OpenGridLevel(0, order_type);
      
      if(success)
      {
         Print("[EA] ✅ Grid entry successful!");
      }
      else
      {
         Print("[EA] ❌ Grid entry failed - Check logs above");
      }
   }
   
   // Print dashboard periodically
   if(InpPrintDashboard)
   {
      datetime now = TimeCurrent();
      if(now - g_last_dashboard_time >= InpDashboardInterval)
      {
         PrintDashboard();
         g_last_dashboard_time = now;
      }
   }
}

//+------------------------------------------------------------------+
//| Print dashboard                                                   |
//+------------------------------------------------------------------+
void PrintDashboard()
{
   Print("");
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║        GridStandalone EA V2 - DASHBOARD                   ║");
   Print("╚════════════════════════════════════════════════════════════╝");
   Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   
   // Account Info
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ ACCOUNT                                                 │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ Balance:  $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("│ Equity:   $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   Print("│ Margin:   $", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2));
   Print("│ Free:     $", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
   Print("└─────────────────────────────────────────────────────────┘");
   
   // Risk Status
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ RISK MANAGEMENT                                         │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ Drawdown:     ", DoubleToString(g_risk_mgr.GetCurrentDD(), 2), "%");
   Print("│ Max DD:       ", DoubleToString(g_risk_mgr.GetMaxDD(), 2), "%");
   Print("│ Emergency DD: ", DoubleToString(InpEmergencyExitDD, 1), "%");
   Print("│ Status:       ", g_risk_mgr.IsEmergencyActive() ? "🚨 EMERGENCY" : "✅ Normal");
   if(g_risk_mgr.IsEmergencyActive())
   {
      Print("│ Cooldown:     ", g_risk_mgr.GetRemainingCooldown(), " seconds");
   }
   Print("└─────────────────────────────────────────────────────────┘");
   
   // Market Analysis
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ MARKET ANALYSIS                                         │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ State:    ", EnumToString(g_decision.GetMarketState()));
   Print("│ RSI:      ", g_decision.IsRSIAvailable() ? DoubleToString(g_decision.GetRSI(), 1) : "N/A");
   Print("│ ADX:      ", g_decision.IsADXAvailable() ? DoubleToString(g_decision.GetADX(), 1) : "N/A");
   Print("│ ATR:      ", DoubleToString(g_execution.GetCurrentATR(), _Digits));
   Print("└─────────────────────────────────────────────────────────┘");
   
   // Spread Filter
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ SPREAD FILTER                                           │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ Current:   ", DoubleToString(g_spread_filter.GetCurrentSpread(), 1), " pts");
   Print("│ VW Avg:    ", DoubleToString(g_spread_filter.GetVWAverage(), 1), " pts");
   Print("│ Threshold: ", DoubleToString(g_spread_filter.GetDynamicThreshold(), 1), " pts");
   Print("│ Rejections:", DoubleToString(g_spread_filter.GetRejectionRate(), 1), "%");
   Print("└─────────────────────────────────────────────────────────┘");
   
   // Slippage
   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ SLIPPAGE CONTROL                                        │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ Base:     ", DoubleToString(g_slippage_ctrl.GetBaseSlippage(), 1), " pips");
   Print("│ Dynamic:  ", DoubleToString(g_slippage_ctrl.GetDynamicSlippagePips(), 1), " pips");
   Print("│ Avg:      ", DoubleToString(g_slippage_ctrl.GetAverageRecentSlippage(), 1), " pts");
   Print("└─────────────────────────────────────────────────────────┘");
   
   Print("╚════════════════════════════════════════════════════════════╝");
   Print("");
}

//+------------------------------------------------------------------+
//| Trade transaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                       const MqlTradeRequest &request,
                       const MqlTradeResult &result)
{
   // Record slippage if order executed
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD || 
      trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         // Calculate slippage
         double requested = request.price;
         double executed = result.price;
         
         if(requested > 0 && executed > 0)
         {
            g_slippage_ctrl.RecordSlippage(requested, executed, true);
         }
      }
      else
      {
         // Order rejected
         g_slippage_ctrl.RecordSlippage(0, 0, false);
      }
   }
}
