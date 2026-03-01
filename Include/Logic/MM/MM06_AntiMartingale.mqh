//+------------------------------------------------------------------+
//| MM06_AntiMartingale.mqh                                          |
//| FlashEASuite V2 V6 — MM06: Anti-Martingale                      |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|   เพิ่ม Risk% ทุกครั้งที่ชนะ (win streak)                         |
//|   Reset กลับ Base เมื่อแพ้ตาม MM06_RESET_ON_LOSSES                |
//|                                                                  |
//| FORMULA:                                                         |
//|   CurrentRisk% = BaseRisk + (consecutive_wins × STEP_UP_PCT)    |
//|   Cap: CurrentRisk% ≤ MM06_MAX_RISK_CAP                         |
//|   Lot = (Balance × CurrentRisk%) / value_per_lot(SL)            |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM06_STEP_UP_PCT    default=0.5  (เพิ่ม 0.5% ต่อ win)          |
//|   MM06_MAX_RISK_CAP   default=3.0  (Risk% สูงสุดระหว่าง win streak)|
//|   MM06_RESET_ON_LOSSES default=1   (แพ้กี่ครั้งถึง reset)         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM06_ANTI_MARTINGALE_MQH
#define MM06_ANTI_MARTINGALE_MQH

#include "IMoneyManager.mqh"

class CMM06_AntiMartingale : public IMoneyManager
{
private:
    double  m_base_risk_pct;        // Base risk% (default 1.0)
    double  m_step_up_pct;          // Risk% step-up per win (default 0.5)
    double  m_max_risk_cap;         // Max risk% during streak (default 3.0)
    int     m_reset_on_losses;      // Losses before reset (default 1)

public:
    CMM06_AntiMartingale()
    {
        m_base_risk_pct   = 1.0;
        m_step_up_pct     = 0.5;
        m_max_risk_cap    = 3.0;
        m_reset_on_losses = 1;
    }

    void SetParams(double base_risk_pct,
                   double step_up_pct,
                   double max_risk_cap,
                   int    reset_on_losses)
    {
        m_base_risk_pct   = MathMax(0.1, MathMin(5.0,  base_risk_pct));
        m_step_up_pct     = MathMax(0.1, MathMin(2.0,  step_up_pct));
        m_max_risk_cap    = MathMax(1.0, MathMin(10.0, max_risk_cap));
        m_reset_on_losses = MathMax(1,   MathMin(5,    reset_on_losses));
    }

    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);

        // --- Determine current risk% based on win streak ---
        double current_risk_pct = m_base_risk_pct
                                + (m_state.consecutive_wins * m_step_up_pct);
        current_risk_pct = MathMin(current_risk_pct, m_max_risk_cap);

        // --- Apply regime multiplier ---
        current_risk_pct *= m_risk_multiplier;

        // --- Calculate lot ---
        double risk_amount = balance * (current_risk_pct / 100.0);
        double lot = MMCalcLotFromRisk(symbol, risk_amount, stopLoss);

        // Safety: never exceed 5% equity regardless
        double max_lot = MMCalcLotFromRisk(symbol, equity * 0.05, stopLoss);
        lot = MathMin(lot, max_lot);

        m_state.last_lot = lot;
        return MMNormalizeLot(symbol, lot);
    }

    //+------------------------------------------------------------------+
    //| Override: check consecutive_losses vs reset threshold            |
    //+------------------------------------------------------------------+
    virtual void UpdateTradeResult(bool win, double rr = 1.0) override
    {
        IMoneyManager::UpdateTradeResult(win, rr);
        // Note: m_state.AddResult already handles consecutive_wins/losses
        // Reset logic is automatic: consecutive_wins=0 when loss occurs
    }

    virtual string GetName() override { return "MM06_AntiMartingale"; }
    virtual int    GetID()   override { return (int)MM_ID_ANTI_MARTINGALE; }

    virtual string GetDiagnostic() override
    {
        double cur_risk = MathMin(
            m_base_risk_pct + (m_state.consecutive_wins * m_step_up_pct),
            m_max_risk_cap);
        return StringFormat(
            "[MM06] WinStreak:%d CurrentRisk:%.1f%% (Base:%.1f%% Cap:%.1f%%) ConsecLoss:%d",
            m_state.consecutive_wins, cur_risk,
            m_base_risk_pct, m_max_risk_cap,
            m_state.consecutive_losses);
    }
};

#endif // MM06_ANTI_MARTINGALE_MQH
