"""
FlashEASuite V2 - P0.6-5: MM Performance Analyzer
วิเคราะห์ performance ของ MM01-MM19 Money Management methods
ใช้ historical trade data + mm_selection_matrix เป็น starting point

Dependencies:
    - ParameterRepository (P0.6-3)
    - mm_parameters.json (P0.6-2)
    - mm_selection_matrix.json (P0.6-2)

Author: FlashEASuite V2 Team | Phase: P0.6-5
"""

import json
import time
import logging
import statistics
from collections import defaultdict
from typing import Any, Optional

logger = logging.getLogger("FlashEA.MMAnalyzer")

# ============================================================
# Constants
# ============================================================

VALID_MM_METHODS = [f"MM{i:02d}" for i in range(1, 20)]  # MM01-MM19
VALID_REGIMES = ["TRENDING", "RANGING", "VOLATILE", "CRISIS"]
VALID_STRATEGIES = [f"S{i:02d}" for i in range(1, 17)]    # S01-S16

DD_TIER1_PCT = 10.0   # → reduce 50%
DD_TIER2_PCT = 15.0   # → reduce 75%
DD_STOP_PCT = 20.0    # → stop new trades

MIN_TRADES_FOR_ANALYSIS = 10
MIN_TRADES_FOR_COMPARISON = 20

SCORE_WEIGHTS = {
    "risk_adjusted": 0.30,
    "profit_factor": 0.25,
    "win_rate": 0.15,
    "recovery_speed": 0.15,
    "max_dd": 0.15
}


# ============================================================
# Data Structures
# ============================================================

class MMTradeRecord:
    """Single trade record with MM information."""
    __slots__ = [
        'strategy_id', 'symbol', 'mm_method', 'regime',
        'pnl', 'lot_size', 'risk_pct', 'duration_seconds',
        'drawdown_at_entry', 'timestamp', 'is_win'
    ]

    def __init__(self, strategy_id: str, symbol: str, mm_method: str,
                 trade_data: dict):
        self.strategy_id = strategy_id
        self.symbol = symbol
        self.mm_method = mm_method
        self.regime = trade_data.get('regime_at_entry', 'UNKNOWN')
        self.pnl = float(trade_data.get('pnl', 0.0))
        self.lot_size = float(trade_data.get('lot_size', 0.01))
        self.risk_pct = float(trade_data.get('risk_pct', 1.0))
        self.duration_seconds = int(trade_data.get('duration_seconds', 0))
        self.drawdown_at_entry = float(trade_data.get('drawdown_at_entry', 0.0))
        self.timestamp = trade_data.get('timestamp', time.time())
        self.is_win = self.pnl > 0


# ============================================================
# MMAnalyzer
# ============================================================

