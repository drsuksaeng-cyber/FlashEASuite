//+------------------------------------------------------------------+
//|                                   GridWithRiskManagement.mqh     |
//|                                  FlashEASuite V2.1 - Option A    |
//|                           Grid Trading + Risk Management         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/your-repo"
#property version   "2.10"
#property strict

// Include Risk Management modules
#include "PositionSizingManager.mqh"
#include "DailyLossLimit.mqh"
#include "RiskGuardian.mqh"

//+------------------------------------------------------------------+
//| Grid Configuration Structure                                      |
//+------------------------------------------------------------------+
struct GridConfig
{
   double            grid_step_points;      // Grid step in points
   int               max_grid_levels;       // Maximum grid levels
   double            base_lot_size;         // Base lot size (will be overridden by risk calc)
   bool              use_risk_based_lots;   // Use risk-based position sizing
   double            risk_per_trade;        // Risk % per trade (for position sizing)
};

//+------------------------------------------------------------------+
//| Grid Trading with Risk Management Class                          |
//+------------------------------------------------------------------+
class CGridWithRiskManagement
{
private:
   // Symbol & Configuration
   string            m_symbol;
   GridConfig        m_config;
   
   // Risk Management Components
   CPositionSizingManager* m_position_sizer;
   CDailyLossLimit*  m_daily_limit;
   CRiskGuardian*    m_risk_guardian;
   
   // Grid State
   int               m_magic_number;
   int               m_active_orders;
   double            m_total_exposure;
   
   // Statistics
   int               m_orders_opened;
   int               m_orders_closed;
   int               m_orders_rejected;
   
public:
   //--- Constructor
   CGridWithRiskManagement(void);
   
   //--- Destructor
   ~CGridWithRiskManagement(void);
   
   //--- Initialization
   bool              Initialize(string symbol, int magic_number, GridConfig &config);
   
   //--- Main Trading Functions
   bool              CanOpenNewPosition(void);
   bool              OpenGridLevel(double entry_price, int direction);
   void              CloseAllGridPositions(void);
   
   //--- Risk Management
   double            CalculateGridLotSize(double entry_price, double stop_loss);
   bool              ValidateGridOrder(double lot_size, double entry_price, double stop_loss);
   
