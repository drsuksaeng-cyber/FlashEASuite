# -*- coding: utf-8 -*-
# FlashEASuite V2 - P0.6-8: Optimization Pipeline Integration Test
# 6 End-to-end scenarios + 3 bonus scheduler tests
# Run from 02_Brain/ or 02_Brain/tests/
# Phase: P0.6-8 | Depends: P0.6-3 to P0.6-7

import os
import sys
import time
import random
from collections import defaultdict

# -- Path Resolution --
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.isdir(os.path.join(SCRIPT_DIR, "config")):
    BRAIN_DIR = SCRIPT_DIR
elif os.path.isdir(os.path.join(SCRIPT_DIR, "..", "config")):
    BRAIN_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
else:
    raise FileNotFoundError("Cannot find config/. Run from 02_Brain/ or 02_Brain/tests/")

CFG_DIR = os.path.join(BRAIN_DIR, "config")
sys.path.insert(0, BRAIN_DIR)
sys.path.insert(0, SCRIPT_DIR)

# -- Import companion test repo --
from test_parameter_repository import ParameterRepository, ParameterFamilyIndex

# -- Import real modules from core/ --
from core.intelligence.generic_strategy_analyzer import GenericStrategyAnalyzer
from core.feedback.multi_strategy_feedback import MultiStrategyFeedback
from core.optimization.optimization_scheduler import OptimizationScheduler

GENERIC = set(["S%02d" % i for i in range(1, 15)])
REGIMES = {"TRENDING", "RANGING", "VOLATILE", "CRISIS", "UNKNOWN"}


# == Mocks ==

class MockMMAnalyzer:
    def __init__(self):
        self._trades = defaultdict(list)

    def record_trade(self, mm, sym, td):
        self._trades[(mm, sym)].append(td)

    def get_best_mm_for_regime(self, sid, regime):
        if regime == "CRISIS":
            return "MM10"
        return None

    def get_dd_override_recommendation(self, dd):
        if dd >= 15:
            return {"override_active": True, "switch_to": "MM10", "risk_reduction": 0.75}
        return {"override_active": False}


class MockRegimeMapper:
    MULTS = {
        "TRENDING": {"entry_sensitivity": 0.9},
        "RANGING": {"entry_sensitivity": 1.2},
        "VOLATILE": {"entry_sensitivity": 0.7},
        "CRISIS": {"entry_sensitivity": 0.5},
    }

    def map_regime_to_params(self, regime, sid):
        return {"adjustment_multipliers": self.MULTS.get(regime, {})}


class MockConflictDetector:
    def detect_conflicts(self, grouped):
        rsi = {}
        for s, ps in grouped.items():
            for p, v in ps.items():
                if "rsi" in p.lower():
                    rsi[s] = v
        if len(rsi) >= 2 and (max(rsi.values()) - min(rsi.values())) > 10:
            return [{"type": "opposing", "severity": "high", "strategies": list(rsi)}]
        return []


class MockConfigGen:
    def generate(self, opt, **kw):
        return {
            "type": 10,
            "version": 2,
            "regime": opt.get("regime"),
            "reasoning": opt.get("reasoning", {}),
        }

    def pack_to_messagepack(self, cp):
        return b"\x01"


# == Mini Optimizer ==

