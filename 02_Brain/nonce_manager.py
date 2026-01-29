#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Nonce Manager
Prevents replay attacks by tracking used nonces

Author: AI Assistant for Dr. Suksaeng
Date: January 27, 2026
Version: 1.0
"""

import uuid
import time
from typing import Set, Dict
from datetime import datetime, timedelta
import threading


class NonceManager:
    """
    Manages nonces (number used once) to prevent replay attacks.
    
    Features:
    - Generate unique UUID v4 nonces
    - Track used nonces
    - Detect duplicate nonces
    - Auto-cleanup old nonces (>1 hour)
    """
    
    def __init__(self, cleanup_interval: int = 3600):
        """
        Initialize Nonce Manager.
        
        Args:
            cleanup_interval: Seconds before nonce expires (default 1 hour)
        """
        self.used_nonces: Dict[str, datetime] = {}  # {nonce: timestamp}
        self.cleanup_interval = cleanup_interval
        self.lock = threading.Lock()  # Thread-safe operations
        
        print("✅ NonceManager initialized")
        print(f"   Cleanup interval: {cleanup_interval} seconds")
    
    def generate_nonce(self) -> str:
        """
        Generate a unique nonce (UUID v4).
        
        Returns:
            str: UUID v4 string (e.g., "550e8400-e29b-41d4-a716-446655440000")
        """
        nonce = str(uuid.uuid4())
        return nonce
    
    def is_nonce_used(self, nonce: str) -> bool:
        """
        Check if nonce has already been used.
        
        Args:
            nonce: Nonce string to check
            
        Returns:
            bool: True if nonce already used, False otherwise
        """
        with self.lock:
            # Cleanup old nonces first
            self._cleanup_old_nonces()
            
            return nonce in self.used_nonces
    
    def store_nonce(self, nonce: str) -> bool:
        """
        Store a nonce as used.
        
        Args:
            nonce: Nonce string to store
            
        Returns:
            bool: True if stored successfully, False if already exists
        """
        with self.lock:
            # Check if already used
            if nonce in self.used_nonces:
                return False
            
            # Store with current timestamp
            self.used_nonces[nonce] = datetime.now()
            return True
    
    def _cleanup_old_nonces(self):
        """
        Remove nonces older than cleanup_interval.
        
        This is called automatically by is_nonce_used() and store_nonce().
        """
        cutoff_time = datetime.now() - timedelta(seconds=self.cleanup_interval)
        
        # Find expired nonces
        expired_nonces = [
            nonce for nonce, timestamp in self.used_nonces.items()
            if timestamp < cutoff_time
        ]
        
        # Remove expired nonces
        for nonce in expired_nonces:
            del self.used_nonces[nonce]
        
        if expired_nonces:
            print(f"🧹 Cleaned up {len(expired_nonces)} expired nonces")
    
    def cleanup_old_nonces(self):
        """
        Public method to manually trigger cleanup.
        """
        with self.lock:
            self._cleanup_old_nonces()
    
    def get_nonce_count(self) -> int:
        """
        Get current number of stored nonces.
        
        Returns:
            int: Number of active nonces
        """
        with self.lock:
            return len(self.used_nonces)
    
    def clear_all(self):
        """
        Clear all stored nonces.
        
        WARNING: Use only for testing or emergency reset.
        """
        with self.lock:
            self.used_nonces.clear()
            print("⚠️ All nonces cleared")
    
    def get_stats(self) -> dict:
        """
        Get statistics about nonce usage.
        
        Returns:
            dict: Statistics including count, oldest nonce age, etc.
        """
        with self.lock:
            if not self.used_nonces:
                return {
                    "total_nonces": 0,
                    "oldest_age_seconds": 0,
                    "newest_age_seconds": 0
                }
            
            now = datetime.now()
            timestamps = list(self.used_nonces.values())
            oldest = min(timestamps)
            newest = max(timestamps)
            
            return {
                "total_nonces": len(self.used_nonces),
                "oldest_age_seconds": (now - oldest).total_seconds(),
                "newest_age_seconds": (now - newest).total_seconds()
            }


# Example usage
if __name__ == "__main__":
    print("=" * 60)
    print("NonceManager Test")
    print("=" * 60)
    
    # Create manager
    manager = NonceManager(cleanup_interval=5)  # 5 seconds for testing
    
    # Test 1: Generate nonces
    print("\n📝 Test 1: Generate Nonces")
    nonce1 = manager.generate_nonce()
    nonce2 = manager.generate_nonce()
    print(f"Nonce 1: {nonce1}")
    print(f"Nonce 2: {nonce2}")
    print(f"✅ Nonces are unique: {nonce1 != nonce2}")
    
    # Test 2: Store nonces
    print("\n📝 Test 2: Store Nonces")
    result1 = manager.store_nonce(nonce1)
    result2 = manager.store_nonce(nonce2)
    print(f"Store nonce1: {result1} ✅")
    print(f"Store nonce2: {result2} ✅")
    print(f"Total nonces: {manager.get_nonce_count()}")
    
    # Test 3: Detect duplicate
    print("\n📝 Test 3: Detect Duplicate")
    is_used = manager.is_nonce_used(nonce1)
    print(f"Is nonce1 used? {is_used} ✅")
    
    result3 = manager.store_nonce(nonce1)
    print(f"Try to store nonce1 again: {result3} ❌ (should be False)")
    
    # Test 4: Cleanup
    print("\n📝 Test 4: Auto Cleanup")
    print(f"Waiting 6 seconds for cleanup...")
    time.sleep(6)
    
    # Try to check old nonce (should trigger cleanup)
    manager.is_nonce_used(nonce1)
    print(f"Nonces after cleanup: {manager.get_nonce_count()}")
    
    # Test 5: Stats
    print("\n📝 Test 5: Statistics")
    nonce3 = manager.generate_nonce()
    manager.store_nonce(nonce3)
    
    stats = manager.get_stats()
    print(f"Stats: {stats}")
    
    print("\n" + "=" * 60)
    print("✅ All Tests Passed!")
    print("=" * 60)
