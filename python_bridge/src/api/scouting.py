"""Scouting report generation: Exa AI search + Claude synthesis.

Ported from sports-fan-agent scouting service.
"""

import json
import logging

from fastapi import APIRouter
from pydantic import BaseModel

from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


class ScoutingGenerateRequest(BaseModel):
    player_name: str
    player_id: str
    sources_text: list[str] = []


class ScoutingSearchRequest(BaseModel):
    player_name: str


@router.post("/generate")
async def generate_scouting(request: ScoutingGenerateRequest):
    """Generate a structured scouting report using Claude."""
    if not settings.anthropic_api_key or not request.sources_text:
        return {"report": _empty_report()}

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        combined_text = "\n\n---\n\n".join(request.sources_text[:10])

        message = await client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=2000,
            messages=[
                {
                    "role": "user",
                    "content": f"""Analyze the following news and data about MLB player \
{request.player_name}.
Return a JSON object with exactly these fields:

- hit_streak: current hitting streak (integer or null)
- hr_streak: current home run streak (integer or null)
- on_base_streak: current on-base streak (integer or null)
- injury_status: one of "healthy", "day-to-day", "IL-10", "IL-15", "IL-60"
- injury_detail: description of injury or null
- positive_factors: array of positive factors affecting performance (strings)
- negative_factors: array of negative factors (strings)
- overall_sentiment: one of "positive", "neutral", "negative"
- confidence_modifier: float between -0.1 and 0.1
- news_summary: 2-3 sentence summary of recent news
- sources_count: number of sources analyzed
- hit_probability: estimated hit probability today (float 0-1 or null)
- hr_probability: estimated HR probability today (float 0-1 or null)

Return ONLY valid JSON, no other text.

Sources:
{combined_text}""",
                }
            ],
        )

        response_text = message.content[0].text.strip()
        if response_text.startswith("```"):
            response_text = response_text.split("```")[1]
            if response_text.startswith("json"):
                response_text = response_text[4:]

        report = json.loads(response_text)
        return {"report": report}

    except Exception as e:
        logger.warning("Scouting generation failed: %s", e)
        return {"report": _empty_report()}


@router.post("/search")
async def search_player(request: ScoutingSearchRequest):
    """Search for player information using Exa AI."""
    if not settings.exa_api_key:
        return {"sources": []}

    try:
        from exa_py import Exa

        exa = Exa(api_key=settings.exa_api_key)

        queries = [
            f'"{request.player_name}" MLB injury status',
            f'"{request.player_name}" MLB hitting streak stats',
            f'"{request.player_name}" MLB recent performance',
        ]

        all_results = []
        for query in queries:
            results = exa.search_and_contents(
                query, num_results=3, text=True, use_autoprompt=True
            )
            for r in results.results:
                all_results.append({
                    "url": r.url,
                    "title": r.title,
                    "text": r.text[:5000] if r.text else None,
                    "published_date": r.published_date,
                    "score": r.score,
                })

        return {"sources": all_results}

    except Exception as e:
        logger.warning("Exa search failed: %s", e)
        return {"sources": []}


def _empty_report() -> dict:
    return {
        "hit_streak": None,
        "hr_streak": None,
        "on_base_streak": None,
        "injury_status": "healthy",
        "injury_detail": None,
        "positive_factors": [],
        "negative_factors": [],
        "overall_sentiment": "neutral",
        "confidence_modifier": 0.0,
        "news_summary": "No data available",
        "sources_count": 0,
        "hit_probability": None,
        "hr_probability": None,
    }
