//+------------------------------------------------------------------+
//| GetMyHWID.mq5                                                    |
//| Get Real HWID from DLL                                           |
//+------------------------------------------------------------------+
#property script_show_inputs

#import "FlashEA_Security.dll"
   void GetHWID(string &output);
#import

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Getting Real HWID ===");
   
   string hwid = "";
   GetHWID(hwid);
   
   Print("════════════════════════════════════════════════════");
   Print("YOUR REAL HWID:");
   Print(hwid);
   Print("════════════════════════════════════════════════════");
   Print("");
   Print("Copy this HWID and use it in license generator!");
   
   // Show in chart comment too
   Comment("YOUR REAL HWID:\n", hwid, "\n\nCopy from log!");
   
   Alert("HWID retrieved! Check Experts log");
}
//+------------------------------------------------------------------+
