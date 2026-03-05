from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE: Path = Path(__file__).resolve().parent / ".env"


class ScraperSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="SCRAPER_", env_file=_ENV_FILE)

    host: str = "0.0.0.0"
    port: int = 8000
    media_dir: str = "./media"
    log_level: str = "DEBUG"

    concurrent_requests: int = 4
    download_delay: float = 1.0
    user_agent: str = "MenuScraper/1.0"

    playwright_enabled: bool = True

    gemini_api_key: str = ""


def get_settings() -> ScraperSettings:
    return ScraperSettings()
