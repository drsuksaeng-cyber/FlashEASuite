//+------------------------------------------------------------------+
//|                                TestPhase1_LicenseVerify_v4.mq5   |
//|                              FlashEASuite V2 - Phase 1 Test     |
//|                              License Test (Encoding Fixed)      |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "4.00"
#property strict

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("");
   Print("============================================================");
   Print("  FlashEASuite V2 - Phase 1 License Test (v4)");
   Print("  Testing: License File with Correct Encoding");
   Print("============================================================");
   Print("");
   
   // Test 1: Check if license file exists
   Print("[TEST 1] Checking license file...");
   if(!FileIsExist("license.key")) {
      Print("[FAIL] License file not found!");
      Print("Expected: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\Files\\license.key");
      return INIT_FAILED;
   }
   Print("[PASS] License file found");
   Print("");
   
   // Test 2: Try reading with different encodings
   Print("[TEST 2] Reading license file with ANSI encoding...");
   string content_ansi = ReadFileANSI("license.key");
   
   if(content_ansi != "" && StringFind(content_ansi, "license_id") >= 0) {
      Print("[PASS] File readable with ANSI encoding");
      Print("[DEBUG] File size: ", StringLen(content_ansi), " characters");
      Print("[DEBUG] First 200 chars:");
      Print(StringSubstr(content_ansi, 0, 200));
      Print("");
      
      // Try to parse
      if(ParseAndDisplay(content_ansi)) {
         Print("");
         Print("============================================================");
         Print("  ✅ Phase 1 Tests: PASSED (ANSI encoding)");
         Print("============================================================");
         return INIT_SUCCEEDED;
      }
   }
   
   Print("[INFO] ANSI encoding failed, trying UTF-8...");
   Print("");
   
   // Test 3: Try UTF-8
   Print("[TEST 3] Reading license file with UTF-8 encoding...");
   string content_utf8 = ReadFileUTF8("license.key");
   
   if(content_utf8 != "" && StringFind(content_utf8, "license_id") >= 0) {
      Print("[PASS] File readable with UTF-8 encoding");
      Print("[DEBUG] File size: ", StringLen(content_utf8), " characters");
      Print("[DEBUG] First 200 chars:");
      Print(StringSubstr(content_utf8, 0, 200));
      Print("");
      
      // Try to parse
      if(ParseAndDisplay(content_utf8)) {
         Print("");
         Print("============================================================");
         Print("  ✅ Phase 1 Tests: PASSED (UTF-8 encoding)");
         Print("============================================================");
         return INIT_SUCCEEDED;
      }
   }
   
   Print("[FAIL] Could not read file with any encoding");
   Print("");
   
   // Test 4: Show hex dump for debugging
   Print("[TEST 4] HEX DUMP (first 100 bytes)...");
   ShowHexDump("license.key", 100);
   
   return INIT_FAILED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   Print("Test EA removed from chart");
}

//+------------------------------------------------------------------+
//| Read file with ANSI encoding                                      |
//+------------------------------------------------------------------+
string ReadFileANSI(string filename) {
   ResetLastError();
   int file = FileOpen(filename, FILE_READ|FILE_ANSI);
   if(file == INVALID_HANDLE) {
      int error = GetLastError();
      Print("[ERROR] Cannot open file (ANSI): ", error);
      return "";
   }
   
   string content = "";
   while(!FileIsEnding(file)) {
      content += FileReadString(file);
   }
   FileClose(file);
   
   return content;
}

//+------------------------------------------------------------------+
//| Read file with UTF-8 encoding                                     |
//+------------------------------------------------------------------+
string ReadFileUTF8(string filename) {
   ResetLastError();
   int file = FileOpen(filename, FILE_READ|FILE_TXT);  // Default is UTF-8
   if(file == INVALID_HANDLE) {
      int error = GetLastError();
      Print("[ERROR] Cannot open file (UTF-8): ", error);
      return "";
   }
   
   string content = "";
   while(!FileIsEnding(file)) {
      content += FileReadString(file);
   }
   FileClose(file);
   
   return content;
}

