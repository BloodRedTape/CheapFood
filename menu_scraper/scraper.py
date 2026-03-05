"""Core scraper: fetches URL with httpx, crawls subpages, parses HTML with parsel."""
from __future__ import annotations

import hashlib
import logging
import re
import shutil
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx
from parsel import Selector

from menu_scraper.models.menu import (
    MediaFile,
    MenuItem,
    MenuResult,
    MenuSourceType,
)
from menu_scraper.processing.html_extractor import HtmlMenuExtractor

logger: logging.Logger = logging.getLogger(__name__)

RUN_DIR: Path = Path(".run_tree")
MAX_DEPTH: int = 2
MAX_PAGES: int = 20

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

USER_AGENT: str = "MenuScraper/1.0"


def _url_to_dirname(url: str) -> str:
    """Convert URL to a safe directory name."""
    parsed = urlparse(url)
    host: str = parsed.netloc or "unknown"
    path: str = parsed.path.strip("/")
    raw: str = f"{host}_{path}" if path else host
    return re.sub(r"[^a-zA-Z0-9]+", "_", raw).strip("_")


def _url_to_filename(url: str) -> str:
    """Convert URL to a safe filename for saving HTML."""
    url_hash: str = hashlib.md5(url.encode()).hexdigest()[:10]
    parsed = urlparse(url)
    path: str = parsed.path.strip("/").replace("/", "_") or "index"
    safe: str = re.sub(r"[^a-zA-Z0-9_]", "", path)[:60]
    return f"{safe}_{url_hash}.html"


def _same_domain(url: str, base_url: str) -> bool:
    """Check if url belongs to the same domain as base_url."""
    return urlparse(url).netloc == urlparse(base_url).netloc


def _find_subpage_links(sel: Selector, base_url: str) -> list[str]:
    """Find links on the page that likely lead to menu-related subpages."""
    links: list[str] = []
    for a in sel.css("a[href]"):
        href: str = a.attrib.get("href", "").strip()
        if not href or href.startswith(("#", "mailto:", "tel:", "javascript:")):
            continue
        full_url: str = urljoin(base_url, href)
        if not _same_domain(full_url, base_url):
            continue
        # Strip fragment
        full_url = full_url.split("#")[0]
        anchor_text: str = " ".join(a.css("::text").getall()).strip().lower()
        combined: str = f"{anchor_text} {full_url.lower()}"
        if any(kw in combined for kw in MENU_KEYWORDS):
            links.append(full_url)
    return links


async def _fetch_page(
    client: httpx.AsyncClient,
    url: str,
    site_dir: Path,
    depth: int,
) -> tuple[str, str] | None:
    """Fetch a single page and save it to disk. Returns (html, resolved_url) or None."""
    try:
        response: httpx.Response = await client.get(url)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("Failed to fetch %s: %s", url, exc)
        return None

    content_type: str = response.headers.get("content-type", "")
    if "text/html" not in content_type:
        return None

    html: str = response.text
    filename: str = _url_to_filename(str(response.url))
    local_path: Path = site_dir / filename
    local_path.write_text(html, encoding="utf-8")
    logger.info("Saved page [depth=%d]: %s -> %s", depth, response.url, filename)

    return html, str(response.url)


async def scrape_menu(
    url: str,
    timeout: int = 30,
    download_media: bool = True,
) -> MenuResult:
    """Fetch a URL, crawl subpages, and extract menu data."""
    site_dir: Path = RUN_DIR / _url_to_dirname(url)
    if site_dir.exists():
        shutil.rmtree(site_dir)
    site_dir.mkdir(parents=True, exist_ok=True)

    extractor: HtmlMenuExtractor = HtmlMenuExtractor()
    all_items: list[MenuItem] = []
    all_media: list[MediaFile] = []
    visited: set[str] = set()

    # BFS queue: (url, depth)
    queue: list[tuple[str, int]] = [(url, 0)]

    async with httpx.AsyncClient(
        follow_redirects=True,
        timeout=float(timeout),
        headers={"User-Agent": USER_AGENT},
    ) as client:
        while queue and len(visited) < MAX_PAGES:
            current_url, depth = queue.pop(0)
            if current_url in visited:
                continue
            visited.add(current_url)

            result = await _fetch_page(client, current_url, site_dir, depth)
            if result is None:
                continue

            html, page_url = result

            sel: Selector = Selector(text=html)
            page_base: str = page_url

            # Extract menu items
            items: list[MenuItem] = _extract_text_items(sel, extractor)
            all_items.extend(items)

            # Collect media references
            all_media.extend(_extract_pdf_links(sel, page_base))
            all_media.extend(_extract_menu_images(sel, page_base))

            # Discover subpage links
            if depth < MAX_DEPTH:
                for link in _find_subpage_links(sel, page_base):
                    if link not in visited:
                        queue.append((link, depth + 1))

    # Deduplicate items
    seen_names: set[str] = set()
    unique_items: list[MenuItem] = []
    for item in all_items:
        key: str = item.name.lower().strip()
        if key not in seen_names:
            seen_names.add(key)
            unique_items.append(item)

    # Deduplicate media by URL
    seen_urls: set[str] = set()
    unique_media: list[MediaFile] = []
    for mf in all_media:
        if mf.original_url not in seen_urls:
            seen_urls.add(mf.original_url)
            unique_media.append(mf)

    source_type: MenuSourceType = MenuSourceType.HTML_TEXT
    if not unique_items and unique_media:
        source_type = unique_media[0].media_type

    return MenuResult(
        url=url,
        items=unique_items,
        source_type=source_type,
        media_files=unique_media,
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

    return all_items


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
