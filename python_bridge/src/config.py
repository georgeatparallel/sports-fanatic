"""Configuration from environment variables."""

import os
from dataclasses import dataclass


@dataclass
class Settings:
    database_url: str = os.getenv(
        "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/sports_fanatic"
    )
    anthropic_api_key: str = os.getenv("ANTHROPIC_API_KEY", "")
    anthropic_model: str = os.getenv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
    exa_api_key: str = os.getenv("EXA_API_KEY", "")
    host: str = os.getenv("HOST", "0.0.0.0")  # noqa: S104
    port: int = int(os.getenv("PORT", "8000"))
    debug: bool = os.getenv("DEBUG", "false").lower() == "true"


settings = Settings()
