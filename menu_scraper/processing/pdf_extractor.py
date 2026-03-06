"""Extract menu items from PDF files using pymupdf4llm + OpenAI text extraction."""
from __future__ import annotations

import asyncio
import hashlib
import logging
from pathlib import Path

import pymupdf  # type: ignore[import-untyped]
import pymupdf4llm  # type: ignore[import-untyped]

from menu_scraper.models.menu import MenuCategory
from menu_scraper.processing.text_extractor import TextMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)


def _pdf_pages_to_markdown(pdf_data: bytes) -> list[str]:
    """Convert each PDF page to a Markdown string. Returns list indexed by page number."""
    doc = pymupdf.open(stream=pdf_data, filetype="pdf")
    pages: list[str] = []
    for page_num in range(len(doc)):
        md: str = str(pymupdf4llm.to_markdown(doc, pages=[page_num]))
        pages.append(md)
    doc.close()
    return pages


class PdfMenuExtractor:
    """Extracts menu items from PDF files.

    Converts each PDF page to Markdown via pymupdf4llm, then sends pages
    to TextMenuExtractor in parallel and merges results.
    """

    def __init__(self, api_key: str, model: str = "gpt-4.1-mini", rpm: int = 500) -> None:
        self._text_extractor = TextMenuExtractor(api_key=api_key, model=model, rpm=rpm)

    async def extract(
        self,
        pdf_data: bytes,
        source_url: str,
        log_dir: Path | None = None,
    ) -> list[MenuCategory]:
        logger.info("Converting PDF to markdown by page: %s", source_url)
        pages = await asyncio.to_thread(_pdf_pages_to_markdown, pdf_data)
        pages = [p for p in pages if p.strip()]

        if not pages:
            logger.warning("PDF yielded no text: %s", source_url)
            return []

        logger.info("PDF has %d non-empty pages (%s)", len(pages), source_url)

        url_hash = hashlib.md5(source_url.encode()).hexdigest()[:10]

        async def _extract_page(page_text: str, page_num: int) -> list[MenuCategory]:
            filename: str | None = None
            if log_dir is not None:
                filename = f"pdf_{url_hash}_p{page_num}.md"
                (log_dir / filename).write_text(page_text, encoding="utf-8")
            logger.info("LLM: processing PDF page %d/%d", page_num + 1, len(pages))
            result = await self._text_extractor.extract(page_text, log_dir=log_dir, filename=filename)
            logger.info("LLM: done PDF page %d/%d — found %d categories", page_num + 1, len(pages), len(result))
            return result

        page_results = await asyncio.gather(*[_extract_page(p, i) for i, p in enumerate(pages)])

        all_categories: list[MenuCategory] = []
        for cats in page_results:
            all_categories.extend(cats)
        return all_categories
