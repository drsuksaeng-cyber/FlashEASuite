//+------------------------------------------------------------------+
//| TestPublicKey.mq5                                                |
//| Test what public key is embedded in DLL                         |
//+------------------------------------------------------------------+
#property script_show_inputs

// We'll create a test function to check
#import "FlashEA_Security.dll"
   void GetHWID(string &output);
   int CheckLicense(const string license_path);
#import

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Testing DLL ===");
   
   // Test 1: HWID (should work regardless)
   string hwid = "";
   GetHWID(hwid);
   Print("HWID: ", hwid);
   Print("");
   
   // Test 2: CheckLicense
   string terminal = TerminalInfoString(TERMINAL_DATA_PATH);
   string license_path = terminal + "\\MQL5\\Files\\License.key";
   
   Print("License path: ", license_path);
   
   // Check if file exists
   int file_handle = FileOpen("License.key", FILE_READ|FILE_TXT);
   if(file_handle != INVALID_HANDLE)
   {
      Print("License file size: ", FileSize(file_handle), " bytes");
      
      // Read first line
      string first_line = FileReadString(file_handle);
      Print("First line: ", first_line);
      
      FileClose(file_handle);
   }
   else
   {
      Print("ERROR: Cannot open License.key");
      return;
   }
   
   Print("");
   Print("Calling CheckLicense()...");
   
   int result = CheckLicense(license_path);
   
   Print("Result: ", result);
   Print("");
   
   switch(result)
   {
      case 1:
         Print("✓ SUCCESS! License is valid!");
         break;
      case -1:
         Print("✗ File not found");
         break;
      case -2:
         Print("✗ Invalid JSON format");
         break;
      case -3:
         Print("✗ Invalid signature - PUBLIC KEY MISMATCH!");
         Print("");
         Print("This means:");
         Print("  - DLL has OLD public key embedded");
         Print("  - Need to rebuild DLL with NEW public key");
         break;
      case -4:
         Print("✗ HWID mismatch");
         break;
      case -5:
         Print("✗ License expired");
         break;
      case -6:
         Print("✗ No available slots");
         break;
      default:
         Print("✗ Unknown error: ", result);
   }
   
   // Check debug log
   Print("");
   Print("Check debug log at:");
   Print(terminal, "\\MQL5\\Libraries\\dll_debug.log");
}
//+------------------------------------------------------------------+
