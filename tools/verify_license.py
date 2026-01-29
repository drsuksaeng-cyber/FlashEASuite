#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Verifier
Verifies license signatures (for testing)
"""

import json
import base64
from datetime import datetime
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend
from cryptography.exceptions import InvalidSignature


class LicenseVerifier:
    """Verify license signatures"""
    
    def __init__(self, public_key_path="keys/server_public.pem"):
        """Initialize with public key"""
        self.public_key_path = public_key_path
        self.public_key = self._load_public_key()
    
    def _load_public_key(self):
        """Load public key from file"""
        with open(self.public_key_path, "rb") as f:
            return serialization.load_pem_public_key(
                f.read(),
                backend=default_backend()
            )
    
    def verify_license(self, license_path):
        """
        Verify license file
        
        Args:
            license_path: Path to License.key file
            
        Returns:
            (bool, dict): (is_valid, license_data)
        """
        
        print(f"🔍 Verifying license: {license_path}")
        print()
        
        # Load license
        try:
            with open(license_path, "r") as f:
                license_data = json.load(f)
        except Exception as e:
            print(f"❌ Failed to load license: {e}")
            return False, None
        
        # Extract signature
        if "signature" not in license_data:
            print("❌ No signature found")
            return False, license_data
        
        signature_b64 = license_data["signature"]
        signature = base64.b64decode(signature_b64)
        
        # Remove signature for verification
        license_copy = license_data.copy()
        del license_copy["signature"]
        
        # Convert to JSON (same format as signing)
        license_json = json.dumps(license_copy, sort_keys=True)
        
        # Verify signature
        try:
            self.public_key.verify(
                signature,
                license_json.encode('utf-8'),
                padding.PSS(
                    mgf=padding.MGF1(hashes.SHA256()),
                    salt_length=padding.PSS.MAX_LENGTH
                ),
                hashes.SHA256()
            )
            print("✅ Signature verification: PASSED")
        except InvalidSignature:
            print("❌ Signature verification: FAILED")
            return False, license_data
        
        # Check expiry date
        expiry_str = license_data["validity"]["expiry_date"]
        expiry_date = datetime.strptime(expiry_str, "%Y-%m-%d")
        now = datetime.now()
        
        if now > expiry_date:
            print(f"⚠️  License expired: {expiry_str}")
            return False, license_data
        else:
            days_left = (expiry_date - now).days
            print(f"✅ Expiry check: Valid ({days_left} days remaining)")
        
        # Print license info
        print()
        print("📋 License Details:")
        print(f"   ID: {license_data['license_id']}")
        print(f"   Type: {license_data['license_type']}")
        print(f"   Client: {license_data['client']['name']}")
        print(f"   Email: {license_data['client']['email']}")
        print(f"   HWID: {license_data['hardware_binding']['hwid']}")
        print(f"   Max Slots: {license_data['hardware_binding']['max_slots']}")
        print(f"   Issued: {license_data['validity']['issued_date']}")
        print(f"   Expires: {license_data['validity']['expiry_date']}")
        print(f"   Grace Days: {license_data['validity']['grace_days']}")
        print()
        
        return True, license_data


def main():
    """Test license verification"""
    print("=" * 60)
    print("FlashEASuite V2 - License Verifier")
    print("=" * 60)
    print()
    
    # Create verifier
    verifier = LicenseVerifier()
    
    # Verify example license
    is_valid, license_data = verifier.verify_license("example_license.key")
    
    if is_valid:
        print("🎉 License is VALID!")
    else:
        print("❌ License is INVALID!")
    
    return is_valid


if __name__ == "__main__":
    import sys
    sys.exit(0 if main() else 1)
