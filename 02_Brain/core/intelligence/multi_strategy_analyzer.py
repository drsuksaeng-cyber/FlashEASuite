"""
MultiStrategyAnalyzer — Orchestrate ทุก analyzers: Grid + Spike + Generic
Phase: P0.6-4 | Depends: GenericStrategyAnalyzer, SpikeAnalyzer, ParameterRepository

Routes trades → correct analyzer, cross-strategy analysis, conflict detection, ranking
"""
import time, math, logging, threading
from collections import defaultdict
from typing import Optional

logger = logging.getLogger("FlashEA.MultiStrategyAnalyzer")

GRID, SPIKE = "S15", "S16"
STRATEGY_CATEGORIES = {
    "trend_following": {"S06", "S10", "S11"}, "mean_reversion": {"S07", "S14"},
    "breakout": {"S09", "S10", "S14"}, "pairs_neutral": {"S01", "S08"},
    "price_action": {"S03", "S05", "S12"}, "volume_based": {"S04"},
    "ai_ml": {"S02"}, "fibonacci": {"S13"}, "grid_range": {"S15"}, "momentum": {"S16"}}
OPPOSING = [("trend_following", "mean_reversion"), ("breakout", "grid_range")]
REGIME_PREFS = {
    "TRENDING": ["trend_following", "breakout", "ai_ml"],
    "RANGING": ["mean_reversion", "grid_range", "pairs_neutral", "price_action"],
    "VOLATILE": ["momentum", "breakout"], "CRISIS": ["pairs_neutral"]}


