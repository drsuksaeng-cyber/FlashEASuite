//+------------------------------------------------------------------+
//| MM15_AdaptiveWinStreak.mqh                                       |
//| FlashEASuite V2 — Money Management Method 15                     |
//| Adaptive Win-Streak: เพิ่ม Lot ช้าๆ หลังจาก 3+ wins ติดกัน     |
//|   - เริ่มเพิ่มหลัง MIN_STREAK wins (default = 3)                |
//|   - เพิ่มขึ้น STEP_UP% ต่อ 1 win ที่เพิ่ม                       |
//|   - จำกัดไม่เกิน MAX_RISK_CAP%                                  |
//|   - เมื่อแพ้ 1 ครั้ง: reset กลับ Base Risk ทันที                 |
//| ต่างจาก MM06 (Anti-Martingale): MM15 เริ่มเพิ่มช้ากว่าและ       |
//| ต้องรอ streak ขั้นต่ำก่อน                                         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM15_ADAPTIVEWINSTREAK_MQH
#define MM15_ADAPTIVEWINSTREAK_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| CLASS: CMM15_AdaptiveWinStreak                                   |
//+------------------------------------------------------------------+
class CMM15_AdaptiveWinStreak : public IMoneyManager
{
private:
    int     m_min_streak;           // Minimum wins before increasing (default 3)
    double  m_step_up_pct;          // Risk increase per extra win beyond min (default 10%)
    double  m_max_risk_cap;         // Maximum risk % cap (default 3%)
    double  m_base_risk_pct;        // Base risk % (default 1%)

    int     m_current_streak;       // Current consecutive win count
    double  m_current_risk_pct;     // Current active risk %

    //+--------------------------------------------------------------+
    //| RecalcRisk: Recalculate risk based on current streak         |
    //+--------------------------------------------------------------+
    void RecalcRisk()
    {
        if(m_current_streak < m_min_streak)
        {
            // Below minimum streak → stay at base
            m_current_risk_pct = m_base_risk_pct;
            return;
        }

        // Extra wins beyond min_streak
        int extra_wins = m_current_streak - m_min_streak;
        double increase = extra_wins * (m_step_up_pct / 100.0) * m_base_risk_pct;
        m_current_risk_pct = m_base_risk_pct + increase;

        // Cap at max
        if(m_current_risk_pct > m_max_risk_cap)
            m_current_risk_pct = m_max_risk_cap;
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM15_AdaptiveWinStreak()
    {
        m_min_streak       = 3;
        m_step_up_pct      = 10.0;
        m_max_risk_cap     = 3.0;
        m_base_risk_pct    = 1.0;
        m_current_streak   = 0;
        m_current_risk_pct = 1.0;
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        m_current_streak   = 0;
        m_current_risk_pct = m_base_risk_pct;
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 15; }
    virtual string GetName() override { return "MM15_AdaptiveWinStreak"; }

    //+--------------------------------------------------------------+
    //| SetParams: Customize streak parameters                       |
    //+--------------------------------------------------------------+
    void SetParams(int min_streak, double step_up_pct,
                   double max_risk_cap, double base_risk_pct = 1.0)
    {
        m_min_streak    = MathMax(1, min_streak);
        m_step_up_pct   = MathMax(1.0, MathMin(50.0, step_up_pct));
        m_max_risk_cap  = MathMax(base_risk_pct, MathMin(10.0, max_risk_cap));
        m_base_risk_pct = MathMax(0.1, base_risk_pct);

        m_current_streak   = 0;
        m_current_risk_pct = m_base_risk_pct;
    }

    //+--------------------------------------------------------------+
    //| RecordWin: Call after each winning trade                     |
    //+--------------------------------------------------------------+
    void RecordWin()
    {
        m_current_streak++;
        RecalcRisk();
    }

    //+--------------------------------------------------------------+
    //| RecordLoss: Call after each losing trade — resets streak     |
    //+--------------------------------------------------------------+
    void RecordLoss()
    {
        m_current_streak   = 0;           // Reset streak on any loss
        m_current_risk_pct = m_base_risk_pct; // Return to base immediately
    }

    //+--------------------------------------------------------------+
    //| GetCurrentStreak / GetCurrentRiskPct: Accessors              |
    //+--------------------------------------------------------------+
    int    GetCurrentStreak()  { return m_current_streak;   }
    double GetCurrentRiskPct() { return m_current_risk_pct; }

    //+--------------------------------------------------------------+
    //| CalculateLot: Win-streak adjusted lot sizing                 |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // Use current risk (updated by RecordWin/RecordLoss)
        double risk_pct = m_current_risk_pct;

        // --- Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        // --- SL distance
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        // --- Lot calculation
        double risk_amount = balance * (risk_pct / 100.0);
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
    void PrintDiagnostics()
    {
        bool boosted = (m_current_streak >= m_min_streak);
        PrintFormat("[MM15] Streak=%d | MinStreak=%d | ActiveRisk=%.2f%% | BaseRisk=%.2f%% | Cap=%.2f%% | Boosted=%s",
            m_current_streak, m_min_streak,
            m_current_risk_pct, m_base_risk_pct,
            m_max_risk_cap,
            boosted ? "YES" : "NO");
    }
};

#endif // MM15_ADAPTIVEWINSTREAK_MQH
//+------------------------------------------------------------------+
