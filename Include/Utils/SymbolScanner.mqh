//+------------------------------------------------------------------+
//|                                            Utils/SymbolScanner.mqh |
//|                                      FlashEASuite V2 - Program C |
//|                Multi-Symbol Scanner for Grid Trading Strategy     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| Symbol Information Structure                                      |
//+------------------------------------------------------------------+
struct SymbolInfo
  {
   string            symbol;              // Symbol name
   bool              is_active;           // Active in Market Watch
   bool              is_tradeable;        // Can be traded
   double            spread_points;       // Current spread in points
   double            spread_percent;      // Spread as % of price
   double            tick_value;          // Tick value in account currency
   double            tick_size;           // Minimum price change
   long              trade_mode;          // Trading mode
   double            volume_min;          // Minimum volume
   double            volume_max;          // Maximum volume
   double            volume_step;         // Volume step
   datetime          last_update;         // Last update time
   
   // Market conditions
   double            volatility;          // ATR-based volatility
   double            current_price;       // Current bid/ask average
   int               session;             // 0=Asian, 1=European, 2=American
   
   // Constructor
   void SymbolInfo()
     {
      symbol = "";
      is_active = false;
      is_tradeable = false;
      spread_points = 0.0;
      spread_percent = 0.0;
      tick_value = 0.0;
      tick_size = 0.0;
      trade_mode = 0;
      volume_min = 0.0;
      volume_max = 0.0;
      volume_step = 0.0;
      last_update = 0;
      volatility = 0.0;
      current_price = 0.0;
      session = 0;
     }
  };

//+------------------------------------------------------------------+
//| Class: CSymbolScanner                                            |
//| Scans and manages multiple symbols for trading                   |
//+------------------------------------------------------------------+
class CSymbolScanner
  {
private:
   SymbolInfo        m_symbols[];         // Array of scanned symbols
   int               m_symbol_count;      // Number of active symbols
   datetime          m_last_scan_time;    // Last full scan time
   int               m_rescan_interval;   // Rescan interval in seconds (default: 300 = 5 min)
   
   // Filtering criteria
   double            m_max_spread_percent;    // Maximum spread % (default: 0.1% = 10 pips on EURUSD)
   double            m_min_volatility;        // Minimum ATR for trading
   bool              m_forex_only;            // Only forex pairs
   bool              m_major_pairs_only;      // Only major pairs
   
   // Helper methods
   bool              IsSymbolValid(string symbol);
   bool              GetSymbolData(string symbol, SymbolInfo &info);
   double            CalculateVolatility(string symbol);
   int               GetTradingSession();
   bool              IsMajorPair(string symbol);

public:
                     CSymbolScanner();
                    ~CSymbolScanner();
   
   // Configuration
   void              SetRescanInterval(int seconds) { m_rescan_interval = seconds; }
   void              SetMaxSpreadPercent(double percent) { m_max_spread_percent = percent; }
   void              SetMinVolatility(double atr) { m_min_volatility = atr; }
   void              SetForexOnly(bool flag) { m_forex_only = flag; }
   void              SetMajorPairsOnly(bool flag) { m_major_pairs_only = flag; }
   
   // Main scanning methods
   bool              ScanMarketWatch();
   bool              ScanAllSymbols();
   void              UpdateSymbolInfo(string symbol);
   
   // Query methods
   int               GetSymbolCount() const { return m_symbol_count; }
   bool              IsSymbolActive(string symbol);
   bool              IsSymbolTradeable(string symbol);
   void              GetSymbols(string &symbols[]);
   bool              GetSymbolInfo(string symbol, SymbolInfo &info);
   
   // Analysis methods
   void              PrintScanResults();
   string            GetBestSymbol();  // Get symbol with best conditions
  };

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSymbolScanner::CSymbolScanner()
  {
   m_symbol_count = 0;
   m_last_scan_time = 0;
   m_rescan_interval = 300;  // 5 minutes
   
   // Default filtering
   m_max_spread_percent = 0.1;  // 0.1% = 10 pips on EURUSD
   m_min_volatility = 0.0001;   // Minimum ATR
   m_forex_only = true;
   m_major_pairs_only = false;
   
   ArrayResize(m_symbols, 0);
  }

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSymbolScanner::~CSymbolScanner()
  {
   ArrayFree(m_symbols);
  }

//+------------------------------------------------------------------+
//| Scan Market Watch for Active Symbols                             |
//+------------------------------------------------------------------+
bool CSymbolScanner::ScanMarketWatch()
  {
   Print("[Scanner] 🔍 Scanning Market Watch...");
   
   ArrayResize(m_symbols, 0);
   m_symbol_count = 0;
   
   int total = SymbolsTotal(true);  // true = only Market Watch symbols
   Print("[Scanner] Found ", total, " symbols in Market Watch");
   
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, true);
      
      if(symbol == "" || !IsSymbolValid(symbol))
         continue;
      
      SymbolInfo info;
      if(GetSymbolData(symbol, info))
        {
         if(info.is_tradeable)
           {
            // Add to array
            int size = ArraySize(m_symbols);
            ArrayResize(m_symbols, size + 1);
            m_symbols[size] = info;
            m_symbol_count++;
            
            Print("[Scanner] ✅ ", symbol, 
                  " | Spread: ", DoubleToString(info.spread_percent, 3), "%",
                  " | Vol: ", DoubleToString(info.volatility, 5));
           }
        }
     }
   
   m_last_scan_time = TimeCurrent();
   
   Print("[Scanner] ✅ Scan complete: ", m_symbol_count, " tradeable symbols");
   return (m_symbol_count > 0);
  }

