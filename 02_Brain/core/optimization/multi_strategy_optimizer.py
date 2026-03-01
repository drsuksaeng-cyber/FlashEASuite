"""
FlashEASuite V2 — P0.6-6: Multi-Strategy Optimizer Engine
หัวใจของ Phase 0.6 — 10-factor optimization logic ตัดสินใจปรับ 208 parameters
รับ input จาก GenericAnalyzer + MMAnalyzer + RegimeMapper → output optimized changes

10 Factors:
    1. Market Regime Analysis → regime-specific param adjustments
    2. Parameter Effectiveness → which values work best
    3. Cross-Strategy Conflict Detection → prevent contradictions
    4. Client Feedback Aggregation → aggregate from up to 50 clients
    5. Symbol-Specific Tuning → per-symbol optimization
    6. TF-Specific Tuning → per-timeframe optimization
    7. Broker-Specific Adjustment → broker-specific quirks
    8. Parameter Family Co-optimization → linked params change together
    9. Constraint Enforcement → max 20% change per cycle
    10. Confidence-Weighted Decision → high confidence = bigger changes

Dependencies:
    - ParameterRepository (P0.6-3)
    - ParameterFamilyIndex (P0.6-3)
    - GenericStrategyAnalyzer (P0.6-4)
    - MultiStrategyAnalyzer (P0.6-4)
    - MMAnalyzer (P0.6-5)
    - RegimeParameterMapper (P0.6-5)
    - ParameterFamilyOptimizer (P0.6-6)

Author: FlashEASuite V2 Team | Phase: P0.6-6
"""

import time
import logging
import threading
from collections import defaultdict
from typing import Optional

logger = logging.getLogger("FlashEA.MultiStrategyOptimizer")

# ============================================================
# Constants
# ============================================================

MIN_CONFIDENCE = 0.50          # ต่ำกว่านี้ไม่ปรับ
MAX_CHANGE_PCT_DEFAULT = 20.0  # % สูงสุดต่อ cycle (default)
MIN_TRADES_FOR_OPTIMIZE = 30   # trades ขั้นต่ำ
CLIENT_DECAY_FACTOR = 0.95     # older feedback decays

VALID_REGIMES = {"TRENDING", "RANGING", "VOLATILE", "CRISIS", "UNKNOWN"}
GENERIC_STRATEGIES = {f"S{i:02d}" for i in range(1, 15)}
ALL_STRATEGIES = {f"S{i:02d}" for i in range(1, 17)}

# Broker-specific quirks (spread, slippage multipliers)
BROKER_ADJUSTMENTS = {
    "icmarkets": {"spread_factor": 1.0, "slippage_factor": 1.0, "desc": "Low spread, fast execution"},
    "exness":    {"spread_factor": 1.1, "slippage_factor": 1.0, "desc": "Low spread, good API"},
    "xm":        {"spread_factor": 1.3, "slippage_factor": 1.1, "desc": "Wider spread, average"},
    "pepperstone":{"spread_factor": 1.0, "slippage_factor": 1.0, "desc": "Low spread, ECN"},
}

# Symbol-specific tuning profiles
SYMBOL_PROFILES = {
    "XAUUSD": {"volatility_class": "high", "spread_class": "wide",
               "entry_scale": 1.2, "sl_scale": 1.5, "tp_scale": 1.3},
    "EURUSD": {"volatility_class": "low", "spread_class": "tight",
               "entry_scale": 0.9, "sl_scale": 0.8, "tp_scale": 0.9},
    "GBPUSD": {"volatility_class": "medium", "spread_class": "medium",
               "entry_scale": 1.0, "sl_scale": 1.0, "tp_scale": 1.0},
    "USDJPY": {"volatility_class": "medium", "spread_class": "tight",
               "entry_scale": 0.95, "sl_scale": 0.9, "tp_scale": 0.95},
    "GBPJPY": {"volatility_class": "high", "spread_class": "wide",
               "entry_scale": 1.15, "sl_scale": 1.4, "tp_scale": 1.2},
}

# TF-specific adjustments (lookback/patience multiplier)
TF_ADJUSTMENTS = {
    "M1":  {"lookback_scale": 0.5, "patience_scale": 0.3, "noise_level": "very_high"},
    "M5":  {"lookback_scale": 0.7, "patience_scale": 0.5, "noise_level": "high"},
    "M15": {"lookback_scale": 0.85, "patience_scale": 0.7, "noise_level": "medium"},
    "M30": {"lookback_scale": 1.0, "patience_scale": 0.85, "noise_level": "medium"},
    "H1":  {"lookback_scale": 1.0, "patience_scale": 1.0, "noise_level": "low"},
    "H4":  {"lookback_scale": 1.3, "patience_scale": 1.3, "noise_level": "low"},
    "D1":  {"lookback_scale": 1.5, "patience_scale": 1.5, "noise_level": "very_low"},
}


# ============================================================
# MultiStrategyOptimizer
# ============================================================

