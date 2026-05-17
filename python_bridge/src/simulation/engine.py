"""Monte Carlo simulation engine for game outcome prediction.

Ported from sports-fan-agent simulation engine.
"""

import logging
from dataclasses import dataclass

import numpy as np
from fastapi import APIRouter
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()

RNG = np.random.default_rng()


class SimulationPlayer(BaseModel):
    player_id: str
    player_name: str
    hit_probability: float
    hr_probability: float = 0.0


class SimulationRequest(BaseModel):
    players: list[SimulationPlayer]
    n_simulations: int = 10000


class SimulationResult(BaseModel):
    player_id: str
    player_name: str
    hit_rate: float
    multi_hit_rate: float
    hr_rate: float
    expected_hits: float
    rank: int
    percentile: float


@dataclass
class MonteCarloSimulation:
    """Vectorized Monte Carlo simulation for hit/HR outcomes."""

    n_simulations: int = 10000

    def simulate_player(
        self, hit_prob: float, hr_prob: float, at_bats: int = 4
    ) -> dict:
        """Run simulation for a single player across all simulations."""
        hit_prob = np.clip(hit_prob, 0.0, 1.0)
        hr_prob = np.clip(hr_prob, 0.0, 1.0)

        hits = RNG.binomial(at_bats, hit_prob, size=self.n_simulations)
        hrs = RNG.binomial(at_bats, hr_prob, size=self.n_simulations)

        return {
            "hit_rate": float(np.mean(hits >= 1)),
            "multi_hit_rate": float(np.mean(hits >= 2)),
            "hr_rate": float(np.mean(hrs >= 1)),
            "expected_hits": float(np.mean(hits)),
        }

    def simulate_batch(self, players: list[SimulationPlayer]) -> list[dict]:
        """Run simulation for all players and rank them."""
        results = []

        for player in players:
            sim = self.simulate_player(player.hit_probability, player.hr_probability)
            results.append(
                {
                    "player_id": player.player_id,
                    "player_name": player.player_name,
                    **sim,
                }
            )

        results.sort(key=lambda x: x["hit_rate"], reverse=True)
        n = len(results)
        for i, r in enumerate(results):
            r["rank"] = i + 1
            r["percentile"] = float((n - i) / n) if n > 0 else 0.0

        return results


@router.post("/run")
async def run_simulation(request: SimulationRequest):
    """Run Monte Carlo simulation for a set of players."""
    if not request.players:
        return {"results": [], "metadata": {"n_simulations": request.n_simulations}}

    n_sims = min(max(request.n_simulations, 1000), 100000)
    engine = MonteCarloSimulation(n_simulations=n_sims)
    results = engine.simulate_batch(request.players)

    return {
        "results": results,
        "metadata": {
            "n_simulations": n_sims,
            "n_players": len(request.players),
        },
    }
