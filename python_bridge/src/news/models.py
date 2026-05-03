"""Pydantic models for news article analysis."""

from enum import StrEnum

from pydantic import BaseModel, Field


class NewsCategory(StrEnum):
    """Categories for MLB news articles.

    Injury categories use severity/trajectory rather than body part.
    """

    INJURY_NEW = "injury_new"
    INJURY_WORSENING = "injury_worsening"
    INJURY_UPDATE = "injury_update"
    INJURY_RECOVERY = "injury_recovery"
    INJURY_CLEARED = "injury_cleared"
    TRADE = "trade"
    PERFORMANCE = "performance"
    TRANSACTION = "transaction"
    NEWS = "news"


class NewsSentiment(StrEnum):
    """Sentiment classification for news articles."""

    NEGATIVE = "negative"
    NEUTRAL = "neutral"
    POSITIVE = "positive"


class NewsAnalysis(BaseModel):
    """Structured result from AI news analysis."""

    category: str = Field(description="Article category classification")
    sentiment: str = Field(description="Article sentiment: negative, neutral, or positive")
    summary: str = Field(description="One-sentence summary of the article")
    player_names: list[str] = Field(
        default_factory=list,
        description="MLB player names mentioned in the article",
    )
    team_names: list[str] = Field(
        default_factory=list,
        description="MLB team names or abbreviations mentioned",
    )
