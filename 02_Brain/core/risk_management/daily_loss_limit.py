#!/usr/bin/env python3
"""
Daily Loss Limit Manager - Python Implementation
FlashEASuite V2.1 - Risk Management Module

Purpose: Enforce daily loss limit (4% default)
Features:
    - Track daily P&L
    - Enforce configurable limit
    - Auto reset on new day
    - Track daily metrics (wins/losses)

Author: Dr. Suksaeng Kukanok
Version: 2.10
"""

from datetime import datetime, time as dt_time
from typing import Tuple, Dict
from dataclasses import dataclass


@dataclass
class DailyMetrics:
    """Daily trading metrics"""
    pnl: float = 0.0
    wins: float = 0.0
    losses: float = 0.0
    trades: int = 0
    wins_count: int = 0
    losses_count: int = 0


class DailyLossLimit:
    """
    Daily Loss Limit Manager
    
    Enforce daily loss limits to prevent excessive losses
    and protect trading capital.
    """
    
    def __init__(self, daily_limit_pct: float = 4.0):
        """
        Initialize Daily Loss Limit Manager
        
        Args:
            daily_limit_pct: Daily loss limit percentage (4.0 = 4%)
        """
        self.daily_limit_pct = daily_limit_pct
        self.max_daily_loss = 0.0
        
        # Daily tracking
        self.current_day = self._get_day_start()
        self.starting_balance = 0.0
        self.metrics = DailyMetrics()
        
        # State
        self.is_limit_reached = False
        self.limit_reached_time = None
        
        # Statistics
        self.total_limit_hits = 0
        self.last_reset_time = datetime.now()
        
        print(f"✅ Daily Loss Limit initialized")
        print(f"   Limit: {self.daily_limit_pct}%")
    
    def initialize(self, starting_balance: float) -> bool:
        """
        Initialize with starting balance
        
        Args:
            starting_balance: Account balance at start
            
        Returns:
            True if successful
        """
        self.starting_balance = starting_balance
        self.max_daily_loss = starting_balance * (self.daily_limit_pct / 100.0)
        self.current_day = self._get_day_start()
        self.reset_daily()
        
        print(f"   Max Loss: ${self.max_daily_loss:.2f}")
        print(f"   Starting Balance: ${self.starting_balance:.2f}")
        
        return True
    
    def is_daily_limit_reached(self) -> bool:
        """
        Check if daily limit is reached
        
        Returns:
            True if limit reached
        """
        # Check for new day
        if self._is_new_day():
            self.reset_daily()
            return False
        
        return self.is_limit_reached
    
    def check_and_update_limit(self, current_equity: float) -> bool:
        """
        Check and update limit status
        
        Args:
            current_equity: Current account equity
            
        Returns:
            True if limit reached
        """
        # Check for new day
        if self._is_new_day():
            self.reset_daily()
        
        # Already reached?
        if self.is_limit_reached:
            return True
        
        # Calculate current P&L
        current_pnl = current_equity - self.starting_balance
        self.metrics.pnl = current_pnl
        
        # Check if limit reached
        if current_pnl <= -self.max_daily_loss:
            self.is_limit_reached = True
            self.limit_reached_time = datetime.now()
            self.total_limit_hits += 1
            
            print("🚨 DAILY LOSS LIMIT REACHED!")
            print(f"   Daily P&L: ${current_pnl:.2f}")
            print(f"   Limit: ${-self.max_daily_loss:.2f}")
            print(f"   Time: {self.limit_reached_time}")
            print("   Trading STOPPED for today!")
            
            return True
        
        # Check if approaching limit (80%)
        limit_used_pct = (-current_pnl / self.max_daily_loss) * 100.0
        if limit_used_pct >= 80.0:
            print(f"⚠️ WARNING: Daily limit {limit_used_pct:.1f}% used")
            print(f"   P&L: ${current_pnl:.2f} / ${-self.max_daily_loss:.2f}")
        
        return False
    
    def update_daily_pnl(self, trade_pnl: float):
        """
        Update daily P&L with trade result
        
        Args:
            trade_pnl: Trade profit/loss
        """
        # Check for new day
        if self._is_new_day():
            self.reset_daily()
        
        self.metrics.pnl += trade_pnl
        
        if trade_pnl > 0:
            self.metrics.wins += trade_pnl
            self.metrics.wins_count += 1
        else:
            self.metrics.losses += trade_pnl  # Already negative
            self.metrics.losses_count += 1
        
        self.metrics.trades += 1
    
    def update_trade(self, pnl: float, is_win: bool, current_equity: float):
        """
        Update with trade result
        
        Args:
            pnl: Trade profit/loss
            is_win: True if winning trade
            current_equity: Current account equity
        """
        self.update_daily_pnl(pnl)
        self.check_and_update_limit(current_equity)
    
    def get_daily_limit_remaining(self, current_equity: float) -> float:
        """
        Get remaining daily loss limit
        
        Args:
            current_equity: Current account equity
            
        Returns:
            Remaining loss limit amount
        """
        if self._is_new_day():
            self.reset_daily()
        
        current_pnl = current_equity - self.starting_balance
        remaining = self.max_daily_loss + current_pnl  # current_pnl is negative
        
        return max(0, remaining)
    
    def get_daily_pnl_percent(self) -> float:
        """
        Get daily P&L as percentage
        
        Returns:
            P&L percentage
        """
        if self.starting_balance <= 0:
            return 0.0
        
        return (self.metrics.pnl / self.starting_balance) * 100.0
    
    def _is_new_day(self) -> bool:
        """Check if it's a new day"""
        current = self._get_day_start()
        return current > self.current_day
    
    def _get_day_start(self) -> datetime:
        """Get start of current day (00:00:00)"""
        now = datetime.now()
        return datetime.combine(now.date(), dt_time.min)
    
    def reset_daily(self):
        """Reset daily tracking for new day"""
        print("🔄 Daily Loss Limit Reset")
        
        # Print yesterday's summary if there was activity
        if self.metrics.trades > 0:
            self.print_daily_summary()
        
        # Update day
        self.current_day = self._get_day_start()
        
        # Reset metrics
        self.metrics = DailyMetrics()
        self.is_limit_reached = False
        self.limit_reached_time = None
        self.last_reset_time = datetime.now()
        
        print(f"   New Day: {self.current_day.strftime('%Y-%m-%d')}")
        print(f"   Starting Balance: ${self.starting_balance:.2f}")
        print(f"   Max Loss Allowed: ${self.max_daily_loss:.2f}")
    
    def set_daily_limit(self, limit_pct: float):
        """
        Update daily limit percentage
        
        Args:
            limit_pct: New limit percentage
        """
        self.daily_limit_pct = limit_pct
        self.max_daily_loss = self.starting_balance * (limit_pct / 100.0)
        
        print(f"✅ Daily limit updated to {self.daily_limit_pct}%")
        print(f"   Max Loss: ${self.max_daily_loss:.2f}")
    
    def manual_reset(self):
        """Manually reset daily tracking"""
        print("🔄 Manual Reset Requested")
        self.reset_daily()
    
    def print_info(self):
        """Print current status"""
        print("=== Daily Loss Limit Info ===")
        print(f"Limit: {self.daily_limit_pct}%")
        print(f"Max Loss: ${self.max_daily_loss:.2f}")
        print(f"Starting Balance: ${self.starting_balance:.2f}")
        print()
        print(f"Current Day: {self.current_day.strftime('%Y-%m-%d')}")
        print(f"Daily P&L: ${self.metrics.pnl:.2f} ({self.get_daily_pnl_percent():.2f}%)")
        print()
        print(f"Daily Trades: {self.metrics.trades}")
        print(f"Wins: {self.metrics.wins_count} (${self.metrics.wins:.2f})")
        print(f"Losses: {self.metrics.losses_count} (${self.metrics.losses:.2f})")
        print()
        print(f"Limit Reached: {'YES' if self.is_limit_reached else 'NO'}")
        if self.is_limit_reached:
            print(f"Reached At: {self.limit_reached_time}")
        print(f"Total Limit Hits: {self.total_limit_hits}")
        print(f"Last Reset: {self.last_reset_time}")
        print("=================================")
    
    def print_daily_summary(self):
        """Print daily trading summary"""
        print("╔════════════════════════════════════════╗")
        print("║        DAILY SUMMARY                    ║")
        print("╚════════════════════════════════════════╝")
        print(f"Date: {self.current_day.strftime('%Y-%m-%d')}")
        print()
        print(f"Trades: {self.metrics.trades}")
        print(f"  Wins: {self.metrics.wins_count} (${self.metrics.wins:.2f})")
        print(f"  Losses: {self.metrics.losses_count} (${self.metrics.losses:.2f})")
        print()
        print(f"Total P&L: ${self.metrics.pnl:.2f}")
        print(f"P&L %: {self.get_daily_pnl_percent():.2f}%")
        print()
        
        if self.metrics.trades > 0:
            win_rate = (self.metrics.wins_count / self.metrics.trades) * 100.0
            print(f"Win Rate: {win_rate:.1f}%")
            
            avg_win = self.metrics.wins / self.metrics.wins_count if self.metrics.wins_count > 0 else 0
            avg_loss = self.metrics.losses / self.metrics.losses_count if self.metrics.losses_count > 0 else 0
            print(f"Avg Win: ${avg_win:.2f}")
            print(f"Avg Loss: ${avg_loss:.2f}")
        
        print()
        limit_used = (abs(self.metrics.pnl) / self.max_daily_loss) * 100.0 if self.max_daily_loss > 0 else 0
        print(f"Limit Used: {limit_used:.1f}%")
        print(f"Limit Reached: {'YES ⚠️' if self.is_limit_reached else 'NO ✅'}")
        print("════════════════════════════════════════")


