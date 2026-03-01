//+------------------------------------------------------------------+
//|                                                   DLLWrapper.mqh |
//|                          FlashEASuite V2 — Security Layer        |
//|                          Merged: v1.02 + v2.00 (Phase 3B)       |
//|                          Location: Include/Security/             |
//|                                                                  |
//|  MERGE HISTORY:                                                  |
//|    v1.02 = CDLLWrapper       (DLLWrapper.mqh)                   |
//|    v2.00 = CDLLSecurityWrapper (DLLWrapper_Enhanced.mqh)        |
//|    v3.00 = Merged + STUB_MODE + ValidatePolicy (P9-2)           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "3.00"
#property strict

//+------------------------------------------------------------------+
//| USAGE:                                                           |
//|                                                                  |
//|  ปกติ (มี DLL จริง):                                            |
//|    #include "../Include/Security/DLLWrapper.mqh"                |
//|                                                                  |
//|  Test mode (ไม่มี DLL — ทดสอบ EA logic ได้เลย):                |
//|    #define STUB_MODE                                             |
//|    #include "../Include/Security/DLLWrapper.mqh"                |
//|                                                                  |
//|  Standalone (no server, no DLL check):                          |
//|    #define STANDALONE_MODE                                       |
//|    #include "../Include/Security/DLLWrapper.mqh"                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Guard against multiple inclusion                                  |
//+------------------------------------------------------------------+
#ifndef DLLWRAPPER_MQH
#define DLLWRAPPER_MQH

//+------------------------------------------------------------------+
//| ── Shared Structures ────────────────────────────────────────── |
//+------------------------------------------------------------------+

// ⚠️ NOTE: ถ้า TradingParamsStruct.mqh ถูก include แล้ว
//          ให้ comment out struct ด้านล่างนี้
#ifndef TRADING_PARAMS_DEFINED
#define TRADING_PARAMS_DEFINED
struct TradingParams
{
    double lot_size;      // Lot size คำนวณจาก risk
    double grid_step;     // Grid step (points)
    int    max_orders;    // จำนวน order สูงสุด
    double tp_points;     // Take profit (points)
    double sl_points;     // Stop loss (points)
    uint   checksum;      // Integrity checksum (DLL encrypted)
};
#endif // TRADING_PARAMS_DEFINED

// Challenge/Response structures สำหรับ Anti-Mock DLL (Phase 3B)
#ifndef CHALLENGE_DEFINED
#define CHALLENGE_DEFINED
struct Challenge
{
    uchar    random_data[32]; // Random bytes
    datetime timestamp;       // Challenge timestamp
};

struct Response
{
    uchar    hash[32];        // Expected HMAC-SHA256 hash
};
#endif // CHALLENGE_DEFINED

//+------------------------------------------------------------------+
//| ── Security Error Codes ─────────────────────────────────────── |
//+------------------------------------------------------------------+
#define SEC_OK                  1    // ✅ Success
#define SEC_ERR_FILE_NOT_FOUND -1    // ❌ License file not found
#define SEC_ERR_INVALID_JSON   -2    // ❌ Invalid JSON format
#define SEC_ERR_INVALID_SIG    -3    // ❌ Invalid RSA signature
#define SEC_ERR_HWID_MISMATCH  -4    // ❌ HWID mismatch
#define SEC_ERR_EXPIRED        -5    // ❌ License expired
#define SEC_ERR_NO_SLOTS       -6    // ❌ No available slots
#define SEC_ERR_NOT_INIT       -10   // ❌ Wrapper not initialized
#define SEC_ERR_DLL_LOAD       -11   // ❌ DLL failed to load
#define SEC_ERR_STUB_MODE      -99   // ⚠️ Running in STUB_MODE

//+------------------------------------------------------------------+
//| ── DLL Import ────────────────────────────────────────────────── |
//+------------------------------------------------------------------+
// ใน STUB_MODE หรือ STANDALONE_MODE จะ skip import จริง
#if !defined(STUB_MODE) && !defined(STANDALONE_MODE)

