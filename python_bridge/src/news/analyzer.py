"""News article analysis using Claude with tool_use for structured output."""

import logging

from src.config import settings

logger = logging.getLogger(__name__)

CLASSIFY_TOOL = {
    "name": "classify_article",
    "description": (
        "Classify an MLB news article with category, sentiment, summary, and entity extraction."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "category": {
                "type": "string",
                "enum": [
                    "injury_new",
                    "injury_worsening",
                    "injury_update",
                    "injury_recovery",
                    "injury_cleared",
                    "trade",
                    "performance",
                    "transaction",
                    "news",
                ],
                "description": (
                    "The primary category of the article. "
                    "injury_new: just got injured, initial report. "
                    "injury_worsening: getting worse, needs imaging, "
                    "setback, moved to IL. "
                    "injury_update: status unknown, day-to-day, "
                    "awaiting results. "
                    "injury_recovery: rehab, progressing, ramp-up. "
                    "injury_cleared: cleared to play, returning. "
                    "trade: trade rumors, deals. "
                    "performance: stats, streaks, milestones. "
                    "transaction: roster moves, DFA, optioned, "
                    "called up, signings. "
                    "news: general news."
                ),
            },
            "sentiment": {
                "type": "string",
                "enum": ["negative", "neutral", "positive"],
                "description": "Overall sentiment of the article.",
            },
            "summary": {
                "type": "string",
                "description": "One clear sentence summarizing the article.",
            },
            "player_names": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Full names of MLB players mentioned.",
            },
            "team_names": {
                "type": "array",
                "items": {"type": "string"},
                "description": "MLB team names or abbreviations mentioned.",
            },
        },
        "required": ["category", "sentiment", "summary"],
    },
}

SYSTEM_PROMPT = (
    "You are an MLB news classifier. Analyze the article and classify it accurately.\n\n"
    "For injury articles, pay close attention to the trajectory and severity:\n"
    "- Look for keywords: imaging, MRI, X-ray, CT scan, IL (injured list), "
    "day-to-day, cleared, setback, rehab, surgery, soreness, strain, sprain, "
    "fracture, inflammation, tightness, discomfort, hit by pitch\n"
    "- Determine if the situation is NEW (just happened), WORSENING (getting worse, "
    "needs tests, moved to IL), UPDATE (status unknown, awaiting results), "
    "RECOVERY (improving, rehab), or CLEARED (good to go, returning)\n"
    "- 'Requires imaging' or 'scheduled for MRI' = injury_worsening (escalation)\n"
    "- 'Results still unknown' or 'day-to-day' = injury_update\n"
    "- 'Cleared to play' or 'activated from IL' = injury_cleared\n"
    "- 'Rehab assignment' or 'threw bullpen session' = injury_recovery\n\n"
    "For non-injury articles:\n"
    "- Roster moves (optioned, called up, DFA, designated, waiver) = transaction\n"
    "- Stats, records, streaks, milestones, MVP discussion = performance\n"
    "- Trade rumors, deals, deadline = trade\n"
    "- Everything else = news"
)


async def analyze_article(headline: str, excerpt: str) -> dict:
    """Analyze an MLB news article using Claude tool_use.

    Returns a dict with category, sentiment, summary, player_names, team_names.
    Falls back to defaults if the API call fails.
    """
    if not settings.anthropic_api_key:
        return _default_analysis()

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        message = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=256,
            temperature=0.0,
            system=SYSTEM_PROMPT,
            tools=[CLASSIFY_TOOL],
            tool_choice={"type": "tool", "name": "classify_article"},
            messages=[
                {
                    "role": "user",
                    "content": (
                        "Classify the following MLB news article.\n\n"
                        f"Headline: {headline}\n\n"
                        f"Excerpt: {excerpt}\n\n"
                        "Use the classify_article tool to return structured data."
                    ),
                }
            ],
        )

        # Extract tool_use result
        for block in message.content:
            if block.type == "tool_use" and block.name == "classify_article":
                result = block.input
                return {
                    "category": result.get("category", "news"),
                    "sentiment": result.get("sentiment", "neutral"),
                    "summary": result.get("summary", ""),
                    "player_names": result.get("player_names", []),
                    "team_names": result.get("team_names", []),
                }

        logger.warning("No tool_use block in Claude response")
        return _default_analysis()

    except Exception as e:
        logger.warning("News analysis failed: %s", e)
        return _default_analysis()


def _default_analysis() -> dict:
    return {
        "category": "news",
        "sentiment": "neutral",
        "summary": "",
        "player_names": [],
        "team_names": [],
    }
