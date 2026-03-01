//+------------------------------------------------------------------+
//| MM10_DrawdownBased.mqh                                           |
//| FlashEASuite V2 V6 — MM10: Drawdown-Based Sizing                |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|   ตรวจ Current Drawdown (DD) จาก Peak Equity                     |
//|   DD > TIER1 (10%) → ลด risk 50%                                 |
//|   DD > TIER2 (15%) → ลด risk 75%                                 |
//|   DD > STOP  (20%) → Emergency: lot = min_lot                    |
//|   Recovery: เพิ่ม risk กลับเมื่อ DD ลดลงถึง RECOVERY_LAG_PCT       |
//|                                                                  |
//| FORMULA:                                                         |
//|   DD% = (PeakEquity - CurrentEquity) / PeakEquity × 100         |
//|   BaseLot = 1% risk sizing                                       |
//|   if DD > STOP:   Lot = min_lot (emergency mode)                 |
//|   elif DD > TIER2: Lot = BaseLot × 0.25 (reduce 75%)            |
//|   elif DD > TIER1: Lot = BaseLot × 0.50 (reduce 50%)            |
//|   else:            Lot = BaseLot (normal)                        |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM10_DD_TIER1_PCT      default=10.0  (DD% → ลด 50%)            |
//|   MM10_DD_TIER2_PCT      default=15.0  (DD% → ลด 75%)            |
//|   MM10_DD_STOP_PCT       default=20.0  (DD% → emergency)         |
//|   MM10_RECOVERY_LAG_PCT  default=50.0  (% recovery ก่อน step up) |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM10_DRAWDOWN_BASED_MQH
#define MM10_DRAWDOWN_BASED_MQH

#include "IMoneyManager.mqh"

//--- Drawdown states
enum ENUM_DD_STATE
{
    DD_STATE_NORMAL    = 0,     // DD < Tier1 → full size
    DD_STATE_TIER1     = 1,     // DD > Tier1 → 50% size
    DD_STATE_TIER2     = 2,     // DD > Tier2 → 25% size
    DD_STATE_EMERGENCY = 3      // DD > Stop  → min lot
};

class CMM10_DrawdownBased : public IMoneyManager
{
private:
    double  m_dd_tier1_pct;         // DD% threshold tier1 (default 10%)
    double  m_dd_tier2_pct;         // DD% threshold tier2 (default 15%)
    double  m_dd_stop_pct;          // DD% emergency stop (default 20%)
    double  m_recovery_lag_pct;     // Recovery% to step back up (default 50%)
    double  m_base_risk_pct;        // Base risk% (default 1.0)

    // State
    ENUM_DD_STATE   m_dd_state;         // Current drawdown state
    double          m_peak_equity;      // Tracked peak equity
    double          m_last_dd_pct;      // Last calculated DD%

public:
    CMM10_DrawdownBased()
    {
        m_dd_tier1_pct      = 10.0;
        m_dd_tier2_pct      = 15.0;
        m_dd_stop_pct       = 20.0;
        m_recovery_lag_pct  = 50.0;
        m_base_risk_pct     = 1.0;
        m_dd_state          = DD_STATE_NORMAL;
        m_peak_equity       = 0.0;
        m_last_dd_pct       = 0.0;
    }

