#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Signer
Sign license JSON with RSA private key

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend
import json
import base64


def load_private_key(private_key_path):
    """
    Load RSA private key from PEM file.
    
    Args:
        private_key_path: Path to private key file
    
    Returns:
        RSAPrivateKey object
    """
    with open(private_key_path, "rb") as f:
        private_key = serialization.load_pem_private_key(
            f.read(),
            password=None,
            backend=default_backend()
        )
    return private_key


def sign_license(license_dict, private_key_path):
    """
    Sign license dictionary with RSA private key.
    
    Args:
        license_dict: License data as dictionary
        private_key_path: Path to private key
    
    Returns:
        str: Base64-encoded signature
    """
    # Load private key
    private_key = load_private_key(private_key_path)
    
    # Create canonical JSON (sorted keys, no whitespace)
    # Remove 'signature' field if exists
    license_copy = {k: v for k, v in license_dict.items() if k != 'signature'}
    canonical_json = json.dumps(license_copy, sort_keys=True, separators=(',', ':'))
    
    # Sign
    signature = private_key.sign(
        canonical_json.encode('utf-8'),
        padding.PSS(
            mgf=padding.MGF1(hashes.SHA256()),
            salt_length=padding.PSS.MAX_LENGTH
        ),
        hashes.SHA256()
    )
    
    # Encode to Base64
    signature_b64 = base64.b64encode(signature).decode('utf-8')
    
    return signature_b64


def create_signed_license(license_dict, private_key_path):
    """
    Create license with signature.
    
    Args:
        license_dict: License data as dictionary
        private_key_path: Path to private key
    
    Returns:
        dict: License with signature field
    """
    # Sign license
    signature = sign_license(license_dict, private_key_path)
    
    # Add signature to license
    license_with_sig = license_dict.copy()
    license_with_sig['signature'] = signature
    
    return license_with_sig


if __name__ == "__main__":
    # Test signing
    print("Testing license signing...")
    
    test_license = {
        "license_id": "FLASH-2026-TEST-0001",
        "product": "FlashEASuite-Pro",
        "license_type": "trial"
    }
    
    try:
        sig = sign_license(test_license, "keys/server_private.pem")
        print(f"✅ Signature generated: {sig[:50]}...")
        print(f"   Signature length: {len(sig)} chars")
    except Exception as e:
        print(f"❌ Error: {e}")
