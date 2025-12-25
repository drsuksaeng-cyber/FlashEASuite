#!/usr/bin/env python3
"""
Position Sizing Manager - Python Implementation
FlashEASuite V2.1 - Risk Management Module

Purpose: Calculate lot sizes based on 1% risk rule
Features:
    - Fixed percentage risk (default 1%)
    - Volatility adjustment (ATR-based)
    - Symbol-specific calculations
    - Lot normalization and validation

Author: Dr. Suksaeng Kukanok
Version: 2.10
"""

import numpy as np
from typing import Optional, Dict, Tuple
from dataclasses import dataclass


@dataclass
class SymbolInfo:
    """Symbol trading properties"""
    min_lot: float = 0.01
    max_lot: float = 100.0
    lot_step: float = 0.01
    point: float = 0.00001  # 5 digits
    digits: int = 5
    tick_value: float = 1.0
    tick_size: float = 0.00001


class PositionSizingManager:
    """
    Position Sizing Manager
    
    Calculate optimal lot sizes based on:
    - Account risk percentage (default 1%)
    - Stop loss distance
    - Market volatility (optional)
    """
    
    def __init__(
        self,
        symbol: str = "EURUSD",
        default_risk_pct: float = 1.0,
        use_volatility: bool = True
    ):
        """
        Initialize Position Sizing Manager
        
        Args:
            symbol: Trading symbol
            default_risk_pct: Default risk percentage (1.0 = 1%)
            use_volatility: Use ATR-based volatility adjustment
        """
        self.symbol = symbol
        self.default_risk_pct = default_risk_pct
        self.use_volatility = use_volatility
        
        # Symbol properties
        self.symbol_info = SymbolInfo()
        
        # ATR for volatility
        self.atr_period = 14
        self.atr_values = []
        
        # Statistics
        self.calculations_count = 0
        self.last_calculated_lot = 0.0
        
        print(f"✅ Position Sizing Manager initialized")
        print(f"   Symbol: {self.symbol}")
        print(f"   Default Risk: {self.default_risk_pct}%")
        print(f"   Volatility Adjustment: {'Enabled' if self.use_volatility else 'Disabled'}")
    
    def set_symbol_info(
        self,
        min_lot: float,
        max_lot: float,
        lot_step: float,
        point: float,
        digits: int,
        tick_value: float = 1.0,
        tick_size: float = 0.00001
    ):
        """
        Set symbol trading properties
        
        Args:
            min_lot: Minimum lot size
            max_lot: Maximum lot size
            lot_step: Lot size step
            point: Point size (smallest price change)
            digits: Price digits
            tick_value: Value per tick
            tick_size: Tick size
        """
        self.symbol_info = SymbolInfo(
            min_lot=min_lot,
            max_lot=max_lot,
            lot_step=lot_step,
            point=point,
            digits=digits,
            tick_value=tick_value,
            tick_size=tick_size
        )
        
        print(f"   Lot Range: {min_lot} - {max_lot} (step: {lot_step})")
    
    def calculate_lot_size(
        self,
        entry_price: float,
        stop_loss: float,
        balance: float,
        risk_pct: Optional[float] = None
    ) -> float:
        """
        Calculate lot size based on risk percentage
        
        Formula: Lot = (Balance * Risk%) / (Stop Distance * Pip Value)
        
        Args:
            entry_price: Entry price
            stop_loss: Stop loss price
            balance: Account balance
            risk_pct: Risk percentage (uses default if None)
        
        Returns:
            Calculated lot size (normalized and validated)
        """
        # Use default if not specified
        if risk_pct is None or risk_pct <= 0:
            risk_pct = self.default_risk_pct
        
        # Validate inputs
        if balance <= 0:
            print(f"❌ Invalid balance: {balance}")
            return 0.0
        
        if entry_price <= 0 or stop_loss <= 0:
            print(f"❌ Invalid prices - Entry: {entry_price} SL: {stop_loss}")
            return 0.0
        
        # Calculate risk amount
        risk_amount = balance * (risk_pct / 100.0)
        
        # Calculate lot size
        lot_size = self._calculate_lot_by_risk_amount(
            risk_amount,
            entry_price,
            stop_loss
        )
        
        # Update statistics
        self.calculations_count += 1
        self.last_calculated_lot = lot_size
        
        return lot_size
    
    def calculate_lot_with_volatility(
        self,
        entry_price: float,
        stop_loss: float,
        balance: float,
        risk_pct: Optional[float] = None
    ) -> float:
        """
        Calculate lot size with volatility adjustment
        
        Args:
            entry_price: Entry price
            stop_loss: Stop loss price
            balance: Account balance
            risk_pct: Risk percentage
        
        Returns:
            Volatility-adjusted lot size
        """
        # Calculate base lot
        base_lot = self.calculate_lot_size(entry_price, stop_loss, balance, risk_pct)
        
        if not self.use_volatility or base_lot <= 0:
            return base_lot
        
        # Get volatility multiplier
        vol_multiplier = self._calculate_volatility_multiplier()
        
        # Adjust lot size
        adjusted_lot = base_lot * vol_multiplier
        
        # Normalize and validate
        adjusted_lot = self.normalize_lot_size(adjusted_lot)
        
        if not self.validate_lot_size(adjusted_lot):
            adjusted_lot = self.clamp_lot_size(adjusted_lot)
        
        print(f"📊 Volatility Adjustment: Base: {base_lot:.2f} × {vol_multiplier:.2f} = {adjusted_lot:.2f}")
        
        return adjusted_lot
    
    def _calculate_lot_by_risk_amount(
        self,
        risk_amount: float,
        entry_price: float,
        stop_loss: float
    ) -> float:
        """
        Calculate lot size by risk amount
        
        Args:
            risk_amount: Amount to risk (in account currency)
            entry_price: Entry price
            stop_loss: Stop loss price
        
        Returns:
            Calculated lot size
        """
        # Validate inputs
        if risk_amount <= 0:
            print(f"❌ Invalid risk amount: {risk_amount}")
            return 0.0
        
        # Calculate stop distance in points
        stop_distance_points = abs(entry_price - stop_loss) / self.symbol_info.point
        
        if stop_distance_points < 1:
            print("❌ Stop loss too close to entry")
            return 0.0
        
        # Get pip value for 1 lot
        pip_value = self._get_pip_value(1.0)
        
        if pip_value <= 0:
            print(f"❌ Invalid pip value: {pip_value}")
            return 0.0
        
        # Calculate stop distance in pips
        pip_size = 10.0 if self.symbol_info.digits in [5, 3] else 1.0
        stop_distance_pips = stop_distance_points / pip_size
        
        # Calculate lot size
        lot_size = risk_amount / (stop_distance_pips * pip_value)
        
        # Normalize and validate
        lot_size = self.normalize_lot_size(lot_size)
        
        if not self.validate_lot_size(lot_size):
            print("⚠️ Calculated lot size invalid, clamping to limits")
            lot_size = self.clamp_lot_size(lot_size)
        
        return lot_size
    
    def _get_pip_value(self, lot_size: float = 1.0) -> float:
        """
        Get pip value for given lot size
        
        Args:
            lot_size: Lot size
        
        Returns:
            Pip value in account currency
        """
        tick_value = self.symbol_info.tick_value
        tick_size = self.symbol_info.tick_size
        point = self.symbol_info.point
        
        if tick_size <= 0 or point <= 0:
            return 0.0
        
        # Calculate pip size
        pip_size = 10.0 * point if self.symbol_info.digits in [5, 3] else point
        
        # Calculate pip value
        pip_value = (tick_value / tick_size) * pip_size * lot_size
        
        return pip_value
    
    def update_atr(self, atr_value: float):
        """
        Update ATR value for volatility calculation
        
        Args:
            atr_value: Current ATR value
        """
        self.atr_values.append(atr_value)
        
        # Keep last 100 values
        if len(self.atr_values) > 100:
            self.atr_values.pop(0)
    
    def _calculate_volatility_multiplier(self) -> float:
        """
        Calculate volatility multiplier based on ATR
        
        Returns:
            Multiplier (0.5 to 1.5)
            - High volatility → smaller multiplier (reduce lot)
            - Low volatility → larger multiplier (increase lot)
        """
        if len(self.atr_values) < 10:
            return 1.0  # Not enough data
        
        current_atr = self.atr_values[-1]
        average_atr = np.mean(self.atr_values)
        
        if average_atr <= 0:
            return 1.0
        
        # Calculate multiplier
        # If current ATR > average: reduce lot (high volatility)
        # If current ATR < average: increase lot (low volatility)
        multiplier = average_atr / current_atr
        
        # Clamp to 0.5 - 1.5 range
        multiplier = max(0.5, min(1.5, multiplier))
        
        return multiplier
    
    def normalize_lot_size(self, lot: float) -> float:
        """
        Normalize lot size to valid step
        
        Args:
            lot: Lot size
        
        Returns:
            Normalized lot size
        """
        if lot <= 0:
            return 0.0
        
        # Round to lot step
        normalized = round(lot / self.symbol_info.lot_step) * self.symbol_info.lot_step
        
        # Ensure precision
        normalized = round(normalized, 2)
        
        return normalized
    
    def validate_lot_size(self, lot: float) -> bool:
        """
        Validate lot size
        
        Args:
            lot: Lot size
        
        Returns:
            True if valid, False otherwise
        """
        if lot < self.symbol_info.min_lot:
            print(f"⚠️ Lot too small: {lot} < {self.symbol_info.min_lot}")
            return False
        
        if lot > self.symbol_info.max_lot:
            print(f"⚠️ Lot too large: {lot} > {self.symbol_info.max_lot}")
            return False
        
        # Check if multiple of step
        remainder = lot % self.symbol_info.lot_step
        if remainder > 0.0001:  # Small tolerance
            print(f"⚠️ Lot not a multiple of step: {lot} (step: {self.symbol_info.lot_step})")
            return False
        
        return True
    
    def clamp_lot_size(self, lot: float) -> float:
        """
        Clamp lot size to valid range
        
        Args:
            lot: Lot size
        
        Returns:
            Clamped lot size
        """
        if lot < self.symbol_info.min_lot:
            return self.symbol_info.min_lot
        
        if lot > self.symbol_info.max_lot:
            return self.symbol_info.max_lot
        
        return self.normalize_lot_size(lot)
    
    def print_info(self):
        """Print manager information"""
        print("=== Position Sizing Manager Info ===")
        print(f"Symbol: {self.symbol}")
        print(f"Default Risk: {self.default_risk_pct}%")
        print(f"Lot Range: {self.symbol_info.min_lot} - {self.symbol_info.max_lot}")
        print(f"Lot Step: {self.symbol_info.lot_step}")
        print(f"Volatility Adjustment: {'Yes' if self.use_volatility else 'No'}")
        print(f"Calculations Made: {self.calculations_count}")
        print(f"Last Calculated Lot: {self.last_calculated_lot:.2f}")
        print("=====================================")