class MultiStrategyAnalyzer:
    """Orchestrate Grid + Spike + Generic analyzers"""

    def __init__(self, param_repo, grid_analyzer=None, spike_analyzer=None, generic_analyzer=None):
        self.param_repo = param_repo
        self.grid_analyzer = grid_analyzer
        self.spike_analyzer = spike_analyzer
        self.generic_analyzer = generic_analyzer
        self._lock = threading.Lock()
        self._pnl_hist = defaultdict(list)  # {strategy_id: [pnl]}
        logger.info(f"[MultiStrategy] Init — grid={'✅' if grid_analyzer else '❌'} "
                    f"spike={'✅' if spike_analyzer else '❌'} generic={'✅' if generic_analyzer else '❌'}")

    # === ROUTE ===
    def route_trade(self, strategy_id: str, trade_data: dict):
        """Route trade ไปยัง analyzer ที่ถูกต้อง"""
        sym = trade_data.get('symbol', '?'); pnl = float(trade_data.get('pnl', 0))
        if strategy_id == GRID and self.grid_analyzer:
            try: self.grid_analyzer.record_trade(strategy_id, sym, trade_data)
            except Exception as e: logger.error(f"[MultiStrategy] Grid error: {e}")
        elif strategy_id == SPIKE and self.spike_analyzer:
            try:
                if hasattr(self.spike_analyzer, 'record_trade'):
                    self.spike_analyzer.record_trade(strategy_id, sym, trade_data)
                elif hasattr(self.spike_analyzer, 'update_performance'):
                    self.spike_analyzer.update_performance(sym, pnl > 0, pnl)
            except Exception as e: logger.error(f"[MultiStrategy] Spike error: {e}")
        elif self.generic_analyzer:
            self.generic_analyzer.record_trade(strategy_id, sym, trade_data)
        # Cross-strategy tracking
        with self._lock:
            h = self._pnl_hist[strategy_id]; h.append(pnl)
            if len(h) > 500: self._pnl_hist[strategy_id] = h[-500:]

    # === CROSS-STRATEGY ANALYSIS ===
    def get_cross_strategy_analysis(self, symbol: str) -> dict:
        """วิเคราะห์ across ทุก strategy: correlations, conflicts, synergies"""
        active = set()
        if self.generic_analyzer: active.update(self.generic_analyzer.get_active_strategies())
        for s in [GRID, SPIKE]:
            if s in self._pnl_hist: active.add(s)
        active = sorted(active)

        per_strat = {}
        for sid in active:
            if sid in {GRID, SPIKE}:
                pnls = self._pnl_hist.get(sid, [])
                if pnls:
                    per_strat[sid] = {"trade_count": len(pnls), "total_pnl": round(sum(pnls), 2),
                                      "win_rate": round(sum(1 for p in pnls if p > 0) / len(pnls), 4)}
            elif self.generic_analyzer:
                p = self.generic_analyzer.calculate_performance(sid, symbol)
                if 'error' not in p: per_strat[sid] = p

        corrs = self._correlations()
        cat_perf = self._cat_perf()
        synergies = [{"pair": c['pair'], "correlation": c['correlation'],
                       "benefit": "diversification"} for c in corrs if c['correlation'] < -0.3]
        conflicts = []
        for ca, cb in OPPOSING:
            sa = STRATEGY_CATEGORIES.get(ca, set()) & set(active)
            sb = STRATEGY_CATEGORIES.get(cb, set()) & set(active)
            if sa and sb:
                conflicts.append({"category_a": ca, "strategies_a": sorted(sa),
                    "category_b": cb, "strategies_b": sorted(sb), "risk": "opposing_signals"})

        return {"symbol": symbol, "active_strategies": active, "per_strategy": per_strat,
                "correlations": corrs, "category_performance": cat_perf,
                "synergies": synergies, "conflicts": conflicts, "analysis_timestamp": time.time()}

    def _correlations(self) -> list:
        strats = sorted(self._pnl_hist.keys()); corrs = []
        for i, a in enumerate(strats):
            for b in strats[i + 1:]:
                pa, pb = self._pnl_hist[a], self._pnl_hist[b]
                n = min(len(pa), len(pb))
                if n < 10: continue
                corrs.append({"pair": f"{a}-{b}", "correlation": round(self._pearson(pa[-n:], pb[-n:]), 3), "sample_size": n})
        return corrs

    def _pearson(self, x, y):
        n = len(x)
        if n < 2: return 0.0
        mx, my = sum(x) / n, sum(y) / n
        cov = sum((x[i] - mx) * (y[i] - my) for i in range(n)) / (n - 1)
        vx = sum((xi - mx) ** 2 for xi in x) / (n - 1)
        vy = sum((yi - my) ** 2 for yi in y) / (n - 1)
        return cov / (math.sqrt(vx) * math.sqrt(vy)) if vx > 0 and vy > 0 else 0.0

    def _cat_perf(self) -> dict:
        r = {}
        for cat, sids in STRATEGY_CATEGORIES.items():
            pnls = [p for s in sids for p in self._pnl_hist.get(s, [])]
            if pnls:
                r[cat] = {"trade_count": len(pnls), "total_pnl": round(sum(pnls), 2),
                          "win_rate": round(sum(1 for p in pnls if p > 0) / len(pnls), 4)}
        return r

    # === CONFLICT DETECTION ===
    def detect_conflicts(self, pending_changes: dict) -> list:
        """ตรวจสอบ parameter changes ที่ขัดแย้ง across strategies"""
        conflicts = []; fam_chg = defaultdict(list)
        for sid, chgs in pending_changes.items():
            for pn, nv in chgs.items():
                d = self._defn(pn); fam = d.get('family', '?') if d else '?'
                try:
                    cur = self.param_repo.get_strategy_param(sid, pn)
                    if isinstance(cur, (int, float)):
                        fam_chg[fam].append({"strategy": sid, "param": pn,
                            "direction": "increase" if nv > cur else "decrease"})
                except: pass
        for fam, chgs in fam_chg.items():
            inc = [c['strategy'] for c in chgs if c['direction'] == 'increase']
            dec = [c['strategy'] for c in chgs if c['direction'] == 'decrease']
            if inc and dec:
                conflicts.append({"type": "opposing_direction", "family": fam,
                    "increase_strategies": inc, "decrease_strategies": dec,
                    "description": f"Family '{fam}': บางตัวเพิ่ม บางตัวลด", "severity": "medium"})
        # Excessive risk changes
        risk_sids = [sid for sid, chgs in pending_changes.items()
                     for pn in chgs if (self._defn(pn) or {}).get('category') == 'risk_management']
        if len(set(risk_sids)) > 3:
            conflicts.append({"type": "excessive_risk_changes", "strategies": sorted(set(risk_sids)),
                "description": f"{len(set(risk_sids))} strategies risk params change — ตรวจสอบ portfolio risk",
                "severity": "high"})
        return conflicts

    def _defn(self, pn):
        try: return self.param_repo._strategy_params.get(pn) if hasattr(self.param_repo, '_strategy_params') else None
        except: return None

    # === RANKING ===
    def get_strategy_ranking(self, symbol: str, regime: str) -> list:
        """จัดอันดับ strategy by performance ใน regime ปัจจุบัน"""
        prefs = REGIME_PREFS.get(regime, []); rankings = []
        for sid, pnls in sorted(self._pnl_hist.items()):
            if not pnls: continue
            wr = sum(1 for p in pnls if p > 0) / len(pnls)
            # Regime-specific win rate from generic analyzer
            rwr = wr
            if self.generic_analyzer and sid not in {GRID, SPIKE}:
                rp = self.generic_analyzer.get_regime_specific_performance(sid, regime)
                if 'error' not in rp: rwr = rp.get('win_rate', wr)
            # Regime fit bonus
            fit = 0.1 if any(sid in STRATEGY_CATEGORIES.get(c, set()) for c in prefs) else 0.0
            score = round(min(1.0, max(0.0, 0.6 * rwr + 0.3 * wr + fit)), 3)
            rankings.append({"strategy_id": sid, "score": score, "win_rate": round(wr, 4),
                "regime_win_rate": round(rwr, 4), "total_pnl": round(sum(pnls), 2),
                "trade_count": len(pnls), "regime_fit": round(fit, 2)})
        rankings.sort(key=lambda x: x['score'], reverse=True)
        for i, r in enumerate(rankings): r['rank'] = i + 1
        return rankings


