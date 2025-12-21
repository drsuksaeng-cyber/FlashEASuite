//+------------------------------------------------------------------+
//|                                           GridRiskManager.mqh    |
//|                                  Grid Standalone Strategy V2     |
//|                            NEW! Advanced Risk Management Module   |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property link      ""
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Grid Risk Manager - Cash Buffer & Emergency Exit                 |
//+------------------------------------------------------------------+
class CGridRiskManager
{
private:
   // Cash Buffer Management
   double   m_cash_buffer_percent;       // Reserve % (default 30%)
   double   m_max_capital_usage;         // Max usage % (default 70%)
   double   m_initial_capital;           // Starting capital
   
   // Emergency Exit
   double   m_emergency_dd_threshold;    // DD% to trigger emergency (default 20%)
   int      m_emergency_cooldown_sec;    // Cooldown period (default 300)
   bool     m_emergency_triggered;       // Emergency state
   datetime m_emergency_time;            // When triggered
   
   // Drawdown tracking
   double   m_peak_balance;              // Peak balance achieved
   double   m_peak_equity;               // Peak equity achieved
   double   m_current_dd_percent;        // Current DD%
   double   m_max_dd_percent;            // Max DD ever
   
   // Capital tracking
   double   m_used_margin;               // Current margin used
   double   m_usage_percent;             // Current usage %
   
   // Statistics
   int      m_emergency_count;           // Times emergency triggered
   datetime m_last_emergency_reset;      // Last reset time
   
   // Trade management (for emergency exit)
   string   m_symbol;
   int      m_magic_number;
   
public:
   CGridRiskManager();
   ~CGridRiskManager();
   
   // Initialization
   bool     Initialize(string symbol, int magic = 0);
   
   // Configuration
   void     SetCashBuffer(double percent);
   void     SetEmergencyDD(double dd_percent);
   void     SetEmergencyCooldown(int seconds);
   
   // Capital management
   double   GetAvailableCapital() const;
   double   GetReservedCapital() const;
   double   GetUsedCapital() const;
   double   GetUsagePercent() const;
   bool     CanUseCapital(double required_margin);
   
   // Emergency management
   bool     CheckEmergencyCondition();
   bool     TriggerEmergencyExit();
   void     ResetEmergency();
   bool     IsEmergencyActive() const { return m_emergency_triggered; }
   bool     IsCooldownActive() const;
   int      GetRemainingCooldown() const;
   
   // Drawdown tracking
   void     UpdateDrawdown();
   double   GetCurrentDD() const { return m_current_dd_percent; }
   double   GetMaxDD() const { return m_max_dd_percent; }
   double   GetPeakBalance() const { return m_peak_balance; }
   
   // Update
   bool     Update();
   
