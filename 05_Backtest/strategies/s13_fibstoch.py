"""S13 Fibonacci + Stochastic Reversal."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

def _stochastic(high, low, close, k_period=14, d_period=3, slowing=3):
    lowest = low.rolling(k_period).min(); highest = high.rolling(k_period).max()
    raw_k = 100.0 * (close - lowest) / (highest - lowest).replace(0, 1e-10)
    k = raw_k.rolling(slowing).mean(); d = k.rolling(d_period).mean()
    return k, d

class S13FibStoch(BaseStrategy):
    name = "S13_FibStoch"
    max_positions = 1
    param_space = {
        "fib_lookback": ("int", 50, 150), "stoch_k": ("int", 10, 20),
        "stoch_ob": ("float", 70.0, 90.0), "stoch_os": ("float", 10.0, 30.0),
        "swing_min": ("int", 3, 8), "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"fib_lookback":100,"stoch_k":14,"stoch_d":3,"stoch_slow":3,"stoch_ob":80,"stoch_os":20,"swing_min":5,"atr_period":14}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"].values; high=df["high"].values; low=df["low"].values
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        stoch_k, _ = _stochastic(df["high"], df["low"], df["close"], p["stoch_k"], p.get("stoch_d",3), p.get("stoch_slow",3))
        sk_arr = stoch_k.values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        lb = p["fib_lookback"]; sm = p["swing_min"]
        for i in range(lb, n):
            a=atr_arr[i]; sk=sk_arr[i]
            if np.isnan(a) or a<1e-10 or np.isnan(sk): continue
            seg_h = high[i-lb:i]; seg_l = low[i-lb:i]
            swing_high = seg_h.max(); swing_low = seg_l.min()
            fib_range = swing_high - swing_low
            if fib_range < a * 0.5: continue
            price = close[i]
            # Fib levels
            fib_382 = swing_low + fib_range * 0.382
            fib_618 = swing_low + fib_range * 0.618
            fib_786 = swing_low + fib_range * 0.786
            # Determine trend: if swing_high is more recent -> uptrend pullback
            hi_idx = np.argmax(seg_h); lo_idx = np.argmin(seg_l)
            sig = 0
            if hi_idx > lo_idx:  # uptrend: buy on pullback into fib zone
                if fib_382 <= price <= fib_618 and sk < p["stoch_os"]:
                    sig = 1
                    fib_acc = 1.0 - min(abs(price-fib_618)/(fib_618-fib_382+1e-10), 1.0)
                    stoch_ext = 1.0 - sk/p["stoch_os"]
            elif lo_idx > hi_idx:  # downtrend: sell on pullback
                inv_382 = swing_high - fib_range * 0.382
                inv_618 = swing_high - fib_range * 0.618
                if inv_618 <= price <= inv_382 and sk > p["stoch_ob"]:
                    sig = -1
                    fib_acc = 1.0 - min(abs(price-inv_618)/(inv_382-inv_618+1e-10), 1.0)
                    stoch_ext = (sk-p["stoch_ob"])/(100-p["stoch_ob"])
            if sig != 0:
                conf = min(fib_acc * stoch_ext, 1.0)
                sl_d = abs(price - fib_786) if sig==1 else abs(fib_786 - price)
                tp_d = abs(swing_high - price) if sig==1 else abs(price - swing_low)
                if sl_d < a*0.3: sl_d = a*0.5
                if tp_d < a*0.5: tp_d = a*1.0
                signal[i]=sig; sl_dist[i]=sl_d; tp_dist[i]=tp_d; confidence[i]=conf
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
