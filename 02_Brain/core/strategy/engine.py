#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Strategy Engine - DEBUG VERSION with CORRECT MessagePack Format
Version: 2.4 (Adaptive Parameter Tuning)

แก้ไข v2.3:
- FIX #1: Normalize symbol key (strip .tp/.m/_m suffix) → merge tick_history
- FIX #2: Spike score window 20 → 50 ticks
- FIX #3: Spike debug log ทุก tick (ไม่ใช่แค่ทุก N ticks)
- FIX #4: MIN_TICKS_REQUIRED 50 → 30

แก้ไข v2.4 (Adaptive Params):
- Added PerformanceTracker — records trade results from feedback_queue
- Added AdaptiveParamManager — adjusts strategy params based on performance
- _process_feedback(): drains feedback_queue every iteration (non-blocking)
- _check_adaptive_params(): runs every 60s, pushes type=14 MSG_DYNAMIC_PARAMS
- _send_dynamic_params(): publishes [14, ts, symbol, sid, {params}] via ZMQ PUB
"""

import time
import threading
import queue
import zmq
import msgpack
from datetime import datetime
from collections import defaultdict, deque
from typing import Dict, List, Optional, Tuple

from .performance_tracker import PerformanceTracker
from .adaptive_params import AdaptiveParamManager

# ========================================================================
# CONFIGURATION
# ========================================================================

class StrategyConfig:
    """Configuration ที่ปรับได้"""
    
    # Policy Generation Thresholds
    MIN_SPIKE_SCORE = 70.0
    MIN_GRID_CONFIDENCE = 0.3
    MIN_TICKS_REQUIRED = 30          # FIX #4: ลดจาก 50 → 30
    
    # Spike Detection
    SPIKE_SCORE_WINDOW = 50          # FIX #2: ขยายจาก 20 → 50
    SPIKE_DEBUG_ENABLED = True       # FIX #3: log spike score ทุก tick
    SPIKE_DEBUG_THRESHOLD = 30.0     # log เมื่อ score > threshold นี้
    
    # Cooldown (seconds)
    POLICY_COOLDOWN = 10
    
    # Symbol Filtering
    ALLOWED_SYMBOLS = [
        "EURUSD", "GBPUSD", "USDJPY", "XAUUSD",
        "EURJPY", "GBPJPY", "AUDJPY", "NZDJPY",
        "GBPAUD", "AUDCAD", "AUDUSD", "NZDUSD"
    ]
    
    # Broker suffix patterns to strip
    SUFFIX_PATTERNS = [".tp", "_m", ".m", ".raw", ".pro", ".ecn", ".std"]
    
    # Debug Mode
    VERBOSE_LOGGING = True
    LOG_EVERY_N_TICKS = 50

# ========================================================================
# DEBUG LOGGER
# ========================================================================

class DebugLogger:
    """Logger พร้อมระบุจุดที่ผ่านมา"""
    
    def __init__(self, verbose=True):
        self.verbose = verbose
        self.tick_count = 0
        self.checkpoint_counts = defaultdict(int)
    
    def checkpoint(self, point: str, message: str = ""):
        """บันทึก checkpoint"""
        self.checkpoint_counts[point] += 1
        
        if self.verbose:
            timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            print(f"[{timestamp}] ✓ CHECKPOINT: {point} | {message}")
    
    def decision(self, condition: str, result: bool, reason: str = ""):
        """บันทึกการตัดสินใจ"""
        symbol = "✅" if result else "❌"
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        
        if self.verbose:
            print(f"[{timestamp}] {symbol} DECISION: {condition} = {result} | {reason}")
    
    def policy_attempt(self, symbol: str, strategy: str, score: float, sent: bool, reason: str = ""):
        """บันทึกความพยายามส่ง policy"""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        status = "📤 SENT" if sent else "🚫 BLOCKED"
        
        print(f"[{timestamp}] {status}: {symbol} | {strategy} | Score: {score:.2f} | {reason}")
    
    def spike_debug(self, symbol: str, score: float, price_change: float, 
                    volatility: float, window_size: int, first_price: float, last_price: float):
        """FIX #3: Spike-specific debug log"""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        print(f"[{timestamp}] 🔥 SPIKE_SCORE: {symbol} | "
              f"Score={score:.2f} | PriceChg={price_change:.2f}pips | "
              f"Vol={volatility:.2f} | Window={window_size} | "
              f"Price: {first_price:.5f} → {last_price:.5f}")
    
    def summary(self):
        """แสดงสรุป checkpoints"""
        print("\n" + "="*70)
        print("📊 CHECKPOINT SUMMARY")
        print("="*70)
        
        for point, count in sorted(self.checkpoint_counts.items()):
            print(f"  {point:30s}: {count:6d} times")
        
        print("="*70 + "\n")


