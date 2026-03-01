#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 - Configuration
Program B: The Brain

All configurable parameters in one place.
InfluxDB settings added for P0-4.

Author: Dr. Suksaeng Kukanok
Version: 2.1.0 (Added InfluxDB config)
Date: 2025-12-06
"""

import os

# =============================================================================
# ZMQ Configuration (existing - DO NOT CHANGE)
# =============================================================================
ZMQ_FEEDER_ADDRESS = "tcp://127.0.0.1:7777"    # Feeder → Brain (SUB)
ZMQ_POLICY_ADDRESS = "tcp://127.0.0.1:7778"    # Brain → Trader (PUB)
ZMQ_FEEDBACK_ADDRESS = "tcp://127.0.0.1:7779"  # Trader → Brain (PULL)

ZMQ_POLL_TIMEOUT_MS = 10       # Poll timeout in milliseconds
ZMQ_RECONNECT_INTERVAL_MS = 5000

# =============================================================================
# System Configuration (existing - DO NOT CHANGE)
# =============================================================================
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]
MONITOR_INTERVAL_SEC = 5
QUEUE_WARNING_SIZE = 100

# =============================================================================
# Message Type IDs (existing - DO NOT CHANGE)
# =============================================================================
MSG_TICK_DATA = 1
MSG_OHLC_DATA = 2
MSG_INDICATOR_DATA = 3
MSG_CONFIG_PUSH = 10
MSG_CLIENT_HELLO = 11
MSG_INITIAL_CONFIG = 12
MSG_HEARTBEAT = 13
MSG_TRADE_REPORT = 20
MSG_POSITION_UPDATE = 21
MSG_PERFORMANCE_METRICS = 22
MSG_NEWS_ALERT = 30
MSG_REGIME_CHANGE = 31
MSG_COMMAND = 40
MSG_POLICY_UPDATE = 50
MSG_ERROR = 99

# =============================================================================
# InfluxDB Configuration (NEW - P0-4)
# =============================================================================
INFLUXDB_URL = os.environ.get("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.environ.get("INFLUXDB_TOKEN", "_2Rnkee4DHBmXjDe60pILHKHGkXZ_uiB47SG_UcGg658WP_wNRf3XH7hFNFYq7S5w0rH2Uc240b7LoGGZCu3XA==")
INFLUXDB_ORG = os.environ.get("INFLUXDB_ORG", "flashea")
INFLUXDB_BUCKET = os.environ.get("INFLUXDB_BUCKET", "trading")

# Retention policy
DATA_RETENTION_DAYS = 180           # Total data retention
TICK_RAW_RETENTION_DAYS = 7         # Keep raw ticks for 7 days
                                     # After 7 days → downsample to OHLC M1
                                     # OHLC kept for full 180 days

# Write performance tuning
INFLUXDB_BATCH_SIZE = 500           # Points per batch write
INFLUXDB_FLUSH_INTERVAL_MS = 1000   # Auto-flush interval
INFLUXDB_WRITE_TIMEOUT_MS = 10000   # Write timeout

# Query defaults
INFLUXDB_DEFAULT_LOOKBACK_BARS = 500  # Default bars for ML features

# =============================================================================
# Measurement Names (InfluxDB)
# =============================================================================
MEASUREMENT_TICKS = "ticks"
MEASUREMENT_OHLC = "ohlc"
MEASUREMENT_INDICATORS = "indicators"

# =============================================================================
# Supported Timeframes
# =============================================================================
TIMEFRAMES = ["M1", "M5", "M15", "H1", "H4", "D1"]

# =============================================================================
# Derived Indicator Settings
# =============================================================================
INDICATOR_RSI_PERIOD = 14
INDICATOR_ATR_PERIOD = 14
INDICATOR_ADX_PERIOD = 14
INDICATOR_BB_PERIOD = 20
INDICATOR_BB_STD = 2.0
