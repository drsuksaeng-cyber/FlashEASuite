#pragma once
//+------------------------------------------------------------------+
//| LicenseVerifier.h                                                |
//| FlashEASuite V2 - License Verification                          |
//| Verifies License.key with RSA signature + HWID                  |
//+------------------------------------------------------------------+

#include <string>
#include <vector>
#include "RSAVerifier.h"

//+------------------------------------------------------------------+
//| License Data Structure                                           |
//+------------------------------------------------------------------+
struct LicenseData
{
    std::string license_id;
    std::string product;
    std::string license_type;
    
    // Hardware binding
    std::string hwid;
    int max_slots;
    
    // Features
    std::vector<std::string> strategies;
    bool hidden_tpsl;
    bool trailing_stop;
    bool multi_symbol;
    int max_symbols;
    
    // Validity
    std::string issued_date;
    std::string expiry_date;
    int grace_days;
    
    // Brain config
    bool can_receive_policy;
    std::string policy_level;
    bool feedback_enabled;
    
    // Signature
    std::string signature;
};

//+------------------------------------------------------------------+
//| License Verifier Class                                           |
//+------------------------------------------------------------------+
class LicenseVerifier
{
private:
    RSAVerifier m_rsa_verifier;
    std::string m_public_key_pem;
    LicenseData m_license_data;
    bool m_license_valid;
    
public:
    // Constructor
    LicenseVerifier();
    ~LicenseVerifier();
    
    // Set public key (embedded in DLL)
    void SetPublicKey(const std::string& pem_key);
    
    // Verify license file
    // Returns:
    //   1 = Valid
    //  -1 = File not found
    //  -2 = Invalid JSON
    //  -3 = Invalid signature
    //  -4 = HWID mismatch
    //  -5 = Expired
    //  -6 = No slots available
    int VerifyLicense(const std::wstring& license_path, const std::string& system_hwid);
    
    // Get license data (after successful verification)
    const LicenseData& GetLicenseData() const { return m_license_data; }
    
    // Check if specific feature is allowed
    bool IsStrategyAllowed(const std::string& strategy) const;
    bool IsFeatureEnabled(const std::string& feature) const;
    
    // Get max symbols allowed
    int GetMaxSymbols() const { return m_license_data.max_symbols; }
    
private:
    // Read license file
    bool ReadLicenseFile(const std::wstring& filepath, std::string& json_content);
    
    // Parse JSON license
    bool ParseLicense(const std::string& json_content);
    
    // Verify signature
    bool VerifySignature(const std::string& json_without_signature);
    
    // Check expiry date
    bool CheckExpiry(const std::string& expiry_date);
    
    // Build JSON string without signature (for verification)
    std::string BuildJSONWithoutSignature(const std::string& original_json);
};
