#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Security Module
Phase 2 Track A: Policy Security (Anti-Replay Attack)

Complete policy security layer with:
- Nonce generation (UUID v4)
- Sequence tracking (SQLite + cache)
- RSA signature (2048-bit)
- Secure policy generation

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-01-24
"""

# Import classes
from .nonce_manager import NonceManager
from .sequence_tracker import SequenceTracker
from .policy_signer import PolicySigner
from .policy_generator import SecurePolicyGenerator

# Import convenience functions
from .nonce_manager import generate_nonce, validate_nonce_format
from .policy_signer import sign_policy_message
from .policy_generator import generate_secure_policy

# Version info
__version__ = '1.0.0'
__author__ = 'Dr. Suksaeng Kukanok'
__date__ = '2026-01-24'

# Public API
__all__ = [
    # Classes
    'NonceManager',
    'SequenceTracker',
    'PolicySigner',
    'SecurePolicyGenerator',
    
    # Functions
    'generate_nonce',
    'validate_nonce_format',
    'sign_policy_message',
    'generate_secure_policy',
]


# Module-level docstring
"""
Usage Examples
==============

Basic Usage (Recommended):
    >>> from core.policy import generate_secure_policy
    >>> 
    >>> base_policy = {
    ...     "symbol": "XAUUSD",
    ...     "action": 1,
    ...     "params": {"entry_price": 2650.00}
    ... }
    >>> 
    >>> secure_policy = generate_secure_policy(
    ...     base_policy=base_policy,
    ...     license_id="FLASH-2601-TEST-0001"
    ... )
    >>> 
    >>> print(secure_policy['sequence'])
    1
    >>> print(secure_policy['nonce'])
    '550e8400-e29b-41d4-a716-446655440000'
    >>> print(len(secure_policy['signature']))
    344

Advanced Usage (Custom Components):
    >>> from core.policy import SecurePolicyGenerator
    >>> 
    >>> generator = SecurePolicyGenerator()
    >>> 
    >>> # Generate multiple policies
    >>> for i in range(10):
    ...     policy = generator.generate_secure_policy(
    ...         base_policy={"symbol": "XAUUSD", "action": 1},
    ...         license_id="FLASH-2601-TEST-0001"
    ...     )
    ...     print(f"Policy {i+1}: sequence={policy['sequence']}")
    >>> 
    >>> # Save sequences before shutdown
    >>> generator.save_sequences()
    >>> 
    >>> # Get statistics
    >>> stats = generator.get_stats()
    >>> print(f"Generated {stats['policies_generated']} policies")

Individual Components:
    >>> from core.policy import NonceManager, SequenceTracker, PolicySigner
    >>> 
    >>> # Nonce generation
    >>> nonce_mgr = NonceManager()
    >>> nonce = nonce_mgr.generate_nonce()
    >>> 
    >>> # Sequence tracking
    >>> seq_tracker = SequenceTracker()
    >>> seq = seq_tracker.get_next_sequence("FLASH-2601-TEST-0001", "XAUUSD")
    >>> 
    >>> # Policy signing
    >>> signer = PolicySigner()
    >>> signature = signer.sign_policy({"symbol": "XAUUSD", "action": 1})

Security Features
=================

1. Anti-Replay Protection:
   - Each policy has unique nonce (UUID v4)
   - Sequence numbers always increment
   - Timestamp validation (< 5 minutes)
   
2. Integrity Protection:
   - RSA-2048 signature
   - SHA256 hash
   - PKCS1v15 padding
   
3. Performance:
   - Nonce generation: ~0.001ms
   - Sequence lookup: ~0.01ms (cached)
   - Signature generation: ~2-5ms
   - Total: <10ms per policy

Implementation Notes
====================

- Private key must be kept SECRET on server
- Public key is embedded in MQL5 EA
- Sequence database persists across restarts
- Auto-save happens every 5 seconds
- Manual save recommended before shutdown

License ID Format
=================

Format: FLASH-YYMM-TYPE-XXXX

Examples:
- FLASH-2601-TEST-0001 (Test license, January 2026)
- FLASH-2601-C5F5-A3B2 (Production license)

Type Codes:
- TEST: Test/development
- C5F5: Standalone
- TRIAL: Trial version
- PREM: Premium

For More Information
====================

See individual module documentation:
- nonce_manager.py: UUID v4 generation
- sequence_tracker.py: SQLite-based tracking
- policy_signer.py: RSA signature
- policy_generator.py: Integration
"""
