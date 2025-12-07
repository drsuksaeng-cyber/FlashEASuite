# FlashEASuite V2 - Program B (The Brain)

**High-Frequency Hybrid Trading System - Python Server Component**

Author: Dr. Suksaeng Kukanok  
Version: 2.0.0

---

## Architecture Overview

Program B is the central intelligence component of FlashEASuite V2, implementing a high-performance multiprocessing architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    FlashEA Brain (main.py)                   │
│                  Multiprocessing Orchestrator                │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
    ┌───────────▼──────────┐    ┌──────────▼──────────┐
    │  Ingestion Worker    │    │  Strategy Engine    │
    │  (ZMQ SUB)           │───▶│  (AI Processing)    │
    │  core/ingestion.py   │    │  core/strategy.py   │
    └───────────┬──────────┘    └──────────┬──────────┘
                │                           │
    ┌───────────▼──────────┐    ┌──────────▼──────────┐
    │  MQL5 Feeder         │    │  Signal Queue       │
    │  (Port 7777)         │    │  (Future: Exec)     │
    └──────────────────────┘    └─────────────────────┘
```

### Components

1. **Ingestion Worker** (`core/ingestion.py`)
   - Subscribes to tick data from MQL5 Feeder via ZMQ (port 7777)
   - Decodes MessagePack binary data
   - High Water Mark (HWM) protection against buffer overflow
   - Automatic reconnection on disconnection
   - Pushes decoded data to multiprocessing queue

2. **Strategy Engine** (`core/strategy.py`)
   - Consumes tick data from ingestion queue
   - Placeholder for AI-based prediction models
   - Future: Technical analysis, signal generation, risk management

3. **Main Orchestrator** (`main.py`)
   - Manages multiprocessing lifecycle
   - Graceful shutdown handling (SIGINT, SIGTERM)
   - Performance monitoring and logging
   - Resource cleanup

---

## Requirements

- Python 3.8+
- ZeroMQ library
- MessagePack

---

## Installation

1. **Install Python dependencies:**

```bash
pip install -r requirements.txt
```

2. **Verify ZMQ installation:**

```bash
python -c "import zmq; print(f'ZMQ version: {zmq.zmq_version()}')"
```

Expected output: `ZMQ version: 4.3.x` (or higher)

---

## Configuration

Edit `config.py` to customize:

### ZMQ Settings
```python
ZMQ_FEEDER_PORT = 7777          # MQL5 Feeder port
ZMQ_EXECUTION_PORT = 7778       # Execution client port
ZMQ_SUB_HWM = 10000            # High Water Mark
```

### Risk Management
```python
MAX_POSITION_SIZE = 1.0         # Maximum lot size
MAX_DAILY_LOSS = 1000.0         # Maximum daily loss
MAX_SPREAD_POINTS = 20          # Maximum spread filter
```

### Performance
```python
INGESTION_QUEUE_SIZE = 50000    # Ingestion queue capacity
PERFORMANCE_LOG_INTERVAL = 60   # Log metrics every 60s
```

---

## Usage

### Start the Brain

```bash
python main.py
```

### Expected Output

```
================================================================================
FlashEASuite V2 - Program B (The Brain)
High-Frequency Hybrid Trading System
================================================================================
2024-11-27 10:00:00 - FlashEABrain - INFO - Starting FlashEA Brain...
2024-11-27 10:00:00 - FlashEABrain - INFO - Configuration: ZMQ Feeder=tcp://localhost:7777
2024-11-27 10:00:00 - FlashEABrain - INFO - Starting multiprocessing workers...
2024-11-27 10:00:00 - FlashEABrain - INFO - Ingestion Worker started (PID: 12345)
2024-11-27 10:00:00 - FlashEABrain - INFO - Strategy Engine started (PID: 12346)
2024-11-27 10:00:00 - FlashEABrain - INFO - System is running. Press Ctrl+C to stop.
2024-11-27 10:00:01 - IngestionWorker.IngestionWorker-1 - INFO - Connected to MQL5 Feeder at tcp://localhost:7777
```

### Graceful Shutdown

Press `Ctrl+C` or send `SIGTERM`:

```bash
# Send interrupt signal
kill -SIGTERM <PID>

