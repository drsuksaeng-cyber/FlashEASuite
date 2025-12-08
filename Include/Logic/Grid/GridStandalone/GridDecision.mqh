//+------------------------------------------------------------------+
//|                                     GridStandalone/GridDecision.mqh |
//|                                      FlashEASuite V2 - Standalone Grid |
//|                              Decision Engine Module                      |
//+------------------------------------------------------------------+
#property strict

#include "MarketAnalysis.mqh"

//+------------------------------------------------------------------+
//| Grid Decision Engine                                              |
//+------------------------------------------------------------------+
class CGridDecisionEngine : public CMarketAnalysisEngine
{
private:
    // Entry conditions tracking
    bool              m_entry_conditions[10];
    int               m_required_confirmations;
    
    // Time tracking
    datetime          m_last_trade_time;
    datetime          m_daily_reset_time;
    
    // Average spread calculation
    double            m_spread_buffer[100];
    int               m_spread_buffer_index;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridDecisionEngine() : CMarketAnalysisEngine()
    {
        m_required_confirmations = 3;
        m_last_trade_time = 0;
        m_daily_reset_time = TimeCurrent();
        m_spread_buffer_index = 0;
        
        ArrayInitialize(m_entry_conditions, false);
        ArrayInitialize(m_spread_buffer, 0.0);
    }
    
