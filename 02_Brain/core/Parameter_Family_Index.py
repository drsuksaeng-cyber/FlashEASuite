"""
FlashEASuite V2 — P0.6-3: Parameter Family Index
Manage 20 parameter families (14 strategy + 6 MM)
Co-optimization groups, conflict detection, cross-strategy analysis
"""
import json, os
from typing import Optional
from collections import defaultdict


class ParameterFamilyIndex:
    """Manage 20 parameter families (14 strategy + 6 MM)"""

    def __init__(self, config_dir: str):
        self._sfam: dict = {}  # strategy families
        self._mfam: dict = {}  # MM families
        self._rev: dict = {}   # param_name -> family_id
        self._sdefs: dict = {} # strategy param defs (for cross-ref)
        self._mdefs: dict = {} # MM param defs
        # Load families
        for k, v in self._lj(config_dir, "strategy_parameter_families.json").items():
            if not k.startswith("_"): v["_t"] = "s"; self._sfam[k] = v
        for k, v in self._lj(config_dir, "mm_parameter_families.json").items():
            if not k.startswith("_"): v["_t"] = "m"; self._mfam[k] = v
        # Load param defs for cross-ref
        for k, v in self._lj(config_dir, "strategy_parameters.json").items():
            if not k.startswith("_"): self._sdefs[k] = v
        for k, v in self._lj(config_dir, "mm_parameters.json").items():
            if not k.startswith("_"): self._mdefs[k] = v
        # Build reverse index
        for fid, fd in {**self._sfam, **self._mfam}.items():
            for m in fd.get("members", []):
                self._rev[m] = fid

    @staticmethod
    def _lj(d, fn):
        try:
            with open(os.path.join(d, fn), 'r', encoding='utf-8') as f: return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError): return {}

    def get_family_members(self, fid: str) -> list:
        fd = self._sfam.get(fid) or self._mfam.get(fid)
        return list(fd.get("members", [])) if fd else []

    def get_family_for_param(self, pn: str) -> Optional[str]:
        r = self._rev.get(pn)
        if r: return r
        d = self._sdefs.get(pn) or self._mdefs.get(pn)
        return d.get("family") if d else None

    def get_family_info(self, fid: str) -> Optional[dict]:
        return self._sfam.get(fid) or self._mfam.get(fid)

    def get_all_families(self) -> dict:
        r = {}
        for fid, fd in {**self._sfam, **self._mfam}.items():
            r[fid] = {"type": "strategy" if fd.get("_t")=="s" else "mm",
                       "member_count": len(fd.get("members",[])),
                       "co_optimize": fd.get("co_optimize", False),
                       "direction": fd.get("optimization_direction","independent")}
        return r

    def get_cross_strategy_params(self, fid: str) -> dict:
        """Group family members by strategy/MM method"""
        g = defaultdict(list)
        for m in self.get_family_members(fid):
            sd = self._sdefs.get(m)
            if sd: g[sd.get("strategy","?")].append(m); continue
            md = self._mdefs.get(m)
            if md: g[md.get("mm_method","?")].append(m)
        return dict(g)

    def detect_family_conflicts(self, changes: dict) -> list:
        """Detect conflicts: direction mismatch, DD tier order, portfolio cap"""
        conflicts = []
        fc = defaultdict(dict)
        for p, v in changes.items():
            f = self.get_family_for_param(p)
            if f: fc[f][p] = v
        for fid, params in fc.items():
            fd = self.get_family_info(fid)
            if fd is None: continue
            # Same-direction check
            if fd.get("co_optimize") and fd.get("optimization_direction") == "same":
                nums = {}
                for p, nv in params.items():
                    d = self._sdefs.get(p) or self._mdefs.get(p)
                    if d and d.get("type") in ("int","double"):
                        try: nums[p] = {"def": float(d["default"]), "new": float(nv)}
                        except (ValueError, TypeError): pass
                if len(nums) >= 2:
                    dirs = {p: "up" if v["new"]>v["def"] else ("down" if v["new"]<v["def"] else "same")
                            for p, v in nums.items()}
                    active = {p:d for p,d in dirs.items() if d!="same"}
                    if len(set(active.values())) > 1:
                        conflicts.append({"type":"direction_mismatch","family":fid,
                                          "params":list(active.keys()),
                                          "message":f"{fid}: same-direction required but mixed"})
            # DD tier order
            if fid == "MM_DD":
                t1 = float(params.get("MM10_DD_TIER1_PCT", 10))
                t2 = float(params.get("MM10_DD_TIER2_PCT", 15))
                st = float(params.get("MM10_DD_STOP_PCT", 20))
                has_multi = sum(1 for k in ["MM10_DD_TIER1_PCT","MM10_DD_TIER2_PCT","MM10_DD_STOP_PCT"] if k in params) >= 2
                if has_multi and not (t1 < t2 < st):
                    conflicts.append({"type":"dd_tier_order","params":list(params.keys()),
                                      "message":f"DD tiers: {t1}%<{t2}%<{st}% violated"})
            # Portfolio cap
            if fid == "MM_PORT":
                cap = params.get("MM18_PORTFOLIO_CAP_PCT")
                pt = params.get("MM18_PER_TRADE_MAX_PCT")
                if cap is not None and pt is not None and float(pt) > float(cap):
                    conflicts.append({"type":"portfolio_cap",
                                      "params":["MM18_PORTFOLIO_CAP_PCT","MM18_PER_TRADE_MAX_PCT"],
                                      "message":f"Per-trade {pt}% > cap {cap}%"})
        return conflicts

    def get_co_optimize_groups(self) -> list:
        groups = []
        for fid, fd in {**self._sfam, **self._mfam}.items():
            if fd.get("co_optimize") and len(fd.get("members",[])) >= 2:
                groups.append({"family": fid, "type": "strategy" if fd.get("_t")=="s" else "mm",
                               "direction": fd.get("optimization_direction","same"),
                               "members": fd.get("members",[]),
                               "notes": fd.get("optimization_notes_en", fd.get("notes",""))})
        return groups

    def get_independent_params(self) -> list:
        r = []
        for _, fd in {**self._sfam, **self._mfam}.items():
            if not fd.get("co_optimize"): r.extend(fd.get("members",[]))
        return r

    @property
    def strategy_family_count(self): return len(self._sfam)
    @property
    def mm_family_count(self): return len(self._mfam)
    @property
    def total_families(self): return len(self._sfam)+len(self._mfam)
    def __repr__(self):
        return f"<FamilyIndex: {self.strategy_family_count}s+{self.mm_family_count}m={self.total_families} fam, {len(self._rev)} indexed>"


