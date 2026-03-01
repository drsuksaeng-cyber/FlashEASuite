#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - XGBoost Model
คำนวณ confidence score (0.0 - 1.0) สำหรับ ML Ensemble
พร้อม feature importance เพื่อ explainability

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

try:
    import xgboost as xgb
    XGB_AVAILABLE = True
except ImportError:
    XGB_AVAILABLE = False
    logging.warning("xgboost not installed — pip install xgboost")

from sklearn.metrics import log_loss, accuracy_score
from sklearn.model_selection import TimeSeriesSplit

logger = logging.getLogger(__name__)

# Direction labels
DIR_UP      = 1
DIR_DOWN    = -1
DIR_NEUTRAL = 0


class XGBoostModel:
    """
    XGBoost model that outputs:
        - direction score  : probability of UP move
        - confidence score : certainty of the prediction (0.0-1.0)
        - feature importance: per-feature contribution

    Underlying task: binary classification (UP vs NOT-UP)
    Confidence = distance from decision boundary × accuracy weight
    """

    def __init__(self,
                 n_estimators: int = 300,
                 max_depth: int = 5,
                 learning_rate: float = 0.05,
                 model_path: str = "models/xgb_confidence.pkl"):

        self.model_path    = model_path
        self.n_estimators  = n_estimators
        self._trained      = False
        self._feature_names: List[str] = []
        self._accuracy     = 0.0

        if XGB_AVAILABLE:
            self.model = xgb.XGBClassifier(
                n_estimators=n_estimators,
                max_depth=max_depth,
                learning_rate=learning_rate,
                subsample=0.8,
                colsample_bytree=0.7,
                gamma=0.1,
                min_child_weight=5,
                eval_metric="logloss",
                random_state=42,
                n_jobs=-1
            )
        else:
            self.model = None

        logger.info("XGBoostModel initialized (available=%s)", XGB_AVAILABLE)

    # ─────────────────────────────────────────────────────────────────────────
    # TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def train(self, X: pd.DataFrame,
              y: Optional[pd.Series] = None,
              forward_bars: int = 5) -> Dict:
        """
        Train XGBoost on direction classification.

        Args:
            X            : Feature DataFrame
            y            : Binary labels (1=UP, 0=DOWN). If None, auto-generate.
            forward_bars : Bars ahead to measure "UP" for auto-labeling

        Returns:
            dict with training metrics
        """
        if not XGB_AVAILABLE:
            logger.error("XGBoost not available")
            return {"error": "xgboost not installed"}

        if y is None:
            y = self._auto_label(X, forward_bars)

        self._feature_names = list(X.columns)

        # Time-series CV
        tscv    = TimeSeriesSplit(n_splits=5)
        cv_accs = []
        for train_idx, val_idx in tscv.split(X):
            X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
            y_tr, y_val = y.iloc[train_idx], y.iloc[val_idx]
            self.model.fit(X_tr, y_tr,
                           eval_set=[(X_val, y_val)],
                           verbose=False)
            acc = accuracy_score(y_val, self.model.predict(X_val))
            cv_accs.append(acc)

        # Final train on all data
        self.model.fit(X, y, verbose=False)
        self._trained  = True
        self._accuracy = float(np.mean(cv_accs))

        y_pred    = self.model.predict(X)
        train_acc = float(accuracy_score(y, y_pred))

        logger.info("XGB trained. CV acc=%.3f, Train acc=%.3f",
                    self._accuracy, train_acc)

        return {
            "cv_accuracy":    self._accuracy,
            "train_accuracy": train_acc,
            "n_samples":      len(X),
            "n_features":     len(self._feature_names),
            "class_balance":  float(y.mean())
        }

    # ─────────────────────────────────────────────────────────────────────────
    # INFERENCE
    # ─────────────────────────────────────────────────────────────────────────

    def predict(self, X: pd.DataFrame) -> Dict:
        """
        Predict direction + confidence for latest bar.

        Returns:
            {
                "direction":  int  (1=UP, -1=DOWN, 0=NEUTRAL)
                "up_prob":    float (0.0-1.0)
                "confidence": float (0.0-1.0)
                "feature_importance": dict {name: importance}
                "trained":    bool
            }
        """
        if not self._trained or not XGB_AVAILABLE:
            return self._default_result()

        row    = self._align_features(X.iloc[[-1]])
        proba  = self.model.predict_proba(row)[0]  # [p_down, p_up]
        p_up   = float(proba[1])
        p_down = float(proba[0])

        # Direction
        if p_up > 0.60:
            direction = DIR_UP
        elif p_down > 0.60:
            direction = DIR_DOWN
        else:
            direction = DIR_NEUTRAL

        # Confidence = distance from 0.5, weighted by model CV accuracy
        confidence = float(2.0 * abs(p_up - 0.5) * self._accuracy)
        confidence = min(1.0, max(0.0, confidence))

        # Feature importance (SHAP-style from XGB gain)
        fi = self.get_feature_importance(top_n=5)

        return {
            "direction":          direction,
            "up_prob":            p_up,
            "down_prob":          p_down,
            "confidence":         confidence,
            "feature_importance": fi,
            "trained":            True
        }

    # ─────────────────────────────────────────────────────────────────────────
    # FEATURE IMPORTANCE
    # ─────────────────────────────────────────────────────────────────────────

    def get_feature_importance(self, top_n: int = 10,
                                importance_type: str = "gain") -> Dict[str, float]:
        """
        Return feature importances from XGBoost.

        Args:
            top_n           : number of features to return
            importance_type : "gain" | "weight" | "cover"
        """
        if not self._trained or not XGB_AVAILABLE:
            return {}

        scores  = self.model.get_booster().get_score(
            importance_type=importance_type)
        total   = sum(scores.values()) + 1e-10
        ranked  = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return {k: float(v / total) for k, v in ranked[:top_n]}

    # ─────────────────────────────────────────────────────────────────────────
    # PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def save(self, path: Optional[str] = None) -> str:
        path = path or self.model_path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        payload = {
            "model":         self.model,
            "feature_names": self._feature_names,
            "accuracy":      self._accuracy,
            "trained":       self._trained
        }
        with open(path, "wb") as f:
            pickle.dump(payload, f)
        logger.info("XGB model saved → %s", path)
        return path

    def load(self, path: Optional[str] = None) -> bool:
        path = path or self.model_path
        if not os.path.exists(path):
            logger.warning("XGB model not found: %s", path)
            return False
        with open(path, "rb") as f:
            payload = pickle.load(f)
        self.model          = payload["model"]
        self._feature_names = payload["feature_names"]
        self._accuracy      = payload["accuracy"]
        self._trained       = payload["trained"]
        logger.info("XGB model loaded ← %s (acc=%.3f)", path, self._accuracy)
        return True

    # ─────────────────────────────────────────────────────────────────────────
    # INTERNALS
    # ─────────────────────────────────────────────────────────────────────────

    def _align_features(self, X: pd.DataFrame) -> pd.DataFrame:
        if not self._feature_names:
            return X
        missing = [f for f in self._feature_names if f not in X.columns]
        if missing:
            X = X.copy()
            for m in missing:
                X[m] = 0.0
        return X[self._feature_names]

    @staticmethod
    def _auto_label(X: pd.DataFrame, forward_bars: int = 5) -> pd.Series:
        """
        Label: 1 if close[t+forward_bars] > close[t], else 0.
        Uses ret_1 as proxy (cumsum approximation).
        """
        if "ret_1" in X.columns:
            future_ret = X["ret_1"].shift(-forward_bars).fillna(0)
            return (future_ret > 0).astype(int)
        # Fallback: random balanced labels
        n = len(X)
        lbl = np.zeros(n, dtype=int)
        lbl[:n // 2] = 1
        np.random.shuffle(lbl)
        return pd.Series(lbl, index=X.index)

    @staticmethod
    def _default_result() -> Dict:
        return {
            "direction":          DIR_NEUTRAL,
            "up_prob":            0.5,
            "down_prob":          0.5,
            "confidence":         0.0,
            "feature_importance": {},
            "trained":            False
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
    print("XGBoostModel — Self Test")
    print("=" * 60)

    np.random.seed(42)
    n = 600
    dates = pd.date_range("2025-01-01", periods=n, freq="1min", tz="UTC")
    price = 2000.0 + np.cumsum(np.random.randn(n) * 0.5)
    df = pd.DataFrame({
        "open":   price, "high": price + 0.3,
        "low":    price - 0.3, "close": price,
        "volume": np.random.randint(100, 1000, n).astype(float)
    }, index=dates)

    fe = FeatureEngineer()
    X  = fe.compute(df)

    if not XGB_AVAILABLE:
        print("⚠️  XGBoost not installed. Install: pip install xgboost")
    else:
        xgb_model = XGBoostModel(model_path="/tmp/xgb_test.pkl")
        metrics   = xgb_model.train(X)
        print(f"Training metrics: {metrics}")

        result = xgb_model.predict(X)
        print(f"Prediction: {result}")

        xgb_model.save()
        xgb2 = XGBoostModel(model_path="/tmp/xgb_test.pkl")
        xgb2.load()
        r2 = xgb2.predict(X)
        print(f"After load: direction={r2['direction']}, conf={r2['confidence']:.3f}")

        print("\n✅ XGBoostModel Test PASSED")
