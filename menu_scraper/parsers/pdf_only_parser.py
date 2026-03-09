"""Parser for direct PDF links — skips crawling entirely."""
from __future__ import annotations

import logging
from collections.abc import Callable, Coroutine
from pathlib import Path

import httpx

from menu_scraper.models.menu import MenuCategory, RestaurantInfo
from menu_scraper.utils.media_handler import download_pdf
from menu_scraper.common.pdf_extractor import PdfMenuExtractor
from menu_scraper.common.menu_enhancer import MenuEnhancer

logger: logging.Logger = logging.getLogger(__name__)

USER_AGENT: str = "MenuScraper/1.0"

ProgressCallback = Callable[[str], Coroutine[None, None, None]]


class PdfOnlyParser:
    def __init__(self, api_key: str, timeout: int = 30) -> None:
        self.pdf_extractor = PdfMenuExtractor(api_key=api_key)
        self.menu_enhancer = MenuEnhancer(api_key=api_key)
        self.timeout = timeout

    async def parse(
        self,
        url: str,
        pdf_extractor_dir: Path,
        enhancer_dir: Path,
        on_progress: ProgressCallback | None = None,
    ) -> tuple[list[MenuCategory], RestaurantInfo]:
        async def _progress(msg: str) -> None:
            if on_progress:
                await on_progress(msg)

        await _progress("Downloading PDF...")
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(self.timeout),
            headers={"User-Agent": USER_AGENT},
        ) as client:
            pdf_result = await download_pdf(client, url, pdf_extractor_dir)

        if not pdf_result:
            return [], RestaurantInfo()

        pdf_data, _ = pdf_result
        await _progress("Extracting menu from PDF...")
        categories = await self.pdf_extractor.extract(pdf_data, source_url=url, log_dir=pdf_extractor_dir)
        await _progress("Enhancing menu...")
        categories = await self.menu_enhancer.enhance(categories, on_progress=on_progress, log_dir=enhancer_dir)
        return categories, RestaurantInfo()
