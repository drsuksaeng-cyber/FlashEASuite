//+------------------------------------------------------------------+
//|                                                 Grid/GridCore.mqh |
//|                                      FlashEASuite V2 - Program C |
//|                 Elastic Grid Strategy - Core Logic Module         |
//+------------------------------------------------------------------+
#property strict

#include "GridState.mqh"

//+------------------------------------------------------------------+
//| Class: CStrategyGrid                                             |
//| Elastic Grid Strategy Main Implementation                        |
//+------------------------------------------------------------------+
class CStrategyGrid : public CGridState
  {
private:
   string            m_name;
   bool              m_is_active;
   string            m_target_symbol;  // Target symbol for multi-symbol trading

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStrategyGrid() : CGridState()
     {
      m_name = "ElasticGrid";
      m_is_active = true;
      m_target_symbol = _Symbol;  // Default to chart symbol
     }
   
   //+------------------------------------------------------------------+
   //| Main Logic - Get Score                                          |
   //+------------------------------------------------------------------+
   double GetScore()
     {
      if(!m_is_active) return 0.0;
      
      // Safety Check 1: Cooldown from Python
      if(m_is_in_cooldown)
        {
         return 0.0;
        }
      
      // Safety Check 2: Low Confidence
      if(m_python_confidence < 0.3)
        {
         return 0.0;
        }
      
      // Safety Check 3: CSM Data Required
      if(!m_csm_data_received || m_current_direction == GRID_DIR_NONE)
        {
         return 0.0;
        }
      
      // Update ATR and calculate elastic step
      UpdateATRAndElasticStep();
      
      // Update grid state (track active positions)
      UpdateGridState();
      
      // Determine grid direction from CSM
      DetermineGridDirection();
      
      // Check if we need to open new grid level
      if(ShouldOpenNewGridLevel())
        {
         return CalculateGridScore();
        }
      
      return 0.0; // No action needed
     }
   
   //+------------------------------------------------------------------+
   //| Execute Grid Order                                               |
   //+------------------------------------------------------------------+
   void ExecuteGridOrder(ENUM_ORDER_TYPE type)
     {
      // Calculate lot size with risk multiplier
      int next_level = m_active_grid_count;
      double lot_size = CalculateGridLotSize(next_level);
      
      // Get current price
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return;
      
      double price = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
      
      // Calculate SL/TP
      double sl = 0.0;
      double tp = 0.0;
      
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
      
      // Create comment with level info
      string comment = StringFormat("Grid_L%d", next_level);
      
      // Execute order
      m_trade.SetExpertMagicNumber(999000); // Use same magic as system
      
      if(m_trade.PositionOpen(_Symbol, type, lot_size, price, sl, tp, comment))
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

private:
   //+------------------------------------------------------------------+
   //| Update ATR and Calculate Elastic Step                           |
   //+------------------------------------------------------------------+
   void UpdateATRAndElasticStep()
     {
      double atr_buffer[1];
      
      if(CopyBuffer(m_atr_handle, 0, 0, 1, atr_buffer) <= 0)
        {
         Print("[Grid] ERROR: Failed to copy ATR buffer!");
         m_atr_current = m_atr_reference; // Use reference value
         m_current_elastic_step = m_base_step_points;
         return;
        }
      
      m_atr_current = atr_buffer[0] / _Point; // Convert to points
      
      // Calculate elastic step: Base step * (Current ATR / Reference ATR)
      double atr_ratio = m_atr_current / m_atr_reference;
      m_current_elastic_step = m_base_step_points * atr_ratio;
      
      // Safety: Limit elastic step to prevent too wide/narrow grids
      double min_step = m_base_step_points * 0.5;  // Min 50% of base
      double max_step = m_base_step_points * 2.0;  // Max 200% of base
      
      if(m_current_elastic_step < min_step) m_current_elastic_step = min_step;
      if(m_current_elastic_step > max_step) m_current_elastic_step = max_step;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Grid Score                                             |
   //+------------------------------------------------------------------+
   double CalculateGridScore()
     {
      // Base score
      double score = 1.0;
      
      // Adjust by confidence (0.3 - 1.0)
      score *= m_python_confidence;
      
      // Adjust by risk multiplier (0.5 - 1.5)
      score *= m_python_risk_multiplier;
      
      // Higher score for first grid level
      if(m_active_grid_count == 0)
        {
         score *= 1.5;
        }
      
      // Lower score for higher grid levels
      if(m_active_grid_count >= 3)
        {
         score *= 0.7;
        }
      
      return score;
     }
   
   //+------------------------------------------------------------------+
   //| Get Strategy Name                                                |
   //+------------------------------------------------------------------+
   string GetName()
     {
      return m_name;
     }
   
   //+------------------------------------------------------------------+
   //| Get Target Symbol (for multi-symbol support)                     |
   //+------------------------------------------------------------------+
   string GetSymbol()
     {
      return m_target_symbol;
     }
   
   void SetSymbol(string symbol)
     {
      m_target_symbol = symbol;
      Print("[Grid] Target symbol set to: ", symbol);
     }
   
   //+------------------------------------------------------------------+
   //| Update Grid State from Policy Message (NEW)                      |
   //+------------------------------------------------------------------+
   void UpdateFromPolicy(const PolicyMessage &policy)
     {
      // Set target symbol for multi-symbol trading
      m_target_symbol = policy.symbol;
      
      // Update risk parameters from Python feedback
      m_python_risk_multiplier = policy.risk_multiplier;
      m_python_confidence = policy.confidence;
      m_is_in_cooldown = policy.is_in_cooldown;
      
      // Update CSM data from Python Brain
      m_csm_usd = policy.csm_usd;
      m_csm_eur = policy.csm_eur;
      m_csm_gbp = policy.csm_gbp;
      m_csm_jpy = policy.csm_jpy;
      m_csm_aud = policy.csm_aud;
      m_csm_cad = policy.csm_cad;
      m_csm_chf = policy.csm_chf;
      m_csm_nzd = policy.csm_nzd;
      m_csm_data_received = true;  // Mark CSM data as available
      
      // Update grid direction from Python CSM analysis
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
   //| Individual Setter Methods (Optional - for fine-grained control) |
   //+------------------------------------------------------------------+
   void SetRiskMultiplier(double multiplier)
     {
      m_python_risk_multiplier = multiplier;
      Print("[Grid] Risk multiplier set to: ", DoubleToString(multiplier, 2), "x");
     }
   
   void SetCooldown(bool is_cooldown)
     {
      m_is_in_cooldown = is_cooldown;
      Print("[Grid] Cooldown ", is_cooldown ? "ACTIVATED" : "DEACTIVATED");
     }
   
   void SetConfidence(double confidence)
     {
      m_python_confidence = confidence;
      Print("[Grid] Confidence set to: ", DoubleToString(confidence, 2));
     }
   
   void SetGridDirection(ENUM_GRID_DIRECTION direction)
     {
      m_current_direction = direction;
      string dir_str = (direction == GRID_DIR_BUY) ? "BUY" : 
                       (direction == GRID_DIR_SELL) ? "SELL" : "NONE";
      Print("[Grid] Direction set to: ", dir_str);
     }
   
   void SetCSMData(double usd, double eur, double gbp, double jpy,
                   double aud=0.0, double cad=0.0, double chf=0.0, double nzd=0.0)
     {
      m_csm_usd = usd;
      m_csm_eur = eur;
      m_csm_gbp = gbp;
      m_csm_jpy = jpy;
      m_csm_aud = aud;
      m_csm_cad = cad;
      m_csm_chf = chf;
      m_csm_nzd = nzd;
      m_csm_data_received = true;
      
      Print("[Grid] CSM data updated:");
      Print("   USD=", DoubleToString(usd, 2), " EUR=", DoubleToString(eur, 2),
            " GBP=", DoubleToString(gbp, 2), " JPY=", DoubleToString(jpy, 2));
     }
   
   //+------------------------------------------------------------------+
   //| Getter Methods (for monitoring and debugging)                    |
   //+------------------------------------------------------------------+
   double GetRiskMultiplier() const { return m_python_risk_multiplier; }
   double GetConfidence() const { return m_python_confidence; }
   bool IsInCooldown() const { return m_is_in_cooldown; }
   ENUM_GRID_DIRECTION GetGridDirection() const { return m_current_direction; }
   bool HasCSMData() const { return m_csm_data_received; }
   
   // Get CSM values
   double GetCSM_USD() const { return m_csm_usd; }
   double GetCSM_EUR() const { return m_csm_eur; }
   double GetCSM_GBP() const { return m_csm_gbp; }
   double GetCSM_JPY() const { return m_csm_jpy; }
   
   //+------------------------------------------------------------------+
   //| Activate/Deactivate Strategy                                     |
   //+------------------------------------------------------------------+
   void Activate() { m_is_active = true; }
   void Deactivate() { m_is_active = false; }
   bool IsActive() { return m_is_active; }
  };
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CHANGE LOG                                                        |
//+------------------------------------------------------------------+
// Version 2.0 (2025-12-28):
// - Added UpdateFromPolicy() method to receive Python Brain data
// - Added individual setter methods:
//   * SetRiskMultiplier()
//   * SetCooldown()
//   * SetConfidence()
//   * SetGridDirection()
//   * SetCSMData()
// - Added getter methods for monitoring:
//   * GetRiskMultiplier()
//   * GetConfidence()
//   * IsInCooldown()
//   * GetGridDirection()
//   * HasCSMData()
//   * GetCSM_USD/EUR/GBP/JPY()
//
// Purpose:
// - Enable Grid strategy to receive feedback-based risk adjustment
// - Enable CSM-based direction control from Python Brain
// - Support cooldown mechanism after consecutive losses
//
// Integration:
// - Called from ProgramC_Trader::ExecutePolicy() with PolicyMessage
// - Updates all Grid state variables from extended protocol fields
// - Provides logging for debugging and monitoring
//
// Compatibility:
// - Requires PolicyMessage with 11 Grid extended fields
// - Requires GridConfig base class with Grid state variables
//+------------------------------------------------------------------+

