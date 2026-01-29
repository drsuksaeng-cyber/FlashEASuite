#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Sequence Tracker
Phase 2 Track A: Policy Security (Anti-Replay Attack)

Tracks policy sequence numbers per (license_id, symbol) pair.
Uses SQLite for persistence with in-memory cache for performance.

Prevents replay attacks by ensuring sequence numbers always increment.

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-01-24
"""

import sqlite3
import threading
import time
from pathlib import Path
from typing import Dict, Optional, Tuple


class SequenceTracker:
    """
    Sequence number tracker with SQLite persistence and memory cache.
    
    Tracks last sequence number for each (license_id, symbol) combination.
    Ensures new sequences always increment, preventing replay attacks.
    
    Features:
    - SQLite database for persistence
    - In-memory cache for fast access
    - Thread-safe operations
    - Auto-save every 5 seconds
    - Key format: "LICENSE-ID:SYMBOL"
    
    Database Schema:
        CREATE TABLE sequences (
            key TEXT PRIMARY KEY,      -- "FLASH-2601-TEST-0001:XAUUSD"
            sequence INTEGER NOT NULL, -- Last sequence number
            updated_at INTEGER         -- Timestamp (Unix seconds)
        )
    
    Example:
        >>> tracker = SequenceTracker()
        >>> seq1 = tracker.get_next_sequence("FLASH-2601-TEST-0001", "XAUUSD")
        >>> print(seq1)
        1
        >>> seq2 = tracker.get_next_sequence("FLASH-2601-TEST-0001", "XAUUSD")
        >>> print(seq2)
        2
    """
    
    def __init__(self, db_path: Optional[str] = None):
        """
        Initialize Sequence Tracker.
        
        Args:
            db_path: Path to SQLite database file.
                    Default: "02_Brain/data/sequences.db"
        """
        # Database path
        if db_path is None:
            db_path = Path(__file__).parent.parent.parent / "data" / "sequences.db"
        else:
            db_path = Path(db_path)
        
        # Create data directory if not exists
        db_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.db_path = str(db_path)
        
        # In-memory cache: {key: sequence}
        self._cache: Dict[str, int] = {}
        
        # Thread lock for thread-safety
        self._lock = threading.Lock()
        
        # Last save timestamp
        self._last_save = time.time()
        self._save_interval = 5  # Auto-save every 5 seconds
        
        # Initialize database
        self._init_database()
        
        # Load existing sequences into cache
        self._load_cache()
    
    def _init_database(self) -> None:
        """Create database table if not exists."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS sequences (
                    key TEXT PRIMARY KEY,
                    sequence INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            """)
            conn.commit()
    
    def _load_cache(self) -> None:
        """Load all sequences from database into memory cache."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("SELECT key, sequence FROM sequences")
            for key, sequence in cursor.fetchall():
                self._cache[key] = sequence
    
    def _make_key(self, license_id: str, symbol: str) -> str:
        """
        Create composite key from license_id and symbol.
        
        Args:
            license_id: License ID (e.g., "FLASH-2601-TEST-0001")
            symbol: Symbol name (e.g., "XAUUSD")
            
        Returns:
            str: Composite key "LICENSE:SYMBOL"
        """
        return f"{license_id}:{symbol}"
    
    def get_next_sequence(self, license_id: str, symbol: str) -> int:
        """
        Get next sequence number for (license_id, symbol) pair.
        
        Thread-safe operation that:
        1. Gets current sequence from cache
        2. Increments it
        3. Updates cache
        4. Auto-saves to database if needed
        
        Args:
            license_id: License ID
            symbol: Symbol name
            
        Returns:
            int: Next sequence number (starts at 1)
            
        Example:
            >>> tracker = SequenceTracker()
            >>> seq = tracker.get_next_sequence("FLASH-2601-TEST-0001", "XAUUSD")
            >>> print(seq)
            1
        """
        key = self._make_key(license_id, symbol)
        
        with self._lock:
            # Get current sequence (default to 0)
            current_seq = self._cache.get(key, 0)
            
            # Increment
            next_seq = current_seq + 1
            
            # Update cache
            self._cache[key] = next_seq
            
            # Auto-save if interval exceeded
            if time.time() - self._last_save > self._save_interval:
                self._save_to_database()
            
            return next_seq
    
    def get_current_sequence(self, license_id: str, symbol: str) -> int:
        """
        Get current sequence number without incrementing.
        
        Args:
            license_id: License ID
            symbol: Symbol name
            
        Returns:
            int: Current sequence number (0 if never used)
        """
        key = self._make_key(license_id, symbol)
        
        with self._lock:
            return self._cache.get(key, 0)
    
    def _save_to_database(self) -> None:
        """
        Save all cached sequences to database.
        
        Called automatically every 5 seconds when get_next_sequence() is used.
        Can also be called manually.
        """
        with sqlite3.connect(self.db_path) as conn:
            timestamp = int(time.time())
            
            for key, sequence in self._cache.items():
                conn.execute("""
                    INSERT OR REPLACE INTO sequences (key, sequence, updated_at)
                    VALUES (?, ?, ?)
                """, (key, sequence, timestamp))
            
            conn.commit()
        
        self._last_save = time.time()
    
    def save(self) -> None:
        """
        Manually save all sequences to database.
        
        Use this before shutting down to ensure no data loss.
        
        Example:
            >>> tracker = SequenceTracker()
            >>> # ... generate many sequences ...
            >>> tracker.save()  # Ensure saved before exit
        """
        with self._lock:
            self._save_to_database()
    
    def reset_sequence(self, license_id: str, symbol: str) -> None:
        """
        Reset sequence for a specific (license_id, symbol) pair.
        
        WARNING: Only use for testing! This defeats the security purpose.
        
        Args:
            license_id: License ID
            symbol: Symbol name
        """
        key = self._make_key(license_id, symbol)
        
        with self._lock:
            if key in self._cache:
                del self._cache[key]
            
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("DELETE FROM sequences WHERE key = ?", (key,))
                conn.commit()
    
    def get_stats(self) -> dict:
        """
        Get statistics about tracked sequences.
        
        Returns:
            dict: Statistics including total keys, total sequences, etc.
        """
        with self._lock:
            total_keys = len(self._cache)
            total_sequences = sum(self._cache.values())
            
            # Get per-license stats
            license_counts = {}
            for key, seq in self._cache.items():
                license_id = key.split(':')[0]
                if license_id not in license_counts:
                    license_counts[license_id] = {'keys': 0, 'sequences': 0}
                license_counts[license_id]['keys'] += 1
                license_counts[license_id]['sequences'] += seq
            
            return {
                'total_keys': total_keys,
                'total_sequences': total_sequences,
                'license_counts': license_counts,
                'last_save': time.strftime('%Y-%m-%d %H:%M:%S', 
                                          time.localtime(self._last_save)),
                'db_path': self.db_path
            }


