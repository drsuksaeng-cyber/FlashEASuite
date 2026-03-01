"""
FlashEASuite V2 - Program B (The Brain)
Configuration Module

Defines system-wide constants for ZMQ communication, 
networking, and risk management parameters.
"""

# ============================================================================
# ZMQ COMMUNICATION SETTINGS
# ============================================================================

# ZMQ Ports
ZMQ_FEEDER_PORT = 7777          # Subscribe to MQL5 Feeder (Tick Data + Spread Zone)
ZMQ_EXECUTION_PORT = 7778       # Publish to MQL5 Execution Client

# Network Configuration
ZMQ_FEEDER_ADDRESS = "tcp://*:7777"
ZMQ_EXECUTION_ADDRESS = "tcp://*:7778"

# ZMQ Performance Settings
ZMQ_SUB_HWM = 10000            # High Water Mark for SUB socket (prevent buffer overflow)
ZMQ_PUB_HWM = 10000            # High Water Mark for PUB socket
ZMQ_LINGER_MS = 1000           # Time to wait for pending messages on close (ms)
ZMQ_RCVTIMEO_MS = 100          # Receive timeout (ms) - for non-blocking operations
ZMQ_SNDTIMEO_MS = 100          # Send timeout (ms)

# Reconnection Settings
ZMQ_RECONNECT_IVL_MS = 100     # Reconnection interval (ms)
ZMQ_RECONNECT_IVL_MAX_MS = 5000  # Max reconnection interval (ms)

# ============================================================================
# MULTIPROCESSING SETTINGS
# ============================================================================

# Queue Sizes (to prevent memory issues)
INGESTION_QUEUE_SIZE = 50000    # Max items in ingestion queue
SIGNAL_QUEUE_SIZE = 10000       # Max items in signal queue

# Worker Configuration
INGESTION_WORKER_COUNT = 1      # Single ingestion worker (ZMQ serialization)
STRATEGY_WORKER_COUNT = 1       # Single strategy worker for now

# ============================================================================
# RISK MANAGEMENT CONSTANTS
# ============================================================================

# Position Sizing
MAX_POSITION_SIZE = 1.0         # Maximum lot size per trade
MIN_POSITION_SIZE = 0.01        # Minimum lot size per trade
DEFAULT_POSITION_SIZE = 0.1     # Default position size

# Risk Limits
MAX_DAILY_LOSS = 1000.0         # Maximum daily loss in account currency
MAX_DRAWDOWN_PCT = 10.0         # Maximum drawdown percentage
MAX_OPEN_POSITIONS = 5          # Maximum concurrent open positions

# Spread Filtering
MAX_SPREAD_POINTS = 20          # Maximum spread in points to accept trades
SPREAD_MULTIPLIER = 1.5         # Multiplier for dynamic spread filtering

# ============================================================================
# STRATEGY PARAMETERS
# ============================================================================

# Timeframes (for future multi-timeframe analysis)
PRIMARY_TIMEFRAME = "M5"
SECONDARY_TIMEFRAME = "M15"

# Signal Confidence Thresholds
MIN_SIGNAL_CONFIDENCE = 0.65    # Minimum confidence to generate signal
HIGH_CONFIDENCE_THRESHOLD = 0.85  # Threshold for high-confidence trades

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

LOG_LEVEL = "INFO"              # DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
LOG_FILE = "logs/flashea_brain.log"

# Performance Monitoring
ENABLE_PERFORMANCE_LOGGING = True
PERFORMANCE_LOG_INTERVAL = 60   # Log performance metrics every N seconds

# ============================================================================
# SYSTEM CONSTANTS
# ============================================================================

# Symbols (can be expanded)
SUPPORTED_SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]

# Shutdown
GRACEFUL_SHUTDOWN_TIMEOUT = 5.0  # Seconds to wait for graceful shutdown

# Health Check
HEARTBEAT_INTERVAL = 10         # Send heartbeat every N seconds
WATCHDOG_TIMEOUT = 30           # Consider process dead after N seconds

# ============================================================================
# FEATURE FLAGS
# ============================================================================

ENABLE_AI_PREDICTIONS = True    # Enable AI-based predictions (future)
ENABLE_RISK_MANAGEMENT = True   # Enable risk management checks
ENABLE_SIGNAL_FILTERING = True  # Enable signal quality filtering
ENABLE_PERFORMANCE_TRACKING = True  # Enable detailed performance tracking
