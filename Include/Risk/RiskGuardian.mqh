//+------------------------------------------------------------------+
//|                                             RiskGuardian.mqh     |
//|                                    FlashEASuite V2 - Program C   |
//+------------------------------------------------------------------+
#property copyright "Dr. Suksaeng Kukanok"
#property strict

#include <Trade/AccountInfo.mqh>

class CRiskGuardian
  {
private:
   double            m_user_hard_limit_percent; // เช่น 2.0%
   double            m_initial_equity;
   CAccountInfo      m_account;

public:
   CRiskGuardian() { }

   bool Initialize(double user_max_risk)
     {
      m_user_hard_limit_percent = user_max_risk;
      m_initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      if(m_initial_equity <= 0) return false;
      return true;
     }

   // --- เช็คว่า "ผ่าน" หรือไม่ (User Limit vs AI Risk) ---
   // คืนค่า: Lot Size ที่ปลอดภัยที่สุด (หรือ 0.0 ถ้าห้ามเทรด)
   double ValidateEntry(string symbol, double ai_risk_scale, double base_lot)
     {
      // 1. เช็ค Emergency ก่อน
      if(IsEmergency()) return 0.0;

      // 2. ปรับ Lot ตาม AI (Dynamic Risk)
      // เช่น Base 0.1, AI บอกขอเสี่ยง 0.8 -> Lot = 0.08
      double final_lot = base_lot * ai_risk_scale;

      // 3. (Optional) เช็ค Spread Zone ตรงนี้ได้
      
      return final_lot;
     }

   // --- เช็คความปลอดภัยสูงสุด (ตัดจบ) ---
   bool IsEmergency()
     {
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      // ถ้าขาดทุนเกิน Hard Limit (เช่น เริ่ม 1000, เหลือ 980 -> หายไป 2%)
      double drawdown_percent = (m_initial_equity - current_equity) / m_initial_equity * 100.0;
      
      if(drawdown_percent >= m_user_hard_limit_percent)
        {
         return true; // อันตราย! หยุดเทรด
        }
        
      return false; // ปลอดภัย
     }
  };
//+------------------------------------------------------------------+