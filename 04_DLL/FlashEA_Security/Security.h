//+------------------------------------------------------------------+
//|                                                      Security.h |
//|                          FlashEASuite V2 - Phase 3               |
//|                          DLL Security Functions Header           |
//+------------------------------------------------------------------+

#ifndef SECURITY_H
#define SECURITY_H

#include <windows.h>
#include "TradingParams.h"

//+------------------------------------------------------------------+
//| Export declarations                                              |
//+------------------------------------------------------------------+

#ifdef __cplusplus
extern "C" {
#endif

// 1. License Verification
__declspec(dllexport) int CheckLicense(const wchar_t* license_path);

// 2. HWID Generation
__declspec(dllexport) void GetHWID(wchar_t* output);

// 3. Trading Parameters Calculation
__declspec(dllexport) int CalculateTradingParams(
    const wchar_t* license_path,
    const char* symbol,
    double account_balance,
    TradingParams* output
);

// 4. Policy Verification
__declspec(dllexport) int VerifyPolicy(
    const char* policy_json,
    const char* public_key
);

// 5. DLL Integrity Check
__declspec(dllexport) int VerifyDLLIntegrity();

#ifdef __cplusplus
}
#endif

#endif // SECURITY_H