    void SetParams(double dd_tier1_pct, double dd_tier2_pct,
                   double dd_stop_pct,  double recovery_lag_pct,
                   double base_risk_pct = 1.0)
    {
        m_dd_tier1_pct     = MathMax(1.0,  MathMin(20.0, dd_tier1_pct));
        m_dd_tier2_pct     = MathMax(m_dd_tier1_pct, MathMin(30.0, dd_tier2_pct));
        m_dd_stop_pct      = MathMax(m_dd_tier2_pct, MathMin(50.0, dd_stop_pct));
        m_recovery_lag_pct = MathMax(0.0,  MathMin(100.0, recovery_lag_pct));
        m_base_risk_pct    = MathMax(0.1,  MathMin(5.0,   base_risk_pct));
    }

    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);

        // --- Update peak equity ---
        if(equity > m_peak_equity) m_peak_equity = equity;

        // --- Calculate current DD% ---
        m_last_dd_pct = 0.0;
        if(m_peak_equity > 0.0)
            m_last_dd_pct = (m_peak_equity - equity) / m_peak_equity * 100.0;

        // --- Determine DD state (with recovery hysteresis) ---
        _UpdateDDState(m_last_dd_pct);

        // --- Calculate base lot ---
        double risk_amount = balance * (m_base_risk_pct * m_risk_multiplier / 100.0);
        double base_lot    = MMCalcLotFromRisk(symbol, risk_amount, stopLoss);

        // --- Apply DD multiplier ---
        double lot = 0.0;
        switch(m_dd_state)
        {
            case DD_STATE_EMERGENCY:
                // Emergency: use minimum lot only
                lot = MMNormalizeLot(symbol, m_base_lot);
                break;

            case DD_STATE_TIER2:
                // DD > Tier2: reduce 75%
                lot = base_lot * 0.25;
                break;

            case DD_STATE_TIER1:
                // DD > Tier1: reduce 50%
                lot = base_lot * 0.50;
                break;

            default: // DD_STATE_NORMAL
                lot = base_lot;
                break;
        }

        // Safety cap: 5% equity
        if(m_dd_state != DD_STATE_EMERGENCY)
        {
            double max_lot = MMCalcLotFromRisk(symbol, equity * 0.05, stopLoss);
            lot = MathMin(lot, max_lot);
        }

        m_state.last_lot = lot;
        return MMNormalizeLot(symbol, lot);
    }

    //+------------------------------------------------------------------+
    //| IsEmergencyMode: Called by EA to halt new trades if true         |
    //+------------------------------------------------------------------+
    bool IsEmergencyMode() const { return (m_dd_state == DD_STATE_EMERGENCY); }

    double GetCurrentDD()   const { return m_last_dd_pct; }
    double GetPeakEquity()  const { return m_peak_equity; }
    ENUM_DD_STATE GetState() const { return m_dd_state; }

    virtual void UpdateTradeResult(bool win, double rr = 1.0) override
    {
        IMoneyManager::UpdateTradeResult(win, rr);
        // Peak equity update happens in CalculateLot (live equity)
    }

    virtual string GetName() override { return "MM10_DrawdownBased"; }
    virtual int    GetID()   override { return (int)MM_ID_DRAWDOWN_BASED; }

    virtual string GetDiagnostic() override
    {
        string state_str = "";
        switch(m_dd_state)
        {
            case DD_STATE_NORMAL:    state_str = "NORMAL";    break;
            case DD_STATE_TIER1:     state_str = "TIER1-50%"; break;
            case DD_STATE_TIER2:     state_str = "TIER2-75%"; break;
            case DD_STATE_EMERGENCY: state_str = "EMERGENCY"; break;
        }
        return StringFormat(
            "[MM10] State:%s DD:%.1f%% Peak:%.2f Tiers:[%.0f/%.0f/%.0f%%]",
            state_str, m_last_dd_pct, m_peak_equity,
            m_dd_tier1_pct, m_dd_tier2_pct, m_dd_stop_pct);
    }

private:
    //+------------------------------------------------------------------+
    //| Update DD state with recovery hysteresis                         |
    //| Recovery: only step down when DD reduces by RECOVERY_LAG_PCT%   |
    //| of the distance to the previous threshold                        |
    //+------------------------------------------------------------------+
    void _UpdateDDState(double dd_pct)
    {
        // Step UP (worsening): immediate
        if(dd_pct >= m_dd_stop_pct)
        {
            m_dd_state = DD_STATE_EMERGENCY;
            return;
        }
        if(dd_pct >= m_dd_tier2_pct)
        {
            m_dd_state = DD_STATE_TIER2;
            return;
        }
        if(dd_pct >= m_dd_tier1_pct)
        {
            m_dd_state = DD_STATE_TIER1;
            return;
        }

        // Step DOWN (recovering): apply hysteresis
        // Recover to lower state only when DD drops sufficiently below threshold
        if(m_dd_state == DD_STATE_EMERGENCY)
        {
            double recover_target = m_dd_stop_pct * (1.0 - m_recovery_lag_pct / 100.0);
            if(dd_pct <= recover_target) m_dd_state = DD_STATE_TIER2;
        }
        else if(m_dd_state == DD_STATE_TIER2)
        {
            double recover_target = m_dd_tier2_pct * (1.0 - m_recovery_lag_pct / 100.0);
            if(dd_pct <= recover_target) m_dd_state = DD_STATE_TIER1;
        }
        else if(m_dd_state == DD_STATE_TIER1)
        {
            double recover_target = m_dd_tier1_pct * (1.0 - m_recovery_lag_pct / 100.0);
            if(dd_pct <= recover_target) m_dd_state = DD_STATE_NORMAL;
        }
        // If already NORMAL: keep normal
    }
};

#endif // MM10_DRAWDOWN_BASED_MQH
