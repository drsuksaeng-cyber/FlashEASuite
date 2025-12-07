//+------------------------------------------------------------------+
//|                                     Strategy_Implementation.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                                      Smart Execution Logic       |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#include <Trade/Trade.mqh>
#include "PolicyManager.mqh"

//+------------------------------------------------------------------+
//| Smart Executor Class                                             |
//+------------------------------------------------------------------+
class CSmartExecutor
  {
private:
   CTrade            m_trade;           // Execution Module
   CPolicyManager*   m_policy_mgr;      // Reference to Policy Manager
   int               m_magic_number;
   
public:
   // Constructor
   CSmartExecutor() { }
   
   // Initialization
   void Initialize(CPolicyManager* policy_mgr, int magic)
     {
      m_policy_mgr = policy_mgr;
      m_magic_number = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC); 
      // หมายเหตุ: ถ้า Backtest ไม่ได้ ให้เปลี่ยนเป็น ORDER_FILLING_FOK หรือ return true
     }

   // --- Main Execution Loop (เรียกใน OnTick) ---
   void Execute()
     {
      // 1. เช็คโหมดก่อน
      if(m_policy_mgr.IsStandaloneMode())
        {
         ExecuteStandalone();
        }
      else
        {
         ExecuteHybrid();
        }

      // 2. จัดการออเดอร์เก่า (Trailing / Break-even)
      ManagePositions();
     }

private:
   // --- Logic 1: Standalone (Defensive) ---
   void ExecuteStandalone()
     {
      // ตัวอย่าง: ถ้าขาดการติดต่อ Brain ให้เทรดแบบ Grid ธรรมดา หรือไม่เปิดเพิ่ม
      // Print("Operating in Standalone Mode (Defensive)");
     }

   // --- Logic 2: Hybrid (Brain Guided) ---
   void ExecuteHybrid()
     {
      // อ่าน Policy ล่าสุด
      // PolicyMsg current_policy = m_policy_mgr.GetCurrentPolicy();
      
      // ตัวอย่าง: ถ้า Brain บอก "Sniper Mode" และ RSI < 30 -> BUY
      // (ตรงนี้คือจุดที่อาจารย์ใส่ Logic หน้างานเพิ่มได้)
     }

   // --- Logic 3: Intelligent Exit (Trailing / Partial Close) ---
   void ManagePositions()
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetInteger(POSITION_MAGIC) == m_magic_number)
              {
               double profit_points = 0; // คำนวณกำไรเป็นจุด...
               // ใส่ Logic Trailing Stop ตรงนี้
               // m_trade.PositionModify(ticket, new_sl, tp);
              }
           }
        }
     }
  };
//+------------------------------------------------------------------+