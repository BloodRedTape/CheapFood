"""Extract menu items from raw HTML using OpenAI."""
from __future__ import annotations

import logging
from pathlib import Path

import trafilatura

from menu_scraper.models.menu import MenuCategory
from menu_scraper.processing.text_extractor import TextMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)


def clean_html(html: str) -> str:
    text = trafilatura.extract(html)
    return text if text else ""


class HtmlMenuExtractor:
    """Extracts menu items from raw HTML — cleans it first, then delegates to TextMenuExtractor."""

    def __init__(self, api_key: str, model: str = "gpt-4o-mini", rpm: int = 500) -> None:
        self._text_extractor = TextMenuExtractor(api_key=api_key, model=model, rpm=rpm)

    async def extract(
        self,
        html: str,
        filename: str | None = None,
        log_dir: Path | None = None,
    ) -> list[MenuCategory]:
        clean_text = clean_html(html)
        if not clean_text.strip():
            logger.info("No text after cleaning HTML")
            return []

        if log_dir is not None and filename is not None:
            stem = Path(filename).stem
            (log_dir / f"{stem}.txt").write_text(clean_text, encoding="utf-8")

        return await self._text_extractor.extract(clean_text, log_dir=log_dir, filename=filename)
