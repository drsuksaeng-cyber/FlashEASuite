"""
regime_classifier.py — 3-Layer Market Regime Classifier
FlashEASuite V2 | 02_Brain/core/intelligence/

Layer 1: Rule-based   (fast, shared with MQL5 standalone)
Layer 2: Random Forest (accuracy > 80%, confidence threshold 0.75)
Layer 3: HMM           (regime shift prediction, threshold 0.80)

Combined decision:
    if RF_confidence > 0.75  → use RF regime
    elif HMM_shift_prob > 0.80 → use HMM predicted regime
    else                       → use Rule-based regime

Author: FlashEASuite V2 Dev | P4-1
"""

from __future__ import annotations

import logging
import pickle
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# Constants / Enums
# ──────────────────────────────────────────────────────────────────────────────

class Regime(IntEnum):
    """Market regime labels (must match MQL5 ENUM_MARKET_REGIME)"""
    RANGING   = 0
    TRENDING  = 1
    VOLATILE  = 2
    SQUEEZE   = 3

    def __str__(self) -> str:          # noqa: D105
        return self.name

REGIME_NAMES: Dict[int, str] = {r.value: r.name for r in Regime}

# Hysteresis thresholds
ADX_ENTER_TRENDING = 27.0   # enter TRENDING above this
ADX_EXIT_TRENDING  = 23.0   # exit  TRENDING below this
ADX_RANGING_MAX    = 20.0   # RANGING: ADX < 20

# Volatility / Squeeze windows
ATR_MA_PERIOD   = 14        # period for MA(ATR)
BB_MA_PERIOD    = 20        # period for MA(BB_Width)
ATR_MULT        = 1.5       # VOLATILE: ATR > 1.5 × MA(ATR)
BB_MULT         = 0.5       # SQUEEZE:  BB_Width < 0.5 × MA(BB_Width)

# ML thresholds
RF_CONFIDENCE_THRESHOLD  = 0.75
HMM_SHIFT_PROB_THRESHOLD = 0.80

# ──────────────────────────────────────────────────────────────────────────────
# Data class for classifier output
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class RegimeResult:
    """Result returned by RegimeClassifier.classify()"""
    regime:           Regime     # final decided regime
    source:           str        # "RF" | "HMM" | "RULE"
    rf_regime:        Optional[Regime]  = None
    rf_confidence:    float             = 0.0
    hmm_shift_prob:   float             = 0.0
    hmm_next_regime:  Optional[Regime]  = None
    rule_regime:      Optional[Regime]  = None
    # decision trace
    reasoning:        str               = ""

    def as_dict(self) -> dict:
        return {
            "regime":         self.regime.name,
            "source":         self.source,
            "rf_regime":      self.rf_regime.name  if self.rf_regime  else None,
            "rf_confidence":  round(self.rf_confidence, 4),
            "hmm_shift_prob": round(self.hmm_shift_prob, 4),
            "hmm_next_regime":self.hmm_next_regime.name if self.hmm_next_regime else None,
            "rule_regime":    self.rule_regime.name if self.rule_regime else None,
            "reasoning":      self.reasoning,
        }

# ──────────────────────────────────────────────────────────────────────────────
# Layer 1 — Rule-based Classifier
# ──────────────────────────────────────────────────────────────────────────────

