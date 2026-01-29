//+------------------------------------------------------------------+
//|                                                 TradingParams.h |
//|                          FlashEASuite V2 - Phase 3               |
//|                          Trading Parameters Structure            |
//+------------------------------------------------------------------+

#ifndef TRADINGPARAMS_H
#define TRADINGPARAMS_H

//+------------------------------------------------------------------+
//| TradingParams Structure                                          |
//| Must match MQL5 structure EXACTLY                                |
//+------------------------------------------------------------------+
#pragma pack(push, 1)  // Ensure exact memory layout match with MQL5

struct TradingParams
{
    double lot_size;          // Calculated lot size
    double grid_step;         // Grid step in points
    int max_orders;           // Maximum orders allowed
    double tp_points;         // Take Profit in points
    double sl_points;         // Stop Loss in points
    unsigned int checksum;    // Encrypted checksum for validation
};

#pragma pack(pop)

#endif // TRADINGPARAMS_H
