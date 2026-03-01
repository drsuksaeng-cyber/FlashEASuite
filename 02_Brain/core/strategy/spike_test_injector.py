#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Spike Signal Test Injector
Version: 1.0

จุดประสงค์: ส่งสัญญาณ spike ปลอมเพื่อทดสอบว่า strategy engine ทำงานหรือไม่

วิธีใช้:
    python spike_test_injector.py [mode]
    
    mode:
        fake    - ส่ง spike ปลอม (ไม่ต้องมี MT5)
        replay  - เล่น spike จากประว ัติจริง (ถ้ามี)
"""

import zmq
import msgpack
import time
import random
import argparse
from datetime import datetime
from typing import List, Dict

# ========================================================================
# SPIKE PATTERNS (จากประสบการณ์จริง)
# ========================================================================

class SpikePatterns:
    """
    Spike patterns จากสถิติจริงของตลาด
    
    ข้อมูลจาก:
    - Flash Crash (2010)
    - Swiss Franc Spike (2015)  
    - Gold Spike (COVID-19)
    - Daily spikes ตามปกติ
    """
    
    @staticmethod
    def generate_spike_entry(
        symbol: str,
        base_price: float,
        direction: str = "UP",  # "UP" or "DOWN"
        intensity: float = 1.0   # 0.5-2.0 (mild-extreme)
    ) -> List[Dict]:
        """
        สร้าง spike entry pattern
        
        Entry = ช่วงที่เริ่มเห็น spike (ราคาพุ่งขึ้น/ลงเร็ว)
        
        Pattern:
        1. ราคาเริ่มขยับเร็วขึ้น
        2. Volume เพิ่มขึ้น
        3. Volatility พุ่งขึ้น
        """
        
        ticks = []
        current_price = base_price
        timestamp = int(time.time() * 1000)
        
        # Entry phase: 20-50 ticks (2-5 seconds if 50ms interval)
        num_ticks = random.randint(20, 50)
        
        for i in range(num_ticks):
            # Price movement (accelerating)
            move_size = (i / num_ticks) * 0.001 * base_price * intensity
            
            if direction == "UP":
                current_price += move_size
            else:
                current_price -= move_size
            
            # Small spread
            spread = current_price * 0.0001  # 0.01%
            
            tick = {
                'type': 1,  # TICK message
                'sequence': i + 1,
                'timestamp': timestamp + (i * 50),
                'symbol': symbol,
                'bid': current_price,
                'ask': current_price + spread,
                'flags': 6
            }
            
            ticks.append(tick)
        
        return ticks
    
    @staticmethod
    def generate_spike_reversal(
        symbol: str,
        base_price: float,
        spike_price: float,
        intensity: float = 1.0
    ) -> List[Dict]:
        """
        สร้าง spike reversal pattern
        
        Reversal = ช่วงที่ spike หักหัวกลับ (ราคากลับตัว)
        
        Pattern:
        1. ราคาถึงจุดสูงสุด/ต่ำสุด
        2. เริ่มชะลอตัว
        3. กลับตัวเร็ว
        """
        
        ticks = []
        current_price = spike_price
        timestamp = int(time.time() * 1000)
        
        # Reversal phase: 30-60 ticks
        num_ticks = random.randint(30, 60)
        
        # Direction: back to base
        direction = -1 if spike_price > base_price else 1
        
        for i in range(num_ticks):
            # Price reversion (fast at first, then slower)
            move_ratio = (1 - i / num_ticks) * 0.8 + 0.2  # 1.0 -> 0.2
            move_size = move_ratio * abs(spike_price - base_price) / num_ticks * intensity
            
            current_price += direction * move_size
            
            spread = current_price * 0.0001
            
            tick = {
                'type': 1,
                'sequence': i + 1,
                'timestamp': timestamp + (i * 50),
                'symbol': symbol,
                'bid': current_price,
                'ask': current_price + spread,
                'flags': 6
            }
            
            ticks.append(tick)
        
        return ticks


# ========================================================================
# SPIKE SCENARIOS
# ========================================================================

class SpikeScenarios:
    """Pre-defined spike scenarios สำหรับทดสอบ"""
    
    @staticmethod
    def gold_spike_scenario() -> Dict:
        """
        Gold spike (ตัวอย่างจริง: COVID-19 pandemic)
        
        XAUUSD พุ่งจาก $1,600 → $1,900 ในไม่กี่นาที
        """
        return {
            'name': 'Gold Spike (COVID-19 style)',
            'symbol': 'XAUUSD',
            'base_price': 1600.0,
            'spike_price': 1900.0,
            'direction': 'UP',
            'intensity': 1.5,
            'duration_seconds': 180  # 3 minutes
        }
    
    @staticmethod
    def gbpusd_flash_crash() -> Dict:
        """
        GBPUSD flash crash (ตัวอย่าง: Brexit flash crash 2016)
        
        GBPUSD ดิ่งจาก 1.2800 → 1.1800 ภายใน 2 นาที
        """
        return {
            'name': 'GBPUSD Flash Crash (Brexit style)',
            'symbol': 'GBPUSD',
            'base_price': 1.2800,
            'spike_price': 1.1800,
            'direction': 'DOWN',
            'intensity': 2.0,
            'duration_seconds': 120  # 2 minutes
        }
    
    @staticmethod
    def daily_spike_mild() -> Dict:
        """
        Mild spike ที่เกิดทุกวัน
        
        เช่น news release ปกติ
        """
        symbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD']
        symbol = random.choice(symbols)
        
        base_prices = {
            'EURUSD': 1.0800,
            'GBPUSD': 1.2700,
            'USDJPY': 148.00,
            'XAUUSD': 2050.0
        }
        
        base_price = base_prices[symbol]
        
        # Mild spike: ±0.5%
        direction = random.choice(['UP', 'DOWN'])
        spike_move = base_price * 0.005
        
        spike_price = base_price + spike_move if direction == 'UP' else base_price - spike_move
        
        return {
            'name': f'{symbol} Daily News Spike',
            'symbol': symbol,
            'base_price': base_price,
            'spike_price': spike_price,
            'direction': direction,
            'intensity': 0.8,
            'duration_seconds': 60
        }


# ========================================================================
# SPIKE INJECTOR
# ========================================================================

class SpikeInjector:
    """
    Spike Signal Injector
    
    ส่งสัญญาณ spike ปลอมไปที่ Python Brain
    """
    
    def __init__(self, zmq_address: str = "tcp://127.0.0.1:7777"):
        self.zmq_address = zmq_address
        self.context = zmq.Context()
        self.publisher = None
    
    def connect(self):
        """Connect to ZMQ"""
        try:
            self.publisher = self.context.socket(zmq.PUB)
            self.publisher.connect(self.zmq_address)
            
            # Wait for connection
            time.sleep(1.0)
            
            print(f"✅ Connected to {self.zmq_address}")
            return True
            
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
    
    def inject_scenario(self, scenario: Dict, with_reversal: bool = True):
        """
        Inject spike scenario
        
        Args:
            scenario: Spike scenario dict
            with_reversal: ส่ง reversal ด้วยหรือไม่
        """
        
        print("\n" + "="*70)
        print(f"🚀 INJECTING SPIKE: {scenario['name']}")
        print("="*70)
        print(f"Symbol:     {scenario['symbol']}")
        print(f"Base Price: {scenario['base_price']}")
        print(f"Spike Price: {scenario['spike_price']}")
        print(f"Direction:  {scenario['direction']}")
        print(f"Intensity:  {scenario['intensity']}")
        print("="*70)
        
        # Phase 1: Entry (spike เริ่มต้น)
        print("\n📈 Phase 1: SPIKE ENTRY...")
        
        entry_ticks = SpikePatterns.generate_spike_entry(
            symbol=scenario['symbol'],
            base_price=scenario['base_price'],
            direction=scenario['direction'],
            intensity=scenario['intensity']
        )
        
        self.send_ticks(entry_ticks, label="ENTRY")
        
        print(f"✅ Sent {len(entry_ticks)} entry ticks")
        
        # Phase 2: Reversal (spike หักหัวกลับ)
        if with_reversal:
            print("\n🔄 Phase 2: SPIKE REVERSAL...")
            
            time.sleep(2.0)  # Pause
            
            reversal_ticks = SpikePatterns.generate_spike_reversal(
                symbol=scenario['symbol'],
                base_price=scenario['base_price'],
                spike_price=scenario['spike_price'],
                intensity=scenario['intensity']
            )
            
            self.send_ticks(reversal_ticks, label="REVERSAL")
            
            print(f"✅ Sent {len(reversal_ticks)} reversal ticks")
        
        print("\n✅ Scenario injection complete!")
        print("="*70 + "\n")
    
    def send_ticks(self, ticks: List[Dict], label: str = ""):
        """Send ticks via ZMQ"""
        
        sent = 0
        
        for tick in ticks:
            try:
                packed = msgpack.packb(tick)
                self.publisher.send(packed)
                sent += 1
                
                # Simulate 50ms tick interval
                time.sleep(0.05)
                
                # Progress indicator
                if sent % 10 == 0:
                    print(f"  [{label}] Sent: {sent}/{len(ticks)} ticks...", end='\r')
                
            except Exception as e:
                print(f"\n❌ Send error: {e}")
                break
        
        print()  # New line
        
        return sent
    
    def run_interactive(self):
        """Interactive mode"""
        
        print("\n" + "="*70)
        print("🎯 SPIKE TEST INJECTOR - INTERACTIVE MODE")
        print("="*70)
        
        scenarios = [
            ('1', 'Gold Spike (COVID-19 style)', SpikeScenarios.gold_spike_scenario),
            ('2', 'GBPUSD Flash Crash (Brexit)', SpikeScenarios.gbpusd_flash_crash),
            ('3', 'Daily News Spike (Random)', SpikeScenarios.daily_spike_mild),
        ]
        
        while True:
            print("\nAvailable Scenarios:")
            
            for key, name, func in scenarios:
                print(f"  {key}. {name}")
            
            print("\n  q. Quit")
            
            choice = input("\nSelect scenario (1-3, q): ").strip()
            
            if choice.lower() == 'q':
                break
            
            # Find scenario
            selected = next((func for k, n, func in scenarios if k == choice), None)
            
            if selected is None:
                print("❌ Invalid choice")
                continue
            
            # Get scenario
            scenario = selected()
            
            # Ask for reversal
            include_reversal = input("Include reversal? (y/n, default=y): ").strip().lower()
            with_reversal = include_reversal != 'n'
            
            # Inject
            self.inject_scenario(scenario, with_reversal=with_reversal)
            
            # Ask to continue
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
    parser = argparse.ArgumentParser(description='Spike Signal Test Injector')
    
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
    
    args = parser.parse_args()
    
    # Create injector
    injector = SpikeInjector(zmq_address=args.address)
    
    # Connect
    if not injector.connect():
        print("❌ Cannot connect. Is Python Brain running?")
        return 1
    
    try:
        if args.mode == 'fake':
            # Quick test: send one spike
            scenario = SpikeScenarios.daily_spike_mild()
            injector.inject_scenario(scenario, with_reversal=True)
        
        elif args.mode == 'interactive':
            # Interactive menu
            injector.run_interactive()
        
        elif args.mode == 'auto':
            # Auto mode: send spikes every 30 seconds
            print("🔄 AUTO MODE: Sending spike every 30 seconds")
            print("   Press Ctrl+C to stop")
            
            while True:
                scenario = SpikeScenarios.daily_spike_mild()
                injector.inject_scenario(scenario, with_reversal=True)
                
                print("⏳ Waiting 30 seconds...")
                time.sleep(30)
    
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
    
    finally:
        injector.cleanup()
    
    return 0


if __name__ == "__main__":
    exit(main())
