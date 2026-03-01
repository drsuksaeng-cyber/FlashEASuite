//+------------------------------------------------------------------+
//| S11_Ichimoku.mqh                                                 |
//| FlashEASuite V2 — Multi-Timeframe Ichimoku                       |
//| Magic: 1011 | Type: Full MQL5 | Standalone: No (ServerOnly)     |
//+------------------------------------------------------------------+
//| LOGIC (3-tier multi-timeframe analysis):                         |
//|  D1  — Major trend: price position above/below Kumo cloud        |
//|  H4  — Confirm trend: Tenkan/Kijun cross direction               |
//|  H1  — Entry timing: Tenkan × Kijun + above/below cloud          |
//|  Chikou: Must clear price 26 bars ago (confirmation)             |
//|  Exit: Tenkan/Kijun cross against position OR price enters cloud |
//|  Confidence = cloud_thickness × tenkan_kijun_dist × tf_alignment |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S11_ICHIMOKU_MQH
#define S11_ICHIMOKU_MQH

#include "../IStrategy.mqh"

//--- Input Parameters
input int    IKU_Tenkan_Period    = 9;    // Tenkan-sen (Conversion Line) period
input int    IKU_Kijun_Period     = 26;   // Kijun-sen (Base Line) period
input int    IKU_Senkou_B_Period  = 52;   // Senkou Span B (cloud) period
input int    IKU_Chikou_Shift     = 26;   // Chikou Span lookback shift
input double IKU_Cloud_Min_Width  = 10.0; // Minimum cloud width in pips (thin cloud = skip)
input double IKU_TF_D1_Weight     = 0.40; // D1 alignment weight for confidence
input double IKU_TF_H4_Weight     = 0.35; // H4 alignment weight for confidence
input double IKU_TF_H1_Weight     = 0.25; // H1 alignment weight for confidence

//+------------------------------------------------------------------+
//| Helper: Ichimoku values for one timeframe                        |
//+------------------------------------------------------------------+
struct SIchimokuSnapshot
{
    double tenkan;        // Tenkan-sen value
    double kijun;         // Kijun-sen value
    double senkou_a;      // Senkou Span A (leading cloud upper/lower)
    double senkou_b;      // Senkou Span B (leading cloud upper/lower)
    double chikou;        // Chikou span (close shifted back 26 bars)
    double cloud_top;     // Max(Senkou A, Senkou B)
    double cloud_bot;     // Min(Senkou A, Senkou B)
    double close;         // Last close for reference
    bool   valid;         // Was data successfully read?

    void Reset()
    {
        tenkan = kijun = senkou_a = senkou_b = chikou = 0.0;
        cloud_top = cloud_bot = close = 0.0;
        valid = false;
    }
};

//+------------------------------------------------------------------+
//| CIchimoku — Multi-Timeframe Ichimoku Strategy                    |
//+------------------------------------------------------------------+
class CIchimoku : public IStrategy
{
private:
    //--- Dynamic params (hot-reloadable via CONFIG_PUSH)
    int     m_tenkan_period;      // S11_TENKAN
    int     m_kijun_period;       // S11_KIJUN
    int     m_senkou_b_period;    // S11_SENKOU_B
    int     m_chikou_shift;       // S11_CHIKOU_SHIFT
    double  m_cloud_min_width;    // S11_CLOUD_MIN (pips)
    double  m_tf_d1_weight;       // S11_TF_D1_W
    double  m_tf_h4_weight;       // S11_TF_H4_W
    double  m_tf_h1_weight;       // S11_TF_H1_W

    //--- Indicator handles (separate per TF)
    int     m_iku_d1_handle;      // D1 Ichimoku
    int     m_iku_h4_handle;      // H4 Ichimoku
    int     m_iku_h1_handle;      // H1 Ichimoku (entry TF)

    //--- Last computed snapshots
    SIchimokuSnapshot m_d1;
    SIchimokuSnapshot m_h4;
    SIchimokuSnapshot m_h1;

    //--- Internal trend state
    int     m_d1_trend;    // +1 = bullish, -1 = bearish, 0 = neutral
    int     m_h4_trend;    // +1 = bullish, -1 = bearish, 0 = neutral
    int     m_h1_signal;   // +1 = buy cross, -1 = sell cross, 0 = no cross