//+------------------------------------------------------------------+
//| Scan All Available Symbols (not just Market Watch)               |
//+------------------------------------------------------------------+
bool CSymbolScanner::ScanAllSymbols()
  {
   Print("[Scanner] 🔍 Scanning ALL symbols...");
   
   ArrayResize(m_symbols, 0);
   m_symbol_count = 0;
   
   int total = SymbolsTotal(false);  // false = all symbols
   Print("[Scanner] Found ", total, " total symbols");
   
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, false);
      
      if(symbol == "" || !IsSymbolValid(symbol))
         continue;
      
      SymbolInfo info;
      if(GetSymbolData(symbol, info))
        {
         if(info.is_tradeable)
           {
            int size = ArraySize(m_symbols);
            ArrayResize(m_symbols, size + 1);
            m_symbols[size] = info;
            m_symbol_count++;
           }
        }
     }
   
   m_last_scan_time = TimeCurrent();
   Print("[Scanner] ✅ Scan complete: ", m_symbol_count, " tradeable symbols");
   return (m_symbol_count > 0);
  }

//+------------------------------------------------------------------+
//| Update Single Symbol Info                                        |
//+------------------------------------------------------------------+
void CSymbolScanner::UpdateSymbolInfo(string symbol)
  {
   for(int i = 0; i < m_symbol_count; i++)
     {
      if(m_symbols[i].symbol == symbol)
        {
         GetSymbolData(symbol, m_symbols[i]);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if Symbol is Valid for Trading                             |
//+------------------------------------------------------------------+
bool CSymbolScanner::IsSymbolValid(string symbol)
  {
   // Select symbol for info access
   if(!SymbolSelect(symbol, true))
      return false;
   
   // Check forex only filter
   if(m_forex_only)
     {
      // Forex symbols typically 6 characters (EURUSD, GBPJPY)
      // Or 7-9 with suffixes (.tp, .m, .ecn)
      string clean = symbol;
      StringReplace(clean, ".tp", "");
      StringReplace(clean, ".m", "");
      StringReplace(clean, ".i", "");
      StringReplace(clean, ".ecn", "");
      
      if(StringLen(clean) != 6)
         return false;
     }
   
   // Check major pairs only filter
   if(m_major_pairs_only && !IsMajorPair(symbol))
      return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| Get Symbol Data                                                   |
//+------------------------------------------------------------------+
bool CSymbolScanner::GetSymbolData(string symbol, SymbolInfo &info)
  {
   info.symbol = symbol;
   info.last_update = TimeCurrent();
   
   // Check if active in Market Watch
   info.is_active = SymbolInfoInteger(symbol, SYMBOL_SELECT);
   
   // Get trade mode
   info.trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   info.is_tradeable = (info.trade_mode == SYMBOL_TRADE_MODE_FULL);
   
   if(!info.is_tradeable)
      return false;
   
   // Get spread
   long spread_points_long = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   info.spread_points = (double)spread_points_long;
   
   // Get current price
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;
   
   info.current_price = (tick.bid + tick.ask) / 2.0;
   
   // Calculate spread percentage
   if(info.current_price > 0)
      info.spread_percent = (info.spread_points * SymbolInfoDouble(symbol, SYMBOL_POINT) / info.current_price) * 100.0;
   
   // Check spread filter
   if(info.spread_percent > m_max_spread_percent)
      return false;
   
   // Get tick info
   info.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   info.tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Get volume info
   info.volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   info.volume_max = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   info.volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   // Calculate volatility
   info.volatility = CalculateVolatility(symbol);
   
   // Check volatility filter
   if(info.volatility < m_min_volatility)
      return false;
   
   // Get trading session
   info.session = GetTradingSession();
   
   return true;
  }

//+------------------------------------------------------------------+
//| Calculate Volatility (ATR-based)                                 |
//+------------------------------------------------------------------+
double CSymbolScanner::CalculateVolatility(string symbol)
  {
   // Use ATR(14) on H1 as volatility measure
   int atr_handle = iATR(symbol, PERIOD_H1, 14);
   if(atr_handle == INVALID_HANDLE)
      return 0.0;
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0)
     {
      IndicatorRelease(atr_handle);
      return 0.0;
     }
   
   double atr = atr_buffer[0];
   IndicatorRelease(atr_handle);
   
   return atr;
  }

//+------------------------------------------------------------------+
//| Get Current Trading Session                                      |
//+------------------------------------------------------------------+
int CSymbolScanner::GetTradingSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int hour = dt.hour;  // GMT hour
   
   // Asian session: 00:00 - 09:00 GMT
   if(hour >= 0 && hour < 9)
      return 0;
   
   // European session: 08:00 - 17:00 GMT
   if(hour >= 8 && hour < 17)
      return 1;
   
   // American session: 13:00 - 22:00 GMT
   if(hour >= 13 && hour < 22)
      return 2;
   
   return 0;  // Default to Asian
  }

//+------------------------------------------------------------------+
//| Check if Symbol is Major Pair                                    |
//+------------------------------------------------------------------+
bool CSymbolScanner::IsMajorPair(string symbol)
  {
   string clean = symbol;
   StringReplace(clean, ".tp", "");
   StringReplace(clean, ".m", "");
   StringReplace(clean, ".i", "");
   StringReplace(clean, ".ecn", "");
   StringToUpper(clean);
   
   // Major pairs: EUR/USD, GBP/USD, USD/JPY, USD/CHF, AUD/USD, USD/CAD, NZD/USD
   string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD"};
   
   for(int i = 0; i < ArraySize(majors); i++)
     {
      if(clean == majors[i])
         return true;
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| Check if Symbol is Active                                        |
//+------------------------------------------------------------------+
bool CSymbolScanner::IsSymbolActive(string symbol)
  {
   for(int i = 0; i < m_symbol_count; i++)
     {
      if(m_symbols[i].symbol == symbol)
         return m_symbols[i].is_active;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if Symbol is Tradeable                                     |
//+------------------------------------------------------------------+
bool CSymbolScanner::IsSymbolTradeable(string symbol)
  {
   for(int i = 0; i < m_symbol_count; i++)
     {
      if(m_symbols[i].symbol == symbol)
         return m_symbols[i].is_tradeable;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Get List of Symbols                                              |
//+------------------------------------------------------------------+
void CSymbolScanner::GetSymbols(string &symbols[])
  {
   ArrayResize(symbols, m_symbol_count);
   
   for(int i = 0; i < m_symbol_count; i++)
     {
      symbols[i] = m_symbols[i].symbol;
     }
  }

//+------------------------------------------------------------------+
//| Get Symbol Info by Name                                          |
//+------------------------------------------------------------------+
bool CSymbolScanner::GetSymbolInfo(string symbol, SymbolInfo &info)
  {
   for(int i = 0; i < m_symbol_count; i++)
     {
      if(m_symbols[i].symbol == symbol)
        {
         info = m_symbols[i];
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Print Scan Results                                               |
//+------------------------------------------------------------------+
void CSymbolScanner::PrintScanResults()
  {
   Print("════════════════════════════════════════════════════════════════");
   Print("Symbol Scanner Results (", m_symbol_count, " symbols)");
   Print("════════════════════════════════════════════════════════════════");
   
   for(int i = 0; i < m_symbol_count; i++)
     {
      Print(i+1, ". ", m_symbols[i].symbol,
            " | Spread: ", DoubleToString(m_symbols[i].spread_percent, 3), "%",
            " | ATR: ", DoubleToString(m_symbols[i].volatility, 5),
            " | Session: ", m_symbols[i].session == 0 ? "Asian" : 
                           m_symbols[i].session == 1 ? "European" : "American");
     }
   
   Print("════════════════════════════════════════════════════════════════");
  }

//+------------------------------------------------------------------+
//| Get Best Symbol (lowest spread, good volatility)                 |
//+------------------------------------------------------------------+
string CSymbolScanner::GetBestSymbol()
  {
   if(m_symbol_count == 0)
      return "";
   
   double best_score = -1;
   int best_index = 0;
   
   for(int i = 0; i < m_symbol_count; i++)
     {
      // Score: Lower spread = better, Higher volatility = better
      // Normalize: spread_percent (lower better), volatility (higher better)
      double score = (1.0 / (m_symbols[i].spread_percent + 0.001)) * m_symbols[i].volatility;
      
      if(score > best_score)
        {
         best_score = score;
         best_index = i;
        }
     }
   
   return m_symbols[best_index].symbol;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CHANGE LOG                                                        |
//+------------------------------------------------------------------+
// Version 1.0 (2025-12-28):
// - Initial implementation of multi-symbol scanner
// - Scans Market Watch or all symbols
// - Filters by spread, volatility, forex/major pairs
// - Provides symbol info: spread, ATR, session, trade mode
// - Supports auto-rescan at intervals
//
// Features:
// - ScanMarketWatch(): Scan symbols in Market Watch
// - ScanAllSymbols(): Scan all available symbols
// - IsSymbolTradeable(): Check if symbol can be traded
// - GetBestSymbol(): Find symbol with best conditions
// - Filtering: Max spread %, min volatility, forex/major only
//
// Usage in ProgramC_Trader:
// - Global scanner instance
// - OnInit(): Initial scan
// - OnTimer(): Periodic rescan
// - CheckForPolicies(): Validate policy symbol
//
// Integration with Grid:
// - Multi-symbol policy support
// - Symbol-specific spread/volatility data
// - Session-aware trading
//+------------------------------------------------------------------+
