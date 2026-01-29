//+------------------------------------------------------------------+
//| HWIDGenerator.cpp                                                |
//| FlashEASuite V2 - Hardware ID Generation Implementation         |
//+------------------------------------------------------------------+

#include "HWIDGenerator.h"
#include "RSAVerifier.h"  // For SHA256Hash
#include <Windows.h>
#include <comdef.h>
#include <Wbemidl.h>
#include <sstream>
#include <iomanip>

#pragma comment(lib, "wbemuuid.lib")

//+------------------------------------------------------------------+
//| Generate HWID                                                    |
//+------------------------------------------------------------------+
std::string HWIDGenerator::GenerateHWID()
{
    std::string components = "";
    
    // 1. CPU Serial
    std::string cpu_serial = GetCPUSerial();
    components += cpu_serial;
    components += "|";
    
    // 2. Disk Volume Serial
    std::string disk_serial = GetDiskVolumeSerial();
    components += disk_serial;
    components += "|";
    
    // 3. Machine GUID
    std::string machine_guid = GetMachineGUID();
    components += machine_guid;
    components += "|";
    
    // 4. MT5 Path - for now, use a placeholder
    // In real implementation, pass MT5 path from MQL5
    components += "MT5_PATH_PLACEHOLDER";
    
    // 5. Compute SHA256
    std::string hwid = RSAVerifier::SHA256Hash(components);
    
    return hwid;
}

//+------------------------------------------------------------------+
//| Generate HWID (wstring version)                                 |
//+------------------------------------------------------------------+
std::wstring HWIDGenerator::GenerateHWIDW()
{
    std::string hwid = GenerateHWID();
    return StringToWString(hwid);
}

//+------------------------------------------------------------------+
//| Get CPU Serial Number (via WMI)                                 |
//+------------------------------------------------------------------+
std::string HWIDGenerator::GetCPUSerial()
{
    std::string cpu_serial = "UNKNOWN_CPU";
    
    HRESULT hres;
    
    // Initialize COM
    hres = CoInitializeEx(0, COINIT_MULTITHREADED);
    if (FAILED(hres) && hres != RPC_E_CHANGED_MODE)
    {
        return cpu_serial;
    }
    
    // Initialize security
    hres = CoInitializeSecurity(
        NULL,
        -1,
        NULL,
        NULL,
        RPC_C_AUTHN_LEVEL_DEFAULT,
        RPC_C_IMP_LEVEL_IMPERSONATE,
        NULL,
        EOAC_NONE,
        NULL
    );
    
    if (FAILED(hres) && hres != RPC_E_TOO_LATE)
    {
        CoUninitialize();
        return cpu_serial;
    }
    
    // Obtain WMI locator
    IWbemLocator* pLoc = NULL;
    hres = CoCreateInstance(
        CLSID_WbemLocator,
        0,
        CLSCTX_INPROC_SERVER,
        IID_IWbemLocator,
        (LPVOID*)&pLoc
    );
    
    if (FAILED(hres))
    {
        CoUninitialize();
        return cpu_serial;
    }
    
    // Connect to WMI
    IWbemServices* pSvc = NULL;
    hres = pLoc->ConnectServer(
        _bstr_t(L"ROOT\\CIMV2"),
        NULL,
        NULL,
        0,
        NULL,
        0,
        0,
        &pSvc
    );
    
    if (FAILED(hres))
    {
        pLoc->Release();
        CoUninitialize();
        return cpu_serial;
    }
    
    // Set security levels
    hres = CoSetProxyBlanket(
        pSvc,
        RPC_C_AUTHN_WINNT,
        RPC_C_AUTHZ_NONE,
        NULL,
        RPC_C_AUTHN_LEVEL_CALL,
        RPC_C_IMP_LEVEL_IMPERSONATE,
        NULL,
        EOAC_NONE
    );
    
    if (FAILED(hres))
    {
        pSvc->Release();
        pLoc->Release();
        CoUninitialize();
        return cpu_serial;
    }
    
    // Query for CPU ProcessorId
    IEnumWbemClassObject* pEnumerator = NULL;
    hres = pSvc->ExecQuery(
        bstr_t("WQL"),
        bstr_t("SELECT ProcessorId FROM Win32_Processor"),
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        NULL,
        &pEnumerator
    );
    
    if (FAILED(hres))
    {
        pSvc->Release();
        pLoc->Release();
        CoUninitialize();
        return cpu_serial;
    }
    
    // Get result
    IWbemClassObject* pclsObj = NULL;
    ULONG uReturn = 0;
    
    while (pEnumerator)
    {
        HRESULT hr = pEnumerator->Next(WBEM_INFINITE, 1, &pclsObj, &uReturn);
        
        if (0 == uReturn)
        {
            break;
        }
        
        VARIANT vtProp;
        hr = pclsObj->Get(L"ProcessorId", 0, &vtProp, 0, 0);
        
        if (SUCCEEDED(hr) && vtProp.vt == VT_BSTR)
        {
            cpu_serial = WStringToString(vtProp.bstrVal);
            VariantClear(&vtProp);
            pclsObj->Release();
            break;
        }
        
        VariantClear(&vtProp);
        pclsObj->Release();
    }
    
    // Cleanup
    pSvc->Release();
    pLoc->Release();
    pEnumerator->Release();
    CoUninitialize();
    
    return cpu_serial;
}

