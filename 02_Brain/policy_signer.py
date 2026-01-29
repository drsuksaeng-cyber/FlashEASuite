#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Signer Tool
Standalone tool to sign policy JSON files with RSA signature

Author: AI Assistant for Dr. Suksaeng
Date: January 27, 2026
Version: 1.0
"""

import json
import base64
import sys
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend


class PolicySigner:
    """
    Signs policy JSON files with RSA-2048 signature.
    """
    
    def __init__(self, private_key_path: str):
        """
        Initialize Policy Signer.
        
        Args:
            private_key_path: Path to server_private.pem
        """
        self.private_key = self.load_private_key(private_key_path)
        print(f"✅ Loaded private key from: {private_key_path}")
    
    def load_private_key(self, key_path: str):
        """
        Load RSA private key from PEM file.
        
        Args:
            key_path: Path to private key file
            
        Returns:
            RSA private key object
        """
        try:
            with open(key_path, 'rb') as f:
                private_key = serialization.load_pem_private_key(
                    f.read(),
                    password=None,
                    backend=default_backend()
                )
            return private_key
        except Exception as e:
            print(f"❌ Failed to load private key: {e}")
            sys.exit(1)
    
    def sign_policy(self, policy: dict) -> str:
        """
        Sign policy dictionary with RSA signature.
        
        Args:
            policy: Policy dictionary
            
        Returns:
            str: Base64-encoded signature
        """
        # Remove signature field if exists
        policy_copy = policy.copy()
        policy_copy.pop("signature", None)
        
        # Create canonical JSON (sorted keys for consistency)
        canonical = json.dumps(policy_copy, sort_keys=True)
        
        # Sign with RSA-PSS
        signature = self.private_key.sign(
            canonical.encode('utf-8'),
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        # Return base64
        return base64.b64encode(signature).decode('utf-8')
    
    def sign_policy_file(self, policy_file: str, output_file: str = None):
        """
        Sign a policy JSON file.
        
        Args:
            policy_file: Input policy file path
            output_file: Output file path (if None, overwrites input)
        """
        try:
            # Read policy
            with open(policy_file, 'r') as f:
                policy = json.load(f)
            
            print(f"📄 Loaded policy from: {policy_file}")
            
            # Check required fields
            required = ["symbol", "strategy", "timestamp", "nonce", "sequence"]
            missing = [field for field in required if field not in policy]
            
            if missing:
                print(f"⚠️ Warning: Missing fields: {missing}")
            
            # Sign policy
            signature = self.sign_policy(policy)
            policy["signature"] = signature
            
            print(f"✅ Policy signed successfully")
            print(f"   Signature: {signature[:60]}...")
            
            # Save
            output = output_file if output_file else policy_file
            with open(output, 'w') as f:
                json.dump(policy, f, indent=2)
            
            print(f"💾 Saved to: {output}")
            
        except FileNotFoundError:
            print(f"❌ File not found: {policy_file}")
            sys.exit(1)
        except json.JSONDecodeError:
            print(f"❌ Invalid JSON in file: {policy_file}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Error signing policy: {e}")
            sys.exit(1)
    
    def verify_policy(self, policy_file: str, public_key_path: str):
        """
        Verify a signed policy (for testing).
        
        Args:
            policy_file: Policy file to verify
            public_key_path: Path to server_public.pem
        """
        try:
            # Load policy
            with open(policy_file, 'r') as f:
                policy = json.load(f)
            
            if "signature" not in policy:
                print("❌ Policy has no signature")
                return False
            
            # Load public key
            with open(public_key_path, 'rb') as f:
                public_key = serialization.load_pem_public_key(
                    f.read(),
                    backend=default_backend()
                )
            
            # Extract signature
            signature_b64 = policy["signature"]
            signature = base64.b64decode(signature_b64)
            
            # Create canonical JSON
            policy_copy = policy.copy()
            policy_copy.pop("signature")
            canonical = json.dumps(policy_copy, sort_keys=True)
            
            # Verify
            try:
                public_key.verify(
                    signature,
                    canonical.encode('utf-8'),
                    padding.PSS(
                        mgf=padding.MGF1(hashes.SHA256()),
                        salt_length=padding.PSS.MAX_LENGTH
                    ),
                    hashes.SHA256()
                )
                print("✅ Signature is VALID")
                return True
            except Exception:
                print("❌ Signature is INVALID")
                return False
                
        except Exception as e:
            print(f"❌ Verification failed: {e}")
            return False


def main():
    """
    Command-line interface for policy signer.
    """
    print("=" * 60)
    print("FlashEASuite V2 - Policy Signer Tool")
    print("=" * 60)
    print()
    
    if len(sys.argv) < 3:
        print("Usage:")
        print("  Sign:   python policy_signer.py sign <policy.json> <private_key.pem> [output.json]")
        print("  Verify: python policy_signer.py verify <policy.json> <public_key.pem>")
        print()
        print("Example:")
        print("  python policy_signer.py sign policy.json keys/server_private.pem")
        print("  python policy_signer.py verify policy.json keys/server_public.pem")
        sys.exit(0)
    
    command = sys.argv[1]
    
    if command == "sign":
        if len(sys.argv) < 4:
            print("❌ Missing arguments for sign command")
            sys.exit(1)
        
        policy_file = sys.argv[2]
        private_key = sys.argv[3]
        output_file = sys.argv[4] if len(sys.argv) > 4 else None
        
        signer = PolicySigner(private_key)
        signer.sign_policy_file(policy_file, output_file)
        
    elif command == "verify":
        if len(sys.argv) < 4:
            print("❌ Missing arguments for verify command")
            sys.exit(1)
        
        policy_file = sys.argv[2]
        public_key = sys.argv[3]
        
        # Verify without signer instance
        try:
            # Load policy
            with open(policy_file, 'r') as f:
                policy = json.load(f)
            
            if "signature" not in policy:
                print("❌ Policy has no signature")
                sys.exit(1)
            
            # Load public key
            with open(public_key, 'rb') as f:
                pub_key = serialization.load_pem_public_key(
                    f.read(),
                    backend=default_backend()
                )
            
            # Extract signature
            signature_b64 = policy["signature"]
            signature = base64.b64decode(signature_b64)
            
            # Create canonical JSON
            policy_copy = policy.copy()
            policy_copy.pop("signature")
            canonical = json.dumps(policy_copy, sort_keys=True)
            
            # Verify
            try:
                pub_key.verify(
                    signature,
                    canonical.encode('utf-8'),
                    padding.PSS(
                        mgf=padding.MGF1(hashes.SHA256()),
                        salt_length=padding.PSS.MAX_LENGTH
                    ),
                    hashes.SHA256()
                )
                print("✅ Signature is VALID")
            except Exception:
                print("❌ Signature is INVALID")
                sys.exit(1)
                
        except Exception as e:
            print(f"❌ Verification failed: {e}")
            sys.exit(1)
        
    else:
        print(f"❌ Unknown command: {command}")
        print("   Use 'sign' or 'verify'")
        sys.exit(1)


if __name__ == "__main__":
    # Test mode - create example policy
    if len(sys.argv) == 1:
        print("🧪 TEST MODE")
        print()
        
        # Create example policy
        example_policy = {
            "symbol": "XAUUSD",
            "strategy": "Grid",
            "sequence": 1,
            "timestamp": 1737945600,
            "nonce": "550e8400-e29b-41d4-a716-446655440000",
            "params": {
                "entry_price": 2650.00,
                "lot_size": 0.05,
                "grid_levels": [2640, 2645, 2650, 2655, 2660]
            }
        }
        
        # Save example
        with open("example_policy.json", 'w') as f:
            json.dump(example_policy, f, indent=2)
        
        print("✅ Created example_policy.json")
        print()
        print("To sign it, run:")
        print("  python policy_signer.py sign example_policy.json <private_key.pem>")
    else:
        main()
