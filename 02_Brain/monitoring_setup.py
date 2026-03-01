"""
FlashEASuite V2 — monitoring_setup.py
Production Monitoring Dashboard (Console)
Phase: P9-1 Production & Polish
Author: Claude AI for Dr. Suksaeng Kukanok
Date: 2026-02-25

รัน: python monitoring_setup.py
     หรือ python monitoring_setup.py --interval 30
"""

import argparse
import json
import os
import sys
import time
import subprocess
from datetime import datetime


# ======= Color Helpers =======
class C:
    RESET  = "\033[0m"
    RED    = "\033[91m"
    GREEN  = "\033[92m"
    YELLOW = "\033[93m"
    BLUE   = "\033[94m"
    CYAN   = "\033[96m"
    BOLD   = "\033[1m"
    def ok(s):   return f"{C.GREEN}✅ {s}{C.RESET}"
    def warn(s): return f"{C.YELLOW}⚠️  {s}{C.RESET}"
    def err(s):  return f"{C.RED}❌ {s}{C.RESET}"


# ======= Component Health Checks =======

def check_process(name: str, keyword: str) -> bool:
    """Check ว่า process กำลัง run อยู่ไหม"""
    try:
        result = subprocess.run(
            ["tasklist" if sys.platform == "win32" else "pgrep", "-f", keyword],
            capture_output=True, text=True
        )
        return keyword.lower() in result.stdout.lower()
    except Exception:
        return False


def check_zmq_port(port: int) -> bool:
    """Check ว่า ZMQ port เปิดอยู่"""
    import socket
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def check_influxdb() -> bool:
    """Check InfluxDB health"""
    try:
        import urllib.request
        req = urllib.request.Request("http://localhost:8086/health", method="GET")
        with urllib.request.urlopen(req, timeout=2) as r:
            data = json.loads(r.read())
            return data.get("status") == "pass"
    except Exception:
        return False


def get_log_metrics(log_dir: str = "logs/decisions") -> dict:
    """อ่าน decision log วันนี้"""
    date_str = datetime.utcnow().strftime("%Y-%m-%d")
    path = os.path.join(log_dir, f"decisions_{date_str}.jsonl")
    if not os.path.exists(path):
        return {"total": 0, "approved": 0, "wins": 0, "losses": 0}
    
    total = approved = wins = losses = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                r = json.loads(line)
                total += 1
                if r.get("approved"):
                    approved += 1
                if r.get("outcome"):
                    if r["outcome"]["win"]:
                        wins += 1
                    else:
                        losses += 1
            except Exception:
                pass
    return {"total": total, "approved": approved, "wins": wins, "losses": losses}


def get_retrain_alerts(log_path: str = "logs/retrain_events.jsonl") -> list:
    """ดู retrain events วันนี้"""
    if not os.path.exists(log_path):
        return []
    today = datetime.utcnow().strftime("%Y-%m-%d")
    alerts = []
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            try:
                ev = json.loads(line)
                if ev.get("ts", "").startswith(today):
                    alerts.append(ev)
            except Exception:
                pass
    return alerts


# ======= Display =======

def print_dashboard(interval: int):
    os.system("cls" if sys.platform == "win32" else "clear")
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    
    print(f"\n{C.BOLD}{C.BLUE}{'='*65}{C.RESET}")
    print(f"{C.BOLD}{C.CYAN}  FlashEASuite V2 — Production Monitor   {now}{C.RESET}")
    print(f"{C.BOLD}{C.BLUE}{'='*65}{C.RESET}\n")

    # --- Component Health ---
    print(f"{C.BOLD}[ COMPONENT HEALTH ]{C.RESET}")
    components = [
        ("Python Brain (engine.py)",    check_process("engine", "engine.py")),
        ("FeederEA → ZMQ port 7777",    check_zmq_port(7777)),
        ("Brain    → ZMQ port 7778",    check_zmq_port(7778)),
        ("Trader   → ZMQ port 7779",    check_zmq_port(7779)),
        ("InfluxDB (port 8086)",         check_influxdb()),
    ]
    for name, ok in components:
        status = C.ok(name) if ok else C.err(name + " — NOT RUNNING")
        print(f"  {status}")

    # --- Decision Stats ---
    print(f"\n{C.BOLD}[ TODAY'S DECISIONS ]{C.RESET}")
    m = get_log_metrics()
    total_closed = m["wins"] + m["losses"]
    win_rate = f"{m['wins']/total_closed*100:.0f}%" if total_closed > 0 else "N/A"
    print(f"  Signals: {m['total']}  |  Approved: {m['approved']}  |  Rejected: {m['total']-m['approved']}")
    print(f"  Trades:  W={m['wins']} / L={m['losses']}  |  Win Rate: {win_rate}")

    # --- Retrain Alerts ---
    alerts = get_retrain_alerts()
    print(f"\n{C.BOLD}[ RETRAIN ALERTS (TODAY) ]{C.RESET}")
    if not alerts:
        print(f"  {C.ok('No retrain triggers today')}")
    else:
        for a in alerts[-5:]:
            print(C.warn(f"  S{a['strategy']:02d} {a['symbol']}: acc={a['accuracy']:.3f} < {a['threshold']:.2f}"))

    # --- Log File Sizes ---
    print(f"\n{C.BOLD}[ LOG FILES ]{C.RESET}")
    log_files = [
        "logs/decisions",
        "logs/retrain_events.jsonl",
        "logs/csv_reports",
    ]
    for p in log_files:
        if os.path.isdir(p):
            files = os.listdir(p)
            print(f"  {p}: {len(files)} file(s)")
        elif os.path.isfile(p):
            size_kb = os.path.getsize(p) / 1024
            print(f"  {p}: {size_kb:.1f} KB")
        else:
            print(C.warn(f"  {p}: missing"))

    print(f"\n{C.YELLOW}  Refreshing every {interval}s... Ctrl+C to stop{C.RESET}\n")


def main():
    parser = argparse.ArgumentParser(description="FlashEASuite V2 Monitor")
    parser.add_argument("--interval", type=int, default=30, help="Refresh interval (sec)")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    args = parser.parse_args()

    if args.once:
        print_dashboard(args.interval)
        return

    try:
        while True:
            print_dashboard(args.interval)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n\nMonitor stopped.")


if __name__ == "__main__":
    main()
