//+------------------------------------------------------------------+
//|                                    SecurityHelpers.cpp            |
//|                          FlashEASuite V2 - Phase 3               |
//|                          Helper Functions                        |
//+------------------------------------------------------------------+

#include "Security.h"
#include <Windows.h>
#include <wbemidl.h>
#include <comdef.h>
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace FlashEASecurity {

//+------------------------------------------------------------------+
//| Get CPU Serial Number using WMI                                   |
//+------------------------------------------------------------------+
std::string GetCPUSerial()
{
    try {
        HRESULT hres;
        
        // Initialize COM
        hres = CoInitializeEx(0, COINIT_MULTITHREADED);
        if (FAILED(hres) && hres != RPC_E_CHANGED_MODE) {
            return "CPU_UNKNOWN";
        }
        
        // Set security
        hres = CoInitializeSecurity(
            NULL, -1, NULL, NULL,
            RPC_C_AUTHN_LEVEL_DEFAULT,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            NULL, EOAC_NONE, NULL
        );
        
        // Connect to WMI
        IWbemLocator* pLoc = NULL;
        hres = CoCreateInstance(
            CLSID_WbemLocator, 0,
            CLSCTX_INPROC_SERVER,
            IID_IWbemLocator, (LPVOID*)&pLoc
        );
        
        if (FAILED(hres)) {
            CoUninitialize();
            return "CPU_ERROR";
        }
        
        IWbemServices* pSvc = NULL;
        hres = pLoc->ConnectServer(
            _bstr_t(L"ROOT\\CIMV2"),
            NULL, NULL, 0, NULL, 0, 0, &pSvc
        );
        
        if (FAILED(hres)) {
            pLoc->Release();
            CoUninitialize();
            return "CPU_ERROR";
        }
        
        // Set security on proxy
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
        
        // Query for CPU ProcessorId
        IEnumWbemClassObject* pEnumerator = NULL;
        hres = pSvc->ExecQuery(
            bstr_t("WQL"),
            bstr_t("SELECT ProcessorId FROM Win32_Processor"),
            WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
            NULL,
            &pEnumerator
        );
        
        if (FAILED(hres)) {
            pSvc->Release();
            pLoc->Release();
            CoUninitialize();
            return "CPU_ERROR";
        }
        
        // Get result
        IWbemClassObject* pclsObj = NULL;
        ULONG uReturn = 0;
        std::string cpu_id = "CPU_UNKNOWN";
        
        if (pEnumerator) {
            HRESULT hr = pEnumerator->Next(WBEM_INFINITE, 1, &pclsObj, &uReturn);
            
            if (uReturn > 0) {
                VARIANT vtProp;
                hr = pclsObj->Get(L"ProcessorId", 0, &vtProp, 0, 0);
                
                if (vtProp.vt == VT_BSTR) {
                    _bstr_t bstr(vtProp.bstrVal);
                    cpu_id = (char*)bstr;
                }
                
                VariantClear(&vtProp);
                pclsObj->Release();
            }
        }
        
        // Cleanup
        pEnumerator->Release();
        pSvc->Release();
        pLoc->Release();
        
        return cpu_id;
        
    } catch (...) {
        return "CPU_EXCEPTION";
    }
}

//+------------------------------------------------------------------+
//| Get Disk Volume Serial Number                                     |
//+------------------------------------------------------------------+
std::string GetDiskVolumeSerial()
{
    try {
        DWORD volumeSerialNumber = 0;
        BOOL result = GetVolumeInformationW(
            L"C:\\",
            NULL, 0,
            &volumeSerialNumber,
            NULL, NULL, NULL, 0
        );
        
        if (!result) {
            return "DISK_UNKNOWN";
        }
        
        std::stringstream ss;
        ss << std::hex << std::uppercase << volumeSerialNumber;
        return ss.str();
        
    } catch (...) {
        return "DISK_ERROR";
    }
}

//+------------------------------------------------------------------+
//| Get Windows Machine GUID from Registry                           |
//+------------------------------------------------------------------+
std::string GetMachineGUID()
{
    try {
        HKEY hKey;
        LONG result = RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            L"SOFTWARE\\Microsoft\\Cryptography",
            0,
            KEY_READ | KEY_WOW64_64KEY,
            &hKey
        );
        
        if (result != ERROR_SUCCESS) {
            return "GUID_ERROR";
        }
        
        wchar_t guid[256] = {0};
        DWORD size = sizeof(guid);
        DWORD type = REG_SZ;
        
        result = RegQueryValueExW(
            hKey,
            L"MachineGuid",
            NULL,
            &type,
            (LPBYTE)guid,
            &size
        );
        
        RegCloseKey(hKey);
        
        if (result != ERROR_SUCCESS) {
            return "GUID_ERROR";
        }
        
        std::wstring guid_ws(guid);
        std::string guid_str(guid_ws.begin(), guid_ws.end());
        
        return guid_str;
        
    } catch (...) {
        return "GUID_EXCEPTION";
    }
}

//+------------------------------------------------------------------+
//| Get MT5 Installation Path Hash                                    |
//+------------------------------------------------------------------+
std::string GetMT5PathHash()
{
    try {
        // Try to find MT5 installation path
        HKEY hKey;
        LONG result = RegOpenKeyExW(
            HKEY_CURRENT_USER,
            L"Software\\MetaQuotes\\Terminal",
            0,
            KEY_READ,
            &hKey
        );
        
        if (result != ERROR_SUCCESS) {
            return "MT5_NOT_FOUND";
        }
        
        // For simplicity, just return a fixed string
        // In production, enumerate subkeys and get actual path
        RegCloseKey(hKey);
        
        return "MT5_PATH_HASH";
        
    } catch (...) {
        return "MT5_ERROR";
    }
}

