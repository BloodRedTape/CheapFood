"""Core scraper: fetches URL with httpx, crawls subpages, extracts menus via OpenAI/Gemini."""
from __future__ import annotations

import asyncio
import logging
import re
import shutil
from collections.abc import Callable, Coroutine
from pathlib import Path
from urllib.parse import urlparse

import httpx

from menu_scraper.config import get_settings
from menu_scraper.models.menu import (
    MediaFile,
    MenuCategory,
    MenuSourceType,
)
from menu_scraper.processing.crawler import MenuCrawler, _looks_like_pdf, download_pdf
from menu_scraper.processing.html_extractor import HtmlMenuExtractor
from menu_scraper.processing.image_extractor import ImageMenuExtractor
from menu_scraper.processing.menu_enhancer import MenuEnhancer
from menu_scraper.processing.pdf_extractor import PdfMenuExtractor

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
) -> list[MenuCategory]:
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

    for d in (scraper_dir, html_extractor_dir, pdf_extractor_dir, enhancer_dir):
        await asyncio.to_thread(d.mkdir, parents=True, exist_ok=True)

    settings = get_settings()
    html_extractor = HtmlMenuExtractor(api_key=settings.openai_api_key)
    pdf_extractor = PdfMenuExtractor(api_key=settings.openai_api_key)
    menu_enhancer = MenuEnhancer(api_key=settings.openai_api_key)

    # Если URL ведёт напрямую на PDF — скачиваем и обрабатываем без краулинга
    if _looks_like_pdf(url):
        logger.info("URL is a direct PDF link, skipping crawl: %s", url)
        await _progress("Downloading PDF...")
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(timeout),
            headers={"User-Agent": USER_AGENT},
        ) as client:
            pdf_result = await download_pdf(client, url, pdf_extractor_dir)
        if not pdf_result:
            return []
        pdf_data, _ = pdf_result
        await _progress("Extracting menu from PDF...")
        result = await pdf_extractor.extract(pdf_data, source_url=url, log_dir=pdf_extractor_dir)
        await _progress("Enhancing menu...")
        return await menu_enhancer.enhance(result, on_progress=on_progress, log_dir=enhancer_dir)

    await _progress("Crawling website...")
    crawler = MenuCrawler(timeout=timeout, log_dir=scraper_dir)
    crawl_result = await crawler.crawl(url)
    pending_texts = crawl_result.pending_texts
    all_media = crawl_result.media_files

    all_categories: list[MenuCategory] = []

    async def _extract_pdf(media_file: MediaFile, pdf_result: tuple[bytes, Path] | None) -> list[MenuCategory]:
        if pdf_result is None:
            return []
        pdf_data, local_path = pdf_result
        media_file.local_path = str(local_path)
        logger.info("LLM: processing PDF %s", media_file.original_url)
        items = await pdf_extractor.extract(
            pdf_data, source_url=media_file.original_url, log_dir=pdf_extractor_dir,
        )
        logger.info("LLM: done PDF %s — found %d categories", media_file.original_url, len(items))
        return items

    async def _extract_html(html: str, html_filename: str) -> list[MenuCategory]:
        logger.info("LLM: processing HTML %s", html_filename)
        items = await html_extractor.extract(html, filename=html_filename, log_dir=html_extractor_dir)
        logger.info("LLM: done HTML %s — found %d categories", html_filename, len(items))
        return items

    # Скачиваем PDF-файлы параллельно
    pdf_media: list[MediaFile] = [m for m in all_media if m.media_type == MenuSourceType.PDF]
    pdf_results: list[tuple[bytes, Path] | None] = []
    if pdf_media:
        await _progress(f"Downloading {len(pdf_media)} PDF file(s)...")
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(timeout),
            headers={"User-Agent": USER_AGENT},
        ) as pdf_client:
            pdf_dl_tasks = [download_pdf(pdf_client, m.original_url, pdf_extractor_dir) for m in pdf_media]
            pdf_results = list(await asyncio.gather(*pdf_dl_tasks))

    total = len(pdf_media) + len(pending_texts)
    completed = 0

    async def _tracked(coro: Coroutine[None, None, list[MenuCategory]], label: str) -> list[MenuCategory]:
        nonlocal completed
        result = await coro
        completed += 1
        await _progress(f"Extracted menu from ({completed}/{total})")
        return result

    if total > 0:
        await _progress(f"Extracting menu from {total} sources...")

    pdf_extract_tasks = [_tracked(_extract_pdf(mf, res), mf.original_url) for mf, res in zip(pdf_media, pdf_results)]
    html_extract_tasks = [_tracked(_extract_html(html, fname), fname) for html, fname in pending_texts]
    all_results = await asyncio.gather(*pdf_extract_tasks, *html_extract_tasks)
    for categories in all_results:
        all_categories.extend(categories)

    # Слияние категорий с одинаковым именем + дедупликация блюд по имени
    merged: dict[str | None, list] = {}
    seen_item_names: set[str] = set()
    for category in all_categories:
        key = category.name.strip().lower() if category.name else None
        if key not in merged:
            merged[key] = []
        for item in category.items:
            item_key = item.name.lower().strip()
            if item_key not in seen_item_names:
                seen_item_names.add(item_key)
                merged[key].append(item)

    result = [
        MenuCategory(name=name, items=items)
        for name, items in merged.items()
        if items
    ]
    await _progress("Enhancing menu...")
    return await menu_enhancer.enhance(result, on_progress=on_progress, log_dir=enhancer_dir)

