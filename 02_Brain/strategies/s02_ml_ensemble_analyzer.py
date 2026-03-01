"""
s02_ml_ensemble_analyzer.py — Hybrid Analyzer  (P4-2 + P4-7 MERGED)
FlashEASuite V2 | 02_Brain/strategies/

ML Ensemble (5 Models): RF + LSTM + XGBoost + KMeans + HMM

Architecture (Merged):
  ┌─────────────────────────────────────────────────────────────────┐
  │  P4-2 layer  :  BaseAnalyzer interface (AI Council compatible)  │
  │    analyze()        → reads pre-computed signals from indicators │
  │    analyze_fallback → RSI/MACD/ADX heuristic (standalone mode)  │
  ├─────────────────────────────────────────────────────────────────┤
  │  P4-7 layer  :  ML pipeline (added in P4-7)                     │
  │    run_ml_pipeline(df) → runs all 5 models → returns indicators │
  │    analyze_with_df()   → convenience: pipeline → analyze()      │
  │    load_models() / train_models()                               │
  └─────────────────────────────────────────────────────────────────┘

Usage (two modes):
  Mode A — Pre-computed (AI Council via intelligence_engine):
      indicators = analyzer.run_ml_pipeline(df)
      result     = analyzer.analyze(symbol, regime, indicators)

  Mode B — Direct (testing / standalone):
      result = analyzer.analyze_with_df(symbol, regime, df)

Hybrid extras sent via CONFIG_PUSH:
    ml_signal         → +1 (buy), -1 (sell), 0 (neutral)
    ml_confidence     → 0.0–1.0 ensemble confidence
    ml_model_agreement→ how many models agree (0–5)

Author: FlashEASuite V2 Dev | P4-2 + P4-7
"""

from __future__ import annotations

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  ⚠️  PERFORMANCE WARNING — อ่านก่อน Backtest / Forward Test               ║
# ║                                                                              ║
# ║  run_ml_pipeline() เรียก FeatureEngineer.compute() ทุกครั้ง                ║
# ║  → compute() คำนวณ rolling indicators ทั้ง series ใหม่ = O(N) ทุก call     ║
# ║  → Latency ปัจจุบัน: ~100-340ms ต่อ bar (ยอมรับไม่ได้ใน production)        ║
# ║                                                                              ║
# ║  สิ่งที่ต้องทำก่อน Forward Test / Live Trading:                              ║
# ║  ┌─────────────────────────────────────────────────────────────────────┐   ║
# ║  │  OPTION A (แนะนำ): Cache + Incremental Update                       │   ║
# ║  │    1. เรียก fe.compute(df_full) ครั้งแรก → cache เป็น self._X_cache  │   ║
# ║  │    2. bar ใหม่มา → append 1 row แล้วเรียก compute_incremental()     │   ║
# ║  │    3. compute_incremental() ต้อง implement ก่อน (TODO ใน P5/P8)     │   ║
# ║  │                                                                     │   ║
# ║  │  OPTION B (เร็วกว่า dev แต่ยังไม่ optimal):                          │   ║
# ║  │    1. Cache df_window[-200:] แทน df ทั้งหมด → ลด N ลง              │   ║
# ║  │    2. Latency ลดเหลือ ~30-50ms (พอรับได้ถ้า tick < 1Hz)            │   ║
# ║  └─────────────────────────────────────────────────────────────────────┘   ║
# ║                                                                              ║
# ║  ตัววัด: latency > _PIPELINE_WARN_MS → WARNING log อัตโนมัติ              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

import logging
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

# ── Add ml_models/ to sys.path (works from strategies/ folder) ────────────────
_ML_DIR = Path(__file__).parent / "ml_models"
if _ML_DIR.exists() and str(_ML_DIR) not in sys.path:
    sys.path.insert(0, str(_ML_DIR))

