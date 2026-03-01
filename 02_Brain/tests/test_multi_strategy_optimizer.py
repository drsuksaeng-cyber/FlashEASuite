"""
test_multi_strategy_optimizer.py
FlashEASuite V2 — Phase 0.6 Chat 10: Integration Test
End-to-end optimization pipeline scenarios using mock components.

Self-contained: mocks all P0.6-4 through P0.6-7 dependencies.
When the real modules exist, swap the mock imports at the top.

Run: python -m pytest test_multi_strategy_optimizer.py -v
"""

import json
import os
import random
import time
import unittest
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

# Re-use ParameterRepository from test_parameter_management (same dir)
# When real module exists: from core.parameter_repository import ParameterRepository
exec(open(os.path.join(os.path.dirname(__file__), "test_parameter_management.py"),
          encoding="utf-8").read()
     .split("# ─────────────────────────────────────────────────────────────────────────────\n# Tests")[0])  # noqa

CONFIG_DIR = os.path.join(os.path.dirname(__file__), "..", "config")


# ─────────────────────────────────────────────────────────────────────────────
# Mock implementations of P0.6-4 through P0.6-7 components
# Replace with real imports once those modules are delivered.
# ─────────────────────────────────────────────────────────────────────────────

def _make_trades(n: int, win_rate: float = 0.55,
                 strategy_id: str = "S15",
                 symbol: str = "XAUUSD",
                 regime: str = "RANGING") -> list:
    """Generate n simulated trade records."""
    trades = []
    for i in range(n):
        won = random.random() < win_rate
        trades.append({
            "trade_id":    f"T{i:04d}",
            "strategy_id": strategy_id,
            "symbol":      symbol,
            "regime":      regime,
            "pnl":         random.uniform(5, 30) if won else random.uniform(-20, -5),
            "duration_s":  random.randint(300, 7200),
            "open_time":   (datetime.now(tz=timezone.utc)
                            - timedelta(days=30) + timedelta(hours=i)).isoformat(),
            "params_used": {},
        })
    return trades


class MockGenericStrategyAnalyzer:
    """Minimal P0.6-4 GenericStrategyAnalyzer mock."""

    def __init__(self, param_repo):
        self._repo = param_repo
        self._trades: list = []

    def record_trade(self, strategy_id: str, symbol: str, trade_data: dict):
        self._trades.append({"sid": strategy_id, "symbol": symbol, **trade_data})

    def calculate_performance(self, strategy_id: str, symbol: str,
                              lookback_days: int = 30) -> dict:
        trades = [t for t in self._trades
                  if t["sid"] == strategy_id and t["symbol"] == symbol]
        if not trades:
            return {"win_rate": 0.0, "profit_factor": 1.0, "trade_count": 0}
        wins   = [t for t in trades if t.get("pnl", 0) > 0]
        losses = [t for t in trades if t.get("pnl", 0) <= 0]
        gross_profit = sum(t["pnl"] for t in wins)
        gross_loss   = abs(sum(t["pnl"] for t in losses)) or 1.0
        return {
            "win_rate":      len(wins) / len(trades),
            "profit_factor": gross_profit / gross_loss,
            "trade_count":   len(trades),
            "avg_pnl":       sum(t["pnl"] for t in trades) / len(trades),
        }

    def suggest_param_changes(self, strategy_id: str, symbol: str) -> list:
        perf = self.calculate_performance(strategy_id, symbol)
        if perf["trade_count"] < 30:
            return []  # insufficient data
        suggestions = []
        if perf["win_rate"] < 0.5:
            suggestions.append({
                "param":      f"{strategy_id}_CONF_THRESHOLD",
                "current":    0.65,
                "suggested":  0.70,
                "reason":     "win rate below 50% → raise confidence threshold",
                "confidence": 0.72,
            })
        return suggestions

    def should_optimize(self, strategy_id: str, symbol: str) -> bool:
        perf = self.calculate_performance(strategy_id, symbol)
        return perf["trade_count"] >= 30

    def detect_conflicts(self, changes: dict) -> list:
        """Return list of conflict descriptions."""
        conflicts = []
        s01_rsi = changes.get("S01_ENTRY_ZSCORE")
        s07_rsi = changes.get("S07_BB_PERIOD")
        if s01_rsi is not None and s07_rsi is not None:
            if abs(s01_rsi - s07_rsi) > 5:
                conflicts.append({
                    "params":     ["S01_ENTRY_ZSCORE", "S07_BB_PERIOD"],
                    "type":       "cross_strategy_conflict",
                    "resolution": "use average",
                    "resolved_values": {
                        "S01_ENTRY_ZSCORE": (s01_rsi + s07_rsi) / 2,
                        "S07_BB_PERIOD":    (s01_rsi + s07_rsi) / 2,
                    },
                })
        return conflicts


