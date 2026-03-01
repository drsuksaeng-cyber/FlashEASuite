//+------------------------------------------------------------------+
//| MM02_FixedAggressive.mqh                                         |
//| FlashEASuite V2 V6 — MM02: Fixed Fractional Aggressive           |
//+------------------------------------------------------------------+
//| FORMULA:                                                         |
//|   RiskAmount = Balance × 2% (or Equity if equity_type=1)         |
//|   Lot = RiskAmount / (SL_distance × tick_value/tick_size)        |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM02_RISK_PCT  default=2.0%  range[1.0, 5.0]                   |
//|                                                                  |
//| NOTE: Same logic as MM01, higher default risk (2%)               |
//|       Suitable for high-confidence strategies (S09, S10, S14)    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM02_FIXED_AGGRESSIVE_MQH
#define MM02_FIXED_AGGRESSIVE_MQH

#include "IMoneyManager.mqh"

class CMM02_FixedAggressive : public IMoneyManager
{
private:
    double  m_risk_pct;         // Risk percent per trade (default 2.0)
    int     m_equity_type;      // 0=Balance, 1=Equity
    double  m_min_lot;          // Minimum lot

public:
    CMM02_FixedAggressive()
    {
        m_risk_pct    = 2.0;    // Aggressive: 2%
        m_equity_type = 1;      // Use Equity
        m_min_lot     = 0.01;
    }
    
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        m_min_lot = MathMax(0.01, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
    }
    
    void SetParams(double risk_pct, int equity_type = 1, double min_lot = 0.01)
    {
        m_risk_pct    = MathMax(0.1, MathMin(10.0, risk_pct));
        m_equity_type = (equity_type == 0) ? 0 : 1;
        m_min_lot     = MathMax(0.01, min_lot);
    }
    
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0)
            return MMNormalizeLot(symbol, m_min_lot);
        
        double capital     = (m_equity_type == 1) ? equity : balance;
        if(capital <= 0.0) capital = balance;
        
        double risk_pct    = m_risk_pct * m_risk_multiplier;
        double risk_amount = capital * (risk_pct / 100.0);
        
        double lot = MMCalcLotFromRisk(symbol, risk_amount, stopLoss);
        
        double broker_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        lot = MathMax(lot, MathMax(m_min_lot, broker_min));
        
        return MMNormalizeLot(symbol, lot);
    }
    
    virtual string GetName() override { return "MM02_FixedAggressive"; }
    virtual int    GetID()   override { return (int)MM_ID_FIXED_AGGRESSIVE; }
    
    virtual string GetDiagnostic() override
    {
        string base_str = (m_equity_type == 1) ? "Equity" : "Balance";
        return StringFormat("[MM02] Risk:%.1f%% Base:%s Multiplier:%.2f",
            m_risk_pct, base_str, m_risk_multiplier);
    }
};

#endif // MM02_FIXED_AGGRESSIVE_MQH
