//+------------------------------------------------------------------+
//| PinBarDetector.mqh                                               |
//| FlashEASuite V2 — S12 Price Action: Pin Bar Detection           |
//| Subfolder: Include/Logic/Strategies/PriceAction/                |
//+------------------------------------------------------------------+
//| Pin Bar Definition:                                              |
//|  - Body < 30% of total candle range                             |
//|  - Dominant wick > 60% of total range                           |
//|  - Wick direction opposite to expected signal                   |
//|  - Bullish: long LOWER wick (rejection of lower prices)         |
//|  - Bearish: long UPPER wick (rejection of higher prices)        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef PINBAR_DETECTOR_MQH
#define PINBAR_DETECTOR_MQH

//+------------------------------------------------------------------+
//| ENUM: Pin Bar Type — NO NEGATIVE VALUES (Lesson #1)             |
//+------------------------------------------------------------------+
enum ENUM_PINBAR_TYPE
{
    PINBAR_NONE     = 0,   // Not a pin bar
    PINBAR_BULLISH  = 1,   // Bullish pin bar (long lower wick)
    PINBAR_BEARISH  = 2    // Bearish pin bar (long upper wick)
};

//+------------------------------------------------------------------+
//| STRUCT: Pin Bar Result                                           |
//+------------------------------------------------------------------+
struct SPinBarResult
{
    ENUM_PINBAR_TYPE  type;          // NONE, BULLISH, BEARISH
    double            wick_ratio;    // wick_length / total_range (0.0-1.0)
    double            body_ratio;    // body_length / total_range (0.0-1.0)
    double            confidence;    // raw confidence before multiplier
    int               bar_index;     // which bar (0 = current closed)
    
    void Reset()
    {
        type       = PINBAR_NONE;
        wick_ratio = 0.0;
        body_ratio = 0.0;
        confidence = 0.0;
        bar_index  = 1;
    }
};

//+------------------------------------------------------------------+
//| CPinBarDetector — Direct member class (no pointer, no new/delete)|
//| PATTERN: default constructor + Setup() method (Lesson #2)       |
//+------------------------------------------------------------------+
class CPinBarDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    double          m_body_max_ratio;    // body must be < this% of range
    double          m_wick_min_ratio;    // dominant wick must be > this% of range
    
public:
    //--- Default constructor (no arguments — Lesson #2)
    CPinBarDetector()
    {
        m_symbol         = "";
        m_tf             = PERIOD_D1;
        m_body_max_ratio = 0.30;   // body < 30% of range
        m_wick_min_ratio = 0.60;   // wick > 60% of range
    }
    
    //--- Setup() instead of parameterized constructor (Lesson #2)
    void Setup(string symbol, ENUM_TIMEFRAMES tf,
               double body_max = 0.30, double wick_min = 0.60)
    {
        m_symbol         = symbol;
        m_tf             = tf;
        m_body_max_ratio = body_max;
        m_wick_min_ratio = wick_min;
    }
    
    //+------------------------------------------------------------------+
    //| Detect: Check bar[bar_index] for pin bar pattern                |
    //| bar_index=1 = last closed candle (standard), 0 = current tick   |
    //+------------------------------------------------------------------+
    SPinBarResult Detect(int bar_index = 1)
    {
        SPinBarResult result;
        result.Reset();
        result.bar_index = bar_index;
        
        if(m_symbol == "") return result;
        
        double open  = iOpen(m_symbol,  m_tf, bar_index);
        double high  = iHigh(m_symbol,  m_tf, bar_index);
        double low   = iLow(m_symbol,   m_tf, bar_index);
        double close = iClose(m_symbol, m_tf, bar_index);
        
        double total_range = high - low;
        if(total_range < _Point * 2) return result;  // Doji-like, skip
        
        double body_high  = MathMax(open, close);
        double body_low   = MathMin(open, close);
        double body_size  = body_high - body_low;
        double upper_wick = high - body_high;
        double lower_wick = body_low - low;
        
        double body_ratio  = body_size / total_range;
        double upper_ratio = upper_wick / total_range;
        double lower_ratio = lower_wick / total_range;
        
        // Body must be small
        if(body_ratio > m_body_max_ratio) return result;
        
        // Check Bullish Pin Bar: dominant LOWER wick
        if(lower_ratio >= m_wick_min_ratio && lower_ratio > upper_ratio)
        {
            result.type       = PINBAR_BULLISH;
            result.wick_ratio = lower_ratio;
            result.body_ratio = body_ratio;
            result.confidence = lower_ratio * (1.0 - body_ratio);
            return result;
        }
        
        // Check Bearish Pin Bar: dominant UPPER wick
        if(upper_ratio >= m_wick_min_ratio && upper_ratio > lower_ratio)
        {
            result.type       = PINBAR_BEARISH;
            result.wick_ratio = upper_ratio;
            result.body_ratio = body_ratio;
            result.confidence = upper_ratio * (1.0 - body_ratio);
            return result;
        }
        
        return result;  // PINBAR_NONE
    }
    
    //--- Getters
    string GetSymbol()  const { return m_symbol; }
    ENUM_TIMEFRAMES GetTF() const { return m_tf; }
};

#endif // PINBAR_DETECTOR_MQH
//+------------------------------------------------------------------+
