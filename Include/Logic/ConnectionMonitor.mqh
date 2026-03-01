//+------------------------------------------------------------------+
//| ConnectionMonitor.mqh                                            |
//| FlashEASuite V2 V6 — Connection State Tracker                    |
//| Phase P6-1: Full Implementation                                  |
//+------------------------------------------------------------------+
//| Changes from P0-3 skeleton:                                      |
//|  - ForceDisconnect(): COMMAND "SWITCH_STANDALONE" support        |
//|  - MarkInitialConnected(): call after CLIENT_HELLO ACK          |
//|  - GetHeartbeatTimeout(): expose timeout value                  |
//|  - IsHealthy(): convenience — connected AND recent heartbeat    |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.01"
#property strict

#ifndef CONNECTION_MONITOR_MQH
#define CONNECTION_MONITOR_MQH

//+------------------------------------------------------------------+
//| CLASS: CConnectionMonitor                                        |
//| Monitors heartbeat from Python Server, detects disconnection    |
//+------------------------------------------------------------------+
class CConnectionMonitor
{
private:
    //--- Configuration
    int                 m_heartbeat_timeout;      // Seconds until considered disconnected
    int                 m_warn_threshold;         // Seconds before timeout to issue warning

    //--- State tracking
    bool                m_is_connected;           // Current connection status
    datetime            m_last_heartbeat;         // Timestamp of last heartbeat received
    datetime            m_disconnect_time;        // When disconnection started
    datetime            m_connect_time;           // When last connection was established
    int                 m_consecutive_timeouts;   // Count of consecutive missed heartbeats
    int                 m_total_reconnects;       // Total reconnections during session

    //--- Warning state (pre-timeout warning at m_warn_threshold)
    bool                m_warn_issued;            // Warning already printed this cycle

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CConnectionMonitor() :
        m_heartbeat_timeout(30),
        m_warn_threshold(20),
        m_is_connected(false),
        m_last_heartbeat(0),
        m_disconnect_time(0),
        m_connect_time(0),
        m_consecutive_timeouts(0),
        m_total_reconnects(0),
        m_warn_issued(false)
    {
    }

    ~CConnectionMonitor() {}

    //+------------------------------------------------------------------+
    //| Init: Set heartbeat timeout and initial state                   |
    //| @param timeout_seconds  How long to wait before timeout (def 30)|
    //| @param warn_seconds     Warn before timeout (def 20)           |
    //+------------------------------------------------------------------+
    void Init(int timeout_seconds = 30, int warn_seconds = 20)
    {
        m_heartbeat_timeout  = timeout_seconds;
        m_warn_threshold     = MathMin(warn_seconds, timeout_seconds - 1);
        m_is_connected       = false;
        m_last_heartbeat     = 0;
        m_disconnect_time    = TimeCurrent();
        m_connect_time       = 0;
        m_consecutive_timeouts = 0;
        m_total_reconnects   = 0;
        m_warn_issued        = false;

        PrintFormat("[ConnectionMonitor] Initialized | timeout=%ds | warn=%ds",
            m_heartbeat_timeout, m_warn_threshold);
    }

    //+------------------------------------------------------------------+
    //| UpdateHeartbeat: Call whenever ANY message received from server |
    //| Resets timeout counter and marks as connected                   |
    //| Called by main EA after ConfigReceiver.ReceiveMessage()         |
    //+------------------------------------------------------------------+
    void UpdateHeartbeat()
    {
        datetime now = TimeCurrent();

        if(!m_is_connected)
        {
            int offline_secs = (m_disconnect_time > 0) ? (int)(now - m_disconnect_time) : 0;
            PrintFormat("[ConnectionMonitor] RECONNECTED after %ds offline | total reconnects=%d",
                offline_secs, ++m_total_reconnects);
            m_connect_time = now;
        }

        m_is_connected       = true;
        m_last_heartbeat     = now;
        m_consecutive_timeouts = 0;
        m_warn_issued        = false;
    }

    //+------------------------------------------------------------------+
    //| MarkInitialConnected: Call after CLIENT_HELLO is sent           |
    //| Marks connected without waiting for heartbeat                   |
    //| Server may take a few seconds to respond with INITIAL_CONFIG    |
    //+------------------------------------------------------------------+
    void MarkInitialConnected()
    {
        datetime now = TimeCurrent();
        m_is_connected  = true;
        m_last_heartbeat = now;
        m_connect_time  = now;
        m_warn_issued   = false;
        Print("[ConnectionMonitor] Initial connection marked (CLIENT_HELLO sent)");
    }

    //+------------------------------------------------------------------+
    //| ForceDisconnect: Call when COMMAND "SWITCH_STANDALONE" received |
    //| or when main EA explicitly wants to go offline                  |
    //+------------------------------------------------------------------+
    void ForceDisconnect()
    {
        datetime now = TimeCurrent();
        if(m_is_connected)
        {
            m_is_connected   = false;
            m_disconnect_time = now;
            m_consecutive_timeouts++;
        }
        m_last_heartbeat = 0;  // Prevent immediate reconnect detection
        Print("[ConnectionMonitor] FORCE DISCONNECT — switching to standalone mode");
    }

