//+------------------------------------------------------------------+
//|                                                PolicyManager.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                                Phase 2: Security Integration     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

// Include PolicyVerifier (Phase 2)
#include "../Network/PolicyVerifier.mqh"

// Policy Structure (Extended for Phase 2)
struct Policy
  {
   // Original fields
   string            mode;
   double            risk_scale;
   datetime          timestamp;
   bool              is_active;
   
   // Phase 2: Security fields
   string            symbol;
   int               action;
   long              sequence;
   string            nonce;
   string            license_id;
   string            signature;
  };

class CPolicyManager
  {
private:
   Policy            m_current_policy;
   datetime          m_last_update_time;
   int               m_timeout_seconds;
   
   // Phase 2: Security verifier
   CPolicyVerifier   m_verifier;
   bool              m_verifier_initialized;

public:
   CPolicyManager()
     {
      m_timeout_seconds = 300;
      m_last_update_time = 0;
      m_verifier_initialized = false;
      
      m_current_policy.mode = "STANDALONE";
      m_current_policy.risk_scale = 0.5;
      m_current_policy.is_active = false;
      m_current_policy.symbol = "";
      m_current_policy.action = 0;
      m_current_policy.sequence = 0;
      m_current_policy.nonce = "";
      m_current_policy.license_id = "";
      m_current_policy.signature = "";
     }
   
   //+------------------------------------------------------------------+
   //| Initialize PolicyManager with security verification              |
   //+------------------------------------------------------------------+
   bool Initialize()
     {
      // Initialize PolicyVerifier with public key
      string public_key_path = "server_public.pem";  // In MQL5/Files/
      
      if(!m_verifier.Initialize(public_key_path))
        {
         Print("⚠️ WARNING: PolicyVerifier initialization failed");
         Print("   Policy verification will be DISABLED");
         m_verifier_initialized = false;
         return false;
        }
      
      m_verifier_initialized = true;
      Print("✅ PolicyManager initialized with security verification");
      return true;
     }

   //+------------------------------------------------------------------+
   //| Update Policy (Phase 2: With Security Verification)             |
   //| Input: MessagePack binary data containing JSON policy           |
   //+------------------------------------------------------------------+
   void UpdatePolicy(uchar &data[])
     {
      // TODO: Deserialize MessagePack to JSON string
      // For Phase 2 integration, this will be implemented with proper JSON parser
      
      // TEMPORARY: Parse basic fields
      // In real implementation, use JSON library to parse:
      // - symbol, action, sequence, nonce, timestamp, license_id, signature
      
      string policy_json = "{}";  // TODO: Deserialize from data[]
      
      // Example fields (to be extracted from JSON):
      string symbol = _Symbol;              // Current chart symbol
      long sequence = 12345;                 // From policy JSON
      string nonce = "uuid-here";            // From policy JSON
      datetime timestamp = TimeCurrent();    // From policy JSON
      string signature = "sig-here";         // From policy JSON
      
      // Phase 2: Verify policy before using
      if(m_verifier_initialized)
        {
         string error_msg;
         
         bool valid = m_verifier.VerifyPolicy(
            policy_json,     // Policy as JSON
            signature,       // Signature (base64)
            symbol,          // Symbol
            sequence,        // Sequence number
            nonce,           // Nonce (UUID)
            timestamp,       // Timestamp
            error_msg        // Output: error message
         );
         
         if(!valid)
           {
            Print("❌ Policy verification FAILED: ", error_msg);
            Print("   Policy REJECTED - Using standalone mode");
            return;  // Reject invalid policy
           }
         
         Print("✅ Policy verification PASSED");
        }
      else
        {
         Print("⚠️ WARNING: Policy verification DISABLED");
        }
      
      // Policy verified (or verification disabled) - Update state
      m_last_update_time = TimeCurrent();
      m_current_policy.is_active = true;
      m_current_policy.mode = "SNIPER";
      m_current_policy.risk_scale = 0.8;
      
      // Phase 2: Store security fields
      m_current_policy.symbol = symbol;
      m_current_policy.sequence = sequence;
      m_current_policy.nonce = nonce;
      m_current_policy.timestamp = timestamp;
      m_current_policy.signature = signature;
     }

   void CheckHeartbeat()
     {
      if(IsStandaloneMode())
        {
         // Connection lost
        }
     }

   bool IsStandaloneMode()
     {
      return (TimeCurrent() - m_last_update_time > m_timeout_seconds);
     }

   double GetAIRecommendedRisk()
     {
      if(IsStandaloneMode()) return 0.5;
      return m_current_policy.risk_scale;
     }
     
   string GetCurrentMode()
     {
      if(IsStandaloneMode()) return "STANDALONE";
      return m_current_policy.mode;
     }
   
   //+------------------------------------------------------------------+
   //| Get verification statistics (for monitoring)                     |
   //+------------------------------------------------------------------+
   void PrintVerificationStats()
     {
      if(m_verifier_initialized)
        {
         m_verifier.PrintStats();
        }
      else
        {
         Print("⚠️ Verification disabled - no stats available");
        }
     }
  };
//+------------------------------------------------------------------+
