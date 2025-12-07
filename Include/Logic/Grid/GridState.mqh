//+------------------------------------------------------------------+
//|                                                Grid/GridState.mqh |
//|                                      FlashEASuite V2 - Program C |
//|              Elastic Grid Strategy - State Management Module      |
//+------------------------------------------------------------------+
#property strict

#include "GridConfig.mqh"

//+------------------------------------------------------------------+
//| Class: CGridState                                                |
//| Grid State Management and Position Tracking                      |
//+------------------------------------------------------------------+
class CGridState : public CGridConfig
  {
protected:
   //+------------------------------------------------------------------+
   //| Update Grid State (Track Active Positions)                      |
   //+------------------------------------------------------------------+
   void UpdateGridState()
     {
      // Reset grid state
      m_active_grid_count = 0;
      
      // Scan all positions
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         // Check if position belongs to this symbol and magic
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != 999000) continue;
         
         // Check comment to identify grid level
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "Grid_L") != 0) continue;
         
         // This is a grid position
         if(m_active_grid_count < 10) // Safety check
           {
            m_grid_orders[m_active_grid_count].ticket = ticket;
            m_grid_orders[m_active_grid_count].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            m_grid_orders[m_active_grid_count].lot_size = PositionGetDouble(POSITION_VOLUME);
            m_grid_orders[m_active_grid_count].open_time = (datetime)PositionGetInteger(POSITION_TIME);
            m_grid_orders[m_active_grid_count].level = m_active_grid_count;
            
            m_active_grid_count++;
           }
        }
      
      // Update last grid price (for spacing calculation)
      if(m_active_grid_count > 0)
        {
         m_last_grid_price = m_grid_orders[m_active_grid_count - 1].open_price;
        }
      else
        {
         m_last_grid_price = 0.0;
        }
     }
   
   //+------------------------------------------------------------------+
   //| Determine Grid Direction from CSM                               |
   //+------------------------------------------------------------------+
   void DetermineGridDirection()
     {
      double strength_diff = m_csm_usd - m_csm_eur;
      
      if(strength_diff > 0.1)
        {
         m_grid_direction = GRID_DIR_SELL;  // USD strong -> SELL EURUSD
        }
      else if(strength_diff < -0.1)
        {
         m_grid_direction = GRID_DIR_BUY;   // EUR strong -> BUY EURUSD
        }
      else
        {
         m_grid_direction = GRID_DIR_NONE;  // Neutral - no grid
        }
     }
   
   //+------------------------------------------------------------------+
   //| Check if Should Open New Grid Level                             |
   //+------------------------------------------------------------------+
   bool ShouldOpenNewGridLevel()
     {
      // Safety: Max grid levels reached
      if(m_active_grid_count >= m_grid_max_orders)
         return false;
      
      // Safety: No grid direction set
      if(m_grid_direction == GRID_DIR_NONE)
         return false;
      
      // Safety: No elastic step calculated
      if(m_elastic_step <= 0.0)
         return false;
      
      // Get current price
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return false;
      
      double current_price = (m_grid_direction == GRID_DIR_BUY) ? tick.ask : tick.bid;
      
      // First grid level (no previous grid)
      if(m_active_grid_count == 0)
        {
         return true; // Always open first level
        }
      
      // Check if price moved enough to trigger new grid level
      double price_diff = MathAbs(current_price - m_last_grid_price);
      double price_diff_points = price_diff / _Point;
      
      // Trigger new grid if price moved >= elastic step
      if(price_diff_points >= m_elastic_step)
        {
         return true;
        }
      
      return false;
     }
   
   //+------------------------------------------------------------------+
   //| Calculate Grid Lot Size for Level                               |
   //+------------------------------------------------------------------+
   double CalculateGridLotSize(int level)
     {
      double lot = m_base_lot;
      
      // Apply lot multiplier for each level
      for(int i = 0; i < level; i++)
        {
         lot *= m_lot_multiplier;
        }
      
      // Apply risk multiplier from Python policy
      lot *= m_risk_multiplier;
      
      // Normalize to broker's lot step
      double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lot = MathFloor(lot / lot_step) * lot_step;
      
      // Safety: Check min/max lot
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      
      if(lot < min_lot) lot = min_lot;
      if(lot > max_lot) lot = max_lot;
      
      return lot;
     }
  };
//+------------------------------------------------------------------+
