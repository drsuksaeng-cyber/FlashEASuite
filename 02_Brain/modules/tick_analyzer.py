"""
FlashEASuite V2 - Module
Tick & Spread Analyzer (Ratio Logic + Adaptive Spread) 🧠
"""
from collections import deque
import time
import numpy as np

class TickFlowAnalyzer:
    def __init__(self, window_short_sec=1.0, window_long_sec=900.0): # 900s = 15 min
        self.window_short = window_short_sec
        self.window_long = window_long_sec
        
        # 1. ถังเก็บ Timestamp (สำหรับ Tick Density)
        self.ticks_short = deque()
        self.ticks_long = deque()
        
        # 2. ถังเก็บ Spread (สำหรับ Adaptive Spread)
        # เก็บเป็นคู่ (timestamp, spread_value)
        self.spread_history = deque()
        
        # ค่าสถิติล่าสุด
        self.current_tick_ratio = 0.0
        self.current_spread_avg = 0.0
        self.current_spread_ratio = 0.0

    def on_tick(self, bid, ask):
        """เรียกทุกครั้งที่มี Tick ใหม่เข้ามา (พร้อมราคา Bid/Ask)"""
        now = time.time()
        current_spread = (ask - bid)
        
        # --- PART A: Tick Density ---
        self.ticks_short.append(now)
        self.ticks_long.append(now)
        
        # --- PART B: Spread Analysis ---
        self.spread_history.append((now, current_spread))
        
        # --- Pruning (ลบข้อมูลเก่า) ---
        self._prune_old_data(now)
        
        # --- Calculation ---
        self._calculate_metrics(now, current_spread)
        
        return {
            "tick_ratio": self.current_tick_ratio,
            "spread_ratio": self.current_spread_ratio,
            "avg_spread": self.current_spread_avg
        }

    def _prune_old_data(self, now):
        # ลบ Tick เก่า
        while self.ticks_short and (now - self.ticks_short[0] > self.window_short):
            self.ticks_short.popleft()
        while self.ticks_long and (now - self.ticks_long[0] > self.window_long):
            self.ticks_long.popleft()
            
        # ลบ Spread เก่า (ใช้ Window Long 15 นาทีเหมือนกัน)
        while self.spread_history and (now - self.spread_history[0][0] > self.window_long):
            self.spread_history.popleft()

    def _calculate_metrics(self, now, current_spread):
        # 1. Tick Ratio (1s vs 15m Avg)
        short_count = len(self.ticks_short)
        
        elapsed = min(now - self.ticks_long[0], self.window_long) if self.ticks_long else 1.0
        if elapsed < 1.0: elapsed = 1.0
        long_avg_per_sec = len(self.ticks_long) / elapsed
        
        if long_avg_per_sec > 0:
            self.current_tick_ratio = short_count / long_avg_per_sec
        else:
            self.current_tick_ratio = 0.0
            
        # 2. Spread Ratio (Current vs 15m Avg)
        if len(self.spread_history) > 0:
            # คำนวณค่าเฉลี่ย Spread จากประวัติ
            total_spread = sum(item[1] for item in self.spread_history)
            self.current_spread_avg = total_spread / len(self.spread_history)
            
            if self.current_spread_avg > 0:
                self.current_spread_ratio = current_spread / self.current_spread_avg
            else:
                self.current_spread_ratio = 1.0
        else:
            self.current_spread_avg = current_spread
            self.current_spread_ratio = 1.0

    def get_status(self):
        return {
            "tick_ratio": round(self.current_tick_ratio, 2),
            "spread_avg": f"{self.current_spread_avg:.5f}",
            "spread_ratio": round(self.current_spread_ratio, 2)
        }