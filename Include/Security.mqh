//+------------------------------------------------------------------+
//|                                                     Security.mqh |
//|                        FlashEASuite V2 - CurveZMQ Key Manager    |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property strict

class CSecurity
{
private:
   string m_clientKey;
   string m_clientSecretKey;
   string m_serverKey;
   string m_keysPath;
   bool   m_keysLoaded;
   
   bool ReadFile(string filename, string &content)
   {
      string fullPath = m_keysPath + filename;
      int fileHandle = FileOpen(fullPath, FILE_READ|FILE_TXT|FILE_COMMON);
      if(fileHandle == INVALID_HANDLE) {
         Print("ERROR: Cannot open file: ", fullPath, " in Common/Files");
         return false;
      }
      content = "";
      while(!FileIsEnding(fileHandle)) {
         string line = FileReadString(fileHandle);
         content += line;
         if(!FileIsEnding(fileHandle)) content += "\n";
      }
      FileClose(fileHandle);
      StringTrimLeft(content); StringTrimRight(content);
      return (StringLen(content) > 0);
   }

public:
   CSecurity() { m_keysPath = "FlashEASuite_Keys\\"; m_keysLoaded = false; }
   
   bool LoadKeys()
   {
      bool success = true;
      if(!ReadFile("client.key", m_clientKey)) success = false;
      if(!ReadFile("client.key_secret", m_clientSecretKey)) success = false;
      if(!ReadFile("server.key", m_serverKey)) success = false;
      
      m_keysLoaded = success;
      if(success) Print("✅ Security Keys Loaded Successfully");
      else Print("❌ Failed to load keys. Ensure 'FlashEASuite_Keys' folder exists in Common/Files");
      return success;
   }
   
   bool GetKeys(string &cKey, string &cSecret, string &sKey)
   {
      if(!m_keysLoaded) return false;
      cKey = m_clientKey; cSecret = m_clientSecretKey; sKey = m_serverKey;
      return true;
   }
};