"""S09 Session Breakout — Asian range -> London/NY breakout."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S09SessionBreakout(BaseStrategy):
    name = "S09_SessionBreakout"
    max_positions = 1
    param_space = {
        "range_min_pips": ("float", 10.0, 40.0), "breakout_buf_pips": ("float", 1.0, 10.0),
        "sl_inside_ratio": ("float", 0.3, 0.7), "tp_range_mult": ("float", 1.0, 3.0),
        "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"range_min_pips":20,"breakout_buf_pips":3.0,"sl_inside_ratio":0.5,"tp_range_mult":1.5,"atr_period":14,"broker_gmt_offset":3}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"].values; high=df["high"].values; low=df["low"].values
        times = pd.to_datetime(df["time"])
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        offset = p["broker_gmt_offset"]
        # Session hours (GMT): Asian 0-8, London 8-12, NY 13-17
        asian_start=0+offset; asian_end=8+offset; london_start=8+offset; ny_end=17+offset
        daily_high=0; daily_low=999999; daily_traded=False; day_prev=-1
        for i in range(max(p["atr_period"]+5, 50), n):
            a=atr_arr[i]
            if np.isnan(a) or a<1e-10: continue
            t = times.iloc[i]; hour = t.hour; day = t.dayofyear
            if day != day_prev:
                daily_high=0; daily_low=999999; daily_traded=False; day_prev=day
            # Asian session: build range
            if asian_start <= hour < asian_end:
                daily_high = max(daily_high, high[i]); daily_low = min(daily_low, low[i])
                continue
            rng = daily_high - daily_low
            if rng < p["range_min_pips"] * a * 0.01: continue
            if daily_traded: continue
            if hour >= ny_end: continue
            # Breakout
            buf = max(p["breakout_buf_pips"] * a * 0.01, a * 0.1)
            price = close[i]
            sig = 0
            if price > daily_high + buf: sig = 1
            elif price < daily_low - buf: sig = -1
            if sig != 0:
                daily_traded = True
                rng_atr = rng / a if a > 0 else 0
                sess_factor = 1.0 if london_start <= hour < london_start+4 else 0.75
                conf = min((rng_atr/2.0) * sess_factor, 1.0)
                signal[i]=sig; sl_dist[i]=rng*p["sl_inside_ratio"]; tp_dist[i]=rng*p["tp_range_mult"]; confidence[i]=conf
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
