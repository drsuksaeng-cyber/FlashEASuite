#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test PUSH Socket - Sender
ทดสอบส่งข้อมูลไปยัง test_pull.py
"""

import zmq
import msgpack
import time

def main():
    print("=" * 70)
    print("🧪 TEST PUSH SOCKET - Feedback Sender")
    print("=" * 70)
    print("ℹ️  สคริปต์นี้ทดสอบส่งข้อมูลไปยัง test_pull.py")
    print("=" * 70)
    print()
    
    # Create context and socket
    context = zmq.Context()
    socket = context.socket(zmq.PUSH)
    
    try:
        # Connect (PUSH must connect, PULL must bind)
        socket.connect("tcp://127.0.0.1:7779")
        print("✅ PUSH socket connected to tcp://127.0.0.1:7779")
        
        # IMPORTANT: Wait for connection to establish
        print("⏳ Waiting for connection to establish...")
        time.sleep(2)  # Wait 2 seconds
        
        # Send test messages
        print("\n📤 Sending test messages...\n")
        
        for i in range(5):
            # Create feedback message (same format as Trader)
            msg = {
                'type': 3,  # Feedback message
                'sequence_id': i + 1,
                'ticket': 12345 + i,
                'profit': 10.5 + i,
                'message': f'Test message #{i+1}'
            }
            
            # Serialize
            data = msgpack.packb(msg)
            
            # Send
            socket.send(data, zmq.NOBLOCK)
            
            print(f"✅ Sent message #{i+1}: {len(data)} bytes")
            print(f"   Ticket: {msg['ticket']}")
            print(f"   Profit: {msg['profit']}")
            print()
            
            time.sleep(0.5)  # Wait 500ms between messages
        
        print("=" * 70)
        print("✅ All messages sent successfully")
        print("=" * 70)
        print("\nℹ️  ตรวจสอบที่ test_pull.py ว่ารับข้อมูลได้หรือไม่")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        # Cleanup
        print("\n🧹 Cleaning up...")
        socket.close()
        context.term()
        print("✅ Test completed")

if __name__ == "__main__":
    main()
