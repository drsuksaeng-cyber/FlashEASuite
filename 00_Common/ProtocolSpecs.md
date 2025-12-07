# FlashEASuite V2 Protocol Specifications
Serialization: MessagePack (Binary)
Transport: ZeroMQ (TCP)
Security: CurveZMQ (Server-Client Keys)

## 1. Tick Data (Feeder -> Brain & Trader)
**Topic:** `TICK`
**Structure (Array):**
[
  0: (int)    MSG_TYPE (1 = TICK),
  1: (int)    SEQ_ID (Running Number),
  2: (int)    SERVER_TIME_MS,
  3: (string) SYMBOL,
  4: (double) BID,
  5: (double) ASK,
  6: (int)    FLAGS (1=Real, 2=Simulated)
]

## 2. Signal Data (Brain -> Trader)
**Topic:** `SIG`
**Structure (Map/Dict):**
{
  "t": (int)    MSG_TYPE (2 = SIGNAL),
  "id": (string) STRATEGY_ID,
  "ac": (int)    ACTION (1=BUY, 2=SELL, 3=CLOSE),
  "sl": (double) STOP_LOSS,
  "tp": (double) TAKE_PROFIT,
  "sc": (float)  CONFIDENCE_SCORE (0.0 - 1.0),
  "ts": (int)    TIMESTAMP_MS
}