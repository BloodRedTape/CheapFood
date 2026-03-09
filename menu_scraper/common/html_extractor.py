"""Extract menu items from raw HTML using OpenAI."""
from __future__ import annotations

import asyncio
import logging
import re
from pathlib import Path

import trafilatura

from menu_scraper.models.menu import MenuCategory
from menu_scraper.common.text_extractor import TextMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)

MAX_CHUNK_CHARS: int = 4_000

_HEADING_PATTERNS: tuple[str, ...] = (
    r"(?=^# )",
    r"(?=^## )",
    r"(?=^### )",
    r"(?=^#### )",
)


def clean_html(html: str) -> str:
    text = trafilatura.extract(html, output_format="markdown", include_formatting=True)
    if not text:
        return ""
    # Keep headings (#, ##, etc.) but strip bold/italic markers
    text = re.sub(r"\*{1,3}(.+?)\*{1,3}", r"\1", text)
    text = re.sub(r"\n{2,}", "\n", text)
    return text


def _split_chunks(text: str, max_chars: int, pattern_index: int = 0) -> list[str]:
    """Recursively split markdown into chunks under max_chars.

    Splits by heading level # → ## → ### → ####. If a chunk still exceeds
    max_chars, recurses with the next heading level. If no separators remain,
    returns the chunk as-is.
    """
    if len(text) <= max_chars:
        return [text]

    if pattern_index >= len(_HEADING_PATTERNS):
        # Fallback: split roughly in half on a newline boundary
        mid = len(text) // 2
        split_pos = text.rfind("\n", 0, mid)
        if split_pos == -1:
            split_pos = text.find("\n", mid)
        if split_pos == -1:
            return [text]
        left, right = text[:split_pos].strip(), text[split_pos:].strip()
        return (
            _split_chunks(left, max_chars, pattern_index)
            + _split_chunks(right, max_chars, pattern_index)
        )


    sections = [s for s in re.split(_HEADING_PATTERNS[pattern_index], text, flags=re.MULTILINE) if s.strip()]
    if len(sections) <= 1:
        return _split_chunks(text, max_chars, pattern_index + 1)

    chunks: list[str] = []
    current = ""
    for section in sections:
        if current and len(current) + len(section) > max_chars:
            chunks.extend(_split_chunks(current.strip(), max_chars, pattern_index + 1))
            current = section
        else:
            current += section
    if current.strip():
        chunks.extend(_split_chunks(current.strip(), max_chars, pattern_index + 1))
    return chunks


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

        chunks = _split_chunks(clean_text, MAX_CHUNK_CHARS)
        if len(chunks) > 1:
            logger.info(
                "HTML text split into %d chunks (file=%s, total=%dchars): %s",
                len(chunks),
                filename,
                len(clean_text),
                [f"{len(c)}chars" for c in chunks],
            )
            stem = Path(filename).stem if filename else None
            chunk_results = await asyncio.gather(*[
                self._text_extractor.extract(
                    chunk,
                    log_dir=log_dir,
                    filename=f"{stem}.chunk{i}.md" if stem else None,
                )
                for i, chunk in enumerate(chunks)
            ])
            return [cat for cats in chunk_results for cat in cats]

        return await self._text_extractor.extract(clean_text, log_dir=log_dir, filename=filename)
