-- ============================================================================
-- FlashEASuite V2 — Strategy Parameter History Schema
-- Phase: P0.6-1
-- Date: 2026-02-16
-- Target: InfluxDB 2.x (Flux query language)
-- ============================================================================

-- ============================================================================
-- MEASUREMENT: strategy_parameter_history
-- ============================================================================
-- InfluxDB ไม่ใช้ CREATE TABLE — schema กำหนดด้วย line protocol
-- เอกสารนี้เป็น reference สำหรับ Python code ที่ write data

-- MEASUREMENT NAME: strategy_parameter_history
--
-- TAGS (indexed, searchable):
--   strategy_id   : string  (e.g. "S01", "S15", "S16")
--   symbol        : string  (e.g. "XAUUSD", "EURUSD")
--   param_name    : string  (e.g. "S01_LOOKBACK_PERIOD", "S15_ELASTIC_FACTOR")
--   broker        : string  (e.g. "ICMarkets", "Exness") — optional
--   family        : string  (e.g. "MOMENTUM_TIMING", "GRID_STRUCTURE")
--   category      : string  (e.g. "signal_generation", "risk_management")
--   change_source : string  (e.g. "optimizer", "manual", "emergency", "regime_change")
--
-- FIELDS (values, not indexed):
--   value         : float   — new parameter value
--   old_value     : float   — previous parameter value
--   change_pct    : float   — percentage change ((new-old)/old × 100)
--   reason        : string  — human-readable reason for change
--   regime        : string  — market regime at time of change
--   optimizer_score : float — optimizer confidence in this change (0-1)
--   trade_count   : int     — number of trades since last change

-- TIMESTAMP: automatic (nanosecond precision)

-- ============================================================================
-- LINE PROTOCOL EXAMPLE
-- ============================================================================
-- strategy_parameter_history,strategy_id=S15,symbol=XAUUSD,param_name=S15_ELASTIC_FACTOR,broker=ICMarkets,family=GRID_STRUCTURE,category=signal_generation,change_source=optimizer value=1.8,old_value=1.5,change_pct=20.0,reason="ATR increased — wider grid spacing",regime="VOLATILE",optimizer_score=0.85,trade_count=42 1708099200000000000

-- ============================================================================
-- RETENTION POLICIES
-- ============================================================================
-- Python code ที่ใช้ InfluxDB client ต้องสร้าง bucket ด้วย retention rules:

-- Bucket: flashea_params_raw
--   Retention: 30 days
--   Description: Raw parameter changes ทุกครั้งที่มีการเปลี่ยน
--   Usage: Recent history, debugging, rollback

-- Bucket: flashea_params_weekly
--   Retention: 365 days (1 year)
--   Description: Weekly aggregated — ค่าเฉลี่ย/min/max ของแต่ละ param per week
--   Usage: Long-term trend analysis, seasonal patterns

-- ============================================================================
-- DOWNSAMPLING TASK (Flux)
-- ============================================================================
-- สร้าง InfluxDB Task สำหรับ aggregate weekly:

-- option task = {name: "downsample_params_weekly", every: 1d, offset: 1h}
--
-- from(bucket: "flashea_params_raw")
--   |> range(start: -7d)
--   |> filter(fn: (r) => r._measurement == "strategy_parameter_history")
--   |> group(columns: ["strategy_id", "symbol", "param_name", "broker", "family"])
--   |> aggregateWindow(every: 1w, fn: mean, column: "value", createEmpty: false)
--   |> set(key: "_measurement", value: "strategy_parameter_history_weekly")
--   |> to(bucket: "flashea_params_weekly")

-- ============================================================================
-- PYTHON WRITE EXAMPLE
-- ============================================================================
-- from influxdb_client import InfluxDBClient, Point
-- from datetime import datetime
--
-- point = (
--     Point("strategy_parameter_history")
--     .tag("strategy_id", "S15")
--     .tag("symbol", "XAUUSD")
--     .tag("param_name", "S15_ELASTIC_FACTOR")
--     .tag("broker", "ICMarkets")
--     .tag("family", "GRID_STRUCTURE")
--     .tag("category", "signal_generation")
--     .tag("change_source", "optimizer")
--     .field("value", 1.8)
--     .field("old_value", 1.5)
--     .field("change_pct", 20.0)
--     .field("reason", "ATR increased — wider grid spacing")
--     .field("regime", "VOLATILE")
--     .field("optimizer_score", 0.85)
--     .field("trade_count", 42)
--     .time(datetime.utcnow())
-- )

-- ============================================================================
-- USEFUL FLUX QUERIES
-- ============================================================================

-- Query 1: Get latest value of all params for S15
-- from(bucket: "flashea_params_raw")
--   |> range(start: -30d)
--   |> filter(fn: (r) => r._measurement == "strategy_parameter_history")
--   |> filter(fn: (r) => r.strategy_id == "S15")
--   |> filter(fn: (r) => r._field == "value")
--   |> group(columns: ["param_name"])
--   |> last()

-- Query 2: Parameter change frequency per strategy (last 7 days)
-- from(bucket: "flashea_params_raw")
--   |> range(start: -7d)
--   |> filter(fn: (r) => r._measurement == "strategy_parameter_history")
--   |> filter(fn: (r) => r._field == "value")
--   |> group(columns: ["strategy_id"])
--   |> count()

-- Query 3: Changes triggered by regime_change
-- from(bucket: "flashea_params_raw")
--   |> range(start: -7d)
--   |> filter(fn: (r) => r._measurement == "strategy_parameter_history")
--   |> filter(fn: (r) => r.change_source == "regime_change")
--   |> filter(fn: (r) => r._field == "value" or r._field == "old_value")
--   |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")

-- ============================================================================
-- VALIDATION COUNTS
-- ============================================================================
-- Total strategy parameters: 138
-- Strategies: S01(10) + S02(5) + S03(10) + S04(8) + S05(8) + S06(10)
--           + S07(8) + S08(6) + S09(8) + S10(8) + S11(8) + S12(8)
--           + S13(8) + S14(8) + S15(12) + S16(11) = 138
-- Parameter families: 14
-- Retention: 30 days raw, 365 days weekly aggregated
