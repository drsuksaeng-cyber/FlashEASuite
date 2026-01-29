#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Secure Policy Generator
Phase 2 Track A: Policy Security (Anti-Replay Attack)

Generates secure policy messages with all security fields:
- sequence (incrementing per client)
- nonce (UUID v4 one-time use)
- timestamp (Unix seconds)
- license_id (from license)
- signature (RSA-2048)

Integrates NonceManager, SequenceTracker, and PolicySigner.

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-01-24
"""

import time
from typing import Dict, Any, Optional

from .nonce_manager import NonceManager
from .sequence_tracker import SequenceTracker
from .policy_signer import PolicySigner


class SecurePolicyGenerator:
    """
    Secure policy generator with anti-replay protection.
    
    Adds security fields to base policy:
    1. sequence - Incrementing number per (license_id, symbol)
    2. nonce - UUID v4 for one-time use
    3. timestamp - Unix seconds
    4. license_id - From license
    5. signature - RSA-2048 Base64
    
    Prevents:
    - Replay attacks (old policy reuse)
    - Tampering (signature verification)
    - Nonce reuse (UUID v4 uniqueness)
    
    Example:
        >>> generator = SecurePolicyGenerator()
        >>> base_policy = {"symbol": "XAUUSD", "action": 1}
        >>> secure = generator.generate_secure_policy(
        ...     base_policy=base_policy,
        ...     license_id="FLASH-2601-TEST-0001"
        ... )
        >>> print(secure.keys())
        dict_keys(['symbol', 'action', 'sequence', 'nonce', 'timestamp', 
                   'license_id', 'signature'])
    """
    
    def __init__(
        self,
        private_key_path: Optional[str] = None,
        db_path: Optional[str] = None
    ):
        """
        Initialize Secure Policy Generator.
        
        Args:
            private_key_path: Path to RSA private key (server_private.pem)
            db_path: Path to sequence database (sequences.db)
        """
        # Initialize components
        self.nonce_manager = NonceManager()
        self.sequence_tracker = SequenceTracker(db_path=db_path)
        self.policy_signer = PolicySigner(private_key_path=private_key_path)
        
        # Statistics
        self._policies_generated = 0
    
    def generate_secure_policy(
        self,
        base_policy: Dict[str, Any],
        license_id: str,
        feedback_stats: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Generate secure policy with all security fields.
        
        Process:
        1. Extract symbol from base policy
        2. Generate nonce (UUID v4)
        3. Get next sequence number
        4. Add timestamp
        5. Add license_id
        6. Sign entire policy
        7. Add signature to policy
        
        Args:
            base_policy: Base policy dict (symbol, action, params, etc.)
            license_id: License ID (e.g., "FLASH-2601-TEST-0001")
            feedback_stats: Optional feedback statistics (for logging)
            
        Returns:
            dict: Secure policy with all security fields
            
        Example:
            >>> base = {
            ...     "symbol": "XAUUSD",
            ...     "action": 1,
            ...     "params": {"entry_price": 2650.00}
            ... }
            >>> secure = generator.generate_secure_policy(
            ...     base_policy=base,
            ...     license_id="FLASH-2601-TEST-0001"
            ... )
        """
        # Validate base policy has symbol
        if 'symbol' not in base_policy:
            raise ValueError("base_policy must contain 'symbol' field")
        
        symbol = base_policy['symbol']
        
        # 1. Generate nonce
        nonce = self.nonce_manager.generate_nonce()
        
        # 2. Get next sequence
        sequence = self.sequence_tracker.get_next_sequence(license_id, symbol)
        
        # 3. Get timestamp (Unix seconds)
        timestamp = int(time.time())
        
        # 4. Build policy with security fields
        secure_policy = {
            **base_policy,  # Include all base fields
            'sequence': sequence,
            'nonce': nonce,
            'timestamp': timestamp,
            'license_id': license_id
        }
        
        # 5. Sign policy
        signature = self.policy_signer.sign_policy(secure_policy)
        
        # 6. Add signature
        secure_policy['signature'] = signature
        
        # Update statistics
        self._policies_generated += 1
        
        return secure_policy
    
    def save_sequences(self) -> None:
        """
        Save all sequences to database.
        
        Call this before shutdown to ensure no data loss.
        Auto-save happens every 5 seconds, but manual save is safer.
        """
        self.sequence_tracker.save()
    
    def get_stats(self) -> dict:
        """
        Get generator statistics.
        
        Returns:
            dict: Statistics including policies generated, sequences, etc.
        """
        seq_stats = self.sequence_tracker.get_stats()
        nonce_stats = self.nonce_manager.get_stats()
        key_info = self.policy_signer.get_key_info()
        
        return {
            'policies_generated': self._policies_generated,
            'sequence_tracker': seq_stats,
            'nonce_manager': nonce_stats,
            'signer': {
                'algorithm': key_info['algorithm'],
                'key_size': key_info['key_size_bits'],
                'signature_length': key_info['signature_b64_length']
            }
        }


# ========== CONVENIENCE FUNCTION ==========

def generate_secure_policy(
    base_policy: Dict[str, Any],
    license_id: str,
    feedback_stats: Optional[Dict[str, Any]] = None,
    private_key_path: Optional[str] = None,
    db_path: Optional[str] = None
) -> Dict[str, Any]:
    """
    Convenience function to generate secure policy without creating generator instance.
    
    Args:
        base_policy: Base policy dictionary
        license_id: License ID
        feedback_stats: Optional feedback statistics
        private_key_path: Optional path to private key
        db_path: Optional path to sequence database
        
    Returns:
        dict: Secure policy with all security fields
        
    Example:
        >>> from core.policy import generate_secure_policy
        >>> policy = generate_secure_policy(
        ...     base_policy={"symbol": "XAUUSD", "action": 1},
        ...     license_id="FLASH-2601-TEST-0001"
        ... )
    """
    # Create generator (will be reused if called multiple times - consider caching)
    generator = SecurePolicyGenerator(
        private_key_path=private_key_path,
        db_path=db_path
    )
    
    return generator.generate_secure_policy(
        base_policy=base_policy,
        license_id=license_id,
        feedback_stats=feedback_stats
    )