class RuleBasedClassifier:
    """
    Fast deterministic classifier — runs in MQL5 standalone too.
    Priority order: VOLATILE > SQUEEZE > TRENDING > RANGING
    Hysteresis on TRENDING: enter@27, exit@23
    """

    def __init__(self) -> None:
        self._in_trending = False   # hysteresis state

    def classify(
        self,
        adx:       float,
        atr:       float,
        atr_ma:    float,
        bb_width:  float,
        bb_width_ma: float,
    ) -> Regime:
        """
        Parameters
        ----------
        adx         : ADX value (period=14 typical)
        atr         : current ATR value
        atr_ma      : MA(ATR, ATR_MA_PERIOD)
        bb_width    : (upper - lower) / middle  Bollinger Band width
        bb_width_ma : MA(bb_width, BB_MA_PERIOD)
        """
        # 1. VOLATILE check (highest priority)
        if atr_ma > 0 and atr > ATR_MULT * atr_ma:
            self._in_trending = False
            return Regime.VOLATILE

        # 2. SQUEEZE check
        if bb_width_ma > 0 and bb_width < BB_MULT * bb_width_ma:
            self._in_trending = False
            return Regime.SQUEEZE

        # 3. TRENDING with hysteresis
        if self._in_trending:
            # exit hysteresis
            if adx < ADX_EXIT_TRENDING:
                self._in_trending = False
        else:
            # enter hysteresis
            if adx >= ADX_ENTER_TRENDING:
                self._in_trending = True

        if self._in_trending:
            return Regime.TRENDING

        # 4. RANGING (default)
        return Regime.RANGING

    def reset(self) -> None:
        """Reset internal hysteresis state (call on symbol change)"""
        self._in_trending = False


# ──────────────────────────────────────────────────────────────────────────────
# Layer 2 — Random Forest Classifier
# ──────────────────────────────────────────────────────────────────────────────

