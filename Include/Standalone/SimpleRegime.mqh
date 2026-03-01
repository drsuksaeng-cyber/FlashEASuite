//+------------------------------------------------------------------+
//| SimpleRegime.mqh                                                 |
//| FlashEASuite V2 — Standalone Regime Detector                    |
//| Shared with Server Rule-based regime logic                      |
//+------------------------------------------------------------------+
//| Detects: TRENDING / RANGING / VOLATILE / SQUEEZE                |
//| Method : ADX(14) + ATR(H1/D1 ratio) + BB_Width(M15)            |
//| Hysteresis:                                                      |
//|   Enter TRENDING  → ADX ≥ 27.0                                  |
//|   Exit  TRENDING  → ADX < 23.0                                  |
//|   Enter VOLATILE  → ADX ≥ 35.0                                  |
//|   Enter SQUEEZE   → BB_Width < mult × 20-period avg AND ADX<20  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#ifndef SIMPLE_REGIME_MQH
#define SIMPLE_REGIME_MQH

#include "../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| CSimpleRegime: Rule-based regime detector                        |
//| ใช้ direct indicator handles — ไม่ใช้ pointer/new/delete         |
//+------------------------------------------------------------------+
class CSimpleRegime
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_tf;

    // ── Indicator handles ─────────────────────────────────────────
    int  m_adx_h;       // ADX(14) on m_tf
    int  m_atr_m15_h;   // ATR(14) on PERIOD_M15  (intrabar volatility)
    int  m_atr_h1_h;    // ATR(14) on PERIOD_H1   (session range)
    int  m_bb_h;        // BollingerBands(20,2.0) on m_tf — for BB_Width

    // ── Tunable thresholds ────────────────────────────────────────
    double  m_adx_trend_enter;   // default 27.0
    double  m_adx_trend_exit;    // default 23.0  (hysteresis gap)
    double  m_adx_volatile;      // default 35.0
    double  m_squeeze_mult;      // default 0.60  (width < 60% of 20-bar avg)

    // ── Internal state ────────────────────────────────────────────
    ENUM_MARKET_REGIME  m_regime;           // current detected regime
    ENUM_MARKET_REGIME  m_prev_regime;      // previous bar regime
    double              m_confidence;       // 0.0-1.0
    double              m_adx_val;          // last ADX value (for logging)
    double              m_bb_width;         // last BB_Width (for logging)
    double              m_atr_ratio;        // ATR_M15/ATR_H1 ratio (for logging)
    double              m_bb_width_avg;     // rolling 20-bar avg BB_Width
    double              m_bb_width_buf[20]; // circular buffer for avg
    int                 m_bb_buf_idx;       // current write position
    bool                m_bb_buf_full;      // buffer filled?
    datetime            m_last_tick_time;
    bool                m_ready;

