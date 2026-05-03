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
                    "content": (
                        "Analyze the following news and data about MLB "
                        f"player {request.player_name}.\n"
                        "Return a JSON object with exactly these fields:\n\n"
                        "- hit_streak: current hitting streak "
                        "(integer or null)\n"
                        "- hr_streak: current home run streak "
                        "(integer or null)\n"
                        "- on_base_streak: current on-base streak "
                        "(integer or null)\n"
                        '- injury_status: one of "healthy", "day-to-day", '
                        '"IL-10", "IL-15", "IL-60"\n'
                        "- injury_detail: description of injury or null\n"
                        "- positive_factors: array of positive factors "
                        "affecting performance (strings)\n"
                        "- negative_factors: array of negative factors "
                        "(strings)\n"
                        '- overall_sentiment: one of "positive", "neutral", '
                        '"negative"\n'
                        "- confidence_modifier: float between -0.1 and 0.1\n"
                        "- news_summary: 2-3 sentence summary of recent "
                        "news\n"
                        "- sources_count: number of sources analyzed\n"
                        "- hit_probability: estimated hit probability today "
                        "(float 0-1 or null)\n"
                        "- hr_probability: estimated HR probability today "
                        "(float 0-1 or null)\n\n"
                        "Return ONLY valid JSON, no other text.\n\n"
                        f"Sources:\n{combined_text}"
                    ),
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
            results = exa.search_and_contents(query, num_results=3, text=True, use_autoprompt=True)
            for r in results.results:
                all_results.append(
                    {
                        "url": r.url,
                        "title": r.title,
                        "text": r.text[:5000] if r.text else None,
                        "published_date": r.published_date,
                        "score": r.score,
                    }
                )

        return {"sources": all_results}

    except Exception as e:
        logger.warning("Exa search failed: %s", e)
        return {"sources": []}


class ScoutingClassifyRequest(BaseModel):
    title: str
    text: str


@router.post("/search_multi")
async def search_player_multi(request: ScoutingSearchRequest):
    """Multi-query Exa search: news, analyst reports, and fantasy/betting analysis."""
    if not settings.exa_api_key:
        return {"sources": []}

    try:
        from exa_py import Exa

        exa = Exa(api_key=settings.exa_api_key)

        query_groups = [
            {
                "query": f'"{request.player_name}" MLB latest news',
                "source_type": "news",
            },
            {
                "query": f'"{request.player_name}" MLB scouting report analysis evaluation',
                "source_type": "analyst",
            },
            {
                "query": f'"{request.player_name}" MLB fantasy prop betting analysis',
                "source_type": "fantasy_betting",
            },
        ]

        all_results = []
        for group in query_groups:
            try:
                results = exa.search_and_contents(
                    group["query"],
                    num_results=5,
                    text=True,
                    use_autoprompt=True,
                )
                for r in results.results:
                    all_results.append(
                        {
                            "url": r.url,
                            "title": r.title,
                            "text": r.text[:5000] if r.text else None,
                            "published_date": r.published_date,
                            "score": r.score,
                            "source_type": group["source_type"],
                        }
                    )
            except Exception as e:
                logger.warning("Exa search failed for query '%s': %s", group["query"], e)

        # Deduplicate by URL
        seen_urls = set()
        unique_results = []
        for r in all_results:
            if r["url"] not in seen_urls:
                seen_urls.add(r["url"])
                unique_results.append(r)

        return {"sources": unique_results}

    except Exception as e:
        logger.warning("Exa multi-search failed: %s", e)
        return {"sources": []}


@router.post("/classify")
async def classify_content(request: ScoutingClassifyRequest):
    """Classify content into scouting categories using Claude."""
    if not settings.anthropic_api_key:
        return {
            "classification": "general_news",
            "summary": request.title,
            "key_facts": [],
            "digest": None,
        }

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        truncated_text = request.text[:3000] if request.text else ""

        message = await client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1200,
            messages=[
                {
                    "role": "user",
                    "content": (
                        "Classify the following sports content and extract "
                        "key information.\n\n"
                        f"Title: {request.title}\n"
                        f"Content: {truncated_text}\n\n"
                        "Return a JSON object with exactly these fields:\n"
                        '- classification: one of "performance_analysis", '
                        '"injury_report", "trade_rumor", '
                        '"prospect_evaluation", "fantasy_value", '
                        '"betting_insight", "general_news"\n'
                        "- summary: 1-2 sentence summary of the content\n"
                        "- key_facts: array of key facts, quotes, or data "
                        "points extracted (max 5 items)\n"
                        "- digest: a 2-4 paragraph concise rewrite of the "
                        "source content. Strip filler and prose, keep all "
                        "factual substance, statistics, quotes, and key "
                        "information. Write in a neutral analytical voice. "
                        "The reader should get the full value of the source "
                        "without needing to visit the original URL.\n\n"
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

        result = json.loads(response_text)
        return {
            "classification": result.get("classification", "general_news"),
            "summary": result.get("summary", request.title),
            "key_facts": result.get("key_facts", []),
            "digest": result.get("digest"),
        }

    except Exception as e:
        logger.warning("Content classification failed: %s", e)
        return {
            "classification": "general_news",
            "summary": request.title,
            "key_facts": [],
            "digest": None,
        }


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
