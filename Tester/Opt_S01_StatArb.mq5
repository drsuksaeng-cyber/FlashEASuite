//+------------------------------------------------------------------+
//| Opt_S01_StatArb.mq5                                              |
//| FlashEASuite V2 — Optimization EA for S01 Statistical Arbitrage  |
//| Magic: 1001 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S01_StatArb                                     |
//|   Symbol   : EURUSD.tp (Pair A — EA trades this chart symbol)    |
//|   Timeframe: H1 (แนะนำ) หรือ M30                                |
//|   Model    : Every tick based on real ticks                      |
//|   Period   : 2022.01.01 – 2024.12.31 (3 ปี)                     |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = PF × WinRate × sqrt(Trades) / MaxDD%                  |
//|   เงื่อนไข: Trades >= 25, PF >= 1.0, MaxDD <= 20%               |
//|   Stat Arb เน้น: WinRate สูง (mean reversion → ควร win บ่อย)   |
//+------------------------------------------------------------------+
//| NOTE: S01 GetStopLoss() / GetTakeProfit() คืน absolute prices    |
//|       StatArb_Pair2 = correlated pair (ใช้ราคาคำนวณ Z-score)    |
//|       In tester mode: strategy works on chart symbol (Pair A)    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs (declared FIRST so they appear before StatArb    |
//| string inputs in the tester — prevents strings from breaking Y   |
//| flags on RiskPct / MinConfidence)                                |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per trade
input double   Inp_MinConfidence  = 0.4;    // Min confidence to trade
input int      Inp_MaxPositions   = 1;      // Max concurrent positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// S01 inputs (StatArb_Period/EntryZ/StopZ/Pair1/Pair2) come from
// S01_StatArb.mqh — included AFTER EA inputs so string params land last
#include "../Include/Logic/Strategies/S01_StatArb.mqh"

// NOTE: S01 strategy parameters come from S01_StatArb.mqh inputs:
//   StatArb_Period  : Z-Score lookback period
//   StatArb_EntryZ  : Z-Score threshold for entry (default 2.0)
//   StatArb_StopZ   : Z-Score threshold for emergency exit (default 3.0)
//   StatArb_Pair1   : Pair A symbol (default "EURUSD")
//   StatArb_Pair2   : Pair B symbol (default "GBPUSD")
//
// IMPORTANT: Set StatArb_Pair1 to match the chart symbol (e.g. "EURUSD")
//            Set StatArb_Pair2 to a highly correlated pair (e.g. "GBPUSD")
//            If using broker suffix, set full symbol name (e.g. "EURUSD.tp")

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CStatArb   g_strategy;
CTrade     g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S01] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    g_trade.SetExpertMagicNumber(MAGIC_S01_STAT_ARB);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S01] Initialized | Symbol=", Symbol(),
          " TF=", EnumToString(Period()),
          " Pair1=", StatArb_Pair1, " Pair2=", StatArb_Pair2);
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

    // ── 1. Analyze (S01 fetches Pair2 price internally) ─────────────
    g_strategy.Analyze(tick);

    ENUM_TRADE_SIGNAL signal     = g_strategy.GetSignal();
    double            confidence = g_strategy.GetConfidence();

    // ── 2. Manage existing positions ─────────────────────────────────
    _ManagePositions(tick);

    // ── 3. Confidence filter ─────────────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 4. Max positions guard ───────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 5. Get absolute SL/TP from strategy state ────────────────────
    // S01 stores computed absolute prices in m_state after Analyze()
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
                    StringFormat("S01|Conf=%.2f", confidence));
    }
    else if(signal == SIGNAL_SELL)
    {
        g_trade.Sell(lot, Symbol(), tick.bid, sl, tp,
                     StringFormat("S01|Conf=%.2f", confidence));
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| Stat Arb เน้น: WinRate สูง + DD ต่ำ (mean reversion ควร win บ่อย)|
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

    // Hard filters — Stat Arb: DD เข้มงวด, WR ต้องสูง
    if(trades   <  25)    return 0.0;
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 20.0) return 0.0;   // Stat Arb ควร DD ต่ำ
    if(win_rate <  0.50)  return 0.0;   // Mean reversion ควร WR > 50%

    // Composite score — Stat Arb เน้น WinRate × PF
    double score = pf * win_rate * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: WinRate > 60%
    if(win_rate > 0.60) score *= 1.0 + (win_rate - 0.60) * 0.4;

    // Bonus: Sharpe > 1.5
    if(sharpe > 1.5) score *= 1.0 + (sharpe - 1.5) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S01] Score=%.4f | PF=%.2f | WR=%.1f%% | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate*100, max_dd_pct, trades, sharpe);
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S01_STAT_ARB) continue;

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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S01_STAT_ARB) continue;
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
