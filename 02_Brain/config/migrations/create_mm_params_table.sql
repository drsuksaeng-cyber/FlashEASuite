-- ============================================================
-- FlashEASuite V2 — P0.6-2: MM Parameter History Table
-- InfluxDB Line Protocol Compatible Schema
-- Created: 2026-02
-- ============================================================

-- ============================================================
-- 1. Measurement: mm_parameter_history
--    บันทึกทุกครั้งที่ MM parameter เปลี่ยนค่า
-- ============================================================
-- Tags (indexed):
--   mm_method   : MM01-MM19
--   param_name  : MM01_RISK_PCT, MM03_ATR_PERIOD, ...
--   symbol      : XAUUSD, EURUSD, ... (ถ้า symbol-specific)
--   broker      : broker identifier (optional)
--   source      : optimizer / manual / config_push / default
--
-- Fields:
--   value       : float — ค่าใหม่
--   old_value   : float — ค่าเดิม
--   change_pct  : float — % การเปลี่ยนแปลง
--   reason      : string — เหตุผลที่เปลี่ยน (Thai text)
--   confidence  : float — ความมั่นใจของ optimizer (0.0-1.0)
--   cycle_id    : integer — optimization cycle ที่เปลี่ยน
--
-- Retention Policy:
--   raw  : 30 days  (ทุก change event)
--   weekly: 1 year  (aggregated weekly — avg/min/max)

CREATE DATABASE IF NOT EXISTS flasheasuite_v2;

-- Raw parameter changes — 30 day retention
CREATE RETENTION POLICY "mm_param_raw_30d" ON "flasheasuite_v2"
    DURATION 30d REPLICATION 1 DEFAULT;

-- Weekly aggregated — 1 year retention  
CREATE RETENTION POLICY "mm_param_weekly_1y" ON "flasheasuite_v2"
    DURATION 365d REPLICATION 1;

-- Continuous query: aggregate weekly
CREATE CONTINUOUS QUERY "cq_mm_param_weekly" ON "flasheasuite_v2"
BEGIN
    SELECT
        MEAN("value")       AS "avg_value",
        MIN("value")        AS "min_value",
        MAX("value")        AS "max_value",
        COUNT("value")      AS "change_count",
        MEAN("change_pct")  AS "avg_change_pct",
        MEAN("confidence")  AS "avg_confidence"
    INTO "mm_param_weekly_1y"."mm_parameter_history"
    FROM "mm_param_raw_30d"."mm_parameter_history"
    GROUP BY time(1w), "mm_method", "param_name", "symbol"
END;

-- ============================================================
-- 2. Measurement: mm_selection_history
--    บันทึกเมื่อ strategy เปลี่ยน MM method
-- ============================================================
-- Tags:
--   strategy_id : S01-S16
--   symbol      : XAUUSD, EURUSD, ...
--   regime      : TRENDING / RANGING / VOLATILE / CRISIS
--
-- Fields:
--   old_mm      : string — MM method เดิม
--   new_mm      : string — MM method ใหม่
--   trigger     : string — สาเหตุ (regime_change / dd_override / optimizer / manual)
--   dd_pct      : float  — DD% ณ ตอนเปลี่ยน
--   reasoning   : string — คำอธิบาย (Thai)

-- Uses same retention policies as mm_parameter_history

-- ============================================================
-- 3. Measurement: mm_performance_tracking
--    บันทึก performance ของแต่ละ MM method
-- ============================================================
-- Tags:
--   mm_method   : MM01-MM19
--   strategy_id : S01-S16
--   symbol      : XAUUSD, EURUSD, ...
--   regime      : TRENDING / RANGING / VOLATILE / CRISIS
--
-- Fields:
--   trade_pnl       : float — P/L ของ trade
--   lot_size         : float — Lot ที่ MM คำนวณ
--   risk_pct         : float — Risk% ที่ใช้
--   win              : integer — 1=win, 0=loss
--   drawdown_at_entry: float — DD% ณ ตอนเข้าเทรด
--   duration_seconds : integer — ระยะเวลาถือ

-- Retention: 180 days raw, 1 year weekly
CREATE RETENTION POLICY "mm_perf_raw_180d" ON "flasheasuite_v2"
    DURATION 180d REPLICATION 1;

CREATE CONTINUOUS QUERY "cq_mm_perf_weekly" ON "flasheasuite_v2"
BEGIN
    SELECT
        MEAN("trade_pnl")      AS "avg_pnl",
        SUM("trade_pnl")       AS "total_pnl",
        MEAN("lot_size")       AS "avg_lot",
        MEAN("risk_pct")       AS "avg_risk",
        SUM("win")             AS "wins",
        COUNT("win")           AS "total_trades",
        MAX("drawdown_at_entry") AS "max_dd_at_entry"
    INTO "mm_param_weekly_1y"."mm_performance_tracking"
    FROM "mm_perf_raw_180d"."mm_performance_tracking"
    GROUP BY time(1w), "mm_method", "strategy_id", "symbol"
END;

-- ============================================================
-- Example Line Protocol Writes:
-- ============================================================
-- mm_parameter_history,mm_method=MM01,param_name=MM01_RISK_PCT,symbol=XAUUSD,source=optimizer value=1.5,old_value=1.0,change_pct=50.0,reason="Sharpe สูง ปรับ Risk ขึ้น",confidence=0.82,cycle_id=47
-- mm_selection_history,strategy_id=S15,symbol=XAUUSD,regime=VOLATILE old_mm="MM03",new_mm="MM17",trigger="regime_change",dd_pct=8.5,reasoning="ตลาด Volatile ย้ายจาก ATR→Regime"
-- mm_performance_tracking,mm_method=MM03,strategy_id=S15,symbol=XAUUSD,regime=RANGING trade_pnl=45.20,lot_size=0.05,risk_pct=1.8,win=1i,drawdown_at_entry=3.2,duration_seconds=1800i
