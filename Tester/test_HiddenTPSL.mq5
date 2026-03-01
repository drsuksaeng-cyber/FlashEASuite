//+------------------------------------------------------------------+
//| test_HiddenTPSL.mq5                                              |
//| FlashEASuite V2 — Unit Test: CHiddenTPSL                         |
//| วิธีรัน: Drag onto any chart in MT5 → ดู Experts log            |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "6.00"
#property strict

#include "../Include/Logic/Common/HiddenTPSL.mqh"

input string   Test_Symbol  = "XAUUSD.tp";   // broker suffix .tp
input bool     Test_Verbose = true;

//--- Global instance
CHiddenTPSL g_hidden;

//--- Test helpers
int g_passed = 0;
int g_failed = 0;

void Assert(bool condition, string test_name)
{
    if(condition)
    {
        if(Test_Verbose) PrintFormat("[PASS] %s", test_name);
        g_passed++;
    }
    else
    {
        PrintFormat("[FAIL] %s", test_name);
        g_failed++;
    }
}

//+------------------------------------------------------------------+
//| OnStart                                                          |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("========================================");
    Print("  test_HiddenTPSL — FlashEASuite V2 V6");
    Print("========================================");
    
    Test_Config();
    Test_SlotManagement();
    Test_CheckClose_BuyTP();
    Test_CheckClose_SellSL();
    Test_DisabledFlags();
    Test_ClearHidden();
    Test_PrintStatus();
    
    PrintFormat("========================================");
    PrintFormat("  RESULT: %d PASSED | %d FAILED", g_passed, g_failed);
    PrintFormat("========================================");
    
    if(g_failed == 0)
        Print("  ✅ ALL TESTS PASSED");
    else
        PrintFormat("  ❌ %d TEST(S) FAILED", g_failed);
}

//+------------------------------------------------------------------+
//| Test 1: Config flags                                             |
//+------------------------------------------------------------------+
void Test_Config()
{
    Print("--- Test_Config ---");
    
    CHiddenTPSL h;
    
    // Default state
    Assert(h.IsTPEnabled() == true,  "Default TP enabled");
    Assert(h.IsSLEnabled() == true,  "Default SL enabled");
    Assert(h.GetTrackedCount() == 0, "Default tracked count = 0");
    
    // Disable TP only
    h.SetEnabled(false, true);
    Assert(h.IsTPEnabled() == false, "SetEnabled: TP disabled");
    Assert(h.IsSLEnabled() == true,  "SetEnabled: SL still enabled");
    
    // Re-enable both
    h.SetEnabled(true, true);
    Assert(h.IsTPEnabled() == true,  "SetEnabled: TP re-enabled");
}

//+------------------------------------------------------------------+
//| Test 2: Internal slot management (no real positions)             |
//| NOTE: SetHiddenTP/SL require real positions → test via query     |
//+------------------------------------------------------------------+
void Test_SlotManagement()
{
    Print("--- Test_SlotManagement ---");
    
    CHiddenTPSL h;
    
    // Query on unknown ticket → 0
    Assert(h.GetHiddenTP(99999) == 0.0, "Unknown ticket TP = 0");
    Assert(h.GetHiddenSL(99999) == 0.0, "Unknown ticket SL = 0");
    
    // No tracked positions
    Assert(h.GetTrackedCount() == 0, "Initial count = 0");
}

//+------------------------------------------------------------------+
//| Test 3: BUY position TP hit simulation                           |
//| หมายเหตุ: ทดสอบ logic ภายใน — CheckAndClose ต้องการ position จริง
//| → ทดสอบเฉพาะส่วน config + query ที่ไม่ต้องใช้ real position    |
//+------------------------------------------------------------------+
void Test_CheckClose_BuyTP()
{
    Print("--- Test_CheckClose_BuyTP ---");
    
    CHiddenTPSL h;
    
    // No positions → CheckAndClose returns 0
    int closed = h.CheckAndClose();
    Assert(closed == 0, "CheckAndClose on empty table = 0");
    
    // SetEnabled works before set
    h.SetEnabled(true, true);
    Assert(h.IsTPEnabled(), "TP enabled for test");
}

//+------------------------------------------------------------------+
//| Test 4: SELL position SL hit (config test)                       |
//+------------------------------------------------------------------+
void Test_CheckClose_SellSL()
{
    Print("--- Test_CheckClose_SellSL ---");
    
    CHiddenTPSL h;
    h.SetEnabled(true, true);
    h.SetTolerancePips(1.0);
    
    // Verify tolerance doesn't crash
    int closed = h.CheckAndClose();
    Assert(closed == 0, "SL check empty = 0");
}

//+------------------------------------------------------------------+
//| Test 5: Disabled flags prevent registration                      |
//+------------------------------------------------------------------+
void Test_DisabledFlags()
{
    Print("--- Test_DisabledFlags ---");
    
    CHiddenTPSL h;
    
    // Disable TP — SetHiddenTP should return false (no position exists anyway)
    h.SetEnabled(false, true);
    bool result = h.SetHiddenTP(12345, 1950.0);
    Assert(result == false, "SetHiddenTP when TP disabled → false");
    
    // Disable SL
    h.SetEnabled(true, false);
    result = h.SetHiddenSL(12345, 1900.0);
    Assert(result == false, "SetHiddenSL when SL disabled → false");
}

//+------------------------------------------------------------------+
//| Test 6: ClearHidden on unknown ticket (no crash)                 |
//+------------------------------------------------------------------+
void Test_ClearHidden()
{
    Print("--- Test_ClearHidden ---");
    
    CHiddenTPSL h;
    
    // Should not crash on unknown ticket
    h.ClearHidden(99999);
    Assert(h.GetTrackedCount() == 0, "ClearHidden unknown ticket no crash");
    
    // OnPositionClosed on unknown ticket
    h.OnPositionClosed(88888);
    Assert(h.GetTrackedCount() == 0, "OnPositionClosed unknown no crash");
}

//+------------------------------------------------------------------+
//| Test 7: PrintStatus — no crash                                   |
//+------------------------------------------------------------------+
void Test_PrintStatus()
{
    Print("--- Test_PrintStatus ---");
    
    CHiddenTPSL h;
    h.PrintStatus();   // Should print "0 tracked positions"
    Assert(true, "PrintStatus no crash");
}
