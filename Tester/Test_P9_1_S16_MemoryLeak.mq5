//+------------------------------------------------------------------+
//| Test_P9_1_S16_MemoryLeak.mq5                                     |
//| FlashEASuite V2 — P9-1: Verify BUG-001 Fix                       |
//| วัตถุประสงค์: ยืนยันว่า S16_Spike.mqh ไม่รั่ว memory หลัง patch  |
//+------------------------------------------------------------------+
//| วิธีรัน:                                                          |
//|   MT5 → Strategy Tester → แนบไฟล์นี้                             |
//|   Mode: Custom period หรือ Single pass                           |
//|   ดูผลใน tab "Journal"                                           |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property version   "9.01"
#property strict

// ─── Include paths ตาม tree ───────────────────────────────────────
#include "../Include/Logic/Strategies/S16_Spike.mqh"

// ─── Test configuration ───────────────────────────────────────────
#define INIT_CYCLES   10     // Init/Deinit กี่รอบ
#define SYMBOL_TEST   "XAUUSD"
#define PASS_MARK     "✅ PASS"
#define FAIL_MARK     "❌ FAIL"

// ─── Globals ─────────────────────────────────────────────────────
CS16Spike  g_spike;
int               g_pass_count = 0;
int               g_fail_count = 0;


//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================================");
    Print("FlashEASuite V2 — P9-1: S16 Memory Leak Fix Test");
    Print("========================================================");
    
    RunAllTests();
    
    Print("========================================================");
    PrintFormat("TOTAL: %d PASS / %d FAIL", g_pass_count, g_fail_count);
    if(g_fail_count == 0)
        Print("🏆 BUG-001 FIXED — S16 memory leak resolved");
    else
        Print("⚠️ STILL LEAKING — Check Deinit() patch");
    Print("========================================================");
    
    return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}


//+------------------------------------------------------------------+
//| OnTick — ไม่ใช้ (test-only EA)                                   |
//+------------------------------------------------------------------+
void OnTick() {}


//+------------------------------------------------------------------+
//| RunAllTests                                                      |
//+------------------------------------------------------------------+
void RunAllTests()
{
    Test1_InitDeinitSingle();
    Test2_InitDeinitRepeat();
    Test3_DeinitWithoutInit();
    Test4_DoubleDestroyProtection();
    Test5_MemoryAfterCycles();
}


//+------------------------------------------------------------------+
//| Test 1: Init + Deinit ครั้งเดียว — ต้อง Print message จาก Deinit |
//+------------------------------------------------------------------+
void Test1_InitDeinitSingle()
{
    Print("\n── Test 1: Single Init/Deinit ──");
    CS16Spike spike;
    
    bool ok = spike.Init(SYMBOL_TEST, PERIOD_M15);
    if(!ok)
    {
        Print(FAIL_MARK, " Init() failed — ตรวจสอบ symbol และ indicators");
        g_fail_count++;
        return;
    }
    Print("  Init OK | initialized=", spike.IsInitialized());
    
    spike.Deinit();
    Print("  Deinit called");
    
    // หลัง Deinit: initialized ต้อง false
    bool after_deinit = spike.IsInitialized();
    if(!after_deinit)
    {
        Print(PASS_MARK, " Test 1: m_initialized=false after Deinit ✅");
        g_pass_count++;
    }
    else
    {
        Print(FAIL_MARK, " Test 1: m_initialized ยังเป็น true — IStrategy::Deinit() ไม่ถูกเรียก");
        g_fail_count++;
    }
}


