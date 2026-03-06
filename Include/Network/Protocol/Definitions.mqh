//+------------------------------------------------------------------+
//|                                       Protocol/Definitions.mqh    |
//|                                    FlashEASuite V2 V6             |
//|                            Message Protocol — 15 Type Definitions |
//+------------------------------------------------------------------+
//| UPGRADED from V5 (3 types) to V6 (15 types)                      |
//| - Backward compatible: TickMessage, PolicyMessage, Heartbeat kept |
//| - New V6 structs added for all 15 message types                  |
//| - ENUM_MESSAGE_TYPE expanded to 15 values                        |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| V6 Message Type Enumeration — 15 Types                           |
//+------------------------------------------------------------------+
enum ENUM_MSG_TYPE_V6
  {
   // --- Feeder → Server (Port 7777 PUSH/PULL) ---
   MSG_TICK_DATA           = 1,   // Raw tick data
   MSG_OHLC_DATA           = 2,   // OHLC bars
   MSG_INDICATOR_DATA      = 3,   // Pre-calculated indicators

   // --- Server → Clients (Port 7778 PUB/SUB) ---
   MSG_CONFIG_PUSH         = 10,  // Strategy/MM configuration + reasoning
   MSG_INITIAL_CONFIG      = 12,  // First-time config + standalone fallback
   MSG_HEARTBEAT           = 13,  // Keep-alive (10s interval, 30s timeout)
   MSG_DYNAMIC_PARAMS      = 14,  // Brain→Trader: hot-reload strategy parameters
   MSG_NEWS_ALERT          = 30,  // Economic calendar alert
   MSG_REGIME_CHANGE       = 31,  // Market regime shift
   MSG_COMMAND             = 40,  // Manual command (stop, start, etc.)
   MSG_POLICY_UPDATE       = 50,  // Security policy update

   // --- Clients → Server (Port 7779 PUSH/PULL) ---
   MSG_CLIENT_HELLO        = 11,  // Client registration
   MSG_TRADE_REPORT        = 20,  // Trade execution report
   MSG_POSITION_UPDATE     = 21,  // Position status
   MSG_PERFORMANCE_METRICS = 22,  // Performance stats

   // --- Any → Any ---
   MSG_ERROR               = 99,  // Error message

   // --- V6 unknown ---
   MSG_V6_UNKNOWN          = 0
  };

//+------------------------------------------------------------------+
//| V5 Legacy Enum — kept for backward compatibility                  |
//+------------------------------------------------------------------+
enum ENUM_MESSAGE_TYPE
  {
   MSG_TYPE_TICK      = 1,  // Maps to MSG_TICK_DATA
   MSG_TYPE_POLICY    = 2,  // Legacy: V5 used 2 for policy
   MSG_TYPE_HEARTBEAT = 3,  // Legacy: V5 used 3 for heartbeat
   MSG_TYPE_UNKNOWN   = 0
  };

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                         |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN  = 0,
   REGIME_TRENDING = 1,
   REGIME_RANGING  = 2,
   REGIME_VOLATILE = 3,
   REGIME_SQUEEZE  = 4
  };

//+------------------------------------------------------------------+
//| Grid Direction Enumeration (legacy, kept)                         |
//+------------------------------------------------------------------+
enum ENUM_GRID_DIRECTION
  {
   GRID_DIR_NONE = 0,
   GRID_DIR_BUY  = 1,
   GRID_DIR_SELL = 2
  };

//+------------------------------------------------------------------+
//| ZMQ Port Configuration                                            |
//+------------------------------------------------------------------+
#define ZMQ_PORT_FEEDER  7777   // Feeder → Server (PUSH/PULL)
#define ZMQ_PORT_PUB     7778   // Server → Clients (PUB/SUB)
#define ZMQ_PORT_CLIENT  7779   // Clients → Server (PUSH/PULL)

