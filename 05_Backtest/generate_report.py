#!/usr/bin/env python
"""Generate HTML report from optimization results."""
import json
from pathlib import Path
from datetime import datetime

OUTPUT_DIR = Path(__file__).parent.parent / "output"

# Currency settings
ACCOUNT_CURRENCY = "USD"
DISPLAY_CURRENCY = "THB"
DISPLAY_SYMBOL = "฿"
USD_TO_THB = 34.0


def to_display(usd_amount: float) -> float:
    return usd_amount * USD_TO_THB


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

    symbols = sorted(set(v["symbol"] for v in data.values()))
    tfs = sorted(set(v["tf"] for v in data.values()), key=lambda x: {"H1": 1, "H4": 2, "D1": 3}.get(x, 9))

    # Pre-compute: best PASS combo per strategy (by profit_per_year)
    best_pass_per_strat = {}
    for strat_name, combos in strategies.items():
        pass_combos = [c for c in combos if c.get("wf_status") == "PASS"]
        if pass_combos:
            best = max(pass_combos, key=lambda x: x.get("profit_per_year", x.get("profit", 0) / 5))
            best_pass_per_strat[strat_name] = (best["symbol"], best["tf"])

    # Global best across all strategies
    all_pass = [v for v in data.values() if v.get("wf_status") == "PASS"]
    global_best_key = None
    if all_pass:
        gb = max(all_pass, key=lambda x: x.get("profit_per_year", x.get("profit", 0) / 5))
        global_best_key = (gb["strategy"], gb["symbol"], gb["tf"])

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
  .negative {{ color: #f85149; }}
  .param-table td {{ font-family: monospace; font-size: 0.82em; }}
  .heatmap-good {{ background: rgba(63, 185, 80, 0.15); }}
  .heatmap-bad {{ background: rgba(248, 81, 73, 0.15); }}
  .heatmap-neutral {{ background: rgba(139, 148, 158, 0.08); }}
  .gold {{ background: rgba(255, 215, 0, 0.20) !important; border-left: 3px solid #ffd700 !important; }}
  .strat-best {{ background: rgba(100, 200, 255, 0.15) !important; border-left: 3px solid #58a6ff !important; }}
  .legend {{ display: flex; gap: 20px; margin: 10px 0; font-size: 0.85em; flex-wrap: wrap; }}
  .legend span {{ display: flex; align-items: center; gap: 5px; }}
  .dot {{ width: 12px; height: 12px; border-radius: 50%; display: inline-block; }}
  .dot-pass {{ background: #3fb950; }}
  .dot-fail {{ background: #f85149; }}
  .dot-gold {{ background: #ffd700; }}
  .dot-best {{ background: #58a6ff; }}
  .section {{ margin-bottom: 40px; }}
</style>
</head>
<body>
<h1>FlashEASuite V2 - Optimization Report</h1>
<div class="timestamp">Generated: {now} | Optuna 200 trials | 5y data (2021-2026) | Walk-Forward | {DISPLAY_CURRENCY} (1 USD = {USD_TO_THB:.0f} {DISPLAY_CURRENCY}) | Equity: {DISPLAY_SYMBOL}{to_display(10000):,.0f}</div>
"""

    # ========== SECTION 1: Overview Matrix ==========
    html += '<div class="section"><h2>1. Walk-Forward Results Matrix</h2>'
    html += '<div class="legend">'
    html += '<span><div class="dot dot-pass"></div> WF PASS</span>'
    html += '<span><div class="dot dot-fail"></div> WF FAIL</span>'
    html += '<span><div class="dot dot-gold"></div> Global Best</span>'
    html += '<span><div class="dot dot-best"></div> Best in Strategy</span>'
    html += '</div>'
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
                    ppy = c.get("profit_per_year", c.get("profit", 0) / 5)
                    ppy_thb = to_display(ppy)
                    arp = c.get("annual_return_pct", ppy / 100)

                    is_global_best = global_best_key == (strat_name, sym, tf)
                    is_strat_best = best_pass_per_strat.get(strat_name) == (sym, tf)

                    if is_global_best:
                        bg = "gold"
                    elif is_strat_best:
                        bg = "strat-best"
                    elif wf == "PASS":
                        bg = "heatmap-good"
                    elif pf < 1.0 or ppy < 0:
                        bg = "heatmap-bad"
                    else:
                        bg = "heatmap-neutral"

                    cls = "pass" if wf == "PASS" else "fail"
                    pf_str = f"{pf:.1f}" if pf < 100 else "999"

                    if ppy < 0:
                        money_str = f'<span class="negative">{DISPLAY_SYMBOL}{ppy_thb:,.0f}/yr</span>'
                    else:
                        money_str = f'{DISPLAY_SYMBOL}{ppy_thb:,.0f}/yr'

                    html += f'<td class="{bg}"><span class="{cls}">{wf}</span><br>PF={pf_str}<br>{money_str} ({arp:.0f}%)</td>'
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

        strat_best_sym_tf = best_pass_per_strat.get(strat_name)

        html += f'<table><tr><th>Symbol</th><th>TF</th><th>PF</th><th>WR%</th><th>DD%</th><th>Trades</th><th>{DISPLAY_SYMBOL}/yr</th><th>%/yr</th><th>Score</th><th>WF</th><th>WF PF</th></tr>'
        for c in sorted(combos, key=lambda x: (x["symbol"], x["tf"])):
            wf = c.get("wf_status", "N/A")
            ppy = c.get("profit_per_year", c.get("profit", 0) / 5)
            ppy_thb = to_display(ppy)
            arp = c.get("annual_return_pct", ppy / 100)
            pf_str = f'{c["pf"]:.2f}' if c["pf"] < 100 else "999"

            is_global_best = global_best_key == (strat_name, c["symbol"], c["tf"])
            is_strat_best = strat_best_sym_tf == (c["symbol"], c["tf"])

            if is_global_best:
                row_cls = "gold"
            elif is_strat_best:
                row_cls = "strat-best"
            else:
                row_cls = ""

            cls = "pass" if wf == "PASS" else "fail"

            if ppy < 0:
                money_td = f'<td class="negative">{DISPLAY_SYMBOL}{ppy_thb:,.0f}</td>'
                ret_td = f'<td class="negative">{arp:.1f}%</td>'
            else:
                money_td = f'<td>{DISPLAY_SYMBOL}{ppy_thb:,.0f}</td>'
                ret_td = f'<td>{arp:.1f}%</td>'

            html += f'<tr class="{row_cls}"><td>{c["symbol"]}</td><td>{c["tf"]}</td>'
            html += f'<td>{pf_str}</td><td>{c["wr"]:.1f}</td><td>{c["dd"]:.1f}</td>'
            html += f'<td>{c["trades"]}</td>{money_td}{ret_td}'
            html += f'<td>{c["score"]:.2f}</td>'
            html += f'<td class="{cls}">{wf}</td>'
            html += f'<td>{c.get("wf_avg_pf", 0):.2f}</td></tr>'
        html += '</table>'

        # Parameters table (only for WF PASS combos)
        pass_combos = [c for c in combos if c.get("wf_status") == "PASS"]
        if pass_combos:
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
                    is_gb = global_best_key == (strat_name, c["symbol"], c["tf"])
                    is_sb = strat_best_sym_tf == (c["symbol"], c["tf"])
                    rc = "gold" if is_gb else ("strat-best" if is_sb else "")
                    html += f'<tr class="{rc}"><td>{c["symbol"]}</td><td>{c["tf"]}</td>'
                    for k in all_keys:
                        val = c.get("params", {}).get(k, "")
                        if isinstance(val, float):
                            html += f'<td>{val:.4f}</td>' if val != int(val) else f'<td>{int(val)}</td>'
                        else:
                            html += f'<td>{val}</td>'
                    html += '</tr>'
                html += '</table>'

    html += '</div>'

    # ========== SECTION 3: Summary ==========
    total_combos = len(data)
    total_pass = sum(1 for v in data.values() if v.get("wf_status") == "PASS")

    # Best combo
    if all_pass:
        best_combo = max(all_pass, key=lambda x: x.get("profit_per_year", 0))
        bc_ppy_thb = to_display(best_combo.get("profit_per_year", 0))
    else:
        best_combo = {"strategy": "-", "symbol": "-", "tf": "-", "pf": 0, "score": 0}
        bc_ppy_thb = 0

    html += f"""
<div class="section"><h2>3. Summary</h2>
<div class="summary">
<p><b>Total combinations tested:</b> {total_combos} (7 strategies x 3 symbols x 2 TFs)</p>
<p><b>Walk-Forward PASS:</b> {total_pass}/{total_combos} ({total_pass/total_combos*100:.0f}%)</p>
<p><b>Global Best:</b> {best_combo['strategy']} {best_combo['symbol']} {best_combo['tf']} (PF={best_combo['pf']:.2f}, {DISPLAY_SYMBOL}{bc_ppy_thb:,.0f}/yr)</p>
<p><b>Strategies ready for deployment:</b></p>
<ul style="margin-left:20px;margin-top:5px">"""

    for strat_name, combos in sorted(strategies.items()):
        pass_combos = [c for c in combos if c.get("wf_status") == "PASS"]
        if pass_combos:
            parts = []
            for c in pass_combos:
                ppy_thb = to_display(c.get("profit_per_year", 0))
                sym_short = c["symbol"].replace(".tp", "")
                parts.append(f'{sym_short} {c["tf"]} ({DISPLAY_SYMBOL}{ppy_thb:,.0f}/yr)')
            html += f'<li><b>{strat_name}</b>: {", ".join(parts)}</li>'

    html += """</ul>
</div></div>
</body></html>"""

    html_path = OUTPUT_DIR / "optimization_report.html"
    html_path.write_text(html, encoding="utf-8")
    print(f"Report saved: {html_path}")
    print(f"Total combos: {total_combos} | WF PASS: {total_pass}")


if __name__ == "__main__":
    generate_html()
