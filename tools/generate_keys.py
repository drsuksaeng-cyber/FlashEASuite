#!/usr/bin/env python3
"""
FlashEASuite V2 - RSA Key Generator
Generates 2048-bit RSA key pair for license signing
"""

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

def generate_rsa_keys():
    """Generate RSA 2048-bit key pair"""
    print("🔐 Generating RSA 2048-bit key pair...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    
    # Extract public key
    public_key = private_key.public_key()
    
    # Serialize private key (PEM format, no encryption for simplicity)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    # Serialize public key (PEM format)
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    
    return private_pem, public_pem

if __name__ == "__main__":
    # Generate keys
    private_pem, public_pem = generate_rsa_keys()
    
    # Save private key (SECRET!)
    with open("keys/server_private.pem", "wb") as f:
        f.write(private_pem)
    print("✅ Private key saved: keys/server_private.pem")
    print("   ⚠️  KEEP THIS SECRET! Never share!")
    
    # Save public key
    with open("keys/server_public.pem", "wb") as f:
        f.write(public_pem)
    print("✅ Public key saved: keys/server_public.pem")
    print("   ℹ️  This will be embedded in EA")
    
    print("\n🎉 Key generation complete!")
