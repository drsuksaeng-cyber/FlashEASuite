"""S04 Market Profile — POC/VAH/VAL mean reversion."""
import numpy as np
import pandas as pd
from strategies.base import BaseStrategy
from strategies import indicators as ind

class S04MarketProfile(BaseStrategy):
    name = "S04_MarketProfile"
    max_positions = 1
    param_space = {
        "lookback": ("int", 48, 200), "va_pct": ("float", 0.60, 0.80),
        "vol_mult": ("float", 1.0, 2.0), "sl_atr_mult": ("float", 1.0, 2.5),
        "atr_period": ("int", 10, 20),
    }
    def default_params(self): return {"lookback":96,"va_pct":0.70,"vol_mult":1.2,"sl_atr_mult":1.5,"atr_period":14,"bins":50}
    def compute_signals(self, df, params):
        p = {**self.default_params(), **params}
        close=df["close"].values; high=df["high"].values; low=df["low"].values; vol=df["tick_volume"].values.astype(float)
        atr_s = ind.atr(df["high"], df["low"], df["close"], p["atr_period"]); atr_arr=atr_s.values
        vol_ma = pd.Series(vol).rolling(20).mean().values
        n=len(df); signal=np.zeros(n,dtype=int); sl_dist=np.zeros(n); tp_dist=np.zeros(n); confidence=np.zeros(n)
        lb = p["lookback"]
        for i in range(lb, n):
            a=atr_arr[i]
            if np.isnan(a) or a<1e-10: continue
            # Build simple volume profile
            seg_close = close[i-lb:i]; seg_vol = vol[i-lb:i]
            price_min=seg_close.min(); price_max=seg_close.max()
            if price_max-price_min < a*0.5: continue
            bins = np.linspace(price_min, price_max, p["bins"]+1)
            hist = np.zeros(p["bins"])
            for j in range(lb):
                idx = min(int((seg_close[j]-price_min)/(price_max-price_min)*p["bins"]), p["bins"]-1)
                hist[idx] += seg_vol[j]
            poc_idx = np.argmax(hist); poc = (bins[poc_idx]+bins[poc_idx+1])/2
            # Value area
            total_vol = hist.sum()
            if total_vol < 1: continue
            sorted_idx = np.argsort(hist)[::-1]; cum=0; va_bins=set()
            for si in sorted_idx:
                cum += hist[si]; va_bins.add(si)
                if cum >= total_vol * p["va_pct"]: break
            val_price = bins[min(va_bins)]; vah_price = bins[max(va_bins)+1]
            price = close[i]; vr = vol[i]/vol_ma[i] if vol_ma[i]>0 else 0
            sig = 0
            if price < val_price and vr >= p["vol_mult"] and abs(price-val_price) < 2*a:
                sig = 1
            elif price > vah_price and vr >= p["vol_mult"] and abs(price-vah_price) < 2*a:
                sig = -1
            if sig != 0:
                poc_prox = 1.0 - min(abs(price-poc)/(vah_price-val_price+1e-10), 1.0)
                conf = min(vr/3.0, 1.0) * (0.4 + 0.4*poc_prox)
                tp_d = abs(poc-price) if abs(poc-price) > a*0.5 else a*1.5
                signal[i]=sig; sl_dist[i]=p["sl_atr_mult"]*a; tp_dist[i]=tp_d; confidence[i]=min(conf,1.0)
        return pd.DataFrame({"signal":signal,"sl_dist":sl_dist,"tp_dist":tp_dist,"confidence":confidence},index=df.index)
