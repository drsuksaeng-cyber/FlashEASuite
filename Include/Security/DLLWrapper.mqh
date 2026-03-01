//+------------------------------------------------------------------+
//|                                                   DLLWrapper.mqh |
//|                          FlashEASuite V2 — Security Layer v3.00  |
//|                          Merged: v1.02 + v2.00 + P9-2            |
//|                          Location: Include/Security/             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "3.00"
#property strict

/*
  ─── ใช้งาน ────────────────────────────────────────────────────────
  ปกติ (มี DLL จริง):
    #include "../Include/Security/DLLWrapper.mqh"

  Test / No DLL:
    #define STUB_MODE
    #include "../Include/Security/DLLWrapper.mqh"

  Standalone (ไม่ต้องการ security check):
    #define STANDALONE_MODE
    #include "../Include/Security/DLLWrapper.mqh"

  NOTE: STANDALONE_MODE จะ enable STUB_MODE โดยอัตโนมัติ
  ────────────────────────────────────────────────────────────────── */

#ifndef DLLWRAPPER_MQH
#define DLLWRAPPER_MQH

//+------------------------------------------------------------------+
//| Normalize: STANDALONE_MODE → STUB_MODE                           |
//+------------------------------------------------------------------+
#ifdef STANDALONE_MODE
   #ifndef STUB_MODE
      #define STUB_MODE
   #endif
#endif

//+------------------------------------------------------------------+
//| Shared Structures                                                 |
//+------------------------------------------------------------------+
#ifndef TRADING_PARAMS_DEFINED
#define TRADING_PARAMS_DEFINED
struct TradingParams
{
   double lot_size;
   double grid_step;
   int    max_orders;
   double tp_points;
   double sl_points;
   uint   checksum;
};
#endif

#ifndef CHALLENGE_DEFINED
#define CHALLENGE_DEFINED
struct Challenge
{
   uchar    random_data[32];
   datetime timestamp;
};
struct Response
{
   uchar hash[32];
};
#endif

//+------------------------------------------------------------------+
//| Error Codes                                                       |
//+------------------------------------------------------------------+
#define SEC_OK                   1
#define SEC_ERR_FILE_NOT_FOUND  -1
#define SEC_ERR_INVALID_JSON    -2
#define SEC_ERR_INVALID_SIG     -3
#define SEC_ERR_HWID_MISMATCH   -4
#define SEC_ERR_EXPIRED         -5
#define SEC_ERR_NO_SLOTS        -6
#define SEC_ERR_NOT_INIT        -10
#define SEC_ERR_DLL_LOAD        -11
#define SEC_ERR_STUB_MODE       -99

//+------------------------------------------------------------------+
//| DLL Import — ข้าม block ทั้งหมดถ้า STUB_MODE                    |
//+------------------------------------------------------------------+
#ifndef STUB_MODE
   #import "FlashEA_Security.dll"
      int  CheckLicense(const string license_path);
      void GetHWID(string &output);
      int  VerifyPolicy(const string policy_json, const string public_key_path);
      int  VerifyChallenge(Challenge &challenge, Response &response);
      int  VerifyDLLIntegrity();
   #import
#endif

//+------------------------------------------------------------------+
//| CDLLWrapper Class                                                 |
//+------------------------------------------------------------------+
class CDLLWrapper
{
private:
   bool     m_initialized;
   bool     m_license_valid;
   bool     m_stub_mode;
   int      m_last_error;

   string   m_license_path;
   string   m_public_key_path;
   string   m_hwid;

   TradingParams m_params;
   bool          m_params_cached;
   string        m_last_symbol;
   double        m_last_balance;
   double        m_last_risk;

   datetime m_last_challenge_time;
   int      m_challenge_failures;
   long     m_last_policy_sequence;

   //── private helpers ──────────────────────────────────────────────
   string BuildPath(string filename)
   {
      string p = TerminalInfoString(TERMINAL_DATA_PATH);
      StringReplace(p, "/", "\\");
      return p + "\\MQL5\\Files\\" + filename;
   }