class MMAnalyzer:
    """
    วิเคราะห์ performance ของ MM01-MM19 Money Management methods.
    
    ใช้ mm_selection_matrix.json เป็น starting point
    historical data override ได้ถ้ามีข้อมูลเพียงพอ (>= 20 trades)
    """

    def __init__(self, param_repo, config_dir: str = "02_Brain/config"):
        self.param_repo = param_repo
        self.config_dir = config_dir

        # In-memory trade history: key = (strategy_id, mm_method, symbol)
        self._trade_records: dict[tuple, list[MMTradeRecord]] = defaultdict(list)
        self._cache_dirty = True

        # Load MM selection matrix
        self._selection_matrix = self._load_selection_matrix()
        self._mm_method_info = self._selection_matrix.get("mm_method_info", {})

        logger.info(
            f"MMAnalyzer initialized - "
            f"{len(self._selection_matrix.get('default_mm_per_strategy', {}))} strategy defaults"
        )

    def _load_selection_matrix(self) -> dict:
        """Load mm_selection_matrix.json."""
        path = f"{self.config_dir}/mm_selection_matrix.json"
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            data.pop("_metadata", None)
            return data
        except FileNotFoundError:
            logger.warning(f"mm_selection_matrix.json not found at {path}")
            return {"default_mm_per_strategy": {}, "volatile_mm_per_strategy": {},
                    "dd_mm_per_strategy": {}, "regime_overrides": {}, "dd_overrides": {}}
        except json.JSONDecodeError as e:
            logger.error(f"JSON parse error: {e}")
            return {}

    # --------------------------------------------------------
    # Record Trade
    # --------------------------------------------------------

    def record_mm_usage(self, strategy_id: str, mm_method: str,
                        trade_data: dict) -> bool:
        """บันทึกว่า trade นี้ใช้ MM method ไหน + ผลลัพธ์."""
        if mm_method not in VALID_MM_METHODS:
            logger.warning(f"Invalid MM method: {mm_method}")
            return False
        if strategy_id not in VALID_STRATEGIES:
            logger.warning(f"Invalid strategy_id: {strategy_id}")
            return False

        symbol = trade_data.get('symbol', 'UNKNOWN')
        record = MMTradeRecord(strategy_id, symbol, mm_method, trade_data)
        self._trade_records[(strategy_id, mm_method, symbol)].append(record)
        self._cache_dirty = True

        logger.debug(f"Recorded: {strategy_id}/{mm_method}/{symbol} pnl={record.pnl:.2f}")
        return True

    # --------------------------------------------------------
    # Analyze Effectiveness
    # --------------------------------------------------------

    def analyze_mm_effectiveness(self, mm_method: str,
                                 strategy_id: str = None,
                                 symbol: str = None) -> dict:
        """วิเคราะห์ MM method: avg_lot, max_dd, recovery_speed, risk_adjusted_return."""
        records = self._get_filtered_records(mm_method, strategy_id, symbol)

        if len(records) < MIN_TRADES_FOR_ANALYSIS:
            return {"mm_method": mm_method, "status": "insufficient_data",
                    "trade_count": len(records), "min_required": MIN_TRADES_FOR_ANALYSIS}

        pnls = [r.pnl for r in records]
        wins = [r for r in records if r.is_win]
        losses = [r for r in records if not r.is_win]

        win_sum = sum(r.pnl for r in wins)
        loss_sum = abs(sum(r.pnl for r in losses))
        profit_factor = win_sum / loss_sum if loss_sum > 0 else 999.0

        max_dd = self._calculate_max_dd_from_trades(records)
        recovery_speed = self._calculate_recovery_speed(records)

        pnl_std = statistics.stdev(pnls) if len(pnls) > 1 else 1.0
        risk_adj = (sum(pnls) / len(pnls)) / pnl_std if pnl_std > 0 else 0.0

        return {
            "mm_method": mm_method, "strategy_id": strategy_id,
            "symbol": symbol, "status": "ok",
            "trade_count": len(records),
            "total_pnl": round(sum(pnls), 2),
            "win_rate": round(len(wins) / len(records), 4),
            "avg_win": round(win_sum / len(wins), 2) if wins else 0.0,
            "avg_loss": round(loss_sum / len(losses), 2) if losses else 0.0,
            "profit_factor": round(min(profit_factor, 999.0), 2),
            "avg_lot_size": round(sum(r.lot_size for r in records) / len(records), 4),
            "avg_risk_pct": round(sum(r.risk_pct for r in records) / len(records), 2),
            "avg_duration_sec": round(sum(r.duration_seconds for r in records) / len(records), 0),
            "max_dd_pct": round(max_dd, 2),
            "recovery_speed_trades": recovery_speed,
            "risk_adjusted_return": round(risk_adj, 4)
        }

    # --------------------------------------------------------
    # Compare MM Methods
    # --------------------------------------------------------

    def compare_mm_methods(self, strategy_id: str,
                           mm_list: list, symbol: str) -> dict:
        """เปรียบเทียบ MM methods สำหรับ strategy+symbol → ranked list with scores."""
        analyses = {}
        for mm in mm_list:
            a = self.analyze_mm_effectiveness(mm, strategy_id, symbol)
            if a.get("status") == "ok":
                analyses[mm] = a

        if not analyses:
            return {"strategy_id": strategy_id, "symbol": symbol,
                    "status": "insufficient_data", "compared": mm_list, "ranking": []}

        scored = []
        for mm, a in analyses.items():
            rar = min(max(a["risk_adjusted_return"], -2.0), 2.0)
            rar_score = (rar + 2.0) / 4.0
            pf_score = min(a["profit_factor"], 5.0) / 5.0
            wr_score = a["win_rate"]
            rs_score = 1.0 - min(a.get("recovery_speed_trades", 50), 50) / 50.0
            dd_score = 1.0 - min(a.get("max_dd_pct", 20.0), 20.0) / 20.0

            total = (rar_score * SCORE_WEIGHTS["risk_adjusted"] +
                     pf_score * SCORE_WEIGHTS["profit_factor"] +
                     wr_score * SCORE_WEIGHTS["win_rate"] +
                     rs_score * SCORE_WEIGHTS["recovery_speed"] +
                     dd_score * SCORE_WEIGHTS["max_dd"])

            scored.append({
                "mm_method": mm, "total_score": round(total, 4),
                "breakdown": {"risk_adjusted": round(rar_score, 4),
                              "profit_factor": round(pf_score, 4),
                              "win_rate": round(wr_score, 4),
                              "recovery_speed": round(rs_score, 4),
                              "max_dd": round(dd_score, 4)},
                "trade_count": a["trade_count"]
            })

        scored.sort(key=lambda x: x["total_score"], reverse=True)
        return {"strategy_id": strategy_id, "symbol": symbol,
                "status": "ok", "compared_count": len(scored), "ranking": scored}

    # --------------------------------------------------------
    # Best MM for Regime
    # --------------------------------------------------------

    def get_best_mm_for_regime(self, strategy_id: str, regime: str) -> str:
        """
        เลือก MM method ที่ดีที่สุดสำหรับ strategy+regime.
        Priority: historical data (>= MIN_TRADES_FOR_COMPARISON) > matrix fallback
        """
        if regime not in VALID_REGIMES:
            regime = "RANGING"

        # CRISIS → always MM10
        if regime == "CRISIS":
            return "MM10"

        # Step 1: Build candidates from selection matrix
        regime_cfg = self._selection_matrix.get("regime_overrides", {}).get(regime, {})
        preferred = regime_cfg.get("preferred_mm", [])
        avoid = regime_cfg.get("avoid", [])

        default_mm = self._selection_matrix.get("default_mm_per_strategy", {}).get(strategy_id, "MM01")
        volatile_mm = self._selection_matrix.get("volatile_mm_per_strategy", {}).get(strategy_id)

        candidates = list(set(preferred + [default_mm]))
        if volatile_mm and regime == "VOLATILE":
            candidates.append(volatile_mm)
        candidates = [mm for mm in candidates if mm not in avoid] or [default_mm]

        # Step 2: Try historical comparison
        symbols_seen = {sym for (sid, _, sym) in self._trade_records.keys() if sid == strategy_id}

        for symbol in symbols_seen:
            comp = self.compare_mm_methods(strategy_id, candidates, symbol)
            if comp.get("status") == "ok" and comp["ranking"]:
                best = comp["ranking"][0]
                if best["trade_count"] >= MIN_TRADES_FOR_COMPARISON:
                    logger.info(f"Historical -> {strategy_id}/{regime}: {best['mm_method']}")
                    return best["mm_method"]

        # Step 3: Matrix fallback
        if regime == "VOLATILE" and volatile_mm:
            return volatile_mm
        return preferred[0] if preferred else default_mm

    # --------------------------------------------------------
    # DD Override Recommendation
    # --------------------------------------------------------

    def get_dd_override_recommendation(self, current_dd_pct: float) -> dict:
        """
        ตรวจสอบ drawdown levels → แนะนำ MM override.
        Rules: 10%→reduce50%, 15%→reduce75%, 20%→stop_new_trades
        """
        dd_ovr = self._selection_matrix.get("dd_overrides", {})
        tier1 = dd_ovr.get("dd_10pct", {}).get("threshold_pct", DD_TIER1_PCT)
        tier2 = dd_ovr.get("dd_15pct", {}).get("threshold_pct", DD_TIER2_PCT)
        stop = dd_ovr.get("dd_20pct", {}).get("threshold_pct", DD_STOP_PCT)
        dd = round(current_dd_pct, 2)

        if current_dd_pct >= stop:
            return {"override_active": True, "switch_to": "MM10", "reduce_pct": 100.0,
                    "action": "stop_new_trades", "dd_current": dd, "dd_tier": "STOP",
                    "reasoning_th": f"DD {dd}% >= {stop:.0f}% - หยุดเปิด Trade ใหม่ ใช้ MM10 จัดการ Position เดิม",
                    "reasoning_en": f"DD {dd}% >= {stop:.0f}% - Stop new trades, MM10 manages existing only"}
        elif current_dd_pct >= tier2:
            return {"override_active": True, "switch_to": "MM10", "reduce_pct": 75.0,
                    "action": "reduce_75pct", "dd_current": dd, "dd_tier": "TIER2",
                    "reasoning_th": f"DD {dd}% >= {tier2:.0f}% - ลด Risk เหลือ 25% บังคับ MM10",
                    "reasoning_en": f"DD {dd}% >= {tier2:.0f}% - Reduce to 25%, force MM10"}
        elif current_dd_pct >= tier1:
            return {"override_active": True, "switch_to": "MM10", "reduce_pct": 50.0,
                    "action": "reduce_50pct", "dd_current": dd, "dd_tier": "TIER1",
                    "reasoning_th": f"DD {dd}% >= {tier1:.0f}% - ลด Risk 50% บังคับ MM10",
                    "reasoning_en": f"DD {dd}% >= {tier1:.0f}% - Reduce 50%, force MM10"}
        else:
            return {"override_active": False, "switch_to": None, "reduce_pct": 0.0,
                    "action": "normal", "dd_current": dd, "dd_tier": "NORMAL",
                    "reasoning_th": f"DD {dd}% < {tier1:.0f}% - ปกติ ไม่มี override",
                    "reasoning_en": f"DD {dd}% < {tier1:.0f}% - Normal, no override"}

    # --------------------------------------------------------
    # Summary (for P0.6-6 optimizer input)
    # --------------------------------------------------------

    def get_mm_performance_summary(self, strategy_id: str = None,
                                    symbol: str = None) -> dict:
        """สรุป performance ทุก MM ที่มี data — input สำหรับ P0.6-6."""
        seen = {mm for (sid, mm, sym) in self._trade_records.keys()
                if (not strategy_id or sid == strategy_id) and (not symbol or sym == symbol)}
        return {mm: a for mm in seen
                if (a := self.analyze_mm_effectiveness(mm, strategy_id, symbol)).get("status") == "ok"}

    def get_trade_count(self, mm_method=None, strategy_id=None, symbol=None) -> int:
        return len(self._get_filtered_records(mm_method, strategy_id, symbol))

    # --------------------------------------------------------
    # Private Helpers
    # --------------------------------------------------------

    def _get_filtered_records(self, mm_method=None, strategy_id=None, symbol=None) -> list:
        result = []
        for (sid, mm, sym), records in self._trade_records.items():
            if mm_method and mm != mm_method:
                continue
            if strategy_id and sid != strategy_id:
                continue
            if symbol and sym != symbol:
                continue
            result.extend(records)
        return result

    def _calculate_max_dd_from_trades(self, records: list) -> float:
        """Max drawdown % from sequential trade PnLs."""
        if not records:
            return 0.0
        equity = peak = max_dd = 0.0
        for r in records:
            equity += r.pnl
            if equity > peak:
                peak = equity
            if peak > 0:
                dd_pct = ((peak - equity) / peak) * 100.0
                if dd_pct > max_dd:
                    max_dd = dd_pct
        return max_dd

    def _calculate_recovery_speed(self, records: list) -> int:
        """Avg trades from DD trough to new HWM."""
        if len(records) < 5:
            return 0
        equity = peak = 0.0
        in_dd = False
        dd_start = 0
        counts = []
        for i, r in enumerate(records):
            equity += r.pnl
            if equity > peak:
                if in_dd:
                    counts.append(i - dd_start)
                    in_dd = False
                peak = equity
            elif not in_dd and equity < peak:
                in_dd = True
                dd_start = i
        return round(sum(counts) / len(counts)) if counts else 0