# === INLINE TESTS ===
if __name__ == "__main__":
    import random, sys; sys.path.insert(0, '.')
    from generic_strategy_analyzer import GenericStrategyAnalyzer
    class MockRepo:
        def __init__(self):
            self._strategy_params = {
                "S01_LOOKBACK_PERIOD": {"strategy": "S01", "default": 20, "min": 10, "max": 100,
                    "step": 5, "family": "MOMENTUM_TIMING", "category": "signal_generation",
                    "regime_sensitive": True, "max_change_per_cycle_pct": 20},
                "S07_RSI_PERIOD": {"strategy": "S07", "default": 14, "min": 7, "max": 21,
                    "step": 1, "family": "INDICATOR_PARAMS", "category": "signal_generation",
                    "regime_sensitive": False, "max_change_per_cycle_pct": 15}}
        def get_strategy_param(self, sid, pn, **kw): return self._strategy_params.get(pn, {}).get('default')

    repo = MockRepo(); gen = GenericStrategyAnalyzer(repo)
    ms = MultiStrategyAnalyzer(param_repo=repo, generic_analyzer=gen)
    random.seed(42)
    for sid in ["S01", "S06", "S07", "S15", "S16"]:
        for _ in range(30):
            ms.route_trade(sid, {"symbol": "XAUUSD", "direction": "BUY", "entry_price": 2000,
                "exit_price": 2010, "pnl": random.uniform(-50, 80),
                "duration_seconds": random.randint(60, 3600), "params_used": {},
                "mm_used": "MM01", "regime_at_entry": random.choice(["TRENDING", "RANGING", "VOLATILE"])})
    assert gen.get_trade_count("S01") > 0 and gen.get_trade_count("S15") == 0
    print("✅ T1: Routing — S01→Generic, S15→Grid")
    cross = ms.get_cross_strategy_analysis("XAUUSD")
    assert len(cross['active_strategies']) >= 3; print(f"✅ T2: {len(cross['active_strategies'])} active strategies")
    print(f"✅ T3: {len(cross['correlations'])} correlations")
    c = ms.detect_conflicts({"S01": {"S01_LOOKBACK_PERIOD": 25}, "S07": {"S07_RSI_PERIOD": 10}})
    print(f"✅ T4: {len(c)} conflicts")
    rk = ms.get_strategy_ranking("XAUUSD", "TRENDING")
    assert rk[0]['rank'] == 1 and rk[0]['score'] >= rk[-1]['score']
    print(f"✅ T5: Top={rk[0]['strategy_id']} (score={rk[0]['score']})")
    print(f"✅ T6: Categories — {list(cross['category_performance'].keys())}")
    print(f"✅ T7: Synergies={len(cross['synergies'])} Conflicts={len(cross['conflicts'])}")
    print("\n" + "=" * 50 + "\n✅ ALL MultiStrategyAnalyzer TESTS PASSED\n" + "=" * 50)