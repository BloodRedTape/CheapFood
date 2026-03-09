"""Generic menu parser: PDF + HTML pages → LLM extraction."""
from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable, Coroutine
from pathlib import Path

import httpx

from menu_scraper.models.menu import MediaFile, MenuCategory, MenuSourceType
from menu_scraper.processing.crawler import CrawlResult, download_pdf
from menu_scraper.processing.html_extractor import HtmlMenuExtractor
from menu_scraper.processing.menu_enhancer import MenuEnhancer
from menu_scraper.processing.pdf_extractor import PdfMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)

USER_AGENT: str = "MenuScraper/1.0"

ProgressCallback = Callable[[str], Coroutine[None, None, None]]


class GenericParser:
    def __init__(
        self,
        html_extractor: HtmlMenuExtractor,
        pdf_extractor: PdfMenuExtractor,
        menu_enhancer: MenuEnhancer,
        timeout: int = 30,
    ) -> None:
        self.html_extractor = html_extractor
        self.pdf_extractor = pdf_extractor
        self.menu_enhancer = menu_enhancer
        self.timeout = timeout

    async def parse(
        self,
        crawl_result: CrawlResult,
        log_dir: Path,
        html_extractor_dir: Path,
        pdf_extractor_dir: Path,
        enhancer_dir: Path,
        on_progress: ProgressCallback | None = None,
    ) -> list[MenuCategory]:
        async def _progress(msg: str) -> None:
            if on_progress:
                await on_progress(msg)

        pending_texts = crawl_result.pending_texts
        all_media = crawl_result.media_files

        # Download PDFs in parallel
        pdf_media: list[MediaFile] = [m for m in all_media if m.media_type == MenuSourceType.PDF]
        pdf_results: list[tuple[bytes, Path] | None] = []
        if pdf_media:
            await _progress(f"Downloading {len(pdf_media)} PDF file(s)...")
            async with httpx.AsyncClient(
                follow_redirects=True,
                timeout=float(self.timeout),
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

        async def _extract_pdf(media_file: MediaFile, pdf_result: tuple[bytes, Path] | None) -> list[MenuCategory]:
            if pdf_result is None:
                return []
            pdf_data, local_path = pdf_result
            media_file.local_path = str(local_path)
            logger.info("LLM: processing PDF %s", media_file.original_url)
            items = await self.pdf_extractor.extract(
                pdf_data, source_url=media_file.original_url, log_dir=pdf_extractor_dir,
            )
            logger.info("LLM: done PDF %s — found %d categories", media_file.original_url, len(items))
            return items

        async def _extract_html(html: str, html_filename: str) -> list[MenuCategory]:
            logger.info("LLM: processing HTML %s", html_filename)
            items = await self.html_extractor.extract(html, filename=html_filename, log_dir=html_extractor_dir)
            logger.info("LLM: done HTML %s — found %d categories", html_filename, len(items))
            return items

        if total > 0:
            await _progress(f"Extracting menu from {total} sources...")

        pdf_extract_tasks = [_tracked(_extract_pdf(mf, res), mf.original_url) for mf, res in zip(pdf_media, pdf_results)]
        html_extract_tasks = [_tracked(_extract_html(html, fname), fname) for html, fname in pending_texts]
        all_results = await asyncio.gather(*pdf_extract_tasks, *html_extract_tasks)

        all_categories: list[MenuCategory] = []
        for categories in all_results:
            all_categories.extend(categories)

        # Merge categories with same name, deduplicate items by name
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
        return await self.menu_enhancer.enhance(result, on_progress=on_progress, log_dir=enhancer_dir)
