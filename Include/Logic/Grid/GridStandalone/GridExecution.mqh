//+------------------------------------------------------------------+
//|                                   GridStandalone/GridExecution.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                             Grid Execution Engine Module                 |
//+------------------------------------------------------------------+
#property strict

#include "GridDecision.mqh"

//+------------------------------------------------------------------+
//| Grid Execution Engine                                             |
//+------------------------------------------------------------------+
class CGridExecutionEngine : public CGridDecisionEngine
{
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridExecutionEngine() : CGridDecisionEngine()
    {
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Elastic Step                                           |
    //+------------------------------------------------------------------+
    double CalculateElasticStep()
    {
        // Get ATR ratio
        double atr_ratio = m_atr_current / m_atr_reference;
        
        // Calculate base elastic step
        double elastic = m_base_step_points * atr_ratio;
        
        // Apply safety limits (0.5x to 2.0x)
        double min_step = m_base_step_points * 0.5;
        double max_step = m_base_step_points * 2.0;
        
        if(elastic < min_step) elastic = min_step;
        if(elastic > max_step) elastic = max_step;
        
        // Market state adjustment
        if(m_current_market_state == MARKET_STATE_RANGING_NORMAL)
        {
            // Very ranging → Tighter grid
            double adx[1];
            if(CopyBuffer(m_adx_handle, 0, 0, 1, adx) > 0)
            {
                if(adx[0] < 15)
                    elastic *= 0.8;  // 20% tighter
            }
        }
        
        if(m_current_market_state == MARKET_STATE_TRENDING_WEAK)
        {
            // Trending → Wider grid
            elastic *= 1.2;  // 20% wider
        }
        
        m_current_elastic_step = elastic;
        
        Print("[Execution] Elastic Step: ", elastic, " points (ATR: ", m_atr_current, 
              ", Ratio: ", DoubleToString(atr_ratio, 2), ")");
        
        return elastic;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Lot Size                                               |
    //+------------------------------------------------------------------+
    double CalculateLotSize(int level)
    {
        // Base lot
        double lot = m_base_lot;
        
        // Apply progression (Anti-Martingale)
        if(level < 5)
            lot *= m_lot_progression[level];
        else
            lot *= 2.0;  // Max multiplier
        
        // Apply Python risk multiplier (if connected)
        lot *= m_python_risk_multiplier;
        
        // Normalize to broker step
        double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        lot = MathFloor(lot / lot_step) * lot_step;
        
        // Safety checks
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        
        if(lot < min_lot) lot = min_lot;
        if(lot > max_lot) lot = max_lot;
        
        // Risk validation
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double max_risk = balance * (m_max_risk_per_grid / 100.0);
        double sl_points = m_current_elastic_step * m_sl_multiplier;
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double risk_amount = lot * sl_points * tick_value;
        
        if(risk_amount > max_risk)
        {
            // Reduce lot to meet risk limit
            lot = max_risk / (sl_points * tick_value);
            lot = MathFloor(lot / lot_step) * lot_step;
            
            if(lot < min_lot) lot = min_lot;
        }
        
        Print("[Execution] Level ", level, " Lot: ", lot, 
              " (Risk Mult: ", m_python_risk_multiplier, ")");
        
        return lot;
    }
    
    //+------------------------------------------------------------------+
    //| Open Grid Level                                                  |
    //+------------------------------------------------------------------+
    bool OpenGridLevel(int level)
    {
        // Get current price
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
        {
            Print("[Execution] ERROR: Failed to get tick");
            return false;
        }
        
        double price = (m_current_direction == GRID_DIR_BUY) ? tick.ask : tick.bid;
        
        // Calculate lot size
        double lot = CalculateLotSize(level);
        
        // Calculate TP/SL
        double tp_distance = m_current_elastic_step * m_tp_multiplier;
        double sl_distance = m_current_elastic_step * m_sl_multiplier;
        
        double tp = 0.0, sl = 0.0;
        
        if(m_current_direction == GRID_DIR_BUY)
        {
            tp = price + (tp_distance * _Point);
            sl = price - (sl_distance * _Point);
        }
        else  // SELL
        {
            tp = price - (tp_distance * _Point);
            sl = price + (sl_distance * _Point);
        }
        
        // Create comment
        string comment = StringFormat("Grid_L%d_%s", level, 
                                     (m_current_direction == GRID_DIR_BUY) ? "BUY" : "SELL");
        
        // Determine order type
        ENUM_ORDER_TYPE order_type = (m_current_direction == GRID_DIR_BUY) ? 
                                      ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        
        // Open position
        if(m_trade.PositionOpen(_Symbol, order_type, lot, price, sl, tp, comment))
        {
            ulong ticket = m_trade.ResultOrder();
            
            // Store in grid orders array
            m_grid_orders[level].ticket = ticket;
            m_grid_orders[level].open_price = price;
            m_grid_orders[level].lot_size = lot;
            m_grid_orders[level].open_time = TimeCurrent();
            m_grid_orders[level].level = level;
            m_grid_orders[level].profit = 0.0;
            
            m_active_grid_count++;
            m_last_grid_price = price;
            
            // Set grid start time (for level 0)
            if(level == 0)
            {
                m_grid_start_time = TimeCurrent();
                m_grid_id = GenerateGridID();
            }
            
            Print("[Execution] ✅ Level ", level, " opened:");
            Print("  Type: ", EnumToString(order_type));
            Print("  Ticket: ", ticket);
            Print("  Lot: ", lot);
            Print("  Price: ", price);
            Print("  SL: ", sl);
            Print("  TP: ", tp);
            
            return true;
        }
        else
        {
            Print("[Execution] ❌ Failed to open Level ", level, ": ", GetLastError());
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Update Grid State                                                |
    //+------------------------------------------------------------------+
    void UpdateGridState()
    {
        if(m_active_grid_count == 0)
            return;
        
        double total_profit = 0.0;
        
        // Update each grid order
        for(int i = 0; i < m_active_grid_count; i++)
        {
            ulong ticket = m_grid_orders[i].ticket;
            
            if(PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT);
                m_grid_orders[i].profit = profit;
                total_profit += profit;
            }
        }
        
        // Update highest PnL
        if(total_profit > m_highest_pnl)
        {
            m_highest_pnl = total_profit;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Total Floating PnL                                           |
    //+------------------------------------------------------------------+
    double GetTotalFloatingPnL()
    {
        double total = 0.0;
        
        for(int i = 0; i < m_active_grid_count; i++)
        {
            total += m_grid_orders[i].profit;
        }
        
        return total;
    }
    
    //+------------------------------------------------------------------+
    //| Get Total Risk (SL distance)                                     |
    //+------------------------------------------------------------------+
    double GetTotalRisk()
    {
        double total_risk = 0.0;
        
        for(int i = 0; i < m_active_grid_count; i++)
        {
            ulong ticket = m_grid_orders[i].ticket;
            
            if(PositionSelectByTicket(ticket))
            {
                double entry = PositionGetDouble(POSITION_PRICE_OPEN);
                double sl = PositionGetDouble(POSITION_SL);
                double lot = PositionGetDouble(POSITION_VOLUME);
                double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                
                double risk = MathAbs(entry - sl) / _Point * tick_value * lot;
                total_risk += risk;
            }
        }
        
        return total_risk;
    }
    
    //+------------------------------------------------------------------+
    //| Check Individual TP                                              |
    //+------------------------------------------------------------------+
    bool CheckIndividualTP(int index)
    {
        if(index >= m_active_grid_count)
            return false;
        
        ulong ticket = m_grid_orders[index].ticket;
        if(!PositionSelectByTicket(ticket))
            return false;
        
        double tp = PositionGetDouble(POSITION_TP);
        double current_price;
        
        if(m_current_direction == GRID_DIR_BUY)
        {
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(current_price >= tp)
            {
                Print("[Execution] Level ", index, " TP hit at ", current_price);
                return true;
            }
        }
        else  // SELL
        {
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(current_price <= tp)
            {
                Print("[Execution] Level ", index, " TP hit at ", current_price);
                return true;
            }
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Trailing Stop (Per Order)                                        |
    //+------------------------------------------------------------------+
    void TrailingStop(int index)
    {
        if(index >= m_active_grid_count)
            return;
        
        ulong ticket = m_grid_orders[index].ticket;
        if(!PositionSelectByTicket(ticket))
            return;
        
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double current_sl = PositionGetDouble(POSITION_SL);
        double current_tp = PositionGetDouble(POSITION_TP);
        
        double current_price;
        if(m_current_direction == GRID_DIR_BUY)
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        else
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Calculate profit in points
        double profit_points = 0.0;
        if(m_current_direction == GRID_DIR_BUY)
            profit_points = (current_price - entry) / _Point;
        else
            profit_points = (entry - current_price) / _Point;
        
        // Only activate trailing if profit > ATR
        if(profit_points < m_atr_current)
            return;
        
        // Trail distance = ATR * 0.5
        double trail_distance = m_atr_current * 0.5 * _Point;
        double new_sl;
        
        if(m_current_direction == GRID_DIR_BUY)
        {
            new_sl = current_price - trail_distance;
            
            // Only move SL up
            if(new_sl > current_sl && new_sl < current_price)
            {
                if(m_trade.PositionModify(ticket, new_sl, current_tp))
                {
                    Print("[Execution] Level ", index, " trailing SL moved to: ", new_sl);
                }
            }
        }
        else  // SELL
        {
            new_sl = current_price + trail_distance;
            
            // Only move SL down
            if((current_sl == 0 || new_sl < current_sl) && new_sl > current_price)
            {
                if(m_trade.PositionModify(ticket, new_sl, current_tp))
                {
                    Print("[Execution] Level ", index, " trailing SL moved to: ", new_sl);
                }
            }
        }
    }
};
//+------------------------------------------------------------------+
