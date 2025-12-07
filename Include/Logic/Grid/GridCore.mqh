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

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStrategyGrid() : CGridState()
     {
      m_name = "ElasticGrid";
      m_is_active = true;
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
      if(m_confidence_score < 0.3)
        {
         return 0.0;
        }
      
      // Safety Check 3: CSM Data Required
      if(!m_csm_data_received || m_grid_direction == GRID_DIR_NONE)
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
         m_current_atr = m_atr_reference; // Use reference value
         m_elastic_step = m_base_step_points;
         return;
        }
      
      m_current_atr = atr_buffer[0] / _Point; // Convert to points
      
      // Calculate elastic step: Base step * (Current ATR / Reference ATR)
      double atr_ratio = m_current_atr / m_atr_reference;
      m_elastic_step = m_base_step_points * atr_ratio;
      
      // Safety: Limit elastic step to prevent too wide/narrow grids
      double min_step = m_base_step_points * 0.5;  // Min 50% of base
      double max_step = m_base_step_points * 2.0;  // Max 200% of base
      
      if(m_elastic_step < min_step) m_elastic_step = min_step;
      if(m_elastic_step > max_step) m_elastic_step = max_step;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Grid Score                                             |
   //+------------------------------------------------------------------+
   double CalculateGridScore()
     {
      // Base score
      double score = 1.0;
      
      // Adjust by confidence (0.3 - 1.0)
      score *= m_confidence_score;
      
      // Adjust by risk multiplier (0.5 - 1.5)
      score *= m_risk_multiplier;
      
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
   //| Activate/Deactivate Strategy                                     |
   //+------------------------------------------------------------------+
   void Activate() { m_is_active = true; }
   void Deactivate() { m_is_active = false; }
   bool IsActive() { return m_is_active; }
  };
//+------------------------------------------------------------------+
