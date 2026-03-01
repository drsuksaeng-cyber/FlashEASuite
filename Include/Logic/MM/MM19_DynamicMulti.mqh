//+------------------------------------------------------------------+
//| MM19_DynamicMulti.mqh                                            |
//| FlashEASuite V2 — Money Management Method 19                     |
//| Dynamic Multi-Method: รวม 2-3 MM methods เข้าด้วยกัน            |
//|   - Primary, Secondary, Tertiary MM IDs (1-18)                  |
//|   - Combine modes:                                               |
//|     0 = MIN_LOT  → ใช้ค่าน้อยสุด (conservative)                 |
//|     1 = AVG_LOT  → เฉลี่ย                                        |
//|     2 = WEIGHTED → ถ่วงน้ำหนัก primary 50%, secondary 30%, T20%  |
//|   - Inline calculation เพื่อหลีกเลี่ยง pointer dependencies     |
//|   - Default: Primary=MM01, Secondary=MM03, Tertiary=MM10        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM19_DYNAMICMULTI_MQH
#define MM19_DYNAMICMULTI_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| ENUM: Combine mode for multi-method                              |
//+------------------------------------------------------------------+
enum ENUM_MM19_COMBINE
{
    MM19_COMBINE_MIN      = 0,  // Use minimum lot (most conservative)
    MM19_COMBINE_AVG      = 1,  // Simple average
    MM19_COMBINE_WEIGHTED = 2   // Weighted: Primary 50%, Secondary 30%, Tertiary 20%
};

//+------------------------------------------------------------------+
//| CLASS: CMM19_DynamicMulti                                        |
//+------------------------------------------------------------------+
class CMM19_DynamicMulti : public IMoneyManager
{
private:
    //--- Configuration
    int                 m_primary_id;       // Primary MM ID (1-18, default 1)
    int                 m_secondary_id;     // Secondary MM ID (1-18, default 3)
    int                 m_tertiary_id;      // Tertiary MM ID (0=disabled, default 10)
    ENUM_MM19_COMBINE   m_combine_mode;     // How to combine lots

    //--- State for inline calculations
    double  m_base_risk_pct;        // Base risk %
    double  m_atr_value;            // ATR for ATR-based methods
    double  m_win_rate;             // For Kelly-based methods
    double  m_avg_rr;               // Average R:R for Kelly
    int     m_consecutive_wins;     // For streak/pyramid methods
    int     m_consecutive_losses;   // For streak/pyramid methods
    double  m_current_dd_pct;       // Drawdown % for DD-based methods