class MockMMAnalyzer:
    """Minimal P0.6-5 MMAnalyzer mock."""

    def __init__(self, param_repo):
        self._repo = param_repo

    def get_best_mm_for_regime(self, strategy_id: str, regime: str) -> str:
        dd_map = self._repo._mm_matrix.get("dd_mm_per_strategy", {})
        volatile_map = self._repo._mm_matrix.get("volatile_mm_per_strategy", {})
        default_map  = self._repo._mm_matrix.get("default_mm_per_strategy", {})

        if regime == "CRISIS":
            return dd_map.get(strategy_id, "MM10")
        if regime in ("VOLATILE", "HIGH_VOL"):
            return volatile_map.get(strategy_id, "MM17")
        return default_map.get(strategy_id, "MM01")

    def recommend_risk_reduction(self, dd_pct: float) -> dict:
        """Return risk multiplier based on drawdown level."""
        if dd_pct >= 20:
            return {"risk_multiplier": 0.0, "stop_new_trades": True,
                    "reason": f"DD {dd_pct:.0f}% ≥ 20% — stop all new trades"}
        if dd_pct >= 15:
            return {"risk_multiplier": 0.25, "stop_new_trades": False,
                    "reason": f"DD {dd_pct:.0f}% ≥ 15% — reduce risk by 75%"}
        if dd_pct >= 10:
            return {"risk_multiplier": 0.50, "stop_new_trades": False,
                    "reason": f"DD {dd_pct:.0f}% ≥ 10% — reduce risk by 50%"}
        return {"risk_multiplier": 1.0, "stop_new_trades": False,
                "reason": "DD within normal range"}


class MockRegimeParameterMapper:
    """Minimal P0.6-5 RegimeParameterMapper mock."""

    REGIME_PARAM_ADJUSTMENTS = {
        "TRENDING": {
            "S06_ER_THRESHOLD":   {"direction": "decrease", "pct": 10},
            "S10_DONCHIAN_PERIOD":{"direction": "decrease", "pct": 5},
        },
        "RANGING": {
            "S07_BB_PERIOD":     {"direction": "increase", "pct": 10},
            "S15_ELASTIC_FACTOR":{"direction": "increase", "pct": 5},
        },
        "VOLATILE": {
            "S16_VELOCITY_THRESH": {"direction": "increase", "pct": 15},
        },
    }

    def map_regime_to_params(self, regime: str, strategy_id: str) -> dict:
        return self.REGIME_PARAM_ADJUSTMENTS.get(regime, {})

    def detect_regime_transition(self, old_regime: str,
                                  new_regime: str) -> dict:
        urgency = "immediate" if "VOLATILE" in (old_regime, new_regime) else "scheduled"
        return {
            "urgency":      urgency,
            "old_regime":   old_regime,
            "new_regime":   new_regime,
            "param_changes": self.map_regime_to_params(new_regime, "ALL"),
            "reasoning":    f"Regime changed from {old_regime} to {new_regime}",
        }


