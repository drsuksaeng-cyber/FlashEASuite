"""
FlashEASuite V2 — P0.6-6: Parameter Family Optimizer
Optimize parameters within the same family together — ensure co-optimization consistency
ทำงานร่วมกับ ParameterFamilyIndex (P0.6-3) + ParameterRepository (P0.6-3)

Dependencies:
    - ParameterFamilyIndex (P0.6-3)
    - ParameterRepository (P0.6-3)

Author: FlashEASuite V2 Team | Phase: P0.6-6
"""

import logging
from typing import Optional

logger = logging.getLogger("FlashEA.FamilyOptimizer")

# Priority order: risk families first → entry/exit → signal generation → rest
FAMILY_PRIORITY = {
    "MM_RISK": 1, "MM_DD": 2, "MM_PORT": 3,
    "EXIT_RULES": 10, "RISK_SIZING": 11,
    "ENTRY_THRESHOLD": 20, "VOLATILITY_FILTER": 21,
    "MOMENTUM_TIMING": 30, "TREND_DETECTION": 31, "INDICATOR_PARAMS": 32,
    "GRID_STRUCTURE": 40, "SPIKE_DETECTION": 41,
    "PATTERN_DETECTION": 50, "CORRELATION_PARAMS": 51,
    "ML_HYPERPARAMS": 60, "TIMEFRAME_WEIGHT": 61,
    "REGIME_PREFERENCE": 70,
    "MM_SCALE": 80, "MM_TIME": 81, "MM_COMPOUND": 82,
}

# Max multiplier change per direction to prevent overshoot
MAX_DIRECTION_SCALE = 0.20  # 20%


