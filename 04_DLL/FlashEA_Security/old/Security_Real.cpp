//+------------------------------------------------------------------+
//| Security.cpp                                                     |
//| FlashEASuite V2 - DLL Security Layer                           |
//| OPTION 2: REAL IMPLEMENTATION                                  |
//+------------------------------------------------------------------+

#include "Security.h"
#include "LicenseVerifier.h"
#include "HWIDGenerator.h"
#include "TradingParams.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <iomanip>

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+

// Embedded Public Key (Generated: 2026-01-26)
const char* g_PublicKeyPEM = R"(-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA29mdr5kcSS3HuUWJEso6
3nxeHpnxN72oS6oFeWQGzQEcOFNxyCMa9JMPlEKmhcc411VjhaNUO7s3p9zEyXxD
i4uqdJ6PyM7SHGd/Xo0PP3wjJL6LVR+8pOh5l14xdPF/ZTgKBEDvpYw89GjBqJYi
xo7+LzYxAMlmEohjT+Q9b0+soO2z96rNfYPezHQ4sVZ4OBeQG7FUKJ5H0sOOOOrO
nv7l12pMOXEGxaxQmbkj7COeaaL9fDi6pddYIUqHqCi4RW0acJeY1fY6SxDrVp3E
rV3RGkexcA9ZsGS7H7/VFnyb8DtSuS49g+y00iQ+9RZ2l+abYl31gmbTmNQg9PFq
bwIDAQAB
-----END PUBLIC KEY-----)";


// License Verifier (singleton)
static LicenseVerifier* g_LicenseVerifier = nullptr;

// Mode flag
static bool g_RealMode = true;  // TRUE = Real implementation

// Debug logging
static void DebugLog(const std::string& message)
{
    std::ofstream log("dll_debug.log", std::ios::app);
    if (log.is_open())
    {
        log << message << std::endl;
        log.close();
    }
}

//+------------------------------------------------------------------+
//| DLL Entry Point                                                  |
//+------------------------------------------------------------------+
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    switch (ul_reason_for_call)
    {
    case DLL_PROCESS_ATTACH:
        DebugLog("=== DLL LOADED (REAL MODE) ===");
        // Initialize license verifier
        g_LicenseVerifier = new LicenseVerifier();
        g_LicenseVerifier->SetPublicKey(g_PublicKeyPEM);
        break;
        
    case DLL_PROCESS_DETACH:
        DebugLog("=== DLL UNLOADED ===");
        // Cleanup
        if (g_LicenseVerifier)
        {
            delete g_LicenseVerifier;
            g_LicenseVerifier = nullptr;
        }
        break;
    }
    return TRUE;
}

