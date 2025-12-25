//+------------------------------------------------------------------+
//|                                      Grid/GridDecision.mqh       |
//|                                    FlashEASuite V2 - Week 3      |
//|                      Smart Grid Level Decision Making             |
//+------------------------------------------------------------------+
#property strict

// ENUM_GRID_DIRECTION is defined in GridConfig.mqh
// This file assumes GridConfig.mqh is included before this file

#include "MarketAnalysis.mqh"

//+------------------------------------------------------------------+
//| Grid Decision Structure                                          |
//+------------------------------------------------------------------+
struct GridDecisionResult
{
    bool              should_open;        // Should open new level?
    ENUM_ORDER_TYPE   order_type;         // BUY or SELL
    double            lot_size;           // Calculated lot
    double            confidence;         // 0.0-1.0
    string            reason;             // Decision reason
};

//+------------------------------------------------------------------+
//| Class: CGridDecision                                             |
//| Makes intelligent decisions about opening grid levels            |
//+------------------------------------------------------------------+
class CGridDecision
{
private:
    CMarketAnalysis*  m_market_analysis;  // Market analyzer
    
    // Grid state (passed from GridState)
    int               m_active_count;
    int               m_max_levels;
    double            m_last_price;
    double            m_elastic_step;
    ENUM_GRID_DIRECTION m_direction;
    
    // Decision thresholds
    double            m_min_confidence;   // 0.3 minimum
    double            m_price_buffer;     // 1.2x elastic (don't open too early)
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CGridDecision()
    {
        m_market_analysis = NULL;
        m_active_count = 0;
        m_max_levels = 5;
        m_last_price = 0.0;
        m_elastic_step = 0.0;
        m_direction = GRID_DIR_NONE;
        
        m_min_confidence = 0.3;
        m_price_buffer = 1.2;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CGridDecision()
    {
        if(m_market_analysis != NULL)
        {
            delete m_market_analysis;
            m_market_analysis = NULL;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Initialize with market analyzer                                 |
    //+------------------------------------------------------------------+
    void Initialize(CMarketAnalysis* analyzer)
    {
        m_market_analysis = analyzer;
    }
    
    //+------------------------------------------------------------------+
    //| Update Grid State                                               |
    //+------------------------------------------------------------------+
    void UpdateState(int active_count, int max_levels, double last_price, 
                     double elastic_step, ENUM_GRID_DIRECTION direction)
    {
        m_active_count = active_count;
        m_max_levels = max_levels;
        m_last_price = last_price;
        m_elastic_step = elastic_step;
        m_direction = direction;
    }
    
    //+------------------------------------------------------------------+
    //| Main Decision Function                                          |
    //+------------------------------------------------------------------+
    GridDecisionResult MakeDecision(double python_confidence)
    {
        GridDecisionResult result;
        result.should_open = false;
        result.order_type = ORDER_TYPE_BUY;
        result.lot_size = 0.0;
        result.confidence = 0.0;
        result.reason = "Unknown";
        
        // Safety Check 1: Max levels
        if(m_active_count >= m_max_levels)
        {
            result.reason = "Max levels reached";
            return result;
        }
        
        // Safety Check 2: Direction set
        if(m_direction == GRID_DIR_NONE)
        {
            result.reason = "No direction set";
            return result;
        }
        
        // Safety Check 3: Elastic step calculated
        if(m_elastic_step <= 0.0)
        {
            result.reason = "Elastic step not set";
            return result;
        }
        
        // Safety Check 4: Confidence too low
        if(python_confidence < m_min_confidence)
        {
            result.reason = "Confidence too low";
            return result;
        }
        
        // Check market condition
        if(m_market_analysis != NULL)
        {
            if(!m_market_analysis.IsGridFriendly())
            {
                result.reason = "Market not grid-friendly";
                return result;
            }
        }
        
        // Get current price
        MqlTick tick;
        if(!SymbolInfoTick(_Symbol, tick))
        {
            result.reason = "Cannot get tick";
            return result;
        }
        
        // Set order type based on direction
        result.order_type = (m_direction == GRID_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        double current_price = (result.order_type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
        
        // First level: Always open
        if(m_active_count == 0)
        {
            result.should_open = true;
            result.confidence = python_confidence;
            result.reason = "First grid level";
            return result;
        }
        
        // Check if price moved enough
        double price_diff = MathAbs(current_price - m_last_price);
        double price_diff_points = price_diff / _Point;
        double required_move = m_elastic_step * m_price_buffer; // 1.2x buffer
        
        if(price_diff_points < required_move)
        {
            result.reason = StringFormat("Price not moved enough (%.1f/%.1f)", 
                                        price_diff_points, required_move);
            return result;
        }
        
        // Calculate confidence based on:
        // 1. Python confidence (50%)
        // 2. Distance from last level (30%)
        // 3. Market condition (20%)
        
        double distance_confidence = MathMin(price_diff_points / (m_elastic_step * 2.0), 1.0);
        double market_confidence = m_market_analysis != NULL ? 
                                   (m_market_analysis.IsGridFriendly() ? 1.0 : 0.5) : 0.8;
        
        result.confidence = python_confidence * 0.5 + 
                           distance_confidence * 0.3 + 
                           market_confidence * 0.2;
        
        // Open if confidence > threshold
        if(result.confidence >= m_min_confidence)
        {
            result.should_open = true;
            result.reason = StringFormat("Confidence: %.2f", result.confidence);
        }
        else
        {
            result.reason = StringFormat("Confidence too low: %.2f", result.confidence);
        }
        
        return result;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Optimal Lot Size                                      |
    //+------------------------------------------------------------------+
    double CalculateOptimalLot(int level, double base_lot, const double &lot_progression[], 
                               double risk_multiplier)
    {
        double lot = base_lot;
        
        // Apply progression
        if(level < 5)
            lot *= lot_progression[level];
        else
            lot *= lot_progression[4];
        
        // Apply risk multiplier
        lot *= risk_multiplier;
        
        // Normalize
        double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        lot = MathFloor(lot / lot_step) * lot_step;
        
        // Safety limits
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        
        if(lot < min_lot) lot = min_lot;
        if(lot > max_lot) lot = max_lot;
        
        return lot;
    }
    
    //+------------------------------------------------------------------+
    //| Adjust Decision Based on Market Regime                         |
    //+------------------------------------------------------------------+
    void AdjustForMarketRegime(GridDecisionResult &result)
    {
        if(m_market_analysis == NULL)
            return;
            
        MarketCondition condition = m_market_analysis.AnalyzeMarket();
        
        // In strong trending market: Don't trade
        if(condition.state == MARKET_STATE_TRENDING_STRONG)
        {
            result.should_open = false;
            result.reason = "Strong trend - avoid grid";
            return;
        }
        
        // In weak trending market: Reduce confidence
        if(condition.state == MARKET_STATE_TRENDING_WEAK)
        {
            result.confidence *= 0.7; // Reduce by 30%
            
            if(result.confidence < m_min_confidence)
            {
                result.should_open = false;
                result.reason = "Weak trend - confidence reduced";
            }
        }
        
        // In high volatility ranging: Don't trade
        if(condition.state == MARKET_STATE_RANGING_HIGH_VOL)
        {
            result.should_open = false;
            result.reason = "High volatility - avoid grid";
            return;
        }
        
        // In normal ranging market: Boost confidence
        if(condition.state == MARKET_STATE_RANGING_NORMAL)
        {
            result.confidence *= 1.2; // Boost by 20%
            if(result.confidence > 1.0) result.confidence = 1.0;
        }
    }
};
//+------------------------------------------------------------------+
