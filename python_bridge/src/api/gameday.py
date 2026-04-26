"""Game Day Magazine generation: Claude-based editorial content."""

import json
import logging

from fastapi import APIRouter
from pydantic import BaseModel

from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


class GameDayRequest(BaseModel):
    game_date: str
    away_team: str
    home_team: str
    away_lineup: list[dict] = []
    home_lineup: list[dict] = []
    venue: str = ""
    weather: dict | None = None
    picks: list[dict] = []
    hr_picks: list[dict] = []


@router.post("/generate")
async def generate_game_day(request: GameDayRequest):
    """Generate a Game Day Magazine using Claude."""
    if not settings.anthropic_api_key:
        return {"magazine": _empty_magazine(request)}

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        context = _build_context(request)

        message = await client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4000,
            messages=[
                {
                    "role": "user",
                    "content": (
                        "You are a baseball magazine editor creating a "
                        "Game Day Magazine preview.\n"
                        "Write an engaging, data-driven preview for "
                        "today's game.\n\n"
                        f"Game Context:\n{context}\n\n"
                        "Return a JSON object with these fields:\n"
                        "- headline: catchy headline for the matchup (string)\n"
                        "- subheadline: supporting detail (string)\n"
                        "- narrative: 3-4 paragraph editorial narrative about "
                        "the matchup (string, use \\n for paragraph breaks)\n"
                        "- key_matchups: array of 3 key player matchups, each "
                        'with "title" and "analysis" (strings)\n'
                        "- predictions_narrative: 1-2 paragraph analysis of "
                        "our model predictions (string)\n"
                        "- weather_impact: one sentence about weather impact "
                        "on the game or null\n"
                        "- fan_meter: excitement rating 1-10 (integer)\n"
                        "- tags: array of 3-5 tags for SEO (strings)\n\n"
                        "Return ONLY valid JSON, no other text."
                    ),
                }
            ],
        )

        response_text = message.content[0].text.strip()
        if response_text.startswith("```"):
            response_text = response_text.split("```")[1]
            if response_text.startswith("json"):
                response_text = response_text[4:]

        magazine = json.loads(response_text)
        return {"magazine": magazine}

    except Exception as e:
        logger.warning("Game Day generation failed: %s", e)
        return {"magazine": _empty_magazine(request)}


def _build_context(request: GameDayRequest) -> str:
    """Build context string for Claude from request data."""
    lines = [
        f"Date: {request.game_date}",
        f"Matchup: {request.away_team} at {request.home_team}",
    ]

    if request.venue:
        lines.append(f"Venue: {request.venue}")

    if request.weather:
        w = request.weather
        lines.append(
            f"Weather: {w.get('temp', 'N/A')}F, "
            f"Wind: {w.get('wind_speed', 'N/A')} mph {w.get('wind_dir', '')}, "
            f"Condition: {w.get('condition', 'N/A')}"
        )

    if request.away_lineup:
        lines.append(f"\n{request.away_team} Lineup:")
        for p in request.away_lineup[:9]:
            name = p.get("name", "Unknown")
            pos = p.get("position", "")
            avg = p.get("batting_avg", "")
            lines.append(f"  {name} ({pos}) - AVG: {avg}")

    if request.home_lineup:
        lines.append(f"\n{request.home_team} Lineup:")
        for p in request.home_lineup[:9]:
            name = p.get("name", "Unknown")
            pos = p.get("position", "")
            avg = p.get("batting_avg", "")
            lines.append(f"  {name} ({pos}) - AVG: {avg}")

    if request.picks:
        lines.append("\nHit Predictions (top 5):")
        sorted_picks = sorted(request.picks, key=lambda x: x.get("probability", 0), reverse=True)
        for p in sorted_picks[:5]:
            name = p.get("player_name", "Unknown")
            prob = p.get("probability", 0)
            lines.append(f"  {name}: {prob:.1%}")

    if request.hr_picks:
        lines.append("\nHR Predictions (top 3):")
        sorted_hr = sorted(request.hr_picks, key=lambda x: x.get("probability", 0), reverse=True)
        for p in sorted_hr[:3]:
            name = p.get("player_name", "Unknown")
            prob = p.get("probability", 0)
            lines.append(f"  {name}: {prob:.1%}")

    return "\n".join(lines)


def _empty_magazine(request: GameDayRequest) -> dict:
    return {
        "headline": f"{request.away_team} vs {request.home_team}",
        "subheadline": f"Game Day Preview - {request.game_date}",
        "narrative": "Preview content is currently being generated.",
        "key_matchups": [],
        "predictions_narrative": "Predictions are being calculated.",
        "weather_impact": None,
        "fan_meter": 5,
        "tags": ["mlb", "preview"],
    }