   //--- Information
   void              UpdateGridState(void);
   void              PrintStatus(void);
   int               GetActiveOrders(void) const { return m_active_orders; }
   double            GetTotalExposure(void) const { return m_total_exposure; }
   
private:
   void              UpdateStatistics(void);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridWithRiskManagement::CGridWithRiskManagement(void)
{
   m_symbol = "";
   m_magic_number = 0;
   m_active_orders = 0;
   m_total_exposure = 0.0;
   m_orders_opened = 0;
   m_orders_closed = 0;
   m_orders_rejected = 0;
   
   m_position_sizer = NULL;
   m_daily_limit = NULL;
   m_risk_guardian = NULL;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridWithRiskManagement::~CGridWithRiskManagement(void)
{
   if(m_position_sizer != NULL)
   {
      delete m_position_sizer;
      m_position_sizer = NULL;
   }
   
   if(m_daily_limit != NULL)
   {
      delete m_daily_limit;
      m_daily_limit = NULL;
   }
   
   if(m_risk_guardian != NULL)
   {
      delete m_risk_guardian;
      m_risk_guardian = NULL;
   }
}

//+------------------------------------------------------------------+
//| Initialize Grid with Risk Management                             |
//+------------------------------------------------------------------+
bool CGridWithRiskManagement::Initialize(string symbol, int magic_number, GridConfig &config)
{
   m_symbol = symbol;
   m_magic_number = magic_number;
   m_config = config;
   
   Print("🔧 Initializing Grid with Risk Management...");
   Print("   Symbol: ", m_symbol);
   Print("   Magic Number: ", m_magic_number);
   Print("   Grid Step: ", m_config.grid_step_points, " points");
   Print("   Max Levels: ", m_config.max_grid_levels);
   
   // Initialize Position Sizing Manager
   m_position_sizer = new CPositionSizingManager();
   if(!m_position_sizer.Initialize(m_symbol, m_config.risk_per_trade))
   {
      Print("❌ Failed to initialize Position Sizing Manager");
      return false;
   }
   
   // Initialize Daily Loss Limit
   m_daily_limit = new CDailyLossLimit();
   if(!m_daily_limit.Initialize(4.0)) // 4% daily limit
   {
      Print("❌ Failed to initialize Daily Loss Limit");
      return false;
   }
   
   // Initialize Risk Guardian
   m_risk_guardian = new CRiskGuardian();
   if(!m_risk_guardian.Initialize(m_config.max_grid_levels, 2.0, 15.0, 4.0))
   {
      Print("❌ Failed to initialize Risk Guardian");
      return false;
   }
   
   // Link components
   m_risk_guardian.SetPositionSizingManager(m_position_sizer);
   m_risk_guardian.SetDailyLossLimit(m_daily_limit);
   
   Print("✅ Grid with Risk Management initialized successfully");
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if can open new position                                   |
//+------------------------------------------------------------------+
bool CGridWithRiskManagement::CanOpenNewPosition(void)
{
   // Update grid state
   UpdateGridState();
   
   // Check 1: Daily loss limit
   if(!m_daily_limit.CanTrade())
   {
      Print("⛔ Cannot open position: Daily loss limit reached");
      return false;
   }
   
   // Check 2: Max grid levels
   if(m_active_orders >= m_config.max_grid_levels)
   {
      Print("⛔ Cannot open position: Max grid levels reached (", m_active_orders, "/", m_config.max_grid_levels, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate grid lot size with risk management                     |
//+------------------------------------------------------------------+
double CGridWithRiskManagement::CalculateGridLotSize(double entry_price, double stop_loss)
{
   if(m_config.use_risk_based_lots)
   {
      // Use position sizing manager (1% risk)
      double lot_size = m_position_sizer.CalculateLotSize(entry_price, stop_loss, m_config.risk_per_trade);
      
      if(lot_size > 0.0)
      {
         Print("📊 Risk-based lot size: ", DoubleToString(lot_size, 2), 
               " (Entry: ", DoubleToString(entry_price, 5), 
               ", SL: ", DoubleToString(stop_loss, 5), ")");
      }
      
      return lot_size;
   }
   else
   {
      // Use fixed base lot
      return m_config.base_lot_size;
   }
}

//+------------------------------------------------------------------+
//| Validate grid order with Risk Guardian                           |
//+------------------------------------------------------------------+
bool CGridWithRiskManagement::ValidateGridOrder(double lot_size, double entry_price, double stop_loss)
{
   // Create trade validation structure (simplified for now)
   // In real implementation, this would use RiskGuardian.ValidateTrade()
   
   // Check lot size is valid
   if(lot_size <= 0.0)
   {
      Print("❌ Invalid lot size: ", lot_size);
      m_orders_rejected++;
      return false;
   }
   
   // Check prices are valid
   if(entry_price <= 0.0 || stop_loss <= 0.0)
   {
      Print("❌ Invalid prices: Entry=", entry_price, " SL=", stop_loss);
      m_orders_rejected++;
      return false;
   }
   
   // Check daily limit
   if(!m_daily_limit.CanTrade())
   {
      Print("❌ Daily loss limit reached");
      m_orders_rejected++;
      return false;
   }
   
   // All checks passed
   return true;
}

//+------------------------------------------------------------------+
//| Open grid level                                                   |
//+------------------------------------------------------------------+
bool CGridWithRiskManagement::OpenGridLevel(double entry_price, int direction)
{
   // Check if can open
   if(!CanOpenNewPosition())
   {
      m_orders_rejected++;
      return false;
   }
   
   // Calculate stop loss (grid step distance)
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double stop_loss = entry_price + (direction * m_config.grid_step_points * point);
   
   // Calculate lot size
   double lot_size = CalculateGridLotSize(entry_price, stop_loss);
   
   // Validate order
   if(!ValidateGridOrder(lot_size, entry_price, stop_loss))
   {
      return false;
   }
   
   // Simulate order opening (in real EA, use OrderSend)
   // PATCH 1: Fix ternary operator (Line 86 area)
   string direction_text = "BUY";
   if(direction <= 0) direction_text = "SELL";
   
   Print("📈 Opening Grid Level:");
   Print("   Direction: ", direction_text);
   Print("   Entry: ", DoubleToString(entry_price, 5));
   Print("   Stop Loss: ", DoubleToString(stop_loss, 5));
   Print("   Lot Size: ", DoubleToString(lot_size, 2));
   Print("   Grid Level: ", m_active_orders + 1, "/", m_config.max_grid_levels);
   
   // Update statistics
   m_orders_opened++;
   m_active_orders++;
   
   // PATCH 2: Fix UpdateTrade parameters (Line 138 area)
   // UpdateTrade requires: (double profit, bool is_win)
   m_daily_limit.UpdateTrade(0.0, true);
   
   Print("✅ Grid level opened successfully");
   
   return true;
}

//+------------------------------------------------------------------+
//| Close all grid positions                                          |
//+------------------------------------------------------------------+
void CGridWithRiskManagement::CloseAllGridPositions(void)
{
   Print("🔄 Closing all grid positions...");
   
   // In real implementation, loop through all orders with m_magic_number and close
   
   // Simulate closing
   int closed = m_active_orders;
   m_active_orders = 0;
   m_total_exposure = 0.0;
   m_orders_closed += closed;
   
   Print("✅ Closed ", closed, " grid positions");
}

//+------------------------------------------------------------------+
//| Update grid state                                                 |
//+------------------------------------------------------------------+
void CGridWithRiskManagement::UpdateGridState(void)
{
   // In real implementation, count orders from MT5
   // For now, we already track m_active_orders
   
   // Calculate total exposure
   m_total_exposure = m_active_orders * m_config.base_lot_size;
}

//+------------------------------------------------------------------+
//| Update statistics                                                 |
//+------------------------------------------------------------------+
void CGridWithRiskManagement::UpdateStatistics(void)
{
   // Placeholder for future statistics tracking
}

//+------------------------------------------------------------------+
//| Print current status                                              |
//+------------------------------------------------------------------+
void CGridWithRiskManagement::PrintStatus(void)
{
   UpdateGridState();
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║           GRID WITH RISK MANAGEMENT STATUS                ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   Print("");
   
   // Grid Status
   Print("📊 Grid Status:");
   Print("   Symbol: ", m_symbol);
   Print("   Magic Number: ", m_magic_number);
   Print("   Active Orders: ", m_active_orders, "/", m_config.max_grid_levels);
   Print("   Total Exposure: ", DoubleToString(m_total_exposure, 2), " lots");
   Print("   Grid Step: ", m_config.grid_step_points, " points");
   Print("");
   
   // Statistics
   Print("📈 Statistics:");
   Print("   Orders Opened: ", m_orders_opened);
   Print("   Orders Closed: ", m_orders_closed);
   Print("   Orders Rejected: ", m_orders_rejected);
   
   // PATCH 3: Fix ternary operator (Line 110 area)
   double approval_rate = 0.0;
   if(m_orders_opened + m_orders_rejected > 0)
   {
      approval_rate = m_orders_opened * 100.0 / (m_orders_opened + m_orders_rejected);
   }
   Print("   Approval Rate: ", DoubleToString(approval_rate, 1), "%");
   Print("");
   
   // Risk Management Status
   Print("🛡️ Risk Management:");
   
   if(m_position_sizer != NULL)
   {
      Print("   Position Sizing: ✅ Active (", DoubleToString(m_config.risk_per_trade, 1), "% risk)");
   }
   
   if(m_daily_limit != NULL)
   {
      // PATCH 4: Fix ternary operator (Line 173 area)
      string limit_status = "✅ OK";
      if(m_daily_limit.IsLimitReached()) limit_status = "⚠️ REACHED";
      
      Print("   Daily Loss Limit: ", limit_status);
      Print("   Daily P&L: $", DoubleToString(m_daily_limit.GetDailyPnL(), 2));
      Print("   Remaining: $", DoubleToString(m_daily_limit.GetRemainingLoss(), 2));
   }
   
   if(m_risk_guardian != NULL)
   {
      Print("   Risk Guardian: ✅ Active");
   }
   
   Print("═══════════════════════════════════════════════════════════");
}