    //+------------------------------------------------------------------+
    //| Check: Verify connection status, call every OnTimer (10s)       |
    //| Returns true if connected, false if timeout exceeded            |
    //| Side effect: logs timeout and warning messages                  |
    //+------------------------------------------------------------------+
    bool Check()
    {
        datetime now = TimeCurrent();

        if(m_last_heartbeat == 0)
        {
            // Never received heartbeat since Init()
            return false;
        }

        int elapsed = (int)(now - m_last_heartbeat);

        // --- Hard timeout ---
        if(elapsed > m_heartbeat_timeout)
        {
            if(m_is_connected)
            {
                m_is_connected    = false;
                m_disconnect_time = now;
                m_consecutive_timeouts++;
                PrintFormat("[ConnectionMonitor] TIMEOUT after %ds (threshold=%ds) | timeouts=%d",
                    elapsed, m_heartbeat_timeout, m_consecutive_timeouts);
            }
            return false;
        }

        // --- Pre-timeout warning ---
        if(elapsed > m_warn_threshold && !m_warn_issued)
        {
            m_warn_issued = true;
            PrintFormat("[ConnectionMonitor] WARNING: No heartbeat for %ds (timeout in %ds)",
                elapsed, m_heartbeat_timeout - elapsed);
        }

        // --- Connection restored ---
        if(!m_is_connected)
        {
            m_is_connected = true;
            m_warn_issued  = false;
            Print("[ConnectionMonitor] Connection restored (internal check)");
        }

        return true;
    }

    //=================================================================
    //  STATE QUERIES
    //=================================================================

    //+------------------------------------------------------------------+
    //| IsConnected: Get current connection status (last Check() result)|
    //+------------------------------------------------------------------+
    bool IsConnected() const { return m_is_connected; }

    //+------------------------------------------------------------------+
    //| IsHealthy: Connected AND heartbeat within warn_threshold        |
    //| Use this when you want to be sure link is solid                |
    //+------------------------------------------------------------------+
    bool IsHealthy()
    {
        if(!m_is_connected || m_last_heartbeat == 0) return false;
        return ((int)(TimeCurrent() - m_last_heartbeat) <= m_warn_threshold);
    }

    //+------------------------------------------------------------------+
    //| GetLastHeartbeatTime: Timestamp of last heartbeat/message       |
    //+------------------------------------------------------------------+
    datetime GetLastHeartbeatTime() const { return m_last_heartbeat; }

    //+------------------------------------------------------------------+
    //| GetSecondsSinceHeartbeat: How long since last message?          |
    //| Returns -1 if never received                                    |
    //+------------------------------------------------------------------+
    int GetSecondsSinceHeartbeat()
    {
        if(m_last_heartbeat == 0) return -1;
        return (int)(TimeCurrent() - m_last_heartbeat);
    }

    //+------------------------------------------------------------------+
    //| GetDisconnectDuration: How long has it been disconnected?       |
    //| Returns 0 if currently connected                                |
    //+------------------------------------------------------------------+
    int GetDisconnectDuration()
    {
        if(m_is_connected) return 0;
        if(m_disconnect_time == 0) return 0;
        return (int)(TimeCurrent() - m_disconnect_time);
    }

    //+------------------------------------------------------------------+
    //| GetConnectedDuration: How long has current connection lasted?   |
    //| Returns 0 if disconnected                                       |
    //+------------------------------------------------------------------+
    int GetConnectedDuration()
    {
        if(!m_is_connected || m_connect_time == 0) return 0;
        return (int)(TimeCurrent() - m_connect_time);
    }

    int GetConsecutiveTimeouts() const { return m_consecutive_timeouts; }
    int GetTotalReconnects()     const { return m_total_reconnects; }
    int GetHeartbeatTimeout()    const { return m_heartbeat_timeout; }

    //+------------------------------------------------------------------+
    //| SetHeartbeatTimeout: Adjust timeout threshold at runtime        |
    //+------------------------------------------------------------------+
    void SetHeartbeatTimeout(int timeout_seconds)
    {
        m_heartbeat_timeout = timeout_seconds;
        m_warn_threshold    = MathMin(m_warn_threshold, timeout_seconds - 1);
        PrintFormat("[ConnectionMonitor] Heartbeat timeout updated to %ds", timeout_seconds);
    }

    //+------------------------------------------------------------------+
    //| Reset: Clear all state (useful before reconnection attempt)     |
    //+------------------------------------------------------------------+
    void Reset()
    {
        m_is_connected         = false;
        m_last_heartbeat       = 0;
        m_disconnect_time      = TimeCurrent();
        m_connect_time         = 0;
        m_consecutive_timeouts = 0;
        m_warn_issued          = false;
        Print("[ConnectionMonitor] State reset");
    }

    //+------------------------------------------------------------------+
    //| GetStatus: Human-readable status string (for dashboard/log)     |
    //+------------------------------------------------------------------+
    string GetStatus()
    {
        if(m_is_connected)
        {
            return StringFormat("ONLINE | last_msg=%ds ago | uptime=%ds | reconnects=%d",
                GetSecondsSinceHeartbeat(),
                GetConnectedDuration(),
                m_total_reconnects);
        }
        else
        {
            return StringFormat("OFFLINE | down=%ds | timeouts=%d | reconnects=%d",
                GetDisconnectDuration(),
                m_consecutive_timeouts,
                m_total_reconnects);
        }
    }
};

#endif // CONNECTION_MONITOR_MQH
