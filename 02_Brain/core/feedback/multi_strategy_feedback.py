"""
FlashEASuite V2 — P0.6-7: Multi-Strategy Feedback Processor
รับ TRADE_REPORT จาก MQL5 → route ไปยัง analyzer ที่ถูกต้อง
Aggregate feedback จาก ≤50 clients → weighted average

Dependencies:
    - GenericStrategyAnalyzer (P0.6-4) — S01-S14
    - MMAnalyzer (P0.6-5) — MM method performance
    - ParameterRepository (P0.6-3) — parameter definitions

Author: FlashEASuite V2 Team | Phase: P0.6-7
"""

import time
import logging
import threading
from collections import defaultdict
from typing import Optional, Any

logger = logging.getLogger("FlashEA.Feedback")

# Strategy routing constants
GENERIC_STRATEGIES = {f"S{i:02d}" for i in range(1, 15)}   # S01-S14
GRID_STRATEGY = "S15"
SPIKE_STRATEGY = "S16"
ALL_STRATEGIES = GENERIC_STRATEGIES | {GRID_STRATEGY, SPIKE_STRATEGY}
MAX_CLIENTS = 50
FEEDBACK_EXPIRY_SECONDS = 7 * 86400   # 7 days
CLIENT_WEIGHT_DECAY = 0.95            # Older reports decay per day


class ClientProfile:
    """Track client reliability + history for weighted aggregation."""
    __slots__ = ['client_id', 'broker', 'first_seen', 'last_seen',
                 'total_reports', 'recent_win_rate', 'weight']

    def __init__(self, client_id: str, broker: str = ""):
        self.client_id = client_id
        self.broker = broker
        self.first_seen = time.time()
        self.last_seen = time.time()
        self.total_reports = 0
        self.recent_win_rate = 0.5
        self.weight = 1.0

    def update(self, win: bool):
        self.last_seen = time.time()
        self.total_reports += 1
        # EMA win rate (alpha=0.05)
        alpha = 0.05
        self.recent_win_rate = alpha * (1.0 if win else 0.0) + (1 - alpha) * self.recent_win_rate
        # Weight: more reports + more recent = higher weight
        age_days = max(1, (time.time() - self.first_seen) / 86400)
        self.weight = min(2.0, (self.total_reports / 50) * (CLIENT_WEIGHT_DECAY ** age_days))
        self.weight = max(0.1, self.weight)