# ========== TESTING ==========

if __name__ == "__main__":
    print("=" * 60)
    print("Sequence Tracker - Test Suite")
    print("=" * 60)
    
    # Use test database
    import tempfile
    test_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
    tracker = SequenceTracker(db_path=test_db.name)
    
    license_id = "FLASH-2601-TEST-0001"
    
    # Test 1: Get sequences for XAUUSD
    print("\n✅ Test 1: Generate sequences for XAUUSD")
    for i in range(5):
        seq = tracker.get_next_sequence(license_id, "XAUUSD")
        print(f"   Sequence {i+1}: {seq}")
    
    # Test 2: Get sequences for EURUSD
    print("\n✅ Test 2: Generate sequences for EURUSD")
    for i in range(3):
        seq = tracker.get_next_sequence(license_id, "EURUSD")
        print(f"   Sequence {i+1}: {seq}")
    
    # Test 3: Check current sequences
    print("\n✅ Test 3: Check current sequences")
    xau_seq = tracker.get_current_sequence(license_id, "XAUUSD")
    eur_seq = tracker.get_current_sequence(license_id, "EURUSD")
    print(f"   XAUUSD current: {xau_seq}")
    print(f"   EURUSD current: {eur_seq}")
    
    # Test 4: Save to database
    print("\n✅ Test 4: Save to database")
    tracker.save()
    print("   Saved to database")
    
    # Test 5: Reload from database
    print("\n✅ Test 5: Reload from database")
    tracker2 = SequenceTracker(db_path=test_db.name)
    xau_seq2 = tracker2.get_current_sequence(license_id, "XAUUSD")
    eur_seq2 = tracker2.get_current_sequence(license_id, "EURUSD")
    print(f"   XAUUSD after reload: {xau_seq2}")
    print(f"   EURUSD after reload: {eur_seq2}")
    print(f"   Persistence: {'✅ PASS' if xau_seq == xau_seq2 else '❌ FAIL'}")
    
    # Test 6: Statistics
    print("\n✅ Test 6: Statistics")
    stats = tracker2.get_stats()
    print(f"   Total keys: {stats['total_keys']}")
    print(f"   Total sequences: {stats['total_sequences']}")
    print(f"   Database: {stats['db_path']}")
    
    # Test 7: Multiple licenses
    print("\n✅ Test 7: Multiple licenses")
    license2 = "FLASH-2601-TEST-0002"
    seq_a = tracker2.get_next_sequence(license2, "XAUUSD")
    seq_b = tracker2.get_next_sequence(license2, "XAUUSD")
    print(f"   License 2 - XAUUSD sequence 1: {seq_a}")
    print(f"   License 2 - XAUUSD sequence 2: {seq_b}")
    print(f"   Separate tracking: {'✅ PASS' if seq_a == 1 and seq_b == 2 else '❌ FAIL'}")
    
    # Cleanup
    import os
    os.unlink(test_db.name)
    
    print("\n" + "=" * 60)
    print("✅ All tests completed!")
    print("=" * 60)
