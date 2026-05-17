"""X (Twitter) agent drafting endpoints.

Two endpoints:

  POST /x-agent/draft-post  — composes the main + self-reply pair for a
                              scheduled daily post.
  POST /x-agent/draft-reply — composes a single reply tweet given a target
                              tweet + our local facts.

Both reject URLs from the main_body and apply length truncation as a
hard server-side guard. The Elixir side re-validates everything.
"""

import json
import logging
import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from src.agents.x_agent_prompts import (
    INJURY_SYSTEM,
    REPLY_SYSTEM,
    TEAM_MAGAZINE_SYSTEM,
    TOP_HITS_SYSTEM,
    looks_like_injection,
)
from src.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_DEFAULT_CHARS = 270
URL_REGEX = re.compile(r"https?://\S+", re.IGNORECASE)
CONTROL_CHAR_REGEX = re.compile(r"[\x00-\x09\x0b-\x1f\x7f]")
ALLOWED_POST_TYPES = {"top_hits", "injury", "team_magazine"}


class DraftPostRequest(BaseModel):
    post_type: str = Field(..., min_length=1, max_length=50)
    context: dict = Field(default_factory=dict)
    link_url: str | None = None
    max_main_chars: int = MAX_DEFAULT_CHARS
    max_reply_chars: int = MAX_DEFAULT_CHARS


class DraftReplyRequest(BaseModel):
    target_tweet: dict
    our_context: dict
    max_chars: int = MAX_DEFAULT_CHARS


@router.post("/draft-post")
async def draft_post(request: DraftPostRequest):
    """Draft a main tweet + URL-bearing self-reply pair via Claude Haiku."""
    if request.post_type not in ALLOWED_POST_TYPES:
        raise HTTPException(status_code=422, detail="unsupported post_type")

    if not settings.anthropic_api_key:
        return _fallback_draft(request)

    system_prompt = _system_for(request.post_type)
    user_prompt = _user_prompt_for_draft(request)

    try:
        body = await _call_claude(system_prompt, user_prompt, max_tokens=600)
        main_body = _strip_urls(body.get("main_body", ""), limit=request.max_main_chars)
        reply_body = _truncate(body.get("reply_body", ""), limit=request.max_reply_chars)
        had_url = bool(URL_REGEX.search(body.get("main_body", "")))

        return {
            "main_body": main_body,
            "reply_body": reply_body,
            "model": settings.anthropic_model or "claude-haiku-4-5",
            "input_tokens": body.get("input_tokens", 0),
            "output_tokens": body.get("output_tokens", 0),
            "had_url_in_main": had_url,
        }
    except Exception as exc:
        logger.warning("draft_post failed: %s", exc)
        return _fallback_draft(request)


@router.post("/draft-reply")
async def draft_reply(request: DraftReplyRequest):
    """Draft a single reply tweet given a target tweet + our local facts."""
    target_text = (request.target_tweet or {}).get("text", "")

    if looks_like_injection(target_text):
        raise HTTPException(status_code=422, detail="rejected_injection_pattern")

    if CONTROL_CHAR_REGEX.search(target_text):
        raise HTTPException(status_code=422, detail="control_chars_in_target")

    if not settings.anthropic_api_key:
        return _fallback_reply(request)

    user_prompt = _user_prompt_for_reply(request)

    try:
        body = await _call_claude(REPLY_SYSTEM, user_prompt, max_tokens=400)
        reply_body = _truncate(
            _strip_urls(body.get("reply_body", "")),
            limit=request.max_chars,
        )

        return {
            "reply_body": reply_body,
            "confidence": float(body.get("confidence", 0.7) or 0.7),
            "model": settings.anthropic_model or "claude-haiku-4-5",
            "input_tokens": body.get("input_tokens", 0),
            "output_tokens": body.get("output_tokens", 0),
        }
    except Exception as exc:
        logger.warning("draft_reply failed: %s", exc)
        return _fallback_reply(request)


def _system_for(post_type: str) -> str:
    return {
        "top_hits": TOP_HITS_SYSTEM,
        "injury": INJURY_SYSTEM,
        "team_magazine": TEAM_MAGAZINE_SYSTEM,
    }[post_type]


def _user_prompt_for_draft(request: DraftPostRequest) -> str:
    return (
        "Compose a tweet pair (main_body + reply_body) given this context.\n\n"
        f"post_type: {request.post_type}\n"
        f"context: {json.dumps(request.context)[:2000]}\n"
        f"link_url: {request.link_url or ''}\n"
        f"max_main_chars: {request.max_main_chars}\n"
        f"max_reply_chars: {request.max_reply_chars}\n\n"
        'Return ONLY valid JSON with keys "main_body" and "reply_body".'
    )


def _user_prompt_for_reply(request: DraftReplyRequest) -> str:
    target = request.target_tweet or {}
    return (
        "Compose a single reply tweet given the target tweet and our facts.\n\n"
        f"target_tweet: {json.dumps(target)[:1500]}\n"
        f"our_context: {json.dumps(request.our_context)[:2000]}\n"
        f"max_chars: {request.max_chars}\n\n"
        'Return ONLY valid JSON with keys "reply_body" and optional '
        '"confidence" (0..1 float).'
    )


async def _call_claude(system: str, user: str, max_tokens: int = 600) -> dict:
    import anthropic

    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
    model = settings.anthropic_model or "claude-haiku-4-5-20251001"

    message = await client.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
    )

    text = message.content[0].text.strip()
    text = _unwrap_code_block(text)

    parsed = json.loads(text)
    parsed["input_tokens"] = getattr(message, "usage", None) and message.usage.input_tokens or 0
    parsed["output_tokens"] = getattr(message, "usage", None) and message.usage.output_tokens or 0
    return parsed


def _unwrap_code_block(text: str) -> str:
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    return text


def _strip_urls(text: str, limit: int | None = None) -> str:
    cleaned = URL_REGEX.sub("", text or "").strip()
    if limit is not None:
        cleaned = _truncate(cleaned, limit)
    return cleaned


def _truncate(text: str, limit: int) -> str:
    text = (text or "").strip()
    if limit and len(text) > limit:
        return text[: max(limit - 1, 0)].rstrip() + "…"
    return text


def _fallback_draft(request: DraftPostRequest) -> dict:
    """Cheap deterministic fallback when Claude is unavailable.

    Used when ANTHROPIC_API_KEY is unset or upstream errors. Keeps the
    pipeline running in tests/dev with no network calls.
    """
    title = {
        "top_hits": "🎯 Top hit predictions for today",
        "injury": "🩹 Today's injury report",
        "team_magazine": "📰 Team magazine update",
    }.get(request.post_type, "Sports Fanatic update")

    main = _truncate(title, request.max_main_chars)
    reply = _truncate(request.link_url or "", request.max_reply_chars)

    return {
        "main_body": main,
        "reply_body": reply,
        "model": "fallback",
        "input_tokens": 0,
        "output_tokens": 0,
        "had_url_in_main": False,
    }


def _fallback_reply(request: DraftReplyRequest) -> dict:
    return {
        "reply_body": "Thanks for the question — we'll dig into this and share more soon.",
        "confidence": 0.5,
        "model": "fallback",
        "input_tokens": 0,
        "output_tokens": 0,
    }
