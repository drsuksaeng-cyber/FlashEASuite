#!/usr/bin/env python
"""
Run M5/M15/M30/H1 screen + optimize for all 29 symbols x 16 strategies.
Output: top 30 table sorted by %/yr.
"""
import sys, json, time, re
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from data.mt5_fetcher import fetch_ohlcv, _cache_path
from strategies.base import discover_strategies
from engine.backtester import run_backtest
from optimize.optuna_runner import optimize
from optimize.walk_forward import run_walk_forward

OUTPUT_DIR = Path(__file__).parent.parent / "output"

SYMBOLS = [
    "EURUSD.tp","GBPUSD.tp","USDJPY.tp","USDCHF.tp","USDCAD.tp","AUDUSD.tp","NZDUSD.tp",
    "EURGBP.tp","EURJPY.tp","EURCHF.tp","EURAUD.tp","EURCAD.tp","EURNZD.tp",
    "GBPJPY.tp","GBPCHF.tp","GBPAUD.tp","GBPCAD.tp","GBPNZD.tp",
    "AUDJPY.tp","AUDNZD.tp","AUDCAD.tp","AUDCHF.tp",
    "NZDJPY.tp","NZDCAD.tp","NZDCHF.tp",
    "CADJPY.tp","CADCHF.tp","CHFJPY.tp",
    "XAUUSD.tp",
]

TIMEFRAMES = ["M15", "M30", "H1"]  # M5 not available for 2+ years
EQUITY = 10000.0
YEARS = 2.0  # M15 data is 2 years


def main():
    strategies = discover_strategies()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    all_results = []

    # Load data
    data_map = {}
    for sym in SYMBOLS:
        for tf in TIMEFRAMES:
            key = f"{sym}_{tf}"
            try:
                df = fetch_ohlcv(sym, tf, source="mt5")
                if len(df) >= 200:
                    data_map[key] = df
            except:
                pass
    print(f"Data loaded: {len(data_map)} symbol-TF combos")

    # Screen
    total = len(data_map) * len(strategies)
    done = 0
    t0 = time.time()
    screen = []

    for data_key, df in sorted(data_map.items()):
        parts = data_key.rsplit("_", 1)
        sym, tf = parts[0], parts[1]
        for sk, strat in sorted(strategies.items()):
            done += 1
            try:
                r = run_backtest(df, strat, strat.default_params(),
                                  EQUITY, 1.0, strat.max_positions, spread_mode="data")
                s = r.summary(YEARS)
                s["symbol"] = sym
                s["tf"] = tf
                s["strategy"] = strat.name
                s["strategy_key"] = sk
                screen.append(s)
            except:
                pass
            if done % 200 == 0:
                el = time.time() - t0
                print(f"  Screen: {done}/{total} ({el:.0f}s)")

    print(f"Screen done: {len(screen)} combos in {time.time()-t0:.0f}s")

    # Filter viable
    viable = [r for r in screen if r["trades"] >= 10 and r["PF"] >= 0.8 and r["profit"] > 0]
    print(f"Viable: {len(viable)}/{len(screen)}")

    # Optimize viable
    t0 = time.time()
    for i, combo in enumerate(viable):
        sym, tf, sk = combo["symbol"], combo["tf"], combo["strategy_key"]
        strat = strategies[sk]
        df = data_map.get(f"{sym}_{tf}")
        if df is None:
            continue

        if (i+1) % 20 == 0:
            print(f"  Optimize: {i+1}/{len(viable)} ({time.time()-t0:.0f}s)")

        try:
            best_params, _ = optimize(df, strat, n_trials=100,
                                       max_positions=strat.max_positions, verbose=False)
            r = run_backtest(df, strat, best_params, EQUITY, 1.0,
                              strat.max_positions, spread_mode="data")
            s = r.summary(YEARS)
            s["symbol"] = sym
            s["tf"] = tf
            s["strategy"] = strat.name

            # WF
            wf = run_walk_forward(df, strat, best_params, max_positions=strat.max_positions)
            oos_pfs = [w["OOS_PF"] for w in wf if w["OOS_trades"] > 0]
            wf_pc = sum(1 for p in oos_pfs if p >= 1.0) if oos_pfs else 0
            wf_tot = len(oos_pfs)
            wf_avg = sum(oos_pfs)/len(oos_pfs) if oos_pfs else 0
            s["wf"] = "PASS" if wf_pc >= wf_tot*0.6 and wf_avg >= 1.2 else "FAIL"
            s["wf_detail"] = f"{wf_pc}/{wf_tot}"
            s["params"] = best_params

            all_results.append(s)
        except:
            pass

    print(f"Optimize done: {len(all_results)} combos in {time.time()-t0:.0f}s")

    # Save
    json_path = OUTPUT_DIR / f"low_tf_{timestamp}.json"
    json_path.write_text(json.dumps(all_results, indent=2, default=str))

    # Print results by TF
    for tf in TIMEFRAMES:
        tf_results = [r for r in all_results if r["tf"] == tf]
        tf_pass = [r for r in tf_results if r.get("wf") == "PASS"]
        print(f"\n{'='*70}")
        print(f"  {tf}: {len(tf_pass)} PASS / {len(tf_results)} optimized")
        print(f"{'='*70}")
        tf_pass.sort(key=lambda x: x["%/yr"], reverse=True)
        for r in tf_pass[:15]:
            print(f"  {r['strategy']:22s} {r['symbol']:14s} | PF={r['PF']:5.2f} | {r['%/yr']:6.1f}% | DD={r['DD%']:5.1f}% | trades={r['trades']:5d} | WF={r['wf_detail']}")

    # Top 30 overall
    passed = [r for r in all_results if r.get("wf") == "PASS"]
    passed.sort(key=lambda x: x["%/yr"], reverse=True)
    print(f"\n{'='*70}")
    print(f"  TOP 30 (M5-H1, WF PASS, sorted by %)")
    print(f"{'='*70}")
    print(f"  {'Strategy':22s} {'Symbol':14s} {'TF':4s} | {'PF':>5s} | {'%':>6s} | {'DD%':>5s} | {'Trades':>6s} | {'WF':>5s}")
    print(f"  {'-'*22} {'-'*14} {'-'*4} | {'-'*5} | {'-'*6} | {'-'*5} | {'-'*6} | {'-'*5}")
    for r in passed[:30]:
        print(f"  {r['strategy']:22s} {r['symbol']:14s} {r['tf']:4s} | {r['PF']:5.2f} | {r['%/yr']:5.1f}% | {r['DD%']:5.1f}% | {r['trades']:6d} | {r['wf_detail']:>5s}")


if __name__ == "__main__":
    main()
