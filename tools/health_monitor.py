#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FlashEASuite V2 — Health Monitor (P9-4)
========================================
ตรวจสอบ health ของทุก component ทุก 30 วินาที
- ตรวจ ZMQ heartbeat (ports 7777, 7778, 7779)
- ตรวจ process: Python Brain, MT5 terminal
- auto-restart Brain ถ้า crash
- log ลง health.log + console

Usage:
    python health_monitor.py                  # Run monitor
    python health_monitor.py --once           # Check once and exit
    python health_monitor.py --restart-brain  # Force restart Brain

Save: FlashEASuite_V2/tools/health_monitor.py

Author: Dr. Suksaeng Kukanok
Version: 1.0 (P9-4)
Date: 2026-02-26
"""

import os
import sys
import time
import socket
import signal
import logging
import argparse
import subprocess
from datetime import datetime, timedelta
from dataclasses import dataclass, field
from typing import Optional, List, Dict
from pathlib import Path

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────

FLASHEA_ROOT = Path(__file__).resolve().parent.parent  # FlashEASuite_V2/
BRAIN_DIR = FLASHEA_ROOT / "02_Brain"
BRAIN_ENTRY = BRAIN_DIR / "main.py"
LOG_DIR = FLASHEA_ROOT / "logs"
HEALTH_LOG = LOG_DIR / "health.log"

# Check intervals (seconds)
CHECK_INTERVAL = 30          # Heartbeat check interval
BRAIN_RESTART_DELAY = 5      # Wait before restarting Brain
MAX_RESTART_ATTEMPTS = 3     # Max auto-restart within RESTART_WINDOW
RESTART_WINDOW = 300         # Reset restart counter after 5 minutes

# ZMQ ports to monitor
ZMQ_PORTS = {
    7777: "FeederEA (tick data PUB)",
    7778: "Brain (policy PUB)",
    7779: "Trader (feedback PUB)",
}

# MT5 process name
MT5_PROCESS = "terminal64.exe"


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class ComponentStatus:
    """Status of a single component."""
    name: str
    alive: bool = False
    last_seen: Optional[datetime] = None
    details: str = ""
    
    @property
    def status_icon(self) -> str:
        return "🟢" if self.alive else "🔴"
    
    def __str__(self) -> str:
        ts = self.last_seen.strftime("%H:%M:%S") if self.last_seen else "never"
        return f"{self.status_icon} {self.name:20s} | {'UP':6s if self.alive else 'DOWN':6s} | last: {ts} | {self.details}"


@dataclass
class HealthReport:
    """Overall system health."""
    timestamp: datetime = field(default_factory=datetime.now)
    components: List[ComponentStatus] = field(default_factory=list)
    all_healthy: bool = False
    brain_running: bool = False
    mt5_running: bool = False
    ports_active: Dict[int, bool] = field(default_factory=dict)
    
    def summary(self) -> str:
        status = "HEALTHY" if self.all_healthy else "DEGRADED"
        return (
            f"[{self.timestamp.strftime('%Y-%m-%d %H:%M:%S')}] "
            f"System: {status} | "
            f"Brain: {'UP' if self.brain_running else 'DOWN'} | "
            f"MT5: {'UP' if self.mt5_running else 'DOWN'} | "
            f"Ports: {sum(self.ports_active.values())}/{len(self.ports_active)}"
        )


# ─────────────────────────────────────────────
# Health Checker
# ─────────────────────────────────────────────

class HealthMonitor:
    """
    Monitor FlashEASuite V2 system health.
    
    Checks:
    1. Python Brain process alive
    2. MT5 terminal64.exe alive
    3. ZMQ ports 7777/7778/7779 listening
    4. Auto-restart Brain if crashed
    """
    
    def __init__(self, auto_restart: bool = True):
        self.auto_restart = auto_restart
        self._running = False
        self._brain_process: Optional[subprocess.Popen] = None
        self._restart_count = 0
        self._restart_window_start = time.time()
        self._last_report: Optional[HealthReport] = None
        
        # Setup logging
        self._setup_logging()
        
    def _setup_logging(self):
        """Configure dual logging: console + file."""
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        
        self.logger = logging.getLogger("FlashEA.Health")
        self.logger.setLevel(logging.INFO)
        self.logger.handlers.clear()
        
        # Console handler
        ch = logging.StreamHandler(sys.stdout)
        ch.setLevel(logging.INFO)
        ch.setFormatter(logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s",
            datefmt="%H:%M:%S"
        ))
        self.logger.addHandler(ch)
        
        # File handler (append)
        fh = logging.FileHandler(str(HEALTH_LOG), encoding="utf-8")
        fh.setLevel(logging.INFO)
        fh.setFormatter(logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        ))
        self.logger.addHandler(fh)
    
    # ─────────────────────────────────────────
    # Process Checks
    # ─────────────────────────────────────────
    
    def check_brain_alive(self) -> ComponentStatus:
        """Check if Python Brain (main.py) is running."""
        status = ComponentStatus(name="Python Brain")
        
        try:
            # Method 1: Check our managed process
            if self._brain_process and self._brain_process.poll() is None:
                status.alive = True
                status.last_seen = datetime.now()
                status.details = f"PID={self._brain_process.pid} (managed)"
                return status
            
            # Method 2: Check via tasklist (Windows)
            if sys.platform == "win32":
                result = subprocess.run(
                    ["wmic", "process", "where",
                     "commandline like '%main.py%' and name='python.exe'",
                     "get", "processid"],
                    capture_output=True, text=True, timeout=5
                )
                lines = [l.strip() for l in result.stdout.strip().split("\n") if l.strip().isdigit()]
                if lines:
                    status.alive = True
                    status.last_seen = datetime.now()
                    status.details = f"PID={lines[0]} (external)"
                    return status
            
            # Method 3: Check by socket (port 7778 = Brain PUB)
            if self._check_port(7778):
                status.alive = True
                status.last_seen = datetime.now()
                status.details = "port 7778 active"
                return status
                
        except Exception as e:
            status.details = f"check error: {e}"
        
        status.details = "not running"
        return status
    
    def check_mt5_alive(self) -> ComponentStatus:
        """Check if MetaTrader 5 is running."""
        status = ComponentStatus(name="MetaTrader 5")
        
        try:
            if sys.platform == "win32":
                result = subprocess.run(
                    ["tasklist", "/fi", f"IMAGENAME eq {MT5_PROCESS}"],
                    capture_output=True, text=True, timeout=5
                )
                if MT5_PROCESS.lower() in result.stdout.lower():
                    status.alive = True
                    status.last_seen = datetime.now()
                    status.details = "terminal64.exe running"
                    return status
            
            status.details = "not running"
            
        except Exception as e:
            status.details = f"check error: {e}"
        
        return status
    
    def check_zmq_ports(self) -> Dict[int, ComponentStatus]:
        """Check if ZMQ ports are listening."""
        results = {}
        
        for port, description in ZMQ_PORTS.items():
            status = ComponentStatus(name=f"Port {port}")
            status.details = description
            
            if self._check_port(port):
                status.alive = True
                status.last_seen = datetime.now()
                status.details += " [LISTENING]"
            else:
                status.details += " [NOT LISTENING]"
            
            results[port] = status
        
        return results
    
    def _check_port(self, port: int, host: str = "127.0.0.1") -> bool:
        """Check if a port is listening (TCP connect test)."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1.0)
                result = s.connect_ex((host, port))
                return result == 0
        except Exception:
            return False
    
    # ─────────────────────────────────────────
    # Full Health Check
    # ─────────────────────────────────────────
    
    def run_health_check(self) -> HealthReport:
        """Run all health checks and return report."""
        report = HealthReport()
        
        # Check Brain
        brain_status = self.check_brain_alive()
        report.components.append(brain_status)
        report.brain_running = brain_status.alive
        
        # Check MT5
        mt5_status = self.check_mt5_alive()
        report.components.append(mt5_status)
        report.mt5_running = mt5_status.alive
        
        # Check ZMQ ports
        port_statuses = self.check_zmq_ports()
        for port, status in port_statuses.items():
            report.components.append(status)
            report.ports_active[port] = status.alive
        
        # Overall health: Brain must be up, MT5 should be up
        report.all_healthy = report.brain_running and report.mt5_running
        
        self._last_report = report
        return report
    
    # ─────────────────────────────────────────
    # Auto-Restart
    # ─────────────────────────────────────────
    
    def restart_brain(self) -> bool:
        """
        Restart Python Brain (main.py).
        
        Returns:
            True if restart was successful.
        """
        # Check restart limit
        now = time.time()
        if now - self._restart_window_start > RESTART_WINDOW:
            self._restart_count = 0
            self._restart_window_start = now
        
        if self._restart_count >= MAX_RESTART_ATTEMPTS:
            self.logger.error(
                f"RESTART LIMIT REACHED ({MAX_RESTART_ATTEMPTS} within "
                f"{RESTART_WINDOW}s). Manual intervention required!"
            )
            return False
        
        self.logger.warning(
            f"Restarting Brain (attempt {self._restart_count + 1}/{MAX_RESTART_ATTEMPTS})..."
        )
        
        # Kill existing process if managed
        if self._brain_process and self._brain_process.poll() is None:
            try:
                self._brain_process.terminate()
                self._brain_process.wait(timeout=5)
            except Exception:
                self._brain_process.kill()
        
        # Wait before restart
        time.sleep(BRAIN_RESTART_DELAY)
        
        # Start new process
        try:
            brain_log = LOG_DIR / f"brain_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
            
            self._brain_process = subprocess.Popen(
                [sys.executable, str(BRAIN_ENTRY)],
                cwd=str(BRAIN_DIR),
                stdout=open(str(brain_log), "w", encoding="utf-8"),
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
            )
            
            self._restart_count += 1
            self.logger.info(
                f"Brain restarted: PID={self._brain_process.pid} | "
                f"log: {brain_log.name}"
            )
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to restart Brain: {e}")
            return False
    
    # ─────────────────────────────────────────
    # Display
    # ─────────────────────────────────────────
    
    def print_dashboard(self, report: HealthReport):
        """Print health dashboard to console."""
        print()
        print("╔══════════════════════════════════════════════════════════╗")
        print("║   FlashEASuite V2 — Health Monitor Dashboard            ║")
        print(f"║   {report.timestamp.strftime('%Y-%m-%d %H:%M:%S'):55s}║")
        print("╠══════════════════════════════════════════════════════════╣")
        
        for comp in report.components:
            icon = "🟢" if comp.alive else "🔴"
            name = comp.name[:20].ljust(20)
            st = "UP".ljust(6) if comp.alive else "DOWN".ljust(6)
            det = comp.details[:35]
            print(f"║  {icon} {name} {st} {det:35s} ║")
        
        print("╠══════════════════════════════════════════════════════════╣")
        overall = "🟢 ALL HEALTHY" if report.all_healthy else "🟡 DEGRADED"
        restarts = f"Restarts: {self._restart_count}/{MAX_RESTART_ATTEMPTS}"
        print(f"║  Status: {overall:20s}  {restarts:25s} ║")
        print("╚══════════════════════════════════════════════════════════╝")
        print()
    
    # ─────────────────────────────────────────
    # Main Loop
    # ─────────────────────────────────────────
    
    def run(self):
        """Main monitoring loop."""
        self._running = True
        
        self.logger.info("=" * 60)
        self.logger.info("FlashEASuite V2 — Health Monitor Started")
        self.logger.info(f"  Check interval: {CHECK_INTERVAL}s")
        self.logger.info(f"  Auto-restart: {self.auto_restart}")
        self.logger.info(f"  Max restarts: {MAX_RESTART_ATTEMPTS} per {RESTART_WINDOW}s")
        self.logger.info(f"  Log file: {HEALTH_LOG}")
        self.logger.info("=" * 60)
        
        # Setup signal handlers
        def handle_signal(signum, frame):
            self.logger.info("Shutdown signal received. Stopping monitor...")
            self._running = False
        
        signal.signal(signal.SIGINT, handle_signal)
        signal.signal(signal.SIGTERM, handle_signal)
        
        consecutive_brain_down = 0
        
        while self._running:
            try:
                # Run health check
                report = self.run_health_check()
                
                # Log summary
                self.logger.info(report.summary())
                
                # Print dashboard
                self.print_dashboard(report)
                
                # Auto-restart logic
                if not report.brain_running:
                    consecutive_brain_down += 1
                    self.logger.warning(
                        f"Brain is DOWN (consecutive: {consecutive_brain_down})"
                    )
                    
                    if self.auto_restart and consecutive_brain_down >= 2:
                        # Brain down for 2 consecutive checks (~60s)
                        self.logger.warning("Attempting auto-restart...")
                        if self.restart_brain():
                            consecutive_brain_down = 0
                            # Wait extra for Brain to initialize
                            time.sleep(BRAIN_RESTART_DELAY)
                else:
                    if consecutive_brain_down > 0:
                        self.logger.info("Brain recovered.")
                    consecutive_brain_down = 0
                
                # Alert if MT5 is down
                if not report.mt5_running:
                    self.logger.warning(
                        "MT5 is DOWN — FeederEA and Trader cannot operate. "
                        "Please start MetaTrader 5."
                    )
                
                # Sleep until next check
                for _ in range(CHECK_INTERVAL):
                    if not self._running:
                        break
                    time.sleep(1)
                    
            except Exception as e:
                self.logger.error(f"Monitor error: {e}")
                time.sleep(CHECK_INTERVAL)
        
        self.logger.info("Health Monitor stopped.")
    
    def run_once(self):
        """Run a single health check and print results."""
        report = self.run_health_check()
        self.print_dashboard(report)
        return report.all_healthy


# ─────────────────────────────────────────────
# CLI Entry Point
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="FlashEASuite V2 — Health Monitor"
    )
    parser.add_argument(
        "--once", action="store_true",
        help="Run single check and exit"
    )
    parser.add_argument(
        "--no-restart", action="store_true",
        help="Disable auto-restart of Brain"
    )
    parser.add_argument(
        "--restart-brain", action="store_true",
        help="Force restart Brain and exit"
    )
    parser.add_argument(
        "--interval", type=int, default=CHECK_INTERVAL,
        help=f"Check interval in seconds (default: {CHECK_INTERVAL})"
    )
    
    args = parser.parse_args()
    
    monitor = HealthMonitor(auto_restart=not args.no_restart)
    
    if args.restart_brain:
        print("Force restarting Brain...")
        success = monitor.restart_brain()
        sys.exit(0 if success else 1)
    
    if args.once:
        healthy = monitor.run_once()
        sys.exit(0 if healthy else 1)
    
    # Override interval if specified
    global CHECK_INTERVAL
    CHECK_INTERVAL = args.interval
    
    monitor.run()


if __name__ == "__main__":
    main()