//+------------------------------------------------------------------+
//| Show hex dump of file                                             |
//+------------------------------------------------------------------+
void ShowHexDump(string filename, int max_bytes) {
   int file = FileOpen(filename, FILE_READ|FILE_BIN);
   if(file == INVALID_HANDLE) {
      Print("[ERROR] Cannot open file for hex dump");
      return;
   }
   
   uchar buffer[];
   int bytes_read = FileReadArray(file, buffer, 0, max_bytes);
   FileClose(file);
   
   Print("[HEX] First ", bytes_read, " bytes:");
   
   string hex = "";
   string ascii = "";
   
   for(int i = 0; i < bytes_read; i++) {
      // Hex
      hex += StringFormat("%02X ", buffer[i]);
      
      // ASCII
      if(buffer[i] >= 32 && buffer[i] <= 126) {
         ascii += CharToString((char)buffer[i]);
      } else {
         ascii += ".";
      }
      
      // Print every 16 bytes
      if((i + 1) % 16 == 0 || i == bytes_read - 1) {
         Print(StringFormat("%04X: %-48s %s", i - (i % 16), hex, ascii));
         hex = "";
         ascii = "";
      }
   }
}

//+------------------------------------------------------------------+
//| Parse JSON and display                                            |
//+------------------------------------------------------------------+
bool ParseAndDisplay(string json) {
   Print("[TEST] Parsing JSON...");
   
   // Extract license_id
   string license_id = ExtractValue(json, "license_id");
   if(license_id == "") {
      Print("[FAIL] Could not extract license_id");
      return false;
   }
   
   Print("[PASS] License data extracted:");
   Print("  License ID:    ", license_id);
   
   // Extract other fields
   string product = ExtractValue(json, "product");
   string license_type = ExtractValue(json, "license_type");
   
   Print("  Product:       ", product);
   Print("  Type:          ", license_type);
   
   // Client
   int client_pos = StringFind(json, "\"client\"");
   if(client_pos >= 0) {
      string client_section = StringSubstr(json, client_pos, 200);
      string client_name = ExtractValue(client_section, "name");
      string client_email = ExtractValue(client_section, "email");
      Print("  Client:        ", client_name);
      Print("  Email:         ", client_email);
   }
   
   // HWID
   int hwid_pos = StringFind(json, "\"hardware_binding\"");
   if(hwid_pos >= 0) {
      string hwid_section = StringSubstr(json, hwid_pos, 200);
      string hwid = ExtractValue(hwid_section, "hwid");
      string max_slots = ExtractValue(hwid_section, "max_slots");
      Print("  HWID:          ", StringSubstr(hwid, 0, 40), "...");
      Print("  Max Slots:     ", max_slots);
   }
   
   // Validity
   int validity_pos = StringFind(json, "\"validity\"");
   if(validity_pos >= 0) {
      string validity_section = StringSubstr(json, validity_pos, 200);
      string issued = ExtractValue(validity_section, "issued_date");
      string expiry = ExtractValue(validity_section, "expiry_date");
      string grace = ExtractValue(validity_section, "grace_days");
      Print("  Issued:        ", issued);
      Print("  Expires:       ", expiry);
      Print("  Grace Days:    ", grace);
   }
   
   // Signature
   string signature = ExtractValue(json, "signature");
   Print("  Signature:     ", StringSubstr(signature, 0, 50), "...");
   
   // Check public key
   Print("");
   Print("[TEST] Checking public key...");
   if(!FileIsExist("server_public.pem")) {
      Print("[FAIL] Public key not found");
      return false;
   }
   Print("[PASS] Public key found");
   
   return true;
}

//+------------------------------------------------------------------+
//| Extract value from JSON (improved)                                |
//+------------------------------------------------------------------+
string ExtractValue(string json, string key) {
   // Look for "key":
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0) return "";
   
   // Find colon
   int colon = StringFind(json, ":", pos);
   if(colon < 0) return "";
   
   // Skip whitespace after colon
   int start = colon + 1;
   while(start < StringLen(json)) {
      ushort ch = StringGetCharacter(json, start);
      if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') break;
      start++;
   }
   
   // Check if quoted
   ushort first = StringGetCharacter(json, start);
   
   if(first == '\"') {
      // String value
      int end = StringFind(json, "\"", start + 1);
      if(end < 0) return "";
      return StringSubstr(json, start + 1, end - start - 1);
   } else {
      // Number or boolean
      int end = start;
      while(end < StringLen(json)) {
         ushort ch = StringGetCharacter(json, end);
         if(ch == ',' || ch == '}' || ch == ']' || ch == '\n' || ch == '\r' || ch == ' ') break;
         end++;
      }
      
      string value = StringSubstr(json, start, end - start);
      StringTrimLeft(value);
      StringTrimRight(value);
      return value;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // No action
}
//+------------------------------------------------------------------+