# ── Import ML model classes (P4-7) — soft import: ok if not installed yet ─────
try:
    import pandas as pd
    import numpy as np
    from feature_engineering import FeatureEngineer
    from random_forest_model  import RandomForestModel
    from xgboost_model        import XGBoostModel
    from lstm_model           import LSTMModel
    from kmeans_model         import KMeansModel
    from hmm_model            import HMMModel
    _ML_AVAILABLE = True
except ImportError as _e:
    _ML_AVAILABLE = False
    logging.getLogger(__name__).warning(
        "ML models not available (%s) — will use fallback only", _e
    )

# ── BaseAnalyzer (P4-2 core) ──────────────────────────────────────────────────
from .base_analyzer import BaseAnalyzer, AnalysisResult, REGIME_RANGING, REGIME_TRENDING

logger = logging.getLogger(__name__)

# ── Model weight allocation (must sum to 1.0) ──────────────────────────────────
_MODEL_WEIGHTS = {
    "random_forest": 0.25,
    "lstm":          0.25,
    "xgboost":       0.25,
    "kmeans":        0.10,
    "hmm":           0.15,
}

# ── ML pipeline config ─────────────────────────────────────────────────────────
_DEFAULT_MODEL_DIR   = str(Path(__file__).parent / "ml_models" / "trained")
_MIN_DF_ROWS         = 100     # minimum bars for ML inference
_ML_SIGNAL_THRESHOLD = 0.10    # |w_signal| < threshold → NEUTRAL

# ⚠️ Latency thresholds — ถ้าเกินนี้ต้อง fix ก่อน live trading
_PIPELINE_WARN_MS    = 100     # warn: ต้อง optimize
_PIPELINE_ERROR_MS   = 400     # error: SLA breach — ห้าม live
_DF_WINDOW_OPTIMAL   = 200     # OPTION B: ใช้แค่ 200 bars ล่าสุด (ลด latency)


