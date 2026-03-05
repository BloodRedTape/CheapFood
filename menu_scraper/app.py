from __future__ import annotations

import logging
import time

from fastapi import FastAPI

from menu_scraper.models.requests import ScrapeRequest, ScrapeResponse
from menu_scraper.scraper import scrape_menu

logging.basicConfig(level=logging.INFO)

app: FastAPI = FastAPI(
    title="CheapFood Menu Scraper",
    description="Microservice that scrapes restaurant menus and returns structured JSON",
    version="0.1.0",
)


@app.post("/scrape", response_model=ScrapeResponse)
async def scrape_endpoint(request: ScrapeRequest) -> ScrapeResponse:
    """Scrape a restaurant menu from the given URL."""
    start: float = time.monotonic()
    try:
        result = await scrape_menu(
            url=str(request.url),
            timeout=request.timeout,
            download_media=request.download_media,
        )
        return ScrapeResponse(
            success=True,
            data=result,
            elapsed_seconds=round(time.monotonic() - start, 3),
        )
    except Exception as exc:
        return ScrapeResponse(
            success=False,
            error=str(exc),
            elapsed_seconds=round(time.monotonic() - start, 3),
        )


@app.get("/health")
async def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "ok"}
