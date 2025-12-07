//+------------------------------------------------------------------+
//|                                          StrategyManager.mqh     |
//|                                      FlashEASuite V2 - Program C |
//|                                          The Council (Manager)   |
//+------------------------------------------------------------------+
#property strict

// ต้อง Include Base และ Grid เพื่อให้รู้จัก Class ลูก
#include "StrategyBase.mqh"
#include "Strategy_Grid.mqh" 
#include <Trade/Trade.mqh>

class CStrategyManager
  {
private:
   CStrategyBase* m_strategies[];
   int               m_total_strategies;
   CTrade            m_trade;
   double            m_vote_threshold;

public:
   CStrategyManager()
     {
      m_vote_threshold = 40.0; // คะแนนขั้นต่ำในการโหวตผ่าน
      m_total_strategies = 0;
      m_trade.SetExpertMagicNumber(999000); 
     }
     
   ~CStrategyManager()
     {
      // ลบ Object ที่สร้างด้วย new เพื่อคืนหน่วยความจำ
      for(int i=0; i<ArraySize(m_strategies); i++) 
        {
         if(CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) 
            delete m_strategies[i];
        }
      ArrayResize(m_strategies, 0);
     }

   void Initialize() 
     { 
      // เตรียมความพร้อม (ถ้ามี Logic เสริม)
     }
     
   void AddStrategy(CStrategyBase* strat)
     {
      m_total_strategies = ArraySize(m_strategies);
      ArrayResize(m_strategies, m_total_strategies + 1);
      m_strategies[m_total_strategies] = strat;
     }

   // --- หัวใจหลัก: การโหวต (The Council Vote) ---
   void OnTickLogic()
     {
      // [FIX] ลบบรรทัดนี้ออก เพื่อให้ Grid ทำงานต่อได้แม้มีออเดอร์ค้าง
      // if(PositionsTotal() > 0) return; 

      double total_buy_score = 0;
      double total_sell_score = 0;
      
      // 1. วนลูปถามคะแนนจากทุก Strategy (Spike, Grid, etc.)
      for(int i=0; i<ArraySize(m_strategies); i++)
        {
         // ข้ามถ้า Strategy ปิดอยู่
         if(!m_strategies[i].IsActive()) continue;

         double raw_score = m_strategies[i].GetScore(); 
         double weight = m_strategies[i].GetWeight();   
         
         // คะแนนถ่วงน้ำหนัก
         double weighted_score = raw_score * weight;
         
         if(weighted_score > 0) total_buy_score += weighted_score;
         else if(weighted_score < 0) total_sell_score += MathAbs(weighted_score); 
        }
        
      // 2. ตัดสินใจ (Execute Decision)
      if(total_buy_score > m_vote_threshold && total_buy_score > total_sell_score)
        {
         Print(">> COUNCIL VOTE BUY! Score: ", total_buy_score);
         ExecuteTradeWithGrid(ORDER_TYPE_BUY); // เรียกตัวใหม่ที่รองรับ Grid
        }
      else if(total_sell_score > m_vote_threshold && total_sell_score > total_buy_score)
        {
         Print(">> COUNCIL VOTE SELL! Score: ", total_sell_score);
         ExecuteTradeWithGrid(ORDER_TYPE_SELL); // เรียกตัวใหม่ที่รองรับ Grid
        }
     }
     
   // ฟังก์ชันเปิดเทรดแบบปกติ (สำหรับ Spike)
   void ExecuteTrade(ENUM_ORDER_TYPE type)
     {
      // ตรวจสอบว่ามีออเดอร์ Spike ค้างอยู่ไหม (ปกติ Spike เปิดทีละไม้)
      // แต่ถ้าเป็น Grid มันจะจัดการตัวเองใน ExecuteTradeWithGrid
      if(PositionsTotal() == 0) // เปิดไม้แรก
        {
         double lot = 0.01;
         double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_trade.PositionOpen(_Symbol, type, lot, price, 0, 0, "Council_Action");
        }
     }
   
   // --- [FIX] ฟังก์ชันใหม่: รองรับทั้งเทรดปกติและ Grid ---
   void ExecuteTradeWithGrid(ENUM_ORDER_TYPE type)
     {
      // 1. ให้ Strategy ทั่วไปทำงาน (เช่น Spike เปิดไม้แรก)
      ExecuteTrade(type);
      
      // 2. เช็คว่า Grid Strategy ต้องการทำงานไหม (เติมไม้)
      for(int i=0; i<ArraySize(m_strategies); i++)
        {
         // เช็คชื่อว่าเป็น ElasticGrid หรือไม่
         if(m_strategies[i].GetName() == "ElasticGrid")
           {
            // แปลงร่าง (Cast) เพื่อเรียกฟังก์ชันเฉพาะของ Grid
            CStrategyGrid* grid = dynamic_cast<CStrategyGrid*>(m_strategies[i]);
            
            if(CheckPointer(grid) != POINTER_INVALID)
              {
               // ให้ Grid ตัดสินใจเองว่าจะเปิดไม้เพิ่มไหม (เช็คระยะ/ATR ข้างใน)
               grid.ExecuteGridOrder(type);
              }
           }
        }
     }
  };
//+------------------------------------------------------------------+