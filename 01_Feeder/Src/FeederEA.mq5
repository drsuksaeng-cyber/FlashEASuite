//+------------------------------------------------------------------+
//|                                                     FeederEA.mq5 |
//|                                        FeederEA - Fixed Version  |
//|                                        With .tp suffix support   |
//+------------------------------------------------------------------+
#property strict
#include "../../Include/Zmq/Zmq.mqh"
#include "../../Include/MqlMsgPack.mqh"

input string InpZmqConnStr = "tcp://127.0.0.1:7777";
input int    InpTimerMs    = 50;
input bool   InpShowDebug  = true;

// ⚠️ CRITICAL FIX: Added ".tp" suffix for this broker
// If your broker doesn't use suffix, remove ".tp"
string g_StandardSymbols[] = { "EURUSD.tp", "GBPUSD.tp", "USDJPY.tp", "XAUUSD.tp" };

Context     g_Context;
Socket      g_Socket(ZMQ_PUB);
CMsgPack    g_MsgPack;
long        g_SequenceID = 0;
long        g_LastTickTime[];

int OnInit() {
   if(!g_Context.initialize()) {
      Print("❌ Failed to initialize ZMQ context");
      return INIT_FAILED;
   }
   
   if(!g_Socket.initialize(g_Context, ZMQ_PUB)) {
      Print("❌ Failed to initialize ZMQ socket");
      return INIT_FAILED;
   }
   
   if(!g_Socket.connect(InpZmqConnStr)) {
      Print("❌ Failed to connect to ", InpZmqConnStr);
      return INIT_FAILED;
   }
   
   g_Socket.setLinger(0);
   g_Socket.setSendHighWaterMark(100000);
   
   int total = ArraySize(g_StandardSymbols);
   ArrayResize(g_LastTickTime, total);
   ArrayInitialize(g_LastTickTime, 0);
   
   EventSetMillisecondTimer(InpTimerMs);
   
   Print("========================================");
   Print("  FeederEA - FIXED VERSION");
   Print("  Symbols: ", ArraySize(g_StandardSymbols));
   for(int i=0; i<total; i++) {
      Print("  [", i, "] ", g_StandardSymbols[i]);
   }
   Print("  ZMQ: ", InpZmqConnStr);
   Print("  Timer: ", InpTimerMs, "ms");
   Print("========================================");
   Print("✅ Feeder Ready");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
   g_Socket.close();
   g_Context.shutdown();
   Print("FeederEA stopped. Reason: ", reason);
}

void OnTimer() {
   MqlTick tick;
   int total = ArraySize(g_StandardSymbols);
   
   for(int i=0; i<total; i++) {
      // 🔍 DEBUG: Check if symbol exists and has data
      if(!SymbolInfoTick(g_StandardSymbols[i], tick)) {
         // Only show warning occasionally to avoid spam
         if(InpShowDebug && g_SequenceID % 200 == 0) {
            Print("⚠️ No tick data for: ", g_StandardSymbols[i]);
            Print("   → Check if symbol exists in Market Watch");
            Print("   → Symbol name might be incorrect");
         }
         continue;
      }
      
      // Skip if not a new tick
      if(tick.time_msc <= g_LastTickTime[i]) continue;
      
      g_LastTickTime[i] = tick.time_msc;
      g_SequenceID++;
      
      // Pack tick data
      g_MsgPack.Reset();
      g_MsgPack.PackArray(7);
      g_MsgPack.PackInt(1);                      // Message type: Tick
      g_MsgPack.PackInt(g_SequenceID);           // Sequence ID
      g_MsgPack.PackInt(tick.time_msc);          // Timestamp
      g_MsgPack.PackString(g_StandardSymbols[i]);// Symbol
      g_MsgPack.PackDouble(tick.bid);            // Bid
      g_MsgPack.PackDouble(tick.ask);            // Ask
      g_MsgPack.PackInt(tick.flags);             // Flags
      
      uchar data[];
      g_MsgPack.GetData(data);
      
      // Send via ZMQ
      int sent = g_Socket.send_bin(data, true);
      
      // 🔍 IMPROVED: Show log every 10 ticks (not 100!) with detailed info
      if(InpShowDebug && sent > 0 && g_SequenceID % 10 == 0) {
         Print("🚀 Tick #", g_SequenceID, " sent: ", g_StandardSymbols[i], 
               " | Bid: ", DoubleToString(tick.bid, 2), 
               " | Ask: ", DoubleToString(tick.ask, 2),
               " | Bytes: ", sent);
      }
      
      // Show error if send failed
      if(sent <= 0 && InpShowDebug) {
         Print("❌ Failed to send tick #", g_SequenceID, " for: ", g_StandardSymbols[i]);
         Print("   → ZMQ connection may be lost");
         Print("   → Check if Python Brain is running");
      }
   }
}
