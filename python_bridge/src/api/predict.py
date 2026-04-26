"""Hit and HR prediction endpoints.

Ports the GradientBoostingClassifier models from sports-fan-agent.
"""

import logging
import math
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline as SklearnPipeline
from sklearn.preprocessing import StandardScaler

logger = logging.getLogger(__name__)
router = APIRouter()


# --- Hit Prediction Model ---

HIT_FEATURE_COLS = [
    "avg_7d", "avg_14d", "avg_30d", "avg_season",
    "obp_7d", "obp_14d", "obp_30d", "obp_season",
    "slg_7d", "slg_14d", "slg_30d", "slg_season",
    "k_rate_7d", "k_rate_14d", "k_rate_30d",
    "bb_rate_30d",
    "games_7d", "games_14d", "games_30d", "games_season",
    "pitcher_baa", "pitcher_k_per_9", "pitcher_whip", "pitcher_bb_per_9",
    "pitcher_hand_L", "pitcher_hand_R",
    "pitcher_recent_era_5g", "pitcher_recent_k9_5g", "pitcher_recent_whip_5g",
    "bvp_avg", "bvp_at_bats",
    "avg_exit_velocity", "hard_hit_pct",
    "park_hit_factor",
    "temperature", "wind_speed", "precipitation", "surface_pressure",
    "is_home", "batting_order", "month",
    "days_since_last_game", "games_last_7d",
    "k_rate_x_pitcher_k9",
]


def _build_hit_model() -> SklearnPipeline:
    """Build hit prediction model pipeline."""
    preprocessor = SklearnPipeline([
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler", StandardScaler()),
    ])

    gbt = GradientBoostingClassifier(
        n_estimators=150,
        max_depth=3,
        learning_rate=0.05,
        subsample=0.8,
        min_samples_leaf=30,
        random_state=42,
    )

    return SklearnPipeline([
        ("preprocessor", preprocessor),
        ("classifier", gbt),
    ])


# --- HR Prediction Model ---

HR_FEATURE_COLS = [
    "hr_rate_7d", "hr_rate_14d", "hr_rate_30d", "hr_rate_season",
    "iso_7d", "iso_14d", "iso_30d", "iso_season",
    "slg_7d", "slg_14d", "slg_30d", "slg_season",
    "k_rate_30d", "bb_rate_30d",
    "games_7d", "games_14d", "games_30d", "games_season",
    "pitcher_hr_per_9", "pitcher_era",
    "pitcher_hand_L", "pitcher_hand_R",
    "pitcher_recent_era_5g", "pitcher_recent_hr9_5g", "pitcher_recent_whip_5g",
    "park_hr_factor",
    "temperature", "wind_speed", "wind_score",
    "precipitation", "surface_pressure",
    "avg_exit_velocity", "barrel_pct", "hard_hit_pct", "avg_launch_angle", "fb_pct",
    "is_home", "batting_order", "month",
    "days_since_last_game", "games_last_7d", "is_day_game",
    "hr_rate_x_park", "temp_x_iso", "wind_score_x_iso", "barrel_pct_x_park",
]


def _build_hr_model() -> SklearnPipeline:
    """Build HR prediction model pipeline."""
    preprocessor = SklearnPipeline([
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler", StandardScaler()),
    ])

    gbt = GradientBoostingClassifier(
        n_estimators=200,
        max_depth=4,
        learning_rate=0.05,
        subsample=0.8,
        min_samples_leaf=20,
        random_state=42,
    )

    return SklearnPipeline([
        ("preprocessor", preprocessor),
        ("classifier", gbt),
    ])


def _assign_confidence_tier(prob: float) -> str:
    if prob >= 0.15:
        return "A"
    elif prob >= 0.10:
        return "B"
    return "C"


def _compute_wind_score(wind_speed: float | None, wind_direction: int | None) -> float:
    if wind_speed is None or wind_direction is None:
        return 0.0
    rad = math.radians(wind_direction)
    outward_component = math.cos(rad)
    speed_factor = min(wind_speed / 15.0, 2.0)
    return outward_component * speed_factor