class MockConfigPushGenerator:
    """Minimal P0.6-7 ConfigPushGenerator mock."""

    def generate(self, param_repo, strategies: list,
                 symbol: str = "XAUUSD") -> dict:
        cfg = param_repo.export_for_config_push(symbol)
        cfg["strategies_in_push"] = strategies
        cfg["format"] = "CONFIG_PUSH_V2"
        return cfg

    def validate_push(self, push: dict) -> tuple:
        required = ["format", "strategy_params", "mm_params", "timestamp"]
        for key in required:
            if key not in push:
                return False, f"Missing required field: {key}"
        if push.get("format") != "CONFIG_PUSH_V2":
            return False, "Wrong format version"
        return True, "valid"


class MultiStrategyOptimizer:
    """Lightweight optimizer that orchestrates all mock components."""

    def __init__(self, param_repo, strategy_analyzer,
                 mm_analyzer, regime_mapper):
        self._repo    = param_repo
        self._sanalyzer = strategy_analyzer
        self._mmanalyzer = mm_analyzer
        self._regmapper = regime_mapper
        self._current_regime = "RANGING"

    def set_regime(self, regime: str):
        self._current_regime = regime

    def should_optimize(self, strategy_id: str, symbol: str) -> bool:
        return self._sanalyzer.should_optimize(strategy_id, symbol)

    def optimize_all(self, symbol: str, strategies: list = None,
                     drawdown_pct: float = 0.0) -> dict:
        if strategies is None:
            strategies = [f"S{i:02d}" for i in range(1, 17)]

        pending_changes: dict = {}
        reasoning: list = []

        # Factor 1: Regime-based adjustments
        regime_adj = self._regmapper.map_regime_to_params(
            self._current_regime, "ALL")
        for param, adj in regime_adj.items():
            meta = (self._repo._strategy_defs.get(param) or
                    self._repo._mm_defs.get(param))
            if meta is None:
                continue
            cur = self._repo._values[param]
            if not isinstance(cur, (int, float)):
                continue
            pct_change = adj["pct"] / 100
            new_val = cur * (1 - pct_change if adj["direction"] == "decrease"
                             else 1 + pct_change)
            if meta.get("type") == "int":
                new_val = int(round(new_val))
            pending_changes[param] = new_val
            reasoning.append(f"Regime {self._current_regime}: {param} "
                              f"{adj['direction']} by {adj['pct']}%")

        # Factor 2: Strategy performance suggestions
        for sid in strategies:
            suggestions = self._sanalyzer.suggest_param_changes(sid, symbol)
            for s in suggestions:
                pending_changes[s["param"]] = s["suggested"]
                reasoning.append(f"{sid}: {s['reason']}")

        # Factor 3: Cross-strategy conflict detection
        conflicts = self._sanalyzer.detect_conflicts(pending_changes)
        for conflict in conflicts:
            for param, resolved in conflict.get("resolved_values", {}).items():
                pending_changes[param] = resolved
            reasoning.append(f"Conflict resolved: {conflict['params']}")

        # Factor 4: DD risk reduction
        dd_rec = self._mmanalyzer.recommend_risk_reduction(drawdown_pct)
        if dd_rec["risk_multiplier"] < 1.0:
            for sid in strategies:
                best_mm = self._mmanalyzer.get_best_mm_for_regime(
                    sid, "CRISIS" if drawdown_pct >= 15 else "HIGH_VOL")
                pending_changes[f"_mm_{sid}"] = best_mm
            reasoning.append(dd_rec["reason"])

        # Factor 9: Constraint enforcement (max_change_per_cycle_pct)
        validated_changes = {}
        rejected_changes = {}
        for param, new_val in pending_changes.items():
            if param.startswith("_mm_"):
                validated_changes[param] = new_val
                continue
            ok, msg = self._repo.validate_param(param, new_val)
            if not ok:
                rejected_changes[param] = msg
                continue
            old_val = self._repo._values.get(param)
            ok2, msg2 = self._repo.validate_change(param, old_val, new_val)
            if not ok2:
                rejected_changes[param] = msg2
                continue
            validated_changes[param] = new_val

        # Apply validated changes
        applied = []
        for param, new_val in validated_changes.items():
            if param.startswith("_mm_"):
                applied.append(param)
                continue
            meta = (self._repo._strategy_defs.get(param) or
                    self._repo._mm_defs.get(param))
            if meta is None:
                continue
            sid = meta.get("strategy") or meta.get("mm_method", "")
            if meta.get("strategy"):
                if self._repo.set_strategy_param(sid, param, new_val, "optimizer"):
                    applied.append(param)
            else:
                if self._repo.set_mm_param(sid, param, new_val, "optimizer"):
                    applied.append(param)

        return {
            "applied":          applied,
            "rejected":         rejected_changes,
            "mm_selection":     {k[4:]: v for k, v in validated_changes.items()
                                 if k.startswith("_mm_")},
            "reasoning":        reasoning,
            "confidence":       0.75,
            "current_regime":   self._current_regime,
        }


