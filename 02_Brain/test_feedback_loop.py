#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Test Script
Feedback Loop Verification

จำลอง MT5 Trader เพื่อทดสอบ Feedback Loop:
1. ส่ง fake trade results ไปยัง Python Brain
2. ตรวจสอบว่า Strategy ปรับตัวตาม feedback หรือไม่
3. Verify cooldown mechanism

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
"""

import zmq
import msgpack
import time
import random
from datetime import datetime
from typing import List, Dict, Any


class FeedbackLoopTester:
    """
    Test harness สำหรับทดสอบ Feedback Loop.
    
    จำลอง MT5 Trader โดยส่ง fake trade results ไปยัง Python Brain
    และตรวจสอบว่า Strategy ปรับตัวอย่างถูกต้อง.
    """
    
    def __init__(self):
        """Initialize test harness."""
        self.context = zmq.Context()
        
        # PUSH socket - ส่ง trade results ไปยัง Brain (port 7779)
        self.push_socket = None
        
        # SUB socket - รับ policy จาก Brain (port 7778)
        self.sub_socket = None
        
        # Test data
        self.test_ticket = 16373000
        self.message_count = 0
        
        print("=" * 70)
        print("🧪 FEEDBACK LOOP TESTER")
        print("=" * 70)
        print("Purpose: Test Python Brain's adaptation to trade results")
        print("=" * 70)
    
    def setup_sockets(self) -> bool:
        """
        Setup ZMQ sockets.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            # 1. PUSH socket (ส่ง trade results)
            print("\n[1/2] Setting up PUSH socket (Trade Results → Brain)...")
            self.push_socket = self.context.socket(zmq.PUSH)
            self.push_socket.connect("tcp://127.0.0.1:7779")
            print("   ✅ Connected to tcp://127.0.0.1:7779")
            
            # 2. SUB socket (รับ policy updates)
            print("\n[2/2] Setting up SUB socket (Brain → Policy)...")
            self.sub_socket = self.context.socket(zmq.SUB)
            self.sub_socket.connect("tcp://127.0.0.1:7778")
            self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")  # Subscribe to all
            self.sub_socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1 second timeout
            print("   ✅ Connected to tcp://127.0.0.1:7778")
            
            # Give sockets time to connect
            time.sleep(1)
            
            print("\n✅ All sockets ready!")
            return True
            
        except Exception as e:
            print(f"\n❌ Error setting up sockets: {e}")
            return False
    
    def send_trade_result(
        self,
        symbol: str = "XAUUSD",
        trade_type: int = 0,  # 0=BUY, 1=SELL
        profit: float = 0.0,
        volume: float = 0.01
    ) -> None:
        """
        ส่ง fake trade result ไปยัง Brain.
        
        Args:
            symbol: Symbol name
            trade_type: 0=BUY, 1=SELL
            profit: Profit/loss amount
            volume: Lot size
        """
        self.test_ticket += 1
        self.message_count += 1
        
        # สร้าง MessagePack payload (format เดียวกับ MT5)
        timestamp_ms = int(time.time() * 1000)
        
        data = [
            100,                    # [0] msg_type (TRADE_RESULT)
            timestamp_ms,           # [1] timestamp
            self.test_ticket,       # [2] ticket
            symbol,                 # [3] symbol
            trade_type,             # [4] type (0=BUY, 1=SELL)
            volume,                 # [5] volume
            2650.50,                # [6] open_price (fake)
            2645.00,                # [7] sl (fake)
            2655.00,                # [8] tp (fake)
            profit,                 # [9] profit ⭐ KEY FIELD
            999000,                 # [10] magic
            f"Test_{self.test_ticket}"  # [11] comment
        ]
        
        # Pack และส่ง
        packed = msgpack.packb(data)
        self.push_socket.send(packed)
        
        # Display
        result_type = "💚 WIN" if profit > 0 else "💔 LOSS" if profit < 0 else "⚪ BE"
        print(f"\n{'='*60}")
        print(f"📤 [Message #{self.message_count}] Sent to Brain: {result_type}")
        print(f"{'='*60}")
        print(f"   Ticket:  {self.test_ticket}")
        print(f"   Symbol:  {symbol}")
        print(f"   Type:    {'BUY' if trade_type == 0 else 'SELL'}")
        print(f"   Profit:  {profit:+.2f}")
        print(f"{'='*60}")
    
    def listen_for_policy_changes(self, duration: float = 2.0) -> None:
        """
        ฟัง policy updates จาก Brain.
        
        Args:
            duration: ระยะเวลาที่จะฟัง (seconds)
        """
        print(f"\n👂 Listening for policy changes ({duration}s)...")
        
        start_time = time.time()
        policy_count = 0
        
        while time.time() - start_time < duration:
            try:
                raw_data = self.sub_socket.recv()
                policy = msgpack.unpackb(raw_data, raw=False)
                
                policy_count += 1
                
                # แสดง policy
                policy_type = policy.get('type', 'UNKNOWN')
                symbol = policy.get('symbol', 'N/A')
                action = policy.get('action', 0)
                confidence = policy.get('confidence', 0.0)
                debug_info = policy.get('debug_info', '')
                
                if policy_type == 'POLICY' and symbol != 'CSM_MONITOR':
                    action_str = "BUY" if action == 1 else "SELL" if action == 2 else "HOLD"
                    print(f"   📡 Policy #{policy_count}: {action_str} {symbol} | "
                          f"Conf: {confidence*100:.0f}% | {debug_info}")
                    
            except zmq.Again:
                # Timeout - no data
                continue
            except Exception as e:
                print(f"   ⚠️ Error receiving policy: {e}")
        
        if policy_count == 0:
            print(f"   ℹ️ No policies received (this is normal during cooldown)")
    
    def cleanup(self) -> None:
        """Clean up resources."""
        print("\n🧹 Cleaning up...")
        
        if self.push_socket:
            self.push_socket.close()
        if self.sub_socket:
            self.sub_socket.close()
        
        self.context.term()
        print("✅ Cleanup complete")
    
    # =============================
    # Test Scenarios
    # =============================
    
    def test_scenario_1_single_win(self) -> None:
        """
        Test Scenario 1: Single Win
        
        Expected:
        - Brain receives WIN
        - consecutive_wins = 1
        - risk_multiplier increases slightly
        - No cooldown
        """
        print("\n" + "="*70)
        print("📋 TEST SCENARIO 1: Single Win")
        print("="*70)
        print("Expected: Risk increase, No cooldown")
        print("="*70)
        
        input("\nPress Enter to send WIN trade result...")
        
        self.send_trade_result(
            symbol="XAUUSD",
            trade_type=0,  # BUY
            profit=15.75   # WIN
        )
        
        time.sleep(2)
        print("\n✅ Scenario 1 complete")
        print("   Check Brain output for: 💚 WIN, Risk increase")
    
    def test_scenario_2_win_streak(self) -> None:
        """
        Test Scenario 2: Win Streak (3 consecutive wins)
        
        Expected:
        - Brain detects hot streak
        - risk_multiplier increases significantly
        - "🔥 HOT STREAK!" message
        """
        print("\n" + "="*70)
        print("📋 TEST SCENARIO 2: Win Streak (3 Wins)")
        print("="*70)
        print("Expected: Hot Streak detection, Higher risk")
        print("="*70)
        
        input("\nPress Enter to send 3 WIN results...")
        
        for i in range(3):
            print(f"\n[Win {i+1}/3]")
            self.send_trade_result(
                symbol="XAUUSD",
                trade_type=0,
                profit=random.uniform(10.0, 25.0)  # Random win
            )
            time.sleep(1)
        
        time.sleep(2)
        print("\n✅ Scenario 2 complete")
        print("   Check Brain output for: 🔥 HOT STREAK!, Risk > 1.3x")
    
    def test_scenario_3_single_loss(self) -> None:
        """
        Test Scenario 3: Single Loss
        
        Expected:
        - Brain receives LOSS
        - Cooldown activated (30 seconds)
        - risk_multiplier decreases
        - "⚠️ COOLDOWN ACTIVATED" message
        """
        print("\n" + "="*70)
        print("📋 TEST SCENARIO 3: Single Loss")
        print("="*70)
        print("Expected: Cooldown 30s, Risk decrease")
        print("="*70)
        
        input("\nPress Enter to send LOSS trade result...")
        
        self.send_trade_result(
            symbol="XAUUSD",
            trade_type=1,  # SELL
            profit=-12.50  # LOSS
        )
        
        time.sleep(2)
        print("\n✅ Scenario 3 complete")
        print("   Check Brain output for: 💔 LOSS, ⚠️ COOLDOWN")
        print("   Cooldown should last 30 seconds")
    
    def test_scenario_4_losing_streak(self) -> None:
        """
        Test Scenario 4: Losing Streak (3 consecutive losses)
        
        Expected:
        - Emergency cooldown (300 seconds)
        - risk_multiplier drops to minimum
        - "🚨 EMERGENCY COOLDOWN!" message
        """
        print("\n" + "="*70)
        print("📋 TEST SCENARIO 4: Losing Streak (3 Losses)")
        print("="*70)
        print("Expected: EMERGENCY COOLDOWN 300s, Risk = 0.5x")
        print("="*70)
        
        input("\nPress Enter to send 3 LOSS results...")
        
        for i in range(3):
            print(f"\n[Loss {i+1}/3]")
            self.send_trade_result(
                symbol="XAUUSD",
                trade_type=0,
                profit=-random.uniform(10.0, 20.0)  # Random loss
            )
            time.sleep(1)
        
        time.sleep(2)
        print("\n✅ Scenario 4 complete")
        print("   Check Brain output for: 🚨 EMERGENCY!, 🛑 300s cooldown")
    
    def test_scenario_5_mixed_results(self) -> None:
        """
        Test Scenario 5: Mixed Win/Loss
        
        Expected:
        - Risk adapts dynamically
        - Cooldown triggers and cancels
        - System remains stable
        """
        print("\n" + "="*70)
        print("📋 TEST SCENARIO 5: Mixed Win/Loss")
        print("="*70)
        print("Expected: Dynamic adaptation, Stable operation")
        print("="*70)
        
        input("\nPress Enter to send mixed results...")
        
        results = [
            ("WIN", 15.0),
            ("LOSS", -10.0),
            ("WIN", 20.0),
            ("WIN", 12.0),
            ("LOSS", -8.0),
        ]
        
        for i, (result_type, profit) in enumerate(results, 1):
            print(f"\n[Trade {i}/{len(results)}]: {result_type}")
            self.send_trade_result(
                symbol="XAUUSD",
                trade_type=random.choice([0, 1]),
                profit=profit
            )
            time.sleep(1.5)
        
        time.sleep(2)
        print("\n✅ Scenario 5 complete")
        print("   Check Brain output for dynamic risk adjustments")
    
    # =============================
    # Main Test Runner
    # =============================
    
    def run_all_tests(self) -> None:
        """Run all test scenarios."""
        try:
            # Setup
            if not self.setup_sockets():
                print("\n❌ Failed to setup sockets. Is main.py running?")
                return
            
            print("\n" + "="*70)
            print("🚀 STARTING TEST SUITE")
            print("="*70)
            print("\nIMPORTANT: Make sure main.py is running in another terminal!")
            print("=" * 70)
            
            input("\nPress Enter to start tests...")
            
            # Run scenarios
            self.test_scenario_1_single_win()
            time.sleep(3)
            
            self.test_scenario_2_win_streak()
            time.sleep(3)
            
            self.test_scenario_3_single_loss()
            print("\n⏳ Waiting for cooldown to expire (30s)...")
            time.sleep(35)  # Wait for cooldown
            
            self.test_scenario_4_losing_streak()
            print("\n⚠️ EMERGENCY COOLDOWN active!")
            print("   Skipping remaining tests (system in emergency mode)")
            
            # Final summary
            print("\n" + "="*70)
            print("✅ TEST SUITE COMPLETE")
            print("="*70)
            print(f"Total trade results sent: {self.message_count}")
            print("\nPlease verify in Brain output:")
            print("  - 💚 WIN messages appeared")
            print("  - 💔 LOSS messages appeared")
            print("  - ⚠️ COOLDOWN activated after loss")
            print("  - 🚨 EMERGENCY triggered after 3 losses")
            print("  - 📊 Statistics updated correctly")
            print("="*70)
            
        except KeyboardInterrupt:
            print("\n\n⚠️ Test interrupted by user")
        
        finally:
            self.cleanup()
    
    def run_interactive_mode(self) -> None:
        """Interactive mode - manual testing."""
        try:
            if not self.setup_sockets():
                print("\n❌ Failed to setup sockets. Is main.py running?")
                return
            
            print("\n" + "="*70)
            print("🎮 INTERACTIVE MODE")
            print("="*70)
            print("\nCommands:")
            print("  w <amount>  - Send WIN with profit amount (e.g., 'w 15.75')")
            print("  l <amount>  - Send LOSS with loss amount (e.g., 'l 12.50')")
            print("  auto        - Run automated test suite")
            print("  quit        - Exit")
            print("="*70)
            
            while True:
                try:
                    cmd = input("\n>>> ").strip().lower()
                    
                    if cmd == 'quit' or cmd == 'q':
                        break
                    
                    elif cmd == 'auto':
                        self.run_all_tests()
                        break
                    
                    elif cmd.startswith('w '):
                        try:
                            profit = float(cmd.split()[1])
                            self.send_trade_result(profit=profit)
                            time.sleep(1)
                        except (IndexError, ValueError):
                            print("❌ Usage: w <amount>  (e.g., 'w 15.75')")
                    
                    elif cmd.startswith('l '):
                        try:
                            loss = -abs(float(cmd.split()[1]))
                            self.send_trade_result(profit=loss)
                            time.sleep(1)
                        except (IndexError, ValueError):
                            print("❌ Usage: l <amount>  (e.g., 'l 12.50')")
                    
                    else:
                        print("❌ Unknown command. Type 'w <amount>', 'l <amount>', 'auto', or 'quit'")
                
                except KeyboardInterrupt:
                    print("\n")
                    break
            
        finally:
            self.cleanup()


def main():
    """Main entry point."""
    print("""
    ╔════════════════════════════════════════════════════════════════╗
    ║                  FEEDBACK LOOP TESTER                         ║
    ║          FlashEASuite V2 - Quality Assurance Tool             ║
    ╚════════════════════════════════════════════════════════════════╝
    
    This script tests the Feedback Loop by sending fake trade results
    to the Python Brain and verifying its adaptive behavior.
    
    Prerequisites:
    1. Start main.py in another terminal first
    2. Make sure ports 7778 and 7779 are available
    
    """)
    
    print("Select mode:")
    print("  1. Automated Test Suite (recommended)")
    print("  2. Interactive Mode (manual testing)")
    
    try:
        choice = input("\nYour choice (1/2): ").strip()
    except KeyboardInterrupt:
        print("\n\nExiting...")
        return
    
    tester = FeedbackLoopTester()
    
    if choice == '1':
        tester.run_all_tests()
    elif choice == '2':
        tester.run_interactive_mode()
    else:
        print("Invalid choice. Exiting.")


if __name__ == "__main__":
    main()
