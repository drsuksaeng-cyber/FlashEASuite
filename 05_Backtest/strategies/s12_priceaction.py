"""S12 Price Action — Pin Bar + Engulfing at key levels."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S12PriceAction(BaseStrategy):
    name = "S12_PriceAction"
    max_positions = 1
    param_space = {
        "body_max_ratio": ("float", 0.2, 0.4), "wick_min_ratio": ("float", 0.5, 0.75),
        "tp_mult": ("float", 1.5, 3.5), "swing_bars": ("int", 3, 8),
        "lookback": ("int", 50, 150), "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"body_max_ratio":0.30,"wick_min_ratio":0.60,"tp_mult":2.0,"swing_bars":5,"lookback":100,"atr_period":14}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        opn=df["open"].values; close=df["close"].values; high=df["high"].values; low=df["low"].values
        vol=df["tick_volume"].values.astype(float)
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        vol_ma = pd.Series(vol).rolling(20).mean().values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        sb = p["swing_bars"]
        for i in range(p["lookback"], n):
            a=atr_arr[i]
            if np.isnan(a) or a<1e-10: continue
            # Use bar[i-1] (completed bar)
            j = i-1
            rng = high[j]-low[j]
            if rng < a * 0.1: continue
            body = abs(close[j]-opn[j]); body_ratio = body/rng
            upper_wick = high[j]-max(close[j],opn[j]); lower_wick = min(close[j],opn[j])-low[j]
            vr = vol[j]/vol_ma[j] if vol_ma[j]>0 else 1.0
            # Key levels (simple: swing highs/lows)
            seg_h = high[max(0,i-p["lookback"]):i]; seg_l = low[max(0,i-p["lookback"]):i]
            recent_highs = []; recent_lows = []
            for k in range(sb, len(seg_h)-sb):
                if seg_h[k] == max(seg_h[max(0,k-sb):k+sb+1]): recent_highs.append(seg_h[k])
                if seg_l[k] == min(seg_l[max(0,k-sb):k+sb+1]): recent_lows.append(seg_l[k])
            # Check proximity to key level
            price = close[j]; proximity = 0.0
            for lvl in recent_highs + recent_lows:
                dist = abs(price - lvl)
                if dist < a * 1.5: proximity = max(proximity, 1.0 - dist/(a*1.5))
            if proximity < 0.3: continue
            sig = 0
            # Pin bar
            if body_ratio <= p["body_max_ratio"]:
                if lower_wick/rng >= p["wick_min_ratio"]: sig = 1  # bullish pin
                elif upper_wick/rng >= p["wick_min_ratio"]: sig = -1  # bearish pin
                if sig != 0:
                    wick_r = (lower_wick if sig==1 else upper_wick)/rng
                    conf = wick_r * min(vr, 1.5) * proximity
            # Engulfing
            if sig == 0 and i >= 2:
                if close[j]>opn[j] and opn[j]<close[j-1] and close[j]>opn[j-1]:  # bullish engulf
                    sig = 1; size_r = body/(abs(close[j-1]-opn[j-1])+1e-10)
                    conf = min(size_r, 1.5)*0.4 * proximity * min(vr, 1.5)
                elif close[j]<opn[j] and opn[j]>close[j-1] and close[j]<opn[j-1]:  # bearish engulf
                    sig = -1; size_r = body/(abs(close[j-1]-opn[j-1])+1e-10)
                    conf = min(size_r, 1.5)*0.4 * proximity * min(vr, 1.5)
            if sig != 0:
                signal[i]=sig; sl_dist[i]=rng+a*0.1; tp_dist[i]=rng*p["tp_mult"]; confidence[i]=min(conf,1.0)
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
