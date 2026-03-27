#!/usr/bin/env python
"""
Parallel optimizer — uses multiprocessing to run N workers.
Each worker handles a batch of symbol-TF combos.
"""
import sys, json, time, os, multiprocessing
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
os.environ["PYTHONPATH"] = str(Path(__file__).parent)

OUTPUT = Path(__file__).parent.parent / "output"
OUTPUT.mkdir(exist_ok=True)
CACHE = Path(__file__).parent / "data" / "cache"

TFS = ["M15", "M30", "H1", "H4", "D1"]  # Skip M5 (500K bars too slow per worker)
EQUITY = 10000.0
N_TRIALS = 100


def load_all_data():
    """Load all cached parquet files into a dict."""
    import pandas as pd
    data_map = {}
    for f in sorted(CACHE.glob("*.parquet")):
        name = f.stem
        # Dukascopy: EURUSD.tp_M5_20210101_20260101
        # MT5: EURUSD_tp_M5_20210325_20260325
        parts = name.split("_")
        if ".tp" in parts[0]:
            sym = parts[0]
            tf = parts[1]
        elif len(parts) >= 3 and parts[1] == "tp":
            sym = parts[0] + ".tp"
            tf = parts[2]
        else:
            continue
        if tf not in TFS:
            continue
        key = f"{sym}_{tf}"
        if key not in data_map:
            try:
                df = pd.read_parquet(f)
                if len(df) >= 200:
                    data_map[key] = str(f)  # store path, not df (for pickling)
            except:
                pass
    return data_map


def process_combo(args):
    """Worker: screen + optimize + WF for one combo."""
    import pandas as pd
    sys.path.insert(0, str(Path(__file__).parent))
    from strategies.base import discover_strategies
    from engine.backtester import run_backtest
    from optimize.optuna_runner import optimize
    from optimize.walk_forward import run_walk_forward

    data_path, sym, tf, strat_key = args
    strategies = discover_strategies()
    strat = strategies.get(strat_key)
    if strat is None:
        return None

    try:
        df = pd.read_parquet(data_path)
    except:
        return None

    days = (df["time"].iloc[-1] - df["time"].iloc[0]).days
    years = max(days / 365.0, 0.5)

    # Screen with default params
    try:
        r = run_backtest(df, strat, strat.default_params(), EQUITY, 1.0, strat.max_positions, "none")
        s = r.summary(years)
    except:
        return None

    # Filter
    if s["trades"] < 10 or s["PF"] < 0.8 or s["profit"] <= 0:
        return {"symbol": sym, "tf": tf, "strategy": strat.name, "status": "filtered",
                "trades": s["trades"], "PF": s["PF"]}

    # Optimize
    try:
        best_params, _ = optimize(df, strat, n_trials=N_TRIALS,
                                   max_positions=strat.max_positions, verbose=False)
        r = run_backtest(df, strat, best_params, EQUITY, 1.0, strat.max_positions, "none")
        s = r.summary(years)
        s["symbol"] = sym
        s["tf"] = tf
        s["strategy"] = strat.name
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
        s["status"] = "optimized"
        return s

    except Exception as e:
        return {"symbol": sym, "tf": tf, "strategy": strat.name, "status": f"error: {e}"}


def main():
    n_workers = max(1, multiprocessing.cpu_count() - 1)
    print(f"Workers: {n_workers} CPUs")

    # Load data paths
    data_map = load_all_data()
    print(f"Data: {len(data_map)} symbol-TF combos")

    # Build job list
    from strategies.base import discover_strategies
    strategies = discover_strategies()
    print(f"Strategies: {len(strategies)}")

    jobs = []
    for dkey, fpath in sorted(data_map.items()):
        sym, tf = dkey.rsplit("_", 1)
        for sk in sorted(strategies.keys()):
            jobs.append((fpath, sym, tf, sk))

    total = len(jobs)
    print(f"Total jobs: {total}")
    print(f"Starting {n_workers} workers...\n")

    t0 = time.time()
    results = []
    optimized = 0
    wf_pass = 0

    with multiprocessing.Pool(n_workers) as pool:
        for i, result in enumerate(pool.imap_unordered(process_combo, jobs)):
            if result is not None:
                results.append(result)
                if result.get("status") == "optimized":
                    optimized += 1
                    if result.get("wf") == "PASS":
                        wf_pass += 1
                        # Print PASS results
                        pf = result.get("PF", 0)
                        pct = result.get("%/yr", 0)
                        dd = result.get("DD%", 0)
                        trades = result.get("trades", 0)
                        print(f"  [{i+1}/{total}] {result['strategy']:22s} {result['symbol']:14s} {result['tf']:4s} | "
                              f"PF={pf:5.2f} | {pct:6.1f}% | DD={dd:5.1f}% | WF={result.get('wf_detail','')} PASS")

            if (i + 1) % 100 == 0:
                elapsed = time.time() - t0
                rate = (i + 1) / elapsed
                eta = (total - i - 1) / rate
                print(f"  Progress: {i+1}/{total} | optimized={optimized} | WF PASS={wf_pass} | "
                      f"{elapsed:.0f}s elapsed | ETA {eta:.0f}s ({eta/60:.0f}min)")

    elapsed = time.time() - t0
    print(f"\nDone! {total} jobs in {elapsed:.0f}s ({elapsed/60:.0f}min)")
    print(f"Optimized: {optimized} | WF PASS: {wf_pass}")

    # Save
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    out_path = OUTPUT / f"parallel_{timestamp}.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print(f"Saved: {out_path}")

    # Top 30
    passed = [r for r in results if r.get("wf") == "PASS" and r.get("status") == "optimized"]
    passed.sort(key=lambda x: x.get("%/yr", 0), reverse=True)
    print(f"\nTOP 30 (WF PASS):")
    print(f"  {'#':>2s}  {'Strategy':22s} {'Symbol':14s} {'TF':4s} | {'PF':>5s} | {'%':>6s} | {'DD%':>5s} | {'Trades':>6s} | {'WF':>5s}")
    for i, r in enumerate(passed[:30]):
        pf = f"{r['PF']:.2f}" if r['PF'] < 100 else f"{r['PF']:.0f}"
        print(f"  {i+1:2d}  {r['strategy']:22s} {r['symbol']:14s} {r['tf']:4s} | "
              f"{pf:>5s} | {r['%/yr']:5.1f}% | {r['DD%']:5.1f}% | {r['trades']:6d} | {r.get('wf_detail','')}")


if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
