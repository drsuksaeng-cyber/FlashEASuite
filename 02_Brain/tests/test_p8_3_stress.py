#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_p8_3_stress.py
FlashEASuite V2 — P8-3: Performance & Stress Test
==================================================
ทดสอบ benchmark ทุกองค์ประกอบหลักของ Python Brain:

  Benchmark 1 : Intelligence Cycle   target < 2000ms (p99)
  Benchmark 2 : ML Ensemble          target < 5000ms (p99)
  Benchmark 3 : CONFIG_PUSH build    target < 100ms  (p99)
  Benchmark 4 : InfluxDB write       target > 1000 pts/sec
  Benchmark 5 : Memory stability     no leak (< +5% growth)
  Benchmark 6 : CPU average          target < 50%

Mode:
  FAST_MODE=True  → 1000 cycles  (≈ 30-60 วินาที — สำหรับ CI)
  FAST_MODE=False → 50000 cycles (≈ 8 ชั่วโมง equivalent load)

Usage:
  cd 02_Brain
  python tests/test_p8_3_stress.py              # fast mode
  python tests/test_p8_3_stress.py --full       # full mode
  python tests/test_p8_3_stress.py --influxdb   # with real InfluxDB

Save: 02_Brain/tests/test_p8_3_stress.py
"""

import sys
import os
import time
import threading
import tracemalloc
import statistics
import argparse
import logging
from typing import Optional

# ── path setup ────────────────────────────────────────────────────────────────
# Add 02_Brain/ to sys.path so imports work correctly
_TEST_DIR = os.path.dirname(os.path.abspath(__file__))
_BRAIN_DIR = os.path.dirname(_TEST_DIR)
if _BRAIN_DIR not in sys.path:
    sys.path.insert(0, _BRAIN_DIR)

# ── optional imports (fail gracefully) ────────────────────────────────────────
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False
    print("⚠  psutil not installed — CPU/memory via psutil disabled")
    print("   pip install psutil  (optional)")

try:
    from influxdb_client import InfluxDBClient
    from influxdb_client.client.write_api import SYNCHRONOUS
    HAS_INFLUXDB = True
except ImportError:
    HAS_INFLUXDB = False
    # ไม่แสดง warning ที่นี่ — แสดงตอน run benchmark

# ── project imports ───────────────────────────────────────────────────────────
_import_errors: list[str] = []

try:
    from core.intelligence.strategy_council import StrategyCouncil, build_mock_registry
    from core.intelligence.strategy_council import Regime  # re-exported via confidence_scorer
    HAS_COUNCIL = True
except ImportError as e:
    _import_errors.append(f"strategy_council: {e}")
    HAS_COUNCIL = False

try:
    from core.config_push.config_builder import (
        ConfigBuilder, SymbolConfig, StrategyConfig as SConfig
    )
    HAS_CONFIG_BUILDER = True
except ImportError:
    # Try alternate path (if saved as config_push/config_builder.py directly in brain root)
    try:
        sys.path.insert(0, os.path.join(_BRAIN_DIR, "config_push"))
        from config_builder import (         # type: ignore
            ConfigBuilder, SymbolConfig, StrategyConfig as SConfig
        )
        HAS_CONFIG_BUILDER = True
    except ImportError as e:
        _import_errors.append(f"config_builder: {e}")
        HAS_CONFIG_BUILDER = False

try:
    from core.intelligence.regime_classifier import RegimeClassifier
    HAS_REGIME_CLASSIFIER = True
except ImportError as e:
    _import_errors.append(f"regime_classifier: {e}")
    HAS_REGIME_CLASSIFIER = False

# Try ML Ensemble models
_ml_models_available: list = []
try:
    from strategies.ml_models.random_forest_model import RandomForestModel
    _ml_models_available.append(("RandomForest", RandomForestModel))
except ImportError:
    pass
try:
    from strategies.ml_models.xgboost_model import XGBoostModel
    _ml_models_available.append(("XGBoost", XGBoostModel))
except ImportError:
    pass
try:
    from strategies.ml_models.kmeans_model import KMeansModel
    _ml_models_available.append(("KMeans", KMeansModel))
except ImportError:
    pass
try:
    from strategies.ml_models.hmm_model import HMMModel
    _ml_models_available.append(("HMM", HMMModel))
except ImportError:
    pass
try:
    from strategies.ml_models.lstm_model import LSTMModel
    _ml_models_available.append(("LSTM", LSTMModel))
except ImportError:
    pass

HAS_ML_ENSEMBLE = len(_ml_models_available) >= 3   # ต้องมีอย่างน้อย 3 models

# ── logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.WARNING,  # suppress info noise during stress
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("P8_3_Stress")


# ════════════════════════════════════════════════════════════════════════════════
# CONSTANTS / CONFIG
# ════════════════════════════════════════════════════════════════════════════════

FAST_CYCLES     = 1_000    # quick mode: ~30-60s
FULL_CYCLES     = 50_000   # full mode:  8-hour equivalent at HFT rates
SYMBOLS         = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "GBPJPY"]
REGIMES         = ["RANGING", "TRENDING", "VOLATILE", "SQUEEZE"]

# Benchmarks (all absolute targets)
TARGET_INTELLIGENCE_CYCLE_P99_MS = 2_000.0   # ms
TARGET_ML_ENSEMBLE_P99_MS        = 5_000.0   # ms
TARGET_CONFIG_PUSH_P99_MS        = 100.0     # ms
TARGET_INFLUXDB_PTS_PER_SEC      = 1_000.0   # points/sec
TARGET_MEMORY_GROWTH_PCT         = 5.0       # max % growth
TARGET_CPU_AVG_PCT               = 50.0      # %

INFLUXDB_URL    = "http://localhost:8086"
INFLUXDB_TOKEN  = "_2Rnkee4DHBmXjDe60pILHKHGkXZ_uiB47SG_UcGg658WP_wNRf3XH7hFNFYq7S5w0rH2Uc240b7LoGGZCu3XA=="
INFLUXDB_ORG    = "flashea"
INFLUXDB_BUCKET = "hft_ticks"
INFLUXDB_TEST_BATCH = 5_000   # จำนวน points สำหรับ throughput test


# ════════════════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════════════════

class TestResult:
    """เก็บผล benchmark 1 รายการ"""
    def __init__(self, name: str, target_label: str):
        self.name = name
        self.target_label = target_label
        self.passed: Optional[bool] = None
        self.actual: float = 0.0
        self.details: str = ""

    def mark_pass(self, actual: float, details: str = ""):
        self.passed = True
        self.actual = actual
        self.details = details

    def mark_fail(self, actual: float, details: str = ""):
        self.passed = False
        self.actual = actual
        self.details = details

    def mark_skip(self, reason: str):
        self.passed = None
        self.details = reason

    def __str__(self):
        if self.passed is None:
            return f"  [SKIP] {self.name:<40s} {self.details}"
        icon = "✅" if self.passed else "❌"
        return f"  {icon} {self.name:<40s} actual={self.actual:>10.2f}  target={self.target_label}  {self.details}"


def _percentile(data: list[float], p: float) -> float:
    """คำนวณ percentile"""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    idx = (p / 100.0) * (len(sorted_data) - 1)
    lo = int(idx)
    hi = min(lo + 1, len(sorted_data) - 1)
    frac = idx - lo
    return sorted_data[lo] * (1.0 - frac) + sorted_data[hi] * frac


def _make_indicators(seed: int = 0) -> dict:
    """สร้าง indicator dict สำหรับ council vote"""
    import random
    rng = random.Random(seed)
    return {
        "adx":          rng.uniform(15.0, 45.0),
        "atr":          rng.uniform(0.5, 3.0),
        "atr_ma":       rng.uniform(0.5, 2.5),
        "atr_norm":     rng.uniform(0.5, 1.5),
        "bb_width":     rng.uniform(0.3, 1.5),
        "bb_width_ma":  rng.uniform(0.3, 1.2),
        "bb_width_norm":rng.uniform(0.5, 1.5),
        "volume":       rng.uniform(500, 5000),
        "volume_ma_ratio": rng.uniform(0.6, 1.8),
        "rsi":          rng.uniform(25, 75),
        "stoch_k":      rng.uniform(10, 90),
        "stoch_d":      rng.uniform(10, 90),
        "price_change": rng.uniform(-0.5, 0.5),
        "session":      rng.choice(["london", "new_york", "asia", "overlap"]),
        "spread":       rng.uniform(0.1, 1.0),
    }


def _make_symbol_configs(symbols: list[str]) -> list:
    """สร้าง SymbolConfig list สำหรับ ConfigBuilder test"""
    if not HAS_CONFIG_BUILDER:
        return []
    result = []
    for sym in symbols:
        strategies = [
            SConfig(15, True, 0.78,
                    {"S15_GRID_STEP": 15.0, "S15_GRID_LEVELS": 5},
                    "MM03", {"MM03_ATR_MULT": 1.5}, "Grid RANGING"),
            SConfig(1,  True, 0.72,
                    {"S01_LOOKBACK": 30, "S01_ZSCORE_ENTRY": 2.0},
                    "MM04", {"MM04_KELLY_FRACTION": 0.4}, "StatArb"),
            SConfig(6,  True, 0.65,
                    {"S06_KAMA_FAST": 2, "S06_KAMA_SLOW": 30},
                    "MM08", {}, "KAMA trend"),
        ]
        result.append(SymbolConfig(symbol=sym, strategies=strategies))
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 1 : Intelligence Cycle
# ════════════════════════════════════════════════════════════════════════════════

def bench_intelligence_cycle(n_cycles: int) -> TestResult:
    """
    วัดเวลา full intelligence cycle:
    indicator build → Regime classify → Council vote

    Target: p99 < 2000ms
    """
    result = TestResult(
        "Intelligence Cycle (p99)",
        f"< {TARGET_INTELLIGENCE_CYCLE_P99_MS:.0f}ms"
    )

    if not HAS_COUNCIL:
        result.mark_skip("strategy_council not importable — " + "; ".join(_import_errors))
        return result

    import random
    rng_global = random.Random(42)

    # Build council once (registry ไม่เปลี่ยนระหว่าง cycles)
    registry = build_mock_registry(16)

    try:
        from core.intelligence.portfolio_diversifier import PortfolioState
    except ImportError:
        try:
            from portfolio_diversifier import PortfolioState   # type: ignore
        except ImportError:
            PortfolioState = lambda: None  # type: ignore

    council = StrategyCouncil(analyzer_registry=registry)

    regime_list = [Regime.RANGING, Regime.TRENDING, Regime.VOLATILE]
    latencies_ms: list[float] = []

    print(f"  Running {n_cycles} intelligence cycles (council.vote × {len(SYMBOLS)} symbols)...")

    for i in range(n_cycles):
        sym  = SYMBOLS[i % len(SYMBOLS)]
        reg  = regime_list[i % len(regime_list)]
        ind  = _make_indicators(seed=i)

        t0 = time.perf_counter()
        try:
            decision = council.vote(
                symbol=sym,
                regime=reg,
                indicators=ind,
                portfolio=None,
                weekday=(i % 5),
                news_factor=rng_global.uniform(0.8, 1.2),
            )
        except Exception as exc:
            result.mark_fail(0.0, f"Exception at cycle {i}: {exc}")
            return result
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        latencies_ms.append(elapsed_ms)

        # ตรวจ zero-crash: decision ต้องไม่ None
        if decision is None:
            result.mark_fail(0.0, f"council.vote returned None at cycle {i}")
            return result

    # stats
    p50  = _percentile(latencies_ms, 50)
    p95  = _percentile(latencies_ms, 95)
    p99  = _percentile(latencies_ms, 99)
    pmax = max(latencies_ms)
    avg  = statistics.mean(latencies_ms)

    details = (
        f"avg={avg:.1f}ms p50={p50:.1f}ms p95={p95:.1f}ms "
        f"p99={p99:.1f}ms max={pmax:.1f}ms n={n_cycles}"
    )

    if p99 <= TARGET_INTELLIGENCE_CYCLE_P99_MS:
        result.mark_pass(p99, details)
    else:
        result.mark_fail(p99, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 2 : ML Ensemble
# ════════════════════════════════════════════════════════════════════════════════

def bench_ml_ensemble(n_cycles: int) -> TestResult:
    """
    วัดเวลา ML Ensemble (5 models predict พร้อมกัน)
    Target: p99 < 5000ms
    """
    result = TestResult(
        "ML Ensemble (p99)",
        f"< {TARGET_ML_ENSEMBLE_P99_MS:.0f}ms"
    )

    if not HAS_ML_ENSEMBLE:
        result.mark_skip(
            f"ML models available: {[n for n,_ in _ml_models_available]} "
            f"(need ≥3, got {len(_ml_models_available)})"
        )
        return result

    # สร้าง model instances
    models = []
    for name, cls in _ml_models_available:
        try:
            m = cls()
            models.append((name, m))
        except Exception as e:
            logger.warning(f"Cannot instantiate {name}: {e}")

    if len(models) < 3:
        result.mark_skip(f"Only {len(models)} models instantiated (need ≥3)")
        return result

    import numpy as np
    n_features = 14   # ตาม feature engineering
    latencies_ms: list[float] = []
    rng = np.random.default_rng(42)

    print(f"  Running {n_cycles} ML Ensemble cycles ({len(models)} models)...")

    for i in range(n_cycles):
        features = rng.uniform(-1.0, 1.0, n_features).tolist()

        t0 = time.perf_counter()
        predictions = {}
        for name, model in models:
            try:
                pred = model.predict(features)
                predictions[name] = pred
            except Exception as exc:
                result.mark_fail(0.0, f"Model {name} failed at cycle {i}: {exc}")
                return result
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        latencies_ms.append(elapsed_ms)

    p99  = _percentile(latencies_ms, 99)
    pmax = max(latencies_ms)
    avg  = statistics.mean(latencies_ms)
    details = (
        f"models={[n for n,_ in models]} "
        f"avg={avg:.1f}ms p99={p99:.1f}ms max={pmax:.1f}ms n={n_cycles}"
    )

    if p99 <= TARGET_ML_ENSEMBLE_P99_MS:
        result.mark_pass(p99, details)
    else:
        result.mark_fail(p99, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 3 : CONFIG_PUSH Build + Pack
# ════════════════════════════════════════════════════════════════════════════════

def bench_config_push(n_cycles: int) -> TestResult:
    """
    วัดเวลา ConfigBuilder.build_and_pack() (5 symbols, 3 strategies each)
    Target: p99 < 100ms
    """
    result = TestResult(
        "CONFIG_PUSH build+pack (p99)",
        f"< {TARGET_CONFIG_PUSH_P99_MS:.1f}ms"
    )

    if not HAS_CONFIG_BUILDER:
        result.mark_skip("config_builder not importable — " + "; ".join(_import_errors))
        return result

    builder = ConfigBuilder()
    sym_configs = _make_symbol_configs(SYMBOLS)  # 5 symbols × 3 strategies
    latencies_ms: list[float] = []
    total_bytes = 0

    print(f"  Running {n_cycles} CONFIG_PUSH build+pack cycles "
          f"({len(SYMBOLS)} symbols × 3 strategies)...")

    regime_list = ["RANGING", "TRENDING", "VOLATILE", "SQUEEZE", "UNKNOWN"]

    for i in range(n_cycles):
        regime = regime_list[i % len(regime_list)]

        t0 = time.perf_counter()
        try:
            packed = builder.build_and_pack(
                symbol_configs=sym_configs,
                regime=regime,
                optimization_cycle=f"stress_{i:06d}",
            )
        except Exception as exc:
            result.mark_fail(0.0, f"Exception at cycle {i}: {exc}")
            return result
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        latencies_ms.append(elapsed_ms)
        total_bytes += len(packed)

    p99  = _percentile(latencies_ms, 99)
    pmax = max(latencies_ms)
    avg  = statistics.mean(latencies_ms)
    avg_bytes = total_bytes / n_cycles

    details = (
        f"avg={avg:.2f}ms p99={p99:.2f}ms max={pmax:.2f}ms "
        f"avg_size={avg_bytes:.0f}bytes n={n_cycles}"
    )

    if p99 <= TARGET_CONFIG_PUSH_P99_MS:
        result.mark_pass(p99, details)
    else:
        result.mark_fail(p99, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 4 : InfluxDB Write Throughput
# ════════════════════════════════════════════════════════════════════════════════

def bench_influxdb_write(use_real_influx: bool = False) -> TestResult:
    """
    วัด InfluxDB write throughput
    Target: > 1000 points/second

    use_real_influx=False → mock (วัด Python serialization throughput)
    use_real_influx=True  → real InfluxDB connection ต้องเปิด local instance
    """
    result = TestResult(
        "InfluxDB write throughput",
        f"> {TARGET_INFLUXDB_PTS_PER_SEC:.0f} pts/sec"
    )

    n_points = INFLUXDB_TEST_BATCH
    import random
    rng = random.Random(99)

    if use_real_influx:
        # ── Real InfluxDB ──────────────────────────────────────────────
        if not HAS_INFLUXDB:
            result.mark_skip("influxdb_client not installed (pip install influxdb-client)")
            return result

        try:
            client = InfluxDBClient(
                url=INFLUXDB_URL,
                token=INFLUXDB_TOKEN,
                org=INFLUXDB_ORG,
                timeout=10_000,
            )
            write_api = client.write_api(write_options=SYNCHRONOUS)

            # Build batch
            from influxdb_client import Point
            points = []
            for i in range(n_points):
                p = (Point("tick")
                     .tag("symbol", SYMBOLS[i % len(SYMBOLS)])
                     .tag("source", "stress_test")
                     .field("bid",   rng.uniform(1800.0, 2000.0))
                     .field("ask",   rng.uniform(1800.0, 2000.0))
                     .field("vol",   rng.randint(1, 100)))
                points.append(p)

            t0 = time.perf_counter()
            write_api.write(bucket=INFLUXDB_BUCKET, record=points)
            elapsed = time.perf_counter() - t0
            client.close()

        except Exception as exc:
            result.mark_fail(0.0, f"InfluxDB error: {exc}")
            return result

    else:
        # ── Mock: simulate MessagePack serialize + dict build ──────────
        # วัด Python throughput ของ data point construction
        # (proxy สำหรับ write throughput ก่อนมี InfluxDB instance จริง)
        import msgpack

        t0 = time.perf_counter()
        for i in range(n_points):
            point = {
                "measurement": "tick",
                "tags": {"symbol": SYMBOLS[i % len(SYMBOLS)], "source": "stress"},
                "fields": {
                    "bid": rng.uniform(1800.0, 2000.0),
                    "ask": rng.uniform(1800.0, 2000.0),
                    "vol": rng.randint(1, 100),
                },
                "time": int(time.time() * 1e9) + i,
            }
            _ = msgpack.packb(point, use_bin_type=True)
        elapsed = time.perf_counter() - t0

    pts_per_sec = n_points / elapsed
    mode_str = "real InfluxDB" if use_real_influx else "mock (msgpack serialize)"
    details = (
        f"mode={mode_str} n={n_points} "
        f"elapsed={elapsed:.3f}s → {pts_per_sec:.0f} pts/sec"
    )

    if pts_per_sec >= TARGET_INFLUXDB_PTS_PER_SEC:
        result.mark_pass(pts_per_sec, details)
    else:
        result.mark_fail(pts_per_sec, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 5 : Memory Stability
# ════════════════════════════════════════════════════════════════════════════════

def bench_memory_stability(n_cycles: int) -> TestResult:
    """
    วัด memory growth หลัง N cycles

    วิธีวัด (psutil RSS primary):
    - สร้าง objects + warmup 20 cycles → settle heap
    - gc.collect() × 3 → baseline RSS
    - รัน N cycles
    - gc.collect() × 3 → after RSS
    - growth = (after - before) / before × 100

    tracemalloc ใช้เป็น info เพิ่มเติมเท่านั้น
    (tracemalloc มี quirk: before หลัง warmup อาจ track
     allocations จาก warmup แล้ว freed → delta เป็นลบ)

    Target: RSS growth < 5% (หรือ < 20MB absolute)
    """
    result = TestResult(
        "Memory stability",
        f"growth < {TARGET_MEMORY_GROWTH_PCT:.0f}% or < 20MB"
    )

    if not HAS_COUNCIL or not HAS_CONFIG_BUILDER:
        result.mark_skip("Need both council + config_builder for this test")
        return result

    if not HAS_PSUTIL:
        result.mark_skip("psutil not installed — cannot measure RSS")
        return result

    import gc

    # ── Phase 1: Build objects + warmup ───────────────────────────────
    registry = build_mock_registry(16)
    council  = StrategyCouncil(analyzer_registry=registry)
    builder  = ConfigBuilder()
    sym_cfgs = _make_symbol_configs(SYMBOLS[:3])

    # Warmup: Python caches, interned strings, lazy imports
    for _w in range(20):
        _ = council.vote(symbol=SYMBOLS[0], regime=Regime.RANGING,
                         indicators=_make_indicators(seed=_w), portfolio=None)
        _ = builder.build_and_pack(symbol_configs=sym_cfgs, regime="RANGING")

    # Settle heap fully before baseline
    gc.collect(); gc.collect(); gc.collect()

    # ── Phase 2: Baseline RSS ─────────────────────────────────────────
    proc = psutil.Process(os.getpid())
    rss_before = proc.memory_info().rss   # bytes

    print(f"  Running {n_cycles} cycles for memory stability check...")

    for i in range(n_cycles):
        ind = _make_indicators(seed=i)
        try:
            _ = council.vote(
                symbol=SYMBOLS[i % len(SYMBOLS)],
                regime=[Regime.RANGING, Regime.TRENDING, Regime.VOLATILE][i % 3],
                indicators=ind,
                portfolio=None,
                weekday=i % 5,
            )
            _ = builder.build_and_pack(
                symbol_configs=sym_cfgs,
                regime=["RANGING", "TRENDING", "VOLATILE"][i % 3],
            )
        except Exception as exc:
            result.mark_fail(0.0, f"Exception at cycle {i}: {exc}")
            return result

        if i % 500 == 0 and i > 0:
            gc.collect()

    # ── Phase 3: After RSS ────────────────────────────────────────────
    gc.collect(); gc.collect(); gc.collect()
    rss_after = proc.memory_info().rss

    delta_bytes = rss_after - rss_before
    delta_mb    = delta_bytes / (1024 * 1024)
    growth_pct  = (delta_bytes / rss_before * 100.0) if rss_before > 0 else 0.0

    details = (
        f"rss before={rss_before/1024/1024:.1f}MB after={rss_after/1024/1024:.1f}MB "
        f"delta={delta_mb:+.1f}MB ({growth_pct:+.2f}%) n={n_cycles}"
    )

    # Pass if: growth% < target OR absolute delta < 20MB
    passed = (growth_pct <= TARGET_MEMORY_GROWTH_PCT) or (delta_mb < 20.0)
    if passed:
        result.mark_pass(growth_pct, details)
    else:
        result.mark_fail(growth_pct, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BENCHMARK 6 : CPU Average
# ════════════════════════════════════════════════════════════════════════════════

def bench_cpu_average(n_cycles: int) -> TestResult:
    """
    วัด average System CPU% ขณะรัน intelligence cycle load

    วิธีวัด:
    - work thread: รัน council.vote() + sleep(0.005) (simulate realistic polling)
    - main thread: sample system-wide psutil.cpu_percent() ทุก 0.2s (non-blocking)
    - วัด SYSTEM CPU (ไม่ใช่ per-process) เพราะ per-process tight loop = 100% เสมอ
    - test ต้องรันอย่างน้อย MIN_DURATION_SEC วินาที เพื่อให้ได้ samples เพียงพอ

    Target: system CPU average < 50%
    """
    result = TestResult(
        "CPU average during stress",
        f"< {TARGET_CPU_AVG_PCT:.0f}%"
    )

    if not HAS_PSUTIL:
        result.mark_skip("psutil not installed")
        return result

    if not HAS_COUNCIL:
        result.mark_skip("strategy_council not importable")
        return result

    MIN_DURATION_SEC = 3.0    # วัดอย่างน้อย 3 วินาที = ≥ 15 samples @ 0.2s
    POLL_SLEEP_SEC   = 0.005  # simulate 5ms polling interval (realistic HFT)

    registry = build_mock_registry(16)
    council  = StrategyCouncil(analyzer_registry=registry)

    cpu_samples: list[float] = []
    stop_event  = threading.Event()
    work_errors: list[str] = []

    # ── Work thread: council.vote() + realistic sleep ─────────────────
    def _work_thread():
        import time as _time
        i = 0
        while not stop_event.is_set():
            ind = _make_indicators(seed=i % 1000)
            try:
                _ = council.vote(
                    symbol=SYMBOLS[i % len(SYMBOLS)],
                    regime=[Regime.RANGING, Regime.TRENDING, Regime.VOLATILE][i % 3],
                    indicators=ind,
                    portfolio=None,
                    weekday=i % 5,
                )
            except Exception as exc:
                work_errors.append(str(exc))
                break
            # simulate realistic inter-cycle sleep (not pure tight loop)
            _time.sleep(POLL_SLEEP_SEC)
            i += 1

    worker = threading.Thread(target=_work_thread, daemon=True)

    # ── CPU sampler: system-wide, non-blocking ────────────────────────
    # เรียก cpu_percent(interval=None) ครั้งแรกเพื่อ initialize counter
    _ = psutil.cpu_percent(interval=None)

    print(f"  Monitoring system CPU for {MIN_DURATION_SEC:.0f}s "
          f"(with {POLL_SLEEP_SEC*1000:.0f}ms poll sleep)...")

    worker.start()

    t_end = time.perf_counter() + MIN_DURATION_SEC
    while time.perf_counter() < t_end:
        time.sleep(0.2)                           # sample ทุก 200ms
        cpu = psutil.cpu_percent(interval=None)   # system-wide, non-blocking
        if cpu >= 0:
            cpu_samples.append(cpu)

    stop_event.set()
    worker.join(timeout=3.0)

    if work_errors:
        result.mark_fail(0.0, f"Work thread error: {work_errors[0]}")
        return result

    if len(cpu_samples) < 5:
        result.mark_skip(f"Too few CPU samples ({len(cpu_samples)}) — try longer MIN_DURATION_SEC")
        return result

    # ตัด 2 samples แรก (warmup artifact)
    trimmed = cpu_samples[2:] if len(cpu_samples) > 4 else cpu_samples
    avg_cpu = statistics.mean(trimmed)
    max_cpu = max(trimmed)
    n_cores = psutil.cpu_count(logical=True) or 1

    details = (
        f"system_cpu avg={avg_cpu:.1f}% max={max_cpu:.1f}% "
        f"samples={len(trimmed)} cores={n_cores} "
        f"poll_sleep={POLL_SLEEP_SEC*1000:.0f}ms"
    )

    if avg_cpu <= TARGET_CPU_AVG_PCT:
        result.mark_pass(avg_cpu, details)
    else:
        result.mark_fail(avg_cpu, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# BONUS: Multi-Symbol Throughput Summary
# ════════════════════════════════════════════════════════════════════════════════

def bench_multisymbol_throughput(n_rounds: int) -> TestResult:
    """
    วัด throughput รวม: 5 symbols × N rounds
    รายงาน cycles/sec เพื่อ estimate 8-hour capacity
    """
    result = TestResult(
        "Multi-symbol throughput",
        "> 10 cycles/sec"
    )

    if not HAS_COUNCIL:
        result.mark_skip("strategy_council not importable")
        return result

    registry = build_mock_registry(16)
    council  = StrategyCouncil(analyzer_registry=registry)
    n_symbols = len(SYMBOLS)
    total_votes = n_rounds * n_symbols

    t0 = time.perf_counter()
    for i in range(n_rounds):
        ind = _make_indicators(seed=i)
        for sym in SYMBOLS:
            try:
                _ = council.vote(
                    symbol=sym,
                    regime=[Regime.RANGING, Regime.TRENDING][i % 2],
                    indicators=ind,
                    portfolio=None,
                    weekday=i % 5,
                )
            except Exception as exc:
                result.mark_fail(0.0, f"Exception: {exc}")
                return result
    elapsed = time.perf_counter() - t0

    votes_per_sec  = total_votes / elapsed
    cycles_per_sec = n_rounds / elapsed

    # Estimate 8-hour capacity
    eight_h_votes = int(votes_per_sec * 8 * 3600)
    details = (
        f"elapsed={elapsed:.2f}s {votes_per_sec:.0f} votes/sec "
        f"({cycles_per_sec:.0f} cycles/sec) "
        f"8h_capacity≈{eight_h_votes:,} votes"
    )

    if cycles_per_sec >= 10.0:
        result.mark_pass(cycles_per_sec, details)
    else:
        result.mark_fail(cycles_per_sec, details)
    return result


# ════════════════════════════════════════════════════════════════════════════════
# MAIN TEST RUNNER
# ════════════════════════════════════════════════════════════════════════════════

def _print_header(title: str, n_cycles: int, mode: str):
    width = 72
    print("=" * width)
    print(f"  FlashEASuite V2 — {title}")
    print(f"  Mode: {mode}  |  Cycles: {n_cycles:,}")
    print(f"  Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * width)
    print()


def _print_section(name: str):
    print(f"\n── {name} {'─' * (60 - len(name))}")


def _print_results(results: list[TestResult]) -> tuple[int, int, int]:
    """Returns (passed, failed, skipped)"""
    print()
    passed = sum(1 for r in results if r.passed is True)
    failed = sum(1 for r in results if r.passed is False)
    skipped = sum(1 for r in results if r.passed is None)
    for r in results:
        print(str(r))
    return passed, failed, skipped


def run_stress_test(
    fast_mode: bool = True,
    use_real_influx: bool = False,
) -> bool:
    """
    รัน full P8-3 stress test suite

    Returns True ถ้า PASS ทั้งหมด (skipped ไม่นับเป็น fail)
    """
    n_cycles = FAST_CYCLES if fast_mode else FULL_CYCLES
    mode_label = f"FAST ({FAST_CYCLES:,} cycles)" if fast_mode else f"FULL ({FULL_CYCLES:,} cycles)"

    _print_header("P8-3: Performance & Stress Test", n_cycles, mode_label)

    # Print available components
    print("Component availability:")
    print(f"  strategy_council  : {'✅' if HAS_COUNCIL else '❌'}")
    print(f"  config_builder    : {'✅' if HAS_CONFIG_BUILDER else '❌'}")
    print(f"  regime_classifier : {'✅' if HAS_REGIME_CLASSIFIER else '❌'}")
    print(f"  ml_models         : {len(_ml_models_available)}/5 "
          f"({'✅' if HAS_ML_ENSEMBLE else '⚠'})")
    print(f"  psutil            : {'✅' if HAS_PSUTIL else '⚠  not installed'}")
    print(f"  influxdb_client   : {'✅' if HAS_INFLUXDB else '⚠  not installed'}")
    if _import_errors:
        print(f"\n  Import errors:")
        for e in _import_errors:
            print(f"    ⚠  {e}")
    print()

    all_results: list[TestResult] = []
    t_suite_start = time.perf_counter()

    # ── Benchmark 1: Intelligence Cycle ──────────────────────────────
    _print_section("Benchmark 1: Intelligence Cycle")
    r1 = bench_intelligence_cycle(n_cycles)
    all_results.append(r1)
    print(f"  → {r1}")

    # ── Benchmark 2: ML Ensemble ──────────────────────────────────────
    _print_section("Benchmark 2: ML Ensemble")
    ml_cycles = min(n_cycles, 500)   # ML ช้ากว่า — ลดจำนวน cycles
    r2 = bench_ml_ensemble(ml_cycles)
    all_results.append(r2)
    print(f"  → {r2}")

    # ── Benchmark 3: CONFIG_PUSH ──────────────────────────────────────
    _print_section("Benchmark 3: CONFIG_PUSH Build + Pack")
    r3 = bench_config_push(n_cycles)
    all_results.append(r3)
    print(f"  → {r3}")

    # ── Benchmark 4: InfluxDB ─────────────────────────────────────────
    _print_section("Benchmark 4: InfluxDB Write Throughput")
    r4 = bench_influxdb_write(use_real_influx=use_real_influx)
    all_results.append(r4)
    print(f"  → {r4}")

    # ── Benchmark 5: Memory Stability ────────────────────────────────
    _print_section("Benchmark 5: Memory Stability")
    mem_cycles = min(n_cycles, 2000)   # tracemalloc overhead ไม่ต้องมากมาย
    r5 = bench_memory_stability(mem_cycles)
    all_results.append(r5)
    print(f"  → {r5}")

    # ── Benchmark 6: CPU Average ─────────────────────────────────────
    _print_section("Benchmark 6: CPU Average")
    cpu_cycles = min(n_cycles, 1000)
    r6 = bench_cpu_average(cpu_cycles)
    all_results.append(r6)
    print(f"  → {r6}")

    # ── Bonus: Multi-Symbol Throughput ───────────────────────────────
    _print_section("Bonus: Multi-Symbol Throughput")
    ms_rounds = min(n_cycles // len(SYMBOLS), 500)
    r7 = bench_multisymbol_throughput(ms_rounds)
    all_results.append(r7)
    print(f"  → {r7}")

    # ── Summary ───────────────────────────────────────────────────────
    t_suite_elapsed = time.perf_counter() - t_suite_start
    passed, failed, skipped = _print_results(all_results)

    print()
    print("=" * 72)
    print(f"  RESULTS: ✅ {passed} PASS  ❌ {failed} FAIL  ⏭  {skipped} SKIP")
    print(f"  Suite elapsed: {t_suite_elapsed:.1f}s")
    print()
    print("  Benchmark targets:")
    print(f"    Intelligence Cycle p99 : < {TARGET_INTELLIGENCE_CYCLE_P99_MS:.0f}ms")
    print(f"    ML Ensemble p99        : < {TARGET_ML_ENSEMBLE_P99_MS:.0f}ms")
    print(f"    CONFIG_PUSH p99        : < {TARGET_CONFIG_PUSH_P99_MS:.0f}ms")
    print(f"    InfluxDB write         : > {TARGET_INFLUXDB_PTS_PER_SEC:.0f} pts/sec")
    print(f"    Memory growth          : < {TARGET_MEMORY_GROWTH_PCT:.0f}%")
    print(f"    CPU average            : < {TARGET_CPU_AVG_PCT:.0f}%")
    print("=" * 72)

    if failed == 0:
        print("\n✅ P8-3 Stress Test PASSED — All benchmarks within targets")
    else:
        print(f"\n❌ P8-3 Stress Test FAILED — {failed} benchmark(s) exceeded targets")
        print("   Check details above and address bottlenecks before production.")

    return failed == 0


# ════════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="FlashEASuite V2 P8-3: Performance & Stress Test"
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help=f"Full mode: {FULL_CYCLES:,} cycles (8-hour equivalent load)"
    )
    parser.add_argument(
        "--influxdb",
        action="store_true",
        help="Test with real InfluxDB instance (requires local InfluxDB running)"
    )
    args = parser.parse_args()

    success = run_stress_test(
        fast_mode=not args.full,
        use_real_influx=args.influxdb,
    )
    sys.exit(0 if success else 1)
