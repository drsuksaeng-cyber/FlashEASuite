//+------------------------------------------------------------------+
//| ZoneDetector.mqh                                                 |
//| FlashEASuite V2 — S05 Sub-Module: Supply & Demand Zone Detection |
//| Save to: Include/Logic/Strategies/SupplyDemand/ZoneDetector.mqh  |
//+------------------------------------------------------------------+
#ifndef ZONE_DETECTOR_MQH
#define ZONE_DETECTOR_MQH

#define MAX_SD_ZONES 16

//--- MQL5 enum values ต้องเป็น non-negative
enum ENUM_ZONE_TYPE
{
    ZONE_DEMAND = 0,   // DBR — demand zone
    ZONE_SUPPLY = 1    // RBD — supply zone
};

struct SSDZone
{
    datetime        time;
    double          top;
    double          bottom;
    ENUM_ZONE_TYPE  zone_type;
    int             touches;
    int             bar_index;
    datetime        created_time;
    double          strength;
    bool            is_active;
    double          departure_atr;
};

//+------------------------------------------------------------------+
//| CZoneDetector — direct member, ไม่ใช้ pointer                    |
//+------------------------------------------------------------------+
class CZoneDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_lookback;
    int             m_max_touches;
    double          m_base_range_mult;
    double          m_departure_mult;

    SSDZone m_zones[MAX_SD_ZONES];
    int     m_count;

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

    bool _IsBase(int bar, double atr)
    {
        double range = iHigh(m_symbol, m_tf, bar) - iLow(m_symbol, m_tf, bar);
        return (range <= m_base_range_mult * atr);
    }

    bool _IsDeparture(int older_bar, int newer_bar, double atr, bool want_bull)
    {
        if(older_bar >= Bars(m_symbol, m_tf) || newer_bar < 0) return false;
        double open  = iOpen (m_symbol, m_tf, older_bar);
        double close = iClose(m_symbol, m_tf, newer_bar);
        double move  = close - open;
        if(want_bull) return (move  >  m_departure_mult * atr);
        else          return (move  < -m_departure_mult * atr);
    }

    double _CalcStrength(const SSDZone &z, double atr)
    {
        if(atr <= 0) return 0;
        double width       = z.top - z.bottom;
        double width_ratio = MathMin(1.0, width / (atr * 2.0));
        double freshness   = MathMax(0.0, 1.0 - z.touches * 0.25);
        int    age         = (int)((TimeCurrent() - z.created_time) /
                                    PeriodSeconds(m_tf));
        double time_decay  = MathMax(0.2, 1.0 - age * 0.002);
        return MathMin(1.0, width_ratio * freshness * time_decay);
    }

public:
    CZoneDetector()
    {
        m_symbol          = "";
        m_tf              = PERIOD_H1;
        m_lookback        = 100;
        m_max_touches     = 3;
        m_base_range_mult = 0.6;
        m_departure_mult  = 1.2;
        m_count           = 0;
    }

    void Setup(string symbol, ENUM_TIMEFRAMES tf,
               int lookback = 100, int max_touches = 3,
               double base_range_mult = 0.6, double departure_mult = 1.2)
    {
        m_symbol          = symbol;
        m_tf              = tf;
        m_lookback        = lookback;
        m_max_touches     = max_touches;
        m_base_range_mult = base_range_mult;
        m_departure_mult  = departure_mult;
        m_count           = 0;
    }

    void Scan()
    {
        m_count = 0;
        int bars = Bars(m_symbol, m_tf);
        if(bars < m_lookback + 6) return;

        double atr = _ATR(14);
        if(atr <= 0) return;

        for(int i = m_lookback - 6; i >= 4; i--)
        {
            if(m_count >= MAX_SD_ZONES) break;

            // DBR pattern (Drop → Base → Rally = Demand Zone)
            if(_IsDeparture(i + 3, i + 1, atr, false) &&
               _IsBase(i, atr) &&
               _IsDeparture(i - 1, i - 3, atr, true))
            {
                SSDZone z;
                z.zone_type    = ZONE_DEMAND;
                z.time         = iTime(m_symbol, m_tf, i);
                z.created_time = z.time;
                z.bottom       = iLow (m_symbol, m_tf, i);
                z.top          = iHigh(m_symbol, m_tf, i);
                if(i + 1 < bars)
                {
                    z.bottom = MathMin(z.bottom, iLow (m_symbol, m_tf, i + 1));
                    z.top    = MathMax(z.top,    iHigh(m_symbol, m_tf, i + 1));
                }
                z.touches        = 0;
                z.bar_index      = i;
                z.is_active      = true;
                z.departure_atr  = atr;
                z.strength       = _CalcStrength(z, atr);
                m_zones[m_count] = z;
                m_count++;
                continue;
            }

            // RBD pattern (Rally → Base → Drop = Supply Zone)
            if(_IsDeparture(i + 3, i + 1, atr, true) &&
               _IsBase(i, atr) &&
               _IsDeparture(i - 1, i - 3, atr, false))
            {
                SSDZone z;
                z.zone_type    = ZONE_SUPPLY;
                z.time         = iTime(m_symbol, m_tf, i);
                z.created_time = z.time;
                z.bottom       = iLow (m_symbol, m_tf, i);
                z.top          = iHigh(m_symbol, m_tf, i);
                if(i + 1 < bars)
                {
                    z.bottom = MathMin(z.bottom, iLow (m_symbol, m_tf, i + 1));
                    z.top    = MathMax(z.top,    iHigh(m_symbol, m_tf, i + 1));
                }
                z.touches        = 0;
                z.bar_index      = i;
                z.is_active      = true;
                z.departure_atr  = atr;
                z.strength       = _CalcStrength(z, atr);
                m_zones[m_count] = z;
                m_count++;
            }
        }
    }

    void UpdateTouches(double price, double atr)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(!m_zones[i].is_active) continue;
            if(price >= m_zones[i].bottom && price <= m_zones[i].top)
            {
                m_zones[i].touches++;
                m_zones[i].strength = _CalcStrength(m_zones[i], atr);
                if(m_zones[i].touches >= m_max_touches)
                    m_zones[i].is_active = false;
            }
            // Invalidate ถ้า price ทะลุผ่านโซน
            if(m_zones[i].zone_type == ZONE_DEMAND && price < m_zones[i].bottom - atr)
                m_zones[i].is_active = false;
            if(m_zones[i].zone_type == ZONE_SUPPLY && price > m_zones[i].top + atr)
                m_zones[i].is_active = false;
        }
    }

    bool GetNearestFreshZone(ENUM_ZONE_TYPE zone_type, double price, SSDZone &out)
    {
        double best  = -1;
        bool   found = false;
        for(int i = 0; i < m_count; i++)
        {
            if(!m_zones[i].is_active) continue;
            if(m_zones[i].zone_type != zone_type) continue;
            double mid = (m_zones[i].top + m_zones[i].bottom) * 0.5;
            if(zone_type == ZONE_DEMAND && mid > price) continue;
            if(zone_type == ZONE_SUPPLY && mid < price) continue;
            if(m_zones[i].strength > best)
            {
                best  = m_zones[i].strength;
                out   = m_zones[i];
                found = true;
            }
        }
        return found;
    }

    int     Count()          const { return m_count; }
    SSDZone GetZone(int idx) const { return m_zones[idx]; }
};

#endif // ZONE_DETECTOR_MQH
