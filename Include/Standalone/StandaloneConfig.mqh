//+------------------------------------------------------------------+
//| StandaloneConfig.mqh                                             |
//| FlashEASuite V2 — Standalone Config File Read/Write             |
//+------------------------------------------------------------------+
//| Format: INI text (human-readable, easy to debug)                 |
//| File: MQL5/Files/standalone_selector.dat                         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#ifndef STANDALONE_CONFIG_MQH
#define STANDALONE_CONFIG_MQH

#include "../Network/Protocol/Definitions.mqh"

//+------------------------------------------------------------------+
//| SStandaloneConfig: Persistent tunable parameters                 |
//| Saved/loaded between EA restarts                                 |
//+------------------------------------------------------------------+
struct SStandaloneConfig
{
    // Regime detection thresholds
    double              adx_trend_enter;   // ADX to enter TRENDING (default 27.0)
    double              adx_trend_exit;    // ADX to exit  TRENDING (default 23.0)
    double              adx_volatile;      // ADX for VOLATILE       (default 35.0)
    double              squeeze_mult;      // BB_Width squeeze mult  (default 0.60)

    // Execution
    double              confidence_min;    // Min confidence to act  (default 0.50)
    double              risk_multiplier;   // Risk scaling           (default 0.50)
    string              mm_method;         // MM method ID           (default "MM01")

    // State persistence
    ENUM_MARKET_REGIME  last_regime;       // Last known regime
    datetime            last_saved;        // Timestamp of last save

    void SetDefaults()
    {
        adx_trend_enter = 27.0;
        adx_trend_exit  = 23.0;
        adx_volatile    = 35.0;
        squeeze_mult    = 0.60;
        confidence_min  = 0.50;
        risk_multiplier = 0.50;
        mm_method       = "MM01";
        last_regime     = REGIME_UNKNOWN;
        last_saved      = 0;
    }
};

//+------------------------------------------------------------------+
//| CStandaloneConfig: File I/O manager for SStandaloneConfig        |
//+------------------------------------------------------------------+
class CStandaloneConfig
{
private:
public:
    //+------------------------------------------------------------------+
    //| SetDefaults: Fill struct with safe defaults                      |
    //+------------------------------------------------------------------+
    void SetDefaults(SStandaloneConfig &cfg)
    {
        cfg.SetDefaults();
    }