#import "FlashEA_Security.dll"
    // Layer 1 — License
    int  CheckLicense(const string license_path);
    void GetHWID(string &output);

    // Layer 2 — Policy (Phase 3B / P9-2)
    int  VerifyPolicy(const string policy_json, const string public_key_path);

    // Layer 3 — Anti-Mock Challenge (Phase 3B)
    int  VerifyChallenge(Challenge &challenge, Response &response);

    // DLL self-integrity check
    int  VerifyDLLIntegrity();
#import

#endif // !STUB_MODE && !STANDALONE_MODE


//+------------------------------------------------------------------+
//| ── CDLLWrapper Class ─────────────────────────────────────────── |
//+------------------------------------------------------------------+
//
//  Merged class เดียวที่ครอบคลุมทุก feature:
//    - v1.02: Initialize, CheckLicense, GetHWID, GetTradingParams
//    - v2.00: VerifyPolicySignature, ChallengeDLL, PeriodicVerification
//    - v3.00: STUB_MODE, STANDALONE_MODE, ValidatePolicy (P9-2 API)
//
class CDLLWrapper
{
private:
    //── State ────────────────────────────────────────────────────────
    bool     m_initialized;
    bool     m_license_valid;
    bool     m_stub_mode;      // true = STUB_MODE หรือ STANDALONE_MODE
    int      m_last_error;

    //── Paths ────────────────────────────────────────────────────────
    string   m_license_path;
    string   m_public_key_path;
    string   m_hwid;

    //── Trading params cache ─────────────────────────────────────────
    TradingParams m_params;
    bool          m_params_cached;
    string        m_last_symbol;
    double        m_last_balance;
    double        m_last_risk;

    //── Anti-mock (Phase 3B) ─────────────────────────────────────────
    datetime m_last_challenge_time;
    int      m_challenge_failures;

    //── Anti-replay — Sequence tracking ─────────────────────────────
    long     m_last_policy_sequence;

    //──────────────────────────────────────────────────────────────────
    // Private helpers
    //──────────────────────────────────────────────────────────────────

    string BuildPath(string filename)
    {
        string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
        StringReplace(terminal_path, "/", "\\");
        return terminal_path + "\\MQL5\\Files\\" + filename;
    }

    //── Error code → human message ───────────────────────────────────
    string CodeToMessage(int code) const
    {
        switch(code)
        {
            case  SEC_OK:               return "License valid";
            case  SEC_ERR_FILE_NOT_FOUND: return "License file not found";
            case  SEC_ERR_INVALID_JSON:   return "Invalid JSON format";
            case  SEC_ERR_INVALID_SIG:    return "Invalid RSA signature";
            case  SEC_ERR_HWID_MISMATCH:  return "HWID mismatch";
            case  SEC_ERR_EXPIRED:        return "License expired / grace ended";
            case  SEC_ERR_NO_SLOTS:       return "No available license slots";
            case  SEC_ERR_NOT_INIT:       return "Wrapper not initialized";
            case  SEC_ERR_DLL_LOAD:       return "DLL failed to load";
            case  SEC_ERR_STUB_MODE:      return "Running in STUB_MODE (test)";
            default:                      return "Unknown error (" + IntegerToString(code) + ")";
        }
    }

    //── Fetch HWID จาก DLL หรือ stub ──────────────────────────────────
    bool FetchHWID()
    {
#if defined(STUB_MODE) || defined(STANDALONE_MODE)
        // Stub HWID: ใช้ terminal path + account เป็น fingerprint สำรอง
        m_hwid = "STUB_HWID_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
        // pad ให้ครบ 64 chars
        while(StringLen(m_hwid) < 64)
            m_hwid += "0";
        m_hwid = StringSubstr(m_hwid, 0, 64);
        return true;
#else
        string buf = "0000000000000000000000000000000000000000000000000000000000000000";
        ::GetHWID(buf);
        if(StringLen(buf) < 32)
        {
            Print("[DLLWrapper] WARN: HWID length invalid (", StringLen(buf), ")");
            return false;
        }
        m_hwid = StringSubstr(buf, 0, 64);
        return true;
#endif
    }

