#!/usr/bin/env python
"""Generate Top 30 HTML report — re-runs backtest for accurate %/yr and trades."""
import re, sys, json
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent))

from data.mt5_fetcher import fetch_ohlcv
from strategies.base import discover_strategies
from engine.backtester import run_backtest

OUTPUT_DIR = Path(__file__).parent.parent / "output"
USD_TO_THB = 34.0
EQUITY = 10000.0


def parse_wf_pass_combos():
    """Parse all WF PASS combos from logs."""
    all_entries = []
    for logfile in [OUTPUT_DIR / "full_matrix_run.txt", OUTPUT_DIR / "low_tf_run.txt"]:
        if not logfile.exists():
            continue
        lines = logfile.read_text(errors="replace").split("\n")
        for i, line in enumerate(lines):
            m = re.search(r"Optimize: (\S+) (\S+) (\S+)", line)
            if m:
                strat, sym, tf = m.groups()
                if i + 1 < len(lines):
                    wm = re.search(r"PF=([\d.]+) DD=([\d.]+)% WF=(\w+) \((\d+/\d+)\)", lines[i + 1].strip())
                    if wm:
                        pf, dd, wf, wf_d = wm.groups()
                        if wf == "PASS":
                            all_entries.append(dict(strat=strat, sym=sym, tf=tf,
                                                    pf=float(pf), dd=float(dd), wf_d=wf_d))

    # Deduplicate
    best = {}
    for e in all_entries:
        key = f"{e['strat']}|{e['sym']}|{e['tf']}"
        if key not in best or e["pf"] > best[key]["pf"]:
            best[key] = e
    return list(best.values())


def compute_metrics(combos, strategies):
    """Re-run backtest for each combo to get accurate %/yr and trades."""
    results = []
    total = len(combos)

    for i, e in enumerate(combos):
        strat_name = e["strat"]
        sym = e["sym"]
        tf = e["tf"]

        # Find strategy
        strat_obj = None
        for sk, s in strategies.items():
            if s.name == strat_name:
                strat_obj = s
                break
        if strat_obj is None:
            continue

        try:
            df = fetch_ohlcv(sym, tf, source="mt5")
        except Exception:
            continue

        if len(df) < 200:
            continue

        # Estimate years from data range
        days = (df["time"].iloc[-1] - df["time"].iloc[0]).days
        years = max(days / 365.0, 0.5)

        try:
            r = run_backtest(df, strat_obj, strat_obj.default_params(),
                              EQUITY, 1.0, strat_obj.max_positions, spread_mode="data")
            s = r.summary(years)
            e["pct"] = s["%/yr"]
            e["thb_yr"] = s["$/yr"] * USD_TO_THB
            e["trades"] = s["trades"]
            e["profit"] = s["profit"]
            e["pf_actual"] = s["PF"]
            e["dd_actual"] = s["DD%"]
            e["sharpe"] = s["Sharpe"]
            e["years"] = round(years, 1)
            results.append(e)
        except Exception:
            continue

        if (i + 1) % 50 == 0:
            print(f"  Computing: {i+1}/{total}")

    return results


