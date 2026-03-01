//+------------------------------------------------------------------+
//| TransferToGrid.mqh                                               |
//| FlashEASuite V2 — Emergency TransferToGrid() Function           |
//+------------------------------------------------------------------+
//| ฟังก์ชัน Emergency ที่ใช้ร่วมกันระหว่างทุก strategy             |
//| เมื่อเกิดสถานการณ์ฉุกเฉิน (drawdown เกิน, news สำคัญ, ฯลฯ):   |
//|  1. ปิด positions ทุกตัวที่ไม่ใช่ Grid (magic ไม่ใช่ 1015)     |
//|  2. เปิดใช้งาน S15_Grid strategy                               |
//|  3. Log เหตุผลและสถานะ                                         |
//|                                                                  |
//| ✅ Preserved from legacy system                                  |
//| ✅ Thread-safe: ไม่ใช้ global state                             |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#ifndef TRANSFER_TO_GRID_MQH
#define TRANSFER_TO_GRID_MQH

//+------------------------------------------------------------------+
//| ENUM: TransferToGrid trigger reason                              |
//+------------------------------------------------------------------+
enum ENUM_TRANSFER_REASON
{
    TRANSFER_DRAWDOWN        = 0,   // Drawdown exceeded threshold
    TRANSFER_NEWS_EVENT      = 1,   // High-impact news approaching
    TRANSFER_SERVER_COMMAND  = 2,   // Server sent COMMAND=SWITCH_GRID
    TRANSFER_MANUAL          = 3,   // Manual trigger (test/override)
    TRANSFER_STRATEGY_SIGNAL = 4    // Strategy self-triggered
};

//+------------------------------------------------------------------+
//| STRUCT: TransferToGrid result log                                |
//+------------------------------------------------------------------+
struct STransferResult
{
    bool    success;
    int     closed_count;       // Non-grid positions closed
    int     close_failed;       // Positions that failed to close
    double  realized_pnl;       // Total P&L of closed positions
    string  reason_str;
    datetime transfer_time;

    void Reset()
    {
        success       = false;
        closed_count  = 0;
        close_failed  = 0;
        realized_pnl  = 0.0;
        reason_str    = "";
        transfer_time = 0;
    }
};

//+------------------------------------------------------------------+
//| TransferToGrid: Close all non-grid positions and activate Grid   |
//|                                                                  |
//| @param symbol       Trading symbol to filter                     |
//| @param grid_magic   Grid magic number (default 1015)            |
//| @param reason       Why transfer was triggered                   |
//| @param slippage     Order slippage in points (default 10)       |
//| @return STransferResult with outcome details                     |
//+------------------------------------------------------------------+
STransferResult TransferToGrid(string symbol,
                                int grid_magic = 1015,
                                ENUM_TRANSFER_REASON reason = TRANSFER_MANUAL,
                                int slippage = 10)
{
    STransferResult result;
    result.Reset();
    result.transfer_time = TimeCurrent();
    result.reason_str    = _TransferReasonToString(reason);

    Print("╔═══════════════════════════════════════════════╗");
    PrintFormat("║ 🚨 EMERGENCY: TransferToGrid | %s | reason=%s",
                symbol, result.reason_str);
    Print("╚═══════════════════════════════════════════════╝");

    // ── Step 1: Close all non-grid positions for this symbol ─────────
    int total_positions = PositionsTotal();

    for(int i = total_positions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;

        // Filter by symbol
        string pos_symbol = PositionGetString(POSITION_SYMBOL);
        if(pos_symbol != symbol) continue;

        // Skip grid positions
        long pos_magic = PositionGetInteger(POSITION_MAGIC);
        if(pos_magic == grid_magic) continue;

        // Close non-grid position
        double volume   = PositionGetDouble(POSITION_VOLUME);
        double open_pnl = PositionGetDouble(POSITION_PROFIT);
        long   pos_type = PositionGetInteger(POSITION_TYPE);
        double price    = (pos_type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(symbol, SYMBOL_BID)
                          : SymbolInfoDouble(symbol, SYMBOL_ASK);

        MqlTradeRequest req = {};
        MqlTradeResult  res = {};
        req.action     = TRADE_ACTION_DEAL;
        req.symbol     = symbol;
        req.volume     = volume;
        req.type       = (pos_type == POSITION_TYPE_BUY)
                          ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        req.price      = price;
        req.deviation  = slippage;
        req.magic      = pos_magic;
        req.comment    = "TransferToGrid_" + result.reason_str;
        req.type_filling = ORDER_FILLING_IOC;

        bool ok = OrderSend(req, res);
        if(ok && res.retcode == TRADE_RETCODE_DONE)
        {
            PrintFormat("[TransferToGrid] Closed #%d | magic=%d | P&L=%.2f | price=%.5f",
                        ticket, pos_magic, open_pnl, price);
            result.closed_count++;
            result.realized_pnl += open_pnl;
        }
        else
        {
            PrintFormat("[TransferToGrid] ❌ Failed to close #%d | retcode=%d",
                        ticket, res.retcode);
            result.close_failed++;
        }
    }

    // ── Step 2: Summary ──────────────────────────────────────────────
    result.success = (result.close_failed == 0);

    PrintFormat("[TransferToGrid] Done | closed=%d | failed=%d | P&L=%.2f | grid_magic=%d",
                result.closed_count, result.close_failed,
                result.realized_pnl, grid_magic);
    PrintFormat("[TransferToGrid] Grid positions remaining: %d",
                _CountGridPositions(symbol, grid_magic));

    return result;
}

//+------------------------------------------------------------------+
//| TransferToGridByDD: Auto-trigger when drawdown exceeds threshold |
//| @param symbol         Trading symbol                              |
//| @param dd_threshold   Drawdown % to trigger (e.g., 15.0)        |
//| @return true if transfer was triggered                           |
//+------------------------------------------------------------------+
bool TransferToGridByDD(string symbol,
                         double dd_threshold = 15.0,
                         int grid_magic = 1015)
{
    double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double dd_pct     = (balance > 0.0)
                        ? (balance - equity) / balance * 100.0
                        : 0.0;

    if(dd_pct < dd_threshold) return false;

    PrintFormat("[TransferToGrid] DD=%.1f%% exceeds threshold=%.1f%% → Triggering!",
                dd_pct, dd_threshold);

    STransferResult res = TransferToGrid(symbol, grid_magic, TRANSFER_DRAWDOWN);
    return res.success;
}

//+------------------------------------------------------------------+
//| Private helper: Count open grid positions                         |
//+------------------------------------------------------------------+
int _CountGridPositions(string symbol, int grid_magic)
{
    int count = 0;
    int total = PositionsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) == symbol &&
           PositionGetInteger(POSITION_MAGIC) == grid_magic)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Private helper: Reason enum → string                            |
//+------------------------------------------------------------------+
string _TransferReasonToString(ENUM_TRANSFER_REASON reason)
{
    switch(reason)
    {
        case TRANSFER_DRAWDOWN:        return "DRAWDOWN";
        case TRANSFER_NEWS_EVENT:      return "NEWS_EVENT";
        case TRANSFER_SERVER_COMMAND:  return "SERVER_CMD";
        case TRANSFER_MANUAL:          return "MANUAL";
        case TRANSFER_STRATEGY_SIGNAL: return "STRATEGY";
        default:                       return "UNKNOWN";
    }
}

#endif // TRANSFER_TO_GRID_MQH
//+------------------------------------------------------------------+