    //+------------------------------------------------------------------+
    //| Save: Write config to INI text file                              |
    //| @param filename  File name in MQL5/Files/                        |
    //| @param cfg       Config struct to save                           |
    //| @return true on success                                          |
    //+------------------------------------------------------------------+
    bool Save(string filename, const SStandaloneConfig &cfg)
    {
        int fh = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[StandaloneConfig] ❌ Cannot open for write: '%s' err=%d",
                        filename, GetLastError());
            return false;
        }

        // Write header
        FileWriteString(fh, "FLASHEA_V6_STANDALONE_CFG_V1\n");
        FileWriteString(fh, StringFormat("saved=%s\n", TimeToString((datetime)cfg.last_saved, TIME_DATE | TIME_SECONDS)));
        FileWriteString(fh, "\n");

        // Regime detection
        FileWriteString(fh, "[regime_detector]\n");
        FileWriteString(fh, StringFormat("adx_trend_enter=%.4f\n", cfg.adx_trend_enter));
        FileWriteString(fh, StringFormat("adx_trend_exit=%.4f\n",  cfg.adx_trend_exit));
        FileWriteString(fh, StringFormat("adx_volatile=%.4f\n",    cfg.adx_volatile));
        FileWriteString(fh, StringFormat("squeeze_mult=%.4f\n",    cfg.squeeze_mult));
        FileWriteString(fh, "\n");

        // Execution
        FileWriteString(fh, "[execution]\n");
        FileWriteString(fh, StringFormat("confidence_min=%.4f\n",  cfg.confidence_min));
        FileWriteString(fh, StringFormat("risk_multiplier=%.4f\n", cfg.risk_multiplier));
        FileWriteString(fh, StringFormat("mm_method=%s\n",          cfg.mm_method));
        FileWriteString(fh, "\n");

        // State
        FileWriteString(fh, "[state]\n");
        FileWriteString(fh, StringFormat("last_regime=%s\n", RegimeToString(cfg.last_regime)));

        FileClose(fh);
        PrintFormat("[StandaloneConfig] Saved: '%s' | regime=%s | risk=%.2f | conf_min=%.2f",
                    filename, RegimeToString(cfg.last_regime),
                    cfg.risk_multiplier, cfg.confidence_min);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Load: Read config from INI text file                             |
    //| @param filename  File name in MQL5/Files/                        |
    //| @param cfg       Config struct to fill (set to defaults first)   |
    //| @return true if file found and valid header                      |
    //+------------------------------------------------------------------+
    bool Load(string filename, SStandaloneConfig &cfg)
    {
        cfg.SetDefaults();  // seed defaults before overwriting

        if(!FileIsExist(filename))
        {
            PrintFormat("[StandaloneConfig] File not found: '%s' — using defaults", filename);
            return false;
        }

        int fh = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[StandaloneConfig] ❌ Cannot open for read: '%s' err=%d",
                        filename, GetLastError());
            return false;
        }

        // Check header
        string header = "";
        if(!FileIsEnding(fh))
        {
            header = FileReadString(fh);
            StringTrimLeft(header);
            StringTrimRight(header);
        }

        if(header != "FLASHEA_V6_STANDALONE_CFG_V1")
        {
            FileClose(fh);
            PrintFormat("[StandaloneConfig] ❌ Invalid header in '%s': '%s'", filename, header);
            return false;
        }

        // Parse line by line
        while(!FileIsEnding(fh))
        {
            string line = FileReadString(fh);
            StringTrimLeft(line);
            StringTrimRight(line);

            // Skip blank lines and section headers
            if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '[') continue;

            // Find '='
            int eq_pos = StringFind(line, "=");
            if(eq_pos <= 0) continue;

            string key = StringSubstr(line, 0, eq_pos);
            string val = StringSubstr(line, eq_pos + 1);

            _ParseKeyValue(key, val, cfg);
        }

        FileClose(fh);
        PrintFormat("[StandaloneConfig] Loaded: '%s' | regime=%s | risk=%.2f | conf_min=%.2f",
                    filename, RegimeToString(cfg.last_regime),
                    cfg.risk_multiplier, cfg.confidence_min);
        return true;
    }

private:
    //+------------------------------------------------------------------+
    //| _ParseKeyValue: Map key → struct field                           |
    //+------------------------------------------------------------------+
    void _ParseKeyValue(string key, string val, SStandaloneConfig &cfg)
    {
        double dval = StringToDouble(val);

        if(key == "adx_trend_enter")  { if(dval > 10.0 && dval < 60.0) cfg.adx_trend_enter = dval; }
        else if(key == "adx_trend_exit") { if(dval > 10.0 && dval < 60.0) cfg.adx_trend_exit = dval; }
        else if(key == "adx_volatile")   { if(dval > 20.0 && dval < 80.0) cfg.adx_volatile   = dval; }
        else if(key == "squeeze_mult")   { if(dval > 0.1  && dval < 1.5)  cfg.squeeze_mult   = dval; }
        else if(key == "confidence_min") { if(dval > 0.0  && dval < 1.0)  cfg.confidence_min = dval; }
        else if(key == "risk_multiplier"){ if(dval > 0.0  && dval <= 3.0) cfg.risk_multiplier= dval; }
        else if(key == "mm_method")      { if(StringLen(val) >= 4)         cfg.mm_method      = val;  }
        else if(key == "last_regime")
        {
            // Convert string back to enum
            if(val == "TRENDING")       cfg.last_regime = REGIME_TRENDING;
            else if(val == "RANGING")   cfg.last_regime = REGIME_RANGING;
            else if(val == "VOLATILE")  cfg.last_regime = REGIME_VOLATILE;
            else if(val == "SQUEEZE")   cfg.last_regime = REGIME_SQUEEZE;
            else                        cfg.last_regime = REGIME_UNKNOWN;
        }
    }
};

#endif // STANDALONE_CONFIG_MQH
//+------------------------------------------------------------------+