class MultiStrategyOptimizer:
    """
    10-Factor optimization engine สำหรับ 208 parameters.

    Pipeline:
    optimize_all() →
      Factor 1: Regime Analysis
      Factor 2: Parameter Effectiveness
      Factor 3: Cross-Strategy Conflicts
      Factor 4: Client Feedback
      Factor 5: Symbol-Specific
      Factor 6: Timeframe-Specific
      Factor 7: Broker-Specific
      Factor 8: Family Co-optimization
      Factor 9: Constraint Enforcement
      Factor 10: Confidence Weighting
      → apply via ParameterRepository
      → generate reasoning (Thai)
    """

    def __init__(self, param_repo, strategy_analyzer, mm_analyzer,
                 regime_mapper, family_index,
                 multi_strategy_analyzer=None, family_optimizer=None):
        """
        Args:
            param_repo: ParameterRepository (P0.6-3)
            strategy_analyzer: GenericStrategyAnalyzer (P0.6-4)
            mm_analyzer: MMAnalyzer (P0.6-5)
            regime_mapper: RegimeParameterMapper (P0.6-5)
            family_index: ParameterFamilyIndex (P0.6-3)
            multi_strategy_analyzer: MultiStrategyAnalyzer (P0.6-4), optional
            family_optimizer: ParameterFamilyOptimizer (P0.6-6), optional
        """
        self.param_repo = param_repo
        self.strategy_analyzer = strategy_analyzer
        self.mm_analyzer = mm_analyzer
        self.regime_mapper = regime_mapper
        self.family_index = family_index
        self.multi_strategy_analyzer = multi_strategy_analyzer
        self.family_optimizer = family_optimizer

        self._lock = threading.Lock()
        self._current_regime: str = "UNKNOWN"
        self._client_feedback: dict = defaultdict(list)  # {client_id: [feedback_records]}
        self._last_optimize_ts: float = 0.0
        self._optimize_count: int = 0

        logger.info("[Optimizer] 10-Factor Multi-Strategy Optimizer initialized")

    # ============================================================
    # Public — Main Entry Point
    # ============================================================

    def optimize_all(self, symbol: str, broker: str = None,
                     regime: str = None, timeframe: str = "H1",
                     dd_pct: float = 0.0) -> dict:
        """
        Main optimization method — ใช้ 10 factors.

        Args:
            symbol: e.g. "XAUUSD"
            broker: e.g. "icmarkets" (optional)
            regime: current market regime (optional, uses last known)
            timeframe: primary timeframe (default H1)
            dd_pct: current drawdown %

        Returns:
            dict: {strategy_changes, mm_changes, mm_selection,
                   reasoning, confidence, applied, factors_used}
        """
        t0 = time.time()
        if regime and regime in VALID_REGIMES:
            self._current_regime = regime
        current_regime = self._current_regime

        logger.info(f"[Optimizer] === START optimize_all: {symbol} | "
                    f"regime={current_regime} | broker={broker} | TF={timeframe} | DD={dd_pct:.1f}% ===")

        # Collect factor results
        factor_results = {}
        pending_changes = {}  # {param_name: {"value": val, "reason": str, "confidence": float}}

        # --- Factor 1: Market Regime Analysis ---
        f1 = self._factor_1_regime(symbol, current_regime)
        factor_results["F1_regime"] = f1
        self._merge_factor(pending_changes, f1.get("param_adjustments", {}), "regime")

        # --- Factor 2: Parameter Effectiveness ---
        f2 = self._factor_2_effectiveness(symbol)
        factor_results["F2_effectiveness"] = f2
        self._merge_factor(pending_changes, f2.get("suggestions", {}), "effectiveness")

        # --- Factor 3: Cross-Strategy Conflict Detection ---
        f3 = self._factor_3_conflicts(pending_changes, symbol)
        factor_results["F3_conflicts"] = f3
        # Factor 3 may REMOVE conflicting changes from pending
        for pn in f3.get("removed_params", []):
            pending_changes.pop(pn, None)

        # --- Factor 4: Client Feedback Aggregation ---
        f4 = self._factor_4_client_feedback()
        factor_results["F4_feedback"] = f4
        self._merge_factor(pending_changes, f4.get("aggregated", {}), "client_feedback")

        # --- Factor 5: Symbol-Specific Tuning ---
        f5 = self._factor_5_symbol(symbol)
        factor_results["F5_symbol"] = f5
        self._apply_symbol_scaling(pending_changes, f5)

        # --- Factor 6: TF-Specific Tuning ---
        f6 = self._factor_6_timeframe(timeframe)
        factor_results["F6_timeframe"] = f6
        self._apply_tf_scaling(pending_changes, f6)

        # --- Factor 7: Broker-Specific Adjustment ---
        f7 = self._factor_7_broker(broker)
        factor_results["F7_broker"] = f7
        self._apply_broker_scaling(pending_changes, f7)

        # --- Factor 8: Parameter Family Co-optimization ---
        f8 = self._factor_8_family(pending_changes)
        factor_results["F8_family"] = f8
        # f8 may add co-optimization changes
        for pn, chg in f8.get("added", {}).items():
            if pn not in pending_changes:
                pending_changes[pn] = chg

        # --- Factor 9: Constraint Enforcement ---
        f9 = self._factor_9_constraints(pending_changes)
        factor_results["F9_constraints"] = f9
        pending_changes = f9.get("constrained_changes", pending_changes)

        # --- Factor 10: Confidence-Weighted Decision ---
        f10 = self._factor_10_confidence(pending_changes)
        factor_results["F10_confidence"] = f10
        final_changes = f10.get("final_changes", {})
        overall_confidence = f10.get("overall_confidence", 0.0)

        # === MM Selection ===
        mm_selection = self._compute_mm_selection(symbol, current_regime, dd_pct)

        # === Separate strategy_changes and mm_changes ===
        strategy_changes, mm_changes = self._split_changes(final_changes)

        # === Apply to ParameterRepository ===
        applied = False
        apply_result = {}
        if final_changes and overall_confidence >= MIN_CONFIDENCE:
            apply_result = self.param_repo.apply_optimization_result(
                final_changes, source="optimizer_10factor"
            )
            applied = len(apply_result.get("applied", [])) > 0

        # === Generate Reasoning ===
        reasoning = self.generate_reasoning(
            final_changes, factor_results, overall_confidence,
            symbol, current_regime, applied
        )

        elapsed = round((time.time() - t0) * 1000, 1)
        self._last_optimize_ts = time.time()
        self._optimize_count += 1

        result = {
            "strategy_changes": strategy_changes,
            "mm_changes": mm_changes,
            "mm_selection": mm_selection,
            "reasoning": reasoning,
            "confidence": round(overall_confidence, 4),
            "applied": applied,
            "apply_result": apply_result,
            "factors_used": list(factor_results.keys()),
            "total_changes": len(final_changes),
            "elapsed_ms": elapsed,
            "optimize_count": self._optimize_count,
            "symbol": symbol,
            "regime": current_regime,
        }

        logger.info(f"[Optimizer] === DONE: {len(final_changes)} changes, "
                    f"conf={overall_confidence:.2f}, applied={applied}, {elapsed}ms ===")
        return result

    # ============================================================
    # Public — Helpers
    # ============================================================

    def set_regime(self, regime: str):
        """Update current regime (called from analysis pipeline)."""
        if regime in VALID_REGIMES:
            self._current_regime = regime

    def add_client_feedback(self, client_id: str, feedback: dict):
        """
        Add feedback from a client.
        feedback: {"strategy_id": str, "symbol": str, "param_results": {param: {"pnl": float}}}
        """
        with self._lock:
            fb = self._client_feedback[client_id]
            fb.append({"data": feedback, "timestamp": time.time()})
            if len(fb) > 100:
                self._client_feedback[client_id] = fb[-100:]

    def should_optimize(self, symbol: str, min_trades: int = None) -> bool:
        """Check if enough data exists to run optimization."""
        mt = min_trades or MIN_TRADES_FOR_OPTIMIZE
        total = 0
        for sid in GENERIC_STRATEGIES:
            total += self.strategy_analyzer.get_trade_count(sid, symbol)
        return total >= mt

    @property
    def last_optimize_time(self) -> float:
        return self._last_optimize_ts

    # ============================================================
    # Factor 1: Market Regime Analysis
    # ============================================================

    def _factor_1_regime(self, symbol: str, regime: str) -> dict:
        """Factor 1: Map current regime → parameter adjustment multipliers."""
        if regime == "UNKNOWN":
            return {"regime": regime, "param_adjustments": {},
                    "note": "Regime unknown — ไม่ปรับ regime params"}

        adjustments = {}
        # Get regime adjustments per active strategy
        for sid in self.param_repo.get_all_strategy_ids():
            mapping = self.regime_mapper.map_regime_to_params(regime, sid)
            multipliers = mapping.get("adjustment_multipliers", {})

            # Apply multipliers to regime-sensitive params
            for pn in self.param_repo.get_param_names_for_strategy(sid):
                defn = self.param_repo.get_strategy_param_definition(pn)
                if defn is None or not defn.get("regime_sensitive", False):
                    continue
                if defn.get("type") not in ("int", "double"):
                    continue

                cur = self.param_repo.get_strategy_param(sid, pn, symbol=symbol)
                if cur is None or not isinstance(cur, (int, float)):
                    continue

                # Determine which multiplier to apply based on param category
                cat = defn.get("category", "")
                mult = self._select_regime_multiplier(cat, multipliers)
                if mult is None or mult == 1.0:
                    continue

                new_val = cur * mult
                # Clamp to min/max
                if defn.get("min") is not None:
                    new_val = max(new_val, float(defn["min"]))
                if defn.get("max") is not None:
                    new_val = min(new_val, float(defn["max"]))

                # Round to step
                step = defn.get("step")
                if step and step > 0:
                    if defn["type"] == "int":
                        new_val = int(round(new_val / step) * step)
                    else:
                        new_val = round(round(new_val / step) * step, 4)

                if new_val != cur:
                    adjustments[pn] = {
                        "value": new_val,
                        "reason": f"Regime {regime}: {cat} ×{mult:.2f}",
                        "confidence": 0.7 if regime != "CRISIS" else 0.9
                    }

        return {"regime": regime, "param_adjustments": adjustments,
                "total_adjusted": len(adjustments)}

    @staticmethod
    def _select_regime_multiplier(category: str, multipliers: dict) -> Optional[float]:
        """Map param category → regime multiplier key."""
        mapping = {
            "signal_generation": "entry_sensitivity",
            "filter": "entry_sensitivity",
            "risk_management": "sl_multiplier",
        }
        key = mapping.get(category)
        return multipliers.get(key) if key else None

    # ============================================================
    # Factor 2: Parameter Effectiveness
    # ============================================================

    def _factor_2_effectiveness(self, symbol: str) -> dict:
        """Factor 2: Use GenericStrategyAnalyzer suggestions per strategy."""
        suggestions = {}
        strategies_analyzed = 0

        for sid in self.strategy_analyzer.get_active_strategies():
            sug_list = self.strategy_analyzer.suggest_param_changes(sid, symbol)
            if not sug_list:
                continue
            strategies_analyzed += 1
            for s in sug_list:
                pn = s["param"]
                suggestions[pn] = {
                    "value": s["suggested"],
                    "reason": f"Effectiveness ({sid}): {s['reason']}",
                    "confidence": s.get("confidence", 0.5)
                }

        return {"suggestions": suggestions, "strategies_analyzed": strategies_analyzed,
                "total_suggestions": len(suggestions)}

    # ============================================================
    # Factor 3: Cross-Strategy Conflict Detection
    # ============================================================

    def _factor_3_conflicts(self, pending: dict, symbol: str) -> dict:
        """Factor 3: Detect and resolve cross-strategy conflicts."""
        removed = []
        conflicts_found = []

        # Family-level conflicts
        change_vals = {pn: chg.get("value") for pn, chg in pending.items()}
        fam_conflicts = self.family_index.detect_family_conflicts(change_vals)
        if fam_conflicts:
            conflicts_found.extend(fam_conflicts)
            for c in fam_conflicts:
                for pn in c.get("params", []):
                    if pn in pending:
                        removed.append(pn)
                        logger.info(f"[F3] Removed {pn} due to family conflict: {c['type']}")

        # Cross-strategy direction conflicts via MultiStrategyAnalyzer
        if self.multi_strategy_analyzer:
            grouped = defaultdict(dict)
            for pn, chg in pending.items():
                defn = self.param_repo.get_strategy_param_definition(pn)
                if defn and defn.get("strategy"):
                    grouped[defn["strategy"]][pn] = chg.get("value")
            if grouped:
                ms_conflicts = self.multi_strategy_analyzer.detect_conflicts(dict(grouped))
                if ms_conflicts:
                    conflicts_found.extend(ms_conflicts)
                    # Remove params from high-severity conflicts
                    for c in ms_conflicts:
                        if c.get("severity") == "high":
                            for sid in c.get("strategies", c.get("increase_strategies", []) +
                                             c.get("decrease_strategies", [])):
                                for pn in list(pending.keys()):
                                    defn = self.param_repo.get_strategy_param_definition(pn)
                                    if defn and defn.get("strategy") == sid and pn not in removed:
                                        removed.append(pn)

        return {"conflicts": conflicts_found, "removed_params": removed,
                "conflicts_count": len(conflicts_found)}

    # ============================================================
    # Factor 4: Client Feedback Aggregation
    # ============================================================

    def _factor_4_client_feedback(self) -> dict:
        """Factor 4: Aggregate feedback from up to 50 clients."""
        with self._lock:
            if not self._client_feedback:
                return {"aggregated": {}, "client_count": 0,
                        "note": "ไม่มี client feedback"}

            # Collect param-level PnL from all clients
            param_pnl = defaultdict(list)  # {param_name: [(pnl, timestamp)]}
            client_count = 0

            for cid, records in self._client_feedback.items():
                client_count += 1
                if client_count > 50:
                    break
                for rec in records[-20:]:  # Last 20 per client
                    ts = rec.get("timestamp", 0)
                    pr = rec.get("data", {}).get("param_results", {})
                    for pn, result in pr.items():
                        pnl = result.get("pnl", 0.0)
                        param_pnl[pn].append((pnl, ts))

        # Weighted average (decay by time)
        aggregated = {}
        now = time.time()
        for pn, entries in param_pnl.items():
            if len(entries) < 3:
                continue
            total_w = 0.0
            weighted_pnl = 0.0
            for pnl, ts in entries:
                age_hours = (now - ts) / 3600.0
                weight = CLIENT_DECAY_FACTOR ** age_hours
                weighted_pnl += pnl * weight
                total_w += weight

            if total_w > 0:
                avg_pnl = weighted_pnl / total_w
                # Positive avg PnL → param working well → small increase confidence
                # Negative → decrease confidence
                defn = (self.param_repo.get_strategy_param_definition(pn) or
                        self.param_repo.get_mm_param_definition(pn))
                if defn is None:
                    continue

                sid = defn.get("strategy")
                mm = defn.get("mm_method")
                if sid:
                    cur = self.param_repo.get_strategy_param(sid, pn)
                elif mm:
                    cur = self.param_repo.get_mm_param(mm, pn)
                else:
                    continue

                if cur is None or not isinstance(cur, (int, float)):
                    continue

                # Adjust: positive PnL → nudge slightly in same direction
                # Negative PnL → nudge away
                step = defn.get("step", 1) if defn.get("step") else 1
                if avg_pnl > 0:
                    suggested = cur  # keep — it's working
                else:
                    suggested = cur - step if avg_pnl < -1.0 else cur

                if suggested != cur:
                    aggregated[pn] = {
                        "value": suggested,
                        "reason": f"Client feedback ({len(entries)} reports): avg_pnl={avg_pnl:.2f}",
                        "confidence": round(min(0.8, len(entries) / 50.0 + 0.3), 2)
                    }

        return {"aggregated": aggregated, "client_count": client_count,
                "params_with_feedback": len(param_pnl)}

    # ============================================================
    # Factor 5: Symbol-Specific Tuning
    # ============================================================

    def _factor_5_symbol(self, symbol: str) -> dict:
        """Factor 5: Apply symbol-specific scaling factors."""
        # Strip broker suffix (e.g. "XAUUSD.tp" → "XAUUSD")
        clean = symbol.split(".")[0].upper()
        profile = SYMBOL_PROFILES.get(clean, {})

        if not profile:
            return {"symbol": symbol, "profile": "default",
                    "scales": {}, "note": "ไม่มี symbol profile — ใช้ค่า default"}

        return {"symbol": symbol, "profile": clean,
                "entry_scale": profile.get("entry_scale", 1.0),
                "sl_scale": profile.get("sl_scale", 1.0),
                "tp_scale": profile.get("tp_scale", 1.0),
                "volatility_class": profile.get("volatility_class", "medium")}

    # ============================================================
    # Factor 6: Timeframe-Specific Tuning
    # ============================================================

    def _factor_6_timeframe(self, timeframe: str) -> dict:
        """Factor 6: Apply timeframe-specific adjustments."""
        tf_upper = timeframe.upper() if timeframe else "H1"
        adj = TF_ADJUSTMENTS.get(tf_upper, TF_ADJUSTMENTS.get("H1", {}))

        return {"timeframe": tf_upper,
                "lookback_scale": adj.get("lookback_scale", 1.0),
                "patience_scale": adj.get("patience_scale", 1.0),
                "noise_level": adj.get("noise_level", "medium")}

    # ============================================================
    # Factor 7: Broker-Specific Adjustment
    # ============================================================

    def _factor_7_broker(self, broker: str) -> dict:
        """Factor 7: Broker-specific quirks (spread, slippage)."""
        if not broker:
            return {"broker": None, "adjustments": {},
                    "note": "ไม่ระบุ broker — ไม่ปรับ"}

        brk = broker.lower().replace(" ", "")
        adj = BROKER_ADJUSTMENTS.get(brk, {})

        if not adj:
            return {"broker": broker, "adjustments": {},
                    "note": f"ไม่มี profile สำหรับ broker '{broker}'"}

        return {"broker": broker,
                "spread_factor": adj.get("spread_factor", 1.0),
                "slippage_factor": adj.get("slippage_factor", 1.0),
                "description": adj.get("desc", "")}

    # ============================================================
    # Factor 8: Parameter Family Co-optimization
    # ============================================================

    def _factor_8_family(self, pending: dict) -> dict:
        """Factor 8: Co-optimize related parameters within families."""
        if self.family_optimizer is None:
            return {"added": {}, "note": "FamilyOptimizer not available"}

        # Group pending changes by family
        by_family = defaultdict(dict)
        for pn, chg in pending.items():
            fid = self.family_index.get_family_for_param(pn)
            if fid:
                by_family[fid][pn] = chg

        added = {}

        # For each family that has changes, propagate to co-opt members
        for fid, fam_changes in by_family.items():
            info = self.family_index.get_family_info(fid)
            if info is None or not info.get("co_optimize", False):
                continue

            members = self.family_index.get_family_members(fid)
            lead_param = next(iter(fam_changes))  # First changed param as lead
            lead_chg = fam_changes[lead_param]

            # Calculate lead change %
            defn = (self.param_repo.get_strategy_param_definition(lead_param) or
                    self.param_repo.get_mm_param_definition(lead_param))
            if defn is None:
                continue

            sid = defn.get("strategy")
            mm = defn.get("mm_method")
            if sid:
                cur = self.param_repo.get_strategy_param(sid, lead_param)
            elif mm:
                cur = self.param_repo.get_mm_param(mm, lead_param)
            else:
                continue

            if cur is None or not isinstance(cur, (int, float)) or cur == 0:
                continue

            new_v = lead_chg.get("value", cur)
            try:
                lead_pct = ((float(new_v) - float(cur)) / float(cur)) * 100.0
            except (ValueError, TypeError, ZeroDivisionError):
                continue

            # Get co-opt adjustments
            co_adj = self.family_optimizer.get_co_optimize_adjustments(
                fid, lead_param, lead_pct
            )

            for pn, adj in co_adj.items():
                if pn in pending:
                    continue  # Already being changed

                p_defn = (self.param_repo.get_strategy_param_definition(pn) or
                          self.param_repo.get_mm_param_definition(pn))
                if p_defn is None or p_defn.get("type") not in ("int", "double"):
                    continue

                p_sid = p_defn.get("strategy")
                p_mm = p_defn.get("mm_method")
                if p_sid:
                    p_cur = self.param_repo.get_strategy_param(p_sid, pn)
                elif p_mm:
                    p_cur = self.param_repo.get_mm_param(p_mm, pn)
                else:
                    continue

                if p_cur is None or not isinstance(p_cur, (int, float)):
                    continue

                scale = adj.get("scale_factor", 0)
                new_val = p_cur * (1.0 + scale)

                # Clamp
                if p_defn.get("min") is not None:
                    new_val = max(new_val, float(p_defn["min"]))
                if p_defn.get("max") is not None:
                    new_val = min(new_val, float(p_defn["max"]))

                step = p_defn.get("step")
                if step and step > 0:
                    if p_defn["type"] == "int":
                        new_val = int(round(new_val / step) * step)
                    else:
                        new_val = round(round(new_val / step) * step, 4)

                if new_val != p_cur:
                    added[pn] = {
                        "value": new_val,
                        "reason": adj.get("reason", f"co-opt from {lead_param}"),
                        "confidence": 0.6
                    }

        # Ensure family consistency
        if added:
            merged = {**{pn: chg for pn, chg in pending.items()}, **added}
            consistent = self.family_optimizer.ensure_family_consistency(merged)
            # Only keep newly added
            added = {pn: consistent[pn] for pn in added if pn in consistent}

        return {"added": added, "families_processed": len(by_family)}

    # ============================================================
    # Factor 9: Constraint Enforcement
    # ============================================================

    def _factor_9_constraints(self, pending: dict) -> dict:
        """Factor 9: Enforce max 20% change per cycle + min/max bounds."""
        constrained = {}
        rejected = []

        for pn, chg in pending.items():
            new_val = chg.get("value")
            if new_val is None:
                continue

            defn = (self.param_repo.get_strategy_param_definition(pn) or
                    self.param_repo.get_mm_param_definition(pn))
            if defn is None:
                rejected.append({"param": pn, "reason": "Unknown param definition"})
                continue

            # Get current value
            sid = defn.get("strategy")
            mm = defn.get("mm_method")
            if sid:
                cur = self.param_repo.get_strategy_param(sid, pn)
            elif mm:
                cur = self.param_repo.get_mm_param(mm, pn)
            else:
                cur = None

            if cur is None:
                rejected.append({"param": pn, "reason": "ไม่พบค่าปัจจุบัน"})
                continue

            # Validate via ParameterRepository
            ok, msg = self.param_repo.validate_change(pn, cur, new_val)
            if ok:
                constrained[pn] = chg
            else:
                # Try to clamp to max allowed change
                if defn.get("type") in ("int", "double") and isinstance(cur, (int, float)):
                    max_pct = defn.get("max_change_per_cycle_pct", MAX_CHANGE_PCT_DEFAULT) / 100.0
                    max_delta = abs(cur * max_pct) if cur != 0 else abs(float(defn.get("step", 1)))
                    try:
                        nv = float(new_val)
                        if nv > cur:
                            clamped = cur + max_delta
                        else:
                            clamped = cur - max_delta
                        # Re-clamp to min/max
                        if defn.get("min") is not None:
                            clamped = max(clamped, float(defn["min"]))
                        if defn.get("max") is not None:
                            clamped = min(clamped, float(defn["max"]))
                        # Round to step
                        step = defn.get("step")
                        if step and step > 0:
                            if defn["type"] == "int":
                                clamped = int(round(clamped / step) * step)
                            else:
                                clamped = round(round(clamped / step) * step, 4)
                        if clamped != cur:
                            chg_copy = dict(chg)
                            chg_copy["value"] = clamped
                            chg_copy["reason"] += f" (clamped จาก {new_val})"
                            constrained[pn] = chg_copy
                        else:
                            rejected.append({"param": pn, "reason": f"Clamped = current ({msg})"})
                    except (ValueError, TypeError):
                        rejected.append({"param": pn, "reason": msg})
                else:
                    rejected.append({"param": pn, "reason": msg})

        return {"constrained_changes": constrained, "rejected": rejected,
                "accepted": len(constrained), "rejected_count": len(rejected)}

    # ============================================================
    # Factor 10: Confidence-Weighted Decision
    # ============================================================

    def _factor_10_confidence(self, pending: dict) -> dict:
        """Factor 10: Only apply changes with confidence ≥ 0.5. Higher confidence = larger changes."""
        final = {}
        removed = []
        confidences = []

        for pn, chg in pending.items():
            conf = chg.get("confidence", 0.5)

            if conf < MIN_CONFIDENCE:
                removed.append({"param": pn, "confidence": conf,
                                "reason": f"conf {conf:.2f} < {MIN_CONFIDENCE}"})
                continue

            # Scale change magnitude by confidence
            defn = (self.param_repo.get_strategy_param_definition(pn) or
                    self.param_repo.get_mm_param_definition(pn))

            if defn and defn.get("type") in ("int", "double"):
                sid = defn.get("strategy")
                mm = defn.get("mm_method")
                if sid:
                    cur = self.param_repo.get_strategy_param(sid, pn)
                elif mm:
                    cur = self.param_repo.get_mm_param(mm, pn)
                else:
                    cur = None

                if cur is not None and isinstance(cur, (int, float)):
                    new_v = chg.get("value", cur)
                    try:
                        delta = float(new_v) - float(cur)
                        # Scale delta by confidence: conf=0.5→50% delta, conf=1.0→100% delta
                        scaled_delta = delta * conf
                        scaled_val = float(cur) + scaled_delta

                        step = defn.get("step")
                        if step and step > 0:
                            if defn["type"] == "int":
                                scaled_val = int(round(scaled_val / step) * step)
                            else:
                                scaled_val = round(round(scaled_val / step) * step, 4)

                        if defn.get("min") is not None:
                            scaled_val = max(scaled_val, float(defn["min"]))
                        if defn.get("max") is not None:
                            scaled_val = min(scaled_val, float(defn["max"]))

                        if scaled_val == cur:
                            removed.append({"param": pn, "reason": "scaled change = 0"})
                            continue

                        chg_copy = dict(chg)
                        chg_copy["value"] = scaled_val
                        final[pn] = chg_copy
                        confidences.append(conf)
                    except (ValueError, TypeError):
                        final[pn] = chg
                        confidences.append(conf)
                else:
                    final[pn] = chg
                    confidences.append(conf)
            else:
                final[pn] = chg
                confidences.append(conf)

        overall = round(sum(confidences) / len(confidences), 4) if confidences else 0.0

        return {"final_changes": final, "removed": removed,
                "overall_confidence": overall, "changes_count": len(final)}

    # ============================================================
    # MM Selection
    # ============================================================

    def _compute_mm_selection(self, symbol: str, regime: str,
                               dd_pct: float) -> dict:
        """Compute optimal MM method per strategy."""
        selection = {}
        for sid in self.param_repo.get_all_strategy_ids():
            # DD override takes priority
            if dd_pct >= 10.0:
                dd_rec = self.mm_analyzer.get_dd_override_recommendation(dd_pct)
                if dd_rec.get("override_active"):
                    selection[sid] = dd_rec.get("switch_to", "MM10")
                    continue

            # Try MMAnalyzer historical best
            best = self.mm_analyzer.get_best_mm_for_regime(sid, regime)
            if best:
                selection[sid] = best
            else:
                # Fallback to ParamRepo matrix
                selection[sid] = self.param_repo.get_mm_for_strategy(sid, regime=regime)

        return selection

    # ============================================================
    # Reasoning Generation (Thai)
    # ============================================================

    def generate_reasoning(self, changes: dict, factor_results: dict,
                           confidence: float, symbol: str, regime: str,
                           applied: bool) -> dict:
        """สร้าง reasoning text (Thai) สำหรับ CONFIG_PUSH."""
        change_list = []

        for pn, chg in changes.items():
            defn = (self.param_repo.get_strategy_param_definition(pn) or
                    self.param_repo.get_mm_param_definition(pn))
            desc = ""
            if defn:
                desc = defn.get("description_th", defn.get("description_en", pn))

            change_list.append({
                "param": pn,
                "new_value": chg.get("value"),
                "reason_th": chg.get("reason", "ไม่ระบุเหตุผล"),
                "description": desc,
                "confidence": chg.get("confidence", 0.5)
            })

        # Summary
        f1 = factor_results.get("F1_regime", {})
        f3 = factor_results.get("F3_conflicts", {})
        f4 = factor_results.get("F4_feedback", {})
        f9 = factor_results.get("F9_constraints", {})

        regime_count = f1.get("total_adjusted", 0)
        conflict_count = f3.get("conflicts_count", 0)
        client_count = f4.get("client_count", 0)
        rejected_count = f9.get("rejected_count", 0)

        parts = [f"🔄 Optimization สำหรับ {symbol} (regime: {regime})"]
        parts.append(f"📊 ปรับ {len(changes)} parameters (confidence: {confidence:.0%})")

        if regime_count > 0:
            parts.append(f"🌡️ Regime '{regime}' → ปรับ {regime_count} params")
        if conflict_count > 0:
            parts.append(f"⚠️ พบ {conflict_count} conflicts → แก้ไขแล้ว")
        if client_count > 0:
            parts.append(f"👥 Client feedback จาก {client_count} clients")
        if rejected_count > 0:
            parts.append(f"🚫 ปฏิเสธ {rejected_count} changes (เกิน constraint)")

        if applied:
            parts.append("✅ Applied สำเร็จ")
        elif confidence < MIN_CONFIDENCE:
            parts.append(f"❌ ไม่ apply — confidence {confidence:.0%} < {MIN_CONFIDENCE:.0%}")
        else:
            parts.append("❌ ไม่มี changes ที่ผ่าน constraint")

        return {
            "summary_th": " | ".join(parts),
            "changes": change_list,
            "total_changes": len(changes),
            "applied": applied,
            "confidence": confidence
        }

    # ============================================================
    # Private — Merging & Scaling Helpers
    # ============================================================

    def _merge_factor(self, pending: dict, new_changes: dict, source: str):
        """Merge new factor changes into pending. Higher confidence wins."""
        for pn, chg in new_changes.items():
            if pn not in pending:
                pending[pn] = chg
            else:
                # Higher confidence wins
                if chg.get("confidence", 0.5) > pending[pn].get("confidence", 0.5):
                    pending[pn] = chg

    def _apply_symbol_scaling(self, pending: dict, f5: dict):
        """Apply symbol-specific scaling to entry/SL/TP related params."""
        entry_s = f5.get("entry_scale", 1.0)
        sl_s = f5.get("sl_scale", 1.0)
        tp_s = f5.get("tp_scale", 1.0)

        if entry_s == 1.0 and sl_s == 1.0 and tp_s == 1.0:
            return

        for pn, chg in list(pending.items()):
            defn = self.param_repo.get_strategy_param_definition(pn)
            if defn is None:
                continue
            cat = defn.get("category", "")
            val = chg.get("value")
            if not isinstance(val, (int, float)):
                continue

            scale = 1.0
            if cat == "signal_generation" and entry_s != 1.0:
                scale = entry_s
            elif cat == "risk_management":
                # Check if SL or TP related
                pn_lower = pn.lower()
                if "sl" in pn_lower or "stop" in pn_lower:
                    scale = sl_s
                elif "tp" in pn_lower or "take" in pn_lower or "profit" in pn_lower:
                    scale = tp_s

            if scale != 1.0:
                chg["value"] = round(val * scale, 4) if isinstance(val, float) else int(round(val * scale))
                chg["reason"] += f" (symbol scale ×{scale:.2f})"

    def _apply_tf_scaling(self, pending: dict, f6: dict):
        """Apply TF-specific scaling to lookback/patience params."""
        lb_s = f6.get("lookback_scale", 1.0)
        pt_s = f6.get("patience_scale", 1.0)

        if lb_s == 1.0 and pt_s == 1.0:
            return

        for pn, chg in list(pending.items()):
            val = chg.get("value")
            if not isinstance(val, (int, float)):
                continue

            pn_lower = pn.lower()
            scale = 1.0
            if "lookback" in pn_lower or "period" in pn_lower:
                scale = lb_s
            elif "patience" in pn_lower or "hold" in pn_lower or "timeout" in pn_lower:
                scale = pt_s

            if scale != 1.0:
                chg["value"] = round(val * scale, 4) if isinstance(val, float) else int(round(val * scale))
                chg["reason"] += f" (TF scale ×{scale:.2f})"

    def _apply_broker_scaling(self, pending: dict, f7: dict):
        """Apply broker-specific scaling to spread-sensitive params."""
        spread_f = f7.get("spread_factor", 1.0)
        slip_f = f7.get("slippage_factor", 1.0)

        if spread_f == 1.0 and slip_f == 1.0:
            return

        for pn, chg in list(pending.items()):
            val = chg.get("value")
            if not isinstance(val, (int, float)):
                continue

            pn_lower = pn.lower()
            # SL/pending distance affected by spread
            if ("sl" in pn_lower or "pending" in pn_lower or "dist" in pn_lower) and spread_f != 1.0:
                chg["value"] = round(val * spread_f, 4) if isinstance(val, float) else int(round(val * spread_f))
                chg["reason"] += f" (broker spread ×{spread_f:.2f})"

    def _split_changes(self, changes: dict) -> tuple:
        """Split changes into strategy_changes and mm_changes dicts."""
        sc = defaultdict(dict)  # {strategy_id: {param: new_val}}
        mc = defaultdict(dict)  # {mm_method: {param: new_val}}

        for pn, chg in changes.items():
            val = chg.get("value")
            defn = self.param_repo.get_strategy_param_definition(pn)
            if defn:
                sc[defn["strategy"]][pn] = val
                continue
            defn = self.param_repo.get_mm_param_definition(pn)
            if defn:
                mc[defn["mm_method"]][pn] = val

        return dict(sc), dict(mc)


