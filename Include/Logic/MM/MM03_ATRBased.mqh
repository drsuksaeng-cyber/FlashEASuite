//+------------------------------------------------------------------+
//| MM03_ATRBased.mqh                                                |
//| FlashEASuite V2 V6 — MM03: ATR-Based Dynamic Sizing             |
//+------------------------------------------------------------------+
//| FORMULA:                                                         |
//|   ATR_SL = ATR(period) × ATR_multiplier   (derived SL if=0)     |
//|   SL_used = (stopLoss > 0) ? stopLoss : ATR_SL                  |
//|   RiskAmount = Balance × Risk%                                   |
//|   Lot = RiskAmount / (SL_used × tick_value/tick_size)            |
//|   BLOCK if: ATR_H1 / ATR_D1 > ATR_ratio_max  (trending filter)  |
//|                                                                  |
//| PARAMS (from CONFIG_PUSH):                                       |
//|   MM03_ATR_PERIOD      default=14  range[7,21]                   |
//|   MM03_ATR_MULTIPLIER  default=2.0 range[1.5,3.0]               |
//|   MM03_ATR_TIMEFRAME   default=60  (H1, in minutes)             |
//|   MM03_ATR_RATIO_MAX   default=0.8 (H1/D1 ratio cap)            |
//|   MM01_RISK_PCT        default=1.0% (shared param for risk)      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#ifndef MM03_ATR_BASED_MQH
#define MM03_ATR_BASED_MQH

#include "IMoneyManager.mqh"

class CMM03_ATRBased : public IMoneyManager
{
private:
    int     m_atr_period;           // ATR period (default 14)
    double  m_atr_multiplier;       // ATR × mult = SL distance (default 2.0)
    int     m_atr_tf;               // ATR timeframe for sizing (default PERIOD_H1)
    double  m_atr_ratio_max;        // Max ATR_H1/ATR_D1 ratio (default 0.8)
    double  m_risk_pct;             // Risk percent (default 1.0%)
    
    // Indicator handles (persistent across calls)
    int     m_atr_h1_handle;        // ATR on H1 for sizing
    int     m_atr_d1_handle;        // ATR on D1 for ratio filter

    //--- Convert minutes to ENUM_TIMEFRAMES
    ENUM_TIMEFRAMES MinutesToTF(int minutes)
    {
        switch(minutes)
        {
            case 1:    return PERIOD_M1;
            case 5:    return PERIOD_M5;
            case 15:   return PERIOD_M15;
            case 30:   return PERIOD_M30;
            case 60:   return PERIOD_H1;
            case 240:  return PERIOD_H4;
            case 1440: return PERIOD_D1;
            default:   return PERIOD_H1;
        }
    }

public:
    CMM03_ATRBased()
    {
        m_atr_period      = 14;
        m_atr_multiplier  = 2.0;
        m_atr_tf          = 60;     // H1 in minutes
        m_atr_ratio_max   = 0.8;
        m_risk_pct        = 1.0;
        m_atr_h1_handle   = INVALID_HANDLE;
        m_atr_d1_handle   = INVALID_HANDLE;
    }
    
    virtual ~CMM03_ATRBased()
    {
        if(m_atr_h1_handle != INVALID_HANDLE) IndicatorRelease(m_atr_h1_handle);
        if(m_atr_d1_handle != INVALID_HANDLE) IndicatorRelease(m_atr_d1_handle);
    }
    
    virtual void Setup(string symbol, int history_window = 50) override
    {
        IMoneyManager::Setup(symbol, history_window);
        _CreateHandles(symbol);
    }
    
    void SetParams(double risk_pct, int atr_period, double atr_mult,
                   int atr_tf_minutes = 60, double ratio_max = 0.8)
    {
        m_risk_pct       = MathMax(0.1, MathMin(10.0, risk_pct));
        m_atr_period     = MathMax(3, MathMin(50, atr_period));
        m_atr_multiplier = MathMax(0.5, MathMin(5.0, atr_mult));
        m_atr_tf         = atr_tf_minutes;
        m_atr_ratio_max  = MathMax(0.3, MathMin(1.0, ratio_max));
        
        // Recreate handles if symbol is set
        if(m_symbol != "") _CreateHandles(m_symbol);
    }
    
    virtual double CalculateLot(double balance, double equity,
                                 double stopLoss, string symbol) override
    {
        if(!m_initialized || balance <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot);
        
        // Get ATR values
        double atr_h1 = _GetATR(m_atr_h1_handle);
        double atr_d1 = _GetATR(m_atr_d1_handle);
        
        if(atr_h1 <= 0.0)
            return MMNormalizeLot(symbol, m_base_lot); // no data yet
        
        // ATR ratio filter: block if market trending strongly
        if(atr_d1 > 0.0 && (atr_h1 / atr_d1) > m_atr_ratio_max)
        {
            // Market too volatile/trending → use minimum lot
            Print("[MM03] ATR ratio filter triggered: H1/D1=",
                  DoubleToString(atr_h1 / atr_d1, 3), " > ",
                  DoubleToString(m_atr_ratio_max, 3));
            return MMNormalizeLot(symbol, m_base_lot);
        }
        
        // SL distance: use provided stopLoss or derive from ATR
        double sl_distance = (stopLoss > 0.0)
                             ? stopLoss
                             : (atr_h1 * m_atr_multiplier);
        
        if(sl_distance <= 0.0) return MMNormalizeLot(symbol, m_base_lot);
        
        // Risk amount
        double risk_pct    = m_risk_pct * m_risk_multiplier;
        double risk_amount = balance * (risk_pct / 100.0);
        
        double lot = MMCalcLotFromRisk(symbol, risk_amount, sl_distance);
        return MMNormalizeLot(symbol, lot);
    }
    
    virtual string GetName() override { return "MM03_ATRBased"; }
    virtual int    GetID()   override { return (int)MM_ID_ATR_BASED; }
    
    virtual string GetDiagnostic() override
    {
        double atr = _GetATR(m_atr_h1_handle);
        return StringFormat("[MM03] Risk:%.1f%% ATR:%.5f×%.1f Period:%d Mult:%.2f",
            m_risk_pct, atr, m_atr_multiplier, m_atr_period, m_risk_multiplier);
    }

private:
    void _CreateHandles(string symbol)
    {
        if(m_atr_h1_handle != INVALID_HANDLE) IndicatorRelease(m_atr_h1_handle);
        if(m_atr_d1_handle != INVALID_HANDLE) IndicatorRelease(m_atr_d1_handle);
        
        ENUM_TIMEFRAMES sizing_tf = MinutesToTF(m_atr_tf);
        m_atr_h1_handle = iATR(symbol, sizing_tf, m_atr_period);
        m_atr_d1_handle = iATR(symbol, PERIOD_D1, m_atr_period);
    }
    
    double _GetATR(int handle)
    {
        if(handle == INVALID_HANDLE) return 0.0;
        double buf[1];
        if(CopyBuffer(handle, 0, 1, 1, buf) <= 0) return 0.0;
        return buf[0];
    }
};

#endif // MM03_ATR_BASED_MQH
