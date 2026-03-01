//+------------------------------------------------------------------+
//| MM05_MartingaleControlled.mqh                                    |
//| FlashEASuite V2 V6 — MM05: Controlled Martingale                |
//+------------------------------------------------------------------+
//| FORMULA:                                                         |
//|   BaseLot = MM01 calculation (1% risk)                           |
//|   After each loss: Multiplier = Lot_multiplier^consecutive_losses |
//|   Lot = BaseLot × Multiplier                                     |
//|   Cap: total multiplier ≤ MM05_MAX_TOTAL_MULT (default 4×)       |
//|   Levels: consecutive_losses ≤ MM05_MAX_LEVELS (default 4)       |
//|   Reset on win; optional break-even close all on P/L ≥ 0        |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM05_LOT_MULTIPLIER  default=2.0  (2× after each loss)         |
//|   MM05_MAX_LEVELS      default=4    (stop escalating at L4)      |
//|   MM05_MAX_TOTAL_MULT  default=4.0  (absolute cap multiplier)    |
//|   MM05_BREAK_EVEN_CLOSE default=1  (close all when P/L >= 0)    |
//|                                                                  |
//| DANGER: Martingale has exponential risk — use with strict caps   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM05_MARTINGALE_CONTROLLED_MQH
#define MM05_MARTINGALE_CONTROLLED_MQH

#include "IMoneyManager.mqh"

class CMM05_MartingaleControlled : public IMoneyManager
{
private:
    double  m_lot_multiplier;       // Multiplier per loss (default 2.0)
    int     m_max_levels;           // Max consecutive losses before cap
    double  m_max_total_mult;       // Absolute cap on multiplier (default 4.0)
    bool    m_break_even_close;     // Close all when total P/L >= 0
    double  m_base_risk_pct;        // Base risk% for BaseLot calc (default 1.0)
    
    // State
    double  m_base_lot_cache;       // Cached base lot (recalculate when balance changes)
    double  m_last_balance;         // Balance when base lot was calculated

public:
    CMM05_MartingaleControlled()
    {
        m_lot_multiplier  = 2.0;
        m_max_levels      = 4;
        m_max_total_mult  = 4.0;
        m_break_even_close= true;
        m_base_risk_pct   = 1.0;
        m_base_lot_cache  = 0.0;
        m_last_balance    = 0.0;
    }
    
    void SetParams(double lot_multiplier, int max_levels,
                   double max_total_mult, bool break_even_close = true,
                   double base_risk_pct = 1.0)
    {
        m_lot_multiplier   = MathMax(1.1, MathMin(5.0, lot_multiplier));
        m_max_levels       = MathMax(1, MathMin(10, max_levels));
        m_max_total_mult   = MathMax(1.1, MathMin(20.0, max_total_mult));
        m_break_even_close = break_even_close;
        m_base_risk_pct    = MathMax(0.1, MathMin(5.0, base_risk_pct));
    }
    
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);
        
        // Calculate base lot using MM01-style (1% risk)
        double base_lot = _CalcBaseLot(balance, equity, stopLoss, symbol);
        
        // Current consecutive losses (capped at m_max_levels)
        int losses = MathMin(m_state.consecutive_losses, m_max_levels);
        
        // Martingale multiplier: 2^losses
        double multiplier = 1.0;
        if(losses > 0)
            multiplier = MathPow(m_lot_multiplier, losses);
        
        // Apply absolute cap
        multiplier = MathMin(multiplier, m_max_total_mult);
        
        // Apply regime multiplier (can reduce during high risk)
        multiplier *= m_risk_multiplier;
        
        double lot = base_lot * multiplier;
        
        // Safety: never exceed 5% equity risk regardless of multiplier
        double max_risk_lot = MMCalcLotFromRisk(symbol, equity * 0.05, stopLoss);
        lot = MathMin(lot, max_risk_lot);
        
        m_state.last_lot = lot;
        return MMNormalizeLot(symbol, lot);
    }
    
    //--- Check if break-even close is needed (call from EA OnTick)
    bool ShouldCloseAll()
    {
        if(!m_break_even_close) return false;
        if(m_state.consecutive_losses == 0) return false; // No active sequence
        
        // Sum open P/L
        double total_pl = 0.0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
                total_pl += PositionGetDouble(POSITION_PROFIT);
        }
        return (total_pl >= 0.0 && m_state.consecutive_losses > 0);
    }
    
    virtual string GetName() override { return "MM05_MartingaleControlled"; }
    virtual int    GetID()   override { return (int)MM_ID_MARTINGALE; }
    
    virtual string GetDiagnostic() override
    {
        int losses     = MathMin(m_state.consecutive_losses, m_max_levels);
        double mult    = (losses > 0) ? MathPow(m_lot_multiplier, losses) : 1.0;
        mult = MathMin(mult, m_max_total_mult);
        return StringFormat("[MM05] ConsecLoss:%d Multiplier:%.1f× (cap:%.1f×) BaseLot:%.2f",
            m_state.consecutive_losses, mult, m_max_total_mult, m_base_lot_cache);
    }

private:
    double _CalcBaseLot(double balance, double equity,
                         double stopLoss, string symbol)
    {
        double risk_amount = balance * (m_base_risk_pct / 100.0);
        return MMCalcLotFromRisk(symbol, risk_amount, stopLoss);
    }
};

#endif // MM05_MARTINGALE_CONTROLLED_MQH