class ParameterFamilyOptimizer:
    """
    Optimize parameters within the same family together.

    Responsibilities:
    1. Batch optimize ทุก params ใน family เดียวกัน (co-optimize)
    2. Ensure consistency ของ params ที่มี optimization_direction = "same"
    3. Enforce DD tier ordering, portfolio cap consistency
    4. Provide family optimization order (risk-first)
    """

    def __init__(self, family_index, param_repo):
        """
        Args:
            family_index: ParameterFamilyIndex instance (P0.6-3)
            param_repo: ParameterRepository instance (P0.6-3)
        """
        self.family_index = family_index
        self.param_repo = param_repo
        logger.info("[FamilyOptimizer] Initialized")

    # ============================================================
    # Public API
    # ============================================================

    def optimize_family(self, family_id: str, market_data: dict,
                        feedback: dict) -> dict:
        """
        Batch optimize ทุก params ใน family เดียวกัน.

        Args:
            family_id: e.g. "GRID_STRUCTURE", "MM_RISK"
            market_data: {"regime": str, "volatility": float, "trend_strength": float}
            feedback: {"param_name": {"suggested": val, "confidence": float, "direction": str}}

        Returns:
            dict: {param_name: {"value": new_val, "reason": str}}
        """
        info = self.family_index.get_family_info(family_id)
        if info is None:
            return {}

        members = self.family_index.get_family_members(family_id)
        if not members:
            return {}

        co_optimize = info.get("co_optimize", False)
        direction = info.get("optimization_direction", "independent")

        changes = {}

        if co_optimize and direction == "same":
            changes = self._optimize_same_direction(family_id, members, feedback, market_data)
        elif co_optimize and direction == "inverse":
            changes = self._optimize_inverse_direction(family_id, members, feedback, market_data)
        else:
            # Independent — each param optimized individually from feedback
            changes = self._optimize_independent(family_id, members, feedback)

        return changes

    def ensure_family_consistency(self, changes: dict) -> dict:
        """
        ตรวจสอบว่า params ใน family เดียวกัน consistent.
        Fix inconsistencies in-place.

        Args:
            changes: {param_name: {"value": val, "reason": str, ...}}

        Returns:
            dict: corrected changes (may remove or adjust some)
        """
        # Group changes by family
        by_family = {}
        for pn, chg in changes.items():
            fid = self.family_index.get_family_for_param(pn)
            if fid:
                by_family.setdefault(fid, {})[pn] = chg

        corrected = dict(changes)

        for fid, fam_changes in by_family.items():
            info = self.family_index.get_family_info(fid)
            if info is None:
                continue

            co_opt = info.get("co_optimize", False)
            direction = info.get("optimization_direction", "independent")

            # Check same-direction consistency
            if co_opt and direction == "same":
                corrected = self._fix_same_direction(fid, fam_changes, corrected)

            # Special: DD tier ordering
            if fid == "MM_DD":
                corrected = self._fix_dd_tiers(fam_changes, corrected)

            # Special: Portfolio cap
            if fid == "MM_PORT":
                corrected = self._fix_portfolio_cap(fam_changes, corrected)

        return corrected

    def get_family_optimization_order(self) -> list:
        """
        ลำดับ family ที่ควร optimize ก่อน-หลัง.
        Risk management families → entry/exit → signal generation → others

        Returns:
            list: [{"family": fid, "priority": int, "type": str, "reason": str}]
        """
        all_fam = self.family_index.get_all_families()
        ordered = []

        for fid, info in all_fam.items():
            priority = FAMILY_PRIORITY.get(fid, 99)
            ordered.append({
                "family": fid,
                "priority": priority,
                "type": info.get("type", "unknown"),
                "co_optimize": info.get("co_optimize", False),
                "direction": info.get("direction", "independent"),
                "reason": self._priority_reason(fid, priority)
            })

        ordered.sort(key=lambda x: x["priority"])
        return ordered

    def get_co_optimize_adjustments(self, family_id: str,
                                     lead_param: str,
                                     lead_change_pct: float) -> dict:
        """
        เมื่อ lead param เปลี่ยน → คำนวณ proportional changes สำหรับ params อื่นใน family.

        Args:
            family_id: family ที่ co-optimize
            lead_param: param ที่ถูก optimize จาก factor analysis
            lead_change_pct: % change ของ lead param (e.g. +10%)

        Returns:
            dict: {param_name: {"scale_factor": float, "reason": str}}
        """
        info = self.family_index.get_family_info(family_id)
        if info is None or not info.get("co_optimize", False):
            return {}

        members = self.family_index.get_family_members(family_id)
        direction = info.get("optimization_direction", "same")

        result = {}
        for pn in members:
            if pn == lead_param:
                continue

            defn = self.param_repo.get_strategy_param_definition(pn)
            if defn is None:
                defn = self.param_repo.get_mm_param_definition(pn)
            if defn is None or defn.get("type") not in ("int", "double"):
                continue

            # Max allowed change for this param
            max_pct = defn.get("max_change_per_cycle_pct", 20) / 100.0

            if direction == "same":
                # Same direction as lead, proportional
                scale = lead_change_pct / 100.0
                scale = max(-max_pct, min(max_pct, scale))
            elif direction == "inverse":
                # Opposite direction
                scale = -(lead_change_pct / 100.0)
                scale = max(-max_pct, min(max_pct, scale))
            else:
                continue

            result[pn] = {
                "scale_factor": round(scale, 4),
                "reason": f"co-opt จาก {lead_param} ({direction} direction, {lead_change_pct:+.1f}%)"
            }

        return result

    # ============================================================
    # Private — Direction-based optimization
    # ============================================================

    def _optimize_same_direction(self, family_id: str, members: list,
                                  feedback: dict, market_data: dict) -> dict:
        """Same-direction co-optimization: all params move in same direction."""
        # Find dominant direction from feedback
        up_count = down_count = 0
        avg_pct = 0.0
        count = 0

        for pn in members:
            fb = feedback.get(pn)
            if fb is None:
                continue
            d = fb.get("direction", "none")
            if d in ("higher_better", "increase"):
                up_count += 1
            elif d in ("lower_better", "decrease"):
                down_count += 1
            conf = fb.get("confidence", 0.5)
            if conf >= 0.5:
                count += 1

        if count == 0:
            return {}

        dominant = "up" if up_count >= down_count else "down"
        changes = {}

        for pn in members:
            fb = feedback.get(pn, {})
            suggested = fb.get("suggested")
            if suggested is None:
                continue

            conf = fb.get("confidence", 0.5)
            if conf < 0.5:
                continue

            d = fb.get("direction", "none")
            # Enforce same direction
            defn = self.param_repo.get_strategy_param_definition(pn)
            if defn is None:
                defn = self.param_repo.get_mm_param_definition(pn)
            if defn is None:
                continue

            cur = self._get_current(pn, defn)
            if cur is None or not isinstance(cur, (int, float)):
                continue

            # If direction matches dominant, use suggested; otherwise skip
            param_dir = "up" if suggested > cur else "down"
            if param_dir != dominant:
                continue

            changes[pn] = {
                "value": suggested,
                "reason": f"co-opt {family_id}: {dominant} direction (conf={conf:.2f})"
            }

        return changes

    def _optimize_inverse_direction(self, family_id: str, members: list,
                                     feedback: dict, market_data: dict) -> dict:
        """Inverse direction: e.g. EXIT_RULES — TP↑ implies SL may need to adjust inversely."""
        changes = {}
        for pn in members:
            fb = feedback.get(pn, {})
            suggested = fb.get("suggested")
            if suggested is None:
                continue
            conf = fb.get("confidence", 0.5)
            if conf < 0.5:
                continue
            changes[pn] = {
                "value": suggested,
                "reason": f"family {family_id}: inverse-optimized (conf={conf:.2f})"
            }
        return changes

    def _optimize_independent(self, family_id: str, members: list,
                               feedback: dict) -> dict:
        """Independent: each param individually."""
        changes = {}
        for pn in members:
            fb = feedback.get(pn, {})
            suggested = fb.get("suggested")
            if suggested is None:
                continue
            conf = fb.get("confidence", 0.5)
            if conf < 0.5:
                continue
            changes[pn] = {
                "value": suggested,
                "reason": f"family {family_id}: independent opt (conf={conf:.2f})"
            }
        return changes

    # ============================================================
    # Private — Consistency fixes
    # ============================================================

    def _fix_same_direction(self, family_id: str, fam_changes: dict,
                             all_changes: dict) -> dict:
        """Fix mixed directions in same-direction family."""
        directions = {}
        for pn, chg in fam_changes.items():
            nv = chg.get("value")
            defn = self.param_repo.get_strategy_param_definition(pn)
            if defn is None:
                defn = self.param_repo.get_mm_param_definition(pn)
            if defn is None or defn.get("type") not in ("int", "double"):
                continue
            cur = self._get_current(pn, defn)
            if cur is None or not isinstance(cur, (int, float)):
                continue
            try:
                d = "up" if float(nv) > float(cur) else ("down" if float(nv) < float(cur) else "same")
            except (TypeError, ValueError):
                continue
            if d != "same":
                directions[pn] = d

        if len(set(directions.values())) <= 1:
            return all_changes  # Already consistent

        # Majority wins
        up_c = sum(1 for d in directions.values() if d == "up")
        down_c = sum(1 for d in directions.values() if d == "down")
        dominant = "up" if up_c >= down_c else "down"

        for pn, d in directions.items():
            if d != dominant and pn in all_changes:
                del all_changes[pn]
                logger.info(f"[FamilyOpt] Removed {pn} — mismatched direction in {family_id}")

        return all_changes

    def _fix_dd_tiers(self, fam_changes: dict, all_changes: dict) -> dict:
        """Ensure DD tiers: Tier1 < Tier2 < Stop."""
        t1_pn, t2_pn, st_pn = "MM10_DD_TIER1_PCT", "MM10_DD_TIER2_PCT", "MM10_DD_STOP_PCT"

        def _val(pn):
            if pn in fam_changes:
                return float(fam_changes[pn].get("value", 0))
            defn = self.param_repo.get_mm_param_definition(pn)
            if defn is None:
                return None
            v = self.param_repo.get_mm_param("MM10", pn)
            return float(v) if v is not None else float(defn.get("default", 0))

        t1, t2, st = _val(t1_pn), _val(t2_pn), _val(st_pn)
        if t1 is None or t2 is None or st is None:
            return all_changes

        if not (t1 < t2 < st):
            # Remove all DD changes to maintain existing order
            for pn in [t1_pn, t2_pn, st_pn]:
                if pn in all_changes:
                    del all_changes[pn]
                    logger.warning(f"[FamilyOpt] Removed {pn} — DD tier ordering violated")

        return all_changes

    def _fix_portfolio_cap(self, fam_changes: dict, all_changes: dict) -> dict:
        """Ensure per-trade max ≤ portfolio cap."""
        cap_pn = "MM18_PORTFOLIO_CAP_PCT"
        pt_pn = "MM18_PER_TRADE_MAX_PCT"

        cap_v = fam_changes.get(cap_pn, {}).get("value")
        pt_v = fam_changes.get(pt_pn, {}).get("value")

        if cap_v is not None and pt_v is not None:
            if float(pt_v) > float(cap_v):
                if pt_pn in all_changes:
                    all_changes[pt_pn]["value"] = cap_v
                    all_changes[pt_pn]["reason"] += " (capped to portfolio cap)"
                    logger.info(f"[FamilyOpt] Capped {pt_pn} to {cap_v}")

        return all_changes

    # ============================================================
    # Private — Helpers
    # ============================================================

    def _get_current(self, pn: str, defn: dict):
        """Get current value from repo."""
        sid = defn.get("strategy")
        mm = defn.get("mm_method")
        if sid:
            return self.param_repo.get_strategy_param(sid, pn)
        elif mm:
            return self.param_repo.get_mm_param(mm, pn)
        return None

    @staticmethod
    def _priority_reason(fid: str, priority: int) -> str:
        if priority <= 5:
            return "Risk/DD control — ต้อง optimize ก่อน"
        elif priority <= 15:
            return "Exit/risk sizing — ป้องกัน loss ก่อน profit"
        elif priority <= 25:
            return "Entry/filter — ควบคุม quality ของ trade"
        elif priority <= 45:
            return "Signal generation — ปรับ strategy logic"
        elif priority <= 65:
            return "Pattern/correlation/ML — specialized tuning"
        else:
            return "Supplementary — optimize ท้ายสุด"
