//+------------------------------------------------------------------+
//|                                   IntegrationTest_Trader.mq5     |
//|                            FlashEASuite V2 Integration Testing   |
//|                                      Dr. Suksaeng Kukanok        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://github.com/drsuksaeng-cyber/FlashEASuite"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES - Using relative paths from Tester/                    |
//+------------------------------------------------------------------+

// Test logger (in same Tester/ folder)
#include "TestLogger.mqh"

// ZMQ (from Include/Zmq/)
#include "../Include/Zmq/Zmq.mqh"

// Protocol (from Include/Network/Protocol/)
#include "../Include/Network/Protocol/Definitions.mqh"
#include "../Include/Network/Protocol/Serialization.mqh"

//--- Input Parameters
input string SYMBOL_PREFIX = "";          // Symbol Prefix (e.g., "f", "")
input string SYMBOL_SUFFIX = ".tp";       // Symbol Suffix (e.g., ".tp", "m")
input int    TEST_DURATION_SEC = 1800;    // Test Duration (seconds, 1800=30min)

//--- Global Variables
Context      g_Context;
Socket       *g_PolicySocket = NULL;  // SUB: Receive policies (pointer)
CTestLogger  g_Logger;                // Test logger

int          g_TestPhase = 0;         // Current test phase
datetime     g_TestStartTime;         // Test start time

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Integration Test - Starting...");
   Print("========================================");
   
   //--- Initialize logger
   if(!g_Logger.Initialize("integration_test"))
   {
      Print("Failed to initialize logger");
      return INIT_FAILED;
   }
   
   g_Logger.Log("EA Initialized on " + _Symbol);
   g_Logger.Log("Test Duration: " + IntegerToString(TEST_DURATION_SEC) + " seconds");
   
   //--- Test 1: ZMQ Initialization
   g_Logger.StartTest("ZMQ Initialization");
   
   if(!g_Context.initialize())
   {
      g_Logger.EndTest(false, "Failed to create ZMQ context");
      return INIT_FAILED;
   }
   
   // Create socket
   g_PolicySocket = new Socket(ZMQ_SUB);
   if(!g_PolicySocket.initialize(g_Context, ZMQ_SUB))
   {
      g_Logger.EndTest(false, "Failed to create policy socket");
      delete g_PolicySocket;
      return INIT_FAILED;
   }
   
   if(!g_PolicySocket.connect("tcp://127.0.0.1:7778"))
   {
      g_Logger.EndTest(false, "Failed to connect to port 7778");
      delete g_PolicySocket;
      return INIT_FAILED;
   }
   
   // Subscribe to all messages
   g_PolicySocket.setSubscribe("");
   g_Logger.EndTest(true, "Connected to tcp://127.0.0.1:7778");
   
   //--- Test 2: Symbol Formatting
   g_Logger.StartTest("Symbol Formatting");
   
   // ✅ FIXED: Just verify that _Symbol has the expected suffix
   // No need to format anything - Python sends symbols with suffix already
   bool has_suffix = StringFind(_Symbol, SYMBOL_SUFFIX) >= 0;
   
   g_Logger.Log("Current chart: " + _Symbol);
   g_Logger.Log("Expected suffix: " + SYMBOL_SUFFIX);
   g_Logger.Log("Suffix present: " + (has_suffix ? "YES" : "NO"));
   
   g_Logger.EndTest(has_suffix, 
                    has_suffix ? "Symbol has correct suffix" : "Symbol missing suffix!");
   
   //--- Start timer
   EventSetMillisecondTimer(100);  // Check every 100ms
   
   g_TestStartTime = TimeCurrent();
   g_TestPhase = 1;  // Start receiving policies
   
   g_Logger.Log("Initialization Complete");
   g_Logger.Log("Starting policy monitoring...");
   g_Logger.Log("");
   
   Print("Integration Test EA Ready");
   Print("Duration: " + IntegerToString(TEST_DURATION_SEC) + " seconds");
   Print("Monitoring policies on port 7778");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("========================================");
   Print("Integration Test - Stopping...");
   Print("========================================");
   
   EventKillTimer();
   
   g_Logger.Log("");
   g_Logger.Log("Test stopped: " + GetDeInitReasonText(reason));
   
   // Cleanup
   if(g_PolicySocket != NULL)
   {
      g_PolicySocket.close();
      delete g_PolicySocket;
      g_PolicySocket = NULL;
   }
   
   g_Context.shutdown();
   
   Print("Test Complete - Check log files in MQL5/Files/");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Check if test duration exceeded
   if(TimeCurrent() - g_TestStartTime >= TEST_DURATION_SEC)
   {
      g_Logger.Log("Test duration reached (" + IntegerToString(TEST_DURATION_SEC) + " sec)");
      ExpertRemove();
      return;
   }
   
   //--- Poll for policy messages
   if(g_PolicySocket == NULL) return;
   
   uchar data[];
   int received = g_PolicySocket.recv_bin(data, 10000, true);  // Non-blocking, max 10KB
   
   if(received > 0)
   {
      // Deserialize policy
      PolicyMessage policy;
      if(CProtocol::DeserializePolicyMessage(data, policy))
      {
         // Log policy received
         g_Logger.LogPolicyReceived(policy.symbol, policy.timestamp_ms);
         
         // Test 3: Symbol Validation
         // ✅ FIXED: Don't use FormatSymbol() because Python already sends symbol with suffix
         // Python sends: "XAUUSD.tp"
         // Chart symbol: "XAUUSD.tp"
         // Direct comparison works!
         bool is_my_symbol = (policy.symbol == _Symbol);
         
         // Debug log (can be removed after testing)
         if(!is_my_symbol)
         {
            g_Logger.Log(StringFormat("  Symbol mismatch: Policy='%s' Chart='%s'", 
                                     policy.symbol, _Symbol));
         }
         
         if(is_my_symbol)
         {
            g_Logger.Log("  Policy for this chart");
            g_Logger.Log(StringFormat("     Action: %s, Confidence: %.2f",
                                     GetActionString(policy.action),
                                     policy.confidence));
            
            // Test 4: Policy Data Validation
            g_Logger.StartTest("Policy Data Validation");
            
            bool valid = true;
            string issues = "";
            
            // Check required fields
            if(policy.confidence < 0 || policy.confidence > 1)
            {
               valid = false;
               issues += "Invalid confidence; ";
            }
            
            if(policy.entry_price <= 0)
            {
               valid = false;
               issues += "Invalid entry price; ";
            }
            
            if(policy.position_size <= 0)
            {
               valid = false;
               issues += "Invalid position size; ";
            }
            
            g_Logger.EndTest(valid, valid ? "All fields valid" : issues);
         }
         else
         {
            g_Logger.Log("  Policy for different symbol (" + policy.symbol + ")");
         }
      }
      else
      {
         g_Logger.Log("Failed to deserialize policy");
      }
   }
}

//+------------------------------------------------------------------+
//| Helper function to format symbol name                            |
//+------------------------------------------------------------------+
string FormatSymbol(string base_symbol)
{
   return SYMBOL_PREFIX + base_symbol + SYMBOL_SUFFIX;
}

//+------------------------------------------------------------------+
//| Get action string                                                |
//+------------------------------------------------------------------+
string GetActionString(int action)
{
   switch(action)
   {
      case 0: return "HOLD";
      case 1: return "BUY";
      case 2: return "SELL";
      default: return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Get deinit reason text                                           |
//+------------------------------------------------------------------+
string GetDeInitReasonText(int reason)
{
   switch(reason)
   {
      case REASON_PROGRAM:     return "Program terminated";
      case REASON_REMOVE:      return "Removed from chart";
      case REASON_RECOMPILE:   return "Recompiled";
      case REASON_CHARTCHANGE: return "Chart changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Parameters changed";
      case REASON_ACCOUNT:     return "Account changed";
      default:                 return "Unknown reason";
   }
}
//+------------------------------------------------------------------+
