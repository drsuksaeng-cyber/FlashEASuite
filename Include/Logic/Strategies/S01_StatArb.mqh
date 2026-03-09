//+------------------------------------------------------------------+
//| S01_StatArb.mqh                                                  |
//| FlashEASuite V2 — Statistical Arbitrage (Pairs Trading)         |
//| Magic: 1001 | Type: Hybrid | Standalone: Yes                    |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|  Online : Python ส่ง Beta + pair selection ผ่าน CONFIG_PUSH     |
//|  Offline: ใช้ Beta=1.0, monitor EURUSD vs GBPUSD               |
//|  Spread = Price_A - (Beta * Price_B)                            |
//|  Z-Score = (Spread - MA(20)) / StdDev(20)                       |
//|  Entry: Long  @ Z < -EntryZ, Short @ Z > +EntryZ               |
//|  Exit : Z → 0 หรือ |Z| > StopZ                                |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef S01_STATARB_MQH
#define S01_STATARB_MQH

#include "../IStrategy.mqh"

//--- Input Parameters
input int    StatArb_Period  = 20;        // Z-Score lookback period
input double StatArb_EntryZ  = 2.0;       // Z-Score threshold for entry
input double StatArb_StopZ   = 3.0;       // Z-Score threshold for emergency exit
input string StatArb_Pair1   = "EURUSD";  // Pair A (standalone fallback)
input string StatArb_Pair2   = "GBPUSD";  // Pair B (standalone fallback)

//+------------------------------------------------------------------+
//| CStatArb — Statistical Arbitrage Strategy                        |
//+------------------------------------------------------------------+
class CStatArb : public IStrategy
{
private:
    //--- Dynamic params (updated by CONFIG_PUSH)
    double  m_beta;             // Hedge ratio Beta (Python-calculated online)
    int     m_period;           // Lookback period for MA/StdDev
    double  m_entry_z;          // Entry Z threshold
    double  m_stop_z;           // Emergency exit Z threshold
    string  m_pair1;            // Symbol A
    string  m_pair2;            // Symbol B

    //--- Spread history buffer
    double  m_spread_buf[];     // Rolling buffer of spread values
    int     m_buf_pos;          // Current write position (circular)
    bool    m_buf_full;         // Has buffer been filled at least once?

    //--- Indicator handles
    int     m_rsi_handle;       // Not used for S01, kept for consistency

    //--- Internal state
    double  m_last_zscore;      // Last computed Z-Score (for logging)
    bool    m_in_long_spread;   // Currently long spread position
    bool    m_in_short_spread;  // Currently short spread position

    //=================================================================
    //  PRIVATE HELPERS
    //=================================================================

    //+------------------------------------------------------------------+
    //| _GetMidPrice: Get current mid price for a symbol                |
    //| In Strategy Tester, SymbolInfoDouble returns 0 for non-chart    |
    //| symbols — fall back to CopyClose() bar data instead.            |
    //+------------------------------------------------------------------+
    double _GetMidPrice(string symbol)
    {
        if(MQLInfoInteger(MQL_TESTER))
        {
            double arr[1];
            if(CopyClose(symbol, PERIOD_CURRENT, 0, 1, arr) > 0) return arr[0];
            return 0.0;
        }
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        if(bid <= 0 || ask <= 0) return 0.0;
        return (bid + ask) * 0.5;
    }

    //+------------------------------------------------------------------+
    //| _PushSpread: Add new spread value to circular buffer            |
    //+------------------------------------------------------------------+
    void _PushSpread(double value)
    {
        m_spread_buf[m_buf_pos] = value;
        m_buf_pos = (m_buf_pos + 1) % m_period;
        if(m_buf_pos == 0) m_buf_full = true;
    }

    //+------------------------------------------------------------------+
    //| _BufferCount: How many valid samples are in the buffer?         |
    //+------------------------------------------------------------------+
    int _BufferCount()
    {
        return m_buf_full ? m_period : m_buf_pos;
    }

