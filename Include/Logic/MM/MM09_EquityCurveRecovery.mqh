//+------------------------------------------------------------------+
//| MM09_EquityCurveRecovery.mqh                                     |
//| FlashEASuite V2 V6 — MM09: Equity Curve Recovery                |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|   ติดตาม equity curve (rolling history) เทียบกับ MA               |
//|   ถ้า equity ต่ำกว่า MA → ลด lot size ลง X%                      |
//|   ถ้า equity สูงกว่า MA → trade ด้วย size ปกติ                   |
//|                                                                  |
//| FORMULA:                                                         |
//|   EquityMA = SMA หรือ EMA ของ equity ย้อนหลัง N trades            |
//|   if equity < EquityMA:                                          |
//|     Lot = BaseLot × (1 - BELOW_MA_REDUCE_PCT/100)               |
//|   else:                                                          |
//|     Lot = BaseLot (1% risk)                                      |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM09_EC_MA_PERIOD        default=20  (จำนวน trades สำหรับ MA)   |
//|   MM09_BELOW_MA_REDUCE_PCT default=50  (ลด% เมื่อ equity < MA)    |
//|   MM09_MA_TYPE             default=0   (0=SMA, 1=EMA)             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM09_EQUITY_CURVE_RECOVERY_MQH
#define MM09_EQUITY_CURVE_RECOVERY_MQH

#include "IMoneyManager.mqh"

class CMM09_EquityCurveRecovery : public IMoneyManager
{
private:
    int     m_ma_period;            // MA period in trades (default 20)
    double  m_below_ma_reduce_pct;  // Reduce % when below MA (default 50)
    int     m_ma_type;              // 0=SMA, 1=EMA (default 0)
    double  m_base_risk_pct;        // Base risk% (default 1.0)

    // Equity history buffer (circular)
    double  m_equity_history[];     // Rolling equity snapshots
    int     m_history_idx;          // Current write index
    int     m_history_count;        // Items written so far

public:
    CMM09_EquityCurveRecovery()
    {
        m_ma_period           = 20;
        m_below_ma_reduce_pct = 50.0;
        m_ma_type             = 0;
        m_base_risk_pct       = 1.0;
        m_history_idx         = 0;
        m_history_count       = 0;
    }

    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        ArrayResize(m_equity_history, m_ma_period);
        ArrayInitialize(m_equity_history, 0.0);
    }

    void SetParams(int ma_period, double below_ma_reduce_pct, int ma_type,
                   double base_risk_pct = 1.0)
    {
        m_ma_period           = MathMax(5,   MathMin(200, ma_period));
        m_below_ma_reduce_pct = MathMax(0.0, MathMin(100.0, below_ma_reduce_pct));
        m_ma_type             = (ma_type == 1) ? 1 : 0;
        m_base_risk_pct       = MathMax(0.1, MathMin(5.0,  base_risk_pct));
        ArrayResize(m_equity_history, m_ma_period);
        ArrayInitialize(m_equity_history, 0.0);
    }

    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);

        // Record current equity
        _RecordEquity(equity);

        // Calculate base lot (1% risk)
        double risk_amount = balance * (m_base_risk_pct / 100.0);
        double base_lot    = MMCalcLotFromRisk(symbol, risk_amount, stopLoss);

        // Apply regime multiplier
        base_lot *= m_risk_multiplier;

        // Check equity vs MA
        double eq_ma  = _CalcEquityMA();
        double factor = 1.0;

        if(eq_ma > 0.0 && equity < eq_ma)
        {
            // Below MA: reduce size
            factor = 1.0 - (m_below_ma_reduce_pct / 100.0);
            factor = MathMax(0.0, factor); // 100% reduce = stop trading
        }

        double lot = base_lot * factor;

        // Safety cap
        if(lot > 0.0)
        {
            double max_lot = MMCalcLotFromRisk(symbol, equity * 0.05, stopLoss);
            lot = MathMin(lot, max_lot);
        }

        m_state.last_lot = lot;
        return (lot > 0.0) ? MMNormalizeLot(symbol, lot)
                           : MMNormalizeLot(symbol, m_base_lot); // min lot if factor=0
    }

    //+------------------------------------------------------------------+
    //| UpdateTradeResult: Record equity after each trade                 |
    //+------------------------------------------------------------------+
    virtual void UpdateTradeResult(bool win, double rr = 1.0) override
    {
        IMoneyManager::UpdateTradeResult(win, rr);
        // Equity will be recorded on next CalculateLot call
    }

    virtual string GetName() override { return "MM09_EquityCurveRecovery"; }
    virtual int    GetID()   override { return (int)MM_ID_EQUITY_RECOVERY; }

    virtual string GetDiagnostic() override
    {
        double eq      = AccountInfoDouble(ACCOUNT_EQUITY);
        double eq_ma   = _CalcEquityMA();
        bool   below   = (eq_ma > 0.0 && eq < eq_ma);
        double factor  = below ? (1.0 - m_below_ma_reduce_pct / 100.0) : 1.0;
        return StringFormat(
            "[MM09] Equity:%.2f MA(%s%d):%.2f %s Factor:%.0f%%",
            eq, (m_ma_type == 1 ? "EMA" : "SMA"), m_ma_period, eq_ma,
            below ? "BELOW↓" : "ABOVE↑", factor * 100.0);
    }

private:
    void _RecordEquity(double equity)
    {
        if(ArraySize(m_equity_history) < m_ma_period)
            ArrayResize(m_equity_history, m_ma_period);

        m_equity_history[m_history_idx % m_ma_period] = equity;
        m_history_idx++;
        if(m_history_count < m_ma_period) m_history_count++;
    }

    double _CalcEquityMA()
    {
        int count = MathMin(m_history_count, m_ma_period);
        if(count == 0) return 0.0;

        if(m_ma_type == 0) // SMA
        {
            double sum = 0.0;
            for(int i = 0; i < count; i++) sum += m_equity_history[i];
            return sum / count;
        }
        else // EMA
        {
            // EMA over circular buffer (ordered oldest→newest)
            double k   = 2.0 / (count + 1.0);
            int start  = (m_history_count >= m_ma_period)
                         ? (m_history_idx % m_ma_period)
                         : 0;
            double ema = m_equity_history[start % m_ma_period];
            for(int i = 1; i < count; i++)
            {
                int idx = (start + i) % m_ma_period;
                ema = m_equity_history[idx] * k + ema * (1.0 - k);
            }
            return ema;
        }
    }
};

#endif // MM09_EQUITY_CURVE_RECOVERY_MQH
