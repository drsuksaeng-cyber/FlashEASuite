"""
FlashEASuite V2 - P0.6-5: Regime-Parameter Mapper
Map market regime → parameter adjustments + MM scaling

Dependencies:
    - ParameterRepository (P0.6-3)
    - mm_selection_matrix.json (P0.6-2)
    - mm_parameter_families.json (P0.6-2)

Regime types: TRENDING, RANGING, VOLATILE, CRISIS

Author: FlashEASuite V2 Team | Phase: P0.6-5
"""

import json
import logging
from typing import Optional

logger = logging.getLogger("FlashEA.RegimeMapper")

# ============================================================
# Constants
# ============================================================

VALID_REGIMES = ["TRENDING", "RANGING", "VOLATILE", "CRISIS"]

# Regime urgency levels for transitions
TRANSITION_URGENCY = {
    # (old, new) → urgency: "low" | "medium" | "high" | "critical"
    ("TRENDING", "RANGING"):   "low",
    ("TRENDING", "VOLATILE"):  "medium",
    ("TRENDING", "CRISIS"):    "critical",
    ("RANGING", "TRENDING"):   "low",
    ("RANGING", "VOLATILE"):   "medium",
    ("RANGING", "CRISIS"):     "critical",
    ("VOLATILE", "TRENDING"):  "medium",
    ("VOLATILE", "RANGING"):   "medium",
    ("VOLATILE", "CRISIS"):    "high",
    ("CRISIS", "TRENDING"):    "medium",
    ("CRISIS", "RANGING"):     "medium",
    ("CRISIS", "VOLATILE"):    "high",
}

# Default regime→parameter adjustment multipliers
# ใช้เป็น base — ParameterRepository จะ apply ค่าจริง
REGIME_PARAM_PROFILES = {
    "TRENDING": {
        "description_th": "Trending: aggressive trend params, TP ใหญ่ขึ้น, SL ตาม ATR",
        "adjustments": {
            "tp_multiplier": 1.5,      # TP ใหญ่ขึ้น 50% — ให้กำไรวิ่ง
            "sl_multiplier": 1.2,      # SL กว้างขึ้นเล็กน้อย — ป้องกัน noise
            "entry_sensitivity": 0.8,  # เข้า trade เร็วขึ้น — ตามเทรนด์
            "exit_patience": 1.3,      # ถือนานขึ้น — ให้ trend วิ่ง
            "position_size": 1.0,      # ขนาดปกติ
            "lookback_scale": 1.2,     # lookback ยาวขึ้น — จับ trend ใหญ่
        }
    },
    "RANGING": {
        "description_th": "Ranging: tight ranges, mean-reversion params, TP สั้น",
        "adjustments": {
            "tp_multiplier": 0.7,      # TP สั้นลง — ตลาดวิ่งจำกัด
            "sl_multiplier": 0.8,      # SL แคบลง — tight range
            "entry_sensitivity": 1.2,  # เข้าช้าลง — รอสัญญาณชัด
            "exit_patience": 0.7,      # ออกเร็ว — ไม่รอ
            "position_size": 1.0,      # ขนาดปกติ
            "lookback_scale": 0.8,     # lookback สั้นลง — responsive
        }
    },
    "VOLATILE": {
        "description_th": "Volatile: reduce size, widen stops, ลดความถี่",
        "adjustments": {
            "tp_multiplier": 1.3,      # TP กว้างขึ้น — vol สูง = opportunity
            "sl_multiplier": 1.8,      # SL กว้างมาก — ป้องกัน whipsaw
            "entry_sensitivity": 1.5,  # เข้ายากขึ้น — filter noise
            "exit_patience": 0.8,      # ออกเร็ว — lock profit
            "position_size": 0.5,      # ลดขนาด 50%
            "lookback_scale": 1.0,     # lookback ปกติ
        }
    },
    "CRISIS": {
        "description_th": "Crisis: emergency params, minimal/no trading",
        "adjustments": {
            "tp_multiplier": 0.5,      # TP สั้นมาก — take what you can
            "sl_multiplier": 2.0,      # SL กว้างที่สุด — survive
            "entry_sensitivity": 3.0,  # แทบไม่เข้า trade
            "exit_patience": 0.3,      # ออกเร็วที่สุด
            "position_size": 0.0,      # ไม่เปิด trade ใหม่
            "lookback_scale": 0.5,     # lookback สั้น — react fast
        }
    }
}

# MM17 regime multipliers (from mm_parameters.json defaults)
MM17_DEFAULT_MULTIPLIERS = {
    "TRENDING": 1.2,
    "RANGING": 1.0,
    "VOLATILE": 0.3,
    "CRISIS": 0.0
}


# ============================================================
# RegimeParameterMapper
# ============================================================