   // Statistics
   int      GetEmergencyCount() const { return m_emergency_count; }
   void     PrintStatus() const;
   
private:
   // Internal methods
   double   CalculateDrawdown();
   bool     CloseAllPositions();
   bool     CancelAllPendingOrders();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CGridRiskManager::CGridRiskManager() : m_cash_buffer_percent(30.0),
                                        m_max_capital_usage(70.0),
                                        m_initial_capital(0.0),
                                        m_emergency_dd_threshold(20.0),
                                        m_emergency_cooldown_sec(300),
                                        m_emergency_triggered(false),
                                        m_emergency_time(0),
                                        m_peak_balance(0.0),
                                        m_peak_equity(0.0),
                                        m_current_dd_percent(0.0),
                                        m_max_dd_percent(0.0),
                                        m_used_margin(0.0),
                                        m_usage_percent(0.0),
                                        m_emergency_count(0),
                                        m_last_emergency_reset(0),
                                        m_symbol(""),
                                        m_magic_number(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CGridRiskManager::~CGridRiskManager()
{
}

//+------------------------------------------------------------------+
//| Initialize risk manager                                           |
//+------------------------------------------------------------------+
bool CGridRiskManager::Initialize(string symbol, int magic = 0)
{
   m_symbol = symbol;
   m_magic_number = magic;
   
   // Store initial capital
   m_initial_capital = AccountInfoDouble(ACCOUNT_BALANCE);
   m_peak_balance = m_initial_capital;
   m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   Print("[RiskMgr] Initialized:");
   Print("  Symbol: ", m_symbol);
   Print("  Initial Capital: $", DoubleToString(m_initial_capital, 2));
   Print("  Cash Buffer: ", DoubleToString(m_cash_buffer_percent, 1), "%");
   Print("  Emergency DD: ", DoubleToString(m_emergency_dd_threshold, 1), "%");
   
   return true;
}

//+------------------------------------------------------------------+
//| Set cash buffer percent                                           |
//+------------------------------------------------------------------+
void CGridRiskManager::SetCashBuffer(double percent)
{
   if(percent < 0.0) percent = 0.0;
   if(percent > 50.0) percent = 50.0;
   
   m_cash_buffer_percent = percent;
   m_max_capital_usage = 100.0 - percent;
   
   Print("[RiskMgr] Cash buffer set: ", DoubleToString(percent, 1), "%");
}

//+------------------------------------------------------------------+
//| Set emergency DD threshold                                        |
//+------------------------------------------------------------------+
void CGridRiskManager::SetEmergencyDD(double dd_percent)
{
   if(dd_percent < 5.0) dd_percent = 5.0;
   if(dd_percent > 90.0) dd_percent = 90.0;
   
   m_emergency_dd_threshold = dd_percent;
   
   Print("[RiskMgr] Emergency DD set: ", DoubleToString(dd_percent, 1), "%");
}

//+------------------------------------------------------------------+
//| Set emergency cooldown                                            |
//+------------------------------------------------------------------+
void CGridRiskManager::SetEmergencyCooldown(int seconds)
{
   if(seconds < 60) seconds = 60;
   if(seconds > 3600) seconds = 3600;
   
   m_emergency_cooldown_sec = seconds;
   
   Print("[RiskMgr] Emergency cooldown set: ", seconds, " seconds");
}

//+------------------------------------------------------------------+
//| Get available capital for trading                                 |
//+------------------------------------------------------------------+
double CGridRiskManager::GetAvailableCapital() const
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return balance * m_max_capital_usage / 100.0;
}

//+------------------------------------------------------------------+
//| Get reserved capital                                              |
//+------------------------------------------------------------------+
double CGridRiskManager::GetReservedCapital() const
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return balance * m_cash_buffer_percent / 100.0;
}

//+------------------------------------------------------------------+
//| Get used capital (margin)                                         |
//+------------------------------------------------------------------+
double CGridRiskManager::GetUsedCapital() const
{
   return AccountInfoDouble(ACCOUNT_MARGIN);
}

