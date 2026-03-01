//+------------------------------------------------------------------+
//| TestP12.mq5                                                      |
//| Test S06_KAMA and S10_Turtle                                     |
//| Save at: MQL5\Tester\TestP12.mq5                                 |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "..\include\Logic\Strategies\S06_KAMA.mqh"
#include "..\include\Logic\Strategies\S10_Turtle.mqh"

void OnStart()
{
    Print("========== P1-2 TEST START ==========");

    //--- Test S06 KAMA
    CKAMATrend kama;
    bool ok6 = kama.Init(_Symbol, PERIOD_H1);
    PrintFormat("[S06] Init=%s | Magic=%d | Standalone=%s",
        ok6 ? "OK" : "FAIL",
        kama.GetMagic(),
        kama.IsStandaloneCapable() ? "YES" : "NO");

    if(ok6)
    {
        kama.Enable();
        MqlTick tick;
        SymbolInfoTick(_Symbol, tick);
        kama.Analyze(tick);

        PrintFormat("[S06] KAMA=%.5f | ER=%.3f | ATR=%.5f | Slope=%.6f",
            kama.GetKAMAValue(),
            kama.GetER(),
            kama.GetATR(),
            kama.GetKAMASlope());

        string sig = "NONE";
        if(kama.GetSignal() == SIGNAL_BUY)  sig = "BUY";
        if(kama.GetSignal() == SIGNAL_SELL) sig = "SELL";
        PrintFormat("[S06] Signal=%s | Confidence=%.3f | TP_offset=%.5f | SL_offset=%.5f",
            sig, kama.GetConfidence(), kama.GetTakeProfit(), kama.GetStopLoss());
    }

    Print("-------------------------------------");

    //--- Test S10 Turtle
    CTurtle turtle;
    bool ok10 = turtle.Init(_Symbol, PERIOD_H1);
    PrintFormat("[S10] Init=%s | Magic=%d | Standalone=%s",
        ok10 ? "OK" : "FAIL",
        turtle.GetMagic(),
        turtle.IsStandaloneCapable() ? "YES" : "NO");

    if(ok10)
    {
        turtle.Enable();
        MqlTick tick;
        SymbolInfoTick(_Symbol, tick);
        turtle.Analyze(tick);

        PrintFormat("[S10] EntryHigh=%.5f | EntryLow=%.5f | ExitHigh=%.5f | ExitLow=%.5f",
            turtle.GetEntryHigh(),
            turtle.GetEntryLow(),
            turtle.GetExitHigh(),
            turtle.GetExitLow());

        PrintFormat("[S10] ATR=%.5f | Units=%d | SL_offset=%.5f",
            turtle.GetATR(),
            turtle.GetUnitCount(),
            turtle.GetStopLoss());

        string sig = "NONE";
        if(turtle.GetSignal() == SIGNAL_BUY)  sig = "BUY";
        if(turtle.GetSignal() == SIGNAL_SELL) sig = "SELL";
        PrintFormat("[S10] Signal=%s | Confidence=%.3f", sig, turtle.GetConfidence());
    }

    Print("========== P1-2 TEST END ==========");
}
//+------------------------------------------------------------------+
