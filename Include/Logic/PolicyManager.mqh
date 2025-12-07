//+------------------------------------------------------------------+
//|                                                PolicyManager.mqh |
//|                                    FlashEASuite V2 - Program C   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

// Policy Structure
struct Policy
  {
   string            mode;
   double            risk_scale;
   datetime          timestamp;
   bool              is_active;
  };

class CPolicyManager
  {
private:
   Policy            m_current_policy;
   datetime          m_last_update_time;
   int               m_timeout_seconds;

public:
   CPolicyManager()
     {
      m_timeout_seconds = 300;
      m_last_update_time = 0;
      
      m_current_policy.mode = "STANDALONE";
      m_current_policy.risk_scale = 0.5;
      m_current_policy.is_active = false;
     }

   void UpdatePolicy(uchar &data[])
     {
      m_last_update_time = TimeCurrent();
      m_current_policy.is_active = true;
      m_current_policy.mode = "SNIPER";
      m_current_policy.risk_scale = 0.8;
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
  };
//+------------------------------------------------------------------+
