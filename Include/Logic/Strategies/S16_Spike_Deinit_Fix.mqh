//+------------------------------------------------------------------+
//|  FlashEASuite V2 — S16_Spike Memory Leak Fix (P9-1)             |
//|  แก้ไข: 6 dynamic objects ไม่ถูก delete ใน Deinit = 11,520 bytes |
//|  วันที่: 2026-02-25                                              |
//+------------------------------------------------------------------+
//
// ปัญหา (จาก P8-4 Lessons Learned):
//   Deinit() เดิมไม่ได้ delete CArrayObj, CList, หรือ pointer objects
//   ที่สร้างใน Init() ทำให้หน่วยความจำรั่ว 11,520 bytes ทุกครั้ง
//   ที่ EA ถูก deinit (เช่น restart, optimization run)
//
// วิธีแก้ไข:
//   1. ระบุทุก dynamic object ที่สร้างใน Init()
//   2. สร้าง idempotent Deinit() ที่ check NULL ก่อน delete ทุกครั้ง
//   3. Set pointer = NULL หลัง delete (ป้องกัน double-free)
//
// Pattern ที่ถูกต้องสำหรับ MQL5:
//
// ❌ WRONG — memory leak
//   void Deinit() override {}
//
// ✅ CORRECT — idempotent cleanup
//   void Deinit() override {
//       if(m_spike_detector != NULL) {
//           delete m_spike_detector;
//           m_spike_detector = NULL;
//       }
//       if(m_buffer != NULL) {
//           delete m_buffer;
//           m_buffer = NULL;
//       }
//       // ... repeat for all 6 objects
//   }
//
//=======================================================================
// PATCH: เพิ่มโค้ดต่อไปนี้ใน S16_Spike.mqh หรือ Strategy_Spike.mqh
//=======================================================================

// ------ ส่วนที่ 1: เพิ่ม member variables (ถ้ายังไม่มี) ------
// ตรวจสอบว่า class มี pointer members เหล่านี้ไหม:
/*
private:
    CSpikeDetector*     m_spike_detector;   // object 1
    CRingBuffer*        m_price_buffer;     // object 2
    CRingBuffer*        m_vol_buffer;       // object 3
    CSpikeStat*         m_stat_tracker;     // object 4
    CArrayDouble*       m_levels;           // object 5
    CSignalFilter*      m_filter;           // object 6
*/

// ------ ส่วนที่ 2: Init() ต้องตั้งค่า pointer ก่อนสร้าง ------
/*
bool Init(string symbol, ENUM_TIMEFRAMES tf) override {
    // Reset all pointers (สำคัญมาก — ป้องกัน double-init)
    m_spike_detector = NULL;
    m_price_buffer   = NULL;
    m_vol_buffer     = NULL;
    m_stat_tracker   = NULL;
    m_levels         = NULL;
    m_filter         = NULL;
    
    // Create objects
    m_spike_detector = new CSpikeDetector(symbol, tf);
    if(m_spike_detector == NULL) { Deinit(); return false; }
    
    m_price_buffer = new CRingBuffer(200);
    if(m_price_buffer == NULL) { Deinit(); return false; }
    
    // ... etc for all 6 objects
    return true;
}
*/

// ------ ส่วนที่ 3: Deinit() ที่ถูกต้อง (IDEMPOTENT) ------
/*
void Deinit() override {
    // ตรวจ NULL ก่อน delete ทุกตัว — ทำได้หลายครั้งโดยปลอดภัย
    if(m_spike_detector != NULL) {
        delete m_spike_detector;
        m_spike_detector = NULL;
    }
    if(m_price_buffer != NULL) {
        delete m_price_buffer;
        m_price_buffer = NULL;
    }
    if(m_vol_buffer != NULL) {
        delete m_vol_buffer;
        m_vol_buffer = NULL;
    }
    if(m_stat_tracker != NULL) {
        delete m_stat_tracker;
        m_stat_tracker = NULL;
    }
    if(m_levels != NULL) {
        delete m_levels;
        m_levels = NULL;
    }
    if(m_filter != NULL) {
        delete m_filter;
        m_filter = NULL;
    }
}
*/

// ------ ส่วนที่ 4: Destructor ต้องเรียก Deinit() ------
/*
~CS16_Spike() {
    Deinit();   // ป้องกัน leak ถ้า destructor ถูกเรียกโดยตรง
}
*/

//=======================================================================
// วิธีทดสอบ (หลัง apply fix):
//=======================================================================
// 1. เปิด MetaTrader 5 → Tools → Profiler
// 2. Run Strategy Tester → Custom → S16_Spike
// 3. หลัง optimization ปิด → ดู Memory column
// 4. ต้องไม่มี +11,520 bytes accumulated ทุก run
//
// หรือใช้ Print statement ใน Deinit():
//   Print("S16 Deinit: cleaning up 6 objects...");
//   // ... delete ...
//   Print("S16 Deinit: done. Memory freed.");
//=======================================================================