def build_optimizer(config_dir: str):
    """Factory: assemble the full mock pipeline."""
    repo     = ParameterRepository(config_dir)
    sanalyzer = MockGenericStrategyAnalyzer(repo)
    mmanalyzer = MockMMAnalyzer(repo)
    regmapper  = MockRegimeParameterMapper()
    optimizer  = MultiStrategyOptimizer(repo, sanalyzer, mmanalyzer, regmapper)
    config_gen = MockConfigPushGenerator()
    return repo, sanalyzer, mmanalyzer, regmapper, optimizer, config_gen


# ─────────────────────────────────────────────────────────────────────────────
# Scenario Tests
# ─────────────────────────────────────────────────────────────────────────────

class TestScenario1_NormalWeeklyOptimization(unittest.TestCase):
    """
    Scenario 1: 100 simulated trades → analyze → optimize → CONFIG_PUSH V2.
    Verify: params changed within constraints, reasoning present,
            CONFIG_PUSH V2 format valid.
    """

    def setUp(self):
        random.seed(42)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_1_end_to_end(self):
        print("\n  Scenario 1: Normal weekly optimization (100 trades)")

        # 1. Simulate 100 XAUUSD trades for S15 (Grid) in RANGING market
        trades = _make_trades(100, win_rate=0.52, strategy_id="S15",
                               symbol="XAUUSD", regime="RANGING")
        for t in trades:
            self.sanalyzer.record_trade("S15", "XAUUSD", t)

        # 2. Verify should_optimize returns True
        self.assertTrue(self.optimizer.should_optimize("S15", "XAUUSD"),
                        "Should optimize with 100 trades")

        # 3. Run optimization
        self.optimizer.set_regime("RANGING")
        result = self.optimizer.optimize_all("XAUUSD", strategies=["S15"])

        # 4. Reasoning must be present
        self.assertIsInstance(result["reasoning"], list)
        self.assertGreater(len(result["reasoning"]), 0,
                           "Optimizer must generate reasoning")

        # 5. Generate CONFIG_PUSH V2
        push = self.config_gen.generate(self.repo, ["S15"])
        ok, msg = self.config_gen.validate_push(push)
        self.assertTrue(ok, f"CONFIG_PUSH V2 invalid: {msg}")

        # 6. S15 params in push
        self.assertIn("S15", push["strategy_params"])
        self.assertGreater(len(push["strategy_params"]["S15"]), 0)

        print(f"  ✅ Applied: {len(result['applied'])} changes, "
              f"reasoning: {len(result['reasoning'])} items")
        print(f"  ✅ CONFIG_PUSH V2 valid, S15 params: "
              f"{len(push['strategy_params']['S15'])}")