# ========================================================================
# SYMBOL NORMALIZER
# ========================================================================

def normalize_symbol(symbol: str, suffix_patterns: list = None) -> str:
    """
    FIX #1: Strip broker suffix to get base symbol
    
    "XAUUSD.tp" → "XAUUSD"
    "GBPUSD_m"  → "GBPUSD"  
    "EURUSD.raw" → "EURUSD"
    "EURUSD"    → "EURUSD" (no change)
    """
    if suffix_patterns is None:
        suffix_patterns = [".tp", "_m", ".m", ".raw", ".pro", ".ecn", ".std"]
    
    result = symbol
    for suffix in suffix_patterns:
        if result.endswith(suffix):
            result = result[:-len(suffix)]
            break  # Only strip one suffix
    
    return result


# ========================================================================
# STRATEGY ENGINE
# ========================================================================

class StrategyEngineThreaded:
    """Strategy Engine with CORRECT MessagePack format"""
    
    def __init__(
        self,
        ingestion_queue: queue.Queue,
        signal_queue: queue.Queue,
        feedback_queue: queue.Queue,
        shutdown_event: threading.Event,
        zmq_pub_address: str
    ):
        self.ingestion_queue = ingestion_queue
        self.signal_queue = signal_queue
        self.feedback_queue = feedback_queue
        self.shutdown_event = shutdown_event
        self.zmq_pub_address = zmq_pub_address
        
        # Configuration
        self.config = StrategyConfig()
        
        # Debug Logger
        self.logger = DebugLogger(verbose=self.config.VERBOSE_LOGGING)
        
        # ZMQ Publisher
        self.context = zmq.Context()
        self.publisher = None
        
        # State
        self.tick_count = 0
        self.policy_count = 0
        
        # FIX #1: tick_history keyed by NORMALIZED symbol (no suffix)
        self.tick_history = defaultdict(lambda: deque(maxlen=500))
        
        # Map: raw_symbol → normalized_symbol (for debugging)
        self.symbol_map = {}
        
        self.last_policy_time = defaultdict(float)
        
        # Spike scores (keyed by normalized symbol)
        self.spike_scores = {}
        
        # Risk multiplier
        self.risk_multiplier = 1.0

        # ── Adaptive parameter tuning ─────────────────────────────────
        self.perf_tracker  = PerformanceTracker()
        self.param_manager = AdaptiveParamManager()
        self._last_adapt_check = 0.0   # wall-clock time of last _check_adaptive_params

        print("🔍 DEBUG MODE: Strategy Engine v2.4 (Adaptive Params)")
        print(f"   - Min Spike Score: {self.config.MIN_SPIKE_SCORE}")
        print(f"   - Min Grid Confidence: {self.config.MIN_GRID_CONFIDENCE}")
        print(f"   - Min Ticks Required: {self.config.MIN_TICKS_REQUIRED}")
        print(f"   - Spike Score Window: {self.config.SPIKE_SCORE_WINDOW} ticks")
        print(f"   - Policy Cooldown: {self.config.POLICY_COOLDOWN}s")
        print(f"   - Suffix Patterns: {self.config.SUFFIX_PATTERNS}")
        print("   - ✅ FIX #1: Symbol normalization (merge tick history)")
        print("   - ✅ FIX #2: Spike window 50 ticks")
        print("   - ✅ FIX #3: Spike debug logging")
        print("   - ✅ FIX #4: MIN_TICKS_REQUIRED = 30")
        print("   - ✅ v2.4: Adaptive param tuning (PerformanceTracker + AdaptiveParamManager)")
    
    def setup_zmq(self):
        """Setup ZMQ publisher"""
        try:
            self.publisher = self.context.socket(zmq.PUB)
            self.publisher.setsockopt(zmq.LINGER, 0)
            self.publisher.setsockopt(zmq.SNDHWM, 100000)
            self.publisher.bind(self.zmq_pub_address)
            
            self.logger.checkpoint("ZMQ_SETUP", f"Bound to {self.zmq_pub_address}")
            return True
            
        except Exception as e:
            print(f"❌ ZMQ Setup Error: {e}")
            return False
    
    def process_tick(self, tick_data: Dict):
        """Process one tick"""
        
        # CHECKPOINT 1: Tick received
        self.tick_count += 1
        raw_symbol = tick_data.get('symbol', 'UNKNOWN')
        
        # FIX #1: Normalize symbol for storage
        symbol = normalize_symbol(raw_symbol, self.config.SUFFIX_PATTERNS)
        
        # Track mapping (first time only)
        if raw_symbol not in self.symbol_map:
            self.symbol_map[raw_symbol] = symbol
            self.logger.checkpoint(
                "SYMBOL_MAPPED",
                f"'{raw_symbol}' → '{symbol}'"
            )
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.checkpoint(
                "TICK_RECEIVED", 
                f"Total: {self.tick_count} | Raw: {raw_symbol} | Normalized: {symbol}"
            )
        
        # Store in history using NORMALIZED symbol key
        self.tick_history[symbol].append(tick_data)
        
        # CHECKPOINT 2: Check if enough data
        history_len = len(self.tick_history[symbol])
        has_enough_data = history_len >= self.config.MIN_TICKS_REQUIRED
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.decision(
                f"ENOUGH_DATA[{symbol}]",
                has_enough_data,
                f"History: {history_len}/{self.config.MIN_TICKS_REQUIRED}"
            )
        
        if not has_enough_data:
            return
        
        # CHECKPOINT 3: Analysis
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.checkpoint("ANALYSIS_START", f"Symbol: {symbol}")
        
        spike_score = self.calculate_spike_score(symbol)
        grid_confidence = self.calculate_grid_confidence(symbol)
        
        self.spike_scores[symbol] = spike_score
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.checkpoint(
                "ANALYSIS_COMPLETE",
                f"{symbol}: Spike={spike_score:.2f}, Grid={grid_confidence:.2f}"
            )
        
        # CHECKPOINT 4: Try to generate policy
        # ส่ง raw_symbol ไปด้วยเพื่อให้ Trader ใช้ symbol ที่ถูกต้องตาม broker
        self.try_generate_policy(symbol, raw_symbol, spike_score, grid_confidence)
    
    def calculate_spike_score(self, symbol: str) -> float:
        """
        คำนวณ spike score
        
        FIX #2: ใช้ SPIKE_SCORE_WINDOW (50) แทน hardcode 20
        FIX #3: Log spike score เมื่อเกิน threshold
        """
        history = list(self.tick_history[symbol])
        
        window = self.config.SPIKE_SCORE_WINDOW
        
        if len(history) < window:
            # ถ้ายังไม่ถึง window size ใช้ทั้งหมดที่มี (ต้อง >= 10)
            if len(history) < 10:
                return 0.0
            window = len(history)
        
        prices = [t.get('bid', 0) for t in history[-window:]]
        
        if not prices or prices[0] == 0:
            return 0.0
        
        # Price change (first → last in window)
        price_change = abs(prices[-1] - prices[0]) / prices[0] * 10000  # in pips
        
        # Volatility (standard deviation)
        mean_price = sum(prices) / len(prices)
        variance = sum((p - mean_price)**2 for p in prices) / len(prices)
        std_dev = variance ** 0.5
        volatility = std_dev / mean_price * 10000  # in pips
        
        # Spike score
        spike_score = min(100, (price_change * 2 + volatility * 3))
        
        # FIX #3: Debug log when score is notable
        if self.config.SPIKE_DEBUG_ENABLED and spike_score >= self.config.SPIKE_DEBUG_THRESHOLD:
            self.logger.spike_debug(
                symbol=symbol,
                score=spike_score,
                price_change=price_change,
                volatility=volatility,
                window_size=len(prices),
                first_price=prices[0],
                last_price=prices[-1]
            )
        
        return spike_score
    
    def calculate_grid_confidence(self, symbol: str) -> float:
        """คำนวณ grid confidence"""
        history = list(self.tick_history[symbol])
        
        if len(history) < 50:
            return 0.0
        
        prices = [t.get('bid', 0) for t in history[-50:]]
        
        if not prices or prices[0] == 0:
            return 0.0
        
        max_price = max(prices)
        min_price = min(prices)
        price_range = max_price - min_price
        
        trend_strength = price_range / prices[0]
        confidence = max(0.0, 1.0 - trend_strength * 100)
        
        return confidence
    
    def try_generate_policy(self, symbol: str, raw_symbol: str,
                            spike_score: float, grid_confidence: float):
        """
        พยายามสร้าง policy
        
        FIX #1: symbol = normalized, raw_symbol = ตัวจริงจาก broker
        ส่ง raw_symbol ใน policy เพื่อให้ Trader match กับ _Symbol ได้
        """
        
        # CHECKPOINT 5: Symbol filter (ใช้ normalized symbol)
        is_allowed = symbol in self.config.ALLOWED_SYMBOLS
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.decision(
                f"SYMBOL_ALLOWED[{symbol}]",
                is_allowed,
                f"Raw: {raw_symbol}"
            )
        
        if not is_allowed:
            return
        
        # CHECKPOINT 6: Score threshold (Spike)
        spike_ok = spike_score >= self.config.MIN_SPIKE_SCORE
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.decision(
                f"SPIKE_THRESHOLD[{symbol}]",
                spike_ok,
                f"Score {spike_score:.2f} vs {self.config.MIN_SPIKE_SCORE}"
            )
        
        # CHECKPOINT 7: Grid confidence threshold
        grid_ok = grid_confidence >= self.config.MIN_GRID_CONFIDENCE
        
        if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
            self.logger.decision(
                f"GRID_THRESHOLD[{symbol}]",
                grid_ok,
                f"Confidence {grid_confidence:.2f} vs {self.config.MIN_GRID_CONFIDENCE}"
            )
        
        # Choose strategy
        if spike_ok:
            strategy = "Spike"
            score = spike_score
        elif grid_ok:
            strategy = "Grid"
            score = grid_confidence * 100
        else:
            if self.tick_count % self.config.LOG_EVERY_N_TICKS == 0:
                self.logger.policy_attempt(
                    symbol, "None", 0.0, False,
                    f"No strategy: Spike={spike_score:.2f}, Grid={grid_confidence:.2f}"
                )
            return
        
        # CHECKPOINT 8: Cooldown check (ใช้ normalized symbol)
        now = time.time()
        last_time = self.last_policy_time.get(symbol, 0)
        cooldown_remaining = self.config.POLICY_COOLDOWN - (now - last_time)
        cooldown_ok = cooldown_remaining <= 0
        
        self.logger.decision(
            f"COOLDOWN[{symbol}]",
            cooldown_ok,
            f"Remaining: {max(0, cooldown_remaining):.1f}s"
        )
        
        if not cooldown_ok:
            self.logger.policy_attempt(
                symbol, strategy, score, False,
                f"Cooldown: {cooldown_remaining:.1f}s remaining"
            )
            return
        
        # CHECKPOINT 9: Send policy! (ใช้ raw_symbol เพื่อ match broker)
        success = self.send_policy(raw_symbol, strategy, score, symbol)
        
        if success:
            self.policy_count += 1
            self.last_policy_time[symbol] = now  # Cooldown by normalized symbol
            
            self.logger.policy_attempt(
                symbol, strategy, score, True,
                f"Policy #{self.policy_count} sent! (raw={raw_symbol})"
            )
        else:
            self.logger.policy_attempt(
                symbol, strategy, score, False,
                "ZMQ send failed"
            )
    
    def send_policy(self, symbol: str, strategy: str, score: float,
                    normalized_symbol: str = None) -> bool:
        """
        Send policy via ZMQ with CORRECT format
        
        symbol: raw symbol with broker suffix (for Trader)
        normalized_symbol: base symbol (for tick history lookup)
        """
        
        try:
            # Use normalized symbol to look up tick history
            lookup_key = normalized_symbol or normalize_symbol(symbol, self.config.SUFFIX_PATTERNS)
            # Send base symbol in policy — Trader's FormatSymbol adds the suffix back.
            # Sending the raw broker symbol (e.g. "EURUSD.tp") caused double-suffix ".tp.tp"
            send_symbol = lookup_key
            
            history = list(self.tick_history[lookup_key])
            if not history:
                return False
            
            last_tick = history[-1]
            current_price = last_tick.get('bid', 0.0)
            
            if current_price == 0:
                return False
            
            # Calculate trading parameters
            lot_size = 0.01 * self.risk_multiplier
            
            # Compute grid_direction from recent price trend for Trader's GridCore
            # [6] must be 1=BUY or 2=SELL — GRID_DIR_NONE(0) blocks all Grid orders
            # Mean-reversion logic: price rising → expect reversion down → SELL(2)
            #                       price falling → expect reversion up  → BUY(1)
            if len(history) >= 5:
                recent_prices = [t.get('bid', 0.0) for t in history[-5:]]
                price_trend = recent_prices[-1] - recent_prices[0]
                grid_direction = 2 if price_trend > 0 else 1  # 1=BUY, 2=SELL
            else:
                grid_direction = 1  # Default BUY

            if strategy == "Grid":
                tp_distance = current_price * 0.002  # 0.2% TP
                sl_distance = current_price * 0.001  # 0.1% SL

                policy_msg = [
                    2,                          # type: POLICY
                    int(time.time() * 1000),   # timestamp (milliseconds)
                    send_symbol,               # base symbol — Trader adds suffix via FormatSymbol
                    strategy,                   # strategy name
                    current_price,              # entry_price
                    lot_size,                   # lot_size
                    grid_direction,             # [6] grid_direction: 1=BUY, 2=SELL
                    current_price + tp_distance,  # tp
                    current_price - sl_distance,  # sl
                    score / 100.0,              # confidence (0.0-1.0)
                    self.risk_multiplier        # risk_multiplier
                ]

            elif strategy == "Spike":
                # Spike direction: same mean-reversion logic (sharp move → expect reversal)
                spike_direction = grid_direction
                tp_distance = current_price * 0.005  # 0.5% TP
                sl_distance = current_price * 0.002  # 0.2% SL

                policy_msg = [
                    2,                          # type: POLICY
                    int(time.time() * 1000),   # timestamp (milliseconds)
                    send_symbol,               # base symbol — Trader adds suffix via FormatSymbol
                    strategy,                   # strategy name
                    current_price,              # entry_price
                    lot_size,                   # lot_size
                    spike_direction,            # [6] grid_direction: 1=BUY, 2=SELL
                    current_price + tp_distance,  # tp
                    current_price - sl_distance,  # sl
                    score / 100.0,              # confidence (0.0-1.0)
                    self.risk_multiplier        # risk_multiplier
                ]
            
            else:
                return False
            
            # Serialize as MessagePack ARRAY (not dict)
            packed = msgpack.packb(policy_msg)
            
            # Send via ZMQ
            self.publisher.send(packed, flags=zmq.NOBLOCK)
            
            print(f"✅ Policy sent: {len(packed)} bytes | {symbol} | {strategy} | "
                  f"Price: {current_price:.2f} | Score: {score:.2f}")
            
            return True
            
        except Exception as e:
            print(f"❌ Policy send error: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    # ====================================================================
    # ADAPTIVE PARAMETER FEEDBACK LOOP (v2.4)
    # ====================================================================

    def _process_feedback(self) -> None:
        """
        Drain feedback_queue (non-blocking) and record each closed trade
        in PerformanceTracker.

        Expected feedback format (12 fields from ProgramC_Trader SendFeedback):
          [100, ts_ms, ticket, symbol, type, volume, open_px,
           sl, tp, profit, magic, comment]
        """
        while True:
            try:
                result = self.feedback_queue.get_nowait()
            except queue.Empty:
                break

            try:
                # Support both list/tuple and dict formats
                if isinstance(result, (list, tuple)) and len(result) >= 11:
                    symbol_raw = str(result[3])
                    profit     = float(result[9])
                    magic      = int(result[10])
                elif isinstance(result, dict):
                    symbol_raw = str(result.get('symbol', ''))
                    profit     = float(result.get('profit', 0))
                    magic      = int(result.get('magic', 0))
                else:
                    continue

                sid = PerformanceTracker.magic_to_strategy_id(magic)
                if sid is None:
                    continue

                sym = normalize_symbol(symbol_raw, self.config.SUFFIX_PATTERNS)

                self.perf_tracker.record_trade(sym, sid, profit, result)

                print(f"[FEEDBACK] {sym} {sid} | profit={profit:.2f} | "
                      f"magic={magic} | WR={self.perf_tracker.get_win_rate(sym, sid):.2f}")

            except Exception as e:
                print(f"[FEEDBACK] Parse error: {e}")

    def _check_adaptive_params(self) -> None:
        """
        Called every 60 seconds from run().
        Iterates over all (symbol, strategy_id) pairs with recorded trades,
        triggers adaptation if conditions are met, and publishes type=14
        MSG_DYNAMIC_PARAMS over ZMQ when parameters change.
        """
        for sym, sid in self.perf_tracker.active_pairs():
            changed, new_params = self.param_manager.update_if_needed(
                sym, sid, self.perf_tracker
            )
            if changed:
                self._send_dynamic_params(sym, sid, new_params)

    def _send_dynamic_params(self, symbol: str, strategy_id: str,
                             params: dict) -> None:
        """
        Publish MSG_DYNAMIC_PARAMS (type=14) to MQL5 Trader via ZMQ PUB.

        Format: [14, timestamp_ms, symbol, strategy_id, {param_key: value, ...}]
        """
        if self.publisher is None:
            return
        try:
            msg = [
                14,                         # MSG_DYNAMIC_PARAMS
                int(time.time() * 1000),    # timestamp_ms
                symbol,
                strategy_id,
                params                      # msgpack map
            ]
            packed = msgpack.packb(msg, use_bin_type=True)
            self.publisher.send(packed, flags=zmq.NOBLOCK)
            print(f"📡 [ADAPT→MT5] {symbol} {strategy_id} params pushed "
                  f"({len(params)} keys, {len(packed)} bytes)")
        except zmq.Again:
            print(f"⚠️  [ADAPT→MT5] ZMQ send blocked (NOBLOCK) for {symbol} {strategy_id}")
        except Exception as e:
            print(f"❌ [ADAPT→MT5] Send error: {e}")

    def run(self):
        """Main loop"""

        # Setup ZMQ
        if not self.setup_zmq():
            print("❌ Cannot start without ZMQ")
            return
        
        print("🚀 Strategy Engine v2.4 (Adaptive Params) running...")
        print(f"   Listening to ingestion_queue")
        print(f"   Publishing to {self.zmq_pub_address}")
        print()
        
        last_dashboard = time.time()

        while not self.shutdown_event.is_set():
            try:
                # Get tick
                tick_data = self.ingestion_queue.get(timeout=0.1)

                # Process it
                self.process_tick(tick_data)

                # Drain feedback queue (non-blocking)
                self._process_feedback()

                # Check adaptive params every 60 seconds
                now = time.time()
                if now - self._last_adapt_check >= 60.0:
                    self._check_adaptive_params()
                    self._last_adapt_check = now

                # Dashboard every 10 seconds
                if now - last_dashboard > 10:
                    self.print_dashboard()
                    last_dashboard = now

            except queue.Empty:
                # Still drain feedback and check adapt on idle ticks
                self._process_feedback()
                now = time.time()
                if now - self._last_adapt_check >= 60.0:
                    self._check_adaptive_params()
                    self._last_adapt_check = now
                continue

            except Exception as e:
                print(f"❌ Engine error: {e}")
                import traceback
                traceback.print_exc()
        
        # Cleanup
        self.logger.summary()
        
        if self.publisher:
            self.publisher.close()
        
        self.context.term()
        
        print("🛑 Strategy Engine stopped")
    
    def print_dashboard(self):
        """แสดง dashboard"""

        print("\n" + "="*70)
        print("📊 STRATEGY ENGINE DASHBOARD v2.4 (Adaptive Params)")
        print("="*70)
        print(f"Ticks Processed:    {self.tick_count}")
        print(f"Policies Sent:      {self.policy_count}")
        print(f"Risk Multiplier:    {self.risk_multiplier:.2f}x")
        print()

        # Symbol mapping
        if self.symbol_map:
            print("Symbol Mapping:")
            for raw, norm in self.symbol_map.items():
                ticks = len(self.tick_history[norm])
                print(f"  {raw:16s} → {norm:10s} ({ticks} ticks)")
            print()

        # Top 5 spike scores
        sorted_scores = sorted(
            self.spike_scores.items(),
            key=lambda x: x[1],
            reverse=True
        )[:5]

        print("Top 5 Symbols (Spike Score):")
        for i, (sym, score) in enumerate(sorted_scores, 1):
            status = "✅ ABOVE THRESHOLD" if score >= self.config.MIN_SPIKE_SCORE else "⏳ Below"
            print(f"  {i}. {sym:12s}: {score:6.2f} {status}")

        # Performance summary (adaptive tuning)
        perf_summary = self.perf_tracker.get_summary()
        if perf_summary:
            print()
            print("Strategy Performance (Adaptive Tuning):")
            print(f"  {'Symbol':<10} {'SID':<5} {'Trades':>6} {'WR':>6} {'PF':>6} {'DD':>6} {'CL':>4}")
            print(f"  {'-'*48}")
            for (sym, sid), stats in sorted(perf_summary.items()):
                print(f"  {sym:<10} {sid:<5} {stats['trades']:>6} "
                      f"{stats['wr']:>6.2f} {stats['pf']:>6.2f} "
                      f"{stats['dd']:>6.2f} {stats['consec_loss']:>4}")

        print("="*70 + "\n")


# ========================================================================
# FACTORY FUNCTION
# ========================================================================

def create_strategy_engine_threaded(
    ingestion_queue: queue.Queue,
    signal_queue: queue.Queue,
    feedback_queue: queue.Queue,
    shutdown_event: threading.Event,
    zmq_pub_address: str
) -> threading.Thread:
    """สร้าง Strategy Engine thread"""
    
    engine = StrategyEngineThreaded(
        ingestion_queue=ingestion_queue,
        signal_queue=signal_queue,
        feedback_queue=feedback_queue,
        shutdown_event=shutdown_event,
        zmq_pub_address=zmq_pub_address
    )
    
    thread = threading.Thread(
        target=engine.run,
        name="StrategyEngine-v2.4"
    )
    
    return thread


if __name__ == "__main__":
    print("This is a module. Import it from main.py")
