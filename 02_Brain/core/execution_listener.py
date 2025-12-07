#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Execution Listener (Threading Version)
Receives trade results from MT5 Trader via ZMQ

Threading-safe version for Windows compatibility.
"""

import zmq
import msgpack
import threading
import queue
import time
from typing import Dict, Any, Optional
from datetime import datetime


class ExecutionListenerThreaded(threading.Thread):
    """
    Execution Listener using Threading (Windows-safe).
    
    Receives trade results from MT5 Trader (Program C) via ZMQ PULL socket
    and forwards to Strategy Engine via thread-safe queue (Feedback Loop).
    """
    
    def __init__(
        self,
        feedback_queue: queue.Queue,
        shutdown_event: threading.Event,
        zmq_pull_address: str = "tcp://127.0.0.1:7779"
    ):
        """
        Initialize Execution Listener.
        
        Args:
            feedback_queue: Thread-safe queue to forward feedback
            shutdown_event: Event to signal shutdown
            zmq_pull_address: ZMQ address to pull from
        """
        super().__init__(name="ExecutionListener")
        self.feedback_queue = feedback_queue
        self.shutdown_event = shutdown_event
        self.zmq_pull_address = zmq_pull_address
        
        # ZMQ socket (will be created in run())
        self.context = None
        self.pull_socket = None
        
        # Statistics
        self.message_count = 0
        self.error_count = 0
    
    def _setup_zmq(self) -> bool:
        """
        Setup ZMQ PULL socket.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self.context = zmq.Context()
            self.pull_socket = self.context.socket(zmq.PULL)
            self.pull_socket.bind(self.zmq_pull_address)
            self.pull_socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1 second timeout
            
            print(f"📥 EXECUTION LISTENER: Ready to receive trade results on {self.zmq_pull_address}")
            return True
            
        except Exception as e:
            print(f"❌ EXECUTION LISTENER: Failed to setup ZMQ: {e}")
            return False
    
    def _parse_trade_result(self, raw_data: bytes) -> Optional[Dict[str, Any]]:
        """
        Parse MessagePack trade result.
        
        Format (12 fields):
        [0] msg_type: 100 (TRADE_RESULT)
        [1] timestamp: milliseconds
        [2] ticket: position ticket
        [3] symbol: "XAUUSD"
        [4] type: 0=BUY, 1=SELL
        [5] volume: lot size
        [6] open_price: entry price
        [7] sl: stop loss
        [8] tp: take profit
        [9] profit: P&L
        [10] magic: magic number
        [11] comment: order comment
        
        Args:
            raw_data: Raw binary data
            
        Returns:
            Parsed result dictionary or None if invalid
        """
        try:
            data = msgpack.unpackb(raw_data, raw=False)
            
            # Validate format
            if not isinstance(data, list) or len(data) < 12:
                print(f"⚠️ Invalid data format: Expected 12 fields, got {len(data)}")
                return None
            
            # Extract fields
            result = {
                'msg_type': int(data[0]),
                'timestamp': int(data[1]),
                'ticket': int(data[2]),
                'symbol': str(data[3]),
                'type': int(data[4]),
                'volume': float(data[5]),
                'open_price': float(data[6]),
                'sl': float(data[7]),
                'tp': float(data[8]),
                'profit': float(data[9]),
                'magic': int(data[10]),
                'comment': str(data[11]),
            }
            
            # Add computed fields
            result['is_win'] = result['profit'] > 0
            result['is_loss'] = result['profit'] < 0
            result['datetime'] = datetime.fromtimestamp(result['timestamp'] / 1000.0)
            
            return result
            
        except Exception as e:
            print(f"⚠️ EXECUTION LISTENER: Parse error: {e}")
            return None
    
    def _log_trade_result(self, result: Dict[str, Any]) -> None:
        """
        Log trade result to console.
        
        Args:
            result: Parsed trade result
        """
        # Determine result type
        if result['is_win']:
            emoji = "💚"
            result_type = "WIN"
        elif result['is_loss']:
            emoji = "💔"
            result_type = "LOSS"
        else:
            emoji = "⚪"
            result_type = "BREAKEVEN"
        
        print("=" * 60)
        print(f"📥 [Message #{self.message_count}] Trade Result Received!")
        print("=" * 60)
        print(f"   🕐 Time:       {result['datetime'].strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}")
        print(f"   🎫 Ticket:     {result['ticket']}")
        print(f"   📊 Symbol:     {result['symbol']}")
        print(f"   📈 Type:       {'BUY' if result['type'] == 0 else 'SELL'}")
        print(f"   📦 Volume:     {result['volume']:.2f}")
        print(f"   💰 Entry:      {result['open_price']:.2f}")
        print(f"   🛑 SL:         {result['sl']:.2f}")
        print(f"   🎯 TP:         {result['tp']:.2f}")
        print(f"   💵 Profit:     {result['profit']:.2f} {emoji} {result_type}")
        print(f"   🔮 Magic:      {result['magic']}")
        print(f"   💬 Comment:    {result['comment']}")
        print("=" * 60)
    
    def run(self) -> None:
        """Main worker loop."""
        print("🔄 EXECUTION LISTENER: Worker started")
        
        # Setup ZMQ
        if not self._setup_zmq():
            print("❌ EXECUTION LISTENER: Failed to initialize, exiting")
            return
        
        try:
            while not self.shutdown_event.is_set():
                try:
                    # Receive data (with timeout)
                    raw_data = self.pull_socket.recv()
                    
                    # Parse
                    result = self._parse_trade_result(raw_data)
                    
                    if result:
                        self.message_count += 1
                        
                        # Log to console
                        self._log_trade_result(result)
                        
                        # Forward to feedback queue (non-blocking)
                        self.feedback_queue.put(result, block=False)
                    
                except zmq.Again:
                    # Timeout - no data
                    continue
                
                except queue.Full:
                    # Queue full (shouldn't happen with unlimited queue)
                    print("⚠️ EXECUTION LISTENER: Feedback queue full, dropping message")
                    self.error_count += 1
                
                except Exception as e:
                    print(f"⚠️ EXECUTION LISTENER: Error processing message: {e}")
                    self.error_count += 1
        
        finally:
            # Cleanup
            print(f"\n🛑 EXECUTION LISTENER: Shutting down "
                  f"(Processed: {self.message_count}, Errors: {self.error_count})")
            
            if self.pull_socket:
                self.pull_socket.close()
            if self.context:
                self.context.term()
            
            print("✅ EXECUTION LISTENER: Worker stopped")


def create_execution_listener_threaded(
    feedback_queue: queue.Queue,
    shutdown_event: threading.Event,
    zmq_pull_address: str = "tcp://127.0.0.1:7779"
) -> threading.Thread:
    """
    Factory function to create Execution Listener thread.
    
    Args:
        feedback_queue: Thread-safe queue
        shutdown_event: Shutdown event
        zmq_pull_address: ZMQ address
        
    Returns:
        ExecutionListenerThreaded instance (not started)
    """
    return ExecutionListenerThreaded(
        feedback_queue=feedback_queue,
        shutdown_event=shutdown_event,
        zmq_pull_address=zmq_pull_address
    )
