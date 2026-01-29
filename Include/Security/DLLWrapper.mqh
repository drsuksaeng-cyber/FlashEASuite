//+------------------------------------------------------------------+
//|                                                   DLLWrapper.mqh |
//|                          FlashEASuite V2 - Phase 3B              |
//|                          MQL5 DLL Security Wrapper               |
//|                          Location: Include/Security/             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.02"
#property strict

//+------------------------------------------------------------------+
//| TradingParams Structure (must match DLL exactly)                 |
//+------------------------------------------------------------------+
struct TradingParams
{
    double lot_size;
    double grid_step;
    int max_orders;
    double tp_points;
    double sl_points;
    uint checksum;
};

//+------------------------------------------------------------------+
//| DLL Import Declarations                                          |
//+------------------------------------------------------------------+
#import "FlashEA_Security.dll"
    int CheckLicense(const string license_path);
    void GetHWID(string &output);
    // CalculateTradingParams disabled due to struct passing issue
    // Will use default calculation instead
#import

//+------------------------------------------------------------------+
//| CDLLWrapper Class                                                 |
//+------------------------------------------------------------------+
class CDLLWrapper
{
private:
    string m_license_path;
    bool m_license_valid;
    int m_last_error;
    string m_hwid;
    TradingParams m_params;
    string m_last_symbol;
    double m_last_balance;
    double m_last_risk;
    bool m_params_cached;
    bool m_initialized;
    
    string BuildLicensePath()
    {
        string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
        StringReplace(terminal_path, "/", "\\");
        return terminal_path + "\\MQL5\\Files\\License.key";
    }
    
    string ErrorCodeToMessage(int error_code) const
    {
        switch(error_code)
        {
            case 1:  return "License valid";
            case -1: return "License file not found";
            case -2: return "Invalid JSON format";
            case -3: return "Invalid RSA signature";
            case -4: return "HWID mismatch";
            case -5: return "License expired";
            case -6: return "No available slots";
            default: return "Unknown error (" + IntegerToString(error_code) + ")";
        }
    }
    
    void GetHWIDFromDLL()
    {
        string hwid_buffer = "0000000000000000000000000000000000000000000000000000000000000000";
        ::GetHWID(hwid_buffer);
        m_hwid = StringSubstr(hwid_buffer, 0, 64);
    }

public:
    CDLLWrapper()
    {
        m_license_path = "";
        m_license_valid = false;
        m_last_error = 0;
        m_hwid = "";
        m_initialized = false;
        m_params_cached = false;
        m_last_symbol = "";
        m_last_balance = 0.0;
        m_last_risk = 0.0;
        ZeroMemory(m_params);
    }
    
    ~CDLLWrapper() {}
    
    bool Initialize()
    {
        Print("======================================");
        Print("🔐 DLL Security Wrapper Initializing");
        Print("======================================");
        
        m_license_path = BuildLicensePath();
        Print("📂 License path: ", m_license_path);
        
        if(!FileIsExist("License.key"))
        {
            Print("❌ ERROR: License file not found");
            m_last_error = -1;
            m_license_valid = false;
            m_initialized = true;
            return false;
        }
        
        Print("✅ License file found");
        GetHWIDFromDLL();
        
        Print("🔍 Verifying license...");
        int result = CheckLicense(m_license_path);
        
        m_last_error = result;
        m_license_valid = (result == 1);
        m_initialized = true;
        
        if(m_license_valid)
        {
            Print("✅ SUCCESS: License is VALID");
            Print("   HWID: ", m_hwid);
        }
        else
        {
            Print("❌ FAILED: License verification failed");
            Print("   Error: ", GetErrorMessage(result));
            Print("   HWID: ", m_hwid);
        }
        
        Print("======================================");
        return m_license_valid;
    }
    
    bool IsLicenseValid() const { return m_license_valid; }
    int GetLastError() const { return m_last_error; }
    
    string GetErrorMessage(int error_code) const
    {
        return ErrorCodeToMessage(error_code);
    }
    
    string GetErrorMessage() const
    {
        return ErrorCodeToMessage(m_last_error);
    }
    
    string GetHWID()
    {
        if(m_hwid == "") GetHWIDFromDLL();
        return m_hwid;
    }
    
