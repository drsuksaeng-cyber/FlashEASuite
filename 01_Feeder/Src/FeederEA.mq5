//+------------------------------------------------------------------+
//|                                                     FeederEA.mq5 |
//+------------------------------------------------------------------+
#property strict
#include "../../Include/Zmq/Zmq.mqh"
#include "../../Include/MqlMsgPack.mqh"

input string InpZmqConnStr = "tcp://127.0.0.1:7777";
input int    InpTimerMs    = 50;
input bool   InpShowDebug  = true;

string g_StandardSymbols[] = { "EURUSD", "GBPUSD", "USDJPY", "XAUUSD" };

Context     g_Context;
Socket      g_Socket(ZMQ_PUB); // ✅ ถูกต้อง
CMsgPack    g_MsgPack;
long        g_SequenceID = 0;
long        g_LastTickTime[];

int OnInit() {
   if(!g_Context.initialize()) return INIT_FAILED;
   if(!g_Socket.initialize(g_Context, ZMQ_PUB)) return INIT_FAILED;
   if(!g_Socket.connect(InpZmqConnStr)) return INIT_FAILED; // ✅ ใช้ตัวแปร input
   
   g_Socket.setLinger(0);
   g_Socket.setSendHighWaterMark(100000);
   
   int total = ArraySize(g_StandardSymbols);
   ArrayResize(g_LastTickTime, total);
   ArrayInitialize(g_LastTickTime, 0);
   
   EventSetMillisecondTimer(InpTimerMs);
   Print("✅ Feeder Ready");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
   g_Socket.close();
   g_Context.shutdown();
}

void OnTimer() {
   MqlTick tick;
   int total = ArraySize(g_StandardSymbols);
   
   for(int i=0; i<total; i++) {
      if(!SymbolInfoTick(g_StandardSymbols[i], tick)) continue;
      if(tick.time_msc <= g_LastTickTime[i]) continue;
      
      g_LastTickTime[i] = tick.time_msc;
      g_SequenceID++;
      
      g_MsgPack.Reset();
      g_MsgPack.PackArray(7);
      g_MsgPack.PackInt(1);
      g_MsgPack.PackInt(g_SequenceID);
      g_MsgPack.PackInt(tick.time_msc);
      g_MsgPack.PackString(g_StandardSymbols[i]);
      g_MsgPack.PackDouble(tick.bid);
      g_MsgPack.PackDouble(tick.ask);
      g_MsgPack.PackInt(tick.flags);
      
      uchar data[];
      g_MsgPack.GetData(data);
      
      // ✅ ใช้ send_bin
      int sent = g_Socket.send_bin(data, true);
      if(InpShowDebug && sent > 0 && g_SequenceID % 100 == 0) Print("🚀 Tick Sent: ", g_StandardSymbols[i]);
   }
}