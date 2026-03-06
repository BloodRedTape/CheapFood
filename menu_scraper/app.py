from __future__ import annotations

import logging

from fastapi import FastAPI

from menu_scraper.models.menu import MenuCategory
from menu_scraper.models.requests import ScrapeRequest
from menu_scraper.scraper import scrape_menu

logging.basicConfig(level=logging.INFO)

app: FastAPI = FastAPI(
    title="CheapFood Menu Scraper",
    description="Microservice that scrapes restaurant menus and returns structured JSON",
    version="0.1.0",
)


@app.post("/scrape", response_model=list[MenuCategory])
async def scrape_endpoint(request: ScrapeRequest) -> list[MenuCategory]:
    """Scrape a restaurant menu from the given URL."""
    return await scrape_menu(
        url=str(request.url),
        timeout=request.timeout,
        download_media=request.download_media,
    )


@app.get("/health")
async def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "ok"}
