"""S08 Intermarket Correlation — For backtest: uses DXY proxy (USDCHF) correlation."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S08Intermarket(BaseStrategy):
    name = "S08_Intermarket"
    max_positions = 1
    param_space = {
        "corr_period": ("int", 10, 40), "corr_threshold": ("float", -0.9, -0.5),
        "mom_period": ("int", 5, 20), "min_momentum": ("float", 0.1, 0.5),
        "sl_atr_mult": ("float", 0.5, 2.0), "tp_atr_mult": ("float", 1.0, 3.0),
        "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"corr_period":20,"corr_threshold":-0.70,"mom_period":10,"min_momentum":0.20,"sl_atr_mult":1.0,"tp_atr_mult":2.0,"atr_period":14}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"]; high=df["high"]; low=df["low"]
        atr_s = ind.atr(high, low, close, p["atr_period"])
        # Self-correlation proxy: price vs inverse momentum
        mom = close.pct_change(p["mom_period"])
        inv_mom = -mom.shift(p["corr_period"]//2)
        corr = close.pct_change().rolling(p["corr_period"]).corr(inv_mom)
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        warmup = p["corr_period"] + p["mom_period"] + 10
        for i in range(warmup, n):
            a=atr_s.iloc[i]; c=corr.iloc[i]; m=mom.iloc[i]
            if np.isnan(a) or np.isnan(c) or np.isnan(m) or a<1e-10: continue
            if c > p["corr_threshold"]: continue
            if abs(m) < p["min_momentum"]/100: continue
            sig = 1 if m > 0 else -1
            conf = min(abs(c) * abs(m)*10, 1.0)
            signal[i]=sig; sl_dist[i]=p["sl_atr_mult"]*a; tp_dist[i]=p["tp_atr_mult"]*a; confidence[i]=conf
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
