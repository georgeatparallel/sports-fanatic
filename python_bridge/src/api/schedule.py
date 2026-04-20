"""MLB Schedule API endpoint using statsapi library."""

import logging
from datetime import date, datetime

import statsapi
from fastapi import APIRouter

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/fetch")
async def fetch_schedule(request: dict):
    """Fetch MLB schedule for a given date."""
    date_str = request.get("date", date.today().isoformat())

    try:
        # statsapi expects MM/DD/YYYY format
        d = datetime.strptime(date_str, "%Y-%m-%d")
        formatted = d.strftime("%m/%d/%Y")
    except ValueError:
        formatted = date_str

    logger.info(f"Fetching schedule for {date_str}")
    raw = statsapi.schedule(start_date=formatted, end_date=formatted)

    games = []
    for g in raw:
        games.append({
            "game_id": g["game_id"],
            "game_date": g.get("game_date", date_str),
            "game_datetime": g.get("game_datetime"),
            "away_mlb_id": g.get("away_id"),
            "home_mlb_id": g.get("home_id"),
            "away_name": g.get("away_name"),
            "home_name": g.get("home_name"),
            "away_probable_pitcher": g.get("away_probable_pitcher"),
            "home_probable_pitcher": g.get("home_probable_pitcher"),
            "venue_id": g.get("venue_id"),
            "venue_name": g.get("venue_name"),
            "status": g.get("status"),
        })

    logger.info(f"Found {len(games)} games for {date_str}")
    return {"games": games}


@router.post("/teams")
async def fetch_teams(request: dict = {}):
    """Fetch all MLB teams."""
    data = statsapi.get("teams", {"sportIds": 1})
    teams = data.get("teams", [])

    result = []
    for t in teams:
        result.append({
            "mlb_id": t["id"],
            "name": t.get("teamName", ""),
            "city": t.get("locationName", ""),
            "abbreviation": t.get("abbreviation", ""),
            "league": t.get("league", {}).get("name", ""),
            "division": t.get("division", {}).get("name", ""),
        })

    return {"teams": result}


@router.post("/roster")
async def fetch_roster(request: dict):
    """Fetch roster for a team by MLB team ID."""
    team_id = request.get("team_id")
    if not team_id:
        return {"players": []}

    try:
        raw = statsapi.roster(team_id, rosterType="40Man")
    except Exception as e:
        logger.error(f"Failed to fetch roster for team {team_id}: {e}")
        return {"players": []}

    players = []
    for line in raw.strip().split("\n"):
        # statsapi.roster returns formatted text, we need the API directly
        pass

    # Use the JSON API instead
    try:
        data = statsapi.get("team_roster", {"teamId": team_id, "rosterType": "fullRoster"})
        for entry in data.get("roster", []):
            person = entry.get("person", {})
            position = entry.get("position", {})
            players.append({
                "mlb_id": person.get("id"),
                "full_name": person.get("fullName", ""),
                "first_name": person.get("firstName", ""),
                "last_name": person.get("lastName", ""),
                "jersey_number": entry.get("jerseyNumber", ""),
                "position": position.get("abbreviation", ""),
                "status": entry.get("status", {}).get("description", "Active"),
            })
    except Exception as e:
        logger.error(f"Failed to fetch full roster for team {team_id}: {e}")

    return {"players": players}
