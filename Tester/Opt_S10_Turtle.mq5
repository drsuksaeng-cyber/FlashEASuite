//+------------------------------------------------------------------+
//| Opt_S10_Turtle.mq5                                               |
//| FlashEASuite V2 — Optimization EA for S10 Turtle Trading        |
//| Magic: 1010 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S10_Turtle                                      |
//|   Symbol   : XAUUSD.tp, USDJPY.tp, EURUSD.tp                    |
//|   Timeframe: H4 (แนะนำ) หรือ D1                                 |
//|   Model    : Every tick based on real ticks                      |
//|   Period   : 2022.01.01 – 2024.12.31 (3 ปี)                     |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = PF × WinRate × sqrt(Trades) / MaxDD%                  |
//|   เงื่อนไข: Trades >= 15, PF >= 1.0, MaxDD <= 30%               |
//|   Bonus: RR > 3.0 (Turtle classic: ตัด loss เร็ว กำไรให้วิ่ง)  |
//+------------------------------------------------------------------+
//| NOTE: S10 GetStopLoss() = 2*ATR offset (ไม่ใช่ absolute price)  |
//|       S10 GetTakeProfit() = 0.0 — ใช้ ShouldExit() (Donchian)   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/Strategies/S10_Turtle.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs                                                  |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per unit (Turtle unit sizing)
input double   Inp_MinConfidence  = 0.4;    // Min confidence for entry
input int      Inp_MaxPositions   = 4;      // Max units (matches Turtle_MaxUnits)
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// NOTE: S10 strategy parameters (Turtle_EntryPeriod, Turtle_ExitPeriod,
//       Turtle_ATR_Period, Turtle_BreakoutBuf, Turtle_MaxUnits,
//       Turtle_UnitSpacing, Turtle_RiskPct) come from S10_Turtle.mqh
// OPTIMIZED: Pass23 XAUUSD H4 (2022-2024) — Entry=20 Exit=20 Buf=0.1 | Profit=3091 DD=27.8%

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CTurtle   g_strategy;
CTrade    g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S10] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    g_trade.SetExpertMagicNumber(MAGIC_S10_TURTLE);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S10] Initialized | Symbol=", Symbol(),
          " TF=", EnumToString(Period()),
          " Risk/unit=", Inp_RiskPct, "%");
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

    // ── 2. Donchian exit — check all open positions ──────────────────
    // ShouldExit() checks if price crossed Donchian exit channel
    if(g_strategy.GetDirection() != SIGNAL_NONE && g_strategy.ShouldExit())
    {
        _CloseAllMyPositions("DONCHIAN_EXIT");
    }

    // ── 3. Signal filter ─────────────────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 4. Max units guard ────────────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 5. S10 GetStopLoss() = 2*ATR offset, GetTakeProfit() = 0.0 ──
    double sl_offset = g_strategy.GetStopLoss();   // 2 * ATR
    if(sl_offset <= 0.0) return;

    double sl_price;
    if(signal == SIGNAL_BUY)
        sl_price = tick.ask - sl_offset;
    else
        sl_price = tick.bid + sl_offset;

    // ── 6. Calculate lot size ────────────────────────────────────────
    double lot = _CalcLot(tick, sl_offset);
    if(lot <= 0.0) return;

    // ── 7. Execute (no broker TP — Donchian exit manages close) ─────
    if(signal == SIGNAL_BUY)
    {
        g_trade.Buy(lot, Symbol(), tick.ask, sl_price, 0.0,
                    StringFormat("S10|Unit=%d|ATR=%.5f|Conf=%.2f",
                                 g_strategy.GetUnitCount()+1,
                                 g_strategy.GetATR(), confidence));
    }
    else if(signal == SIGNAL_SELL)
    {
        g_trade.Sell(lot, Symbol(), tick.bid, sl_price, 0.0,
                     StringFormat("S10|Unit=%d|ATR=%.5f|Conf=%.2f",
                                  g_strategy.GetUnitCount()+1,
                                  g_strategy.GetATR(), confidence));
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| Turtle เน้น: RR สูง (ตัด loss เร็ว ปล่อยกำไรวิ่ง)             |
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

    // Hard filters — Turtle: fewer trades on higher TF, WR ต่ำได้ถ้า RR ดี
    if(trades   <  15)    return 0.0;
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 30.0) return 0.0;
    // WR filter removed — Turtle pyramid WR=15-25% is normal; PF>=1.0 is sufficient quality gate

    // Composite score
    double score = pf * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: RR > 3.0 — Turtle "let profits run" principle
    if(rr_ratio > 3.0) score *= 1.0 + (rr_ratio - 3.0) * 0.10;

    // Bonus: Sharpe
    if(sharpe > 1.0) score *= 1.0 + (sharpe - 1.0) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S10] Score=%.4f | PF=%.2f | WR=%.1f%% | RR=%.2f | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate*100, rr_ratio, max_dd_pct, trades, sharpe);
    }
    return score;
}

//+------------------------------------------------------------------+
//| _CloseAllMyPositions                                             |
//+------------------------------------------------------------------+
void _CloseAllMyPositions(string reason)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S10_TURTLE) continue;
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S10_TURTLE) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| _CalcLot: Risk-based lot size using ATR offset as SL distance   |
//+------------------------------------------------------------------+
double _CalcLot(const MqlTick &tick, double sl_dist)
{
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