# Or just use Ctrl+C in terminal
```

---

## Performance Monitoring

The system logs performance metrics every 60 seconds (configurable):

```
Performance: 1250.45 msg/s | Processed: 75027 | Errors: 3 | Success Rate: 99.996% | Queue Size: 245
```

Metrics tracked:
- **Message rate**: Messages per second
- **Success rate**: Percentage of successfully processed messages
- **Queue size**: Current queue depth
- **Error count**: Failed operations

---

## Project Structure

```
FlashEASuite_V2_Brain/
├── main.py                 # Entry point
├── config.py               # Configuration constants
├── requirements.txt        # Python dependencies
├── README.md              # This file
├── core/
│   ├── __init__.py        # Package initialization
│   ├── ingestion.py       # ZMQ ingestion worker
│   └── strategy.py        # Strategy engine (placeholder)
└── logs/
    └── flashea_brain.log  # Application logs
```

---

## Key Features

### 1. **Multiprocessing Architecture**
- Separate processes for I/O and computation
- Non-blocking operations with timeouts
- Process isolation for fault tolerance

### 2. **ZMQ High-Performance Messaging**
- Sub-20ms target latency
- High Water Mark (HWM) protection
- Automatic reconnection
- Binary MessagePack serialization

### 3. **Robust Error Handling**
- ZMQ disconnection recovery
- MessagePack decoding validation
- Queue overflow protection
- Graceful degradation

### 4. **Production-Ready Logging**
- File and console output
- Performance metrics
- Structured log format
- Configurable log levels

### 5. **Graceful Shutdown**
- Signal handling (SIGINT, SIGTERM)
- Worker cleanup with timeout
- Queue draining
- Resource release

---

## Integration with MQL5

### MQL5 Feeder (Program A)
The Brain expects MessagePack-encoded tick data from the MQL5 Feeder on port 7777 with the following structure:

```python
{
    'symbol': 'EURUSD',
    'bid': 1.08456,
    'ask': 1.08459,
    'spread': 3,
    'time': 1732700000,
    'spread_zone': 'NORMAL',  # NORMAL, HIGH, EXTREME
    # Additional fields as needed
}
```

### MQL5 Execution Client (Program C)
Future: The Brain will publish trading signals to port 7778 for execution.

---

## Future Enhancements

- [ ] AI-based prediction models (TensorFlow/PyTorch)
- [ ] FastAPI REST interface for monitoring
- [ ] Multi-symbol parallel processing
- [ ] Advanced technical indicators
- [ ] Risk management engine
- [ ] Position sizing optimization
- [ ] Real-time performance dashboard
- [ ] Database integration (TimescaleDB/QuestDB)

---

## Troubleshooting

### ZMQ Connection Issues

**Problem**: `zmq.error.ZMQError: Connection refused`

**Solution**:
1. Verify MQL5 Feeder (Program A) is running
2. Check port configuration matches (7777)
3. Verify firewall allows local connections

### High Memory Usage

**Problem**: Python process consuming excessive memory

**Solution**:
1. Reduce `INGESTION_QUEUE_SIZE` in config.py
2. Check for message processing bottlenecks
3. Monitor queue depths in logs

### Worker Process Crashes

**Problem**: Worker died unexpectedly

**Solution**:
1. Check logs/flashea_brain.log for errors
2. Verify ZMQ library compatibility
3. Ensure sufficient system resources

---

## Performance Benchmarks

Target performance metrics:
- **End-to-End Latency**: < 20ms (tick reception to signal generation)
- **Throughput**: > 1000 ticks/second per symbol
- **Message Loss**: < 0.01%
- **CPU Usage**: < 50% on modern hardware

---

## License

Proprietary - Dr. Suksaeng Kukanok

---

## Support

For questions or issues, refer to the main FlashEASuite V2 documentation.

---

**Version History**

- **v2.0.0** (2024-11-27): Initial infrastructure release
  - Multiprocessing architecture
  - ZMQ ingestion worker
  - Graceful shutdown handling
  - Performance monitoring