//+------------------------------------------------------------------+
//| Get Disk Volume Serial Number                                   |
//+------------------------------------------------------------------+
std::string HWIDGenerator::GetDiskVolumeSerial()
{
    DWORD volumeSerial;
    BOOL result = GetVolumeInformationW(
        L"C:\\",
        NULL,
        0,
        &volumeSerial,
        NULL,
        NULL,
        NULL,
        0
    );
    
    if (!result)
    {
        return "UNKNOWN_DISK";
    }
    
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << volumeSerial;
    
    return ss.str();
}

//+------------------------------------------------------------------+
//| Get Machine GUID from Registry                                  |
//+------------------------------------------------------------------+
std::string HWIDGenerator::GetMachineGUID()
{
    std::string machine_guid = "UNKNOWN_GUID";
    
    HKEY hKey;
    LONG result = RegOpenKeyExW(
        HKEY_LOCAL_MACHINE,
        L"SOFTWARE\\Microsoft\\Cryptography",
        0,
        KEY_READ,
        &hKey
    );
    
    if (result != ERROR_SUCCESS)
    {
        return machine_guid;
    }
    
    wchar_t guid[256];
    DWORD bufferSize = sizeof(guid);
    DWORD dataType;
    
    result = RegQueryValueExW(
        hKey,
        L"MachineGuid",
        NULL,
        &dataType,
        (LPBYTE)guid,
        &bufferSize
    );
    
    RegCloseKey(hKey);
    
    if (result == ERROR_SUCCESS && dataType == REG_SZ)
    {
        machine_guid = WStringToString(guid);
    }
    
    return machine_guid;
}

//+------------------------------------------------------------------+
//| Get MT5 Path Hash                                               |
//+------------------------------------------------------------------+
std::string HWIDGenerator::GetMT5PathHash(const std::string& mt5_path)
{
    if (mt5_path.empty())
    {
        return "UNKNOWN_PATH";
    }
    
    return RSAVerifier::SHA256Hash(mt5_path);
}

//+------------------------------------------------------------------+
//| Convert wstring to string                                       |
//+------------------------------------------------------------------+
std::string HWIDGenerator::WStringToString(const std::wstring& wstr)
{
    if (wstr.empty())
    {
        return std::string();
    }
    
    int size_needed = WideCharToMultiByte(
        CP_UTF8,
        0,
        &wstr[0],
        (int)wstr.size(),
        NULL,
        0,
        NULL,
        NULL
    );
    
    std::string str(size_needed, 0);
    WideCharToMultiByte(
        CP_UTF8,
        0,
        &wstr[0],
        (int)wstr.size(),
        &str[0],
        size_needed,
        NULL,
        NULL
    );
    
    return str;
}

//+------------------------------------------------------------------+
//| Convert string to wstring                                       |
//+------------------------------------------------------------------+
std::wstring HWIDGenerator::StringToWString(const std::string& str)
{
    if (str.empty())
    {
        return std::wstring();
    }
    
    int size_needed = MultiByteToWideChar(
        CP_UTF8,
        0,
        &str[0],
        (int)str.size(),
        NULL,
        0
    );
    
    std::wstring wstr(size_needed, 0);
    MultiByteToWideChar(
        CP_UTF8,
        0,
        &str[0],
        (int)str.size(),
        &wstr[0],
        size_needed
    );
    
    return wstr;
}