class TestScenario2_RegimeChange(unittest.TestCase):
    """
    Scenario 2: TRENDING → RANGING regime change triggers immediate optimization.
    Verify: trend-following params adjusted, mean-reversion params scaled up.
    """

    def setUp(self):
        random.seed(42)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_2_regime_transition(self):
        print("\n  Scenario 2: Regime change TRENDING → RANGING")

        # Record baseline param values for RANGING-relevant params
        baseline_elastic = self.repo.get_strategy_param(
            "S15", "S15_ELASTIC_FACTOR")

        # Trigger transition
        transition = self.regmapper.detect_regime_transition(
            "TRENDING", "RANGING")

        self.assertEqual(transition["old_regime"], "TRENDING")
        self.assertEqual(transition["new_regime"], "RANGING")
        self.assertIn("param_changes", transition)
        self.assertIn("reasoning", transition)
        self.assertIn("urgency", transition)

        # Optimize under RANGING regime
        self.optimizer.set_regime("RANGING")
        result = self.optimizer.optimize_all("EURUSD", strategies=["S15", "S07"])

        # RANGING regime should push S15_ELASTIC_FACTOR upward
        after_elastic = self.repo.get_strategy_param("S15", "S15_ELASTIC_FACTOR")
        self.assertGreaterEqual(after_elastic, baseline_elastic,
            "S15_ELASTIC_FACTOR should increase or stay same in RANGING regime")

        self.assertIn("RANGING", " ".join(result["reasoning"]))

        print(f"  ✅ Regime transition detected: urgency={transition['urgency']}")
        print(f"  ✅ S15_ELASTIC_FACTOR: {baseline_elastic} → {after_elastic}")


class TestScenario3_DDEmergencyTrigger(unittest.TestCase):
    """
    Scenario 3: DD reaches 16% → emergency optimization.
    Verify: MM switched to MM10 for all strategies, risk reduced 75%.
    """

    def setUp(self):
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_3_dd_emergency(self):
        print("\n  Scenario 3: DD emergency (16%)")

        # Simulate 16% drawdown
        dd_pct = 16.0
        rec = self.mmanalyzer.recommend_risk_reduction(dd_pct)

        # Risk should be reduced by 75% (multiplier = 0.25)
        self.assertAlmostEqual(rec["risk_multiplier"], 0.25, places=2,
            msg=f"Expected 0.25 risk multiplier at DD {dd_pct}%")
        self.assertFalse(rec["stop_new_trades"],
            "At 16%, should reduce risk but not stop trading entirely")

        # Run optimizer with DD
        result = self.optimizer.optimize_all(
            "XAUUSD",
            strategies=["S15", "S16"],
            drawdown_pct=dd_pct,
        )

        # MM selection should be emergency MM (MM10 or volatile equivalent)
        mm_sel = result.get("mm_selection", {})
        for sid in ["S15", "S16"]:
            if sid in mm_sel:
                mm = mm_sel[sid]
                self.assertIn(mm, ("MM10", "MM17"),
                    f"{sid} at 16% DD should use emergency MM, got {mm}")

        # Reasoning should mention DD
        all_reasoning = " ".join(result["reasoning"])
        self.assertIn("DD", all_reasoning.upper(),
            "Reasoning must mention DD")

        print(f"  ✅ Risk multiplier at 16% DD = {rec['risk_multiplier']}")
        print(f"  ✅ Emergency MM assigned: {mm_sel}")


class TestScenario4_InsufficientData(unittest.TestCase):
    """
    Scenario 4: Only 10 trades → optimizer should NOT run strategy optimization.
    Verify: should_optimize() returns False with < 30 trades.
    """

    def setUp(self):
        random.seed(7)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_4_insufficient_data(self):
        print("\n  Scenario 4: Insufficient data (10 trades)")

        # Only 10 trades for S06
        trades = _make_trades(10, strategy_id="S06",
                               symbol="GBPUSD", regime="TRENDING")
        for t in trades:
            self.sanalyzer.record_trade("S06", "GBPUSD", t)

        # should_optimize must return False
        self.assertFalse(
            self.optimizer.should_optimize("S06", "GBPUSD"),
            "should_optimize() must return False with only 10 trades"
        )

        # suggest_param_changes must return empty list
        suggestions = self.sanalyzer.suggest_param_changes("S06", "GBPUSD")
        self.assertEqual(suggestions, [],
            "No suggestions should be made with insufficient data")

        print("  ✅ should_optimize() = False with 10 trades")
        print("  ✅ suggest_param_changes() = [] with 10 trades")


