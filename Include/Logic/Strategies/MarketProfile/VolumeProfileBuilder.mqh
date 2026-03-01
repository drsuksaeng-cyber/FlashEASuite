//+------------------------------------------------------------------+
//| VolumeProfileBuilder.mqh                                         |
//| FlashEASuite V2 — Market Profile Subfolder                       |
//| Builds tick-volume profile across N price bins from OHLCV bars  |
//| Method: distribute bar tick-volume across its High-Low range     |
//+------------------------------------------------------------------+
//| Location: Include/Logic/Strategies/MarketProfile/                |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef VOLUMEPROFILEBUILDER_MQH
#define VOLUMEPROFILEBUILDER_MQH

//--- Maximum bins supported
#define VP_MAX_BINS 100

//+------------------------------------------------------------------+
//| CVolumeProfileBuilder                                            |
//| Collects OHLCV bar data and distributes tick volume across       |
//| price bins to form a Volume Profile histogram.                   |
//| Pattern: direct member, use Setup() then Build()                 |
//+------------------------------------------------------------------+
class CVolumeProfileBuilder
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int             m_bins;          // Number of price bins (default 50)
    int             m_lookback;      // Number of bars to include
    
    double          m_bin_volume[VP_MAX_BINS];   // Volume at each bin
    double          m_price_low;     // Lowest price in profile range
    double          m_price_high;    // Highest price in profile range
    double          m_bin_size;      // Price width of each bin
    
    long            m_total_volume;  // Total tick volume across all bins
    bool            m_built;         // Has Build() been called successfully?
    
