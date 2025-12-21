//+------------------------------------------------------------------+
//|                                             Strategy_Grid.mqh    |
//|                                      FlashEASuite V2 - Program C |
//|                       Elastic Grid Strategy (Consolidated)       |
//+------------------------------------------------------------------+
#property strict
#include "StrategyBase.mqh"
#include <Trade/Trade.mqh>

enum ENUM_GRID_DIRECTION { GRID_DIR_NONE=0, GRID_DIR_BUY=1, GRID_DIR_SELL=-1 };

struct GridOrder {
   ulong ticket;
   double open_price;
   double lot_size;
   int level;
};

class CStrategyGrid : public CStrategyBase
  {
private:
   CTrade            m_trade;
   int               m_atr_handle;
   
   // --- Inputs ---
   int               m_max_orders;
   double            m_base_step;
   double            m_lot_multiplier; // ✅ แก้ชื่อให้ตรงกันเป๊ะๆ
   double            m_base_lot;
   double            m_sl_points;
   double            m_tp_points;
   
   // --- Policy Data ---
   double            m_risk_mult;
   bool              m_cooldown;
   double            m_confidence;
   double            m_csm_usd;
   double            m_csm_eur;
   
   // --- State ---
   ENUM_GRID_DIRECTION m_direction;
   double            m_elastic_step;
   
   // --- Tracking ---
   GridOrder         m_grid_orders[];
   int               m_active_count;
   double            m_last_grid_price;

public:
   CStrategyGrid() {
      m_name = "ElasticGrid";
      m_max_orders = 5;
      m_base_step = 200;
      m_lot_multiplier = 1.5; // ✅ ใช้ชื่อนี้
      m_base_lot = 0.01;
      m_sl_points = 500;
      m_tp_points = 300;
      
      m_risk_mult = 1.0;
      m_cooldown = false;
      m_confidence = 0.5;
      
      m_direction = GRID_DIR_NONE;
      m_active_count = 0;
      
      m_atr_handle = iATR(_Symbol, PERIOD_M15, 14);
      m_trade.SetExpertMagicNumber(999000);
      
      ArrayResize(m_grid_orders, m_max_orders);
   }
   
   ~CStrategyGrid() {
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
   }

   void UpdateConfig(int max, double step, double mult) {
      m_max_orders = max;
      m_base_step = step;
      m_lot_multiplier = mult; // ✅ ตรงกันแล้ว ไม่ Error แน่นอน
   }
   
   // ฟังก์ชันแก้ขัดสำหรับ UpdateConfig ที่เรียกใน ProgramC
   void UpdateConfig(int max, double step, double mult, double base_lot, int atr_period, double atr_ref) {
      m_max_orders = max;
      m_base_step = step;
      m_lot_multiplier = mult; // ✅ ตรงกัน
      m_base_lot = base_lot;
   }

   void UpdatePolicyData(double risk, bool cool, double conf) {
      m_risk_mult = risk;
      m_cooldown = cool;
      m_confidence = conf;
   }
   
   void UpdateCSMData(double usd, double eur) {
      m_csm_usd = usd;
      m_csm_eur = eur;
      if(usd > eur + 0.5) m_direction = GRID_DIR_SELL;
      else if(eur > usd + 0.5) m_direction = GRID_DIR_BUY;
      else m_direction = GRID_DIR_NONE;
   }

   virtual double GetScore() override {
      if(!m_is_active) return 0.0;
      if(m_cooldown) return 0.0;
      if(m_confidence < 0.3) return 0.0;
      
      // Update ATR & Elastic Step
      UpdateATR();
      
      // Update State
      UpdateGridState();
      
      // Check Condition
      if(m_direction != GRID_DIR_NONE && ShouldOpenNewLevel()) {
         return (m_direction == GRID_DIR_BUY) ? 50.0 : -50.0;
      }
      
      return 0.0;
   }
   
   void ExecuteGridOrder(ENUM_ORDER_TYPE type) {
      int level = m_active_count;
      // ใช้ m_lot_multiplier ที่ถูกต้อง
      double lot = m_base_lot * MathPow(m_lot_multiplier, level) * m_risk_mult;
      
      // Normalize Lot
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lot = MathFloor(lot / step_lot) * step_lot;
      lot = MathMax(lot, min_lot);
      
      double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = (m_sl_points > 0) ? (type==ORDER_TYPE_BUY ? price - m_sl_points*_Point : price + m_sl_points*_Point) : 0;
      double tp = (m_tp_points > 0) ? (type==ORDER_TYPE_BUY ? price + m_tp_points*_Point : price - m_tp_points*_Point) : 0;
      
      string comment = "Grid_L" + IntegerToString(level);
      
      if(m_trade.PositionOpen(_Symbol, type, lot, price, sl, tp, comment)) {
         Print("[Grid] Opened Level ", level, " | Lot: ", lot, " | Step: ", m_elastic_step/_Point);
      }
   }

private:
   void UpdateATR() {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_atr_handle, 0, 0, 1, atr) > 0) {
         double ratio = atr[0] / 30.0; 
         if(ratio < 0.5) ratio = 0.5;
         if(ratio > 2.0) ratio = 2.0;
         m_elastic_step = m_base_step * ratio * _Point;
      } else {
         m_elastic_step = m_base_step * _Point;
      }
   }
   
   void UpdateGridState() {
      m_active_count = 0;
      m_last_grid_price = 0;
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == 999000 &&
            StringFind(PositionGetString(POSITION_COMMENT), "Grid") >= 0) {
            m_active_count++;
            if(m_active_count == 1) m_last_grid_price = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
   }
   
   bool ShouldOpenNewLevel() {
      if(m_active_count >= m_max_orders) return false;
      if(m_active_count == 0) return true;
      
      MqlTick tick; SymbolInfoTick(_Symbol, tick);
      double current = (m_direction == GRID_DIR_BUY) ? tick.ask : tick.bid;
      double dist = MathAbs(current - m_last_grid_price);
      
      bool moved_against = false;
      if(m_direction == GRID_DIR_BUY && current < m_last_grid_price) moved_against = true;
      if(m_direction == GRID_DIR_SELL && current > m_last_grid_price) moved_against = true;
      
      return (moved_against && dist >= m_elastic_step);
   }
};