class MiniOptimizer:
    def __init__(self, repo, analyzer, mm_az, regime_map, conflict=None):
        self.param_repo = repo
        self.strategy_analyzer = analyzer
        self.mm_analyzer = mm_az
        self.regime_mapper = regime_map
        self.conflict = conflict
        self._regime = "UNKNOWN"

    def should_optimize(self, symbol, min_trades=30):
        total = 0
        for s in GENERIC:
            total += self.strategy_analyzer.get_trade_count(s, symbol)
        return total >= min_trades

    def optimize_all(self, symbol="XAUUSD", regime=None, dd_pct=0.0, **kw):
        if regime and regime in REGIMES:
            self._regime = regime
        regime = self._regime
        pending = {}

        # F1: Regime adjustments
        for sid in self.strategy_analyzer.get_active_strategies():
            mapping = self.regime_mapper.map_regime_to_params(regime, sid)
            mults = mapping.get("adjustment_multipliers", {})
            for pn in self.param_repo.get_param_names_for_strategy(sid):
                d = self.param_repo.get_strategy_param_definition(pn)
                if not d:
                    continue
                if not d.get("regime_sensitive"):
                    continue
                if d.get("type") not in ("int", "double"):
                    continue
                cur = self.param_repo.get_strategy_param(sid, pn)
                if not isinstance(cur, (int, float)):
                    continue
                m = None
                if d.get("category") == "signal_generation":
                    m = mults.get("entry_sensitivity")
                if m is None or m == 1.0:
                    continue
                nv = cur * m
                if d.get("min"):
                    nv = max(nv, float(d["min"]))
                if d.get("max"):
                    nv = min(nv, float(d["max"]))
                step = d.get("step")
                if step and step > 0:
                    if d["type"] == "int":
                        nv = int(round(nv / step) * step)
                    else:
                        nv = round(round(nv / step) * step, 4)
                if nv != cur:
                    pending[pn] = {
                        "value": nv,
                        "reason": "Regime %s" % regime,
                        "confidence": 0.7,
                    }

        # F2: Effectiveness suggestions
        for sid in self.strategy_analyzer.get_active_strategies():
            for s in self.strategy_analyzer.suggest_param_changes(sid, symbol):
                pn = s["param"]
                if pn not in pending or s.get("confidence", 0) > pending[pn].get("confidence", 0):
                    pending[pn] = {
                        "value": s["suggested"],
                        "reason": s["reason"],
                        "confidence": s.get("confidence", 0.5),
                    }

        # F3: Conflict removal
        removed = []
        if self.conflict:
            gr = defaultdict(dict)
            for pn, ch in pending.items():
                d = self.param_repo.get_strategy_param_definition(pn)
                if d:
                    gr[d["strategy"]][pn] = ch.get("value")
            for c in self.conflict.detect_conflicts(dict(gr)):
                if c.get("severity") == "high":
                    for sid in c.get("strategies", []):
                        for pn in list(pending):
                            d = self.param_repo.get_strategy_param_definition(pn)
                            if d and d.get("strategy") == sid:
                                removed.append(pn)
        for pn in removed:
            pending.pop(pn, None)

        # F9+F10: Constraints + confidence filter
        final = {}
        for pn, ch in pending.items():
            if ch.get("confidence", 0.5) < 0.5:
                continue
            d = self.param_repo.get_strategy_param_definition(pn)
            if not d:
                d = self.param_repo.get_mm_param_definition(pn)
            if not d:
                continue
            sid = d.get("strategy")
            cur = self.param_repo.get_strategy_param(sid, pn) if sid else None
            if cur is None:
                continue
            ok, _ = self.param_repo.validate_change(pn, cur, ch["value"])
            if ok:
                final[pn] = ch
            else:
                # Clamp to max allowed change
                mx = abs(cur * d.get("max_change_per_cycle_pct", 20) / 100.0)
                if ch["value"] > cur:
                    cl = cur + mx
                else:
                    cl = cur - mx
                if d.get("min"):
                    cl = max(cl, float(d["min"]))
                if d.get("max"):
                    cl = min(cl, float(d["max"]))
                step = d.get("step")
                if step:
                    if d["type"] == "int":
                        cl = int(round(cl / step) * step)
                    else:
                        cl = round(round(cl / step) * step, 4)
                if cl != cur:
                    c2 = dict(ch)
                    c2["value"] = cl
                    final[pn] = c2

        # MM selection
        mm_sel = {}
        for sid in self.param_repo.get_all_strategy_ids():
            if dd_pct >= 15:
                rec = self.mm_analyzer.get_dd_override_recommendation(dd_pct)
                if rec.get("override_active"):
                    mm_sel[sid] = "MM10"
                    continue
            best = self.mm_analyzer.get_best_mm_for_regime(sid, regime)
            if best:
                mm_sel[sid] = best
            else:
                mm_sel[sid] = self.param_repo.get_mm_for_strategy(sid, regime)

        # Overall confidence
        confs = [c.get("confidence", 0.5) for c in final.values()]
        overall = sum(confs) / len(confs) if confs else 0.0

        # Apply
        applied = False
        if final and overall >= 0.5:
            r = self.param_repo.apply_optimization_result(final, source="optimizer")
            applied = len(r.get("applied", [])) > 0

        reasoning = {
            "summary_th": "Opt %s (%s) -- %d changes" % (symbol, regime, len(final)),
            "changes": [],
            "total_changes": len(final),
        }

        return {
            "strategy_changes": {},
            "mm_changes": {},
            "mm_selection": mm_sel,
            "reasoning": reasoning,
            "confidence": round(overall, 4),
            "applied": applied,
            "total_changes": len(final),
            "factors_used": ["F1", "F2", "F3", "F9", "F10"],
            "regime": regime,
        }


def inject_trades(az, sid, sym, n, seed=42):
    random.seed(seed)
    for _ in range(n):
        az.record_trade(sid, sym, {
            "direction": "BUY",
            "entry_price": 2000,
            "exit_price": 2010,
            "pnl": random.uniform(-50, 80),
            "duration_seconds": random.randint(60, 3600),
            "params_used": {"S01_LOOKBACK_PERIOD": random.choice([15, 20, 25, 30])},
            "mm_used": "MM04",
            "regime_at_entry": random.choice(["TRENDING", "RANGING", "VOLATILE"]),
            "timestamp": time.time() - random.randint(0, 86400 * 30),
        })