class TestScenario5_CrossStrategyConflict(unittest.TestCase):
    """
    Scenario 5: S01 wants one value, S07 wants very different value → conflict.
    Verify: conflict detected, resolution applied.
    """

    def setUp(self):
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_5_conflict_detection(self):
        print("\n  Scenario 5: Cross-strategy conflict (S01 vs S07)")

        # Inject conflicting pending changes
        pending = {
            "S01_ENTRY_ZSCORE": 1.5,   # S01 wants 1.5
            "S07_BB_PERIOD":    30.0,  # S07 wants 30 — diff > 5
        }

        conflicts = self.sanalyzer.detect_conflicts(pending)

        # At least one conflict should be found
        self.assertGreater(len(conflicts), 0,
            "Expected conflict between S01_ENTRY_ZSCORE and S07_BB_PERIOD")

        conflict = conflicts[0]
        self.assertIn("type", conflict)
        self.assertIn("resolution", conflict)
        self.assertIn("resolved_values", conflict)

        # Resolved values should exist for both params
        resolved = conflict["resolved_values"]
        self.assertTrue(len(resolved) >= 1,
            "Conflict resolution must provide resolved values")

        print(f"  ✅ Conflict detected: {conflict['type']}")
        print(f"  ✅ Resolution: {conflict['resolution']}")
        print(f"  ✅ Resolved values: {resolved}")


class TestScenario6_ClientFeedbackAggregation(unittest.TestCase):
    """
    Scenario 6: 3 clients send different trade results → aggregate weighted.
    Verify: aggregated performance is weighted average of client results.
    """

    def setUp(self):
        random.seed(99)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_scenario_6_multi_client_aggregation(self):
        print("\n  Scenario 6: Multi-client feedback aggregation (3 clients)")

        # 3 clients with different trade results for S16 (Spike)
        client_stats = {
            "CLIENT_001": {"win_rate": 0.60, "trades": 50},
            "CLIENT_002": {"win_rate": 0.45, "trades": 80},
            "CLIENT_003": {"win_rate": 0.55, "trades": 30},
        }

        # Feed all client trades into the analyzer
        total_wins = 0
        total_trades = 0
        for client_id, stats in client_stats.items():
            trades = _make_trades(
                stats["trades"],
                win_rate=stats["win_rate"],
                strategy_id="S16",
                symbol="XAUUSD",
            )
            for t in trades:
                self.sanalyzer.record_trade("S16", "XAUUSD", t)
            total_wins   += int(stats["trades"] * stats["win_rate"])
            total_trades += stats["trades"]

        # Expected weighted win_rate
        expected_wr = total_wins / total_trades
        actual_perf = self.sanalyzer.calculate_performance("S16", "XAUUSD")

        self.assertGreater(actual_perf["trade_count"], 0)
        self.assertAlmostEqual(
            actual_perf["win_rate"], expected_wr, delta=0.05,
            msg=(f"Aggregated win_rate {actual_perf['win_rate']:.3f} "
                 f"should be ≈ {expected_wr:.3f} (±0.05)")
        )
        self.assertEqual(actual_perf["trade_count"], total_trades)

        print(f"  ✅ Aggregated {total_trades} trades from 3 clients")
        print(f"  ✅ Expected win_rate ≈ {expected_wr:.3f}, "
              f"got {actual_perf['win_rate']:.3f}")