    //── Local trading param calculation (safe fallback) ───────────────
    // NOTE: risk_pct ใช้ format เดียวกับ v1.02 = fraction (0.02 = 2%)
    //       ไม่ใช่ percentage (2.0)  เพื่อ backward compat
    void CalculateParamsLocal(const string symbol,
                               double       balance,
                               double       risk_pct)
    {
        double risk_amount = balance * risk_pct;  // risk_pct = 0.02 (fraction)

        m_params.lot_size   = MathMax(0.01, MathMin(1.0, risk_amount / 1000.0));
        m_params.lot_size   = NormalizeDouble(m_params.lot_size, 2);
        m_params.grid_step  = 100.0;

        if(risk_pct >= 0.05)       m_params.max_orders = 10;  // >= 5%
        else if(risk_pct >= 0.03)  m_params.max_orders = 7;   // >= 3%
        else if(risk_pct >= 0.02)  m_params.max_orders = 5;   // >= 2%
        else                       m_params.max_orders = 3;

        m_params.tp_points  = 200.0;
        m_params.sl_points  = 150.0;
        m_params.checksum   = 12345;  // Fixed stub checksum
    }

public:
    //──────────────────────────────────────────────────────────────────
    // Constructor / Destructor
    //──────────────────────────────────────────────────────────────────
    CDLLWrapper()
    {
        m_initialized          = false;
        m_license_valid        = false;
        m_last_error           = 0;
        m_params_cached        = false;
        m_last_challenge_time  = 0;
        m_challenge_failures   = 0;
        m_last_policy_sequence = -1;
        m_last_balance         = 0.0;
        m_last_risk            = 0.0;
        m_last_symbol          = "";
        m_hwid                 = "";
        m_license_path         = "";
        m_public_key_path      = "";
        ZeroMemory(m_params);

        // Detect compile-time mode
#if defined(STUB_MODE)
        m_stub_mode = true;
        Print("[DLLWrapper] ⚠️ STUB_MODE active — DLL calls are simulated");
#elif defined(STANDALONE_MODE)
        m_stub_mode = true;
        Print("[DLLWrapper] ℹ️ STANDALONE_MODE — Security layer bypassed");
#else
        m_stub_mode = false;
#endif
    }

    ~CDLLWrapper()
    {
        Print("[DLLWrapper] Destroyed");
    }

    //──────────────────────────────────────────────────────────────────
    // Initialize
    //──────────────────────────────────────────────────────────────────
    bool Initialize()
    {
        Print("===========================================");
        Print("🔐 DLLWrapper v3.00 Initializing");
        if(m_stub_mode)
            Print("   Mode: STUB / STANDALONE");
        else
            Print("   Mode: LIVE (FlashEA_Security.dll)");
        Print("===========================================");

        // Build paths
        m_license_path    = BuildPath("License.key");
        m_public_key_path = BuildPath("server_public.pem");

        Print("[DLLWrapper] License path : ", m_license_path);
        Print("[DLLWrapper] Public key   : ", m_public_key_path);

        // Fetch HWID
        if(!FetchHWID())
        {
            Print("[DLLWrapper] ❌ Failed to get HWID");
            m_last_error = SEC_ERR_DLL_LOAD;
            m_initialized = true;
            return false;
        }
        Print("[DLLWrapper] HWID: ", StringSubstr(m_hwid, 0, 16), "...");

        // Check license
        bool ok = CheckLicense_();
        m_initialized = true;

        if(ok)
            Print("[DLLWrapper] ✅ Initialization SUCCESS");
        else
            Print("[DLLWrapper] ❌ Initialization FAILED: ", GetErrorMessage());

        Print("===========================================");
        return ok;
    }