class RegimeParameterMapper:
    """
    Map market regime → parameter adjustments.
    
    Responsibilities:
    1. map_regime_to_params: regime → strategy parameter adjustment ratios
    2. get_mm_regime_scaling: MM17 integration, regime-based risk multiplier
    3. detect_regime_transition: old→new regime transition strategy
    """

    def __init__(self, param_repo, config_dir: str = "02_Brain/config"):
        """
        Args:
            param_repo: ParameterRepository instance (P0.6-3)
            config_dir: path to config directory
        """
        self.param_repo = param_repo
        self.config_dir = config_dir

        # Load selection matrix for regime overrides
        self._selection_matrix = self._load_json("mm_selection_matrix.json")
        self._regime_overrides = self._selection_matrix.get("regime_overrides", {})

        logger.info("RegimeParameterMapper initialized")

    def _load_json(self, filename: str) -> dict:
        """Load JSON file from config directory."""
        path = f"{self.config_dir}/{filename}"
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            data.pop("_metadata", None)
            return data
        except (FileNotFoundError, json.JSONDecodeError) as e:
            logger.warning(f"Failed to load {filename}: {e}")
            return {}

    # --------------------------------------------------------
    # Map Regime to Parameters
    # --------------------------------------------------------

    def map_regime_to_params(self, regime: str, strategy_id: str) -> dict:
        """
        Return parameter adjustment ratios for given regime + strategy.
        
        TRENDING → aggressive trend params, larger TP
        RANGING  → tight ranges, mean-reversion params  
        VOLATILE → reduce size, widen stops
        CRISIS   → emergency params, minimal trading

        Returns:
            dict with adjustment_multipliers, mm_preference, risk_adjustment, reasoning
        """
        if regime not in VALID_REGIMES:
            logger.warning(f"Invalid regime: {regime}, using RANGING")
            regime = "RANGING"

        profile = REGIME_PARAM_PROFILES.get(regime, REGIME_PARAM_PROFILES["RANGING"])
        regime_cfg = self._regime_overrides.get(regime, {})

        # Get risk_adjustment from matrix (e.g. VOLATILE → 0.5)
        risk_adj = regime_cfg.get("risk_adjustment", 1.0)

        # Preferred/avoid MM methods for this regime
        preferred_mm = regime_cfg.get("preferred_mm", [])
        avoid_mm = regime_cfg.get("avoid", [])

        # Strategy-specific default + volatile MM from matrix
        default_mm = self._selection_matrix.get(
            "default_mm_per_strategy", {}
        ).get(strategy_id, "MM01")
        volatile_mm = self._selection_matrix.get(
            "volatile_mm_per_strategy", {}
        ).get(strategy_id)

        # Select recommended MM
        if regime == "CRISIS":
            recommended_mm = "MM10"
        elif regime == "VOLATILE" and volatile_mm:
            recommended_mm = volatile_mm
        elif preferred_mm:
            recommended_mm = preferred_mm[0]
        else:
            recommended_mm = default_mm

        return {
            "regime": regime,
            "strategy_id": strategy_id,
            "adjustment_multipliers": profile["adjustments"],
            "description_th": profile["description_th"],
            "risk_adjustment": risk_adj,
            "recommended_mm": recommended_mm,
            "preferred_mm_list": preferred_mm,
            "avoid_mm_list": avoid_mm,
            "force_reduce": regime_cfg.get("force_reduce", False)
        }

    # --------------------------------------------------------
    # MM Regime Scaling (MM17 Integration)
    # --------------------------------------------------------

    def get_mm_regime_scaling(self, regime: str, base_mm: str) -> dict:
        """
        MM17 integration: regime-based risk multiplier.
        
        ดึงค่า MM17 multipliers จาก ParameterRepository ถ้ามี
        ถ้าไม่มี → ใช้ defaults (TRENDING=1.2, RANGING=1.0, VOLATILE=0.3, CRISIS=0.0)

        Args:
            regime: current market regime
            base_mm: base MM method being used (e.g. "MM03")

        Returns:
            dict with mm_method, risk_multiplier, additional_params, reasoning
        """
        if regime not in VALID_REGIMES:
            regime = "RANGING"

        # Try to get MM17 multipliers from ParameterRepository
        mm17_param_map = {
            "TRENDING": "MM17_TREND_MULTIPLIER",
            "RANGING": "MM17_RANGE_MULTIPLIER",
            "VOLATILE": "MM17_VOLATILE_MULTIPLIER",
            "CRISIS": "MM17_CRISIS_MULTIPLIER"
        }

        param_name = mm17_param_map.get(regime)
        multiplier = MM17_DEFAULT_MULTIPLIERS.get(regime, 1.0)

        if param_name and self.param_repo:
            try:
                repo_val = self.param_repo.get_mm_param("MM17", param_name)
                if repo_val is not None:
                    multiplier = float(repo_val)
            except Exception:
                pass  # Use default

        # MM17 confirm bars
        confirm_bars = 3  # default
        if self.param_repo:
            try:
                cb = self.param_repo.get_mm_param("MM17", "MM17_CONFIRM_BARS")
                if cb is not None:
                    confirm_bars = int(cb)
            except Exception:
                pass

        # CRISIS → override to 0.0 regardless
        if regime == "CRISIS":
            multiplier = 0.0

        return {
            "mm_method": base_mm,
            "regime": regime,
            "risk_multiplier": round(multiplier, 2),
            "confirm_bars_required": confirm_bars,
            "additional_params": {
                "regime_scaling_active": True,
                "base_mm_preserved": base_mm,
                "effective_risk_factor": round(multiplier, 2)
            },
            "reasoning_th": (
                f"MM17 Regime Scaling: {regime} → risk×{multiplier:.1f} "
                f"(base MM: {base_mm}, ต้องยืนยัน {confirm_bars} bars)"
            ),
            "reasoning_en": (
                f"MM17 Regime Scaling: {regime} → risk×{multiplier:.1f} "
                f"(base MM: {base_mm}, confirm {confirm_bars} bars)"
            )
        }

    # --------------------------------------------------------
    # Detect Regime Transition
    # --------------------------------------------------------

    def detect_regime_transition(self, old_regime: str,
                                  new_regime: str) -> dict:
        """
        วิเคราะห์การเปลี่ยน regime → แนะนำ transition strategy.
        
        Returns:
            dict with urgency, param_changes, mm_changes, reasoning
        """
        if old_regime == new_regime:
            return {
                "transition": False,
                "old_regime": old_regime,
                "new_regime": new_regime,
                "urgency": "none",
                "reasoning_th": "ไม่มีการเปลี่ยน regime",
                "reasoning_en": "No regime change"
            }

        # Validate
        old_r = old_regime if old_regime in VALID_REGIMES else "RANGING"
        new_r = new_regime if new_regime in VALID_REGIMES else "RANGING"

        urgency = TRANSITION_URGENCY.get((old_r, new_r), "medium")

        # Get old and new profiles
        old_profile = REGIME_PARAM_PROFILES.get(old_r, REGIME_PARAM_PROFILES["RANGING"])
        new_profile = REGIME_PARAM_PROFILES.get(new_r, REGIME_PARAM_PROFILES["RANGING"])

        # Calculate parameter change deltas
        param_changes = {}
        old_adj = old_profile["adjustments"]
        new_adj = new_profile["adjustments"]
        for key in new_adj:
            old_val = old_adj.get(key, 1.0)
            new_val = new_adj[key]
            if old_val != new_val:
                param_changes[key] = {
                    "old": old_val,
                    "new": new_val,
                    "change_pct": round(((new_val - old_val) / old_val) * 100.0, 1) if old_val != 0 else 0.0
                }

        # MM changes
        old_regime_cfg = self._regime_overrides.get(old_r, {})
        new_regime_cfg = self._regime_overrides.get(new_r, {})

        mm_changes = {
            "old_preferred": old_regime_cfg.get("preferred_mm", []),
            "new_preferred": new_regime_cfg.get("preferred_mm", []),
            "old_avoid": old_regime_cfg.get("avoid", []),
            "new_avoid": new_regime_cfg.get("avoid", []),
            "old_risk_adj": old_regime_cfg.get("risk_adjustment", 1.0),
            "new_risk_adj": new_regime_cfg.get("risk_adjustment", 1.0),
            "force_reduce": new_regime_cfg.get("force_reduce", False)
        }

        # Build reasoning
        reasoning_parts_th = [f"เปลี่ยนจาก {old_r} → {new_r} (urgency: {urgency})"]
        reasoning_parts_en = [f"Transition {old_r} → {new_r} (urgency: {urgency})"]

        if urgency in ("high", "critical"):
            reasoning_parts_th.append("⚠️ ต้องปรับ parameters ทันที")
            reasoning_parts_en.append("⚠️ Immediate parameter adjustment required")

        if mm_changes["force_reduce"]:
            reasoning_parts_th.append("🔴 force_reduce=true → หยุด/ลด trading")
            reasoning_parts_en.append("🔴 force_reduce=true → stop/reduce trading")

        # Gradual vs immediate application
        if urgency == "critical":
            application = "immediate"  # Apply all changes now
        elif urgency == "high":
            application = "fast"       # Apply within 1-2 bars
        elif urgency == "medium":
            application = "gradual"    # Apply over 3-5 bars
        else:
            application = "slow"       # Apply over 5-10 bars

        return {
            "transition": True,
            "old_regime": old_r,
            "new_regime": new_r,
            "urgency": urgency,
            "application_mode": application,
            "param_changes": param_changes,
            "mm_changes": mm_changes,
            "reasoning_th": " | ".join(reasoning_parts_th),
            "reasoning_en": " | ".join(reasoning_parts_en),
            "new_profile_description_th": new_profile["description_th"]
        }