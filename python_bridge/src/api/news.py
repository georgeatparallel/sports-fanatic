"""News article analysis endpoint."""

import logging

from fastapi import APIRouter
from pydantic import BaseModel

from src.news.analyzer import analyze_article

logger = logging.getLogger(__name__)
router = APIRouter()


class AnalyzeRequest(BaseModel):
    headline: str
    excerpt: str


@router.post("/analyze")
async def analyze(request: AnalyzeRequest):
    """Analyze an MLB news article for category, sentiment, and summary."""
    result = await analyze_article(request.headline, request.excerpt)
    return result
