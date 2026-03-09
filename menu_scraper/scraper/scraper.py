"""Core scraper: fetches URL with httpx, crawls subpages, extracts menus via OpenAI/Gemini."""
from __future__ import annotations

import asyncio
import logging
import re
import shutil
from collections.abc import Callable, Coroutine
from pathlib import Path
from urllib.parse import urlparse

from menu_scraper.config import get_settings
from menu_scraper.models.menu import (
    MenuCategory,
    RestaurantInfo,
)
from menu_scraper.parsers.choiceqr_parser import ChoiceQrParser
from menu_scraper.scraper.crawler import MenuCrawler
from menu_scraper.utils.media_handler import looks_like_pdf
from menu_scraper.parsers.generic_parser import GenericParser
from menu_scraper.parsers.pdf_only_parser import PdfOnlyParser
from menu_scraper.scraper.site_detector import SiteType, detect_site_type

logger: logging.Logger = logging.getLogger(__name__)

RUN_DIR: Path = Path(".run_tree")

USER_AGENT: str = "MenuScraper/1.0"


def _url_to_dirname(url: str) -> str:
    """Convert URL to a safe directory name."""
    parsed = urlparse(url)
    host: str = parsed.netloc or "unknown"
    path: str = parsed.path.strip("/")
    raw: str = f"{host}_{path}" if path else host
    return re.sub(r"[^a-zA-Z0-9]+", "_", raw).strip("_")


ProgressCallback = Callable[[str], Coroutine[None, None, None]]


async def scrape_menu(
    url: str,
    timeout: int = 30,
    download_media: bool = True,
    on_progress: ProgressCallback | None = None,
) -> tuple[list[MenuCategory], RestaurantInfo]:
    async def _progress(msg: str) -> None:
        if on_progress:
            await on_progress(msg)

    site_dir: Path = RUN_DIR / _url_to_dirname(url)

    if site_dir.exists():
        await asyncio.to_thread(shutil.rmtree, site_dir)

    scraper_dir: Path = site_dir / "scraper"
    html_extractor_dir: Path = site_dir / "html_extractor"
    pdf_extractor_dir: Path = site_dir / "pdf_extractor"
    enhancer_dir: Path = site_dir / "enhancer"
    restaurant_info_dir: Path = site_dir / "restaurant_info"

    for d in (scraper_dir, html_extractor_dir, pdf_extractor_dir, enhancer_dir, restaurant_info_dir):
        await asyncio.to_thread(d.mkdir, parents=True, exist_ok=True)

    settings = get_settings()

    # Direct PDF link — skip crawl entirely
    if looks_like_pdf(url):
        logger.info("URL is a direct PDF link, skipping crawl: %s", url)
        return await PdfOnlyParser(api_key=settings.openai_api_key, timeout=timeout).parse(
            url=url,
            pdf_extractor_dir=pdf_extractor_dir,
            enhancer_dir=enhancer_dir,
            on_progress=on_progress,
        )

    # Stage 1: Crawl
    await _progress("Crawling website...")
    crawler = MenuCrawler(timeout=timeout, log_dir=scraper_dir)
    crawl_result = await crawler.crawl(url)

    # Stage 2: Detect site type
    main_html = crawl_result.pending_texts[0][0] if crawl_result.pending_texts else ""
    site_type = detect_site_type(main_html)
    logger.info("Detected site type: %s", site_type.value)
    await _progress(f"Detected site type: {site_type.value}")

    # Stage 3: Parse
    if site_type == SiteType.CHOICEQR:
        return ChoiceQrParser().parse(crawl_result.pending_texts, log_dir=scraper_dir)

    # Generic: LLM-based extraction
    return await GenericParser(api_key=settings.openai_api_key, timeout=timeout).parse(
        crawl_result=crawl_result,
        site_url=url,
        log_dir=scraper_dir,
        html_extractor_dir=html_extractor_dir,
        pdf_extractor_dir=pdf_extractor_dir,
        enhancer_dir=enhancer_dir,
        restaurant_info_dir=restaurant_info_dir,
        on_progress=on_progress,
    )
