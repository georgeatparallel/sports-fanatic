"""ML inference endpoint for the Elixir-native hit predictions pipeline.

This is the *only* ML endpoint the Python bridge exposes to Elixir. Feature
engineering and persistence live entirely in Elixir; the bridge only:

  1. Receives training_rows + inference_rows (already-built feature dicts).
  2. Fits a GradientBoostingClassifier on the training rows.
  3. Predicts hit probabilities for the inference rows.
  4. Returns the predictions + model metadata.

Payload size cap: 25 MB (FastAPI's default).
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

import numpy as np
import pandas as pd
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import brier_score_loss, roc_auc_score
from sklearn.pipeline import Pipeline as SklearnPipeline
from sklearn.preprocessing import StandardScaler

logger = logging.getLogger(__name__)
router = APIRouter()


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


class InferenceRequest(BaseModel):
    training_rows: list[dict[str, Any]] = Field(default_factory=list)
    inference_rows: list[dict[str, Any]] = Field(default_factory=list)


class PredictionEntry(BaseModel):
    player_mlb_id: int | None = None
    hit_prob: float
    prediction: str


class InferenceResponse(BaseModel):
    model_version: str
    training_metrics: dict[str, float | int]
    predictions: list[PredictionEntry]


def _build_model() -> SklearnPipeline:
    """Mirror of sports-fan-agent steps/predict.py model."""
    preprocessor = SklearnPipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )

    gbt = GradientBoostingClassifier(
        n_estimators=150,
        max_depth=3,
        learning_rate=0.05,
        subsample=0.8,
        min_samples_leaf=30,
        random_state=42,
    )

    return SklearnPipeline([("preprocessor", preprocessor), ("classifier", gbt)])


@router.post("/hit", response_model=InferenceResponse)
async def infer_hit(req: InferenceRequest) -> InferenceResponse:
    if not req.training_rows:
        raise HTTPException(status_code=400, detail="training_rows empty")

    if not req.inference_rows:
        return InferenceResponse(
            model_version=_version_string(),
            training_metrics={"samples": 0},
            predictions=[],
        )

    train_df = pd.DataFrame(req.training_rows)
    infer_df = pd.DataFrame(req.inference_rows)

    if "target_hit" not in train_df.columns:
        raise HTTPException(status_code=400, detail="training_rows missing target_hit")

    feature_cols = [c for c in HIT_FEATURE_COLS if c in train_df.columns]
    if not feature_cols:
        raise HTTPException(
            status_code=400, detail="training_rows missing all expected feature columns"
        )

    X_train = train_df[feature_cols].apply(pd.to_numeric, errors="coerce")
    y_train = train_df["target_hit"].astype(int)

    if len(X_train) < 50:
        logger.warning("Tiny training set (%d rows) — predictions may be unreliable", len(X_train))

    model = _build_model()
    model.fit(X_train, y_train)
    logger.info("Hit model fit on %d rows × %d features", len(X_train), len(feature_cols))

    # Diagnostic metrics on training data (in-sample — not a substitute for CV).
    train_probs = model.predict_proba(X_train)[:, 1]
    try:
        auc = float(roc_auc_score(y_train, train_probs))
    except ValueError:
        auc = float("nan")
    brier = float(brier_score_loss(y_train, train_probs))

    # Inference
    for c in feature_cols:
        if c not in infer_df.columns:
            infer_df[c] = np.nan
    X_inf = infer_df[feature_cols].apply(pd.to_numeric, errors="coerce")

    probs = model.predict_proba(X_inf)[:, 1]

    predictions: list[PredictionEntry] = []
    for prob, row in zip(probs.tolist(), req.inference_rows):
        predictions.append(
            PredictionEntry(
                player_mlb_id=_safe_int(row.get("player_mlb_id")),
                hit_prob=float(prob),
                prediction="Hit" if prob >= 0.5 else "No Hit",
            )
        )

    return InferenceResponse(
        model_version=_version_string(),
        training_metrics={
            "samples": int(len(X_train)),
            "features": int(len(feature_cols)),
            "roc_auc": float(auc) if not _isnan(auc) else 0.0,
            "brier": brier,
        },
        predictions=predictions,
    )


def _version_string() -> str:
    return f"gbt-{datetime.utcnow().strftime('%Y%m%d')}"


def _safe_int(v: Any) -> int | None:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _isnan(v: Any) -> bool:
    try:
        return v != v  # NaN is the only value not equal to itself
    except Exception:
        return False
