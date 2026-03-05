from __future__ import annotations

from pydantic import BaseModel, Field, HttpUrl

from menu_scraper.models.menu import MenuResult


class ScrapeRequest(BaseModel):
    url: HttpUrl
    use_playwright: bool = False
    timeout: int = Field(default=30, ge=5, le=120)
    download_media: bool = True


class ScrapeResponse(BaseModel):
    success: bool
    data: MenuResult | None = None
    error: str | None = None
    elapsed_seconds: float
