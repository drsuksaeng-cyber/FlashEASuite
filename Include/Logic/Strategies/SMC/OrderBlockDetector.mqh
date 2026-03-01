//+------------------------------------------------------------------+
//| OrderBlockDetector.mqh                                           |
//| FlashEASuite V2 — SMC Sub-Module: Order Block Detection          |
//| Save to: Include/Logic/Strategies/SMC/OrderBlockDetector.mqh     |
//+------------------------------------------------------------------+
#ifndef ORDER_BLOCK_DETECTOR_MQH
#define ORDER_BLOCK_DETECTOR_MQH

#define MAX_OB_ZONES 10

struct SOrderBlock
{
    datetime time;
    double   high;
    double   low;
    bool     is_bullish;
    bool     is_active;
    double   strength;
    int      bar_index;
};

//+------------------------------------------------------------------+
//| COrderBlockDetector — direct member, ไม่ใช้ pointer              |
//+------------------------------------------------------------------+
class COrderBlockDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_lookback;
    double          m_min_vol_mult;
    double          m_min_reversal;

    SOrderBlock m_blocks[MAX_OB_ZONES];
    int         m_count;

    double _AvgVolume(int start_bar, int n)
    {
        long vol[];
        int got = (int)CopyTickVolume(m_symbol, m_tf, start_bar, n, vol);
        if(got <= 0) return 1.0;
        double sum = 0;
        for(int i = 0; i < got; i++) sum += (double)vol[i];
        return sum / got;
    }

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
    COrderBlockDetector()
    {
        m_symbol       = "";
        m_tf           = PERIOD_H1;
        m_lookback     = 50;
        m_min_vol_mult = 1.5;
        m_min_reversal = 0.5;
        m_count        = 0;
    }

    void Setup(string symbol, ENUM_TIMEFRAMES tf,
               int lookback = 50, double min_vol_mult = 1.5,
               double min_reversal = 0.5)
    {
        m_symbol       = symbol;
        m_tf           = tf;
        m_lookback     = lookback;
        m_min_vol_mult = min_vol_mult;
        m_min_reversal = min_reversal;
        m_count        = 0;
    }

    void Scan()
    {
        m_count = 0;
        int bars = Bars(m_symbol, m_tf);
        if(bars < m_lookback + 5) return;

        double atr     = _ATR(14);
        double avg_vol = _AvgVolume(2, MathMin(m_lookback, bars - 4));
        if(atr <= 0 || avg_vol <= 0) return;

        for(int i = m_lookback; i >= 4; i--)
        {
            if(m_count >= MAX_OB_ZONES) break;

            double open  = iOpen (m_symbol, m_tf, i);
            double close = iClose(m_symbol, m_tf, i);
            double high  = iHigh (m_symbol, m_tf, i);
            double low   = iLow  (m_symbol, m_tf, i);
            long   vol   = iVolume(m_symbol, m_tf, i);

            if((double)vol < m_min_vol_mult * avg_vol) continue;

            double next_close = iClose(m_symbol, m_tf, i - 3);
            double move_up    = next_close - high;
            double move_down  = low - next_close;
            bool   bear_candle = (close < open);
            bool   bull_candle = (close > open);

            if(bear_candle && move_up > m_min_reversal * atr)
            {
                SOrderBlock ob;
                ob.time       = iTime(m_symbol, m_tf, i);
                ob.high       = high;
                ob.low        = low;
                ob.is_bullish = true;
                ob.is_active  = true;
                ob.bar_index  = i;
                ob.strength   = MathMin(1.0, move_up / (atr * 3.0));
                m_blocks[m_count] = ob;
                m_count++;
            }
            else if(bull_candle && move_down > m_min_reversal * atr)
            {
                SOrderBlock ob;
                ob.time       = iTime(m_symbol, m_tf, i);
                ob.high       = high;
                ob.low        = low;
                ob.is_bullish = false;
                ob.is_active  = true;
                ob.bar_index  = i;
                ob.strength   = MathMin(1.0, move_down / (atr * 3.0));
                m_blocks[m_count] = ob;
                m_count++;
            }
        }
    }

    void MarkRetested(double price)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_blocks[i].is_active &&
               price >= m_blocks[i].low &&
               price <= m_blocks[i].high)
                m_blocks[i].is_active = false;
        }
    }

    bool GetNearestActive(bool want_bullish, double price, SOrderBlock &out)
    {
        double best = DBL_MAX;
        bool   found = false;
        for(int i = 0; i < m_count; i++)
        {
            if(!m_blocks[i].is_active) continue;
            if(m_blocks[i].is_bullish != want_bullish) continue;
            double dist;
            if(want_bullish)
            {
                if(m_blocks[i].high > price) continue;
                dist = price - m_blocks[i].high;
            }
            else
            {
                if(m_blocks[i].low < price) continue;
                dist = m_blocks[i].low - price;
            }
            if(dist < best) { best = dist; out = m_blocks[i]; found = true; }
        }
        return found;
    }

    int         Count()            const { return m_count; }
    SOrderBlock GetBlock(int idx)  const { return m_blocks[idx]; }
};

#endif // ORDER_BLOCK_DETECTOR_MQH