//+------------------------------------------------------------------+
//| Test 2: Init/Deinit หลายรอบ — ตรวจ idempotency                  |
//+------------------------------------------------------------------+
void Test2_InitDeinitRepeat()
{
    PrintFormat("\n── Test 2: %d×Init/Deinit cycles ──", INIT_CYCLES);
    
    bool all_ok = true;
    for(int i = 0; i < INIT_CYCLES; i++)
    {
        CS16Spike spike;
        
        bool init_ok = spike.Init(SYMBOL_TEST, PERIOD_M15);
        spike.Deinit();
        
        if(!init_ok)
        {
            PrintFormat("  Cycle %d: Init() failed", i+1);
            all_ok = false;
            break;
        }
    }
    
    if(all_ok)
    {
        PrintFormat(PASS_MARK + " Test 2: %d cycles completed without crash ✅", INIT_CYCLES);
        g_pass_count++;
    }
    else
    {
        Print(FAIL_MARK, " Test 2: crash ใน Init/Deinit cycle");
        g_fail_count++;
    }
}


//+------------------------------------------------------------------+
//| Test 3: Deinit ก่อน Init — ต้องไม่ crash (idempotent)           |
//+------------------------------------------------------------------+
void Test3_DeinitWithoutInit()
{
    Print("\n── Test 3: Deinit without Init (should not crash) ──");
    
    CS16Spike spike;
    spike.Deinit();   // เรียก Deinit ก่อนที่จะ Init
    spike.Deinit();   // เรียกซ้ำ
    
    // ถ้าถึงบรรทัดนี้ได้โดยไม่ crash = pass
    Print(PASS_MARK, " Test 3: Double Deinit without crash ✅");
    g_pass_count++;
}


//+------------------------------------------------------------------+
//| Test 4: Init → Deinit → Init → Deinit (re-init pattern)         |
//+------------------------------------------------------------------+
void Test4_DoubleDestroyProtection()
{
    Print("\n── Test 4: Re-Init after Deinit ──");
    
    CS16Spike spike;
    
    // รอบแรก
    bool ok1 = spike.Init(SYMBOL_TEST, PERIOD_M15);
    spike.Deinit();
    
    // รอบสอง (re-init หลัง deinit)
    bool ok2 = spike.Init(SYMBOL_TEST, PERIOD_M15);
    spike.Deinit();
    
    if(ok1 && ok2)
    {
        Print(PASS_MARK, " Test 4: Re-Init after Deinit works ✅");
        g_pass_count++;
    }
    else
    {
        PrintFormat(FAIL_MARK + " Test 4: ok1=%s ok2=%s — pointer reset ใน Init() ผิด",
                    ok1 ? "true" : "false", ok2 ? "true" : "false");
        g_fail_count++;
    }
}


//+------------------------------------------------------------------+
//| Test 5: Memory stability — ตรวจ heap ก่อนและหลัง cycles          |
//+------------------------------------------------------------------+
void Test5_MemoryAfterCycles()
{
    PrintFormat("\n── Test 5: Memory stability after %d cycles ──", INIT_CYCLES * 5);
    
    // MQL5 ไม่มี GetUsedMemory() โดยตรงใน EA
    // ใช้ MQLInfoInteger(MQL_MEMORY_USED) ถ้า available
    // หรือสังเกตจาก "Memory" column ใน Tester
    
    long mem_before = MQLInfoInteger(MQL_MEMORY_USED);
    
    for(int i = 0; i < INIT_CYCLES * 5; i++)
    {
        CS16Spike spike;
        spike.Init(SYMBOL_TEST, PERIOD_M15);
        spike.Deinit();
    }
    
    long mem_after = MQLInfoInteger(MQL_MEMORY_USED);
    long mem_delta = mem_after - mem_before;
    
    // ยอมรับ ±50KB สำหรับ GC และ allocation fragmentation
    bool stable = (mem_delta < 50 * 1024);
    
    PrintFormat("  Memory before: %d KB | after: %d KB | delta: %+d bytes",
                mem_before / 1024, mem_after / 1024, mem_delta);
    
    if(stable)
    {
        Print(PASS_MARK, " Test 5: Memory stable — no significant accumulation ✅");
        g_pass_count++;
    }
    else
    {
        PrintFormat(FAIL_MARK + " Test 5: Memory grew %d bytes — STILL LEAKING!", mem_delta);
        PrintFormat("  คาดหวัง: 0 bytes | ก่อนแก้: +%d bytes per cycle",
                    11520);
        g_fail_count++;
    }
}
