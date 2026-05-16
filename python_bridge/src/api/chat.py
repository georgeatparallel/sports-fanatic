"""Chat context resolution endpoint using Claude for topic detection and prompt generation."""

import logging

import anthropic
from fastapi import APIRouter
from pydantic import BaseModel

from src.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

RESOLVE_CONTEXT_TOOL = {
    "name": "resolve_context",
    "description": (
        "Analyze a user's chat message in the context of their conversation history. "
        "Determine if it's a follow-up or new topic, resolve references, and generate search prompts."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "is_continuation": {
                "type": "boolean",
                "description": "True if this message continues the previous topic, False if it's a new topic.",
            },
            "resolved_query": {
                "type": "string",
                "description": (
                    "The user's query with all pronouns and references resolved to explicit names. "
                    "E.g., 'when is he expected back' becomes 'when is Hunter Brown expected back from IL'."
                ),
            },
            "entities": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Key MLB entities mentioned or referenced (player names, team names).",
            },
            "search_prompts": {
                "type": "array",
                "items": {"type": "string"},
                "description": (
                    "2-3 specific search queries for Exa.ai to find relevant MLB articles. "
                    "Always include 'MLB' or 'baseball' in each query. Include the year 2026 in at least one."
                ),
            },
            "reasoning": {
                "type": "string",
                "description": "Brief explanation of why this is a continuation or new topic.",
            },
        },
        "required": [
            "is_continuation",
            "resolved_query",
            "entities",
            "search_prompts",
            "reasoning",
        ],
    },
}

SYSTEM_PROMPT = """You are an MLB news research assistant analyzing user queries in a conversation.

Given the conversation history and the new user message, you must:

1. Determine if the new message is a CONTINUATION of the previous topic or a NEW topic.
   - CONTINUATION signals: pronouns (he, she, they, his, their, him), follow-up phrases (when is, what about, tell me more, how about, and also, any update on), references to entities from prior messages.
   - NEW TOPIC signals: new proper nouns not mentioned before, completely different subject matter (e.g., switching from a player to "hr streaks"), explicit topic changes.

2. Resolve any pronouns or implicit references using conversation context.
   - "when is he expected back" → if prior messages discussed Hunter Brown's injury, resolve to "when is Hunter Brown expected back from injury"
   - "what about his stats" → resolve "his" to the specific player discussed

3. Generate 2-3 specific Exa.ai search queries to find relevant MLB articles.
   - ALWAYS include "MLB" or "baseball" in each query to filter noise
   - Include "2026" in at least one query for recency
   - Make queries specific enough to get relevant results
   - For injury return timelines: include "IL", "return", "timeline", "expected back"
   - For performance topics: include "stats", "season", relevant stat names
   - For trades: include "trade", "rumors", "deal"

Use the resolve_context tool to return your analysis."""


class ConversationMessage(BaseModel):
    role: str
    content: str


class ResolveContextRequest(BaseModel):
    query: str
    conversation: list[ConversationMessage]


class ResolveContextResponse(BaseModel):
    is_continuation: bool
    resolved_query: str
    entities: list[str]
    search_prompts: list[str]
    reasoning: str


@router.post("/resolve-context", response_model=ResolveContextResponse)
async def resolve_context(request: ResolveContextRequest):
    """Resolve chat context: detect topic changes, resolve references, generate search prompts."""

    if not settings.anthropic_api_key:
        logger.warning("ANTHROPIC_API_KEY not set, returning passthrough response")
        return ResolveContextResponse(
            is_continuation=False,
            resolved_query=request.query,
            entities=[],
            search_prompts=[
                f"{request.query} MLB baseball 2026",
                f"{request.query} MLB news",
            ],
            reasoning="No API key configured, treating as new topic.",
        )

    try:
        client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

        # Build conversation context for the LLM
        messages = []
        for msg in request.conversation:
            messages.append({"role": msg.role, "content": msg.content})

        # Add the current query as the latest user message
        messages.append(
            {
                "role": "user",
                "content": f"New user message to analyze: \"{request.query}\"",
            }
        )

        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=512,
            temperature=0.0,
            system=SYSTEM_PROMPT,
            messages=messages,
            tools=[RESOLVE_CONTEXT_TOOL],
            tool_choice={"type": "tool", "name": "resolve_context"},
        )

        # Extract tool use result
        for block in response.content:
            if block.type == "tool_use" and block.name == "resolve_context":
                result = block.input
                return ResolveContextResponse(
                    is_continuation=result.get("is_continuation", False),
                    resolved_query=result.get("resolved_query", request.query),
                    entities=result.get("entities", []),
                    search_prompts=result.get("search_prompts", []),
                    reasoning=result.get("reasoning", ""),
                )

        # Fallback if no tool use found
        logger.warning("No tool_use block in context resolution response")
        return _fallback_response(request.query)

    except Exception as e:
        logger.error(f"Context resolution failed: {e}")
        return _fallback_response(request.query)


def _fallback_response(query: str) -> ResolveContextResponse:
    """Fallback when LLM call fails."""
    return ResolveContextResponse(
        is_continuation=False,
        resolved_query=query,
        entities=[],
        search_prompts=[
            f"{query} MLB baseball 2026",
            f"{query} MLB news latest",
        ],
        reasoning="Fallback: treating as new topic due to processing error.",
    )
