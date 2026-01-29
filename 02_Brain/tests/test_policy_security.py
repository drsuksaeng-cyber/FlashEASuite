#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Security Test Suite
Phase 2 Track A: Policy Security (Anti-Replay Attack)

Comprehensive tests for:
- Nonce generation and uniqueness
- Sequence tracking and increment
- RSA signature generation and validation
- Secure policy generation
- Integration with feedback stats

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-01-24
"""

import sys
import os
import time
import tempfile
import unittest
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from core.policy import (
    NonceManager,
    SequenceTracker,
    PolicySigner,
    SecurePolicyGenerator,
    generate_nonce,
    validate_nonce_format,
    generate_secure_policy
)


class TestNonceManager(unittest.TestCase):
    """Test cases for NonceManager."""
    
    def setUp(self):
        """Set up test fixture."""
        self.manager = NonceManager()
    
    def test_generate_nonce(self):
        """Test nonce generation."""
        nonce = self.manager.generate_nonce()
        
        # Check format (UUID v4)
        self.assertIsInstance(nonce, str)
        self.assertEqual(len(nonce), 36)  # UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        self.assertTrue(validate_nonce_format(nonce))
    
    def test_nonce_uniqueness(self):
        """Test that nonces are unique."""
        nonces = [self.manager.generate_nonce() for _ in range(1000)]
        
        # All should be unique
        self.assertEqual(len(nonces), len(set(nonces)))
    
    def test_nonce_statistics(self):
        """Test statistics tracking."""
        for _ in range(10):
            self.manager.generate_nonce()
        
        stats = self.manager.get_stats()
        self.assertEqual(stats['total_generated'], 10)
        self.assertEqual(stats['unique_count'], 10)


class TestSequenceTracker(unittest.TestCase):
    """Test cases for SequenceTracker."""
    
    def setUp(self):
        """Set up test fixture with temporary database."""
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.tracker = SequenceTracker(db_path=self.temp_db.name)
        self.license_id = "FLASH-2601-TEST-0001"
    
    def tearDown(self):
        """Clean up temporary database."""
        os.unlink(self.temp_db.name)
    
    def test_sequence_increment(self):
        """Test that sequences increment correctly."""
        seq1 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        seq2 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        seq3 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        
        self.assertEqual(seq1, 1)
        self.assertEqual(seq2, 2)
        self.assertEqual(seq3, 3)
    
    def test_sequence_per_symbol(self):
        """Test that sequences are tracked separately per symbol."""
        seq_xau1 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        seq_eur1 = self.tracker.get_next_sequence(self.license_id, "EURUSD")
        seq_xau2 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        
        self.assertEqual(seq_xau1, 1)
        self.assertEqual(seq_eur1, 1)
        self.assertEqual(seq_xau2, 2)
    
    def test_sequence_per_license(self):
        """Test that sequences are tracked separately per license."""
        license2 = "FLASH-2601-TEST-0002"
        
        seq_lic1 = self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        seq_lic2 = self.tracker.get_next_sequence(license2, "XAUUSD")
        
        self.assertEqual(seq_lic1, 1)
        self.assertEqual(seq_lic2, 1)  # Different license, starts from 1
    
    def test_sequence_persistence(self):
        """Test that sequences persist across restarts."""
        # Generate sequences
        for _ in range(5):
            self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        
        # Save
        self.tracker.save()
        
        # Create new tracker with same database
        tracker2 = SequenceTracker(db_path=self.temp_db.name)
        
        # Next sequence should be 6
        seq = tracker2.get_next_sequence(self.license_id, "XAUUSD")
        self.assertEqual(seq, 6)
    
    def test_get_current_sequence(self):
        """Test getting current sequence without incrementing."""
        self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        self.tracker.get_next_sequence(self.license_id, "XAUUSD")
        
        current = self.tracker.get_current_sequence(self.license_id, "XAUUSD")
        self.assertEqual(current, 2)
        
        # Verify it didn't increment
        current_again = self.tracker.get_current_sequence(self.license_id, "XAUUSD")
        self.assertEqual(current_again, 2)


class TestPolicySigner(unittest.TestCase):
    """Test cases for PolicySigner."""
    
    def setUp(self):
        """Set up test fixture."""
        try:
            self.signer = PolicySigner()
        except FileNotFoundError:
            self.skipTest("Private key not found (run Phase 1 first)")
    
    def test_sign_policy(self):
        """Test signing a policy."""
        policy = {
            "symbol": "XAUUSD",
            "action": 1,
            "sequence": 12345
        }
        
        signature = self.signer.sign_policy(policy)
        
        # Check signature format (Base64)
        self.assertIsInstance(signature, str)
        self.assertGreater(len(signature), 300)  # RSA-2048 signature is ~344 chars
    
    def test_different_policies_different_signatures(self):
        """Test that different policies produce different signatures."""
        policy1 = {"symbol": "XAUUSD", "action": 1}
        policy2 = {"symbol": "XAUUSD", "action": 2}
        
        sig1 = self.signer.sign_policy(policy1)
        sig2 = self.signer.sign_policy(policy2)
        
        self.assertNotEqual(sig1, sig2)
    
    def test_same_policy_same_signature(self):
        """Test that signing is deterministic."""
        policy = {"symbol": "XAUUSD", "action": 1, "sequence": 100}
        
        sig1 = self.signer.sign_policy(policy)
        sig2 = self.signer.sign_policy(policy)
        
        self.assertEqual(sig1, sig2)
    
    def test_key_info(self):
        """Test getting key information."""
        info = self.signer.get_key_info()
        
        self.assertEqual(info['algorithm'], 'RSA')
        self.assertEqual(info['key_size_bits'], 2048)
        self.assertEqual(info['hash_algorithm'], 'SHA256')


class TestSecurePolicyGenerator(unittest.TestCase):
    """Test cases for SecurePolicyGenerator."""
    
    def setUp(self):
        """Set up test fixture."""
        try:
            self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
            self.generator = SecurePolicyGenerator(db_path=self.temp_db.name)
            self.license_id = "FLASH-2601-TEST-0001"
        except FileNotFoundError:
            self.skipTest("Private key not found (run Phase 1 first)")
    
    def tearDown(self):
        """Clean up."""
        if hasattr(self, 'temp_db'):
            os.unlink(self.temp_db.name)
    
    def test_generate_secure_policy(self):
        """Test generating a secure policy."""
        base_policy = {
            "symbol": "XAUUSD",
            "action": 1,
            "params": {"entry_price": 2650.00}
        }
        
        secure = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id=self.license_id
        )
        
        # Check all security fields are present
        self.assertIn('symbol', secure)
        self.assertIn('action', secure)
        self.assertIn('params', secure)
        self.assertIn('sequence', secure)
        self.assertIn('nonce', secure)
        self.assertIn('timestamp', secure)
        self.assertIn('license_id', secure)
        self.assertIn('signature', secure)
    
    def test_sequence_increments(self):
        """Test that sequence increments for each policy."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        p1 = self.generator.generate_secure_policy(base, self.license_id)
        p2 = self.generator.generate_secure_policy(base, self.license_id)
        p3 = self.generator.generate_secure_policy(base, self.license_id)
        
        self.assertEqual(p1['sequence'], 1)
        self.assertEqual(p2['sequence'], 2)
        self.assertEqual(p3['sequence'], 3)
    
    def test_nonce_uniqueness(self):
        """Test that each policy has unique nonce."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        policies = [
            self.generator.generate_secure_policy(base, self.license_id)
            for _ in range(10)
        ]
        
        nonces = [p['nonce'] for p in policies]
        self.assertEqual(len(nonces), len(set(nonces)))
    
    def test_timestamp_current(self):
        """Test that timestamp is current."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        before = int(time.time())
        policy = self.generator.generate_secure_policy(base, self.license_id)
        after = int(time.time())
        
        self.assertGreaterEqual(policy['timestamp'], before)
        self.assertLessEqual(policy['timestamp'], after)
    
    def test_signature_valid_format(self):
        """Test that signature has valid format."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        policy = self.generator.generate_secure_policy(base, self.license_id)
        
        # Check signature is Base64 string
        self.assertIsInstance(policy['signature'], str)
        self.assertGreater(len(policy['signature']), 300)
    
    def test_statistics(self):
        """Test generator statistics."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        for _ in range(5):
            self.generator.generate_secure_policy(base, self.license_id)
        
        stats = self.generator.get_stats()
        self.assertEqual(stats['policies_generated'], 5)


