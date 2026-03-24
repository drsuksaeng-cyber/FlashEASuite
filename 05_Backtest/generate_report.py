#!/usr/bin/env python
"""Generate HTML report from optimization results."""
import json
from pathlib import Path
from datetime import datetime

OUTPUT_DIR = Path(__file__).parent.parent / "output"


def generate_html():
    json_path = OUTPUT_DIR / "best_params_all.json"
    if not json_path.exists():
        print("No results found. Run optimization first.")
        return

    data = json.loads(json_path.read_text())

    # Group by strategy
    strategies = {}
    for key, val in sorted(data.items()):
        s = val["strategy"]
        if s not in strategies:
            strategies[s] = []
        strategies[s].append(val)

    # All unique symbols and TFs
    symbols = sorted(set(v["symbol"] for v in data.values()))
    tfs = sorted(set(v["tf"] for v in data.values()), key=lambda x: {"H1": 1, "H4": 2, "D1": 3}.get(x, 9))

    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>FlashEASuite V2 - Optimization Report</title>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: 'Segoe UI', Tahoma, sans-serif; background: #0d1117; color: #c9d1d9; padding: 20px; }}
  h1 {{ color: #58a6ff; margin-bottom: 5px; }}
  h2 {{ color: #79c0ff; margin: 30px 0 10px; border-bottom: 1px solid #30363d; padding-bottom: 5px; }}
  h3 {{ color: #d2a8ff; margin: 20px 0 8px; }}
  .timestamp {{ color: #8b949e; font-size: 0.9em; margin-bottom: 20px; }}
  .summary {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 15px; margin: 15px 0; }}
  table {{ border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 0.85em; }}
  th {{ background: #21262d; color: #58a6ff; padding: 8px 10px; text-align: left; border: 1px solid #30363d; }}
  td {{ padding: 6px 10px; border: 1px solid #30363d; }}
  tr:hover {{ background: #161b22; }}
  .pass {{ color: #3fb950; font-weight: bold; }}
  .fail {{ color: #f85149; }}
  .best {{ background: #1a2332 !important; }}
  .param-table td {{ font-family: monospace; font-size: 0.82em; }}
  .heatmap-good {{ background: rgba(63, 185, 80, 0.15); }}
  .heatmap-bad {{ background: rgba(248, 81, 73, 0.15); }}
  .heatmap-neutral {{ background: rgba(139, 148, 158, 0.08); }}
  .matrix {{ margin: 20px 0; }}
  .legend {{ display: flex; gap: 20px; margin: 10px 0; font-size: 0.85em; }}
  .legend span {{ display: flex; align-items: center; gap: 5px; }}
  .dot {{ width: 12px; height: 12px; border-radius: 50%; display: inline-block; }}
  .dot-pass {{ background: #3fb950; }}
  .dot-fail {{ background: #f85149; }}
  .section {{ margin-bottom: 40px; }}
</style>
</head>
<body>
<h1>FlashEASuite V2 - Optimization Report</h1>
<div class="timestamp">Generated: {now} | Python Optuna 200 trials | 5-year data (2021-2026) | Walk-Forward Validated</div>
"""

    # ========== SECTION 1: Overview Matrix ==========
    html += '<div class="section"><h2>1. Walk-Forward Results Matrix</h2>'
    html += '<div class="legend"><span><div class="dot dot-pass"></div> WF PASS</span><span><div class="dot dot-fail"></div> WF FAIL</span></div>'
    html += '<table><tr><th>Strategy</th>'
    for sym in symbols:
        for tf in tfs:
            html += f'<th>{sym.replace(".tp","")}<br>{tf}</th>'
    html += '<th>PASS</th></tr>'

    for strat_name, combos in sorted(strategies.items()):
        html += f'<tr><td><b>{strat_name}</b></td>'
        pass_count = 0
        for sym in symbols:
            for tf in tfs:
                match = [c for c in combos if c["symbol"] == sym and c["tf"] == tf]
                if match:
                    c = match[0]
                    wf = c.get("wf_status", "N/A")
                    pf = c["pf"]
                    cls = "pass" if wf == "PASS" else "fail"
                    bg = "heatmap-good" if wf == "PASS" else "heatmap-bad" if pf < 1.0 else "heatmap-neutral"
                    pf_str = f"{pf:.1f}" if pf < 100 else "999"
                    html += f'<td class="{bg}"><span class="{cls}">{wf}</span><br>PF={pf_str} DD={c["dd"]:.1f}%</td>'
                    if wf == "PASS":
                        pass_count += 1
                else:
                    html += '<td class="heatmap-neutral">-</td>'
        total_combos = len(symbols) * len(tfs)
        html += f'<td><b>{pass_count}/{total_combos}</b></td></tr>'

    html += '</table></div>'

    # ========== SECTION 2: Detailed Results per Strategy ==========
    html += '<div class="section"><h2>2. Detailed Results & Best Parameters</h2>'

    for strat_name, combos in sorted(strategies.items()):
        html += f'<h3>{strat_name}</h3>'

        # Performance table
        html += '<table><tr><th>Symbol</th><th>TF</th><th>PF</th><th>WR%</th><th>DD%</th><th>Trades</th><th>Score</th><th>WF</th><th>WF Avg PF</th></tr>'
        for c in sorted(combos, key=lambda x: (x["symbol"], x["tf"])):
            wf = c.get("wf_status", "N/A")
            cls = "pass" if wf == "PASS" else "fail"
            row_cls = "best" if wf == "PASS" and c["pf"] > 1.5 else ""
            pf_str = f'{c["pf"]:.2f}' if c["pf"] < 100 else "999"
            html += f'<tr class="{row_cls}"><td>{c["symbol"]}</td><td>{c["tf"]}</td>'
            html += f'<td>{pf_str}</td><td>{c["wr"]:.1f}</td><td>{c["dd"]:.1f}</td>'
            html += f'<td>{c["trades"]}</td><td>{c["score"]:.2f}</td>'
            html += f'<td class="{cls}">{wf}</td>'
            html += f'<td>{c.get("wf_avg_pf", 0):.2f}</td></tr>'
        html += '</table>'

        # Parameters table (only for WF PASS combos)
        pass_combos = [c for c in combos if c.get("wf_status") == "PASS"]
        if pass_combos:
            # Get all param keys
            all_keys = set()
            for c in pass_combos:
                all_keys.update(c.get("params", {}).keys())
            all_keys = sorted(all_keys)

            if all_keys:
                html += '<h4 style="color:#8b949e;margin-top:10px">Best Parameters (WF PASS only):</h4>'
                html += '<table class="param-table"><tr><th>Symbol</th><th>TF</th>'
                for k in all_keys:
                    html += f'<th>{k}</th>'
                html += '</tr>'
                for c in sorted(pass_combos, key=lambda x: (x["symbol"], x["tf"])):
                    html += f'<tr><td>{c["symbol"]}</td><td>{c["tf"]}</td>'
                    for k in all_keys:
                        val = c.get("params", {}).get(k, "")
                        if isinstance(val, float):
                            html += f'<td>{val:.4f}</td>' if val != int(val) else f'<td>{int(val)}</td>'
                        else:
                            html += f'<td>{val}</td>'
                    html += '</tr>'
                html += '</table>'

    html += '</div>'

    # ========== SECTION 3: Summary Stats ==========
    total_combos = len(data)
    total_pass = sum(1 for v in data.values() if v.get("wf_status") == "PASS")
    best_combo = max(data.values(), key=lambda x: x["score"] if x.get("wf_status") == "PASS" else 0)

    html += f"""
<div class="section"><h2>3. Summary</h2>
<div class="summary">
<p><b>Total combinations tested:</b> {total_combos} (7 strategies x 3 symbols x 2 TFs)</p>
<p><b>Walk-Forward PASS:</b> {total_pass}/{total_combos} ({total_pass/total_combos*100:.0f}%)</p>
<p><b>Best WF-PASS combo:</b> {best_combo['strategy']} {best_combo['symbol']} {best_combo['tf']} (PF={best_combo['pf']:.2f}, Score={best_combo['score']:.2f})</p>
<p><b>Strategies ready for deployment:</b></p>
<ul style="margin-left:20px;margin-top:5px">"""

    for strat_name, combos in sorted(strategies.items()):
        pass_combos = [c for c in combos if c.get("wf_status") == "PASS"]
        if pass_combos:
            pairs = ", ".join(f'{c["symbol"].replace(".tp","")} {c["tf"]}' for c in pass_combos)
            html += f'<li><b>{strat_name}</b>: {pairs}</li>'

    html += """</ul>
</div></div>
</body></html>"""

    # Write
    html_path = OUTPUT_DIR / "optimization_report.html"
    html_path.write_text(html, encoding="utf-8")
    print(f"Report saved: {html_path}")
    print(f"Total combos: {total_combos} | WF PASS: {total_pass}")


if __name__ == "__main__":
    generate_html()