# ========== TESTING ==========

if __name__ == "__main__":
    print("=" * 60)
    print("Secure Policy Generator - Test Suite")
    print("=" * 60)
    
    try:
        # Test 1: Create generator
        print("\n✅ Test 1: Create generator")
        generator = SecurePolicyGenerator()
        print("   Generator created successfully")
        
        # Test 2: Generate simple secure policy
        print("\n✅ Test 2: Generate simple secure policy")
        base1 = {
            "symbol": "XAUUSD",
            "action": 1
        }
        secure1 = generator.generate_secure_policy(
            base_policy=base1,
            license_id="FLASH-2601-TEST-0001"
        )
        print(f"   Base fields: {list(base1.keys())}")
        print(f"   Secure fields: {list(secure1.keys())}")
        print(f"   Added: sequence={secure1['sequence']}")
        print(f"   Added: nonce={secure1['nonce'][:30]}...")
        print(f"   Added: timestamp={secure1['timestamp']}")
        print(f"   Added: license_id={secure1['license_id']}")
        print(f"   Added: signature={secure1['signature'][:30]}...")
        
        # Test 3: Generate comprehensive policy
        print("\n✅ Test 3: Generate comprehensive policy")
        base2 = {
            "symbol": "EURUSD",
            "action": 2,
            "params": {
                "entry_price": 1.0543,
                "lot_size": 0.05,
                "tp": 1.0563,
                "sl": 1.0523
            },
            "indicator_params": {
                "atr_period": 14,
                "ema_fast": 12
            }
        }
        secure2 = generator.generate_secure_policy(
            base_policy=base2,
            license_id="FLASH-2601-TEST-0001"
        )
        print(f"   Symbol: {secure2['symbol']}")
        print(f"   Action: {secure2['action']}")
        print(f"   Sequence: {secure2['sequence']}")
        print(f"   Has params: {'params' in secure2}")
        print(f"   Has indicator_params: {'indicator_params' in secure2}")
        
        # Test 4: Sequence increment
        print("\n✅ Test 4: Sequence increment per symbol")
        seq1 = secure1['sequence']  # XAUUSD
        seq2 = secure2['sequence']  # EURUSD
        
        # Generate more XAUUSD policies
        secure3 = generator.generate_secure_policy(
            base_policy={"symbol": "XAUUSD", "action": 2},
            license_id="FLASH-2601-TEST-0001"
        )
        seq3 = secure3['sequence']
        
        print(f"   XAUUSD #1: sequence={seq1}")
        print(f"   EURUSD #1: sequence={seq2}")
        print(f"   XAUUSD #2: sequence={seq3}")
        print(f"   XAUUSD increment: {seq3 - seq1} {'✅ PASS' if seq3 == seq1 + 1 else '❌ FAIL'}")
        
        # Test 5: Nonce uniqueness
        print("\n✅ Test 5: Nonce uniqueness")
        nonce1 = secure1['nonce']
        nonce2 = secure2['nonce']
        nonce3 = secure3['nonce']
        unique = len({nonce1, nonce2, nonce3}) == 3
        print(f"   Nonce 1: {nonce1[:30]}...")
        print(f"   Nonce 2: {nonce2[:30]}...")
        print(f"   Nonce 3: {nonce3[:30]}...")
        print(f"   All unique: {unique} {'✅ PASS' if unique else '❌ FAIL'}")
        
        # Test 6: Signature changes with data
        print("\n✅ Test 6: Signature changes with data")
        sig1 = secure1['signature']
        sig2 = secure2['signature']
        different = (sig1 != sig2)
        print(f"   Sig 1: {sig1[:30]}...")
        print(f"   Sig 2: {sig2[:30]}...")
        print(f"   Different: {different} {'✅ PASS' if different else '❌ FAIL'}")
        
        # Test 7: Statistics
        print("\n✅ Test 7: Statistics")
        stats = generator.get_stats()
        print(f"   Policies generated: {stats['policies_generated']}")
        print(f"   Total sequences: {stats['sequence_tracker']['total_sequences']}")
        print(f"   Unique nonces: {stats['nonce_manager']['unique_count']}")
        print(f"   Key size: {stats['signer']['key_size']} bits")
        
        # Test 8: Save sequences
        print("\n✅ Test 8: Save sequences")
        generator.save_sequences()
        print("   Sequences saved to database")
        
        # Test 9: Multiple licenses
        print("\n✅ Test 9: Multiple licenses")
        secure_lic2 = generator.generate_secure_policy(
            base_policy={"symbol": "XAUUSD", "action": 1},
            license_id="FLASH-2601-TEST-0002"
        )
        seq_lic2 = secure_lic2['sequence']
        print(f"   License 1 - XAUUSD: sequence={seq3}")
        print(f"   License 2 - XAUUSD: sequence={seq_lic2}")
        print(f"   Separate tracking: {'✅ PASS' if seq_lic2 == 1 else '❌ FAIL'}")
        
        print("\n" + "=" * 60)
        print("✅ All tests completed!")
        print("=" * 60)
        
        # Show sample secure policy
        print("\n📋 Sample Secure Policy:")
        print("-" * 60)
        import json
        print(json.dumps(secure1, indent=2))
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
