//+------------------------------------------------------------------+
//|                                                 Grid/GridCore.mqh |
//|                                      FlashEASuite V2 - Program C |
//|                 Elastic Grid Strategy - Core Logic Module         |
//|                                                                    |
//|                      Phase 3.5: ATR Ratio Protection ENABLED      |
//|                      Phase 3.6: Swap Filter ENABLED               |
//+------------------------------------------------------------------+
#property strict

#include "GridState.mqh"
#include "../../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| Class: CStrategyGrid                                             |
//| Elastic Grid Strategy Main Implementation                        |
//| Phase 3.5: Multi-timeframe ATR Protection                        |
//+------------------------------------------------------------------+
class CStrategyGrid : public CGridState
  {
private:
   // Trading (no Trade.mqh needed - will use built-in functions)
   int               m_atr_handle;          // ATR H1 for elastic step
   int               m_atr_d1_handle;       // NEW: ATR D1 for regime check
   double            m_atr_current;
   double            m_atr_reference;
   double            m_base_step_points;
   double            m_sl_points;
   double            m_tp_points;
   
   // Phase 3.5: ATR Ratio Protection
   double            m_atr_ratio_threshold;  // NEW: Default 0.8 (80%)
   
   // Phase 3.6: Swap Filter
   bool              m_swap_filter_enabled;  // NEW: Enable/disable swap filter
   
   // Phase 3.6.1: Performance Optimization
   datetime          m_last_score_time;      // Last time GetScore was calculated
   double            m_cached_score;         // Cached score value
   bool              m_atr_fail_logged;      // Prevent ATR fail spam
   bool              m_swap_allow_logged;    // Prevent swap allow spam

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStrategyGrid() : CGridState()
     {
      // Initialize ATR for elastic step calculation (H1)
      m_atr_handle = iATR(_Symbol, PERIOD_H1, 14);
      
      // NEW: Initialize ATR D1 for regime protection
      m_atr_d1_handle = iATR(_Symbol, PERIOD_D1, 14);
      
      m_atr_reference = 100.0;
      m_atr_current = m_atr_reference;
      m_base_step_points = 100.0;
      m_sl_points = 0;
      m_tp_points = 0;
      
      // NEW: Set ATR ratio threshold (configurable)
      m_atr_ratio_threshold = 0.8;  // 80% - if H1/D1 > this, possible trend
      
      // NEW: Set swap filter (configurable)
      m_swap_filter_enabled = true;  // Enable by default
      
      // NEW: Initialize cache variables
      m_last_score_time = 0;
      m_cached_score = -1.0;
      m_atr_fail_logged = false;
      m_swap_allow_logged = false;
      
      Print("[Grid] ✅ Phase 3.5 + 3.6 Initialized");
      Print("   ATR Ratio Protection: Active");
      Print("   ATR Ratio Threshold: ", DoubleToString(m_atr_ratio_threshold, 2));
      Print("   Swap Filter: ", m_swap_filter_enabled ? "Enabled" : "Disabled");
     }
   
   //+------------------------------------------------------------------+
   //| Main Logic - Get Score                                          |
   //+------------------------------------------------------------------+
   double GetScore()
     {
      // ═════════════════════════════════════════════════════════════
      // Phase 3.6.1: Performance Optimization - Rate Limiting
      // ═════════════════════════════════════════════════════════════
      datetime current_time = TimeCurrent();
      
      // Cache score for same second (prevent spam calls)
      if(current_time == m_last_score_time && m_cached_score >= 0)
        {
         return m_cached_score;
        }
      
      // Update cache timestamp
      m_last_score_time = current_time;
      
      // ═════════════════════════════════════════════════════════════
      // NEW: Safety Check 0 - Multi-timeframe ATR Protection (Phase 3.5)
      // ═════════════════════════════════════════════════════════════
      if(!CheckATRRegime())
        {
         // ATR ratio too high - possible trend regime
         // Grid should NOT trade against strong trends
         m_cached_score = 0.0;
         return 0.0;
        }
      
      // ═════════════════════════════════════════════════════════════
      // NEW: Safety Check 0.5 - Swap Filter (Phase 3.6)
      // ═════════════════════════════════════════════════════════════
      if(m_swap_filter_enabled && !CheckSwapFilter())
        {
         // Swap is negative for this direction
         // Grid should NOT trade with negative swap
         m_cached_score = 0.0;
         return 0.0;
        }
      
      // Safety Check 1: Cooldown from Python
      if(m_is_in_cooldown)
        {
         m_cached_score = 0.0;
         return 0.0;
        }
      
      // Safety Check 2: Low Confidence
      if(m_python_confidence < 0.3)
        {
         m_cached_score = 0.0;
         return 0.0;
        }
      
      // Safety Check 3: CSM Data Required
      if(!m_csm_data_received || m_current_direction == GRID_DIR_NONE)
        {
         m_cached_score = 0.0;
         return 0.0;
        }
      
      // Update ATR and elastic step
      UpdateATRAndElasticStep();
      
      // Update grid state (track active positions)
      UpdateGridState();
      
      // Determine grid direction from CSM
      DetermineGridDirection();
      
      // Check if we need to open new grid level
      if(ShouldOpenNewGridLevel())
        {
         double score = CalculateGridScore();
         m_cached_score = score;
         return score;
        }
      
      m_cached_score = 0.0;
      return 0.0; // No action needed
     }
   
   //+------------------------------------------------------------------+
   //| Execute Grid Order                                               |
   //+------------------------------------------------------------------+
   void ExecuteGridOrder(ENUM_ORDER_TYPE type)
     {
      int next_level = m_active_grid_count;
      double lot_size = CalculateGridLotSize(next_level);
      
      MqlTick tick;
      if(!SymbolInfoTick(GetSymbol(), tick)) return;
      
      double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
      double sl = 0, tp = 0;
      
      if(m_sl_points > 0)
        {
         sl = (type == ORDER_TYPE_BUY) ? 
              price - m_sl_points * _Point : 
              price + m_sl_points * _Point;
        }
      
      if(m_tp_points > 0)
        {
         tp = (type == ORDER_TYPE_BUY) ? 
              price + m_tp_points * _Point : 
              price - m_tp_points * _Point;
        }
      
      string comment = StringFormat("Grid_L%d", next_level);
      
      // Use built-in OrderSend
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = GetSymbol();
      request.volume = lot_size;
      request.type = type;
      request.price = price;
      request.sl = sl;
      request.tp = tp;
      request.deviation = 10;
      request.magic = 999000;
      request.comment = comment;
      
      if(OrderSend(request, result))
        {
         string type_str = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
         Print("[Grid] ✅ Opened Grid Level ", next_level, 
               " | Type: ", type_str,
               " | Lot: ", lot_size,
               " | Price: ", price);
        }
      else
        {
         Print("[Grid] ❌ Failed to open grid! Error: ", GetLastError());
        }
     }
   
   //+------------------------------------------------------------------+
   //| Update Grid State from Policy Message (PUBLIC)                  |
   //+------------------------------------------------------------------+
   void UpdateFromPolicy(const PolicyMessage &policy)
     {
      // Set target symbol
      m_target_symbol = policy.symbol;
      
      // Update risk parameters
      m_python_risk_multiplier = policy.risk_multiplier;
      m_python_confidence = policy.confidence;
      m_is_in_cooldown = policy.is_in_cooldown;
      
      // Update CSM data
      m_csm_usd = policy.csm_usd;
      m_csm_eur = policy.csm_eur;
      m_csm_gbp = policy.csm_gbp;
      m_csm_jpy = policy.csm_jpy;
      m_csm_aud = policy.csm_aud;
      m_csm_cad = policy.csm_cad;
      m_csm_chf = policy.csm_chf;
      m_csm_nzd = policy.csm_nzd;
      m_csm_data_received = true;
      
      // Update grid direction
      if(policy.grid_direction == 1)
         m_current_direction = GRID_DIR_BUY;
      else if(policy.grid_direction == 2)
         m_current_direction = GRID_DIR_SELL;
      else
         m_current_direction = GRID_DIR_NONE;
      
      // Log update
      Print("[Grid] ✅ Updated from Policy:");
      Print("   Symbol: ", policy.symbol);
      Print("   Risk Multiplier: ", DoubleToString(m_python_risk_multiplier, 2), "x");
      Print("   Confidence: ", DoubleToString(m_python_confidence, 2));
      Print("   Cooldown: ", m_is_in_cooldown ? "YES (paused)" : "NO (active)");
      Print("   Direction: ", m_current_direction == GRID_DIR_BUY ? "BUY" : 
                              m_current_direction == GRID_DIR_SELL ? "SELL" : "NONE");
      Print("   CSM: USD=", DoubleToString(m_csm_usd, 2), 
            " EUR=", DoubleToString(m_csm_eur, 2),
            " GBP=", DoubleToString(m_csm_gbp, 2),
            " JPY=", DoubleToString(m_csm_jpy, 2));
     }
   
   //+------------------------------------------------------------------+
   //| NEW: Set ATR Ratio Threshold (Configurable)                     |
   //+------------------------------------------------------------------+
   void SetATRRatioThreshold(double threshold)
     {
      if(threshold > 0 && threshold <= 1.0)
        {
         m_atr_ratio_threshold = threshold;
         Print("[Grid] ✅ ATR Ratio Threshold updated: ", DoubleToString(threshold, 2));
        }
      else
        {
         Print("[Grid] ⚠️ Invalid ATR Ratio Threshold (", threshold, ") - keeping default: ", 
               DoubleToString(m_atr_ratio_threshold, 2));
        }
     }
   
   //+------------------------------------------------------------------+
   //| NEW: Set Swap Filter Enabled (Configurable) - Phase 3.6         |
   //+------------------------------------------------------------------+
   void SetSwapFilterEnabled(bool enabled)
     {
      m_swap_filter_enabled = enabled;
      Print("[Grid] ✅ Swap Filter: ", enabled ? "Enabled" : "Disabled");
     }
   
   //+------------------------------------------------------------------+
   //| SetDynamicParams: Apply CONFIG_PUSH V2 params to Grid strategy   |
   //| Entry point from StrategyManager_V6.DistributeDynamicParams()    |
   //| Backward safe: if no params received, existing values unchanged  |
   //+------------------------------------------------------------------+
   void SetDynamicParams(SDynamicParams &params)
     {
      // 1. Apply to GridConfig layer (spacing, levels, thresholds)
      ApplyDynamicParams(params);
      
      // 2. Sync ATR ratio threshold with the configurable member
      if(params.HasParam("S15_ATR_RATIO"))
         SetATRRatioThreshold(m_atr_ratio_thresh_dyn);
      
      // 3. Sync swap filter
      if(params.HasParam("S15_SWAP_FILTER"))
         SetSwapFilterEnabled(m_swap_filter_dyn);
      
      // 4. Risk multiplier from server regime analysis
      if(params.risk_multiplier > 0.0)
         m_python_risk_multiplier = params.risk_multiplier;
      
      PrintFormat("[Grid] SetDynamicParams complete: levels=%d step=%.0f elastic=%.2f confThresh=%.2f",
                  m_max_grid_levels, m_base_elastic_step,
                  m_elastic_factor, m_conf_threshold);
     }
   
   //+------------------------------------------------------------------+
   //| GetCurrentParams: Export current Grid params for TRADE_REPORT   |
   //| StrategyManager calls this when building feedback messages       |
   //+------------------------------------------------------------------+
   SDynamicParams GetCurrentParams()
     {
      SDynamicParams p;
      p.Reset();
      p.risk_multiplier = m_python_risk_multiplier;
      
      p.SetParam("S15_MAX_ORDERS",     (double)m_max_grid_levels);
      p.SetParam("S15_BASE_STEP",      m_base_elastic_step);
      p.SetParam("S15_ELASTIC_FACTOR", m_elastic_factor);
      p.SetParam("S15_CONF_THRESHOLD", m_conf_threshold);
      p.SetParam("S15_ATR_RATIO",      m_atr_ratio_threshold);
      p.SetParam("S15_SWAP_FILTER",    m_swap_filter_enabled ? 1.0 : 0.0);
      
      return p;
     }

private:
   //+------------------------------------------------------------------+
   //| NEW: Check ATR Regime (Phase 3.5)                               |
   //| Returns: true if safe to trade, false if regime protection active|
   //+------------------------------------------------------------------+
   bool CheckATRRegime()
     {
      // Get ATR H1
      double atr_h1_buffer[1];
      if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_h1_buffer) <= 0)
        {
         // Log only first time to avoid spam
         if(!m_atr_fail_logged)
           {
            Print("[Grid] ⚠️ Failed to get ATR H1 - allowing trade (safe default)");
            m_atr_fail_logged = true;
           }
         return true;  // If can't get data, don't block
        }
      
      // Get ATR D1
      double atr_d1_buffer[1];
      if(CopyBuffer(m_atr_d1_handle, 0, 0, 1, atr_d1_buffer) <= 0)
        {
         // Log only first time to avoid spam
         if(!m_atr_fail_logged)
           {
            Print("[Grid] ⚠️ Failed to get ATR D1 - allowing trade (safe default)");
            m_atr_fail_logged = true;
           }
         return true;  // If can't get data, don't block
        }
      
      // Reset flag when we successfully get data
      m_atr_fail_logged = false;
      
      double atr_h1 = atr_h1_buffer[0];
      double atr_d1 = atr_d1_buffer[0];
      
      // Prevent division by zero
      if(atr_d1 <= 0)
        {
         // Rare case, log once
         if(!m_atr_fail_logged)
           {
            Print("[Grid] ⚠️ ATR D1 is zero - allowing trade");
            m_atr_fail_logged = true;
           }
         return true;
        }
      
      // Calculate ratio
      double atr_ratio = atr_h1 / atr_d1;
      
      // Check if H1 volatility is too high relative to D1
      // High ratio means H1 is very volatile compared to D1 = possible trend regime
      if(atr_ratio > m_atr_ratio_threshold)
        {
         Print("[Grid] 🛡️ ATR REGIME PROTECTION ACTIVE");
         Print("   ATR H1: ", DoubleToString(atr_h1, 5));
         Print("   ATR D1: ", DoubleToString(atr_d1, 5));
         Print("   Ratio: ", DoubleToString(atr_ratio, 3), " (threshold: ", 
               DoubleToString(m_atr_ratio_threshold, 2), ")");
         Print("   🚫 Grid disabled - possible trend regime detected");
         return false;  // Block grid trading
        }
      
      // Ratio is OK - safe to trade
      Print("[Grid] ✅ ATR regime check passed");
      Print("   ATR H1: ", DoubleToString(atr_h1, 5), 
            " | D1: ", DoubleToString(atr_d1, 5), 
            " | Ratio: ", DoubleToString(atr_ratio, 3), 
            " (OK < ", DoubleToString(m_atr_ratio_threshold, 2), ")");
      
      return true;  // Safe to trade
     }
   
   //+------------------------------------------------------------------+
   //| NEW: Check Swap Filter (Phase 3.6)                              |
   //| Returns: true if swap is positive, false if negative            |
   //+------------------------------------------------------------------+
   bool CheckSwapFilter()
     {
      // Get swap values for current symbol
      double swap_long = SymbolInfoDouble(m_target_symbol, SYMBOL_SWAP_LONG);
      double swap_short = SymbolInfoDouble(m_target_symbol, SYMBOL_SWAP_SHORT);
      
      // Determine which direction we're trading
      bool is_buy = (m_current_direction == GRID_DIR_BUY);
      bool is_sell = (m_current_direction == GRID_DIR_SELL);
      
      // Check if our direction has positive swap
      if(is_buy)
        {
         if(swap_long <= 0)
           {
            // Only log if this is state change (was allowed, now blocked)
            if(!m_swap_allow_logged)
              {
               Print("[Grid] 🚫 SWAP FILTER BLOCKED");
               Print("   Direction: BUY");
               Print("   Swap Long: ", DoubleToString(swap_long, 2), " (NEGATIVE)");
               Print("   Swap Short: ", DoubleToString(swap_short, 2));
               Print("   Grid disabled - negative swap for BUY direction");
              }
            m_swap_allow_logged = false;
            return false;
           }
         
         // Only log first time or after being blocked
         if(!m_swap_allow_logged)
           {
            Print("[Grid] ✅ Swap filter passed");
            Print("   Direction: BUY | Swap Long: ", DoubleToString(swap_long, 2), " (POSITIVE ✅)");
            m_swap_allow_logged = true;
           }
         return true;
        }
      
      if(is_sell)
        {
         if(swap_short <= 0)
           {
            // Only log if this is state change
            if(!m_swap_allow_logged)
              {
               Print("[Grid] 🚫 SWAP FILTER BLOCKED");
               Print("   Direction: SELL");
               Print("   Swap Long: ", DoubleToString(swap_long, 2));
               Print("   Swap Short: ", DoubleToString(swap_short, 2), " (NEGATIVE)");
               Print("   Grid disabled - negative swap for SELL direction");
              }
            m_swap_allow_logged = false;
            return false;
           }
         
         // Only log first time or after being blocked
         if(!m_swap_allow_logged)
           {
            Print("[Grid] ✅ Swap filter passed");
            Print("   Direction: SELL | Swap Short: ", DoubleToString(swap_short, 2), " (POSITIVE ✅)");
            m_swap_allow_logged = true;
           }
         return true;
        }
      
      // No direction set - allow silently (normal for HOLD action)
      // Don't log to avoid spam when action = 0 (HOLD)
      return true;
     }
   
   //+------------------------------------------------------------------+
   //| Update ATR and Calculate Elastic Step                           |
   //+------------------------------------------------------------------+
   void UpdateATRAndElasticStep()
     {
      double atr_buffer[1];
      
      if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
        {
         m_atr_current = m_atr_reference;
         m_current_elastic_step = m_base_step_points;
         return;
        }
      
      m_atr_current = atr_buffer[0] / _Point;
      double atr_ratio = m_atr_current / m_atr_reference;
      m_current_elastic_step = m_base_step_points * atr_ratio;
      
      double min_step = m_base_step_points * 0.5;
      double max_step = m_base_step_points * 2.0;
      
      if(m_current_elastic_step < min_step) m_current_elastic_step = min_step;
      if(m_current_elastic_step > max_step) m_current_elastic_step = max_step;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Grid Score                                             |
   //+------------------------------------------------------------------+
   double CalculateGridScore()
     {
      double score = 1.0;
      score *= m_python_confidence;
      score *= m_python_risk_multiplier;
      
      if(m_active_grid_count == 0)
         score *= 1.5;
      
      if(m_active_grid_count >= 3)
         score *= 0.7;
      
      return score;
     }
  };
//+------------------------------------------------------------------+