    //+--------------------------------------------------------------+
    //| CalcLotByID: inline calculation for a given MM method ID     |
    //| Supports IDs 1-15 with simplified formulas                   |
    //| IDs 16-18 (need special data) → fallback to MM01             |
    //+--------------------------------------------------------------+
    double CalcLotByID(int mm_id,
                       double balance,
                       double equity,
                       double stop_loss_price,
                       string symbol)
    {
        double vol_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(vol_min  <= 0.0) vol_min  = 0.01;
        if(vol_max  <= 0.0) vol_max  = 100.0;
        if(vol_step <= 0.0) vol_step = 0.01;

        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        double sl_ticks    = sl_distance / tick_size;
        double sl_currency = sl_ticks * tick_value;
        if(sl_currency <= 0.0) return vol_min;

        double risk_pct = m_base_risk_pct;

        //--- Select risk% based on MM ID
        switch(mm_id)
        {
            case 1:  // MM01: Fixed Fractional Conservative 1%
                risk_pct = 1.0;
                break;

            case 2:  // MM02: Fixed Fractional Aggressive 2%
                risk_pct = 2.0;
                break;

            case 3:  // MM03: ATR-Based Dynamic
            {
                // Use ATR to scale: risk_pct = base * (atr_ref / current_atr)
                // If m_atr_value not set → use base 1%
                if(m_atr_value > 0.0 && sl_distance > 0.0)
                {
                    // Normalize: base lot targets 1% risk at 1× ATR
                    double atr_ratio = MathMin(2.0, sl_distance / m_atr_value);
                    risk_pct = 1.0 / MathMax(0.1, atr_ratio);
                    risk_pct = MathMax(0.5, MathMin(2.0, risk_pct));
                }
                else
                    risk_pct = 1.0;
                break;
            }

            case 4:  // MM04: Kelly Criterion (Half-Kelly)
            {
                double wr = MathMax(0.1, MathMin(0.9, m_win_rate));
                double rr = MathMax(0.5, m_avg_rr);
                double kelly = (wr * rr - (1.0 - wr)) / rr;
                kelly = MathMax(0.0, MathMin(0.25, kelly)); // capped at 25%
                risk_pct = kelly * 100.0 * 0.5; // Half-Kelly
                risk_pct = MathMax(0.5, risk_pct);
                break;
            }

            case 5:  // MM05: Martingale Controlled (×2 per loss, max 4)
            {
                int levels = MathMin(m_consecutive_losses, 2); // max 2 levels up
                double multiplier = MathPow(2.0, levels);
                multiplier = MathMin(4.0, multiplier);
                risk_pct = 1.0 * multiplier;
                break;
            }

            case 6:  // MM06: Anti-Martingale (increase after win)
            {
                double step = 0.25;
                risk_pct = 1.0 + step * MathMin(m_consecutive_wins, 3);
                risk_pct = MathMin(3.0, risk_pct);
                break;
            }

            case 7:  // MM07: Percent Volatility
            {
                // Target: risk = 1% of equity based on ATR-denominated SL
                if(m_atr_value > 0.0)
                {
                    double vol_risk = equity * 0.01;
                    double lot = vol_risk / sl_currency;
                    lot = MathMax(vol_min, MathMin(vol_max, lot));
                    lot = MathRound(lot / vol_step) * vol_step;
                    return NormalizeDouble(lot, 2);
                }
                risk_pct = 1.0;
                break;
            }

            case 8:  // MM08: Pyramid (add to winners)
            {
                // Base lot; existing positions already open (tracked externally)
                // Here: reduce per-trade size as we add more
                int level = MathMin(m_consecutive_wins, 3);
                double decay = MathPow(0.7, level); // 1.0, 0.7, 0.49, 0.34
                risk_pct = 1.0 * decay;
                risk_pct = MathMax(0.3, risk_pct);
                break;
            }

            case 9:  // MM09: Equity Curve Recovery
            {
                double eq_ratio = (balance > 0.0) ? equity / balance : 1.0;
                risk_pct = (eq_ratio >= 1.0) ? 1.0 : 0.5; // reduce when equity < balance
                break;
            }

            case 10: // MM10: Drawdown-Based (tiered)
            {
                if(m_current_dd_pct >= 20.0)
                    return vol_min; // Stop new trades
                else if(m_current_dd_pct >= 15.0)
                    risk_pct = 1.0 * 0.25;
                else if(m_current_dd_pct >= 10.0)
                    risk_pct = 1.0 * 0.50;
                else
                    risk_pct = 1.0;
                break;
            }

            case 11: // MM11: Session-Based (simplified — London = 1.2%)
            {
                MqlDateTime t;
                TimeToStruct(TimeCurrent(), t);
                int hour = t.hour;
                if(hour >= 7 && hour < 12)       risk_pct = 1.5; // London
                else if(hour >= 12 && hour < 20) risk_pct = 1.2; // NY
                else                              risk_pct = 0.5; // Asian
                break;
            }

            case 12: // MM12: Equity Curve Filter
            {
                // If equity < balance (drawdown period) → halve risk
                risk_pct = (equity >= balance) ? 1.0 : 0.5;
                break;
            }

            case 13: // MM13: Correlation Adjusted (use base)
                risk_pct = 1.0;
                break;

            case 14: // MM14: Tiered Risk by Balance
            {
                if(balance < 1000.0)       risk_pct = 2.0;
                else if(balance < 10000.0) risk_pct = 1.5;
                else                        risk_pct = 1.0;
                break;
            }

            case 15: // MM15: Adaptive Win-Streak
            {
                int extra = MathMax(0, m_consecutive_wins - 3);
                risk_pct  = 1.0 + extra * 0.1;
                risk_pct  = MathMin(3.0, risk_pct);
                if(m_consecutive_losses > 0) risk_pct = 1.0; // reset on loss
                break;
            }

            default: // Unsupported ID → MM01 fallback
                risk_pct = 1.0;
                break;
        }

        // Clamp and convert to lot
        risk_pct = MathMax(0.1, MathMin(5.0, risk_pct)) * m_risk_multiplier;
        double risk_amount = balance * (risk_pct / 100.0);
        double lot = risk_amount / sl_currency;
        lot = MathMax(vol_min, MathMin(vol_max, lot));
        lot = MathRound(lot / vol_step) * vol_step;
        return NormalizeDouble(lot, 2);
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM19_DynamicMulti()
    {
        m_primary_id         = 1;
        m_secondary_id       = 3;
        m_tertiary_id        = 10;
        m_combine_mode       = MM19_COMBINE_MIN;
        m_base_risk_pct      = 1.0;
        m_atr_value          = 0.0;
        m_win_rate           = 0.5;
        m_avg_rr             = 1.5;
        m_consecutive_wins   = 0;
        m_consecutive_losses = 0;
        m_current_dd_pct     = 0.0;
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 19; }
    virtual string GetName() override { return "MM19_DynamicMulti"; }

    //+--------------------------------------------------------------+
    //| SetParams: Configure which MM methods to combine             |
    //+--------------------------------------------------------------+
    void SetParams(int   primary_id     = 1,
                   int   secondary_id   = 3,
                   int   tertiary_id    = 10,
                   int   combine_mode   = 0,
                   double base_risk_pct = 1.0)
    {
        m_primary_id   = MathMax(1, MathMin(18, primary_id));
        m_secondary_id = MathMax(1, MathMin(18, secondary_id));
        m_tertiary_id  = MathMax(0, MathMin(18, tertiary_id)); // 0 = disabled
        m_combine_mode = (ENUM_MM19_COMBINE)MathMax(0, MathMin(2, combine_mode));
        m_base_risk_pct= MathMax(0.1, MathMin(5.0, base_risk_pct));
    }

    //+--------------------------------------------------------------+
    //| UpdateContext: feed state data for inline calculations       |
    //| Call before CalculateLot                                     |
    //+--------------------------------------------------------------+
    void UpdateContext(double atr_value,
                       double win_rate,
                       double avg_rr,
                       int    consec_wins,
                       int    consec_losses,
                       double drawdown_pct)
    {
        m_atr_value          = MathMax(0.0, atr_value);
        m_win_rate           = MathMax(0.0, MathMin(1.0, win_rate));
        m_avg_rr             = MathMax(0.1, avg_rr);
        m_consecutive_wins   = MathMax(0, consec_wins);
        m_consecutive_losses = MathMax(0, consec_losses);
        m_current_dd_pct     = MathMax(0.0, drawdown_pct);
    }

    //+--------------------------------------------------------------+
    //| CalculateLot: Multi-method combined lot                      |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        double lot_primary   = CalcLotByID(m_primary_id,   balance, equity, stop_loss_price, symbol);
        double lot_secondary = CalcLotByID(m_secondary_id, balance, equity, stop_loss_price, symbol);

        double vol_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(vol_min <= 0.0) vol_min = 0.01;

        bool use_tertiary = (m_tertiary_id > 0);
        double lot_tertiary = vol_min;
        if(use_tertiary)
            lot_tertiary = CalcLotByID(m_tertiary_id, balance, equity, stop_loss_price, symbol);

        double final_lot = vol_min;

        switch(m_combine_mode)
        {
            case MM19_COMBINE_MIN:
            {
                final_lot = MathMin(lot_primary, lot_secondary);
                if(use_tertiary) final_lot = MathMin(final_lot, lot_tertiary);
                break;
            }

            case MM19_COMBINE_AVG:
            {
                if(use_tertiary)
                    final_lot = (lot_primary + lot_secondary + lot_tertiary) / 3.0;
                else
                    final_lot = (lot_primary + lot_secondary) / 2.0;
                break;
            }

            case MM19_COMBINE_WEIGHTED:
            {
                if(use_tertiary)
                    // 50% primary + 30% secondary + 20% tertiary
                    final_lot = lot_primary * 0.5 + lot_secondary * 0.3 + lot_tertiary * 0.2;
                else
                    // 60% primary + 40% secondary
                    final_lot = lot_primary * 0.6 + lot_secondary * 0.4;
                break;
            }
        }

        // Normalize
        double vol_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        double vol_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        if(vol_step <= 0.0) vol_step = 0.01;
        if(vol_max  <= 0.0) vol_max  = 100.0;

        final_lot = MathMax(vol_min, MathMin(vol_max, final_lot));
        final_lot = MathRound(final_lot / vol_step) * vol_step;
        return NormalizeDouble(final_lot, 2);
    }

    //+--------------------------------------------------------------+
    //| Diagnostics                                                  |
    //+--------------------------------------------------------------+
    void PrintDiagnostics()
    {
        string mode_names[] = {"MIN_LOT", "AVG_LOT", "WEIGHTED"};
        string mname = mode_names[(int)m_combine_mode];
        PrintFormat("[MM19] Primary=MM%02d | Secondary=MM%02d | Tertiary=MM%02d | Mode=%s | BaseRisk=%.2f%%",
            m_primary_id, m_secondary_id, m_tertiary_id, mname, m_base_risk_pct);
    }
};

#endif // MM19_DYNAMICMULTI_MQH
//+------------------------------------------------------------------+
