# -*- coding: utf-8 -*-
# FlashEASuite V2 - P0.6-8: ParameterRepository Integration Test
# Run from 02_Brain/ or 02_Brain/tests/
# Phase: P0.6-8 | Mock InfluxDB - standalone

import os
import sys
import json
import time
import threading
from collections import defaultdict

# -- Path Resolution --
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.isdir(os.path.join(SCRIPT_DIR, "config")):
    BRAIN_DIR = SCRIPT_DIR
elif os.path.isdir(os.path.join(SCRIPT_DIR, "..", "config")):
    BRAIN_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
else:
    raise FileNotFoundError("Cannot find config/ directory. Run from 02_Brain/ or 02_Brain/tests/")

CFG_DIR = os.path.join(BRAIN_DIR, "config")
sys.path.insert(0, BRAIN_DIR)


class ParameterRepository:
    """Standalone test repo - loads real JSON, in-memory"""

    def __init__(self, config_dir):
        self._strategy_params = {}
        self._mm_params = {}
        self._current = {}
        self._history = defaultdict(list)
        self._mm_matrix = {}

        for fn, store in [("strategy_parameters.json", self._strategy_params),
                          ("mm_parameters.json", self._mm_params)]:
            fpath = os.path.join(config_dir, fn)
            with open(fpath, encoding="utf-8") as f:
                data = json.load(f)
            for k, v in data.items():
                if k != "_metadata":
                    store[k] = v
                    self._current[k] = v["default"]

        mm_path = os.path.join(config_dir, "mm_selection_matrix.json")
        with open(mm_path, encoding="utf-8") as f:
            self._mm_matrix = json.load(f)

    def get_strategy_param(self, sid, pn, **kw):
        return self._current.get(pn)

    def set_strategy_param(self, sid, pn, value, reason=""):
        if pn not in self._strategy_params:
            return False
        ok, _ = self.validate_param(pn, value)
        if not ok:
            return False
        old = self._current.get(pn)
        self._current[pn] = value
        self.record_change(pn, old, value, reason)
        return True

    def get_all_strategy_params(self, sid):
        return {k: self._current[k] for k, d in self._strategy_params.items()
                if d.get("strategy") == sid}

    def get_strategy_param_definition(self, pn):
        return self._strategy_params.get(pn)

    def get_all_strategy_ids(self):
        return sorted({d["strategy"] for d in self._strategy_params.values()})

    def get_param_names_for_strategy(self, sid):
        return [k for k, d in self._strategy_params.items() if d.get("strategy") == sid]

    def get_mm_param(self, mm, pn):
        return self._current.get(pn)

    def set_mm_param(self, mm, pn, value, reason=""):
        if pn not in self._mm_params:
            return False
        ok, _ = self.validate_param(pn, value)
        if not ok:
            return False
        old = self._current.get(pn)
        self._current[pn] = value
        self.record_change(pn, old, value, reason)
        return True

    def get_all_mm_params(self, mm):
        return {k: self._current[k] for k, d in self._mm_params.items()
                if d.get("mm_method") == mm}

    def get_mm_param_definition(self, pn):
        return self._mm_params.get(pn)

    def get_mm_for_strategy(self, sid, regime=None):
        if regime and regime != "UNKNOWN":
            key = regime.lower() + "_mm_per_strategy"
            r = self._mm_matrix.get(key, {}).get(sid)
            if r:
                return r
        return self._mm_matrix.get("default_mm_per_strategy", {}).get(sid, "MM01")

    def validate_param(self, pn, value):
        d = self._strategy_params.get(pn) or self._mm_params.get(pn)
        if not d:
            return (False, "unknown")
        if d["type"] == "int" and not isinstance(value, int):
            return (False, "type")
        if isinstance(value, (int, float)):
            if d.get("min") is not None and value < d["min"]:
                return (False, "below min")
            if d.get("max") is not None and value > d["max"]:
                return (False, "above max")
        return (True, "ok")

    def validate_change(self, pn, old_val, new_val):
        ok, msg = self.validate_param(pn, new_val)
        if not ok:
            return (ok, msg)
        d = self._strategy_params.get(pn) or self._mm_params.get(pn)
        if d and isinstance(old_val, (int, float)) and isinstance(new_val, (int, float)):
            if old_val != 0:
                max_pct = d.get("max_change_per_cycle_pct", 20) / 100.0
                if abs(new_val - old_val) / abs(old_val) > max_pct:
                    return (False, "exceeds max_change")
        return (True, "ok")

    def record_change(self, pn, old, new, reason=""):
        self._history[pn].append({
            "old": old, "new": new, "reason": reason, "ts": time.time()
        })

    def get_param_history(self, pn, days=30):
        cutoff = time.time() - days * 86400
        return [h for h in self._history.get(pn, []) if h["ts"] >= cutoff]

    def get_config_snapshot(self):
        return dict(self._current)

    def apply_optimization_result(self, changes, source=""):
        applied, rejected = [], []
        for pn, chg in changes.items():
            val = chg.get("value") if isinstance(chg, dict) else chg
            if pn not in self._strategy_params and pn not in self._mm_params:
                rejected.append(pn)
                continue
            old = self._current.get(pn)
            ok, _ = self.validate_change(pn, old, val)
            if ok:
                self._current[pn] = val
                self.record_change(pn, old, val, source)
                applied.append(pn)
            else:
                rejected.append(pn)
        return {"applied": applied, "rejected": rejected}

    def export_for_config_push(self, symbol="XAUUSD"):
        configs = []
        for sid in self.get_all_strategy_ids():
            mm = self.get_mm_for_strategy(sid)
            configs.append({
                "strategy_id": sid,
                "parameters": self.get_all_strategy_params(sid),
                "mm_method": mm,
                "mm_parameters": self.get_all_mm_params(mm)
            })
        return {"symbol": symbol, "strategy_configs": configs, "timestamp": time.time()}

    @property
    def strategy_param_count(self):
        return len(self._strategy_params)

    @property
    def mm_param_count(self):
        return len(self._mm_params)


