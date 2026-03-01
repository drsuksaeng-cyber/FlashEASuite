#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Feedback Processing Module
Handles trade results and risk adaptation
"""

import time
from typing import Dict, Any


class FeedbackProcessor:
    """
    Feedback processing module for adapting to trade results.
    
    Manages:
    - Win/loss tracking
    - Risk adjustment
    - Cooldown system
    - Performance statistics
    """
    
    def __init__(self):
        """Initialize Feedback Processor."""
        # Feedback state variables
        self.consecutive_wins = 0
        self.consecutive_losses = 0
        self.total_trades = 0
        self.total_wins = 0
        self.total_losses = 0
        self.total_profit = 0.0
        
        # Cooldown system
        self.cooldown_until = 0  # timestamp
        self._is_in_cooldown = False
        self.LOSS_COOLDOWN_SECONDS = 30.0
        self.EMERGENCY_COOLDOWN_SECONDS = 300.0
        self.MAX_CONSECUTIVE_LOSSES = 3
        
        # Risk management
        self.risk_multiplier = 1.0  # Range: 0.5 - 1.5
        self.MIN_RISK_MULTIPLIER = 0.5
        self.MAX_RISK_MULTIPLIER = 1.5
    
    def process_feedback(self, feedback: Dict[str, Any]) -> None:
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
            self._process_win(ticket, symbol, profit)
            
        elif is_loss:
            # LOSS Logic
            self._process_loss(ticket, symbol, profit)
        
        else:
            # Breakeven
            print(f"⚪ FEEDBACK: BREAKEVEN | Ticket {ticket} | Profit: {profit:.2f}")
        
        # Display statistics
        self._print_statistics()
    
    def _process_win(self, ticket: int, symbol: str, profit: float) -> None:
        """Process winning trade."""
        self.total_wins += 1
        self.consecutive_wins += 1
        self.consecutive_losses = 0  # Reset
        self.total_profit += profit
        
        # Increase risk (max 1.5x)
        self.risk_multiplier *= 1.1
        if self.risk_multiplier > self.MAX_RISK_MULTIPLIER:
            self.risk_multiplier = self.MAX_RISK_MULTIPLIER
        
        # Cancel cooldown if active
        if self._is_in_cooldown:
            self._is_in_cooldown = False
            self.cooldown_until = 0
            print("✅ COOLDOWN CANCELED - Win during cooldown!")
        
        # Hot streak detection
        if self.consecutive_wins >= 3:
            print(f"🔥 HOT STREAK! {self.consecutive_wins} consecutive wins!")
        
        print(f"💚 FEEDBACK: WIN | Ticket {ticket} | Profit: +{profit:.2f}")
    
    def _process_loss(self, ticket: int, symbol: str, profit: float) -> None:
        """Process losing trade."""
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
            self._is_in_cooldown = True
            print(f"🚨 EMERGENCY COOLDOWN! {self.consecutive_losses} consecutive losses!")
            print(f"🛑 Trading paused for {self.EMERGENCY_COOLDOWN_SECONDS:.0f} seconds")
        else:
            # Normal cooldown
            self.cooldown_until = current_time + self.LOSS_COOLDOWN_SECONDS
            self._is_in_cooldown = True
            print(f"⚠️ COOLDOWN ACTIVATED for {self.LOSS_COOLDOWN_SECONDS:.0f} seconds")
        
        print(f"💔 FEEDBACK: LOSS | Ticket {ticket} | Loss: {profit:.2f}")
    
    def _print_statistics(self) -> None:
        """Print feedback statistics."""
        win_rate = (self.total_wins / self.total_trades * 100) if self.total_trades > 0 else 0
        print(f"📊 Stats: {self.total_wins}W / {self.total_losses}L / {self.total_profit:+.2f} Total "
              f"| Win Rate: {win_rate:.1f}% | Risk: {self.risk_multiplier:.2f}x")
    
    def is_in_cooldown(self) -> bool:
        """
        Check if currently in cooldown.
        
        Returns:
            True if in cooldown (should not trade), False otherwise
        """
        if not self._is_in_cooldown:
            return False
        
        current_time = time.time()
        
        # Check if cooldown expired
        if current_time >= self.cooldown_until:
            self._is_in_cooldown = False
            print("✅ COOLDOWN ENDED - Trading resumed")
            return False
        
        # Still in cooldown
        remaining = self.cooldown_until - current_time
        
        # Print every 10 seconds
        if int(remaining) % 10 == 0:
            print(f"⏳ COOLDOWN: {remaining:.0f}s remaining...")
        
        return True
    
    def calculate_confidence(self) -> float:
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
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get current statistics.
        
        Returns:
            Dictionary with all statistics
        """
        return {
            'total_trades': self.total_trades,
            'total_wins': self.total_wins,
            'total_losses': self.total_losses,
            'total_profit': self.total_profit,
            'consecutive_wins': self.consecutive_wins,
            'consecutive_losses': self.consecutive_losses,
            'risk_multiplier': self.risk_multiplier,
            'is_in_cooldown': self._is_in_cooldown,
            'cooldown_until': self.cooldown_until
        }
    
    def get_risk_multiplier(self) -> float:
        """Get current risk multiplier."""
        return self.risk_multiplier
