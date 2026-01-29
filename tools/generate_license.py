#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Generator
Generates license files with RSA signatures
"""

import json
import base64
from datetime import datetime, timedelta
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend


class LicenseGenerator:
    """Generate and sign license files"""
    
    def __init__(self, private_key_path="keys/server_private.pem"):
        """Initialize with private key"""
        self.private_key_path = private_key_path
        self.private_key = self._load_private_key()
    
    def _load_private_key(self):
        """Load private key from file"""
        with open(self.private_key_path, "rb") as f:
            return serialization.load_pem_private_key(
                f.read(),
                password=None,
                backend=default_backend()
            )
    
    def generate_license(self, 
                        license_id,
                        client_name,
                        client_email,
                        hwid,
                        license_type="reporting",
                        max_slots=5,
                        validity_days=1825):  # 5 years default
        """
        Generate license data
        
        Args:
            license_id: Unique license ID (e.g., "FLASH-2026-AAAA-XXXX")
            client_name: Client name
            client_email: Client email
            hwid: Hardware ID (SHA256)
            license_type: "standalone", "trial", "reporting", "premium"
            max_slots: Maximum MT5 installations
            validity_days: License validity in days
        """
        
        # Calculate dates
        issued_date = datetime.now()
        expiry_date = issued_date + timedelta(days=validity_days)
        
        # Grace period based on license type
        grace_periods = {
            "standalone": 0,
            "trial": 3,
            "reporting": 7,
            "premium": 14
        }
        
        # License data (without signature)
        license_data = {
            "license_id": license_id,
            "product": "FlashEASuite-Pro",
            "license_type": license_type,
            
            "client": {
                "name": client_name,
                "email": client_email
            },
            
            "hardware_binding": {
                "hwid": hwid,
                "max_slots": max_slots,
                "used_slots": []
            },
            
            "features": {
                "strategies": ["Grid", "Spike", "Trend", "Range"],
                "hidden_tpsl": True,
                "trailing_stop": True,
                "multi_symbol": True,
                "max_symbols": 10
            },
            
            "validity": {
                "issued_date": issued_date.strftime("%Y-%m-%d"),
                "expiry_date": expiry_date.strftime("%Y-%m-%d"),
                "grace_days": grace_periods.get(license_type, 7)
            },
            
            "brain_config": {
                "can_receive_policy": True,
                "policy_level": "FULL",
                "feedback_enabled": True
            }
        }
        
        return license_data
    
    def sign_license(self, license_data):
        """
        Sign license data with private key
        
        Args:
            license_data: License dictionary
            
        Returns:
            Signed license dictionary
        """
        
        # Convert to JSON string (without signature)
        license_json = json.dumps(license_data, sort_keys=True)
        
        # Sign with RSA private key
        signature = self.private_key.sign(
            license_json.encode('utf-8'),
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        # Add signature to license data
        license_data["signature"] = base64.b64encode(signature).decode('utf-8')
        
        return license_data
    
    def save_license(self, license_data, output_path="License.key"):
        """Save license to file"""
        with open(output_path, "w") as f:
            json.dump(license_data, f, indent=2)
        
        print(f"✅ License saved: {output_path}")
        return output_path


def main():
    """Example usage"""
    print("=" * 60)
    print("FlashEASuite V2 - License Generator")
    print("=" * 60)
    print()
    
    # Create generator
    generator = LicenseGenerator()
    
    # Generate example license
    print("📝 Generating example license...")
    license_data = generator.generate_license(
        license_id="FLASH-2026-0001-DEMO",
        client_name="Dr. Suksaeng Kukanok",
        client_email="dr.suksaeng@example.com",
        hwid="test-hwid-sha256-hash-here",
        license_type="reporting",
        max_slots=5,
        validity_days=1825  # 5 years
    )
    
    print(f"   License ID: {license_data['license_id']}")
    print(f"   Client: {license_data['client']['name']}")
    print(f"   Type: {license_data['license_type']}")
    print(f"   Valid until: {license_data['validity']['expiry_date']}")
    print()
    
    # Sign license
    print("🔐 Signing license...")
    signed_license = generator.sign_license(license_data)
    print(f"   Signature: {signed_license['signature'][:50]}...")
    print()
    
    # Save to file
    generator.save_license(signed_license, "example_license.key")
    print()
    
    print("🎉 License generation complete!")
    print()
    print("Next steps:")
    print("1. Copy 'example_license.key' to MT5/Files/ directory")
    print("2. Copy 'keys/server_public.pem' to MT5/Files/ directory")
    print("3. Run EA to test license verification")


if __name__ == "__main__":
    main()
