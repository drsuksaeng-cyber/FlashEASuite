//+------------------------------------------------------------------+
//| FlashEA_V6.mq5                                                   |
//| FlashEASuite V2 V6 — Main EA Skeleton                            |
//| Online Mode + Standalone Mode + StrategyManager + ConfigReceiver |
//+------------------------------------------------------------------+
//| Purpose:                                                         |
//| - Main entry point for FlashEASuite V2 V6                        |
//| - Manages Online Mode (server-driven) & Standalone Mode (offline)|
//| - Initializes all components: Protocol, ConfigReceiver, etc.    |
//| - Handles heartbeat, connection monitoring, mode switching       |
//| - Routes messages from server to appropriate handlers            |
//+------------------------------------------------------------------+
//| Architecture:                                                    |
//| - Online Mode: Receive CONFIG_PUSH → Enable strategies          |
//| - Standalone Mode: Use CStandaloneSelector → Detect regime      |
//| - Heartbeat: Every 10s (OnTimer)                                |
//| - Timeout: 30s without heartbeat → switch to Standalone         |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict
#property description "FlashEASuite V2 V6 — Main EA with Online/Standalone modes"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include "..\Include\Logic\IStrategy.mqh"
#include "..\Include\Logic\StrategyConstants.mqh"
#include "..\Include\Logic\ConnectionMonitor.mqh"
#include "..\Include\Logic\ConfigReceiver.mqh"
#include "..\Include\Logic\StrategyManager_V6.mqh"
#include "..\Include\Network\Protocol.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string    ServerIP            = "127.0.0.1";      // Python Server IP
input int       ServerPort          = 7778;             // ZMQ PUB port for CONFIG_PUSH
input string    ClientID            = "MT5_Client_001"; // Unique client identifier
input bool      EnableStandalone    = true;             // Allow Standalone mode?
input int       HeartbeatTimeout    = 30;              // Seconds until disconnect
input int       HeartbeatInterval   = 10;              // Seconds between heartbeats
input bool      DebugMode           = true;             // Print debug messages?

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                   |
//+------------------------------------------------------------------+
CConnectionMonitor      g_connection_monitor;
CConfigReceiver         g_config_receiver;
CStrategyManager_V6     g_strategy_manager;

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
bool                    g_is_online_mode        = false;
bool                    g_is_standalone_mode    = false;
datetime                g_last_heartbeat_sent   = 0;
int                     g_heartbeat_timer_id    = 1;
int                     g_message_count         = 0;

//+------------------------------------------------------------------+
//| OnInit: Initialize EA                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════════════════════════");
    Print("[FlashEA_V6] Initializing FlashEASuite V2 V6...");
    Print("[FlashEA_V6] Symbol: ", _Symbol, " | Timeframe: ", _Period);
    Print("[FlashEA_V6] Server: ", ServerIP, ":", ServerPort);
    Print("[FlashEA_V6] ClientID: ", ClientID);
    Print("═══════════════════════════════════════════════════════════");
    
    //--- Initialize components
    g_connection_monitor.Init(HeartbeatTimeout);
    g_config_receiver.Init();
    g_strategy_manager.Init();
    
    //--- Initialize strategy table
    if(!g_strategy_table_initialized)
    {
        InitStrategyTable();
    }
    
    //--- Try to connect to server
    if(!ConnectToServer())
    {
        Print("[FlashEA_V6] WARNING: Cannot connect to server");
        
        if(EnableStandalone)
        {
            Print("[FlashEA_V6] Switching to STANDALONE MODE");
            SwitchToStandaloneMode();
        }
        else
        {
            Print("[FlashEA_V6] ERROR: Standalone mode disabled - EA cannot start");
            return INIT_FAILED;
        }
    }
    else
    {
        Print("[FlashEA_V6] Connected to server - ONLINE MODE");
        g_is_online_mode = true;
        
        //--- Send CLIENT_HELLO to server
        SendClientHello();
    }
    
    //--- Set up timer for heartbeat
    EventSetTimer(HeartbeatInterval);
    
    Print("[FlashEA_V6] Initialization complete");
    Print("═══════════════════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit: Cleanup                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("[FlashEA_V6] Shutting down... (reason: ", reason, ")");
    
    //--- Kill timer
    EventKillTimer();
    
    //--- Disable all strategies
    g_strategy_manager.DisableAll_V6();
    
    //--- Close ZMQ connections (if implemented)
    // TODO: Call Protocol.Shutdown() when Protocol handler is ready
    
    Print("[FlashEA_V6] Shutdown complete");
}

