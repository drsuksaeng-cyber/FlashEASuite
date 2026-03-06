#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pre_optimizer.py — Brain Pre-Optimizer (Stage 1 before MT5)
FlashEASuite V2 | 02_Brain/core/optimization/

Purpose:
    Run a fast Python parameter search on historical OHLCV data (via yfinance)
    BEFORE launching the full MT5 Strategy Tester optimization.
    Generates narrow .set files so MT5 validates only the best neighborhood
    (~20-50 passes vs. 400-1200 in the blind grid search).

Supported strategies: S01, S06, S10, S14, S15
S16 is excluded — spike detection relies on tick-level data unavailable in yfinance.

Author: FlashEASuite V2 Dev
"""

from __future__ import annotations

import json
import logging
import math
import random
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from ..intelligence.regime_classifier import (
    Regime,
    RuleBasedClassifier,
    build_features,
)
from ..strategy.adaptive_params import PARAM_BOUNDS, STRATEGY_DEFAULTS

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# yfinance symbol map
# ─────────────────────────────────────────────────────────────────────────────

YFINANCE_MAP: Dict[str, str] = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "EURJPY": "EURJPY=X",
    "GBPJPY": "GBPJPY=X",
    "AUDJPY": "AUDJPY=X",
    "NZDJPY": "NZDJPY=X",
    "GBPAUD": "GBPAUD=X",
    "AUDCAD": "AUDCAD=X",
    "AUDUSD": "AUDUSD=X",
    "NZDUSD": "NZDUSD=X",
    "XAUUSD": "GC=F",
}

# Interval string to TF label map (for .set filenames)
INTERVAL_TF_MAP: Dict[str, str] = {
    "1h": "H1",
    "4h": "H4",
    "1d": "D1",
    "30m": "M30",
    "15m": "M15",
}

# Strategies handled by pre-optimizer
SUPPORTED_STRATEGIES = ["S01", "S06", "S10", "S14", "S15"]

# Parameters to optimize per strategy (Brain internal names)
STRATEGY_OPT_PARAMS: Dict[str, List[str]] = {
    "S01": ["S01_PERIOD", "S01_ENTRY_Z", "S01_STOP_Z"],
    "S06": ["S06_KAMA_PERIOD", "S06_ER_THRESH", "S06_TP_ATR", "S06_SL_ATR"],
    "S10": ["S10_ENTRY_PERIOD", "S10_EXIT_PERIOD", "S10_BREAKOUT_BUF"],
    "S14": ["S14_BB_PERIOD", "S14_KC_ATR_MULT", "S14_SQUEEZE_MIN", "S14_SL_ATR", "S14_TP_ATR"],
    "S15": ["S15_MAX_ORDERS", "S15_CONF_THRESHOLD", "S15_ATR_RATIO"],
}


# ─────────────────────────────────────────────────────────────────────────────
# BrainPreOptimizer
# ─────────────────────────────────────────────────────────────────────────────

class BrainPreOptimizer:
    """
    Fast Python parameter search on historical OHLCV data.

    Workflow:
        1. fetch_ohlcv()         — download via yfinance
        2. classify_regimes()    — rule-based per bar
        3. run_strategy_preopt() — random search, regime-weighted scoring
        4. export_results()      — JSON + narrow .set files
    """

    def __init__(self, seed: int = 42) -> None:
        self._seed = seed
        random.seed(seed)
        np.random.seed(seed)

    # ──────────────────────────────────────────────────────────────────────
    # DATA FETCH
    # ──────────────────────────────────────────────────────────────────────

    def fetch_ohlcv(
        self,
        symbol: str,
        period: str = "2y",
        interval: str = "1h",
    ) -> pd.DataFrame:
        """
        Download OHLCV from yfinance.

        Parameters
        ----------
        symbol   : FlashEASuite symbol name, e.g. "EURUSD"
        period   : yfinance period string, e.g. "2y"
        interval : yfinance interval string, e.g. "1h"

        Returns
        -------
        pd.DataFrame with lowercase columns: open, high, low, close, volume
        plus 'hour' column (UTC hour of bar).
        """
        try:
            import yfinance as yf
        except ImportError:
            raise ImportError(
                "yfinance not installed. Run: pip install yfinance"
            )

        yf_symbol = YFINANCE_MAP.get(symbol.upper(), symbol)
        logger.info("[PreOpt] Downloading %s (%s) | period=%s interval=%s",
                    symbol, yf_symbol, period, interval)

        ticker = yf.Ticker(yf_symbol)
        df = ticker.history(period=period, interval=interval, auto_adjust=True)

        if df.empty:
            raise ValueError(
                f"yfinance returned empty data for {symbol} ({yf_symbol})"
            )

        # Normalise column names
        df.columns = [c.lower() for c in df.columns]
        df = df[["open", "high", "low", "close", "volume"]].copy()
        df.dropna(inplace=True)

        # Add hour for session mapping (needed by build_features)
        if hasattr(df.index, "hour"):
            df["hour"] = df.index.hour
        else:
            df["hour"] = 0

        logger.info("[PreOpt] %s: %d bars downloaded", symbol, len(df))
        return df

    # ──────────────────────────────────────────────────────────────────────
    # REGIME CLASSIFICATION
    # ──────────────────────────────────────────────────────────────────────

    def classify_regimes(self, df: pd.DataFrame) -> pd.Series:
        """
        Classify regime per bar using the rule-based classifier.

        Returns pd.Series of regime name strings ("TRENDING" | "RANGING" | etc.)
        aligned to df's index (after build_features dropna).
        """
        df_in = df.copy()
        # Forex pairs from yfinance often have zero/NaN volume.
        # build_features computes volume_ma_ratio which becomes all-NaN → dropna removes all rows.
        # Fix: use a synthetic constant volume so volume_ma_ratio = 1.0 everywhere.
        if "volume" not in df_in.columns or (df_in["volume"] == 0).all() or df_in["volume"].isna().all():
            df_in["volume"] = 1000.0
        else:
            # Replace zeros with NaN then forward-fill so rolling mean isn't 0
            df_in["volume"] = df_in["volume"].replace(0, float("nan")).ffill().fillna(1000.0)

        feat_df = build_features(df_in)

        clf = RuleBasedClassifier()
        regimes = []
        for _, row in feat_df.iterrows():
            regime = clf.classify(
                adx=row["adx"],
                atr=row["atr"],
                atr_ma=row["atr_ma"],
                bb_width=row["bb_width"],
                bb_width_ma=row["bb_width_ma"],
            )
            regimes.append(regime.name)

        return pd.Series(regimes, index=feat_df.index, name="regime")

    # ──────────────────────────────────────────────────────────────────────
    # SCORING
    # ──────────────────────────────────────────────────────────────────────

    def score_params(self, metrics: dict) -> float:
        """
        Composite score matching OnTester() in Opt EAs.

        Formula: score = (PF × WinRate × sqrt(trades)) / max(max_dd_pct, 1.0)

        Hard filters:
            trades ≥ 15, PF ≥ 1.0, max_dd_pct ≤ 30%
        """
        trades      = metrics.get("trades", 0)
        gross_profit = metrics.get("gross_profit", 0.0)
        gross_loss   = abs(metrics.get("gross_loss", 0.0))
        wins        = metrics.get("wins", 0)
        max_dd      = metrics.get("max_dd", 0.0)
        equity_start = metrics.get("equity_start", 10_000.0)

        if trades < 15:
            return 0.0

        pf = gross_profit / max(gross_loss, 1e-9)
        wr = wins / max(trades, 1)
        max_dd_pct = (max_dd / max(equity_start, 1.0)) * 100.0

        if pf < 1.0 or max_dd_pct > 30.0:
            return 0.0

        return (pf * wr * math.sqrt(trades)) / max(max_dd_pct, 1.0)

    # ──────────────────────────────────────────────────────────────────────
    # STRATEGY SIMULATORS
    # ──────────────────────────────────────────────────────────────────────

    @staticmethod
    def _risk_pnl(
        price: float,
        entry_px: float,
        position: int,
        sl_dist: float,
        equity: float,
        risk_pct: float = 0.01,
    ) -> float:
        """
        Risk-adjusted P&L — instrument-agnostic.

        Sizes each trade so that 1×SL distance = risk_pct of equity.
        Works identically for EURUSD (price≈1.1, ATR≈0.001)
        and XAUUSD (price≈2500, ATR≈30).

        lot_equiv = (equity × risk_pct) / sl_dist
        pnl       = (price − entry) × direction × lot_equiv
        """
        if sl_dist <= 0:
            return 0.0
        lot_equiv = (equity * risk_pct) / sl_dist
        return (price - entry_px) * position * lot_equiv

    def _simulate_s06(self, df: pd.DataFrame, params: dict) -> dict:
        """
        S06 KAMA Trend — Kaufman Adaptive MA bar-by-bar simulation.

        Entry: ER >= ER_Thresh AND close crosses KAMA direction
        Exit : ATR-based SL/TP
        """
        period    = int(params.get("S06_KAMA_PERIOD", 10))
        er_thresh = float(params.get("S06_ER_THRESH", 0.3))
        tp_atr    = float(params.get("S06_TP_ATR", 3.0))
        sl_atr    = float(params.get("S06_SL_ATR", 1.0))
        fast_sc   = 2.0 / (2 + 1)    # fast=2
        slow_sc   = 2.0 / (30 + 1)   # slow=30

        # Trend-following: TP must be >= SL for viable R:R (≥1.0)
        if tp_atr < sl_atr:
            return self._empty_metrics()

        close = df["close"].values
        high  = df["high"].values
        low   = df["low"].values
        n     = len(close)

        if n < period + 30:
            return self._empty_metrics()

        # Compute ATR (EWM)
        atr = self._compute_atr(df, 14)

        # Compute KAMA
        kama = np.empty(n)
        kama[:period] = close[:period]
        for i in range(period, n):
            direction = abs(close[i] - close[i - period])
            volatility = np.sum(np.abs(np.diff(close[i - period: i + 1])))
            er = direction / max(volatility, 1e-10)
            sc = (er * (fast_sc - slow_sc) + slow_sc) ** 2
            kama[i] = kama[i - 1] + sc * (close[i] - kama[i - 1])

        # Simulate trades
        equity       = 10_000.0
        equity_start = equity
        peak_equity  = equity
        max_dd       = 0.0
        trades = wins = 0
        gross_profit = gross_loss = 0.0

        position  = 0   # 0=flat, 1=long, -1=short
        entry_px  = 0.0
        sl_px     = 0.0
        tp_px     = 0.0
        sl_dist   = 0.0

        for i in range(period + 1, n):
            price = close[i]
            cur_atr = atr[i] if atr[i] > 0 else (price * 0.001)

            # Exit check
            if position != 0:
                hit_sl = (position == 1 and price <= sl_px) or \
                         (position == -1 and price >= sl_px)
                hit_tp = (position == 1 and price >= tp_px) or \
                         (position == -1 and price <= tp_px)

                if hit_sl or hit_tp:
                    pnl = self._risk_pnl(price, entry_px, position, sl_dist, equity)
                    equity += pnl
                    trades += 1
                    if pnl > 0:
                        wins += 1
                        gross_profit += pnl
                    else:
                        gross_loss += pnl

                    peak_equity = max(peak_equity, equity)
                    dd = peak_equity - equity
                    max_dd = max(max_dd, dd)
                    position = 0

            # Entry check
            if position == 0:
                er_direction = abs(close[i] - close[i - period])
                er_vol = np.sum(np.abs(np.diff(close[i - period: i + 1])))
                er = er_direction / max(er_vol, 1e-10)

                if er >= er_thresh:
                    if close[i] > kama[i] and close[i - 1] <= kama[i - 1]:
                        position = 1
                        entry_px = price
                        sl_dist  = sl_atr * cur_atr
                        sl_px    = price - sl_dist
                        tp_px    = price + tp_atr * cur_atr
                    elif close[i] < kama[i] and close[i - 1] >= kama[i - 1]:
                        position = -1
                        entry_px = price
                        sl_dist  = sl_atr * cur_atr
                        sl_px    = price + sl_dist
                        tp_px    = price - tp_atr * cur_atr

        return {
            "trades":       trades,
            "wins":         wins,
            "gross_profit": gross_profit,
            "gross_loss":   gross_loss,
            "max_dd":       max_dd,
            "equity_start": equity_start,
        }

    def _simulate_s10(self, df: pd.DataFrame, params: dict) -> dict:
        """
        S10 Turtle — Donchian breakout bar-by-bar simulation.

        Entry: close > Donchian(EntryPeriod) high + buf*ATR (or < low)
        Exit : close < Donchian(ExitPeriod) low (for long), or SL
        """
        entry_period  = int(params.get("S10_ENTRY_PERIOD", 20))
        exit_period   = int(params.get("S10_EXIT_PERIOD", 20))
        breakout_buf  = float(params.get("S10_BREAKOUT_BUF", 0.1))

        close = df["close"].values
        high  = df["high"].values
        low   = df["low"].values
        n     = len(close)
        warmup = max(entry_period, exit_period) + 5

        if n < warmup + 30:
            return self._empty_metrics()

        atr = self._compute_atr(df, 14)

        equity       = 10_000.0
        equity_start = equity
        peak_equity  = equity
        max_dd       = 0.0
        trades = wins = 0
        gross_profit = gross_loss = 0.0

        position  = 0
        entry_px  = 0.0
        sl_px     = 0.0
        sl_dist   = 0.0

        for i in range(warmup, n):
            price   = close[i]
            cur_atr = atr[i] if atr[i] > 0 else (price * 0.001)

            # Exit check
            if position != 0:
                exit_high = np.max(high[i - exit_period: i])
                exit_low  = np.min(low[i - exit_period: i])
                hit_sl    = (position == 1  and price <= sl_px) or \
                            (position == -1 and price >= sl_px)
                hit_exit  = (position == 1  and price < exit_low) or \
                            (position == -1 and price > exit_high)

                if hit_sl or hit_exit:
                    pnl = self._risk_pnl(price, entry_px, position, sl_dist, equity)
                    equity += pnl
                    trades += 1
                    if pnl > 0:
                        wins += 1
                        gross_profit += pnl
                    else:
                        gross_loss += pnl

                    peak_equity = max(peak_equity, equity)
                    max_dd = max(max_dd, peak_equity - equity)
                    position = 0

            # Entry check
            if position == 0:
                entry_high = np.max(high[i - entry_period: i])
                entry_low  = np.min(low[i - entry_period: i])

                if price > entry_high + breakout_buf * cur_atr:
                    position = 1
                    entry_px = price
                    sl_dist  = 2.0 * cur_atr
                    sl_px    = price - sl_dist
                elif price < entry_low - breakout_buf * cur_atr:
                    position = -1
                    entry_px = price
                    sl_dist  = 2.0 * cur_atr
                    sl_px    = price + sl_dist

        return {
            "trades":       trades,
            "wins":         wins,
            "gross_profit": gross_profit,
            "gross_loss":   gross_loss,
            "max_dd":       max_dd,
            "equity_start": equity_start,
        }

    def _simulate_s01(self, df: pd.DataFrame, params: dict) -> dict:
        """
        S01 StatArb — single-symbol Z-score mean reversion.

        In standalone mode, uses rolling Z-score of close vs its own mean.
        Entry long: Z < -EntryZ | Entry short: Z > +EntryZ
        Exit: Z crosses 0 or |Z| > StopZ
        """
        period  = int(params.get("S01_PERIOD", 20))
        entry_z = float(params.get("S01_ENTRY_Z", 2.0))
        stop_z  = float(params.get("S01_STOP_Z", 3.0))

        # StopZ must be LARGER than EntryZ (StopZ = adverse move emergency exit).
        # If stop_z <= entry_z, the emergency-stop fires immediately after every
        # entry → 0 completed trades in MT5.  Discard these params entirely.
        if stop_z <= entry_z:
            return self._empty_metrics()

        close = df["close"].values
        n     = len(close)

        if n < period + 30:
            return self._empty_metrics()

        atr = self._compute_atr(df, 14)

        equity       = 10_000.0
        equity_start = equity
        peak_equity  = equity
        max_dd       = 0.0
        trades = wins = 0
        gross_profit = gross_loss = 0.0

        position  = 0
        entry_px  = 0.0
        entry_atr = 0.0  # ATR at entry, used as proxy SL distance for sizing

        for i in range(period, n):
            window = close[i - period: i + 1]
            mu  = np.mean(window)
            sig = np.std(window)
            if sig < 1e-10:
                continue
            z = (close[i] - mu) / sig
            price   = close[i]
            cur_atr = atr[i] if atr[i] > 0 else (price * 0.001)

            # Exit check — matches S01_StatArb.mqh MT5 logic exactly:
            #   Long  exit: z >= 0 (revert to mean) OR z < -stop_z (adverse crash)
            #   Short exit: z <= 0 (revert to mean) OR z > +stop_z (adverse rally)
            if position != 0:
                hit_stop  = (position == 1  and z < -stop_z) or \
                            (position == -1 and z > stop_z)
                hit_exit  = (position == 1  and z >= 0) or \
                            (position == -1 and z <= 0)

                if hit_stop or hit_exit:
                    # Use 1×ATR-at-entry as proxy SL distance for sizing
                    pnl = self._risk_pnl(price, entry_px, position, entry_atr, equity)
                    equity += pnl
                    trades += 1
                    if pnl > 0:
                        wins += 1
                        gross_profit += pnl
                    else:
                        gross_loss += pnl

                    peak_equity = max(peak_equity, equity)
                    max_dd = max(max_dd, peak_equity - equity)
                    position = 0

            # Entry check
            if position == 0:
                if z < -entry_z:
                    position = 1
                    entry_px  = price
                    entry_atr = cur_atr
                elif z > entry_z:
                    position = -1
                    entry_px  = price
                    entry_atr = cur_atr

        return {
            "trades":       trades,
            "wins":         wins,
            "gross_profit": gross_profit,
            "gross_loss":   gross_loss,
            "max_dd":       max_dd,
            "equity_start": equity_start,
        }

    def _simulate_s14(self, df: pd.DataFrame, params: dict) -> dict:
        """
        S14 BBSqueeze — Bollinger Band / Keltner Channel squeeze breakout.

        Squeeze: BB width < KC width for squeeze_min consecutive bars.
        Entry on momentum (close direction after squeeze).
        Exit: ATR SL/TP.
        """
        bb_period   = int(params.get("S14_BB_PERIOD", 20))
        bb_dev      = float(params.get("S14_BB_DEV", 2.0))
        kc_atr_mult = float(params.get("S14_KC_ATR_MULT", 1.5))
        squeeze_min = int(params.get("S14_SQUEEZE_MIN", 6))
        sl_atr      = float(params.get("S14_SL_ATR", 2.0))
        tp_atr      = float(params.get("S14_TP_ATR", 3.0))

        # Squeeze_Min > 8 bars on H1 rarely occurs → zero trades in MT5
        if squeeze_min > 8:
            return self._empty_metrics()
        # Breakout strategy: TP must be >= SL for viable R:R
        if tp_atr < sl_atr:
            return self._empty_metrics()

        close = df["close"].values
        n     = len(close)
        warmup = bb_period + squeeze_min + 10

        if n < warmup + 30:
            return self._empty_metrics()

        atr = self._compute_atr(df, 14)

        equity       = 10_000.0
        equity_start = equity
        peak_equity  = equity
        max_dd       = 0.0
        trades = wins = 0
        gross_profit = gross_loss = 0.0

        position    = 0
        entry_px    = 0.0
        sl_px       = 0.0
        tp_px       = 0.0
        sl_dist     = 0.0
        squeeze_cnt = 0

        for i in range(bb_period, n):
            price   = close[i]
            cur_atr = atr[i] if atr[i] > 0 else (price * 0.001)

            window = close[i - bb_period: i + 1]
            bb_mid = np.mean(window)
            bb_std = np.std(window)
            bb_width = 2 * bb_dev * bb_std

            kc_width = 2 * kc_atr_mult * cur_atr

            in_squeeze = bb_width < kc_width
            if in_squeeze:
                squeeze_cnt += 1
            else:
                # Squeeze just released — entry signal
                if squeeze_cnt >= squeeze_min and position == 0:
                    # Direction: close relative to mid
                    if price > bb_mid:
                        position = 1
                        entry_px = price
                        sl_dist  = sl_atr * cur_atr
                        sl_px    = price - sl_dist
                        tp_px    = price + tp_atr * cur_atr
                    else:
                        position = -1
                        entry_px = price
                        sl_dist  = sl_atr * cur_atr
                        sl_px    = price + sl_dist
                        tp_px    = price - tp_atr * cur_atr
                squeeze_cnt = 0

            # Exit check
            if position != 0:
                hit_sl = (position == 1  and price <= sl_px) or \
                         (position == -1 and price >= sl_px)
                hit_tp = (position == 1  and price >= tp_px) or \
                         (position == -1 and price <= tp_px)

                if hit_sl or hit_tp:
                    pnl = self._risk_pnl(price, entry_px, position, sl_dist, equity)
                    equity += pnl
                    trades += 1
                    if pnl > 0:
                        wins += 1
                        gross_profit += pnl
                    else:
                        gross_loss += pnl

                    peak_equity = max(peak_equity, equity)
                    max_dd = max(max_dd, peak_equity - equity)
                    position = 0

        return {
            "trades":       trades,
            "wins":         wins,
            "gross_profit": gross_profit,
            "gross_loss":   gross_loss,
            "max_dd":       max_dd,
            "equity_start": equity_start,
        }

    def _simulate_s15(self, df: pd.DataFrame, params: dict) -> dict:
        """
        S15 Grid — Ranging quality score (simplified, not full grid execution).

        Grid works best when: ATR is low relative to range, market is oscillating.
        Returns quality_score (0-1) based on ranging characteristics.
        """
        atr_ratio     = float(params.get("S15_ATR_RATIO", 0.8))
        max_orders    = int(params.get("S15_MAX_ORDERS", 10))
        conf_threshold = float(params.get("S15_CONF_THRESHOLD", 0.65))

        close = df["close"].values
        n     = len(close)

        if n < 50:
            return {"quality_score": 0.0, "is_grid": True}

        atr = self._compute_atr(df, 14)

        # Ranging quality metrics:
        # 1. Low ATR/price ratio (low volatility relative to price)
        atr_pct = np.nanmean(atr[-100:] / np.abs(close[-100:] + 1e-10))

        # 2. Mean-reversion frequency (zero-cross of de-trended close)
        window = min(50, n // 4)
        detrended = close[-window:] - np.mean(close[-window:])
        zero_crosses = np.sum(np.diff(np.sign(detrended)) != 0)
        reversion_score = min(1.0, zero_crosses / max(window // 2, 1))

        # 3. ATR ratio check (user param)
        atr_score = 1.0 - min(1.0, atr_pct / max(atr_ratio, 0.001))

        quality_score = (reversion_score * 0.6 + atr_score * 0.4)
        quality_score = max(0.0, min(1.0, quality_score))

        # Hard filter: need decent ranging quality for grid to work
        if quality_score < 0.3:
            return {"quality_score": 0.0, "is_grid": True}

        # Translate quality score into pseudo-trade metrics
        # so score_params() can be used uniformly
        equity_ref     = 10_000.0
        pseudo_trades  = int(quality_score * max_orders * 5)
        pseudo_wins    = int(pseudo_trades * (0.5 + quality_score * 0.3))
        pseudo_profit  = quality_score * 1000.0
        pseudo_loss    = (1.0 - quality_score) * 500.0
        pseudo_dd      = (1.0 - quality_score) * equity_ref * 0.05

        return {
            "trades":        max(pseudo_trades, 0),
            "wins":          max(pseudo_wins, 0),
            "gross_profit":  pseudo_profit,
            "gross_loss":    -pseudo_loss,
            "max_dd":        pseudo_dd,
            "equity_start":  equity_ref,
            "quality_score": quality_score,
            "is_grid":       True,
        }

    # ──────────────────────────────────────────────────────────────────────
    # RANDOM SEARCH
    # ──────────────────────────────────────────────────────────────────────

    def run_strategy_preopt(
        self,
        strategy_id: str,
        symbol: str,
        n_trials: int = 300,
        period: str = "2y",
        interval: str = "1h",
    ) -> dict:
        """
        Random-search n_trials parameter combinations for one (strategy, symbol) pair.

        Returns
        -------
        {
            "strategy":            str,
            "symbol":              str,
            "interval":            str,
            "overall_best":        {params, score},
            "per_regime_best":     {regime_name: {params, score}},
            "score_history":       [float],
            "regime_distribution": {regime_name: float},
            "n_bars":              int,
        }
        """
        if strategy_id not in SUPPORTED_STRATEGIES:
            raise ValueError(f"Strategy {strategy_id} not supported by pre-optimizer.")

        logger.info("[PreOpt] %s %s - %d trials | interval=%s",
                    strategy_id, symbol, n_trials, interval)

        # Download & feature-build once
        df_raw = self.fetch_ohlcv(symbol, period=period, interval=interval)
        regime_series = self.classify_regimes(df_raw)

        # Re-index df_raw to regime_series index (build_features drops NaN rows)
        df = df_raw.loc[regime_series.index].copy()
        df["regime"] = regime_series

        regime_counts = df["regime"].value_counts()
        total         = len(df)
        regime_dist   = {r: float(c / total) for r, c in regime_counts.items()}

        logger.info("[PreOpt] %s %s | regime_dist=%s | bars=%d",
                    strategy_id, symbol, regime_dist, total)

        simulate_fn = self._get_simulate_fn(strategy_id)
        opt_params  = STRATEGY_OPT_PARAMS[strategy_id]

        overall_best_score = -1.0
        overall_best_params: dict = {}
        per_regime_best: Dict[str, dict] = {}
        score_history: List[float] = []

        for trial_idx in range(n_trials):
            # Sample params
            params = self._sample_params(strategy_id, opt_params)

            # Overall score: simulate on full df
            metrics = simulate_fn(df, params)
            score   = self._score_metrics(metrics)
            score_history.append(score)

            if score > overall_best_score:
                overall_best_score  = score
                overall_best_params = dict(params)

            # Per-regime score: simulate on regime-filtered slices
            for regime_name, weight in regime_dist.items():
                if weight < 0.05:
                    continue  # skip negligible regimes
                df_regime = df[df["regime"] == regime_name]
                if len(df_regime) < 50:
                    continue
                metrics_r = simulate_fn(df_regime.reset_index(drop=True), params)
                score_r   = self._score_metrics(metrics_r)
                weighted_r = score_r * weight

                prev = per_regime_best.get(regime_name, {})
                if weighted_r > prev.get("weighted_score", -1.0):
                    per_regime_best[regime_name] = {
                        "params":         dict(params),
                        "score":          score_r,
                        "weighted_score": weighted_r,
                    }

            if (trial_idx + 1) % 50 == 0:
                logger.info("[PreOpt] %s %s | trial %d/%d | best=%.4f",
                            strategy_id, symbol, trial_idx + 1, n_trials,
                            overall_best_score)

        logger.info(
            "[PreOpt] %s %s DONE | best_score=%.4f | params=%s",
            strategy_id, symbol, overall_best_score, overall_best_params
        )

        return {
            "strategy":            strategy_id,
            "symbol":              symbol,
            "interval":            interval,
            "overall_best":        {"params": overall_best_params, "score": overall_best_score},
            "per_regime_best":     per_regime_best,
            "score_history":       score_history,
            "regime_distribution": regime_dist,
            "n_bars":              total,
        }

    # ──────────────────────────────────────────────────────────────────────
    # RUN ALL
    # ──────────────────────────────────────────────────────────────────────

    def run_all(
        self,
        strategies: Optional[List[str]] = None,
        symbols:    Optional[List[str]] = None,
        n_trials:   int = 300,
        period:     str = "2y",
        interval:   str = "1h",
    ) -> dict:
        """
        Run pre-optimization for all (strategy, symbol) combinations.

        Returns nested dict: results[strategy_id][symbol] = run_strategy_preopt()
        """
        if strategies is None:
            strategies = ["S01", "S06", "S10", "S14", "S15"]
        if symbols is None:
            symbols = ["EURUSD", "XAUUSD", "GBPUSD"]

        results: dict = {}

        for strategy_id in strategies:
            results[strategy_id] = {}
            for symbol in symbols:
                try:
                    result = self.run_strategy_preopt(
                        strategy_id=strategy_id,
                        symbol=symbol,
                        n_trials=n_trials,
                        period=period,
                        interval=interval,
                    )
                    results[strategy_id][symbol] = result
                except Exception as exc:
                    logger.error(
                        "[PreOpt] FAILED %s %s: %s", strategy_id, symbol, exc
                    )
                    results[strategy_id][symbol] = {"error": str(exc)}

        return results

    # ──────────────────────────────────────────────────────────────────────
    # EXPORT
    # ──────────────────────────────────────────────────────────────────────

    def export_results(
        self,
        results: dict,
        output_dir: Optional[str] = None,
        profiles_path: Optional[str] = None,
    ) -> List[str]:
        """
        Save results to JSON and generate .set files.

        Parameters
        ----------
        results       : dict from run_all()
        output_dir    : folder for preopt_results.json (defaults to this file's dir)
        profiles_path : MT5 Profiles\\Tester path for .set files

        Returns
        -------
        List of generated .set file paths.
        """
        # Determine output dir
        if output_dir is None:
            output_dir = str(Path(__file__).parent)
        out_path = Path(output_dir)
        out_path.mkdir(parents=True, exist_ok=True)

        # Save JSON
        json_path = out_path / "preopt_results.json"
        # Convert score_history (large list) to summary for readability
        json_results = {}
        for strat, sym_dict in results.items():
            json_results[strat] = {}
            for sym, r in sym_dict.items():
                if "error" in r:
                    json_results[strat][sym] = r
                    continue
                r_copy = dict(r)
                history = r_copy.pop("score_history", [])
                r_copy["score_stats"] = {
                    "max":  max(history) if history else 0,
                    "mean": sum(history) / max(len(history), 1),
                    "n_nonzero": sum(1 for s in history if s > 0),
                }
                json_results[strat][sym] = r_copy

        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(json_results, f, indent=2, default=str)
        logger.info("[PreOpt] Results saved -> %s", json_path)

        # Generate .set files
        generated_paths: List[str] = []

        if profiles_path is None:
            # Auto-detect MT5 Profiles/Tester path
            profiles_path = self._find_mt5_profiles()
        elif profiles_path:
            # Strip any newlines/spaces that may appear from terminal line-wrapping
            profiles_path = profiles_path.strip().replace("\n", "").replace("\r", "")

        from .setfile_generator import SetFileGenerator
        gen = SetFileGenerator()

        for strategy_id, sym_dict in results.items():
            for symbol, r in sym_dict.items():
                if "error" in r or not r.get("overall_best", {}).get("params"):
                    continue
                try:
                    best_params = r["overall_best"]["params"]
                    tf_label    = INTERVAL_TF_MAP.get(r.get("interval", "1h"), "H1")
                    content     = gen.generate(strategy_id, best_params, symbol, tf_label)
                    if profiles_path:
                        path = gen.write(strategy_id, content, profiles_path, symbol, tf_label)
                        generated_paths.append(path)
                        logger.info("[PreOpt] .set written -> %s", path)
                    else:
                        logger.warning("[PreOpt] profiles_path not found; .set not written for %s %s",
                                       strategy_id, symbol)
                except Exception as exc:
                    logger.error("[PreOpt] .set generation failed %s %s: %s",
                                 strategy_id, symbol, exc)

        return generated_paths

    # ──────────────────────────────────────────────────────────────────────
    # PRIVATE HELPERS
    # ──────────────────────────────────────────────────────────────────────

    def _get_simulate_fn(self, strategy_id: str):
        return {
            "S01": self._simulate_s01,
            "S06": self._simulate_s06,
            "S10": self._simulate_s10,
            "S14": self._simulate_s14,
            "S15": self._simulate_s15,
        }[strategy_id]

    def _score_metrics(self, metrics: dict) -> float:
        """Unified scorer: handles grid (quality_score) and regular trade metrics."""
        if metrics.get("is_grid"):
            # S15: use quality_score directly, scale to comparable range
            return metrics.get("quality_score", 0.0) * 5.0
        return self.score_params(metrics)

    def _sample_params(self, strategy_id: str, opt_params: List[str]) -> dict:
        """
        Sample parameters randomly within PARAM_BOUNDS.
        Respects step sizes by rounding to nearest step.
        Non-optimized params get their STRATEGY_DEFAULTS values.
        """
        defaults = dict(STRATEGY_DEFAULTS.get(strategy_id, {}))
        # Map Brain default keys to PARAM_BOUNDS keys (they match directly)
        params = {}

        # Start with all defaults
        for key, val in defaults.items():
            params[key] = val

        # Randomise only the optimised ones
        for key in opt_params:
            bounds = PARAM_BOUNDS.get(key)
            if bounds is None:
                continue
            lo, hi, step = bounds
            n_steps = max(1, round((hi - lo) / step))
            chosen_step = random.randint(0, n_steps)
            value = lo + chosen_step * step
            value = max(lo, min(hi, value))

            # Round to step precision
            if isinstance(step, int) or step == int(step):
                params[key] = int(round(value))
            else:
                decimals = max(0, -int(math.floor(math.log10(abs(step)))))
                params[key] = round(value, decimals)

        return params

    @staticmethod
    def _compute_atr(df: pd.DataFrame, period: int = 14) -> np.ndarray:
        """Compute ATR via EWM on True Range."""
        high  = df["high"].values
        low   = df["low"].values
        close = df["close"].values
        n     = len(close)

        tr = np.empty(n)
        tr[0] = high[0] - low[0]
        for i in range(1, n):
            tr[i] = max(
                high[i] - low[i],
                abs(high[i] - close[i - 1]),
                abs(low[i]  - close[i - 1]),
            )

        # EWM
        alpha = 2.0 / (period + 1)
        atr   = np.empty(n)
        atr[0] = tr[0]
        for i in range(1, n):
            atr[i] = alpha * tr[i] + (1 - alpha) * atr[i - 1]
        return atr

    @staticmethod
    def _empty_metrics() -> dict:
        return {
            "trades":       0,
            "wins":         0,
            "gross_profit": 0.0,
            "gross_loss":   0.0,
            "max_dd":       0.0,
            "equity_start": 10_000.0,
        }

    @staticmethod
    def _find_mt5_profiles() -> Optional[str]:
        """
        Locate the MT5 Profiles/Tester directory by walking UP from this file.

        pre_optimizer.py lives inside:
            ...Terminal/{ID}/MQL5/Experts/FlashEASuite_V2/02_Brain/core/optimization/
        Walking up until we find a directory that contains MQL5/Experts guarantees
        we land in the CORRECT terminal (B2C22A9C...), not the first one found.
        """
        this_file = Path(__file__).resolve()
        for parent in this_file.parents:
            mql5 = parent / "MQL5"
            if mql5.exists() and (mql5 / "Experts").exists():
                tester = mql5 / "Profiles" / "Tester"
                tester.mkdir(parents=True, exist_ok=True)
                return str(tester)
        return None