    //--- To detect fresh H1 Tenkan/Kijun cross (only fire once per bar)
    datetime m_last_h1_cross_bar;
    int      m_last_h1_cross_dir; // +1/-1

    double   m_point_value;
    int      m_digits;

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    //+------------------------------------------------------------------+
    //| _PipSize: 1 pip in price units                                   |
    //+------------------------------------------------------------------+
    double _PipSize()
    {
        return (m_digits == 3 || m_digits == 5) ? m_point_value * 10.0 : m_point_value;
    }

    //+------------------------------------------------------------------+
    //| _InitIndicators: Create Ichimoku handles for D1, H4, H1          |
    //+------------------------------------------------------------------+
    bool _InitIndicators()
    {
        _ReleaseIndicators();

        m_iku_d1_handle = iIchimoku(m_symbol, PERIOD_D1,
                                     m_tenkan_period,
                                     m_kijun_period,
                                     m_senkou_b_period);
        if(m_iku_d1_handle == INVALID_HANDLE)
        {
            Print("[S11] ERROR: D1 Ichimoku handle failed");
            return false;
        }

        m_iku_h4_handle = iIchimoku(m_symbol, PERIOD_H4,
                                     m_tenkan_period,
                                     m_kijun_period,
                                     m_senkou_b_period);
        if(m_iku_h4_handle == INVALID_HANDLE)
        {
            Print("[S11] ERROR: H4 Ichimoku handle failed");
            return false;
        }

        m_iku_h1_handle = iIchimoku(m_symbol, PERIOD_H1,
                                     m_tenkan_period,
                                     m_kijun_period,
                                     m_senkou_b_period);
        if(m_iku_h1_handle == INVALID_HANDLE)
        {
            Print("[S11] ERROR: H1 Ichimoku handle failed");
            return false;
        }

        PrintFormat("[S11] Ichimoku D1/H4/H1 | Tenkan=%d Kijun=%d SenkouB=%d Chikou=%d",
                    m_tenkan_period, m_kijun_period, m_senkou_b_period, m_chikou_shift);
        return true;
    }

    //+------------------------------------------------------------------+
    //| _ReleaseIndicators: Free all handles                             |
    //+------------------------------------------------------------------+
    void _ReleaseIndicators()
    {
        if(m_iku_d1_handle != INVALID_HANDLE) { IndicatorRelease(m_iku_d1_handle); m_iku_d1_handle = INVALID_HANDLE; }
        if(m_iku_h4_handle != INVALID_HANDLE) { IndicatorRelease(m_iku_h4_handle); m_iku_h4_handle = INVALID_HANDLE; }
        if(m_iku_h1_handle != INVALID_HANDLE) { IndicatorRelease(m_iku_h1_handle); m_iku_h1_handle = INVALID_HANDLE; }
    }

