#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - License Admin CLI
Interactive tool for generating licenses
"""

import sys
from generate_license import LicenseGenerator
from verify_license import LicenseVerifier


def print_header():
    """Print header"""
    print()
    print("=" * 70)
    print(" " * 15 + "FlashEASuite V2 - License Admin")
    print("=" * 70)
    print()


def generate_license_interactive():
    """Interactive license generation"""
    print("📝 License Generation")
    print("-" * 70)
    print()
    
    # Get input
    print("Enter license details:")
    license_id = input("  License ID (e.g., FLASH-2026-0001-XXXX): ").strip()
    client_name = input("  Client Name: ").strip()
    client_email = input("  Client Email: ").strip()
    hwid = input("  Hardware ID (HWID): ").strip()
    
    print()
    print("License Type:")
    print("  1. Standalone (offline, no grace)")
    print("  2. Trial (3 days grace)")
    print("  3. Reporting (7 days grace) ← Default")
    print("  4. Premium (14 days grace)")
    license_type_choice = input("  Select (1-4) [3]: ").strip() or "3"
    
    license_types = {
        "1": "standalone",
        "2": "trial",
        "3": "reporting",
        "4": "premium"
    }
    license_type = license_types.get(license_type_choice, "reporting")
    
    max_slots = input("  Max MT5 Installations [5]: ").strip() or "5"
    max_slots = int(max_slots)
    
    validity_years = input("  Validity (years) [5]: ").strip() or "5"
    validity_days = int(validity_years) * 365
    
    print()
    print("Generating license...")
    
    # Generate
    generator = LicenseGenerator()
    license_data = generator.generate_license(
        license_id=license_id,
        client_name=client_name,
        client_email=client_email,
        hwid=hwid,
        license_type=license_type,
        max_slots=max_slots,
        validity_days=validity_days
    )
    
    # Sign
    signed_license = generator.sign_license(license_data)
    
    # Save
    output_file = f"{license_id}.key"
    generator.save_license(signed_license, output_file)
    
    print()
    print("✅ License generated successfully!")
    print(f"   File: {output_file}")
    print()
    print("📋 Summary:")
    print(f"   ID: {license_id}")
    print(f"   Type: {license_type}")
    print(f"   Client: {client_name}")
    print(f"   Valid: {validity_years} years")
    print(f"   Max Slots: {max_slots}")
    print()


def verify_license_interactive():
    """Interactive license verification"""
    print("🔍 License Verification")
    print("-" * 70)
    print()
    
    license_file = input("  License file path [example_license.key]: ").strip()
    if not license_file:
        license_file = "example_license.key"
    
    print()
    
    verifier = LicenseVerifier()
    is_valid, _ = verifier.verify_license(license_file)
    
    print()
    if is_valid:
        print("✅ License is VALID")
    else:
        print("❌ License is INVALID")
    print()


def main_menu():
    """Main menu"""
    while True:
        print_header()
        print("Main Menu:")
        print("  1. Generate New License")
        print("  2. Verify License")
        print("  3. Generate Example License")
        print("  4. Exit")
        print()
        
        choice = input("Select option (1-4): ").strip()
        print()
        
        if choice == "1":
            generate_license_interactive()
            input("Press Enter to continue...")
            
        elif choice == "2":
            verify_license_interactive()
            input("Press Enter to continue...")
            
        elif choice == "3":
            print("📝 Generating example license...")
            generator = LicenseGenerator()
            license_data = generator.generate_license(
                license_id="FLASH-2026-DEMO-0001",
                client_name="Example Client",
                client_email="client@example.com",
                hwid="demo-hwid-12345",
                license_type="reporting",
                max_slots=5,
                validity_days=1825
            )
            signed = generator.sign_license(license_data)
            generator.save_license(signed, "example_license.key")
            print()
            print("✅ Example license created: example_license.key")
            print()
            input("Press Enter to continue...")
            
        elif choice == "4":
            print("👋 Goodbye!")
            break
            
        else:
            print("❌ Invalid choice")
            input("Press Enter to continue...")


if __name__ == "__main__":
    try:
        main_menu()
    except KeyboardInterrupt:
        print("\n\n👋 Interrupted by user")
        sys.exit(0)