//+------------------------------------------------------------------+
//| V6 Tick Message Structure (Type 1)                                |
//+------------------------------------------------------------------+
struct TickMessageV6
  {
   int               msg_type;         // MSG_TICK_DATA = 1
   long              timestamp_ms;     // Server receive time
   string            symbol;           // e.g. "XAUUSD.tp"
   double            bid;
   double            ask;
   double            last;
   long              volume;
   long              time_msc_sent;    // When Feeder sent this tick

   void TickMessageV6()
     {
      msg_type = MSG_TICK_DATA;
      timestamp_ms = 0;  symbol = "";
      bid = 0; ask = 0; last = 0; volume = 0; time_msc_sent = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 OHLC Data Structure (Type 2)                                   |
//+------------------------------------------------------------------+
struct OHLCDataV6
  {
   int               msg_type;         // MSG_OHLC_DATA = 2
   long              timestamp_ms;
   string            symbol;
   string            timeframe;        // "M1","M5","M15","H1","H4","D1"
   double            open;
   double            high;
   double            low;
   double            close;
   long              volume;
   long              bar_time;         // Bar open time (epoch seconds)

   void OHLCDataV6()
     {
      msg_type = MSG_OHLC_DATA;
      timestamp_ms = 0;  symbol = "";  timeframe = "";
      open = 0; high = 0; low = 0; close = 0; volume = 0; bar_time = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 Config Push Structure (Type 10)                                |
//| Simplified for MQL5 — complex JSON parsed field-by-field          |
//+------------------------------------------------------------------+
struct StrategyConfig
  {
   string            id;               // "S01", "S15", etc.
   string            name;             // "StatArb", "Grid", etc.
   bool              enabled;
   double            confidence;
   string            timeframe;
   string            mm_method;        // "MM1", "MM4", etc.

   void StrategyConfig()
     {
      id = "";  name = "";  enabled = false;
      confidence = 0;  timeframe = "";  mm_method = "";
     }
  };

struct SymbolConfig
  {
   string            symbol;
   int               strategy_count;
   StrategyConfig    strategies[16];   // Max 16 strategies per symbol

   void SymbolConfig()
     {
      symbol = "";
      strategy_count = 0;
     }
  };

struct ConfigPushV6
  {
   int               msg_type;         // MSG_CONFIG_PUSH = 10
   long              timestamp_ms;
   string            regime;           // "TRENDING","RANGING","VOLATILE","SQUEEZE"
   int               symbol_count;
   SymbolConfig      symbols[28];      // Max 28 symbols

   void ConfigPushV6()
     {
      msg_type = MSG_CONFIG_PUSH;
      timestamp_ms = 0;  regime = "";  symbol_count = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 Client Hello Structure (Type 11)                               |
//+------------------------------------------------------------------+
struct ClientHelloV6
  {
   int               msg_type;         // MSG_CLIENT_HELLO = 11
   long              timestamp_ms;
   string            client_id;
   long              account_number;
   string            broker;
   string            terminal_version;
   string            symbol_suffix;    // ".tp", "", etc.

   void ClientHelloV6()
     {
      msg_type = MSG_CLIENT_HELLO;
      timestamp_ms = 0;  client_id = "";  account_number = 0;
      broker = "";  terminal_version = "";  symbol_suffix = "";
     }
  };

//+------------------------------------------------------------------+
//| V6 Heartbeat Structure (Type 13)                                  |
//+------------------------------------------------------------------+
struct HeartbeatV6
  {
   int               msg_type;         // MSG_HEARTBEAT = 13
   long              timestamp_ms;
   string            source;           // "SERVER", "CLIENT_xxx"
   int               sequence;
   bool              is_alive;

   void HeartbeatV6()
     {
      msg_type = MSG_HEARTBEAT;
      timestamp_ms = 0;  source = "";  sequence = 0;  is_alive = true;
     }
  };

//+------------------------------------------------------------------+
//| V6 Trade Report Structure (Type 20)                               |
//+------------------------------------------------------------------+
struct TradeReportV6
  {
   int               msg_type;         // MSG_TRADE_REPORT = 20
   long              timestamp_ms;
   string            client_id;
   string            symbol;
   string            strategy_id;      // "S01", "S15", etc.
   int               magic;
   int               order_type;       // 0=BUY, 1=SELL
   double            lots;
   double            open_price;
   double            close_price;
   double            profit;
   double            commission;
   double            swap;
   long              open_time_ms;
   long              close_time_ms;

   void TradeReportV6()
     {
      msg_type = MSG_TRADE_REPORT;
      timestamp_ms = 0;  client_id = "";  symbol = "";  strategy_id = "";
      magic = 0;  order_type = 0;  lots = 0;
      open_price = 0;  close_price = 0;  profit = 0;
      commission = 0;  swap = 0;  open_time_ms = 0;  close_time_ms = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 Position Update Structure (Type 21)                            |
//+------------------------------------------------------------------+
struct PositionUpdateV6
  {
   int               msg_type;         // MSG_POSITION_UPDATE = 21
   long              timestamp_ms;
   string            client_id;
   string            symbol;
   string            strategy_id;
   int               magic;
   int               direction;        // 0=FLAT, 1=LONG, 2=SHORT
   double            lots;
   double            open_price;
   double            current_price;
   double            unrealized_pnl;
   double            sl;
   double            tp;

   void PositionUpdateV6()
     {
      msg_type = MSG_POSITION_UPDATE;
      timestamp_ms = 0;  client_id = "";  symbol = "";  strategy_id = "";
      magic = 0;  direction = 0;  lots = 0;
      open_price = 0;  current_price = 0;  unrealized_pnl = 0;
      sl = 0;  tp = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 Performance Metrics Structure (Type 22)                        |
//+------------------------------------------------------------------+
struct PerformanceMetricsV6
  {
   int               msg_type;         // MSG_PERFORMANCE_METRICS = 22
   long              timestamp_ms;
   string            client_id;
   double            balance;
   double            equity;
   double            margin_level;
   int               total_trades;
   double            win_rate;
   double            daily_pnl;
   double            max_drawdown;

   void PerformanceMetricsV6()
     {
      msg_type = MSG_PERFORMANCE_METRICS;
      timestamp_ms = 0;  client_id = "";
      balance = 0;  equity = 0;  margin_level = 0;
      total_trades = 0;  win_rate = 0;  daily_pnl = 0;  max_drawdown = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 News Alert Structure (Type 30)                                 |
//+------------------------------------------------------------------+
struct NewsAlertV6
  {
   int               msg_type;         // MSG_NEWS_ALERT = 30
   long              timestamp_ms;
   string            event_name;
   string            currency;         // "USD", "EUR", etc.
   int               impact;           // 1=Low, 2=Med, 3=High
   string            forecast;
   string            previous;
   long              event_time_ms;

   void NewsAlertV6()
     {
      msg_type = MSG_NEWS_ALERT;
      timestamp_ms = 0;  event_name = "";  currency = "";
      impact = 0;  forecast = "";  previous = "";  event_time_ms = 0;
     }
  };

//+------------------------------------------------------------------+
//| V6 Regime Change Structure (Type 31)                              |
//+------------------------------------------------------------------+
struct RegimeChangeV6
  {
   int               msg_type;         // MSG_REGIME_CHANGE = 31
   long              timestamp_ms;
   string            old_regime;
   string            new_regime;
   double            confidence;
   string            method;           // "RULE", "RF_ML", "HMM"

   void RegimeChangeV6()
     {
      msg_type = MSG_REGIME_CHANGE;
      timestamp_ms = 0;  old_regime = "";  new_regime = "";
      confidence = 0;  method = "";
     }
  };

//+------------------------------------------------------------------+
//| V6 Command Structure (Type 40)                                    |
//+------------------------------------------------------------------+
struct CommandV6
  {
   int               msg_type;         // MSG_COMMAND = 40
   long              timestamp_ms;
   string            target_client;    // "" = broadcast
   string            command;          // "STOP","START","CLOSE_ALL","SWITCH_STANDALONE"

   void CommandV6()
     {
      msg_type = MSG_COMMAND;
      timestamp_ms = 0;  target_client = "";  command = "";
     }
  };

//+------------------------------------------------------------------+
//| V6 Error Structure (Type 99)                                      |
//+------------------------------------------------------------------+
struct ErrorMsgV6
  {
   int               msg_type;         // MSG_ERROR = 99
   long              timestamp_ms;
   string            source;
   int               error_code;
   string            error_message;

   void ErrorMsgV6()
     {
      msg_type = MSG_ERROR;
      timestamp_ms = 0;  source = "";  error_code = 0;  error_message = "";
     }
  };

//+------------------------------------------------------------------+
//| V5 Legacy Structures — Kept for backward compatibility            |
//| Used by existing Grid/Spike strategies until fully migrated       |
//+------------------------------------------------------------------+
struct TickMessage
  {
   string            symbol;
   long              time_msc;
   double            bid;
   double            ask;
   double            last;
   ulong             volume;
   long              time_msc_sent;

   void TickMessage()
     {
      symbol = "";  time_msc = 0;
      bid = 0; ask = 0; last = 0; volume = 0; time_msc_sent = 0;
     }
  };

struct PolicyMessage
  {
   string            symbol;
   int               action;           // 0=HOLD, 1=BUY, 2=SELL
   double            confidence;
   double            entry_price;
   double            stop_loss;
   double            take_profit;
   double            position_size;
   long              timestamp_ms;
   string            model_version;
   double            risk_multiplier;
   bool              is_in_cooldown;
   double            csm_usd;
   double            csm_eur;
   double            csm_gbp;
   double            csm_jpy;
   double            csm_aud;
   double            csm_cad;
   double            csm_chf;
   double            csm_nzd;
   int               grid_direction;

   void PolicyMessage()
     {
      symbol = "";  action = 0;  confidence = 0;
      entry_price = 0;  stop_loss = 0;  take_profit = 0;
      position_size = 0;  timestamp_ms = 0;  model_version = "";
      risk_multiplier = 1.0;  is_in_cooldown = false;
      csm_usd = 0; csm_eur = 0; csm_gbp = 0; csm_jpy = 0;
      csm_aud = 0; csm_cad = 0; csm_chf = 0; csm_nzd = 0;
      grid_direction = 0;
     }
  };

struct Heartbeat
  {
   string            source;
   long              timestamp_ms;
   int               sequence;
   bool              is_alive;

   void Heartbeat()
     {
      source = "";  timestamp_ms = 0;  sequence = 0;  is_alive = true;
     }
  };

//+------------------------------------------------------------------+
//| Helper: String → ENUM_MARKET_REGIME                               |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME StringToRegime(string regime_str)
  {
   if(regime_str == "TRENDING") return REGIME_TRENDING;
   if(regime_str == "RANGING")  return REGIME_RANGING;
   if(regime_str == "VOLATILE") return REGIME_VOLATILE;
   if(regime_str == "SQUEEZE")  return REGIME_SQUEEZE;
   return REGIME_UNKNOWN;
  }

string RegimeToString(ENUM_MARKET_REGIME regime)
  {
   switch(regime)
     {
      case REGIME_TRENDING: return "TRENDING";
      case REGIME_RANGING:  return "RANGING";
      case REGIME_VOLATILE: return "VOLATILE";
      case REGIME_SQUEEZE:  return "SQUEEZE";
      default:              return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| CHANGE LOG                                                        |
//+------------------------------------------------------------------+
// V6.0 (2026-02-13):
// - Expanded ENUM_MSG_TYPE_V6 from 3 to 15 message types
// - Added V6 structs for all 15 message types
// - Added ENUM_MARKET_REGIME enum
// - Added ZMQ port #defines
// - Kept V5 legacy structs (TickMessage, PolicyMessage, Heartbeat)
//   for backward compatibility with existing Grid/Spike code
// - Added StringToRegime() / RegimeToString() helpers
//+------------------------------------------------------------------+
