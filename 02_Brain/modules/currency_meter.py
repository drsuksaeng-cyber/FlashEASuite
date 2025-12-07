import time
import math
from collections import deque
import numpy as np

class CurrencyStrengthMeter:
    def __init__(self):
        self.currencies = ['USD', 'EUR', 'JPY', 'GBP', 'AUD', 'CAD', 'CHF', 'NZD']
        self.history = {} 
        
        # เก็บ Score แยก 2 ถัง: Fast (ซิ่ง) และ Slow (เทรนด์)
        self.scores_fast = {c: 5.0 for c in self.currencies}
        self.scores_slow = {c: 5.0 for c in self.currencies}

        # Config
        self.FAST_WINDOW = 5      # 5 วินาที (สำหรับ Spike)
        self.SLOW_WINDOW = 1800   # 1800 วินาที = 30 นาที (สำหรับ Trend)
        
        self.SLOPE_FAST = 50.0    # ไวเวอร์ (Spike)
        self.SLOPE_SLOW = 2.0     # นิ่งๆ (Trend)

    def update_tick(self, symbol, price, timestamp_ms):
        current_time = timestamp_ms / 1000.0
        if symbol not in self.history:
            self.history[symbol] = deque(maxlen=5000) # เพิ่ม Buffer เผื่อเก็บยาวๆ
            
        self.history[symbol].append((current_time, price))
        
        # Clean up: ลบข้อมูลที่เก่าเกิน Slow Window ออกเพื่อประหยัด Ram
        while self.history[symbol][0][0] < current_time - self.SLOW_WINDOW - 10:
             self.history[symbol].popleft()

    def calculate_strengths(self):
        """ คำนวณทีเดียวได้ 2 แบบเลย """
        self._calc_logic(self.FAST_WINDOW, self.SLOPE_FAST, self.scores_fast)
        self._calc_logic(self.SLOW_WINDOW, self.SLOPE_SLOW, self.scores_slow)

    def _calc_logic(self, window_sec, slope, score_dict):
        raw_forces = {c: 0.0 for c in self.currencies}
        current_time = time.time()
        
        for symbol, history_deque in self.history.items():
            if len(history_deque) < 2: continue
            
            current_price = history_deque[-1][1]
            latest_ts = history_deque[-1][0]
            target_ts = latest_ts - window_sec
            
            # Find past price
            past_price = current_price
            for i in range(len(history_deque)-1, -1, -1):
                if history_deque[i][0] <= target_ts:
                    past_price = history_deque[i][1]
                    break
            
            if past_price == 0: continue
            
            velocity = (current_price - past_price) / past_price * 100.0
            
            base = symbol[:3]
            quote = symbol[3:]
            if base in raw_forces and quote in raw_forces:
                raw_forces[base] += velocity
                raw_forces[quote] -= velocity

        # Normalize
        for c in self.currencies:
            force = raw_forces[c]
            sigmoid_val = 1.0 / (1.0 + math.exp(-force * slope))
            score_dict[c] = sigmoid_val * 10.0

    def get_dashboard_string(self):
        # โชว์ค่า Fast เทียบ Slow ให้เห็นชัดๆ
        # Format: USD[F:9.2|S:7.5]
        items = []
        # เรียงลำดับตามความแรงของ Fast
        sorted_keys = sorted(self.scores_fast, key=self.scores_fast.get, reverse=True)
        
        for c in sorted_keys:
            f_val = self.scores_fast[c]
            s_val = self.scores_slow[c]
            items.append(f"{c}[F:{f_val:.1f}|S:{s_val:.1f}]")
            
        return " | ".join(items)