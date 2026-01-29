//+------------------------------------------------------------------+
//|                                              TestLogger.mqh      |
//|                            FlashEASuite V2 Integration Testing   |
//|                                      Dr. Suksaeng Kukanok        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/drsuksaeng-cyber/FlashEASuite"
#property version   "1.00"
#property strict

class CTestLogger
{
private:
   string   m_log_file;
   int      m_log_handle;
   int      m_test_count;
   int      m_pass_count;
   int      m_fail_count;
   datetime m_test_start;
   int      m_policy_count;
   
public:
   CTestLogger()
   {
      m_test_count = 0;
      m_pass_count = 0;
      m_fail_count = 0;
      m_policy_count = 0;
      m_test_start = TimeCurrent();
      m_log_handle = INVALID_HANDLE;
   }
   
   ~CTestLogger()
   {
      CloseFiles();
   }
   
   bool Initialize(string test_name = "integration_test")
   {
      datetime now = TimeCurrent();
      string timestamp = TimeToString(now, TIME_DATE | TIME_MINUTES);
      StringReplace(timestamp, ":", "");
      StringReplace(timestamp, ".", "");
      StringReplace(timestamp, " ", "_");
      
      m_log_file = StringFormat("%s_%s.log", test_name, timestamp);
      m_log_handle = FileOpen(m_log_file, FILE_WRITE | FILE_TXT | FILE_ANSI);
      
      if(m_log_handle == INVALID_HANDLE)
      {
         Print("Failed to create log file: ", m_log_file);
         return false;
      }
      
      FileWrite(m_log_handle, "=========================================");
      FileWrite(m_log_handle, "FlashEASuite V2 - Integration Test Log");
      FileWrite(m_log_handle, "=========================================");
      FileWrite(m_log_handle, "Test Name: " + test_name);
      FileWrite(m_log_handle, "Start Time: " + TimeToString(m_test_start, TIME_DATE | TIME_SECONDS));
      FileWrite(m_log_handle, "Symbol: " + _Symbol);
      FileWrite(m_log_handle, "=========================================");
      FileWrite(m_log_handle, "");
      FileFlush(m_log_handle);
      
      Print("Test logger initialized");
      Print("Log file: ", m_log_file);
      
      return true;
   }
   
   void Log(string message, bool also_print = true)
   {
      if(m_log_handle == INVALID_HANDLE) return;
      
      string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      string full_msg = StringFormat("[%s] %s", timestamp, message);
      
      FileWrite(m_log_handle, full_msg);
      FileFlush(m_log_handle);
      
      if(also_print)
         Print(full_msg);
   }
   
   void StartTest(string test_name)
   {
      m_test_count++;
      Log("========================================");
      Log("TEST #" + IntegerToString(m_test_count) + ": " + test_name);
      Log("========================================");
   }
   
   void EndTest(bool passed, string details = "")
   {
      if(passed)
      {
         m_pass_count++;
         Log("TEST PASSED" + (details != "" ? ": " + details : ""));
      }
      else
      {
         m_fail_count++;
         Log("TEST FAILED" + (details != "" ? ": " + details : ""));
      }
      Log("");
   }
   
   void LogPolicyReceived(string symbol, long timestamp_ms)
   {
      m_policy_count++;
      string msg = StringFormat("Policy #%d received: %s", m_policy_count, symbol);
      Log(msg);
   }
   
   void CloseFiles()
   {
      if(m_log_handle != INVALID_HANDLE)
      {
         Log("========================================");
         Log("TEST STATISTICS");
         Log("========================================");
         Log(StringFormat("Total Tests:  %d", m_test_count));
         Log(StringFormat("Passed:       %d", m_pass_count));
         Log(StringFormat("Failed:       %d", m_fail_count));
         Log(StringFormat("Policies:     %d", m_policy_count));
         Log("========================================");
         
         FileClose(m_log_handle);
         m_log_handle = INVALID_HANDLE;
      }
   }
};