# == MAIN ==
if __name__ == "__main__":
    print("[CFG] " + CFG_DIR)

    repo = ParameterRepository(CFG_DIR)
    fam = ParameterFamilyIndex(CFG_DIR)
    az = GenericStrategyAnalyzer(repo)
    mm = MockMMAnalyzer()
    rm = MockRegimeMapper()
    cd = MockConflictDetector()
    cg = MockConfigGen()
    opt = MiniOptimizer(repo, az, mm, rm, cd)

    # -- S1: Normal weekly optimization --
    inject_trades(az, "S01", "XAUUSD", 100)
    assert opt.should_optimize("XAUUSD")
    r = opt.optimize_all("XAUUSD", regime="TRENDING")
    assert "reasoning" in r and r["reasoning"]["summary_th"]
    cp = cg.generate(r)
    assert cp["type"] == 10
    print("[PASS] S1: Weekly -- %d changes, conf=%.2f, applied=%s" % (
        r["total_changes"], r["confidence"], r["applied"]))

    # -- S2: Regime change TRENDING -> RANGING --
    for pn in repo.get_param_names_for_strategy("S01"):
        d = repo.get_strategy_param_definition(pn)
        if d:
            repo._current[pn] = d["default"]
    r_tr = opt.optimize_all("XAUUSD", regime="TRENDING")
    snap_tr = dict(repo._current)

    for pn in repo.get_param_names_for_strategy("S01"):
        d = repo.get_strategy_param_definition(pn)
        if d:
            repo._current[pn] = d["default"]
    r_rn = opt.optimize_all("XAUUSD", regime="RANGING")
    snap_rn = dict(repo._current)

    sig_params = []
    for p in repo.get_param_names_for_strategy("S01"):
        d = repo.get_strategy_param_definition(p)
        if d and d.get("category") == "signal_generation" and d.get("regime_sensitive"):
            sig_params.append(p)
    if sig_params:
        assert snap_rn.get(sig_params[0], 0) >= snap_tr.get(sig_params[0], 0)
    print("[PASS] S2: Regime TRENDING->RANGING -- signal params adjusted")

    # -- S3: DD emergency -> all MM10 --
    r_dd = opt.optimize_all("XAUUSD", regime="VOLATILE", dd_pct=16.0)
    assert all(v == "MM10" for v in r_dd["mm_selection"].values())
    print("[PASS] S3: DD=16%% -- all %d strategies -> MM10" % len(r_dd["mm_selection"]))

    # -- S4: Insufficient data --
    fresh = GenericStrategyAnalyzer(repo)
    inject_trades(fresh, "S01", "EURUSD", 10, seed=99)
    opt2 = MiniOptimizer(repo, fresh, mm, rm)
    assert not opt2.should_optimize("EURUSD")
    sch = OptimizationScheduler(optimizer=opt2, config_gen=cg)
    ok, reason = sch.check_data_sufficient("EURUSD")
    assert not ok
    print("[PASS] S4: 10 trades -> should_optimize=False (%s)" % reason)

    # -- S5: Cross-strategy conflict --
    conflicts = cd.detect_conflicts({
        "S01": {"MOCK_RSI_A": 25},
        "S07": {"MOCK_RSI_B": 55},
    })
    assert len(conflicts) > 0 and conflicts[0]["severity"] == "high"
    print("[PASS] S5: Conflict detected -- RSI spread=30 > threshold=10")

    # -- S6: Client feedback aggregation --
    fb = MultiStrategyFeedback(generic_analyzer=az, mm_analyzer=mm)
    random.seed(42)
    for cid in ["A", "B", "C"]:
        reps = []
        for _ in range(20):
            reps.append({
                "symbol": "XAUUSD",
                "strategy_id": "S01",
                "order_type": 0,
                "open_price": 2000,
                "close_price": 2010,
                "profit": random.uniform(-30, 60),
                "mm_used": "MM04",
                "regime_at_entry": "TRENDING",
                "params_used": {"S01_LOOKBACK_PERIOD": 20},
            })
        fb.aggregate_client_feedback("CLI_" + cid, reps)

    wf = fb.get_weighted_feedback("S01", "XAUUSD")
    assert wf["client_count"] == 3
    assert isinstance(wf["weighted_pnl"], (int, float))
    assert 0 <= wf["weighted_win_rate"] <= 1.0
    assert len(fb.get_client_profiles()) == 3
    print("[PASS] S6: 3 clients x 20 trades, weighted_pnl=%.2f, WR=%.2f%%" % (
        wf["weighted_pnl"], wf["weighted_win_rate"] * 100))

    # -- Bonus: Scheduler triggers --
    sch3 = OptimizationScheduler(optimizer=opt, config_gen=cg)
    sch3.update_drawdown(16.0)
    should, reason = sch3.should_optimize()
    assert should and "EMERGENCY" in reason
    print("[PASS] B1: DD trigger -- %s" % reason)

    sch3._last_optimize_ts = time.time() - 25 * 3600
    sch3.update_drawdown(3.0)
    trig = sch3.update_regime("RANGING")
    assert trig and "REGIME_CHANGE" in trig
    print("[PASS] B2: Regime trigger -- %s" % trig)

    res = sch3.run_optimization_cycle("XAUUSD", trigger=trig)
    assert res["success"]
    print("[PASS] B3: Full cycle -- changes=%s" % res["changes"])

    print("")
    print("=" * 50)
    print("ALL 6 SCENARIOS + 3 BONUS PASSED")
    print("=" * 50)
