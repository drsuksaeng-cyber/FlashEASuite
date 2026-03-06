//+------------------------------------------------------------------+
//| Opt_S15_Grid.mq5                                                 |
//| FlashEASuite V2 — Optimization EA for S15 Immortal Grid         |
//| Magic: 1015 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S15_Grid                                        |
//|   Symbol   : EURUSD.tp, AUDUSD.tp, AUDCAD.tp, NZDUSD.tp         |
//|   Timeframe: H1 (แนะนำ) หรือ H4                                 |
//|   Model    : Every tick based on real ticks (จำเป็น!)            |
//|   Period   : 2022.01.01 – 2024.12.31 (3 ปี)                     |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = PF × WinRate × sqrt(Trades) / MaxDD%                  |
//|   เงื่อนไข: Trades >= 30, PF >= 1.0, MaxDD <= 20%               |
//|   Grid เน้น: DD ต่ำ + consistent income (WinRate bonus)          |
//+------------------------------------------------------------------+
//| NOTE: S15 uses ManagePositions() for hidden TP/SL management     |
//|       lot sizing uses ATR14 as SL distance proxy                 |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/Strategies/S15_Grid.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs                                                  |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 0.5;    // Risk % per trade (Grid: ใช้น้อย)
input double   Inp_MinConfidence  = 0.3;    // Min confidence to open
input int      Inp_MaxPositions   = 5;      // Max grid positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// S15-specific hidden TP/SL config
input double   Inp_TP_ATR_Mult    = 2.0;   // Hidden TP = N × ATR14
input double   Inp_SL_ATR_Mult    = 1.5;   // Hidden SL = N × ATR14
input bool     Inp_TrailEnabled   = false;  // Enable trailing stop

// NOTE: S15 GridCore parameters come from GridCore.mqh inputs
// (grid level spacing, direction bias, etc.)

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CS15Grid   g_strategy;
CTrade     g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S15] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    // Configure hidden TP/SL
    g_strategy.SetTPSLConfig(
        Inp_TP_ATR_Mult,
        Inp_SL_ATR_Mult,
        Inp_TrailEnabled
    );

    g_trade.SetExpertMagicNumber(MAGIC_S15_GRID);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S15] Initialized | Symbol=", Symbol(),
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

    // ── 1. Analyze + ManagePositions (hidden TP/SL + trailing) ──────
    g_strategy.Analyze(tick);
    g_strategy.ManagePositions(tick);

    ENUM_TRADE_SIGNAL signal     = g_strategy.GetSignal();
    double            confidence = g_strategy.GetConfidence();

    // ── 2. Confidence filter ─────────────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 3. Max positions guard ───────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 4. Lot sizing — use ATR14 as SL proxy for risk calc ─────────
    // Grid doesn't have a fixed broker SL; hidden SL = Inp_SL_ATR_Mult × ATR14
    // We need ATR14 to compute sl_dist for lot calculation
    double atr14 = _GetATR14();
    if(atr14 <= 0.0) return;

    double sl_dist = Inp_SL_ATR_Mult * atr14;
    double sl_price = (signal == SIGNAL_BUY)
                      ? tick.ask - sl_dist
                      : tick.bid + sl_dist;

    double lot = _CalcLot(tick, sl_price);
    if(lot <= 0.0) return;

    // ── 5. Execute (broker SL=0, hidden SL managed by ManagePositions) ─
    if(signal == SIGNAL_BUY)
    {
        g_trade.Buy(lot, Symbol(), tick.ask, 0.0, 0.0,
                    StringFormat("S15|Conf=%.2f|ATR=%.5f", confidence, atr14));
    }
    else if(signal == SIGNAL_SELL)
    {
        g_trade.Sell(lot, Symbol(), tick.bid, 0.0, 0.0,
                     StringFormat("S15|Conf=%.2f|ATR=%.5f", confidence, atr14));
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| Grid เน้น: ความสม่ำเสมอ + DD ต่ำ + Win rate สูง               |
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

    // Hard filters — Grid: DD threshold เข้มงวดกว่า
    if(trades   <  30)    return 0.0;
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 20.0) return 0.0;   // Grid ต้อง DD < 20%
    if(win_rate <  0.50)  return 0.0;   // Grid ควร WR สูง

    // Composite score — Grid เน้น WinRate มากกว่า RR
    double score = pf * win_rate * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: WinRate > 65% (Grid ideal zone)
    if(win_rate > 0.65) score *= 1.0 + (win_rate - 0.65) * 0.5;

    // Bonus: Sharpe > 1.5 (Grid income-like)
    if(sharpe > 1.5) score *= 1.0 + (sharpe - 1.5) * 0.15;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S15] Score=%.4f | PF=%.2f | WR=%.1f%% | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate*100, max_dd_pct, trades, sharpe);
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S15_GRID) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| _GetATR14: ATR(14) for current symbol/tf                        |
//+------------------------------------------------------------------+
double _GetATR14()
{
    int atr_handle = iATR(Symbol(), Period(), 14);
    if(atr_handle == INVALID_HANDLE) return 0.0;

    double atr_buf[1];
    if(CopyBuffer(atr_handle, 0, 1, 1, atr_buf) <= 0) return 0.0;
    IndicatorRelease(atr_handle);
    return atr_buf[0];
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
