//+------------------------------------------------------------------+
//| LicenseVerifier.cpp                                              |
//| FlashEASuite V2 - License Verification Implementation           |
//+------------------------------------------------------------------+

#include "LicenseVerifier.h"
#include <rapidjson/document.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>
#include <fstream>
#include <sstream>
#include <ctime>
#include <iomanip>

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
LicenseVerifier::LicenseVerifier() : m_license_valid(false)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
LicenseVerifier::~LicenseVerifier()
{
}

//+------------------------------------------------------------------+
//| Set public key                                                    |
//+------------------------------------------------------------------+
void LicenseVerifier::SetPublicKey(const std::string& pem_key)
{
    m_public_key_pem = pem_key;
    m_rsa_verifier.LoadPublicKey(pem_key);
}

//+------------------------------------------------------------------+
//| Verify license file                                              |
//+------------------------------------------------------------------+
int LicenseVerifier::VerifyLicense(const std::wstring& license_path, const std::string& system_hwid)
{
    m_license_valid = false;
    
    // 1. Read license file
    std::string json_content;
    if (!ReadLicenseFile(license_path, json_content))
    {
        return -1;  // File not found
    }
    
    // 2. Parse JSON
    if (!ParseLicense(json_content))
    {
        return -2;  // Invalid JSON
    }
    
    // 3. Verify signature
    std::string json_without_sig = BuildJSONWithoutSignature(json_content);
    if (!VerifySignature(json_without_sig))
    {
        return -3;  // Invalid signature
    }
    
    // 4. Check HWID match
    if (m_license_data.hwid != system_hwid)
    {
        return -4;  // HWID mismatch
    }
    
    // 5. Check expiry
    if (!CheckExpiry(m_license_data.expiry_date))
    {
        return -5;  // Expired
    }
    
    // 6. Check slots (basic check - in real system, would check fingerprints)
    // For now, just verify max_slots > 0
    if (m_license_data.max_slots <= 0)
    {
        return -6;  // No slots
    }
    
    m_license_valid = true;
    return 1;  // Valid!
}

