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
                    "injury_elbow",
                    "injury_shoulder",
                    "injury_oblique",
                    "injury_back",
                    "injury_knee",
                    "injury_hamstring",
                    "injury_other",
                    "trade",
                    "hit_by_pitch",
                    "news",
                ],
                "description": "The primary category of the article.",
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
