"""News article analysis using Claude with tool_use for structured output."""

import logging

from src.config import settings

logger = logging.getLogger(__name__)

CLASSIFY_TOOL = {
    "name": "classify_article",
    "description": (
        "Classify an MLB news article with category, sentiment, summary, "
        "entity extraction, and injury details when applicable."
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
            "injury_area": {
                "type": "string",
                "description": (
                    "Short label for the body part or injury type, 1-3 words max. "
                    "Only set for injury categories. Examples: 'Oblique Strain', "
                    "'Elbow - UCL', 'Hamstring', 'Shoulder', 'Back', 'Knee - ACL', "
                    "'Finger Fracture', 'Concussion', 'General Soreness', 'Undisclosed'."
                ),
            },
            "injury_grade": {
                "type": "string",
                "enum": [
                    "day_to_day",
                    "10_day_il",
                    "15_day_il",
                    "60_day_il",
                    "season_ending",
                    "pending_imaging",
                    "cleared",
                    "rehab_assignment",
                    "unknown",
                ],
                "description": (
                    "Severity/timeline grade for the injury. Only set for injury categories. "
                    "day_to_day: minor, could return soon. "
                    "10_day_il: 10-day injured list. "
                    "15_day_il: 15-day injured list. "
                    "60_day_il: 60-day injured list, serious. "
                    "season_ending: out for the season (surgery, major tear). "
                    "pending_imaging: awaiting MRI/X-ray results. "
                    "cleared: cleared to return. "
                    "rehab_assignment: on rehab in minors. "
                    "unknown: severity not yet determined."
                ),
            },
            "domain_tags": {
                "type": "array",
                "items": {"type": "string"},
                "description": (
                    "Baseball-domain concept tags for the article. Use lowercase hyphenated tags. "
                    "Examples: streak, home-run, trade-deadline, walk-off, no-hitter, "
                    "save, closer, bullpen, rotation, prospect, call-up, slump, "
                    "injury, comeback, milestone, record, all-star, free-agency, "
                    "arbitration, spring-training, postseason, world-series, "
                    "perfect-game, grand-slam, stolen-base, pitching-duel."
                ),
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
    "For ALL injury categories, you MUST also provide:\n"
    "- injury_area: Short label for the body part or injury type (1-3 words). "
    "Examples: 'Oblique Strain', 'Elbow - UCL', 'Hamstring', 'Shoulder', 'Back', "
    "'Knee - ACL', 'Finger Fracture', 'Concussion', 'General Soreness', 'Undisclosed'.\n"
    "- injury_grade: The severity/timeline. Use 'day_to_day' for minor issues, "
    "'10_day_il'/'15_day_il'/'60_day_il' when IL placement is mentioned, "
    "'season_ending' for surgery or season-ending injuries, "
    "'pending_imaging' when awaiting test results, "
    "'cleared' when returning to play, "
    "'rehab_assignment' when on rehab in the minors, "
    "'unknown' when severity is not yet determined.\n\n"
    "For non-injury articles, do NOT set injury_area or injury_grade.\n\n"
    "For non-injury articles:\n"
    "- Roster moves (optioned, called up, DFA, designated, waiver) = transaction\n"
    "- Stats, records, streaks, milestones, MVP discussion = performance\n"
    "- Trade rumors, deals, deadline = trade\n"
    "- Everything else = news\n\n"
    "For ALL articles, provide domain_tags — lowercase hyphenated baseball concept tags.\n"
    "Examples: streak, home-run, trade-deadline, walk-off, no-hitter, save, closer, "
    "bullpen, rotation, prospect, call-up, slump, injury, comeback, milestone, record, "
    "all-star, free-agency, stolen-base, pitching-duel, grand-slam.\n"
    "Include 1-5 relevant tags per article."
)


async def analyze_article(headline: str, excerpt: str) -> dict:
    """Analyze an MLB news article using Claude tool_use.

    Returns a dict with category, sentiment, summary, player_names, team_names,
    and optionally injury_area and injury_grade for injury articles.
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
                    "injury_area": result.get("injury_area"),
                    "injury_grade": result.get("injury_grade"),
                    "domain_tags": result.get("domain_tags", []),
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
        "injury_area": None,
        "injury_grade": None,
        "domain_tags": [],
    }
