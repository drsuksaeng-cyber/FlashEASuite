//+------------------------------------------------------------------+
//|                                      Grid_Test_Mode_EA.mq5        |
//|                          Grid Strategy with TEST MODE enabled     |
//|                       Force RANGING market for immediate testing  |
//+------------------------------------------------------------------+
#property copyright "FlashEASuite V2 - Test Mode"
#property version   "1.00"
#property strict

// Include the main strategy
#include "Include/Logic/Grid/GridStandalone/Strategy_Grid_Standalone.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== 🧪 TEST MODE ==="
input bool     InpTestMode = true;                // 🧪 Enable Test Mode
input string   InpForceDirection = "AUTO";        // Force Direction (AUTO/BUY/SELL)
input int      InpTestDelaySeconds = 10;          // Delay before test entry (seconds)

input group "=== Grid Parameters ==="
input int      InpMaxGridLevels = 3;              // Max Grid Levels (smaller for test)
input double   InpBaseStepPoints = 200.0;         // Base Step (points)
input double   InpBaseLot = 0.01;                 // Base Lot Size

input group "=== Risk Management ==="
input double   InpMaxDD = 15.0;                   // Max Drawdown %
input double   InpMaxRiskPerGrid = 2.0;           // Max Risk Per Grid %

input group "=== Exit Parameters ==="
input double   InpProfitTargetMult = 1.5;         // Profit Target Multiplier
input int      InpMaxDurationHours = 24;          // Max Duration (hours) - shorter for test

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CStrategyGridStandalone* g_Strategy;
datetime g_TestStartTime = 0;
bool g_TestEntryDone = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════");
    Print("  🧪 GRID STRATEGY - TEST MODE");
    Print("  Forcing RANGING market...");
    Print("═══════════════════════════════════════");
    
    if(!InpTestMode)
    {
        Print("⚠️  Test Mode is DISABLED");
        Print("    Set InpTestMode = true to enable");
    }
    else
    {
        Print("✅ Test Mode ENABLED");
        Print("   Will force entry after ", InpTestDelaySeconds, " seconds");
        Print("   Direction: ", InpForceDirection);
        g_TestStartTime = TimeCurrent();
    }
    
    // Create strategy instance
    g_Strategy = new CStrategyGridStandalone();
    if(g_Strategy == NULL)
    {
        Print("ERROR: Failed to create strategy instance");
        return INIT_FAILED;
    }
    
    // Update configuration
    g_Strategy.UpdateConfig(InpMaxGridLevels, InpBaseStepPoints, InpBaseLot);
    
    // Initialize strategy
    if(!g_Strategy.Initialize(_Symbol, PERIOD_M15))
    {
        Print("ERROR: Strategy initialization failed");
        delete g_Strategy;
        return INIT_FAILED;
    }
    
    // Start timer (faster for testing)
    EventSetMillisecondTimer(100);
    
    Print("═══════════════════════════════════════");
    Print("  ✅ TEST MODE READY");
    Print("  Symbol: ", _Symbol);
    Print("  Waiting ", InpTestDelaySeconds, "s before force entry...");
    Print("═══════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_Strategy != NULL)
    {
        delete g_Strategy;
        g_Strategy = NULL;
    }
    
    EventKillTimer();
    
    Print("═══════════════════════════════════════");
    Print("  🧪 TEST MODE - Stopped");
    Print("═══════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Timer function - Test Mode Logic                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(g_Strategy == NULL) return;
    
    // Test Mode: Force entry after delay
    if(InpTestMode && !g_TestEntryDone)
    {
        int elapsed = (int)(TimeCurrent() - g_TestStartTime);
        
        if(elapsed >= InpTestDelaySeconds)
        {
            Print("🧪 TEST MODE: Forcing entry NOW!");
            Print("   Elapsed: ", elapsed, " seconds");
            
            // Force test entry
            ForceTestEntry();
            g_TestEntryDone = true;
        }
        else
        {
            // Show countdown
            static int last_countdown = -1;
            int remaining = InpTestDelaySeconds - elapsed;
            if(remaining != last_countdown)
            {
                Print("⏰ Countdown: ", remaining, " seconds until test entry...");
                last_countdown = remaining;
            }
        }
    }
    
    // Normal strategy update
    g_Strategy.OnTimer();
    
    // Show test status on chart
    if(InpTestMode)
    {
        ShowTestStatus();
    }
}

//+------------------------------------------------------------------+
//| Force Test Entry                                                  |
//+------------------------------------------------------------------+
void ForceTestEntry()
{
    Print("═══════════════════════════════════════");
    Print("  🧪 FORCING TEST ENTRY");
    Print("═══════════════════════════════════════");
    
    // Get current price
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick))
    {
        Print("ERROR: Cannot get tick data");
        return;
    }
    
    // Determine direction
    int direction = 0; // 0=auto, 1=buy, -1=sell
    
    if(InpForceDirection == "BUY")
    {
        direction = 1;
        Print("📊 Force Direction: BUY");
    }
    else if(InpForceDirection == "SELL")
    {
        direction = -1;
        Print("📊 Force Direction: SELL");
    }
    else
    {
        // Auto: Check current price position
        double mid_price = (tick.bid + tick.ask) / 2.0;
        
        // Simple logic: if price is in upper half, SELL; lower half, BUY
        MqlRates rates[];
        if(CopyRates(_Symbol, PERIOD_M15, 0, 20, rates) > 0)
        {
            double high = rates[ArrayMaximum(rates, 0, 20)].high;
            double low = rates[ArrayMinimum(rates, 0, 20)].low;
            double range = high - low;
            
            if(mid_price > low + range * 0.6)
            {
                direction = -1; // Upper area → SELL
                Print("📊 Auto Direction: SELL (price in upper range)");
            }
            else if(mid_price < low + range * 0.4)
            {
                direction = 1; // Lower area → BUY
                Print("📊 Auto Direction: BUY (price in lower range)");
            }
            else
            {
                // Middle area - choose randomly
                direction = (MathRand() % 2 == 0) ? 1 : -1;
                Print("📊 Auto Direction: ", (direction > 0 ? "BUY" : "SELL"), " (random, price in middle)");
            }
        }
    }
    
    // Calculate test parameters
    double step = InpBaseStepPoints * _Point;
    double lot = InpBaseLot;
    
    Print("═══════════════════════════════════════");
    Print("  📊 TEST GRID PARAMETERS:");
    Print("     Direction: ", (direction > 0 ? "BUY" : "SELL"));
    Print("     Levels: ", InpMaxGridLevels);
    Print("     Step: ", step);
    Print("     Base Lot: ", lot);
    Print("═══════════════════════════════════════");
    
    // Open test grid orders
    int opened = 0;
    for(int i = 0; i < InpMaxGridLevels; i++)
    {
        double price;
        int order_type;
        string comment = StringFormat("TEST Grid L%d", i+1);
        
        if(direction > 0) // BUY
        {
            price = tick.ask - (i * step);
            order_type = ORDER_TYPE_BUY;
        }
        else // SELL
        {
            price = tick.bid + (i * step);
            order_type = ORDER_TYPE_SELL;
        }
        
        // Calculate lot size (anti-martingale)
        double level_lot = lot;
        if(i > 0)
        {
            level_lot = NormalizeDouble(lot * (1.0 + i * 0.3), 2);
        }
        
        // Open order
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.volume = level_lot;
        request.type = order_type;
        request.price = price;
        request.deviation = 10;
        request.magic = 999999; // Test magic number
        request.comment = comment;
        
        if(OrderSend(request, result))
        {
            if(result.retcode == TRADE_RETCODE_DONE)
            {
                Print("✅ Test Order ", i+1, ": Ticket #", result.order, 
                      " | ", (direction > 0 ? "BUY" : "SELL"),
                      " ", level_lot, " @ ", price);
                opened++;
            }
            else
            {
                Print("❌ Test Order ", i+1, " failed: ", result.retcode, " - ", result.comment);
            }
        }
        
        Sleep(100); // Small delay between orders
    }
    
    Print("═══════════════════════════════════════");
    Print("  ✅ TEST ENTRY COMPLETE");
    Print("     Orders opened: ", opened, " / ", InpMaxGridLevels);
    Print("═══════════════════════════════════════");
    Print("");
    Print("📊 Now watch the grid behavior:");
    Print("   - Price movement");
    Print("   - P&L updates");
    Print("   - Exit conditions");
    Print("   - Risk management");
    Print("");
    Print("Press 'S' to see dashboard");
}