# ═══════════════════════════════════════════════════════════════════════════════
class S02MlEnsembleAnalyzer(BaseAnalyzer):
    """
    Hybrid analyzer: orchestrates ML ensemble vote.

    Inherits BaseAnalyzer so the AI Council can call analyze() directly.
    Internally manages the 5 ML models (RF / LSTM / XGBoost / KMeans / HMM).
    Models are lazy-loaded on first use.
    """

    # ── Identity ──────────────────────────────────────────────────────────────
    def get_id(self)   -> str: return "S02"
    def get_name(self) -> str: return "ML Ensemble (5 Models)"

    def get_preferred_regimes(self) -> List[str]:
        # ML adapts to all regimes → no specific preference
        return [REGIME_TRENDING, REGIME_RANGING]

    # ── Constructor ───────────────────────────────────────────────────────────
    def __init__(self, model_dir: str = _DEFAULT_MODEL_DIR, symbol: str = "XAUUSD"):
        """
        Args:
            model_dir : directory containing trained .pkl model files
            symbol    : default symbol for model file names
        """
        super().__init__()
        self.model_dir  = model_dir
        self.symbol     = symbol
        self._models_loaded = False
        self._pipeline_stats: Dict[str, Any] = {}

        # ── ML model instances (P4-7) — None until load_models() called ──────
        if _ML_AVAILABLE:
            self._fe      = FeatureEngineer(normalize=False)
            self._fe_norm = FeatureEngineer(normalize=True)
            sym = symbol.upper()
            mdir = model_dir
            self._rf   = RandomForestModel(model_path=f"{mdir}/rf_{sym}.pkl")
            self._xgb  = XGBoostModel(model_path=f"{mdir}/xgb_{sym}.pkl")
            self._lstm = LSTMModel(model_path=f"{mdir}/lstm_{sym}.pkl")
            self._km   = KMeansModel(model_path=f"{mdir}/km_{sym}.pkl")
            self._hmm  = HMMModel(model_path=f"{mdir}/hmm_{sym}.pkl")
        else:
            self._fe = self._fe_norm = None
            self._rf = self._xgb = self._lstm = self._km = self._hmm = None

        logger.info("S02MlEnsembleAnalyzer created (symbol=%s, ml_available=%s)",
                    symbol, _ML_AVAILABLE)

    # ══════════════════════════════════════════════════════════════════════════
    # P4-2 LAYER — BaseAnalyzer interface (DO NOT MODIFY — AI Council uses this)
    # ══════════════════════════════════════════════════════════════════════════

    def analyze(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
        history:    Optional[List[Dict[str, Any]]] = None,
    ) -> AnalysisResult:
        """
        [P4-2] Weighted ensemble vote using pre-computed model signals.

        indicators dict must contain (populated by run_ml_pipeline or upstream):
            rf_signal / rf_confidence
            lstm_signal / lstm_confidence
            xgb_signal / xgb_confidence
            km_signal / km_confidence
            hmm_signal / hmm_confidence

        If any key is missing, defaults: signal=0, confidence=0.5
        """

        # ── Per-model signals and confidences ─────────────────────────────────
        rf_signal   = int(self._safe_get(indicators,   "rf_signal",        0))
        rf_conf     = float(self._safe_get(indicators, "rf_confidence",    0.5))

        lstm_signal = int(self._safe_get(indicators,   "lstm_signal",      0))
        lstm_conf   = float(self._safe_get(indicators, "lstm_confidence",  0.5))

        xgb_signal  = int(self._safe_get(indicators,   "xgb_signal",       0))
        xgb_conf    = float(self._safe_get(indicators, "xgb_confidence",   0.5))

        km_signal   = int(self._safe_get(indicators,   "km_signal",        0))
        km_conf     = float(self._safe_get(indicators, "km_confidence",    0.5))

        hmm_signal  = int(self._safe_get(indicators,   "hmm_signal",       0))
        hmm_conf    = float(self._safe_get(indicators, "hmm_confidence",   0.5))

        # ── Ensemble vote ──────────────────────────────────────────────────────
        signals  = [rf_signal, lstm_signal, xgb_signal, km_signal, hmm_signal]
        weights  = list(_MODEL_WEIGHTS.values())
        confs    = [rf_conf, lstm_conf, xgb_conf, km_conf, hmm_conf]

        # Weighted signal: Σ(signal × weight × confidence)
        w_signal = sum(s * w * c for s, w, c in zip(signals, weights, confs))

        # Model agreement (how many models agree on direction)
        buys     = sum(1 for s in signals if s > 0)
        sells    = sum(1 for s in signals if s < 0)
        agreement = max(buys, sells)

        # Final signal direction
        if   w_signal >  _ML_SIGNAL_THRESHOLD: final_signal = 1
        elif w_signal < -_ML_SIGNAL_THRESHOLD: final_signal = -1
        else:                                   final_signal = 0

        # Ensemble confidence = weighted avg × agreement factor
        avg_conf     = sum(w * c for w, c in zip(weights, confs))
        agree_factor = agreement / 5.0      # 1.0 when all 5 agree
        raw_conf     = avg_conf * (0.6 + 0.4 * agree_factor)
        confidence   = self._clamp(raw_conf)

        # Regime shift penalty (populated by run_ml_pipeline if available)
        shift_prob = float(self._safe_get(indicators, "hmm_regime_shift_prob", 0.0))
        if shift_prob > 0.4:
            confidence = self._clamp(confidence * (1.0 - shift_prob * 0.5))

        extra = {
            "ml_signal":          final_signal,
            "ml_confidence":      round(confidence, 4),
            "ml_model_agreement": agreement,
            "ml_w_signal":        round(w_signal, 4),
            # Pass-through extras from run_ml_pipeline (if present)
            "ml_regime":          self._safe_get(indicators, "ml_regime", regime),
            "ml_feature_importance": self._safe_get(indicators, "ml_feature_importance", {}),
        }

        reasoning = (
            f"MLEnsemble w_signal={w_signal:.3f} agreement={agreement}/5 "
            f"avg_conf={avg_conf:.3f} regime={regime} shift_risk={shift_prob:.2f}"
            f" → conf={confidence:.3f}"
        )
        return AnalysisResult(confidence=confidence, reasoning=reasoning,
                              extra_params=extra)

    # ──────────────────────────────────────────────────────────────────────────
    def analyze_fallback(
        self,
        symbol:     str,
        regime:     str,
        indicators: Dict[str, Any],
    ) -> AnalysisResult:
        """
        [P4-2] Rule-based fallback when ML models not available / not trained yet.
        Uses RSI + MACD + ADX heuristics to approximate ML output.
        """
        rsi  = float(self._safe_get(indicators, "rsi",  50.0))
        macd = float(self._safe_get(indicators, "macd",  0.0))
        adx  = float(self._safe_get(indicators, "adx",  20.0))

        # Heuristic signal
        if rsi > 55 and macd > 0 and adx > 25:
            fb_signal, fb_conf = 1, 0.55
        elif rsi < 45 and macd < 0 and adx > 25:
            fb_signal, fb_conf = -1, 0.55
        else:
            fb_signal, fb_conf = 0, 0.40

        extra = {
            "ml_signal":          fb_signal,
            "ml_confidence":      fb_conf,
            "ml_model_agreement": 0,
            "ml_fallback":        True,
        }
        return AnalysisResult(
            confidence=fb_conf,
            reasoning=(
                f"ML_fallback RSI={rsi:.1f} MACD={macd:.5f} ADX={adx:.1f} "
                f"→ sig={fb_signal} conf={fb_conf:.3f}"
            ),
            extra_params=extra,
        )

    # ══════════════════════════════════════════════════════════════════════════
    # P4-7 LAYER — ML Pipeline (runs the 5 actual models)
    # ══════════════════════════════════════════════════════════════════════════

    def load_models(self) -> Dict[str, bool]:
        """
        [P4-7] Load all pre-trained models from disk.

        Returns:
            dict {model_name: loaded_ok}
        """
        if not _ML_AVAILABLE:
            logger.warning("S02: ML libraries not installed — models cannot be loaded")
            return {k: False for k in ("rf", "xgb", "lstm", "kmeans", "hmm")}

        results = {
            "rf":     self._rf.load(),
            "xgb":    self._xgb.load(),
            "lstm":   self._lstm.load(),
            "kmeans": self._km.load(),
            "hmm":    self._hmm.load(),
        }
        n_loaded = sum(results.values())
        self._models_loaded = n_loaded >= 3   # need at least 3/5
        logger.info("S02: Models loaded %d/5 (ready=%s)", n_loaded, self._models_loaded)
        return results

    def is_ml_ready(self) -> bool:
        """True if at least 3 models are loaded and trained."""
        if not _ML_AVAILABLE:
            return False
        trained = sum([
            getattr(self._rf,   "_trained", False),
            getattr(self._xgb,  "_trained", False),
            getattr(self._lstm, "_trained", False),
            getattr(self._km,   "_trained", False),
            getattr(self._hmm,  "_trained", False),
        ])
        return trained >= 3

    def run_ml_pipeline(self, df: "pd.DataFrame") -> Dict[str, Any]:
        """
        [P4-7] Run all 5 ML models on OHLCV data.

        Returns an indicators-compatible dict ready to pass directly into
        analyze() — keys match the ones analyze() expects.

        Args:
            df : OHLCV DataFrame with DatetimeIndex (UTC), ≥ 100 bars

        Returns:
            dict with rf_signal, rf_confidence, lstm_signal, ... etc.
            Returns empty dict on error (analyze() will use defaults = 0.5).
        """
        if not _ML_AVAILABLE:
            logger.debug("S02 pipeline skipped: ML not available")
            return {}

        if df is None or len(df) < _MIN_DF_ROWS:
            logger.debug("S02 pipeline skipped: need ≥%d bars, got %d",
                         _MIN_DF_ROWS, len(df) if df is not None else 0)
            return {}

        if not self.is_ml_ready():
            logger.debug("S02 pipeline skipped: models not loaded")
            return {}

        t_start = time.perf_counter()

        try:
            # ── ⚠️ OPTION B: ลด latency โดยใช้เฉพาะ N bars ล่าสุด ──────────
            # TODO (ก่อน forward test): เปลี่ยนเป็น compute_incremental()
            # ตอนนี้ใช้ df[-_DF_WINDOW_OPTIMAL:] แทน df เต็มเพื่อลด latency
            # ข้อเสีย: D1 trend อาจ inaccurate ถ้า window สั้นเกิน
            # หมายเหตุ: ถ้า len(df) ≤ _DF_WINDOW_OPTIMAL จะใช้ df ทั้งหมด
            df_window = df.iloc[-_DF_WINDOW_OPTIMAL:] if len(df) > _DF_WINDOW_OPTIMAL else df

            # ── Feature engineering ──────────────────────────────────────
            X      = self._fe.compute(df_window)        # raw (for RF, XGB, HMM)
            X_norm = self._fe_norm.compute(df_window)   # normalized (for LSTM, KMeans)

            if X.empty:
                return {}

            # ── 1. Random Forest → regime → rf_signal ────────────────────
            rf_res     = self._rf.predict(X)
            rf_regime  = rf_res.get("regime", 1)      # 0=TRENDING,1=RANGING,...
            rf_conf    = float(rf_res.get("confidence", 0.5))
            # TRENDING → slight BUY bias, SQUEEZE/VOLATILE → neutral
            rf_signal  = 1 if rf_regime == 0 else (-1 if rf_regime == 2 else 0)

            # ── 2. XGBoost → direction + confidence ──────────────────────
            xgb_res    = self._xgb.predict(X)
            xgb_signal = int(xgb_res.get("direction", 0))
            xgb_conf   = float(xgb_res.get("confidence", 0.5))
            xgb_fi     = xgb_res.get("feature_importance", {})

            # ── 3. LSTM → direction + confidence ─────────────────────────
            lstm_res    = self._lstm.predict(X_norm)
            lstm_signal = int(lstm_res.get("direction", 0))
            lstm_conf   = float(lstm_res.get("confidence", 0.5))

            # ── 4. KMeans → profitable cluster → signal + confidence ──────
            km_res    = self._km.predict(X_norm)
            km_profit = km_res.get("is_profitable", False)
            km_conf   = float(km_res.get("confidence", 0.5))
            # KMeans doesn't give direction — reinforce XGBoost direction if profitable
            km_signal = xgb_signal if km_profit else 0

            # ── 5. HMM → current regime + shift probability ───────────────
            hmm_res       = self._hmm.predict(X)
            hmm_regime_nm = hmm_res.get("current_regime", "RANGING")
            hmm_conf      = float(hmm_res.get("confidence", 0.0))
            shift_prob    = float(hmm_res.get("regime_shift_prob", 0.3))
            # HMM reinforces current trend: TRENDING → align with XGB
            hmm_signal = xgb_signal if hmm_regime_nm == "TRENDING" else 0

            # ── Build indicators dict (P4-2 compatible keys) ──────────────
            latency_ms = (time.perf_counter() - t_start) * 1000
            self._pipeline_stats = {
                "last_run_ms":      round(latency_ms, 1),
                "last_run_utc":     datetime.now(timezone.utc).isoformat(),
                "df_rows":          len(df),
                "df_window_rows":   len(df_window)
            }

            # ── ⚠️ Latency gate: ถ้าช้าเกิน threshold ให้ warn / error ──────
            if latency_ms >= _PIPELINE_ERROR_MS:
                logger.error(
                    "🚨 S02 PIPELINE BREACH: %.0fms ≥ %dms — "
                    "ห้าม live trading ก่อน implement compute_incremental()! "
                    "ดู PERFORMANCE WARNING ที่ top ของไฟล์นี้",
                    latency_ms, _PIPELINE_ERROR_MS
                )
            elif latency_ms >= _PIPELINE_WARN_MS:
                logger.warning(
                    "⚠️  S02 PIPELINE SLOW: %.0fms ≥ %dms — "
                    "ใน production ต้อง cache X + incremental update "
                    "(TODO: compute_incremental ใน P5/P8)",
                    latency_ms, _PIPELINE_WARN_MS
                )

            result: Dict[str, Any] = {
                # ── Keys consumed by analyze() ────────────────────────────
                "rf_signal":        rf_signal,
                "rf_confidence":    round(rf_conf, 4),
                "lstm_signal":      lstm_signal,
                "lstm_confidence":  round(lstm_conf, 4),
                "xgb_signal":       xgb_signal,
                "xgb_confidence":   round(xgb_conf, 4),
                "km_signal":        km_signal,
                "km_confidence":    round(km_conf, 4),
                "hmm_signal":       hmm_signal,
                "hmm_confidence":   round(hmm_conf, 4),
                # ── Extra context passed through extra_params ─────────────
                "hmm_regime_shift_prob":  round(shift_prob, 4),
                "ml_regime":              rf_res.get("regime_name", "RANGING"),
                "ml_feature_importance":  xgb_fi,
                "ml_pipeline_latency_ms": round(latency_ms, 1),
            }

            logger.debug("S02 pipeline done in %.1fms", latency_ms)
            return result

        except Exception as exc:
            logger.error("S02 run_ml_pipeline error: %s", exc, exc_info=True)
            return {}

    # ──────────────────────────────────────────────────────────────────────────
    def analyze_with_df(
        self,
        symbol:     str,
        regime:     str,
        df:         "pd.DataFrame",
        history:    Optional[List[Dict[str, Any]]] = None,
    ) -> AnalysisResult:
        """
        [P4-7 convenience] Run ML pipeline then analyze in one call.

        Equivalent to:
            inds   = analyzer.run_ml_pipeline(df)
            result = analyzer.analyze(symbol, regime, inds)

        Falls back to analyze_fallback() if pipeline fails or models not loaded.

        Args:
            symbol  : trading symbol ("XAUUSD")
            regime  : current regime string (from regime_classifier)
            df      : OHLCV DataFrame ≥ 100 bars
            history : optional trade history (passed to analyze)
        """
        inds = self.run_ml_pipeline(df)

        if not inds:
            # Pipeline failed or models not ready — extract simple indicators for fallback
            fallback_inds = self._extract_fallback_indicators(df)
            return self.analyze_fallback(symbol, regime, fallback_inds)

        return self.analyze(symbol, regime, inds, history)

    def get_pipeline_stats(self) -> Dict[str, Any]:
        """Return last ML pipeline execution stats."""
        return dict(self._pipeline_stats)

    # ══════════════════════════════════════════════════════════════════════════
    # PRIVATE HELPERS
    # ══════════════════════════════════════════════════════════════════════════

    def _extract_fallback_indicators(self, df: "pd.DataFrame") -> Dict[str, Any]:
        """
        Extract simple RSI/MACD/ADX from df for use in analyze_fallback().
        Used when ML pipeline cannot run.
        """
        if not _ML_AVAILABLE or df is None or len(df) < 30:
            return {}

        try:
            close = df["close"] if "close" in df.columns else df.iloc[:, 3]

            # Simple RSI
            delta  = close.diff()
            gain   = delta.clip(lower=0).ewm(com=13, adjust=False).mean()
            loss   = (-delta.clip(upper=0)).ewm(com=13, adjust=False).mean()
            rsi    = float(100 - 100 / (1 + gain.iloc[-1] / (loss.iloc[-1] + 1e-10)))

            # Simple MACD histogram
            ema12  = float(close.ewm(span=12, adjust=False).mean().iloc[-1])
            ema26  = float(close.ewm(span=26, adjust=False).mean().iloc[-1])
            macd   = ema12 - ema26

            # Simple ATR as ADX proxy
            hi = df["high"] if "high" in df.columns else close
            lo = df["low"]  if "low"  in df.columns else close
            tr = (hi - lo).iloc[-14:].mean()
            adx = float(tr / (close.iloc[-1] + 1e-10) * 1000)  # normalize

            return {"rsi": rsi, "macd": macd, "adx": min(adx, 60.0)}
        except Exception:
            return {}
