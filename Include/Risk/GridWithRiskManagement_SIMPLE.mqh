//+------------------------------------------------------------------+
//|                                   GridWithRiskManagement.mqh     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.10"
#property strict

#include "PositionSizingManager.mqh"
#include "DailyLossLimit.mqh"
#include "RiskGuardian.mqh"

struct GridConfig
{
   double grid_step_points;
   int max_grid_levels;
   double base_lot_size;
   bool use_risk_based_lots;
   double risk_per_trade;
};

class CGridWithRiskManagement
{
private:
   string m_symbol;
   GridConfig m_config;
   CPositionSizingManager m_position_sizer;
   CDailyLossLimit m_daily_limit;
   CRiskGuardian m_risk_guardian;
   bool m_initialized;
   int m_magic_number;
   int m_active_orders;
   double m_total_exposure;
   int m_orders_opened;
   int m_orders_closed;
   int m_orders_rejected;
   
public:
   CGridWithRiskManagement(void);
   ~CGridWithRiskManagement(void);
   bool Initialize(string symbol, int magic_number, GridConfig &config);
   bool CanOpenNewPosition(void);
   bool OpenGridLevel(double entry_price, int direction);
   void CloseAllGridPositions(void);
   double CalculateGridLotSize(double entry_price, double stop_loss);
   bool ValidateGridOrder(double lot_size, double entry_price, double stop_loss);
   void UpdateGridState(void);
   void PrintStatus(void);
   int GetActiveOrders(void) const { return m_active_orders; }
   double GetTotalExposure(void) const { return m_total_exposure; }
};

CGridWithRiskManagement::CGridWithRiskManagement(void)
{
   m_symbol = "";
   m_magic_number = 0;
   m_active_orders = 0;
   m_total_exposure = 0.0;
   m_orders_opened = 0;
   m_orders_closed = 0;
   m_orders_rejected = 0;
   m_initialized = false;
}

CGridWithRiskManagement::~CGridWithRiskManagement(void)
{
}

bool CGridWithRiskManagement::Initialize(string symbol, int magic_number, GridConfig &config)
{
   m_symbol = symbol;
   m_magic_number = magic_number;
   m_config = config;
   
   if(!m_position_sizer.Initialize(m_symbol, m_config.risk_per_trade)) return false;
   if(!m_daily_limit.Initialize(4.0)) return false;
   if(!m_risk_guardian.Initialize(m_config.max_grid_levels, 2.0, 15.0, 4.0)) return false;
   
   m_initialized = true;
   Print("Grid with Risk Management initialized");
   return true;
}

bool CGridWithRiskManagement::CanOpenNewPosition(void)
{
   UpdateGridState();
   if(!m_daily_limit.CanTrade()) return false;
   if(m_active_orders >= m_config.max_grid_levels) return false;
   return true;
}

double CGridWithRiskManagement::CalculateGridLotSize(double entry_price, double stop_loss)
{
   if(m_config.use_risk_based_lots)
      return m_position_sizer.CalculateLotSize(entry_price, stop_loss, m_config.risk_per_trade);
   return m_config.base_lot_size;
}

bool CGridWithRiskManagement::ValidateGridOrder(double lot_size, double entry_price, double stop_loss)
{
   if(lot_size <= 0.0)
   {
      m_orders_rejected++;
      return false;
   }
   if(entry_price <= 0.0 || stop_loss <= 0.0)
   {
      m_orders_rejected++;
      return false;
   }
   if(!m_daily_limit.CanTrade())
   {
      m_orders_rejected++;
      return false;
   }
   return true;
}

bool CGridWithRiskManagement::OpenGridLevel(double entry_price, int direction)
{
   if(!CanOpenNewPosition())
   {
      m_orders_rejected++;
      return false;
   }
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double stop_loss = entry_price + (direction * m_config.grid_step_points * point);
   double lot_size = CalculateGridLotSize(entry_price, stop_loss);
   
   if(!ValidateGridOrder(lot_size, entry_price, stop_loss)) return false;
   
   Print("Opening Grid Level: ", m_active_orders + 1, "/", m_config.max_grid_levels);
   
   m_orders_opened++;
   m_active_orders++;
   
   // FIXED: Only 1 parameter for UpdateTrade
   m_daily_limit.UpdateTrade(0.0);
   
   return true;
}

void CGridWithRiskManagement::CloseAllGridPositions(void)
{
   int closed = m_active_orders;
   m_active_orders = 0;
   m_total_exposure = 0.0;
   m_orders_closed += closed;
   Print("Closed ", closed, " grid positions");
}

void CGridWithRiskManagement::UpdateGridState(void)
{
   m_total_exposure = m_active_orders * m_config.base_lot_size;
}

void CGridWithRiskManagement::PrintStatus(void)
{
   UpdateGridState();
   
   Print("=== GRID STATUS ===");
   Print("Symbol: ", m_symbol);
   Print("Active Orders: ", m_active_orders, "/", m_config.max_grid_levels);
   Print("Orders Opened: ", m_orders_opened);
   Print("Orders Rejected: ", m_orders_rejected);
   
   double rate = 0.0;
   int total = m_orders_opened + m_orders_rejected;
   if(total > 0) rate = (m_orders_opened * 100.0) / total;
   Print("Approval Rate: ", rate, "%");
   
   Print("Daily PnL: $", m_daily_limit.GetDailyPnL());
   Print("Remaining: $", m_daily_limit.GetRemainingLoss());
   
   bool reached = m_daily_limit.IsLimitReached();
   if(reached)
      Print("Daily Limit: REACHED");
   else
      Print("Daily Limit: OK");
   
   Print("==================");
}
