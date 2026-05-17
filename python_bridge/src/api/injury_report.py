"""Injury report generation endpoint.

Takes a player + local news items + Exa search results and synthesizes the
flattened classification trail into a single magazine-style page payload.
The Elixir side persists the result in `content.injury_reports`.
"""

import json
import logging

from fastapi import APIRouter
from pydantic import BaseModel, Field

from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

ALLOWED_STATUS = {
    "active",
    "day-to-day",
    "injured-list-10",
    "injured-list-15",
    "injured-list-60",
    "recovering",
    "cleared",
    "unknown",
}


class InjuryReportRequest(BaseModel):
    player: dict
    local_news_items: list[dict] = Field(default_factory=list)
    exa_results: list[dict] = Field(default_factory=list)


@router.post("/generate")
async def generate_injury_report(request: InjuryReportRequest):
    """Synthesize an injury report for one player from news + Exa sources."""
    if not settings.anthropic_api_key:
        return _fallback(request)

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        model = settings.anthropic_model or "claude-haiku-4-5-20251001"

        system = (
            "You are a baseball injury beat reporter writing a brief, "
            "concerned-fan summary of one player's injury timeline. Use "
            "ONLY the news items and Exa sources provided. Never invent "
            "diagnoses. Cite each timeline entry to a source_url when one "
            "is available."
        )

        prompt = (
            "Summarize this player's current injury situation.\n\n"
            f"Player: {json.dumps(request.player)[:500]}\n\n"
            "Local news items (last 3 days):\n"
            f"{json.dumps(request.local_news_items)[:6000]}\n\n"
            "External sources:\n"
            f"{json.dumps(request.exa_results)[:8000]}\n\n"
            "Return ONLY a JSON object with these fields:\n"
            "  - tldr (string, <= 240 chars)\n"
            "  - current_status (one of: active, day-to-day, "
            "injured-list-10, injured-list-15, injured-list-60, recovering, "
            "cleared, unknown)\n"
            "  - timeline (array of {date: YYYY-MM-DD, event: string, "
            "source_url: string|null})\n"
            "  - expected_return (string|null, free text)\n"
            "  - fantasy_impact (string, 1-2 sentences)\n"
            "  - sources (array of {title, url, domain, published_at})\n"
        )

        message = await client.messages.create(
            model=model,
            max_tokens=1500,
            system=system,
            messages=[{"role": "user", "content": prompt}],
        )

        text = _unwrap(message.content[0].text.strip())
        body = json.loads(text)

        status = body.get("current_status", "unknown")
        if status not in ALLOWED_STATUS:
            status = "unknown"

        return {
            "tldr": body.get("tldr", ""),
            "current_status": status,
            "timeline": body.get("timeline", []) or [],
            "expected_return": body.get("expected_return"),
            "fantasy_impact": body.get("fantasy_impact", ""),
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
        logger.warning("generate_injury_report failed: %s", exc)
        return _fallback(request)


def _unwrap(text: str) -> str:
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    return text


def _fallback(request: InjuryReportRequest) -> dict:
    name = (request.player or {}).get("full_name", "this player")
    return {
        "tldr": f"Status for {name} is currently being compiled.",
        "current_status": "unknown",
        "timeline": [],
        "expected_return": None,
        "fantasy_impact": "Insufficient data to assess fantasy impact at this time.",
        "sources": [],
        "model": "fallback",
        "input_tokens": 0,
        "output_tokens": 0,
    }
