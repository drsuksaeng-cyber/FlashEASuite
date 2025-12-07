# FlashEASuite V2 - Quick Start Testing Guide

## Prerequisites

```bash
# Install dependencies
pip install pyzmq msgpack
```

## Testing Without MQL5

You can test the Python infrastructure without the MQL5 Feeder by using the test simulator.

### Step 1: Start the Test Feeder (Terminal 1)

```bash
python test_feeder.py
```

Expected output:
```
================================================================================
FlashEA Test Feeder Simulator
================================================================================
ZMQ Publisher bound to tcp://*:7777
Waiting 2 seconds for subscribers to connect...
Starting to publish test tick data...
Press Ctrl+C to stop
--------------------------------------------------------------------------------
Published 100 messages | Latest: EURUSD Bid=1.08512 Ask=1.08517
Published 200 messages | Latest: GBPUSD Bid=1.26489 Ask=1.26493
...
```

### Step 2: Start the Brain (Terminal 2)

```bash
python main.py
```

Expected output:
```
================================================================================
FlashEASuite V2 - Program B (The Brain)
High-Frequency Hybrid Trading System
================================================================================
2024-11-27 10:00:00 - FlashEABrain - INFO - Starting FlashEA Brain...
2024-11-27 10:00:00 - FlashEABrain - INFO - Starting multiprocessing workers...
2024-11-27 10:00:00 - IngestionWorker.IngestionWorker-1 - INFO - Connected to MQL5 Feeder at tcp://localhost:7777
2024-11-27 10:00:00 - StrategyEngine.StrategyEngine-1 - INFO - Starting StrategyEngine-1 (PID: 12346)
2024-11-27 10:01:00 - IngestionWorker.IngestionWorker-1 - INFO - Performance: 98.5 msg/s | Processed: 5910 | Errors: 0 | Success Rate: 100.00% | Queue Size: 12
```

### Step 3: Monitor Logs

In a third terminal:

```bash
tail -f logs/flashea_brain.log
```

### Step 4: Graceful Shutdown

In the Brain terminal, press `Ctrl+C`:

```
^C
2024-11-27 10:05:00 - FlashEABrain - WARNING - Received SIGINT, initiating graceful shutdown...
2024-11-27 10:05:00 - FlashEABrain - INFO - Shutting down workers...
2024-11-27 10:05:01 - IngestionWorker.IngestionWorker-1 - INFO - Shutdown event received, stopping ingestion loop
2024-11-27 10:05:01 - FlashEABrain - INFO - IngestionWorker-1 stopped cleanly
2024-11-27 10:05:02 - FlashEABrain - INFO - All workers stopped
2024-11-27 10:05:02 - FlashEABrain - INFO - FlashEA Brain shutdown complete
```

Also stop the test feeder in Terminal 1 with `Ctrl+C`.

## Performance Testing

### Adjust Tick Frequency

In `test_feeder.py`, modify the sleep duration:

```python
# High frequency: 1000 ticks/sec
time.sleep(0.001)

# Medium frequency: 100 ticks/sec (default)
time.sleep(0.01)

# Low frequency: 10 ticks/sec
time.sleep(0.1)
```

### Monitor System Resources

```bash
# CPU and Memory usage
top -p $(pgrep -f "python main.py")

# Network statistics
netstat -an | grep 7777
```

## Troubleshooting

### "Connection refused" Error

If you see this error in the Brain logs:
```
zmq.error.ZMQError: Connection refused
```

**Solution**: Make sure the test feeder is running first (Terminal 1) before starting the Brain (Terminal 2).

### High Queue Size Warning

If you see warnings about queue size:
```
WARNING - Output queue full, dropping message
```

**Solution**: The Strategy Engine is processing slower than ingestion. This is expected with the placeholder engine. When you implement real strategy logic, ensure it processes ticks fast enough.

### Process Not Stopping

If workers don't stop cleanly with `Ctrl+C`:

```bash
# Find Python processes
ps aux | grep python

# Force kill if necessary
kill -9 <PID>
```

## Next Steps

1. ✅ Infrastructure tested and working
2. 🔄 Implement Strategy Engine AI logic in `core/strategy.py`
3. 🔄 Add execution publisher to send signals to Program C
4. 🔄 Integrate with real MQL5 Feeder (Program A)
5. 🔄 Add FastAPI REST interface for monitoring
6. 🔄 Implement risk management logic

## Performance Benchmarks

With the test setup, you should observe:
- **Ingestion Rate**: 80-100 msg/s (limited by test feeder sleep)
- **Processing Rate**: 80-100 ticks/s
- **Success Rate**: > 99.9%
- **Queue Size**: < 50 (stable)
- **CPU Usage**: < 10% (with placeholder strategy)
- **Memory**: < 100 MB per process

## Integration with Real MQL5

Once Program A (MQL5 Feeder) is ready:

1. Stop the test feeder
2. Start Program A in MT5
3. Start the Brain (main.py)
4. Monitor logs for real tick data

The Brain will automatically connect to the real MQL5 Feeder on port 7777.
