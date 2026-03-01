"""
GenericStrategyAnalyzer — วิเคราะห์ performance ของ S01-S14
ที่ไม่มี specialized analyzer (Grid=S15, Spike=S16 มี analyzer แยก)
Phase: P0.6-4 | Depends: ParameterRepository (P0.6-3)

Trade data: {strategy_id, symbol, direction, entry_price, exit_price,
    pnl, duration_seconds, params_used: dict, mm_used: str, regime_at_entry: str}
"""
import time, math, logging, threading
from collections import defaultdict
from typing import Optional

logger = logging.getLogger("FlashEA.GenericAnalyzer")
VALID_REGIMES = {"TRENDING", "RANGING", "VOLATILE", "CRISIS", "UNKNOWN"}
GENERIC_STRATEGIES = {f"S{i:02d}" for i in range(1, 15)}
SPECIALIZED = {"S15", "S16"}

class TradeRecord:
    __slots__ = ['strategy_id', 'symbol', 'direction', 'entry_price', 'exit_price',
                 'pnl', 'duration_seconds', 'params_used', 'mm_used', 'regime_at_entry', 'timestamp']
    def __init__(self, d: dict):
        self.strategy_id, self.symbol = d['strategy_id'], d['symbol']
        self.direction = d.get('direction', 'BUY')
        self.entry_price, self.exit_price = float(d['entry_price']), float(d['exit_price'])
        self.pnl = float(d['pnl'])
        self.duration_seconds = int(d.get('duration_seconds', 0))
        self.params_used = dict(d.get('params_used', {}))
        self.mm_used = d.get('mm_used', 'MM01')
        self.regime_at_entry = d.get('regime_at_entry', 'UNKNOWN')
        self.timestamp = d.get('timestamp', time.time())
    @property
    def is_win(self): return self.pnl > 0


