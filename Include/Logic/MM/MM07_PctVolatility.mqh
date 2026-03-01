//+------------------------------------------------------------------+
//| MM07_PctVolatility.mqh                                           |
//| FlashEASuite V2 V6 — MM07: Percent Volatility                   |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|   ปรับ Lot ให้ volatility impact ต่อ trade = Target%             |
//|   Volatility = Realized Vol = StdDev of Close returns (lookback) |
//|                                                                  |
//| FORMULA:                                                         |
//|   RealizedVol = StdDev(Close[i] - Close[i-1]) over lookback bars |
//|   Target Vol Amount = Balance × TARGET_VOL_PCT%                  |
//|   Lot = Target Vol Amount / (RealizedVol × value_per_lot(1pip)) |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM07_TARGET_VOL_PCT  default=1.0  (vol-target 1% ต่อ trade)    |
//|   MM07_VOL_LOOKBACK    default=20   (bars สำหรับ realized vol)    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM07_PCT_VOLATILITY_MQH
#define MM07_PCT_VOLATILITY_MQH

#include "IMoneyManager.mqh"

class CMM07_PctVolatility : public IMoneyManager
{
private:
    double  m_target_vol_pct;       // Target vol% per trade (default 1.0)
    int     m_vol_lookback;         // Bars for realized vol (default 20)
    string  m_tf_symbol;            // Symbol for vol calculation

public:
    CMM07_PctVolatility()
    {
        m_target_vol_pct = 1.0;
        m_vol_lookback   = 20;
        m_tf_symbol      = "";
    }

    void SetParams(double target_vol_pct, int vol_lookback)
    {
        m_target_vol_pct = MathMax(0.1, MathMin(5.0,  target_vol_pct));
        m_vol_lookback   = MathMax(5,   MathMin(200,  vol_lookback));
    }

    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);

        // --- Calculate Realized Volatility ---
        double realized_vol = _CalcRealizedVol(symbol);
        if(realized_vol <= 0.0)
        {
            // Fallback: use stopLoss as vol proxy
            if(stopLoss > 0.0)
                realized_vol = stopLoss;
            else
                return MMNormalizeLot(symbol, m_base_lot);
        }

        // --- Target vol amount in account currency ---
        double target_risk = balance * ((m_target_vol_pct * m_risk_multiplier) / 100.0);

        // --- Lot sizing: target_risk / value_per_lot_at_vol ---
        double lot = MMCalcLotFromRisk(symbol, target_risk, realized_vol);

        // Safety: cap at 5% equity
        double max_lot = MMCalcLotFromRisk(symbol, equity * 0.05, realized_vol);
        lot = MathMin(lot, max_lot);

        m_state.last_lot = lot;
        return MMNormalizeLot(symbol, lot);
    }

    virtual string GetName() override { return "MM07_PctVolatility"; }
    virtual int    GetID()   override { return (int)MM_ID_PCT_VOLATILITY; }

    virtual string GetDiagnostic() override
    {
        double vol = _CalcRealizedVol(m_symbol);
        return StringFormat(
            "[MM07] TargetVol:%.1f%% RealizedVol:%.5f Lookback:%d",
            m_target_vol_pct, vol, m_vol_lookback);
    }

private:
    //+------------------------------------------------------------------+
    //| Calculate realized volatility as StdDev of price changes        |
    //| Returns vol in price units (same as stopLoss parameter)         |
    //+------------------------------------------------------------------+
    double _CalcRealizedVol(string symbol)
    {
        int bars_needed = m_vol_lookback + 1;
        if(Bars(symbol, PERIOD_CURRENT) < bars_needed) return 0.0;

        double closes[];
        ArraySetAsSeries(closes, true);
        if(CopyClose(symbol, PERIOD_CURRENT, 0, bars_needed, closes) < bars_needed)
            return 0.0;

        // Calculate returns
        double returns[];
        ArrayResize(returns, m_vol_lookback);
        for(int i = 0; i < m_vol_lookback; i++)
            returns[i] = MathAbs(closes[i] - closes[i + 1]);

        // StdDev of returns (use mean absolute deviation as vol proxy)
        double sum = 0.0, sum_sq = 0.0;
        for(int i = 0; i < m_vol_lookback; i++)
        {
            sum    += returns[i];
            sum_sq += returns[i] * returns[i];
        }
        double mean   = sum / m_vol_lookback;
        double var    = (sum_sq / m_vol_lookback) - (mean * mean);
        double stddev = (var > 0.0) ? MathSqrt(var) : mean;

        return stddev;
    }
};

#endif // MM07_PCT_VOLATILITY_MQH
