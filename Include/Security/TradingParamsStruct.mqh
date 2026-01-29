//+------------------------------------------------------------------+
//|                                          TradingParamsStruct.mqh |
//|                          FlashEASuite V2 - Phase 3               |
//|                          Trading Parameters Structure            |
//+------------------------------------------------------------------+

#property copyright "Dr. Suksaeng Kukanok"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| TradingParams Structure                                          |
//| Must match C++ DLL structure EXACTLY                             |
//+------------------------------------------------------------------+
struct TradingParams
  {
   double            lot_size;          // Calculated lot size
   double            grid_step;         // Grid step in points
   int               max_orders;        // Maximum orders allowed
   double            tp_points;         // Take Profit in points
   double            sl_points;         // Stop Loss in points
   uint              checksum;          // Encrypted checksum for validation
  };

//+------------------------------------------------------------------+
//| Initialize TradingParams to safe defaults                        |
//+------------------------------------------------------------------+
void InitTradingParams(TradingParams &params)
  {
   params.lot_size = 0.0;
   params.grid_step = 0.0;
   params.max_orders = 0;
   params.tp_points = 0.0;
   params.sl_points = 0.0;
   params.checksum = 0;
  }

//+------------------------------------------------------------------+
//| Print TradingParams for debugging                                |
//+------------------------------------------------------------------+
void PrintTradingParams(const TradingParams &params)
  {
   Print("═══════════════════════════════════════════════════════════");
   Print("  Trading Parameters");
   Print("═══════════════════════════════════════════════════════════");
   Print("📊 Lot Size:      ", DoubleToString(params.lot_size, 2));
   Print("📏 Grid Step:     ", DoubleToString(params.grid_step, 1), " points");
   Print("🔢 Max Orders:    ", params.max_orders);
   Print("🎯 TP Points:     ", DoubleToString(params.tp_points, 1));
   Print("🛡️ SL Points:     ", DoubleToString(params.sl_points, 1));
   Print("✅ Checksum:      ", params.checksum);
   Print("═══════════════════════════════════════════════════════════");
  }

//+------------------------------------------------------------------+
