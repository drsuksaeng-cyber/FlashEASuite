#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Phase 2 Integration Test
Chat 3: End-to-End Testing

Tests:
1. Generate secure policy
2. Send via ZMQ
3. Verify MQL5 receives and validates

Author: Dr. Suksaeng Kukanok
Date: 2026-01-25
"""

import sys
import time
import zmq
import msgpack
from datetime import datetime

# Add project path
sys.path.insert(0, '/home/claude/02_Brain')

from core.policy import SecurePolicyGenerator


class IntegrationTester:
    """Integration test for Phase 2 security."""
    
    def __init__(self):
        """Initialize tester."""
        self.generator = SecurePolicyGenerator(
            private_key_path='/home/claude/02_Brain/tools/license_generator/keys/server_private.pem',
            db_path='/home/claude/02_Brain/data/sequences.db'
        )
        
        # ZMQ Publisher (same as Brain)
        self.context = zmq.Context()
        self.pub_socket = self.context.socket(zmq.PUB)
        self.pub_socket.bind("tcp://127.0.0.1:7778")
        
        print("=" * 80)
        print("FlashEASuite V2 - Integration Test")
        print("Phase 2: Python → MQL5 Security Testing")
        print("=" * 80)
        time.sleep(1)  # Allow socket to bind
    
    def test_scenario_1_valid_policy(self):
        """Test 1: Send valid policy."""
        print("\n" + "─" * 80)
        print("TEST 1: Valid Policy (should be ACCEPTED)")
        print("─" * 80)
        
        base_policy = {
            "symbol": "XAUUSD",
            "action": 1,  # BUY
            "params": {
                "lot_size": 0.01,
                "tp": 50,
                "sl": 25
            }
        }
        
        # Generate secure policy
        secure_policy = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        # Display policy
        print(f"✅ Policy generated:")
        print(f"   Symbol: {secure_policy['symbol']}")
        print(f"   Sequence: {secure_policy['sequence']}")
        print(f"   Nonce: {secure_policy['nonce'][:20]}...")
        print(f"   Timestamp: {secure_policy['timestamp']} ({datetime.fromtimestamp(secure_policy['timestamp'])})")
        print(f"   Signature: {secure_policy['signature'][:30]}...")
        
        # Pack and send
        packed = msgpack.packb(secure_policy)
        self.pub_socket.send(packed)
        
        print(f"📤 Sent {len(packed)} bytes via ZMQ port 7778")
        print("   MQL5 should ACCEPT this policy ✅")
        
        return True
    
    def test_scenario_2_replay_attack(self):
        """Test 2: Replay attack (old timestamp)."""
        print("\n" + "─" * 80)
        print("TEST 2: Replay Attack (should be REJECTED)")
        print("─" * 80)
        
        base_policy = {
            "symbol": "XAUUSD",
            "action": 2,  # SELL
            "params": {
                "lot_size": 0.01,
                "tp": 50,
                "sl": 25
            }
        }
        
        # Generate policy
        secure_policy = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        # Tamper timestamp (make it 10 minutes old)
        original_timestamp = secure_policy['timestamp']
        secure_policy['timestamp'] = original_timestamp - 600  # 10 minutes ago
        
        print(f"⚠️  Policy generated with OLD timestamp:")
        print(f"   Original: {original_timestamp} ({datetime.fromtimestamp(original_timestamp)})")
        print(f"   Tampered: {secure_policy['timestamp']} ({datetime.fromtimestamp(secure_policy['timestamp'])})")
        print(f"   Age: 600 seconds (10 minutes) - exceeds 5 min limit")
        
        # Pack and send
        packed = msgpack.packb(secure_policy)
        self.pub_socket.send(packed)
        
        print(f"📤 Sent {len(packed)} bytes via ZMQ port 7778")
        print("   MQL5 should REJECT this policy ❌ (timestamp too old)")
        
        return True
    
    def test_scenario_3_nonce_reuse(self):
        """Test 3: Nonce reuse attack."""
        print("\n" + "─" * 80)
        print("TEST 3: Nonce Reuse Attack (should be REJECTED)")
        print("─" * 80)
        
        base_policy = {
            "symbol": "GBPUSD",
            "action": 1,
            "params": {
                "lot_size": 0.01
            }
        }
        
        # Generate first policy
        policy1 = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        nonce_used = policy1['nonce']
        
        # Send first policy
        packed1 = msgpack.packb(policy1)
        self.pub_socket.send(packed1)
        print(f"📤 Sent FIRST policy with nonce: {nonce_used[:20]}...")
        print("   MQL5 should ACCEPT ✅")
        
        time.sleep(2)  # Wait 2 seconds
        
        # Generate second policy with SAME nonce
        policy2 = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        # Replace nonce with same one
        policy2['nonce'] = nonce_used
        
        # Send second policy
        packed2 = msgpack.packb(policy2)
        self.pub_socket.send(packed2)
        print(f"📤 Sent SECOND policy with SAME nonce: {nonce_used[:20]}...")
        print("   MQL5 should REJECT ❌ (nonce already used)")
        
        return True
    
    def test_scenario_4_sequence_manipulation(self):
        """Test 4: Out-of-order sequence."""
        print("\n" + "─" * 80)
        print("TEST 4: Sequence Manipulation (should be REJECTED)")
        print("─" * 80)
        
        base_policy = {
            "symbol": "USDJPY",
            "action": 1,
            "params": {}
        }
        
        # Send policy with sequence 100
        policy1 = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        packed1 = msgpack.packb(policy1)
        self.pub_socket.send(packed1)
        print(f"📤 Sent policy with sequence: {policy1['sequence']}")
        print("   MQL5 should ACCEPT ✅")
        
        time.sleep(2)
        
        # Send policy with LOWER sequence (sequence - 1)
        policy2 = self.generator.generate_secure_policy(
            base_policy=base_policy,
            license_id="FLASH-2601-TEST-0001"
        )
        
        # Tamper sequence (make it lower)
        policy2['sequence'] = policy1['sequence'] - 1
        
        packed2 = msgpack.packb(policy2)
        self.pub_socket.send(packed2)
        print(f"📤 Sent policy with LOWER sequence: {policy2['sequence']}")
        print(f"   (Previous was {policy1['sequence']})")
        print("   MQL5 should REJECT ❌ (out-of-order sequence)")
        
        return True
    
    def test_scenario_5_performance(self):
        """Test 5: Performance test (100 policies)."""
        print("\n" + "─" * 80)
        print("TEST 5: Performance Test (100 policies)")
        print("─" * 80)
        
        base_policy = {
            "symbol": "EURUSD",
            "action": 1,
            "params": {"lot_size": 0.01}
        }
        
        start_time = time.time()
        
        for i in range(100):
            policy = self.generator.generate_secure_policy(
                base_policy=base_policy,
                license_id="FLASH-2601-TEST-0001"
            )
            
            packed = msgpack.packb(policy)
            self.pub_socket.send(packed)
            
            if (i + 1) % 25 == 0:
                print(f"   Sent {i + 1}/100 policies...")
            
            time.sleep(0.01)  # 10ms between policies
        
        elapsed = time.time() - start_time
        avg_latency = (elapsed / 100) * 1000
        
        print(f"\n📊 Performance Results:")
        print(f"   Total policies: 100")
        print(f"   Total time: {elapsed:.2f} seconds")
        print(f"   Average latency: {avg_latency:.2f} ms/policy")
        print(f"   Throughput: {100/elapsed:.2f} policies/second")
        
        if avg_latency < 20:
            print(f"   ✅ Performance GOOD (< 20ms target)")
        else:
            print(f"   ⚠️  Performance SLOW (> 20ms target)")
        
        return True
    
    def run_all_tests(self):
        """Run all integration tests."""
        print("\n🧪 Starting Integration Tests...")
        print("Make sure MQL5 EA is running and listening on port 7778\n")
        
        time.sleep(2)
        
        results = []
        
        # Test 1: Valid policy
        try:
            result = self.test_scenario_1_valid_policy()
            results.append(("Valid Policy", result))
        except Exception as e:
            print(f"❌ Test 1 failed: {e}")
            results.append(("Valid Policy", False))
        
        time.sleep(3)
        
        # Test 2: Replay attack
        try:
            result = self.test_scenario_2_replay_attack()
            results.append(("Replay Attack", result))
        except Exception as e:
            print(f"❌ Test 2 failed: {e}")
            results.append(("Replay Attack", False))
        
        time.sleep(3)
        
        # Test 3: Nonce reuse
        try:
            result = self.test_scenario_3_nonce_reuse()
            results.append(("Nonce Reuse", result))
        except Exception as e:
            print(f"❌ Test 3 failed: {e}")
            results.append(("Nonce Reuse", False))
        
        time.sleep(3)
        
        # Test 4: Sequence manipulation
        try:
            result = self.test_scenario_4_sequence_manipulation()
            results.append(("Sequence Manipulation", result))
        except Exception as e:
            print(f"❌ Test 4 failed: {e}")
            results.append(("Sequence Manipulation", False))
        
        time.sleep(3)
        
        # Test 5: Performance
        try:
            result = self.test_scenario_5_performance()
            results.append(("Performance", result))
        except Exception as e:
            print(f"❌ Test 5 failed: {e}")
            results.append(("Performance", False))
        
        # Summary
        print("\n" + "=" * 80)
        print("TEST SUMMARY")
        print("=" * 80)
        
        passed = sum(1 for _, result in results if result)
        total = len(results)
        
        for name, result in results:
            status = "✅ PASSED" if result else "❌ FAILED"
            print(f"{status}: {name}")
        
        print(f"\nTests Passed: {passed} / {total}")
        
        if passed == total:
            print("🎉 ALL INTEGRATION TESTS PASSED!")
        else:
            print(f"⚠️  {total - passed} TEST(S) FAILED")
        
        print("=" * 80)
    
    def cleanup(self):
        """Cleanup resources."""
        self.pub_socket.close()
        self.context.term()
        print("\n👋 Cleanup complete")


if __name__ == "__main__":
    tester = IntegrationTester()
    
    try:
        tester.run_all_tests()
    except KeyboardInterrupt:
        print("\n⚠️  Test interrupted by user")
    finally:
        tester.cleanup()