    //+------------------------------------------------------------------+
    //| _ReadIchimoku: Fill SIchimokuSnapshot from indicator handle      |
    //| MQL5 iIchimoku buffer indices:                                   |
    //|  0 = Tenkan-sen                                                  |
    //|  1 = Kijun-sen                                                   |
    //|  2 = Senkou Span A (current, shifted +26 on chart)              |
    //|  3 = Senkou Span B (current, shifted +26 on chart)              |
    //|  4 = Chikou Span   (close shifted -26 on chart)                 |
    //+------------------------------------------------------------------+
    bool _ReadIchimoku(int handle, SIchimokuSnapshot &snap, ENUM_TIMEFRAMES tf)
    {
        snap.Reset();
        if(handle == INVALID_HANDLE) return false;

        double buf[1];

        // Tenkan-sen (shift=1: completed bar)
        if(CopyBuffer(handle, 0, 1, 1, buf) != 1) return false;
        snap.tenkan = buf[0];

        // Kijun-sen
        if(CopyBuffer(handle, 1, 1, 1, buf) != 1) return false;
        snap.kijun = buf[0];

        // Senkou Span A — the cloud is plotted 26 bars ahead, so for current cloud
        // we use shift = -(Kijun_period - 1) but in MQL5 with iIchimoku we read shift=1
        // Buffer 2 = Senkou Span A (future cloud): shift = 1-m_kijun_period for current cloud
        int cloud_shift = 1 - m_kijun_period;  // negative = future bars → leads indicator
        // For current price vs cloud: use shift = 1 (bar 1 shows cloud that covers current price)
        // Actually in MQL5, Senkou Span A at shift=1 gives the cloud value at the current bar
        if(CopyBuffer(handle, 2, 1, 1, buf) != 1) return false;
        snap.senkou_a = buf[0];

        if(CopyBuffer(handle, 3, 1, 1, buf) != 1) return false;
        snap.senkou_b = buf[0];

        // Chikou Span — plotted 26 bars back; shift = m_chikou_shift gives close 26 bars ago
        if(CopyBuffer(handle, 4, m_chikou_shift + 1, 1, buf) != 1) return false;
        snap.chikou = buf[0];

        // Last close for chikou comparison
        double close_buf[1];
        if(CopyClose(m_symbol, tf, 1, 1, close_buf) != 1) return false;
        snap.close = close_buf[0];

        snap.cloud_top = MathMax(snap.senkou_a, snap.senkou_b);
        snap.cloud_bot = MathMin(snap.senkou_a, snap.senkou_b);
        snap.valid = true;
        return true;
    }

    //+------------------------------------------------------------------+
    //| _GetD1Trend: +1 bullish / -1 bearish / 0 neutral                |
    //| Bullish: price above cloud AND Tenkan >= Kijun                  |
    //+------------------------------------------------------------------+
    int _GetD1Trend(const SIchimokuSnapshot &s)
    {
        if(!s.valid) return 0;
        bool price_above_cloud = (s.close > s.cloud_top);
        bool price_below_cloud = (s.close < s.cloud_bot);
        if(price_above_cloud && s.tenkan >= s.kijun) return  1;
        if(price_below_cloud && s.tenkan <= s.kijun) return -1;
        return 0;  // price inside cloud or mixed signals
    }

    //+------------------------------------------------------------------+
    //| _GetH4Trend: +1 / -1 / 0 — Tenkan/Kijun cross + cloud position  |
    //+------------------------------------------------------------------+
    int _GetH4Trend(const SIchimokuSnapshot &s)
    {
        if(!s.valid) return 0;
        // Bullish cross: Tenkan > Kijun AND price above cloud
        if(s.tenkan > s.kijun && s.close > s.cloud_top) return  1;
        if(s.tenkan < s.kijun && s.close < s.cloud_bot) return -1;
        return 0;
    }

    //+------------------------------------------------------------------+
    //| _GetH1CrossSignal: Detect fresh Tenkan/Kijun cross on H1         |
    //| Returns +1 (bullish cross just completed) / -1 / 0              |
    //+------------------------------------------------------------------+
    int _GetH1CrossSignal(int handle)
    {
        if(handle == INVALID_HANDLE) return 0;

        // Read 2 bars: shift=1 (just-closed) and shift=2 (prior)
        // ✅ Dynamic arrays — ArraySetAsSeries ใช้ไม่ได้กับ static array (MQL5 rule)
        double tenkan[], kijun[];
        ArrayResize(tenkan, 2);
        ArrayResize(kijun,  2);
        ArraySetAsSeries(tenkan, true);
        ArraySetAsSeries(kijun,  true);

        if(CopyBuffer(handle, 0, 1, 2, tenkan) != 2) return 0;
        if(CopyBuffer(handle, 1, 1, 2, kijun)  != 2) return 0;

        // Cross detection: bar[1] (older) had tenkan below kijun, bar[0] above = bullish cross
        bool bullish_cross = (tenkan[1] <= kijun[1]) && (tenkan[0] > kijun[0]);
        bool bearish_cross = (tenkan[1] >= kijun[1]) && (tenkan[0] < kijun[0]);

        if(bullish_cross) return  1;
        if(bearish_cross) return -1;
        return 0;
    }