public:
    //--- Default constructor (no arguments — MQL5 pattern)
    CVolumeProfileBuilder()
    {
        m_symbol        = "";
        m_tf            = PERIOD_M15;
        m_bins          = 50;
        m_lookback      = 96;       // 96 × M15 = 24 hours
        m_price_low     = 0.0;
        m_price_high    = 0.0;
        m_bin_size      = 0.0;
        m_total_volume  = 0;
        m_built         = false;
        ArrayInitialize(m_bin_volume, 0.0);
    }
    
    //--- Setup: configure before calling Build()
    void Setup(string symbol, ENUM_TIMEFRAMES tf, int bins = 50, int lookback_bars = 96)
    {
        m_symbol   = symbol;
        m_tf       = tf;
        m_bins     = (bins > VP_MAX_BINS) ? VP_MAX_BINS : (bins < 2 ? 2 : bins);
        m_lookback = (lookback_bars < 1) ? 1 : lookback_bars;
        m_built    = false;
    }
    
    //+------------------------------------------------------------------+
    //| Build: Construct volume profile from last m_lookback bars        |
    //| Distributes each bar's tick volume proportionally across bins   |
    //| that overlap the bar's High-Low range.                          |
    //| @return true if profile built successfully                       |
    //+------------------------------------------------------------------+
    bool Build()
    {
        if(m_symbol == "") return false;
        
        int bars_available = Bars(m_symbol, m_tf);
        if(bars_available < 2) return false;
        
        int count = (m_lookback < bars_available) ? m_lookback : bars_available - 1;
        
        //--- Copy OHLCV arrays
        double arr_high[], arr_low[];
        long   arr_vol[];
        ArraySetAsSeries(arr_high, true);
        ArraySetAsSeries(arr_low,  true);
        ArraySetAsSeries(arr_vol,  true);
        
        if(CopyHigh(m_symbol, m_tf, 1, count, arr_high) <= 0) return false;
        if(CopyLow (m_symbol, m_tf, 1, count, arr_low)  <= 0) return false;
        if(CopyTickVolume(m_symbol, m_tf, 1, count, arr_vol) <= 0) return false;
        
        //--- Determine overall price range
        m_price_high = arr_high[ArrayMaximum(arr_high, 0, count)];
        m_price_low  = arr_low [ArrayMinimum(arr_low,  0, count)];
        
        double range = m_price_high - m_price_low;
        if(range <= 0.0) return false;
        
        m_bin_size = range / (double)m_bins;
        
        //--- Reset bins
        ArrayInitialize(m_bin_volume, 0.0);
        m_total_volume = 0;
        
        //--- Distribute volume across bins
        for(int b = 0; b < count; b++)
        {
            double bar_low  = arr_low[b];
            double bar_high = arr_high[b];
            double bar_vol  = (double)arr_vol[b];
            double bar_range = bar_high - bar_low;
            
            if(bar_vol <= 0 || bar_range <= 0.0) continue;
            
            //--- Find first and last bin this bar spans
            int bin_start = (int)((bar_low  - m_price_low) / m_bin_size);
            int bin_end   = (int)((bar_high - m_price_low) / m_bin_size);
            
            bin_start = MathMax(0, MathMin(bin_start, m_bins - 1));
            bin_end   = MathMax(0, MathMin(bin_end,   m_bins - 1));
            
            int span = bin_end - bin_start + 1;
            
            //--- Distribute proportionally
            for(int i = bin_start; i <= bin_end; i++)
            {
                //--- Price range of this bin
                double bin_lo = m_price_low + i * m_bin_size;
                double bin_hi = bin_lo + m_bin_size;
                
                //--- Overlap between bar range and bin range
                double overlap_lo = MathMax(bar_low,  bin_lo);
                double overlap_hi = MathMin(bar_high, bin_hi);
                double overlap    = MathMax(0.0, overlap_hi - overlap_lo);
                
                double fraction = (bar_range > 0.0) ? overlap / bar_range : 1.0 / span;
                m_bin_volume[i] += bar_vol * fraction;
            }
            
            m_total_volume += arr_vol[b];
        }
        
        m_built = true;
        return true;
    }
    
    //--- Getters
    bool    IsBuilt()      const { return m_built; }
    int     GetBinCount()  const { return m_bins; }
    double  GetPriceLow()  const { return m_price_low; }
    double  GetPriceHigh() const { return m_price_high; }
    double  GetBinSize()   const { return m_bin_size; }
    long    GetTotalVolume() const { return m_total_volume; }
    
    //--- Get volume at bin index (0 = lowest price)
    double GetBinVolume(int bin_index) const
    {
        if(!m_built || bin_index < 0 || bin_index >= m_bins) return 0.0;
        return m_bin_volume[bin_index];
    }
    
    //--- Get mid-price of a bin
    double GetBinPrice(int bin_index) const
    {
        if(!m_built || bin_index < 0 || bin_index >= m_bins) return 0.0;
        return m_price_low + (bin_index + 0.5) * m_bin_size;
    }
    
    //--- Find which bin a given price falls into
    int PriceToBin(double price) const
    {
        if(!m_built || m_bin_size <= 0.0) return -1;
        int bin = (int)((price - m_price_low) / m_bin_size);
        return MathMax(0, MathMin(bin, m_bins - 1));
    }
    
    //--- Find the bin with maximum volume (POC bin index)
    int GetMaxVolumeBin() const
    {
        if(!m_built) return -1;
        int    best_bin = 0;
        double best_vol = 0.0;
        for(int i = 0; i < m_bins; i++)
        {
            if(m_bin_volume[i] > best_vol)
            {
                best_vol = m_bin_volume[i];
                best_bin = i;
            }
        }
        return best_bin;
    }
    
    //--- Debug: print top-N bins by volume
    void PrintTopBins(int top_n = 5)
    {
        if(!m_built) { Print("[VP] Not built yet"); return; }
        Print("[VP] Volume Profile — Top ", top_n, " bins:");
        for(int n = 0; n < top_n; n++)
        {
            double best_vol = -1;
            int    best_bin = -1;
            for(int i = 0; i < m_bins; i++)
            {
                if(m_bin_volume[i] > best_vol)
                {
                    best_vol = m_bin_volume[i];
                    best_bin = i;
                }
            }
            if(best_bin < 0) break;
            PrintFormat("[VP]   #%d BIN=%d  Price=%.5f  Vol=%.0f",
                        n + 1, best_bin, GetBinPrice(best_bin), best_vol);
            m_bin_volume[best_bin] = -1.0;  // mark as used (temporary)
        }
        Build();  // rebuild to restore (side effect acceptable — only debug)
    }
};

#endif // VOLUMEPROFILEBUILDER_MQH
//+------------------------------------------------------------------+
