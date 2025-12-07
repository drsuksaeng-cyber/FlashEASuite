//+------------------------------------------------------------------+
//|                                                 SpreadFilter.mqh |
//|                                    FlashEASuite V2 - Program C   |
//|                                      Standalone Spread Check     |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

class CSpreadFilter
  {
private:
   double            m_sum_spread;
   int               m_count;
   double            m_avg_spread;
   int               m_max_samples;
   
   // เกณฑ์การตัด (เช่น 2.0 เท่าของค่าเฉลี่ย)
   double            m_ratio_limit;

public:
   CSpreadFilter()
     {
      m_sum_spread = 0;
      m_count = 0;
      m_avg_spread = 0;
      m_max_samples = 1000; // ค่าเฉลี่ยเคลื่อนที่อย่างง่าย (สะสม 1000 tick แล้ว reset หรือใช้ MA)
      m_ratio_limit = 2.0;  // Default Standalone Limit
     }

   void OnTick()
     {
      double current_spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
      
      // คำนวณค่าเฉลี่ยแบบ Cumulative Moving Average (ง่ายและเร็ว)
      m_count++;
      m_sum_spread += current_spread;
      
      // รีเซ็ตถ้านานเกินไป (เพื่อให้ค่าเฉลี่ย Update ตามเวลาปัจจุบัน)
      if(m_count > m_max_samples) {
         m_avg_spread = m_sum_spread / m_count; // เก็บค่าล่าสุดไว้เป็นฐาน
         m_sum_spread = m_avg_spread; // เริ่มนับใหม่จากค่าเฉลี่ย
         m_count = 1;
      }
      
      m_avg_spread = m_sum_spread / m_count;
     }

   bool IsSpreadSafe()
     {
      double current_spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
      
      if(m_avg_spread == 0) return true; // เพิ่งเริ่ม
      
      double ratio = current_spread / m_avg_spread;
      
      // ถ้าถ่างเกิน Limit -> ไม่ปลอดภัย
      if(ratio > m_ratio_limit) return false;
      
      return true;
     }
     
   // ให้ Python มาอัปเดต Limit ได้ ถ้าต่อกันติด
   void UpdateLimit(double limit) { m_ratio_limit = limit; }
  };
//+------------------------------------------------------------------+