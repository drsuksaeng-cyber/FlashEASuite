//+------------------------------------------------------------------+
//|                                            Network Layer README  |
//|                                    FlashEASuite V2 - Program C   |
//|                                          Networking Layer Docs   |
//+------------------------------------------------------------------+

# FlashEASuite V2 - Program C (Trader) Networking Layer

## Overview
The Networking Layer provides high-performance, non-blocking communication between 
the MQL5 Trader (Program C) and the Python Brain (Program B) using ZeroMQ messaging 
with binary serialization.

## Architecture

### Components

1. **Protocol.mqh**
   - Message structure definitions
   - Binary serialization/deserialization
   - Type-safe message handling
   - Support for TickMessage, PolicyMessage, and Heartbeat

2. **ZmqHub.mqh**
   - ZeroMQ socket management
   - Non-blocking I/O operations
   - Connection state tracking
   - Statistics and diagnostics

## Message Types

### 1. TickMessage
Carries real-time tick data from Feeder to Brain.
```mql5
struct TickMessage {
    string symbol;           // Symbol name (e.g., "EURUSD")
    long   time_msc;        // Tick timestamp (milliseconds)
    double bid;             // Bid price
    double ask;             // Ask price
    double last;            // Last price
    ulong  volume;          // Tick volume
    long   time_msc_sent;   // Feeder send timestamp
}
```

### 2. PolicyMessage
Carries AI trading decisions from Brain to Trader.
```mql5
struct PolicyMessage {
    string symbol;          // Symbol to trade
    int    action;          // 0=HOLD, 1=BUY, 2=SELL
    double confidence;      // AI confidence (0.0-1.0)
    double entry_price;     // Suggested entry
    double stop_loss;       // Suggested SL
    double take_profit;     // Suggested TP
    double position_size;   // Suggested lots
    long   timestamp_ms;    // Policy timestamp
    string model_version;   // AI model identifier
}
```

### 3. Heartbeat
System health monitoring message.
```mql5
struct Heartbeat {
    string source;          // Source identifier
    long   timestamp_ms;    // Heartbeat timestamp
    int    sequence;        // Sequence number
    bool   is_alive;        // Alive status
}
```

## Usage Example

### Basic Setup

```mql5
#include <Network/ZmqHub.mqh>
#include <Network/Protocol.mqh>

// Global variables
CZmqHub *g_zmq_hub = NULL;

int OnInit()
{
    // Initialize ZMQ Hub
    g_zmq_hub = new CZmqHub();
    if(!g_zmq_hub.Initialize(100, 1000)) // 100ms rcv, 1000ms snd timeout
    {
        Print("Failed to initialize ZMQ Hub");
        return INIT_FAILED;
    }
    
    // Subscribe to Brain's policy messages
    if(!g_zmq_hub.Subscribe("tcp://localhost:5556"))
    {
        Print("Failed to subscribe to Brain");
        return INIT_FAILED;
    }
    
    // Connect PUSH socket for confirmations
    if(!g_zmq_hub.ConnectPush("tcp://localhost:5557"))
    {
        Print("Failed to connect PUSH socket");
        return INIT_FAILED;
    }
    
    Print("Trader networking initialized successfully");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if(g_zmq_hub != NULL)
    {
        g_zmq_hub.Disconnect();
        delete g_zmq_hub;
        g_zmq_hub = NULL;
    }
}

void OnTick()
{
    if(g_zmq_hub == NULL || !g_zmq_hub.IsFullyConnected())
        return;
    
    // Non-blocking message check
    uchar recv_buffer[];
    if(g_zmq_hub.Poll(recv_buffer, 0)) // 0 = non-blocking
    {
        // Determine message type
        ENUM_MESSAGE_TYPE msg_type = CProtocol::GetMessageType(recv_buffer);
        
        if(msg_type == MSG_TYPE_POLICY)
        {
            PolicyMessage policy;
            if(CProtocol::DeserializePolicyMessage(recv_buffer, policy))
            {
                ProcessPolicy(policy);
            }
        }
        else if(msg_type == MSG_TYPE_HEARTBEAT)
        {
            Heartbeat hb;
            if(CProtocol::DeserializeHeartbeat(recv_buffer, hb))
            {
                ProcessHeartbeat(hb);
            }
        }
    }
}

void ProcessPolicy(const PolicyMessage &policy)
{
    Print("Received Policy: ", policy.symbol, 
          " Action=", policy.action,
          " Confidence=", policy.confidence);
    
    // Execute trade based on policy
    if(policy.confidence >= 0.75) // Confidence threshold
    {
        if(policy.action == 1) // BUY
        {
            // Execute BUY order
            // ...
        }
        else if(policy.action == 2) // SELL
        {
            // Execute SELL order
            // ...
        }
        
        // Send confirmation back to Brain
        g_zmq_hub.SendPolicyConfirmation(
            policy.symbol,
            policy.action,
            policy.timestamp_ms
        );
    }
}

void ProcessHeartbeat(const Heartbeat &hb)
{
    Print("Heartbeat from ", hb.source, 
          " Seq=", hb.sequence,
          " Alive=", hb.is_alive);
}
```

