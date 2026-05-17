"""Team magazine generation endpoint.

Takes a team + scheduled game + lineup + Exa research + injury watch and
returns prose + bulleted today-at-a-glance fields ready to insert into
content.team_magazines.
"""

import json
import logging

from fastapi import APIRouter
from pydantic import BaseModel, Field

from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


class TeamMagazineRequest(BaseModel):
    team: dict
    scheduled_game: dict | None = None
    lineup: list[dict] = Field(default_factory=list)
    exa_results: list[dict] = Field(default_factory=list)
    injury_watch: list[dict] = Field(default_factory=list)


@router.post("/generate")
async def generate_team_magazine(request: TeamMagazineRequest):
    """Synthesize a team magazine summary for one team."""
    if not settings.anthropic_api_key:
        return _fallback(request)

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        model = settings.anthropic_model or "claude-haiku-4-5-20251001"

        system = (
            "You are a team-beat editor writing a daily magazine update for "
            "ONE MLB team. Use ONLY the data provided. Never invent stats. "
            "Tone: informed, not promissory. Do not promise a result; state "
            "the matchup and storyline."
        )

        prompt = (
            "Compose a daily magazine update.\n\n"
            f"Team: {json.dumps(request.team)[:500]}\n\n"
            f"Today's game: {json.dumps(request.scheduled_game)[:1500]}\n\n"
            f"Lineup: {json.dumps(request.lineup)[:3000]}\n\n"
            "Recent external coverage:\n"
            f"{json.dumps(request.exa_results)[:6000]}\n\n"
            f"Injury watch: {json.dumps(request.injury_watch)[:2000]}\n\n"
            "Return ONLY a JSON object with these fields:\n"
            "  - state_of_the_team (2-3 paragraph string)\n"
            "  - today_at_a_glance (array of 4-6 short bullet strings)\n"
            "  - game_summary_prose (one paragraph string)\n"
            "  - sources (array of {title, url, domain, published_at})\n"
        )

        message = await client.messages.create(
            model=model,
            max_tokens=1800,
            system=system,
            messages=[{"role": "user", "content": prompt}],
        )

        text = _unwrap(message.content[0].text.strip())
        body = json.loads(text)

        return {
            "state_of_the_team": body.get("state_of_the_team", ""),
            "today_at_a_glance": body.get("today_at_a_glance", []) or [],
            "game_summary_prose": body.get("game_summary_prose", ""),
            "sources": body.get("sources", []) or [],
            "model": model,
            "input_tokens": getattr(message, "usage", None)
            and message.usage.input_tokens
            or 0,
            "output_tokens": getattr(message, "usage", None)
            and message.usage.output_tokens
            or 0,
        }
    except Exception as exc:
        logger.warning("generate_team_magazine failed: %s", exc)
        return _fallback(request)


def _unwrap(text: str) -> str:
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    return text


def _fallback(request: TeamMagazineRequest) -> dict:
    team_name = (request.team or {}).get("name", "the team")
    return {
        "state_of_the_team": (
            f"{team_name} update is being compiled. Check back shortly for "
            "the full magazine."
        ),
        "today_at_a_glance": [
            "Game details loading",
            "Lineup snapshot loading",
            "Injury watch loading",
        ],
        "game_summary_prose": "Game preview is being prepared.",
        "sources": [],
        "model": "fallback",
        "input_tokens": 0,
        "output_tokens": 0,
    }
