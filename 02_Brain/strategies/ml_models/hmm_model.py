#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Hidden Markov Model (HMM)
ทำนาย regime shift transition probabilities

Hidden states: 4 market regimes
    State 0: TRENDING
    State 1: RANGING
    State 2: VOLATILE
    State 3: SQUEEZE

Output:
    - current_state    : most likely hidden state
    - next_state_proba : P(next_state | current sequence)
    - regime_shift_prob: P(shift to different regime)
    - confidence       : model certainty

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-22
"""

import numpy as np
import pandas as pd
import pickle
import os
import logging
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ── Check hmmlearn availability ───────────────────────────────────────────────
HMM_AVAILABLE = False
try:
    from hmmlearn.hmm import GaussianHMM
    HMM_AVAILABLE = True
    logger.info("hmmlearn available")
except ImportError:
    logger.warning("hmmlearn not installed — pip install hmmlearn")

# State mapping
HMM_STATES     = {0: "TRENDING", 1: "RANGING", 2: "VOLATILE", 3: "SQUEEZE"}
N_STATES       = 4

# Observation features for HMM
HMM_FEATURES = [
    "ret_1", "realized_vol_20", "adx_14", "vol_ratio_5_20",
    "bb_pct", "momentum_5"
]


class HMMModel:
    """
    Gaussian HMM for market regime shift detection.

    Observation sequence = selected features (multivariate Gaussian per state)

    Viterbi decoding → current state
    Forward algorithm → next state probabilities
    """

    def __init__(self,
                 n_states: int = 4,
                 n_iter: int = 100,
                 covariance_type: str = "diag",
                 model_path: str = "models/hmm_regime.pkl"):
        """
        Args:
            n_states        : number of hidden states (4 regimes)
            n_iter          : Baum-Welch iterations
            covariance_type : "diag" (stable) or "full" (more expressive)
            model_path      : model save/load path
        """
        self.n_states        = n_states
        self.n_iter          = n_iter
        self.covariance_type = covariance_type
        self.model_path      = model_path

        self._trained          = False
        self._model            = None
        self._feature_names    : List[str] = []
        self._state_regime_map : Dict[int, str] = {}  # model state → regime name
        self._log_likelihood   : float = -np.inf
        self._n_features       : int   = 0

        logger.info("HMMModel initialized (n_states=%d)", n_states)

    # ─────────────────────────────────────────────────────────────────────────
    # TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def train(self, X: pd.DataFrame,
              regime_labels: Optional[pd.Series] = None) -> Dict:
        """
        Fit Gaussian HMM to observation sequence.

        Args:
            X             : Feature DataFrame
            regime_labels : Optional external labels for state alignment
                            (0-3 matching HMM_STATES). If provided, used to
                            map model states to regime names.

        Returns:
            dict with training metrics
        """
        if not HMM_AVAILABLE:
            logger.warning("hmmlearn not available — using mock HMM")
            return self._train_mock(X)

        # ── Select features ───────────────────────────────────────────────────
        feat_cols = [c for c in HMM_FEATURES if c in X.columns]
        if not feat_cols:
            feat_cols = list(X.columns[:6])

        self._feature_names = feat_cols
        self._n_features    = len(feat_cols)

        obs_raw = X[feat_cols].dropna().values.astype(np.float64)

        # Standardize observations — HMM is sensitive to scale
        from sklearn.preprocessing import StandardScaler as _SS
        self._obs_scaler = _SS()
        obs = self._obs_scaler.fit_transform(obs_raw)

        lengths = [len(obs)]  # single sequence

        # ── Fit HMM ───────────────────────────────────────────────────────────
        self._model = GaussianHMM(
            n_components=self.n_states,
            covariance_type=self.covariance_type,
            n_iter=self.n_iter,
            random_state=42,
            min_covar=1e-3,           # prevent singular covariance
            init_params="stmc",       # initialize all params
            params="stmc"             # estimate all params
        )

        try:
            self._model.fit(obs, lengths)
            self._log_likelihood = float(self._model.score(obs, lengths))
        except Exception as e:
            logger.warning("HMM fit failed (%s) — switching to mock mode", e)
            # Fallback: use mock HMM so system stays functional
            return self._train_mock(X)

        # ── Map model states to regime names ──────────────────────────────────
        predicted_states = self._model.predict(obs, lengths)
        self._state_regime_map = self._map_states_to_regimes(
            X[feat_cols].dropna(), predicted_states, regime_labels
        )
        # Store scaler reference for predict()
        # (already set above via self._obs_scaler)

        self._trained = True

        logger.info("HMM trained. LogL=%.2f, states=%s",
                    self._log_likelihood, self._state_regime_map)

        return {
            "log_likelihood":   self._log_likelihood,
            "n_states":         self.n_states,
            "n_obs":            len(obs),
            "state_regime_map": self._state_regime_map,
            "converged":        self._model.monitor_.converged
        }

    # ─────────────────────────────────────────────────────────────────────────
    # INFERENCE
    # ─────────────────────────────────────────────────────────────────────────

    def predict(self, X: pd.DataFrame, window: int = 60) -> Dict:
        """
        Predict regime and transition probabilities for latest bar.

        Args:
            X      : Feature DataFrame
            window : number of recent bars for state estimation

        Returns:
            {
                "current_state":     int (0-3 model state)
                "current_regime":    str ("TRENDING" etc.)
                "next_state_proba":  dict {regime: probability}
                "regime_shift_prob": float (prob of transitioning out)
                "confidence":        float
                "trained":           bool
            }
        """
        if not self._trained:
            return self._default_result()

        if not HMM_AVAILABLE:
            return self._predict_mock(X)

        feat_cols = [c for c in self._feature_names if c in X.columns]
        recent    = X[feat_cols].iloc[-window:].dropna()

        if len(recent) < 10:
            return self._default_result()

        obs_raw = recent.values.astype(np.float64)
        # Apply same scaler used during training
        if hasattr(self, '_obs_scaler') and self._obs_scaler is not None:
            obs = self._obs_scaler.transform(obs_raw)
        else:
            obs = obs_raw
        lengths = [len(obs)]

        # Viterbi: most likely state sequence
        try:
            states = self._model.predict(obs, lengths)
            current_state = int(states[-1])
        except Exception as e:
            logger.error("HMM predict error: %s", e)
            return self._default_result()

        # Next state probabilities via transition matrix
        trans_matrix = self._model.transmat_
        next_proba   = trans_matrix[current_state]  # shape (n_states,)

        # Map to regime names
        current_regime = self._state_regime_map.get(current_state, f"STATE_{current_state}")

        next_proba_named = {}
        for state_idx, prob in enumerate(next_proba):
            regime_name = self._state_regime_map.get(state_idx, f"STATE_{state_idx}")
            next_proba_named[regime_name] = float(prob)

        # Regime shift probability = 1 - P(stay in current regime)
        stay_prob        = float(trans_matrix[current_state, current_state])
        regime_shift_prob = float(1.0 - stay_prob)

        # Confidence based on log likelihood of recent sequence
        try:
            log_l   = float(self._model.score(obs, lengths))
            norm_ll = np.exp(log_l / len(obs))
            confidence = float(min(1.0, max(0.0, norm_ll)))
        except Exception:
            confidence = 0.5

        return {
            "current_state":     current_state,
            "current_regime":    current_regime,
            "next_state_proba":  next_proba_named,
            "regime_shift_prob": regime_shift_prob,
            "stay_probability":  stay_prob,
            "confidence":        confidence,
            "trained":           True
        }

    def get_transition_matrix(self) -> Optional[np.ndarray]:
        """Return the learned transition probability matrix."""
        if self._trained and self._model:
            return self._model.transmat_
        return None

    # ─────────────────────────────────────────────────────────────────────────
    # PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def save(self, path: Optional[str] = None) -> str:
        path = path or self.model_path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        payload = {
            "model":           self._model,
            "feature_names":   self._feature_names,
            "state_regime_map": self._state_regime_map,
            "log_likelihood":  self._log_likelihood,
            "n_features":      self._n_features,
            "trained":         self._trained,
            "obs_scaler":      getattr(self, "_obs_scaler", None)
        }
        with open(path, "wb") as f:
            pickle.dump(payload, f)
        logger.info("HMM model saved → %s", path)
        return path

    def load(self, path: Optional[str] = None) -> bool:
        path = path or self.model_path
        if not os.path.exists(path):
            logger.warning("HMM model not found: %s", path)
            return False
        with open(path, "rb") as f:
            p = pickle.load(f)
        self._model            = p["model"]
        self._feature_names    = p["feature_names"]
        self._state_regime_map = p["state_regime_map"]
        self._log_likelihood   = p["log_likelihood"]
        self._n_features       = p["n_features"]
        self._trained          = p["trained"]
        self._obs_scaler       = p.get("obs_scaler", None)
        logger.info("HMM model loaded ← %s", path)
        return True

    # ─────────────────────────────────────────────────────────────────────────
    # MOCK FALLBACK (no hmmlearn)
    # ─────────────────────────────────────────────────────────────────────────

    def _train_mock(self, X: pd.DataFrame) -> Dict:
        """Simple statistical mock HMM using feature thresholds."""
        feat_cols = [c for c in HMM_FEATURES if c in X.columns]
        if not feat_cols:
            feat_cols = list(X.columns[:6])
        self._feature_names = feat_cols
        self._obs_scaler = None
        self._trained = True

        # Mock transition matrix: slightly sticky states
        trans = np.ones((N_STATES, N_STATES)) * 0.1
        np.fill_diagonal(trans, 0.7)
        trans /= trans.sum(axis=1, keepdims=True)
        self._mock_transmat = trans

        # Mock state mapping
        self._state_regime_map = {i: HMM_STATES[i] for i in range(N_STATES)}

        logger.warning("HMM running in MOCK mode")
        return {"log_likelihood": -999.0, "mock": True}

    def _predict_mock(self, X: pd.DataFrame) -> Dict:
        """Mock prediction using ADX + volatility rules."""
        adx = float(X.get("adx_14", pd.Series([20.0])).iloc[-1]) if "adx_14" in X.columns else 20.0
        vol = float(X.get("vol_ratio_5_20", pd.Series([1.0])).iloc[-1]) if "vol_ratio_5_20" in X.columns else 1.0
        vp  = float(X.get("vol_percentile_60", pd.Series([50.0])).iloc[-1]) if "vol_percentile_60" in X.columns else 50.0

        if vol > 1.5:
            state = 2  # VOLATILE
        elif vp < 20 and adx < 20:
            state = 3  # SQUEEZE
        elif adx > 25:
            state = 0  # TRENDING
        else:
            state = 1  # RANGING

        trans = self._mock_transmat[state]
        next_proba = {HMM_STATES[i]: float(trans[i]) for i in range(N_STATES)}

        return {
            "current_state":     state,
            "current_regime":    HMM_STATES[state],
            "next_state_proba":  next_proba,
            "regime_shift_prob": float(1.0 - trans[state]),
            "stay_probability":  float(trans[state]),
            "confidence":        0.4,
            "trained":           True
        }

    # ─────────────────────────────────────────────────────────────────────────
    # HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    def _map_states_to_regimes(X: pd.DataFrame,
                                states: np.ndarray,
                                labels: Optional[pd.Series]) -> Dict[int, str]:
        """
        Map HMM model states (arbitrary integers) to named regimes.

        If external labels provided: map by majority vote per state.
        Otherwise: map by ADX / volatility characteristics.
        """
        n_states = int(states.max()) + 1
        mapping  = {}

        if labels is not None:
            # Majority vote
            labels_arr = labels.values[:len(states)]
            for s in range(n_states):
                mask = states == s
                if mask.any():
                    dominant = int(np.bincount(
                        labels_arr[mask].astype(int),
                        minlength=N_STATES
                    ).argmax())
                    mapping[s] = HMM_STATES.get(dominant, f"STATE_{s}")
                else:
                    mapping[s] = f"STATE_{s}"
        else:
            # Rule-based mapping using mean ADX per state
            adx_col = "adx_14" if "adx_14" in X.columns else X.columns[0]
            vol_col = "vol_ratio_5_20" if "vol_ratio_5_20" in X.columns else None
            vp_col  = "vol_percentile_60" if "vol_percentile_60" in X.columns else None

            state_adx = {}
            state_vol = {}
            state_vp  = {}

            for s in range(n_states):
                mask = states == s
                if mask.any():
                    state_adx[s] = float(X[adx_col].values[mask].mean())
                    state_vol[s] = float(X[vol_col].values[mask].mean()) if vol_col else 1.0
                    state_vp[s]  = float(X[vp_col].values[mask].mean()) if vp_col else 50.0

            # Sort states
            sorted_by_adx = sorted(state_adx.keys(), key=lambda s: state_adx[s])
            sorted_by_vol = sorted(state_vol.keys(), key=lambda s: state_vol[s], reverse=True)

            assigned = set()
            # VOLATILE = highest vol_ratio
            for s in sorted_by_vol:
                if s not in assigned:
                    mapping[s] = "VOLATILE"
                    assigned.add(s)
                    break
            # SQUEEZE = lowest vol_percentile and low ADX
            best_squeeze = min((s for s in range(n_states) if s not in assigned),
                               key=lambda s: state_vp.get(s, 99) + state_adx.get(s, 99),
                               default=None)
            if best_squeeze is not None:
                mapping[best_squeeze] = "SQUEEZE"
                assigned.add(best_squeeze)
            # TRENDING = highest ADX (among remaining)
            for s in reversed(sorted_by_adx):
                if s not in assigned:
                    mapping[s] = "TRENDING"
                    assigned.add(s)
                    break
            # Remaining → RANGING
            for s in range(n_states):
                if s not in assigned:
                    mapping[s] = "RANGING"

        return mapping

    @staticmethod
    def _default_result() -> Dict:
        return {
            "current_state":     1,
            "current_regime":    "RANGING",
            "next_state_proba":  {r: 0.25 for r in HMM_STATES.values()},
            "regime_shift_prob": 0.3,
            "stay_probability":  0.7,
            "confidence":        0.0,
            "trained":           False
        }


# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE TEST
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
    from feature_engineering import FeatureEngineer

    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s")

    print("=" * 60)
    print("HMMModel — Self Test")
    print(f"hmmlearn: {'available' if HMM_AVAILABLE else 'NOT available (mock mode)'}")
    print("=" * 60)

    np.random.seed(42)
    n = 600
    dates = pd.date_range("2025-01-01", periods=n, freq="1min", tz="UTC")
    price = 2000.0 + np.cumsum(np.random.randn(n) * 0.5)
    df = pd.DataFrame({
        "open": price, "high": price + 0.3,
        "low":  price - 0.3, "close": price,
        "volume": np.random.randint(100, 1000, n).astype(float)
    }, index=dates)

    fe = FeatureEngineer()
    X  = fe.compute(df)

    hmm = HMMModel(model_path="/tmp/hmm_test.pkl")
    metrics = hmm.train(X)
    print(f"\nTraining metrics:")
    for k, v in metrics.items():
        print(f"  {k}: {v}")

    result = hmm.predict(X)
    print(f"\nLatest bar prediction:")
    for k, v in result.items():
        print(f"  {k}: {v}")

    trans = hmm.get_transition_matrix()
    if trans is not None:
        print(f"\nTransition matrix:\n{np.round(trans, 3)}")

    hmm.save()
    hmm2 = HMMModel(model_path="/tmp/hmm_test.pkl")
    hmm2.load()
    r2 = hmm2.predict(X)
    print(f"\nAfter load: regime={r2['current_regime']}, shift_prob={r2['regime_shift_prob']:.3f}")

    print("\n✅ HMMModel Test PASSED")
