//+------------------------------------------------------------------+
//|                              Grid/GridCostCalculator.mqh         |
//|                                    FlashEASuite V2 - Week 6      |
//|        Spread, Swap, Commission Calculator (หลุมพรางค่าธรรมเนียม)|
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Cost Breakdown Structure                                         |
//+------------------------------------------------------------------+
struct TradingCosts
{
    double   total_spread_cost;      // รวม spread ทั้งหมด
    double   total_swap_cost;        // รวม swap ทั้งหมด
    double   total_commission;       // รวม commission ทั้งหมด
    double   total_cost;             // รวมค่าใช้จ่ายทั้งหมด
    
    double   avg_spread_per_trade;   // Spread เฉลี่ยต่อ trade
    double   avg_swap_per_day;       // Swap เฉลี่ยต่อวัน
    
    int      total_trades;           // จำนวน trade ทั้งหมด
    int      trades_with_swap;       // จำนวน trade ที่มี swap
    
    double   cost_to_profit_ratio;   // ค่าใช้จ่าย / กำไร (%)
};

//+------------------------------------------------------------------+
//| Grid Cost Calculator Class                                       |
//+------------------------------------------------------------------+
class CGridCostCalculator
{
private:
    string   m_symbol;
    
    // Cost tracking
    double   m_total_spread_cost;
    double   m_total_swap_cost;
    double   m_total_commission;
    int      m_total_trades;
    int      m_trades_with_swap;
    
    // Current market conditions
    double   m_current_spread_points;
    double   m_current_spread_cost;
    double   m_avg_spread_points;
    
    // Swap rates
    double   m_swap_long;          // Swap rate for long positions
    double   m_swap_short;         // Swap rate for short positions
    
    // Simulation parameters
    bool     m_use_high_spread;    // ทดสอบ spread สูง
    double   m_spread_multiplier;  // ขยาย spread เท่าไร (1.0 = normal, 2.0 = double)
    
    // Warning thresholds
    double   m_max_acceptable_spread_points;  // Default: 30 points
    double   m_max_cost_to_profit_pct;        // Default: 20%
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridCostCalculator(string symbol = "")
    {
        m_symbol = (symbol == "") ? _Symbol : symbol;
        
        m_total_spread_cost = 0;
        m_total_swap_cost = 0;
        m_total_commission = 0;
        m_total_trades = 0;
        m_trades_with_swap = 0;
        
        m_current_spread_points = 0;
        m_current_spread_cost = 0;
        m_avg_spread_points = 0;
        
        m_swap_long = 0;
        m_swap_short = 0;
        
        m_use_high_spread = false;
        m_spread_multiplier = 1.0;
        
        m_max_acceptable_spread_points = 30.0;
        m_max_cost_to_profit_pct = 20.0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                       |
    //+------------------------------------------------------------------+
    bool Initialize()
    {
        // Get swap rates
        m_swap_long = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG);
        m_swap_short = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT);
        
