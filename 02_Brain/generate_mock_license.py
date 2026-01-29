#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Mock License Generator (Windows Compatible)
สร้าง License.key สำหรับทดสอบ DLL

Version: 1.1 - Windows Compatible
Date: 2026-01-26
"""

import json
import base64
import os
from datetime import datetime, timedelta
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.backends import default_backend

def generate_rsa_keys():
    """สร้าง RSA key pair สำหรับ mock"""
    print("🔑 Generating RSA key pair...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    
    # Get public key
    public_key = private_key.public_key()
    
    # Serialize keys
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    
    print("✅ RSA keys generated")
    return private_key, public_key, private_pem, public_pem

def create_mock_license(private_key):
    """สร้าง mock license"""
    print("\n📝 Creating mock license...")
    
    # License data
    license_data = {
        "license_id": "MOCK-2026-TEST-0001",
        "product": "FlashEASuite-Pro",
        "license_type": "reporting",
        
        "hardware_binding": {
            "hwid": "MOCK_HWID_FOR_TESTING_12345678",
            "max_slots": 5,
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
            "issued_date": datetime.now().strftime("%Y-%m-%d"),
            "expiry_date": (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%d"),
            "grace_days": 7
        },
        
        "brain_config": {
            "can_receive_policy": True,
            "policy_level": "FULL",
            "feedback_enabled": True
        }
    }
    
    # Convert to JSON string (without signature)
    license_json = json.dumps(license_data, indent=2, sort_keys=True)
    
    # Sign the license
    signature = private_key.sign(
        license_json.encode('utf-8'),
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    
    # Add signature to license
    license_data["signature"] = base64.b64encode(signature).decode('utf-8')
    
    print("✅ Mock license created")
    return license_data

def save_files(license_data, public_pem):
    """บันทึกไฟล์ - ใช้ current directory"""
    print("\n💾 Saving files...")
    
    # Get current directory
    current_dir = os.getcwd()
    print(f"📂 Current directory: {current_dir}")
    
    # Save License.key
    license_path = os.path.join(current_dir, 'License.key')
    with open(license_path, 'w', encoding='utf-8') as f:
        json.dump(license_data, f, indent=2)
    print(f"✅ Saved: {license_path}")
    
    # Save public key
    pubkey_path = os.path.join(current_dir, 'server_public.pem')
    with open(pubkey_path, 'wb') as f:
        f.write(public_pem)
    print(f"✅ Saved: {pubkey_path}")
    
    # Save info
    info = f"""
╔═══════════════════════════════════════════════════════════╗
║         Mock License Generated Successfully               ║
╚═══════════════════════════════════════════════════════════╝

📋 License Details:
   ID: {license_data["license_id"]}
   Type: {license_data["license_type"]}
   Valid until: {license_data["validity"]["expiry_date"]}
   Max Slots: {license_data["hardware_binding"]["max_slots"]}

📂 Files Created (in current directory):
   ✅ License.key
   ✅ server_public.pem
   ✅ LICENSE_INFO.txt

🔧 Next Steps:
   1. Copy License.key to MT5:
      {os.environ.get('APPDATA')}\\MetaQuotes\\Terminal\\
      B2C22A9C2EA0D03B7096C9AF7E852052\\MQL5\\Files\\License.key
   
   2. Keep server_public.pem for DLL later

⚠️  Note: This is a MOCK license for testing only!
   HWID check is relaxed for development.
"""
    
    info_path = os.path.join(current_dir, 'LICENSE_INFO.txt')
    with open(info_path, 'w', encoding='utf-8') as f:
        f.write(info)
    print(f"✅ Saved: {info_path}")
    
    print(info)
    
    return license_path

def main():
    """Main function"""
    print("╔═══════════════════════════════════════════════════════════╗")
    print("║      FlashEASuite V2 - Mock License Generator            ║")
    print("║      For Development & Testing Only                       ║")
    print("║      (Windows Compatible Version)                         ║")
    print("╚═══════════════════════════════════════════════════════════╝\n")
    
    # Generate keys
    private_key, public_key, private_pem, public_pem = generate_rsa_keys()
    
    # Create license
    license_data = create_mock_license(private_key)
    
    # Save files
    license_path = save_files(license_data, public_pem)
    
    print("\n✅ Mock license generation completed!")
    print(f"📁 Files saved in: {os.getcwd()}")
    print("\n🚀 Next: Copy License.key to MQL5\\Files\\")

if __name__ == "__main__":
    main()
