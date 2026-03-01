#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Main Orchestrator (Threading Version for Windows)
Program B: The Brain - Safe Mode

Threading version with correct imports from core/ modules.

Author: Dr. Suksaeng Kukanok
Version: 2.0.2 (Fixed imports for renamed files)
Date: 2025-12-04
"""

import threading
import queue
import signal
import sys
import time
from typing import Optional

# Import from core/ modules (after files are renamed)
from core.ingestion import create_ingestion_worker_threaded
from core.strategy import create_strategy_engine_threaded
from core.execution_listener import create_execution_listener_threaded


class FlashEABrain:
    """
    Main orchestrator for FlashEA Brain using Threading (Windows-Safe).
    
    Manages 3 worker threads:
    1. Ingestion Worker - Receives tick data from Feeder
    2. Strategy Engine - Generates trading signals
    3. Execution Listener - Receives trade results (Feedback Loop)
    """
    
    def __init__(self):
        """Initialize the Brain with threading components."""
        # Threading events for shutdown
        self.shutdown_event = threading.Event()
        
        # Thread-safe queues (no maxsize limit to prevent deadlock)
        self.ingestion_queue = queue.Queue()      # Unlimited
        self.signal_queue = queue.Queue()         # Unlimited
        self.feedback_queue = queue.Queue()       # Unlimited
        
        # Worker threads
        self.threads = []
        
        print("=" * 80)
        print("FlashEASuite V2 - Program B (The Brain) 🧠")
        print("High-Frequency Hybrid Trading System")
        print("WITH FEEDBACK LOOP 🔄")
        print("MODE: Threading (Windows Safe Mode)")
        print("VERSION: 2.0.2 (Core Module Imports)")
        print("=" * 80)
    
    def _setup_signal_handlers(self) -> None:
        """Setup signal handlers for graceful shutdown."""
        def signal_handler(signum, frame):
            print("\n\n⚠️ Shutdown signal received. Stopping gracefully...")
            self.shutdown_event.set()
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    def _start_workers(self) -> bool:
        """
        Start all worker threads.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            print("\n🚀 Starting FlashEA Brain with Feedback Loop...")
            print("Configuration:")
            print("  - ZMQ Feeder (Tick Data):    tcp://127.0.0.1:7777")
            print("  - ZMQ Execution (Policy):    tcp://127.0.0.1:7778")
            print("  - ZMQ Feedback (Results):    tcp://127.0.0.1:7779")
            print("\nQueue Implementation: Thread-safe queue.Queue (unlimited)")
            print("\nStarting worker threads...")
            
            # 1. Ingestion Worker (Receives tick data)
            ingestion_thread = create_ingestion_worker_threaded(
                ingestion_queue=self.ingestion_queue,
                shutdown_event=self.shutdown_event,
                zmq_sub_address="tcp://127.0.0.1:7777"
            )
            ingestion_thread.daemon = True  # Daemon thread
            ingestion_thread.start()
            self.threads.append(('IngestionWorker', ingestion_thread))
            print(f"✅ Ingestion Worker started (Thread: {ingestion_thread.name})")
            
            # Small delay to ensure socket binding
            time.sleep(0.5)
            
            # 2. Strategy Engine (Generates signals + Processes feedback)
            strategy_thread = create_strategy_engine_threaded(
                ingestion_queue=self.ingestion_queue,
                signal_queue=self.signal_queue,
                feedback_queue=self.feedback_queue,
                shutdown_event=self.shutdown_event,
                zmq_pub_address="tcp://127.0.0.1:7778"
            )
            strategy_thread.daemon = True
            strategy_thread.start()
            self.threads.append(('StrategyEngine', strategy_thread))
            print(f"✅ Strategy Engine started (Thread: {strategy_thread.name})")
            
            time.sleep(0.5)
            
            # 3. Execution Listener (Receives trade results)
            execution_thread = create_execution_listener_threaded(
                feedback_queue=self.feedback_queue,
                shutdown_event=self.shutdown_event,
                zmq_pull_address="tcp://127.0.0.1:7779"
            )
            execution_thread.daemon = True
            execution_thread.start()
            self.threads.append(('ExecutionListener', execution_thread))
            print(f"✅ Execution Listener started (Thread: {execution_thread.name})")
            
            print(f"\n🚀 All workers started successfully ({len(self.threads)} threads)")
            print("=" * 80)
            print("🎯 System is running with FEEDBACK LOOP enabled!")
            print("   📥 Receiving tick data from Feeder")
            print("   🧠 Generating trading signals")
            print("   📤 Sending policies to Trader")
            print("   🔄 Receiving trade results (Feedback Loop)")
            print("=" * 80)
            print("Press Ctrl+C to stop.")
            print()
            
            return True
            
        except Exception as e:
            print(f"❌ Error starting workers: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def _monitor_threads(self) -> None:
        """Monitor thread health."""
        while not self.shutdown_event.is_set():
            time.sleep(5)  # Check every 5 seconds
            
            # Check if any thread died
            for name, thread in self.threads:
                if not thread.is_alive():
                    print(f"\n⚠️ WARNING: Thread {name} is not alive!")
                    # Don't restart - just notify
            
            # Check queue sizes (for monitoring only)
            ing_size = self.ingestion_queue.qsize()
            sig_size = self.signal_queue.qsize()
            fb_size = self.feedback_queue.qsize()
            
            if ing_size > 100 or sig_size > 100 or fb_size > 100:
                print(f"⚠️ Queue sizes: Ingestion={ing_size}, "
                      f"Signal={sig_size}, Feedback={fb_size}")
    
    def _cleanup_resources(self) -> None:
        """Clean up resources before shutdown."""
        print("\n🧹 Cleaning up resources...")
        
        # Set shutdown event (threads should exit their loops)
        self.shutdown_event.set()
        
        # Wait for threads to finish (with timeout)
        print("⏳ Waiting for threads to finish...")
        for name, thread in self.threads:
            thread.join(timeout=3.0)
            if thread.is_alive():
                print(f"⚠️ Thread {name} did not stop gracefully")
            else:
                print(f"✅ Thread {name} stopped")
        
        # Clear queues
        for q in [self.ingestion_queue, self.signal_queue, self.feedback_queue]:
            while not q.empty():
                try:
                    q.get_nowait()
                except queue.Empty:
                    break
        
        print("✅ Cleanup complete")
    
    def run(self) -> None:
        """Main run loop."""
        try:
            # Setup signal handlers
            self._setup_signal_handlers()
            
            # Start workers
            if not self._start_workers():
                print("❌ Failed to start workers. Exiting.")
                return
            
            # Monitor threads
            self._monitor_threads()
            
        except KeyboardInterrupt:
            print("\n\n⚠️ Keyboard interrupt received")
        
        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")
            import traceback
            traceback.print_exc()
        
        finally:
            # Cleanup
            self._cleanup_resources()
            print("\n👋 FlashEA Brain stopped")


def main():
    """Main entry point."""
    brain = FlashEABrain()
    brain.run()


if __name__ == "__main__":
    # This guard is CRITICAL for Windows multiprocessing/threading
    main()