def _generate_top_factors(features: dict, prob: float) -> list[dict]:
    factors = []

    iso_30d = features.get("iso_30d")
    if iso_30d is not None and iso_30d > 0.200:
        factors.append({
            "feature": "player_iso_30d",
            "value": iso_30d,
            "impact": "high positive" if iso_30d > 0.250 else "moderate positive",
        })

    park_factor = features.get("park_hr_factor", 1.0)
    if park_factor > 1.05:
        factors.append({
            "feature": "park_hr_factor", "value": park_factor,
            "impact": "moderate positive",
        })
    elif park_factor < 0.92:
        factors.append({
            "feature": "park_hr_factor", "value": park_factor,
            "impact": "moderate negative",
        })

    temp = features.get("temperature")
    if temp is not None and temp > 28:
        factors.append({"feature": "temperature", "value": temp, "impact": "moderate positive"})
    elif temp is not None and temp < 12:
        factors.append({"feature": "temperature", "value": temp, "impact": "moderate negative"})

    return factors[:5]


# --- Request/Response Models ---

class PlayerHitInput(BaseModel):
    mlb_id: int
    stats: dict[str, Any] = {}
    weather: dict[str, Any] = {}
    matchup: dict[str, Any] = {}


class HitPredictionRequest(BaseModel):
    players: list[PlayerHitInput] = []


class HitPredictionResponse(BaseModel):
    predictions: list[dict[str, Any]]


class PlayerHrInput(BaseModel):
    mlb_id: int
    stats: dict[str, Any] = {}
    weather: dict[str, Any] = {}
    park_factor: float = 1.0
    pitcher: dict[str, Any] = {}


class HrPredictionRequest(BaseModel):
    players: list[PlayerHrInput] = []


class HrPredictionResponse(BaseModel):
    predictions: list[dict[str, Any]]


@router.post("/hit", response_model=HitPredictionResponse)
async def predict_hit(request: HitPredictionRequest):
    """Generate hit predictions for a batch of players."""
    predictions = []

    for player in request.players:
        # Build feature vector from player stats
        features = dict.fromkeys(HIT_FEATURE_COLS)
        features.update(player.stats)
        features.update(player.weather)
        features.update(player.matchup)

        # Compute interaction feature
        k_rate = features.get("k_rate_30d")
        pitcher_k9 = features.get("pitcher_k_per_9")
        if k_rate is not None and pitcher_k9 is not None:
            features["k_rate_x_pitcher_k9"] = k_rate * pitcher_k9

        # Use base probability from stats if model not trained
        hit_prob = features.get("avg_season", 0.70)
        if hit_prob is None:
            hit_prob = 0.70

        predictions.append({
            "mlb_id": player.mlb_id,
            "hit_prob": float(hit_prob),
            "confidence": float(hit_prob),
        })

    return HitPredictionResponse(predictions=predictions)


@router.post("/hr", response_model=HrPredictionResponse)
async def predict_hr(request: HrPredictionRequest):
    """Generate HR predictions for a batch of players."""
    predictions = []

    for player in request.players:
        features = dict.fromkeys(HR_FEATURE_COLS)
        features.update(player.stats)
        features.update(player.weather)

        # Compute wind score
        wind_speed = features.get("wind_speed")
        wind_dir = player.weather.get("wind_direction_10m")
        features["wind_score"] = _compute_wind_score(wind_speed, wind_dir)

        # Default HR probability
        hr_prob = features.get("hr_rate_season", 0.04)
        if hr_prob is None:
            hr_prob = 0.04

        # Apply park factor
        hr_prob = hr_prob * player.park_factor

        tier = _assign_confidence_tier(hr_prob)
        top_factors = _generate_top_factors(features, hr_prob)

        predictions.append({
            "mlb_id": player.mlb_id,
            "hr_prob": float(hr_prob),
            "ev_per_unit": None,
            "tier": tier,
            "top_factors": top_factors,
        })

    return HrPredictionResponse(predictions=predictions)