## Performance Characteristics

### Non-Blocking I/O
- `Poll()` with timeout=0 returns immediately
- No blocking on network operations
- Suitable for OnTick() event handlers

### Latency Targets
- Message serialization: < 50 microseconds
- Socket send/receive: < 1 millisecond
- Total processing: < 5 milliseconds per message

### Memory Management
- Automatic cleanup via destructors
- No memory leaks with proper usage
- Buffer resizing handled internally

## Connection Management

### State Machine
```
DISCONNECTED -> CONNECTING -> CONNECTED
                     |
                     v
                  ERROR
```

### Error Handling
```mql5
// Check connection state
if(!g_zmq_hub.IsFullyConnected())
{
    Print("Connection lost, attempting reconnect...");
    g_zmq_hub.Disconnect();
    g_zmq_hub.Subscribe("tcp://localhost:5556");
    g_zmq_hub.ConnectPush("tcp://localhost:5557");
}

// Monitor error rates
if(g_zmq_hub.GetReceiveErrors() > 100)
{
    Print("High error rate detected: ", 
          g_zmq_hub.GetStatusString());
}
```

## Best Practices

1. **Non-Blocking Operations**
   - Always use `Poll()` with timeout=0 in OnTick()
   - Process messages quickly to avoid buffering

2. **Error Recovery**
   - Monitor connection state regularly
   - Implement automatic reconnection logic
   - Log errors for diagnostics

3. **Message Validation**
   - Check message type before deserializing
   - Validate field values (e.g., confidence 0.0-1.0)
   - Handle malformed messages gracefully

4. **Resource Management**
   - Delete CZmqHub in OnDeinit()
   - Call Disconnect() before deletion
   - Reset statistics periodically

5. **Diagnostics**
   ```mql5
   // Print status every 1000 ticks
   static int tick_count = 0;
   if(++tick_count % 1000 == 0)
   {
       Print(g_zmq_hub.GetStatusString());
   }
   ```

## Technical Specifications

### Binary Format
- Big-endian byte order
- Type prefixes for safety
- Variable-length strings (length-prefixed)
- 8-byte alignment for doubles

### Socket Configuration
- SUB socket: Receive policies and heartbeats
- PUSH socket: Send confirmations
- Linger time: 0 (immediate discard on close)
- High water mark: 1000 messages
- Timeouts: Configurable (default 100ms RCV, 1000ms SND)

### Thread Safety
- Single-threaded operation (MQL5 constraint)
- No concurrent access issues
- State changes are atomic

## Troubleshooting

### Common Issues

1. **Connection Failures**
   - Verify Python Brain is running
   - Check port availability
   - Confirm firewall settings

2. **Message Loss**
   - Increase high water mark
   - Check buffer flush frequency
   - Monitor system resources

3. **High Latency**
   - Reduce message size
   - Optimize serialization
   - Check network configuration

### Debug Output
```mql5
// Enable verbose logging
Print("ZMQ Status: ", g_zmq_hub.GetStatusString());
Print("Messages RX: ", g_zmq_hub.GetMessagesReceived());
Print("Messages TX: ", g_zmq_hub.GetMessagesSent());
Print("Errors RX: ", g_zmq_hub.GetReceiveErrors());
Print("Errors TX: ", g_zmq_hub.GetSendErrors());
```

## Integration with FlashEASuite V2

### Program A (Feeder)
- Sends TickMessages to Brain via PUB socket
- Not directly connected to Trader

### Program B (Brain - Python)
- Receives TickMessages from Feeder (SUB socket)
- Sends PolicyMessages to Trader (PUB socket)
- Receives confirmations from Trader (PULL socket)

### Program C (Trader - This Module)
- Receives PolicyMessages from Brain (SUB socket)
- Sends confirmations to Brain (PUSH socket)
- Executes trades based on policies

## Dependencies

- MQL5 Standard Library (Zmq/Zmq.mqh)
- libzmq.dll (Standard ZeroMQ library)
- No external custom DLLs required

## License
Copyright Dr. Suksaeng Kukanok
FlashEASuite V2 - Professional Trading System

## Version History
- v2.0 (2024): Initial release for FlashEASuite V2
- Non-blocking I/O implementation
- Binary serialization protocol
- Enhanced error handling

## Support
For issues or questions regarding the Networking Layer:
1. Check connection states via GetStatusString()
2. Review error counters
3. Verify Python Brain connectivity
4. Consult system logs

---
End of README
