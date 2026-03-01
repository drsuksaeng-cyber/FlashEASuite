#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - KMeans Model
Pattern clustering เพื่อระบุ market state ที่ทำกำไรได้

Logic:
    1. Cluster price patterns into K groups
    2. Label each cluster as "profitable" or "unprofitable" 
       based on historical forward returns
    3. Predict: ถ้าสภาวะปัจจุบันคล้าย profitable cluster → confidence สูง

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
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score

logger = logging.getLogger(__name__)

# Features used for pattern clustering
CLUSTER_FEATURES = [
    "ret_1", "ret_5", "momentum_5", "momentum_15",
    "rsi_14", "bb_pct", "macd_hist",
    "adx_14", "atr_14", "vol_ratio_5_20",
    "volume_ma_ratio", "stoch_k", "high_low_range"
]


class KMeansModel:
    """
    KMeans clustering for market pattern identification.

    Identifies "profitable states" = clusters where mean forward return > threshold.

    predict() returns:
        - cluster_id       : current cluster assignment
        - is_profitable    : bool (cluster historically profitable)
        - profitability    : float 0.0-1.0 (normalized profit score)
        - confidence       : float 0.0-1.0 (distance-based, closer center = higher conf)
        - nearest_distance : float (distance to cluster center)
    """

    def __init__(self,
                 n_clusters: int = 8,
                 use_pca: bool = True,
                 pca_components: int = 6,
                 model_path: str = "models/kmeans_pattern.pkl"):
        """
        Args:
            n_clusters     : number of clusters (auto-optimized if 0)
            use_pca        : dimensionality reduction before clustering
            pca_components : PCA dimensions
            model_path     : model save path
        """
        self.n_clusters     = n_clusters
        self.use_pca        = use_pca
        self.pca_components = pca_components
        self.model_path     = model_path

        self._trained          = False
        self._scaler           = StandardScaler()
        self._pca              = PCA(n_components=pca_components) if use_pca else None
        self._kmeans           = None
        self._cluster_profits  : Dict[int, float] = {}  # cluster_id → mean forward return
        self._profit_threshold : float = 0.0
        self._max_distance     : float = 1.0
        self._feature_names    : List[str] = []
        self._silhouette_score : float = 0.0

        logger.info("KMeansModel initialized (k=%d, pca=%s)", n_clusters, use_pca)

    # ─────────────────────────────────────────────────────────────────────────
    # TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def train(self, X: pd.DataFrame,
              forward_bars: int = 10,
              profit_threshold: float = 0.0) -> Dict:
        """
        Cluster patterns and label profitable clusters.

        Args:
            X                 : Feature DataFrame
            forward_bars      : bars ahead to measure actual return
            profit_threshold  : min mean return to be "profitable" (0=above avg)

        Returns:
            dict with training metrics
        """
        # ── Select and prepare features ───────────────────────────────────────
        feat_cols = [c for c in CLUSTER_FEATURES if c in X.columns]
        if not feat_cols:
            feat_cols = list(X.columns[:min(10, len(X.columns))])

        self._feature_names = feat_cols
        X_sel = X[feat_cols].dropna()

        if len(X_sel) < self.n_clusters * 10:
            return {"error": f"Need ≥ {self.n_clusters * 10} samples, got {len(X_sel)}"}

        # ── Scale ─────────────────────────────────────────────────────────────
        X_scaled = self._scaler.fit_transform(X_sel)

        # ── Optional PCA ──────────────────────────────────────────────────────
        if self.use_pca and self._pca:
            n_comp = min(self.pca_components, X_scaled.shape[1])
            self._pca = PCA(n_components=n_comp)
            X_input = self._pca.fit_transform(X_scaled)
            logger.info("PCA: %d → %d dims (explained=%.2f)",
                        X_scaled.shape[1], n_comp,
                        float(self._pca.explained_variance_ratio_.sum()))
        else:
            X_input = X_scaled

        # ── Auto-tune K if n_clusters=0 ───────────────────────────────────────
        if self.n_clusters == 0:
            self.n_clusters = self._find_optimal_k(X_input)
            logger.info("Optimal K found: %d", self.n_clusters)

        # ── KMeans clustering ─────────────────────────────────────────────────
        self._kmeans = KMeans(
            n_clusters=self.n_clusters,
            init="k-means++",
            n_init=10,
            max_iter=300,
            random_state=42
        )
        labels = self._kmeans.fit_predict(X_input)

        # ── Silhouette score ──────────────────────────────────────────────────
        if len(np.unique(labels)) > 1:
            self._silhouette_score = float(
                silhouette_score(X_input, labels, sample_size=min(2000, len(X_input)))
            )

        # ── Label profitable clusters ─────────────────────────────────────────
        self._cluster_profits = self._label_clusters(
            X_sel, labels, forward_bars, profit_threshold
        )

        # ── Max distance for normalization ────────────────────────────────────
        centers   = self._kmeans.cluster_centers_
        distances = np.linalg.norm(X_input - centers[labels], axis=1)
        self._max_distance = float(distances.max()) or 1.0

        # Set profit threshold (default = mean profit)
        profits = list(self._cluster_profits.values())
        self._profit_threshold = profit_threshold if profit_threshold != 0 else float(np.mean(profits))

        self._trained = True
        n_profitable  = sum(1 for v in self._cluster_profits.values()
                            if v > self._profit_threshold)

        logger.info("KMeans trained: k=%d, silhouette=%.3f, "
                    "profitable_clusters=%d/%d",
                    self.n_clusters, self._silhouette_score,
                    n_profitable, self.n_clusters)

        return {
            "n_clusters":       self.n_clusters,
            "silhouette_score": self._silhouette_score,
            "n_profitable":     n_profitable,
            "cluster_profits":  self._cluster_profits,
            "profit_threshold": self._profit_threshold,
            "n_samples":        len(X_sel)
        }

    # ─────────────────────────────────────────────────────────────────────────
    # INFERENCE
    # ─────────────────────────────────────────────────────────────────────────

    def predict(self, X: pd.DataFrame) -> Dict:
        """
        Predict cluster membership for latest bar.

        Returns:
            {
                "cluster_id":       int
                "is_profitable":    bool
                "profitability":    float (0.0-1.0)
                "confidence":       float (0.0-1.0, distance-based)
                "nearest_distance": float
                "trained":          bool
            }
        """
        if not self._trained:
            return self._default_result()

        row = X.iloc[[-1]]

        # Select features
        feat_cols = [c for c in self._feature_names if c in row.columns]
        X_sel     = row[feat_cols].fillna(0)

        # Scale → PCA → cluster
        X_scaled  = self._scaler.transform(X_sel)
        X_input   = self._pca.transform(X_scaled) if (self.use_pca and self._pca) else X_scaled

        cluster_id = int(self._kmeans.predict(X_input)[0])
        center     = self._kmeans.cluster_centers_[cluster_id]
        distance   = float(np.linalg.norm(X_input[0] - center))

        # Profitability score
        profit       = self._cluster_profits.get(cluster_id, 0.0)
        all_profits  = list(self._cluster_profits.values())
        p_min, p_max = min(all_profits), max(all_profits)
        if p_max > p_min:
            profitability = (profit - p_min) / (p_max - p_min)
        else:
            profitability = 0.5

        is_profitable = profit > self._profit_threshold

        # Confidence: inverse distance normalized (closer = more confident)
        norm_dist  = distance / (self._max_distance + 1e-10)
        confidence = float(max(0.0, 1.0 - norm_dist))
        # Weight by profitability
        confidence *= profitability if is_profitable else (1.0 - profitability)

        return {
            "cluster_id":       cluster_id,
            "is_profitable":    is_profitable,
            "profitability":    float(profitability),
            "confidence":       float(min(1.0, confidence)),
            "nearest_distance": distance,
            "cluster_profit":   profit,
            "trained":          True
        }

    # ─────────────────────────────────────────────────────────────────────────
    # PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def save(self, path: Optional[str] = None) -> str:
        path = path or self.model_path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        payload = {
            "kmeans":           self._kmeans,
            "scaler":           self._scaler,
            "pca":              self._pca,
            "cluster_profits":  self._cluster_profits,
            "profit_threshold": self._profit_threshold,
            "max_distance":     self._max_distance,
            "feature_names":    self._feature_names,
            "silhouette":       self._silhouette_score,
            "trained":          self._trained
        }
        with open(path, "wb") as f:
            pickle.dump(payload, f)
        logger.info("KMeans model saved → %s", path)
        return path

    def load(self, path: Optional[str] = None) -> bool:
        path = path or self.model_path
        if not os.path.exists(path):
            logger.warning("KMeans model not found: %s", path)
            return False
        with open(path, "rb") as f:
            p = pickle.load(f)
        self._kmeans           = p["kmeans"]
        self._scaler           = p["scaler"]
        self._pca              = p["pca"]
        self._cluster_profits  = p["cluster_profits"]
        self._profit_threshold = p["profit_threshold"]
        self._max_distance     = p["max_distance"]
        self._feature_names    = p["feature_names"]
        self._silhouette_score = p["silhouette"]
        self._trained          = p["trained"]
        logger.info("KMeans model loaded ← %s", path)
        return True

    # ─────────────────────────────────────────────────────────────────────────
    # INTERNALS
    # ─────────────────────────────────────────────────────────────────────────

    def _label_clusters(self, X_sel: pd.DataFrame,
                        labels: np.ndarray,
                        forward_bars: int,
                        threshold: float) -> Dict[int, float]:
        """Compute mean forward return per cluster."""
        if "ret_1" in X_sel.columns:
            future_ret = X_sel["ret_1"].shift(-forward_bars).fillna(0).values
        else:
            future_ret = np.zeros(len(X_sel))

        profits = {}
        for k in range(self.n_clusters):
            mask = labels == k
            if mask.sum() > 0:
                profits[k] = float(future_ret[mask].mean())
            else:
                profits[k] = 0.0

        return profits

    @staticmethod
    def _find_optimal_k(X: np.ndarray,
                        k_range: Tuple[int, int] = (4, 12)) -> int:
        """Elbow method + silhouette to find optimal K."""
        best_k, best_s = k_range[0], -1.0

        for k in range(k_range[0], k_range[1] + 1):
            km = KMeans(n_clusters=k, init="k-means++", n_init=5,
                        max_iter=100, random_state=42)
            lbl = km.fit_predict(X)
            if len(np.unique(lbl)) < 2:
                continue
            s = float(silhouette_score(X, lbl, sample_size=min(1000, len(X))))
            if s > best_s:
                best_s, best_k = s, k

        return best_k

    @staticmethod
    def _default_result() -> Dict:
        return {
            "cluster_id":       0,
            "is_profitable":    False,
            "profitability":    0.5,
            "confidence":       0.0,
            "nearest_distance": 999.0,
            "cluster_profit":   0.0,
            "trained":          False
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
    print("KMeansModel — Self Test")
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
    print(f"Features: {X.shape}")

    km = KMeansModel(n_clusters=8, model_path="/tmp/km_test.pkl")

    metrics = km.train(X)
    print(f"\nTraining metrics:")
    for k, v in metrics.items():
        if k != "cluster_profits":
            print(f"  {k}: {v}")

    result = km.predict(X)
    print(f"\nLatest bar prediction:")
    for k, v in result.items():
        print(f"  {k}: {v}")

    km.save()
    km2 = KMeansModel(model_path="/tmp/km_test.pkl")
    km2.load()
    r2 = km2.predict(X)
    print(f"\nAfter load: cluster={r2['cluster_id']}, "
          f"profitable={r2['is_profitable']}, conf={r2['confidence']:.3f}")

    print("\n✅ KMeansModel Test PASSED")
