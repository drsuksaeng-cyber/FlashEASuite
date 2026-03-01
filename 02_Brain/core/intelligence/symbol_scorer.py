#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Symbol Scorer (7-Factor Ranking)
Location: 02_Brain/core/intelligence/symbol_scorer.py

Ranks all tradeable symbols using 7 factors to find best symbols for Spike Strategy.

Author: Dr. Suksaeng Kukanok
Date: 2026-01-30
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Tuple
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)


class SymbolScorer:
    """
    Professional-grade symbol scoring for Spike Strategy.
    
    Uses 7 factors with weighted scoring:
    1. ATR Volatility (25%)
    2. Spike Frequency (20%)
    3. Volume Quality (15%)
    4. Spread Quality (15%)
    5. Trend Strength/ADX (10%)
    6. Liquidity/Tick Volume (10%)
    7. Session Overlap (5%)
    """
    
    # Trading universe - 42 symbols
    UNIVERSE = [
        # Majors (7)
        "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD",
        
        # JPY Crosses (7)
        "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY", "CADJPY", "CHFJPY", "SGDJPY",
        
        # GBP Crosses (6)
        "EURGBP", "GBPAUD", "GBPNZD", "GBPCAD", "GBPCHF", "GBPSGD",
        
        # EUR Crosses (5)
        "EURAUD", "EURCAD", "EURCHF", "EURNZD", "EURSGD",
        
        # Other Crosses (4)
        "AUDNZD", "AUDCAD", "NZDCAD", "CADCHF",
        
        # Metals (2)
        "XAUUSD", "XAGUSD",
        
        # Scandinavian (4)
        "EURSEK", "USDSEK", "EURNOK", "USDNOK",
        
        # Asian (3)
        "USDSGD", "USDHKD", "USDCNH",
        
        # Emerging (4) - Optional
        "USDMXN", "USDZAR", "USDTRY", "USDBRL"
    ]
    
    # Factor weights
    WEIGHTS = {
        'atr_volatility': 0.25,
        'spike_frequency': 0.20,
        'volume_quality': 0.15,
        'spread_quality': 0.15,
        'trend_strength': 0.10,  # ADX
        'liquidity': 0.10,
        'session_overlap': 0.05
    }
    
    def __init__(self, market_data_provider=None):
        """
        Initialize scorer.
        
        Args:
            market_data_provider: Optional data provider for historical data
        """
        self.data_provider = market_data_provider
        self.scores_cache = {}
        self.last_update = None
        
    def calculate_atr(self, symbol: str, data: pd.DataFrame, period: int = 14) -> float:
        """
        Calculate Average True Range.
        
        Args:
            symbol: Symbol name
            data: OHLC DataFrame
            period: ATR period
            
        Returns:
            ATR value in price units
        """
        try:
            high = data['high'].values
            low = data['low'].values
            close = data['close'].values
            
            # True Range calculation
            tr1 = high - low
            tr2 = np.abs(high - np.roll(close, 1))
            tr3 = np.abs(low - np.roll(close, 1))
            
            tr = np.maximum(tr1, np.maximum(tr2, tr3))
            
            # Skip first value (NaN from roll)
            tr = tr[1:]
            
            # Simple moving average
            atr = np.mean(tr[-period:]) if len(tr) >= period else np.mean(tr)
            
            return atr
            
        except Exception as e:
            logger.error(f"Error calculating ATR for {symbol}: {e}")
            return 0.0
    
    def count_spikes(self, symbol: str, data: pd.DataFrame, 
                     days: int = 30, threshold_mult: float = 2.0) -> int:
        """
        Count number of price spikes in recent history.
        
        Args:
            symbol: Symbol name
            data: OHLC DataFrame
            days: Number of days to analyze
            threshold_mult: Spike threshold (multiplier of ATR)
            
        Returns:
            Number of spikes detected
        """
        try:
            atr = self.calculate_atr(symbol, data)
            if atr == 0:
                return 0
            
            # Calculate price changes
            close = data['close'].values
            price_changes = np.abs(np.diff(close))
            
            # Count spikes exceeding threshold
            spike_threshold = threshold_mult * atr
            spikes = np.sum(price_changes > spike_threshold)
            
            return int(spikes)
            
        except Exception as e:
            logger.error(f"Error counting spikes for {symbol}: {e}")
            return 0
    
    def analyze_volume_quality(self, symbol: str, data: pd.DataFrame) -> float:
        """
        Analyze volume spike ratio.
        
        Args:
            symbol: Symbol name
            data: OHLCV DataFrame
            
        Returns:
            Volume spike ratio (0-2+)
        """
        try:
            if 'volume' not in data.columns:
                return 1.0  # Default if no volume data
            
            volume = data['volume'].values
            
            # Calculate average volume
            avg_volume = np.mean(volume)
            if avg_volume == 0:
                return 1.0
            
            # Count volume spikes (>1.5x average)
            volume_spikes = np.sum(volume > 1.5 * avg_volume)
            
            # Ratio of volume spikes to total bars
            ratio = volume_spikes / len(volume)
            
            return ratio
            
        except Exception as e:
            logger.error(f"Error analyzing volume for {symbol}: {e}")
            return 1.0
    
    def get_spread_quality(self, symbol: str, avg_spread_pips: float, atr: float) -> float:
        """
        Calculate spread quality score.
        
        Args:
            symbol: Symbol name
            avg_spread_pips: Average spread in pips
            atr: ATR value
            
        Returns:
            Spread quality (0-1, higher is better)
        """
        try:
            if atr == 0:
                return 0.5
            
            # Spread as percentage of ATR
            spread_pct = avg_spread_pips / (atr * 10000)  # Assuming ATR in price units
            
            # Lower spread is better
            # 0.05 (5%) = perfect, 0.20 (20%) = acceptable, >0.20 = poor
            quality = 1.0 - min(spread_pct / 0.20, 1.0)
            
            return quality
            
        except Exception as e:
            logger.error(f"Error calculating spread quality for {symbol}: {e}")
            return 0.5
    
    def calculate_adx(self, symbol: str, data: pd.DataFrame, period: int = 14) -> float:
        """
        Calculate ADX (Average Directional Index).
        
        Args:
            symbol: Symbol name
            data: OHLC DataFrame
            period: ADX period
            
        Returns:
            ADX value (0-100)
        """
        try:
            high = data['high'].values
            low = data['low'].values
            close = data['close'].values
            
            # Calculate +DM and -DM
            up_move = high[1:] - high[:-1]
            down_move = low[:-1] - low[1:]
            
            plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0)
            minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0)
            
            # Calculate ATR for normalization
            atr = self.calculate_atr(symbol, data, period)
            if atr == 0:
                return 25.0  # Default moderate value
            
            # Calculate smoothed DI+ and DI-
            plus_di = 100 * np.mean(plus_dm[-period:]) / atr
            minus_di = 100 * np.mean(minus_dm[-period:]) / atr
            
            # Calculate DX and ADX
            dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di) if (plus_di + minus_di) > 0 else 0
            
            return dx
            
        except Exception as e:
            logger.error(f"Error calculating ADX for {symbol}: {e}")
            return 25.0
    
    def get_tick_volume(self, symbol: str, data: pd.DataFrame, bars: int = 100) -> int:
        """
        Get average tick volume.
        
        Args:
            symbol: Symbol name
            data: DataFrame with tick_volume
            bars: Number of bars to average
            
        Returns:
            Average tick volume
        """
        try:
            if 'tick_volume' in data.columns:
                tick_vol = data['tick_volume'].values[-bars:]
                return int(np.mean(tick_vol))
            else:
                # Fallback: use regular volume
                volume = data['volume'].values[-bars:]
                return int(np.mean(volume))
                
        except Exception as e:
            logger.error(f"Error getting tick volume for {symbol}: {e}")
            return 5000  # Default
    
    def check_session_overlap(self, symbol: str) -> float:
        """
        Check if symbol benefits from major session overlaps.
        
        Args:
            symbol: Symbol name
            
        Returns:
            Bonus score (0-1)
        """
        # Define session overlaps
        overlap_symbols = {
            'GBPJPY': 1.0,   # London + Tokyo overlap
            'EURJPY': 1.0,
            'AUDJPY': 0.8,   # Tokyo + Sydney
            'NZDJPY': 0.8,
            'GBPAUD': 0.7,   # London + Sydney
            'EURAUD': 0.7,
            'XAUUSD': 0.6,   # Global asset
        }
        
        return overlap_symbols.get(symbol, 0.3)  # Default small bonus
    
    def score_symbol(self, symbol: str, data: Dict) -> Tuple[float, Dict]:
        """
        Calculate comprehensive score for a symbol.
        
        Args:
            symbol: Symbol name
            data: Dictionary with OHLCV data and metadata
                  {
                      'df': pd.DataFrame (OHLCV),
                      'avg_spread_pips': float,
                      'point_value': float
                  }
        
        Returns:
            Tuple of (total_score, factor_breakdown)
        """
        try:
            df = data['df']
            avg_spread = data.get('avg_spread_pips', 2.0)
            
            scores = {}
            
            # Factor 1: ATR Volatility (25%)
            atr = self.calculate_atr(symbol, df)
            atr_pips = (atr / data.get('point_value', 0.0001)) if data.get('point_value') else atr * 10000
            atr_score = min(atr_pips / 200, 1.0)
            scores['atr'] = atr_score * 25
            
            # Factor 2: Spike Frequency (20%)
            spike_count = self.count_spikes(symbol, df, days=30, threshold_mult=2.0)
            spike_score = min(spike_count / 60, 1.0)
            scores['spikes'] = spike_score * 20
            
            # Factor 3: Volume Quality (15%)
            vol_ratio = self.analyze_volume_quality(symbol, df)
            vol_score = min(vol_ratio / 2.0, 1.0)
            scores['volume'] = vol_score * 15
            
            # Factor 4: Spread Quality (15%)
            spread_quality = self.get_spread_quality(symbol, avg_spread, atr)
            scores['spread'] = spread_quality * 15
            
            # Factor 5: Trend Strength (ADX) (10%)
            adx = self.calculate_adx(symbol, df)
            adx_score = min(adx / 40, 1.0)
            scores['adx'] = adx_score * 10
            
            # Factor 6: Liquidity (10%)
            tick_vol = self.get_tick_volume(symbol, df)
            liq_score = min(tick_vol / 10000, 1.0)
            scores['liquidity'] = liq_score * 10
            
            # Factor 7: Session Overlap (5%)
            overlap_bonus = self.check_session_overlap(symbol)
            scores['session'] = overlap_bonus * 5
            
            # Total score
            total = sum(scores.values())
            
            # Factor breakdown for logging
            breakdown = {
                'atr_pips': round(atr_pips, 1),
                'spike_count': spike_count,
                'vol_ratio': round(vol_ratio, 2),
                'spread_quality': round(spread_quality, 2),
                'adx': round(adx, 1),
                'tick_volume': tick_vol,
                'overlap_bonus': round(overlap_bonus, 2),
                'scores': {k: round(v, 2) for k, v in scores.items()}
            }
            
            return total, breakdown
            
        except Exception as e:
            logger.error(f"Error scoring {symbol}: {e}")
            return 0.0, {}
    
    def rank_all_symbols(self, market_data: Dict[str, Dict]) -> List[Dict]:
        """
        Rank all symbols in universe.
        
        Args:
            market_data: Dictionary mapping symbol -> data dict
                        {
                            'GBPJPY': {
                                'df': DataFrame,
                                'avg_spread_pips': 1.5,
                                'point_value': 0.01
                            },
                            ...
                        }
        
        Returns:
            List of ranked symbols with scores:
            [
                {
                    'symbol': 'GBPJPY',
                    'score': 87.5,
                    'rank': 1,
                    'factors': {...}
                },
                ...
            ]
        """
        results = []
        
        for symbol in self.UNIVERSE:
            if symbol not in market_data:
                logger.warning(f"No data for {symbol}, skipping")
                continue
            
            score, breakdown = self.score_symbol(symbol, market_data[symbol])
            
            results.append({
                'symbol': symbol,
                'score': round(score, 2),
                'factors': breakdown
            })
        
        # Sort by score (descending)
        results.sort(key=lambda x: x['score'], reverse=True)
        
        # Add rank
        for i, item in enumerate(results):
            item['rank'] = i + 1
        
        # Cache results
        self.scores_cache = {r['symbol']: r for r in results}
        self.last_update = datetime.now()
        
        return results
    
    def get_top_n(self, n: int = 5, market_data: Dict = None) -> List[Dict]:
        """
        Get top N symbols.
        
        Args:
            n: Number of top symbols to return
            market_data: Market data (if not cached)
        
        Returns:
            List of top N symbols
        """
        if market_data is None and not self.scores_cache:
            raise ValueError("No cached scores and no market_data provided")
        
        if market_data is not None:
            ranked = self.rank_all_symbols(market_data)
        else:
            # Use cached scores
            ranked = sorted(self.scores_cache.values(), 
                          key=lambda x: x['score'], 
                          reverse=True)
        
        return ranked[:n]
    
    def generate_config_params(self, symbol: str) -> Dict:
        """
        Generate optimized parameters for a symbol based on its characteristics.
        
        Args:
            symbol: Symbol name
        
        Returns:
            Dictionary of parameters
        """
        if symbol not in self.scores_cache:
            raise ValueError(f"No cached score for {symbol}")
        
        factors = self.scores_cache[symbol]['factors']
        
        # Base parameters
        params = {
            'atr_period': 14,
            'atr_tp_mult': 0.8,
            'atr_sl_mult': 0.4,
            'roc_period': 10,
            'volume_spike_mult': 1.5,
            'spread_max_atr_pct': 0.20,
            'use_adx_filter': False,
            'adx_minimum': 20,
            'use_zscore_filter': False,
            'zscore_threshold': 2.0
        }
        
        # Adjust based on volatility
        atr_pips = factors.get('atr_pips', 100)
        if atr_pips > 150:  # High volatility (e.g., GBP/JPY)
            params['atr_spike_mult'] = 2.5
            params['roc_threshold'] = 0.6
            params['density_threshold'] = 3.5
            params['max_hold_seconds'] = 600  # 10 min
        elif atr_pips > 100:  # Medium volatility
            params['atr_spike_mult'] = 2.0
            params['roc_threshold'] = 0.5
            params['density_threshold'] = 3.0
            params['max_hold_seconds'] = 750  # 12.5 min
        else:  # Lower volatility
            params['atr_spike_mult'] = 1.8
            params['roc_threshold'] = 0.4
            params['density_threshold'] = 2.5
            params['max_hold_seconds'] = 900  # 15 min
        
        # Tighter spread for high-quality symbols
        spread_quality = factors.get('spread_quality', 0.5)
        if spread_quality > 0.8:
            params['spread_max_atr_pct'] = 0.15
        
        return params


