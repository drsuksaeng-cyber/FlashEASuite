#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — Brain Control Server
========================================
ZMQ REP server บน port 7780 สำหรับรับ command จาก host_cli.py

ใช้งาน:
  from brain_control import BrainControlServer
  ctrl = BrainControlServer(brain_ref, retrain_ref, engine_ref)
  thread = ctrl.start_daemon()

Supported commands (JSON):
  {"cmd": "status"}
  {"cmd": "retrain", "reason": "..."}
  {"cmd": "stop_engine"}
  {"cmd": "start_engine"}
  {"cmd": "force_config", "symbol": "...", "config": {...}}
  {"cmd": "report", "period": "weekly"}

Author: FlashEASuite V2 Team
Phase: P4-8
Date: 2026-02-22
"""

import json
import logging
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional

# ─────────────────────────────────────────────
# Soft import ZMQ
# ─────────────────────────────────────────────
try:
    import zmq
    _ZMQ_AVAILABLE = True
except ImportError:
    _ZMQ_AVAILABLE = False

_BRAIN_DIR    = Path(__file__).resolve().parent
_STATUS_FILE  = _BRAIN_DIR / "logs" / "brain_status.json"
_CONTROL_PORT = 7780

logger = logging.getLogger("brain_control")


# ═════════════════════════════════════════════
# BrainControlServer
# ═════════════════════════════════════════════
class BrainControlServer:
    """
    ZMQ REP server — รับ command จาก host_cli.py

    brain_ref   : FlashEABrain object (หรือ None)
    retrain_ref : AutoRetrainer object (หรือ None)
    engine_ref  : Strategy engine thread/object (หรือ None)
    """

    def __init__(
        self,
        brain_ref: Optional[Any] = None,
        retrain_ref: Optional[Any] = None,
        engine_ref: Optional[Any] = None,
        port: int = _CONTROL_PORT,
    ):
        self.brain   = brain_ref
        self.retrain = retrain_ref
        self.engine  = engine_ref
        self.port    = port

        self._stop_event      = threading.Event()
        self._start_time      = datetime.utcnow()
        self._cmd_count       = 0
        self._engine_running  = True
        self._connected_clients: dict = {}  # client_id → last_seen
        self._active_strategies: list = []
        self._current_regime  = "UNKNOWN"

        # Write initial status file
        self._write_status_file()

    # ─────────────────────────────────────────
    # Public API (called by Brain)
    # ─────────────────────────────────────────

    def start_daemon(self) -> threading.Thread:
        """Start control server เป็น daemon thread"""
        t = threading.Thread(
            target=self._serve_loop,
            name="BrainControlServer",
            daemon=True,
        )
        t.start()
        logger.info("BrainControlServer started on port %d", self.port)
        return t

    def stop(self):
        self._stop_event.set()

    def update_state(
        self,
        connected_clients: Optional[dict] = None,
        active_strategies: Optional[list] = None,
        current_regime: Optional[str] = None,
    ):
        """เรียกจาก Brain เพื่ออัปเดต state ปัจจุบัน"""
        if connected_clients is not None:
            self._connected_clients = connected_clients
        if active_strategies is not None:
            self._active_strategies = active_strategies
        if current_regime is not None:
            self._current_regime = current_regime
        self._write_status_file()

    # ─────────────────────────────────────────
    # Internal — ZMQ serve loop
    # ─────────────────────────────────────────

    def _serve_loop(self):
        if not _ZMQ_AVAILABLE:
            logger.error("ZMQ not available — control server disabled")
            self._file_only_loop()
            return

        ctx = zmq.Context()
        sock = ctx.socket(zmq.REP)
        sock.setsockopt(zmq.RCVTIMEO, 1000)   # 1s timeout สำหรับ polling stop event
        sock.bind(f"tcp://127.0.0.1:{self.port}")
        logger.info("Control ZMQ REP listening on port %d", self.port)

        while not self._stop_event.is_set():
            try:
                raw = sock.recv_string()
                self._cmd_count += 1
                response = self._handle_command(raw)
                sock.send_string(json.dumps(response))
            except zmq.Again:
                continue  # timeout → check stop event
            except Exception as e:
                logger.error("Control server error: %s", e)
                try:
                    sock.send_string(json.dumps({"ok": False, "error": str(e)}))
                except Exception:
                    pass

        sock.close()
        ctx.term()
        logger.info("Control server stopped")

    def _file_only_loop(self):
        """Fallback เมื่อไม่มี ZMQ — write status file เท่านั้น"""
        logger.warning("Running in file-only mode (no ZMQ)")
        while not self._stop_event.is_set():
            self._write_status_file()
            self._stop_event.wait(timeout=30)

    # ─────────────────────────────────────────
    # Command handlers
    # ─────────────────────────────────────────

    def _handle_command(self, raw: str) -> dict:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            return {"ok": False, "error": "invalid JSON"}

        cmd = msg.get("cmd", "").lower()
        logger.info("CMD received: %s", cmd)

        handlers = {
            "status":       self._cmd_status,
            "retrain":      self._cmd_retrain,
            "stop_engine":  self._cmd_stop_engine,
            "start_engine": self._cmd_start_engine,
            "force_config": self._cmd_force_config,
            "report":       self._cmd_report,
        }

        handler = handlers.get(cmd)
        if handler is None:
            return {"ok": False, "error": f"unknown command: {cmd}"}

        try:
            return handler(msg)
        except Exception as e:
            logger.error("Command handler error [%s]: %s", cmd, e)
            return {"ok": False, "error": str(e)}

    def _cmd_status(self, msg: dict) -> dict:
        status = {
            "ok": True,
            "uptime_sec": int(
                (datetime.utcnow() - self._start_time).total_seconds()
            ),
            "engine_running": self._engine_running,
            "connected_clients": self._connected_clients,
            "active_strategies": self._active_strategies,
            "current_regime": self._current_regime,
            "cmd_count": self._cmd_count,
        }
        # ถ้า retrain available — เพิ่ม retrain status
        if self.retrain is not None:
            try:
                status["retrain"] = self.retrain.get_status()
            except Exception:
                status["retrain"] = {}
        self._write_status_file(status)
        return status

    def _cmd_retrain(self, msg: dict) -> dict:
        reason = msg.get("reason", "manual-via-cli")
        if self.retrain is None:
            return {"ok": False, "error": "AutoRetrainer not connected"}
        self.retrain.trigger_now(reason)
        return {"ok": True, "message": f"Retrain triggered — reason: {reason}"}

    def _cmd_stop_engine(self, _msg: dict) -> dict:
        self._engine_running = False
        if self.brain is not None:
            try:
                self.brain.shutdown_event.set()
                return {"ok": True, "message": "Brain shutdown initiated"}
            except Exception as e:
                return {"ok": False, "error": str(e)}
        return {"ok": True, "message": "No Brain ref — flag set only"}

    def _cmd_start_engine(self, _msg: dict) -> dict:
        # ไม่สามารถ restart thread ที่ stop แล้วได้โดยตรง — แจ้ง user
        self._engine_running = True
        return {
            "ok": True,
            "message": (
                "Engine flag set to running. "
                "If stopped, restart Brain process manually."
            ),
        }

    def _cmd_force_config(self, msg: dict) -> dict:
        symbol = msg.get("symbol", "")
        config = msg.get("config", {})
        if not symbol or not config:
            return {"ok": False, "error": "symbol and config required"}

        # Attempt to push via config_pusher (P4-5)
        try:
            sys.path.insert(0, str(_BRAIN_DIR))
            from config_push.config_pusher import ConfigPusher
            pusher = ConfigPusher()
            pusher.push_to_all({"symbol": symbol, **config})
            return {"ok": True, "message": f"Config pushed for {symbol}"}
        except ImportError:
            # Write to file แทน (CLI อ่านได้)
            _force_cfg = _BRAIN_DIR / "logs" / "force_config_pending.json"
            _force_cfg.parent.mkdir(parents=True, exist_ok=True)
            pending = {"timestamp": datetime.utcnow().isoformat(),
                       "symbol": symbol, "config": config}
            with open(_force_cfg, "w") as f:
                json.dump(pending, f, indent=2)
            return {
                "ok": True,
                "message": (
                    f"Config saved to {_force_cfg} "
                    "(config_pusher not available — apply manually)"
                ),
            }

    def _cmd_report(self, msg: dict) -> dict:
        period = msg.get("period", "weekly")
        events = []

        if _RETRAIN_DB.exists():
            try:
                import json as _json
                with open(_RETRAIN_DB) as f:
                    all_events = _json.load(f)
                cutoff = {
                    "daily":  datetime.utcnow() - timedelta(days=1),
                    "weekly": datetime.utcnow() - timedelta(days=7),
                    "all":    datetime.utcnow() - timedelta(days=3650),
                }.get(period, datetime.utcnow() - timedelta(days=7))

                events = [
                    e for e in all_events
                    if datetime.fromisoformat(e["timestamp"]) >= cutoff
                ]
            except Exception as e:
                return {"ok": False, "error": f"Report load failed: {e}"}

        summary = {
            "period": period,
            "total_events": len(events),
            "successful": sum(1 for e in events if e.get("success")),
            "failed": sum(1 for e in events if not e.get("success")),
            "events": events[-10:],  # last 10 entries
        }
        return {"ok": True, "report": summary}

    # ─────────────────────────────────────────
    # Status file (file-based fallback สำหรับ host_cli.py)
    # ─────────────────────────────────────────

    def _write_status_file(self, extra: Optional[dict] = None):
        try:
            _STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
            status = {
                "updated_at": datetime.utcnow().isoformat(),
                "engine_running": self._engine_running,
                "connected_clients": self._connected_clients,
                "active_strategies": self._active_strategies,
                "current_regime": self._current_regime,
            }
            if extra:
                status.update(extra)
            with open(_STATUS_FILE, "w") as f:
                json.dump(status, f, indent=2)
        except Exception as e:
            logger.warning("Status file write failed: %s", e)


import sys
_RETRAIN_DB = _BRAIN_DIR / "logs" / "retrain_events.json"