# Example usage
if __name__ == "__main__":
    print("\n" + "="*60)
    print("POSITION SIZING MANAGER - PYTHON TEST")
    print("="*60 + "\n")
    
    # Create manager
    ps = PositionSizingManager(
        symbol="EURUSD",
        default_risk_pct=1.0,
        use_volatility=False
    )
    
    # Set symbol info (EURUSD typical values)
    ps.set_symbol_info(
        min_lot=0.01,
        max_lot=100.0,
        lot_step=0.01,
        point=0.00001,
        digits=5,
        tick_value=1.0,
        tick_size=0.00001
    )
    
    # Test cases
    print("\n--- Test 1: Standard Trade (50 pips) ---")
    balance = 10000.0
    entry = 1.0500
    sl = 1.0450  # 50 pips
    lot = ps.calculate_lot_size(entry, sl, balance)
    print(f"Balance: ${balance:.2f}")
    print(f"Entry: {entry}")
    print(f"SL: {sl} (50 pips)")
    print(f"Calculated Lot: {lot:.2f}")
    print(f"Expected: ~0.20 lots")
    
    print("\n--- Test 2: Tight Stop (20 pips) ---")
    sl = 1.0480  # 20 pips
    lot = ps.calculate_lot_size(entry, sl, balance)
    print(f"Entry: {entry}")
    print(f"SL: {sl} (20 pips)")
    print(f"Calculated Lot: {lot:.2f}")
    print(f"Expected: ~0.50 lots")
    
    print("\n--- Test 3: Wide Stop (100 pips) ---")
    sl = 1.0400  # 100 pips
    lot = ps.calculate_lot_size(entry, sl, balance)
    print(f"Entry: {entry}")
    print(f"SL: {sl} (100 pips)")
    print(f"Calculated Lot: {lot:.2f}")
    print(f"Expected: ~0.10 lots")
    
    print("\n--- Test 4: Different Risk (0.5%) ---")
    sl = 1.0450  # 50 pips
    lot = ps.calculate_lot_size(entry, sl, balance, risk_pct=0.5)
    print(f"Risk: 0.5%")
    print(f"Calculated Lot: {lot:.2f}")
    print(f"Expected: ~0.10 lots (half of 1%)")
    
    # Print summary
    print()
    ps.print_info()
    
    print("\n" + "="*60)
    print("TESTS COMPLETE")
    print("="*60 + "\n")
