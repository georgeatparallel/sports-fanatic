"""Agent setting parsing and execution endpoints."""

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from src.agents.parser import parse_setting

logger = logging.getLogger(__name__)
router = APIRouter()

MAX_PROMPT_LENGTH = 500


class ParseSettingRequest(BaseModel):
    raw_prompt: str = Field(..., max_length=MAX_PROMPT_LENGTH)
    context: dict | None = None


@router.post("/parse-setting")
async def parse_setting_endpoint(request: ParseSettingRequest):
    """Parse a natural language agent setting into structured criteria."""
    if len(request.raw_prompt.strip()) == 0:
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")

    if len(request.raw_prompt) > MAX_PROMPT_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=f"Prompt exceeds {MAX_PROMPT_LENGTH} character limit",
        )

    result = await parse_setting(request.raw_prompt, request.context)

    if "error" in result:
        raise HTTPException(status_code=422, detail=result["error"])

    return result
