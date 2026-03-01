//+------------------------------------------------------------------+
//| MM13_CorrelationAdjusted.mqh                                     |
//| FlashEASuite V2 — Money Management Method 13                     |
//| Correlation Adjusted: ลด Lot เมื่อมี Correlated Positions เปิดอยู่|
//| สูตร: Lot = BaseLot × (1 - corr_pairs × reduce_per_corr)        |
//| ตัวอย่าง: 2 correlated positions + reduce 20% each               |
//|           → Lot = BaseLot × (1 - 2×0.20) = 60% of base          |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#ifndef MM13_CORRELATIONADJUSTED_MQH
#define MM13_CORRELATIONADJUSTED_MQH

#include "IMoneyManager.mqh"

//+------------------------------------------------------------------+
//| CLASS: CMM13_CorrelationAdjusted                                 |
//+------------------------------------------------------------------+
class CMM13_CorrelationAdjusted : public IMoneyManager
{
private:
    int     m_max_corr_pairs;       // Max correlated positions before reduce
    double  m_corr_threshold;       // Correlation threshold (0-1, default 0.7)
    double  m_reduce_per_corr_pct;  // Reduce % per correlated pair (default 20%)
    double  m_base_risk_pct;        // Base risk %
    int     m_corr_count;           // Current correlated positions (set externally)

    // Correlated symbols tracking (direct array — no pointer)
    string  m_corr_symbols[10];     // List of symbols considered correlated
    int     m_corr_symbol_count;

    //+--------------------------------------------------------------+
    //| CountOpenCorrelatedPositions: Count open positions on        |
    //| correlated symbols (excluding current symbol)                |
    //+--------------------------------------------------------------+
    int CountOpenCorrelatedPositions(string current_symbol)
    {
        int count = 0;
        int total = PositionsTotal();

        for(int i = 0; i < total; i++)
        {
            string pos_symbol = PositionGetSymbol(i);
            if(pos_symbol == current_symbol) continue; // Skip self

            // Check if this symbol is in the correlated list
            for(int j = 0; j < m_corr_symbol_count; j++)
            {
                if(pos_symbol == m_corr_symbols[j])
                {
                    count++;
                    break;
                }
            }
        }
        return count;
    }

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CMM13_CorrelationAdjusted()
    {
        m_max_corr_pairs      = 3;
        m_corr_threshold      = 0.7;
        m_reduce_per_corr_pct = 20.0;
        m_base_risk_pct       = 1.0;
        m_corr_count          = 0;
        m_corr_symbol_count   = 0;
        // ✅ MQL5: ใช้ loop สำหรับ string array — ArrayInitialize() ใช้กับ string ไม่ได้
        for(int i = 0; i < 10; i++) m_corr_symbols[i] = "";
    }

    //+--------------------------------------------------------------+
    //| Setup                                                        |
    //+--------------------------------------------------------------+
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        // Auto-add common correlated XAUUSD pairs
        AddCorrelatedSymbol("XAUEUR.tp");
        AddCorrelatedSymbol("XAGUSD.tp");
        AddCorrelatedSymbol("XPTUSD.tp");
        AddCorrelatedSymbol("DXY.tp");
    }

    //+--------------------------------------------------------------+
    //| GetID / GetName                                              |
    //+--------------------------------------------------------------+
    virtual int    GetID()   override { return 13; }
    virtual string GetName() override { return "MM13_CorrelationAdjusted"; }

    //+--------------------------------------------------------------+
    //| SetParams: Customize correlation parameters                  |
    //+--------------------------------------------------------------+
    void SetParams(int max_corr_pairs, double corr_threshold,
                   double reduce_per_corr_pct, double base_risk_pct = 1.0)
    {
        m_max_corr_pairs      = MathMax(1, max_corr_pairs);
        m_corr_threshold      = MathMax(0.0, MathMin(1.0, corr_threshold));
        m_reduce_per_corr_pct = MathMax(0.0, MathMin(50.0, reduce_per_corr_pct));
        m_base_risk_pct       = MathMax(0.1, base_risk_pct);
    }

    //+--------------------------------------------------------------+
    //| AddCorrelatedSymbol: Add symbol to correlation watch list    |
    //+--------------------------------------------------------------+
    void AddCorrelatedSymbol(string sym)
    {
        if(m_corr_symbol_count >= 10) return;
        m_corr_symbols[m_corr_symbol_count] = sym;
        m_corr_symbol_count++;
    }

    //+--------------------------------------------------------------+
    //| SetCorrCount: Override auto-detection with external count    |
    //| (For use when Python Brain provides correlation data)        |
    //+--------------------------------------------------------------+
    void SetCorrCount(int count)
    {
        m_corr_count = MathMax(0, count);
    }

    //+--------------------------------------------------------------+
    //| GetCorrMultiplier: Calculate reduction multiplier            |
    //+--------------------------------------------------------------+
    double GetCorrMultiplier(int corr_pairs)
    {
        if(corr_pairs <= 0) return 1.0;
        if(corr_pairs > m_max_corr_pairs) corr_pairs = m_max_corr_pairs;

        double reduction = corr_pairs * (m_reduce_per_corr_pct / 100.0);
        double multiplier = 1.0 - reduction;
        return MathMax(0.1, multiplier); // Minimum 10% of base
    }

    //+--------------------------------------------------------------+
    //| CalculateLot: Apply correlation adjustment                   |
    //+--------------------------------------------------------------+
    virtual double CalculateLot(double balance,
                                 double equity,
                                 double stop_loss_price,
                                 string symbol) override
    {
        // --- Symbol info
        double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double vol_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double vol_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double vol_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

        if(tick_value <= 0.0 || tick_size <= 0.0) return vol_min;

        // --- Count correlated open positions
        int corr_pairs = CountOpenCorrelatedPositions(symbol);
        // If external count was set via SetCorrCount(), use whichever is higher
        if(m_corr_count > corr_pairs) corr_pairs = m_corr_count;

        // --- Get multiplier
        double corr_multiplier = GetCorrMultiplier(corr_pairs);
        double effective_risk  = m_base_risk_pct * corr_multiplier;

        // --- SL distance
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return vol_min;

        double sl_distance = MathAbs(price - stop_loss_price);
        if(sl_distance <= 0.0) sl_distance = tick_size * 100;

        // --- Lot calculation
        double risk_amount = balance * (effective_risk / 100.0);
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
    void PrintDiagnostics(string symbol)
    {
        int corr = CountOpenCorrelatedPositions(symbol);
        double mult = GetCorrMultiplier(corr);
        PrintFormat("[MM13] CorrPairs=%d | Multiplier=%.2f | EffectiveRisk=%.2f%% | MaxCorr=%d | ReducePerCorr=%.1f%%",
            corr, mult, m_base_risk_pct * mult,
            m_max_corr_pairs, m_reduce_per_corr_pct);
    }
};

#endif // MM13_CORRELATIONADJUSTED_MQH
//+------------------------------------------------------------------+
