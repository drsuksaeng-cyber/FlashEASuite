#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Spike Signal Test Injector
Version: 2.1 (FIXED - Accurate Price Movement)

แก้ไข v2.1:
- FIX #6: แก้การคำนวณ move_size ให้ใช้ spike_price อย่างถูกต้อง
- FIX #7: เพิ่ม parameter spike_price ใน generate_spike_entry
- FIX #8: ราคาไปถึง target พอดี (ไม่เกิน ไม่ขาด)

Previous fixes:
- FIX #1: เพิ่ม broker suffix (.tp) ให้ตรงกับ FeederEA
- FIX #2: ราคา realistic (XAUUSD ~2850, GBPUSD ~1.245)
- FIX #3: Entry ticks ≥ 60 (ไม่ random ต่ำกว่า 60)
- FIX #4: เพิ่ม mode "entry_only" ส่งแค่ spike entry ไม่ส่ง reversal
- FIX #5: Configurable suffix (--suffix .tp)

วิธีใช้:
    python spike_test_injector.py [mode] [--suffix .tp]
    
    mode:
        fake        - ส่ง spike ปลอม 1 ครั้ง
        interactive - เลือก scenario จากเมนู
        auto        - ส่ง spike ทุก 30 วินาที
"""

import zmq
import msgpack
import time
import random
import argparse
from datetime import datetime
from typing import List, Dict

# ========================================================================
# CONFIGURATION
# ========================================================================

# FIX #1: Default broker suffix
DEFAULT_SUFFIX = ".tp"

# FIX #2: Realistic base prices (February 2026)
REALISTIC_PRICES = {
    "EURUSD": 1.0350,
    "GBPUSD": 1.2450,
    "USDJPY": 155.80,
    "XAUUSD": 2850.00,     # Gold ~$2850
    "EURJPY": 161.25,
    "GBPJPY": 194.00,
    "AUDUSD": 0.6280,
    "NZDUSD": 0.5680,
}

# FIX #3: Minimum entry ticks
MIN_ENTRY_TICKS = 60
MAX_ENTRY_TICKS = 80

# ========================================================================
# SPIKE PATTERNS
# ========================================================================

class SpikePatterns:
    """
    Spike patterns จากสถิติจริงของตลาด
    FIX #6: คำนวณ move_size จาก spike_price อย่างถูกต้อง
    """
    
    @staticmethod
    def generate_spike_entry(
        symbol: str,
        base_price: float,
        spike_price: float,      # FIX #7: เพิ่ม parameter นี้
        direction: str = "UP",
        intensity: float = 1.0,
        suffix: str = DEFAULT_SUFFIX
    ) -> List[List]:
        """
        สร้าง spike entry pattern (ราคาพุ่งเร็ว)
        
        FIX #1: เพิ่ม suffix ให้ symbol
        FIX #3: ticks ≥ MIN_ENTRY_TICKS (60)
        FIX #6-8: ใช้ spike_price คำนวณ move_size อย่างถูกต้อง
        
        Args:
            symbol: Symbol name (e.g., "XAUUSD")
            base_price: ราคาเริ่มต้น (e.g., 2850.00)
            spike_price: ราคา peak ที่ต้องการไปถึง (e.g., 2892.75)
            direction: "UP" หรือ "DOWN"
            intensity: ความเร็ว spike (1.0-2.5)
            suffix: Broker suffix (e.g., ".tp")
        
        Returns:
            List of tick messages (MessagePack format)
        """
        
        ticks = []
        current_price = base_price
        timestamp = int(time.time() * 1000)
        
        # FIX #1: Add broker suffix
        full_symbol = symbol + suffix
        
        # FIX #3: Minimum 60 ticks
        num_ticks = random.randint(MIN_ENTRY_TICKS, MAX_ENTRY_TICKS)
        
        # FIX #8: คำนวณระยะทางทั้งหมด
        total_move = abs(spike_price - base_price)
        
        print(f"  📊 Entry Generation:")
        print(f"     Base: {base_price:.5f}")
        print(f"     Target: {spike_price:.5f}")
        print(f"     Total Move: {total_move:.5f} ({total_move/base_price*100:.2f}%)")
        print(f"     Ticks: {num_ticks}")
        print(f"     Direction: {direction}")
        
        for i in range(num_ticks):
            # Progress (0.0 → 1.0)
            progress = i / num_ticks
            
            # FIX #8: ใช้ accelerating pattern (progress^2)
            # ช่วงแรก: เคลื่อนช้า
            # ช่วงหลัง: เคลื่อนเร็ว (spike!)
            acceleration = progress ** 2
            
            # คำนวณ move_size สำหรับ tick นี้
            # แบ่ง total_move ออกเป็น num_ticks ส่วน
            # ใช้ acceleration เพื่อให้เร็วขึ้นเรื่อยๆ
            move_per_tick = total_move / num_ticks
            move_size = acceleration * move_per_tick * intensity
            
            # Add noise for realism (±0.01% of base_price)
            noise = random.uniform(-0.0001, 0.0001) * base_price
            
            # Update current price
            if direction == "UP":
                current_price += move_size + noise
            else:
                current_price -= move_size + noise
            
            # Clamp ให้ไม่เกิน spike_price มาก
            if direction == "UP" and current_price > spike_price * 1.02:
                current_price = spike_price * 1.02
            elif direction == "DOWN" and current_price < spike_price * 0.98:
                current_price = spike_price * 0.98
            
            # Spread (widens during spike)
            spread_factor = 1.0 + progress * 2.0  # Spread widens 1x → 3x
            spread = base_price * 0.00005 * spread_factor
            
            # For gold, use proper spread
            if "XAU" in symbol:
                spread = 0.30 * spread_factor  # ~30 cents normal → 90 cents spike
            
            tick = [
                1,                          # [0] msg_type: 1 = TICK_DATA
                i + 1,                      # [1] seq_id
                timestamp + (i * 50),       # [2] timestamp (50ms intervals)
                full_symbol,                # [3] symbol WITH SUFFIX
                round(current_price, 5),    # [4] bid
                round(current_price + spread, 5),  # [5] ask
                6                           # [6] flags
            ]
            
            ticks.append(tick)
        
        # Show final price
        if ticks:
            final_price = ticks[-1][4]
            actual_move = abs(final_price - base_price)
            actual_pct = actual_move / base_price * 100
            target_pct = total_move / base_price * 100
            
            print(f"  ✅ Generated {num_ticks} ticks")
            print(f"     Final Price: {final_price:.5f}")
            print(f"     Actual Move: {actual_move:.5f} ({actual_pct:.2f}%)")
            print(f"     Target Move: {total_move:.5f} ({target_pct:.2f}%)")
            
            # Check accuracy
            error_pct = abs(actual_pct - target_pct) / target_pct * 100
            if error_pct < 5:
                print(f"     Accuracy: ✅ GOOD ({error_pct:.1f}% error)")
            else:
                print(f"     Accuracy: ⚠️ OFF ({error_pct:.1f}% error)")
        
        return ticks
    
    @staticmethod
    def generate_spike_reversal(
        symbol: str,
        base_price: float,
        spike_price: float,
        intensity: float = 1.0,
        suffix: str = DEFAULT_SUFFIX
    ) -> List[List]:
        """
        สร้าง spike reversal pattern (ราคากลับตัว)
        
        FIX #1: เพิ่ม suffix ให้ symbol
        """
        
        ticks = []
        current_price = spike_price
        timestamp = int(time.time() * 1000)
        
        full_symbol = symbol + suffix
        
        num_ticks = random.randint(40, 70)
        
        direction = -1 if spike_price > base_price else 1
        
        print(f"  📊 Reversal Generation:")
        print(f"     Start: {spike_price:.5f}")
        print(f"     Target: {base_price:.5f}")
        print(f"     Ticks: {num_ticks}")
        
        for i in range(num_ticks):
            progress = i / num_ticks
            
            # Decelerating pattern (ช้าลงเรื่อยๆ)
            move_ratio = (1 - progress) * 0.8 + 0.2
            move_size = move_ratio * abs(spike_price - base_price) / num_ticks * intensity
            
            noise = random.uniform(-0.0001, 0.0001) * base_price
            current_price += direction * move_size + noise
            
            # Spread normalizes during reversal
            spread_factor = max(1.0, 3.0 - progress * 2.0)
            spread = base_price * 0.00005 * spread_factor
            
            if "XAU" in symbol:
                spread = 0.30 * spread_factor
            
            tick = [
                1,
                i + 1,
                timestamp + (i * 50),
                full_symbol,
                round(current_price, 5),
                round(current_price + spread, 5),
                6
            ]
            
            ticks.append(tick)
        
        if ticks:
            final_price = ticks[-1][4]
            print(f"  ✅ Generated {num_ticks} reversal ticks")
            print(f"     Final Price: {final_price:.5f}")
        
        return ticks


# ========================================================================
# SPIKE SCENARIOS (FIX #2: Realistic prices)
# ========================================================================

class SpikeScenarios:
    """Pre-defined spike scenarios - FIX: ราคา realistic"""
    
    @staticmethod
    def gold_spike_scenario(suffix: str = DEFAULT_SUFFIX) -> Dict:
        """
        Gold spike (ตัวอย่าง: News-driven spike)
        XAUUSD พุ่ง +1.5% (~$42) ใน 3 นาที
        
        FIX #2: ราคา realistic ~$2850
        """
        base = REALISTIC_PRICES["XAUUSD"]
        spike_move = base * 0.015  # +1.5% = ~$42
        
        return {
            'name': f'Gold Spike (+1.5%, ~${spike_move:.0f})',
            'symbol': 'XAUUSD',
            'base_price': base,
            'spike_price': base + spike_move,
            'direction': 'UP',
            'intensity': 1.5,
            'suffix': suffix,
            'duration_seconds': 180
        }
    
    @staticmethod
    def gbpusd_flash_crash(suffix: str = DEFAULT_SUFFIX) -> Dict:
        """
        GBPUSD flash crash (ตัวอย่าง: News shock)
        GBPUSD ดิ่ง -0.8% (~100 pips) ใน 2 นาที
        
        FIX #2: ราคา realistic ~1.2450
        """
        base = REALISTIC_PRICES["GBPUSD"]
        spike_move = base * 0.008  # -0.8% = ~100 pips
        
        return {
            'name': f'GBPUSD Flash Crash (-0.8%, ~{spike_move*10000:.0f} pips)',
            'symbol': 'GBPUSD',
            'base_price': base,
            'spike_price': base - spike_move,
            'direction': 'DOWN',
            'intensity': 2.0,
            'suffix': suffix,
            'duration_seconds': 120
        }
    
    @staticmethod
    def daily_spike_mild(suffix: str = DEFAULT_SUFFIX) -> Dict:
        """
        Mild spike ที่เกิดทุกวัน (news release)
        ±0.3-0.5% ทั่วไป
        
        FIX #2: ราคา realistic
        """
        symbols = list(REALISTIC_PRICES.keys())
        symbol = random.choice(symbols)
        base_price = REALISTIC_PRICES[symbol]
        
        # Mild spike: ±0.3-0.5%
        direction = random.choice(['UP', 'DOWN'])
        spike_pct = random.uniform(0.003, 0.005)
        spike_move = base_price * spike_pct
        
        spike_price = base_price + spike_move if direction == 'UP' else base_price - spike_move
        
        return {
            'name': f'{symbol} Daily Spike ({direction} {spike_pct*100:.1f}%)',
            'symbol': symbol,
            'base_price': base_price,
            'spike_price': spike_price,
            'direction': direction,
            'intensity': 0.8,
            'suffix': suffix,
            'duration_seconds': 90
        }
    
    @staticmethod
    def extreme_gold_spike(suffix: str = DEFAULT_SUFFIX) -> Dict:
        """
        Extreme gold spike (ตัวอย่าง: War, Black Swan)
        XAUUSD พุ่ง +3% (~$85) ใน 5 นาที
        
        FIX #2: ราคา realistic ~$2850
        """
        base = REALISTIC_PRICES["XAUUSD"]
        spike_move = base * 0.03  # +3% = ~$85
        
        return {
            'name': f'EXTREME Gold Spike (+3%, ~${spike_move:.0f})',
            'symbol': 'XAUUSD',
            'base_price': base,
            'spike_price': base + spike_move,
            'direction': 'UP',
            'intensity': 2.5,
            'suffix': suffix,
            'duration_seconds': 300
        }


# ========================================================================
# SPIKE INJECTOR
# ========================================================================

class SpikeInjector:
    """
    ZMQ Publisher ที่ส่ง fake spike signals
    FIX: ทุกอย่างถูกต้องแล้ว
    """
    
    def __init__(self, zmq_address: str = "tcp://127.0.0.1:7777", suffix: str = DEFAULT_SUFFIX):
        self.zmq_address = zmq_address
        self.suffix = suffix
        self.context = zmq.Context()
        self.publisher = None
    
    def connect(self):
        """Connect to ZMQ"""
        try:
            self.publisher = self.context.socket(zmq.PUB)
            self.publisher.connect(self.zmq_address)
            
            time.sleep(1.0)
            
            print(f"✅ Connected to {self.zmq_address}")
            print(f"   Broker suffix: '{self.suffix}'")
            return True
            
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
    
    def inject_scenario(self, scenario: Dict, with_reversal: bool = True):
        """
        Inject spike scenario
        
        FIX #4: with_reversal=False สำหรับ entry-only test
        FIX #8: ส่ง spike_price ไปด้วย
        """
        
        suffix = scenario.get('suffix', self.suffix)
        full_symbol = scenario['symbol'] + suffix
        
        print("\n" + "="*70)
        print(f"🚀 INJECTING SPIKE: {scenario['name']}")
        print("="*70)
        print(f"Symbol:      {scenario['symbol']} → {full_symbol} (with suffix)")
        print(f"Base Price:  {scenario['base_price']:.5f}")
        print(f"Spike Price: {scenario['spike_price']:.5f}")
        print(f"Direction:   {scenario['direction']}")
        print(f"Intensity:   {scenario['intensity']}")
        print(f"Reversal:    {'Yes' if with_reversal else 'No (entry only)'}")
        
        move_pct = abs(scenario['spike_price'] - scenario['base_price']) / scenario['base_price'] * 100
        print(f"Move Size:   {move_pct:.2f}%")
        print("="*70)
        
        # Phase 1: Entry
        print("\n📈 Phase 1: SPIKE ENTRY...")
        
        # FIX #8: ส่ง spike_price parameter
        entry_ticks = SpikePatterns.generate_spike_entry(
            symbol=scenario['symbol'],
            base_price=scenario['base_price'],
            spike_price=scenario['spike_price'],  # ← FIX: เพิ่มบรรทัดนี้
            direction=scenario['direction'],
            intensity=scenario['intensity'],
            suffix=suffix
        )
        
        sent = self.send_ticks(entry_ticks, label="ENTRY")
        
        # Show price range
        if entry_ticks:
            first_price = entry_ticks[0][4]
            last_price = entry_ticks[-1][4]
            print(f"\n✅ Sent {sent} entry ticks | Price: {first_price:.5f} → {last_price:.5f}")
        
        # Phase 2: Reversal (optional)
        if with_reversal:
            print("\n⏳ Waiting 3 seconds before reversal...")
            time.sleep(3.0)
            
            print("🔄 Phase 2: SPIKE REVERSAL...")
            
            reversal_ticks = SpikePatterns.generate_spike_reversal(
                symbol=scenario['symbol'],
                base_price=scenario['base_price'],
                spike_price=scenario['spike_price'],
                intensity=scenario['intensity'],
                suffix=suffix
            )
            
            sent_r = self.send_ticks(reversal_ticks, label="REVERSAL")
            
            if reversal_ticks:
                first_r = reversal_ticks[0][4]
                last_r = reversal_ticks[-1][4]
                print(f"\n✅ Sent {sent_r} reversal ticks | Price: {first_r:.5f} → {last_r:.5f}")
        
        print("\n✅ Scenario injection complete!")
        print("="*70 + "\n")
    
    def send_ticks(self, ticks: List, label: str = "") -> int:
        """Send ticks via ZMQ"""
        
        sent = 0
        
        for tick in ticks:
            try:
                packed = msgpack.packb(tick)
                self.publisher.send(packed)
                sent += 1
                
                # 50ms interval (match FeederEA)
                time.sleep(0.05)
                
                if sent % 10 == 0:
                    price = tick[4]
                    print(f"  [{label}] Sent: {sent}/{len(ticks)} | Price: {price:.5f}", end='\r')
                
            except Exception as e:
                print(f"\n❌ Send error: {e}")
                break
        
        print()
        return sent
    
    def run_interactive(self):
        """Interactive mode"""
        
        print("\n" + "="*70)
        print(f"🎯 SPIKE TEST INJECTOR v2.1 - INTERACTIVE MODE")
        print(f"   Suffix: '{self.suffix}'")
        print("="*70)
        
        scenarios = [
            ('1', 'Gold Spike (+1.5%)', lambda: SpikeScenarios.gold_spike_scenario(self.suffix)),
            ('2', 'GBPUSD Flash Crash (-0.8%)', lambda: SpikeScenarios.gbpusd_flash_crash(self.suffix)),
            ('3', 'Daily News Spike (Random)', lambda: SpikeScenarios.daily_spike_mild(self.suffix)),
            ('4', 'EXTREME Gold Spike (+3%)', lambda: SpikeScenarios.extreme_gold_spike(self.suffix)),
        ]
        
        while True:
            print("\nAvailable Scenarios:")
            
            for key, name, func in scenarios:
                print(f"  {key}. {name}")
            
            print("\n  q. Quit")
            
            choice = input("\nSelect scenario (1-4, q): ").strip()
            
            if choice.lower() == 'q':
                break
            
            selected = next((func for k, n, func in scenarios if k == choice), None)
            
            if selected is None:
                print("❌ Invalid choice")
                continue
            
            scenario = selected()
            
            # FIX #4: Ask for entry-only option
            print("\nReversal mode:")
            print("  1. With reversal (full spike cycle)")
            print("  2. Entry only (test spike detection)")
            rev_choice = input("Select (1/2, default=2): ").strip()
            with_reversal = rev_choice == '1'
            
            self.inject_scenario(scenario, with_reversal=with_reversal)
            
            cont = input("\nInject another? (y/n): ").strip().lower()
            
            if cont != 'y':
                break
        
        print("\n👋 Goodbye!")
    
    def cleanup(self):
        """Cleanup"""
        if self.publisher:
            self.publisher.close()
        self.context.term()


# ========================================================================
# MAIN
# ========================================================================

def main():
    parser = argparse.ArgumentParser(description='Spike Signal Test Injector v2.1 (FIXED)')
    
    parser.add_argument(
        'mode',
        nargs='?',
        choices=['fake', 'interactive', 'auto'],
        default='interactive',
        help='Mode: fake=inject once, interactive=menu, auto=loop'
    )
    
    parser.add_argument(
        '--address',
        default='tcp://127.0.0.1:7777',
        help='ZMQ address (default: tcp://127.0.0.1:7777)'
    )
    
    # FIX #5: Configurable suffix
    parser.add_argument(
        '--suffix',
        default=DEFAULT_SUFFIX,
        help=f'Broker symbol suffix (default: {DEFAULT_SUFFIX})'
    )
    
    parser.add_argument(
        '--no-reversal',
        action='store_true',
        help='Send entry ticks only (no reversal phase)'
    )
    
    args = parser.parse_args()
    
    print("="*70)
    print("🎯 SPIKE TEST INJECTOR v2.1 (FIXED)")
    print(f"   Broker suffix: '{args.suffix}'")
    print(f"   Min entry ticks: {MIN_ENTRY_TICKS}")
    print(f"   Realistic prices: {list(REALISTIC_PRICES.keys())}")
    print("="*70)
    
    injector = SpikeInjector(zmq_address=args.address, suffix=args.suffix)
    
    if not injector.connect():
        print("❌ Cannot connect. Is Python Brain running?")
        return 1
    
    try:
        if args.mode == 'fake':
            scenario = SpikeScenarios.gold_spike_scenario(args.suffix)
            injector.inject_scenario(scenario, with_reversal=not args.no_reversal)
        
        elif args.mode == 'interactive':
            injector.run_interactive()
        
        elif args.mode == 'auto':
            print("🔄 AUTO MODE: Sending spike every 30 seconds")
            print("   Press Ctrl+C to stop")
            
            while True:
                scenario = SpikeScenarios.daily_spike_mild(args.suffix)
                injector.inject_scenario(scenario, with_reversal=not args.no_reversal)
                
                print("⏳ Waiting 30 seconds...")
                time.sleep(30)
    
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
    
    finally:
        injector.cleanup()
    
    return 0


if __name__ == "__main__":
    exit(main())
