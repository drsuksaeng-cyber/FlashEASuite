"""S02 ML Ensemble — ServerOnly thin wrapper. For backtesting: uses momentum+vol as proxy."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S02MLEnsemble(BaseStrategy):
    name = "S02_MLEnsemble"
    max_positions = 1
    param_space = {
        "rsi_period": ("int", 10, 20), "mom_period": ("int", 5, 20),
        "conf_threshold": ("float", 0.5, 0.9), "atr_period": ("int", 10, 20),
        "sl_atr_mult": ("float", 1.0, 3.0), "tp_atr_mult": ("float", 1.0, 4.0),
    }
    def default_params(self): return {"rsi_period":14,"mom_period":10,"conf_threshold":0.70,"atr_period":14,"sl_atr_mult":1.5,"tp_atr_mult":2.0}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close = df["close"]; high = df["high"]; low = df["low"]
        atr_s = ind.atr(high, low, close, p["atr_period"])
        # Proxy: RSI momentum + trend direction
        delta = close.diff(p["mom_period"])
        rsi_raw = close.diff().rolling(p["rsi_period"]).apply(lambda x: (x[x>0].sum()) / (x.abs().sum()+1e-10))
        n = len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        warmup = max(p["rsi_period"], p["mom_period"], p["atr_period"]) + 5
        for i in range(warmup, n):
            a = atr_s.iloc[i]; r = rsi_raw.iloc[i]; d = delta.iloc[i]
            if np.isnan(a) or a<1e-10 or np.isnan(r): continue
            conf = abs(r - 0.5) * 2.0
            if conf < p["conf_threshold"]: continue
            sig = 1 if d > 0 and r > 0.6 else (-1 if d < 0 and r < 0.4 else 0)
            if sig != 0:
                signal[i]=sig; sl_dist[i]=p["sl_atr_mult"]*a; tp_dist[i]=p["tp_atr_mult"]*a; confidence[i]=min(conf,1.0)
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
