//+------------------------------------------------------------------+
//| Opt_S06_KAMA.mq5                                                 |
//| FlashEASuite V2 — Optimization EA for S06 KAMA Adaptive Trend   |
//| Magic: 1006 | Mode: Strategy Tester Optimization                 |
//+------------------------------------------------------------------+
//| วิธีใช้ใน Strategy Tester:                                        |
//|   Expert   : Opt_S06_KAMA                                        |
//|   Symbol   : EURUSD.tp, GBPUSD.tp, USDJPY.tp                    |
//|   Timeframe: H1 (แนะนำ) หรือ H4                                 |
//|   Model    : Every tick based on real ticks (ดีที่สุด)           |
//|   Period   : 2022.01.01 – 2024.12.31 (3 ปี)                     |
//|   Optimize : Custom max (OnTester criterion)                     |
//|   Deposit  : 10,000 USD                                          |
//+------------------------------------------------------------------+
//| Optimization Criterion (OnTester):                               |
//|   score = PF × WinRate × sqrt(Trades) / MaxDD%                  |
//|   เงื่อนไข: Trades >= 20, PF >= 1.0, MaxDD <= 30%               |
//|   Bonus: RR > 2.0 (KAMA เน้นให้กำไรต่อ trade สูง)              |
//+------------------------------------------------------------------+
//| NOTE: S06 GetStopLoss() / GetTakeProfit() คืนค่า ATR offset      |
//|       (ไม่ใช่ absolute price) — EA จะคำนวณ absolute price เอง   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "../Include/Logic/IStrategy.mqh"
#include "../Include/Logic/StrategyConstants.mqh"
#include "../Include/Logic/Strategies/S06_KAMA.mqh"

//+------------------------------------------------------------------+
//| EA-level inputs                                                  |
//+------------------------------------------------------------------+
input double   Inp_RiskPct        = 1.0;    // Risk % per trade
input double   Inp_MinConfidence  = 0.3;    // Min confidence to trade (0.0=off)
input int      Inp_MaxPositions   = 1;      // Max concurrent positions
input int      Inp_Slippage       = 10;     // Slippage points
input bool     Inp_UseOnTester    = true;   // Print OnTester score
input bool     Inp_UseKAMAExit    = true;   // Use KAMA crossback exit (ShouldExit)

// NOTE: S06 strategy parameters (KAMA_Period, KAMA_Fast, KAMA_Slow,
//       KAMA_ER_Thresh, KAMA_TP_ATR, KAMA_SL_ATR, KAMA_ATR_Period)
// come from S06_KAMA.mqh inputs — they appear automatically
// in Strategy Tester parameter list

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CKAMATrend   g_strategy;
CTrade       g_trade;

// Track open position direction for KAMA exit check
ENUM_TRADE_SIGNAL g_open_direction = SIGNAL_NONE;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!g_strategy.Init(Symbol(), Period()))
    {
        Print("[OPT-S06] ERROR: Strategy Init failed");
        return INIT_FAILED;
    }

    // ★ CRITICAL: Enable strategy — m_enabled defaults to false
    g_strategy.Enable();

    g_trade.SetExpertMagicNumber(MAGIC_S06_KAMA);
    g_trade.SetDeviationInPoints(Inp_Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.LogLevel(LOG_LEVEL_NO);

    Print("[OPT-S06] Initialized | Symbol=", Symbol(),
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

    // ── 2. KAMA crossback exit (optional) ───────────────────────────
    if(Inp_UseKAMAExit && g_open_direction != SIGNAL_NONE)
    {
        if(g_strategy.ShouldExit(g_open_direction))
            _CloseAllMyPositions("KAMA_EXIT");
    }

    // ── 3. Check confidence filter ───────────────────────────────────
    if(signal == SIGNAL_NONE) return;
    if(confidence < Inp_MinConfidence) return;

    // ── 4. Max positions guard ───────────────────────────────────────
    if(_CountMyPositions() >= Inp_MaxPositions) return;

    // ── 5. Get SL/TP — S06 returns ATR OFFSETS (not absolute prices) ─
    double sl_offset = g_strategy.GetStopLoss();    // e.g. 1.0 * ATR
    double tp_offset = g_strategy.GetTakeProfit();  // e.g. 3.0 * ATR
    if(sl_offset <= 0.0) return;

    double sl_price, tp_price;
    if(signal == SIGNAL_BUY)
    {
        sl_price = tick.ask - sl_offset;
        tp_price = (tp_offset > 0.0) ? tick.ask + tp_offset : 0.0;
    }
    else
    {
        sl_price = tick.bid + sl_offset;
        tp_price = (tp_offset > 0.0) ? tick.bid - tp_offset : 0.0;
    }

    // ── 6. Calculate lot size ────────────────────────────────────────
    double lot = _CalcLot(tick, sl_offset);
    if(lot <= 0.0) return;

    // ── 7. Execute ───────────────────────────────────────────────────
    if(signal == SIGNAL_BUY)
    {
        if(g_trade.Buy(lot, Symbol(), tick.ask, sl_price, tp_price,
                       StringFormat("S06|Conf=%.2f|ER=%.2f", confidence, g_strategy.GetER())))
        {
            g_open_direction = SIGNAL_BUY;
        }
    }
    else if(signal == SIGNAL_SELL)
    {
        if(g_trade.Sell(lot, Symbol(), tick.bid, sl_price, tp_price,
                        StringFormat("S06|Conf=%.2f|ER=%.2f", confidence, g_strategy.GetER())))
        {
            g_open_direction = SIGNAL_SELL;
        }
    }
}

//+------------------------------------------------------------------+
//| OnTester: Custom optimization criterion                          |
//| KAMA Trend เน้น: กำไรต่อ trade สูง (RR), DD ต่ำ               |
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
    if(trades   <  20)    return 0.0;   // Trend strategy: fewer trades OK
    if(profit   <= 0.0)   return 0.0;
    if(pf       <  1.0)   return 0.0;
    if(max_dd_pct > 30.0) return 0.0;
    // WR filter removed — KAMA trend WR=20-30% is normal; PF>=1.0 is sufficient quality gate

    // Composite score
    double score = pf * win_rate * MathSqrt(trades) / MathMax(max_dd_pct, 1.0);

    // Bonus: RR > 2.0 (KAMA เน้นให้ get big runs)
    if(rr_ratio > 2.0) score *= 1.0 + (rr_ratio - 2.0) * 0.08;

    // Bonus: Sharpe
    if(sharpe > 1.0) score *= 1.0 + (sharpe - 1.0) * 0.1;

    if(Inp_UseOnTester)
    {
        PrintFormat("[OPT-S06] Score=%.4f | PF=%.2f | WR=%.1f%% | RR=%.2f | DD=%.1f%% | Trades=%.0f | ER_Exit=%s",
                    score, pf, win_rate*100, rr_ratio, max_dd_pct, trades,
                    Inp_UseKAMAExit ? "ON" : "OFF");
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S06_KAMA) continue;
        g_trade.PositionClose(ticket);
    }
    g_open_direction = SIGNAL_NONE;
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
        if(PositionGetInteger(POSITION_MAGIC) != MAGIC_S06_KAMA) continue;
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