//+------------------------------------------------------------------+
//| Simple SHA256 implementation (stub - requires OpenSSL)           |
//+------------------------------------------------------------------+
std::string SHA256(const std::string& data)
{
    // TODO: Replace with real SHA256 using OpenSSL
    // For now, use simple hash for testing
    
    unsigned long hash = 5381;
    for (char c : data) {
        hash = ((hash << 5) + hash) + c;
    }
    
    std::stringstream ss;
    ss << std::hex << std::setw(16) << std::setfill('0') << hash;
    return ss.str();
    
    /* Production code with OpenSSL:
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, data.c_str(), data.length());
    SHA256_Final(hash, &sha256);
    
    std::stringstream ss;
    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        ss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    }
    return ss.str();
    */
}

//+------------------------------------------------------------------+
//| CRC32 Checksum                                                    |
//+------------------------------------------------------------------+
uint32_t CRC32(const unsigned char* data, size_t length)
{
    uint32_t crc = 0xFFFFFFFF;
    
    static uint32_t crc_table[256];
    static bool table_initialized = false;
    
    // Initialize table once
    if (!table_initialized) {
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t c = i;
            for (int j = 0; j < 8; j++) {
                c = (c & 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
            }
            crc_table[i] = c;
        }
        table_initialized = true;
    }
    
    // Calculate CRC32
    for (size_t i = 0; i < length; i++) {
        crc = crc_table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    
    return crc ^ 0xFFFFFFFF;
}

//+------------------------------------------------------------------+
//| Parse License JSON (simplified)                                  |
//+------------------------------------------------------------------+
bool ParseLicenseJSON(const std::string& json_content, 
                      std::string& license_id,
                      std::string& hwid, 
                      std::string& expiry_date)
{
    // TODO: Use proper JSON parser (RapidJSON or similar)
    // For now, simple string search
    
    try {
        // Find license_id
        size_t pos = json_content.find("\"license_id\"");
        if (pos != std::string::npos) {
            size_t start = json_content.find("\"", pos + 13);
            size_t end = json_content.find("\"", start + 1);
            license_id = json_content.substr(start + 1, end - start - 1);
        }
        
        // Find hwid (in hardware_binding section)
        pos = json_content.find("\"hwid\"");
        if (pos != std::string::npos) {
            size_t start = json_content.find("\"", pos + 7);
            size_t end = json_content.find("\"", start + 1);
            hwid = json_content.substr(start + 1, end - start - 1);
        }
        
        // Find expiry_date
        pos = json_content.find("\"expiry_date\"");
        if (pos != std::string::npos) {
            size_t start = json_content.find("\"", pos + 14);
            size_t end = json_content.find("\"", start + 1);
            expiry_date = json_content.substr(start + 1, end - start - 1);
        }
        
        return !license_id.empty() && !hwid.empty();
        
    } catch (...) {
        return false;
    }
}

//+------------------------------------------------------------------+
//| Verify RSA Signature (stub - requires OpenSSL)                   |
//+------------------------------------------------------------------+
bool VerifyRSASignature(const std::string& data, 
                        const std::string& signature,
                        const std::string& public_key)
{
    // TODO: Implement with OpenSSL
    // For Phase 3 initial version, return true
    return true;
    
    /* Production code with OpenSSL:
    BIO* bio = BIO_new_mem_buf(public_key.c_str(), -1);
    RSA* rsa = PEM_read_bio_RSA_PUBKEY(bio, NULL, NULL, NULL);
    BIO_free(bio);
    
    if (!rsa) return false;
    
    // Decode base64 signature
    // Verify signature
    // ...
    
    RSA_free(rsa);
    return verified;
    */
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on balance                              |
//+------------------------------------------------------------------+
double CalculateLotSize(const std::string& symbol, double balance)
{
    // Risk 1% per trade
    double risk_percent = 0.01;
    double risk_amount = balance * risk_percent;
    
    // Base lot calculation
    if (symbol.find("USD") != std::string::npos) {
        // Forex: $10 per 0.01 lot (rough estimate)
        return (std::max)(0.01, risk_amount / 100.0);
    } else if (symbol == "XAUUSD") {
        // Gold: Higher value per lot
        return (std::max)(0.01, risk_amount / 500.0);
    }
    
    return 0.01; // Minimum lot
}

//+------------------------------------------------------------------+
//| Calculate Grid Step based on balance                             |
//+------------------------------------------------------------------+
double CalculateGridStep(const std::string& symbol, double balance)
{
    if (symbol.find("JPY") != std::string::npos) {
        // JPY pairs: larger pip values
        return balance > 10000 ? 500.0 : 300.0;
    } else if (symbol == "XAUUSD") {
        // Gold: wider steps
        return balance > 10000 ? 100.0 : 50.0;
    } else {
        // Standard forex
        return balance > 10000 ? 300.0 : 200.0;
    }
}

//+------------------------------------------------------------------+
//| Calculate Maximum Orders based on balance                        |
//+------------------------------------------------------------------+
int CalculateMaxOrders(double balance)
{
    if (balance < 1000) return 3;
    if (balance < 5000) return 5;
    if (balance < 10000) return 7;
    return 10;
}

//+------------------------------------------------------------------+
//| Get License Secret (hardcoded in DLL)                            |
//+------------------------------------------------------------------+
const char* GetLicenseSecret()
{
    // This secret is hardcoded in DLL
    // Used for challenge-response verification
    return "FlashEA_Secret_Key_2026_Phase3";
}

} // namespace FlashEASecurity