class GenericStrategyAnalyzer:
    """วิเคราะห์ performance S01-S14 — in-memory, thread-safe"""
    MAX_TRADES, MIN_TRADES, MIN_PARAM = 2000, 10, 20

    def __init__(self, param_repo):
        self.param_repo = param_repo
        self._trades = defaultdict(lambda: defaultdict(list))
        self._lock = threading.Lock()
        logger.info("[GenericAnalyzer] Initialized — covers S01-S14")

    def record_trade(self, strategy_id: str, symbol: str, trade_data: dict):
        """บันทึก trade result"""
        if strategy_id in SPECIALIZED:
            logger.warning(f"[GenericAnalyzer] {strategy_id} has specialized analyzer — skipped"); return
        if strategy_id not in GENERIC_STRATEGIES:
            logger.warning(f"[GenericAnalyzer] Unknown: {strategy_id}"); return
        trade_data.update(strategy_id=strategy_id, symbol=symbol)
        with self._lock:
            b = self._trades[strategy_id][symbol]
            b.append(TradeRecord(trade_data))
            if len(b) > self.MAX_TRADES: self._trades[strategy_id][symbol] = b[-self.MAX_TRADES:]

    def get_trade_count(self, sid: str, sym: str = None) -> int:
        return len(self._trades[sid][sym]) if sym else sum(len(v) for v in self._trades[sid].values())

    def calculate_performance(self, sid: str, sym: str, lookback_days: int = 30) -> dict:
        """คำนวณ win_rate, profit_factor, avg_pnl, max_dd, sharpe"""
        trades = [t for t in self._trades[sid][sym] if t.timestamp >= time.time() - lookback_days * 86400]
        if len(trades) < self.MIN_TRADES:
            return {"error": "insufficient_data", "trade_count": len(trades), "min_required": self.MIN_TRADES}
        return self._metrics(trades)

    def _metrics(self, trades: list) -> dict:
        n = len(trades)
        wins = [t for t in trades if t.is_win]; losses = [t for t in trades if not t.is_win]
        pnls = [t.pnl for t in trades]
        gp = sum(t.pnl for t in wins) if wins else 0.0
        gl = abs(sum(t.pnl for t in losses)) if losses else 0.0
        wr = len(wins) / n
        pf = gp / gl if gl > 0 else (999.0 if gp > 0 else 0.0)
        aw = gp / len(wins) if wins else 0.0; al = gl / len(losses) if losses else 0.0
        return {"trade_count": n, "win_count": len(wins), "loss_count": len(losses),
                "win_rate": round(wr, 4), "profit_factor": round(pf, 2),
                "avg_pnl": round(sum(pnls) / n, 2), "total_pnl": round(sum(pnls), 2),
                "max_drawdown": round(self._max_dd(pnls), 2),
                "sharpe_ratio": round(self._sharpe(pnls), 2),
                "avg_duration_seconds": round(sum(t.duration_seconds for t in trades) / n, 1),
                "avg_win": round(aw, 2), "avg_loss": round(al, 2),
                "expectancy": round(wr * aw - (1 - wr) * al, 2)}

    def _max_dd(self, pnls):
        eq = pk = dd = 0.0
        for p in pnls:
            eq += p
            if eq > pk: pk = eq
            if pk - eq > dd: dd = pk - eq
        return dd

    def _sharpe(self, pnls):
        if len(pnls) < 2: return 0.0
        m = sum(pnls) / len(pnls)
        v = sum((p - m) ** 2 for p in pnls) / (len(pnls) - 1)
        s = math.sqrt(v) if v > 0 else 0.0
        return (m / s) * math.sqrt(252) if s > 0 else 0.0

    # === PARAMETER EFFECTIVENESS ===
    def analyze_parameter_effectiveness(self, sid: str, param_name: str) -> dict:
        """วิเคราะห์ค่า param ไหนให้ performance ดีสุด → optimize direction"""
        all_t = [t for st in self._trades[sid].values() for t in st]
        if len(all_t) < self.MIN_PARAM:
            return {"error": "insufficient_data", "trade_count": len(all_t)}
        pt = [(t, t.params_used[param_name]) for t in all_t if param_name in t.params_used]
        if len(pt) < self.MIN_PARAM:
            return {"error": "param_not_recorded", "trade_count": len(pt)}
        groups = self._bucket(pt)
        best = max(groups, key=lambda g: g.get('expectancy', 0)) if groups else None
        return {"param_name": param_name, "total_trades": len(pt), "groups": groups,
                "best_range": best['value_range'] if best else "N/A",
                "trend_direction": self._trend(groups)}

    def _bucket(self, pt):
        vals = [v for _, v in pt if isinstance(v, (int, float))]
        if not vals: return []
        lo, hi = min(vals), max(vals)
        if lo == hi:
            ts = [t for t, _ in pt]
            return [{"value_range": f"{lo}", "trade_count": len(ts),
                     **(self._metrics(ts) if len(ts) >= 5 else {})}]
        nb = min(5, max(3, len(set(vals)) // 3)); bs = (hi - lo) / nb
        groups = []
        for i in range(nb):
            blo, bhi = lo + i * bs, (lo + (i + 1) * bs if i < nb - 1 else hi + 0.001)
            bt = [t for t, v in pt if isinstance(v, (int, float)) and blo <= v < bhi]
            if len(bt) >= 5:
                m = self._metrics(bt); m['value_range'] = f"{blo:.2f}-{bhi:.2f}"; groups.append(m)
        return groups

    def _trend(self, groups):
        if len(groups) < 2: return "inconclusive"
        mid = len(groups) // 2
        lo_e = sum(g.get('expectancy', 0) for g in groups[:mid]) / max(mid, 1)
        hi_e = sum(g.get('expectancy', 0) for g in groups[mid:]) / max(len(groups) - mid, 1)
        if len(groups) >= 3 and groups[mid].get('expectancy', 0) > max(
                groups[0].get('expectancy', 0), groups[-1].get('expectancy', 0)) * 1.2:
            return "optimal_middle"
        th = max(abs(lo_e), abs(hi_e)) * 0.15
        return "higher_better" if hi_e - lo_e > th else ("lower_better" if hi_e - lo_e < -th else "inconclusive")

    # === REGIME ===
    def get_regime_specific_performance(self, sid: str, regime: str) -> dict:
        if regime not in VALID_REGIMES: return {"error": f"invalid_regime: {regime}"}
        rt = [t for st in self._trades[sid].values() for t in st if t.regime_at_entry == regime]
        if len(rt) < self.MIN_TRADES:
            return {"error": "insufficient_data", "trade_count": len(rt), "regime": regime}
        m = self._metrics(rt); m['regime'] = regime; m['symbols'] = list(set(t.symbol for t in rt))
        return m

    def get_all_regime_performance(self, sid: str) -> dict:
        return {r: p for r in VALID_REGIMES if 'error' not in (p := self.get_regime_specific_performance(sid, r))}

    # === COMPREHENSIVE ===
    def get_comprehensive_analysis(self, sid: str, sym: str) -> dict:
        """Full analysis → input สำหรับ optimizer (P0.6-6)"""
        pa = {}
        for pn in self._get_param_names(sid):
            if self._is_rs(pn):
                r = self.analyze_parameter_effectiveness(sid, pn)
                if 'error' not in r: pa[pn] = r
                if len(pa) >= 5: break
        return {"strategy_id": sid, "symbol": sym,
                "overall_performance": self.calculate_performance(sid, sym),
                "regime_breakdown": self.get_all_regime_performance(sid),
                "param_effectiveness": pa, "trade_count": self.get_trade_count(sid, sym),
                "analysis_timestamp": time.time()}

    # === SUGGESTIONS ===
    def suggest_param_changes(self, sid: str, sym: str) -> list:
        """แนะนำ parameter changes → [{param, current, suggested, reason, confidence}]"""
        a = self.get_comprehensive_analysis(sid, sym)
        if 'error' in a.get('overall_performance', {}): return []
        sug = []
        for pn, eff in a.get('param_effectiveness', {}).items():
            s = self._suggest(pn, eff, sid)
            if s: sug.append(s)
        sug.sort(key=lambda x: x['confidence'], reverse=True)
        return sug

    def _suggest(self, pn, eff, sid):
        tr = eff.get('trend_direction', 'inconclusive')
        if tr == 'inconclusive': return None
        try: cur = self.param_repo.get_strategy_param(sid, pn)
        except: return None
        if not isinstance(cur, (int, float)): return None
        d = self._defn(pn); step = d.get('step', 1) if d else 1
        mcp = (d.get('max_change_per_cycle_pct', 20) / 100) if d else 0.2
        br = eff.get('best_range', '?')
        if tr == 'higher_better': sug, rsn = cur + step, f"ค่าสูงกว่าดีกว่า (best: {br})"
        elif tr == 'lower_better': sug, rsn = cur - step, f"ค่าต่ำกว่าดีกว่า (best: {br})"
        else: return None
        md = abs(cur * mcp) if cur != 0 else abs(step)
        if abs(sug - cur) > md: sug = cur + math.copysign(md, sug - cur)
        if d:
            if d.get('min') is not None: sug = max(sug, d['min'])
            if d.get('max') is not None: sug = min(sug, d['max'])
        if step > 0: sug = int(round(sug / step) * step) if isinstance(cur, int) else round(round(sug / step) * step, 4)
        if sug == cur: return None
        return {"param": pn, "current": cur, "suggested": sug, "reason": rsn,
                "confidence": round(min(1.0, eff.get('total_trades', 0) / 100 * 0.7 + 0.2), 2)}

    # === HELPERS ===
    def _defn(self, pn):
        try: return self.param_repo._strategy_params.get(pn) if hasattr(self.param_repo, '_strategy_params') else None
        except: return None
    def _get_param_names(self, sid):
        try: return [n for n, d in self.param_repo._strategy_params.items() if d.get('strategy') == sid] if hasattr(self.param_repo, '_strategy_params') else []
        except: return []
    def _is_rs(self, pn):
        d = self._defn(pn); return d.get('regime_sensitive', False) if d else False
    def get_active_strategies(self):
        return [s for s in sorted(self._trades) if any(len(t) > 0 for t in self._trades[s].values())]
    def get_active_symbols(self, sid):
        return [s for s, t in self._trades[sid].items() if len(t) > 0]


# === INLINE TESTS ===
if __name__ == "__main__":
    import random
    class MockRepo:
        def __init__(self):
            self._strategy_params = {
                "S01_LOOKBACK_PERIOD": {"strategy": "S01", "default": 20, "min": 10, "max": 100, "step": 5,
                    "regime_sensitive": True, "max_change_per_cycle_pct": 20},
                "S01_ENTRY_ZSCORE": {"strategy": "S01", "default": 2.0, "min": 1.0, "max": 3.0, "step": 0.1,
                    "regime_sensitive": True, "max_change_per_cycle_pct": 15}}
        def get_strategy_param(self, sid, pn, **kw): return self._strategy_params.get(pn, {}).get('default')

    az = GenericStrategyAnalyzer(MockRepo()); random.seed(42)
    for i in range(50):
        az.record_trade("S01", "XAUUSD", {"direction": "BUY", "entry_price": 2000, "exit_price": 2010,
            "pnl": random.uniform(-50, 80), "duration_seconds": random.randint(60, 3600),
            "params_used": {"S01_LOOKBACK_PERIOD": random.choice([15, 20, 25, 30]),
                "S01_ENTRY_ZSCORE": random.choice([1.5, 2.0, 2.5])},
            "mm_used": "MM04", "regime_at_entry": random.choice(["TRENDING", "RANGING", "VOLATILE"]),
            "timestamp": time.time() - random.randint(0, 86400 * 30)})
    assert az.get_trade_count("S01", "XAUUSD") == 50; print("✅ T1: Record 50 trades")
    p = az.calculate_performance("S01", "XAUUSD"); assert 'error' not in p
    print(f"✅ T2: WR={p['win_rate']:.2%} PF={p['profit_factor']} Sharpe={p['sharpe_ratio']}")
    assert az.calculate_performance("S02", "EURUSD").get('error'); print("✅ T3: Insufficient data")
    az.record_trade("S15", "XAUUSD", {"direction": "BUY", "entry_price": 2000, "exit_price": 2010,
        "pnl": 10, "duration_seconds": 100, "params_used": {}, "mm_used": "MM03", "regime_at_entry": "RANGING"})
    assert az.get_trade_count("S15") == 0; print("✅ T4: S15 rejected → specialized")
    print(f"✅ T5: Regimes — {list(az.get_all_regime_performance('S01').keys())}")
    pe = az.analyze_parameter_effectiveness("S01", "S01_LOOKBACK_PERIOD")
    print(f"✅ T6: Param trend={pe.get('trend_direction', 'N/A')}")
    assert az.get_comprehensive_analysis("S01", "XAUUSD")['strategy_id'] == "S01"; print("✅ T7: Comprehensive")
    print(f"✅ T8: {len(az.suggest_param_changes('S01', 'XAUUSD'))} suggestions")
    assert az._max_dd([10, -5, 8, -15, 3]) > 0; print("✅ T9: Max DD OK")
    assert "S01" in az.get_active_strategies(); print("✅ T10: Active strategies")
    print("\n" + "=" * 50 + "\n✅ ALL GenericStrategyAnalyzer TESTS PASSED\n" + "=" * 50)