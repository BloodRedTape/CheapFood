from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class AppSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CHEAPFOOD_", env_file=".env")

    host: str = "0.0.0.0"
    port: int = 8000
    media_dir: str = "./media"
    log_level: str = "DEBUG"

    scrapy_concurrent_requests: int = 4
    scrapy_download_delay: float = 1.0
    scrapy_user_agent: str = "CheapFood Menu Bot/1.0"

    playwright_enabled: bool = True

    gemini_api_key: str = ""


def get_settings() -> AppSettings:
    return AppSettings()
