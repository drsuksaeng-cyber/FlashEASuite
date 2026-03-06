//+------------------------------------------------------------------+
//| Opt_S14_BBSqueeze.mq5                                            |
//| FlashEASuite V2 — Optimization EA for S14 BB Squeeze Breakout   |
//| Magic: 1014 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S14_BBSqueeze                                   |
//|   Symbol   : EURUSD.tp, XAUUSD.tp                                |
//|   Timeframe: H1 (แนะนำ) หรือ H4                                 |
//|   Model    : Every tick based on real ticks                      |
//|   Period   : 2022.01.01 – 2024.12.31 (3 ปี)                     |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = PF × WinRate × sqrt(Trades) / MaxDD%                  |
//|   เงื่อนไข: Trades >= 20, PF >= 1.0, MaxDD <= 25%               |
//|   Bonus: RR > 1.5 (BB Squeeze คาด breakout ชัด → RR ดี)         |
//+------------------------------------------------------------------+
//| NOTE: S14 GetStopLoss() / GetTakeProfit() คืน absolute prices    |
//|       จาก m_state.last_sl / m_state.last_tp                      |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/Strategies/S14_BBSqueeze.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs                                                  |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per trade
input double   Inp_MinConfidence  = 0.4;    // Min confidence to trade
input int      Inp_MaxPositions   = 1;      // Max concurrent positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// NOTE: S14 strategy parameters (BS_BB_Period, BS_BB_Deviation,
//       BS_KC_Period, BS_KC_ATR_Mult, BS_Squeeze_Min, BS_Breakout_Mom,
//       BS_SL_ATR_Mult, BS_TP_ATR_Mult, BS_ATR_Period, BS_LR_Period)
// come from S14_BBSqueeze.mqh inputs

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CBBSqueeze   g_strategy;
CTrade       g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S14] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    g_trade.SetExpertMagicNumber(MAGIC_S14_BB_SQUEEZE);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S14] Initialized | Symbol=", Symbol(),
          " TF=", EnumToString(Period()),
          " Risk=", Inp_RiskPct, "%");
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

    // ── 1. Analyze ──────────────────────────────────────────────────
    g_strategy.Analyze(tick);

    ENUM_TRADE_SIGNAL signal     = g_strategy.GetSignal();
    double            confidence = g_strategy.GetConfidence();

    // ── 2. Manage existing positions ─────────────────────────────────
    _ManagePositions(tick);

    // ── 3. Check confidence filter ───────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 4. Max positions guard ───────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 5. Get absolute SL/TP from strategy state ────────────────────
    // S14 stores computed absolute prices in m_state after Analyze()
    double sl = g_strategy.GetStopLoss();
    double tp = g_strategy.GetTakeProfit();
    if(sl <= 0.0) return;

    // ── 6. Calculate lot size ────────────────────────────────────────
    double lot = _CalcLot(tick, sl);
    if(lot <= 0.0) return;

    // ── 7. Execute ───────────────────────────────────────────────────
    if(signal == SIGNAL_BUY)
    {
        g_trade.Buy(lot, Symbol(), tick.ask, sl, tp,
                    StringFormat("S14|Conf=%.2f", confidence));
    }
    else if(signal == SIGNAL_SELL)
    {
        g_trade.Sell(lot, Symbol(), tick.bid, sl, tp,
                     StringFormat("S14|Conf=%.2f", confidence));
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| BB Squeeze เน้น: breakout quality — RR ดี, DD ต่ำ              |
//+------------------------------------------------------------------+
double OnTester()
{
    double profit     = TesterStatistics(STAT_PROFIT);
    double pf         = TesterStatistics(STAT_PROFIT_FACTOR);
    double trades     = TesterStatistics(STAT_TRADES);
    double profit_tr  = TesterStatistics(STAT_PROFIT_TRADES);
    double win_rate   = (trades > 0) ? profit_tr / trades : 0.0;
    double max_dd_pct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double sharpe     = TesterStatistics(STAT_SHARPE_RATIO);
    double loss_tr    = TesterStatistics(STAT_LOSS_TRADES);
    double gross_profit = TesterStatistics(STAT_GROSS_PROFIT);
    double gross_loss   = TesterStatistics(STAT_GROSS_LOSS);
    double avg_profit = (profit_tr > 0) ? gross_profit / profit_tr : 0.0;
    double avg_loss   = (loss_tr   > 0) ? MathAbs(gross_loss / loss_tr) : 0.0;
    double rr_ratio   = (avg_loss != 0) ? avg_profit / avg_loss : 1.0;

    // Hard filters
    if(trades   <  20)    return 0.0;
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 25.0) return 0.0;   // BB Squeeze: DD ควรต่ำกว่า Spike
    if(win_rate <  0.35)  return 0.0;

    // Composite score
    double score = pf * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: RR > 1.5 (breakout trade ควรได้ RR ดี)
    if(rr_ratio > 1.5) score *= 1.0 + (rr_ratio - 1.5) * 0.06;

    // Bonus: Sharpe
    if(sharpe > 1.0) score *= 1.0 + (sharpe - 1.0) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S14] Score=%.4f | PF=%.2f | WR=%.1f%% | RR=%.2f | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate*100, rr_ratio, max_dd_pct, trades, sharpe);
    }
    return score;
}

//+------------------------------------------------------------------+
//| _ManagePositions: Close on reverse signal                        |
//+------------------------------------------------------------------+
void _ManagePositions(const MqlTick &tick)
{
    ENUM_TRADE_SIGNAL sig = g_strategy.GetSignal();
    if(sig == SIGNAL_NONE) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S14_BB_SQUEEZE) continue;

        long pos_type = PositionGetInteger(POSITION_TYPE);
        if(sig == SIGNAL_BUY  && pos_type == POSITION_TYPE_SELL)
            g_trade.PositionClose(ticket);
        else if(sig == SIGNAL_SELL && pos_type == POSITION_TYPE_BUY)
            g_trade.PositionClose(ticket);
    }
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S14_BB_SQUEEZE) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| _CalcLot: Risk-based lot size using absolute SL price           |
//+------------------------------------------------------------------+
double _CalcLot(const MqlTick &tick, double sl_price)
{
    double price   = (tick.bid + tick.ask) / 2.0;
    double sl_dist = MathAbs(price - sl_price);
    if(sl_dist <= 0.0) return 0.0;

    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double risk_money = equity * Inp_RiskPct / 100.0;

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