def generate_html(results):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    eq_thb = EQUITY * USD_TO_THB

    # Sort by %
    results.sort(key=lambda x: x.get("pct", 0), reverse=True)
    top30 = results[:30]

    rows_html = ""
    for i, e in enumerate(top30):
        pf = e.get("pf_actual", e["pf"])
        pct = e.get("pct", 0)
        dd = e.get("dd_actual", e["dd"])
        trades = e.get("trades", 0)
        wf_d = e["wf_d"]
        thb_yr = e.get("thb_yr", 0)
        sharpe = e.get("sharpe", 0)
        years = e.get("years", 0)

        # Rating
        if pct > 20 and dd < 10 and trades > 100:
            rating, rat_cls = "A+", "pass"
        elif pct > 10 and dd < 15:
            rating, rat_cls = "A", "pass"
        elif pct > 5 and dd < 10:
            rating, rat_cls = "B+", "pass"
        elif pct > 3 and dd < 15:
            rating, rat_cls = "B", "warn"
        elif pct > 0:
            rating, rat_cls = "C", "warn"
        else:
            rating, rat_cls = "-", "bad"

        row_cls = "gold" if i == 0 else ("top3" if i < 3 else "")
        pf_s = f"{pf:.2f}" if pf < 100 else f"{pf:.0f}"
        dd_cls = "pass" if dd < 5 else ("warn" if dd < 15 else "bad")

        rows_html += f"""<tr class="{row_cls}">
  <td class="rank">{i+1}</td>
  <td>{e['strat']}</td><td>{e['sym']}</td><td>{e['tf']}</td>
  <td>{pf_s}</td>
  <td><b>{pct:.1f}%</b></td>
  <td>{thb_yr:,.0f}</td>
  <td class="{dd_cls}">{dd:.1f}%</td>
  <td>{trades:,}</td>
  <td>{sharpe:.2f}</td>
  <td>{years}y</td>
  <td class="pass">{wf_d}</td>
  <td class="{rat_cls}">{rating}</td>
</tr>
"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>FlashEASuite V2 - TOP 30</title>
<style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ font-family:'Segoe UI',Tahoma,sans-serif; background:#0d1117; color:#c9d1d9; padding:20px; }}
  h1 {{ color:#ffd700; margin-bottom:5px; font-size:1.6em; }}
  .sub {{ color:#8b949e; font-size:0.9em; margin-bottom:20px; }}
  table {{ border-collapse:collapse; width:100%; margin:15px 0; font-size:0.85em; }}
  th {{ background:#21262d; color:#58a6ff; padding:10px 12px; text-align:left; border:1px solid #30363d; position:sticky; top:0; }}
  td {{ padding:8px 12px; border:1px solid #30363d; }}
  tr:hover {{ background:#161b22; }}
  .gold {{ background:rgba(255,215,0,0.18) !important; border-left:3px solid #ffd700 !important; }}
  .top3 {{ background:rgba(255,215,0,0.10) !important; }}
  .pass {{ color:#3fb950; font-weight:bold; }}
  .warn {{ color:#d29922; font-weight:bold; }}
  .bad {{ color:#f85149; font-weight:bold; }}
  .rank {{ color:#ffd700; font-weight:bold; font-size:1.1em; }}
  .note {{ color:#8b949e; font-size:0.82em; margin:8px 0; }}
  .summary-box {{ background:#161b22; border:1px solid #30363d; border-radius:8px; padding:15px; margin:15px 0; }}
  h2 {{ color:#79c0ff; margin:25px 0 10px; font-size:1.2em; }}
  .rating-table {{ width:auto; margin:10px 0; }}
  .rating-table td, .rating-table th {{ padding:5px 15px; }}
</style>
</head>
<body>
<h1>FlashEASuite V2 - TOP 30 Strategy Combinations</h1>
<div class="sub">Generated: {now} | WF Validated | Spread Cost Included | THB (1 USD = {USD_TO_THB:.0f}) | Equity: {eq_thb:,.0f}</div>

<div class="summary-box">
  <p><b>Total WF PASS:</b> {len(results)} combos | 29 symbols x 16 strategies x M15-W1</p>
  <p><b>Optimization:</b> Optuna TPE 100 trials | <b>Spread:</b> Real broker data | <b>Backtest:</b> Re-computed with spread cost</p>
  <p class="note">% = annualized return | DD% = max drawdown | Sharpe = risk-adjusted | Data = actual years available</p>
</div>

<table>
<tr>
  <th>#</th><th>Strategy</th><th>Symbol</th><th>TF</th>
  <th>PF</th><th>%</th><th>THB</th><th>DD%</th><th>Trades</th><th>Sharpe</th><th>Data</th><th>WF</th><th>Rate</th>
</tr>
{rows_html}
</table>

<h2>Rating Criteria</h2>
<table class="rating-table">
<tr><th>Rating</th><th>Conditions</th></tr>
<tr><td class="pass">A+</td><td>% &gt; 20, DD &lt; 10%, Trades &gt; 100</td></tr>
<tr><td class="pass">A</td><td>% &gt; 10, DD &lt; 15%</td></tr>
<tr><td class="pass">B+</td><td>% &gt; 5, DD &lt; 10%</td></tr>
<tr><td class="warn">B</td><td>% &gt; 3, DD &lt; 15%</td></tr>
<tr><td class="warn">C</td><td>% &gt; 0</td></tr>
</table>

</body></html>"""

    out_path = OUTPUT_DIR / "top30_report.html"
    out_path.write_text(html, encoding="utf-8")
    print(f"Saved: {out_path}")
    print(f"Top 30 of {len(results)} combos with full metrics")


def main():
    print("Parsing WF PASS combos...")
    combos = parse_wf_pass_combos()
    print(f"Found {len(combos)} WF PASS combos")

    print("Loading strategies...")
    strategies = discover_strategies()

    print("Re-computing metrics (with spread)...")
    results = compute_metrics(combos, strategies)
    print(f"Computed: {len(results)} combos")

    print("Generating HTML...")
    generate_html(results)


if __name__ == "__main__":
    main()