class MultiStrategyFeedback:
    """
    รับ TRADE_REPORT จาก MQL5 → route to correct analyzer.
    Aggregate feedback from up to 50 clients → weighted average.

    Flow: TRADE_REPORT → parse → route → record → aggregate
    """

    def __init__(self, generic_analyzer=None, grid_analyzer=None,
                 spike_analyzer=None, mm_analyzer=None, param_repo=None):
        """
        Args:
            generic_analyzer: GenericStrategyAnalyzer (S01-S14)
            grid_analyzer: GridAnalyzer (S15) — optional, None = skip
            spike_analyzer: SpikeAnalyzer (S16) — optional, None = skip
            mm_analyzer: MMAnalyzer — optional
            param_repo: ParameterRepository
        """
        self._generic = generic_analyzer
        self._grid = grid_analyzer
        self._spike = spike_analyzer
        self._mm = mm_analyzer
        self._repo = param_repo
        self._lock = threading.Lock()

        # Client tracking
        self._clients: dict[str, ClientProfile] = {}

        # Aggregated feedback per strategy×symbol
        # key: (strategy_id, symbol) → list of {pnl, params_used, mm_used, ...}
        self._feedback_buffer: dict[tuple, list] = defaultdict(list)

        # Stats
        self._total_processed = 0
        self._total_rejected = 0
        self._route_counts = defaultdict(int)   # strategy_id → count

        logger.info("[Feedback] Initialized — routes: "
                    f"generic={'YES' if self._generic else 'NO'}, "
                    f"grid={'YES' if self._grid else 'NO'}, "
                    f"spike={'YES' if self._spike else 'NO'}, "
                    f"mm={'YES' if self._mm else 'NO'}")

    # ================================================================
    # Main Entry Point
    # ================================================================

    def process_trade_report(self, trade_data: dict) -> dict:
        """
        Parse TRADE_REPORT dict and route to correct analyzer.

        Expected keys (matching TradeReportMsg fields):
            client_id, symbol, strategy_id, order_type (0=BUY,1=SELL),
            open_price, close_price, profit, lots,
            commission, swap, open_time_ms, close_time_ms,
            params_used (dict, optional), mm_used (str, optional),
            regime_at_entry (str, optional)

        Returns:
            dict: {status, strategy_id, symbol, routed_to, pnl}
        """
        sid = trade_data.get("strategy_id", "")
        symbol = trade_data.get("symbol", "")
        client_id = trade_data.get("client_id", "unknown")

        # Validate
        if sid not in ALL_STRATEGIES:
            self._total_rejected += 1
            logger.warning(f"[Feedback] Unknown strategy: {sid}")
            return {"status": "rejected", "reason": f"unknown_strategy: {sid}"}

        if not symbol:
            self._total_rejected += 1
            return {"status": "rejected", "reason": "missing_symbol"}

        pnl = float(trade_data.get("profit", 0.0))
        is_win = pnl > 0

        # Update client profile
        self._update_client(client_id, trade_data.get("broker", ""), is_win)

        # Build normalized trade dict for analyzers
        duration_ms = (int(trade_data.get("close_time_ms", 0)) -
                       int(trade_data.get("open_time_ms", 0)))
        normalized = {
            "strategy_id": sid,
            "symbol": symbol,
            "direction": "BUY" if int(trade_data.get("order_type", 0)) == 0 else "SELL",
            "entry_price": float(trade_data.get("open_price", 0)),
            "exit_price": float(trade_data.get("close_price", 0)),
            "pnl": pnl,
            "duration_seconds": max(0, duration_ms // 1000),
            "params_used": dict(trade_data.get("params_used", {})),
            "mm_used": trade_data.get("mm_used", "MM01"),
            "regime_at_entry": trade_data.get("regime_at_entry", "UNKNOWN"),
            "timestamp": time.time(),
        }

        # Route to correct analyzer
        routed_to = self._route_trade(sid, symbol, normalized)

        # Route MM data
        if self._mm and normalized.get("mm_used"):
            try:
                self._mm.record_trade(normalized["mm_used"], symbol, normalized)
                routed_to += "+MM"
            except Exception as e:
                logger.debug(f"[Feedback] MM record err: {e}")

        # Buffer for aggregation
        with self._lock:
            key = (sid, symbol)
            buf = self._feedback_buffer[key]
            buf.append({
                "client_id": client_id,
                "pnl": pnl,
                "is_win": is_win,
                "params_used": normalized["params_used"],
                "mm_used": normalized["mm_used"],
                "regime": normalized["regime_at_entry"],
                "timestamp": time.time(),
            })
            # Trim old entries
            cutoff = time.time() - FEEDBACK_EXPIRY_SECONDS
            self._feedback_buffer[key] = [r for r in buf if r["timestamp"] > cutoff][-500:]

        self._total_processed += 1
        self._route_counts[sid] += 1

        return {
            "status": "ok",
            "strategy_id": sid,
            "symbol": symbol,
            "routed_to": routed_to,
            "pnl": pnl,
        }

    # ================================================================
    # Client Feedback Aggregation
    # ================================================================

    def aggregate_client_feedback(self, client_id: str, reports: list) -> dict:
        """
        Process batch of reports from a single client.
        Used when client reconnects and sends buffered trades.

        Args:
            client_id: Client identifier
            reports: list of trade_data dicts

        Returns:
            dict: {processed, rejected, client_weight}
        """
        processed, rejected = 0, 0
        for report in reports:
            report["client_id"] = client_id
            result = self.process_trade_report(report)
            if result.get("status") == "ok":
                processed += 1
            else:
                rejected += 1

        profile = self._clients.get(client_id)
        return {
            "processed": processed,
            "rejected": rejected,
            "client_weight": profile.weight if profile else 0.0,
            "total_reports": profile.total_reports if profile else 0,
        }

    def get_feedback_summary(self, strategy_id: str, symbol: str) -> dict:
        """
        สรุป feedback สำหรับ strategy×symbol pair.

        Returns:
            dict: {trade_count, win_rate, avg_pnl, total_pnl,
                   unique_clients, dominant_regime, mm_distribution}
        """
        with self._lock:
            buf = self._feedback_buffer.get((strategy_id, symbol), [])

        if not buf:
            return {"trade_count": 0, "error": "no_data"}

        wins = sum(1 for r in buf if r["is_win"])
        pnls = [r["pnl"] for r in buf]
        clients = set(r["client_id"] for r in buf)

        # Regime distribution
        regime_counts = defaultdict(int)
        for r in buf:
            regime_counts[r["regime"]] += 1
        dominant = max(regime_counts, key=regime_counts.get) if regime_counts else "UNKNOWN"

        # MM distribution
        mm_counts = defaultdict(int)
        for r in buf:
            mm_counts[r["mm_used"]] += 1

        return {
            "strategy_id": strategy_id,
            "symbol": symbol,
            "trade_count": len(buf),
            "win_rate": round(wins / len(buf), 4),
            "avg_pnl": round(sum(pnls) / len(pnls), 2),
            "total_pnl": round(sum(pnls), 2),
            "unique_clients": len(clients),
            "dominant_regime": dominant,
            "regime_distribution": dict(regime_counts),
            "mm_distribution": dict(mm_counts),
        }

    def get_weighted_feedback(self, strategy_id: str, symbol: str) -> dict:
        """
        Weighted aggregation — clients with more data + better performance
        get higher weight in the feedback signal for Factor 4.

        Returns:
            dict: {weighted_pnl, weighted_win_rate, client_count, param_results}
        """
        with self._lock:
            buf = list(self._feedback_buffer.get((strategy_id, symbol), []))

        if not buf:
            return {"client_count": 0}

        # Group by client
        client_data = defaultdict(list)
        for r in buf:
            client_data[r["client_id"]].append(r)

        total_w = 0.0
        w_pnl = 0.0
        w_wins = 0.0
        w_total = 0.0
        param_scores = defaultdict(lambda: {"weighted_pnl": 0.0, "weight": 0.0, "count": 0})

        for cid, trades in client_data.items():
            profile = self._clients.get(cid)
            w = profile.weight if profile else 0.5
            total_w += w

            c_pnl = sum(r["pnl"] for r in trades)
            c_wins = sum(1 for r in trades if r["is_win"])
            w_pnl += c_pnl * w
            w_wins += c_wins * w
            w_total += len(trades) * w

            # Param-level aggregation
            for r in trades:
                for pn, pv in r.get("params_used", {}).items():
                    ps = param_scores[pn]
                    ps["weighted_pnl"] += r["pnl"] * w
                    ps["weight"] += w
                    ps["count"] += 1

        if total_w == 0:
            return {"client_count": 0}

        # Normalize param scores
        param_results = {}
        for pn, ps in param_scores.items():
            if ps["weight"] > 0 and ps["count"] >= 5:
                param_results[pn] = {
                    "weighted_avg_pnl": round(ps["weighted_pnl"] / ps["weight"], 2),
                    "sample_count": ps["count"],
                }

        return {
            "weighted_pnl": round(w_pnl / total_w, 2),
            "weighted_win_rate": round(w_wins / w_total, 4) if w_total > 0 else 0.0,
            "client_count": len(client_data),
            "param_results": param_results,
        }

    # ================================================================
    # Helpers
    # ================================================================

    def _route_trade(self, sid: str, symbol: str, trade: dict) -> str:
        """Route trade to the correct specialized analyzer."""
        if sid == GRID_STRATEGY:
            if self._grid:
                try:
                    self._grid.record_trade(sid, symbol, trade)
                    return "GridAnalyzer"
                except Exception as e:
                    logger.warning(f"[Feedback] Grid route err: {e}")
            return "SKIP_no_grid_analyzer"

        if sid == SPIKE_STRATEGY:
            if self._spike:
                try:
                    self._spike.record_trade(sid, symbol, trade)
                    return "SpikeAnalyzer"
                except Exception as e:
                    logger.warning(f"[Feedback] Spike route err: {e}")
            return "SKIP_no_spike_analyzer"

        # S01-S14 → GenericAnalyzer
        if self._generic:
            try:
                self._generic.record_trade(sid, symbol, trade)
                return "GenericAnalyzer"
            except Exception as e:
                logger.warning(f"[Feedback] Generic route err: {e}")
        return "SKIP_no_generic_analyzer"

    def _update_client(self, client_id: str, broker: str, is_win: bool):
        """Register or update client profile."""
        with self._lock:
            if client_id not in self._clients:
                if len(self._clients) >= MAX_CLIENTS:
                    # Evict oldest inactive client
                    oldest = min(self._clients.values(), key=lambda c: c.last_seen)
                    del self._clients[oldest.client_id]
                    logger.info(f"[Feedback] Evicted client {oldest.client_id}")
                self._clients[client_id] = ClientProfile(client_id, broker)
            self._clients[client_id].update(is_win)

    # ================================================================
    # Stats & Queries
    # ================================================================

    def get_stats(self) -> dict:
        return {
            "total_processed": self._total_processed,
            "total_rejected": self._total_rejected,
            "active_clients": len(self._clients),
            "buffer_pairs": len(self._feedback_buffer),
            "route_counts": dict(self._route_counts),
        }

    def get_client_profiles(self) -> list:
        return [{"id": c.client_id, "broker": c.broker, "reports": c.total_reports,
                 "weight": round(c.weight, 3), "win_rate": round(c.recent_win_rate, 3)}
                for c in sorted(self._clients.values(), key=lambda x: -x.weight)]

    def get_active_pairs(self) -> list:
        """Return all strategy×symbol pairs with feedback data."""
        return [(sid, sym) for (sid, sym), buf in self._feedback_buffer.items() if buf]

    def cleanup_expired(self):
        """Remove expired feedback entries (called periodically)."""
        cutoff = time.time() - FEEDBACK_EXPIRY_SECONDS
        removed = 0
        with self._lock:
            for key in list(self._feedback_buffer.keys()):
                before = len(self._feedback_buffer[key])
                self._feedback_buffer[key] = [r for r in self._feedback_buffer[key]
                                               if r["timestamp"] > cutoff]
                removed += before - len(self._feedback_buffer[key])
                if not self._feedback_buffer[key]:
                    del self._feedback_buffer[key]
        if removed:
            logger.info(f"[Feedback] Cleanup: removed {removed} expired entries")
        return removed


# ================================================================
# INLINE TESTS
# ================================================================
if __name__ == "__main__":
    import random

    # Mock analyzers
    class MockGeneric:
        def __init__(self): self.trades = []
        def record_trade(self, sid, sym, td): self.trades.append((sid, sym, td))
        def get_trade_count(self, sid, sym=None): return len([t for t in self.trades if t[0]==sid])

    class MockMM:
        def __init__(self): self.trades = []
        def record_trade(self, mm, sym, td): self.trades.append((mm, sym))

    ga = MockGeneric()
    ma = MockMM()
    fb = MultiStrategyFeedback(generic_analyzer=ga, mm_analyzer=ma)

    # T1: Process basic trade report
    r = fb.process_trade_report({
        "client_id": "CLI_001", "symbol": "XAUUSD", "strategy_id": "S01",
        "order_type": 0, "open_price": 2000, "close_price": 2010, "profit": 10.0,
        "open_time_ms": 1000000, "close_time_ms": 1060000,
        "params_used": {"S01_LOOKBACK_PERIOD": 20}, "mm_used": "MM04",
        "regime_at_entry": "TRENDING"
    })
    assert r["status"] == "ok" and r["routed_to"] == "GenericAnalyzer+MM"
    assert len(ga.trades) == 1 and len(ma.trades) == 1
    print("✅ T1: Basic trade routed to GenericAnalyzer + MM")

    # T2: Reject unknown strategy
    r = fb.process_trade_report({"strategy_id": "S99", "symbol": "EURUSD", "profit": 5})
    assert r["status"] == "rejected"
    print("✅ T2: Unknown strategy rejected")

    # T3: S15 Grid → no grid analyzer → skip
    r = fb.process_trade_report({
        "client_id": "CLI_001", "symbol": "XAUUSD", "strategy_id": "S15",
        "order_type": 1, "open_price": 2010, "close_price": 2000, "profit": 10.0
    })
    assert "SKIP" in r["routed_to"]
    print("✅ T3: S15 → no grid analyzer → skip")

    # T4: Batch processing (aggregate_client_feedback)
    reports = []
    random.seed(42)
    for i in range(30):
        reports.append({
            "symbol": "XAUUSD", "strategy_id": "S01", "order_type": random.choice([0,1]),
            "open_price": 2000, "close_price": 2000 + random.uniform(-20, 30),
            "profit": random.uniform(-50, 80), "mm_used": "MM04",
            "regime_at_entry": random.choice(["TRENDING", "RANGING"]),
            "params_used": {"S01_LOOKBACK_PERIOD": random.choice([15, 20, 25])}
        })
    agg = fb.aggregate_client_feedback("CLI_002", reports)
    assert agg["processed"] == 30
    print(f"✅ T4: Batch — {agg['processed']} processed, weight={agg['client_weight']:.2f}")

    # T5: Feedback summary
    s = fb.get_feedback_summary("S01", "XAUUSD")
    assert s["trade_count"] > 0 and "win_rate" in s
    print(f"✅ T5: Summary — {s['trade_count']} trades, WR={s['win_rate']:.2%}, "
          f"regime={s['dominant_regime']}")

    # T6: Weighted feedback
    wf = fb.get_weighted_feedback("S01", "XAUUSD")
    assert wf["client_count"] >= 1
    print(f"✅ T6: Weighted — clients={wf['client_count']}, pnl={wf['weighted_pnl']}")

    # T7: Client profiles
    profiles = fb.get_client_profiles()
    assert len(profiles) >= 2
    print(f"✅ T7: {len(profiles)} client profiles tracked")

    # T8: Stats
    st = fb.get_stats()
    assert st["total_processed"] > 30 and st["active_clients"] >= 2
    print(f"✅ T8: Stats — processed={st['total_processed']}, clients={st['active_clients']}")

    # T9: Cleanup (nothing expired yet)
    removed = fb.cleanup_expired()
    assert removed == 0
    print(f"✅ T9: Cleanup — {removed} expired (expected 0)")

    # T10: Active pairs
    pairs = fb.get_active_pairs()
    assert ("S01", "XAUUSD") in pairs
    print(f"✅ T10: Active pairs — {pairs}")

    print("\n" + "=" * 50)
    print("✅ ALL MultiStrategyFeedback TESTS PASSED")
    print("=" * 50)