    //+------------------------------------------------------------------+
    //| _CalcMean: Mean of all valid samples in buffer                  |
    //+------------------------------------------------------------------+
    double _CalcMean()
    {
        int n = _BufferCount();
        if(n == 0) return 0.0;
        double sum = 0.0;
        for(int i = 0; i < n; i++) sum += m_spread_buf[i];
        return sum / n;
    }

    //+------------------------------------------------------------------+
    //| _CalcStdDev: Population StdDev of buffer                        |
    //+------------------------------------------------------------------+
    double _CalcStdDev(double mean)
    {
        int n = _BufferCount();
        if(n < 2) return 0.0001;   // Guard against division by zero
        double sum_sq = 0.0;
        for(int i = 0; i < n; i++)
        {
            double diff = m_spread_buf[i] - mean;
            sum_sq += diff * diff;
        }
        double sd = MathSqrt(sum_sq / n);
        return (sd < 0.000001) ? 0.000001 : sd;   // Minimum noise floor
    }

    //+------------------------------------------------------------------+
    //| _CalcZScore: Z = (current_spread - mean) / stdev               |
    //+------------------------------------------------------------------+
    double _CalcZScore(double spread)
    {
        int n = _BufferCount();
        if(n < m_period) return 0.0;  // Wait until buffer is full

        double mean = _CalcMean();
        double sd   = _CalcStdDev(mean);
        return (spread - mean) / sd;
    }

    //+------------------------------------------------------------------+
    //| _ParseJsonDouble: Simple JSON value extractor                   |
    //| Finds  "key": value  pattern; returns default_val if not found  |
    //+------------------------------------------------------------------+
    double _ParseJsonDouble(const string &json, const string key, double default_val)
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return default_val;

        int start = pos + StringLen(search);
        // Skip whitespace
        while(start < StringLen(json) && StringGetCharacter(json, start) == ' ') start++;

