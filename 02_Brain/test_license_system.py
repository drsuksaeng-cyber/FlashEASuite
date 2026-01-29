#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License System Testing Script
Test all components of license generation and verification

Location: 02_Brain/test_license_system.py

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

import os
import sys
import json

# Add tools path
sys.path.insert(0, 'tools/license_generator')

from generate_keys import generate_rsa_keys
from sign_license import sign_license, create_signed_license
from verify_license import verify_license, verify_license_file
from generate_from_csv import create_license_from_row


def test_1_key_generation():
    """Test 1: RSA Key Generation"""
    print("\n" + "=" * 70)
    print("TEST 1: RSA Key Generation")
    print("=" * 70)
    
    try:
        # Check if keys exist
        private_key = "tools/license_generator/keys/server_private.pem"
        public_key = "tools/license_generator/keys/server_public.pem"
        
        if os.path.exists(private_key) and os.path.exists(public_key):
            print("✅ RSA keys already exist")
            print(f"   Private: {private_key}")
            print(f"   Public: {public_key}")
            return True
        else:
            print("❌ Keys not found")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_2_license_creation():
    """Test 2: License Creation"""
    print("\n" + "=" * 70)
    print("TEST 2: License Creation")
    print("=" * 70)
    
    try:
        # Create test license
        test_row = {
            'client_name': 'Test Client',
            'client_email': 'test@example.com',
            'client_phone': '081-111-1111',
            'account_number': '99999999',
            'broker_name': 'TestBroker',
            'license_type': 'trial',
            'product': 'FlashEASuite-Pro',
            'hwid': '',
            'max_slots': '1',
            'issued_date': '2026-01-22',
            'expiry_date': '2026-02-22',
            'strategies': 'Grid',
            'hidden_tpsl': 'true',
            'trailing_stop': 'false',
            'multi_symbol': 'false',
            'max_symbols': '1',
            'notes': 'Test license'
        }
        
        license_dict = create_license_from_row(test_row)
        
        print("✅ License created successfully")
        print(f"   License ID: {license_dict['license_id']}")
        print(f"   Type: {license_dict['license_type']}")
        print(f"   Client: {license_dict['client_info']['name']}")
        
        return license_dict
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return None


def test_3_license_signing(license_dict):
    """Test 3: License Signing"""
    print("\n" + "=" * 70)
    print("TEST 3: License Signing")
    print("=" * 70)
    
    try:
        private_key = "tools/license_generator/keys/server_private.pem"
        signed = create_signed_license(license_dict, private_key)
        
        print("✅ License signed successfully")
        print(f"   Signature length: {len(signed['signature'])} chars")
        print(f"   Signature preview: {signed['signature'][:50]}...")
        
        return signed
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return None


def test_4_license_verification(signed_license):
    """Test 4: License Verification"""
    print("\n" + "=" * 70)
    print("TEST 4: License Verification")
    print("=" * 70)
    
    try:
        public_key = "tools/license_generator/keys/server_public.pem"
        is_valid = verify_license(signed_license, public_key)
        
        if is_valid:
            print("✅ License verification PASSED")
        else:
            print("❌ License verification FAILED")
        
        return is_valid
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_5_tamper_detection(signed_license):
    """Test 5: Tamper Detection"""
    print("\n" + "=" * 70)
    print("TEST 5: Tamper Detection")
    print("=" * 70)
    
    try:
        # Tamper with license
        tampered = signed_license.copy()
        tampered['license_type'] = 'premium'  # Change from trial to premium
        
        public_key = "tools/license_generator/keys/server_public.pem"
        is_valid = verify_license(tampered, public_key)
        
        if not is_valid:
            print("✅ Tamper detection works correctly")
            print("   Modified license was rejected ✅")
        else:
            print("❌ SECURITY ISSUE: Tampered license accepted!")
        
        return not is_valid  # Should be False (tampered license rejected)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_6_csv_generation():
    """Test 6: CSV Batch Generation"""
    print("\n" + "=" * 70)
    print("TEST 6: CSV Batch Generation")
    print("=" * 70)
    
    try:
        csv_file = "tools/license_generator/templates/clients_template.csv"
        licenses_dir = "tools/license_generator/licenses"
        
        # Count generated licenses
        if os.path.exists(licenses_dir):
            license_files = [f for f in os.listdir(licenses_dir) if f.endswith('.key')]
            print(f"✅ Found {len(license_files)} generated licenses")
            
            for lf in license_files[:3]:  # Show first 3
                print(f"   - {lf}")
            
            return len(license_files) > 0
        else:
            print("❌ Licenses directory not found")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_7_file_verification():
    """Test 7: File-based Verification"""
    print("\n" + "=" * 70)
    print("TEST 7: File-based Verification")
    print("=" * 70)
    
    try:
        licenses_dir = "tools/license_generator/licenses"
        public_key = "tools/license_generator/keys/server_public.pem"
        
        if os.path.exists(licenses_dir):
            license_files = [f for f in os.listdir(licenses_dir) if f.endswith('.key')]
            
            if license_files:
                test_file = os.path.join(licenses_dir, license_files[0])
                is_valid = verify_license_file(test_file, public_key)
                
                if is_valid:
                    print("✅ File verification PASSED")
                else:
                    print("❌ File verification FAILED")
                
                return is_valid
            else:
                print("❌ No license files found")
                return False
        else:
            print("❌ Licenses directory not found")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def run_all_tests():
    """Run all tests"""
    print("\n" + "=" * 70)
    print("FlashEASuite V2 - License System Test Suite")
    print("=" * 70)
    
    results = {}
    
    # Test 1: Key Generation
    results['key_generation'] = test_1_key_generation()
    
    # Test 2: License Creation
    license_dict = test_2_license_creation()
    results['license_creation'] = license_dict is not None
    
    if license_dict:
        # Test 3: License Signing
        signed_license = test_3_license_signing(license_dict)
        results['license_signing'] = signed_license is not None
        
        if signed_license:
            # Test 4: License Verification
            results['license_verification'] = test_4_license_verification(signed_license)
            
            # Test 5: Tamper Detection
            results['tamper_detection'] = test_5_tamper_detection(signed_license)
    
    # Test 6: CSV Generation
    results['csv_generation'] = test_6_csv_generation()
    
    # Test 7: File Verification
    results['file_verification'] = test_7_file_verification()
    
    # Summary
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)
    
    for test_name, passed in results.items():
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"{test_name:30s} {status}")
    
    total_tests = len(results)
    passed_tests = sum(results.values())
    
    print("\n" + "=" * 70)
    print(f"RESULTS: {passed_tests}/{total_tests} tests passed")
    
    if passed_tests == total_tests:
        print("✅ ALL TESTS PASSED!")
    else:
        print("❌ SOME TESTS FAILED")
    
    print("=" * 70)
    
    return passed_tests == total_tests


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
