"""MLB schedule endpoints.

Wraps the MLB Stats API (statsapi.mlb.com) to fetch daily schedules,
team lists, and rosters.
"""

import logging
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

logger = logging.getLogger(__name__)
router = APIRouter()

MLB_STATS_BASE = "https://statsapi.mlb.com/api/v1"


class FetchScheduleRequest(BaseModel):
    date: str  # ISO 8601 date string, e.g. "2026-05-01"


class FetchTeamsRequest(BaseModel):
    pass


class FetchRosterRequest(BaseModel):
    team_id: int


@router.post("/fetch")
async def fetch_schedule(request: FetchScheduleRequest) -> dict[str, Any]:
    """Fetch MLB schedule for a given date."""
    url = f"{MLB_STATS_BASE}/schedule"
    params = {
        "date": request.date,
        "sportId": 1,  # MLB
        "hydrate": "probablePitcher,venue",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            logger.error(f"MLB Stats API error: {e.response.status_code}")
            raise HTTPException(
                status_code=502,
                detail=f"MLB Stats API returned {e.response.status_code}",
            ) from e
        except httpx.RequestError as e:
            logger.error(f"MLB Stats API request failed: {e}")
            raise HTTPException(
                status_code=502,
                detail="Failed to connect to MLB Stats API",
            ) from e

    data = response.json()
    games = []

    for date_entry in data.get("dates", []):
        for game in date_entry.get("games", []):
            away = game.get("teams", {}).get("away", {}).get("team", {})
            home = game.get("teams", {}).get("home", {}).get("team", {})
            venue = game.get("venue", {})

            away_pitcher = (
                game.get("teams", {}).get("away", {}).get("probablePitcher", {}).get("fullName")
            )
            home_pitcher = (
                game.get("teams", {}).get("home", {}).get("probablePitcher", {}).get("fullName")
            )

            games.append(
                {
                    "game_id": game.get("gamePk"),
                    "game_date": request.date,
                    "game_datetime": game.get("gameDate"),
                    "away_mlb_id": away.get("id"),
                    "home_mlb_id": home.get("id"),
                    "away_name": away.get("name"),
                    "home_name": home.get("name"),
                    "away_probable_pitcher": away_pitcher,
                    "home_probable_pitcher": home_pitcher,
                    "venue_id": venue.get("id"),
                    "venue_name": venue.get("name"),
                }
            )

    logger.info(f"Fetched {len(games)} games for {request.date}")
    return {"games": games}


@router.post("/teams")
async def fetch_teams(_request: FetchTeamsRequest) -> dict[str, Any]:
    """Fetch all MLB teams."""
    url = f"{MLB_STATS_BASE}/teams"
    params = {"sportId": 1}

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(
                status_code=502,
                detail=f"MLB Stats API returned {e.response.status_code}",
            ) from e
        except httpx.RequestError as e:
            raise HTTPException(
                status_code=502,
                detail="Failed to connect to MLB Stats API",
            ) from e

    data = response.json()
    teams = []

    for team in data.get("teams", []):
        teams.append(
            {
                "mlb_id": team.get("id"),
                "name": team.get("name"),
                "abbreviation": team.get("abbreviation"),
                "league": team.get("league", {}).get("name"),
                "division": team.get("division", {}).get("name"),
                "venue_id": team.get("venue", {}).get("id"),
                "venue_name": team.get("venue", {}).get("name"),
            }
        )

    return {"teams": teams}


@router.post("/roster")
async def fetch_roster(request: FetchRosterRequest) -> dict[str, Any]:
    """Fetch active roster for a team."""
    url = f"{MLB_STATS_BASE}/teams/{request.team_id}/roster"
    params = {"rosterType": "active"}

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            response = await client.get(url, params=params)
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            raise HTTPException(
                status_code=502,
                detail=f"MLB Stats API returned {e.response.status_code}",
            ) from e
        except httpx.RequestError as e:
            raise HTTPException(
                status_code=502,
                detail="Failed to connect to MLB Stats API",
            ) from e

    data = response.json()
    players = []

    for entry in data.get("roster", []):
        person = entry.get("person", {})
        position = entry.get("position", {})
        players.append(
            {
                "mlb_id": person.get("id"),
                "full_name": person.get("fullName"),
                "jersey_number": entry.get("jerseyNumber"),
                "position": position.get("abbreviation"),
                "status": entry.get("status", {}).get("description"),
            }
        )

    return {"roster": players}