    //+------------------------------------------------------------------+
    //| Main Entry Decision                                              |
    //+------------------------------------------------------------------+
    bool ShouldEnterGrid()
    {
        // Phase 1: Pre-entry validation
        if(!CheckMarketState()) return false;
        if(!CheckTimeFilter()) return false;
        if(!CheckSpreadFilter()) return false;
        if(!CheckNewsFilter()) return false;
        if(!CheckRiskLimits()) return false;
        if(!CheckNoActiveGrid()) return false;
        
        // Phase 2: Direction confirmation
        int buy_signals = CountBuySignals();
        int sell_signals = CountSellSignals();
        
        // Need 3+ signals
        if(buy_signals >= m_required_confirmations && buy_signals > sell_signals)
        {
            m_current_direction = GRID_DIR_BUY;
            m_market_confidence = (double)buy_signals / 6.0;
            
            Print("[Decision] ✅ BUY Grid approved: ", buy_signals, " signals, confidence: ", 
                  DoubleToString(m_market_confidence, 2));
            return true;
        }
        
        if(sell_signals >= m_required_confirmations && sell_signals > buy_signals)
        {
            m_current_direction = GRID_DIR_SELL;
            m_market_confidence = (double)sell_signals / 6.0;
            
            Print("[Decision] ✅ SELL Grid approved: ", sell_signals, " signals, confidence: ", 
                  DoubleToString(m_market_confidence, 2));
            return true;
        }
        
        // Not enough signals
        Print("[Decision] ❌ Insufficient signals - BUY:", buy_signals, " SELL:", sell_signals);
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Market State                                               |
    //+------------------------------------------------------------------+
    bool CheckMarketState()
    {
        ENUM_MARKET_STATE state = m_current_market_state;
        
        // CASE 1: RANGING + NORMAL (IDEAL)
        if(state == MARKET_STATE_RANGING_NORMAL)
        {
            m_entry_conditions[0] = true;
            Print("[Decision] Market: RANGING_NORMAL ✅");
            return true;
        }
        
        // CASE 2: TRENDING + WEAK (OK)
        if(state == MARKET_STATE_TRENDING_WEAK)
        {
            m_entry_conditions[0] = true;
            Print("[Decision] Market: TRENDING_WEAK ⚠️ (Conservative)");
            return true;
        }
        
        // CASE 3: RANGING + HIGH VOLATILITY (DANGEROUS)
        if(state == MARKET_STATE_RANGING_HIGH_VOL)
        {
            m_entry_conditions[0] = false;
            Print("[Decision] Market: RANGING_HIGH_VOL ❌ (Too risky)");
            return false;
        }
        
        // CASE 4: TRENDING + STRONG (NO GRID)
        if(state == MARKET_STATE_TRENDING_STRONG)
        {
            m_entry_conditions[0] = false;
            Print("[Decision] Market: TRENDING_STRONG ❌ (Use Spike instead)");
            return false;
        }
        
        m_entry_conditions[0] = false;
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check Time Filter                                                |
    //+------------------------------------------------------------------+
    bool CheckTimeFilter()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int hour = dt.hour;
        int day = dt.day_of_week;
        
        // Day filter
        if(day == 0 && hour < 21)  // Sunday before market open
        {
            m_entry_conditions[1] = false;
            return false;
        }
        
        if(day == 5 && hour > 20)  // Friday near close
        {
            m_entry_conditions[1] = false;
            return false;
        }
        
        // Low liquidity filter (Asian session)
        if(hour >= 0 && hour < 6)
        {
            m_entry_conditions[1] = false;
            return false;
        }
        
        // Rollover filter
        if(hour == 23 || hour == 0)
        {
            m_entry_conditions[1] = false;
            return false;
        }
        
        m_entry_conditions[1] = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check Spread Filter                                              |
    //+------------------------------------------------------------------+
    bool CheckSpreadFilter()
    {
        // Get current spread
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double current_spread = (ask - bid) / _Point;
        
        // Update spread buffer
        m_spread_buffer[m_spread_buffer_index] = current_spread;
        m_spread_buffer_index = (m_spread_buffer_index + 1) % 100;
        
        // Calculate average spread
        double avg_spread = 0.0;
        for(int i = 0; i < 100; i++)
        {
            avg_spread += m_spread_buffer[i];
        }
        avg_spread /= 100.0;
        
        // Check if spread is within limit
        if(current_spread > avg_spread * 2.0)
        {
            m_entry_conditions[2] = false;
            Print("[Decision] Spread too wide: ", current_spread, " (avg: ", avg_spread, ")");
            return false;
        }
        
        m_entry_conditions[2] = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check News Filter                                                |
    //+------------------------------------------------------------------+
    bool CheckNewsFilter()
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int hour = dt.hour;
        int minute = dt.min;
        
        // Major news times (GMT)
        // 08:30 GMT (USD data)
        if(hour == 8 && minute >= 15 && minute <= 45)
        {
            m_entry_conditions[3] = false;
            return false;
        }
        
        // 12:30 GMT (UK data)
        if(hour == 12 && minute >= 15 && minute <= 45)
        {
            m_entry_conditions[3] = false;
            return false;
        }
        
        // 14:00 GMT (EUR data)
        if(hour == 14 && minute >= 0 && minute <= 30)
        {
            m_entry_conditions[3] = false;
            return false;
        }
        
        m_entry_conditions[3] = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check Risk Limits                                                |
    //+------------------------------------------------------------------+
    bool CheckRiskLimits()
    {
        // This will be implemented in RiskGuardian
        // For now, just return true
        m_entry_conditions[4] = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check No Active Grid                                             |
    //+------------------------------------------------------------------+
    bool CheckNoActiveGrid()
    {
        if(m_active_grid_count > 0)
        {
            m_entry_conditions[5] = false;
            Print("[Decision] Grid already active: ", m_active_grid_count, " levels");
            return false;
        }
        
        m_entry_conditions[5] = true;
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get Entry Confidence                                             |
    //+------------------------------------------------------------------+
    double GetEntryConfidence()
    {
        return m_market_confidence;
    }
    
    //+------------------------------------------------------------------+
    //| Should Open Next Grid Level                                      |
    //+------------------------------------------------------------------+
    bool ShouldOpenNextLevel()
    {
        // Check if we hit max levels
        if(m_active_grid_count >= m_max_grid_levels)
        {
            return false;
        }
        
        // Get current price
        double current_price;
        if(m_current_direction == GRID_DIR_BUY)
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        else
            current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Calculate distance from last grid
        double distance = MathAbs(current_price - m_last_grid_price) / _Point;
        
        // Check if price moved enough
        if(distance < m_current_elastic_step)
        {
            return false;
        }
        
        // Check if price moved AGAINST position
        bool moved_against = false;
        
        if(m_current_direction == GRID_DIR_BUY)
        {
            // For BUY grid, we open next level when price goes DOWN
            if(current_price < m_last_grid_price)
                moved_against = true;
        }
        else  // SELL
        {
            // For SELL grid, we open next level when price goes UP
            if(current_price > m_last_grid_price)
                moved_against = true;
        }
        
        if(!moved_against)
        {
            return false;
        }
        
        Print("[Decision] ✅ Should open next level: Distance=", distance, 
              " Elastic=", m_current_elastic_step);
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Average Spread                                         |
    //+------------------------------------------------------------------+
    double CalculateAverageSpread()
    {
        double sum = 0.0;
        for(int i = 0; i < 100; i++)
        {
            sum += m_spread_buffer[i];
        }
        return sum / 100.0;
    }
};
//+------------------------------------------------------------------+
