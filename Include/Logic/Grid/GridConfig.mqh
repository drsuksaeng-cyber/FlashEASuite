//+------------------------------------------------------------------+
//|                                              Grid/GridConfig.mqh |
//|                                      FlashEASuite V2 - Program C |
//|           Elastic Grid Strategy - Configuration Module           |
//+------------------------------------------------------------------+
#property strict

#include "../../Logic/StrategyBase.mqh"  // For CStrategyBase inheritance
#include "../../Network/Protocol/Definitions.mqh"  // For ENUM_GRID_DIRECTION

//+------------------------------------------------------------------+
//| Grid Order Structure                                             |
//+------------------------------------------------------------------+
struct GridOrder
  {
   ulong             ticket;
   double            open_price;
   double            lot_size;
   datetime          open_time;
   int               level;
  };

//+------------------------------------------------------------------+
//| Class: CGridConfig                                               |
//| Grid Strategy Configuration and Base Settings                    |
//+------------------------------------------------------------------+
class CGridConfig : public CStrategyBase
  {
protected:
   // Grid Configuration
   int               m_max_grid_levels;
   double            m_base_lot;
   double            m_lot_progression[5];
   double            m_base_elastic_step;
   double            m_current_elastic_step;
   
   // Multi-Symbol Support (NEW)
   string            m_target_symbol;  // Target symbol for trading
   
   // Grid State
   int               m_active_grid_count;
   GridOrder         m_grid_orders[10];
   double            m_last_grid_price;
   
   // Grid Direction (from Python CSM analysis)
   ENUM_GRID_DIRECTION m_current_direction;  // Uses enum from Definitions.mqh
   
   // Python Brain Parameters (NEW - for Grid Integration)
   double            m_python_risk_multiplier;
   double            m_python_confidence;
   bool              m_is_in_cooldown;
   
   // CSM Data (NEW - from Python Brain)
   double            m_csm_usd;
   double            m_csm_eur;
   double            m_csm_gbp;
   double            m_csm_jpy;
   double            m_csm_aud;
   double            m_csm_cad;
   double            m_csm_chf;
   double            m_csm_nzd;
   bool              m_csm_data_received;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CGridConfig()
     {
      // Default Configuration
      m_max_grid_levels = 5;
      m_base_lot = 0.01;
      
      // Multi-Symbol Support
      m_target_symbol = _Symbol;  // Default to chart symbol
      
      // Lot progression (martingale-style)
      m_lot_progression[0] = 1.0;
      m_lot_progression[1] = 1.5;
      m_lot_progression[2] = 2.0;
      m_lot_progression[3] = 3.0;
      m_lot_progression[4] = 4.5;
      
      // Elastic step (in points)
      m_base_elastic_step = 100.0;
      m_current_elastic_step = 100.0;
      
      // State
      m_active_grid_count = 0;
      m_last_grid_price = 0.0;
      m_current_direction = GRID_DIR_NONE;
      
      // Python Brain defaults
      m_python_risk_multiplier = 1.0;
      m_python_confidence = 0.0;
      m_is_in_cooldown = false;
      
      // CSM defaults
      m_csm_usd = 0.0;
      m_csm_eur = 0.0;
      m_csm_gbp = 0.0;
      m_csm_jpy = 0.0;
      m_csm_aud = 0.0;
      m_csm_cad = 0.0;
      m_csm_chf = 0.0;
      m_csm_nzd = 0.0;
      m_csm_data_received = false;
     }
   
   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int GetMaxGridLevels() { return m_max_grid_levels; }
   double GetBaseLot() { return m_base_lot; }
   int GetActiveGridCount() { return m_active_grid_count; }
   ENUM_GRID_DIRECTION GetCurrentDirection() { return m_current_direction; }
   
   // Multi-Symbol Support
   string GetSymbol() { return m_target_symbol; }
   
   //+------------------------------------------------------------------+
   //| Setters                                                          |
   //+------------------------------------------------------------------+
   void SetSymbol(string symbol) 
     { 
      m_target_symbol = symbol; 
     }
   void SetMaxGridLevels(int levels) 
     { 
      m_max_grid_levels = (levels > 0 && levels <= 10) ? levels : 5; 
     }
   
   void SetBaseLot(double lot) 
     { 
      m_base_lot = (lot > 0.0) ? lot : 0.01; 
     }
   
   void SetBaseElasticStep(double step) 
     { 
      m_base_elastic_step = (step > 0.0) ? step : 100.0;
      m_current_elastic_step = m_base_elastic_step;
     }
  };
//+------------------------------------------------------------------+