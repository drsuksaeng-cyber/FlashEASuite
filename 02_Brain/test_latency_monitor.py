#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Latency Monitor
Measures end-to-end latency of policy messages from Python Brain to MT5 Trader

Author: Dr. Suksaeng Kukanok
Date: January 6, 2026
"""

import zmq
import msgpack
import time
import statistics
from datetime import datetime
from collections import deque

class LatencyMonitor:
    """Monitor and measure policy message latency"""
    
    def __init__(self):
        self.context = zmq.Context()
        
        # Subscribe to policy messages (same as Trader)
        self.policy_sub = self.context.socket(zmq.SUB)
        self.policy_sub.connect("tcp://127.0.0.1:7778")
        self.policy_sub.setsockopt_string(zmq.SUBSCRIBE, "")
        
        # Stats
        self.latencies = deque(maxlen=1000)  # Keep last 1000 measurements
        self.policy_count = 0
        self.start_time = time.time()
        
        print("=" * 60)
        print("🔬 FlashEASuite V2 - Latency Monitor")
        print("=" * 60)
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Monitoring port: tcp://127.0.0.1:7778")
        print("Waiting for policy messages...")
        print("-" * 60)
    
    def calculate_latency(self, policy_timestamp_ms):
        """Calculate latency from policy timestamp to now"""
        now_ms = int(time.time() * 1000)
        latency_ms = now_ms - policy_timestamp_ms
        return latency_ms
    
    def print_stats(self):
        """Print current statistics"""
        if not self.latencies:
            return
        
        avg = statistics.mean(self.latencies)
        median = statistics.median(self.latencies)
        min_lat = min(self.latencies)
        max_lat = max(self.latencies)
        
        # Calculate percentiles
        sorted_lat = sorted(self.latencies)
        p95_idx = int(len(sorted_lat) * 0.95)
        p99_idx = int(len(sorted_lat) * 0.99)
        p95 = sorted_lat[p95_idx] if p95_idx < len(sorted_lat) else max_lat
        p99 = sorted_lat[p99_idx] if p99_idx < len(sorted_lat) else max_lat
        
        elapsed = time.time() - self.start_time
        rate = self.policy_count / elapsed if elapsed > 0 else 0
        
        print(f"\n📊 Latency Statistics (n={self.policy_count}):")
        print(f"   Average:  {avg:7.2f} ms")
        print(f"   Median:   {median:7.2f} ms")
        print(f"   Min:      {min_lat:7.2f} ms")
        print(f"   Max:      {max_lat:7.2f} ms")
        print(f"   95th %:   {p95:7.2f} ms")
        print(f"   99th %:   {p99:7.2f} ms")
        print(f"   Rate:     {rate:7.2f} policies/sec")
        print(f"   Uptime:   {elapsed:7.1f} sec")
        
        # Performance indicator
        if avg < 50:
            status = "✅ EXCELLENT"
        elif avg < 100:
            status = "✅ GOOD"
        elif avg < 200:
            status = "⚠️ ACCEPTABLE"
        else:
            status = "❌ NEEDS IMPROVEMENT"
        
        print(f"   Status:   {status}")
        print("-" * 60)
    
    def run(self, duration_sec=None, report_interval=10):
        """
        Run latency monitoring
        
        Args:
            duration_sec: Duration to run (None = infinite)
            report_interval: Print stats every N seconds
        """
        last_report = time.time()
        end_time = time.time() + duration_sec if duration_sec else None
        
        try:
            while True:
                # Check if duration exceeded
                if end_time and time.time() >= end_time:
                    print("\n⏰ Duration reached. Stopping...")
                    break
                
                # Poll for policy message
                try:
                    if self.policy_sub.poll(timeout=100):  # 100ms timeout
                        data = self.policy_sub.recv()
                        
                        # Deserialize
                        try:
                            policy = msgpack.unpackb(data, raw=False)
                            
                            # Extract timestamp
                            if isinstance(policy, dict) and 'timestamp_ms' in policy:
                                timestamp_ms = policy['timestamp_ms']
                                latency = self.calculate_latency(timestamp_ms)
                                
                                # Record
                                self.latencies.append(latency)
                                self.policy_count += 1
                                
                                # Print individual measurement
                                symbol = policy.get('symbol', 'UNKNOWN')
                                print(f"[{self.policy_count:4d}] {symbol:10s} "
                                      f"Latency: {latency:6.2f} ms")
                            
                        except Exception as e:
                            print(f"❌ Error deserializing: {e}")
                
                except zmq.ZMQError as e:
                    if e.errno == zmq.EAGAIN:
                        pass  # Timeout, continue
                    else:
                        raise
                
                # Print periodic stats
                if time.time() - last_report >= report_interval:
                    self.print_stats()
                    last_report = time.time()
        
        except KeyboardInterrupt:
            print("\n\n⏹️ Stopped by user (Ctrl+C)")
        
        finally:
            # Final stats
            print("\n" + "=" * 60)
            print("📋 FINAL STATISTICS")
            print("=" * 60)
            self.print_stats()
            
            # Save to file
            self.save_report()
            
            # Cleanup
            self.policy_sub.close()
            self.context.term()
    
    def save_report(self):
        """Save test report to file"""
        if not self.latencies:
            print("⚠️ No data to save")
            return
        
        filename = f"latency_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write("=" * 60 + "\n")
            f.write("FlashEASuite V2 - Latency Test Report\n")
            f.write("=" * 60 + "\n")
            f.write(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Duration: {time.time() - self.start_time:.1f} seconds\n")
            f.write(f"Samples: {self.policy_count}\n")
            f.write("\n")
            
            # Calculate stats
            avg = statistics.mean(self.latencies)
            median = statistics.median(self.latencies)
            min_lat = min(self.latencies)
            max_lat = max(self.latencies)
            
            sorted_lat = sorted(self.latencies)
            p95_idx = int(len(sorted_lat) * 0.95)
            p99_idx = int(len(sorted_lat) * 0.99)
            p95 = sorted_lat[p95_idx] if p95_idx < len(sorted_lat) else max_lat
            p99 = sorted_lat[p99_idx] if p99_idx < len(sorted_lat) else max_lat
            
            f.write("Latency Statistics:\n")
            f.write(f"  Average:     {avg:.2f} ms\n")
            f.write(f"  Median:      {median:.2f} ms\n")
            f.write(f"  Min:         {min_lat:.2f} ms\n")
            f.write(f"  Max:         {max_lat:.2f} ms\n")
            f.write(f"  95th %ile:   {p95:.2f} ms\n")
            f.write(f"  99th %ile:   {p99:.2f} ms\n")
            f.write("\n")
            
            # Pass/Fail criteria
            f.write("Pass/Fail Criteria:\n")
            f.write(f"  Average < 50ms:   {'✅ PASS' if avg < 50 else '❌ FAIL'}\n")
            f.write(f"  Max < 100ms:      {'✅ PASS' if max_lat < 100 else '❌ FAIL'}\n")
            f.write(f"  95% < 75ms:       {'✅ PASS' if p95 < 75 else '❌ FAIL'}\n")
            f.write("\n")
            
            # Overall
            overall = avg < 50 and max_lat < 100 and p95 < 75
            f.write(f"Overall Result: {'✅ PASS' if overall else '❌ FAIL'}\n")
        
        print(f"✅ Report saved: {filename}")


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Monitor policy message latency',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run for 10 minutes (600 sec)
  python test_latency_monitor.py --duration 600
  
  # Run for 30 minutes with stats every 5 seconds
  python test_latency_monitor.py --duration 1800 --interval 5
  
  # Run indefinitely (Ctrl+C to stop)
  python test_latency_monitor.py
        """
    )
    
    parser.add_argument(
        '--duration',
        type=int,
        default=None,
        help='Duration to run in seconds (default: infinite)'
    )
    
    parser.add_argument(
        '--interval',
        type=int,
        default=10,
        help='Stats report interval in seconds (default: 10)'
    )
    
    args = parser.parse_args()
    
    monitor = LatencyMonitor()
    monitor.run(duration_sec=args.duration, report_interval=args.interval)


if __name__ == '__main__':
    main()