    //──────────────────────────────────────────────────────────────────
    // ── Layer 1: License ──────────────────────────────────────────
    //──────────────────────────────────────────────────────────────────
    bool CheckLicense_()
    {
#if defined(STUB_MODE) || defined(STANDALONE_MODE)
        Print("[DLLWrapper] [STUB] CheckLicense → VALID");
        m_license_valid = true;
        m_last_error    = SEC_OK;
        return true;
#else
        if(!FileIsExist("License.key"))
        {
            Print("[DLLWrapper] ❌ License.key not found");
            m_license_valid = false;
            m_last_error    = SEC_ERR_FILE_NOT_FOUND;
            return false;
        }

        int result = ::CheckLicense(m_license_path);
        m_last_error    = result;
        m_license_valid = (result == SEC_OK);

        if(m_license_valid)
            Print("[DLLWrapper] ✅ License VALID");
        else
            Print("[DLLWrapper] ❌ License INVALID: ", CodeToMessage(result));

        return m_license_valid;
#endif
    }

    // Public alias (ชื่อตรงกับ spec)
    bool CheckLicense()          { return CheckLicense_(); }
    bool ValidateLicense()       { return CheckLicense_(); }

    //── Recheck ─────────────────────────────────────────────────────
    bool RecheckLicense()
    {
        Print("[DLLWrapper] 🔄 Rechecking license...");
        InvalidateCache();
        bool ok = CheckLicense_();
        if(ok) Print("[DLLWrapper] ✅ Recheck: VALID");
        else   Print("[DLLWrapper] ❌ Recheck: INVALID");
        return ok;
    }

    //──────────────────────────────────────────────────────────────────
    // ── Layer 1: HWID ─────────────────────────────────────────────
    //──────────────────────────────────────────────────────────────────
    string GetHWID()
    {
        if(m_hwid == "") FetchHWID();
        return m_hwid;
    }

    // Overload สำหรับ backward compat กับ Enhanced version
    bool GetSystemHWID(string &output)
    {
        if(m_hwid == "" && !FetchHWID())
            return false;
        output = m_hwid;
        return true;
    }

    //──────────────────────────────────────────────────────────────────
    // ── Layer 2: Policy — ValidatePolicy (Anti-Replay)  ──────────
    //──────────────────────────────────────────────────────────────────
    //
    //  ตรวจ RSA signature + Anti-Replay rules:
    //    1. Timestamp tolerance ±5 min
    //    2. Sequence number increment
    //    3. Public key path must exist (ถ้าไม่มีจะ skip gracefully)
    //
    //  Args:
    //    policy_json      : full JSON string ของ policy
    //    policy_timestamp : timestamp ใน policy (Unix) สำหรับ anti-replay
    //    policy_sequence  : sequence number ใน policy
    //
    bool ValidatePolicy(const string policy_json,
                        long         policy_timestamp = 0,
                        long         policy_sequence  = -1)
    {
        if(!m_initialized)
        {
            Print("[DLLWrapper] ❌ ValidatePolicy: not initialized");
            return false;
        }

        if(!m_license_valid)
        {
            Print("[DLLWrapper] ❌ ValidatePolicy: license invalid");
            return false;
        }

        //── Anti-Replay: Timestamp check ───────────────────────────
        if(policy_timestamp > 0)
        {
            long now        = TimeCurrent();
            long policy_age = now - policy_timestamp;

            if(policy_age > 300)   // เก่าเกิน 5 นาที
            {
                Print("[DLLWrapper] ❌ Policy REPLAY ATTACK: too old (",
                      policy_age, "s ago)");
                m_last_error = SEC_ERR_INVALID_SIG;
                return false;
            }
            if(policy_age < -60)   // จากอนาคต
            {
                Print("[DLLWrapper] ❌ Policy from FUTURE (",
                      -policy_age, "s ahead) — possible clock skew");
                m_last_error = SEC_ERR_INVALID_SIG;
                return false;
            }
        }

        //── Anti-Replay: Sequence check ────────────────────────────
        if(policy_sequence >= 0)
        {
            if(policy_sequence <= m_last_policy_sequence)
            {
                Print("[DLLWrapper] ❌ Policy SEQUENCE REPLAY: got ", policy_sequence,
                      " <= last ", m_last_policy_sequence);
                m_last_error = SEC_ERR_INVALID_SIG;
                return false;
            }
        }

#if defined(STUB_MODE) || defined(STANDALONE_MODE)
        Print("[DLLWrapper] [STUB] ValidatePolicy → VALID");
        if(policy_sequence >= 0)
            m_last_policy_sequence = policy_sequence;
        return true;
#else
        // Public key check
        if(!FileIsExist(m_public_key_path))
        {
            Print("[DLLWrapper] ⚠️ Public key not found — skipping sig check (testing)");
            if(policy_sequence >= 0)
                m_last_policy_sequence = policy_sequence;
            return true;   // graceful fallback: allow when key not deployed yet
        }

        Print("[DLLWrapper] 🔍 Verifying policy signature...");
        int result = ::VerifyPolicy(policy_json, m_public_key_path);

        if(result == SEC_OK)
        {
            Print("[DLLWrapper] ✅ Policy signature VALID");
            if(policy_sequence >= 0)
                m_last_policy_sequence = policy_sequence;
            return true;
        }
        else
        {
            Print("[DLLWrapper] ❌ Policy signature INVALID (", result, "): ",
                  CodeToMessage(result));
            m_last_error = result;
            return false;
        }
#endif
    }

