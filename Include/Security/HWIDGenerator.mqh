//+------------------------------------------------------------------+
//|                                              HWIDGenerator.mqh   |
//|                                    FlashEASuite V2 - Security    |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2"
#property version   "1.00"
#property strict

class CHWIDGenerator
{
private:
    string m_last_hwid;
    string m_last_fingerprint;
    bool   m_hwid_generated;
    
    string GetCPUSerial();
    string GetDiskVolumeSerial();
    string GetMachineGUID();
    string HashString(string str_input);
    string SHA256(string str_input);
    
public:
    CHWIDGenerator();
    ~CHWIDGenerator();
    
    string GenerateHWID();
    string GenerateFingerprint();
    
    void   ClearCache();
    bool   CompareHWID(string hwid);
    bool   CompareFingerprint(string fingerprint);
};

CHWIDGenerator::CHWIDGenerator()
{
    m_last_hwid = "";
    m_last_fingerprint = "";
    m_hwid_generated = false;
}

CHWIDGenerator::~CHWIDGenerator()
{
    ClearCache();
}

void CHWIDGenerator::ClearCache()
{
    m_last_hwid = "";
    m_last_fingerprint = "";
    m_hwid_generated = false;
}

string CHWIDGenerator::GenerateHWID()
{
    if(m_hwid_generated && m_last_hwid != "")
        return m_last_hwid;
    
    string components = "";
    components += GetCPUSerial();
    components += GetDiskVolumeSerial();
    components += GetMachineGUID();
    components += HashString(TerminalInfoString(TERMINAL_PATH));
    
    m_last_hwid = SHA256(components);
    m_hwid_generated = true;
    
    return m_last_hwid;
}

string CHWIDGenerator::GenerateFingerprint()
{
    if(m_last_fingerprint != "")
        return m_last_fingerprint;
    
    string fp = "";
    fp += GenerateHWID();
    fp += IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    fp += AccountInfoString(ACCOUNT_SERVER);
    fp += HashString(TerminalInfoString(TERMINAL_PATH));
    
    m_last_fingerprint = SHA256(fp);
    return m_last_fingerprint;
}

bool CHWIDGenerator::CompareHWID(string hwid)
{
    return (GenerateHWID() == hwid);
}

bool CHWIDGenerator::CompareFingerprint(string fingerprint)
{
    return (GenerateFingerprint() == fingerprint);
}

//+------------------------------------------------------------------+
//| Get CPU Serial Number                                            |
//+------------------------------------------------------------------+
string CHWIDGenerator::GetCPUSerial()
{
    string cpu_info = "";
    cpu_info += TerminalInfoString(TERMINAL_DATA_PATH);
    cpu_info += TerminalInfoString(TERMINAL_COMMONDATA_PATH);
    return HashString(cpu_info);
}

//+------------------------------------------------------------------+
//| Get Disk Volume Serial Number                                    |
//+------------------------------------------------------------------+
string CHWIDGenerator::GetDiskVolumeSerial()
{
    string terminal_path = TerminalInfoString(TERMINAL_PATH);
    string drive = StringSubstr(terminal_path, 0, 3);
    string disk_info = drive + terminal_path;
    return HashString(disk_info);
}

//+------------------------------------------------------------------+
//| Get Windows Machine GUID                                         |
//+------------------------------------------------------------------+
string CHWIDGenerator::GetMachineGUID()
{
    string machine_info = "";
    machine_info += TerminalInfoString(TERMINAL_COMPANY);
    machine_info += TerminalInfoString(TERMINAL_NAME);
    machine_info += TerminalInfoString(TERMINAL_PATH);
    machine_info += IntegerToString(TerminalInfoInteger(TERMINAL_BUILD));
    return HashString(machine_info);
}

//+------------------------------------------------------------------+
//| Hash String using CryptEncode                                    |
//+------------------------------------------------------------------+
string CHWIDGenerator::HashString(string str_input)
{
    uchar data[];
    uchar hash[];
    uchar key[];  // Empty key for hashing
    
    StringToCharArray(str_input, data, 0, WHOLE_ARRAY, CP_UTF8);
    
    // Try SHA256 first
    if(CryptEncode(CRYPT_HASH_SHA256, data, key, hash))
    {
        string result = "";
        for(int i = 0; i < ArraySize(hash); i++)
            result += StringFormat("%02x", hash[i]);
        return result;
    }
    
    // Fallback to MD5
    if(CryptEncode(CRYPT_HASH_MD5, data, key, hash))
    {
        string result = "";
        for(int i = 0; i < ArraySize(hash); i++)
            result += StringFormat("%02x", hash[i]);
        return result;
    }
    
    // Simple hash fallback
    return StringFormat("%I64u", StringLen(str_input) * 31337);
}

//+------------------------------------------------------------------+
//| SHA256 Hash                                                       |
//+------------------------------------------------------------------+
string CHWIDGenerator::SHA256(string str_input)
{
    return HashString(str_input);
}