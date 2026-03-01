//+------------------------------------------------------------------+
//| MM04_KellyCriterion.mqh                                          |
//| FlashEASuite V2 V6 — MM04: Kelly Criterion (Half-Kelly)          |
//+------------------------------------------------------------------+
//| FORMULA:                                                         |
//|   From rolling window of last N trades:                          |
//|     WinRate   = wins / total                                     |
//|     LossRate  = 1 - WinRate                                      |
//|     AvgRR     = avg(profit/initial_risk) for winning trades       |
//|     FullKelly = (WinRate × AvgRR - LossRate) / AvgRR            |
//|     HalfKelly = FullKelly × 0.5  (safer fraction)               |
//|     Kelly%    = Clamp(HalfKelly, 0%, MaxRiskCap%)               |
//|   Fallback: MM01 (1%) if trades < MM04_MIN_TRADES               |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM04_ROLLING_WINDOW   default=50  range[30,100]                |
//|   MM04_KELLY_FRACTION   default=0.5 range[0.25,0.5] (Half-Kelly) |
//|   MM04_MAX_RISK_CAP     default=5.0% range[3,8]                  |
//|   MM04_MIN_TRADES       default=30  (use MM01 before this)       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM04_KELLY_CRITERION_MQH
#define MM04_KELLY_CRITERION_MQH

#include "IMoneyManager.mqh"

class CMM04_KellyCriterion : public IMoneyManager
{
private:
    int     m_rolling_window;       // Trade history window (default 50)
    double  m_kelly_fraction;       // 0.5 = Half-Kelly (default)
    double  m_max_risk_cap;         // Max risk% cap (default 5.0%)
    int     m_min_trades;           // Min trades before activating Kelly
    double  m_fallback_risk_pct;    // Fallback risk% (MM01 = 1%)

public:
    CMM04_KellyCriterion()
    {
        m_rolling_window    = 50;
        m_kelly_fraction    = 0.5;
        m_max_risk_cap      = 5.0;
        m_min_trades        = 30;
        m_fallback_risk_pct = 1.0;
    }
    
    virtual void Setup(string symbol, int history_window = 50) override
    {
        // Use rolling_window as history capacity
        IMoneyManager::Setup(symbol, m_rolling_window);
    }
    
    void SetParams(int rolling_window, double kelly_fraction,
                   double max_risk_cap, int min_trades,
                   double fallback_pct = 1.0)
    {
        m_rolling_window    = MathMax(10, MathMin(200, rolling_window));
        m_kelly_fraction    = MathMax(0.1, MathMin(1.0, kelly_fraction));
        m_max_risk_cap      = MathMax(0.5, MathMin(25.0, max_risk_cap));
        m_min_trades        = MathMax(5, MathMin(200, min_trades));
        m_fallback_risk_pct = MathMax(0.1, MathMin(5.0, fallback_pct));
        
        // Reinit state with new window size
        if(m_symbol != "")
            m_state.Init(m_rolling_window);
    }
    
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);
        
        double risk_pct = _CalcKellyRisk();
        
        // Apply regime multiplier
        risk_pct *= m_risk_multiplier;
        
        // Hard cap
        risk_pct = MathMin(risk_pct, m_max_risk_cap);
        
        double risk_amount = balance * (risk_pct / 100.0);
        double lot         = MMCalcLotFromRisk(symbol, risk_amount, stopLoss);
        
        return MMNormalizeLot(symbol, lot);
    }
    
    virtual string GetName() override { return "MM04_KellyCriterion"; }
    virtual int    GetID()   override { return (int)MM_ID_KELLY; }
    
    virtual string GetDiagnostic() override
    {
        double risk = _CalcKellyRisk();
        bool active = (m_state.total_trades >= m_min_trades);
        return StringFormat("[MM04] %s Kelly:%.2f%% WinRate:%.0f%% AvgRR:%.2f Trades:%d",
            active ? "ACTIVE" : "FALLBACK",
            risk,
            m_state.GetWinRate() * 100.0,
            m_state.GetAvgRR(),
            m_state.total_trades);
    }

private:
    //--- Calculate Kelly risk percent
    double _CalcKellyRisk()
    {
        // Not enough data → use fallback (MM01)
        if(m_state.total_trades < m_min_trades)
            return m_fallback_risk_pct;
        
        double win_rate  = m_state.GetWinRate();
        double loss_rate = 1.0 - win_rate;
        double avg_rr    = m_state.GetAvgRR();
        
        if(avg_rr <= 0.0) return m_fallback_risk_pct;
        
        // Full Kelly: f = (WinRate × RR - LossRate) / RR
        double full_kelly = (win_rate * avg_rr - loss_rate) / avg_rr;
        
        // Negative Kelly = negative edge → fallback
        if(full_kelly <= 0.0)
        {
            Print("[MM04] Negative Kelly (", DoubleToString(full_kelly * 100.0, 2),
                  "%) → using fallback ", m_fallback_risk_pct, "%");
            return m_fallback_risk_pct;
        }
        
        // Apply Kelly fraction (Half-Kelly = 0.5)
        double kelly_pct = full_kelly * m_kelly_fraction * 100.0;
        
        // Clamp to max cap
        return MathMin(kelly_pct, m_max_risk_cap);
    }
};

#endif // MM04_KELLY_CRITERION_MQH
