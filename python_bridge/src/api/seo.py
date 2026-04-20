"""SEO content generation for player daily pages via Claude API."""

import json
import logging
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


class PlayerSeoRequest(BaseModel):
    player_name: str
    player_position: str
    team_name: str
    team_slug: str
    player_slug: str
    bats: Optional[str] = None
    throws: Optional[str] = None
    content_date: str  # ISO date
    opposing_pitcher: Optional[dict] = None
    park_factors: Optional[dict] = None
    hit_prediction: Optional[dict] = None
    hr_prediction: Optional[dict] = None
    scouting_summary: Optional[str] = None
    recent_stats: Optional[dict] = None
    season_stats: Optional[dict] = None


@router.post("/generate-player-daily")
async def generate_player_daily(request: PlayerSeoRequest):
    """Generate structured SEO content for a player's daily page using Claude."""
    if not settings.anthropic_api_key:
        logger.warning("No ANTHROPIC_API_KEY configured, returning empty content")
        return {"content": _empty_content(request)}

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

        prompt = _build_prompt(request)

        message = await client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=3000,
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
        )

        response_text = message.content[0].text.strip()

        # Strip markdown code fences if present
        if response_text.startswith("```"):
            response_text = response_text.split("```")[1]
            if response_text.startswith("json"):
                response_text = response_text[4:]

        content = json.loads(response_text)

        # Validate and truncate meta_description to 160 chars
        if len(content.get("meta_description", "")) > 160:
            content["meta_description"] = content["meta_description"][:157] + "..."

        return {"content": content}

    except Exception as e:
        logger.warning("Player SEO generation failed for %s: %s", request.player_name, e)
        return {"content": _empty_content(request)}


def _build_prompt(request: PlayerSeoRequest) -> str:
    """Build the Claude prompt for player SEO content generation."""
    context_parts = [
        f"Player: {request.player_name}",
        f"Position: {request.player_position}",
        f"Team: {request.team_name}",
        f"Date: {request.content_date}",
    ]

    if request.bats:
        context_parts.append(f"Bats: {request.bats}")
    if request.throws:
        context_parts.append(f"Throws: {request.throws}")

    if request.opposing_pitcher:
        op = request.opposing_pitcher
        context_parts.append(
            f"Opposing Pitcher: {op.get('name', 'Unknown')} "
            f"(Hand: {op.get('hand', 'Unknown')}, "
            f"ERA: {op.get('era', 'N/A')}, "
            f"WHIP: {op.get('whip', 'N/A')})"
        )

    if request.park_factors:
        pf = request.park_factors
        context_parts.append(
            f"Park: {pf.get('venue', 'Unknown')} "
            f"(HR Factor: {pf.get('hr_factor', 'N/A')}, "
            f"Hit Factor: {pf.get('hit_factor', 'N/A')})"
        )

    if request.hit_prediction:
        hp = request.hit_prediction
        context_parts.append(
            f"Hit Prediction: {hp.get('probability', 'N/A')} probability "
            f"(confidence: {hp.get('confidence', 'N/A')}) vs {hp.get('vs_team', 'Unknown')}"
        )

    if request.hr_prediction:
        hrp = request.hr_prediction
        context_parts.append(
            f"HR Prediction: {hrp.get('probability', 'N/A')} probability "
            f"(tier: {hrp.get('confidence_tier', 'N/A')}) vs {hrp.get('vs_team', 'Unknown')}"
        )

    if request.scouting_summary:
        context_parts.append(f"Scouting Summary: {request.scouting_summary}")

    if request.season_stats:
        ss = request.season_stats
        context_parts.append(
            f"Season Stats: AVG {ss.get('avg', 'N/A')}, "
            f"HR {ss.get('hr', 'N/A')}, "
            f"RBI {ss.get('rbi', 'N/A')}, "
            f"OPS {ss.get('ops', 'N/A')}, "
            f"Games {ss.get('games', 'N/A')}"
        )

    if request.recent_stats:
        rs = request.recent_stats
        for period in ["last_7", "last_15", "last_30"]:
            if period in rs:
                ps = rs[period]
                context_parts.append(
                    f"{period.replace('_', ' ').title()} Days: "
                    f"AVG {ps.get('avg', 'N/A')}, OPS {ps.get('ops', 'N/A')}"
                )

    context_block = "\n".join(context_parts)

    return f"""You are an expert MLB analyst and SEO content writer. Generate structured SEO content
for a player's daily analysis page. Be factual and do not fabricate statistics or claims.
Use only the data provided. Write for Google featured snippets and search optimization.

PLAYER CONTEXT:
{context_block}

Generate a JSON object with exactly these fields:

1. "headline" - An engaging H1 headline (50-80 chars) referencing today's matchup or situation.
   Example: "Aaron Judge Faces Left-Handed Challenge at Fenway"

2. "lead_paragraph" - An editorial opening paragraph (2-3 sentences) summarizing the player's
   current situation and today's matchup.

3. "tldr" - A TL;DR summary (1-2 sentences) for quick readers.

4. "matchup_analysis" - Detailed analysis (2-3 paragraphs) of today's specific matchup including
   pitcher handedness vs batter, park factors, and recent performance context.

5. "recent_form" - Narrative on the player's last 7/15/30 day performance trends (1-2 paragraphs).

6. "trends" - Array of trend objects: [{{"period": "7d", "avg": ".340", "ops": ".950", "note": "Hot streak"}}]
   Include 7d, 15d, and 30d periods if data is available.

7. "projections" - Object with: {{"hit_probability": 0.72, "hr_probability": 0.08, "confidence": "high", "model_factors": ["vs LHP advantage", "park factors"]}}

8. "faq_items" - Array of 4-6 FAQ items targeting Google featured snippets. Each: {{"question": "...", "answer": "..."}}
   Include questions like:
   - "Is {request.player_name} playing today?"
   - "What is {request.player_name}'s batting average?"
   - "How does {request.player_name} perform against [handedness] pitching?"
   - "What are {request.player_name}'s stats this season?"
   Answers should be concise (1-2 sentences) and factual based on the provided data.

9. "meta_description" - SEO meta description, max 155 characters. Include player name, team, and today's key angle.

10. "keywords" - Array of 5-8 SEO keywords relevant to this player and today's content.

Return ONLY valid JSON, no other text. Do not wrap in markdown code fences."""


def _empty_content(request: PlayerSeoRequest) -> dict:
    """Return minimal fallback content when generation fails."""
    return {
        "headline": f"{request.player_name} - Today's Analysis",
        "lead_paragraph": f"{request.player_name} of the {request.team_name} is in action today.",
        "tldr": f"Daily analysis for {request.player_name}.",
        "matchup_analysis": None,
        "recent_form": None,
        "trends": [],
        "projections": {},
        "faq_items": [
            {
                "question": f"Is {request.player_name} playing today?",
                "answer": f"{request.player_name} is listed in today's lineup for the {request.team_name}.",
            }
        ],
        "meta_description": f"{request.player_name} daily analysis, stats, and predictions for the {request.team_name}."[:160],
        "keywords": [request.player_name, request.team_name, "MLB", "baseball", "stats"],
    }
