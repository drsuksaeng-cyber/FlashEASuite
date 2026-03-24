"""S05 Supply & Demand Zones."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S05SupplyDemand(BaseStrategy):
    name = "S05_SupplyDemand"
    max_positions = 1
    param_space = {
        "lookback": ("int", 50, 150), "max_touches": ("int", 2, 5),
        "base_range_mult": ("float", 0.3, 1.0), "sl_atr_buffer": ("float", 0.3, 1.0),
        "tp_atr_mult": ("float", 1.5, 4.0), "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"lookback":100,"max_touches":3,"base_range_mult":0.6,"sl_atr_buffer":0.5,"tp_atr_mult":2.5,"atr_period":14}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"].values; high=df["high"].values; low=df["low"].values
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        zones = []  # (type, top, bottom, touches, bar_idx)
        for i in range(p["lookback"], n):
            a=atr_arr[i]
            if np.isnan(a) or a<1e-10: continue
            # Detect new zones: strong move away from consolidation
            body = abs(close[i]-close[i-1]); rng = high[i]-low[i]
            if body > a * p["base_range_mult"] and rng > a * 0.5:
                if close[i] > close[i-1]:  # demand zone below
                    zones.append(("demand", low[i-1]+body*0.3, low[i-1], 0, i))
                else:  # supply zone above
                    zones.append(("supply", high[i-1], high[i-1]-body*0.3, 0, i))
            # Check price in zones
            price = close[i]; sig = 0; best_conf = 0
            active_zones = []
            for z in zones:
                ztype, ztop, zbot, touches, zbar = z
                if touches >= p["max_touches"]: continue
                if i - zbar > p["lookback"]*2: continue
                # Update touch count
                if zbot <= price <= ztop:
                    z_touches = touches + 1
                    freshness = max(0.1, 1.0 - z_touches * 0.25)
                    width_ratio = min(1.0, (ztop-zbot)/(a*1.5))
                    zone_str = min(1.0, body/a) if i==zbar else 0.5
                    conf = freshness*0.4 + width_ratio*0.3 + zone_str*0.3
                    if conf > best_conf:
                        best_conf = conf
                        if ztype == "demand": sig = 1; sl_d = abs(price-zbot) + p["sl_atr_buffer"]*a
                        else: sig = -1; sl_d = abs(ztop-price) + p["sl_atr_buffer"]*a
                    active_zones.append((ztype, ztop, zbot, z_touches, zbar))
                else:
                    active_zones.append(z)
            zones = active_zones[-50:]  # keep recent
            if sig != 0 and best_conf > 0.3:
                signal[i]=sig; sl_dist[i]=max(sl_d, a*0.5); tp_dist[i]=p["tp_atr_mult"]*a; confidence[i]=min(best_conf,1.0)
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