    //+------------------------------------------------------------------+
    //| _ChikouConfirmed: Chikou must clear price 26 bars ago            |
    //| Long: chikou > close_26_bars_ago                                 |
    //+------------------------------------------------------------------+
    bool _ChikouConfirmed(int handle, int direction)
    {
        if(handle == INVALID_HANDLE) return false;

        // Chikou at shift 1 (last closed bar) = close of 26 bars ago (due to shift)
        double chikou_buf[1];
        if(CopyBuffer(handle, 4, 1, 1, chikou_buf) != 1) return false;

        // Price 26 bars ago on close
        double price_ago[1];
        if(CopyClose(m_symbol, PERIOD_H1, m_chikou_shift + 1, 1, price_ago) != 1) return false;

        if(direction > 0) return chikou_buf[0] > price_ago[0];
        if(direction < 0) return chikou_buf[0] < price_ago[0];
        return false;
    }

    //+------------------------------------------------------------------+
    //| _CloudThicknessNorm: Normalized cloud thickness → 0.0-1.0       |
    //| Thicker cloud = stronger support/resistance level                |
    //+------------------------------------------------------------------+
    double _CloudThicknessNorm(const SIchimokuSnapshot &s)
    {
        if(!s.valid || m_last_atr <= 0.0) return 0.5;
        double thick = s.cloud_top - s.cloud_bot;
        // Normalize by ATR: cloud = 1× ATR is reference
        double norm = MathMin(1.0, thick / m_last_atr);
        return norm;
    }

    double m_last_atr; // stored in Analyze for confidence calc

    //+------------------------------------------------------------------+
    //| _CalcConfidence: Weighted multi-TF alignment score               |
    //+------------------------------------------------------------------+
    double _CalcConfidence(int direction)
    {
        // D1 alignment: +1 if d1 trend matches direction
        double d1_score = (m_d1_trend == direction) ? 1.0 : 0.0;
        // H4 alignment
        double h4_score = (m_h4_trend == direction) ? 1.0 : 0.0;
        // H1 entry signal confirmed
        double h1_score = (m_h1_signal == direction) ? 1.0 : 0.0;

        // Weighted combination
        double tf_align = d1_score * m_tf_d1_weight
                        + h4_score * m_tf_h4_weight
                        + h1_score * m_tf_h1_weight;

        // Cloud thickness bonus from H1 cloud
        double cloud_bonus = _CloudThicknessNorm(m_h1);

        // Distance of Tenkan from Kijun on H1 (normalized by cloud width)
        double tk_dist = 0.5;
        if(m_h1.valid && (m_h1.cloud_top - m_h1.cloud_bot) > 0)
            tk_dist = MathMin(1.0, MathAbs(m_h1.tenkan - m_h1.kijun) / (m_h1.cloud_top - m_h1.cloud_bot));

        double conf = tf_align * 0.6 + cloud_bonus * 0.2 + tk_dist * 0.2;
        return MathMax(0.0, MathMin(1.0, conf));
    }

    //+------------------------------------------------------------------+
    //| _ParseJsonDouble: Simple JSON extractor                          |
    //+------------------------------------------------------------------+
    double _ParseJsonDouble(const string &json, const string key, double default_val)
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return default_val;
        int start = pos + StringLen(search);
        while(start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;
        string num_str = "";
        for(int i = start; i < MathMin(start + 20, StringLen(json)); i++)
        {
            ushort ch = StringGetCharacter(json, i);
            if(ch == ',' || ch == '}' || ch == ' ' || ch == '\n') break;
            num_str += ShortToString(ch);
        }
        return (num_str != "") ? StringToDouble(num_str) : default_val;
    }

    //+------------------------------------------------------------------+
    //| _GetATR: Read H1 ATR for confidence normalization                |
    //+------------------------------------------------------------------+
    int m_atr_handle;

