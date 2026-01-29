#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Verifier
Verify license signature with RSA public key

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend
from cryptography.exceptions import InvalidSignature
import json
import base64


def load_public_key(public_key_path):
    """
    Load RSA public key from PEM file.
    
    Args:
        public_key_path: Path to public key file
    
    Returns:
        RSAPublicKey object
    """
    with open(public_key_path, "rb") as f:
        public_key = serialization.load_pem_public_key(
            f.read(),
            backend=default_backend()
        )
    return public_key


def verify_license(license_dict, public_key_path):
    """
    Verify license signature with RSA public key.
    
    Args:
        license_dict: License data with signature
        public_key_path: Path to public key
    
    Returns:
        bool: True if valid, False otherwise
    """
    try:
        # Extract signature
        if 'signature' not in license_dict:
            print("❌ No signature field in license")
            return False
        
        signature_b64 = license_dict['signature']
        signature = base64.b64decode(signature_b64)
        
        # Load public key
        public_key = load_public_key(public_key_path)
        
        # Create canonical JSON (without signature)
        license_copy = {k: v for k, v in license_dict.items() if k != 'signature'}
        canonical_json = json.dumps(license_copy, sort_keys=True, separators=(',', ':'))
        
        # Verify
        public_key.verify(
            signature,
            canonical_json.encode('utf-8'),
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        return True
        
    except InvalidSignature:
        print("❌ Invalid signature")
        return False
    except Exception as e:
        print(f"❌ Verification error: {e}")
        return False


def verify_license_file(license_file_path, public_key_path):
    """
    Verify license from file.
    
    Args:
        license_file_path: Path to license.key file
        public_key_path: Path to public key
    
    Returns:
        bool: True if valid, False otherwise
    """
    try:
        # Load license
        with open(license_file_path, 'r', encoding='utf-8') as f:
            license_dict = json.load(f)
        
        # Verify
        is_valid = verify_license(license_dict, public_key_path)
        
        if is_valid:
            print(f"✅ License {license_dict.get('license_id', 'UNKNOWN')} is VALID")
            print(f"   Client: {license_dict.get('client_name', 'N/A')}")
            print(f"   Type: {license_dict.get('license_type', 'N/A')}")
            print(f"   Expiry: {license_dict.get('validity', {}).get('expiry_date', 'N/A')}")
        else:
            print(f"❌ License is INVALID or TAMPERED")
        
        return is_valid
        
    except Exception as e:
        print(f"❌ Error reading license file: {e}")
        return False


if __name__ == "__main__":
    import sys
    
    print("=" * 60)
    print("FlashEASuite V2 - License Verifier")
    print("=" * 60)
    
    if len(sys.argv) > 1:
        # Verify specified file
        license_file = sys.argv[1]
        result = verify_license_file(license_file, "keys/server_public.pem")
        sys.exit(0 if result else 1)
    else:
        print("\nUsage: python verify_license.py <license_file.key>")
        print("Example: python verify_license.py licenses/FLASH-2026-0001.key")
