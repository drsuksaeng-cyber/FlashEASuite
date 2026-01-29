#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fix license.key encoding issue
Regenerate with proper encoding for MQL5
"""

import json
import sys
import os

def regenerate_license():
    """Regenerate license with correct encoding"""
    
    print("=" * 60)
    print("License Encoding Fix")
    print("=" * 60)
    print()
    
    # License data (same as before)
    license_data = {
        "license_id": "FLASH-2026-0001-DEMO",
        "product": "FlashEASuite-Pro",
        "license_type": "reporting",
        
        "client": {
            "name": "Dr. Suksaeng Kukanok",
            "email": "dr.suksaeng@example.com"
        },
        
        "hardware_binding": {
            "hwid": "test-hwid-sha256-hash-here",
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
            "issued_date": "2026-01-28",
            "expiry_date": "2031-01-27",
            "grace_days": 7
        },
        
        "brain_config": {
            "can_receive_policy": True,
            "policy_level": "FULL",
            "feedback_enabled": True
        },
        
        "signature": "En3Ha6NbjkR7bgyP+5dl65VlJKMSBP/xlQ6hQcHAPhJRxVuh68ZjN/qQr1o/aIn5wHzpGXWN/mJ0IYna5riU57484m/fsGLKOoK/mVOb"
    }
    
    # Save with UTF-8 encoding (no BOM)
    print("Saving license.key (UTF-8, no BOM)...")
    with open("license.key", "w", encoding="utf-8") as f:
        json.dump(license_data, f, indent=2, ensure_ascii=False)
    
    print("✅ Saved: license.key")
    
    # Also save as ANSI
    print()
    print("Saving license_ansi.key (ANSI encoding)...")
    try:
        with open("license_ansi.key", "w", encoding="cp1252") as f:
            json.dump(license_data, f, indent=2, ensure_ascii=True)
        print("✅ Saved: license_ansi.key")
    except Exception as e:
        print(f"⚠️  Could not save ANSI version: {e}")
    
    # Verify
    print()
    print("Verifying files...")
    
    # Check UTF-8
    with open("license.key", "r", encoding="utf-8") as f:
        content = f.read()
        if "license_id" in content:
            print("✅ license.key is readable (UTF-8)")
        else:
            print("❌ license.key has issues")
    
    # Check ANSI
    if os.path.exists("license_ansi.key"):
        with open("license_ansi.key", "r", encoding="cp1252") as f:
            content = f.read()
            if "license_id" in content:
                print("✅ license_ansi.key is readable (ANSI)")
            else:
                print("❌ license_ansi.key has issues")
    
    print()
    print("=" * 60)
    print("Next steps:")
    print("1. Copy license.key to MT5/Files/")
    print("   OR")
    print("2. Copy license_ansi.key to MT5/Files/license.key")
    print()
    print("Then run TestPhase1_LicenseVerify_v4 in MT5")
    print("=" * 60)


if __name__ == "__main__":
    regenerate_license()
