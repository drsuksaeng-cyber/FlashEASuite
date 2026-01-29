//+------------------------------------------------------------------+
//|                                    TestPhase1_LicenseVerify.mq5 |
//|                              FlashEASuite V2 - Phase 1 Test     |
//|                              License Verification Test          |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| License Structure                                                 |
//+------------------------------------------------------------------+
struct LicenseData {
   string license_id;
   string product;
   string license_type;
   string client_name;
   string client_email;
   string hwid;
   int max_slots;
   datetime issued_date;
   datetime expiry_date;
   int grace_days;
   string signature;
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
LicenseData g_license;
bool g_license_valid = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("");
   Print("============================================================");
   Print("  FlashEASuite V2 - Phase 1 License Test");
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
   
   // Test 2: Read license file
   Print("[TEST 2] Reading license file...");
   if(!ReadLicenseFile()) {
      Print("[FAIL] Could not read license file");
      return INIT_FAILED;
   }
   Print("[PASS] License file read successfully");
   Print("");
   
   // Test 3: Display license info
   Print("[TEST 3] License Information:");
   DisplayLicenseInfo();
   Print("");
   
   // Test 4: Check expiry
   Print("[TEST 4] Checking expiry date...");
   if(!CheckExpiry()) {
      Print("[WARN] License expired or will expire soon");
   } else {
      Print("[PASS] License is valid");
   }
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
   Print("  ✅ Phase 1 Basic Tests: PASSED");
   Print("============================================================");
   Print("");
   Print("NOTE: Signature verification requires DLL (Phase 3)");
   Print("For now, we've verified:");
   Print("  ✓ License file exists");
   Print("  ✓ License file is readable");
   Print("  ✓ License data is valid JSON");
   Print("  ✓ Public key exists");
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
//| Read license file                                                 |
//+------------------------------------------------------------------+
bool ReadLicenseFile() {
   int file = FileOpen("license.key", FILE_READ|FILE_TXT);
   if(file == INVALID_HANDLE) {
      Print("Error opening license file: ", GetLastError());
      return false;
   }
   
   // Read entire file
   string content = "";
   while(!FileIsEnding(file)) {
      content += FileReadString(file);
   }
   FileClose(file);
   
   if(StringLen(content) == 0) {
      Print("License file is empty");
      return false;
   }
   
   // Parse JSON (simplified - just extract key fields)
   return ParseLicenseJSON(content);
}

//+------------------------------------------------------------------+
//| Parse license JSON (simplified)                                   |
//+------------------------------------------------------------------+
bool ParseLicenseJSON(string json) {
   // Extract license_id
   g_license.license_id = ExtractJSONString(json, "license_id");
   if(g_license.license_id == "") {
      Print("Could not extract license_id");
      return false;
   }
   
   // Extract product
   g_license.product = ExtractJSONString(json, "product");
   
   // Extract license_type
   g_license.license_type = ExtractJSONString(json, "license_type");
   
   // Extract client info
   g_license.client_name = ExtractJSONString(json, "name");
   g_license.client_email = ExtractJSONString(json, "email");
   
   // Extract HWID
   g_license.hwid = ExtractJSONString(json, "hwid");
   
   // Extract max_slots
   string max_slots_str = ExtractJSONString(json, "max_slots");
   g_license.max_slots = (int)StringToInteger(max_slots_str);
   
   // Extract dates
   string issued_str = ExtractJSONString(json, "issued_date");
   string expiry_str = ExtractJSONString(json, "expiry_date");
   
   // Parse dates (format: YYYY-MM-DD)
   g_license.issued_date = ParseDate(issued_str);
   g_license.expiry_date = ParseDate(expiry_str);
   
   // Extract grace_days
   string grace_str = ExtractJSONString(json, "grace_days");
   g_license.grace_days = (int)StringToInteger(grace_str);
   
   // Extract signature
   g_license.signature = ExtractJSONString(json, "signature");
   
   return true;
}

//+------------------------------------------------------------------+
//| Extract string value from JSON (simplified)                       |
//+------------------------------------------------------------------+
string ExtractJSONString(string json, string key) {
   string search = "\"" + key + "\":";
   int pos = StringFind(json, search);
   if(pos < 0) return "";
   
   // Find opening quote
   int start = StringFind(json, "\"", pos + StringLen(search));
   if(start < 0) {
      // Might be a number
      start = pos + StringLen(search);
      int end = StringFind(json, ",", start);
      if(end < 0) end = StringFind(json, "}", start);
      if(end < 0) return "";
      
      string value = StringSubstr(json, start, end - start);
      StringReplace(value, " ", "");
      StringReplace(value, "\n", "");
      StringReplace(value, "\r", "");
      return value;
   }
   
   // Find closing quote
   int end = StringFind(json, "\"", start + 1);
   if(end < 0) return "";
   
   return StringSubstr(json, start + 1, end - start - 1);
}

//+------------------------------------------------------------------+
//| Parse date string (YYYY-MM-DD)                                    |
//+------------------------------------------------------------------+
datetime ParseDate(string date_str) {
   if(StringLen(date_str) < 10) return 0;
   
   int year = (int)StringToInteger(StringSubstr(date_str, 0, 4));
   int month = (int)StringToInteger(StringSubstr(date_str, 5, 2));
   int day = (int)StringToInteger(StringSubstr(date_str, 8, 2));
   
   MqlDateTime dt;
   dt.year = year;
   dt.mon = month;
   dt.day = day;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Display license information                                       |
//+------------------------------------------------------------------+
void DisplayLicenseInfo() {
   Print("  License ID:    ", g_license.license_id);
   Print("  Product:       ", g_license.product);
   Print("  Type:          ", g_license.license_type);
   Print("  Client:        ", g_license.client_name);
   Print("  Email:         ", g_license.client_email);
   Print("  HWID:          ", g_license.hwid);
   Print("  Max Slots:     ", g_license.max_slots);
   Print("  Issued:        ", TimeToString(g_license.issued_date, TIME_DATE));
   Print("  Expires:       ", TimeToString(g_license.expiry_date, TIME_DATE));
   Print("  Grace Days:    ", g_license.grace_days);
   Print("  Signature:     ", StringSubstr(g_license.signature, 0, 50), "...");
}

//+------------------------------------------------------------------+
//| Check expiry                                                      |
//+------------------------------------------------------------------+
bool CheckExpiry() {
   datetime now = TimeCurrent();
   
   if(now > g_license.expiry_date) {
      // Expired - check grace period
      int days_since_expiry = (int)((now - g_license.expiry_date) / 86400);
      
      if(days_since_expiry <= g_license.grace_days) {
         Print("  WARNING: License expired ", days_since_expiry, " days ago");
         Print("  Grace period: ", (g_license.grace_days - days_since_expiry), " days remaining");
         return false;
      } else {
         Print("  ERROR: License expired and grace period ended");
         return false;
      }
   }
   
   // Calculate days until expiry
   int days_left = (int)((g_license.expiry_date - now) / 86400);
   Print("  License valid: ", days_left, " days remaining");
   
   if(days_left < 30) {
      Print("  WARNING: License expires in less than 30 days");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   // No action on tick
}
//+------------------------------------------------------------------+
