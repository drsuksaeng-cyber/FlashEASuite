#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Single License Generator (CLI)
Interactive CLI for generating individual licenses

Author: Dr. Suksaeng Kukanok
Date: 2026-01-22
"""

import json
import os
from datetime import datetime, timedelta
from generate_from_csv import create_license_from_row, generate_license_id
from sign_license import create_signed_license


def get_input(prompt, default=None, required=True):
    """Get user input with default value."""
    if default:
        full_prompt = f"{prompt} [{default}]: "
    else:
        full_prompt = f"{prompt}: "
    
    value = input(full_prompt).strip()
    
    if not value and default:
        return default
    
    if not value and required:
        print("❌ This field is required!")
        return get_input(prompt, default, required)
    
    return value


def get_bool_input(prompt, default=True):
    """Get boolean input."""
    default_str = "Y/n" if default else "y/N"
    value = input(f"{prompt} [{default_str}]: ").strip().lower()
    
    if not value:
        return default
    
    return value in ('y', 'yes', 'true', '1')


def generate_single_license_interactive():
    """Interactive license generation."""
    print("=" * 70)
    print("FlashEASuite V2 - Single License Generator")
    print("=" * 70)
    print("\n📝 Please provide client information:\n")
    
    # Client info
    client_name = get_input("Client Name", required=True)
    client_email = get_input("Client Email", required=True)
    client_phone = get_input("Client Phone", required=False)
    account_number = get_input("MT5 Account Number", required=False)
    broker_name = get_input("Broker Name", required=False)
    
    # License configuration
    print("\n🔧 License Configuration:\n")
    
    license_types = ['standalone', 'trial', 'reporting', 'premium']
    print("License Types:")
    for i, lt in enumerate(license_types, 1):
        print(f"  {i}. {lt}")
    
    license_type_idx = int(get_input("Select license type (1-4)", "3")) - 1
    license_type = license_types[license_type_idx]
    
    max_slots = int(get_input("Max slots", "5"))
    
    # Dates
    print("\n📅 Validity Period:\n")
    issued_date = get_input("Issue Date (YYYY-MM-DD)", datetime.now().strftime('%Y-%m-%d'))
    
    # Default expiry based on type
    if license_type == 'trial':
        default_expiry = (datetime.now() + timedelta(days=30)).strftime('%Y-%m-%d')
    elif license_type == 'standalone':
        default_expiry = '2030-12-31'
    else:
        default_expiry = (datetime.now() + timedelta(days=365)).strftime('%Y-%m-%d')
    
    expiry_date = get_input("Expiry Date (YYYY-MM-DD)", default_expiry)
    
    # Features
    print("\n🎯 Features:\n")
    
    print("Available strategies: Grid, Spike, Trend, Range")
    strategies_input = get_input("Strategies (comma-separated)", "Grid,Spike,Trend,Range")
    
    hidden_tpsl = get_bool_input("Hidden TP/SL", True)
    trailing_stop = get_bool_input("Trailing Stop", True)
    multi_symbol = get_bool_input("Multi-Symbol", True)
    max_symbols = int(get_input("Max Symbols", "10"))
    
    notes = get_input("Notes (optional)", required=False)
    
    # Create row dict
    row = {
        'client_name': client_name,
        'client_email': client_email,
        'client_phone': client_phone,
        'account_number': account_number,
        'broker_name': broker_name,
        'license_type': license_type,
        'product': 'FlashEASuite-Pro',
        'hwid': '',
        'max_slots': str(max_slots),
        'issued_date': issued_date,
        'expiry_date': expiry_date,
        'strategies': strategies_input,
        'hidden_tpsl': str(hidden_tpsl),
        'trailing_stop': str(trailing_stop),
        'multi_symbol': str(multi_symbol),
        'max_symbols': str(max_symbols),
        'notes': notes
    }
    
    # Generate license
    print("\n🔐 Generating license...\n")
    
    try:
        license_dict = create_license_from_row(row)
        signed_license = create_signed_license(license_dict, "keys/server_private.pem")
        
        # Save
        os.makedirs("licenses", exist_ok=True)
        license_id = signed_license['license_id']
        output_file = f"licenses/{license_id}.key"
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(signed_license, f, indent=2, ensure_ascii=False)
        
        print("=" * 70)
        print("✅ LICENSE GENERATED SUCCESSFULLY!")
        print("=" * 70)
        print(f"\n📄 License Details:")
        print(f"   License ID: {license_id}")
        print(f"   Client: {client_name}")
        print(f"   Email: {client_email}")
        print(f"   Type: {license_type}")
        print(f"   Expires: {expiry_date}")
        print(f"   Strategies: {strategies_input}")
        print(f"\n💾 Saved to: {output_file}")
        
        print(f"\n✅ Next steps:")
        print(f"   1. Send {output_file} to client")
        print(f"   2. Verify: python verify_license.py {output_file}")
        
        return output_file
        
    except Exception as e:
        print(f"\n❌ Error generating license: {e}")
        return None


if __name__ == "__main__":
    generate_single_license_interactive()
