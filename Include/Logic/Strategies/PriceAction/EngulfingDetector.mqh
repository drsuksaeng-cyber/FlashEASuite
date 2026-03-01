//+------------------------------------------------------------------+
//| EngulfingDetector.mqh                                            |
//| FlashEASuite V2 — S12 Price Action: Engulfing Pattern Detection |
//| Subfolder: Include/Logic/Strategies/PriceAction/                |
//+------------------------------------------------------------------+
//| Engulfing Definition:                                            |
//|  - Current bar body COMPLETELY covers previous bar body         |
//|  - Bullish Engulfing: current is bullish, prev is bearish       |
//|  - Bearish Engulfing: current is bearish, prev is bullish       |
//|  - Body size ratio: current body >= body_multiplier × prev body |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef ENGULFING_DETECTOR_MQH
#define ENGULFING_DETECTOR_MQH

//+------------------------------------------------------------------+
//| ENUM: Engulfing Type — NO NEGATIVE VALUES (Lesson #1)           |
//+------------------------------------------------------------------+
enum ENUM_ENGULFING_TYPE
{
    ENGULF_NONE     = 0,   // Not an engulfing
    ENGULF_BULLISH  = 1,   // Bullish engulfing
    ENGULF_BEARISH  = 2    // Bearish engulfing
};

//+------------------------------------------------------------------+
//| STRUCT: Engulfing Result                                         |
//+------------------------------------------------------------------+
struct SEngulfingResult
{
    ENUM_ENGULFING_TYPE type;             // NONE, BULLISH, BEARISH
    double              size_ratio;       // current_body / prev_body
    double              confidence;       // based on size_ratio
    int                 bar_index;        // current bar (engulfs bar+1)
    
    void Reset()
    {
        type       = ENGULF_NONE;
        size_ratio = 0.0;
        confidence = 0.0;
        bar_index  = 1;
    }
};

//+------------------------------------------------------------------+
//| CEngulfingDetector — Direct member class (no pointer)           |
//+------------------------------------------------------------------+
class CEngulfingDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    double          m_min_body_ratio;    // current body must be >= N× prev body

public:
    //--- Default constructor
    CEngulfingDetector()
    {
        m_symbol         = "";
        m_tf             = PERIOD_D1;
        m_min_body_ratio = 1.0;   // current body >= 100% of prev body
    }
    
    //--- Setup() instead of parameterized constructor (Lesson #2)
    void Setup(string symbol, ENUM_TIMEFRAMES tf, double min_body_ratio = 1.0)
    {
        m_symbol         = symbol;
        m_tf             = tf;
        m_min_body_ratio = min_body_ratio;
    }
    
    //+------------------------------------------------------------------+
    //| Detect: Check if bar[bar_index] engulfs bar[bar_index+1]        |
    //+------------------------------------------------------------------+
    SEngulfingResult Detect(int bar_index = 1)
    {
        SEngulfingResult result;
        result.Reset();
        result.bar_index = bar_index;
        
        if(m_symbol == "") return result;
        
        int prev = bar_index + 1;
        
        // Current bar
        double curr_open  = iOpen(m_symbol,  m_tf, bar_index);
        double curr_close = iClose(m_symbol, m_tf, bar_index);
        double curr_body_high = MathMax(curr_open, curr_close);
        double curr_body_low  = MathMin(curr_open, curr_close);
        double curr_body_size = curr_body_high - curr_body_low;
        
        // Previous bar
        double prev_open  = iOpen(m_symbol,  m_tf, prev);
        double prev_close = iClose(m_symbol, m_tf, prev);
        double prev_body_high = MathMax(prev_open, prev_close);
        double prev_body_low  = MathMin(prev_open, prev_close);
        double prev_body_size = prev_body_high - prev_body_low;
        
        if(prev_body_size < _Point || curr_body_size < _Point) return result;
        
        double size_ratio = curr_body_size / prev_body_size;
        
        // Must cover prev body completely
        if(curr_body_high <= prev_body_high) return result;
        if(curr_body_low  >= prev_body_low)  return result;
        if(size_ratio < m_min_body_ratio)    return result;
        
        bool curr_bullish = curr_close > curr_open;
        bool curr_bearish = curr_close < curr_open;
        bool prev_bullish = prev_close > prev_open;
        bool prev_bearish = prev_close < prev_open;
        
        // Bullish Engulfing: current bullish, prev bearish
        if(curr_bullish && prev_bearish)
        {
            result.type       = ENGULF_BULLISH;
            result.size_ratio = size_ratio;
            result.confidence = MathMin(1.0, size_ratio * 0.5);
            return result;
        }
        
        // Bearish Engulfing: current bearish, prev bullish
        if(curr_bearish && prev_bullish)
        {
            result.type       = ENGULF_BEARISH;
            result.size_ratio = size_ratio;
            result.confidence = MathMin(1.0, size_ratio * 0.5);
            return result;
        }
        
        return result;  // ENGULF_NONE
    }
    
    //--- Getters
    string GetSymbol()  const { return m_symbol; }
    ENUM_TIMEFRAMES GetTF() const { return m_tf; }
};

#endif // ENGULFING_DETECTOR_MQH
//+------------------------------------------------------------------+