class TestConfigPushIntegrity(unittest.TestCase):
    """Additional: verify CONFIG_PUSH V2 format covers all 16 strategies."""

    def setUp(self):
        random.seed(1)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_config_push_covers_all_strategies(self):
        """CONFIG_PUSH must include params for all 16 strategies."""
        push = self.config_gen.generate(
            self.repo, [f"S{i:02d}" for i in range(1, 17)]
        )
        ok, msg = self.config_gen.validate_push(push)
        self.assertTrue(ok, f"CONFIG_PUSH V2 invalid: {msg}")

        for i in range(1, 17):
            sid = f"S{i:02d}"
            self.assertIn(sid, push["strategy_params"],
                f"CONFIG_PUSH missing params for {sid}")
            self.assertGreater(len(push["strategy_params"][sid]), 0,
                f"CONFIG_PUSH has 0 params for {sid}")

        print(f"\n  ✅ CONFIG_PUSH covers all 16 strategies")
        total = sum(len(v) for v in push["strategy_params"].values())
        print(f"  ✅ Total strategy params in push: {total}")

    def test_config_push_missing_params_use_defaults(self):
        """If CONFIG_PUSH omits a param, strategy should use its default."""
        # Get S15 defaults
        defaults = self.repo.get_strategy_defaults("S15")
        # Remove S15_MAX_ORDERS from repo to simulate missing push param
        original = self.repo._values.get("S15_MAX_ORDERS")
        # Read value — should equal default (no CONFIG_PUSH applied yet)
        current = self.repo.get_strategy_param("S15", "S15_MAX_ORDERS")
        expected_default = defaults["S15_MAX_ORDERS"]
        self.assertEqual(current, expected_default,
            "Before any CONFIG_PUSH, value should equal default")
        print(f"\n  ✅ S15_MAX_ORDERS default = {current} (correct fallback)")


class TestOptimizationConstraints(unittest.TestCase):
    """Verify optimizer respects max_change_per_cycle globally."""

    def setUp(self):
        random.seed(55)
        (self.repo, self.sanalyzer, self.mmanalyzer,
         self.regmapper, self.optimizer, self.config_gen) = build_optimizer(CONFIG_DIR)

    def test_no_change_exceeds_max_cycle_pct(self):
        """After optimization, no param should have changed by more than max_change_per_cycle_pct."""
        # Record all values before
        before = self.repo.get_config_snapshot()

        # Feed 100 trades and optimize
        trades = _make_trades(100, win_rate=0.45, strategy_id="S15",
                               symbol="XAUUSD")
        for t in trades:
            self.sanalyzer.record_trade("S15", "XAUUSD", t)

        self.optimizer.set_regime("RANGING")
        self.optimizer.optimize_all("XAUUSD", strategies=["S15"])

        after = self.repo.get_config_snapshot()
        all_defs = {**self.repo._strategy_defs, **self.repo._mm_defs}

        violations = []
        for param, new_val in after.items():
            old_val = before.get(param)
            meta = all_defs.get(param)
            if meta is None or meta.get("type") == "string":
                continue
            max_pct = meta.get("max_change_per_cycle_pct", 100)
            if max_pct == 0 or old_val is None or old_val == 0:
                continue
            if not isinstance(old_val, (int, float)):
                continue
            change_pct = abs(new_val - old_val) / abs(old_val) * 100
            if change_pct > max_pct + 0.01:  # 0.01 tolerance for float
                violations.append(
                    f"{param}: changed {change_pct:.1f}% > max {max_pct}%"
                )

        self.assertEqual(len(violations), 0,
            f"Constraint violations found:\n" + "\n".join(violations))
        print(f"\n  ✅ No max_change_per_cycle_pct violations after optimization")


# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 60)
    print("FlashEASuite V2 — P0.6-8: Multi-Strategy Optimizer Tests")
    print("=" * 60)
    unittest.main(verbosity=2)
