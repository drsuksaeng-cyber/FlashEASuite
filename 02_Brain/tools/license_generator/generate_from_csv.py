#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Generator (from CSV)
Generate licenses from CSV file with client information

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

import csv
import json
import os
import uuid
from datetime import datetime
from sign_license import create_signed_license


def generate_license_id():
    """Generate unique license ID."""
    timestamp = datetime.now().strftime("%Y%m")
    unique_id = str(uuid.uuid4())[:8].upper()
    return f"FLASH-{timestamp}-{unique_id}"


def parse_strategies(strategies_str):
    """Parse strategies string to list."""
    if not strategies_str or strategies_str.strip() == "":
        return ["Grid"]
    return [s.strip() for s in strategies_str.split(',')]


def parse_bool(value):
    """Parse boolean value from string."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ('true', 'yes', '1', 'on')
    return False


def create_license_from_row(row):
    """
    Create license dictionary from CSV row.
    
    Args:
        row: Dictionary from CSV row
    
    Returns:
        dict: License structure
    """
    # Generate license ID
    license_id = generate_license_id()
    
    # Parse strategies
    strategies = parse_strategies(row.get('strategies', 'Grid'))
    
    # Parse booleans
    hidden_tpsl = parse_bool(row.get('hidden_tpsl', 'true'))
    trailing_stop = parse_bool(row.get('trailing_stop', 'true'))
    multi_symbol = parse_bool(row.get('multi_symbol', 'true'))
    
    # Parse integers
    max_slots = int(row.get('max_slots', 1))
    max_symbols = int(row.get('max_symbols', 10))
    
    # Get dates
    issued_date = row.get('issued_date', datetime.now().strftime('%Y-%m-%d'))
    expiry_date = row.get('expiry_date', '2027-12-31')
    
    # Get license type and determine grace days
    license_type = row.get('license_type', 'trial')
    grace_days_map = {
        'standalone': 0,
        'trial': 3,
        'reporting': 7,
        'premium': 14
    }
    grace_days = grace_days_map.get(license_type, 7)
    
    # Create license structure (following SECURITY_MASTER_SPEC.txt)
    license_dict = {
        "license_id": license_id,
        "product": row.get('product', 'FlashEASuite-Pro'),
        "license_type": license_type,
        
        "client_info": {
            "name": row.get('client_name', 'Unknown'),
            "email": row.get('client_email', ''),
            "phone": row.get('client_phone', ''),
            "account_number": row.get('account_number', ''),
            "broker_name": row.get('broker_name', ''),
            "notes": row.get('notes', '')
        },
        
        "hardware_binding": {
            "hwid": row.get('hwid', ''),  # Will be filled on first activation
            "max_slots": max_slots,
            "used_slots": []
        },
        
        "features": {
            "strategies": strategies,
            "hidden_tpsl": hidden_tpsl,
            "trailing_stop": trailing_stop,
            "multi_symbol": multi_symbol,
            "max_symbols": max_symbols
        },
        
        "validity": {
            "issued_date": issued_date,
            "expiry_date": expiry_date,
            "grace_days": grace_days
        },
        
        "brain_config": {
            "can_receive_policy": True,
            "policy_level": "FULL",
            "feedback_enabled": True
        }
    }
    
    return license_dict


def generate_licenses_from_csv(csv_file, private_key_path, output_dir="licenses"):
    """
    Generate licenses from CSV file.
    
    Args:
        csv_file: Path to CSV file
        private_key_path: Path to private key
        output_dir: Output directory for licenses
    
    Returns:
        list: List of generated license file paths
    """
    print("=" * 70)
    print("FlashEASuite V2 - License Generator (CSV Mode)")
    print("=" * 70)
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    generated_files = []
    
    # Read CSV
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        for idx, row in enumerate(reader, 1):
            print(f"\n📋 Processing client #{idx}: {row.get('client_name', 'Unknown')}")
            
            try:
                # Create license
                license_dict = create_license_from_row(row)
                
                # Sign license
                signed_license = create_signed_license(license_dict, private_key_path)
                
                # Save to file
                license_id = signed_license['license_id']
                output_file = os.path.join(output_dir, f"{license_id}.key")
                
                with open(output_file, 'w', encoding='utf-8') as out:
                    json.dump(signed_license, out, indent=2, ensure_ascii=False)
                
                print(f"   ✅ License generated: {license_id}")
                print(f"   📁 Saved to: {output_file}")
                print(f"   👤 Client: {signed_license['client_info']['name']}")
                print(f"   📧 Email: {signed_license['client_info']['email']}")
                print(f"   🏷️  Type: {signed_license['license_type']}")
                print(f"   📅 Expires: {signed_license['validity']['expiry_date']}")
                print(f"   🎯 Strategies: {', '.join(signed_license['features']['strategies'])}")
                
                generated_files.append(output_file)
                
            except Exception as e:
                print(f"   ❌ Error generating license: {e}")
                continue
    
    print("\n" + "=" * 70)
    print(f"✅ Generated {len(generated_files)} licenses successfully!")
    print("=" * 70)
    
    return generated_files


if __name__ == "__main__":
    import sys
    
    # Default values
    csv_file = "templates/clients_template.csv"
    private_key = "keys/server_private.pem"
    output_dir = "licenses"
    
    # Check arguments
    if len(sys.argv) > 1:
        csv_file = sys.argv[1]
    
    # Generate licenses
    try:
        generated = generate_licenses_from_csv(csv_file, private_key, output_dir)
        
        print(f"\n📊 Summary:")
        print(f"   Total licenses: {len(generated)}")
        print(f"   Output directory: {output_dir}")
        print(f"\n💡 Next steps:")
        print(f"   1. Review generated licenses in '{output_dir}/'")
        print(f"   2. Verify licenses: python verify_license.py {output_dir}/FLASH-*.key")
        print(f"   3. Send licenses to clients")
        print(f"   4. Share server_public.pem with EA developers")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
