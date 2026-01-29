#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Nonce Manager
Phase 2 Track A: Policy Security

Handles one-time nonce generation for anti-replay protection.
"""

import uuid
from typing import Set


class NonceManager:
    """
    Manages nonce generation for policy messages.
    
    Nonce = Number Used Once (UUID v4)
    Purpose: Prevent replay attacks
    """
    
    def __init__(self):
        """Initialize Nonce Manager."""
        self._generated_nonces: Set[str] = set()
    
    def generate_nonce(self) -> str:
        """
        Generate a unique UUID v4 nonce.
        
        Returns:
            str: UUID v4 string (e.g., "550e8400-e29b-41d4-a716-446655440000")
            
        Example:
            >>> nonce_mgr = NonceManager()
            >>> nonce = nonce_mgr.generate_nonce()
            >>> len(nonce)
            36
            >>> nonce.count('-')
            4
        """
        nonce = str(uuid.uuid4())
        
        # Track generated nonces (for testing uniqueness)
        self._generated_nonces.add(nonce)
        
        return nonce
    
    def get_generated_count(self) -> int:
        """
        Get count of generated nonces (for testing).
        
        Returns:
            int: Number of unique nonces generated
        """
        return len(self._generated_nonces)
    
    def clear_history(self) -> None:
        """Clear generated nonces history (for testing only)."""
        self._generated_nonces.clear()


# =============================================================================
# Public API
# =============================================================================

def generate_nonce() -> str:
    """
    Generate a nonce without creating manager instance.
    
    Returns:
        str: UUID v4 nonce
        
    Example:
        >>> from core.policy import generate_nonce
        >>> nonce = generate_nonce()
        >>> len(nonce)
        36
    """
    return str(uuid.uuid4())


def validate_nonce_format(nonce: str) -> bool:
    """
    Validate nonce format (UUID v4).
    
    Args:
        nonce: Nonce string to validate
        
    Returns:
        bool: True if valid UUID v4 format
        
    Example:
        >>> validate_nonce_format('550e8400-e29b-41d4-a716-446655440000')
        True
        >>> validate_nonce_format('invalid-nonce')
        False
    """
    try:
        uuid_obj = uuid.UUID(nonce, version=4)
        return str(uuid_obj) == nonce
    except (ValueError, AttributeError):
        return False


# =============================================================================
# Change Log
# =============================================================================
# Version 1.0 (2026-01-24):
# - Initial implementation
# - UUID v4 generation
# - Simple and fast (<0.1ms per nonce)