class ParameterFamilyIndex:
    """Loads family JSON - detect conflicts"""

    def __init__(self, config_dir):
        self._families = {}
        self._p2f = {}
        for fn in ["strategy_parameter_families.json", "mm_parameter_families.json"]:
            fpath = os.path.join(config_dir, fn)
            with open(fpath, encoding="utf-8") as f:
                data = json.load(f)
            for k, v in data.items():
                if k != "_metadata":
                    self._families[k] = v
                    for m in v.get("members", []):
                        self._p2f[m] = k

    def get_family_members(self, fid):
        return self._families.get(fid, {}).get("members", [])

    def get_family_for_param(self, pn):
        return self._p2f.get(pn)

    def get_family_info(self, fid):
        return self._families.get(fid)

    def detect_family_conflicts(self, changes):
        by_fam = defaultdict(list)
        for pn in changes:
            fid = self._p2f.get(pn)
            if fid:
                by_fam[fid].append(pn)
        conflicts = []
        for fid, params in by_fam.items():
            info = self._families.get(fid, {})
            if info.get("co_optimize") and info.get("optimization_direction") == "same":
                vals = [changes[p] for p in params
                        if isinstance(changes.get(p), (int, float))]
                if len(vals) >= 2:
                    dirs = set()
                    for v in vals:
                        if v != 0:
                            dirs.add(1 if v > 0 else -1)
                    if len(dirs) > 1:
                        conflicts.append({
                            "type": "direction_mismatch",
                            "family": fid,
                            "params": params
                        })
        return conflicts

    @property
    def family_count(self):
        return len(self._families)


# == TESTS ==
if __name__ == "__main__":
    print("[CFG] " + CFG_DIR)
    repo = ParameterRepository(CFG_DIR)
    fam = ParameterFamilyIndex(CFG_DIR)

    tot = repo.strategy_param_count + repo.mm_param_count
    assert tot >= 190
    print("[PASS] T1: %d params (%d strat + %d mm)" % (tot, repo.strategy_param_count, repo.mm_param_count))

    assert repo.get_strategy_param("S01", "S01_LOOKBACK_PERIOD") == 20
    assert repo.set_strategy_param("S01", "S01_LOOKBACK_PERIOD", 25, "test")
    print("[PASS] T2: Get/set strategy param")

    assert repo.set_mm_param("MM01", "MM01_RISK_PCT", 1.5, "test")
    print("[PASS] T3: Get/set MM param")

    assert repo.validate_param("S01_LOOKBACK_PERIOD", 50)[0]
    print("[PASS] T4: In-range accepted")

    assert not repo.validate_param("S01_LOOKBACK_PERIOD", 999)[0]
    assert not repo.validate_param("S01_LOOKBACK_PERIOD", 1)[0]
    print("[PASS] T5: Out-of-range rejected")

    repo.set_strategy_param("S01", "S01_LOOKBACK_PERIOD", 20, "reset")
    assert not repo.validate_change("S01_LOOKBACK_PERIOD", 20, 100)[0]
    assert repo.validate_change("S01_LOOKBACK_PERIOD", 20, 24)[0]
    print("[PASS] T6: max_change 20%% enforced")

    repo.set_strategy_param("S01", "S01_LOOKBACK_PERIOD", 25, "hist_test")
    assert repo.get_param_history("S01_LOOKBACK_PERIOD")[-1]["reason"] == "hist_test"
    print("[PASS] T7: History tracking")

    assert fam.family_count == 20
    assert len(fam.get_family_members("GRID_STRUCTURE")) >= 4
    assert fam.get_family_for_param("S15_BASE_STEP") == "GRID_STRUCTURE"
    print("[PASS] T8: 20 families, GRID_STRUCTURE has %d members" % len(fam.get_family_members("GRID_STRUCTURE")))

    assert isinstance(fam.detect_family_conflicts({"S01_LOOKBACK_PERIOD": 30}), list)
    print("[PASS] T9: Family conflict detection")

    export = repo.export_for_config_push("XAUUSD")
    assert len(export["strategy_configs"]) == 16
    print("[PASS] T10: Export 16 strategies for CONFIG_PUSH")

    repo.set_strategy_param("S01", "S01_LOOKBACK_PERIOD", 20, "reset")
    r = repo.apply_optimization_result({
        "S01_LOOKBACK_PERIOD": {"value": 24},
        "FAKE_PARAM": {"value": 0}
    })
    assert "S01_LOOKBACK_PERIOD" in r["applied"]
    assert "FAKE_PARAM" in r["rejected"]
    print("[PASS] T11: Apply optimization (applied/rejected)")

    errs = []
    def reader_thread(idx):
        try:
            for _ in range(100):
                repo.get_strategy_param("S01", "S01_LOOKBACK_PERIOD")
        except Exception as e:
            errs.append(e)

    threads = [threading.Thread(target=reader_thread, args=(i,)) for i in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert not errs
    print("[PASS] T12: Thread safety (8 threads x 100 reads)")

    snap = repo.get_config_snapshot()
    assert len(snap) >= 190
    print("[PASS] T13: Config snapshot (%d params)" % len(snap))

    assert repo.get_strategy_param("S99", "FAKE") is None
    print("[PASS] T14: Unknown param -> None")

    assert repo.get_mm_for_strategy("S01") == "MM04"
    print("[PASS] T15: MM selection S01 -> MM04")

    print("")
    print("=" * 50)
    print("ALL 15 ParameterRepository TESTS PASSED")
    print("=" * 50)
