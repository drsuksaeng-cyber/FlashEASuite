#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Sequence Tracker
Tracks policy sequence numbers per client to prevent out-of-order attacks

Author: AI Assistant for Dr. Suksaeng
Date: January 27, 2026
Version: 1.0
"""

import json
import os
from typing import Dict
import threading
from pathlib import Path


class SequenceTracker:
    """
    Tracks sequence numbers for each client to ensure policy ordering.
    
    Features:
    - Track last sequence per client_id
    - Generate next sequence number
    - Validate sequence ordering
    - Persist to file for restart recovery
    """
    
    def __init__(self, storage_file: str = "sequences.json"):
        """
        Initialize Sequence Tracker.
        
        Args:
            storage_file: Path to JSON file for persistence
        """
        self.sequences: Dict[str, int] = {}  # {client_id: last_sequence}
        self.storage_file = storage_file
        self.lock = threading.Lock()  # Thread-safe operations
        
        # Load existing sequences
        self.load_from_file()
        
        print("✅ SequenceTracker initialized")
        print(f"   Storage file: {storage_file}")
        print(f"   Loaded {len(self.sequences)} clients")
    
    def get_next_sequence(self, client_id: str) -> int:
        """
        Get next sequence number for a client.
        
        Args:
            client_id: Client identifier (e.g., license_id or HWID)
            
        Returns:
            int: Next sequence number
        """
        with self.lock:
            # Get current sequence (0 if new client)
            current = self.sequences.get(client_id, 0)
            
            # Increment
            next_seq = current + 1
            
            # Update
            self.sequences[client_id] = next_seq
            
            # Persist
            self._save_to_file()
            
            return next_seq
    
    def validate_sequence(self, client_id: str, sequence: int) -> bool:
        """
        Validate if sequence number is valid (must be greater than last).
        
        Args:
            client_id: Client identifier
            sequence: Sequence number to validate
            
        Returns:
            bool: True if valid (sequence > last_sequence), False otherwise
        """
        with self.lock:
            last_seq = self.sequences.get(client_id, 0)
            
            # First policy (sequence 1) is always valid
            if last_seq == 0 and sequence == 1:
                return True
            
            # Sequence must be greater than last
            return sequence > last_seq
    
    def update_sequence(self, client_id: str, sequence: int):
        """
        Update last sequence number after validation.
        
        Args:
            client_id: Client identifier
            sequence: New sequence number
        """
        with self.lock:
            self.sequences[client_id] = sequence
            self._save_to_file()
    
    def get_last_sequence(self, client_id: str) -> int:
        """
        Get last sequence number for a client.
        
        Args:
            client_id: Client identifier
            
        Returns:
            int: Last sequence number (0 if new client)
        """
        with self.lock:
            return self.sequences.get(client_id, 0)
    
    def _save_to_file(self):
        """
        Save sequences to file (internal method).
        
        Note: Called automatically, no need to call manually.
        """
        try:
            # Create directory if not exists
            storage_path = Path(self.storage_file)
            storage_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write to file
            with open(self.storage_file, 'w') as f:
                json.dump(self.sequences, f, indent=2, sort_keys=True)
                
        except Exception as e:
            print(f"⚠️ Failed to save sequences: {e}")
    
    def save_to_file(self):
        """
        Public method to manually save sequences.
        """
        with self.lock:
            self._save_to_file()
    
    def load_from_file(self):
        """
        Load sequences from file.
        
        Called automatically on init.
        """
        if not os.path.exists(self.storage_file):
            print(f"   No existing sequence file found (will create new)")
            return
        
        try:
            with open(self.storage_file, 'r') as f:
                data = json.load(f)
                
                # Convert string keys back to dict
                self.sequences = {str(k): int(v) for k, v in data.items()}
                
            print(f"   Loaded sequences for {len(self.sequences)} clients")
            
        except Exception as e:
            print(f"⚠️ Failed to load sequences: {e}")
            self.sequences = {}
    
    def get_all_sequences(self) -> Dict[str, int]:
        """
        Get all sequences (for debugging/monitoring).
        
        Returns:
            dict: Copy of all sequences
        """
        with self.lock:
            return self.sequences.copy()
    
    def reset_client(self, client_id: str):
        """
        Reset sequence for a specific client.
        
        Args:
            client_id: Client to reset
        """
        with self.lock:
            if client_id in self.sequences:
                del self.sequences[client_id]
                self._save_to_file()
                print(f"⚠️ Reset sequence for client: {client_id}")
    
    def reset_all(self):
        """
        Reset all sequences.
        
        WARNING: Use only for testing or emergency.
        """
        with self.lock:
            self.sequences.clear()
            self._save_to_file()
            print("⚠️ All sequences reset")
    
    def get_stats(self) -> dict:
        """
        Get statistics about sequences.
        
        Returns:
            dict: Statistics
        """
        with self.lock:
            if not self.sequences:
                return {
                    "total_clients": 0,
                    "total_policies": 0,
                    "highest_sequence": 0
                }
            
            return {
                "total_clients": len(self.sequences),
                "total_policies": sum(self.sequences.values()),
                "highest_sequence": max(self.sequences.values()),
                "average_sequence": sum(self.sequences.values()) / len(self.sequences)
            }


# Example usage
if __name__ == "__main__":
    print("=" * 60)
    print("SequenceTracker Test")
    print("=" * 60)
    
    # Create tracker
    tracker = SequenceTracker(storage_file="test_sequences.json")
    
    client1 = "client-abc-123"
    client2 = "client-xyz-789"
    
    # Test 1: Get next sequences
    print("\n📝 Test 1: Generate Sequences")
    seq1 = tracker.get_next_sequence(client1)
    seq2 = tracker.get_next_sequence(client1)
    seq3 = tracker.get_next_sequence(client1)
    print(f"Client 1 sequences: {seq1}, {seq2}, {seq3}")
    print(f"✅ Sequences increment: {seq1 == 1 and seq2 == 2 and seq3 == 3}")
    
    seq4 = tracker.get_next_sequence(client2)
    print(f"Client 2 first sequence: {seq4}")
    print(f"✅ New client starts at 1: {seq4 == 1}")
    
    # Test 2: Validate sequences
    print("\n📝 Test 2: Validate Sequences")
    valid1 = tracker.validate_sequence(client1, 4)  # Should be valid (3 + 1)
    valid2 = tracker.validate_sequence(client1, 2)  # Should be invalid (< 3)
    print(f"Validate seq 4 for client1: {valid1} ✅ (should be True)")
    print(f"Validate seq 2 for client1: {valid2} ❌ (should be False)")
    
    # Test 3: Update sequence
    print("\n📝 Test 3: Update Sequence")
    tracker.update_sequence(client1, 4)
    last = tracker.get_last_sequence(client1)
    print(f"Updated client1 to seq 4")
    print(f"Last sequence: {last} ✅ (should be 4)")
    
    # Test 4: Persistence
    print("\n📝 Test 4: File Persistence")
    print(f"Saving to file: test_sequences.json")
    tracker.save_to_file()
    
    # Load in new tracker
    tracker2 = SequenceTracker(storage_file="test_sequences.json")
    last2 = tracker2.get_last_sequence(client1)
    print(f"Loaded last sequence: {last2} ✅ (should be 4)")
    
    # Test 5: Stats
    print("\n📝 Test 5: Statistics")
    stats = tracker.get_stats()
    print(f"Stats: {stats}")
    
    # Cleanup
    print("\n🧹 Cleaning up test file...")
    if os.path.exists("test_sequences.json"):
        os.remove("test_sequences.json")
    
    print("\n" + "=" * 60)
    print("✅ All Tests Passed!")
    print("=" * 60)