# ============================================================
# Inline Tests
# ============================================================

if __name__ == "__main__":
    import sys, os, random, json

    # Setup path
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

    # Find config directory
    cfg = sys.argv[1] if len(sys.argv) > 1 else "02_Brain/config"
    if not os.path.exists(cfg):
        cfg = os.path.join(os.path.dirname(__file__), '..', '..', 'config')

    print(f"[TEST] Config dir: {cfg}")

    # Import dependencies
    from core.Parameter_repository import ParameterRepository
    from core.Parameter_Family_Index import ParameterFamilyIndex
    from core.intelligence.generic_strategy_analyzer import GenericStrategyAnalyzer
    from core.intelligence.mm_analyzer import MMAnalyzer
    from core.optimization.regime_parameter_mapper import RegimeParameterMapper
    from core.optimization.parameter_family_optimizer import ParameterFamilyOptimizer

    # Initialize all components
    repo = ParameterRepository(cfg)
    fam_ix = ParameterFamilyIndex(cfg)
    gen_az = GenericStrategyAnalyzer(repo)
    mm_az = MMAnalyzer(repo, cfg)
    regime_mapper = RegimeParameterMapper(repo, cfg)
    fam_opt = ParameterFamilyOptimizer(fam_ix, repo)

    print(f"  {repo}")
    print(f"  {fam_ix}")

    # Create optimizer
    opt = MultiStrategyOptimizer(
        param_repo=repo,
        strategy_analyzer=gen_az,
        mm_analyzer=mm_az,
        regime_mapper=regime_mapper,
        family_index=fam_ix,
        family_optimizer=fam_opt
    )

    # --- T1: should_optimize with no data → False ---
    assert not opt.should_optimize("XAUUSD"), "Should not optimize with no trades"
    print("✅ T1: should_optimize=False (no data)")

    # --- T2: Inject trades and test ---
    random.seed(42)
    for _ in range(50):
        gen_az.record_trade("S01", "XAUUSD", {
            "direction": "BUY", "entry_price": 2000, "exit_price": 2010,
            "pnl": random.uniform(-50, 80), "duration_seconds": random.randint(60, 3600),
            "params_used": {"S01_LOOKBACK_PERIOD": random.choice([15, 20, 25, 30])},
            "mm_used": "MM04", "regime_at_entry": random.choice(["TRENDING", "RANGING"]),
            "timestamp": time.time() - random.randint(0, 86400 * 30)
        })
    assert opt.should_optimize("XAUUSD"), "Should optimize with 50 trades"
    print("✅ T2: should_optimize=True (50 trades)")

    # --- T3: Run optimize_all ---
    result = opt.optimize_all("XAUUSD", regime="TRENDING")
    assert "strategy_changes" in result
    assert "mm_changes" in result
    assert "mm_selection" in result
    assert "reasoning" in result
    assert "confidence" in result
    assert result["factors_used"]
    print(f"✅ T3: optimize_all → {result['total_changes']} changes, "
          f"conf={result['confidence']:.2f}, applied={result['applied']}")

    # --- T4: MM selection ---
    ms = result["mm_selection"]
    assert len(ms) > 0, "MM selection should have entries"
    print(f"✅ T4: MM selection → {len(ms)} strategies assigned")

    # --- T5: Reasoning ---
    r = result["reasoning"]
    assert r["summary_th"], "Reasoning should have Thai summary"
    assert isinstance(r["changes"], list)
    print(f"✅ T5: Reasoning — {r['summary_th'][:80]}...")

    # --- T6: CRISIS regime → safety behavior ---
    result_crisis = opt.optimize_all("XAUUSD", regime="CRISIS", dd_pct=18.0)
    ms_crisis = result_crisis["mm_selection"]
    crisis_mm = set(ms_crisis.values())
    assert "MM10" in crisis_mm, "CRISIS should force MM10"
    print(f"✅ T6: CRISIS+DD18% → MM methods: {crisis_mm}")

    # --- T7: Client feedback ---
    opt.add_client_feedback("client_1", {
        "strategy_id": "S01", "symbol": "XAUUSD",
        "param_results": {"S01_LOOKBACK_PERIOD": {"pnl": -5.0}}
    })
    opt.add_client_feedback("client_2", {
        "strategy_id": "S01", "symbol": "XAUUSD",
        "param_results": {"S01_LOOKBACK_PERIOD": {"pnl": -3.0}}
    })
    opt.add_client_feedback("client_3", {
        "strategy_id": "S01", "symbol": "XAUUSD",
        "param_results": {"S01_LOOKBACK_PERIOD": {"pnl": -4.0}}
    })
    f4 = opt._factor_4_client_feedback()
    assert f4["client_count"] == 3
    print(f"✅ T7: Client feedback — {f4['client_count']} clients, "
          f"{f4['params_with_feedback']} params")

    # --- T8: Constraint enforcement ---
    test_pending = {"S01_LOOKBACK_PERIOD": {"value": 200, "reason": "test", "confidence": 0.8}}
    f9 = opt._factor_9_constraints(test_pending)
    assert f9["rejected_count"] > 0 or f9["accepted"] > 0, "Should either reject or clamp"
    print(f"✅ T8: Constraints — accepted={f9['accepted']}, rejected={f9['rejected_count']}")

    # --- T9: Confidence filter ---
    test_low_conf = {
        "P1": {"value": 1, "reason": "test", "confidence": 0.3},
        "P2": {"value": 2, "reason": "test", "confidence": 0.8}
    }
    f10 = opt._factor_10_confidence(test_low_conf)
    assert len(f10["removed"]) >= 1, "Low confidence should be removed"
    print(f"✅ T9: Confidence filter — {len(f10['final_changes'])} kept, "
          f"{len(f10['removed'])} removed")

    # --- T10: Family optimizer order ---
    order = fam_opt.get_family_optimization_order()
    assert len(order) >= 15, "Should have ≥15 families"
    assert order[0]["priority"] <= order[-1]["priority"], "Should be priority-sorted"
    print(f"✅ T10: Family order — {len(order)} families, first={order[0]['family']}")

    print(f"\n{'='*60}")
    print(f"✅ ALL MultiStrategyOptimizer TESTS PASSED")
    print(f"{'='*60}")
