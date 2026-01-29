#pragma once
//+------------------------------------------------------------------+
//| RSAVerifier.h                                                    |
//| FlashEASuite V2 - RSA Signature Verification                    |
//| Uses OpenSSL for RSA-2048 signature verification                |
//+------------------------------------------------------------------+

#include <string>
#include <vector>

//+------------------------------------------------------------------+
//| RSA Verifier Class                                               |
//+------------------------------------------------------------------+
class RSAVerifier
{
private:
    std::string m_public_key_pem;  // PEM format public key
    void* m_rsa_key;               // EVP_PKEY* (OpenSSL)
    
public:
    // Constructor / Destructor
    RSAVerifier();
    ~RSAVerifier();
    
    // Load public key from PEM string
    bool LoadPublicKey(const std::string& pem_key);
    
    // Load public key from file
    bool LoadPublicKeyFromFile(const std::string& filepath);
    
    // Verify RSA signature
    // data: Original data that was signed
    // signature: Base64-encoded signature
    // Returns: true if valid, false otherwise
    bool VerifySignature(
        const std::string& data,
        const std::string& signature_base64
    );
    
    // Verify RSA signature (binary signature)
    bool VerifySignatureBinary(
        const std::string& data,
        const std::vector<unsigned char>& signature
    );
    
    // Utility: Base64 decode
    static std::vector<unsigned char> Base64Decode(const std::string& encoded);
    
    // Utility: Base64 encode
    static std::string Base64Encode(const std::vector<unsigned char>& data);
    
    // SHA256 hash
    static std::string SHA256Hash(const std::string& data);
    
private:
    // Cleanup OpenSSL resources
    void Cleanup();
};
