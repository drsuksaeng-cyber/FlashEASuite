//+------------------------------------------------------------------+
//| MM12_EquityCurveFilter.mqh                                       |
//| FlashEASuite V2 — Money Management Method 12                     |
//| Equity Curve Filter: เทรดเต็ม Lot เมื่อ Equity > MA(Equity)     |
//| เมื่อ Equity < MA → ลด Lot ตาม filter_mode                       |
//|   Mode 0 (REDUCE): ลด Lot 50%                                   |
//|   Mode 1 (PAUSE):  หยุดเทรด (return 0)                          |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM12_EQUITYCURVEFILTER_MQH
#define MM12_EQUITYCURVEFILTER_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| Enum: Filter mode when equity below MA                           |
//+------------------------------------------------------------------+
enum ENUM_EC_FILTER_MODE
{
    EC_FILTER_REDUCE = 0,   // Reduce lot by 50% — still trade
    EC_FILTER_PAUSE  = 1    // Pause trading entirely (return 0)
};

//+------------------------------------------------------------------+
//| CLASS: CMM12_EquityCurveFilter                                   |
//+------------------------------------------------------------------+
class CMM12_EquityCurveFilter : public IMoneyManager
{
private:
    double              m_equity_history[];     // Circular buffer of equity snapshots
    int                 m_ec_ma_period;         // MA period (in equity snapshots)
    int                 m_history_count;        // How many snapshots recorded
    int                 m_history_index;        // Current write position (circular)
    ENUM_EC_FILTER_MODE m_filter_mode;          // REDUCE or PAUSE
    double              m_base_risk_pct;        // Base risk % (full size)
    double              m_reduce_pct;           // Reduction % when below MA (default 50%)

    //+--------------------------------------------------------------+
    //| ComputeMA: Simple moving average of equity history           |
    //+--------------------------------------------------------------+
    double ComputeMA()
    {
        if(m_history_count == 0) return 0.0;

        int count = MathMin(m_history_count, m_ec_ma_period);
        double sum = 0.0;

        // Walk backward through circular buffer
        for(int i = 0; i < count; i++)
        {
            int idx = (m_history_index - 1 - i + m_ec_ma_period) % m_ec_ma_period;
            if(idx >= ArraySize(m_equity_history)) break;
            sum += m_equity_history[idx];
        }
        return (count > 0) ? sum / count : 0.0;
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM12_EquityCurveFilter()
    {
        m_ec_ma_period   = 20;
        m_history_count  = 0;
        m_history_index  = 0;
        m_filter_mode    = EC_FILTER_REDUCE;
        m_base_risk_pct  = 1.0;
        m_reduce_pct     = 50.0;
        ArrayResize(m_equity_history, m_ec_ma_period);
        ArrayInitialize(m_equity_history, 0.0);
    }

    //+--------------------------------------------------------------+
    //| Setup: Initialize with symbol and history window             |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        m_ec_ma_period = MathMax(5, history_window);
        ArrayResize(m_equity_history, m_ec_ma_period);
        ArrayInitialize(m_equity_history, 0.0);
        m_history_count = 0;
        m_history_index = 0;
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 12; }
    virtual string GetName() override { return "MM12_EquityCurveFilter"; }

    //+--------------------------------------------------------------+
    //| SetParams: Customize filter parameters                       |
    //+--------------------------------------------------------------+
    void SetParams(int ma_period, ENUM_EC_FILTER_MODE mode,
                   double base_risk_pct = 1.0, double reduce_pct = 50.0)
    {
        m_ec_ma_period  = MathMax(5, ma_period);
        m_filter_mode   = mode;
        m_base_risk_pct = MathMax(0.1, base_risk_pct);
        m_reduce_pct    = MathMax(0.0, MathMin(100.0, reduce_pct));

        ArrayResize(m_equity_history, m_ec_ma_period);
        ArrayInitialize(m_equity_history, 0.0);
        m_history_count = 0;
        m_history_index = 0;
    }

    //+--------------------------------------------------------------+
    //| RecordEquity: Push new equity snapshot into circular buffer  |
    //| Call this after each trade close or periodically             |
    //+--------------------------------------------------------------+
    void RecordEquity(double equity)
    {
        if(ArraySize(m_equity_history) == 0)
            ArrayResize(m_equity_history, m_ec_ma_period);

        m_equity_history[m_history_index] = equity;
        m_history_index = (m_history_index + 1) % m_ec_ma_period;
        m_history_count++;
    }

    //+--------------------------------------------------------------+
    //| IsEquityAboveMA: True = full size allowed                    |
    //+--------------------------------------------------------------+
    bool IsEquityAboveMA(double equity)
    {
        if(m_history_count < m_ec_ma_period) return true; // Not enough data → full size
        double ma = ComputeMA();
        return (equity >= ma);
    }

    //+--------------------------------------------------------------+
    //| CalculateLot: Apply equity curve filter                      |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // --- Record current equity
        RecordEquity(equity);

        // --- Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        // --- Determine effective risk %
        double effective_risk_pct = m_base_risk_pct;

        if(!IsEquityAboveMA(equity))
        {
            if(m_filter_mode == EC_FILTER_PAUSE)
                return 0.0; // Signal: do not trade

            // EC_FILTER_REDUCE — reduce lot by reduce_pct
            effective_risk_pct = m_base_risk_pct * (1.0 - m_reduce_pct / 100.0);
            if(effective_risk_pct <= 0.0)
                return 0.0;
        }

        // --- SL distance
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        // --- Lot calculation
        double risk_amount = balance * (effective_risk_pct / 100.0);
        double sl_ticks    = sl_distance / tick_size;
        double sl_currency = sl_ticks * tick_value;
        if(sl_currency <= 0.0) return vol_min;

        double lot = risk_amount / sl_currency;
        lot = MathMax(vol_min, MathMin(vol_max, lot));
        lot = MathRound(lot / vol_step) * vol_step;

        return NormalizeDouble(lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Diagnostics                                                  |
    //+--------------------------------------------------------------+
    void PrintDiagnostics(double equity)
    {
        double ma = ComputeMA();
        bool above = IsEquityAboveMA(equity);
        PrintFormat("[MM12] Equity=%.2f | EC_MA(%.0f)=%.2f | Above=%s | Mode=%s | BaseRisk=%.2f%%",
            equity, (double)m_ec_ma_period, ma,
            above ? "YES" : "NO",
            m_filter_mode == EC_FILTER_REDUCE ? "REDUCE" : "PAUSE",
            m_base_risk_pct);
    }
};

#endif // MM12_EQUITYCURVEFILTER_MQH
//+------------------------------------------------------------------+
