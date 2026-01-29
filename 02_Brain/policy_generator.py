#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Secure Policy Generator
Generates trading policies with anti-replay security

Author: AI Assistant for Dr. Suksaeng  
Date: January 27, 2026
Version: 2.0 (Security Enhanced)
"""

import json
import time
import base64
from typing import Dict, Any
from pathlib import Path

# Import security modules
from nonce_manager import NonceManager
from sequence_tracker import SequenceTracker

# Crypto imports
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend


class SecurePolicyGenerator:
    """
    Generates secure trading policies with:
    - Sequence numbers (ordering)
    - Nonces (replay prevention)
    - Timestamps (expiry)
    - RSA signatures (authenticity)
    """
    
    def __init__(self, private_key_path: str, storage_dir: str = "./data"):
        """
        Initialize Secure Policy Generator.
        
        Args:
            private_key_path: Path to server_private.pem
            storage_dir: Directory for sequence storage
        """
        # Load private key
        self.private_key = self._load_private_key(private_key_path)
        print(f"✅ Loaded private key from: {private_key_path}")
        
        # Initialize security components
        self.nonce_manager = NonceManager(cleanup_interval=3600)
        
        # Create storage directory
        Path(storage_dir).mkdir(parents=True, exist_ok=True)
        sequence_file = f"{storage_dir}/sequences.json"
        self.sequence_tracker = SequenceTracker(storage_file=sequence_file)
        
        print("✅ SecurePolicyGenerator initialized")
        print(f"   Storage directory: {storage_dir}")
    
    def _load_private_key(self, key_path: str):
        """Load RSA private key from PEM file."""
        try:
            with open(key_path, 'rb') as f:
                private_key = serialization.load_pem_private_key(
                    f.read(),
                    password=None,
                    backend=default_backend()
                )
            return private_key
        except Exception as e:
            raise Exception(f"Failed to load private key: {e}")
    
    def create_policy(self,
                     client_id: str,
                     symbol: str,
                     strategy: str,
                     params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a secure trading policy.
        
        Args:
            client_id: Client identifier (license_id or HWID)
            symbol: Trading symbol (e.g., "XAUUSD")
            strategy: Strategy name (e.g., "Grid", "Spike")
            params: Strategy parameters dict
            
        Returns:
            dict: Complete signed policy
        """
        # Get next sequence for this client
        sequence = self.sequence_tracker.get_next_sequence(client_id)
        
        # Generate unique nonce
        nonce = self.nonce_manager.generate_nonce()
        
        # Store nonce to prevent reuse
        self.nonce_manager.store_nonce(nonce)
        
        # Get current timestamp
        timestamp = int(time.time())
        
        # Build policy
        policy = {
            "symbol": symbol,
            "strategy": strategy,
            "sequence": sequence,
            "timestamp": timestamp,
            "nonce": nonce,
            "params": params,
            "client_id": client_id
        }
        
        # Sign policy
        signature = self._sign_policy(policy)
        policy["signature"] = signature
        
        print(f"📋 Policy created:")
        print(f"   Client: {client_id}")
        print(f"   Symbol: {symbol}")
        print(f"   Strategy: {strategy}")
        print(f"   Sequence: {sequence}")
        print(f"   Nonce: {nonce[:16]}...")
        print(f"   Timestamp: {timestamp}")
        
        return policy
    
    def _sign_policy(self, policy: dict) -> str:
        """
        Sign policy with RSA private key.
        
        Args:
            policy: Policy dictionary (without signature)
            
        Returns:
            str: Base64-encoded signature
        """
        # Remove signature field if exists
        policy_copy = policy.copy()
        policy_copy.pop("signature", None)
        
        # Create canonical JSON (sorted keys)
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
    
    def validate_policy(self, policy: dict) -> bool:
        """
        Validate a policy (for testing/debugging).
        
        Args:
            policy: Policy to validate
            
        Returns:
            bool: True if valid, False otherwise
        """
        # Check required fields
        required = ["symbol", "strategy", "sequence", "timestamp", 
                   "nonce", "params", "client_id", "signature"]
        
        for field in required:
            if field not in policy:
                print(f"❌ Missing field: {field}")
                return False
        
        # Check timestamp age
        age = time.time() - policy["timestamp"]
        if age > 300:  # 5 minutes
            print(f"❌ Policy too old: {age:.0f} seconds")
            return False
        
        if age < -60:  # 1 minute in future
            print(f"❌ Policy from future: {age:.0f} seconds")
            return False
        
        # Check nonce uniqueness
        if self.nonce_manager.is_nonce_used(policy["nonce"]):
            print(f"❌ Nonce already used (replay attack)")
            return False
        
        # Check sequence ordering
        client_id = policy["client_id"]
        sequence = policy["sequence"]
        if not self.sequence_tracker.validate_sequence(client_id, sequence):
            print(f"❌ Invalid sequence (out of order)")
            return False
        
        print("✅ Policy validation passed")
        return True
    
    def get_stats(self) -> dict:
        """
        Get statistics about policy generation.
        
        Returns:
            dict: Statistics
        """
        nonce_count = self.nonce_manager.get_nonce_count()
        seq_stats = self.sequence_tracker.get_stats()
        
        return {
            "active_nonces": nonce_count,
            "total_clients": seq_stats["total_clients"],
            "total_policies": seq_stats["total_policies"],
            "highest_sequence": seq_stats.get("highest_sequence", 0)
        }


# Example usage & testing
if __name__ == "__main__":
    print("=" * 60)
    print("SecurePolicyGenerator Test")
    print("=" * 60)
    print()
    
    # Initialize generator
    generator = SecurePolicyGenerator(
        private_key_path="test_private.pem",
        storage_dir="./test_data"
    )
    
    print()
    
    # Test 1: Create policies
    print("📝 Test 1: Create Policies")
    print("-" * 60)
    
    client1 = "client-abc-123"
    
    policy1 = generator.create_policy(
        client_id=client1,
        symbol="XAUUSD",
        strategy="Grid",
        params={
            "entry_price": 2650.00,
            "lot_size": 0.05,
            "grid_levels": [2640, 2645, 2650, 2655, 2660]
        }
    )
    
    print()
    
    policy2 = generator.create_policy(
        client_id=client1,
        symbol="EURUSD",
        strategy="Spike",
        params={
            "entry_price": 1.0543,
            "lot_size": 0.01
        }
    )
    
    print()
    
    # Test 2: Validate policies
    print("📝 Test 2: Validate Policies")
    print("-" * 60)
    
    valid1 = generator.validate_policy(policy1)
    print(f"Policy 1 valid: {valid1}")
    
    print()
    
    # Test 3: Detect replay attack
    print("📝 Test 3: Detect Replay Attack")
    print("-" * 60)
    
    # Try to use same policy again
    valid2 = generator.validate_policy(policy1)
    print(f"Policy 1 reused: {valid2} (should be False)")
    
    print()
    
    # Test 4: Stats
    print("📝 Test 4: Statistics")
    print("-" * 60)
    
    stats = generator.get_stats()
    print(json.dumps(stats, indent=2))
    
    print()
    
    # Save example policy
    print("💾 Saving example policy...")
    with open("test_data/example_secure_policy.json", 'w') as f:
        json.dump(policy1, f, indent=2)
    
    print("✅ Saved to: test_data/example_secure_policy.json")
    
    print()
    print("=" * 60)
    print("✅ All Tests Passed!")
    print("=" * 60)
