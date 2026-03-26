#!/usr/bin/env python
"""
Overnight Runner: Wait for Dukascopy fetch to complete, then run full optimization.
29 symbols x 16 strategies x 7 TFs (M1,M5,M15,M30,H1,H4,D1) = 3,248 combos
Phase 1: Screen (default params)
Phase 2: Optimize viable (100 trials + WF)
Phase 3: Generate Top 30 HTML report
"""
import sys, time, json, glob
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from strategies.base import discover_strategies
from engine.backtester import run_backtest
from optimize.optuna_runner import optimize
from optimize.walk_forward import run_walk_forward

OUTPUT_DIR = Path(__file__).parent.parent / "output"
CACHE_DIR = Path(__file__).parent / "data" / "cache"

SYMBOLS_BASE = [
    "EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD","NZDUSD",
    "EURGBP","EURJPY","EURCHF","EURAUD","EURCAD","EURNZD",
    "GBPJPY","GBPCHF","GBPAUD","GBPCAD","GBPNZD",
    "AUDJPY","AUDNZD","AUDCAD","AUDCHF",
    "NZDJPY","NZDCAD","NZDCHF",
    "CADJPY","CADCHF","CHFJPY",
    "XAUUSD",
]

TIMEFRAMES = ["M5", "M15", "M30", "H1", "H4", "D1"]  # Skip M1: 1.5M bars too slow + overflow
EQUITY = 10000.0


def wait_for_fetch():
    """Wait until Dukascopy fetch is done (check for M1 parquet files)."""
    print("Waiting for Dukascopy data fetch to complete...")
    expected = len(SYMBOLS_BASE)
    while True:
        m1_files = list(CACHE_DIR.glob("*_M1_2021*.parquet"))
        # Also count .tp versions
        m1_tp = list(CACHE_DIR.glob("*_tp_M1_2021*.parquet"))
        count = len(m1_files) + len(m1_tp)
        if count >= expected:
            print(f"All {count} M1 files ready!")
            return
        # Check if any fetcher is still running
        import subprocess
        result = subprocess.run(["tasklist"], capture_output=True, text=True)
        python_procs = result.stdout.count("python")
        if python_procs <= 1 and count > 0:  # only this script running
            print(f"Fetchers seem done. {count}/{expected} M1 files available.")
            return
        print(f"  {count}/{expected} M1 files... (waiting 60s)")
        time.sleep(60)


def load_data(sym_base, tf):
    """Load cached parquet - try both Dukascopy (no suffix) and MT5 (.tp suffix) formats."""
    import pandas as pd
    # Try Dukascopy format first (EURUSD_M1_20210101_20260101.parquet)
    patterns = [
        CACHE_DIR / f"{sym_base}.tp_{tf}_2021*.parquet",
        CACHE_DIR / f"{sym_base}_{tf}_2021*.parquet",
        CACHE_DIR / f"{sym_base}.tp_{tf}_2024*.parquet",  # M15 2-year from MT5
    ]
    for pattern in patterns:
        files = sorted(glob.glob(str(pattern)))
        if files:
            df = pd.read_parquet(files[-1])  # newest
            if len(df) >= 200:
                return df
    return None


