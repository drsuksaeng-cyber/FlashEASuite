#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Protocol Testing Script
Tests pack_custom_protocol() with all Grid extended fields

Location: FlashEASuite_V2/Tester/TEST_PROTOCOL.py

Usage:
    cd FlashEASuite_V2/Tester
    python TEST_PROTOCOL.py
    
Expected:
    - Prints message size
    - Prints hex dump
    - Verifies field sizes
"""

import struct
import time
import sys
import os

# Add parent directory to path (for accessing 02_Brain)
# From Tester/ → go up to FlashEASuite_V2/ → then to 02_Brain/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '02_Brain', 'core', 'strategy'))

from policy import pack_custom_protocol

def test_protocol_v2():
    """Test protocol with all Grid fields."""
    
    print("=" * 80)
    print("FlashEASuite V2 - Protocol Test (Extended Grid Fields)")
    print("=" * 80)
    print()
    
    # Test data
    test_symbol = "XAUUSD"
    test_action = 1  # BUY
    test_confidence = 0.85
    test_entry_price = 2650.50
    test_stop_loss = 2640.00
    test_take_profit = 2670.00
    test_position_size = 0.01
    test_timestamp_ms = int(time.time() * 1000)
    test_model_version = "GRID_V2_TEST"
    
    # Grid extended fields
    test_risk_multiplier = 0.8
    test_is_in_cooldown = True
    test_csm_data = {
        'USD': 5.2,
        'EUR': 4.8,
        'GBP': 3.5,
        'JPY': -2.1,
        'AUD': 1.2,
        'CAD': 0.5,
        'CHF': -1.0,
        'NZD': 2.3
    }
    test_grid_direction = 1  # BUY
    
    print("Test Data:")
    print(f"  Symbol: {test_symbol}")
    print(f"  Action: {test_action} (BUY)")
    print(f"  Confidence: {test_confidence}")
    print(f"  Entry Price: {test_entry_price}")
    print(f"  Stop Loss: {test_stop_loss}")
    print(f"  Take Profit: {test_take_profit}")
    print(f"  Position Size: {test_position_size}")
    print(f"  Timestamp: {test_timestamp_ms}")
    print(f"  Model Version: {test_model_version}")
    print()
    print("Grid Extended Fields:")
    print(f"  Risk Multiplier: {test_risk_multiplier}")
    print(f"  Is In Cooldown: {test_is_in_cooldown}")
    print(f"  CSM Data:")
    for currency, strength in test_csm_data.items():
        print(f"    {currency}: {strength:.2f}")
    print(f"  Grid Direction: {test_grid_direction} (BUY)")
    print()
    
    # Pack message
    print("Packing message...")
    packed = pack_custom_protocol(
        msg_type=2,
        symbol=test_symbol,
        action=test_action,
        confidence=test_confidence,
        entry_price=test_entry_price,
        stop_loss=test_stop_loss,
        take_profit=test_take_profit,
        position_size=test_position_size,
        timestamp_ms=test_timestamp_ms,
        model_version=test_model_version,
        # Grid fields
        risk_multiplier=test_risk_multiplier,
        is_in_cooldown=test_is_in_cooldown,
        csm_data=test_csm_data,
        grid_direction=test_grid_direction
    )
    
    print(f"✅ Packed successfully! Size: {len(packed)} bytes")
    print()
    
    # Expected size calculation
    print("Size Breakdown:")
    print(f"  Message type (int32):        4 bytes")
    print(f"  Symbol length (int32):       4 bytes")
    print(f"  Symbol '{test_symbol}' (UTF-8):      {len(test_symbol.encode('utf-8'))} bytes")
    print(f"  Action (int32):              4 bytes")
    print(f"  Confidence (double):         8 bytes")
    print(f"  Entry price (double):        8 bytes")
    print(f"  Stop loss (double):          8 bytes")
    print(f"  Take profit (double):        8 bytes")
    print(f"  Position size (double):      8 bytes")
    print(f"  Timestamp (int64):           8 bytes")
    print(f"  Model version length (int32): 4 bytes")
    print(f"  Model version '{test_model_version}' (UTF-8): {len(test_model_version.encode('utf-8'))} bytes")
    print(f"  --- GRID EXTENDED FIELDS ---")
    print(f"  Risk multiplier (double):    8 bytes")
    print(f"  Is in cooldown (int32):      4 bytes")
    print(f"  CSM USD (double):            8 bytes")
    print(f"  CSM EUR (double):            8 bytes")
    print(f"  CSM GBP (double):            8 bytes")
    print(f"  CSM JPY (double):            8 bytes")
    print(f"  CSM AUD (double):            8 bytes")
    print(f"  CSM CAD (double):            8 bytes")
    print(f"  CSM CHF (double):            8 bytes")
    print(f"  CSM NZD (double):            8 bytes")
    print(f"  Grid direction (int32):      4 bytes")
    
    expected_size = (
        4 +  # msg_type
        4 + len(test_symbol.encode('utf-8')) +  # symbol
        4 +  # action
        8 + 8 + 8 + 8 + 8 +  # 5 doubles
        8 +  # timestamp
        4 + len(test_model_version.encode('utf-8')) +  # model_version
        8 +  # risk_multiplier
        4 +  # is_in_cooldown
        64 +  # 8 CSM doubles
        4  # grid_direction
    )
    
    print(f"  --------------------------------")
    print(f"  Expected total:              {expected_size} bytes")
    print(f"  Actual total:                {len(packed)} bytes")
    
    if len(packed) == expected_size:
        print(f"  ✅ Size matches!")
    else:
        print(f"  ❌ Size mismatch! Difference: {len(packed) - expected_size} bytes")
    print()
    
    # Hex dump (first 100 bytes)
    print("Hex Dump (first 100 bytes):")
    hex_str = packed[:100].hex()
    for i in range(0, len(hex_str), 32):
        print(f"  {hex_str[i:i+32]}")
    if len(packed) > 100:
        print(f"  ... ({len(packed) - 100} more bytes)")
    print()
    
    # Manual verification of first few fields
    print("Manual Field Verification:")
    offset = 0
    
    # Message type
    msg_type = struct.unpack('>i', packed[offset:offset+4])[0]
    print(f"  Message Type: {msg_type} (expected: 2)")
    offset += 4
    
    # Symbol length
    symbol_len = struct.unpack('>i', packed[offset:offset+4])[0]
    print(f"  Symbol Length: {symbol_len} (expected: {len(test_symbol)})")
    offset += 4
    
    # Symbol
    symbol = packed[offset:offset+symbol_len].decode('utf-8')
    print(f"  Symbol: {symbol} (expected: {test_symbol})")
    offset += symbol_len
    
    # Action
    action = struct.unpack('>i', packed[offset:offset+4])[0]
    print(f"  Action: {action} (expected: {test_action})")
    offset += 4
    
    # Confidence
    confidence = struct.unpack('>d', packed[offset:offset+8])[0]
    print(f"  Confidence: {confidence:.6f} (expected: {test_confidence})")
    offset += 8
    
    # Skip to Grid fields (after original fields)
    # Original fields: entry_price, sl, tp, position_size, timestamp, model_version
    offset += 8 + 8 + 8 + 8 + 8  # 5 doubles
    model_version_len = struct.unpack('>i', packed[offset:offset+4])[0]
    offset += 4 + model_version_len
    
    print(f"\n  --- GRID EXTENDED FIELDS ---")
    
    # Risk multiplier
    risk_mult = struct.unpack('>d', packed[offset:offset+8])[0]
    print(f"  Risk Multiplier: {risk_mult:.6f} (expected: {test_risk_multiplier})")
    offset += 8
    
    # Is in cooldown
    cooldown_int = struct.unpack('>i', packed[offset:offset+4])[0]
    is_cooldown = (cooldown_int == 1)
    print(f"  Is In Cooldown: {is_cooldown} (expected: {test_is_in_cooldown})")
    offset += 4
    
    # CSM data
    csm_currencies = ['USD', 'EUR', 'GBP', 'JPY', 'AUD', 'CAD', 'CHF', 'NZD']
    print(f"  CSM Data:")
    for currency in csm_currencies:
        csm_value = struct.unpack('>d', packed[offset:offset+8])[0]
        expected = test_csm_data[currency]
        match = "✅" if abs(csm_value - expected) < 0.001 else "❌"
        print(f"    {currency}: {csm_value:.6f} (expected: {expected}) {match}")
        offset += 8
    
    # Grid direction
    grid_dir = struct.unpack('>i', packed[offset:offset+4])[0]
    print(f"  Grid Direction: {grid_dir} (expected: {test_grid_direction})")
    
    print()
    print("=" * 80)
    print("✅ Test complete! Copy hex dump to MQL5 test script.")
    print("=" * 80)
    
    # Output for MQL5 test
    print()
    print("For MQL5 TEST_PROTOCOL.mq5, use this data:")
    print("uchar test_data[] = {")
    hex_bytes = [f"0x{packed[i:i+1].hex()}" for i in range(len(packed))]
    for i in range(0, len(hex_bytes), 16):
        line = ", ".join(hex_bytes[i:i+16])
        if i + 16 < len(hex_bytes):
            line += ","
        print(f"    {line}")
    print("};")
    print()
    
    return packed


if __name__ == "__main__":
    try:
        test_protocol_v2()
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
