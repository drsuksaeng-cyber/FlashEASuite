//+------------------------------------------------------------------+
//| Opt_S07_MeanRev.mq5                                              |
//| FlashEASuite V2 — Optimization EA for S07 Mean Reversion        |
//| Magic: 1007 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S07_MeanRev                                     |
//|   Symbol   : XAUUSD.tp (หรือ symbol broker ของคุณ)              |
//|   Timeframe: H1 (แนะนำ) หรือ M15                                |
//|   Model    : Every tick based on real ticks (ดีที่สุด)           |
//|   Period   : 2023.01.01 – 2024.12.31 (2 ปี)                     |
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
#include "../Include/Logic/Strategies/S07_MeanReversion.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs (trade management)                               |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per trade
input double   Inp_MinConfidence  = 0.3;    // Min confidence to trade (0.0=off)
input int      Inp_MaxPositions   = 1;      // Max concurrent positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score

// NOTE: S07 strategy parameters (MR_RSI_Period, MR_RSI_Buy etc.)
// come from S07_MeanReversion.mqh inputs — they appear automatically
// in Strategy Tester parameter list

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CMeanReversion  g_strategy;
CTrade          g_trade;
int             g_pos_total = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize strategy
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S07] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — without this Analyze() returns immediately
    // IStrategy::m_enabled defaults to false, must call Enable() explicitly
    // (In live system, StrategyManager calls Enable() after CONFIG_PUSH)
    g_strategy.Enable();

    // Trade object setup
    g_trade.SetExpertMagicNumber(MAGIC_S07_MEAN_REV);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);  // Quiet in optimization

    Print("[OPT-S07] Initialized | Symbol=", Symbol(),
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
    int my_pos = _CountMyPositions();
    if(my_pos >= Inp_MaxPositions) return;

    // ── 5. Get SL/TP from strategy state ─────────────────────────────
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
                    StringFormat("S07|Conf=%.2f", confidence));
    }
    else if(signal == SIGNAL_SELL)
    {
        g_trade.Sell(lot, Symbol(), tick.bid, sl, tp,
                     StringFormat("S07|Conf=%.2f", confidence));
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| Return > 0 for valid result, higher = better                     |
//+------------------------------------------------------------------+
double OnTester()
{
    // --- Fetch backtest statistics ---
    double profit       = TesterStatistics(STAT_PROFIT);
    double pf           = TesterStatistics(STAT_PROFIT_FACTOR);
    double win_rate     = TesterStatistics(STAT_TRADES) > 0
                          ? TesterStatistics(STAT_PROFIT_TRADES) / TesterStatistics(STAT_TRADES)
                          : 0.0;
    double max_dd_pct   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);  // %
    double trades       = TesterStatistics(STAT_TRADES);
    double sharpe       = TesterStatistics(STAT_SHARPE_RATIO);

    // --- Hard filters: discard bad results ---
    if(trades   <  30)    return 0.0;   // ต้องมี trade อย่างน้อย 30
    if(profit   <= 0.0)   return 0.0;   // ต้องกำไร
    if(pf       <  1.0)   return 0.0;   // PF ต้องมากกว่า 1
    if(max_dd_pct > 30.0) return 0.0;   // DD ห้ามเกิน 30%
    if(win_rate <  0.35)  return 0.0;   // Win rate ต้องมากกว่า 35%

    // --- Composite score ---
    // PF × WinRate × √Trades / MaxDD%
    double score = pf * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: Sharpe > 1.0
    if(sharpe > 1.0) score *= 1.0 + (sharpe - 1.0) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S07] Score=%.4f | PF=%.2f | WR=%.1f%% | DD=%.1f%% | Trades=%.0f | Sharpe=%.2f",
                    score, pf, win_rate * 100, max_dd_pct, trades, sharpe);
    }
    return score;
}

//+------------------------------------------------------------------+
//| _ManagePositions: Check existing S07 positions for exit          |
//+------------------------------------------------------------------+
void _ManagePositions(const MqlTick &tick)
{
    // Strategy handles SL/TP via broker orders
    // Additional: close if reverse signal and already in opposite position
    if(g_strategy.GetSignal() == SIGNAL_NONE) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S07_MEAN_REV) continue;

        long pos_type = PositionGetInteger(POSITION_TYPE);

        // Close on reverse signal
        if(g_strategy.GetSignal() == SIGNAL_BUY  && pos_type == POSITION_TYPE_SELL)
            g_trade.PositionClose(ticket);
        else if(g_strategy.GetSignal() == SIGNAL_SELL && pos_type == POSITION_TYPE_BUY)
            g_trade.PositionClose(ticket);
    }
}

//+------------------------------------------------------------------+
//| _CountMyPositions: Count open positions for this EA              |
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S07_MEAN_REV) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| _CalcLot: Risk-based lot size                                    |
//+------------------------------------------------------------------+
double _CalcLot(const MqlTick &tick, double sl_price)
{
    double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double risk_money     = account_equity * Inp_RiskPct / 100.0;

    double price    = (tick.bid + tick.ask) / 2.0;
    double sl_dist  = MathAbs(price - sl_price);
    if(sl_dist <= 0.0) return 0.0;

    double tick_size  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    if(tick_size <= 0.0 || tick_value <= 0.0) return 0.0;

    double lot_raw  = risk_money / (sl_dist / tick_size * tick_value);
    double lot_min  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double lot_max  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

    double lot = MathFloor(lot_raw / lot_step) * lot_step;
    lot = MathMax(lot_min, MathMin(lot_max, lot));

    return lot;
}
//+------------------------------------------------------------------+
