#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Model Trainer
Training pipeline สำหรับ ML Ensemble (5 models)

Training schedule:
    - Initial train : 6 months historical data
    - Weekly retrain: rolling 3-month window
    - Auto-retrain  : accuracy drops below 60% for 2 consecutive weeks

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-22
"""

import numpy as np
import pandas as pd
import os
import json
import logging
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple
from pathlib import Path

from feature_engineering import FeatureEngineer
from random_forest_model import RandomForestModel
from xgboost_model import XGBoostModel
from lstm_model import LSTMModel
from kmeans_model import KMeansModel
from hmm_model import HMMModel

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
INITIAL_TRAIN_MONTHS = 6
RETRAIN_WINDOW_MONTHS = 3
MIN_ACCURACY_THRESHOLD = 0.60    # trigger auto-retrain below this
CONSECUTIVE_FAILS_THRESHOLD = 2  # consecutive weeks below threshold


class ModelTrainer:
    """
    Orchestrates training and retraining of all 5 ML models.

    Responsibilities:
        1. Load historical OHLCV data
        2. Build features via FeatureEngineer
        3. Train/retrain RF, XGBoost, LSTM, KMeans, HMM
        4. Track accuracy metrics
        5. Auto-retrain when accuracy drops
        6. Save trained models to disk

    Data source:
        - Accepts DataFrame directly OR reads from InfluxDB via data_loader callback
        - Symbol-specific model files
    """

    def __init__(self,
                 model_dir: str = "models",
                 symbol: str = "XAUUSD",
                 data_loader_fn=None):
        """
        Args:
            model_dir      : directory to save all model files
            symbol         : trading symbol (used in file names)
            data_loader_fn : callable(symbol, start, end) → DataFrame
                             If None, must pass data to train() directly
        """
        self.model_dir      = Path(model_dir)
        self.symbol         = symbol
        self.data_loader_fn = data_loader_fn

        # Create directories
        self.model_dir.mkdir(parents=True, exist_ok=True)

        # ── Component instances ───────────────────────────────────────────────
        self.fe      = FeatureEngineer(normalize=False)
        self.fe_norm = FeatureEngineer(normalize=True)   # for LSTM + KMeans

        sym = symbol.upper()
        self.rf    = RandomForestModel(model_path=str(self.model_dir / f"rf_{sym}.pkl"))
        self.xgb   = XGBoostModel(model_path=str(self.model_dir / f"xgb_{sym}.pkl"))
        self.lstm  = LSTMModel(model_path=str(self.model_dir / f"lstm_{sym}.pkl"))
        self.km    = KMeansModel(model_path=str(self.model_dir / f"km_{sym}.pkl"))
        self.hmm   = HMMModel(model_path=str(self.model_dir / f"hmm_{sym}.pkl"))

        # ── Training state ─────────────────────────────────────────────────
        self._training_history: List[Dict] = []  # log of all training runs
        self._consecutive_fails: int = 0
        self._last_retrain: Optional[datetime] = None
        self._is_training: bool = False
        self._lock = threading.Lock()

        # ── Load existing metrics ─────────────────────────────────────────────
        self._load_training_history()

        logger.info("ModelTrainer initialized for %s (dir=%s)", symbol, model_dir)

    # ─────────────────────────────────────────────────────────────────────────
    # MAIN TRAIN / RETRAIN
    # ─────────────────────────────────────────────────────────────────────────

    def train_all(self, df: Optional[pd.DataFrame] = None,
                  months: int = INITIAL_TRAIN_MONTHS,
                  fast_mode: bool = False) -> Dict:
        """
        Train all 5 models on historical data.

        Args:
            df        : OHLCV DataFrame. If None, loads via data_loader_fn.
            months    : months of data to use
            fast_mode : reduce epochs/estimators for quick testing

        Returns:
            dict with per-model training results
        """
        with self._lock:
            if self._is_training:
                logger.warning("Training already in progress — skipping")
                return {"status": "already_training"}
            self._is_training = True

        try:
            start_time = time.time()
            logger.info("="*60)
            logger.info("Starting full model training: %s", self.symbol)
            logger.info("="*60)

            # ── Load data ─────────────────────────────────────────────────────
            if df is None:
                df = self._load_data(months)
                if df is None or df.empty:
                    return {"error": "No data available"}

            logger.info("Data loaded: %d rows, %s → %s",
                        len(df), df.index[0], df.index[-1])

            # ── Feature engineering ───────────────────────────────────────────
            logger.info("Computing features...")
            X         = self.fe.compute(df)         # for RF, XGBoost, HMM
            X_norm    = self.fe_norm.compute(df)     # for LSTM, KMeans

            logger.info("Features ready: %d rows × %d cols", len(X), len(X.columns))

            results = {}

            # ── 1. Random Forest ──────────────────────────────────────────────
            logger.info("[1/5] Training Random Forest...")
            n_est = 50 if fast_mode else 200
            self.rf.clf.n_estimators = n_est
            rf_metrics = self.rf.train(X, validate=not fast_mode)
            self.rf.save()
            results["random_forest"] = rf_metrics
            logger.info("RF done. CV acc=%.3f", rf_metrics.get("cv_accuracy_mean", 0))

            # ── 2. XGBoost ────────────────────────────────────────────────────
            logger.info("[2/5] Training XGBoost...")
            xgb_metrics = self.xgb.train(X)
            self.xgb.save()
            results["xgboost"] = xgb_metrics
            logger.info("XGB done. CV acc=%.3f", xgb_metrics.get("cv_accuracy", 0))

            # ── 3. LSTM ───────────────────────────────────────────────────────
            logger.info("[3/5] Training LSTM...")
            epochs = 5 if fast_mode else 50
            lstm_metrics = self.lstm.train(X_norm, epochs=epochs, batch_size=32)
            self.lstm.save()
            results["lstm"] = lstm_metrics
            logger.info("LSTM done. Val acc=%.3f", lstm_metrics.get("val_accuracy", 0))

            # ── 4. KMeans ─────────────────────────────────────────────────────
            logger.info("[4/5] Training KMeans...")
            km_metrics = self.km.train(X_norm)
            self.km.save()
            results["kmeans"] = km_metrics
            logger.info("KMeans done. k=%d, silhouette=%.3f",
                        km_metrics.get("n_clusters", 0),
                        km_metrics.get("silhouette_score", 0))

            # ── 5. HMM ────────────────────────────────────────────────────────
            logger.info("[5/5] Training HMM...")
            hmm_metrics = self.hmm.train(X)
            self.hmm.save()
            results["hmm"] = hmm_metrics
            logger.info("HMM done. LogL=%.2f", hmm_metrics.get("log_likelihood", -999))

            # ── Summary ───────────────────────────────────────────────────────
            elapsed = time.time() - start_time
            overall_acc = self._compute_overall_accuracy(results)

            run_record = {
                "timestamp":    datetime.now(timezone.utc).isoformat(),
                "symbol":       self.symbol,
                "data_rows":    len(df),
                "elapsed_sec":  round(elapsed, 1),
                "overall_acc":  overall_acc,
                "results":      results
            }

            self._training_history.append(run_record)
            self._save_training_history()
            self._last_retrain = datetime.now(timezone.utc)
            self._consecutive_fails = 0

            logger.info("="*60)
            logger.info("Training complete in %.1fs. Overall acc=%.3f",
                        elapsed, overall_acc)
            logger.info("="*60)

            return {
                "status":       "success",
                "symbol":       self.symbol,
                "overall_acc":  overall_acc,
                "elapsed_sec":  elapsed,
                "models":       results
            }

        except Exception as e:
            logger.error("Training failed: %s", e, exc_info=True)
            return {"status": "error", "error": str(e)}

        finally:
            with self._lock:
                self._is_training = False

    def retrain_rolling(self, df: Optional[pd.DataFrame] = None,
                        months: int = RETRAIN_WINDOW_MONTHS) -> Dict:
        """
        Weekly retrain on rolling 3-month window.

        Args:
            df     : fresh OHLCV data. If None, loads via data_loader_fn.
            months : rolling window in months

        Returns:
            dict with retrain results
        """
        logger.info("Rolling retrain: %s (window=%dm)", self.symbol, months)
        return self.train_all(df=df, months=months, fast_mode=False)

    # ─────────────────────────────────────────────────────────────────────────
    # AUTO-RETRAIN MONITORING
    # ─────────────────────────────────────────────────────────────────────────

    def check_and_retrain(self, current_accuracy: float) -> bool:
        """
        Check if auto-retrain is needed.

        Called weekly by the scheduler.

        Args:
            current_accuracy : last week's measured accuracy (0.0-1.0)

        Returns:
            True if retrain was triggered
        """
        if current_accuracy < MIN_ACCURACY_THRESHOLD:
            self._consecutive_fails += 1
            logger.warning("Accuracy %.3f below threshold %.3f (fail %d/%d)",
                           current_accuracy, MIN_ACCURACY_THRESHOLD,
                           self._consecutive_fails, CONSECUTIVE_FAILS_THRESHOLD)
        else:
            self._consecutive_fails = 0

        if self._consecutive_fails >= CONSECUTIVE_FAILS_THRESHOLD:
            logger.warning("Auto-retrain triggered!")
            result = self.retrain_rolling()
            return result.get("status") == "success"

        return False

    def schedule_weekly_retrain(self, interval_days: int = 7) -> None:
        """
        Start background thread for weekly auto-retrain.
        Non-blocking.
        """
        def _scheduler():
            while True:
                time.sleep(interval_days * 86400)
                logger.info("Scheduled retrain starting...")
                self.retrain_rolling()

        t = threading.Thread(target=_scheduler, daemon=True, name="WeeklyRetrain")
        t.start()
        logger.info("Weekly retrain scheduler started (interval=%dd)", interval_days)

    # ─────────────────────────────────────────────────────────────────────────
    # MODEL LOADING (for inference)
    # ─────────────────────────────────────────────────────────────────────────

    def load_all_models(self) -> Dict[str, bool]:
        """Load all trained models from disk."""
        results = {
            "rf":    self.rf.load(),
            "xgb":   self.xgb.load(),
            "lstm":  self.lstm.load(),
            "kmeans": self.km.load(),
            "hmm":   self.hmm.load()
        }
        n_loaded = sum(results.values())
        logger.info("Models loaded: %d/5", n_loaded)
        return results

    def are_models_ready(self) -> bool:
        """Check if all models are trained and ready for inference."""
        return all([
            self.rf._trained,
            self.xgb._trained,
            self.lstm._trained,
            self.km._trained,
            self.hmm._trained
        ])

    # ─────────────────────────────────────────────────────────────────────────
    # METRICS & HISTORY
    # ─────────────────────────────────────────────────────────────────────────

    def get_model_accuracies(self) -> Dict[str, float]:
        """Return current accuracy of each model."""
        return {
            "rf":    self.rf._accuracy,
            "xgb":   self.xgb._accuracy,
            "lstm":  self.lstm._accuracy,
            "hmm":   0.5,  # HMM uses log-likelihood, not accuracy
            "kmeans": self.km._silhouette_score
        }

    def get_training_summary(self) -> Dict:
        """Return last training run summary."""
        if not self._training_history:
            return {"message": "No training history"}
        last = self._training_history[-1]
        return {
            "last_retrain":     last["timestamp"],
            "overall_accuracy": last["overall_acc"],
            "data_rows":        last["data_rows"],
            "elapsed_sec":      last["elapsed_sec"],
            "n_retrain_runs":   len(self._training_history)
        }

    # ─────────────────────────────────────────────────────────────────────────
    # BACK-TEST ACCURACY
    # ─────────────────────────────────────────────────────────────────────────

    def measure_accuracy(self, df: pd.DataFrame,
                          forward_bars: int = 5) -> Dict[str, float]:
        """
        Measure prediction accuracy of trained models on held-out data.

        Used to compute current_accuracy for check_and_retrain().

        Args:
            df           : OHLCV data for evaluation
            forward_bars : bars ahead for true label

        Returns:
            dict {model_name: accuracy}
        """
        X = self.fe.compute(df)

        # True directions (UP=1 / DOWN=0)
        fut_ret    = X["ret_1"].shift(-forward_bars).fillna(0) if "ret_1" in X.columns else pd.Series(0, index=X.index)
        y_true_bin = (fut_ret > 0).astype(int)

        accuracies: Dict[str, float] = {}

        # RF: predict direction from regime
        if self.rf._trained:
            reg_df = self.rf.predict_series(X)
            # TRENDING → UP signal
            rf_pred = (reg_df["regime"] == 0).astype(int)
            acc = float((rf_pred.values == y_true_bin.values).mean())
            accuracies["rf"] = acc

        # XGBoost: direct direction prediction
        if self.xgb._trained and self.xgb._trained:
            from sklearn.metrics import accuracy_score as _acc
            try:
                X_al = self.xgb._align_features(X)
                preds = self.xgb.model.predict(X_al)
                accuracies["xgb"] = float(_acc(y_true_bin, preds))
            except Exception:
                accuracies["xgb"] = 0.5

        # Average accuracy
        if accuracies:
            accuracies["overall"] = float(np.mean(list(accuracies.values())))

        return accuracies

    # ─────────────────────────────────────────────────────────────────────────
    # INTERNALS
    # ─────────────────────────────────────────────────────────────────────────

    def _load_data(self, months: int) -> Optional[pd.DataFrame]:
        """Load OHLCV data via data_loader_fn."""
        if self.data_loader_fn is None:
            logger.warning("No data_loader_fn — cannot load data automatically")
            return None

        end   = datetime.now(timezone.utc)
        start = end - timedelta(days=months * 30)

        try:
            df = self.data_loader_fn(self.symbol, start, end)
            return df
        except Exception as e:
            logger.error("Data load error: %s", e)
            return None

    @staticmethod
    def _compute_overall_accuracy(results: Dict) -> float:
        """Weighted average accuracy across models."""
        accs = []

        rf_acc  = results.get("random_forest", {}).get("cv_accuracy_mean", 0)
        xgb_acc = results.get("xgboost", {}).get("cv_accuracy", 0)
        lstm_acc = results.get("lstm", {}).get("val_accuracy", 0)

        for acc in [rf_acc, xgb_acc, lstm_acc]:
            if acc and acc > 0:
                accs.append(float(acc))

        return float(np.mean(accs)) if accs else 0.0

    def _load_training_history(self) -> None:
        hist_path = self.model_dir / f"training_history_{self.symbol}.json"
        if hist_path.exists():
            try:
                with open(hist_path) as f:
                    self._training_history = json.load(f)
                logger.info("Loaded %d training history records",
                            len(self._training_history))
            except Exception as e:
                logger.warning("Could not load training history: %s", e)

    def _save_training_history(self) -> None:
        hist_path = self.model_dir / f"training_history_{self.symbol}.json"
        try:
            with open(hist_path, "w") as f:
                json.dump(self._training_history[-50:], f, indent=2, default=str)
        except Exception as e:
            logger.warning("Could not save training history: %s", e)


# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE TEST
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s")

    print("=" * 70)
    print("ModelTrainer — Self Test (Fast Mode)")
    print("Simulating 6-month XAUUSD data")
    print("=" * 70)

    # ── Generate synthetic 6-month M1 data ────────────────────────────────────
    np.random.seed(42)
    n = 1500  # ~1 day of M1 bars (fast test)
    dates = pd.date_range("2025-01-01", periods=n, freq="1min", tz="UTC")
    price = 2000.0 + np.cumsum(np.random.randn(n) * 0.5)

    df_test = pd.DataFrame({
        "open":   price + np.random.randn(n) * 0.1,
        "high":   price + np.abs(np.random.randn(n) * 0.3),
        "low":    price - np.abs(np.random.randn(n) * 0.3),
        "close":  price,
        "volume": np.random.randint(100, 1000, n).astype(float)
    }, index=dates)

    # ── Train ─────────────────────────────────────────────────────────────────
    trainer = ModelTrainer(model_dir="/tmp/flashea_models", symbol="XAUUSD")
    results = trainer.train_all(df=df_test, fast_mode=True)

    print("\n📊 Training Results:")
    print(f"  Status      : {results.get('status')}")
    print(f"  Overall Acc : {results.get('overall_acc', 0):.3f}")
    print(f"  Elapsed     : {results.get('elapsed_sec', 0):.1f}s")

    for model_name, m in results.get("models", {}).items():
        print(f"\n  [{model_name}]")
        for k, v in m.items():
            if not isinstance(v, dict):
                print(f"    {k}: {v}")

    # ── Load models ───────────────────────────────────────────────────────────
    trainer2 = ModelTrainer(model_dir="/tmp/flashea_models", symbol="XAUUSD")
    loaded   = trainer2.load_all_models()
    print(f"\n📂 Models loaded: {loaded}")
    print(f"   Ready for inference: {trainer2.are_models_ready()}")

    # ── Accuracy check ────────────────────────────────────────────────────────
    accs = trainer.measure_accuracy(df_test)
    print(f"\n📈 Accuracy measurement: {accs}")

    # ── Auto-retrain simulation ────────────────────────────────────────────────
    print("\n🔄 Simulating 2 consecutive accuracy failures...")
    triggered1 = trainer.check_and_retrain(0.50)  # fail
    triggered2 = trainer.check_and_retrain(0.52)  # fail → retrain!
    print(f"   Retrain triggered: {triggered2}")

    print("\n" + "=" * 70)
    print("ModelTrainer Test COMPLETE ✅")
    print("=" * 70)
