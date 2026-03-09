"""Extract menu items from raw HTML using OpenAI."""
from __future__ import annotations

import asyncio
import logging
import re
from pathlib import Path

from bs4 import BeautifulSoup, Tag

from menu_scraper.models.menu import MenuCategory
from menu_scraper.common.text_extractor import TextMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)

MAX_CHUNK_CHARS: int = 4_000
MAX_CHUNK_HARD_LIMIT: int = 6_000

_HEADING_PATTERNS: tuple[str, ...] = (
    r"(?=^# )",
    r"(?=^## )",
    r"(?=^### )",
    r"(?=^#### )",
)

_JUNK_TAGS: tuple[str, ...] = (
    "script", "style", "noscript", "head",
    "nav", "footer", "header", "aside", "iframe",
)

_HEADING_MAP: dict[str, str] = {
    "h1": "#", "h2": "##", "h3": "###",
    "h4": "####", "h5": "#####", "h6": "######",
}

_BLOCK_TAGS: frozenset[str] = frozenset({
    "h1", "h2", "h3", "h4", "h5", "h6",
    "p", "li", "td", "th", "dt", "dd",
})

# div/span are leaf-collected separately: only if they contain no nested block elements
_DIV_LIKE: frozenset[str] = frozenset({"div", "span", "section", "article"})


def extract_page_title(html: str) -> str | None:
    soup = BeautifulSoup(html, "lxml")
    title_tag = soup.find("title")
    if title_tag:
        return title_tag.get_text(strip=True) or None
    return None


def clean_html(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")

    for tag in soup(_JUNK_TAGS):
        tag.decompose()

    lines: list[str] = []
    body = soup.body or soup

    for el in body.descendants:
        if not isinstance(el, Tag):
            continue
        name = el.name

        if name in _HEADING_MAP:
            text = el.get_text(" ", strip=True)
            if text:
                lines.append(f"{_HEADING_MAP[name]} {text}")

        elif name in _BLOCK_TAGS and not el.find(_BLOCK_TAGS):
            # leaf block — no child block elements, no text duplication
            text = el.get_text(" ", strip=True)
            if text:
                lines.append(text)

        elif name in _DIV_LIKE and not el.find(_BLOCK_TAGS | _DIV_LIKE):
            # leaf div/span — contains only inline text, no nested blocks
            text = el.get_text(" ", strip=True)
            if text:
                lines.append(text)

    return "\n".join(lines)


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
        page_title = extract_page_title(html)
        clean_text = clean_html(html)
        if not clean_text.strip():
            logger.info("No text after cleaning HTML")
            return []

        if log_dir is not None and filename is not None:
            stem = Path(filename).stem
            (log_dir / f"{stem}.txt").write_text(clean_text, encoding="utf-8")

        MAX_CHUNKS: int = 10
        chunks = _split_chunks(clean_text, MAX_CHUNK_CHARS)
        if len(chunks) > MAX_CHUNKS:
            logger.error(
                "SKIPPING page — too large: %d chunks (file=%s, total=%dchars)",
                len(chunks),
                filename,
                len(clean_text),
            )
            return []

        oversized = [i for i, c in enumerate(chunks) if len(c) > MAX_CHUNK_HARD_LIMIT]
        if oversized:
            logger.error(
                "SKIPPING page — chunks exceed hard limit of %d chars (file=%s, chunks=%s)",
                MAX_CHUNK_HARD_LIMIT,
                filename,
                [f"#{i}:{len(chunks[i])}chars" for i in oversized],
            )
            return []

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
                    page_title=page_title,
                    log_dir=log_dir,
                    filename=f"{stem}.chunk{i}.md" if stem else None,
                )
                for i, chunk in enumerate(chunks)
            ])
            return [cat for cats in chunk_results for cat in cats]

        return await self._text_extractor.extract(clean_text, page_title=page_title, log_dir=log_dir, filename=filename)
