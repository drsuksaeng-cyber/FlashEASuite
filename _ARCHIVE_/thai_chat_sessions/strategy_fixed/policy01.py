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
                         position_size, timestamp_ms, model_version,
                         risk_multiplier=1.0, is_in_cooldown=False,
                         csm_data=None, grid_direction=0):
    """
    Pack policy as Custom Protocol (compatible with Serialization.mqh).
    
    EXTENDED VERSION 2.0 - Includes Grid Strategy fields
    
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
    
    GRID FIELDS (NEW):
    - double: risk_multiplier (0.5-1.5)
    - int32: is_in_cooldown (0=active, 1=paused)
    - double: csm_usd
    - double: csm_eur
    - double: csm_gbp
    - double: csm_jpy
    - double: csm_aud
    - double: csm_cad
    - double: csm_chf
    - double: csm_nzd
    - int32: grid_direction (0=NONE, 1=BUY, 2=SELL)
    
    Args:
        msg_type: Message type (2 for POLICY)
        symbol: Symbol name (e.g., "XAUUSD")
        action: 0=HOLD, 1=BUY, 2=SELL
        confidence: Confidence score (0.0-1.0)
        entry_price: Entry price
        stop_loss: Stop loss price
        take_profit: Take profit price
        position_size: Position size in lots
        timestamp_ms: Timestamp in milliseconds
        model_version: Model version string
        risk_multiplier: Risk adjustment (default 1.0)
        is_in_cooldown: Pause trading flag (default False)
        csm_data: Dict with currency strengths (default None)
        grid_direction: 0=NONE, 1=BUY, 2=SELL (default 0)
        
    Returns:
        bytes: Custom Protocol binary (big-endian)
    """
    data = bytearray()
    
    # ===== ORIGINAL FIELDS =====
    
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
    
    # ===== GRID EXTENDED FIELDS =====
    
    # Risk multiplier (double)
    data.extend(struct.pack('>d', risk_multiplier))
    
    # Is in cooldown (int32: 0 or 1)
    data.extend(struct.pack('>i', 1 if is_in_cooldown else 0))
    
    # CSM data (8 doubles)
    if csm_data is None:
        csm_data = {}
    
    data.extend(struct.pack('>d', csm_data.get('USD', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('EUR', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('GBP', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('JPY', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('AUD', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('CAD', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('CHF', 0.0)))
    data.extend(struct.pack('>d', csm_data.get('NZD', 0.0)))
    
    # Grid direction (int32)
    data.extend(struct.pack('>i', grid_direction))
    
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


# ========== GRID STRATEGY HELPER FUNCTIONS ==========

def get_csm_data() -> Dict[str, float]:
    """
    Get Currency Strength Meter data from CSM module.
    
    Returns:
        Dictionary with currency strengths (USD, EUR, GBP, JPY, AUD, CAD, CHF, NZD)
        Default values: 0.0 (neutral) if CSM module unavailable
    """
    csm_data = {
        'USD': 0.0,
        'EUR': 0.0,
        'GBP': 0.0,
        'JPY': 0.0,
        'AUD': 0.0,
        'CAD': 0.0,
        'CHF': 0.0,
        'NZD': 0.0
    }
    
    # Try to get CSM data if module available
    try:
        from modules.currency_meter import CurrencyStrengthMeter
        
        # Create CSM instance
        csm = CurrencyStrengthMeter()
        
        # Use scores_fast dictionary (fast strength calculation)
        csm_data['USD'] = csm.scores_fast.get('USD', 0.0)
        csm_data['EUR'] = csm.scores_fast.get('EUR', 0.0)
        csm_data['GBP'] = csm.scores_fast.get('GBP', 0.0)
        csm_data['JPY'] = csm.scores_fast.get('JPY', 0.0)
        csm_data['AUD'] = csm.scores_fast.get('AUD', 0.0)
        csm_data['CAD'] = csm.scores_fast.get('CAD', 0.0)
        csm_data['CHF'] = csm.scores_fast.get('CHF', 0.0)
        csm_data['NZD'] = csm.scores_fast.get('NZD', 0.0)
        
    except ImportError:
        # Module not available, use defaults (0.0 = neutral)
        pass
    except Exception as e:
        print(f"⚠️ CSM error: {e}")
    
    return csm_data


def determine_grid_direction(csm_data: Dict[str, float], symbol: str) -> int:
    """
    Determine Grid direction based on CSM data and symbol.
    
    Logic:
    - For EURUSD: EUR strong → BUY (1), USD strong → SELL (2)
    - For GBPUSD: GBP strong → BUY (1), USD strong → SELL (2)
    - For USDJPY: USD strong → BUY (1), JPY strong → SELL (2)
    - For XAUUSD: Use USD strength inverted (Gold vs USD)
    
    Args:
        csm_data: Dictionary with currency strengths
        symbol: Symbol name (e.g., "EURUSD", "XAUUSD")
        
    Returns:
        0 = GRID_DIR_NONE (neutral, no grid)
        1 = GRID_DIR_BUY (long grid)
        2 = GRID_DIR_SELL (short grid)
    """
    # Clean symbol (remove broker suffixes)
    clean_symbol = symbol.replace('.tp', '').replace('.m', '').replace('.i', '').upper()
    
    # Threshold for direction decision (minimum strength difference)
    threshold = 0.5
    
    # ✅ ADDED: Check if CSM data is available (all zeros = no data)
    csm_total = sum(abs(v) for v in csm_data.values())
    if csm_total < 0.1:  # All CSM values are zero or near-zero
        print("⚠️ CSM data not available, using simple alternating strategy")
        # Fallback: Alternate between BUY and SELL every 30 seconds
        import time
        cycle = int(time.time() / 30) % 2  # 0 or 1 every 30 seconds
        if cycle == 0:
            print("   → Fallback: BUY (cycle 0)")
            return 1  # BUY
        else:
            print("   → Fallback: SELL (cycle 1)")
            return 2  # SELL
    
    # Parse symbol into base and quote currencies
    if clean_symbol == 'EURUSD':
        base_strength = csm_data.get('EUR', 0.0)
        quote_strength = csm_data.get('USD', 0.0)
    elif clean_symbol == 'GBPUSD':
        base_strength = csm_data.get('GBP', 0.0)
        quote_strength = csm_data.get('USD', 0.0)
    elif clean_symbol == 'USDJPY':
        base_strength = csm_data.get('USD', 0.0)
        quote_strength = csm_data.get('JPY', 0.0)
    elif clean_symbol == 'AUDUSD':
        base_strength = csm_data.get('AUD', 0.0)
        quote_strength = csm_data.get('USD', 0.0)
    elif clean_symbol == 'USDCAD':
        base_strength = csm_data.get('USD', 0.0)
        quote_strength = csm_data.get('CAD', 0.0)
    elif clean_symbol == 'USDCHF':
        base_strength = csm_data.get('USD', 0.0)
        quote_strength = csm_data.get('CHF', 0.0)
    elif clean_symbol == 'NZDUSD':
        base_strength = csm_data.get('NZD', 0.0)
        quote_strength = csm_data.get('USD', 0.0)
    elif clean_symbol == 'XAUUSD':
        # Gold: Strong USD → SELL (2), Weak USD → BUY (1)
        base_strength = -csm_data.get('USD', 0.0)  # Invert USD for gold
        quote_strength = 0.0
    else:
        # Unknown symbol: No direction
        return 0
    
    # Calculate strength difference
    strength_diff = base_strength - quote_strength
    
    # Determine direction
    if strength_diff > threshold:
        return 1  # GRID_DIR_BUY (base currency stronger)
    elif strength_diff < -threshold:
        return 2  # GRID_DIR_SELL (quote currency stronger)
    else:
        return 0  # GRID_DIR_NONE (neutral, no clear direction)


def publish_grid_policy(
    symbol: str,
    pub_socket,
    feedback_processor,
    csm_data: Optional[Dict[str, float]] = None,
    current_price: float = 0.0  # ✅ NEW: Add current price parameter
) -> bytes:
    """
    Publish comprehensive Grid policy with all extended fields.
    
    This function sends a complete policy message including:
    - Risk multiplier from feedback loop
    - Cooldown status
    - Confidence score based on performance
    - CSM data for all 8 currencies
    - Grid direction based on CSM analysis
    
    Args:
        symbol: Symbol to trade (e.g., "XAUUSD.tp")
        pub_socket: ZMQ PUB socket
        feedback_processor: FeedbackProcessor instance
        csm_data: Optional CSM data dict (will fetch if None)
        current_price: Current market price (default 0.0)
        
    Returns:
        bytes: Packed message
    """
    # Get feedback stats
    stats = feedback_processor.get_stats()
    
    # Calculate confidence from performance
    confidence = feedback_processor.calculate_confidence()
    
    # Get CSM data if not provided
    if csm_data is None:
        csm_data = get_csm_data()
    
    # Determine grid direction from CSM
    grid_direction = determine_grid_direction(csm_data, symbol)
    
    # ✅ FIXED: Use grid_direction as action (TEST MODE - direct trading)
    # In production, this should be action=0 with Grid Strategy handling it
    # But for testing, we send action directly so orders execute
    action = grid_direction  # 0=HOLD, 1=BUY, 2=SELL
    
    # ✅ FIXED: Use current_price as entry_price (default to 1.0 if not provided)
    entry_price = current_price if current_price > 0 else 1.0
    
    # Create comprehensive policy with all Grid fields
    packed = pack_custom_protocol(
        msg_type=2,                              # MSG_TYPE_POLICY
        symbol=symbol,
        action=action,                           # ✅ FIXED: Use grid_direction instead of 0
        confidence=confidence,
        entry_price=entry_price,                 # ✅ FIXED: Use real price instead of 0.0
        stop_loss=0.0,
        take_profit=0.0,
        position_size=0.01,
        timestamp_ms=int(time.time() * 1000),
        model_version="GRID_V2_FEEDBACK",
        # Grid extended fields
        risk_multiplier=stats['risk_multiplier'],
        is_in_cooldown=stats['is_in_cooldown'],
        csm_data=csm_data,
        grid_direction=grid_direction
    )
    
    # Send via ZMQ
    pub_socket.send(packed)
    
    # Log comprehensive info
    action_name = 'HOLD' if action == 0 else ('BUY' if action == 1 else 'SELL')
    print(f"📤 GRID POLICY: {symbol} ({len(packed)} bytes)")
    print(f"   Action: {action_name} | Entry: {entry_price:.2f} | Risk: {stats['risk_multiplier']:.2f}x | Cooldown: {stats['is_in_cooldown']}")
    print(f"   Confidence: {confidence:.2f} | Direction: {grid_direction} ({'BUY' if grid_direction == 1 else 'SELL' if grid_direction == 2 else 'NONE'})")
    print(f"   Performance: {stats['total_wins']}W/{stats['total_losses']}L | Profit: {stats['total_profit']:+.2f}")
    
    # Log CSM if available
    if csm_data.get('USD') != 0.0 or csm_data.get('EUR') != 0.0:
        print(f"   CSM: USD={csm_data.get('USD', 0):.2f} EUR={csm_data.get('EUR', 0):.2f} " +
              f"GBP={csm_data.get('GBP', 0):.2f} JPY={csm_data.get('JPY', 0):.2f}")
    
    return packed


# ========== CHANGE LOG ==========
# Version 2.0 (2025-12-28):
# - Extended pack_custom_protocol() with 11 new Grid fields
# - Added get_csm_data() helper function
# - Added determine_grid_direction() helper function
# - Added publish_grid_policy() comprehensive function
# - Message size increased: ~50 bytes → ~205 bytes
#
# Grid Extended Fields:
# 1. risk_multiplier (double): From FeedbackProcessor
# 2. is_in_cooldown (bool): Trading pause flag
# 3-10. csm_usd/eur/gbp/jpy/aud/cad/chf/nzd (8 doubles): Currency strengths
# 11. grid_direction (int): 0=NONE, 1=BUY, 2=SELL
#
# Compatibility:
# - Requires MQL5 Serialization.mqh V2.0
# - Requires MQL5 Definitions.mqh V2.0
# - Breaking change from V1.0