    double _ReadATR()
    {
        if(m_atr_handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(m_atr_handle, 0, 1, 1, buf) != 1) return 0.0;
        return buf[0];
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CIchimoku()
    {
        m_strategy_id       = S11_ICHIMOKU;

        m_tenkan_period     = IKU_Tenkan_Period;
        m_kijun_period      = IKU_Kijun_Period;
        m_senkou_b_period   = IKU_Senkou_B_Period;
        m_chikou_shift      = IKU_Chikou_Shift;
        m_cloud_min_width   = IKU_Cloud_Min_Width;
        m_tf_d1_weight      = IKU_TF_D1_Weight;
        m_tf_h4_weight      = IKU_TF_H4_Weight;
        m_tf_h1_weight      = IKU_TF_H1_Weight;

        m_iku_d1_handle     = INVALID_HANDLE;
        m_iku_h4_handle     = INVALID_HANDLE;
        m_iku_h1_handle     = INVALID_HANDLE;
        m_atr_handle        = INVALID_HANDLE;

        m_d1.Reset();
        m_h4.Reset();
        m_h1.Reset();

        m_d1_trend          = 0;
        m_h4_trend          = 0;
        m_h1_signal         = 0;
        m_last_h1_cross_bar = 0;
        m_last_h1_cross_dir = 0;
        m_last_atr          = 0.0;
        m_point_value       = 0.0;
        m_digits            = 5;
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CIchimoku()
    {
        Deinit();
    }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    //+------------------------------------------------------------------+
    //| Init: Initialize for given symbol/timeframe                      |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        if(!IStrategy::Init(symbol, tf)) return false;

        m_strategy_id = S11_ICHIMOKU;
        m_info = g_strategy_table[S11_ICHIMOKU];

        m_point_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        m_digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        // ATR handle for confidence normalization
        m_atr_handle = iATR(symbol, PERIOD_H1, 14);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[S11] WARNING: ATR handle failed — confidence fallback to 0.5");
        }

        if(!_InitIndicators()) return false;

        PrintFormat("[S11] Init OK | %s | D1/H4/H1 Ichimoku | Tenkan=%d Kijun=%d",
                    symbol, m_tenkan_period, m_kijun_period);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release all resources                                    |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        _ReleaseIndicators();
        if(m_atr_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atr_handle);
            m_atr_handle = INVALID_HANDLE;
        }
        IStrategy::Deinit();
    }

    //+------------------------------------------------------------------+
    //| UpdateParams: Hot-reload from CONFIG_PUSH V2                     |
    //+------------------------------------------------------------------+
    virtual void UpdateParams(SDynamicParams &params)
    {
        bool needs_reinit = false;

        int new_tenkan    = (int)params.GetParam("S11_TENKAN",      (double)m_tenkan_period);
        int new_kijun     = (int)params.GetParam("S11_KIJUN",       (double)m_kijun_period);
        int new_senkou_b  = (int)params.GetParam("S11_SENKOU_B",    (double)m_senkou_b_period);
        int new_chikou    = (int)params.GetParam("S11_CHIKOU_SHIFT", (double)m_chikou_shift);

        if(new_tenkan   != m_tenkan_period   ||
           new_kijun    != m_kijun_period    ||
           new_senkou_b != m_senkou_b_period ||
           new_chikou   != m_chikou_shift)
        {
            needs_reinit = true;
        }

        m_tenkan_period   = new_tenkan;
        m_kijun_period    = new_kijun;
        m_senkou_b_period = new_senkou_b;
        m_chikou_shift    = new_chikou;
        m_cloud_min_width = params.GetParam("S11_CLOUD_MIN",  m_cloud_min_width);
        m_tf_d1_weight    = params.GetParam("S11_TF_D1_W",    m_tf_d1_weight);
        m_tf_h4_weight    = params.GetParam("S11_TF_H4_W",    m_tf_h4_weight);
        m_tf_h1_weight    = params.GetParam("S11_TF_H1_W",    m_tf_h1_weight);

        // Normalize weights to sum to 1.0
        double w_sum = m_tf_d1_weight + m_tf_h4_weight + m_tf_h1_weight;
        if(w_sum > 0.0)
        {
            m_tf_d1_weight /= w_sum;
            m_tf_h4_weight /= w_sum;
            m_tf_h1_weight /= w_sum;
        }

        // Ichimoku periods changed → must recreate handles
        if(needs_reinit) _InitIndicators();

        PrintFormat("[S11] Params updated | Tenkan=%d Kijun=%d SenkouB=%d Chikou=%d CloudMin=%.1f D1w=%.2f H4w=%.2f H1w=%.2f",
                    m_tenkan_period, m_kijun_period, m_senkou_b_period, m_chikou_shift,
                    m_cloud_min_width, m_tf_d1_weight, m_tf_h4_weight, m_tf_h1_weight);
    }

    //+------------------------------------------------------------------+
    //| Analyze: Process tick — refresh multi-TF Ichimoku snapshots      |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_enabled || !m_initialized) return;

        // Update ATR
        m_last_atr = _ReadATR();

        // --- Refresh D1 snapshot (lower frequency — sufficient per bar) ---
        _ReadIchimoku(m_iku_d1_handle, m_d1, PERIOD_D1);
        m_d1_trend = _GetD1Trend(m_d1);

        // --- Refresh H4 snapshot ---
        _ReadIchimoku(m_iku_h4_handle, m_h4, PERIOD_H4);
        m_h4_trend = _GetH4Trend(m_h4);

        // --- Refresh H1 snapshot ---
        _ReadIchimoku(m_iku_h1_handle, m_h1, PERIOD_H1);

        // --- D1 must have a clear trend for any trade ---
        if(m_d1_trend == 0)
        {
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            return;
        }

        // --- D1 and H4 must agree ---
        if(m_d1_trend != m_h4_trend)
        {
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            return;
        }

        // --- Check H1 cloud width (thin cloud = weak support → skip) ---
        if(m_h1.valid)
        {
            double cloud_width = (m_h1.cloud_top - m_h1.cloud_bot) / _PipSize();
            if(cloud_width < m_cloud_min_width)
            {
                m_state.last_signal     = SIGNAL_NONE;
                m_state.last_confidence = 0.0;
                return;
            }
        }

        // --- H1 price must be on correct side of cloud ---
        bool price_above_cloud_h1 = m_h1.valid && (tick.bid > m_h1.cloud_top);
        bool price_below_cloud_h1 = m_h1.valid && (tick.ask < m_h1.cloud_bot);

        if(m_d1_trend > 0 && !price_above_cloud_h1)
        {
            m_state.last_signal = SIGNAL_NONE;
            return;
        }
        if(m_d1_trend < 0 && !price_below_cloud_h1)
        {
            m_state.last_signal = SIGNAL_NONE;
            return;
        }

        // --- Detect H1 Tenkan/Kijun cross (only once per bar) ---
        datetime current_h1_bar = iTime(m_symbol, PERIOD_H1, 1); // last closed bar time
        if(current_h1_bar != m_last_h1_cross_bar)
        {
            int cross = _GetH1CrossSignal(m_iku_h1_handle);
            if(cross != 0)
            {
                m_last_h1_cross_bar = current_h1_bar;
                m_last_h1_cross_dir = cross;
                m_h1_signal = cross;
            }
            else
            {
                // No fresh cross → reset H1 signal (avoid stale signals)
                m_h1_signal = 0;
            }
        }

        // --- Entry condition: cross in direction of major trend ---
        int direction = m_d1_trend;  // +1 or -1

        if(m_h1_signal != direction)
        {
            // No aligned H1 entry cross → hold last signal if it's still fresh
            // or clear signal
            if(m_state.last_signal != SIGNAL_NONE)
            {
                // Allow signal to persist for 1 tick only (consumed by StrategyManager)
                // StrategyManager calls GetSignal() and then Analyze() again
                // so we clear here to prevent re-triggering
                m_state.last_signal = SIGNAL_NONE;
            }
            return;
        }

        // --- Chikou Span confirmation ---
        if(!_ChikouConfirmed(m_iku_h1_handle, direction))
        {
            m_state.last_signal     = SIGNAL_NONE;
            m_state.last_confidence = 0.0;
            return;
        }

        // --- All conditions met: generate entry signal ---
        m_state.last_signal     = (direction > 0) ? SIGNAL_BUY : SIGNAL_SELL;
        m_state.last_confidence = _CalcConfidence(direction);

        PrintFormat("[S11] %s | D1=%+d H4=%+d H1_cross=%+d Chikou=OK | Conf=%.2f | Tenkan=%.5f Kijun=%.5f CloudTop=%.5f CloudBot=%.5f",
                    (direction > 0) ? "BUY" : "SELL",
                    m_d1_trend, m_h4_trend, m_h1_signal,
                    m_state.last_confidence,
                    m_h1.tenkan, m_h1.kijun, m_h1.cloud_top, m_h1.cloud_bot);
    }

    //+------------------------------------------------------------------+
    //| GetSignal: Return last signal                                    |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }

    //+------------------------------------------------------------------+
    //| GetConfidence: Return last confidence                            |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }

    //+------------------------------------------------------------------+
    //| ShouldExit: Called by StrategyManager each tick for open pos     |
    //| Returns true when Tenkan/Kijun cross against position OR        |
    //| price re-enters cloud                                            |
    //+------------------------------------------------------------------+
    bool ShouldExit(int position_direction)
    {
        if(!m_h1.valid) return false;

        // Exit if Tenkan/Kijun crossed against us
        if(position_direction > 0 && m_h1.tenkan < m_h1.kijun) return true;
        if(position_direction < 0 && m_h1.tenkan > m_h1.kijun) return true;

        // Exit if price has re-entered cloud (using last tick's close approximation)
        // StrategyManager passes current price for comparison
        return false;
    }

    //+------------------------------------------------------------------+
    //| ShouldExitPrice: Price-based exit — price entering cloud         |
    //+------------------------------------------------------------------+
    bool ShouldExitPrice(double current_price, int position_direction)
    {
        if(!m_h1.valid) return false;
        if(position_direction > 0 && current_price < m_h1.cloud_top) return true;
        if(position_direction < 0 && current_price > m_h1.cloud_bot) return true;
        return false;
    }

    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export params for TRADE_REPORT                 |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.SetParam("S11_TENKAN",       (double)m_tenkan_period);
        p.SetParam("S11_KIJUN",        (double)m_kijun_period);
        p.SetParam("S11_SENKOU_B",     (double)m_senkou_b_period);
        p.SetParam("S11_CHIKOU_SHIFT", (double)m_chikou_shift);
        p.SetParam("S11_CLOUD_MIN",    m_cloud_min_width);
        p.SetParam("S11_TF_D1_W",      m_tf_d1_weight);
        p.SetParam("S11_TF_H4_W",      m_tf_h4_weight);
        p.SetParam("S11_TF_H1_W",      m_tf_h1_weight);
        return p;
    }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================

    //+------------------------------------------------------------------+
    //| PrintIchimokuStatus: Full multi-TF snapshot to terminal         |
    //+------------------------------------------------------------------+
    void PrintIchimokuStatus()
    {
        PrintFormat("[S11] ===== Ichimoku Multi-TF Status =====");
        PrintFormat("[S11] D1  | Trend=%+d | Close=%.5f vs Cloud [%.5f - %.5f] | Tenkan=%.5f Kijun=%.5f",
                    m_d1_trend, m_d1.close, m_d1.cloud_bot, m_d1.cloud_top, m_d1.tenkan, m_d1.kijun);
        PrintFormat("[S11] H4  | Trend=%+d | Close=%.5f vs Cloud [%.5f - %.5f] | Tenkan=%.5f Kijun=%.5f",
                    m_h4_trend, m_h4.close, m_h4.cloud_bot, m_h4.cloud_top, m_h4.tenkan, m_h4.kijun);
        PrintFormat("[S11] H1  | Signal=%+d | Close=%.5f vs Cloud [%.5f - %.5f] | Tenkan=%.5f Kijun=%.5f | Chikou=%.5f",
                    m_h1_signal, m_h1.close, m_h1.cloud_bot, m_h1.cloud_top, m_h1.tenkan, m_h1.kijun, m_h1.chikou);
        PrintFormat("[S11] Alignment: D1=%+d H4=%+d H1_entry=%+d | LastSignal=%s Conf=%.2f",
                    m_d1_trend, m_h4_trend, m_h1_signal,
                    SignalToString(m_state.last_signal), m_state.last_confidence);
    }
};

#endif // S11_ICHIMOKU_MQH
//+------------------------------------------------------------------+
