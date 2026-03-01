#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Random Forest Model
จำแนก Market Regime เป็น 4 classes

Classes:
    0 = TRENDING
    1 = RANGING
    2 = VOLATILE
    3 = SQUEEZE

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
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, TimeSeriesSplit
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, accuracy_score

logger = logging.getLogger(__name__)

# ── Regime Labels ─────────────────────────────────────────────────────────────
REGIME_TRENDING  = 0
REGIME_RANGING   = 1
REGIME_VOLATILE  = 2
REGIME_SQUEEZE   = 3
REGIME_NAMES     = {0: "TRENDING", 1: "RANGING", 2: "VOLATILE", 3: "SQUEEZE"}


class RandomForestModel:
    """
    Random Forest classifier for Market Regime detection.

    Flow:
        train(X, y) → predict(X) → {regime, probabilities}

    Training targets (y) are auto-generated from price data if not provided.
    """

    # Features most important for regime classification
    KEY_FEATURES = [
        "adx_14", "atr_14", "realized_vol_20", "vol_ratio_5_20",
        "bb_pct", "vol_percentile_60", "high_low_range",
        "rsi_14", "macd_hist", "momentum_15",
        "volume_ma_ratio", "h1_trend", "h4_trend"
    ]

    def __init__(self,
                 n_estimators: int = 200,
                 max_depth: int = 8,
                 min_samples_split: int = 20,
                 model_path: str = "models/rf_regime.pkl"):
        """
        Args:
            n_estimators      : number of trees
            max_depth         : max tree depth (prevent overfitting)
            min_samples_split : min samples to split node
            model_path        : where to save/load the trained model
        """
        self.model_path = model_path
        self.n_estimators = n_estimators

        self.clf = RandomForestClassifier(
            n_estimators=n_estimators,
            max_depth=max_depth,
            min_samples_split=min_samples_split,
            max_features="sqrt",
            random_state=42,
            n_jobs=-1,
            class_weight="balanced"   # handle imbalanced regimes
        )
        self._trained = False
        self._feature_names: List[str] = []
        self._accuracy: float = 0.0

        logger.info("RandomForestModel initialized (n_estimators=%d)", n_estimators)

    # ─────────────────────────────────────────────────────────────────────────
    # TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def train(self, X: pd.DataFrame, y: Optional[pd.Series] = None,
              validate: bool = True) -> Dict:
        """
        Train the Random Forest classifier.

        Args:
            X        : Feature DataFrame (output of FeatureEngineer)
            y        : Target labels (0-3). If None, auto-generates from features.
            validate : Run time-series CV

        Returns:
            dict with training metrics
        """
        if y is None:
            y = self._auto_label(X)
            logger.info("Auto-generated labels: %s", y.value_counts().to_dict())

        self._feature_names = list(X.columns)

        # Time-series aware split — auto-adjust n_splits for small datasets
        n_splits = min(5, max(2, len(X) // 100))
        tscv = TimeSeriesSplit(n_splits=n_splits)

        if validate and len(X) >= n_splits * 20:
            cv_scores = cross_val_score(self.clf, X, y, cv=tscv,
                                        scoring="accuracy", n_jobs=-1)
            cv_mean = float(cv_scores.mean())
            cv_std  = float(cv_scores.std())
            logger.info("CV Accuracy: %.3f ± %.3f (splits=%d)", cv_mean, cv_std, n_splits)
        else:
            cv_mean, cv_std = 0.0, 0.0
            if validate:
                logger.info("CV skipped — dataset too small (%d rows)", len(X))

        # Train on full data
        self.clf.fit(X, y)
        self._trained = True

        # In-sample accuracy
        y_pred = self.clf.predict(X)
        train_acc = float(accuracy_score(y, y_pred))
        self._accuracy = cv_mean if validate else train_acc

        logger.info("Training complete. Train acc=%.3f, CV acc=%.3f",
                    train_acc, cv_mean)

        return {
            "train_accuracy":    train_acc,
            "cv_accuracy_mean":  cv_mean,
            "cv_accuracy_std":   cv_std,
            "n_samples":         len(X),
            "feature_count":     len(self._feature_names),
            "class_distribution": dict(y.value_counts())
        }

    # ─────────────────────────────────────────────────────────────────────────
    # INFERENCE
    # ─────────────────────────────────────────────────────────────────────────

    def predict(self, X: pd.DataFrame) -> Dict:
        """
        Predict market regime for the latest bar.

        Args:
            X : Feature DataFrame (at least 1 row)

        Returns:
            {
                "regime":      int  (0-3),
                "regime_name": str  ("TRENDING" / "RANGING" / "VOLATILE" / "SQUEEZE"),
                "confidence":  float (max class probability),
                "proba":       dict  {regime_name: probability},
                "trained":     bool
            }
        """
        if not self._trained:
            logger.warning("RF model not trained — returning default")
            return self._default_result()

        # Use latest row only
        row = X.iloc[[-1]]

        # Align features
        row = self._align_features(row)

        proba      = self.clf.predict_proba(row)[0]  # shape (4,)
        regime_idx = int(np.argmax(proba))
        confidence = float(proba[regime_idx])

        proba_dict = {REGIME_NAMES[i]: float(proba[i])
                      for i in range(len(proba))}

        return {
            "regime":      regime_idx,
            "regime_name": REGIME_NAMES[regime_idx],
            "confidence":  confidence,
            "proba":       proba_dict,
            "trained":     True
        }

    def predict_series(self, X: pd.DataFrame) -> pd.DataFrame:
        """
        Predict regime for all rows (used during training evaluation).
        Returns DataFrame with regime and confidence columns.
        """
        if not self._trained:
            return pd.DataFrame()

        X_aligned  = self._align_features(X)
        probas     = self.clf.predict_proba(X_aligned)
        regimes    = np.argmax(probas, axis=1)
        confidence = np.max(probas, axis=1)

        return pd.DataFrame({
            "regime":      regimes,
            "regime_name": [REGIME_NAMES[r] for r in regimes],
            "confidence":  confidence
        }, index=X.index)

    # ─────────────────────────────────────────────────────────────────────────
    # FEATURE IMPORTANCE
    # ─────────────────────────────────────────────────────────────────────────

    def get_feature_importance(self, top_n: int = 10) -> Dict[str, float]:
        """Return top-N feature importances."""
        if not self._trained:
            return {}

        importances = self.clf.feature_importances_
        names       = self._feature_names
        ranked      = sorted(zip(names, importances),
                             key=lambda x: x[1], reverse=True)
        return {k: float(v) for k, v in ranked[:top_n]}

    # ─────────────────────────────────────────────────────────────────────────
    # PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def save(self, path: Optional[str] = None) -> str:
        """Save trained model to disk."""
        path = path or self.model_path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

        payload = {
            "clf":           self.clf,
            "feature_names": self._feature_names,
            "accuracy":      self._accuracy,
            "trained":       self._trained
        }
        with open(path, "wb") as f:
            pickle.dump(payload, f)

        logger.info("RF model saved → %s", path)
        return path

    def load(self, path: Optional[str] = None) -> bool:
        """Load trained model from disk."""
        path = path or self.model_path
        if not os.path.exists(path):
            logger.warning("RF model file not found: %s", path)
            return False

        with open(path, "rb") as f:
            payload = pickle.load(f)

        self.clf            = payload["clf"]
        self._feature_names = payload["feature_names"]
        self._accuracy      = payload["accuracy"]
        self._trained       = payload["trained"]

        logger.info("RF model loaded ← %s (acc=%.3f)", path, self._accuracy)
        return True

    # ─────────────────────────────────────────────────────────────────────────
    # INTERNALS
    # ─────────────────────────────────────────────────────────────────────────

    def _align_features(self, X: pd.DataFrame) -> pd.DataFrame:
        """Ensure feature order matches training, fill missing with 0."""
        if not self._feature_names:
            return X

        missing = [f for f in self._feature_names if f not in X.columns]
        if missing:
            for m in missing:
                X = X.copy()
                X[m] = 0.0

        return X[self._feature_names]

    @staticmethod
    def _auto_label(X: pd.DataFrame) -> pd.Series:
        """
        Rule-based regime labeling from features.
        Used when ground-truth labels are unavailable.

        Rules (priority order):
            VOLATILE : realized_vol_20 high AND vol_ratio_5_20 > 1.5
            SQUEEZE  : vol_percentile_60 < 20 AND adx_14 < 20
            TRENDING : adx_14 > 25 AND abs(h1_trend) > 0
            RANGING  : default
        """
        n   = len(X)
        lbl = np.ones(n, dtype=int) * REGIME_RANGING  # default: RANGING

        # Safely get columns (with fallback)
        adx     = X.get("adx_14",          pd.Series(np.zeros(n))).values
        vol_r   = X.get("vol_ratio_5_20",  pd.Series(np.ones(n))).values
        vol_p   = X.get("vol_percentile_60", pd.Series(np.full(n, 50.0))).values
        h1_t    = X.get("h1_trend",         pd.Series(np.zeros(n))).values
        rv      = X.get("realized_vol_20",  pd.Series(np.zeros(n))).values

        # Thresholds
        rv_thresh = np.percentile(rv[~np.isnan(rv)], 70) if rv.any() else 0.01

        for i in range(n):
            if vol_r[i] > 1.5 and rv[i] > rv_thresh:
                lbl[i] = REGIME_VOLATILE
            elif vol_p[i] < 20 and adx[i] < 20:
                lbl[i] = REGIME_SQUEEZE
            elif adx[i] > 25 and abs(h1_t[i]) > 0:
                lbl[i] = REGIME_TRENDING
            # else: RANGING (default)

        return pd.Series(lbl, index=X.index)

    @staticmethod
    def _default_result() -> Dict:
        return {
            "regime":      REGIME_RANGING,
            "regime_name": "RANGING",
            "confidence":  0.25,
            "proba":       {n: 0.25 for n in REGIME_NAMES.values()},
            "trained":     False
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
    print("RandomForestModel — Self Test")
    print("=" * 60)

    np.random.seed(42)
    n = 600
    dates = pd.date_range("2025-01-01", periods=n, freq="1min", tz="UTC")
    price = 2000.0 + np.cumsum(np.random.randn(n) * 0.5)

    df = pd.DataFrame({
        "open":   price + np.random.randn(n) * 0.1,
        "high":   price + np.abs(np.random.randn(n) * 0.3),
        "low":    price - np.abs(np.random.randn(n) * 0.3),
        "close":  price,
        "volume": np.random.randint(100, 1000, n).astype(float)
    }, index=dates)

    fe = FeatureEngineer()
    X  = fe.compute(df)
    print(f"Features: {X.shape}")

    rf = RandomForestModel(model_path="/tmp/rf_test.pkl")

    # Train
    metrics = rf.train(X, validate=True)
    print(f"\nTraining metrics:")
    for k, v in metrics.items():
        print(f"  {k}: {v}")

    # Predict latest bar
    result = rf.predict(X)
    print(f"\nLatest bar prediction:")
    for k, v in result.items():
        print(f"  {k}: {v}")

    # Feature importance
    fi = rf.get_feature_importance(top_n=5)
    print(f"\nTop-5 feature importances:")
    for feat, imp in fi.items():
        print(f"  {feat}: {imp:.4f}")

    # Save / Load
    rf.save()
    rf2 = RandomForestModel(model_path="/tmp/rf_test.pkl")
    rf2.load()
    result2 = rf2.predict(X)
    print(f"\nAfter load — regime: {result2['regime_name']} "
          f"(conf={result2['confidence']:.3f})")

    print("\n✅ RandomForestModel Test PASSED")
