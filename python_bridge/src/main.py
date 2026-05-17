"""FastAPI Python Bridge for Sports Fanatic.

Provides ML inference and AI content generation endpoints. The hits-prediction
pipeline now lives entirely in Elixir; this bridge only exposes a single
inference endpoint (`/inference/hit`) plus the Claude-driven content endpoints.
"""

import logging

from fastapi import FastAPI

from src.api.agents import router as agents_router
from src.api.chat import router as chat_router
from src.api.gameday import router as gameday_router
from src.api.inference import router as inference_router
from src.api.injury_report import router as injury_report_router
from src.api.news import router as news_router
from src.api.scouting import router as scouting_router
from src.api.team_magazine import router as team_magazine_router
from src.api.x_agent import router as x_agent_router
from src.config import settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Sports Fanatic Python Bridge",
    version="2.0.0",
    docs_url="/docs" if settings.debug else None,
)

# ML inference (single supported endpoint for predictions)
app.include_router(inference_router, prefix="/inference", tags=["inference"])

# Claude-driven content endpoints (kept on the Python bridge)
app.include_router(agents_router, prefix="/agents", tags=["agents"])
app.include_router(chat_router, prefix="/chat", tags=["chat"])
app.include_router(scouting_router, prefix="/scouting", tags=["scouting"])
app.include_router(gameday_router, prefix="/gameday", tags=["gameday"])
app.include_router(news_router, prefix="/news", tags=["news"])

# X (Twitter) marketing agent
app.include_router(x_agent_router, prefix="/x-agent", tags=["x-agent"])
app.include_router(
    injury_report_router, prefix="/injury-report", tags=["injury-report"]
)
app.include_router(
    team_magazine_router, prefix="/team-magazine", tags=["team-magazine"]
)


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "models_loaded": True}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "src.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
