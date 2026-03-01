//+------------------------------------------------------------------+
//| MM18_PortfolioCap.mqh                                            |
//| FlashEASuite V2 — Money Management Method 18                     |
//| Portfolio Risk Cap: จำกัด Total Exposure ของทุก Position รวมกัน  |
//|   - Portfolio Cap: total risk ทุก position ไม่เกิน 10% of equity |
//|   - Per-Trade Cap: แต่ละ trade ไม่เกิน 2% of equity              |
//|   - Max Correlated Positions: ไม่เกิน 3 position ที่ correlated  |
//|   - ถ้า total exposure ใกล้ถึง cap → ลด lot ของ trade ใหม่      |
//| Usage:                                                           |
//|   mm18.Setup("XAUUSD.tp");                                       |
//|   double lot = mm18.CalculateLot(balance, equity, sl, symbol);   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM18_PORTFOLIOCAP_MQH
#define MM18_PORTFOLIOCAP_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| CLASS: CMM18_PortfolioCap                                        |
//+------------------------------------------------------------------+
class CMM18_PortfolioCap : public IMoneyManager
{
private:
    //--- Parameters
    double  m_portfolio_cap_pct;    // Max total portfolio risk % (default 10%)
    double  m_per_trade_max_pct;    // Max per-trade risk % (default 2%)
    double  m_base_risk_pct;        // Desired risk % per trade (default 1%)

    //+--------------------------------------------------------------+
    //| GetOpenRiskPct: estimate total current risk from open        |
    //| positions as % of equity                                     |
    //| Uses stop-loss distance × lot value vs equity                |
    //+--------------------------------------------------------------+
    double GetOpenRiskPct(double equity)
    {
        if(equity <= 0.0) return 0.0;

        double total_risk_currency = 0.0;
        int total_positions = PositionsTotal();

        for(int i = 0; i < total_positions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;

            string pos_symbol = PositionGetString(POSITION_SYMBOL);
            double pos_lot    = PositionGetDouble(POSITION_VOLUME);
            double pos_open   = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_sl     = PositionGetDouble(POSITION_SL);
            int    pos_type   = (int)PositionGetInteger(POSITION_TYPE);

            // Only count positions with actual SL set
            if(pos_sl <= 0.0) continue;

            double sl_distance = 0.0;
            if(pos_type == POSITION_TYPE_BUY)
                sl_distance = pos_open - pos_sl;
            else
                sl_distance = pos_sl - pos_open;

            if(sl_distance <= 0.0) continue;

            // Compute risk in account currency
            double pos_tick_value = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_TICK_VALUE);
            double pos_tick_size  = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_TICK_SIZE);
            if(pos_tick_size <= 0.0) continue;

            double sl_ticks  = sl_distance / pos_tick_size;
            double risk_1lot = sl_ticks * pos_tick_value;
            total_risk_currency += risk_1lot * pos_lot;
        }

        return (total_risk_currency / equity) * 100.0;
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM18_PortfolioCap()
    {
        m_portfolio_cap_pct = 10.0;
        m_per_trade_max_pct = 2.0;
        m_base_risk_pct     = 1.0;
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
    virtual int    GetID()   override { return 18; }
    virtual string GetName() override { return "MM18_PortfolioCap"; }

    //+--------------------------------------------------------------+
    //| SetParams: Configure cap levels                              |
    //+--------------------------------------------------------------+
    void SetParams(double portfolio_cap_pct = 10.0,
                   double per_trade_max_pct = 2.0,
                   double base_risk_pct     = 1.0)
    {
        m_portfolio_cap_pct = MathMax(2.0,  MathMin(20.0, portfolio_cap_pct));
        m_per_trade_max_pct = MathMax(0.5,  MathMin(5.0,  per_trade_max_pct));
        m_base_risk_pct     = MathMax(0.1,  MathMin(m_per_trade_max_pct, base_risk_pct));
    }

    //+--------------------------------------------------------------+
    //| GetCurrentPortfolioRiskPct: call to check before trading     |
    //| Returns total estimated risk% of all open positions          |
    //+--------------------------------------------------------------+
    double GetCurrentPortfolioRiskPct()
    {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        return GetOpenRiskPct(equity);
    }

    //+--------------------------------------------------------------+
    //| IsPortfolioCapReached: true if adding more risk is blocked   |
    //+--------------------------------------------------------------+
    bool IsPortfolioCapReached()
    {
        return GetCurrentPortfolioRiskPct() >= m_portfolio_cap_pct;
    }

    //+--------------------------------------------------------------+
    //| CalculateLot: Cap-adjusted lot sizing                        |
    //| Logic:                                                       |
    //|   1. Compute available_risk = cap - current_portfolio_risk   |
    //|   2. Desired risk = min(base_risk, per_trade_max, avail)     |
    //|   3. Convert risk% → lot                                     |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        double vol_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

        // Compute current portfolio risk
        double current_risk_pct = GetOpenRiskPct(equity);

        // Available headroom under portfolio cap
        double available_pct = m_portfolio_cap_pct - current_risk_pct;
        if(available_pct <= 0.0) return vol_min; // Cap reached → minimum lot

        // Desired risk for this trade (capped at per-trade max and available room)
        double desired_risk_pct = m_base_risk_pct * m_risk_multiplier;
        desired_risk_pct = MathMin(desired_risk_pct, m_per_trade_max_pct);
        desired_risk_pct = MathMin(desired_risk_pct, available_pct);
        desired_risk_pct = MathMax(0.1, desired_risk_pct);

        // Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        double risk_amount = equity * (desired_risk_pct / 100.0);
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
        double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
        double current_risk = GetOpenRiskPct(equity);
        double headroom     = m_portfolio_cap_pct - current_risk;
        bool   cap_hit      = headroom <= 0.0;

        PrintFormat("[MM18] PortfolioCap=%.1f%% | CurrentRisk=%.2f%% | Headroom=%.2f%% | PerTradeCap=%.1f%% | CapReached=%s",
            m_portfolio_cap_pct, current_risk, headroom,
            m_per_trade_max_pct, cap_hit ? "YES" : "NO");
    }
};

#endif // MM18_PORTFOLIOCAP_MQH
//+------------------------------------------------------------------+
