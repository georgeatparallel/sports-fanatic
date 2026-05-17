"""FastAPI Python Bridge for Sports Fanatic.

Provides ML prediction endpoints and AI content generation.
"""

import logging

from fastapi import FastAPI

from src.api.agents import router as agents_router
from src.api.chat import router as chat_router
from src.api.gameday import router as gameday_router
from src.api.injury_report import router as injury_report_router
from src.api.news import router as news_router
from src.api.predict import router as predict_router
from src.api.schedule import router as schedule_router
from src.api.scouting import router as scouting_router
from src.api.team_magazine import router as team_magazine_router
from src.api.x_agent import router as x_agent_router
from src.config import settings
from src.simulation.engine import router as simulation_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Sports Fanatic Python Bridge",
    version="1.0.0",
    docs_url="/docs" if settings.debug else None,
)

app.include_router(agents_router, prefix="/agents", tags=["agents"])
app.include_router(chat_router, prefix="/chat", tags=["chat"])
app.include_router(predict_router, prefix="/predict", tags=["predictions"])
app.include_router(scouting_router, prefix="/scouting", tags=["scouting"])
app.include_router(gameday_router, prefix="/gameday", tags=["gameday"])
app.include_router(news_router, prefix="/news", tags=["news"])
app.include_router(schedule_router, prefix="/schedule", tags=["schedule"])
app.include_router(simulation_router, prefix="/simulation", tags=["simulation"])
app.include_router(x_agent_router, prefix="/x-agent", tags=["x-agent"])
app.include_router(injury_report_router, prefix="/injury-report", tags=["injury-report"])
app.include_router(team_magazine_router, prefix="/team-magazine", tags=["team-magazine"])


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