def get_top_symbols(n: int = 5, market_data: Dict = None) -> List[Dict]:
    """
    Convenience function to get top N symbols.
    
    Args:
        n: Number of symbols
        market_data: Market data dictionary
    
    Returns:
        List of top symbols with scores
    """
    scorer = SymbolScorer()
    return scorer.get_top_n(n, market_data)


if __name__ == "__main__":
    # Example usage
    print("Symbol Scorer - Example")
    print("=" * 60)
    
    # Mock data for testing
    import random
    
    mock_data = {}
    for symbol in SymbolScorer.UNIVERSE[:10]:  # Test with first 10
        df = pd.DataFrame({
            'high': np.random.randn(100) * 0.01 + 1.1,
            'low': np.random.randn(100) * 0.01 + 1.0,
            'close': np.random.randn(100) * 0.01 + 1.05,
            'volume': np.random.randint(1000, 5000, 100),
            'tick_volume': np.random.randint(100, 1000, 100)
        })
        
        mock_data[symbol] = {
            'df': df,
            'avg_spread_pips': random.uniform(1.0, 3.0),
            'point_value': 0.0001
        }
    
    scorer = SymbolScorer()
    ranked = scorer.rank_all_symbols(mock_data)
    
    print("\nTop 5 Symbols:")
    for item in ranked[:5]:
        print(f"{item['rank']}. {item['symbol']}: {item['score']:.2f}")
        print(f"   Factors: {item['factors']['scores']}")