class RandomForestClassifier:
    """
    Random Forest for market regime classification.
    Features: ADX, ATR, BB_Width, Volume, RSI, Stochastic, Price_Change, Session
    Labels:   RANGING(0), TRENDING(1), VOLATILE(2), SQUEEZE(3)
    """

    FEATURE_NAMES = [
        "adx",
        "atr",
        "atr_norm",       # atr / close
        "bb_width",
        "bb_width_norm",  # bb_width / bb_width_ma
        "volume",
        "volume_ma_ratio",# volume / MA(volume)
        "rsi",
        "stoch_k",
        "stoch_d",
        "price_change",   # (close - close[n]) / close[n]
        "session",        # 0=Asian 1=London 2=NY 3=Overlap
    ]
    N_FEATURES = len(FEATURE_NAMES)

    def __init__(
        self,
        n_estimators: int = 200,
        max_depth: int = 8,
        min_samples_leaf: int = 10,
        random_state: int = 42,
    ) -> None:
        from sklearn.ensemble import RandomForestClassifier as _RFC
        from sklearn.preprocessing import StandardScaler

        self._model = _RFC(
            n_estimators=n_estimators,
            max_depth=max_depth,
            min_samples_leaf=min_samples_leaf,
            class_weight="balanced",    # handle imbalanced regimes
            n_jobs=-1,
            random_state=random_state,
        )
        self._scaler = StandardScaler()
        self._trained = False

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def train(self, X: np.ndarray, y: np.ndarray) -> Dict[str, float]:
        """
        Train on historical data.

        Parameters
        ----------
        X : shape (n_samples, N_FEATURES) — feature matrix
        y : shape (n_samples,)            — Regime int labels
        """
        from sklearn.model_selection import cross_val_score

        X_scaled = self._scaler.fit_transform(X)
        scores = cross_val_score(self._model, X_scaled, y, cv=5, scoring="accuracy")
        self._model.fit(X_scaled, y)
        self._trained = True
        metrics = {
            "cv_accuracy_mean": float(scores.mean()),
            "cv_accuracy_std":  float(scores.std()),
            "n_samples":        len(y),
        }
        logger.info(
            "RF trained | CV accuracy: %.3f ± %.3f | n=%d",
            metrics["cv_accuracy_mean"], metrics["cv_accuracy_std"], metrics["n_samples"]
        )
        return metrics

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------

    def predict(self, x: np.ndarray) -> Tuple[Regime, float]:
        """
        Returns
        -------
        (regime, confidence)  — confidence = max class probability
        """
        if not self._trained:
            raise RuntimeError("RandomForestClassifier: call train() first")

        if x.ndim == 1:
            x = x.reshape(1, -1)

        x_scaled = self._scaler.transform(x)
        proba = self._model.predict_proba(x_scaled)[0]
        idx   = int(np.argmax(proba))
        return Regime(idx), float(proba[idx])

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save(self, path: Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump({"model": self._model, "scaler": self._scaler, "trained": self._trained}, f)
        logger.info("RF model saved → %s", path)

    def load(self, path: Path) -> None:
        with open(path, "rb") as f:
            d = pickle.load(f)
        self._model   = d["model"]
        self._scaler  = d["scaler"]
        self._trained = d["trained"]
        logger.info("RF model loaded ← %s", path)

    @property
    def is_trained(self) -> bool:
        return self._trained


# ──────────────────────────────────────────────────────────────────────────────
# Layer 3 — Hidden Markov Model
# ──────────────────────────────────────────────────────────────────────────────

class HMMRegimeClassifier:
    """
    Gaussian HMM with 4 hidden states (= 4 regimes).
    Purpose: predict regime shift probability for early warning.
    """

    N_STATES = 4   # matches len(Regime)

    # Features fed into HMM (simpler than RF — time-series friendly)
    HMM_FEATURE_NAMES = ["adx", "atr_norm", "bb_width_norm", "rsi"]

    def __init__(
        self,
        n_iter: int = 100,
        covariance_type: str = "diag",   # "diag" more robust than "full" on small data
        random_state: int = 42,
    ) -> None:
        from hmmlearn import hmm
        from sklearn.preprocessing import StandardScaler

        self._model = hmm.GaussianHMM(
            n_components=self.N_STATES,
            covariance_type=covariance_type,
            n_iter=n_iter,
            random_state=random_state,
        )
        self._scaler = StandardScaler()
        self._state_to_regime: Dict[int, Regime] = {}  # HMM state → Regime (learned)
        self._trained = False

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def train(self, X: np.ndarray, y_rule: np.ndarray) -> None:
        """
        Fit HMM on sequence data.

        Parameters
        ----------
        X      : (n_samples, n_hmm_features) time-ordered observations
        y_rule : (n_samples,) regime labels from Rule-based classifier
                 used to map HMM states → Regime after fitting
        """
        X_scaled = self._scaler.fit_transform(X)
        self._model.fit(X_scaled)

        # Map each HMM hidden state to the most common rule-based regime
        state_seq = self._model.predict(X_scaled)
        for state in range(self.N_STATES):
            mask = state_seq == state
            if mask.sum() == 0:
                self._state_to_regime[state] = Regime.RANGING
                continue
            counts = np.bincount(y_rule[mask], minlength=self.N_STATES)
            self._state_to_regime[state] = Regime(int(np.argmax(counts)))

        self._trained = True
        logger.info("HMM trained | state→regime mapping: %s",
                    {s: r.name for s, r in self._state_to_regime.items()})

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------

    def predict_shift(
        self, recent_window: np.ndarray
    ) -> Tuple[float, Optional[Regime]]:
        """
        Compute regime-shift probability for the NEXT bar.

        Parameters
        ----------
        recent_window : (n_bars, n_hmm_features) — recent observations (e.g. 30 bars)

        Returns
        -------
        (shift_prob, predicted_next_regime)
          shift_prob  — probability that NEXT regime ≠ CURRENT regime
          predicted_next_regime — most probable next regime if shift_prob high
        """
        if not self._trained:
            return 0.0, None

        # Decode current state
        window_scaled = self._scaler.transform(recent_window)
        _, state_seq = self._model.decode(window_scaled, algorithm="viterbi")
        current_state = int(state_seq[-1])

        # Transition row = probability distribution over next state
        trans_row = self._model.transmat_[current_state]

        # Shift probability = 1 - probability of staying in same state
        stay_prob  = float(trans_row[current_state])
        shift_prob = 1.0 - stay_prob

        # Next most probable state
        next_proba = trans_row.copy()
        next_proba[current_state] = 0.0          # exclude staying
        if next_proba.sum() < 1e-9:
            return shift_prob, None

        next_state    = int(np.argmax(next_proba))
        next_regime   = self._state_to_regime.get(next_state, Regime.RANGING)
        return shift_prob, next_regime

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save(self, path: Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump({
                "model":            self._model,
                "scaler":           self._scaler,
                "state_to_regime":  self._state_to_regime,
                "trained":          self._trained,
            }, f)
        logger.info("HMM model saved → %s", path)

    def load(self, path: Path) -> None:
        with open(path, "rb") as f:
            d = pickle.load(f)
        self._model           = d["model"]
        self._scaler          = d["scaler"]
        self._state_to_regime = d["state_to_regime"]
        self._trained         = d["trained"]
        logger.info("HMM model loaded ← %s", path)

    @property
    def is_trained(self) -> bool:
        return self._trained


# ──────────────────────────────────────────────────────────────────────────────
# Master Classifier — combines all 3 layers
# ──────────────────────────────────────────────────────────────────────────────

class RegimeClassifier:
    """
    3-Layer Market Regime Classifier.

    Decision logic:
        if RF_confidence > 0.75   → regime = RF result
        elif HMM_shift_prob > 0.80 → regime = HMM predicted next regime
        else                       → regime = Rule-based result

    Usage
    -----
    clf = RegimeClassifier()
    clf.train(df_historical)          # or clf.load_models(path)
    result = clf.classify(features)
    print(result.regime, result.source, result.rf_confidence)
    """

    def __init__(
        self,
        rf_confidence_threshold:  float = RF_CONFIDENCE_THRESHOLD,
        hmm_shift_threshold:      float = HMM_SHIFT_PROB_THRESHOLD,
        hmm_window:               int   = 30,   # bars fed into HMM
    ) -> None:
        self.rule_clf = RuleBasedClassifier()
        self.rf_clf   = RandomForestClassifier()
        self.hmm_clf  = HMMRegimeClassifier()

        self.rf_threshold  = rf_confidence_threshold
        self.hmm_threshold = hmm_shift_threshold
        self.hmm_window    = hmm_window

        # Rolling buffer for HMM (time-ordered HMM features)
        self._hmm_buffer: List[np.ndarray] = []

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def train(self, df: pd.DataFrame, symbol: str = "UNKNOWN") -> Dict:
        """
        Train all ML layers on 6-month historical data.

        Required columns in df
        ----------------------
        adx, atr, atr_ma, atr_norm, bb_width, bb_width_ma, bb_width_norm,
        volume, volume_ma_ratio, rsi, stoch_k, stoch_d, price_change, session,
        close

        The method auto-labels rows using Rule-based classifier.
        """
        logger.info("Training RegimeClassifier | symbol=%s | rows=%d", symbol, len(df))
        df = df.dropna().copy()

        # ── Auto-label with Rule-based ──────────────────────────────────
        rule_labels = []
        for _, row in df.iterrows():
            lbl = self.rule_clf.classify(
                adx=row["adx"],
                atr=row["atr"],
                atr_ma=row["atr_ma"],
                bb_width=row["bb_width"],
                bb_width_ma=row["bb_width_ma"],
            )
            rule_labels.append(int(lbl))
        y = np.array(rule_labels, dtype=int)
        self.rule_clf.reset()   # reset hysteresis after labelling

        # ── Train RF ───────────────────────────────────────────────────
        rf_cols = RandomForestClassifier.FEATURE_NAMES
        X_rf = df[rf_cols].values.astype(float)
        rf_metrics = self.rf_clf.train(X_rf, y)

        # ── Train HMM ──────────────────────────────────────────────────
        hmm_cols = HMMRegimeClassifier.HMM_FEATURE_NAMES
        X_hmm = df[hmm_cols].values.astype(float)
        self.hmm_clf.train(X_hmm, y)

        return {
            "symbol": symbol,
            "n_samples": len(df),
            "rf": rf_metrics,
            "label_distribution": {
                Regime(i).name: int((y == i).sum()) for i in range(4)
            },
        }

    # ------------------------------------------------------------------
    # Classify single tick / bar
    # ------------------------------------------------------------------

    def classify(
        self,
        adx:           float,
        atr:           float,
        atr_ma:        float,
        atr_norm:      float,   # atr / close
        bb_width:      float,
        bb_width_ma:   float,
        bb_width_norm: float,   # bb_width / bb_width_ma
        volume:        float,
        volume_ma_ratio: float,
        rsi:           float,
        stoch_k:       float,
        stoch_d:       float,
        price_change:  float,
        session:       int,     # 0=Asian 1=London 2=NY 3=Overlap
    ) -> RegimeResult:
        """
        Classify current market regime using all 3 layers.
        Call this every tick or every bar close.
        """
        # ── Layer 1: Rule-based ────────────────────────────────────────
        rule_regime = self.rule_clf.classify(
            adx=adx, atr=atr, atr_ma=atr_ma,
            bb_width=bb_width, bb_width_ma=bb_width_ma,
        )

        # ── Layer 2: Random Forest ─────────────────────────────────────
        rf_regime: Optional[Regime] = None
        rf_confidence = 0.0
        if self.rf_clf.is_trained:
            x_rf = np.array([
                adx, atr, atr_norm, bb_width, bb_width_norm,
                volume, volume_ma_ratio, rsi, stoch_k, stoch_d,
                price_change, float(session),
            ], dtype=float)
            try:
                rf_regime, rf_confidence = self.rf_clf.predict(x_rf)
            except Exception as e:
                logger.warning("RF predict failed: %s", e)

        # ── Layer 3: HMM (rolling window) ─────────────────────────────
        hmm_shift_prob = 0.0
        hmm_next_regime: Optional[Regime] = None
        if self.hmm_clf.is_trained:
            x_hmm = np.array([adx, atr_norm, bb_width_norm, rsi], dtype=float)
            self._hmm_buffer.append(x_hmm)
            if len(self._hmm_buffer) > self.hmm_window:
                self._hmm_buffer.pop(0)

            if len(self._hmm_buffer) >= self.hmm_window:
                window = np.vstack(self._hmm_buffer)
                try:
                    hmm_shift_prob, hmm_next_regime = self.hmm_clf.predict_shift(window)
                except Exception as e:
                    logger.warning("HMM predict failed: %s", e)

        # ── Combined Decision ──────────────────────────────────────────
        if rf_confidence > self.rf_threshold and rf_regime is not None:
            final_regime = rf_regime
            source       = "RF"
            reasoning    = (
                f"RF confidence {rf_confidence:.3f} > {self.rf_threshold} → {rf_regime}"
            )
        elif hmm_shift_prob > self.hmm_threshold and hmm_next_regime is not None:
            final_regime = hmm_next_regime
            source       = "HMM"
            reasoning    = (
                f"HMM shift prob {hmm_shift_prob:.3f} > {self.hmm_threshold} "
                f"→ early warning: {hmm_next_regime}"
            )
        else:
            final_regime = rule_regime
            source       = "RULE"
            reasoning    = (
                f"RF conf={rf_confidence:.3f} HMM shift={hmm_shift_prob:.3f} "
                f"→ fallback Rule-based: {rule_regime}"
            )

        return RegimeResult(
            regime=final_regime,
            source=source,
            rf_regime=rf_regime,
            rf_confidence=rf_confidence,
            hmm_shift_prob=hmm_shift_prob,
            hmm_next_regime=hmm_next_regime,
            rule_regime=rule_regime,
            reasoning=reasoning,
        )

    def reset_symbol(self) -> None:
        """Call when switching symbols to reset hysteresis + HMM buffer"""
        self.rule_clf.reset()
        self._hmm_buffer.clear()

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save_models(self, base_path: Path, symbol: str) -> None:
        base_path = Path(base_path)
        self.rf_clf.save(base_path / f"rf_{symbol}.pkl")
        self.hmm_clf.save(base_path / f"hmm_{symbol}.pkl")

    def load_models(self, base_path: Path, symbol: str) -> None:
        base_path = Path(base_path)
        rf_path  = base_path / f"rf_{symbol}.pkl"
        hmm_path = base_path / f"hmm_{symbol}.pkl"
        if rf_path.exists():
            self.rf_clf.load(rf_path)
        if hmm_path.exists():
            self.hmm_clf.load(hmm_path)


# ──────────────────────────────────────────────────────────────────────────────
# Feature Builder helper (standalone utility)
# ──────────────────────────────────────────────────────────────────────────────

def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Build all required features from raw OHLCV + tick data.

    Expected raw columns: open, high, low, close, volume, hour (0-23)

    Returns df with all feature columns added.
    """
    import warnings
    warnings.filterwarnings("ignore")

    df = df.copy()

    # ── ATR (manual, period=14) ────────────────────────────────────────
    high_low   = df["high"] - df["low"]
    high_close = (df["high"] - df["close"].shift(1)).abs()
    low_close  = (df["low"]  - df["close"].shift(1)).abs()
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df["atr"]    = tr.ewm(span=14, adjust=False).mean()
    df["atr_ma"] = df["atr"].rolling(ATR_MA_PERIOD).mean()
    df["atr_norm"] = df["atr"] / df["close"].replace(0, np.nan)

    # ── Bollinger Band Width ──────────────────────────────────────────
    bb_mid = df["close"].rolling(20).mean()
    bb_std = df["close"].rolling(20).std()
    df["bb_width"]    = (2 * bb_std) / bb_mid.replace(0, np.nan)
    df["bb_width_ma"] = df["bb_width"].rolling(BB_MA_PERIOD).mean()
    df["bb_width_norm"] = df["bb_width"] / df["bb_width_ma"].replace(0, np.nan)

    # ── ADX (simplified via DI+/DI- directional movement) ────────────
    up_move   = df["high"].diff()
    down_move = -df["low"].diff()
    plus_dm   = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
    minus_dm  = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)
    atr14     = df["atr"]
    plus_di   = 100 * pd.Series(plus_dm, index=df.index).ewm(span=14).mean() / atr14.replace(0, np.nan)
    minus_di  = 100 * pd.Series(minus_dm, index=df.index).ewm(span=14).mean() / atr14.replace(0, np.nan)
    dx        = (100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan))
    df["adx"] = dx.ewm(span=14).mean()

    # ── RSI ──────────────────────────────────────────────────────────
    delta = df["close"].diff()
    gain  = delta.clip(lower=0).ewm(span=14, adjust=False).mean()
    loss  = (-delta.clip(upper=0)).ewm(span=14, adjust=False).mean()
    rs    = gain / loss.replace(0, np.nan)
    df["rsi"] = 100 - (100 / (1 + rs))

    # ── Stochastic (%K, %D) ──────────────────────────────────────────
    low14  = df["low"].rolling(14).min()
    high14 = df["high"].rolling(14).max()
    df["stoch_k"] = 100 * (df["close"] - low14) / (high14 - low14).replace(0, np.nan)
    df["stoch_d"] = df["stoch_k"].rolling(3).mean()

    # ── Volume MA ratio ──────────────────────────────────────────────
    df["volume_ma_ratio"] = df["volume"] / df["volume"].rolling(20).mean().replace(0, np.nan)

    # ── Price change (14-bar) ────────────────────────────────────────
    df["price_change"] = df["close"].pct_change(14)

    # ── Session mapping ──────────────────────────────────────────────
    def _hour_to_session(h: int) -> int:
        if  2 <= h <  9: return 0   # Asian
        if  9 <= h < 13: return 1   # London
        if 13 <= h < 18: return 2   # NY (overlap if < 17)
        return 3                    # Off-hours / overlap end
    df["session"] = df["hour"].apply(_hour_to_session)

    return df.dropna()


# ──────────────────────────────────────────────────────────────────────────────
# Quick self-test (also serves as usage example)
# ──────────────────────────────────────────────────────────────────────────────

def _generate_synthetic_ohlcv(n: int = 1500, seed: int = 42) -> pd.DataFrame:
    """Generate synthetic OHLCV with embedded regime transitions for testing."""
    rng = np.random.default_rng(seed)
    # Regime blocks: (n_bars, vol_mult, trend_slope)
    blocks = [
        (375, 0.5, 0.0001),    # RANGING
        (375, 0.5, 0.0008),    # TRENDING up
        (375, 2.5, 0.0),       # VOLATILE
        (375, 0.2, 0.0),       # SQUEEZE
    ]
    prices = [1.1000]
    vols   = []
    for n_bars, v_mult, slope in blocks:
        for _ in range(n_bars):
            ret = slope + rng.normal(0, 0.0003 * v_mult)
            prices.append(prices[-1] * (1 + ret))
            vols.append(rng.uniform(500, 1500) * v_mult)

    prices = prices[1:]
    close  = np.array(prices[:n])
    vol    = np.array(vols[:n])
    noise  = rng.uniform(0.0002, 0.0006, n)
    high   = close * (1 + noise)
    low    = close * (1 - noise)
    hours  = np.tile(np.arange(24), n // 24 + 1)[:n]

    return pd.DataFrame({
        "open":   np.roll(close, 1),
        "high":   high,
        "low":    low,
        "close":  close,
        "volume": vol,
        "hour":   hours,
    })


def run_self_test(n_periods: int = 100) -> None:
    """
    Classify 100 historical periods and print results.
    Tests all 3 layers end-to-end.
    """
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    logger.info("=" * 60)
    logger.info("RegimeClassifier — Self Test")
    logger.info("=" * 60)

    # ── 1. Generate synthetic data ─────────────────────────────────
    logger.info("Generating synthetic OHLCV (1500 bars)...")
    df_raw = _generate_synthetic_ohlcv(n=1500)

    # ── 2. Build features ─────────────────────────────────────────
    logger.info("Building features...")
    df = build_features(df_raw)
    logger.info("Feature rows after dropna: %d", len(df))

    # ── 3. Train on first 80% ─────────────────────────────────────
    split = int(len(df) * 0.8)
    df_train = df.iloc[:split]
    df_test  = df.iloc[split:]

    clf = RegimeClassifier()
    metrics = clf.train(df_train, symbol="XAUUSD.tp")
    logger.info("Training metrics: %s", metrics)

    # ── 4. Classify test periods ──────────────────────────────────
    source_counts = {"RF": 0, "HMM": 0, "RULE": 0}
    regime_counts = {r.name: 0 for r in Regime}
    sample = df_test.tail(n_periods)

    results = []
    for idx, row in sample.iterrows():
        result = clf.classify(
            adx=row["adx"],
            atr=row["atr"],
            atr_ma=row["atr_ma"],
            atr_norm=row["atr_norm"],
            bb_width=row["bb_width"],
            bb_width_ma=row["bb_width_ma"],
            bb_width_norm=row["bb_width_norm"],
            volume=row["volume"],
            volume_ma_ratio=row["volume_ma_ratio"],
            rsi=row["rsi"],
            stoch_k=row["stoch_k"],
            stoch_d=row["stoch_d"],
            price_change=row["price_change"],
            session=int(row["session"]),
        )
        source_counts[result.source] += 1
        regime_counts[result.regime.name] += 1
        results.append(result)

    # ── 5. Report ─────────────────────────────────────────────────
    logger.info("-" * 40)
    logger.info("Results over %d test periods:", n_periods)
    logger.info("  Source distribution : %s", source_counts)
    logger.info("  Regime distribution : %s", regime_counts)
    logger.info("  Sample results (last 5):")
    for r in results[-5:]:
        logger.info("    %s", r.reasoning)

    # ── 6. Assertions ─────────────────────────────────────────────
    assert len(results) == n_periods, "classify() must return one result per period"
    for r in results:
        assert isinstance(r.regime, Regime), "regime must be Regime enum"
        assert r.source in ("RF", "HMM", "RULE"), "source must be RF/HMM/RULE"
        assert 0.0 <= r.rf_confidence <= 1.0, "rf_confidence out of range"
        assert 0.0 <= r.hmm_shift_prob <= 1.0, "hmm_shift_prob out of range"

    logger.info("=" * 60)
    logger.info("✅ ALL ASSERTIONS PASSED — RegimeClassifier OK")
    logger.info("=" * 60)


if __name__ == "__main__":
    run_self_test(n_periods=100)