def main():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    log_path = OUTPUT_DIR / f"overnight_{timestamp}.txt"
    log = open(log_path, "w", encoding="utf-8")

    def log_print(msg):
        print(msg)
        log.write(msg + "\n")
        log.flush()

    # Phase 0: Wait for data
    wait_for_fetch()

    strategies = discover_strategies()
    log_print(f"Strategies: {len(strategies)}")
    log_print(f"Symbols: {len(SYMBOLS_BASE)}")
    log_print(f"Timeframes: {TIMEFRAMES}")
    log_print(f"Total potential combos: {len(SYMBOLS_BASE) * len(strategies) * len(TIMEFRAMES)}")

    # Phase 1: Screen
    log_print(f"\n{'='*60}")
    log_print(f"  PHASE 1: SCREEN")
    log_print(f"{'='*60}")

    screen_results = []
    data_map = {}
    t0 = time.time()
    data_loaded = 0
    data_failed = 0

    for sym in SYMBOLS_BASE:
        for tf in TIMEFRAMES:
            key = f"{sym}_{tf}"
            df = load_data(sym, tf)
            if df is not None:
                data_map[key] = df
                data_loaded += 1
            else:
                data_failed += 1

    log_print(f"Data loaded: {data_loaded} OK, {data_failed} failed")

    total = len(data_map) * len(strategies)
    done = 0

    for data_key, df in sorted(data_map.items()):
        sym, tf = data_key.rsplit("_", 1)
        days = (df["time"].iloc[-1] - df["time"].iloc[0]).days
        years = max(days / 365.0, 0.5)

        for sk, strat in sorted(strategies.items()):
            done += 1
            try:
                r = run_backtest(df, strat, strat.default_params(),
                                  EQUITY, 1.0, strat.max_positions, spread_mode="data")
                s = r.summary(years)
                s["symbol"] = sym
                s["tf"] = tf
                s["strategy"] = strat.name
                s["strategy_key"] = sk
                s["years"] = round(years, 1)
                screen_results.append(s)
            except Exception:
                pass

            if done % 500 == 0:
                el = time.time() - t0
                log_print(f"  Screen: {done}/{total} ({el:.0f}s)")

    log_print(f"Screen done: {len(screen_results)} combos in {time.time()-t0:.0f}s")

    # Filter viable
    viable = [r for r in screen_results
              if r["trades"] >= 10 and r["PF"] >= 0.8 and r["profit"] > 0]
    log_print(f"Viable: {len(viable)}/{len(screen_results)}")

    # Save screen
    screen_path = OUTPUT_DIR / f"overnight_screen_{timestamp}.json"
    with open(screen_path, "w") as f:
        json.dump(screen_results, f, indent=2, default=str)

    # Phase 2: Optimize
    log_print(f"\n{'='*60}")
    log_print(f"  PHASE 2: OPTIMIZE ({len(viable)} viable, 100 trials each)")
    log_print(f"{'='*60}")

    opt_results = []
    t0 = time.time()

    for i, combo in enumerate(viable):
        sym, tf, sk = combo["symbol"], combo["tf"], combo["strategy_key"]
        strat = strategies[sk]
        df = data_map.get(f"{sym}_{tf}")
        if df is None:
            continue

        days = (df["time"].iloc[-1] - df["time"].iloc[0]).days
        years = max(days / 365.0, 0.5)

        try:
            best_params, _ = optimize(df, strat, n_trials=100,
                                       max_positions=strat.max_positions, verbose=False)
            r = run_backtest(df, strat, best_params, EQUITY, 1.0,
                              strat.max_positions, spread_mode="data")
            s = r.summary(years)
            s["symbol"] = sym
            s["tf"] = tf
            s["strategy"] = strat.name
            s["strategy_key"] = sk
            s["years"] = round(years, 1)
            s["params"] = best_params

            # WF
            wf = run_walk_forward(df, strat, best_params, max_positions=strat.max_positions)
            oos_pfs = [w["OOS_PF"] for w in wf if w["OOS_trades"] > 0]
            wf_pc = sum(1 for p in oos_pfs if p >= 1.0) if oos_pfs else 0
            wf_tot = len(oos_pfs)
            wf_avg = sum(oos_pfs) / len(oos_pfs) if oos_pfs else 0
            s["wf"] = "PASS" if wf_pc >= wf_tot * 0.6 and wf_avg >= 1.2 else "FAIL"
            s["wf_detail"] = f"{wf_pc}/{wf_tot}"

            opt_results.append(s)

            if (i + 1) % 10 == 0 or s["wf"] == "PASS":
                el = time.time() - t0
                log_print(f"  [{i+1}/{len(viable)}] {strat.name:22s} {sym:14s} {tf:4s} | "
                          f"PF={s['PF']:5.2f} | {s['%/yr']:5.1f}% | DD={s['DD%']:5.1f}% | "
                          f"WF={s['wf']} ({s['wf_detail']}) | {el:.0f}s")

        except Exception as e:
            pass

    log_print(f"\nOptimize done: {len(opt_results)} combos in {time.time()-t0:.0f}s")

    # Save optimize results
    opt_path = OUTPUT_DIR / f"overnight_optimize_{timestamp}.json"
    with open(opt_path, "w") as f:
        json.dump(opt_results, f, indent=2, default=str)

    # Phase 3: Summary
    wf_pass = [r for r in opt_results if r.get("wf") == "PASS"]
    log_print(f"\n{'='*60}")
    log_print(f"  RESULTS")
    log_print(f"{'='*60}")
    log_print(f"  Screen:   {len(screen_results)} tested, {len(viable)} viable")
    log_print(f"  Optimize: {len(opt_results)} done, {len(wf_pass)} WF PASS")

    # Top 30
    wf_pass.sort(key=lambda x: x.get("%/yr", 0), reverse=True)
    log_print(f"\n  TOP 30 (WF PASS, sorted by %):")
    log_print(f"  {'#':>2s}  {'Strategy':22s} {'Symbol':14s} {'TF':4s} | {'PF':>5s} | {'%':>6s} | {'DD%':>5s} | {'Trades':>6s} | {'Data':>4s} | {'WF':>5s}")
    for i, r in enumerate(wf_pass[:30]):
        pf_s = f"{r['PF']:.2f}" if r['PF'] < 100 else f"{r['PF']:.0f}"
        log_print(f"  {i+1:2d}  {r['strategy']:22s} {r['symbol']:14s} {r['tf']:4s} | "
                  f"{pf_s:>5s} | {r['%/yr']:5.1f}% | {r['DD%']:5.1f}% | {r['trades']:6d} | "
                  f"{r['years']}y | {r['wf_detail']:>5s}")

    log.close()

    # Generate HTML
    try:
        from generate_top30 import generate_html as gen_top30
        gen_top30()
    except Exception as e:
        print(f"Top30 report generation: {e}")

    print(f"\nAll done! Results in: {log_path}")


if __name__ == "__main__":
    main()
