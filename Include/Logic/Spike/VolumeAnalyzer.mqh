//+------------------------------------------------------------------+
//| VolumeAnalyzer.mqh                                               |
//| FlashEASuite V2 - Volume Spike Detection                        |
//| Location: Include/Logic/Spike/VolumeAnalyzer.mqh               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Volume Analyzer Class                                            |
//| Detects volume spikes for Spike Strategy                        |
//+------------------------------------------------------------------+
class CVolumeAnalyzer
{
private:
    long              m_volume_history[100];    // Volume buffer
    int               m_index;                  // Current index
    int               m_period;                 // Averaging period
    double            m_spike_multiplier;       // Spike threshold
    
public:
    //--- Constructor
    CVolumeAnalyzer()
        : m_index(0)
        , m_period(20)
        , m_spike_multiplier(1.5)
    {
        ArrayInitialize(m_volume_history, 0);
    }
    
    //--- Destructor
    ~CVolumeAnalyzer() {}
    
    //--- Initialize
    bool Init(int period = 20, double spike_mult = 1.5)
    {
        m_period = period;
        m_spike_multiplier = spike_mult;
        
        Print("✅ VolumeAnalyzer initialized (period: ", m_period, 
              ", multiplier: ", DoubleToString(m_spike_multiplier, 1), "x)");
        
        return true;
    }
    
    //--- Update with new volume
    void UpdateVolume(long tick_volume)
    {
        m_volume_history[m_index] = tick_volume;
        m_index = (m_index + 1) % 100;
    }
    
    //--- Calculate average volume
    double CalculateAverageVolume(int period)
    {
        if(period > 100) period = 100;
        
        long sum = 0;
        int count = 0;
        
        for(int i = 0; i < period; i++)
        {
            int idx = (m_index - i - 1 + 100) % 100;
            sum += m_volume_history[idx];
            count++;
        }
        
        if(count == 0) return 0;
        
        return (double)sum / count;
    }
    
    //--- Check if current volume is a spike
    bool IsVolumeSpike(double multiplier = 0)
    {
        if(multiplier == 0) multiplier = m_spike_multiplier;
        
        // Get current volume (most recent)
        int current_idx = (m_index - 1 + 100) % 100;
        long current_volume = m_volume_history[current_idx];
        
        // Calculate average
        double avg_volume = CalculateAverageVolume(m_period);
        
        if(avg_volume == 0) return false;
        
        // Check spike
        bool is_spike = (current_volume >= avg_volume * multiplier);
        
        if(is_spike)
        {
            Print("📊 Volume Spike Detected! Current: ", current_volume, 
                  " vs Avg: ", DoubleToString(avg_volume, 0),
                  " (", DoubleToString(multiplier, 1), "x)");
        }
        
        return is_spike;
    }
    
    //--- Get volume ratio
    double GetVolumeRatio()
    {
        int current_idx = (m_index - 1 + 100) % 100;
        long current_volume = m_volume_history[current_idx];
        
        double avg_volume = CalculateAverageVolume(m_period);
        
        if(avg_volume == 0) return 1.0;
        
        return (double)current_volume / avg_volume;
    }
    
    //--- Get current volume
    long GetCurrentVolume()
    {
        int current_idx = (m_index - 1 + 100) % 100;
        return m_volume_history[current_idx];
    }
};

//+------------------------------------------------------------------+