        // Read until delimiter
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
    //| _ParseJsonString: Extract string value from JSON                |
    //+------------------------------------------------------------------+
    string _ParseJsonString(const string &json, const string key, const string default_val)
    {
        string search = "\"" + key + "\":\"";
        int pos = StringFind(json, search);
        if(pos < 0) return default_val;

        int start = pos + StringLen(search);
        int end   = StringFind(json, "\"", start);
        if(end < 0) return default_val;

        return StringSubstr(json, start, end - start);
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CStatArb()
    {
        m_strategy_id   = S01_STAT_ARB;

        // Default parameters
        m_beta          = 1.0;
        m_period        = StatArb_Period;
        m_entry_z       = StatArb_EntryZ;
        m_stop_z        = StatArb_StopZ;
        m_pair1         = StatArb_Pair1;
        m_pair2         = StatArb_Pair2;

        m_buf_pos       = 0;
        m_buf_full      = false;
        m_last_zscore   = 0.0;
        m_in_long_spread  = false;
        m_in_short_spread = false;
        m_rsi_handle    = INVALID_HANDLE;
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CStatArb()
    {
        Deinit();
    }

    //=================================================================
    //  CORE INTERFACE OVERRIDES
    //=================================================================

    //+------------------------------------------------------------------+
    //| Init: Allocate spread buffer, validate symbols                  |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES tf)
    {
        // Call base class Init
        if(!IStrategy::Init(symbol, tf)) return false;

        // Set strategy identity
        m_strategy_id = S01_STAT_ARB;
        m_info = g_strategy_table[S01_STAT_ARB];

        // Use first chart symbol as Pair1 if not standalone fallback
        // In hybrid mode, Python will push pair1/pair2 via CONFIG_PUSH
        if(m_pair1 == "") m_pair1 = symbol;

        // Allocate circular buffer
        ArrayResize(m_spread_buf, m_period);
        ArrayInitialize(m_spread_buf, 0.0);
        m_buf_pos  = 0;
        m_buf_full = false;

        // Validate Pair2 is accessible
        if(!SymbolSelect(m_pair2, true))
        {
            PrintFormat("[S01] WARNING: Symbol %s not found in Market Watch — using Pair2 fallback", m_pair2);
            // Non-fatal: we'll check at runtime
        }

        m_initialized = true;
        PrintFormat("[S01] StatArb Init OK | Pair1=%s Pair2=%s Beta=%.4f Period=%d EntryZ=%.2f StopZ=%.2f",
                    m_pair1, m_pair2, m_beta, m_period, m_entry_z, m_stop_z);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Deinit: Release resources                                       |
    //+------------------------------------------------------------------+
    virtual void Deinit()
    {
        if(m_rsi_handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_rsi_handle);
            m_rsi_handle = INVALID_HANDLE;
        }
        IStrategy::Deinit();
    }

    //+------------------------------------------------------------------+
    //| Analyze: Main tick processing                                   |
    //| 1. Get mid prices for both pairs                                |
    //| 2. Compute spread = P_A - (Beta * P_B)                         |
    //| 3. Push spread into rolling buffer                              |
    //| 4. Compute Z-Score                                              |
    //| 5. Generate BUY/SELL/NONE signal                               |
    //+------------------------------------------------------------------+
    virtual void Analyze(const MqlTick &tick)
    {
        if(!m_initialized || !m_enabled) return;

        // --- Step 1: Get prices
        double price_a = _GetMidPrice(m_pair1);
        double price_b = _GetMidPrice(m_pair2);

        if(price_a <= 0 || price_b <= 0)
        {
            // Cannot get valid prices — skip this tick
            m_state.last_signal = SIGNAL_NONE;
            return;
        }

        // --- Step 2: Calculate spread
        double spread = price_a - (m_beta * price_b);

        // --- Step 3: Update rolling buffer
        _PushSpread(spread);

        // --- Step 4: Calculate Z-Score (requires full buffer)
        double zscore = _CalcZScore(spread);
        m_last_zscore = zscore;

        // --- Step 5: Generate signal
        ENUM_TRADE_SIGNAL new_signal = SIGNAL_NONE;

        // Entry logic
        if(!m_in_long_spread && !m_in_short_spread)
        {
            if(zscore < -m_entry_z)
            {
                // Spread too low → expect mean reversion upward → LONG spread (buy A, sell B)
                new_signal = SIGNAL_BUY;
                m_in_long_spread = true;
            }
            else if(zscore > m_entry_z)
            {
                // Spread too high → expect mean reversion downward → SHORT spread (sell A, buy B)
                new_signal = SIGNAL_SELL;
                m_in_short_spread = true;
            }
        }
        // Exit logic — check if we're in a position
        else if(m_in_long_spread)
        {
            if(zscore >= 0.0 || zscore < -m_stop_z)
            {
                // Z returned to mean OR exceeded emergency stop
                new_signal = SIGNAL_NONE;
                m_in_long_spread = false;
            }
            else
            {
                // Still in trade, maintain signal
                new_signal = SIGNAL_BUY;
            }
        }
        else if(m_in_short_spread)
        {
            if(zscore <= 0.0 || zscore > m_stop_z)
            {
                new_signal = SIGNAL_NONE;
                m_in_short_spread = false;
            }
            else
            {
                new_signal = SIGNAL_SELL;
            }
        }

        // --- Confidence Calculation
        // Higher |Z-score| relative to entry threshold → higher confidence
        // Caps at 1.0 when |Z| reaches StopZ
        double abs_z = MathAbs(zscore);
        double conf  = 0.0;

        if(abs_z >= m_entry_z)
        {
            conf = MathMin(1.0, (abs_z - m_entry_z) / (m_stop_z - m_entry_z));
            // Reduce confidence as Z approaches stop level (risk of overshoot)
            if(abs_z > m_stop_z * 0.85)
                conf *= 0.7;  // Penalty factor near emergency exit
        }

        // --- SL / TP (price levels on Pair1)
        double atr_approx  = MathAbs(price_a) * 0.001;  // 0.1% of price as ATR proxy
        double sl_distance = atr_approx * 2.0;
        double tp_distance = atr_approx * 1.5;  // TP closer: mean reversion strategy

        if(new_signal == SIGNAL_BUY)
        {
            m_state.last_sl = price_a - sl_distance;
            m_state.last_tp = price_a + tp_distance;
        }
        else if(new_signal == SIGNAL_SELL)
        {
            m_state.last_sl = price_a + sl_distance;
            m_state.last_tp = price_a - tp_distance;
        }
        else
        {
            m_state.last_sl = 0.0;
            m_state.last_tp = 0.0;
        }

        // --- Update state
        m_state.last_signal     = new_signal;
        m_state.last_confidence = conf;
        m_state.last_signal_time = TimeCurrent();
    }

    //+------------------------------------------------------------------+
    //| GetSignal: Return current signal                                |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetSignal()
    {
        return m_state.last_signal;
    }

    //+------------------------------------------------------------------+
    //| GetConfidence: Return signal confidence 0.0-1.0                 |
    //+------------------------------------------------------------------+
    virtual double GetConfidence()
    {
        return m_state.last_confidence;
    }

    //=================================================================
    //  CONFIG INTERFACE
    //=================================================================

    //+------------------------------------------------------------------+
    //| SetParameters: Parse JSON from CONFIG_PUSH                      |
    //| Expected keys: StatArb_Beta, StatArb_Period, StatArb_EntryZ,    |
    //|                StatArb_StopZ, StatArb_Pair1, StatArb_Pair2      |
    //+------------------------------------------------------------------+
    virtual void SetParameters(const string jsonParams)
    {
        IStrategy::SetParameters(jsonParams);
        if(jsonParams == "") return;

        double new_beta   = _ParseJsonDouble(jsonParams, "StatArb_Beta",   m_beta);
        double new_period = _ParseJsonDouble(jsonParams, "StatArb_Period",  (double)m_period);
        double new_entry  = _ParseJsonDouble(jsonParams, "StatArb_EntryZ",  m_entry_z);
        double new_stop   = _ParseJsonDouble(jsonParams, "StatArb_StopZ",   m_stop_z);
        string new_pair1  = _ParseJsonString(jsonParams, "StatArb_Pair1",   m_pair1);
        string new_pair2  = _ParseJsonString(jsonParams, "StatArb_Pair2",   m_pair2);

        // Apply beta change (hot-reload)
        if(MathAbs(new_beta - m_beta) > 0.0001)
        {
            OnParamUpdate("StatArb_Beta", m_beta, new_beta);
            m_beta = new_beta;
        }

        // Apply period change (requires buffer resize + reset)
        int int_period = (int)MathMax(5, new_period);
        if(int_period != m_period)
        {
            OnParamUpdate("StatArb_Period", (double)m_period, (double)int_period);
            m_period = int_period;
            ArrayResize(m_spread_buf, m_period);
            ArrayInitialize(m_spread_buf, 0.0);
            m_buf_pos  = 0;
            m_buf_full = false;
        }

        // Thresholds
        if(MathAbs(new_entry - m_entry_z) > 0.001)
        {
            OnParamUpdate("StatArb_EntryZ", m_entry_z, new_entry);
            m_entry_z = new_entry;
        }
        if(MathAbs(new_stop - m_stop_z) > 0.001)
        {
            OnParamUpdate("StatArb_StopZ", m_stop_z, new_stop);
            m_stop_z = new_stop;
        }

        // Pair changes (reset state if changed)
        if(new_pair1 != "" && new_pair1 != m_pair1)
        {
            PrintFormat("[S01] Pair1 changed: %s → %s", m_pair1, new_pair1);
            m_pair1 = new_pair1;
            _ResetSpreadBuffer();
        }
        if(new_pair2 != "" && new_pair2 != m_pair2)
        {
            PrintFormat("[S01] Pair2 changed: %s → %s", m_pair2, new_pair2);
            m_pair2 = new_pair2;
            SymbolSelect(m_pair2, true);
            _ResetSpreadBuffer();
        }
    }

    //+------------------------------------------------------------------+
    //| SetDynamicParams: Apply CONFIG_PUSH V2 bundle                   |
    //+------------------------------------------------------------------+
    virtual void SetDynamicParams(SDynamicParams &params)
    {
        IStrategy::SetDynamicParams(params);

        double v;
        v = params.GetParam("S01_BETA",     m_beta);      if(MathAbs(v - m_beta)    > 0.0001) { OnParamUpdate("S01_BETA", m_beta, v);       m_beta    = v; }
        v = params.GetParam("S01_PERIOD",   (double)m_period); int p = (int)MathMax(5, v); if(p != m_period) { OnParamUpdate("S01_PERIOD", (double)m_period, v); m_period = p; ArrayResize(m_spread_buf, m_period); ArrayInitialize(m_spread_buf, 0.0); m_buf_pos = 0; m_buf_full = false; }
        v = params.GetParam("S01_ENTRY_Z",  m_entry_z);   if(MathAbs(v - m_entry_z) > 0.001)  { OnParamUpdate("S01_ENTRY_Z", m_entry_z, v); m_entry_z = v; }
        v = params.GetParam("S01_STOP_Z",   m_stop_z);    if(MathAbs(v - m_stop_z)  > 0.001)  { OnParamUpdate("S01_STOP_Z",  m_stop_z,  v); m_stop_z  = v; }
    }

    //+------------------------------------------------------------------+
    //| GetCurrentParams: Export current params for TRADE_REPORT        |
    //+------------------------------------------------------------------+
    virtual SDynamicParams GetCurrentParams()
    {
        SDynamicParams p;
        p.Reset();
        p.mm_method = m_config.mm_method;
        p.SetParam("S01_BETA",    m_beta);
        p.SetParam("S01_PERIOD",  (double)m_period);
        p.SetParam("S01_ENTRY_Z", m_entry_z);
        p.SetParam("S01_STOP_Z",  m_stop_z);
        return p;
    }

    //+------------------------------------------------------------------+
    //| GetName: Strategy display name                                  |
    //+------------------------------------------------------------------+
    virtual string GetName() { return "Statistical Arbitrage"; }

    //+------------------------------------------------------------------+
    //| GetMagic: Magic number                                          |
    //+------------------------------------------------------------------+
    virtual int GetMagic() { return MAGIC_S01_STAT_ARB; }

    //+------------------------------------------------------------------+
    //| IsStandaloneCapable: Yes — uses Beta=1.0, EURUSD/GBPUSD        |
    //+------------------------------------------------------------------+
    virtual bool IsStandaloneCapable() { return true; }

    //+------------------------------------------------------------------+
    //| GetCategory: Hybrid (Python calculates Beta)                    |
    //+------------------------------------------------------------------+
    virtual string GetCategory() { return "Hybrid"; }

    //=================================================================
    //  DIAGNOSTICS
    //=================================================================

    //+------------------------------------------------------------------+
    //| GetLastZScore: For external reporting / dashboard               |
    //+------------------------------------------------------------------+
    double GetLastZScore() const { return m_last_zscore; }

    //+------------------------------------------------------------------+
    //| GetBeta: Current hedge ratio                                    |
    //+------------------------------------------------------------------+
    double GetBeta() const { return m_beta; }

    //+------------------------------------------------------------------+
    //| PrintDiagnostics: Full state dump                               |
    //+------------------------------------------------------------------+
    void PrintDiagnostics()
    {
        PrintFormat("[S01] StatArb | Pair1=%s Pair2=%s Beta=%.4f Period=%d",
                    m_pair1, m_pair2, m_beta, m_period);
        PrintFormat("[S01] Z-Score=%.4f EntryZ=±%.2f StopZ=±%.2f",
                    m_last_zscore, m_entry_z, m_stop_z);
        PrintFormat("[S01] Signal=%s Confidence=%.4f BufFull=%s",
                    SignalToString(m_state.last_signal),
                    m_state.last_confidence,
                    m_buf_full ? "YES" : "NO");
    }

private:
    //+------------------------------------------------------------------+
    //| _ResetSpreadBuffer: Clear history (called on pair change)       |
    //+------------------------------------------------------------------+
    void _ResetSpreadBuffer()
    {
        ArrayInitialize(m_spread_buf, 0.0);
        m_buf_pos  = 0;
        m_buf_full = false;
        m_in_long_spread  = false;
        m_in_short_spread = false;
        m_state.last_signal = SIGNAL_NONE;
    }
};

#endif // S01_STATARB_MQH
//+------------------------------------------------------------------+
