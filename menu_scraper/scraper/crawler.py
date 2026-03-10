"""Web crawler: fetches and traverses pages BFS-style, collects HTML and media links."""
from __future__ import annotations

import asyncio
import hashlib
import logging
import re
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlparse

import httpx
from parsel import Selector

from menu_scraper.models.menu import MediaFile, MenuSourceType
from menu_scraper.utils.media_handler import looks_like_pdf
from menu_scraper.utils.debug import DebugLogContext

logger: logging.Logger = logging.getLogger(__name__)

MAX_DEPTH: int = 3
MAX_PAGES: int = 40
USER_AGENT: str = "MenuScraper/1.0"

MENU_KEYWORDS: set[str] = {
    "menu", "dishes", "appetizer", "starter", "main", "dessert",
    "drink", "beverage", "soup", "salad", "pizza", "pasta",
    "burger", "sandwich", "price", "order",
    "תפריט", "מנות", "מחיר",
    # Czech/Slovak
    "jidelni", "jídelní", "listek", "lístek", "napoje", "napojovy", "nápojový",
    "steaky", "jidlo", "jídlo", "poledni", "polední",
}

_NOISE_SEGMENTS: frozenset[str] = frozenset({
    "galerie", "gallery", "o-nas", "about", "kontakt", "contact",
    "partneri", "partners", "aktuality", "news", "blog",
    "karriera", "kariera", "jobs", "career",
    "obchodni-podminky", "gdpr", "cookies",
})


@dataclass
class CrawlResult:
    pending_texts: list[tuple[str, str]] = field(default_factory=list)
    media_files: list[MediaFile] = field(default_factory=list)


class MenuCrawler:
    def __init__(self, timeout: int = 30, ctx: DebugLogContext | None = None) -> None:
        self.timeout = timeout
        self._ctx = ctx

    async def crawl(self, url: str) -> CrawlResult:
        visited: set[str] = {url}
        current_urls: list[str] = [url]
        pending_texts: list[tuple[str, str]] = []
        all_media: list[MediaFile] = []

        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(self.timeout),
            headers={"User-Agent": USER_AGENT},
        ) as client:
            for depth in range(MAX_DEPTH + 1):
                if not current_urls or len(visited) >= MAX_PAGES:
                    break

                tasks = [self._process_url(client, u, depth) for u in current_urls]
                results = await asyncio.gather(*tasks)

                next_urls: list[str] = []
                next_seen: set[str] = set()
                for res in results:
                    if not res:
                        continue
                    html, html_filename, media, links = res
                    if html.strip():
                        pending_texts.append((html, html_filename))
                    all_media.extend(media)

                    for link in links:
                        if link not in visited and link not in next_seen and len(visited) + len(next_urls) < MAX_PAGES:
                            visited.add(link)
                            next_seen.add(link)
                            next_urls.append(link)

                current_urls = next_urls

        # Дедупликация медиа
        seen_urls: set[str] = set()
        deduped_media: list[MediaFile] = []
        for mf in all_media:
            if mf.original_url not in seen_urls:
                seen_urls.add(mf.original_url)
                deduped_media.append(mf)

        return CrawlResult(pending_texts=pending_texts, media_files=deduped_media)

    async def _process_url(
        self, client: httpx.AsyncClient, url: str, depth: int
    ) -> tuple[str, str, list[MediaFile], list[str]] | None:
        result = await self._fetch_page(client, url, depth)
        if not result:
            return None

        html, page_url = result
        sel = Selector(text=html)
        html_filename = _url_to_filename(page_url)

        media = _extract_pdf_links(sel, page_url) + _extract_menu_images(sel, page_url)
        sub_links = _find_subpage_links(sel, page_url) if depth < MAX_DEPTH else []

        return html, html_filename, media, sub_links

    async def _fetch_page(
        self, client: httpx.AsyncClient, url: str, depth: int
    ) -> tuple[str, str] | None:
        try:
            response: httpx.Response = await client.get(url)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("Failed to fetch %s: %s", url, exc)
            return None

        if "text/html" not in response.headers.get("content-type", ""):
            return None

        html: str = response.text
        filename = _url_to_filename(str(response.url))
        if self._ctx is not None:
            self._ctx.write_file(filename, html)
        logger.info("Saved page [depth=%d]: %s -> %s", depth, response.url, filename)

        return html, str(response.url)


def _url_to_filename(url: str) -> str:
    url_hash = hashlib.md5(url.encode()).hexdigest()[:10]
    parsed = urlparse(url)
    path = parsed.path.strip("/").replace("/", "_") or "index"
    safe = re.sub(r"[^a-zA-Z0-9_]", "", path)[:60]
    return f"{safe}_{url_hash}.html"


def _link_score(url: str, anchor: str) -> int:
    """Higher score = more likely to contain menu content. Negative = noise."""
    combined = f"{url} {anchor}".lower()
    path_segments = set(urlparse(url).path.strip("/").split("/"))
    if path_segments & _NOISE_SEGMENTS:
        return -1
    score = sum(1 for kw in MENU_KEYWORDS if kw in combined)
    return score


def _find_subpage_links(sel: Selector, base_url: str) -> list[str]:
    seen: set[str] = set()
    scored: list[tuple[int, str]] = []
    base_netloc = urlparse(base_url).netloc

    for a in sel.css("a"):
        href = a.attrib.get("href", "").strip()
        anchor = a.css("::text").get(default="")
        if not href:
            continue
        if href.startswith(("mailto:", "tel:", "javascript:", "#")):
            continue
        full_url = urljoin(base_url, href)
        parsed = urlparse(full_url)
        if parsed.scheme not in ("http", "https"):
            continue
        if parsed.netloc != base_netloc:
            continue
        if full_url in seen:
            continue
        seen.add(full_url)
        score = _link_score(full_url, anchor)
        if score >= 0:
            scored.append((score, full_url))

    # Higher score first — menu-relevant pages visited before noise
    scored.sort(key=lambda x: x[0], reverse=True)
    return [url for _, url in scored]


def _extract_pdf_links(sel: Selector, base_url: str) -> list[MediaFile]:
    results: list[MediaFile] = []
    seen_urls: set[str] = set()
    for link in sel.css("a"):
        href = link.attrib.get("href", "").strip()
        if not href:
            continue
        full_url = urljoin(base_url, href)
        if not (looks_like_pdf(href) or looks_like_pdf(full_url)):
            continue
        if full_url in seen_urls:
            continue
        seen_urls.add(full_url)
        results.append(MediaFile(
            original_url=full_url,
            local_path="",
            media_type=MenuSourceType.PDF,
        ))
    return results


def _extract_menu_images(sel: Selector, base_url: str) -> list[MediaFile]:
    results: list[MediaFile] = []
    for img in sel.css("img[src]"):
        src = img.attrib.get("src", "")
        alt = img.attrib.get("alt", "").lower()
        if not src:
            continue
        full_url = urljoin(base_url, src)
        combined = f"{alt} {src.lower()}"
        parent_text = " ".join(
            img.xpath("ancestor::*[position() <= 3]//text()").getall()
        ).lower()
        if any(kw in combined or kw in parent_text for kw in MENU_KEYWORDS):
            results.append(MediaFile(
                original_url=full_url,
                local_path="",
                media_type=MenuSourceType.IMAGE,
            ))
    return results


