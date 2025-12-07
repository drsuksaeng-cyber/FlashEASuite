//+------------------------------------------------------------------+
//|                                                 StrategyBase.mqh |
//|                                      FlashEASuite V2 - Program C |
//+------------------------------------------------------------------+
#property strict

class CStrategyBase
  {
protected:
   double            m_weight;
   bool              m_is_active;
   string            m_name;

public:
   CStrategyBase() { m_weight = 1.0; m_is_active = true; m_name = "Base"; }
   virtual ~CStrategyBase() {}

   void SetWeight(double w)   { m_weight = w; }
   double GetWeight()         { return m_weight; }
   string GetName()           { return m_name; }
   
   // --- [FIX] เติมฟังก์ชันนี้กลับมา เพื่อให้ Manager เรียกใช้ได้ ---
   bool IsActive()            { return m_is_active; }
   void SetActive(bool flag)  { m_is_active = flag; }
   // -----------------------------------------------------------

   // 1. ขอคะแนน (-100 ถึง 100)
   virtual double GetScore() { return 0.0; }

   // 2. ขอระยะ SL/TP ที่แนะนำ
   virtual double GetRecommendedSL() { return 500; } 
   virtual double GetRecommendedTP() { return 100; } 
   
   // 3. รับ Config
   virtual void UpdateConfig(double param1, double param2) {}
  };
//+------------------------------------------------------------------+