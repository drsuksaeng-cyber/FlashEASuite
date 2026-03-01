#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Policy Publishing Module
UPDATED: Custom Protocol format (compatible with Serialization.mqh from GitHub)
"""

import time
import struct
import msgpack
from typing import Dict, Any, Optional


class PolicyPublisher:
    """
    Policy publishing module for sending trading policies to MT5.
    
    Handles:
    - Policy message creation
    - CSM data integration
    - ZMQ message packing
    """
    
    def __init__(self):
        """Initialize Policy Publisher."""
        pass
    
    def publish_policy(
        self,
        signal: str,
        symbol: str,
        pub_socket,
        feedback_processor,
        confidence: float = 0.8
    ) -> None:
        """
        Publish trading policy to MT5.
        
        Args:
            signal: 'BUY' or 'SELL'
            symbol: Symbol name
            pub_socket: ZMQ PUB socket
            feedback_processor: FeedbackProcessor instance
            confidence: Signal confidence
        """
        # Get risk multiplier from feedback
        risk_multiplier = feedback_processor.get_risk_multiplier()
        
        # Apply risk multiplier to confidence
        adjusted_confidence = confidence * risk_multiplier
        
        # Create policy message
        policy = {
            'type': 'POLICY',
            'symbol': symbol,
            'action': 1 if signal == 'BUY' else 2,  # 0=HOLD, 1=BUY, 2=SELL
            'confidence': adjusted_confidence,
            'timestamp': int(time.time() * 1000),
            'model_version': 'DYN_V6_FEEDBACK',
            'debug_info': f"Risk:{risk_multiplier:.2f}x"
        }
        
        # Pack and send
        packed = msgpack.packb(policy)
        pub_socket.send(packed)
        
        print(f"📤 POLICY: {signal} {symbol} | Confidence: {adjusted_confidence:.2f} | "
              f"Risk: {risk_multiplier:.2f}x")
    
    def publish_policy_with_grid_data(
        self,
        symbol: str,
        pub_socket,
        feedback_processor
    ) -> None:
        """
        Publish policy with Grid-specific data.
        
        This method sends comprehensive data for the Elastic Grid Strategy:
        - risk_multiplier (from feedback loop)
        - is_in_cooldown (pause trading)
        - confidence (based on performance)
        - CSM data (currency strength)
        
        Args:
            symbol: Symbol to trade
            pub_socket: ZMQ PUB socket
            feedback_processor: FeedbackProcessor instance
        """
        # Get feedback stats
        stats = feedback_processor.get_stats()
        
        # Calculate confidence from performance
        confidence = feedback_processor.calculate_confidence()
        
        # Get CSM data (if available)
        csm_data = self._get_csm_data()
        
        # Create comprehensive policy
        policy = {
            'type': 'POLICY',
            'symbol': symbol,
            'action': 0,  # 0=HOLD, wait for Grid to decide
            'weight': 1.0,
            'timestamp': int(time.time() * 1000),
            'model_version': 'DYN_V6_FEEDBACK_GRID',
            
            # Grid-specific data
            'risk_multiplier': stats['risk_multiplier'],
            'is_in_cooldown': stats['is_in_cooldown'],
            'confidence': confidence,
            
            # CSM data
            'csm': csm_data,
            
            # Debug info
            'debug_info': {
                'total_trades': stats['total_trades'],
                'win_rate': (stats['total_wins'] / stats['total_trades'] * 100) if stats['total_trades'] > 0 else 0,
                'total_profit': stats['total_profit'],
                'consecutive_wins': stats['consecutive_wins'],
                'consecutive_losses': stats['consecutive_losses']
            }
        }
        
        # Pack and send
        packed = msgpack.packb(policy)
        pub_socket.send(packed)
        
        # Log
        print(f"📤 POLICY (Grid): {symbol}")
        print(f"   Risk: {stats['risk_multiplier']:.2f}x | Cooldown: {stats['is_in_cooldown']} | Conf: {confidence:.2f}")
        if csm_data.get('USD') is not None:
            print(f"   CSM: USD={csm_data.get('USD', 0):.2f} EUR={csm_data.get('EUR', 0):.2f}")
    
    def _get_csm_data(self) -> Dict[str, float]:
        """
        Get Currency Strength Meter data.
        
        Returns:
            Dictionary with currency strengths
        """
        csm_data = {
            'USD': 0.0,
            'EUR': 0.0,
            'GBP': 0.0,
            'JPY': 0.0
        }
        
        # Try to get CSM data if module available
        try:
            from modules.currency_meter import CurrencyStrengthMeter
            
            # Create CSM instance
            csm = CurrencyStrengthMeter()
            
            # Use scores_fast dictionary (fast strength calculation)
            csm_data['USD'] = csm.scores_fast.get('USD', 5.0)
            csm_data['EUR'] = csm.scores_fast.get('EUR', 5.0)
            csm_data['GBP'] = csm.scores_fast.get('GBP', 5.0)
            csm_data['JPY'] = csm.scores_fast.get('JPY', 5.0)
            
        except ImportError:
            # Module not available, use defaults
            pass
        except Exception as e:
            print(f"⚠️ CSM error: {e}")
        
        return csm_data


# ========== NEW: CUSTOM PROTOCOL FORMAT ==========

def pack_custom_protocol(msg_type, symbol, action, confidence, 
                         entry_price, stop_loss, take_profit, 
                         position_size, timestamp_ms, model_version):
    """
    Pack policy as Custom Protocol (compatible with Serialization.mqh).
    
    Format matches CProtocol::DeserializePolicyMessage():
    - int32: message type (2 = POLICY)
    - string: symbol (int32 length + utf-8 bytes)
    - int32: action (0=HOLD, 1=BUY, 2=SELL)
    - double: confidence
    - double: entry_price
    - double: stop_loss
    - double: take_profit
    - double: position_size
    - int64: timestamp_ms
    - string: model_version
    
    Args:
        All policy fields
        
    Returns:
        bytes: Custom Protocol binary
    """
    data = bytearray()
    
    # Message type (int32, big-endian)
    data.extend(struct.pack('>i', msg_type))
    
    # Symbol (string: length + bytes)
    symbol_bytes = symbol.encode('utf-8')
    data.extend(struct.pack('>i', len(symbol_bytes)))
    data.extend(symbol_bytes)
    
    # Action (int32)
    data.extend(struct.pack('>i', action))
    
    # Confidence (double, big-endian)
    data.extend(struct.pack('>d', confidence))
    
    # Entry price (double)
    data.extend(struct.pack('>d', entry_price))
    
    # Stop loss (double)
    data.extend(struct.pack('>d', stop_loss))
    
    # Take profit (double)
    data.extend(struct.pack('>d', take_profit))
    
    # Position size (double)
    data.extend(struct.pack('>d', position_size))
    
    # Timestamp (int64, big-endian)
    data.extend(struct.pack('>q', timestamp_ms))
    
    # Model version (string: length + bytes)
    version_bytes = model_version.encode('utf-8')
    data.extend(struct.pack('>i', len(version_bytes)))
    data.extend(version_bytes)
    
    return bytes(data)


def publish_policy_custom(symbol, pub_socket):
    """
    Send policy using Custom Protocol format.
    
    This is compatible with Serialization.mqh from GitHub.
    
    Args:
        symbol: Symbol name (e.g., "XAUUSD")
        pub_socket: ZMQ PUB socket
    """
    packed = pack_custom_protocol(
        msg_type=2,              # MSG_TYPE_POLICY
        symbol=symbol,           # "XAUUSD"
        action=1,                # 1=BUY
        confidence=0.8,
        entry_price=0.0,
        stop_loss=0.0,
        take_profit=0.0,
        position_size=0.01,
        timestamp_ms=int(time.time() * 1000),
        model_version="CUSTOM_V1"
    )
    
    pub_socket.send(packed)
    print(f"📤 POLICY (Custom): {symbol} action=BUY conf=0.80 ({len(packed)} bytes)")
    return packed
