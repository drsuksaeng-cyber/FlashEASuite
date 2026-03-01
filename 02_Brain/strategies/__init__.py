"""
strategies/__init__.py
FlashEASuite V2 | 02_Brain/strategies/

Exports all 16 strategy analyzers + convenience registry.
Usage:
    from strategies import ANALYZER_REGISTRY
    analyzer = ANALYZER_REGISTRY["S07"]
    result   = analyzer.analyze(symbol, regime, indicators)
"""

from .base_analyzer              import BaseAnalyzer, AnalysisResult

# ── 3 Hybrid analyzers ────────────────────────────────────────────────
from .s01_stat_arb_analyzer      import S01StatArbAnalyzer
from .s02_ml_ensemble_analyzer   import S02MlEnsembleAnalyzer
from .s08_intermarket_analyzer   import S08IntermarketAnalyzer

# ── 13 Simple analyzers ───────────────────────────────────────────────
from .s03_smc_analyzer           import S03SmcAnalyzer
from .s04_market_profile_analyzer import S04MarketProfileAnalyzer
from .s05_supply_demand_analyzer  import S05SupplyDemandAnalyzer
from .s06_kama_analyzer           import S06KamaAnalyzer
from .s07_mean_reversion_analyzer import S07MeanReversionAnalyzer
from .s09_session_breakout_analyzer import S09SessionBreakoutAnalyzer
from .s10_turtle_analyzer         import S10TurtleAnalyzer
from .s11_ichimoku_analyzer       import S11IchimokuAnalyzer
from .s12_price_action_analyzer   import S12PriceActionAnalyzer
from .s13_fib_stoch_analyzer      import S13FibStochAnalyzer
from .s14_bb_squeeze_analyzer     import S14BbSqueezeAnalyzer
from .s15_grid_analyzer           import S15GridAnalyzer
from .s16_spike_analyzer          import S16SpikeAnalyzer

# ── Registry: ID → instance ───────────────────────────────────────────
ANALYZER_REGISTRY: dict = {
    "S01": S01StatArbAnalyzer(),
    "S02": S02MlEnsembleAnalyzer(),
    "S03": S03SmcAnalyzer(),
    "S04": S04MarketProfileAnalyzer(),
    "S05": S05SupplyDemandAnalyzer(),
    "S06": S06KamaAnalyzer(),
    "S07": S07MeanReversionAnalyzer(),
    "S08": S08IntermarketAnalyzer(),
    "S09": S09SessionBreakoutAnalyzer(),
    "S10": S10TurtleAnalyzer(),
    "S11": S11IchimokuAnalyzer(),
    "S12": S12PriceActionAnalyzer(),
    "S13": S13FibStochAnalyzer(),
    "S14": S14BbSqueezeAnalyzer(),
    "S15": S15GridAnalyzer(),
    "S16": S16SpikeAnalyzer(),
}

__all__ = [
    "BaseAnalyzer",
    "AnalysisResult",
    "ANALYZER_REGISTRY",
    "S01StatArbAnalyzer", "S02MlEnsembleAnalyzer", "S03SmcAnalyzer",
    "S04MarketProfileAnalyzer", "S05SupplyDemandAnalyzer", "S06KamaAnalyzer",
    "S07MeanReversionAnalyzer", "S08IntermarketAnalyzer", "S09SessionBreakoutAnalyzer",
    "S10TurtleAnalyzer", "S11IchimokuAnalyzer", "S12PriceActionAnalyzer",
    "S13FibStochAnalyzer", "S14BbSqueezeAnalyzer", "S15GridAnalyzer", "S16SpikeAnalyzer",
]
