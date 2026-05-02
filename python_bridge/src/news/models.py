"""Pydantic models for news article analysis."""

from enum import Enum as PyEnum

from pydantic import BaseModel, Field


class NewsCategory(str, PyEnum):
    """Categories for MLB news articles."""

    INJURY_ELBOW = "injury_elbow"
    INJURY_SHOULDER = "injury_shoulder"
    INJURY_OBLIQUE = "injury_oblique"
    INJURY_BACK = "injury_back"
    INJURY_KNEE = "injury_knee"
    INJURY_HAMSTRING = "injury_hamstring"
    INJURY_OTHER = "injury_other"
    TRADE = "trade"
    HIT_BY_PITCH = "hit_by_pitch"
    NEWS = "news"


class NewsSentiment(str, PyEnum):
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