//+------------------------------------------------------------------+
//| Get capital usage percent                                         |
//+------------------------------------------------------------------+
double CGridRiskManager::GetUsagePercent() const
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return 0.0;
   
   double used = GetUsedCapital();
   return (used / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Check if can use additional capital                               |
//+------------------------------------------------------------------+
bool CGridRiskManager::CanUseCapital(double required_margin)
{
   double current_usage = GetUsedCapital();
   double max_allowed = GetAvailableCapital();
   double total_usage = current_usage + required_margin;
   
   if(total_usage > max_allowed)
   {
      Print("[RiskMgr] ❌ Cannot use capital:");
      Print("  Current usage: $", DoubleToString(current_usage, 2));
      Print("  Required: $", DoubleToString(required_margin, 2));
      Print("  Total would be: $", DoubleToString(total_usage, 2));
      Print("  Max allowed: $", DoubleToString(max_allowed, 2));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate current drawdown                                        |
//+------------------------------------------------------------------+
double CGridRiskManager::CalculateDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Use lower of balance/equity
   double current = MathMin(balance, equity);
   
   // Update peaks
   if(balance > m_peak_balance) m_peak_balance = balance;
   if(equity > m_peak_equity) m_peak_equity = equity;
   
   // Calculate DD from peak
   double peak = MathMax(m_peak_balance, m_peak_equity);
   if(peak <= 0) return 0.0;
   
   double dd = (peak - current) / peak * 100.0;
   if(dd < 0) dd = 0.0;
   
   return dd;
}

//+------------------------------------------------------------------+
//| Update drawdown tracking                                          |
//+------------------------------------------------------------------+
void CGridRiskManager::UpdateDrawdown()
{
   m_current_dd_percent = CalculateDrawdown();
   
   if(m_current_dd_percent > m_max_dd_percent)
   {
      m_max_dd_percent = m_current_dd_percent;
      Print("[RiskMgr] ⚠️ New max DD: ", DoubleToString(m_max_dd_percent, 2), "%");
   }
   
   // Update capital usage
   m_used_margin = GetUsedCapital();
   m_usage_percent = GetUsagePercent();
}

//+------------------------------------------------------------------+
//| Check emergency condition                                         |
//+------------------------------------------------------------------+
bool CGridRiskManager::CheckEmergencyCondition()
{
   // Already in emergency?
   if(m_emergency_triggered)
      return true;
   
   // Update DD
   UpdateDrawdown();
   
   // Check if DD exceeds threshold
   if(m_current_dd_percent >= m_emergency_dd_threshold)
   {
      Print("[RiskMgr] 🚨 EMERGENCY CONDITION MET!");
      Print("  Current DD: ", DoubleToString(m_current_dd_percent, 2), "%");
      Print("  Threshold: ", DoubleToString(m_emergency_dd_threshold, 2), "%");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Trigger emergency exit                                            |
//+------------------------------------------------------------------+
bool CGridRiskManager::TriggerEmergencyExit()
{
   if(m_emergency_triggered)
   {
      Print("[RiskMgr] ⚠️ Emergency already active");
      return false;
   }
   
   Print("[RiskMgr] 🚨🚨🚨 EMERGENCY EXIT TRIGGERED 🚨🚨🚨");
   Print("  Drawdown: ", DoubleToString(m_current_dd_percent, 2), "%");
   Print("  Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   
   // Close all positions
   bool positions_closed = CloseAllPositions();
   
   // Cancel all pending orders
   bool orders_cancelled = CancelAllPendingOrders();
   
   // Set emergency state
   m_emergency_triggered = true;
   m_emergency_time = TimeCurrent();
   m_emergency_count++;
   
   Print("[RiskMgr] Emergency actions:");
   Print("  Positions closed: ", positions_closed ? "✅" : "❌");
   Print("  Orders cancelled: ", orders_cancelled ? "✅" : "❌");
   Print("  Cooldown: ", m_emergency_cooldown_sec, " seconds");
   Print("  Total emergencies: ", m_emergency_count);
   
   return true;
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
bool CGridRiskManager::CloseAllPositions()
{
   int total = PositionsTotal();
   int closed = 0;
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            string pos_symbol = PositionGetString(POSITION_SYMBOL);
            int pos_magic = (int)PositionGetInteger(POSITION_MAGIC);
            
            // Check if our position
            if(pos_symbol == m_symbol && (m_magic_number == 0 || pos_magic == m_magic_number))
            {
               CTrade trade;
               if(trade.PositionClose(ticket))
               {
                  closed++;
                  Print("[RiskMgr] Closed position #", ticket);
               }
               else
               {
                  Print("[RiskMgr] ❌ Failed to close #", ticket, ": ", GetLastError());
               }
            }
         }
      }
   }
   
   Print("[RiskMgr] Closed ", closed, " / ", total, " positions");
   return (closed > 0);
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                         |
//+------------------------------------------------------------------+
bool CGridRiskManager::CancelAllPendingOrders()
{
   int total = OrdersTotal();
   int cancelled = 0;
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderSelect(ticket))
         {
            string order_symbol = OrderGetString(ORDER_SYMBOL);
            int order_magic = (int)OrderGetInteger(ORDER_MAGIC);
            
            // Check if our order
            if(order_symbol == m_symbol && (m_magic_number == 0 || order_magic == m_magic_number))
            {
               CTrade trade;
               if(trade.OrderDelete(ticket))
               {
                  cancelled++;
                  Print("[RiskMgr] Cancelled order #", ticket);
               }
               else
               {
                  Print("[RiskMgr] ❌ Failed to cancel #", ticket, ": ", GetLastError());
               }
            }
         }
      }
   }
   
   Print("[RiskMgr] Cancelled ", cancelled, " / ", total, " orders");
   return true; // Always return true even if no orders
}

//+------------------------------------------------------------------+
//| Reset emergency state                                             |
//+------------------------------------------------------------------+
void CGridRiskManager::ResetEmergency()
{
   m_emergency_triggered = false;
   m_last_emergency_reset = TimeCurrent();
   
   Print("[RiskMgr] ✅ Emergency reset - Trading resumed");
   Print("  Time: ", TimeToString(m_last_emergency_reset, TIME_DATE|TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Check if cooldown active                                          |
//+------------------------------------------------------------------+
bool CGridRiskManager::IsCooldownActive() const
{
   if(!m_emergency_triggered) return false;
   
   int elapsed = (int)(TimeCurrent() - m_emergency_time);
   return (elapsed < m_emergency_cooldown_sec);
}

//+------------------------------------------------------------------+
//| Get remaining cooldown seconds                                    |
//+------------------------------------------------------------------+
int CGridRiskManager::GetRemainingCooldown() const
{
   if(!m_emergency_triggered) return 0;
   
   int elapsed = (int)(TimeCurrent() - m_emergency_time);
   int remaining = m_emergency_cooldown_sec - elapsed;
   
   return (remaining > 0) ? remaining : 0;
}

//+------------------------------------------------------------------+
//| Update risk manager                                               |
//+------------------------------------------------------------------+
bool CGridRiskManager::Update()
{
   UpdateDrawdown();
   
   // Auto-reset emergency if cooldown expired
   if(m_emergency_triggered && !IsCooldownActive())
   {
      ResetEmergency();
   }
   
   // Check emergency condition
   if(CheckEmergencyCondition() && !m_emergency_triggered)
   {
      TriggerEmergencyExit();
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Print status                                                      |
//+------------------------------------------------------------------+
void CGridRiskManager::PrintStatus() const
{
   Print("═══════════════════════════════════════════");
   Print("RISK MANAGER STATUS");
   Print("═══════════════════════════════════════════");
   Print("Capital:");
   Print("  Initial: $", DoubleToString(m_initial_capital, 2));
   Print("  Peak: $", DoubleToString(m_peak_balance, 2));
   Print("  Available: $", DoubleToString(GetAvailableCapital(), 2));
   Print("  Reserved: $", DoubleToString(GetReservedCapital(), 2));
   Print("  Used: $", DoubleToString(m_used_margin, 2), 
         " (", DoubleToString(m_usage_percent, 1), "%)");
   
   Print("Drawdown:");
   Print("  Current: ", DoubleToString(m_current_dd_percent, 2), "%");
   Print("  Max: ", DoubleToString(m_max_dd_percent, 2), "%");
   Print("  Threshold: ", DoubleToString(m_emergency_dd_threshold, 2), "%");
   
   Print("Emergency:");
   Print("  Status: ", m_emergency_triggered ? "🚨 ACTIVE" : "✅ Normal");
   if(m_emergency_triggered)
   {
      Print("  Cooldown: ", GetRemainingCooldown(), " seconds remaining");
   }
   Print("  Total count: ", m_emergency_count);
   Print("═══════════════════════════════════════════");
}
