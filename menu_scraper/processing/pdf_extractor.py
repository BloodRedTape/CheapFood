"""Extract menu items from PDF files using pymupdf4llm + OpenAI text extraction."""
from __future__ import annotations

import asyncio
import logging
from pathlib import Path

import pymupdf  # type: ignore[import-untyped]
import pymupdf4llm  # type: ignore[import-untyped]

from menu_scraper.models.menu import MenuCategory
from menu_scraper.processing.text_extractor import TextMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)


def _pdf_bytes_to_markdown(pdf_data: bytes) -> str:
    """Convert PDF bytes to Markdown text using pymupdf4llm."""
    doc = pymupdf.open(stream=pdf_data, filetype="pdf")
    md_text: str = str(pymupdf4llm.to_markdown(doc))
    doc.close()
    return md_text


class PdfMenuExtractor:
    """Extracts menu items from PDF files.

    Converts PDF to Markdown via pymupdf4llm, then delegates to TextMenuExtractor.
    """

    def __init__(self, api_key: str, model: str = "gpt-4o-mini", rpm: int = 500) -> None:
        self._text_extractor = TextMenuExtractor(api_key=api_key, model=model, rpm=rpm)

    async def extract(
        self,
        pdf_data: bytes,
        source_url: str,
        log_dir: Path | None = None,
    ) -> list[MenuCategory]:
        logger.info("Converting PDF to markdown: %s", source_url)
        md_text = await asyncio.to_thread(_pdf_bytes_to_markdown, pdf_data)

        if not md_text.strip():
            logger.warning("PDF yielded no text: %s", source_url)
            return []

        logger.info("PDF markdown length: %d chars (%s)", len(md_text), source_url)

        filename: str | None = None
        if log_dir is not None:
            import hashlib
            url_hash = hashlib.md5(source_url.encode()).hexdigest()[:10]
            filename = f"pdf_{url_hash}.md"
            (log_dir / filename).write_text(md_text, encoding="utf-8")

        return await self._text_extractor.extract(md_text, log_dir=log_dir, filename=filename)
