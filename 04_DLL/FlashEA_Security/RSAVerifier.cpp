//+------------------------------------------------------------------+
//| RSAVerifier.cpp                                                  |
//| FlashEASuite V2 - RSA Signature Verification Implementation     |
//+------------------------------------------------------------------+

#include "RSAVerifier.h"
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <openssl/sha.h>
#include <openssl/err.h>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <cstring>

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
RSAVerifier::RSAVerifier() : m_rsa_key(nullptr)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
RSAVerifier::~RSAVerifier()
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Load public key from PEM string                                  |
//+------------------------------------------------------------------+
bool RSAVerifier::LoadPublicKey(const std::string& pem_key)
{
    // Cleanup existing key
    Cleanup();
    
    // Create BIO from string
    BIO* bio = BIO_new_mem_buf(pem_key.c_str(), -1);
    if (!bio)
    {
        return false;
    }
    
    // Read public key
    EVP_PKEY* pkey = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
    BIO_free(bio);
    
    if (!pkey)
    {
        return false;
    }
    
    m_rsa_key = pkey;
    m_public_key_pem = pem_key;
    
    return true;
}

//+------------------------------------------------------------------+
//| Load public key from file                                        |
//+------------------------------------------------------------------+
bool RSAVerifier::LoadPublicKeyFromFile(const std::string& filepath)
{
    // Read file
    std::ifstream file(filepath, std::ios::binary);
    if (!file.is_open())
    {
        return false;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    file.close();
    
    // Load from string
    return LoadPublicKey(buffer.str());
}

//+------------------------------------------------------------------+
//| Verify RSA signature (Base64-encoded)                           |
//+------------------------------------------------------------------+
bool RSAVerifier::VerifySignature(
    const std::string& data,
    const std::string& signature_base64)
{
    if (!m_rsa_key)
    {
        return false;
    }
    
    // Decode Base64 signature
    std::vector<unsigned char> signature = Base64Decode(signature_base64);
    if (signature.empty())
    {
        return false;
    }
    
    // Verify binary signature
    return VerifySignatureBinary(data, signature);
}

//+------------------------------------------------------------------+
//| Verify RSA signature (binary)                                   |
//+------------------------------------------------------------------+
bool RSAVerifier::VerifySignatureBinary(
    const std::string& data,
    const std::vector<unsigned char>& signature)
{
    if (!m_rsa_key)
    {
        return false;
    }
    
    EVP_PKEY* pkey = static_cast<EVP_PKEY*>(m_rsa_key);
    
    // Create verification context
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx)
    {
        return false;
    }
    
    bool result = false;
    
    // Initialize verification
    if (EVP_DigestVerifyInit(ctx, nullptr, EVP_sha256(), nullptr, pkey) == 1)
    {
        // Update with data
        if (EVP_DigestVerifyUpdate(ctx, data.c_str(), data.length()) == 1)
        {
            // Verify signature
            int verify_result = EVP_DigestVerifyFinal(
                ctx,
                signature.data(),
                signature.size()
            );
            
            result = (verify_result == 1);
        }
    }
    
    EVP_MD_CTX_free(ctx);
    
    return result;
}

//+------------------------------------------------------------------+
//| Base64 Decode                                                    |
//+------------------------------------------------------------------+
std::vector<unsigned char> RSAVerifier::Base64Decode(const std::string& encoded)
{
    std::vector<unsigned char> result;
    
    BIO* bio = BIO_new_mem_buf(encoded.c_str(), -1);
    BIO* b64 = BIO_new(BIO_f_base64());
    
    if (!bio || !b64)
    {
        if (bio) BIO_free(bio);
        if (b64) BIO_free(b64);
        return result;
    }
    
    bio = BIO_push(b64, bio);
    BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
    
    // Allocate buffer
    unsigned char buffer[4096];
    int decoded_length = BIO_read(bio, buffer, sizeof(buffer));
    
    if (decoded_length > 0)
    {
        result.assign(buffer, buffer + decoded_length);
    }
    
    BIO_free_all(bio);
    
    return result;
}

//+------------------------------------------------------------------+
//| Base64 Encode                                                    |
//+------------------------------------------------------------------+
std::string RSAVerifier::Base64Encode(const std::vector<unsigned char>& data)
{
    BIO* bio = BIO_new(BIO_s_mem());
    BIO* b64 = BIO_new(BIO_f_base64());
    
    if (!bio || !b64)
    {
        if (bio) BIO_free(bio);
        if (b64) BIO_free(b64);
        return "";
    }
    
    bio = BIO_push(b64, bio);
    BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
    
    BIO_write(bio, data.data(), static_cast<int>(data.size()));
    BIO_flush(bio);
    
    BUF_MEM* buffer_ptr;
    BIO_get_mem_ptr(bio, &buffer_ptr);
    
    std::string result(buffer_ptr->data, buffer_ptr->length);
    
    BIO_free_all(bio);
    
    return result;
}

//+------------------------------------------------------------------+
//| SHA256 Hash                                                      |
//+------------------------------------------------------------------+
std::string RSAVerifier::SHA256Hash(const std::string& data)
{
    unsigned char hash[SHA256_DIGEST_LENGTH];
    
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, data.c_str(), data.length());
    SHA256_Final(hash, &sha256);
    
    // Convert to hex string
    std::stringstream ss;
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
    {
        ss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(hash[i]);
    }
    
    return ss.str();
}

//+------------------------------------------------------------------+
//| Cleanup OpenSSL resources                                        |
//+------------------------------------------------------------------+
void RSAVerifier::Cleanup()
{
    if (m_rsa_key)
    {
        EVP_PKEY_free(static_cast<EVP_PKEY*>(m_rsa_key));
        m_rsa_key = nullptr;
    }
    
    m_public_key_pem.clear();
}