# === Inline Tests ===
def _run_tests(cfg):
    print("[TEST] ParameterFamilyIndex...")
    ix = ParameterFamilyIndex(cfg); print(f"  {ix}")
    assert ix.strategy_family_count == 14 and ix.mm_family_count == 6; print(f"  [OK] T1: 14+6=20 families")
    g = ix.get_family_members("GRID_STRUCTURE")
    assert "S15_BASE_STEP" in g and "S15_ELASTIC_FACTOR" in g; print(f"  [OK] T2: GRID {len(g)} members")
    assert ix.get_family_for_param("S15_ELASTIC_FACTOR") == "GRID_STRUCTURE"
    assert ix.get_family_for_param("MM01_RISK_PCT") == "MM_RISK"; print("  [OK] T3: reverse lookup")
    assert ix.get_family_for_param("NONEXIST") is None; print("  [OK] T4: unknown=None")
    c = ix.get_cross_strategy_params("ENTRY_THRESHOLD")
    assert len(c) > 1; print(f"  [OK] T5: ENTRY_THRESHOLD spans {len(c)} strategies")
    c = ix.get_cross_strategy_params("MM_RISK")
    assert "MM01" in c; print(f"  [OK] T6: MM_RISK spans {len(c)} methods")
    gr = ix.get_co_optimize_groups()
    assert len(gr) > 0
    gg = [g for g in gr if g["family"]=="GRID_STRUCTURE"]
    assert len(gg)==1 and gg[0]["direction"]=="same"; print(f"  [OK] T7: {len(gr)} co-opt groups")
    cf = ix.detect_family_conflicts({"MM10_DD_TIER1_PCT":15,"MM10_DD_TIER2_PCT":10,"MM10_DD_STOP_PCT":20})
    assert any(c["type"]=="dd_tier_order" for c in cf); print("  [OK] T8: DD conflict detected")
    cf = ix.detect_family_conflicts({"MM10_DD_TIER1_PCT":8,"MM10_DD_TIER2_PCT":14,"MM10_DD_STOP_PCT":20})
    assert not any(c["type"]=="dd_tier_order" for c in cf); print("  [OK] T9: correct DD ok")
    cf = ix.detect_family_conflicts({"MM18_PORTFOLIO_CAP_PCT":5,"MM18_PER_TRADE_MAX_PCT":10})
    assert any(c["type"]=="portfolio_cap" for c in cf); print("  [OK] T10: portfolio cap conflict")
    ind = ix.get_independent_params()
    assert len(ind) > 0; print(f"  [OK] T11: {len(ind)} independent params")
    af = ix.get_all_families()
    assert len(af)==20 and af["GRID_STRUCTURE"]["type"]=="strategy"; print("  [OK] T12: get_all_families")
    print(f"\n[TEST] All 12 PASSED ✅")

if __name__ == "__main__":
    import sys; _run_tests(sys.argv[1] if len(sys.argv)>1 else "02_Brain/config")