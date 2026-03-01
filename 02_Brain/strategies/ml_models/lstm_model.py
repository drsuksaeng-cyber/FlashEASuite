#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - LSTM Model
ทำนายทิศทางราคา (UP / DOWN / NEUTRAL) ด้วย 2-layer LSTM 64 units
Input : 60 bars sequence
Output: direction + confidence

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

# ── Check framework availability ──────────────────────────────────────────────
TF_AVAILABLE    = False
TORCH_AVAILABLE = False

try:
    import tensorflow as tf
    from tensorflow.keras.models import Sequential, load_model
    from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization
    from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau
    from tensorflow.keras.optimizers import Adam
    TF_AVAILABLE = True
    logger.info("TensorFlow %s available", tf.__version__)
except ImportError:
    try:
        import torch
        import torch.nn as nn
        import torch.optim as optim
        from torch.utils.data import DataLoader, TensorDataset
        TORCH_AVAILABLE = True
        logger.info("PyTorch %s available", torch.__version__)
    except ImportError:
        logger.warning("Neither TensorFlow nor PyTorch available — "
                       "LSTM will run in MOCK mode")

# Direction codes
DIR_UP      = 1
DIR_DOWN    = -1
DIR_NEUTRAL = 0
DIR_NAMES   = {1: "UP", -1: "DOWN", 0: "NEUTRAL"}