//+------------------------------------------------------------------+
//| 1. CheckLicense - Verify License.key                            |
//+------------------------------------------------------------------+
extern "C" __declspec(dllexport)
int CheckLicense(const wchar_t* license_path)
{
    DebugLog("=== CheckLicense Called (REAL MODE) ===");
    
    if (!license_path)
    {
        DebugLog("ERROR: Null license path");
        return -1;
    }
    
    if (!g_LicenseVerifier)
    {
        DebugLog("ERROR: License verifier not initialized");
        return -1;
    }
    
    // Generate system HWID
    std::string system_hwid = HWIDGenerator::GenerateHWID();
    DebugLog("System HWID: " + system_hwid);
    
    // Verify license
    int result = g_LicenseVerifier->VerifyLicense(license_path, system_hwid);
    
    switch (result)
    {
        case 1:
            DebugLog("SUCCESS: License valid!");
            break;
        case -1:
            DebugLog("ERROR: License file not found");
            break;
        case -2:
            DebugLog("ERROR: Invalid JSON");
            break;
        case -3:
            DebugLog("ERROR: Invalid signature");
            break;
        case -4:
            DebugLog("ERROR: HWID mismatch");
            break;
        case -5:
            DebugLog("ERROR: License expired");
            break;
        case -6:
            DebugLog("ERROR: No slots available");
            break;
        default:
            DebugLog("ERROR: Unknown error");
            break;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| 2. GetHWID - Get Hardware ID                                    |
//+------------------------------------------------------------------+
extern "C" __declspec(dllexport)
void GetHWID(wchar_t* output)
{
    DebugLog("=== GetHWID Called (REAL MODE) ===");
    
    if (!output)
    {
        DebugLog("ERROR: Null output buffer");
        return;
    }
    
    // Generate real HWID
    std::wstring hwid = HWIDGenerator::GenerateHWIDW();
    
    wcscpy(output, hwid.c_str());
    
    std::string hwid_str(hwid.begin(), hwid.end());
    DebugLog("Generated HWID: " + hwid_str);
}

//+------------------------------------------------------------------+
//| 3. CalculateTradingParams - Calculate from License              |
//+------------------------------------------------------------------+
extern "C" __declspec(dllexport)
int CalculateTradingParams(
    const wchar_t* license_path,
    const char* symbol,
    double account_balance,
    TradingParams* output)
{
    DebugLog("=== CalculateTradingParams Called (REAL MODE) ===");
    
    if (!license_path || !symbol || !output)
    {
        DebugLog("ERROR: Null parameters");
        return -1;
    }
    
    // First, verify license
    int check = CheckLicense(license_path);
    if (check != 1)
    {
        DebugLog("ERROR: License check failed with code: " + std::to_string(check));
        return check;
    }
    
    // Get license data
    const LicenseData& license = g_LicenseVerifier->GetLicenseData();
    
    // Log license info
    DebugLog("License ID: " + license.license_id);
    DebugLog("Product: " + license.product);
    DebugLog("Max Symbols: " + std::to_string(license.max_symbols));
    
    // Calculate trading parameters based on license
    
    // 1. Lot Size (2% risk)
    double risk_percent = 0.02;  // 2%
    double risk_amount = account_balance * risk_percent;
    output->lot_size = 0.01;  // Minimum for safety
    if (account_balance >= 1000.0)
    {
        output->lot_size = risk_amount / 1000.0;  // Simplified calculation
    }
    
    // Apply license limits
    if (output->lot_size > 1.0) output->lot_size = 1.0;  // Cap at 1.0
    
    // 2. Grid Step (from license features or default)
    output->grid_step = 50.0;  // Default 50 points
    if (std::string(symbol).find("JPY") != std::string::npos)
    {
        output->grid_step = 500.0;  // JPY pairs need larger step
    }
    else if (std::string(symbol) == "XAUUSD")
    {
        output->grid_step = 100.0;  // Gold
    }
    
    // 3. Max Orders (from license)
    output->max_orders = 10;  // Default
    // In real implementation, read from license.features
    
    // 4. TP/SL Points
    output->tp_points = output->grid_step * 2.0;
    output->sl_points = output->grid_step * 1.0;
    
    // 5. Checksum (simple for now)
    output->checksum = static_cast<uint32_t>(
        output->lot_size * 100 +
        output->grid_step +
        output->max_orders * 1000
    );
    
    DebugLog("Calculated params:");
    DebugLog("  Lot: " + std::to_string(output->lot_size));
    DebugLog("  Grid Step: " + std::to_string(output->grid_step));
    DebugLog("  Max Orders: " + std::to_string(output->max_orders));
    DebugLog("  TP: " + std::to_string(output->tp_points));
    DebugLog("  SL: " + std::to_string(output->sl_points));
    
    return 1;  // SUCCESS
}

//+------------------------------------------------------------------+
//| 4. VerifyPolicy - Verify Policy Signature                       |
//+------------------------------------------------------------------+
extern "C" __declspec(dllexport)
int VerifyPolicy(const char* policy_json, const char* public_key)
{
    DebugLog("=== VerifyPolicy Called (REAL MODE) ===");
    
    if (!policy_json || !public_key)
    {
        DebugLog("ERROR: Null parameters");
        return 0;
    }
    
    // For now, use the embedded public key
    // In real implementation, parse policy JSON and verify signature
    
    DebugLog("Policy verification not yet fully implemented");
    DebugLog("Accepting policy (TODO: Implement RSA verification)");
    
    return 1;  // Temporary - accept all
}

//+------------------------------------------------------------------+
//| 5. VerifyDLLIntegrity - Self-checksum Verification              |
//+------------------------------------------------------------------+
extern "C" __declspec(dllexport)
int VerifyDLLIntegrity()
{
    DebugLog("=== VerifyDLLIntegrity Called (REAL MODE) ===");
    
    // For now, always pass
    // In real implementation:
    // 1. Get DLL file path
    // 2. Calculate SHA256 of DLL
    // 3. Compare with hardcoded hash
    
    DebugLog("DLL integrity check not yet fully implemented");
    DebugLog("Accepting (TODO: Implement checksum verification)");
    
    return 1;  // Temporary - always pass
}
