#!/usr/bin/env python
"""Generate Top 30 HTML report from all optimization runs."""
import re
from pathlib import Path
from datetime import datetime

OUTPUT_DIR = Path(__file__).parent.parent / "output"
USD_TO_THB = 34.0
EQUITY = 10000.0


def parse_all_results():
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
                        all_entries.append(dict(strat=strat, sym=sym, tf=tf,
                                                pf=float(pf), dd=float(dd), wf=wf, wf_d=wf_d))

    # Parse low_tf for %/yr + trades
    low_tf_path = OUTPUT_DIR / "low_tf_run.txt"
    pct_map = {}
    if low_tf_path.exists():
        for line in low_tf_path.read_text(errors="replace").split("\n"):
            m = re.match(
                r"\s+(\S+)\s+(\S+)\s+(\S+)\s+\|\s+([\d.]+)\s+\|\s+([\d.]+)%\s+\|\s+([\d.]+)%\s+\|\s+(\d+)\s+\|\s+(\S+)",
                line,
            )
            if m:
                strat, sym, tf, pf, pct, dd, trades, wf_d = m.groups()
                pct_map[f"{strat}|{sym}|{tf}"] = dict(pct=float(pct), trades=int(trades))

    # Deduplicate: best per combo, PASS only
    best = {}
    for e in all_entries:
        key = f"{e['strat']}|{e['sym']}|{e['tf']}"
        if e["wf"] != "PASS":
            continue
        if key not in best or e["pf"] > best[key]["pf"]:
            best[key] = e
            info = pct_map.get(key, {})
            e["pct"] = info.get("pct", 0)
            e["trades"] = info.get("trades", 0)

    passed = sorted(best.values(), key=lambda x: x["pct"] if x["pct"] > 0 else x["pf"] * 0.01, reverse=True)
    return passed


def generate_html():
    passed = parse_all_results()
    top30 = passed[:30]
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    eq_thb = EQUITY * USD_TO_THB

    rows_html = ""
    for i, e in enumerate(top30):
        pf = e["pf"]
        pct = e["pct"]
        dd = e["dd"]
        trades = e["trades"]
        wf_d = e["wf_d"]
        thb_yr = pct / 100 * eq_thb

        # Rating
        if pct > 20 and dd < 10 and trades > 100:
            rating = "A+"
            rat_cls = "pass"
        elif pct > 10 and dd < 15:
            rating = "A"
            rat_cls = "pass"
        elif pct > 5 and dd < 10:
            rating = "B+"
            rat_cls = "pass"
        elif pct > 3 and dd < 15:
            rating = "B"
            rat_cls = "warn"
        elif pct > 0:
            rating = "C"
            rat_cls = "warn"
        else:
            rating = "-"
            rat_cls = "bad"

        row_cls = "gold" if i == 0 else ("top3" if i < 3 else "")
        pf_s = f"{pf:.2f}" if pf < 100 else f"{pf:.0f}"
        pct_s = f"{pct:.1f}%" if pct > 0 else "-"
        thb_s = f"{thb_yr:,.0f}" if pct > 0 else "-"
        tr_s = f"{trades:,}" if trades > 0 else "-"
        dd_cls = "pass" if dd < 5 else ("warn" if dd < 15 else "bad")

        rows_html += f"""<tr class="{row_cls}">
  <td class="rank">{i+1}</td>
  <td>{e["strat"]}</td><td>{e["sym"]}</td><td>{e["tf"]}</td>
  <td>{pf_s}</td>
  <td><b>{pct_s}</b></td>
  <td>{thb_s}</td>
  <td class="{dd_cls}">{dd:.1f}%</td>
  <td>{tr_s}</td>
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
  table {{ border-collapse:collapse; width:100%; margin:15px 0; font-size:0.88em; }}
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
  .rating-table {{ width:auto; margin:10px 0; }}
  .rating-table td, .rating-table th {{ padding:5px 15px; }}
  h2 {{ color:#79c0ff; margin:25px 0 10px; font-size:1.2em; }}
</style>
</head>
<body>
<h1>FlashEASuite V2 - TOP 30 Strategy Combinations</h1>
<div class="sub">Generated: {now} | WF Validated | Spread Cost Included | THB (1 USD = {USD_TO_THB:.0f} THB) | Equity: {eq_thb:,.0f}</div>

<div class="summary-box">
  <p><b>Total WF PASS:</b> {len(passed)} combos | 29 symbols x 16 strategies x M15-W1</p>
  <p><b>Data:</b> 2-5 years | <b>Optimization:</b> Optuna TPE 100 trials | <b>Spread:</b> Real broker data</p>
  <p class="note">% = annualized return | DD% = max drawdown | WF = walk-forward windows passed</p>
</div>

<table>
<tr>
  <th>#</th><th>Strategy</th><th>Symbol</th><th>TF</th>
  <th>PF</th><th>%</th><th>THB/yr</th><th>DD%</th><th>Trades</th><th>WF</th><th>Rating</th>
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
    print(f"Top 30 of {len(passed)} WF PASS combos")


if __name__ == "__main__":
    generate_html()
