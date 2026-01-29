//+------------------------------------------------------------------+
//|                                                 Grid/GridCore.mqh |
//|                                      FlashEASuite V2 - Program C |
//|                 Elastic Grid Strategy - Core Logic Module         |
//+------------------------------------------------------------------+
#property strict

#include "GridState.mqh"
#include "../../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| Class: CStrategyGrid                                             |
//| Elastic Grid Strategy Main Implementation                        |
//+------------------------------------------------------------------+
class CStrategyGrid : public CGridState
  {
private:
   // Trading (no Trade.mqh needed - will use built-in functions)
   int               m_atr_handle;
   double            m_atr_current;
   double            m_atr_reference;
   double            m_base_step_points;
   double            m_sl_points;
   double            m_tp_points;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CStrategyGrid() : CGridState()
     {
      // Initialize ATR for elastic step calculation
      m_atr_handle = iATR(_Symbol, PERIOD_H1, 14);
      m_atr_reference = 100.0;
      m_atr_current = m_atr_reference;
      m_base_step_points = 100.0;
      m_sl_points = 0;
      m_tp_points = 0;
     }
   
   //+------------------------------------------------------------------+
   //| Main Logic - Get Score                                          |
   //+------------------------------------------------------------------+
   double GetScore()
     {
      // Safety Check 1: Cooldown from Python
      if(m_is_in_cooldown)
         return 0.0;
      
      // Safety Check 2: Low Confidence
      if(m_python_confidence < 0.3)
         return 0.0;
      
      // Safety Check 3: CSM Data Required
      if(!m_csm_data_received || m_current_direction == GRID_DIR_NONE)
         return 0.0;
      
      // Update ATR and elastic step
      UpdateATRAndElasticStep();
      
      // Update grid state (track active positions)
      UpdateGridState();
      
      // Determine grid direction from CSM
      DetermineGridDirection();
      
      // Check if we need to open new grid level
      if(ShouldOpenNewGridLevel())
         return CalculateGridScore();
      
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

private:
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
