//+------------------------------------------------------------------+
//| FVGDetector.mqh                                                  |
//| FlashEASuite V2 — SMC Sub-Module: Fair Value Gap Detection       |
//| Save to: Include/Logic/Strategies/SMC/FVGDetector.mqh            |
//+------------------------------------------------------------------+
#ifndef FVG_DETECTOR_MQH
#define FVG_DETECTOR_MQH

#define MAX_FVG_ZONES 10

struct SFVG
{
    datetime time;
    double   top;
    double   bottom;
    bool     is_bullish;
    bool     is_active;
    double   size_ratio;
    int      bar_index;
};

//+------------------------------------------------------------------+
//| CFVGDetector — direct member, ไม่ใช้ pointer                     |
//+------------------------------------------------------------------+
class CFVGDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_lookback;
    double          m_min_size;

    SFVG m_fvgs[MAX_FVG_ZONES];
    int  m_count;

    double _ATR(int bars = 14)
    {
        double atr = 0;
        int    cnt = MathMin(bars, Bars(m_symbol, m_tf) - 2);
        if(cnt <= 0) return 1.0;
        for(int i = 1; i <= cnt; i++)
        {
            double hi = iHigh (m_symbol, m_tf, i);
            double lo = iLow  (m_symbol, m_tf, i);
            double pc = iClose(m_symbol, m_tf, i + 1);
            double tr = MathMax(hi - lo, MathMax(MathAbs(hi - pc), MathAbs(lo - pc)));
            atr += tr;
        }
        return atr / cnt;
    }

public:
    CFVGDetector()
    {
        m_symbol   = "";
        m_tf       = PERIOD_H1;
        m_lookback = 50;
        m_min_size = 0.5;
        m_count    = 0;
    }

    void Setup(string symbol, ENUM_TIMEFRAMES tf,
               int lookback = 50, double min_size = 0.5)
    {
        m_symbol   = symbol;
        m_tf       = tf;
        m_lookback = lookback;
        m_min_size = min_size;
        m_count    = 0;
    }

    void Scan()
    {
        m_count = 0;
        int bars = Bars(m_symbol, m_tf);
        if(bars < m_lookback + 2) return;

        double atr = _ATR(14);
        if(atr <= 0) return;

        for(int i = 2; i <= m_lookback - 1; i++)
        {
            if(m_count >= MAX_FVG_ZONES) break;

            double prev_high = iHigh(m_symbol, m_tf, i + 1);
            double prev_low  = iLow (m_symbol, m_tf, i + 1);
            double next_high = iHigh(m_symbol, m_tf, i - 1);
            double next_low  = iLow (m_symbol, m_tf, i - 1);

            double bull_gap = next_low - prev_high;
            if(bull_gap > m_min_size * atr)
            {
                SFVG fvg;
                fvg.time       = iTime(m_symbol, m_tf, i);
                fvg.top        = next_low;
                fvg.bottom     = prev_high;
                fvg.is_bullish = true;
                fvg.is_active  = true;
                fvg.size_ratio = bull_gap / atr;
                fvg.bar_index  = i;
                m_fvgs[m_count] = fvg;
                m_count++;
                continue;
            }

            double bear_gap = prev_low - next_high;
            if(bear_gap > m_min_size * atr)
            {
                SFVG fvg;
                fvg.time       = iTime(m_symbol, m_tf, i);
                fvg.top        = prev_low;
                fvg.bottom     = next_high;
                fvg.is_bullish = false;
                fvg.is_active  = true;
                fvg.size_ratio = bear_gap / atr;
                fvg.bar_index  = i;
                m_fvgs[m_count] = fvg;
                m_count++;
            }
        }
    }

    void MarkFilled(double price)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(!m_fvgs[i].is_active) continue;
            double mid = (m_fvgs[i].top + m_fvgs[i].bottom) * 0.5;
            if(m_fvgs[i].is_bullish  && price <= mid) m_fvgs[i].is_active = false;
            if(!m_fvgs[i].is_bullish && price >= mid) m_fvgs[i].is_active = false;
        }
    }

    bool GetNearestActive(bool want_bullish, double price, SFVG &out)
    {
        double best  = DBL_MAX;
        bool   found = false;
        for(int i = 0; i < m_count; i++)
        {
            if(!m_fvgs[i].is_active) continue;
            if(m_fvgs[i].is_bullish != want_bullish) continue;
            double mid  = (m_fvgs[i].top + m_fvgs[i].bottom) * 0.5;
            double dist;
            if(want_bullish)
            {
                if(mid > price) continue;
                dist = price - mid;
            }
            else
            {
                if(mid < price) continue;
                dist = mid - price;
            }
            if(dist < best) { best = dist; out = m_fvgs[i]; found = true; }
        }
        return found;
    }

    int  Count()          const { return m_count; }
    SFVG GetFVG(int idx)  const { return m_fvgs[idx]; }
};

#endif // FVG_DETECTOR_MQH