//+------------------------------------------------------------------+
//| Read license file                                                |
//+------------------------------------------------------------------+
bool LicenseVerifier::ReadLicenseFile(const std::wstring& filepath, std::string& json_content)
{
    // Convert wstring to string for ifstream
    std::string filepath_str(filepath.begin(), filepath.end());
    
    std::ifstream file(filepath_str, std::ios::binary);
    if (!file.is_open())
    {
        return false;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    file.close();
    
    json_content = buffer.str();
    return !json_content.empty();
}

//+------------------------------------------------------------------+
//| Parse JSON license                                               |
//+------------------------------------------------------------------+
bool LicenseVerifier::ParseLicense(const std::string& json_content)
{
    rapidjson::Document doc;
    doc.Parse(json_content.c_str());
    
    if (doc.HasParseError() || !doc.IsObject())
    {
        return false;
    }
    
    // Parse license_id
    if (doc.HasMember("license_id") && doc["license_id"].IsString())
    {
        m_license_data.license_id = doc["license_id"].GetString();
    }
    else
    {
        return false;
    }
    
    // Parse product
    if (doc.HasMember("product") && doc["product"].IsString())
    {
        m_license_data.product = doc["product"].GetString();
    }
    
    // Parse license_type
    if (doc.HasMember("license_type") && doc["license_type"].IsString())
    {
        m_license_data.license_type = doc["license_type"].GetString();
    }
    
    // Parse hardware_binding
    if (doc.HasMember("hardware_binding") && doc["hardware_binding"].IsObject())
    {
        const auto& hw = doc["hardware_binding"];
        
        if (hw.HasMember("hwid") && hw["hwid"].IsString())
        {
            m_license_data.hwid = hw["hwid"].GetString();
        }
        else
        {
            return false;  // HWID is required
        }
        
        if (hw.HasMember("max_slots") && hw["max_slots"].IsInt())
        {
            m_license_data.max_slots = hw["max_slots"].GetInt();
        }
        else
        {
            m_license_data.max_slots = 1;  // Default
        }
    }
    else
    {
        return false;  // hardware_binding is required
    }
    
    // Parse features
    if (doc.HasMember("features") && doc["features"].IsObject())
    {
        const auto& features = doc["features"];
        
        // Strategies
        if (features.HasMember("strategies") && features["strategies"].IsArray())
        {
            const auto& strategies_array = features["strategies"];
            for (rapidjson::SizeType i = 0; i < strategies_array.Size(); i++)
            {
                if (strategies_array[i].IsString())
                {
                    m_license_data.strategies.push_back(strategies_array[i].GetString());
                }
            }
        }
        
        // Booleans
        m_license_data.hidden_tpsl = features.HasMember("hidden_tpsl") && 
                                     features["hidden_tpsl"].IsBool() && 
                                     features["hidden_tpsl"].GetBool();
        
        m_license_data.trailing_stop = features.HasMember("trailing_stop") && 
                                       features["trailing_stop"].IsBool() && 
                                       features["trailing_stop"].GetBool();
        
        m_license_data.multi_symbol = features.HasMember("multi_symbol") && 
                                      features["multi_symbol"].IsBool() && 
                                      features["multi_symbol"].GetBool();
        
        // Max symbols
        if (features.HasMember("max_symbols") && features["max_symbols"].IsInt())
        {
            m_license_data.max_symbols = features["max_symbols"].GetInt();
        }
        else
        {
            m_license_data.max_symbols = 1;  // Default
        }
    }
    
    // Parse validity
    if (doc.HasMember("validity") && doc["validity"].IsObject())
    {
        const auto& validity = doc["validity"];
        
        if (validity.HasMember("issued_date") && validity["issued_date"].IsString())
        {
            m_license_data.issued_date = validity["issued_date"].GetString();
        }
        
        if (validity.HasMember("expiry_date") && validity["expiry_date"].IsString())
        {
            m_license_data.expiry_date = validity["expiry_date"].GetString();
        }
        else
        {
            return false;  // expiry_date is required
        }
        
        if (validity.HasMember("grace_days") && validity["grace_days"].IsInt())
        {
            m_license_data.grace_days = validity["grace_days"].GetInt();
        }
        else
        {
            m_license_data.grace_days = 0;
        }
    }
    else
    {
        return false;  // validity is required
    }
    
    // Parse brain_config
    if (doc.HasMember("brain_config") && doc["brain_config"].IsObject())
    {
        const auto& brain = doc["brain_config"];
        
        m_license_data.can_receive_policy = brain.HasMember("can_receive_policy") && 
                                            brain["can_receive_policy"].IsBool() && 
                                            brain["can_receive_policy"].GetBool();
        
        if (brain.HasMember("policy_level") && brain["policy_level"].IsString())
        {
            m_license_data.policy_level = brain["policy_level"].GetString();
        }
        
        m_license_data.feedback_enabled = brain.HasMember("feedback_enabled") && 
                                         brain["feedback_enabled"].IsBool() && 
                                         brain["feedback_enabled"].GetBool();
    }
    
    // Parse signature
    if (doc.HasMember("signature") && doc["signature"].IsString())
    {
        m_license_data.signature = doc["signature"].GetString();
    }
    else
    {
        return false;  // signature is required
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verify signature                                                 |
//+------------------------------------------------------------------+
bool LicenseVerifier::VerifySignature(const std::string& json_without_signature)
{
    if (m_license_data.signature.empty())
    {
        return false;
    }
    
    return m_rsa_verifier.VerifySignature(json_without_signature, m_license_data.signature);
}

//+------------------------------------------------------------------+
//| Check expiry date                                                |
//+------------------------------------------------------------------+
bool LicenseVerifier::CheckExpiry(const std::string& expiry_date)
{
    // Parse expiry date (format: YYYY-MM-DD)
    if (expiry_date.length() < 10)
    {
        return false;
    }
    
    int year, month, day;
    if (sscanf(expiry_date.c_str(), "%d-%d-%d", &year, &month, &day) != 3)
    {
        return false;
    }
    
    // Get current time
    time_t now = time(nullptr);
    struct tm* current_time = localtime(&now);
    
    // Create expiry time
    struct tm expiry_time = {};
    expiry_time.tm_year = year - 1900;
    expiry_time.tm_mon = month - 1;
    expiry_time.tm_mday = day;
    expiry_time.tm_hour = 23;
    expiry_time.tm_min = 59;
    expiry_time.tm_sec = 59;
    
    time_t expiry_timestamp = mktime(&expiry_time);
    
    // Compare
    return (now <= expiry_timestamp);
}

//+------------------------------------------------------------------+
//| Build JSON without signature                                    |
//+------------------------------------------------------------------+
std::string LicenseVerifier::BuildJSONWithoutSignature(const std::string& original_json)
{
    // Parse original JSON
    rapidjson::Document doc;
    doc.Parse(original_json.c_str());
    
    if (doc.HasParseError() || !doc.IsObject())
    {
        return "";
    }
    
    // Remove signature field
    if (doc.HasMember("signature"))
    {
        doc.RemoveMember("signature");
    }
    
    // Serialize back to JSON
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    doc.Accept(writer);
    
    return buffer.GetString();
}

//+------------------------------------------------------------------+
//| Check if strategy is allowed                                    |
//+------------------------------------------------------------------+
bool LicenseVerifier::IsStrategyAllowed(const std::string& strategy) const
{
    for (const auto& allowed : m_license_data.strategies)
    {
        if (allowed == strategy)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if feature is enabled                                     |
//+------------------------------------------------------------------+
bool LicenseVerifier::IsFeatureEnabled(const std::string& feature) const
{
    if (feature == "hidden_tpsl") return m_license_data.hidden_tpsl;
    if (feature == "trailing_stop") return m_license_data.trailing_stop;
    if (feature == "multi_symbol") return m_license_data.multi_symbol;
    
    return false;
}