   string CodeToMsg(int code) const
   {
      switch(code)
      {
         case  SEC_OK:                return "License valid";
         case  SEC_ERR_FILE_NOT_FOUND: return "License file not found";
         case  SEC_ERR_INVALID_JSON:   return "Invalid JSON format";
         case  SEC_ERR_INVALID_SIG:    return "Invalid RSA signature";
         case  SEC_ERR_HWID_MISMATCH:  return "HWID mismatch";
         case  SEC_ERR_EXPIRED:        return "License expired";
         case  SEC_ERR_NO_SLOTS:       return "No available slots";
         case  SEC_ERR_NOT_INIT:       return "Not initialized";
         case  SEC_ERR_DLL_LOAD:       return "DLL failed to load";
         case  SEC_ERR_STUB_MODE:      return "Stub mode";
         default: return "Unknown (" + IntegerToString(code) + ")";
      }
   }

   bool FetchHWID()
   {
#ifdef STUB_MODE
      m_hwid = "STUB_HWID_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
      while(StringLen(m_hwid) < 64) m_hwid += "0";
      m_hwid = StringSubstr(m_hwid, 0, 64);
      return true;
#else
      string buf = "0000000000000000000000000000000000000000000000000000000000000000";
      ::GetHWID(buf);
      if(StringLen(buf) < 32)
      {
         Print("[DLLWrapper] WARN: HWID length invalid");
         return false;
      }
      m_hwid = StringSubstr(buf, 0, 64);
      return true;
#endif
   }

   // risk_pct = fraction (0.02 = 2%) — ตาม v1.02 API
   void CalcParamsLocal(const string symbol, double balance, double risk_pct)
   {
      double amt = balance * risk_pct;
      m_params.lot_size  = NormalizeDouble(MathMax(0.01, MathMin(1.0, amt / 1000.0)), 2);
      m_params.grid_step = 100.0;
      if(risk_pct >= 0.05)       m_params.max_orders = 10;
      else if(risk_pct >= 0.03)  m_params.max_orders = 7;
      else if(risk_pct >= 0.02)  m_params.max_orders = 5;
      else                       m_params.max_orders = 3;
      m_params.tp_points  = 200.0;
      m_params.sl_points  = 150.0;
      m_params.checksum   = 12345;
   }

