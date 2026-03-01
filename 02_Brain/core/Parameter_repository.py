"""
FlashEASuite V2 — P0.6-3: Unified Parameter Repository
Single Source of Truth สำหรับ 198 dynamic parameters (136 strategy + 62 MM)
Hierarchical resolution: strategy→symbol→TF→broker | Thread-safe | InfluxDB history
"""
import json, os, threading
from datetime import datetime, timezone
from typing import Any, Optional
from collections import defaultdict


def _cast(value: Any, ptype: str) -> Any:
    if ptype == "int": return int(round(float(value)))
    if ptype == "double": return float(value)
    if ptype == "string": return str(value)
    return value


class ParameterRepository:
    """Unified repository สำหรับ dynamic parameters ทั้งหมด"""

    def __init__(self, config_dir: str, influx_writer=None):
        self._config_dir = config_dir
        self._influx = influx_writer
        self._lock = threading.RLock()
        self._sdefs: dict = {}          # strategy param definitions
        self._mdefs: dict = {}          # MM param definitions
        self._matrix: dict = {}         # MM selection matrix
        self._vals: dict = {}           # current values
        self._ovr: dict = defaultdict(dict)  # overrides: param -> {(sym,tf,brk): val}
        self._hist: list = []
        # Load
        for k, v in self._ljson("strategy_parameters.json").items():
            if not k.startswith("_"): v["_src"] = "s"; self._sdefs[k] = v
        for k, v in self._ljson("mm_parameters.json").items():
            if not k.startswith("_"): v["_src"] = "m"; self._mdefs[k] = v
        self._matrix = self._ljson("mm_selection_matrix.json")
        for n, d in {**self._sdefs, **self._mdefs}.items():
            self._vals[n] = _cast(d["default"], d["type"])

    def _ljson(self, fn: str) -> dict:
        try:
            with open(os.path.join(self._config_dir, fn), 'r', encoding='utf-8') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            print(f"[ParamRepo] WARN: {fn}: {e}"); return {}

    def _gdef(self, n: str) -> Optional[dict]:
        return self._sdefs.get(n) or self._mdefs.get(n)

    def _resolve(self, n, sym=None, tf=None, brk=None) -> Any:
        o = self._ovr.get(n, {})
        if o:
            for k in [(sym,tf,brk),(sym,tf,None),(sym,None,None)]:
                if k[0] is not None and k in o: return o[k]
        return self._vals.get(n)

    def _vdef(self, d: dict, v: Any) -> tuple:
        if d.get("type") == "string":
            return (isinstance(v, str), "OK" if isinstance(v, str) else "Expected str")
        try: vf = float(v)
        except (ValueError, TypeError): return (False, f"Not numeric: {v!r}")
        lo, hi = d.get("min"), d.get("max")
        if lo is not None and vf < float(lo): return (False, f"{vf} < min {lo}")
        if hi is not None and vf > float(hi): return (False, f"{vf} > max {hi}")
        return (True, "OK")

    def _rec(self, n, old, new, reason, src, sid=None, mm=None, sym=None):
        r = {"ts": datetime.now(timezone.utc).isoformat(), "param_name": n,
             "old": old, "new": new, "reason": reason, "source": src,
             "sid": sid, "mm": mm, "symbol": sym}
        self._hist.append(r)
        if len(self._hist) > 10000: self._hist = self._hist[-10000:]
        if self._influx: self._winflux(r)

    def _winflux(self, r):
        try:
            from influxdb_client import Point
            d = self._gdef(r["param_name"])
            meas = "strategy_parameter_history" if r.get("sid") else "mm_parameter_history"
            p = Point(meas).tag("param_name", r["param_name"]).tag("change_source", r["source"])
            for tag, key in [("strategy_id","sid"),("mm_method","mm"),("symbol","symbol")]:
                if r.get(key): p = p.tag(tag, r[key])
            if d: p = p.tag("family", d.get("family","")).tag("category", d.get("category",""))
            if d and d.get("type") in ("int","double"):
                try:
                    p = p.field("value", float(r["new"]))
                    if r["old"] is not None:
                        p = p.field("old_value", float(r["old"]))
                        of = float(r["old"])
                        if of != 0: p = p.field("change_pct", round((float(r["new"])-of)/of*100, 2))
                except (ValueError, TypeError): pass
            p = p.field("reason", r.get("reason",""))
            self._influx.write(bucket="flashea_params_raw", record=p)
        except Exception as e:
            print(f"[ParamRepo] InfluxDB err: {e}")

    # === Strategy Parameters ===
    def get_strategy_param(self, sid: str, pn: str, symbol=None, tf=None, broker=None) -> Any:
        with self._lock:
            d = self._sdefs.get(pn)
            if d is None or d.get("strategy") != sid: return None
            return self._resolve(pn, symbol, tf, broker)

    def set_strategy_param(self, sid: str, pn: str, value: Any,
                           reason="", symbol=None, tf=None, broker=None, source="manual") -> bool:
        with self._lock:
            d = self._sdefs.get(pn)
            if d is None or d.get("strategy") != sid: return False
            c = _cast(value, d["type"])
            ok, _ = self._vdef(d, c)
            if not ok: return False
            old = self._resolve(pn, symbol, tf, broker)
            if symbol or tf or broker:
                self._ovr[pn][(symbol, tf, broker)] = c
            else:
                self._vals[pn] = c
            self._rec(pn, old, c, reason, source, sid=sid, sym=symbol)
            return True

    def get_all_strategy_params(self, sid: str) -> dict:
        with self._lock:
            return {n: self._vals.get(n) for n, d in self._sdefs.items() if d.get("strategy") == sid}

    def get_strategy_defaults(self, sid: str) -> dict:
        return {n: _cast(d["default"], d["type"]) for n, d in self._sdefs.items()
                if d.get("strategy") == sid}

    def get_strategy_param_definition(self, n: str) -> Optional[dict]:
        return self._sdefs.get(n)

    # === MM Parameters ===
    def get_mm_param(self, mm: str, pn: str) -> Any:
        with self._lock:
            d = self._mdefs.get(pn)
            if d is None or d.get("mm_method") != mm: return None
            return self._vals.get(pn)

    def set_mm_param(self, mm: str, pn: str, value: Any, reason="", source="manual") -> bool:
        with self._lock:
            d = self._mdefs.get(pn)
            if d is None or d.get("mm_method") != mm: return False
            c = _cast(value, d["type"])
            ok, _ = self._vdef(d, c)
            if not ok: return False
            old = self._vals.get(pn)
            self._vals[pn] = c
            self._rec(pn, old, c, reason, source, mm=mm)
            return True

    def get_all_mm_params(self, mm: str) -> dict:
        with self._lock:
            return {n: self._vals.get(n) for n, d in self._mdefs.items() if d.get("mm_method") == mm}

    def get_mm_param_definition(self, n: str) -> Optional[dict]:
        return self._mdefs.get(n)

    def get_mm_for_strategy(self, sid: str, regime=None, dd_pct=None) -> str:
        """DD override → regime → default → MM01"""
        with self._lock:
            mx = self._matrix
            if dd_pct is not None:
                for tier in ["dd_20pct","dd_15pct","dd_10pct"]:
                    t = mx.get("dd_overrides",{}).get(tier,{})
                    if dd_pct >= t.get("threshold_pct", 999):
                        return t.get("switch_to", t.get("only_mm","MM10"))
            if regime == "CRISIS":
                return mx.get("dd_mm_per_strategy",{}).get(sid, "MM10")
            if regime == "VOLATILE":
                r = mx.get("volatile_mm_per_strategy",{}).get(sid)
                if r: return r
            r = mx.get("default_mm_per_strategy",{}).get(sid)
            return r if r else mx.get("standalone_default",{}).get("mm_method","MM01")

    # === Validation ===
    def validate_param(self, pn: str, value: Any) -> tuple:
        d = self._gdef(pn)
        if d is None: return (False, f"Unknown: {pn}")
        return self._vdef(d, _cast(value, d["type"]))

    def validate_change(self, pn: str, old_val, new_val) -> tuple:
        d = self._gdef(pn)
        if d is None: return (False, f"Unknown: {pn}")
        c = _cast(new_val, d["type"])
        ok, msg = self._vdef(d, c)
        if not ok: return (ok, msg)
        if d.get("type") not in ("int","double"): return (True, "OK")
        mp = d.get("max_change_per_cycle_pct")
        if mp is None or mp >= 100: return (True, "OK")
        try: of, nf = float(old_val), float(c)
        except (ValueError, TypeError): return (True, "OK")
        if of == 0: return (True, "OK")
        act = abs((nf - of) / of) * 100.0
        if act > mp: return (False, f"Change {act:.1f}% > max {mp}%")
        return (True, "OK")

    # === History ===
    def record_change(self, pn, old, new, reason, source="manual"):
        d = self._gdef(pn)
        sid = d.get("strategy") if d and d.get("_src")=="s" else None
        mm = d.get("mm_method") if d and d.get("_src")=="m" else None
        self._rec(pn, old, new, reason, source, sid=sid, mm=mm)

    def get_param_history(self, pn: str, limit=100) -> list:
        with self._lock:
            return [r for r in self._hist if r["param_name"]==pn][-limit:]

    # === Batch Operations ===
    def get_config_snapshot(self) -> dict:
        with self._lock:
            return {"timestamp": datetime.now(timezone.utc).isoformat(),
                    "total_params": len(self._sdefs)+len(self._mdefs),
                    "strategy_params": dict(self._vals),
                    "overrides_count": sum(len(v) for v in self._ovr.values())}

    def apply_optimization_result(self, changes: dict, source="optimizer") -> dict:
        ap, rj, er = [], [], []
        with self._lock:
            for pn, ci in changes.items():
                nv, reason = ci.get("value"), ci.get("reason","optimization")
                d = self._gdef(pn)
                if d is None: er.append({"param":pn,"error":"Unknown"}); continue
                cur = self._vals.get(pn)
                ok, msg = self.validate_change(pn, cur, nv)
                if not ok: rj.append({"param":pn,"reason":msg,"attempted":nv,"current":cur}); continue
                c = _cast(nv, d["type"]); old = self._vals.get(pn); self._vals[pn] = c
                sid = d.get("strategy") if d.get("_src")=="s" else None
                mm = d.get("mm_method") if d.get("_src")=="m" else None
                self._rec(pn, old, c, reason, source, sid=sid, mm=mm)
                ap.append({"param":pn,"old":old,"new":c})
        return {"applied": ap, "rejected": rj, "errors": er}

    def export_for_config_push(self, symbol: str, strategies=None) -> dict:
        with self._lock:
            res = {"msg_type":"CONFIG_PUSH_V2","symbol":symbol,
                   "timestamp":datetime.now(timezone.utc).isoformat(),"strategies":{}}
            sg = defaultdict(dict)
            for n, d in self._sdefs.items():
                s = d.get("strategy")
                if strategies and s not in strategies: continue
                sg[s][n] = self._resolve(n, symbol)
            for s, params in sorted(sg.items()):
                mm = self.get_mm_for_strategy(s)
                mp = {n: self._vals.get(n) for n, d in self._mdefs.items() if d.get("mm_method")==mm}
                res["strategies"][s] = {"strategy_params":params,"mm_method":mm,"mm_params":mp}
            return res

    # === Override Management ===
    def set_override(self, pn, value, symbol=None, tf=None, broker=None, reason="") -> bool:
        with self._lock:
            d = self._gdef(pn)
            if d is None: return False
            c = _cast(value, d["type"])
            ok, _ = self._vdef(d, c)
            if not ok: return False
            key = (symbol, tf, broker)
            old = self._ovr.get(pn,{}).get(key)
            self._ovr[pn][key] = c
            self._rec(pn, old, c, f"Override {symbol}/{tf}/{broker}. {reason}",
                     "override", sid=d.get("strategy"), mm=d.get("mm_method"), sym=symbol)
            return True

    def clear_override(self, pn, symbol=None, tf=None, broker=None) -> bool:
        with self._lock:
            k = (symbol, tf, broker)
            if pn in self._ovr and k in self._ovr[pn]:
                del self._ovr[pn][k]
                if not self._ovr[pn]: del self._ovr[pn]
                return True
            return False

    def reset_to_defaults(self, strategy_id=None, mm_method=None) -> int:
        cnt = 0
        with self._lock:
            if strategy_id is None and mm_method is None:
                tgt = list(self._sdefs.items()) + list(self._mdefs.items())
            elif strategy_id:
                tgt = [(n,d) for n,d in self._sdefs.items() if d.get("strategy")==strategy_id]
            else:
                tgt = [(n,d) for n,d in self._mdefs.items() if d.get("mm_method")==mm_method]
            ns = set()
            for n, d in tgt:
                df = _cast(d["default"], d["type"])
                if self._vals.get(n) != df: self._vals[n] = df; cnt += 1
                ns.add(n)
            for p in [k for k in self._ovr if k in ns]: del self._ovr[p]
        return cnt

    # === Query Helpers ===
    def get_param_names_for_strategy(self, s):
        return [n for n,d in self._sdefs.items() if d.get("strategy")==s]
    def get_param_names_for_mm(self, m):
        return [n for n,d in self._mdefs.items() if d.get("mm_method")==m]
    def get_all_strategy_ids(self):
        return sorted({d["strategy"] for d in self._sdefs.values()})
    def get_all_mm_methods(self):
        return sorted({d["mm_method"] for d in self._mdefs.values()})
    def get_regime_overrides(self): return self._matrix.get("regime_overrides", {})
    def get_dd_overrides(self): return self._matrix.get("dd_overrides", {})
    @property
    def total_params(self): return len(self._sdefs)+len(self._mdefs)
    @property
    def strategy_param_count(self): return len(self._sdefs)
    @property
    def mm_param_count(self): return len(self._mdefs)
    def __repr__(self):
        return (f"<ParameterRepository: {self.strategy_param_count}s+{self.mm_param_count}m"
                f"={self.total_params} total, {sum(len(v) for v in self._ovr.values())} ovr>")


