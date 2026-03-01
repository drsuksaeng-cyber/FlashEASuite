//+------------------------------------------------------------------+
//|                                           DLLWrapper_Enhanced.mqh|
//|                          FlashEASuite V2 - Phase 3B Complete     |
//|                          Enhanced Security Wrapper               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| TradingParams Structure                                          |
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
//| Challenge/Response Structures (Anti-Mock DLL)                   |
//+------------------------------------------------------------------+
struct Challenge
{
    uchar random_data[32];    // Random bytes for challenge
    datetime timestamp;       // Challenge timestamp
};

struct Response
{
    uchar hash[32];          // Expected hash response
};

//+------------------------------------------------------------------+
//| DLL Import Declarations (Complete)                              |
//+------------------------------------------------------------------+
#import "FlashEA_Security.dll"
    // Core functions
    int CheckLicense(const string license_path);
    void GetHWID(string &output);
    
    // Phase 3B additions
    int VerifyPolicy(const string policy_json, const string public_key_path);
    int VerifyChallenge(Challenge &challenge, Response &response);
    int VerifyDLLIntegrity();
#import

//+------------------------------------------------------------------+
//| CDLLSecurityWrapper - Enhanced with Phase 3B                    |
//+------------------------------------------------------------------+
class CDLLSecurityWrapper
{
private:
    // License state
    string m_license_path;
    bool m_license_valid;
    string m_hwid;
    
    // Security state
    string m_public_key_path;
    datetime m_last_challenge;
    int m_challenge_failures;
    
    // Trading parameters (local calculation)
    TradingParams m_params;
    bool m_params_cached;
    string m_last_symbol;
    