   bool DoCheckLicense()
   {
#ifdef STUB_MODE
      Print("[DLLWrapper] [STUB] CheckLicense → VALID");
      m_license_valid = true;
      m_last_error    = SEC_OK;
      return true;
#else
      if(!FileIsExist("License.key"))
      {
         Print("[DLLWrapper] License.key not found");
         m_license_valid = false;
         m_last_error    = SEC_ERR_FILE_NOT_FOUND;
         return false;
      }
      int r = ::CheckLicense(m_license_path);
      m_last_error    = r;
      m_license_valid = (r == SEC_OK);
      if(m_license_valid) Print("[DLLWrapper] License VALID");
      else                Print("[DLLWrapper] License INVALID: ", CodeToMsg(r));
      return m_license_valid;
#endif
   }

public:
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

#ifdef STUB_MODE
      m_stub_mode = true;
      Print("[DLLWrapper] STUB_MODE active");
#else
      m_stub_mode = false;
#endif
   }

   ~CDLLWrapper() { Print("[DLLWrapper] Destroyed"); }

   //── Initialize ───────────────────────────────────────────────────
   bool Initialize()
   {
      Print("============================================");
      Print("[DLLWrapper] v3.00 Initializing...");
#ifdef STUB_MODE
      Print("[DLLWrapper] Mode: STUB");
#else
      Print("[DLLWrapper] Mode: LIVE (FlashEA_Security.dll)");
#endif

      m_license_path    = BuildPath("License.key");
      m_public_key_path = BuildPath("server_public.pem");

      if(!FetchHWID())
      {
         Print("[DLLWrapper] ERROR: Cannot get HWID");
         m_last_error = SEC_ERR_DLL_LOAD;
         m_initialized = true;
         return false;
      }
      Print("[DLLWrapper] HWID: ", StringSubstr(m_hwid, 0, 16), "...");

      bool ok = DoCheckLicense();
      m_initialized = true;

      if(ok) Print("[DLLWrapper] Initialize OK");
      else   Print("[DLLWrapper] Initialize FAILED: ", GetErrorMessage());
      Print("============================================");
      return ok;
   }

   //── Layer 1: License ─────────────────────────────────────────────
   bool CheckLicense()     { return DoCheckLicense(); }
   bool ValidateLicense()  { return DoCheckLicense(); }
   bool RecheckLicense()
   {
      Print("[DLLWrapper] Rechecking license...");
      InvalidateCache();
      return DoCheckLicense();
   }

   //── Layer 1: HWID ────────────────────────────────────────────────
   string GetHWID()
   {
      if(m_hwid == "") FetchHWID();
      return m_hwid;
   }
   bool GetSystemHWID(string &out)
   {
      if(m_hwid == "" && !FetchHWID()) return false;
      out = m_hwid;
      return true;
   }

   //── Layer 2: Policy — ValidatePolicy (Anti-Replay) ───────────────
   //   policy_timestamp: Unix timestamp ใน policy  (0 = skip check)
   //   policy_sequence:  sequence number ใน policy (-1 = skip check)
   bool ValidatePolicy(const string policy_json,
                       long         policy_timestamp = 0,
                       long         policy_sequence  = -1)
   {
      if(!m_initialized || !m_license_valid)
      {
         Print("[DLLWrapper] ValidatePolicy: not ready");
         return false;
      }

      // Anti-Replay: Timestamp
      if(policy_timestamp > 0)
      {
         long age = TimeCurrent() - policy_timestamp;
         if(age > 300)
         {
            Print("[DLLWrapper] REJECT: policy too old (", age, "s)");
            m_last_error = SEC_ERR_INVALID_SIG;
            return false;
         }
         if(age < -60)
         {
            Print("[DLLWrapper] REJECT: policy from future");
            m_last_error = SEC_ERR_INVALID_SIG;
            return false;
         }
      }

      // Anti-Replay: Sequence
      if(policy_sequence >= 0)
      {
         if(policy_sequence <= m_last_policy_sequence)
         {
            Print("[DLLWrapper] REJECT: sequence replay (", policy_sequence,
                  " <= ", m_last_policy_sequence, ")");
            m_last_error = SEC_ERR_INVALID_SIG;
            return false;
         }
      }

#ifdef STUB_MODE
      Print("[DLLWrapper] [STUB] ValidatePolicy → VALID");
      if(policy_sequence >= 0) m_last_policy_sequence = policy_sequence;
      return true;
#else
      if(!FileIsExist(m_public_key_path))
      {
         Print("[DLLWrapper] WARN: Public key missing — skipping sig check");
         if(policy_sequence >= 0) m_last_policy_sequence = policy_sequence;
         return true;
      }
      int r = ::VerifyPolicy(policy_json, m_public_key_path);
      if(r == SEC_OK)
      {
         if(policy_sequence >= 0) m_last_policy_sequence = policy_sequence;
         return true;
      }
      m_last_error = r;
      Print("[DLLWrapper] Policy sig INVALID: ", CodeToMsg(r));
      return false;
#endif
   }

   // Alias backward compat
   bool VerifyPolicySignature(const string policy_json)
   { return ValidatePolicy(policy_json); }

   //── Layer 3: Anti-Mock Challenge ─────────────────────────────────
   bool ChallengeDLL()
   {
      if(!m_license_valid)
      {
         Print("[DLLWrapper] ChallengeDLL: license invalid — skip");
         return false;
      }
#ifdef STUB_MODE
      Print("[DLLWrapper] [STUB] ChallengeDLL → PASSED");
      m_challenge_failures = 0;
      return true;
#else
      Print("[DLLWrapper] Challenging DLL...");
      Challenge ch;
      ch.timestamp = TimeCurrent();
      for(int i = 0; i < 32; i++)
         ch.random_data[i] = (uchar)(MathRand() % 256);
      Response rsp;
      int r = ::VerifyChallenge(ch, rsp);
      if(r == SEC_OK) { m_challenge_failures = 0; return true; }
      m_challenge_failures++;
      Print("[DLLWrapper] Challenge FAILED (", r, ") failures=", m_challenge_failures);
      if(m_challenge_failures >= 3)
         Print("[DLLWrapper] CRITICAL: Possible FAKE DLL!");
      return false;
#endif
   }

   // เรียกใน OnTimer — return false = ให้ EA stop
   bool PeriodicVerification()
   {
      datetime now = TimeCurrent();
      if(now - m_last_challenge_time < 300) return true;
      m_last_challenge_time = now;
      Print("[DLLWrapper] Periodic DLL verification...");
      if(!ChallengeDLL() && m_challenge_failures >= 3)
      {
         Print("[DLLWrapper] CRITICAL: 3 failures — EA should STOP");
         return false;
      }
      return true;
   }

   //── Trading Parameters ───────────────────────────────────────────
   // v2 API (preferred)
   bool GetTradingParams(const string   symbol,
                         double         balance,
                         double         risk_pct,
                         TradingParams &out)
   {
      if(!m_initialized || !m_license_valid)
      { Print("[DLLWrapper] GetTradingParams: not ready"); return false; }

      if(m_params_cached && m_last_symbol == symbol &&
         m_last_balance == balance && m_last_risk == risk_pct)
      { out = m_params; return true; }

      CalcParamsLocal(symbol, balance, risk_pct);
      if(m_params.checksum == 0) { Print("[DLLWrapper] Checksum invalid"); return false; }

      m_last_symbol  = symbol;
      m_last_balance = balance;
      m_last_risk    = risk_pct;
      m_params_cached = true;
      out = m_params;
      return true;
   }

   // v1.02 API (backward compat — stores in internal cache)
   bool GetTradingParams(const string symbol, double balance, double risk_pct)
   {
      TradingParams tmp;
      return GetTradingParams(symbol, balance, risk_pct, tmp);
   }

   double GetLotSize()      const { return m_params_cached ? m_params.lot_size   : 0.01;  }
   double GetGridStep()     const { return m_params_cached ? m_params.grid_step  : 100.0; }
   double GetTakeProfit()   const { return m_params_cached ? m_params.tp_points  : 50.0;  }
   double GetStopLoss()     const { return m_params_cached ? m_params.sl_points  : 50.0;  }
   int    GetMaxPositions() const { return m_params_cached ? m_params.max_orders : 1;     }
   void   GetParams(TradingParams &p) const { p = m_params; }

   void InvalidateCache()
   {
      m_params_cached = false;
      m_last_symbol   = "";
      Print("[DLLWrapper] Cache invalidated");
   }

   //── Status ───────────────────────────────────────────────────────
   bool   IsLicenseValid()       const { return m_license_valid;        }
   bool   IsInitialized()        const { return m_initialized;          }
   bool   IsStubMode()           const { return m_stub_mode;            }
   int    GetLastError()         const { return m_last_error;           }
   int    GetChallengeFailures() const { return m_challenge_failures;   }
   long   GetLastSequence()      const { return m_last_policy_sequence; }
   string GetErrorMessage()      const { return CodeToMsg(m_last_error); }
   string GetErrorMessage(int c) const { return CodeToMsg(c);           }

   void LogLicenseInfo()
   {
      Print("============================================");
      Print("[DLLWrapper] License Info");
      Print("  Initialized : ", (m_initialized  ? "YES" : "NO"));
      Print("  License     : ", (m_license_valid ? "VALID" : "INVALID"));
      Print("  Mode        : ", (m_stub_mode     ? "STUB" : "LIVE"));
      Print("  HWID        : ", StringSubstr(m_hwid, 0, 20), "...");
      Print("  LastError   : ", GetErrorMessage());
      Print("  Failures    : ", m_challenge_failures);
      Print("  LastSeq     : ", m_last_policy_sequence);
      Print("============================================");
   }
};

#endif // DLLWRAPPER_MQH
//+------------------------------------------------------------------+
