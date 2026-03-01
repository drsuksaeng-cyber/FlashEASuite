#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Strategy Engine Core
Main threading-safe engine class
"""

import zmq
import threading
import queue
import time
from typing import Dict, Any
from collections import deque

# Import sibling modules
from .analysis import MarketAnalyzer
from .feedback import FeedbackProcessor
from .policy import PolicyPublisher

# Import external modules (if available)
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
        
        # Initialize sub-modules
        self.market_analyzer = MarketAnalyzer(HAS_MODULES)
        self.feedback_processor = FeedbackProcessor()
        self.policy_publisher = PolicyPublisher()
        
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
    
    def _print_dashboard(self) -> None:
        """Print status dashboard."""
        current_time = time.time()
        
        # Print every 10 seconds
        if current_time - self.last_dashboard_time < 10:
            return
        
        self.last_dashboard_time = current_time
        
        # Get feedback stats
        stats = self.feedback_processor.get_stats()
        
        print("\n" + "=" * 70)
        print("📊 STRATEGY ENGINE DASHBOARD")
        print("=" * 70)
        print(f"Ticks processed: {self.tick_count}")
        print(f"Policies sent: {self.policy_count}")
        print(f"Feedback: {stats['total_wins']}W/{stats['total_losses']}L ({stats['total_trades']} trades)")
        print(f"Total profit: {stats['total_profit']:+.2f}")
        print(f"Risk multiplier: {stats['risk_multiplier']:.2f}x")
        
        if stats['is_in_cooldown']:
            remaining = stats['cooldown_until'] - current_time
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
                    self.feedback_processor.process_feedback(feedback)
                
                # Step 2: Process tick data (non-blocking)
                tick_data = None
                try:
                    tick_data = self.ingestion_queue.get(timeout=0.1)
                except queue.Empty:
                    pass
                
                if tick_data:
                    self.tick_count += 1
                    self.tick_buffer.append(tick_data)
                    
                    # Analyze market
                    signal = self.market_analyzer.analyze_market(
                        tick_data,
                        self.tick_buffer,
                        self.feedback_processor.is_in_cooldown()
                    )
                    
                    # Generate policy if signal exists
                    if signal:
                        symbol = tick_data.get('symbol', 'XAUUSD')
                        self.policy_publisher.publish_policy(
                            signal,
                            symbol,
                            self.pub_socket,
                            self.feedback_processor
                        )
                        self.policy_count += 1
                
                # Step 3: Publish Grid policy periodically
                current_time = time.time()
                if current_time - last_grid_policy_time >= GRID_POLICY_INTERVAL:
                    self.policy_publisher.publish_policy_with_grid_data(
                        'XAUUSD',
                        self.pub_socket,
                        self.feedback_processor
                    )
                    self.policy_count += 1
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