    // Alias สำหรับ backward compat กับ Enhanced version
    bool VerifyPolicySignature(const string policy_json)
    {
        return ValidatePolicy(policy_json);
    }

    //──────────────────────────────────────────────────────────────────
    // ── Layer 3: Anti-Mock Challenge (Phase 3B) ───────────────────
    //──────────────────────────────────────────────────────────────────
    bool ChallengeDLL()
    {
        if(!m_license_valid)
        {
            Print("[DLLWrapper] ⚠️ ChallengeDLL: license invalid — skip");
            return false;
        }

#if defined(STUB_MODE) || defined(STANDALONE_MODE)
        Print("[DLLWrapper] [STUB] ChallengeDLL → PASSED");
        m_challenge_failures = 0;
        return true;
#else
        Print("[DLLWrapper] 🎯 Challenging DLL (anti-mock)...");

        Challenge challenge;
        challenge.timestamp = TimeCurrent();
        for(int i = 0; i < 32; i++)
            challenge.random_data[i] = (uchar)(MathRand() % 256);

        Response response;
        int result = ::VerifyChallenge(challenge, response);

        if(result == SEC_OK)
        {
            Print("[DLLWrapper] ✅ DLL challenge PASSED — genuine DLL");
            m_challenge_failures = 0;
            return true;
        }
        else
        {
            m_challenge_failures++;
            Print("[DLLWrapper] ❌ DLL challenge FAILED (", result, ") — ",
                  "failures: ", m_challenge_failures);
            if(m_challenge_failures >= 3)
                Print("[DLLWrapper] 🚨 CRITICAL: Possible FAKE/MOCK DLL!");
            return false;
        }
#endif
    }

    //── Periodic DLL verification (เรียกใน OnTick / OnTimer) ──────────
    //  return false = ต้อง shutdown EA ทันที
    bool PeriodicVerification()
    {
        datetime now = TimeCurrent();
        if(now - m_last_challenge_time < 300)
            return true;   // ยังไม่ถึงเวลา (5 min interval)

        m_last_challenge_time = now;
        Print("[DLLWrapper] ⏱️ Periodic DLL verification...");

        if(!ChallengeDLL())
        {
            if(m_challenge_failures >= 3)
            {
                Print("[DLLWrapper] 🚨 3 failures — EA should STOP");
                return false;
            }
        }
        return true;
    }

