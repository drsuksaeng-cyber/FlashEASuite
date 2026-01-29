//+------------------------------------------------------------------+
//|                                TestPhase1_LicenseVerify_v2.mq5   |
//|                              FlashEASuite V2 - Phase 1 Test     |
//|                              License Verification Test (Debug)  |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("");
   Print("============================================================");
   Print("  FlashEASuite V2 - Phase 1 License Test (DEBUG)");
   Print("  Testing: License File Reading & Parsing");
   Print("============================================================");
   Print("");
   
   // Test 1: Check if license file exists
   Print("[TEST 1] Checking license file...");
   if(!TestLicenseFileExists()) {
      Print("[FAIL] License file not found!");
      Print("Expected location: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\Files\\license.key");
      return INIT_FAILED;
   }
   Print("[PASS] License file found");
   Print("");
   
   // Test 2: Read and display raw content
   Print("[TEST 2] Reading license file (RAW CONTENT)...");
   string content = ReadLicenseFileRaw();
   if(content == "") {
      Print("[FAIL] Could not read license file");
      return INIT_FAILED;
   }
   
   Print("[DEBUG] File size: ", StringLen(content), " characters");
   Print("[DEBUG] First 500 chars:");
   Print(StringSubstr(content, 0, 500));
   Print("");
   
   // Test 3: Try to extract license_id
   Print("[TEST 3] Extracting license_id...");
   string license_id = ExtractValue(content, "license_id");
   if(license_id == "") {
      Print("[FAIL] Could not extract license_id");
      Print("[DEBUG] Trying alternative method...");
      
      // Try finding it manually
      int pos = StringFind(content, "\"license_id\"");
      if(pos >= 0) {
         Print("[DEBUG] Found 'license_id' at position: ", pos);
         Print("[DEBUG] Content around it:");
         int start = MathMax(0, pos - 50);
         int len = 200;
         Print(StringSubstr(content, start, len));
      } else {
         Print("[DEBUG] 'license_id' string not found in file");
      }
      
      return INIT_FAILED;
   }
   
   Print("[PASS] License ID: ", license_id);
   Print("");
   
   // Test 4: Extract other fields
   Print("[TEST 4] Extracting other fields...");
   string product = ExtractValue(content, "product");
   string license_type = ExtractValue(content, "license_type");
   string client_name = ExtractValue(content, "name");
   string hwid = ExtractValue(content, "hwid");
   
   Print("  Product:       ", product);
   Print("  Type:          ", license_type);
   Print("  Client:        ", client_name);
   Print("  HWID:          ", StringSubstr(hwid, 0, 30), "...");
   Print("");
   
   // Test 5: Check public key
   Print("[TEST 5] Checking public key...");
   if(!TestPublicKeyExists()) {
      Print("[FAIL] Public key not found!");
      Print("Expected location: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\Files\\server_public.pem");
      return INIT_FAILED;
   }
   Print("[PASS] Public key found");
   Print("");
   
   Print("============================================================");
   Print("  ✅ Phase 1 Debug Tests: COMPLETED");
   Print("============================================================");
   Print("");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   Print("Test EA removed from chart");
}

//+------------------------------------------------------------------+
//| Test if license file exists                                       |
//+------------------------------------------------------------------+
bool TestLicenseFileExists() {
   int file = FileOpen("license.key", FILE_READ|FILE_TXT);
   if(file == INVALID_HANDLE) {
      return false;
   }
   FileClose(file);
   return true;
}

//+------------------------------------------------------------------+
//| Test if public key exists                                         |
//+------------------------------------------------------------------+
bool TestPublicKeyExists() {
   int file = FileOpen("server_public.pem", FILE_READ|FILE_TXT);
   if(file == INVALID_HANDLE) {
      return false;
   }
   FileClose(file);
   return true;
}

//+------------------------------------------------------------------+
//| Read license file (RAW)                                           |
//+------------------------------------------------------------------+
string ReadLicenseFileRaw() {
   int file = FileOpen("license.key", FILE_READ|FILE_TXT);
   if(file == INVALID_HANDLE) {
      Print("Error opening license file: ", GetLastError());
      return "";
   }
   
   // Read entire file
   string content = "";
   while(!FileIsEnding(file)) {
      string line = FileReadString(file);
      content += line;
   }
   FileClose(file);
   
   return content;
}

//+------------------------------------------------------------------+
//| Extract value from JSON (improved method)                         |
//+------------------------------------------------------------------+
string ExtractValue(string json, string key) {
   // Method 1: Look for "key": "value"
   string pattern1 = "\"" + key + "\":";
   int pos = StringFind(json, pattern1);
   
   if(pos < 0) {
      // Try without colon
      pattern1 = "\"" + key + "\"";
      pos = StringFind(json, pattern1);
      if(pos < 0) return "";
      
      // Find the colon after key
      int colon_pos = StringFind(json, ":", pos);
      if(colon_pos < 0) return "";
      pos = colon_pos;
   } else {
      pos += StringLen(pattern1);
   }
   
   // Skip whitespace
   while(pos < StringLen(json)) {
      ushort ch = StringGetCharacter(json, pos);
      if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') break;
      pos++;
   }
   
   // Check if value is quoted string or number
   ushort first_char = StringGetCharacter(json, pos);
   
   if(first_char == '\"') {
      // Quoted string
      int start = pos + 1;
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      
      return StringSubstr(json, start, end - start);
   } else {
      // Number or boolean
      int start = pos;
      int end = start;
      
      // Find end (comma, }, or ])
      while(end < StringLen(json)) {
         ushort ch = StringGetCharacter(json, end);
         if(ch == ',' || ch == '}' || ch == ']' || ch == '\n' || ch == '\r') break;
         end++;
      }
      
      string value = StringSubstr(json, start, end - start);
      StringTrimLeft(value);
      StringTrimRight(value);
      return value;
   }
   
   return "";
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // No action on tick
}
//+------------------------------------------------------------------+
