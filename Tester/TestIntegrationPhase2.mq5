//+------------------------------------------------------------------+
//|                                  TestIntegrationPhase2.mq5       |
//|                          FlashEASuite V2 - Phase 2               |
//|                          Integration Testing (Chat 3)            |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

// Use relative paths with quotes (not system include syntax)
#include "../Include/Network/PolicyVerifier.mqh"
#include "../Include/Zmq/Zmq.mqh"

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CPolicyVerifier g_verifier;

// ZMQ
Context g_context;
Socket g_sub_socket(g_context, ZMQ_SUB);

// Statistics
int g_policies_received = 0;
int g_policies_accepted = 0;
int g_policies_rejected = 0;

datetime g_last_policy_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("═══════════════════════════════════════════════════════════");
   Print("  FlashEASuite V2 - Integration Test (Phase 2)");
   Print("  MQL5 Side: Policy Receiver & Verifier");
   Print("═══════════════════════════════════════════════════════════");
   
   // Initialize verifier
   if(!g_verifier.Initialize("server_public.pem"))
     {
      Print("❌ PolicyVerifier initialization failed");
      return INIT_FAILED;
     }
   
   Print("✅ PolicyVerifier initialized");
   
   // Initialize ZMQ subscriber
   if(!g_sub_socket.bind("tcp://127.0.0.1:7778"))
     {
      Print("❌ Failed to bind ZMQ SUB socket to port 7778");
      return INIT_FAILED;
     }
   
   g_sub_socket.setSubscribe("");  // Subscribe to all messages
   Print("✅ ZMQ SUB bound to tcp://127.0.0.1:7778");
   
   // Set timer for polling
   EventSetMillisecondTimer(100);  // Poll every 100ms
   
   Print("\n🎯 Ready to receive policies from Python Brain");
   Print("   Listening on ZMQ port 7778");
   Print("   Run: python test_integration_phase2.py\n");
   Print("═══════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // ZMQ cleanup (socket closes automatically)
   
   Print("\n═══════════════════════════════════════════════════════════");
   Print("INTEGRATION TEST SUMMARY");
   Print("═══════════════════════════════════════════════════════════");
   Print("Policies Received: ", g_policies_received);
   Print("Policies Accepted: ", g_policies_accepted, " ✅");
   Print("Policies Rejected: ", g_policies_rejected, " ❌");
   
   double acceptance_rate = 0;
   if(g_policies_received > 0)
      acceptance_rate = (double)g_policies_accepted / g_policies_received * 100;
   
   Print("Acceptance Rate: ", DoubleToString(acceptance_rate, 1), "%");
   Print("═══════════════════════════════════════════════════════════");
   
   Print("Integration Test EA stopped");
  }

//+------------------------------------------------------------------+
//| Timer function - Poll for policies                               |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Poll ZMQ socket (non-blocking)
   ZmqMsg msg;
   
   // Try to receive message
   if(g_sub_socket.recv(msg, ZMQ_DONTWAIT))  // Non-blocking
     {
      uchar data[];
      msg.getData(data);
      
      if(ArraySize(data) > 0)
        {
         g_policies_received++;
         ProcessPolicy(data);
        }
     }
  }

//+------------------------------------------------------------------+
//| Process received policy                                           |
//+------------------------------------------------------------------+
void ProcessPolicy(uchar &data[])
  {
   Print("\n─────────────────────────────────────");
   Print("📥 POLICY RECEIVED #", g_policies_received);
   Print("   Size: ", ArraySize(data), " bytes");
   Print("   Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   
   // TODO: Deserialize MessagePack to extract fields
   // For now, we'll simulate with dummy values for testing
   
   // Simulated fields (in real implementation, parse from data[])
   string policy_json = "{\"symbol\":\"XAUUSD\",\"action\":1}";
   string signature = "dummy_signature";
   string symbol = "XAUUSD";
   long sequence = g_policies_received;  // Simulated
   string nonce = StringFormat("nonce-%d-%d", g_policies_received, (int)TimeCurrent());
   datetime timestamp = TimeCurrent();
   string error_msg;
   
   // Try to parse actual data (basic MessagePack parsing)
   if(TryParsePolicy(data, policy_json, signature, symbol, sequence, nonce, timestamp))
     {
      Print("✅ Policy parsed successfully");
     }
   else
     {
      Print("⚠️  Using simulated values for testing");
     }
   
   Print("   Symbol: ", symbol);
   Print("   Sequence: ", sequence);
   Print("   Nonce: ", StringSubstr(nonce, 0, 20), "...");
   Print("   Timestamp: ", TimeToString(timestamp, TIME_DATE|TIME_SECONDS));
   
   // VERIFY POLICY
   bool valid = g_verifier.VerifyPolicy(
      policy_json,
      signature,
      symbol,
      sequence,
      nonce,
      timestamp,
      error_msg
   );
   
   if(valid)
     {
      g_policies_accepted++;
      Print("✅ POLICY ACCEPTED (", g_policies_accepted, "/", g_policies_received, ")");
      Print("   All security checks passed");
      g_last_policy_time = TimeCurrent();
     }
   else
     {
      g_policies_rejected++;
      Print("❌ POLICY REJECTED (", g_policies_rejected, "/", g_policies_received, ")");
      Print("   Reason: ", error_msg);
     }
   
   Print("─────────────────────────────────────");
  }

//+------------------------------------------------------------------+
//| Try to parse policy from MessagePack data                        |
//| Note: This is a simplified parser for testing                    |
//+------------------------------------------------------------------+
bool TryParsePolicy(
   uchar &data[],
   string &policy_json,
   string &signature,
   string &symbol,
   long &sequence,
   string &nonce,
   datetime &timestamp
)
  {
   // This is a placeholder
   // In real implementation, use proper MessagePack parser
   // or existing Serialization.mqh
   
   // For Phase 2 integration testing, we accept the limitation
   // that we can't fully parse MessagePack yet
   
   return false;  // Return false = use simulated values
  }

//+------------------------------------------------------------------+
//| Expert tick function (not used)                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Not used - we use OnTimer for polling
  }

//+------------------------------------------------------------------+
//| Print statistics periodically                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_KEYDOWN)
     {
      // Press 'S' to show statistics
      if(lparam == 83)  // 'S' key
        {
         Print("\n📊 CURRENT STATISTICS:");
         Print("   Policies Received: ", g_policies_received);
         Print("   Policies Accepted: ", g_policies_accepted, " ✅");
         Print("   Policies Rejected: ", g_policies_rejected, " ❌");
         
         if(g_last_policy_time > 0)
           {
            int seconds_ago = (int)(TimeCurrent() - g_last_policy_time);
            Print("   Last policy: ", seconds_ago, " seconds ago");
           }
         
         g_verifier.PrintStats();
        }
     }
  }
//+------------------------------------------------------------------+