public:
    //+------------------------------------------------------------------+
    //| Setup: Initialize handles (ใช้ Setup() pattern ตาม lessons)      |
    //| @param symbol       Trading symbol                               |
    //| @param tf           Primary timeframe                            |
    //| @param adx_enter    ADX threshold to enter TRENDING (default 27) |
    //| @param adx_exit     ADX threshold to exit  TRENDING (default 23) |
    //| @param adx_volatile ADX threshold for VOLATILE   (default 35)   |
    //| @param squeeze_mult BB_Width multiplier for SQUEEZE (default 0.6)|
    //+------------------------------------------------------------------+
    bool Setup(string symbol,
               ENUM_TIMEFRAMES tf,
               double adx_enter   = 27.0,
               double adx_exit    = 23.0,
               double adx_volatile= 35.0,
               double squeeze_mult= 0.60)
    {
        m_symbol         = symbol;
        m_tf             = tf;
        m_adx_trend_enter  = adx_enter;
        m_adx_trend_exit   = adx_exit;
        m_adx_volatile     = adx_volatile;
        m_squeeze_mult     = squeeze_mult;
        m_regime           = REGIME_UNKNOWN;
        m_prev_regime      = REGIME_UNKNOWN;
        m_confidence       = 0.0;
        m_adx_val          = 0.0;
        m_bb_width         = 0.0;
        m_atr_ratio        = 0.0;
        m_bb_width_avg     = 0.0;
        m_bb_buf_idx       = 0;
        m_bb_buf_full      = false;
        m_last_tick_time   = 0;
        m_ready            = false;

        ArrayInitialize(m_bb_width_buf, 0.0);

        // Create indicator handles
        m_adx_h     = iADX(m_symbol, m_tf, 14);
        m_atr_m15_h = iATR(m_symbol, PERIOD_M15, 14);
        m_atr_h1_h  = iATR(m_symbol, PERIOD_H1,  14);
        m_bb_h      = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);

        if(m_adx_h == INVALID_HANDLE || m_atr_m15_h == INVALID_HANDLE ||
           m_atr_h1_h == INVALID_HANDLE || m_bb_h == INVALID_HANDLE)
        {
            PrintFormat("[SimpleRegime] ❌ Indicator create failed | adx=%d atr_m15=%d atr_h1=%d bb=%d",
                        m_adx_h, m_atr_m15_h, m_atr_h1_h, m_bb_h);
            return false;
        }

        m_ready = true;
        PrintFormat("[SimpleRegime] Initialized | %s %s | ADX enter=%.1f exit=%.1f volatile=%.1f squeeze=%.2f",
                    m_symbol, EnumToString(m_tf),
                    m_adx_trend_enter, m_adx_trend_exit, m_adx_volatile, m_squeeze_mult);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release indicator handles                                |
    //+------------------------------------------------------------------+
    void Deinit()
    {
        if(m_adx_h     != INVALID_HANDLE) IndicatorRelease(m_adx_h);
        if(m_atr_m15_h != INVALID_HANDLE) IndicatorRelease(m_atr_m15_h);
        if(m_atr_h1_h  != INVALID_HANDLE) IndicatorRelease(m_atr_h1_h);
        if(m_bb_h      != INVALID_HANDLE) IndicatorRelease(m_bb_h);
        m_adx_h = m_atr_m15_h = m_atr_h1_h = m_bb_h = INVALID_HANDLE;
        m_ready = false;
    }

    //+------------------------------------------------------------------+
    //| Detect: Run regime detection on current bar                      |
    //| เรียกทุก OnTick — ทำงานเฉพาะเมื่อเปลี่ยน bar (ประหยัด CPU)    |
    //| @return detected ENUM_MARKET_REGIME                              |
    //+------------------------------------------------------------------+
    ENUM_MARKET_REGIME Detect(const MqlTick &tick)
    {
        if(!m_ready) return REGIME_UNKNOWN;

        // ── Throttle: run only on new bar ────────────────────────────
        // (ใช้ bar time แทน tick time เพื่อความถูกต้อง)
        datetime bar_time = (datetime)SeriesInfoInteger(m_symbol, m_tf, SERIES_LASTBAR_DATE);
        if(bar_time == m_last_tick_time && m_regime != REGIME_UNKNOWN)
            return m_regime;  // same bar — return cached
        m_last_tick_time = bar_time;

        // ── Read indicators (index 1 = last closed bar) ───────────────
        double adx_buf[3], atr_m15_buf[1], atr_h1_buf[1];
        double bb_upper[1], bb_lower[1], bb_mid[1];

        if(CopyBuffer(m_adx_h, 0, 1, 3, adx_buf)     < 3) return m_regime;
        if(CopyBuffer(m_atr_m15_h, 0, 1, 1, atr_m15_buf) < 1) return m_regime;
        if(CopyBuffer(m_atr_h1_h,  0, 1, 1, atr_h1_buf)  < 1) return m_regime;
        if(CopyBuffer(m_bb_h, UPPER_BAND, 1, 1, bb_upper) < 1) return m_regime;
        if(CopyBuffer(m_bb_h, LOWER_BAND, 1, 1, bb_lower) < 1) return m_regime;
        if(CopyBuffer(m_bb_h, BASE_LINE,  1, 1, bb_mid)   < 1) return m_regime;

        // ── Compute derived values ─────────────────────────────────────
        m_adx_val   = adx_buf[0];  // index 1 from chart = index 0 in copied array
        double price = (bb_mid[0] > 0.0) ? bb_mid[0] : tick.bid;
        m_bb_width  = (price > 0.0) ? (bb_upper[0] - bb_lower[0]) / price * 100.0 : 0.0;
        m_atr_ratio = (atr_h1_buf[0] > 0.0) ? atr_m15_buf[0] / atr_h1_buf[0] : 0.0;

        // ── Update rolling BB_Width avg (20-bar circular buffer) ───────
        _UpdateBBWidthAvg(m_bb_width);

        // ── Regime logic (priority order) ─────────────────────────────
        m_prev_regime = m_regime;
        ENUM_MARKET_REGIME new_regime = _ClassifyRegime();

        if(new_regime != m_prev_regime)
        {
            PrintFormat("[SimpleRegime] REGIME CHANGE: %s → %s | ADX=%.1f BB_W=%.3f ATR_ratio=%.3f",
                        RegimeToString(m_prev_regime), RegimeToString(new_regime),
                        m_adx_val, m_bb_width, m_atr_ratio);
        }

        m_regime = new_regime;
        m_confidence = _CalcConfidence();
        return m_regime;
    }

    // ── Accessors ────────────────────────────────────────────────────
    ENUM_MARKET_REGIME  GetRegime()     const { return m_regime; }
    double              GetConfidence() const { return m_confidence; }
    double              GetADX()        const { return m_adx_val; }
    double              GetBBWidth()    const { return m_bb_width; }
    double              GetATRRatio()   const { return m_atr_ratio; }
    bool                IsReady()       const { return m_ready; }

    //+------------------------------------------------------------------+
    //| GetStatusString: One-line summary for logging                    |
    //+------------------------------------------------------------------+
    string GetStatusString()
    {
        return StringFormat("regime=%s conf=%.2f ADX=%.1f BB_W=%.3f(avg=%.3f) ATR_r=%.3f",
                            RegimeToString(m_regime), m_confidence,
                            m_adx_val, m_bb_width, m_bb_width_avg, m_atr_ratio);
    }

