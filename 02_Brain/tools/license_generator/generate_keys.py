#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - RSA Key Pair Generator
Generate 2048-bit RSA keys for license signing

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import os


def generate_rsa_keys(output_dir="keys", key_size=2048):
    """
    Generate RSA key pair for license signing.
    
    Args:
        output_dir: Directory to save keys
        key_size: RSA key size in bits (default: 2048)
    
    Returns:
        tuple: (private_key_path, public_key_path)
    """
    print("=" * 60)
    print("FlashEASuite V2 - RSA Key Generator")
    print("=" * 60)
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\n🔑 Generating {key_size}-bit RSA key pair...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=key_size,
        backend=default_backend()
    )
    
    # Generate public key from private key
    public_key = private_key.public_key()
    
    # Serialize private key (PEM format, no encryption)
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
    
    # Save private key
    private_key_path = os.path.join(output_dir, "server_private.pem")
    with open(private_key_path, "wb") as f:
        f.write(private_pem)
    print(f"✅ Private key saved: {private_key_path}")
    print(f"   ⚠️  KEEP THIS SECRET! Do not share!")
    
    # Save public key
    public_key_path = os.path.join(output_dir, "server_public.pem")
    with open(public_key_path, "wb") as f:
        f.write(public_pem)
    print(f"✅ Public key saved: {public_key_path}")
    print(f"   📤 Share this with EA (embed in code)")
    
    print("\n" + "=" * 60)
    print("✅ RSA Key Pair Generation Complete!")
    print("=" * 60)
    
    return private_key_path, public_key_path


if __name__ == "__main__":
    generate_rsa_keys()
