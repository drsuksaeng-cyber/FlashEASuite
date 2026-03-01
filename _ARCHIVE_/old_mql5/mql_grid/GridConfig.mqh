//+------------------------------------------------------------------+
//|                                               Grid/GridConfig.mqh |
//|                                      FlashEASuite V2 - Program C |
//|                Elastic Grid Strategy - Configuration Module       |
//+------------------------------------------------------------------+
#property strict

#include "../StrategyBase.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enum: Grid Direction                                             |
//+------------------------------------------------------------------+
enum ENUM_GRID_DIRECTION
  {
   GRID_DIR_NONE = 0,      // No direction set
   GRID_DIR_BUY  = 1,      // Only open BUY grids
   GRID_DIR_SELL = -1      // Only open SELL grids
  };

//+------------------------------------------------------------------+
//| Struct: Grid Order Info                                          |
//+------------------------------------------------------------------+
struct GridOrder
  {
   ulong             ticket;         // Position ticket
   double            open_price;     // Entry price
   double            lot_size;       // Lot size
   datetime          open_time;      // Open time
   int               level;          // Grid level (0, 1, 2, ...)
  };

//+------------------------------------------------------------------+
//| Class: CGridConfig                                               |
//| Grid Configuration and Parameter Management                      |
//+------------------------------------------------------------------+
class CGridConfig
  {
protected:
   // --- Modules ---
   CTrade            m_trade;                     // Trade execution
   int               m_atr_handle;                // ATR indicator handle
   
   // --- Parameters (Inputs) ---
   int               m_grid_max_orders;           // Maximum grid orders
   double            m_base_step_points;          // Base grid step (points)
   double            m_lot_multiplier;            // Lot multiplier per level
   double            m_base_lot;                  // Base lot size
   int               m_atr_period;                // ATR period
   double            m_atr_reference;             // Reference ATR value
   double            m_sl_points;                 // Stop loss (points)
   double            m_tp_points;                 // Take profit (points)
   
   // --- Dynamic Risk Management (From Python) ---
   double            m_risk_multiplier;           // From Policy (0.5x - 1.5x)
   bool              m_is_in_cooldown;            // Cooldown flag from Policy
   double            m_confidence_score;          // Confidence from Policy
   
   // --- Grid State ---
   ENUM_GRID_DIRECTION m_grid_direction;         // Current grid direction
   GridOrder         m_grid_orders[10];           // Array of active grid positions (fixed size)
   int               m_active_grid_count;         // Number of active grid orders
   double            m_last_grid_price;           // Last grid level price
   double            m_current_atr;               // Current ATR value
   double            m_elastic_step;              // Current elastic step size
   
   // --- CSM Data (From ZMQ Policy) ---
   double            m_csm_usd;                   // USD strength
   double            m_csm_eur;                   // EUR strength (example)
   bool              m_csm_data_received;         // Flag for CSM availability

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
   CGridConfig()
     {
      // Default Configuration
      m_grid_max_orders = 5;                    // Max 5 grid levels
      m_base_step_points = 200;                 // 20 pips base (for XAUUSD)
      m_lot_multiplier = 1.5;                   // Multiply lot by 1.5x each level
      m_base_lot = 0.01;                        // Start with 0.01 lot
      m_atr_period = 14;                        // Standard ATR period
      m_atr_reference = 30.0;                   // Reference ATR (30 points)
      m_sl_points = 500;                        // 50 pips SL
      m_tp_points = 300;                        // 30 pips TP
      
      // Initialize Dynamic Variables
      m_risk_multiplier = 1.0;                  // Default 1.0x
      m_is_in_cooldown = false;                 // Not in cooldown
      m_confidence_score = 0.5;                 // Medium confidence
      
      // Initialize Grid State
      m_grid_direction = GRID_DIR_NONE;
      m_active_grid_count = 0;
      m_last_grid_price = 0.0;
      m_current_atr = 0.0;
      m_elastic_step = 0.0;
      
      // Initialize CSM
      m_csm_usd = 0.0;
      m_csm_eur = 0.0;
      m_csm_data_received = false;
      
      // Initialize ATR Indicator
      m_atr_handle = iATR(_Symbol, PERIOD_M15, m_atr_period);
      if(m_atr_handle == INVALID_HANDLE)
        {
         Print("[Grid] ERROR: Failed to create ATR indicator!");
        }
      
      // Initialize grid orders array (manual initialization for struct)
      for(int i = 0; i < 10; i++)
        {
         m_grid_orders[i].ticket = 0;
         m_grid_orders[i].open_price = 0.0;
         m_grid_orders[i].lot_size = 0.0;
         m_grid_orders[i].open_time = 0;
         m_grid_orders[i].level = 0;
        }
     }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
   ~CGridConfig()
     {
      if(m_atr_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr_handle);
     }
   
   //+------------------------------------------------------------------+
   //| Update Configuration                                             |
   //+------------------------------------------------------------------+
   void UpdateConfig(int max_orders, double base_step, double lot_mult)
     {
      m_grid_max_orders = max_orders;
      m_base_step_points = base_step;
      m_lot_multiplier = lot_mult;
     }
   
   //+------------------------------------------------------------------+
   //| Update Policy Data (From Python Brain)                          |
   //+------------------------------------------------------------------+
   void UpdatePolicyData(double risk_mult, bool cooldown, double confidence)
     {
      m_risk_multiplier = risk_mult;
      m_is_in_cooldown = cooldown;
      m_confidence_score = confidence;
      
      // Log policy update
      if(m_is_in_cooldown)
        {
         Print("[Grid] Policy Update: IN COOLDOWN - Grid paused");
        }
      else
        {
         Print("[Grid] Policy Update: Risk=", m_risk_multiplier, 
               "x, Confidence=", DoubleToString(m_confidence_score, 2));
        }
     }
   
   //+------------------------------------------------------------------+
   //| Update CSM Data (From ZMQ Policy)                               |
   //+------------------------------------------------------------------+
   void UpdateCSMData(double usd_strength, double eur_strength)
     {
      m_csm_usd = usd_strength;
      m_csm_eur = eur_strength;
      m_csm_data_received = true;
     }
   
   //+------------------------------------------------------------------+
   //| Get Recommended SL                                               |
   //+------------------------------------------------------------------+
   double GetRecommendedSL()
     {
      return m_sl_points;
     }
   
   //+------------------------------------------------------------------+
   //| Get Recommended TP                                               |
   //+------------------------------------------------------------------+
   double GetRecommendedTP()
     {
      return m_tp_points;
     }
  };
//+------------------------------------------------------------------+