//+------------------------------------------------------------------+
//| OnTick: Main tick handler                                        |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check connection status
    if(g_is_online_mode)
    {
        if(!g_connection_monitor.Check())
        {
            Print("[FlashEA_V6] Connection lost - switching to STANDALONE MODE");
            SwitchToStandaloneMode();
        }
    }
    
    //--- Get current tick
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick))
    {
        Print("[FlashEA_V6] ERROR: Cannot get tick data");
        return;
    }
    
    //--- Process strategies
    if(g_is_online_mode)
    {
        //--- Online mode: strategies enabled by CONFIG_PUSH
        g_strategy_manager.OnTick_V6(tick);
    }
    else if(g_is_standalone_mode)
    {
        //--- Standalone mode: strategies selected by regime detector
        g_strategy_manager.OnTick_V6(tick);
    }
    
    //--- TODO: Execute trades based on strategy signals
    // This will be implemented in Phase P1+ when strategies are ready
}

//+------------------------------------------------------------------+
//| OnTimer: Heartbeat handler (every 10 seconds)                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!g_is_online_mode)
    {
        return;  // No heartbeat in standalone mode
    }
    
    //--- Send heartbeat to server
    SendHeartbeat();
    
    //--- Try to receive messages from server
    ReceiveMessages();
}

//+------------------------------------------------------------------+
//| ConnectToServer: Attempt to connect to Python server             |
//+------------------------------------------------------------------+
bool ConnectToServer()
{
    // TODO: Implement ZMQ connection to server
    // For now, return false (placeholder)
    
    Print("[FlashEA_V6] Attempting to connect to server at ", ServerIP, ":", ServerPort);
    
    // Placeholder: always fail for now (will implement in P0-2)
    return false;
}

//+------------------------------------------------------------------+
//| SendClientHello: Send CLIENT_HELLO message to server             |
//+------------------------------------------------------------------+
void SendClientHello()
{
    Print("[FlashEA_V6] Sending CLIENT_HELLO to server...");
    
    // TODO: Implement CLIENT_HELLO message format (from P0-2)
    // Message type: 11 (CLIENT_HELLO)
    // Content: ClientID, Symbol, Timeframe, etc.
    
    g_connection_monitor.UpdateHeartbeat();
    g_message_count++;
}

//+------------------------------------------------------------------+
//| SendHeartbeat: Send HEARTBEAT message to server                  |
//+------------------------------------------------------------------+
void SendHeartbeat()
{
    // TODO: Implement HEARTBEAT message format (from P0-2)
    // Message type: 13 (HEARTBEAT)
    // Content: ClientID, Timestamp, Status
    
    g_last_heartbeat_sent = TimeCurrent();
    g_connection_monitor.UpdateHeartbeat();
    
    if(DebugMode)
    {
        Print("[FlashEA_V6] Heartbeat sent (", g_connection_monitor.GetStatus(), ")");
    }
}

//+------------------------------------------------------------------+
//| ReceiveMessages: Poll for messages from server                   |
//+------------------------------------------------------------------+
void ReceiveMessages()
{
    // TODO: Implement message reception from ZMQ (from P0-2)
    // Check for: CONFIG_PUSH, REGIME_CHANGE, NEWS_ALERT, COMMAND, etc.
    
    // Placeholder: no messages received yet
}

//+------------------------------------------------------------------+
//| ProcessMessage: Route message by type                            |
//+------------------------------------------------------------------+
void ProcessMessage(int message_type, const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] Processing message type: ", message_type);
    
    switch(message_type)
    {
        case 10:  // CONFIG_PUSH
            HandleConfigPush(data, data_size);
            break;
            
        case 31:  // REGIME_CHANGE
            HandleRegimeChange(data, data_size);
            break;
            
        case 30:  // NEWS_ALERT
            HandleNewsAlert(data, data_size);
            break;
            
        case 40:  // COMMAND
            HandleCommand(data, data_size);
            break;
            
        case 13:  // HEARTBEAT (from server)
            HandleHeartbeat(data, data_size);
            break;
            
        case 99:  // ERROR
            HandleError(data, data_size);
            break;
            
        default:
            Print("[FlashEA_V6] WARNING: Unknown message type: ", message_type);
            break;
    }
}

//+------------------------------------------------------------------+
//| HandleConfigPush: Process CONFIG_PUSH message                    |
//+------------------------------------------------------------------+
void HandleConfigPush(const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] Received CONFIG_PUSH");
    
    //--- Parse config
    if(!g_config_receiver.ReceiveConfig(data, data_size))
    {
        Print("[FlashEA_V6] ERROR: Failed to parse CONFIG_PUSH");
        return;
    }
    
    //--- Apply config to strategy manager
    SConfigData config = g_config_receiver.GetLastConfig();
    g_strategy_manager.ApplyConfig_V6(config);
    
    //--- Save for standalone mode
    g_config_receiver.SaveStandaloneConfig();
    
    Print("[FlashEA_V6] CONFIG_PUSH applied - ", g_strategy_manager.GetEnabledCount_V6(), 
          " strategies active");
}

