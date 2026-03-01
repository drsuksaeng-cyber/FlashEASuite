//+------------------------------------------------------------------+
//| BOSDetector.mqh                                                  |
//| FlashEASuite V2 — SMC Sub-Module: Break of Structure             |
//| Save to: Include/Logic/Strategies/SMC/BOSDetector.mqh            |
//+------------------------------------------------------------------+
#ifndef BOS_DETECTOR_MQH
#define BOS_DETECTOR_MQH

//--- MQL5 enum ต้องเป็น non-negative เท่านั้น
enum ENUM_BOS_DIR
{
    BOS_DIR_NONE    = 0,
    BOS_DIR_BULLISH = 1,
    BOS_DIR_BEARISH = 2
};

struct SBOS
{
    datetime      time;
    ENUM_BOS_DIR  direction;
    double        break_level;
    int           bar_index;
};

//+------------------------------------------------------------------+
//| CBOSDetector — ใช้เป็น direct member (ไม่ใช้ pointer/new)        |
//+------------------------------------------------------------------+
class CBOSDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_swing_bars;

    SBOS            m_last_bos;
    bool            m_has_bos;
    double          m_last_sh;
    double          m_last_sl;

    int _FindPivotHigh(int from_bar, int to_bar, double &out_price)
    {
        double best = -DBL_MAX;
        int    idx  = -1;
        for(int i = to_bar; i >= from_bar; i--)
        {
            double h = iHigh(m_symbol, m_tf, i);
            bool ok  = true;
            for(int j = 1; j <= m_swing_bars && ok; j++)
            {
                if((i + j) < Bars(m_symbol, m_tf) && iHigh(m_symbol, m_tf, i + j) >= h) ok = false;
                if((i - j) >= 0                   && iHigh(m_symbol, m_tf, i - j) >= h) ok = false;
            }
            if(ok && h > best) { best = h; idx = i; }
        }
        out_price = (best > -DBL_MAX) ? best : 0;
        return idx;
    }

    int _FindPivotLow(int from_bar, int to_bar, double &out_price)
    {
        double best = DBL_MAX;
        int    idx  = -1;
        for(int i = to_bar; i >= from_bar; i--)
        {
            double l = iLow(m_symbol, m_tf, i);
            bool ok  = true;
            for(int j = 1; j <= m_swing_bars && ok; j++)
            {
                if((i + j) < Bars(m_symbol, m_tf) && iLow(m_symbol, m_tf, i + j) <= l) ok = false;
                if((i - j) >= 0                   && iLow(m_symbol, m_tf, i - j) <= l) ok = false;
            }
            if(ok && l < best) { best = l; idx = i; }
        }
        out_price = (best < DBL_MAX) ? best : 0;
        return idx;
    }

public:
    CBOSDetector()
    {
        m_symbol     = "";
        m_tf         = PERIOD_H1;
        m_swing_bars = 5;
        m_has_bos    = false;
        m_last_sh    = 0;
        m_last_sl    = 0;
        m_last_bos.direction   = BOS_DIR_NONE;
        m_last_bos.break_level = 0;
        m_last_bos.bar_index   = 0;
        m_last_bos.time        = 0;
    }

    void Setup(string symbol, ENUM_TIMEFRAMES tf, int swing_bars = 5)
    {
        m_symbol     = symbol;
        m_tf         = tf;
        m_swing_bars = swing_bars;
        m_has_bos    = false;
        m_last_sh    = 0;
        m_last_sl    = 0;
    }

    void Detect(int lookback = 50)
    {
        m_has_bos = false;
        int needed = lookback + m_swing_bars * 2 + 2;
        if(Bars(m_symbol, m_tf) < needed) return;

        double sh_price, sl_price;
        int sh_bar = _FindPivotHigh(m_swing_bars + 1, lookback, sh_price);
        int sl_bar = _FindPivotLow (m_swing_bars + 1, lookback, sl_price);
        if(sh_bar < 0 || sl_bar < 0) return;

        double cur_high = iHigh(m_symbol, m_tf, 1);
        double cur_low  = iLow (m_symbol, m_tf, 1);

        if(cur_high > sh_price && sh_price != m_last_sh)
        {
            m_last_bos.time        = iTime(m_symbol, m_tf, 1);
            m_last_bos.direction   = BOS_DIR_BULLISH;
            m_last_bos.break_level = sh_price;
            m_last_bos.bar_index   = 1;
            m_last_sh              = sh_price;
            m_has_bos              = true;
            return;
        }
        if(cur_low < sl_price && sl_price != m_last_sl)
        {
            m_last_bos.time        = iTime(m_symbol, m_tf, 1);
            m_last_bos.direction   = BOS_DIR_BEARISH;
            m_last_bos.break_level = sl_price;
            m_last_bos.bar_index   = 1;
            m_last_sl              = sl_price;
            m_has_bos              = true;
        }
    }

    bool         HasBOS()       const { return m_has_bos; }
    SBOS         GetLastBOS()   const { return m_last_bos; }
    ENUM_BOS_DIR GetDirection() const { return m_last_bos.direction; }
    double       GetSwingHigh() const { return m_last_sh; }
    double       GetSwingLow()  const { return m_last_sl; }
};

#endif // BOS_DETECTOR_MQH
