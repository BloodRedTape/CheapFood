"""Core scraper: fetches URL with httpx, crawls subpages, extracts menus via OpenAI/Gemini."""
from __future__ import annotations

import logging
import re
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
from menu_scraper.utils.debug import DebugLogContext
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

    ctx = DebugLogContext(RUN_DIR / _url_to_dirname(url))
    ctx.clear()

    settings = get_settings()

    # Direct PDF link — skip crawl entirely
    if looks_like_pdf(url):
        logger.info("URL is a direct PDF link, skipping crawl: %s", url)
        return await PdfOnlyParser(api_key=settings.openai_api_key, timeout=timeout).parse(
            url=url,
            ctx=ctx,
            on_progress=on_progress,
        )

    # Stage 1: Crawl
    await _progress("Crawling website...")
    crawler = MenuCrawler(timeout=timeout, ctx=ctx.subcontext("scraper"))
    crawl_result = await crawler.crawl(url)

    # Stage 2: Detect site type
    main_html = crawl_result.pending_texts[0][0] if crawl_result.pending_texts else ""
    site_type = detect_site_type(main_html)
    logger.info("Detected site type: %s", site_type.value)
    await _progress(f"Detected site type: {site_type.value}")

    # Stage 3: Parse
    if site_type == SiteType.CHOICEQR:
        return ChoiceQrParser().parse(crawl_result.pending_texts, ctx=ctx.subcontext("scraper"))

    # Generic: LLM-based extraction
    return await GenericParser(api_key=settings.openai_api_key, timeout=timeout).parse(
        crawl_result=crawl_result,
        site_url=url,
        ctx=ctx,
        on_progress=on_progress,
    )
