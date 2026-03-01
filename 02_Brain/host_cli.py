#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — Host CLI
============================
Command-line interface สำหรับควบคุม FlashEA Brain Server

Communication:
  Primary  : ZMQ REQ → Brain port 7780
  Fallback : อ่าน/เขียน logs/brain_status.json

Commands:
  status       — แสดง connected clients, active strategies, current regime
  force_config — push strategy config ไปยัง clients
  retrain      — trigger immediate model retrain
  report       — generate performance summary
  stop         — หยุด intelligence engine
  start        — เริ่ม intelligence engine

Usage:
  python host_cli.py status
  python host_cli.py retrain
  python host_cli.py report --period weekly
  python host_cli.py force_config --symbol XAUUSD.tp --strategy S01 --param entry_threshold 2.0
  python host_cli.py stop
  python host_cli.py start

Author: FlashEASuite V2 Team
Phase: P4-8
Date: 2026-02-22
"""

import argparse
import json
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Optional

# ─────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────
_BRAIN_DIR   = Path(__file__).resolve().parent
_STATUS_FILE = _BRAIN_DIR / "logs" / "brain_status.json"
_RETRAIN_DB  = _BRAIN_DIR / "logs" / "retrain_events.json"
_WEIGHTS_FILE = _BRAIN_DIR / "logs" / "council_weights.json"

CONTROL_PORT = 7780

# ─────────────────────────────────────────────
# Soft import ZMQ
# ─────────────────────────────────────────────
try:
    import zmq
    _ZMQ_AVAILABLE = True
except ImportError:
    _ZMQ_AVAILABLE = False


# ═════════════════════════════════════════════
# Terminal styling helpers
# ═════════════════════════════════════════════
_BOLD  = "\033[1m"
_GREEN = "\033[92m"
_CYAN  = "\033[96m"
_YELLOW = "\033[93m"
_RED   = "\033[91m"
_RESET = "\033[0m"

def _hdr(text: str):
    print(f"\n{_BOLD}{_CYAN}{'═' * 60}{_RESET}")
    print(f"{_BOLD}{_CYAN}  {text}{_RESET}")
    print(f"{_BOLD}{_CYAN}{'═' * 60}{_RESET}")

def _ok(text: str):
    print(f"  {_GREEN}✅  {text}{_RESET}")

def _warn(text: str):
    print(f"  {_YELLOW}⚠️   {text}{_RESET}")

def _err(text: str):
    print(f"  {_RED}❌  {text}{_RESET}")

def _info(label: str, value: Any):
    print(f"  {_BOLD}{label:<28}{_RESET} {value}")


# ═════════════════════════════════════════════
# ControlClient — สื่อสารกับ Brain
# ═════════════════════════════════════════════
class ControlClient:
    """
    ZMQ REQ client สำหรับส่ง command ไปยัง Brain Control Server
    Fallback: file-based เมื่อ ZMQ ไม่พร้อมหรือ Brain offline
    """

    def __init__(self, port: int = CONTROL_PORT, timeout_ms: int = 5000):
        self.port       = port
        self.timeout_ms = timeout_ms
        self._ctx: Optional[Any]  = None
        self._sock: Optional[Any] = None
        self._connected = False

    def connect(self) -> bool:
        if not _ZMQ_AVAILABLE:
            return False
        try:
            self._ctx  = zmq.Context()
            self._sock = self._ctx.socket(zmq.REQ)
            self._sock.setsockopt(zmq.RCVTIMEO, self.timeout_ms)
            self._sock.setsockopt(zmq.SNDTIMEO, self.timeout_ms)
            self._sock.setsockopt(zmq.LINGER, 0)
            self._sock.connect(f"tcp://127.0.0.1:{self.port}")
            self._connected = True
            return True
        except Exception as e:
            _warn(f"ZMQ connect failed: {e}")
            return False

    def send(self, payload: dict) -> Optional[dict]:
        """ส่ง command — return response หรือ None"""
        if not self._connected:
            return None
        try:
            self._sock.send_string(json.dumps(payload))
            raw = self._sock.recv_string()
            return json.loads(raw)
        except zmq.Again:
            _err("Brain did not respond (timeout)")
            return None
        except Exception as e:
            _err(f"ZMQ send error: {e}")
            return None

    def close(self):
        if self._sock:
            self._sock.close()
        if self._ctx:
            self._ctx.term()

    # ─────────────────────────────────────────
    # File-based fallback
    # ─────────────────────────────────────────

    @staticmethod
    def read_status_file() -> Optional[dict]:
        """อ่าน status จาก file (fallback)"""
        if not _STATUS_FILE.exists():
            return None
        try:
            with open(_STATUS_FILE) as f:
                return json.load(f)
        except Exception:
            return None

    @staticmethod
    def read_retrain_events(period: str = "weekly") -> list:
        if not _RETRAIN_DB.exists():
            return []
        try:
            with open(_RETRAIN_DB) as f:
                events = json.load(f)
            cutoff_map = {
                "daily":  timedelta(days=1),
                "weekly": timedelta(days=7),
                "all":    timedelta(days=3650),
            }
            cutoff = datetime.utcnow() - cutoff_map.get(period, timedelta(days=7))
            return [
                e for e in events
                if datetime.fromisoformat(e["timestamp"]) >= cutoff
            ]
        except Exception:
            return []

    @staticmethod
    def read_weights() -> dict:
        if not _WEIGHTS_FILE.exists():
            return {}
        try:
            with open(_WEIGHTS_FILE) as f:
                return json.load(f)
        except Exception:
            return {}


# ═════════════════════════════════════════════
# Command implementations
# ═════════════════════════════════════════════

def _fmt_uptime(seconds: int) -> str:
    h, r = divmod(seconds, 3600)
    m, s = divmod(r, 60)
    return f"{h:02d}h {m:02d}m {s:02d}s"


def cmd_status(client: ControlClient, args: argparse.Namespace):
    _hdr("FlashEA Brain — STATUS")

    # Try ZMQ first
    resp = client.send({"cmd": "status"}) if client._connected else None

    if resp and resp.get("ok"):
        data = resp
        src  = "ZMQ (live)"
    else:
        # Fallback: file-based
        data = client.read_status_file()
        src  = "File (offline snapshot)"
        if data is None:
            _err("Brain not reachable and no status file found")
            _info("Tip:", "Start Brain with: python main.py")
            sys.exit(1)

    _info("Data source",      src)
    _info("Timestamp",        data.get("updated_at", "N/A"))

    # Engine status
    engine_ok = data.get("engine_running", False)
    status_str = f"{_GREEN}RUNNING{_RESET}" if engine_ok else f"{_RED}STOPPED{_RESET}"
    _info("Intelligence Engine", status_str)

    # Regime
    _info("Current Regime",   data.get("current_regime", "UNKNOWN"))

    # Connected clients
    clients = data.get("connected_clients", {})
    _info("Connected Clients", len(clients))
    if clients:
        for cid, last_seen in list(clients.items())[:5]:
            print(f"    • {cid}  last seen: {last_seen}")
        if len(clients) > 5:
            print(f"    ... and {len(clients) - 5} more")

    # Active strategies
    strategies = data.get("active_strategies", [])
    _info("Active Strategies", len(strategies))
    if strategies:
        for s in strategies[:8]:
            print(f"    • {s}")

    # Uptime
    uptime = data.get("uptime_sec", 0)
    _info("Uptime", _fmt_uptime(uptime) if uptime else "N/A")

    # Retrain status (ถ้ามี)
    retrain = data.get("retrain", {})
    if retrain:
        print()
        _info("Last Retrain",     retrain.get("last_weekly_retrain", "Never"))
        _info("Next Retrain",     retrain.get("next_weekly_retrain", "Unknown"))
        _info("Total Retrains",   retrain.get("total_retrain_events", 0))
        _info("Trainer Ready",    retrain.get("trainer_available", False))

    print()


def cmd_retrain(client: ControlClient, args: argparse.Namespace):
    _hdr("FlashEA Brain — TRIGGER RETRAIN")
    reason = getattr(args, "reason", "manual-via-cli")

    resp = client.send({"cmd": "retrain", "reason": reason}) if client._connected else None

    if resp and resp.get("ok"):
        _ok(resp.get("message", "Retrain triggered"))
    else:
        _warn("Brain not reachable — writing retrain request to file")
        req_file = _BRAIN_DIR / "logs" / "retrain_request.json"
        req_file.parent.mkdir(parents=True, exist_ok=True)
        with open(req_file, "w") as f:
            json.dump({"timestamp": datetime.utcnow().isoformat(),
                       "reason": reason}, f, indent=2)
        _ok(f"Request written to {req_file}")
        _info("Note:", "AutoRetrainer will pick this up on next check cycle")

    print()


def cmd_force_config(client: ControlClient, args: argparse.Namespace):
    _hdr("FlashEA Brain — FORCE CONFIG")

    symbol   = args.symbol
    strategy = args.strategy
    raw_params = args.param  # list of [name, value] pairs

    # Parse param pairs
    config_params: Dict[str, Any] = {}
    if raw_params:
        for pair in raw_params:
            if len(pair) == 2:
                k, v = pair
                # Try numeric conversion
                try:
                    v = float(v)
                    if v == int(v):
                        v = int(v)
                except ValueError:
                    pass
                config_params[k] = v

    config = {"strategy": strategy, "params": config_params}
    payload = {"cmd": "force_config", "symbol": symbol, "config": config}

    _info("Symbol",   symbol)
    _info("Strategy", strategy)
    _info("Params",   config_params)

    resp = client.send(payload) if client._connected else None
    if resp and resp.get("ok"):
        _ok(resp.get("message", "Config pushed"))
    else:
        # File-based fallback
        pending = {
            "timestamp": datetime.utcnow().isoformat(),
            "symbol": symbol,
            "config": config,
        }
        pf = _BRAIN_DIR / "logs" / "force_config_pending.json"
        pf.parent.mkdir(parents=True, exist_ok=True)
        with open(pf, "w") as f:
            json.dump(pending, f, indent=2)
        _ok(f"Config saved to {pf}")

    print()


def cmd_report(client: ControlClient, args: argparse.Namespace):
    period = args.period
    _hdr(f"FlashEA Brain — PERFORMANCE REPORT ({period.upper()})")

    # Try ZMQ
    resp = client.send({"cmd": "report", "period": period}) if client._connected else None

    if resp and resp.get("ok"):
        report = resp["report"]
        src = "ZMQ (live)"
    else:
        # File-based fallback
        events = client.read_retrain_events(period)
        report = {
            "period": period,
            "total_events": len(events),
            "successful": sum(1 for e in events if e.get("success")),
            "failed": sum(1 for e in events if not e.get("success")),
            "events": events[-10:],
        }
        src = "File (offline)"

    _info("Source",          src)
    _info("Period",          report["period"])
    _info("Total Retrains",  report["total_events"])
    _ok(  f"Successful:      {report['successful']}")
    if report["failed"] > 0:
        _warn(f"Failed:        {report['failed']}")

    # Council weights
    weights = client.read_weights()
    if weights:
        print(f"\n  {_BOLD}Council Weights (EMA Accuracy):{_RESET}")
        for key, w in sorted(weights.items()):
            bar = "█" * int(w * 10)
            color = _GREEN if w >= 0.6 else (_YELLOW if w >= 0.4 else _RED)
            print(f"    {key:<28} {color}{w:.4f} {bar}{_RESET}")

    # Recent events
    events = report.get("events", [])
    if events:
        print(f"\n  {_BOLD}Recent Retrain Events:{_RESET}")
        for ev in events[-5:]:
            ts     = ev.get("timestamp", "?")[:16]
            trig   = ev.get("trigger", "?")
            models = ev.get("models", [])
            ok_sym = "✅" if ev.get("success") else "❌"
            dur    = ev.get("duration_sec", 0)
            print(f"    {ok_sym} {ts}  trigger={trig:<14} models={models}  {dur:.1f}s")

    print()


def cmd_stop(client: ControlClient, args: argparse.Namespace):
    _hdr("FlashEA Brain — STOP ENGINE")
    _warn("This will stop the intelligence engine!")

    resp = client.send({"cmd": "stop_engine"}) if client._connected else None
    if resp and resp.get("ok"):
        _ok(resp.get("message", "Stop command sent"))
    else:
        _err("Brain not reachable — cannot stop remotely")
        _info("Alternative:", "Kill the main.py process manually")

    print()


def cmd_start(client: ControlClient, args: argparse.Namespace):
    _hdr("FlashEA Brain — START ENGINE")

    resp = client.send({"cmd": "start_engine"}) if client._connected else None
    if resp and resp.get("ok"):
        _ok(resp.get("message", "Start command sent"))
    else:
        _warn("Brain not reachable")
        _info("Start Brain with:", "python main.py")

    print()


# ═════════════════════════════════════════════
# Main — argparse
# ═════════════════════════════════════════════

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="host_cli",
        description="FlashEASuite V2 — Brain Server CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
ตัวอย่าง:
  python host_cli.py status
  python host_cli.py retrain
  python host_cli.py retrain --reason "drawdown_alert"
  python host_cli.py report --period weekly
  python host_cli.py report --period daily
  python host_cli.py force_config --symbol XAUUSD.tp --strategy S01 --param entry_threshold 2.0
  python host_cli.py stop
  python host_cli.py start
        """,
    )
    parser.add_argument(
        "--port",
        type=int,
        default=CONTROL_PORT,
        help=f"Brain control port (default: {CONTROL_PORT})",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=5000,
        help="ZMQ receive timeout in milliseconds (default: 5000)",
    )

    sub = parser.add_subparsers(dest="command", metavar="COMMAND")
    sub.required = True

    # status
    sub.add_parser("status", help="แสดงสถานะ Brain server")

    # retrain
    p_retrain = sub.add_parser("retrain", help="Trigger immediate model retrain")
    p_retrain.add_argument(
        "--reason",
        default="manual-via-cli",
        help="Reason for retrain (default: manual-via-cli)",
    )

    # force_config
    p_cfg = sub.add_parser("force_config", help="Push specific strategy config")
    p_cfg.add_argument("--symbol",   required=True, help="Symbol e.g. XAUUSD.tp")
    p_cfg.add_argument("--strategy", required=True, help="Strategy ID e.g. S01")
    p_cfg.add_argument(
        "--param",
        nargs=2,
        action="append",
        metavar=("NAME", "VALUE"),
        help="Parameter override (repeatable): --param entry_threshold 2.0",
    )

    # report
    p_report = sub.add_parser("report", help="Generate performance summary")
    p_report.add_argument(
        "--period",
        choices=["daily", "weekly", "all"],
        default="weekly",
        help="Report period (default: weekly)",
    )

    # stop
    sub.add_parser("stop", help="Stop intelligence engine")

    # start
    sub.add_parser("start", help="Start intelligence engine")

    return parser


def main():
    parser = build_parser()
    args   = parser.parse_args()

    # Connect to Brain
    client = ControlClient(port=args.port, timeout_ms=args.timeout)
    connected = client.connect()

    if not connected:
        if not _ZMQ_AVAILABLE:
            _warn("PyZMQ not installed — running in file-only mode")
            _warn("Install: pip install pyzmq --break-system-packages")
        else:
            _warn(f"Cannot connect to Brain on port {args.port} — using file fallback")

    # Dispatch command
    dispatch = {
        "status":      cmd_status,
        "retrain":     cmd_retrain,
        "force_config": cmd_force_config,
        "report":      cmd_report,
        "stop":        cmd_stop,
        "start":       cmd_start,
    }

    handler = dispatch.get(args.command)
    if handler:
        try:
            handler(client, args)
        except KeyboardInterrupt:
            print("\nInterrupted")
        finally:
            client.close()
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
