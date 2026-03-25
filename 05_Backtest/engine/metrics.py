"""
Performance Metrics — matches MT5 Strategy Tester statistics.
"""
from dataclasses import dataclass, field
import numpy as np


@dataclass
class BacktestResult:
    trades: list = field(default_factory=list)
    initial_equity: float = 10000.0

    @property
    def total_trades(self) -> int:
        return len(self.trades)

    @property
    def net_profit(self) -> float:
        return sum(t["pnl"] for t in self.trades)

    @property
    def gross_profit(self) -> float:
        return sum(t["pnl"] for t in self.trades if t["pnl"] > 0)

    @property
    def gross_loss(self) -> float:
        return sum(t["pnl"] for t in self.trades if t["pnl"] < 0)

    @property
    def profit_factor(self) -> float:
        gl = abs(self.gross_loss)
        return self.gross_profit / gl if gl > 0 else 999.0

    @property
    def win_rate(self) -> float:
        if self.total_trades == 0:
            return 0.0
        wins = sum(1 for t in self.trades if t["pnl"] > 0)
        return wins / self.total_trades

    @property
    def total_spread_cost(self) -> float:
        return sum(t.get("spread_cost", 0) for t in self.trades)

    @property
    def avg_trade(self) -> float:
        return self.net_profit / self.total_trades if self.total_trades > 0 else 0.0

    @property
    def max_drawdown_pct(self) -> float:
        if not self.trades:
            return 0.0
        equity = self.initial_equity
        peak = equity
        max_dd = 0.0
        for t in self.trades:
            equity += t["pnl"]
            peak = max(peak, equity)
            dd = (peak - equity) / peak * 100 if peak > 0 else 0.0
            max_dd = max(max_dd, dd)
        return max_dd

    @property
    def sharpe_ratio(self) -> float:
        if self.total_trades < 2:
            return 0.0
        returns = [t["pnl"] for t in self.trades]
        avg = np.mean(returns)
        std = np.std(returns, ddof=1)
        if std < 1e-10:
            return 0.0
        # Annualize: assume ~250 trading days / avg trades per year
        return (avg / std) * np.sqrt(min(self.total_trades, 250))

    @property
    def rr_ratio(self) -> float:
        wins = [t["pnl"] for t in self.trades if t["pnl"] > 0]
        losses = [abs(t["pnl"]) for t in self.trades if t["pnl"] < 0]
        avg_win = np.mean(wins) if wins else 0.0
        avg_loss = np.mean(losses) if losses else 1.0
        return avg_win / avg_loss if avg_loss > 0 else 999.0

    @property
    def max_consecutive_losses(self) -> int:
        max_streak = 0
        streak = 0
        for t in self.trades:
            if t["pnl"] < 0:
                streak += 1
                max_streak = max(max_streak, streak)
            else:
                streak = 0
        return max_streak

    def score(self) -> float:
        """Composite score matching MT5 OnTester criterion."""
        if self.total_trades < 15:
            return 0.0
        if self.net_profit <= 0:
            return 0.0
        if self.profit_factor < 1.0:
            return 0.0
        if self.max_drawdown_pct > 30.0:
            return 0.0

        s = (self.profit_factor * self.win_rate *
             np.sqrt(self.total_trades) / max(self.max_drawdown_pct, 1.0))

        if self.rr_ratio > 3.0:
            s *= 1.0 + (self.rr_ratio - 3.0) * 0.10
        if self.sharpe_ratio > 1.0:
            s *= 1.0 + (self.sharpe_ratio - 1.0) * 0.1

        return s

    def profit_per_year(self, years: float = 5.0) -> float:
        """Annualized profit. Default assumes 5-year backtest period."""
        return self.net_profit / years if years > 0 else 0.0

    def annual_return_pct(self, years: float = 5.0) -> float:
        """Annualized return % on initial equity."""
        return (self.profit_per_year(years) / self.initial_equity) * 100 if self.initial_equity > 0 else 0.0

    def summary(self, years: float = 5.0) -> dict:
        return {
            "trades": self.total_trades,
            "profit": round(self.net_profit, 2),
            "PF": round(self.profit_factor, 2),
            "WR%": round(self.win_rate * 100, 1),
            "DD%": round(self.max_drawdown_pct, 2),
            "Sharpe": round(self.sharpe_ratio, 2),
            "RR": round(self.rr_ratio, 2),
            "Score": round(self.score(), 4),
            "$/yr": round(self.profit_per_year(years), 2),
            "%/yr": round(self.annual_return_pct(years), 1),
        }