    bool GetTradingParams(string symbol, double balance, double risk_percent)
    {
        if(!m_initialized)
        {
            Print("❌ ERROR: Wrapper not initialized");
            return false;
        }
        
        if(!m_license_valid)
        {
            Print("❌ ERROR: License not valid");
            return false;
        }
        
        if(m_params_cached && 
           m_last_symbol == symbol && 
           m_last_balance == balance && 
           m_last_risk == risk_percent)
        {
            Print("📋 Using cached parameters for ", symbol);
            return true;
        }
        
        Print("🔢 Calculating trading parameters...");
        Print("   Symbol: ", symbol);
        Print("   Balance: ", DoubleToString(balance, 2));
        Print("   Risk: ", DoubleToString(risk_percent * 100, 2), "%");
        
        // Calculate parameters locally (DLL struct passing has issues)
        ZeroMemory(m_params);
        
        // Simple calculation based on balance and risk
        double risk_amount = balance * risk_percent;
        
        // Lot size: risk / (grid_step * point_value)
        // Simplified: risk_amount / 1000
        m_params.lot_size = MathMax(0.01, MathMin(1.0, risk_amount / 1000.0));
        m_params.lot_size = NormalizeDouble(m_params.lot_size, 2);
        
        // Grid step: 100 points for most symbols
        m_params.grid_step = 100.0;
        
        // Max orders based on risk
        if(risk_percent >= 0.05)
            m_params.max_orders = 10;
        else if(risk_percent >= 0.03)
            m_params.max_orders = 7;
        else if(risk_percent >= 0.02)
            m_params.max_orders = 5;
        else
            m_params.max_orders = 3;
        
        // TP/SL in points
        m_params.tp_points = 200.0;
        m_params.sl_points = 150.0;
        
        // Checksum (simple validation)
        m_params.checksum = 12345;
        
        Print("✅ Parameters calculated (local):");
        Print("   Note: Using local calculation (DLL disabled)");
        
        if(m_params.checksum == 0)
        {
            Print("⚠️ WARNING: Invalid checksum");
            return false;
        }
        
        m_last_symbol = symbol;
        m_last_balance = balance;
        m_last_risk = risk_percent;
        m_params_cached = true;
        
        Print("✅ Parameters calculated:");
        Print("   Lot Size: ", DoubleToString(m_params.lot_size, 2));
        Print("   Grid Step: ", DoubleToString(m_params.grid_step, 0), " points");
        Print("   Max Orders: ", IntegerToString(m_params.max_orders));
        Print("   TP: ", DoubleToString(m_params.tp_points, 0), " points");
        Print("   SL: ", DoubleToString(m_params.sl_points, 0), " points");
        
        return true;
    }
    
    double GetLotSize() const
    {
        if(!m_params_cached) return 0.01;
        return m_params.lot_size;
    }
    
    double GetGridStep() const
    {
        if(!m_params_cached) return 100.0;
        return m_params.grid_step;
    }
    
    double GetTakeProfit() const
    {
        if(!m_params_cached) return 50.0;
        return m_params.tp_points;
    }
    
    double GetStopLoss() const
    {
        if(!m_params_cached) return 50.0;
        return m_params.sl_points;
    }
    
    int GetMaxPositions() const
    {
        if(!m_params_cached) return 1;
        return m_params.max_orders;
    }
    
    void GetParams(TradingParams &params) const
    {
        params = m_params;
    }
    
    void InvalidateCache()
    {
        m_params_cached = false;
        Print("🔄 Parameter cache invalidated");
    }
    
    void LogLicenseInfo()
    {
        Print("======================================");
        Print("📋 LICENSE INFORMATION");
        Print("======================================");
        Print("Status: ", (m_license_valid ? "✅ VALID" : "❌ INVALID"));
        Print("Path: ", m_license_path);
        Print("HWID: ", m_hwid);
        Print("Last Error: ", GetErrorMessage(m_last_error));
        Print("======================================");
    }
    
    bool RecheckLicense()
    {
        Print("🔄 Rechecking license...");
        InvalidateCache();
        
        int result = CheckLicense(m_license_path);
        m_last_error = result;
        m_license_valid = (result == 1);
        
        if(m_license_valid)
            Print("✅ License revalidation: SUCCESS");
        else
            Print("❌ License revalidation: FAILED - ", GetErrorMessage(result));
        
        return m_license_valid;
    }
};
//+------------------------------------------------------------------+
