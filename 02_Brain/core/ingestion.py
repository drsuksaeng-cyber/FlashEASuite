#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Ingestion Worker (Threading Version)
Receives tick data from MT5 Feeder via ZMQ

Threading-safe version for Windows compatibility.
"""

import zmq
import msgpack
import threading
import queue
import time
from typing import Dict, Any


class IngestionWorkerThreaded(threading.Thread):
    """
    Ingestion Worker using Threading (Windows-safe).
    
    Receives tick data from MT5 Feeder (Program A) via ZMQ SUB socket
    and forwards to Strategy Engine via thread-safe queue.
    """
    
    def __init__(
        self,
        ingestion_queue: queue.Queue,
        shutdown_event: threading.Event,
        zmq_sub_address: str = "tcp://127.0.0.1:7777"
    ):
        """
        Initialize Ingestion Worker.
        
        Args:
            ingestion_queue: Thread-safe queue to forward data
            shutdown_event: Event to signal shutdown
            zmq_sub_address: ZMQ address to subscribe to
        """
        super().__init__(name="IngestionWorker")
        self.ingestion_queue = ingestion_queue
        self.shutdown_event = shutdown_event
        self.zmq_sub_address = zmq_sub_address
        
        # ZMQ socket (will be created in run())
        self.context = None
        self.sub_socket = None
        
        # Statistics
        self.message_count = 0
        self.error_count = 0
    
    def _setup_zmq(self) -> bool:
        """
        Setup ZMQ SUB socket.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            self.context = zmq.Context()
            self.sub_socket = self.context.socket(zmq.SUB)
            self.sub_socket.bind(self.zmq_sub_address)  # ✅ Changed to bind()
            self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "")  # Subscribe all
            self.sub_socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1 second timeout
            
            print(f"📥 INGESTION: Bound to {self.zmq_sub_address}")
            return True
            
        except Exception as e:
            print(f"❌ INGESTION: Failed to setup ZMQ: {e}")
            return False
    
    def _parse_tick_data(self, raw_data: bytes) -> Dict[str, Any]:
        """
        Parse MessagePack tick data.
        
        Args:
            raw_data: Raw binary data
            
        Returns:
            Parsed tick dictionary
        """
        try:
            data = msgpack.unpackb(raw_data, raw=False)
            
            # Validate format
            if not isinstance(data, list) or len(data) < 5:
                raise ValueError("Invalid data format")
            
            # Extract fields
            tick = {
                'msg_type': data[0],      # 1 = TICK_DATA
                'timestamp': data[1],      # milliseconds
                'symbol': data[2],         # "XAUUSD"
                'bid': data[3],           # bid price
                'ask': data[4],           # ask price
            }
            
            return tick
            
        except Exception as e:
            print(f"⚠️ INGESTION: Parse error: {e}")
            raise
    
    def run(self) -> None:
        """Main worker loop."""
        print("🔄 INGESTION: Worker started")
        
        # Setup ZMQ
        if not self._setup_zmq():
            print("❌ INGESTION: Failed to initialize, exiting")
            return
        
        try:
            while not self.shutdown_event.is_set():
                try:
                    # Receive data (with timeout)
                    raw_data = self.sub_socket.recv()
                    
                    # Parse
                    tick = self._parse_tick_data(raw_data)
                    
                    # Forward to queue (non-blocking)
                    self.ingestion_queue.put(tick, block=False)
                    
                    self.message_count += 1
                    
                    # Log every 100 messages
                    if self.message_count % 100 == 0:
                        print(f"📊 INGESTION: Processed {self.message_count} ticks "
                              f"(Queue size: {self.ingestion_queue.qsize()})")
                    
                except zmq.Again:
                    # Timeout - no data
                    continue
                
                except queue.Full:
                    # Queue full (shouldn't happen with unlimited queue)
                    print("⚠️ INGESTION: Queue full, dropping message")
                    self.error_count += 1
                
                except Exception as e:
                    print(f"⚠️ INGESTION: Error processing message: {e}")
                    self.error_count += 1
        
        finally:
            # Cleanup
            print(f"\n🛑 INGESTION: Shutting down "
                  f"(Processed: {self.message_count}, Errors: {self.error_count})")
            
            if self.sub_socket:
                self.sub_socket.close()
            if self.context:
                self.context.term()
            
            print("✅ INGESTION: Worker stopped")


def create_ingestion_worker_threaded(
    ingestion_queue: queue.Queue,
    shutdown_event: threading.Event,
    zmq_sub_address: str = "tcp://127.0.0.1:7777"
) -> threading.Thread:
    """
    Factory function to create Ingestion Worker thread.
    
    Args:
        ingestion_queue: Thread-safe queue
        shutdown_event: Shutdown event
        zmq_sub_address: ZMQ address
        
    Returns:
        IngestionWorkerThreaded instance (not started)
    """
    return IngestionWorkerThreaded(
        ingestion_queue=ingestion_queue,
        shutdown_event=shutdown_event,
        zmq_sub_address=zmq_sub_address
    )