# Example usage
if __name__ == "__main__":
    print("\n" + "="*60)
    print("DAILY LOSS LIMIT - PYTHON TEST")
    print("="*60 + "\n")
    
    # Create manager
    dll = DailyLossLimit(daily_limit_pct=4.0)
    dll.initialize(starting_balance=10000.0)
    
    print("\n--- Test 1: Initial State ---")
    print(f"Limit Reached: {dll.is_daily_limit_reached()}")
    print(f"Daily P&L: ${dll.metrics.pnl:.2f}")
    print(f"Daily Trades: {dll.metrics.trades}")
    
    print("\n--- Test 2: Simulate Trades ---")
    current_equity = 10000.0
    
    # Win $100
    current_equity += 100
    dll.update_trade(100.0, True, current_equity)
    print(f"After +$100: P&L = ${dll.metrics.pnl:.2f}")
    
    # Lose $50
    current_equity -= 50
    dll.update_trade(-50.0, False, current_equity)
    print(f"After -$50: P&L = ${dll.metrics.pnl:.2f}")
    
    # Win $75
    current_equity += 75
    dll.update_trade(75.0, True, current_equity)
    print(f"After +$75: P&L = ${dll.metrics.pnl:.2f}")
    
    print(f"\nDaily Metrics:")
    print(f"  Trades: {dll.metrics.trades}")
    print(f"  Wins: {dll.metrics.wins_count} (${dll.metrics.wins:.2f})")
    print(f"  Losses: {dll.metrics.losses_count} (${dll.metrics.losses:.2f})")
    
    print("\n--- Test 3: Approaching Limit (85%) ---")
    dll.manual_reset()
    current_equity = 10000.0
    
    loss_amount = dll.max_daily_loss * 0.85
    current_equity -= loss_amount
    dll.update_daily_pnl(-loss_amount)
    reached = dll.check_and_update_limit(current_equity)
    
    print(f"Loss: ${loss_amount:.2f}")
    print(f"Limit Reached: {reached}")
    print(f"Remaining: ${dll.get_daily_limit_remaining(current_equity):.2f}")
    
    print("\n--- Test 4: Reaching Limit (110%) ---")
    dll.manual_reset()
    current_equity = 10000.0
    
    loss_amount = dll.max_daily_loss * 1.1
    current_equity -= loss_amount
    dll.update_daily_pnl(-loss_amount)
    reached = dll.check_and_update_limit(current_equity)
    
    print(f"Loss: ${loss_amount:.2f}")
    print(f"Limit Reached: {reached}")
    print(f"Remaining: ${dll.get_daily_limit_remaining(current_equity):.2f}")
    
    # Print summary
    print()
    dll.print_info()
    
    print("\n" + "="*60)
    print("TESTS COMPLETE")
    print("="*60 + "\n")
