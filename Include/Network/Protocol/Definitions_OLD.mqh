//+------------------------------------------------------------------+
//|                                           Protocol/Definitions.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                            Message Protocol - Type Definitions   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| Message Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_MESSAGE_TYPE
  {
   MSG_TYPE_TICK = 1,
   MSG_TYPE_POLICY = 2,
   MSG_TYPE_HEARTBEAT = 3,
   MSG_TYPE_UNKNOWN = 0
  };

//+------------------------------------------------------------------+
//| Tick Message Structure                                            |
//+------------------------------------------------------------------+
struct TickMessage
  {
   string            symbol;           // Symbol name
   long              time_msc;         // Time in milliseconds
   double            bid;              // Bid price
   double            ask;              // Ask price
   double            last;             // Last price
   ulong             volume;           // Volume
   long              time_msc_sent;    // Time sent from feeder
   
   // Constructor
   void TickMessage()
     {
      symbol = "";
      time_msc = 0;
      bid = 0.0;
      ask = 0.0;
      last = 0.0;
      volume = 0;
      time_msc_sent = 0;
     }
  };

//+------------------------------------------------------------------+
//| Policy Message Structure (AI Decision)                           |
//+------------------------------------------------------------------+
struct PolicyMessage
  {
   string            symbol;           // Symbol name
   int               action;           // Action: 0=HOLD, 1=BUY, 2=SELL
   double            confidence;       // Confidence score (0.0-1.0)
   double            entry_price;      // Suggested entry price
   double            stop_loss;        // Suggested stop loss
   double            take_profit;      // Suggested take profit
   double            position_size;    // Suggested position size (lots)
   long              timestamp_ms;     // Policy generation timestamp
   string            model_version;    // AI model version identifier
   
   // Constructor
   void PolicyMessage()
     {
      symbol = "";
      action = 0;
      confidence = 0.0;
      entry_price = 0.0;
      stop_loss = 0.0;
      take_profit = 0.0;
      position_size = 0.0;
      timestamp_ms = 0;
      model_version = "";
     }
  };

//+------------------------------------------------------------------+
//| Heartbeat Message Structure                                       |
//+------------------------------------------------------------------+
struct Heartbeat
  {
   string            source;           // Source identifier (e.g., "BRAIN", "FEEDER")
   long              timestamp_ms;     // Heartbeat timestamp
   int               sequence;         // Sequence number
   bool              is_alive;         // Alive status flag
   
   // Constructor
   void Heartbeat()
     {
      source = "";
      timestamp_ms = 0;
      sequence = 0;
      is_alive = true;
     }
  };
//+------------------------------------------------------------------+
