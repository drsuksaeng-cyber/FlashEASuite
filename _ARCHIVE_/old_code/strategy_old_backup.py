#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Strategy Engine (Threading Version)
WITH FEEDBACK LOOP 🔄

Threading-safe version for Windows compatibility.
Simplified version focusing on core functionality.
"""

import zmq
import msgpack
import threading
import queue
import time
import logging
from typing import Dict, Any, Optional
from collections import deque

# Import modules (if available)
try:
    from modules.tick_analyzer import TickFlowAnalyzer
    from modules.currency_meter import CurrencyStrengthMeter
    HAS_MODULES = True
except ImportError:
    print("⚠️ Warning: tick_analyzer or currency_meter not found, using basic mode")
    HAS_MODULES = False


class StrategyEngineThreaded(threading.Thread):
    """
    Strategy Engine using Threading (Windows-safe).
    
    Receives:
    - Tick data from ingestion_queue
    - Trade results from feedback_queue
    
    Outputs:
    - Trading policies to MT5 via ZMQ PUB
    """
    
    def __init__(
        self,
        ingestion_queue: queue.Queue,
        signal_queue: queue.Queue,
        feedback_queue: queue.Queue,
        shutdown_event: threading.Event,
        zmq_pub_address: str = "tcp://127.0.0.1:7778"
    ):
        """
        Initialize Strategy Engine.
        
        Args:
            ingestion_queue: Queue with tick data
            signal_queue: Queue for signals (unused in this version)
            feedback_queue: Queue with trade results (Feedback Loop)
            shutdown_event: Event to signal shutdown
            zmq_pub_address: ZMQ address to publish policies
        """
        super().__init__(name="StrategyEngine")
        self.ingestion_queue = ingestion_queue
        self.signal_queue = signal_queue
        self.feedback_queue = feedback_queue
        self.shutdown_event = shutdown_event
        self.zmq_pub_address = zmq_pub_address
        
        # ZMQ socket
        self.context = None
        self.pub_socket = None
        
        # Modules (if available)
        if HAS_MODULES:
            try:
                # Try with window_size parameter first
                self.tick_analyzer = TickFlowAnalyzer(window_size=100)
            except TypeError:
                # If doesn't support window_size, create without it
                self.tick_analyzer = TickFlowAnalyzer()
            
            try:
                self.csm = CurrencyStrengthMeter()
            except Exception as e:
                print(f"⚠️ CSM initialization warning: {e}")
                self.csm = None
        else:
            self.tick_analyzer = None
            self.csm = None
        
        # Feedback state variables
        self.consecutive_wins = 0
        self.consecutive_losses = 0
        self.total_trades = 0
        self.total_wins = 0
        self.total_losses = 0
        self.total_profit = 0.0
        
        # Cooldown system
        self.cooldown_until = 0  # timestamp
        self.is_in_cooldown = False
        self.LOSS_COOLDOWN_SECONDS = 30.0
        self.EMERGENCY_COOLDOWN_SECONDS = 300.0
        self.MAX_CONSECUTIVE_LOSSES = 3
        
        # Risk management
        self.risk_multiplier = 1.0  # Range: 0.5 - 1.5
        self.MIN_RISK_MULTIPLIER = 0.5
        self.MAX_RISK_MULTIPLIER = 1.5
        
        # Statistics
        self.tick_count = 0
        self.policy_count = 0
        self.last_dashboard_time = 0
        
        # Tick buffer
        self.tick_buffer = deque(maxlen=100)
    
    def _setup_zmq(self) -> bool:
        """Setup ZMQ PUB socket."""
        try:
            self.context = zmq.Context()
            self.pub_socket = self.context.socket(zmq.PUB)
            self.pub_socket.bind(self.zmq_pub_address)
            
            print(f"📤 STRATEGY: Publishing policies on {self.zmq_pub_address}")
            return True
            
        except Exception as e:
            print(f"❌ STRATEGY: Failed to setup ZMQ: {e}")
            return False
    
    def _process_feedback(self, feedback: Dict[str, Any]) -> None:
        """
        Process trade result feedback and adapt strategy.
        
        Args:
            feedback: Trade result dictionary
        """
        ticket = feedback.get('ticket', 0)
        symbol = feedback.get('symbol', 'N/A')
        profit = feedback.get('profit', 0.0)
        is_win = feedback.get('is_win', False)
        is_loss = feedback.get('is_loss', False)
        
        self.total_trades += 1
        
        if is_win:
            # WIN Logic
            self.total_wins += 1
            self.consecutive_wins += 1
            self.consecutive_losses = 0  # Reset
            self.total_profit += profit
            
            # Increase risk (max 1.5x)
            self.risk_multiplier *= 1.1
            if self.risk_multiplier > self.MAX_RISK_MULTIPLIER:
                self.risk_multiplier = self.MAX_RISK_MULTIPLIER
            
            # Cancel cooldown if active
            if self.is_in_cooldown:
                self.is_in_cooldown = False
                self.cooldown_until = 0
                print("✅ COOLDOWN CANCELED - Win during cooldown!")
            
            # Hot streak detection
            if self.consecutive_wins >= 3:
                print(f"🔥 HOT STREAK! {self.consecutive_wins} consecutive wins!")
            
            print(f"💚 FEEDBACK: WIN | Ticket {ticket} | Profit: +{profit:.2f}")
            
        elif is_loss:
            # LOSS Logic
            self.total_losses += 1
            self.consecutive_losses += 1
            self.consecutive_wins = 0  # Reset
            self.total_profit += profit  # profit is negative
            
            # Decrease risk (min 0.5x)
            self.risk_multiplier *= 0.9
            if self.risk_multiplier < self.MIN_RISK_MULTIPLIER:
                self.risk_multiplier = self.MIN_RISK_MULTIPLIER
            
            # Trigger cooldown
            current_time = time.time()
            
            if self.consecutive_losses >= self.MAX_CONSECUTIVE_LOSSES:
                # EMERGENCY COOLDOWN
                self.cooldown_until = current_time + self.EMERGENCY_COOLDOWN_SECONDS
                self.is_in_cooldown = True
                print(f"🚨 EMERGENCY COOLDOWN! {self.consecutive_losses} consecutive losses!")
                print(f"🛑 Trading paused for {self.EMERGENCY_COOLDOWN_SECONDS:.0f} seconds")
            else:
                # Normal cooldown
                self.cooldown_until = current_time + self.LOSS_COOLDOWN_SECONDS
                self.is_in_cooldown = True
                print(f"⚠️ COOLDOWN ACTIVATED for {self.LOSS_COOLDOWN_SECONDS:.0f} seconds")
            
            print(f"💔 FEEDBACK: LOSS | Ticket {ticket} | Loss: {profit:.2f}")
        
        else:
            # Breakeven
            print(f"⚪ FEEDBACK: BREAKEVEN | Ticket {ticket} | Profit: {profit:.2f}")
        
        # Display statistics
        win_rate = (self.total_wins / self.total_trades * 100) if self.total_trades > 0 else 0
        print(f"📊 Stats: {self.total_wins}W / {self.total_losses}L / {self.total_profit:+.2f} Total "
              f"| Win Rate: {win_rate:.1f}% | Risk: {self.risk_multiplier:.2f}x")
    
    def _check_cooldown(self) -> bool:
        """
        Check if currently in cooldown.
        
        Returns:
            True if in cooldown (should not trade), False otherwise
        """
        if not self.is_in_cooldown:
            return False
        
        current_time = time.time()
        
        # Check if cooldown expired
        if current_time >= self.cooldown_until:
            self.is_in_cooldown = False
            print("✅ COOLDOWN ENDED - Trading resumed")
            return False
        
        # Still in cooldown
        remaining = self.cooldown_until - current_time
        
        # Print every 10 seconds
        if int(remaining) % 10 == 0:
            print(f"⏳ COOLDOWN: {remaining:.0f}s remaining...")
        
        return True
    
    def _analyze_market(self, tick_data: Dict[str, Any]) -> Optional[str]:
        """
        Analyze market and generate signal.
        
        Args:
            tick_data: Tick data dictionary
            
        Returns:
            'BUY', 'SELL', or None
        """
        # Check cooldown first
        if self._check_cooldown():
            return None
        
        # Basic analysis (placeholder - add your strategy here)
        symbol = tick_data.get('symbol', '')
        bid = tick_data.get('bid', 0.0)
        ask = tick_data.get('ask', 0.0)
        
        # Add to buffer
        self.tick_buffer.append(tick_data)
        
        # Simple example: Use modules if available
        if HAS_MODULES and len(self.tick_buffer) > 10:
            # Use TickAnalyzer
            if self.tick_analyzer:
                self.tick_analyzer.add_tick(bid)
            
            # Use CSM (simplified - actual implementation is more complex)
            # This is just a placeholder
            pass
        
        # Return None for now (no signal)
        return None
    
    def _publish_policy(self, signal: str, symbol: str, confidence: float = 0.8) -> None:
        """
        Publish trading policy to MT5.
        
        Args:
            signal: 'BUY' or 'SELL'
            symbol: Symbol name
            confidence: Signal confidence
        """
        # Apply risk multiplier to confidence
        adjusted_confidence = confidence * self.risk_multiplier
        
        # Create policy message
        policy = {
            'type': 'POLICY',
            'symbol': symbol,
            'action': 1 if signal == 'BUY' else 2,  # 0=HOLD, 1=BUY, 2=SELL
            'confidence': adjusted_confidence,
            'timestamp': int(time.time() * 1000),
            'model_version': 'DYN_V6_FEEDBACK',
            'debug_info': f"Risk:{self.risk_multiplier:.2f}x"
        }
        
        # Pack and send
        packed = msgpack.packb(policy)
        self.pub_socket.send(packed)
        
        self.policy_count += 1
        print(f"📤 POLICY: {signal} {symbol} | Confidence: {adjusted_confidence:.2f} | "
              f"Risk: {self.risk_multiplier:.2f}x")
    
    def publish_policy_with_grid_data(self, symbol: str = 'XAUUSD') -> None:
        """
        Publish policy with Grid-specific data.
        
        This method sends comprehensive data for the Elastic Grid Strategy:
        - risk_multiplier (from feedback loop)
        - is_in_cooldown (pause trading)
        - confidence (based on performance)
        - CSM data (currency strength)
        
        Args:
            symbol: Symbol to trade
        """
        # Calculate confidence from performance
        confidence = self._calculate_confidence()
        
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
            'risk_multiplier': self.risk_multiplier,
            'is_in_cooldown': self.is_in_cooldown,
            'confidence': confidence,
            
            # CSM data
            'csm': csm_data,
            
            # Debug info
            'debug_info': {
                'total_trades': self.total_trades,
                'win_rate': (self.total_wins / self.total_trades * 100) if self.total_trades > 0 else 0,
                'total_profit': self.total_profit,
                'consecutive_wins': self.consecutive_wins,
                'consecutive_losses': self.consecutive_losses
            }
        }
        
        # Pack and send
        packed = msgpack.packb(policy)
        self.pub_socket.send(packed)
        
        self.policy_count += 1
        
        # Log
        print(f"📤 POLICY (Grid): {symbol}")
        print(f"   Risk: {self.risk_multiplier:.2f}x | Cooldown: {self.is_in_cooldown} | Conf: {confidence:.2f}")
        if csm_data.get('USD') is not None:
            print(f"   CSM: USD={csm_data.get('USD', 0):.2f} EUR={csm_data.get('EUR', 0):.2f}")
    
    def _calculate_confidence(self) -> float:
        """
        Calculate trading confidence based on recent performance.
        
        Returns:
            Confidence score (0.0 - 1.0)
        """
        if self.total_trades == 0:
            return 0.5  # Medium confidence (no data yet)
        
        # Calculate win rate
        win_rate = self.total_wins / self.total_trades if self.total_trades > 0 else 0.5
        
        # Map win rate to confidence
        # 0% win rate → 0.1 confidence (very low)
        # 50% win rate → 0.5 confidence (medium)
        # 70%+ win rate → 0.8 confidence (high)
        
        if win_rate >= 0.7:
            confidence = 0.8
        elif win_rate >= 0.5:
            confidence = 0.5
        elif win_rate >= 0.3:
            confidence = 0.3
        else:
            confidence = 0.1  # Very low, likely pause grid
        
        # Adjust for consecutive losses (emergency)
        if self.consecutive_losses >= 3:
            confidence = 0.0  # Force pause
        
        return confidence
    
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
        
        # If CSM module available, get real data
        if HAS_MODULES and self.csm is not None:
            try:
                # Use scores_fast dictionary (fast strength calculation)
                csm_data['USD'] = self.csm.scores_fast.get('USD', 5.0)
                csm_data['EUR'] = self.csm.scores_fast.get('EUR', 5.0)
                csm_data['GBP'] = self.csm.scores_fast.get('GBP', 5.0)
                csm_data['JPY'] = self.csm.scores_fast.get('JPY', 5.0)
            except Exception as e:
                print(f"⚠️ CSM error: {e}")
        
        return csm_data
    
    def _print_dashboard(self) -> None:
        """Print status dashboard."""
        current_time = time.time()
        
        # Print every 10 seconds
        if current_time - self.last_dashboard_time < 10:
            return
        
        self.last_dashboard_time = current_time
        
        print("\n" + "=" * 70)
        print("📊 STRATEGY ENGINE DASHBOARD")
        print("=" * 70)
        print(f"Ticks processed: {self.tick_count}")
        print(f"Policies sent: {self.policy_count}")
        print(f"Feedback: {self.total_wins}W/{self.total_losses}L ({self.total_trades} trades)")
        print(f"Total profit: {self.total_profit:+.2f}")
        print(f"Risk multiplier: {self.risk_multiplier:.2f}x")
        
        if self.is_in_cooldown:
            remaining = self.cooldown_until - current_time
            print(f"⏳ COOLDOWN: {remaining:.0f}s remaining")
        else:
            print("✅ Trading active")
        
        print("=" * 70 + "\n")
    
    def run(self) -> None:
        """Main worker loop."""
        print("🔄 STRATEGY ENGINE: Worker started")
        print("🧠 LOGIC: Starting Engine with FEEDBACK LOOP... Waiting for Data...")
        
        # Setup ZMQ
        if not self._setup_zmq():
            print("❌ STRATEGY: Failed to initialize, exiting")
            return
        
        # Small delay to ensure socket binding
        time.sleep(1)
        
        # Grid policy timer
        last_grid_policy_time = 0
        GRID_POLICY_INTERVAL = 5.0  # Publish Grid policy every 5 seconds
        
        try:
            while not self.shutdown_event.is_set():
                # Step 1: Check for feedback (non-blocking)
                feedback = None
                try:
                    feedback = self.feedback_queue.get_nowait()
                except queue.Empty:
                    pass
                
                if feedback:
                    self._process_feedback(feedback)
                
                # Step 2: Process tick data (non-blocking)
                tick_data = None
                try:
                    tick_data = self.ingestion_queue.get(timeout=0.1)
                except queue.Empty:
                    pass
                
                if tick_data:
                    self.tick_count += 1
                    
                    # Analyze market
                    signal = self._analyze_market(tick_data)
                    
                    # Generate policy if signal exists
                    if signal:
                        symbol = tick_data.get('symbol', 'XAUUSD')
                        self._publish_policy(signal, symbol)
                
                # Step 3: Publish Grid policy periodically
                current_time = time.time()
                if current_time - last_grid_policy_time >= GRID_POLICY_INTERVAL:
                    self.publish_policy_with_grid_data('XAUUSD')
                    last_grid_policy_time = current_time
                
                # Step 4: Print dashboard
                self._print_dashboard()
                
                # Small sleep to prevent busy loop
                time.sleep(0.01)
        
        except Exception as e:
            print(f"❌ STRATEGY: Unexpected error: {e}")
            import traceback
            traceback.print_exc()
        
        finally:
            # Cleanup
            print(f"\n🛑 STRATEGY ENGINE: Shutting down "
                  f"(Ticks: {self.tick_count}, Policies: {self.policy_count})")
            
            if self.pub_socket:
                self.pub_socket.close()
            if self.context:
                self.context.term()
            
            print("✅ STRATEGY ENGINE: Worker stopped")


def create_strategy_engine_threaded(
    ingestion_queue: queue.Queue,
    signal_queue: queue.Queue,
    feedback_queue: queue.Queue,
    shutdown_event: threading.Event,
    zmq_pub_address: str = "tcp://127.0.0.1:7778"
) -> threading.Thread:
    """
    Factory function to create Strategy Engine thread.
    
    Args:
        ingestion_queue: Thread-safe queue with tick data
        signal_queue: Thread-safe queue for signals
        feedback_queue: Thread-safe queue with trade results
        shutdown_event: Shutdown event
        zmq_pub_address: ZMQ address
        
    Returns:
        StrategyEngineThreaded instance (not started)
    """
    return StrategyEngineThreaded(
        ingestion_queue=ingestion_queue,
        signal_queue=signal_queue,
        feedback_queue=feedback_queue,
        shutdown_event=shutdown_event,
        zmq_pub_address=zmq_pub_address
    )
