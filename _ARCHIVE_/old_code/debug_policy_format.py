#!/usr/bin/env python3
"""
Debug script to inspect policy message format
"""
import zmq
import msgpack
import time

def inspect_policy_messages():
    """
    Subscribe to policy port and inspect message format
    """
    context = zmq.Context()
    subscriber = context.socket(zmq.SUB)
    subscriber.connect("tcp://127.0.0.1:7778")
    subscriber.subscribe(b"")  # Subscribe to all messages
    
    print("=" * 80)
    print("🔍 POLICY MESSAGE INSPECTOR")
    print("=" * 80)
    print("Listening on tcp://127.0.0.1:7778...")
    print("Waiting for policies from Python Brain...")
    print()
    
    message_count = 0
    
    try:
        while message_count < 5:  # Inspect first 5 messages
            # Wait for message (with timeout)
            if subscriber.poll(timeout=5000):  # 5 second timeout
                raw_data = subscriber.recv()
                message_count += 1
                
                print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print(f"📥 MESSAGE #{message_count}")
                print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print(f"Raw bytes: {len(raw_data)} bytes")
                print(f"First 20 bytes (hex): {raw_data[:20].hex()}")
                print()
                
                # Try to deserialize
                try:
                    policy = msgpack.unpackb(raw_data, raw=False)
                    print("✅ MessagePack deserialization: SUCCESS")
                    print(f"Type: {type(policy)}")
                    
                    if isinstance(policy, dict):
                        print("📋 DICTIONARY FORMAT:")
                        for key, value in policy.items():
                            print(f"   {key}: {value}")
                    elif isinstance(policy, (list, tuple)):
                        print("📋 ARRAY FORMAT:")
                        for i, item in enumerate(policy):
                            print(f"   [{i}]: {item}")
                    else:
                        print(f"📋 OTHER FORMAT: {policy}")
                    
                except Exception as e:
                    print(f"❌ MessagePack deserialization: FAILED")
                    print(f"Error: {e}")
                
                print()
            else:
                print("⏱️ No message received in 5 seconds...")
                print("Is Python Brain running and sending policies?")
                time.sleep(1)
    
    except KeyboardInterrupt:
        print("\n\n⚠️ Stopped by user")
    
    finally:
        subscriber.close()
        context.term()
        print("\n✅ Inspector stopped")

if __name__ == "__main__":
    inspect_policy_messages()
