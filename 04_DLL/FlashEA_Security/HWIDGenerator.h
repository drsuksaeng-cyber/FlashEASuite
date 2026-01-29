#pragma once
//+------------------------------------------------------------------+
//| HWIDGenerator.h                                                  |
//| FlashEASuite V2 - Hardware ID Generation                        |
//| Generates unique HWID from system hardware                      |
//+------------------------------------------------------------------+

#include <string>

//+------------------------------------------------------------------+
//| HWID Generator Class                                             |
//+------------------------------------------------------------------+
class HWIDGenerator
{
public:
    // Generate HWID
    // Returns: SHA256 hash of hardware components
    static std::string GenerateHWID();
    
    // Generate HWID (wstring version for MQL5 compatibility)
    static std::wstring GenerateHWIDW();
    
private:
    // Get CPU Serial Number (via WMI)
    static std::string GetCPUSerial();
    
    // Get Disk Volume Serial Number
    static std::string GetDiskVolumeSerial();
    
    // Get Machine GUID from Registry
    static std::string GetMachineGUID();
    
    // Get MT5 Installation Path Hash
    // For now, we'll use the path passed from MQL5
    // In future, could try to detect automatically
    static std::string GetMT5PathHash(const std::string& mt5_path);
    
    // Utility: Convert wstring to string
    static std::string WStringToString(const std::wstring& wstr);
    
    // Utility: Convert string to wstring
    static std::wstring StringToWString(const std::string& str);
};