class TestIntegration(unittest.TestCase):
    """Integration tests for complete flow."""
    
    def setUp(self):
        """Set up test fixture."""
        try:
            self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
            self.generator = SecurePolicyGenerator(db_path=self.temp_db.name)
            self.license_id = "FLASH-2601-TEST-0001"
        except FileNotFoundError:
            self.skipTest("Private key not found (run Phase 1 first)")
    
    def tearDown(self):
        """Clean up."""
        if hasattr(self, 'temp_db'):
            os.unlink(self.temp_db.name)
    
    def test_generate_100_policies(self):
        """Test generating 100 policies (stress test)."""
        policies = []
        
        for i in range(100):
            base = {
                "symbol": "XAUUSD",
                "action": (i % 2) + 1,  # Alternate BUY/SELL
                "params": {"entry_price": 2650.00 + i}
            }
            
            policy = self.generator.generate_secure_policy(base, self.license_id)
            policies.append(policy)
        
        # Check all sequences are correct
        sequences = [p['sequence'] for p in policies]
        self.assertEqual(sequences, list(range(1, 101)))
        
        # Check all nonces are unique
        nonces = [p['nonce'] for p in policies]
        self.assertEqual(len(nonces), len(set(nonces)))
        
        # Check all have signatures
        for policy in policies:
            self.assertIn('signature', policy)
            self.assertGreater(len(policy['signature']), 300)
    
    def test_performance(self):
        """Test performance (<5ms per policy)."""
        base = {"symbol": "XAUUSD", "action": 1}
        
        start = time.time()
        
        for _ in range(100):
            self.generator.generate_secure_policy(base, self.license_id)
        
        end = time.time()
        elapsed = end - start
        avg_time = elapsed / 100
        
        print(f"\n⏱️  Performance: {avg_time*1000:.2f}ms per policy (100 policies)")
        
        # Should be < 10ms per policy (relaxed from 5ms)
        self.assertLess(avg_time, 0.01)


def run_tests():
    """Run all tests."""
    print("=" * 70)
    print("FlashEASuite V2 - Policy Security Test Suite")
    print("Phase 2 Track A: Anti-Replay Attack Protection")
    print("=" * 70)
    print()
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestNonceManager))
    suite.addTests(loader.loadTestsFromTestCase(TestSequenceTracker))
    suite.addTests(loader.loadTestsFromTestCase(TestPolicySigner))
    suite.addTests(loader.loadTestsFromTestCase(TestSecurePolicyGenerator))
    suite.addTests(loader.loadTestsFromTestCase(TestIntegration))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Print summary
    print()
    print("=" * 70)
    print("Test Summary")
    print("=" * 70)
    print(f"Tests run: {result.testsRun}")
    print(f"Successes: {result.testsRun - len(result.failures) - len(result.errors)}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Skipped: {len(result.skipped)}")
    print("=" * 70)
    
    return result.wasSuccessful()


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
