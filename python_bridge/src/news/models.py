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


class InjuryGrade(StrEnum):
    """Severity/timeline grade for injury articles."""

    DAY_TO_DAY = "day_to_day"
    TEN_DAY_IL = "10_day_il"
    FIFTEEN_DAY_IL = "15_day_il"
    SIXTY_DAY_IL = "60_day_il"
    SEASON_ENDING = "season_ending"
    PENDING_IMAGING = "pending_imaging"
    CLEARED = "cleared"
    REHAB_ASSIGNMENT = "rehab_assignment"
    UNKNOWN = "unknown"


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
    injury_area: str | None = Field(
        default=None,
        description="Body part or injury type label, 1-3 words (only for injury categories)",
    )
    injury_grade: str | None = Field(
        default=None,
        description="Severity/timeline grade (only for injury categories)",
    )
