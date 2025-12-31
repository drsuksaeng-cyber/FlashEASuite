//+------------------------------------------------------------------+
//| TEST_MqlMsgPack.mq5 - Test if MqlMsgPack compiles                 |
//| Location: Tester/TEST_MqlMsgPack.mq5                             |
//+------------------------------------------------------------------+
#property strict

#include "../Include/MqlMsgPack.mqh"  // Local include - relative path from Tester/

void OnInit()
{
   Print("TEST: Creating CMsgPack object");
   
   CMsgPack pack;
   pack.PackArray(3);
   pack.PackInt(123);
   pack.PackDouble(45.67);
   pack.PackString("Hello");
   
   uchar data[];
   pack.GetData(data);
   
   Print("SUCCESS: MqlMsgPack works! Size: ", pack.GetSize());
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
}