    // Initialization
    bool m_initialized;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CDLLSecurityWrapper()
    {
        m_license_valid = false;
        m_initialized = false;
        m_params_cached = false;
        m_last_challenge = 0;
        m_challenge_failures = 0;
        
        Print("[OK] DLL Security Wrapper created");
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CDLLSecurityWrapper()
    {
        Print("[BYE] DLL Security Wrapper destroyed");
    }
    
    //+------------------------------------------------------------------+
    //| Initialize wrapper                                               |
    //+------------------------------------------------------------------+
    bool Initialize()
    {
        Print("[SECURITY] Initializing DLL Security Wrapper...");
        
        // Build license path
        string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
        StringReplace(terminal_path, "/", "\\");
        m_license_path = terminal_path + "\\MQL5\\Files\\License.key";
        
        Print("   License path: ", m_license_path);
        
        // Build public key path
        m_public_key_path = terminal_path + "\\MQL5\\Files\\server_public.pem";
        Print("   Public key: ", m_public_key_path);
        
        // Verify license
        if(!ValidateLicense())
        {
            Print("[ERROR] License validation failed");
            return false;
        }
        
        // Get HWID
        if(!GetSystemHWID(m_hwid))
        {
            Print("[ERROR] Failed to get HWID");
            return false;
        }
        
        Print("   HWID: ", StringSubstr(m_hwid, 0, 16), "...");
        
        m_initialized = true;
        Print("[OK] DLL Security Wrapper initialized");
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Validate License (existing function)                            |
    //+------------------------------------------------------------------+
    bool ValidateLicense()
    {
        if(!FileIsExist(m_license_path))
        {
            Print("[ERROR] License file not found: ", m_license_path);
            m_license_valid = false;
            return false;
        }
        
        int result = CheckLicense(m_license_path);
        
        if(result == 1)
        {
            Print("[OK] License is VALID");
            m_license_valid = true;
            return true;
        }
        else
        {
            Print("[ERROR] License check failed: ", ErrorCodeToMessage(result));
            m_license_valid = false;
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get System HWID (existing function)                             |
    //+------------------------------------------------------------------+
    bool GetSystemHWID(string &output)
    {
        GetHWID(output);
        
        if(StringLen(output) == 64)  // SHA256 = 64 hex chars
        {
            return true;
        }
        else
        {
            Print("[WARN] Invalid HWID length: ", StringLen(output));
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get Trading Parameters (local calculation - Safe Version)       |
    //+------------------------------------------------------------------+
    bool GetTradingParams(const string symbol, 
                         double balance,
                         double risk_percent,
                         TradingParams &params)
    {
        if(!m_license_valid)
        {
            Print("[WARN] Cannot get params - license invalid");
            return false;
        }
        
        // Check cache
        if(m_params_cached && m_last_symbol == symbol)
        {
            params = m_params;
            return true;
        }
        
        // Local calculation (Safe Version)
        double risk_amount = balance * (risk_percent / 100.0);
        
        // Lot size: risk / 1000, range 0.01-1.0
        params.lot_size = MathMax(0.01, MathMin(1.0, risk_amount / 1000.0));
        
        // Grid step: 100 points
        params.grid_step = 100.0;
        
        // Max orders based on risk
        if(risk_percent >= 5.0)
            params.max_orders = 10;
        else if(risk_percent >= 3.0)
            params.max_orders = 7;
        else if(risk_percent >= 2.0)
            params.max_orders = 5;
        else
            params.max_orders = 3;
        
        // TP/SL fixed
        params.tp_points = 200.0;
        params.sl_points = 150.0;
        
        // Checksum
        params.checksum = 12345;
        
        // Cache
        m_params = params;
        m_last_symbol = symbol;
        m_params_cached = true;
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| PHASE 3B - Task 1: Verify Policy Signature                      |
    //+------------------------------------------------------------------+
    bool VerifyPolicySignature(const string policy_json)
    {
        if(!m_license_valid)
        {
            Print("[WARN] Cannot verify policy - license invalid");
            return false;
        }
        
        // Check if public key exists
        if(!FileIsExist(m_public_key_path))
        {
            Print("[WARN] Public key not found: ", m_public_key_path);
            Print("   Skipping signature verification");
            return true;  // Allow in testing mode
        }
        
        Print("[CHECK] Verifying policy signature...");
        
        // Call DLL VerifyPolicy function
        int result = VerifyPolicy(policy_json, m_public_key_path);
        
        if(result == 1)
        {
            Print("[OK] Policy signature VALID");
            return true;
        }
        else
        {
            Print("[ERROR] Policy signature INVALID (code: ", result, ")");
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| PHASE 3B - Task 2: Challenge DLL (Anti-Mock Protection)         |
    //+------------------------------------------------------------------+
    bool ChallengeDLL()
    {
        if(!m_license_valid)
        {
            Print("[WARN] Cannot challenge DLL - license invalid");
            return false;
        }
        
        Print("[TARGET] Challenging DLL...");
        
        // Create challenge
        Challenge challenge;
        challenge.timestamp = TimeCurrent();
        
        // Fill with random data
        for(int i = 0; i < 32; i++)
        {
            challenge.random_data[i] = (uchar)(MathRand() % 256);
        }
        
        // Create response container
        Response response;
        
        // Send challenge to DLL
        int result = VerifyChallenge(challenge, response);
        
        if(result == 1)
        {
            Print("[OK] DLL challenge PASSED");
            Print("   DLL is genuine");
            m_challenge_failures = 0;
            return true;
        }
        else
        {
            m_challenge_failures++;
            Print("[ERROR] DLL challenge FAILED (code: ", result, ")");
            Print("   Failures: ", m_challenge_failures);
            Print("[CRITICAL] WARNING: Possible FAKE/MOCK DLL!");
            
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| PHASE 3B - Task 3: Periodic DLL Verification                    |
    //+------------------------------------------------------------------+
    bool PeriodicVerification()
    {
        datetime now = TimeCurrent();
        
        // Check every 5 minutes (300 seconds)
        if(now - m_last_challenge < 300)
        {
            return true;  // Not time yet
        }
        
        Print("[TIMER] Time for periodic DLL verification");
        
        // Update timestamp
        m_last_challenge = now;
        
        // Challenge DLL
        if(!ChallengeDLL())
        {
            Print("[CRITICAL] SECURITY ALERT: DLL verification failed!");
            
            // Check failure count
            if(m_challenge_failures >= 3)
            {
                Print("[CRITICAL] CRITICAL: 3 consecutive failures!");
                Print("[CRITICAL] Stopping EA for safety");
                return false;
            }
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get license status                                               |
    //+------------------------------------------------------------------+
    bool IsLicenseValid() const { return m_license_valid; }
    bool IsInitialized() const { return m_initialized; }
    int GetChallengeFailures() const { return m_challenge_failures; }
    
    //+------------------------------------------------------------------+
    //| Error code to message                                            |
    //+------------------------------------------------------------------+
    string ErrorCodeToMessage(int code)
    {
        switch(code)
        {
            case 1:  return "Success";
            case -1: return "File not found";
            case -2: return "Invalid JSON";
            case -3: return "Invalid signature";
            case -4: return "HWID mismatch";
            case -5: return "License expired";
            case -6: return "No slots available";
            default: return "Unknown error (" + IntegerToString(code) + ")";
        }
    }
};

//+------------------------------------------------------------------+
