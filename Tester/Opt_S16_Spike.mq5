//+------------------------------------------------------------------+
//| Opt_S16_Spike.mq5                                                |
//| FlashEASuite V2 — Optimization EA for S16 Spike Hunter          |
//| Magic: 1016 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S16_Spike                                       |
//|   Symbol   : XAUUSD.tp                                           |
//|   Timeframe: M5 (แนะนำ) หรือ M1 / M15                           |
//|   Model    : Every tick based on real ticks (จำเป็น!)            |
//|   Period   : 2023.01.01 – 2024.12.31                             |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = ProfitFactor × WinRate × sqrt(Trades) / MaxDD_pct     |
//|   เงื่อนไข: Trades >= 30, PF >= 1.0, MaxDD <= 30%               |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/MM/MMManager.mqh"
#include "../Include/Logic/Common/HiddenTPSL.mqh"
#include "../Include/Logic/Common/TrailingStop.mqh"
#include "../Include/Logic/Common/TransferToGrid.mqh"
#include "../Include/Logic/Strategies/S16_Spike.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs (trade management + S16 hidden TP/SL config)    |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per trade
input double   Inp_MinConfidence  = 0.4;    // Min confidence to trade
input int      Inp_MaxPositions   = 1;      // Max concurrent positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// S16-specific trade config (replicated from SetTPSLConfig)
input double   Inp_TP_ATR_Mult    = 0.8;   // Hidden TP = N × ATR
input double   Inp_SL_ATR_Mult    = 0.4;   // Hidden SL = N × ATR
input bool     Inp_TrailEnabled   = false;  // Enable trailing stop
input int      Inp_MaxHoldSec     = 900;    // Max hold seconds (default 15min)

// NOTE: S16 signal parameters come from S16_Spike.mqh includes via
// Strategy_Spike.mqh (velocity, spread, volume thresholds etc.)

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CS16Spike    g_strategy;
CTrade       g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize strategy
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S16] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    // Apply TP/SL config
    g_strategy.SetTPSLConfig(
        Inp_TP_ATR_Mult,
        Inp_SL_ATR_Mult,
        Inp_TrailEnabled,
        TS_ATR,
        Inp_MaxHoldSec
    );

    // Trade object setup
    g_trade.SetExpertMagicNumber(MAGIC_S16_SPIKE);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S16] Initialized | Symbol=", Symbol(),
          " TF=", EnumToString(Period()),
          " TP×", Inp_TP_ATR_Mult, " SL×", Inp_SL_ATR_Mult);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    g_strategy.Deinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    MqlTick tick;
    if(!SymbolInfoTick(Symbol(), tick)) return;

    // ── 1. Analyze + ManagePositions (Hidden TP/SL + MaxHold) ────────
    g_strategy.Analyze(tick);
    g_strategy.ManagePositions(tick);

    ENUM_TRADE_SIGNAL signal     = g_strategy.GetSignal();
    double            confidence = g_strategy.GetConfidence();

    // ── 2. Check confidence filter ───────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 3. Max positions guard ───────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 4. Calculate lot size ────────────────────────────────────────
    // S16 uses ATR-based SL — estimate from current ATR
    double atr = g_strategy.GetSpikeATR();
    if(atr <= 0.0) return;

    double sl_dist = Inp_SL_ATR_Mult * atr;
    if(sl_dist <= 0.0) return;

    double sl_price = (signal == SIGNAL_BUY)
                      ? tick.ask - sl_dist
                      : tick.bid + sl_dist;

    double lot = _CalcLot(tick, sl_price);
    if(lot <= 0.0) return;

    // ── 5. Execute ───────────────────────────────────────────────────
    // Note: Hidden TP/SL set by ManagePositions() after open
    if(signal == SIGNAL_BUY)
    {
        if(g_trade.Buy(lot, Symbol(), tick.ask, sl_price, 0.0,
                       StringFormat("S16|Conf=%.2f|ATR=%.5f", confidence, atr)))
        {
            // ManagePositions() will register hidden TP/SL next tick
        }
    }
    else if(signal == SIGNAL_SELL)
    {
        if(g_trade.Sell(lot, Symbol(), tick.bid, sl_price, 0.0,
                        StringFormat("S16|Conf=%.2f|ATR=%.5f", confidence, atr)))
        {
            // ManagePositions() will register hidden TP/SL next tick
        }
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| Spike Hunter ต้องการ: trades มาก, DD ต่ำ, PF สูง               |
//+------------------------------------------------------------------+
double OnTester()
{
    double profit       = TesterStatistics(STAT_PROFIT);
    double pf           = TesterStatistics(STAT_PROFIT_FACTOR);
    double trades       = TesterStatistics(STAT_TRADES);
    double profit_tr    = TesterStatistics(STAT_PROFIT_TRADES);
    double win_rate     = (trades > 0) ? profit_tr / trades : 0.0;
    double max_dd_pct   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double sharpe       = TesterStatistics(STAT_SHARPE_RATIO);
    // คำนวณ avg profit/loss เอง (MT5 ไม่มี STAT_PROFIT_TRADES_AVGPROFIT)
    double loss_tr      = TesterStatistics(STAT_LOSS_TRADES);
    double gross_profit = TesterStatistics(STAT_GROSS_PROFIT);
    double gross_loss   = TesterStatistics(STAT_GROSS_LOSS);   // ค่าลบ
    double avg_profit   = (profit_tr  > 0) ? gross_profit / profit_tr  : 0.0;
    double avg_loss     = (loss_tr    > 0) ? MathAbs(gross_loss / loss_tr) : 0.0;
    double rr_ratio     = (avg_loss  != 0) ? MathAbs(avg_profit / avg_loss) : 1.0;

    // Hard filters
    if(trades   <  30)    return 0.0;
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 30.0) return 0.0;
    if(win_rate <  0.30)  return 0.0;  // Spike ยอม WR ต่ำกว่า MeanRev ได้ถ้า RR ดี

    // Composite score
    // S16 เน้น: PF × WR × √Trades / MaxDD × RR bonus
    double score = pf * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: RR > 1.5 (เหมาะกับ Spike ที่ cut loss เร็ว)
    if(rr_ratio > 1.5) score *= 1.0 + (rr_ratio - 1.5) * 0.05;

    // Bonus: Sharpe
    if(sharpe > 1.0) score *= 1.0 + (sharpe - 1.0) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S16] Score=%.4f | PF=%.2f | WR=%.1f%% | RR=%.2f | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate * 100, rr_ratio, max_dd_pct, trades, sharpe);
    }
    return score;
}

//+------------------------------------------------------------------+
//| _CountMyPositions                                                |
//+------------------------------------------------------------------+
int _CountMyPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S16_SPIKE) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| _CalcLot: Risk-based lot size                                    |
//+------------------------------------------------------------------+
double _CalcLot(const MqlTick &tick, double sl_price)
{
    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double risk_money = equity * Inp_RiskPct / 100.0;
    double price      = (tick.bid + tick.ask) / 2.0;
    double sl_dist    = MathAbs(price - sl_price);
    if(sl_dist <= 0.0) return 0.0;

    double tick_size  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    if(tick_size <= 0.0 || tick_value <= 0.0) return 0.0;

    double lot_raw  = risk_money / (sl_dist / tick_size * tick_value);
    double lot_min  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double lot_max  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

    double lot = MathFloor(lot_raw / lot_step) * lot_step;
    return MathMax(lot_min, MathMin(lot_max, lot));
}
//+------------------------------------------------------------------+