# === Inline Tests ===
def _run_tests(cfg):
    print("[TEST] ParameterRepository...")
    r = ParameterRepository(cfg); print(f"  {r}")
    assert r.strategy_param_count > 0 and r.mm_param_count > 0
    assert r.total_params == r.strategy_param_count + r.mm_param_count
    print(f"  [OK] T1: {r.total_params} params")
    v = r.get_strategy_param("S15","S15_ELASTIC_FACTOR")
    d = r.get_strategy_param_definition("S15_ELASTIC_FACTOR")
    assert v == _cast(d["default"], d["type"]); print(f"  [OK] T2: default={v}")
    assert r.set_strategy_param("S15","S15_ELASTIC_FACTOR",1.8,reason="t")
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR") == 1.8; print("  [OK] T3: set")
    assert not r.set_strategy_param("S15","S15_ELASTIC_FACTOR",999.0)
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR") == 1.8; print("  [OK] T4: reject OOR")
    assert r.get_strategy_param("S01","S15_ELASTIC_FACTOR") is None; print("  [OK] T5: wrong SID")
    assert r.get_mm_param("MM01","MM01_RISK_PCT") is not None
    assert r.set_mm_param("MM01","MM01_RISK_PCT",1.5); print("  [OK] T6: MM get/set")
    assert r.get_mm_for_strategy("S01") == "MM04"
    assert r.get_mm_for_strategy("S01",regime="VOLATILE") == "MM07"
    assert r.get_mm_for_strategy("S01",dd_pct=22.0) == "MM10"; print("  [OK] T7: MM selection")
    ok,_ = r.validate_change("MM01_RISK_PCT",1.0,1.08); assert ok
    ok,_ = r.validate_change("MM01_RISK_PCT",1.0,1.15); assert not ok; print("  [OK] T8: validate_change")
    r.set_override("S15_ELASTIC_FACTOR",2.0,symbol="XAUUSD")
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR") == 1.8
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR",symbol="XAUUSD") == 2.0
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR",symbol="EURUSD") == 1.8
    print("  [OK] T9: overrides")
    res = r.apply_optimization_result({"MM01_RISK_PCT":{"value":1.6},"FAKE":{"value":1}})
    assert len(res["applied"])==1 and len(res["errors"])==1; print("  [OK] T10: batch apply")
    assert len(r.get_param_history("S15_ELASTIC_FACTOR")) > 0; print("  [OK] T11: history")
    s = r.get_config_snapshot(); assert s["total_params"]==r.total_params; print("  [OK] T12: snapshot")
    p = r.export_for_config_push("XAUUSD",strategies=["S15"])
    assert p["msg_type"]=="CONFIG_PUSH_V2" and "S15" in p["strategies"]; print("  [OK] T13: CONFIG_PUSH")
    r.reset_to_defaults(strategy_id="S15")
    assert r.get_strategy_param("S15","S15_ELASTIC_FACTOR")==_cast(d["default"],d["type"])
    print("  [OK] T14: reset defaults")
    v = r.get_strategy_param("S01","S01_PAIR1")
    if v: assert isinstance(v,str); print(f"  [OK] T15: string={v}")
    assert len(r.get_all_strategy_params("S15"))>0 and len(r.get_all_mm_params("MM01"))>0
    print("  [OK] T16: get_all")
    print(f"\n[TEST] All 16 PASSED ✅")

if __name__ == "__main__":
    import sys; _run_tests(sys.argv[1] if len(sys.argv)>1 else "02_Brain/config")