private:
    //+------------------------------------------------------------------+
    //| _ClassifyRegime: Apply rules with hysteresis                     |
    //+------------------------------------------------------------------+
    ENUM_MARKET_REGIME _ClassifyRegime()
    {
        // ── Priority 1: SQUEEZE — tight bands + low ADX ───────────────
        // BB_Width < squeeze_mult × 20-bar avg AND ADX < 20
        if(m_bb_buf_full && m_bb_width_avg > 0.0)
        {
            double squeeze_thresh = m_squeeze_mult * m_bb_width_avg;
            if(m_bb_width < squeeze_thresh && m_adx_val < 20.0)
                return REGIME_SQUEEZE;
        }

        // ── Priority 2: VOLATILE — high ADX spike ─────────────────────
        if(m_adx_val >= m_adx_volatile)
            return REGIME_VOLATILE;

        // ── Priority 3: TRENDING — with hysteresis ────────────────────
        // Enter: ADX ≥ enter_thresh
        // Exit:  ADX < exit_thresh (hysteresis gap prevents whipsaw)
        if(m_prev_regime == REGIME_TRENDING)
        {
            // Already trending — keep until ADX drops below EXIT threshold
            if(m_adx_val >= m_adx_trend_exit)
                return REGIME_TRENDING;
            // Fell below exit → re-evaluate below
        }
        else
        {
            // Not trending — need ADX to cross ENTER threshold
            if(m_adx_val >= m_adx_trend_enter)
                return REGIME_TRENDING;
        }

        // ── Priority 4: RANGING — default low-ADX state ───────────────
        return REGIME_RANGING;
    }

    //+------------------------------------------------------------------+
    //| _CalcConfidence: 0.0-1.0 based on how far ADX is from threshold  |
    //+------------------------------------------------------------------+
    double _CalcConfidence()
    {
        double conf = 0.5;  // base

        switch(m_regime)
        {
            case REGIME_TRENDING:
            {
                // Distance from enter threshold; max at ADX=40
                double delta = m_adx_val - m_adx_trend_enter;
                conf = 0.5 + MathMin(delta / 26.0, 0.5);  // 0.5 to 1.0
                break;
            }
            case REGIME_VOLATILE:
            {
                double delta = m_adx_val - m_adx_volatile;
                conf = 0.65 + MathMin(delta / 40.0, 0.35); // 0.65 to 1.0
                break;
            }
            case REGIME_SQUEEZE:
            {
                // Tighter vs avg → higher confidence
                double ratio = (m_bb_width_avg > 0.0) ? m_bb_width / m_bb_width_avg : 1.0;
                conf = 0.5 + MathMax(0.5 - ratio * 0.5, 0.0); // 0.5 to 1.0
                break;
            }
            case REGIME_RANGING:
            {
                // How far below enter threshold
                double below = m_adx_trend_enter - m_adx_val;
                conf = 0.4 + MathMin(below / 27.0, 0.5); // 0.4 to 0.9
                break;
            }
            default:
                conf = 0.3;
        }

        return MathMax(0.0, MathMin(1.0, conf));
    }

    //+------------------------------------------------------------------+
    //| _UpdateBBWidthAvg: Rolling 20-bar average of BB_Width            |
    //+------------------------------------------------------------------+
    void _UpdateBBWidthAvg(double width)
    {
        m_bb_width_buf[m_bb_buf_idx] = width;
        m_bb_buf_idx = (m_bb_buf_idx + 1) % 20;
        if(m_bb_buf_idx == 0) m_bb_buf_full = true;

        // Compute average over filled entries
        int count = m_bb_buf_full ? 20 : m_bb_buf_idx;
        if(count == 0) return;
        double sum = 0.0;
        for(int i = 0; i < count; i++) sum += m_bb_width_buf[i];
        m_bb_width_avg = sum / count;
    }
};

#endif // SIMPLE_REGIME_MQH
//+------------------------------------------------------------------+
