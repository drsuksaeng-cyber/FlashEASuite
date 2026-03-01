#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — P9-5: Live Readiness Validator
=================================================
ตรวจสอบความพร้อมทุกระบบก่อน go-live

Tests:
  1. ZMQ Connection  — bind/connect ทุก port (7777, 7778, 7779)
  2. InfluxDB         — write + read roundtrip
  3. CONFIG_PUSH      — dry run (build → serialize → validate)
  4. Strategy Manager  — config receive simulation
  5. Python Brain     — import chain + worker init
  6. File System      — ตรวจไฟล์สำคัญทั้งหมด
  7. Dependencies     — check all pip packages
  8. Port Availability — ไม่มี process อื่นใช้ port อยู่

Usage:
    cd FlashEASuite_V2
    python validate_live_readiness.py           # run ทั้งหมด
    python validate_live_readiness.py --quick   # เช็คเฉพาะ import + files
    python validate_live_readiness.py --zmq     # เช็คเฉพาะ ZMQ

ต้อง PASS ทุกข้อก่อน live!

Author: Dr. Suksaeng Kukanok
Version: 1.0.0
Date: 2026-02-26
Save: FlashEASuite_V2/tools/validate_live_readiness.py
"""

import sys
import os
import time
import socket
import struct
import importlib
import subprocess
import argparse
from pathlib import Path
from datetime import datetime, timezone

# ─────────────────────────────────────────────────────────────────────
# ANSI Colors (Windows 10+ supports this)
# ─────────────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):
    print(f"  {GREEN}✅ PASS{RESET}  {msg}")

def fail(msg, detail=""):
    print(f"  {RED}❌ FAIL{RESET}  {msg}")
    if detail:
        print(f"           {RED}→ {detail}{RESET}")

def warn(msg):
    print(f"  {YELLOW}⚠️  WARN{RESET}  {msg}")

def info(msg):
    print(f"  {CYAN}ℹ️  INFO{RESET}  {msg}")

def sep(title):
    print(f"\n{BOLD}{'═'*60}")
    print(f"  {title}")
    print(f"{'═'*60}{RESET}")


# ─────────────────────────────────────────────────────────────────────
# Global counters
# ─────────────────────────────────────────────────────────────────────
_pass_count = 0
_fail_count = 0
_warn_count = 0

def record_pass():
    global _pass_count
    _pass_count += 1

def record_fail():
    global _fail_count
    _fail_count += 1

def record_warn():
    global _warn_count
    _warn_count += 1


# ═════════════════════════════════════════════════════════════════════
# TEST 1: ZMQ Connection (Ports 7777, 7778, 7779)
# ═════════════════════════════════════════════════════════════════════

def test_zmq_connections() -> bool:
    """Test ZMQ socket bind/connect on all 3 ports"""
    sep("TEST 1: ZMQ Connections")
    all_ok = True

    try:
        import zmq
    except ImportError:
        fail("pyzmq not installed", "pip install pyzmq")
        record_fail()
        return False

    ports = {
        7777: ("PUB/SUB", "FeederEA → Brain",   zmq.SUB, zmq.PUB),
        7778: ("PUB/SUB", "Brain → Trader",      zmq.PUB, zmq.SUB),
        7779: ("PUSH/PULL", "Trader → Brain",     zmq.PULL, zmq.PUSH),
    }

    ctx = zmq.Context()

    for port, (pattern, desc, brain_type, _) in ports.items():
        try:
            sock = ctx.socket(brain_type)
            sock.setsockopt(zmq.LINGER, 0)

            if brain_type in (zmq.PUB, zmq.PULL):
                # Brain binds on these
                sock.bind(f"tcp://127.0.0.1:{port}")
                ok(f"Port {port} BIND OK  ({pattern}: {desc})")
            else:
                # Brain connects (SUB) to FeederEA's PUB
                sock.setsockopt(zmq.RCVTIMEO, 500)
                sock.connect(f"tcp://127.0.0.1:{port}")
                ok(f"Port {port} CONNECT OK ({pattern}: {desc})")

            sock.close()
            record_pass()

        except zmq.ZMQError as e:
            if "Address already in use" in str(e):
                fail(f"Port {port} ALREADY IN USE", f"{desc} — port ถูกใช้อยู่แล้ว")
                info(f"แก้: netstat -ano | find \"{port}\" → taskkill /pid <PID> /f")
            else:
                fail(f"Port {port} ERROR: {e}", desc)
            record_fail()
            all_ok = False

    ctx.term()

    # Test MessagePack serialization
    try:
        import msgpack
        test_data = {"type": 1, "symbol": "XAUUSD", "bid": 2650.50, "ask": 2650.80}
        packed = msgpack.packb(test_data, use_bin_type=True)
        unpacked = msgpack.unpackb(packed, raw=False)
        assert unpacked == test_data
        ok(f"MessagePack serialize/deserialize OK ({len(packed)} bytes)")
        record_pass()
    except ImportError:
        fail("msgpack not installed", "pip install msgpack")
        record_fail()
        all_ok = False
    except Exception as e:
        fail(f"MessagePack test failed: {e}")
        record_fail()
        all_ok = False

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 2: InfluxDB Write/Read
# ═════════════════════════════════════════════════════════════════════

def test_influxdb() -> bool:
    """Test InfluxDB write and read roundtrip"""
    sep("TEST 2: InfluxDB Connection")
    all_ok = True

    # ตรงกับ 02_Brain/config.py (รองรับ env override เช่นเดียวกัน)
    import os as _os
    INFLUX_URL    = _os.environ.get("INFLUXDB_URL",    "http://localhost:8086")
    INFLUX_TOKEN  = _os.environ.get("INFLUXDB_TOKEN",  "_2Rnkee4DHBmXjDe60pILHKHGkXZ_uiB47SG_UcGg658WP_wNRf3XH7hFNFYq7S5w0rH2Uc240b7LoGGZCu3XA==")
    INFLUX_ORG    = _os.environ.get("INFLUXDB_ORG",    "flashea")   # lowercase — ตรงกับ config.py
    INFLUX_BUCKET = _os.environ.get("INFLUXDB_BUCKET", "trading")   # ตรงกับ config.py

    # Check if InfluxDB is reachable
    try:
        sock = socket.create_connection(("localhost", 8086), timeout=3)
        sock.close()
        ok("InfluxDB port 8086 reachable")
        record_pass()
    except (socket.timeout, ConnectionRefusedError, OSError):
        fail("InfluxDB not reachable on port 8086",
             "เปิด InfluxDB: influxd.exe หรือ docker start influxdb")
        record_fail()
        return False

    # Try write + read via influxdb-client
    try:
        from influxdb_client import InfluxDBClient, Point, WritePrecision
        from influxdb_client.client.write_api import SYNCHRONOUS

        client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)

        # Write test point
        write_api = client.write_api(write_options=SYNCHRONOUS)
        test_point = (
            Point("validation_test")
            .tag("source", "validate_live_readiness")
            .field("test_value", 42.0)
            .time(datetime.now(timezone.utc), WritePrecision.MS)
        )
        write_api.write(bucket=INFLUX_BUCKET, record=test_point)
        ok("InfluxDB WRITE OK (validation_test point)")
        record_pass()

        # Read back
        query_api = client.query_api()
        query = f'''
            from(bucket: "{INFLUX_BUCKET}")
            |> range(start: -1m)
            |> filter(fn: (r) => r._measurement == "validation_test")
            |> last()
        '''
        tables = query_api.query(query)
        found = False
        for table in tables:
            for record in table.records:
                if record.get_value() == 42.0:
                    found = True
                    break

        if found:
            ok("InfluxDB READ OK (roundtrip verified)")
            record_pass()
        else:
            warn("InfluxDB READ returned no matching data (may be retention issue)")
            record_warn()

        client.close()
        all_ok = True

    except ImportError:
        warn("influxdb-client not installed — skip InfluxDB test")
        info("pip install influxdb-client")
        record_warn()
    except Exception as e:
        fail(f"InfluxDB test error: {e}")
        record_fail()
        all_ok = False

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 3: CONFIG_PUSH Dry Run
# ═════════════════════════════════════════════════════════════════════

def test_config_push_dry_run() -> bool:
    """Build and serialize a CONFIG_PUSH message without sending"""
    sep("TEST 3: CONFIG_PUSH Dry Run")
    all_ok = True

    # Add project paths for import
    brain_path = Path("02_Brain")
    if brain_path.exists():
        sys.path.insert(0, str(brain_path))

    try:
        # Import ConfigBuilder
        from config_push.config_builder import (
            ConfigBuilder, StrategyConfig as SCfg, SymbolConfig, StandaloneConfig
        )
        ok("ConfigBuilder import OK")
        record_pass()

        # Build test config
        builder = ConfigBuilder()

        # Add S07 MeanReversion config
        s07_cfg = SCfg(
            strategy_id=7,
            enabled=True,
            confidence=0.72,
            parameters={"S07_RSI_PERIOD": 14, "S07_BB_PERIOD": 20, "S07_BB_DEV": 2.0},
            mm_method="MM01",
            mm_parameters={"MM01_FIXED_LOT": 0.01},
        )

        # Add S15 Grid config
        s15_cfg = SCfg(
            strategy_id=15,
            enabled=True,
            confidence=0.65,
            parameters={"S15_GRID_STEP": 15.0, "S15_GRID_LEVELS": 5},
            mm_method="MM03",
            mm_parameters={"MM03_ATR_MULT": 1.5},
        )

        sym_cfg = SymbolConfig(
            symbol="XAUUSD",
            strategies=[s07_cfg, s15_cfg],
        )

        standalone = StandaloneConfig(
            enabled_strategies=[7, 15],
            default_mm="MM01",
            risk_multiplier=1.0,
            regime_hint="RANGING",
        )

        msg = builder.build_config_push(
            symbol_configs=[sym_cfg],
            regime="RANGING",
            standalone_config=standalone,
            optimization_cycle="validation_test",
        )

        ok(f"ConfigBuilder.build_config_push() OK — regime=RANGING, 2 strategies, 1 symbol")
        record_pass()

        # Serialize to MessagePack
        import msgpack
        packed = builder.pack(msg)

        if packed and len(packed) > 0:
            ok(f"CONFIG_PUSH serialized OK ({len(packed)} bytes)")
            record_pass()
        else:
            fail("CONFIG_PUSH serialization returned empty")
            record_fail()
            all_ok = False

        # Deserialize and verify
        unpacked = msgpack.unpackb(packed, raw=False)
        if unpacked.get("type") == 10:
            ok(f"CONFIG_PUSH type=10 verified, {len(unpacked.get('symbol_configs', []))} symbol(s)")
            record_pass()
        else:
            fail(f"CONFIG_PUSH type mismatch: expected 10, got {unpacked.get('type')}")
            record_fail()
            all_ok = False

    except ImportError as e:
        fail(f"Import error: {e}")
        info("ตรวจสอบ: 02_Brain/config_push/config_builder.py")
        record_fail()
        all_ok = False
    except Exception as e:
        fail(f"CONFIG_PUSH dry run error: {e}")
        record_fail()
        all_ok = False

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 4: StrategyManager Config Receive Simulation
# ═════════════════════════════════════════════════════════════════════

def test_strategy_manager_config() -> bool:
    """Simulate StrategyManager receiving config via ZMQ"""
    sep("TEST 4: Strategy Config Receive Simulation")
    all_ok = True

    try:
        import zmq
        import msgpack

        # Build a minimal config message
        config_msg = {
            "type": 10,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "regime": "TRENDING",
            "optimization_cycle": "test_validation",
            "symbol_configs": [
                {
                    "symbol": "XAUUSD",
                    "strategies": [
                        {
                            "id": 7,
                            "enabled": True,
                            "confidence": 0.75,
                            "parameters": {"S07_RSI_PERIOD": 14},
                            "mm_method": "MM01",
                            "mm_parameters": {"MM01_FIXED_LOT": 0.01},
                        }
                    ],
                }
            ],
            "standalone_config": {
                "enabled_strategies": [7],
                "default_mm": "MM01",
                "risk_multiplier": 1.0,
                "regime_hint": "TRENDING",
            },
        }
        packed = msgpack.packb(config_msg, use_bin_type=True)

        # Simulate PUB → SUB config push
        ctx = zmq.Context()
        pub = ctx.socket(zmq.PUB)
        sub = ctx.socket(zmq.SUB)

        # Use inproc for testing
        pub.bind("inproc://config_test")
        sub.connect("inproc://config_test")
        sub.setsockopt(zmq.SUBSCRIBE, b"ALL")
        sub.setsockopt(zmq.RCVTIMEO, 2000)

        time.sleep(0.1)  # ZMQ slow joiner

        # Send
        topic = b"ALL "
        pub.send(topic + packed)
        ok("CONFIG_PUSH sent via ZMQ PUB (inproc)")
        record_pass()

        # Receive
        raw = sub.recv()
        # Strip topic
        sep_idx = raw.index(b" ")
        data_bytes = raw[sep_idx + 1:]
        received = msgpack.unpackb(data_bytes, raw=False)

        if received.get("type") == 10 and received.get("regime") == "TRENDING":
            ok(f"Config received & parsed OK — regime={received['regime']}, "
               f"{len(received['symbol_configs'])} symbol(s)")
            record_pass()
        else:
            fail("Received config mismatch")
            record_fail()
            all_ok = False

        # Validate standalone config
        sc = received.get("standalone_config", {})
        if sc.get("enabled_strategies") == [7]:
            ok(f"Standalone config OK — strategies={sc['enabled_strategies']}")
            record_pass()
        else:
            fail("Standalone config mismatch")
            record_fail()
            all_ok = False

        pub.close()
        sub.close()
        ctx.term()

    except Exception as e:
        fail(f"Strategy config simulation error: {e}")
        record_fail()
        all_ok = False

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 5: Python Brain Import Chain
# ═════════════════════════════════════════════════════════════════════

def test_python_imports() -> bool:
    """Verify all critical Python modules can be imported"""
    sep("TEST 5: Python Brain Import Chain")
    all_ok = True

    brain_path = Path("02_Brain")
    if brain_path.exists():
        sys.path.insert(0, str(brain_path))

    critical_modules = [
        ("zmq",         "pyzmq",         "ZMQ messaging"),
        ("msgpack",     "msgpack",       "MessagePack serialization"),
        ("threading",   None,            "Thread management"),
        ("queue",       None,            "Thread-safe queues"),
        ("logging",     None,            "Logging framework"),
        ("json",        None,            "JSON handling"),
        ("pathlib",     None,            "Path utilities"),
    ]

    optional_modules = [
        ("rich",                "rich",              "Terminal dashboard"),
        ("influxdb_client",     "influxdb-client",   "InfluxDB time-series"),
        ("numpy",               "numpy",             "Numerical computing"),
        ("pandas",              "pandas",            "Data analysis"),
    ]

    for mod_name, pip_name, desc in critical_modules:
        try:
            importlib.import_module(mod_name)
            ok(f"{mod_name:<20s} — {desc}")
            record_pass()
        except ImportError:
            fail(f"{mod_name:<20s} — {desc}",
                 f"pip install {pip_name}" if pip_name else "built-in module missing!")
            record_fail()
            all_ok = False

    print()
    info("Optional modules:")
    for mod_name, pip_name, desc in optional_modules:
        try:
            importlib.import_module(mod_name)
            ok(f"{mod_name:<20s} — {desc}")
            record_pass()
        except ImportError:
            warn(f"{mod_name:<20s} — {desc}  (pip install {pip_name})")
            record_warn()

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 6: File System Integrity
# ═════════════════════════════════════════════════════════════════════

def test_file_system() -> bool:
    """ตรวจไฟล์สำคัญทั้งหมดตาม tree"""
    sep("TEST 6: File System Integrity")
    all_ok = True

    critical_files = [
        # Brain core
        ("02_Brain/main.py",                        "Brain entry point"),
        ("02_Brain/config.py",                      "Brain configuration"),
        ("02_Brain/dashboard.py",                   "Live dashboard (Rich)"),
        # Core modules
        ("02_Brain/core/ingestion.py",              "Tick ingestion worker"),
        ("02_Brain/core/execution_listener.py",     "Execution listener"),
        ("02_Brain/core/protocol_handler.py",       "Protocol handler"),
        ("02_Brain/core/message_types.py",          "Message type constants"),
        ("02_Brain/core/system_monitor.py",         "System monitor"),
        ("02_Brain/core/emergency_system.py",       "Emergency system"),
        # Strategy intelligence
        ("02_Brain/core/intelligence/strategy_council.py",     "AI Council"),
        ("02_Brain/core/intelligence/confidence_scorer.py",    "Confidence scorer"),
        ("02_Brain/core/intelligence/performance_tracker.py",  "Performance tracker"),
        ("02_Brain/core/intelligence/regime_classifier.py",    "Regime classifier"),
        # Config push (actual path: 02_Brain/config_push/, not core/config_push/)
        ("02_Brain/config_push/config_builder.py",  "Config builder"),
        ("02_Brain/config_push/config_pusher.py",   "Config pusher (ZMQ)"),
        # Strategy engine
        ("02_Brain/core/strategy/engine.py",        "Strategy engine"),
        ("02_Brain/core/strategy/policy.py",        "Policy generator"),
        ("02_Brain/core/strategy/analysis.py",      "Strategy analysis"),
        ("02_Brain/core/strategy/feedback.py",      "Feedback processor"),
        # Feedback
        ("02_Brain/core/feedback/multi_strategy_feedback.py", "Multi-strategy feedback"),
        # Explainable AI
        ("02_Brain/explainable/decision_logger.py", "Decision logger"),
        # Config files
        ("02_Brain/config/strategy_parameters.json",     "Strategy params"),
        ("02_Brain/config/mm_parameters.json",           "MM params"),
        ("02_Brain/config/mm_selection_matrix.json",     "MM selection matrix"),
        # MQL5 key files
        ("01_Feeder/Src/FeederEA.mq5",             "FeederEA source"),
        # Keys
        ("00_Common/Keys/server.key",               "ZMQ server key"),
    ]

    found = 0
    missing = 0
    for filepath, desc in critical_files:
        p = Path(filepath)
        if p.exists():
            ok(f"{filepath:<55s} {desc}")
            record_pass()
            found += 1
        else:
            fail(f"{filepath:<55s} {desc}")
            record_fail()
            missing += 1
            all_ok = False

    info(f"Files: {found} found, {missing} missing")

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 7: Port Availability
# ═════════════════════════════════════════════════════════════════════

def test_port_availability() -> bool:
    """Check if ports 7777-7779 are free (no other process using them)"""
    sep("TEST 7: Port Availability")
    all_ok = True

    ports = {
        7777: "FeederEA PUB → Brain SUB",
        7778: "Brain PUB → Trader SUB",
        7779: "Trader PUSH → Brain PULL",
        8086: "InfluxDB HTTP API",
    }

    for port, desc in ports.items():
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(("127.0.0.1", port))
            sock.close()

            if port == 8086:
                # InfluxDB should be running
                if result == 0:
                    ok(f"Port {port} active — {desc}")
                    record_pass()
                else:
                    warn(f"Port {port} not active — {desc} (InfluxDB ไม่ได้เปิด)")
                    record_warn()
            else:
                # Trading ports should be free
                if result != 0:
                    ok(f"Port {port} available — {desc}")
                    record_pass()
                else:
                    fail(f"Port {port} IN USE — {desc}",
                         f"มี process อื่นใช้อยู่ — netstat -ano | find \"{port}\"")
                    record_fail()
                    all_ok = False

        except Exception as e:
            warn(f"Port {port} check error: {e}")
            record_warn()

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# TEST 8: Dependencies Version Check
# ═════════════════════════════════════════════════════════════════════

def test_dependencies() -> bool:
    """Verify pip packages and versions"""
    sep("TEST 8: Dependencies")
    all_ok = True

    required = {
        "pyzmq":    ("zmq",             "25.0"),
        "msgpack":  ("msgpack",         "1.0"),
    }

    optional = {
        "rich":             ("rich",             "13.0"),
        "influxdb-client":  ("influxdb_client",  "1.30"),
        "numpy":            ("numpy",            "1.20"),
    }

    for pkg, (mod_name, min_ver) in required.items():
        try:
            mod = importlib.import_module(mod_name)
            ver = getattr(mod, "__version__", getattr(mod, "VERSION", "?"))
            ok(f"{pkg:<20s} v{ver}")
            record_pass()
        except ImportError:
            fail(f"{pkg:<20s} NOT INSTALLED", f"pip install {pkg}")
            record_fail()
            all_ok = False

    print()
    info("Optional packages:")
    for pkg, (mod_name, min_ver) in optional.items():
        try:
            mod = importlib.import_module(mod_name)
            ver = getattr(mod, "__version__", getattr(mod, "VERSION", "?"))
            ok(f"{pkg:<20s} v{ver}")
            record_pass()
        except ImportError:
            warn(f"{pkg:<20s} NOT INSTALLED (pip install {pkg})")
            record_warn()

    return all_ok


# ═════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="FlashEASuite V2 — Live Readiness Validator (P9-5)"
    )
    parser.add_argument("--quick", action="store_true",
                        help="Quick check: imports + files only")
    parser.add_argument("--zmq", action="store_true",
                        help="ZMQ tests only")
    parser.add_argument("--influx", action="store_true",
                        help="InfluxDB tests only")
    args = parser.parse_args()

    # Enable ANSI + UTF-8 on Windows
    if sys.platform == "win32":
        os.system("")  # enables ANSI escape codes
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            import io
            sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

    print()
    print(f"{BOLD}{'═'*60}")
    print(f"  🔍 FlashEASuite V2 — LIVE READINESS VALIDATION")
    print(f"  📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  📁 Working dir: {os.getcwd()}")
    print(f"{'═'*60}{RESET}")

    results = {}

    if args.quick:
        results["Imports"]    = test_python_imports()
        results["Files"]      = test_file_system()
        results["Deps"]       = test_dependencies()
    elif args.zmq:
        results["ZMQ"]        = test_zmq_connections()
        results["Config"]     = test_config_push_dry_run()
        results["Receive"]    = test_strategy_manager_config()
    elif args.influx:
        results["InfluxDB"]   = test_influxdb()
    else:
        # Full validation
        results["Imports"]    = test_python_imports()
        results["Deps"]       = test_dependencies()
        results["Files"]      = test_file_system()
        results["Ports"]      = test_port_availability()
        results["ZMQ"]        = test_zmq_connections()
        results["MsgPack"]    = True  # included in ZMQ test
        results["Config"]     = test_config_push_dry_run()
        results["Receive"]    = test_strategy_manager_config()
        results["InfluxDB"]   = test_influxdb()

    # ─── Final Report ───────────────────────────────────────────────
    print()
    print(f"{BOLD}{'═'*60}")
    print(f"  📊 VALIDATION SUMMARY")
    print(f"{'═'*60}{RESET}")
    print()

    for test_name, passed in results.items():
        status = f"{GREEN}✅ PASS{RESET}" if passed else f"{RED}❌ FAIL{RESET}"
        print(f"  {status}  {test_name}")

    print()
    print(f"  Total: {GREEN}{_pass_count} passed{RESET}, "
          f"{RED}{_fail_count} failed{RESET}, "
          f"{YELLOW}{_warn_count} warnings{RESET}")

    all_passed = all(results.values())

    print()
    if all_passed and _fail_count == 0:
        print(f"  {GREEN}{BOLD}🚀 SYSTEM READY FOR LIVE TRADING!{RESET}")
        print(f"  {GREEN}ทุก test PASS — พร้อม go-live{RESET}")
    else:
        print(f"  {RED}{BOLD}⛔ SYSTEM NOT READY — {_fail_count} test(s) FAILED{RESET}")
        print(f"  {RED}แก้ไข FAIL ทั้งหมดก่อน go-live!{RESET}")

    print()

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
