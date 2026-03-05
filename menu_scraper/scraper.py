"""Core scraper: fetches URL with httpx, parses HTML with parsel."""
from __future__ import annotations

import logging
import re
import shutil
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

import httpx
from parsel import Selector

from menu_scraper.models.menu import MediaFile, MenuItem, MenuResult, MenuSourceType
from menu_scraper.processing.html_extractor import HtmlMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)

TEMP_DIR: Path = Path(".run_tree")

MENU_KEYWORDS: set[str] = {
    "menu", "dishes", "appetizer", "starter", "main", "dessert",
    "drink", "beverage", "soup", "salad", "pizza", "pasta",
    "burger", "sandwich", "price", "order",
    "תפריט", "מנות", "מחיר",
}

PRICE_PATTERN: re.Pattern[str] = re.compile(
    r"""
    (?:[\$€£])\s*\d+(?:[.,]\d{1,2})?
    | \d+(?:[.,]\d{1,2})?\s*(?:[\$€£₪])
    | \d+(?:[.,]\d{1,2})?\s*(?:NIS|ש"ח|ILS|EUR|USD)
    """,
    re.VERBOSE | re.IGNORECASE,
)

USER_AGENT: str = "CheapFood Menu Bot/1.0"


def _url_to_dirname(url: str) -> str:
    """Convert URL to a safe directory name."""
    parsed = urlparse(url)
    host: str = parsed.netloc or "unknown"
    path: str = parsed.path.strip("/")
    raw: str = f"{host}_{path}" if path else host
    return re.sub(r"[^a-zA-Z0-9]+", "_", raw).strip("_")


async def scrape_menu(
    url: str,
    timeout: int = 30,
    download_media: bool = True,
) -> MenuResult:
    """Fetch a URL and extract menu data."""
    # Prepare temp dir — delete old, create fresh
    site_dir: Path = TEMP_DIR / _url_to_dirname(url)
    if site_dir.exists():
        shutil.rmtree(site_dir)
    site_dir.mkdir(parents=True, exist_ok=True)

    # Fetch the page
    logger.info("Fetching: %s", url)
    async with httpx.AsyncClient(
        follow_redirects=True,
        timeout=float(timeout),
        headers={"User-Agent": USER_AGENT},
    ) as client:
        response: httpx.Response = await client.get(url)
        response.raise_for_status()

    html: str = response.text
    body: bytes = response.content

    # Save raw response
    (site_dir / "page.html").write_bytes(body)
    (site_dir / "meta.txt").write_text(
        f"url: {str(response.url)}\nstatus: {response.status_code}\n",
        encoding="utf-8",
    )
    logger.info("Saved to %s (%d bytes)", site_dir, len(body))

    # Parse with parsel
    sel: Selector = Selector(text=html)
    base_url: str = str(response.url)

    # Extract text menus
    extractor: HtmlMenuExtractor = HtmlMenuExtractor()
    items: list[MenuItem] = _extract_text_items(sel, extractor)

    # Extract media files (PDF links, menu images)
    media_files: list[MediaFile] = []
    media_files.extend(_extract_pdf_links(sel, base_url))
    media_files.extend(_extract_menu_images(sel, base_url))

    # Determine source type
    source_type: MenuSourceType = MenuSourceType.HTML_TEXT
    if not items and media_files:
        source_type = media_files[0].media_type

    return MenuResult(
        url=url,
        items=items,
        source_type=source_type,
        media_files=media_files,
    )


def _extract_text_items(sel: Selector, extractor: HtmlMenuExtractor) -> list[MenuItem]:
    """Extract menu items from HTML text content."""
    menu_selectors: list[str] = [
        "[class*='menu']", "[id*='menu']",
        "[class*='dish']", "[class*='food']",
        "[class*='price']", "[class*='item']",
        ".product", ".meal",
    ]

    seen_texts: set[str] = set()
    all_items: list[MenuItem] = []

    for css_sel in menu_selectors:
        for element in sel.css(css_sel):
            text: str = " ".join(element.css("::text").getall()).strip()
            if not text or text in seen_texts:
                continue
            if _looks_like_menu(text):
                seen_texts.add(text)
                html_content: str = element.get() or ""
                items = extractor.extract(text=text, html=html_content)
                all_items.extend(items)

    # Tables with price patterns
    for table in sel.css("table"):
        text = " ".join(table.css("::text").getall()).strip()
        if text not in seen_texts and PRICE_PATTERN.search(text):
            seen_texts.add(text)
            items = extractor.extract(text=text, html=table.get() or "")
            all_items.extend(items)

    # Fallback: scan whole body
    if not all_items:
        body_text: str = " ".join(sel.css("body ::text").getall()).strip()
        if PRICE_PATTERN.search(body_text):
            all_items = extractor.extract(text=body_text, html="")

    # Deduplicate
    seen_names: set[str] = set()
    unique: list[MenuItem] = []
    for item in all_items:
        key: str = item.name.lower().strip()
        if key not in seen_names:
            seen_names.add(key)
            unique.append(item)

    return unique


def _extract_pdf_links(sel: Selector, base_url: str) -> list[MediaFile]:
    """Find PDF links that likely contain menus."""
    results: list[MediaFile] = []
    for link in sel.css("a[href$='.pdf'], a[href*='.pdf?']"):
        href: str = link.attrib.get("href", "")
        anchor_text: str = " ".join(link.css("::text").getall()).strip().lower()
        if not href:
            continue
        full_url: str = urljoin(base_url, href)
        combined: str = f"{anchor_text} {href.lower()}"
        if any(kw in combined for kw in MENU_KEYWORDS) or "pdf" in anchor_text:
            results.append(MediaFile(
                original_url=full_url,
                local_path="",
                media_type=MenuSourceType.PDF,
            ))
    return results


def _extract_menu_images(sel: Selector, base_url: str) -> list[MediaFile]:
    """Find images that likely contain menus."""
    results: list[MediaFile] = []
    for img in sel.css("img[src]"):
        src: str = img.attrib.get("src", "")
        alt: str = img.attrib.get("alt", "").lower()
        if not src:
            continue
        full_url: str = urljoin(base_url, src)
        combined: str = f"{alt} {src.lower()}"
        parent_text: str = " ".join(
            img.xpath("ancestor::*[position() <= 3]//text()").getall()
        ).lower()
        if any(kw in combined or kw in parent_text for kw in MENU_KEYWORDS):
            results.append(MediaFile(
                original_url=full_url,
                local_path="",
                media_type=MenuSourceType.IMAGE,
            ))
    return results


def _looks_like_menu(text: str) -> bool:
    """Check if text looks like it contains menu items."""
    text_lower: str = text.lower()
    return any(kw in text_lower for kw in MENU_KEYWORDS) or bool(PRICE_PATTERN.search(text))
