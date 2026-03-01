//+------------------------------------------------------------------+
//| MM08_Pyramid.mqh                                                 |
//| FlashEASuite V2 V6 — MM08: Pyramid Adding                       |
//+------------------------------------------------------------------+
//| LOGIC:                                                           |
//|   เปิด position แรก = 50% ของ full position                      |
//|   เมื่อ trade กำไรถึง +1R → Add position ที่ 25% (50% × decay)   |
//|   เมื่อ trade กำไรถึง +2R → Add position ที่ 12.5% (25% × decay) |
//|   Max 3 levels รวม = ~87.5% (ไม่เกิน 1 full position)           |
//|                                                                  |
//| FORMULA:                                                         |
//|   Level 0: base_lot × (INITIAL_SIZE_PCT / 100)                  |
//|   Level N: Level(N-1) × (LOT_DECAY_PCT / 100)                   |
//|   Add trigger: float_profit ≥ ADD_TRIGGER_R × initial_risk       |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM08_INITIAL_SIZE_PCT  default=50.0 (% ของ full lot สำหรับ L0) |
//|   MM08_ADD_TRIGGER_R     default=1.0  (R-multiple ที่ trigger add)|
//|   MM08_LOT_DECAY_PCT     default=50.0 (lot ลด% ต่อ level)        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM08_PYRAMID_MQH
#define MM08_PYRAMID_MQH

#include "IMoneyManager.mqh"

class CMM08_Pyramid : public IMoneyManager
{
private:
    double  m_initial_size_pct;     // % ของ full position สำหรับ Level 0 (default 50)
    double  m_add_trigger_r;        // R-multiple ที่ trigger add (default 1.0)
    double  m_lot_decay_pct;        // Lot decay% ต่อ level (default 50)
    int     m_max_levels;           // Max pyramid levels (fixed 3)

    // State
    int     m_current_level;        // Pyramid level ปัจจุบัน (0=ยังไม่เริ่ม)
    double  m_initial_lot;          // Lot ที่ใช้ Level 0
    double  m_initial_risk_amount;  // Risk$ ของ trade แรก

public:
    CMM08_Pyramid()
    {
        m_initial_size_pct  = 50.0;
        m_add_trigger_r     = 1.0;
        m_lot_decay_pct     = 50.0;
        m_max_levels        = 3;
        m_current_level     = 0;
        m_initial_lot       = 0.0;
        m_initial_risk_amount = 0.0;
    }

    void SetParams(double initial_size_pct, double add_trigger_r, double lot_decay_pct)
    {
        m_initial_size_pct = MathMax(10.0, MathMin(90.0, initial_size_pct));
        m_add_trigger_r    = MathMax(0.5,  MathMin(5.0,  add_trigger_r));
        m_lot_decay_pct    = MathMax(20.0, MathMin(80.0, lot_decay_pct));
    }

    //+------------------------------------------------------------------+
    //| CalculateLot: Returns lot for the NEXT pyramid add               |
    //| Call GetPyramidLevel() to check which level this is for          |
    //+------------------------------------------------------------------+
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || stopLoss <= 0.0 || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);

        // Full position = 1% risk sizing
        double full_lot = MMCalcLotFromRisk(symbol, balance * 0.01 * m_risk_multiplier, stopLoss);

        double lot = 0.0;

        if(m_current_level == 0)
        {
            // Level 0: Initial entry
            lot = full_lot * (m_initial_size_pct / 100.0);
            m_initial_lot = lot;
            m_initial_risk_amount = MMCalcPriceValue(symbol, stopLoss) * lot;
        }
        else if(m_current_level < m_max_levels)
        {
            // Level N: decay from initial
            lot = m_initial_lot * MathPow(m_lot_decay_pct / 100.0, m_current_level);
        }
        else
        {
            // Max levels reached
            return 0.0;
        }

        // Safety cap: 5% equity per add
        double max_lot = MMCalcLotFromRisk(symbol, equity * 0.05, stopLoss);
        lot = MathMin(lot, max_lot);

        m_state.last_lot = lot;
        return MMNormalizeLot(symbol, lot);
    }

    //+------------------------------------------------------------------+
    //| ShouldAddPosition: Check if conditions met to add next level     |
    //| @param float_profit  Current unrealized P/L in account currency  |
    //| @param initial_risk  Risk$ of the initial entry                  |
    //+------------------------------------------------------------------+
    bool ShouldAddPosition(double float_profit, double initial_risk = -1.0)
    {
        if(m_current_level >= m_max_levels) return false;

        double risk_ref = (initial_risk > 0.0) ? initial_risk : m_initial_risk_amount;
        if(risk_ref <= 0.0) return false;

        // Trigger: profit ≥ level × trigger_r × initial_risk
        double needed = (m_current_level + 1) * m_add_trigger_r * risk_ref;
        return (float_profit >= needed);
    }

    //+------------------------------------------------------------------+
    //| AdvanceLevel: Call this AFTER successfully adding a position      |
    //+------------------------------------------------------------------+
    void AdvanceLevel() { if(m_current_level < m_max_levels) m_current_level++; }

    //+------------------------------------------------------------------+
    //| ResetPyramid: Call when trade closes (win or loss)               |
    //+------------------------------------------------------------------+
    void ResetPyramid()
    {
        m_current_level     = 0;
        m_initial_lot       = 0.0;
        m_initial_risk_amount = 0.0;
    }

    int    GetPyramidLevel() const { return m_current_level; }
    int    GetMaxLevels()    const { return m_max_levels; }

    virtual void UpdateTradeResult(bool win, double rr = 1.0) override
    {
        IMoneyManager::UpdateTradeResult(win, rr);
        ResetPyramid();
    }

    virtual string GetName() override { return "MM08_Pyramid"; }
    virtual int    GetID()   override { return (int)MM_ID_PYRAMID; }

    virtual string GetDiagnostic() override
    {
        return StringFormat(
            "[MM08] Level:%d/%d InitialLot:%.2f TriggerR:%.1f Decay:%.0f%%",
            m_current_level, m_max_levels,
            m_initial_lot, m_add_trigger_r, m_lot_decay_pct);
    }
};

#endif // MM08_PYRAMID_MQH
