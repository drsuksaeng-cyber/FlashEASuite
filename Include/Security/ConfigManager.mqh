//+------------------------------------------------------------------+
//| ConfigManager.mqh                                                |
//| FlashEASuite V2 - Server Configuration Manager                  |
//| Location: Include/Security/ConfigManager.mqh                     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Server Configuration Structure                                    |
//+------------------------------------------------------------------+
struct ServerConfig
{
    // Top 5 Symbols (dynamic from Brain)
    string            symbols[5];
    
    // Symbol-specific parameters
    double            atr_spike_mult[5];
    double            roc_threshold[5];
    double            volume_spike_mult[5];
    double            density_threshold[5];
    double            spread_max_atr_pct[5];
    int               max_hold_seconds[5];
    
    // Global risk
    double            risk_per_trade_pct;
    int               max_concurrent_spike;
    
    // Metadata
    datetime          config_timestamp;
    int               config_version;
};

//+------------------------------------------------------------------+
//| Configuration Manager Class                                      |
//+------------------------------------------------------------------+
class CConfigManager
{
private:
    ServerConfig      m_config;
    string            m_config_file;
    bool              m_config_loaded;
    
public:
    //--- Constructor
    CConfigManager()
        : m_config_file("spike_config.dat")
        , m_config_loaded(false)
    {
        // Initialize with defaults
        InitDefaults();
    }
    
    //--- Initialize default config
    void InitDefaults()
    {
        // Default top 5
        m_config.symbols[0] = "GBPJPY";
        m_config.symbols[1] = "GBPAUD";
        m_config.symbols[2] = "AUDJPY";
        m_config.symbols[3] = "NZDJPY";
        m_config.symbols[4] = "XAUUSD";
        
        // Default parameters
        for(int i = 0; i < 5; i++)
        {
            m_config.atr_spike_mult[i] = 2.0;
            m_config.roc_threshold[i] = 0.5;
            m_config.volume_spike_mult[i] = 1.5;
            m_config.density_threshold[i] = 3.0;
            m_config.spread_max_atr_pct[i] = 0.20;
            m_config.max_hold_seconds[i] = 900;
        }
        
        m_config.risk_per_trade_pct = 0.015;
        m_config.max_concurrent_spike = 3;
        m_config.config_timestamp = TimeCurrent();
        m_config.config_version = 1;
        
        Print("✅ Default config initialized");
    }
    
    //--- Load from file
    bool LoadConfig()
    {
        // TODO: Load from file or GlobalVariables
        Print("ℹ️  Using default config (file loading not implemented)");
        return true;
    }
    
    //--- Save to file
    bool SaveConfig()
    {
        // TODO: Save to file
        return true;
    }
    
    //--- Get config
    ServerConfig GetConfig() const
    {
        return m_config;
    }
    
    //--- Check if symbol is in top 5
    bool IsTopSymbol(string symbol)
    {
        for(int i = 0; i < 5; i++)
        {
            if(m_config.symbols[i] == symbol)
                return true;
        }
        return false;
    }
    
    //--- Get symbol index
    int GetSymbolIndex(string symbol)
    {
        for(int i = 0; i < 5; i++)
        {
            if(m_config.symbols[i] == symbol)
                return i;
        }
        return -1;
    }
};
