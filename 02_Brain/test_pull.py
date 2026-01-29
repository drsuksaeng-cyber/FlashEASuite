#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test PULL Socket - ทดสอบรับ feedback จาก Trader

วิธีใช้:
1. Stop Python Brain (Ctrl+C)
2. Run: python test_pull.py
3. Attach Trader EA ใน MT5
4. ดูว่ามี message มาหรือไม่

หยุด: Ctrl+C
"""

import zmq
import msgpack
import time
from datetime import datetime

def main():
    print("=" * 70)
    print("🧪 TEST PULL SOCKET - Feedback Receiver")
    print("=" * 70)
    print("ℹ️  สคริปต์นี้ทดสอบการรับ feedback จาก Trader")
    print("ℹ️  ใช้แทน Python Brain ชั่วคราว")
    print("=" * 70)
    print()
    
    # Create ZMQ context and PULL socket
    context = zmq.Context()
    socket = context.socket(zmq.PULL)
    
    try:
        # Bind to port 7779
        socket.bind("tcp://127.0.0.1:7779")
        socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1 second timeout
        
        print("✅ PULL socket bound to tcp://127.0.0.1:7779")
        print("✅ Ready to receive messages from Trader (PUSH)")
        print()
        print("⏳ Waiting for messages... (Press Ctrl+C to stop)")
        print("=" * 70)
        print()
        
        message_count = 0
        
        while True:
            try:
                # Receive message
                data = socket.recv()
                message_count += 1
                
                # Deserialize
                msg = msgpack.unpackb(data)
                
                # Display
                print("=" * 70)
                print(f"📨 MESSAGE #{message_count} RECEIVED!")
                print("=" * 70)
                print(f"⏰ Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}")
                print(f"📦 Size: {len(data)} bytes")
                print(f"📋 Content: {msg}")
                print("=" * 70)
                print()
                
                # Parse if it's feedback format (5 fields)
                if isinstance(msg, list) and len(msg) == 5:
                    print("📊 PARSED FEEDBACK:")
                    print(f"   Type:    {msg[0]}")
                    print(f"   Success: {'YES' if msg[1] == 1 else 'NO'}")
                    print(f"   Ticket:  {msg[2]}")
                    print(f"   Profit:  {msg[3]:.2f}")
                    print(f"   Message: {msg[4]}")
                    print("=" * 70)
                    print()
                
            except zmq.Again:
                # Timeout - no message
                continue
            
            except KeyboardInterrupt:
                print("\n\n⚠️  Stopping test...")
                break
            
            except Exception as e:
                print(f"❌ ERROR: {e}")
                continue
    
    except Exception as e:
        print(f"❌ FAILED to bind socket: {e}")
        print()
        print("💡 Possible causes:")
        print("   1. Python Brain is still running (Stop it first!)")
        print("   2. Port 7779 is used by another program")
        print("   3. Permission issue")
        return
    
    finally:
        # Cleanup
        print()
        print("🧹 Cleaning up...")
        socket.close()
        context.term()
        print(f"✅ Test completed (Received {message_count} messages)")
        print("=" * 70)

if __name__ == "__main__":
    main()
