#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Signer
Phase 2 Track A: Policy Security (Anti-Replay Attack)

Signs policy messages with RSA-2048 private key.
Ensures policy authenticity and integrity.

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-01-24
"""

import json
import base64
from pathlib import Path
from typing import Dict, Any, Optional

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.backends import default_backend


class PolicySigner:
    """
    RSA-2048 policy signature generator.
    
    Signs policy dictionaries using RSA private key with:
    - Algorithm: RSA-2048
    - Padding: PKCS1v15
    - Hash: SHA256
    - Output: Base64-encoded signature
    
    Security:
    - Private key must be kept SECRET on server
    - Public key is embedded in MQL5 EA for verification
    - Signature ensures policy authenticity and integrity
    
    Example:
        >>> signer = PolicySigner()
        >>> policy = {"symbol": "XAUUSD", "action": 1, "sequence": 123}
        >>> signature = signer.sign_policy(policy)
        >>> print(len(signature))
        344  # Base64 of 256-byte RSA signature
    """
    
    def __init__(self, private_key_path: Optional[str] = None):
        """
        Initialize Policy Signer.
        
        Args:
            private_key_path: Path to server_private.pem
                            Default: "02_Brain/tools/license_generator/keys/server_private.pem"
        """
        # Default private key path
        if private_key_path is None:
            private_key_path = (
                Path(__file__).parent.parent.parent / 
                "tools" / "license_generator" / "keys" / "server_private.pem"
            )
        else:
            private_key_path = Path(private_key_path)
        
        self.private_key_path = str(private_key_path)
        
        # Load private key
        self._private_key = self._load_private_key()
    
    def _load_private_key(self) -> rsa.RSAPrivateKey:
        """
        Load RSA private key from PEM file.
        
        Returns:
            RSAPrivateKey: Loaded private key
            
        Raises:
            FileNotFoundError: If private key file not found
            ValueError: If key format is invalid
        """
        key_path = Path(self.private_key_path)
        
        if not key_path.exists():
            raise FileNotFoundError(
                f"Private key not found: {self.private_key_path}\n"
                f"Please run Phase 1 license generator first to create keys."
            )
        
        with open(key_path, 'rb') as f:
            private_key = serialization.load_pem_private_key(
                f.read(),
                password=None,
                backend=default_backend()
            )
        
        return private_key
    
    def sign_policy(self, policy_dict: Dict[str, Any]) -> str:
        """
        Sign policy dictionary with RSA private key.
        
        Process:
        1. Convert policy dict to JSON (sorted keys for consistency)
        2. Encode to UTF-8 bytes
        3. Sign with RSA-2048 + PKCS1v15 + SHA256
        4. Encode signature to Base64
        
        Args:
            policy_dict: Policy dictionary (without 'signature' field)
            
        Returns:
            str: Base64-encoded signature
            
        Example:
            >>> policy = {
            ...     "symbol": "XAUUSD",
            ...     "action": 1,
            ...     "sequence": 12345,
            ...     "timestamp": 1737623000,
            ...     "nonce": "550e8400-e29b-41d4-a716-446655440000"
            ... }
            >>> signature = signer.sign_policy(policy)
        """
        # Remove signature field if present (don't sign the signature!)
        policy_copy = {k: v for k, v in policy_dict.items() if k != 'signature'}
        
        # Convert to JSON (sorted keys for consistency)
        policy_json = json.dumps(policy_copy, sort_keys=True)
        policy_bytes = policy_json.encode('utf-8')
        
        # Sign with RSA
        signature_bytes = self._private_key.sign(
            policy_bytes,
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        # Encode to Base64
        signature_b64 = base64.b64encode(signature_bytes).decode('utf-8')
        
        return signature_b64
    
    def verify_key_loaded(self) -> bool:
        """
        Verify that private key is loaded correctly.
        
        Returns:
            bool: True if key is valid RSA private key
        """
        return isinstance(self._private_key, rsa.RSAPrivateKey)
    
    def get_public_key_pem(self) -> str:
        """
        Extract public key from private key (for testing).
        
        Returns:
            str: Public key in PEM format
        """
        public_key = self._private_key.public_key()
        public_pem = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        return public_pem.decode('utf-8')
    
    def get_key_info(self) -> dict:
        """
        Get information about loaded key.
        
        Returns:
            dict: Key information (size, type, path)
        """
        key_size = self._private_key.key_size
        
        return {
            'algorithm': 'RSA',
            'key_size': key_size,
            'key_size_bits': key_size,
            'hash_algorithm': 'SHA256',
            'padding': 'PKCS1v15',
            'signature_length': key_size // 8,  # 256 bytes for RSA-2048
            'signature_b64_length': (key_size // 8) * 4 // 3 + 4,  # ~344 chars
            'private_key_path': self.private_key_path
        }


# ========== UTILITY FUNCTIONS ==========

def sign_policy_message(
    policy_dict: Dict[str, Any],
    private_key_path: Optional[str] = None
) -> str:
    """
    Convenience function to sign a policy without creating signer instance.
    
    Args:
        policy_dict: Policy dictionary to sign
        private_key_path: Optional path to private key
        
    Returns:
        str: Base64-encoded signature
        
    Example:
        >>> from core.policy.policy_signer import sign_policy_message
        >>> signature = sign_policy_message({"symbol": "XAUUSD", "action": 1})
    """
    signer = PolicySigner(private_key_path)
    return signer.sign_policy(policy_dict)


# ========== TESTING ==========

if __name__ == "__main__":
    print("=" * 60)
    print("Policy Signer - Test Suite")
    print("=" * 60)
    
    try:
        # Test 1: Load private key
        print("\n✅ Test 1: Load private key")
        signer = PolicySigner()
        print(f"   Private key loaded: {signer.verify_key_loaded()}")
        print(f"   Key path: {signer.private_key_path}")
        
        # Test 2: Get key info
        print("\n✅ Test 2: Key information")
        info = signer.get_key_info()
        print(f"   Algorithm: {info['algorithm']}")
        print(f"   Key size: {info['key_size_bits']} bits")
        print(f"   Hash: {info['hash_algorithm']}")
        print(f"   Signature length: {info['signature_length']} bytes")
        print(f"   Base64 length: ~{info['signature_b64_length']} chars")
        
        # Test 3: Sign a simple policy
        print("\n✅ Test 3: Sign simple policy")
        policy1 = {
            "symbol": "XAUUSD",
            "action": 1,
            "sequence": 12345
        }
        sig1 = signer.sign_policy(policy1)
        print(f"   Policy: {policy1}")
        print(f"   Signature (first 50 chars): {sig1[:50]}...")
        print(f"   Signature length: {len(sig1)} chars")
        
        # Test 4: Sign comprehensive policy
        print("\n✅ Test 4: Sign comprehensive policy")
        policy2 = {
            "symbol": "XAUUSD",
            "action": 1,
            "sequence": 12345,
            "timestamp": 1737623000,
            "nonce": "550e8400-e29b-41d4-a716-446655440000",
            "license_id": "FLASH-2601-TEST-0001",
            "params": {
                "entry_price": 2650.00,
                "lot_size": 0.05
            }
        }
        sig2 = signer.sign_policy(policy2)
        print(f"   Policy has {len(policy2)} fields")
        print(f"   Signature: {sig2[:50]}...")
        
        # Test 5: Verify different policies = different signatures
        print("\n✅ Test 5: Different policies → Different signatures")
        policy3 = {**policy1, "action": 2}  # Change action
        sig3 = signer.sign_policy(policy3)
        different = (sig1 != sig3)
        print(f"   Policy 1 action: 1 → Sig: {sig1[:30]}...")
        print(f"   Policy 3 action: 2 → Sig: {sig3[:30]}...")
        print(f"   Signatures different: {different} {'✅ PASS' if different else '❌ FAIL'}")
        
        # Test 6: Same policy = same signature (deterministic)
        print("\n✅ Test 6: Same policy → Same signature (deterministic)")
        sig1_again = signer.sign_policy(policy1)
        same = (sig1 == sig1_again)
        print(f"   First signature:  {sig1[:30]}...")
        print(f"   Second signature: {sig1_again[:30]}...")
        print(f"   Signatures same: {same} {'✅ PASS' if same else '❌ FAIL'}")
        
        # Test 7: Get public key
        print("\n✅ Test 7: Extract public key")
        public_pem = signer.get_public_key_pem()
        print(f"   Public key (first 60 chars):")
        print(f"   {public_pem[:60]}...")
        
        print("\n" + "=" * 60)
        print("✅ All tests completed!")
        print("=" * 60)
        
    except FileNotFoundError as e:
        print(f"\n❌ Error: {e}")
        print("\nPlease run Phase 1 first:")
        print("1. cd 02_Brain/tools/license_generator")
        print("2. python generate_keys.py")
        print("\nOr provide a valid private_key_path")