//+------------------------------------------------------------------+
//| Show Test Status on Chart                                         |
//+------------------------------------------------------------------+
void ShowTestStatus()
{
    string label_name = "TestModeStatus";
    
    // Count test orders
    int test_orders = 0;
    double total_profit = 0.0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            if(PositionGetInteger(POSITION_MAGIC) == 999999)
            {
                test_orders++;
                total_profit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    
    // Create or update label
    if(ObjectFind(0, label_name) < 0)
    {
        ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, label_name, OBJPROP_FONT, "Arial Bold");
    }
    
    string status_text;
    if(!g_TestEntryDone)
    {
        int remaining = InpTestDelaySeconds - (int)(TimeCurrent() - g_TestStartTime);
        status_text = StringFormat("🧪 TEST MODE | Entry in: %ds", remaining);
    }
    else if(test_orders > 0)
    {
        status_text = StringFormat("🧪 TEST MODE | Orders: %d | P&L: %.2f", 
                                   test_orders, total_profit);
        
        // Change color based on profit
        if(total_profit > 0)
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrLime);
        else if(total_profit < 0)
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrRed);
    }
    else
    {
        status_text = "🧪 TEST MODE | Waiting for exit...";
    }
    
    ObjectSetString(0, label_name, OBJPROP_TEXT, status_text);
}

//+------------------------------------------------------------------+
//| Trade function (optional - for advanced features)                |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Can add trade event handling here if needed
}

//+------------------------------------------------------------------+
//| Keyboard event (for manual control)                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        // 'T' key = Force test entry immediately
        if(lparam == 84 && InpTestMode && !g_TestEntryDone) // T key
        {
            Print("🧪 Manual trigger: Forcing test entry NOW!");
            ForceTestEntry();
            g_TestEntryDone = true;
        }
        
        // 'C' key = Close all test orders
        if(lparam == 67) // C key
        {
            Print("🧪 Closing all test orders...");
            CloseAllTestOrders();
        }
    }
}

//+------------------------------------------------------------------+
//| Close all test orders                                             |
//+------------------------------------------------------------------+
void CloseAllTestOrders()
{
    int closed = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            if(PositionGetInteger(POSITION_MAGIC) == 999999)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                
                request.action = TRADE_ACTION_DEAL;
                request.position = ticket;
                request.symbol = _Symbol;
                request.volume = PositionGetDouble(POSITION_VOLUME);
                request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                               ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                request.price = (request.type == ORDER_TYPE_SELL) ? 
                                SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                request.deviation = 10;
                
                if(OrderSend(request, result))
                {
                    if(result.retcode == TRADE_RETCODE_DONE)
                    {
                        Print("✅ Closed test order #", ticket);
                        closed++;
                    }
                }
            }
        }
    }
    
    Print("═══════════════════════════════════════");
    Print("  Closed ", closed, " test orders");
    Print("═══════════════════════════════════════");
}
//+------------------------------------------------------------------+
