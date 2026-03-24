"""S03 Smart Money Concepts — Order Block + FVG + BOS."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S03SMC(BaseStrategy):
    name = "S03_SMC"
    max_positions = 1
    param_space = {
        "lookback": ("int", 30, 80), "swing_bars": ("int", 3, 8),
        "min_ob_vol": ("float", 1.0, 2.5), "min_fvg_size": ("float", 0.3, 1.0),
        "sl_atr_buffer": ("float", 0.1, 0.5), "tp_atr_mult": ("float", 1.5, 3.5),
        "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"lookback":50,"swing_bars":5,"min_ob_vol":1.5,"min_fvg_size":0.5,"sl_atr_buffer":0.3,"tp_atr_mult":2.0,"atr_period":14}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"].values; high=df["high"].values; low=df["low"].values; vol=df["tick_volume"].values.astype(float)
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        vol_ma = pd.Series(vol).rolling(20).mean().values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        sb = p["swing_bars"]
        for i in range(p["lookback"], n):
            a=atr_arr[i]
            if np.isnan(a) or a<1e-10: continue
            # Simplified OB: strong candle with high volume
            body = abs(close[i-1]-close[i-2] if i>=2 else 0)
            vr = vol[i-1]/vol_ma[i-1] if vol_ma[i-1]>0 else 0
            if vr < p["min_ob_vol"] or body < a*0.3: continue
            # FVG: gap between bar[i-2] and bar[i]
            fvg_bull = low[i] > high[i-2] if i>=2 else False
            fvg_bear = high[i] < low[i-2] if i>=2 else False
            fvg_size = (low[i]-high[i-2])/a if fvg_bull else ((low[i-2]-high[i])/a if fvg_bear else 0)
            # BOS: higher high / lower low
            recent_high = max(high[max(0,i-sb):i]); recent_low = min(low[max(0,i-sb):i])
            bos_bull = close[i] > recent_high; bos_bear = close[i] < recent_low
            sig = 0
            if close[i-1]>close[i-2] and vr>=p["min_ob_vol"] and (fvg_bull or bos_bull):
                sig = 1
            elif close[i-1]<close[i-2] and vr>=p["min_ob_vol"] and (fvg_bear or bos_bear):
                sig = -1
            if sig != 0:
                ob_str = min(vr/2.0, 1.0); fvg_s = min(abs(fvg_size)/3.0, 0.3); bos_s = 0.2 if (bos_bull if sig==1 else bos_bear) else 0
                conf = ob_str*0.5 + fvg_s + bos_s
                signal[i]=sig; sl_dist[i]=(p["sl_atr_buffer"]+1.0)*a; tp_dist[i]=p["tp_atr_mult"]*a; confidence[i]=min(conf,1.0)
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