        Print("✅ Cost Calculator initialized");
        Print("   Swap Long: ", DoubleToString(m_swap_long, 2));
        Print("   Swap Short: ", DoubleToString(m_swap_short, 2));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update Current Spread                                           |
    //+------------------------------------------------------------------+
    void UpdateSpread()
    {
        MqlTick tick;
        if(!SymbolInfoTick(m_symbol, tick))
            return;
        
        // Calculate spread in points
        double spread = (tick.ask - tick.bid) / _Point;
        
        // Apply multiplier if testing high spread
        if(m_use_high_spread)
        {
            spread *= m_spread_multiplier;
        }
        
        m_current_spread_points = spread;
        
        // Calculate spread cost for 1 lot
        double point_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        m_current_spread_cost = spread * point_value;
        
        // Update average
        if(m_avg_spread_points == 0)
        {
            m_avg_spread_points = spread;
        }
        else
        {
            m_avg_spread_points = (m_avg_spread_points * 0.95) + (spread * 0.05); // EMA
        }
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Spread Cost for Trade                                 |
    //+------------------------------------------------------------------+
    double CalculateSpreadCost(double lots)
    {
        UpdateSpread();
        
        double cost = m_current_spread_cost * lots;
        m_total_spread_cost += cost;
        
        return cost;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Swap Cost                                             |
    //+------------------------------------------------------------------+
    double CalculateSwapCost(ENUM_ORDER_TYPE order_type, double lots, int days_held)
    {
        if(days_held <= 0) return 0;
        
        double swap_rate = (order_type == ORDER_TYPE_BUY) ? m_swap_long : m_swap_short;
        
        // Swap cost = swap rate * lots * days
        double swap_cost = swap_rate * lots * days_held;
        
        m_total_swap_cost += swap_cost;
        
        if(swap_cost != 0)
        {
            m_trades_with_swap++;
        }
        
        return swap_cost;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Commission                                            |
    //+------------------------------------------------------------------+
    double CalculateCommission(double lots)
    {
        // Commission depends on broker
        // Typical: $3-7 per lot per side (round trip = $6-14)
        double commission_per_lot = 7.0;  // Adjustable
        
        double commission = commission_per_lot * lots * 2;  // Round trip
        m_total_commission += commission;
        
        return commission;
    }
    
    //+------------------------------------------------------------------+
    //| Record Trade Costs                                              |
    //+------------------------------------------------------------------+
    void RecordTradeCosts(ENUM_ORDER_TYPE order_type, double lots, int days_held)
    {
        m_total_trades++;
        
        double spread_cost = CalculateSpreadCost(lots);
        double swap_cost = CalculateSwapCost(order_type, lots, days_held);
        double commission = CalculateCommission(lots);
        
        double total_cost = spread_cost + MathAbs(swap_cost) + commission;
        
        if(m_total_trades % 10 == 0)  // Print every 10 trades
        {
            Print("💸 Trade #", m_total_trades, " costs:");
            Print("   Spread: $", DoubleToString(spread_cost, 2));
            Print("   Swap: $", DoubleToString(swap_cost, 2), " (", days_held, " days)");
            Print("   Commission: $", DoubleToString(commission, 2));
            Print("   Total: $", DoubleToString(total_cost, 2));
        }
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Total Costs                                           |
    //+------------------------------------------------------------------+
    TradingCosts CalculateTotalCosts(double total_profit)
    {
        TradingCosts costs;
        
        costs.total_spread_cost = m_total_spread_cost;
        costs.total_swap_cost = m_total_swap_cost;
        costs.total_commission = m_total_commission;
        costs.total_cost = m_total_spread_cost + MathAbs(m_total_swap_cost) + m_total_commission;
        
        costs.total_trades = m_total_trades;
        costs.trades_with_swap = m_trades_with_swap;
        
        if(m_total_trades > 0)
        {
            costs.avg_spread_per_trade = m_total_spread_cost / m_total_trades;
        }
        
        if(m_trades_with_swap > 0)
        {
            costs.avg_swap_per_day = m_total_swap_cost / m_trades_with_swap;
        }
        
        if(total_profit > 0)
        {
            costs.cost_to_profit_ratio = (costs.total_cost / total_profit) * 100.0;
        }
        
        return costs;
    }
    
    //+------------------------------------------------------------------+
    //| Print Cost Report                                               |
    //+------------------------------------------------------------------+
    void PrintCostReport(double total_profit)
    {
        TradingCosts costs = CalculateTotalCosts(total_profit);
        
        Print("═══════════════════════════════════════════");
        Print("💸 TRADING COSTS REPORT");
        Print("═══════════════════════════════════════════");
        Print("Total Trades: ", costs.total_trades);
        Print("───────────────────────────────────────────");
        Print("Cost Breakdown:");
        Print("  Spread Cost: $", DoubleToString(costs.total_spread_cost, 2));
        Print("  Swap Cost: $", DoubleToString(costs.total_swap_cost, 2));
        Print("  Commission: $", DoubleToString(costs.total_commission, 2));
        Print("  ─────────────────────");
        Print("  TOTAL COST: $", DoubleToString(costs.total_cost, 2));
        Print("───────────────────────────────────────────");
        Print("Averages:");
        Print("  Avg Spread/Trade: $", DoubleToString(costs.avg_spread_per_trade, 2));
        Print("  Avg Spread: ", DoubleToString(m_avg_spread_points, 1), " points");
        
        if(costs.trades_with_swap > 0)
        {
            Print("  Avg Swap/Day: $", DoubleToString(costs.avg_swap_per_day, 2));
            Print("  Trades with Swap: ", costs.trades_with_swap);
        }
        
        Print("───────────────────────────────────────────");
        Print("Impact on Profit:");
        Print("  Gross Profit: $", DoubleToString(total_profit + costs.total_cost, 2));
        Print("  Total Costs: -$", DoubleToString(costs.total_cost, 2));
        Print("  Net Profit: $", DoubleToString(total_profit, 2));
        Print("  Cost/Profit Ratio: ", DoubleToString(costs.cost_to_profit_ratio, 2), "%");
        
        // Evaluation
        string verdict = "";
        if(costs.cost_to_profit_ratio < 10)
            verdict = "✅ EXCELLENT - Low cost impact";
        else if(costs.cost_to_profit_ratio < 20)
            verdict = "✅ GOOD - Acceptable costs";
        else if(costs.cost_to_profit_ratio < 30)
            verdict = "⚠️ FAIR - High costs";
        else
            verdict = "❌ POOR - Costs eating profits!";
        
        Print("  Verdict: ", verdict);
        
        // Spread warning
        if(m_avg_spread_points > m_max_acceptable_spread_points)
        {
            Print("  ⚠️ WARNING: High spread detected!");
            Print("     Avg: ", DoubleToString(m_avg_spread_points, 1), " points");
            Print("     Max acceptable: ", m_max_acceptable_spread_points, " points");
        }
        
        Print("═══════════════════════════════════════════");
    }
    
    //+------------------------------------------------------------------+
    //| Check if Spread is Acceptable                                   |
    //+------------------------------------------------------------------+
    bool IsSpreadAcceptable()
    {
        UpdateSpread();
        return (m_current_spread_points <= m_max_acceptable_spread_points);
    }
    
    //+------------------------------------------------------------------+
    //| Enable High Spread Testing                                      |
    //+------------------------------------------------------------------+
    void EnableHighSpreadTesting(double multiplier = 2.0)
    {
        m_use_high_spread = true;
        m_spread_multiplier = multiplier;
        
        Print("⚠️ High Spread Testing Enabled");
        Print("   Multiplier: ", DoubleToString(multiplier, 1), "x");
    }
    
    //+------------------------------------------------------------------+
    //| Disable High Spread Testing                                     |
    //+------------------------------------------------------------------+
    void DisableHighSpreadTesting()
    {
        m_use_high_spread = false;
        m_spread_multiplier = 1.0;
        
        Print("✅ Normal Spread Mode");
    }
    
    //+------------------------------------------------------------------+
    //| Simulate Long Hold (Swap Impact)                                |
    //+------------------------------------------------------------------+
    double SimulateLongHoldSwap(ENUM_ORDER_TYPE order_type, double lots, int days)
    {
        double swap_rate = (order_type == ORDER_TYPE_BUY) ? m_swap_long : m_swap_short;
        double total_swap = swap_rate * lots * days;
        
        Print("💸 Long Hold Simulation:");
        Print("   Type: ", (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL");
        Print("   Lots: ", DoubleToString(lots, 2));
        Print("   Days: ", days);
        Print("   Swap/Day: $", DoubleToString(swap_rate * lots, 2));
        Print("   Total Swap: $", DoubleToString(total_swap, 2));
        
        return total_swap;
    }
    
    //+------------------------------------------------------------------+
    //| Check if Costs are Acceptable                                   |
    //+------------------------------------------------------------------+
    bool AreCostsAcceptable(double total_profit)
    {
        TradingCosts costs = CalculateTotalCosts(total_profit);
        return (costs.cost_to_profit_ratio <= m_max_cost_to_profit_pct);
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetCurrentSpreadPoints() { return m_current_spread_points; }
    double GetAvgSpreadPoints() { return m_avg_spread_points; }
    double GetTotalCosts() { return m_total_spread_cost + MathAbs(m_total_swap_cost) + m_total_commission; }
    double GetSpreadCost() { return m_total_spread_cost; }
    double GetSwapCost() { return m_total_swap_cost; }
    double GetCommission() { return m_total_commission; }
    
    //+------------------------------------------------------------------+
    //| Setters                                                          |
    //+------------------------------------------------------------------+
    void SetMaxAcceptableSpread(double points) { m_max_acceptable_spread_points = points; }
    void SetMaxCostToProfitPct(double pct) { m_max_cost_to_profit_pct = pct; }
};

//+------------------------------------------------------------------+