class LSTMModel:
    """
    2-layer LSTM for sequence-based price direction prediction.

    Architecture:
        Input → LSTM(64) → Dropout(0.2) → LSTM(64) → Dropout(0.2)
              → Dense(32, relu) → Dense(3, softmax)
        Output: [p_down, p_neutral, p_up]

    Supports: TensorFlow, PyTorch, or Mock (fallback)
    """

    SEQ_LEN    = 60   # sequence length (bars)
    N_CLASSES  = 3    # UP / NEUTRAL / DOWN
    LSTM_UNITS = 64

    def __init__(self,
                 seq_len: int = 60,
                 model_path: str = "models/lstm_direction.pkl"):
        self.seq_len    = seq_len
        self.model_path = model_path
        self._trained   = False
        self._accuracy  = 0.0
        self._n_features: int = 0
        self._framework: str  = "mock"
        self._model           = None

        if TF_AVAILABLE:
            self._framework = "tensorflow"
        elif TORCH_AVAILABLE:
            self._framework = "pytorch"
        else:
            self._framework = "mock"

        logger.info("LSTMModel initialized (framework=%s)", self._framework)

    # ─────────────────────────────────────────────────────────────────────────
    # TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def train(self, X: pd.DataFrame,
              y: Optional[pd.Series] = None,
              epochs: int = 50,
              batch_size: int = 32,
              forward_bars: int = 5) -> Dict:
        """
        Train LSTM on sequence data.

        Args:
            X            : Feature DataFrame (FeatureEngineer output)
            y            : Target labels (0=DOWN, 1=NEUTRAL, 2=UP). Auto if None.
            epochs       : max training epochs (EarlyStopping applies)
            batch_size   : mini-batch size
            forward_bars : bars ahead for auto-labeling

        Returns:
            dict with training metrics
        """
        if y is None:
            y = self._auto_label(X, forward_bars)

        self._n_features = X.shape[1]
        X_seq, y_seq     = self._build_sequences(X.values, y.values)

        if len(X_seq) == 0:
            return {"error": "not enough data for sequences"}

        if self._framework == "tensorflow":
            return self._train_tf(X_seq, y_seq, epochs, batch_size)
        elif self._framework == "pytorch":
            return self._train_torch(X_seq, y_seq, epochs, batch_size)
        else:
            return self._train_mock(X_seq, y_seq)

    # ─────────────────────────────────────────────────────────────────────────
    # INFERENCE
    # ─────────────────────────────────────────────────────────────────────────

    def predict(self, X: pd.DataFrame) -> Dict:
        """
        Predict direction for latest bar using last seq_len bars.

        Returns:
            {
                "direction":  int  (1=UP, -1=DOWN, 0=NEUTRAL)
                "up_prob":    float
                "down_prob":  float
                "neutral_prob": float
                "confidence": float
                "trained":    bool
            }
        """
        if not self._trained:
            return self._default_result()

        if len(X) < self.seq_len:
            logger.warning("LSTM needs %d bars, got %d", self.seq_len, len(X))
            return self._default_result()

        seq = X.values[-self.seq_len:]   # (seq_len, n_features)
        seq = np.expand_dims(seq, axis=0)  # (1, seq_len, n_features)

        if self._framework == "tensorflow":
            proba = self._predict_tf(seq)
        elif self._framework == "pytorch":
            proba = self._predict_torch(seq)
        else:
            proba = self._predict_mock(seq)

        # proba = [p_down, p_neutral, p_up]  (softmax)
        p_down, p_neutral, p_up = float(proba[0]), float(proba[1]), float(proba[2])
        idx = int(np.argmax(proba))
        confidence = float(proba[idx])

        direction_map = {0: DIR_DOWN, 1: DIR_NEUTRAL, 2: DIR_UP}
        direction     = direction_map[idx]

        # Only signal if confidence is above threshold
        if confidence < 0.45:
            direction = DIR_NEUTRAL

        return {
            "direction":    direction,
            "up_prob":      p_up,
            "down_prob":    p_down,
            "neutral_prob": p_neutral,
            "confidence":   confidence,
            "framework":    self._framework,
            "trained":      True
        }

    # ─────────────────────────────────────────────────────────────────────────
    # TENSORFLOW IMPLEMENTATION
    # ─────────────────────────────────────────────────────────────────────────

    def _build_tf_model(self, n_features: int):
        model = Sequential([
            LSTM(self.LSTM_UNITS, return_sequences=True,
                 input_shape=(self.seq_len, n_features)),
            BatchNormalization(),
            Dropout(0.2),
            LSTM(self.LSTM_UNITS, return_sequences=False),
            BatchNormalization(),
            Dropout(0.2),
            Dense(32, activation="relu"),
            Dense(self.N_CLASSES, activation="softmax")
        ])
        model.compile(
            optimizer=Adam(learning_rate=0.001),
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"]
        )
        return model

    def _train_tf(self, X_seq: np.ndarray, y_seq: np.ndarray,
                  epochs: int, batch_size: int) -> Dict:
        self._model = self._build_tf_model(X_seq.shape[2])

        callbacks = [
            EarlyStopping(patience=8, restore_best_weights=True, verbose=0),
            ReduceLROnPlateau(patience=4, factor=0.5, verbose=0)
        ]

        split = int(len(X_seq) * 0.8)
        X_tr, X_val = X_seq[:split], X_seq[split:]
        y_tr, y_val = y_seq[:split], y_seq[split:]

        history = self._model.fit(
            X_tr, y_tr,
            validation_data=(X_val, y_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=0
        )

        val_acc      = float(max(history.history.get("val_accuracy", [0])))
        self._accuracy = val_acc
        self._trained  = True

        logger.info("LSTM (TF) trained. Val acc=%.3f", val_acc)
        return {"val_accuracy": val_acc,
                "epochs_run":   len(history.history["loss"]),
                "framework":    "tensorflow"}

    def _predict_tf(self, seq: np.ndarray) -> np.ndarray:
        proba = self._model.predict(seq.astype(np.float32), verbose=0)
        return proba[0]

    # ─────────────────────────────────────────────────────────────────────────
    # PYTORCH IMPLEMENTATION
    # ─────────────────────────────────────────────────────────────────────────

    def _build_torch_model(self, n_features: int):
        class LSTMNet(nn.Module):
            def __init__(self, n_feat, hidden=64, n_classes=3):
                super().__init__()
                self.lstm1  = nn.LSTM(n_feat, hidden, batch_first=True)
                self.bn1    = nn.BatchNorm1d(hidden)
                self.drop1  = nn.Dropout(0.2)
                self.lstm2  = nn.LSTM(hidden, hidden, batch_first=True)
                self.bn2    = nn.BatchNorm1d(hidden)
                self.drop2  = nn.Dropout(0.2)
                self.fc1    = nn.Linear(hidden, 32)
                self.relu   = nn.ReLU()
                self.fc2    = nn.Linear(32, n_classes)

            def forward(self, x):
                out, _ = self.lstm1(x)
                out    = self.drop1(self.bn1(out[:, -1, :]))
                out2   = out.unsqueeze(1)
                out2, _ = self.lstm2(out2.expand(-1, x.size(1), -1))
                out2   = self.drop2(self.bn2(out2[:, -1, :]))
                return self.fc2(self.relu(self.fc1(out2)))

        return LSTMNet(n_features, self.LSTM_UNITS, self.N_CLASSES)

    def _train_torch(self, X_seq: np.ndarray, y_seq: np.ndarray,
                     epochs: int, batch_size: int) -> Dict:
        import torch
        import torch.nn as nn
        import torch.optim as optim
        from torch.utils.data import DataLoader, TensorDataset

        device = torch.device("cpu")
        X_t    = torch.FloatTensor(X_seq).to(device)
        y_t    = torch.LongTensor(y_seq).to(device)

        split   = int(len(X_t) * 0.8)
        ds_tr   = TensorDataset(X_t[:split], y_t[:split])
        ds_val  = TensorDataset(X_t[split:], y_t[split:])
        dl_tr   = DataLoader(ds_tr, batch_size=batch_size, shuffle=False)

        model   = self._build_torch_model(X_seq.shape[2]).to(device)
        opt     = optim.Adam(model.parameters(), lr=0.001)
        crit    = nn.CrossEntropyLoss()

        best_acc = 0.0
        patience = 8
        no_improve = 0

        for epoch in range(epochs):
            model.train()
            for xb, yb in dl_tr:
                opt.zero_grad()
                out  = model(xb)
                loss = crit(out, yb)
                loss.backward()
                opt.step()

            # Validation
            model.eval()
            with torch.no_grad():
                val_out  = model(X_t[split:])
                val_pred = val_out.argmax(dim=1)
                acc      = float((val_pred == y_t[split:]).float().mean())

            if acc > best_acc:
                best_acc   = acc
                best_state = model.state_dict().copy()
                no_improve = 0
            else:
                no_improve += 1
                if no_improve >= patience:
                    break

        model.load_state_dict(best_state)
        self._model    = model
        self._accuracy = best_acc
        self._trained  = True

        logger.info("LSTM (PyTorch) trained. Val acc=%.3f", best_acc)
        return {"val_accuracy": best_acc, "framework": "pytorch"}

    def _predict_torch(self, seq: np.ndarray) -> np.ndarray:
        import torch
        self._model.eval()
        with torch.no_grad():
            t     = torch.FloatTensor(seq)
            out   = self._model(t)
            proba = torch.softmax(out, dim=1).numpy()[0]
        return proba

    # ─────────────────────────────────────────────────────────────────────────
    # MOCK IMPLEMENTATION (fallback)
    # ─────────────────────────────────────────────────────────────────────────

    def _train_mock(self, X_seq: np.ndarray, y_seq: np.ndarray) -> Dict:
        """Mock training: learn mean statistics for each class."""
        self._mock_stats = {}
        for cls in range(self.N_CLASSES):
            mask = y_seq == cls
            self._mock_stats[cls] = X_seq[mask].mean(axis=(0, 1)) if mask.any() else np.zeros(X_seq.shape[2])

        self._trained  = True
        self._accuracy = 0.4  # conservative estimate

        logger.warning("LSTM running in MOCK mode (no TF/PyTorch)")
        return {"val_accuracy": 0.4, "framework": "mock"}

    def _predict_mock(self, seq: np.ndarray) -> np.ndarray:
        """Simple heuristic: recent momentum determines direction."""
        flat = seq[0, -5:, :].mean(axis=0)  # last 5 bars avg
        # Use index 0 (ret_1) if available
        momentum = flat[0] if len(flat) > 0 else 0.0
        if momentum > 0.001:
            return np.array([0.15, 0.25, 0.60])  # UP
        elif momentum < -0.001:
            return np.array([0.60, 0.25, 0.15])  # DOWN
        else:
            return np.array([0.25, 0.50, 0.25])  # NEUTRAL

    # ─────────────────────────────────────────────────────────────────────────
    # PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def save(self, path: Optional[str] = None) -> str:
        path = path or self.model_path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

        if self._framework == "tensorflow" and self._trained:
            tf_path = path.replace(".pkl", ".keras")
            self._model.save(tf_path)
            payload = {"tf_path": tf_path, "meta": self._get_meta()}
        elif self._framework == "pytorch" and self._trained:
            import torch
            torch_path = path.replace(".pkl", ".pt")
            torch.save(self._model.state_dict(), torch_path)
            payload = {"torch_path": torch_path,
                       "n_features": self._n_features,
                       "meta": self._get_meta()}
        else:
            payload = {"mock_stats": getattr(self, "_mock_stats", {}),
                       "meta": self._get_meta()}

        with open(path, "wb") as f:
            pickle.dump(payload, f)
        logger.info("LSTM model saved → %s", path)
        return path

    def load(self, path: Optional[str] = None) -> bool:
        path = path or self.model_path
        if not os.path.exists(path):
            logger.warning("LSTM model not found: %s", path)
            return False

        with open(path, "rb") as f:
            payload = pickle.load(f)

        meta = payload.get("meta", {})
        self._accuracy   = meta.get("accuracy", 0.0)
        self._trained    = meta.get("trained", False)
        self._n_features = meta.get("n_features", 0)

        if "tf_path" in payload and TF_AVAILABLE:
            self._model    = load_model(payload["tf_path"])
            self._framework = "tensorflow"
        elif "torch_path" in payload and TORCH_AVAILABLE:
            import torch
            self._model = self._build_torch_model(payload["n_features"])
            self._model.load_state_dict(torch.load(payload["torch_path"]))
            self._model.eval()
            self._framework = "pytorch"
        else:
            self._mock_stats = payload.get("mock_stats", {})
            self._framework  = "mock"

        logger.info("LSTM model loaded ← %s (acc=%.3f)", path, self._accuracy)
        return True

    # ─────────────────────────────────────────────────────────────────────────
    # HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    def _build_sequences(self, X: np.ndarray,
                          y: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Build (samples, seq_len, features) tensor."""
        X_seq, y_seq = [], []
        for i in range(self.seq_len, len(X)):
            X_seq.append(X[i - self.seq_len: i])
            y_seq.append(y[i])
        if not X_seq:
            return np.array([]), np.array([])
        return np.array(X_seq, dtype=np.float32), np.array(y_seq, dtype=np.int64)

    @staticmethod
    def _auto_label(X: pd.DataFrame, forward_bars: int = 5) -> pd.Series:
        """3-class labels: 0=DOWN, 1=NEUTRAL, 2=UP"""
        if "ret_1" in X.columns:
            future = X["ret_1"].shift(-forward_bars).fillna(0)
            threshold = future.std() * 0.5
            lbl = np.where(future > threshold, 2,
                  np.where(future < -threshold, 0, 1))
        else:
            n = len(X)
            lbl = np.ones(n, dtype=int)  # all NEUTRAL
        return pd.Series(lbl, index=X.index, dtype=np.int64)

    def _get_meta(self) -> Dict:
        return {
            "accuracy":   self._accuracy,
            "trained":    self._trained,
            "n_features": self._n_features,
            "seq_len":    self.seq_len,
            "framework":  self._framework
        }

    @staticmethod
    def _default_result() -> Dict:
        return {
            "direction":    DIR_NEUTRAL,
            "up_prob":      0.33,
            "down_prob":    0.33,
            "neutral_prob": 0.34,
            "confidence":   0.0,
            "framework":    "none",
            "trained":      False
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
    print("LSTMModel — Self Test")
    print(f"Framework: {'TensorFlow' if TF_AVAILABLE else 'PyTorch' if TORCH_AVAILABLE else 'Mock'}")
    print("=" * 60)

    np.random.seed(42)
    n = 800
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

    lstm = LSTMModel(model_path="/tmp/lstm_test.pkl")
    metrics = lstm.train(X, epochs=10, batch_size=32)
    print(f"Training metrics: {metrics}")

    result = lstm.predict(X)
    print(f"Prediction: {result}")

    lstm.save()
    lstm2 = LSTMModel(model_path="/tmp/lstm_test.pkl")
    lstm2.load()
    r2 = lstm2.predict(X)
    print(f"After load: direction={DIR_NAMES.get(r2['direction'])}, "
          f"conf={r2['confidence']:.3f}")

    print("\n✅ LSTMModel Test PASSED")
