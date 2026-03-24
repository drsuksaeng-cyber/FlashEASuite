"""S11 Ichimoku Multi-TF — Tenkan/Kijun cross with cloud filter."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S11Ichimoku(BaseStrategy):
    name = "S11_Ichimoku"
    max_positions = 1
    param_space = {
        "tenkan": ("int", 7, 12), "kijun": ("int", 20, 35), "senkou_b": ("int", 40, 60),
        "cloud_min_atr": ("float", 0.3, 1.5), "atr_period": ("int", 10, 20),
        "sl_atr_mult": ("float", 1.0, 3.0), "tp_atr_mult": ("float", 1.5, 4.0),
    }
    def default_params(self): return {"tenkan":9,"kijun":26,"senkou_b":52,"cloud_min_atr":0.5,"atr_period":14,"sl_atr_mult":2.0,"tp_atr_mult":3.0}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"]; high=df["high"]; low=df["low"]
        atr_s = ind.atr(high, low, close, p["atr_period"])
        # Ichimoku components
        tenkan = (high.rolling(p["tenkan"]).max() + low.rolling(p["tenkan"]).min()) / 2
        kijun = (high.rolling(p["kijun"]).max() + low.rolling(p["kijun"]).min()) / 2
        senkou_a = ((tenkan + kijun) / 2).shift(p["kijun"])
        senkou_b = ((high.rolling(p["senkou_b"]).max() + low.rolling(p["senkou_b"]).min()) / 2).shift(p["kijun"])
        cloud_top = pd.concat([senkou_a, senkou_b], axis=1).max(axis=1)
        cloud_bot = pd.concat([senkou_a, senkou_b], axis=1).min(axis=1)
        cloud_width = cloud_top - cloud_bot
        # TK cross
        tk_cross_bull = (tenkan > kijun) & (tenkan.shift(1) <= kijun.shift(1))
        tk_cross_bear = (tenkan < kijun) & (tenkan.shift(1) >= kijun.shift(1))
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        warmup = p["senkou_b"] + p["kijun"] + 5
        for i in range(warmup, n):
            a=atr_s.iloc[i]
            if np.isnan(a) or a<1e-10: continue
            cw=cloud_width.iloc[i]; ct=cloud_top.iloc[i]; cb=cloud_bot.iloc[i]; price=close.iloc[i]
            if np.isnan(cw) or np.isnan(ct): continue
            if cw < p["cloud_min_atr"] * a: continue
            sig = 0
            if tk_cross_bull.iloc[i] and price > ct:
                sig = 1
            elif tk_cross_bear.iloc[i] and price < cb:
                sig = -1
            if sig != 0:
                tk_dist = abs(tenkan.iloc[i]-kijun.iloc[i])/a if a>0 else 0
                conf = min(0.6 + min(cw/(a*2), 0.2) + min(tk_dist, 0.2), 1.0)
                signal[i]=sig; sl_dist[i]=p["sl_atr_mult"]*a; tp_dist[i]=p["tp_atr_mult"]*a; confidence[i]=conf
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