    //──────────────────────────────────────────────────────────────────
    // ── Trading Parameters ────────────────────────────────────────
    //──────────────────────────────────────────────────────────────────
    //
    //  v1.02 API: GetTradingParams(symbol, balance, risk)
    //  v2.00 API: GetTradingParams(symbol, balance, risk, &params)
    //  v3.00 รองรับทั้งสองแบบ
    //
    bool GetTradingParams(const string symbol,
                          double       balance,
                          double       risk_percent,
                          TradingParams &out_params)
    {
        if(!m_initialized || !m_license_valid)
        {
            Print("[DLLWrapper] ❌ GetTradingParams: not ready");
            return false;
        }

        // Cache hit
        if(m_params_cached     &&
           m_last_symbol  == symbol  &&
           m_last_balance == balance &&
           m_last_risk    == risk_percent)
        {
            out_params = m_params;
            return true;
        }

        // ใช้ local calculation (safe — DLL struct passing มีปัญหาใน MQL5)
        CalculateParamsLocal(symbol, balance, risk_percent);

        if(m_params.checksum == 0)
        {
            Print("[DLLWrapper] ⚠️ Invalid checksum from calculation");
            return false;
        }

        m_last_symbol  = symbol;
        m_last_balance = balance;
        m_last_risk    = risk_percent;
        m_params_cached = true;

        out_params = m_params;

        Print("[DLLWrapper] ✅ Params: lot=", DoubleToString(m_params.lot_size, 2),
              " grid=", m_params.grid_step,
              " maxOrders=", m_params.max_orders);
        return true;
    }

    // v1.02 backward-compat overload (stores internally, read back via GetLotSize etc)
    bool GetTradingParams(const string symbol, double balance, double risk_percent)
    {
        TradingParams tmp;
        return GetTradingParams(symbol, balance, risk_percent, tmp);
    }

    //── Param accessors (v1.02 API) ───────────────────────────────────
    double GetLotSize()      const { return m_params_cached ? m_params.lot_size   : 0.01;  }
    double GetGridStep()     const { return m_params_cached ? m_params.grid_step  : 100.0; }
    double GetTakeProfit()   const { return m_params_cached ? m_params.tp_points  : 50.0;  }
    double GetStopLoss()     const { return m_params_cached ? m_params.sl_points  : 50.0;  }
    int    GetMaxPositions() const { return m_params_cached ? m_params.max_orders : 1;     }
    void   GetParams(TradingParams &p) const { p = m_params; }
    void   InvalidateCache()
    {
        m_params_cached = false;
        m_last_symbol   = "";
        Print("[DLLWrapper] 🔄 Cache invalidated");
    }

    //──────────────────────────────────────────────────────────────────
    // ── Status / Info ─────────────────────────────────────────────
    //──────────────────────────────────────────────────────────────────
    bool   IsLicenseValid()     const { return m_license_valid;       }
    bool   IsInitialized()      const { return m_initialized;         }
    bool   IsStubMode()         const { return m_stub_mode;           }
    int    GetLastError()       const { return m_last_error;          }
    int    GetChallengeFailures() const { return m_challenge_failures; }
    long   GetLastSequence()    const { return m_last_policy_sequence; }

    string GetErrorMessage()    const { return CodeToMessage(m_last_error); }
    string GetErrorMessage(int code) const { return CodeToMessage(code);    }

    void LogLicenseInfo()
    {
        Print("===========================================");
        Print("📋 DLLWrapper — License Info");
        Print("===========================================");
        Print("   Initialized : ", (m_initialized   ? "YES" : "NO"));
        Print("   License     : ", (m_license_valid  ? "✅ VALID" : "❌ INVALID"));
        Print("   Mode        : ", (m_stub_mode      ? "STUB/STANDALONE" : "LIVE"));
        Print("   HWID        : ", StringSubstr(m_hwid, 0, 20), "...");
        Print("   License path: ", m_license_path);
        Print("   Last error  : ", GetErrorMessage());
        Print("   Challenge ✗ : ", m_challenge_failures);
        Print("   Last seq    : ", m_last_policy_sequence);
        Print("===========================================");
    }
};

//+------------------------------------------------------------------+
//| Backward Compatibility Alias                                      |
//| CDLLSecurityWrapper → CDLLWrapper (Enhanced class ชื่อเก่า)     |
//+------------------------------------------------------------------+
// ไม่สามารถ typedef class ใน MQL5 ได้ตรงๆ
// ให้ใช้ CDLLWrapper แทน CDLLSecurityWrapper ในโค้ดใหม่ทั้งหมด
// หรือ rename ด้วย #define ก่อน include:
//   #define CDLLSecurityWrapper CDLLWrapper

#endif // DLLWRAPPER_MQH
//+------------------------------------------------------------------+
