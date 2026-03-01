//+------------------------------------------------------------------+
//| POCCalculator.mqh                                                |
//| FlashEASuite V2 — Market Profile Subfolder                       |
//| Compute POC, VAH, VAL from a built VolumeProfileBuilder         |
//+------------------------------------------------------------------+
//| Location: Include/Logic/Strategies/MarketProfile/                |
//| Definitions:                                                     |
//|   POC = Point of Control  (highest volume bin price)            |
//|   VAH = Value Area High   (upper boundary of 70% volume zone)  |
//|   VAL = Value Area Low    (lower boundary of 70% volume zone)  |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef POCCALCULATOR_MQH
#define POCCALCULATOR_MQH

#include "VolumeProfileBuilder.mqh"

//+------------------------------------------------------------------+
//| CPOCCalculator                                                   |
//| Given a built VolumeProfileBuilder, calculates:                 |
//|  - POC price (highest-volume price level)                        |
//|  - VAH / VAL (70% Value Area boundaries)                         |
//|  - Volume imbalance (buy vs sell proxy via uptick approx)       |
//| Pattern: direct member in parent class, Setup() before use      |
//+------------------------------------------------------------------+
class CPOCCalculator
{
private:
    double  m_poc_price;        // Point of Control price
    double  m_vah_price;        // Value Area High
    double  m_val_price;        // Value Area Low
    int     m_poc_bin;          // POC bin index
    double  m_value_area_pct;   // Value area threshold (default 0.70)
    bool    m_calculated;
    
    //--- Secondary volume nodes (next highest-volume bins)
    double  m_node_prices[5];   // Prices of top volume nodes
    double  m_node_volumes[5];  // Volumes of top nodes
    int     m_node_count;
    
public:
    CPOCCalculator()
    {
        m_poc_price      = 0.0;
        m_vah_price      = 0.0;
        m_val_price      = 0.0;
        m_poc_bin        = -1;
        m_value_area_pct = 0.70;
        m_calculated     = false;
        m_node_count     = 0;
        ArrayInitialize(m_node_prices,  0.0);
        ArrayInitialize(m_node_volumes, 0.0);
    }
    
    //--- Configure value area percentage (default 70%)
    void Setup(double value_area_pct = 0.70)
    {
        m_value_area_pct = (value_area_pct > 0.0 && value_area_pct < 1.0)
                           ? value_area_pct : 0.70;
        m_calculated = false;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate: Run POC + Value Area computation from profile        |
    //| @param vp  Built VolumeProfileBuilder (must call Build() first) |
    //| @return true if calculation successful                           |
    //+------------------------------------------------------------------+
    bool Calculate(CVolumeProfileBuilder &vp)
    {
        m_calculated = false;
        if(!vp.IsBuilt()) return false;
        
        int    bins   = vp.GetBinCount();
        long   total  = vp.GetTotalVolume();
        if(total <= 0 || bins < 2) return false;
        
        //--- Step 1: Find POC bin (highest volume)
        m_poc_bin = vp.GetMaxVolumeBin();
        if(m_poc_bin < 0) return false;
        m_poc_price = vp.GetBinPrice(m_poc_bin);
        
        //--- Step 2: Find secondary volume nodes (top 5)
        double temp_vol[VP_MAX_BINS];
        for(int i = 0; i < bins; i++) temp_vol[i] = vp.GetBinVolume(i);
        
        m_node_count = 0;
        for(int n = 0; n < 5 && n < bins; n++)
        {
            int    best_i = 0;
            double best_v = -1.0;
            for(int i = 0; i < bins; i++)
            {
                if(temp_vol[i] > best_v) { best_v = temp_vol[i]; best_i = i; }
            }
            if(best_v <= 0.0) break;
            m_node_prices [m_node_count] = vp.GetBinPrice(best_i);
            m_node_volumes[m_node_count] = best_v;
            m_node_count++;
            temp_vol[best_i] = -1.0;  // exclude for next iteration
        }
        
        //--- Step 3: Build Value Area
        //--- Start from POC, expand up and down greedily
        //--- Add whichever adjacent bin has more volume each step
        double target_vol = (double)total * m_value_area_pct;
        double accum      = vp.GetBinVolume(m_poc_bin);
        
        int lo = m_poc_bin;
        int hi = m_poc_bin;
        
        while(accum < target_vol && (lo > 0 || hi < bins - 1))
        {
            double vol_up   = (hi < bins - 1) ? vp.GetBinVolume(hi + 1) : 0.0;
            double vol_down = (lo > 0)        ? vp.GetBinVolume(lo - 1) : 0.0;
            
            if(vol_up >= vol_down && hi < bins - 1)
            {
                hi++;
                accum += vol_up;
            }
            else if(vol_down > 0.0 && lo > 0)
            {
                lo--;
                accum += vol_down;
            }
            else if(hi < bins - 1)
            {
                hi++;
                accum += vol_up;
            }
            else
                break;
        }
        
        m_val_price = vp.GetBinPrice(lo) - vp.GetBinSize() * 0.5;
        m_vah_price = vp.GetBinPrice(hi) + vp.GetBinSize() * 0.5;
        
        m_calculated = true;
        return true;
    }
    
    //--- Getters
    bool   IsCalculated()   const { return m_calculated; }
    double GetPOC()         const { return m_poc_price; }
    double GetVAH()         const { return m_vah_price; }
    double GetVAL()         const { return m_val_price; }
    int    GetPOCBin()      const { return m_poc_bin; }
    
    //--- Get nearest volume node above/below current price (for TP)
    double GetNearestNodeAbove(double price) const
    {
        double best = 0.0;
        double dist = 1e20;
        for(int n = 0; n < m_node_count; n++)
        {
            if(m_node_prices[n] > price)
            {
                double d = m_node_prices[n] - price;
                if(d < dist) { dist = d; best = m_node_prices[n]; }
            }
        }
        return best;
    }
    
    double GetNearestNodeBelow(double price) const
    {
        double best = 0.0;
        double dist = 1e20;
        for(int n = 0; n < m_node_count; n++)
        {
            if(m_node_prices[n] < price)
            {
                double d = price - m_node_prices[n];
                if(d < dist) { dist = d; best = m_node_prices[n]; }
            }
        }
        return best;
    }
    
    //--- Proximity of price to POC (0.0 = far, 1.0 = at POC)
    double GetPOCProximity(double price, double atr) const
    {
        if(!m_calculated || atr <= 0.0) return 0.0;
        double dist = MathAbs(price - m_poc_price);
        double prox = 1.0 - MathMin(dist / (2.0 * atr), 1.0);
        return MathMax(0.0, prox);
    }
    
    void PrintInfo()
    {
        if(!m_calculated) { Print("[POC] Not calculated"); return; }
        PrintFormat("[POC] POC=%.5f  VAH=%.5f  VAL=%.5f  VA_bin:[%d]  Nodes=%d",
                    m_poc_price, m_vah_price, m_val_price, m_poc_bin, m_node_count);
    }
};

#endif // POCCALCULATOR_MQH
//+------------------------------------------------------------------+