//+------------------------------------------------------------------+
//| HandleRegimeChange: Process REGIME_CHANGE message                |
//+------------------------------------------------------------------+
void HandleRegimeChange(const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] Received REGIME_CHANGE");
    
    // TODO: Extract regime from message
    // Update strategy parameters based on new regime
}

//+------------------------------------------------------------------+
//| HandleNewsAlert: Process NEWS_ALERT message                      |
//+------------------------------------------------------------------+
void HandleNewsAlert(const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] Received NEWS_ALERT");
    
    // TODO: Extract news event info
    // Reduce risk or pause trading if high-impact event
}

//+------------------------------------------------------------------+
//| HandleCommand: Process COMMAND message                           |
//+------------------------------------------------------------------+
void HandleCommand(const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] Received COMMAND");
    
    // TODO: Extract command (e.g., PAUSE, RESUME, SHUTDOWN)
    // Execute command on EA
}

//+------------------------------------------------------------------+
//| HandleHeartbeat: Process HEARTBEAT from server                   |
//+------------------------------------------------------------------+
void HandleHeartbeat(const uchar &data[], int data_size)
{
    if(DebugMode)
    {
        Print("[FlashEA_V6] Heartbeat ACK from server");
    }
    
    g_connection_monitor.UpdateHeartbeat();
}

//+------------------------------------------------------------------+
//| HandleError: Process ERROR message                               |
//+------------------------------------------------------------------+
void HandleError(const uchar &data[], int data_size)
{
    Print("[FlashEA_V6] ERROR message from server");
    
    // TODO: Extract error details and log
}

//+------------------------------------------------------------------+
//| SwitchToStandaloneMode: Switch from Online to Standalone         |
//+------------------------------------------------------------------+
void SwitchToStandaloneMode()
{
    Print("[FlashEA_V6] ╔════════════════════════════════════════════╗");
    Print("[FlashEA_V6] ║  SWITCHING TO STANDALONE MODE              ║");
    Print("[FlashEA_V6] ╚════════════════════════════════════════════╝");
    
    g_is_online_mode = false;
    g_is_standalone_mode = true;
    
    //--- Disable all strategies first
    g_strategy_manager.DisableAll_V6();
    
    //--- Try to load saved config
    if(!g_config_receiver.LoadStandaloneConfig())
    {
        Print("[FlashEA_V6] No saved config found - enabling default standalone strategies");
    }
    
    //--- Enable 7 standalone strategies
    g_strategy_manager.EnableAllStandalone_V6();
    
    Print("[FlashEA_V6] Standalone mode active - ", g_strategy_manager.GetEnabledCount_V6(), 
          " strategies running");
}

//+------------------------------------------------------------------+
//| SwitchToOnlineMode: Switch from Standalone to Online             |
//+------------------------------------------------------------------+
void SwitchToOnlineMode()
{
    Print("[FlashEA_V6] ╔════════════════════════════════════════════╗");
    Print("[FlashEA_V6] ║  SWITCHING TO ONLINE MODE                  ║");
    Print("[FlashEA_V6] ╚════════════════════════════════════════════╝");
    
    g_is_standalone_mode = false;
    g_is_online_mode = true;
    
    //--- Disable all standalone strategies
    g_strategy_manager.DisableAll_V6();
    
    //--- Send CLIENT_HELLO to re-establish connection
    SendClientHello();
    
    Print("[FlashEA_V6] Online mode active - waiting for CONFIG_PUSH");
}

//+------------------------------------------------------------------+
//| GetConnectionStatus: Get current connection status               |
//+------------------------------------------------------------------+
string GetConnectionStatus()
{
    if(g_is_online_mode)
    {
        return "ONLINE (" + g_connection_monitor.GetStatus() + ")";
    }
    else if(g_is_standalone_mode)
    {
        return "STANDALONE";
    }
    else
    {
        return "DISCONNECTED";
    }
}

//+------------------------------------------------------------------+
//| GetEAStatus: Get comprehensive EA status                         |
//+------------------------------------------------------------------+
string GetEAStatus()
{
    string status = "";
    status += "╔════════════════════════════════════════════╗\n";
    status += "║  FlashEA V6 Status\n";
    status += "║  ─────────────────────────────────────────\n";
    status += "║  Mode: " + GetConnectionStatus() + "\n";
    status += "║  Strategies: " + IntegerToString(g_strategy_manager.GetEnabledCount_V6()) + 
              "/" + IntegerToString(TOTAL_STRATEGIES) + "\n";
    status += "║  Ticks: " + IntegerToString(g_strategy_manager.GetTotalTicksProcessed_V6()) + "\n";
    status += "║  Messages: " + IntegerToString(g_message_count) + "\n";
    status += "╚════════════════════════════════════════════╝";
    
    return status;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
