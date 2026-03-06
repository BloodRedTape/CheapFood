"""Core scraper: fetches URL with httpx, crawls subpages, extracts menus via Gemini."""
from __future__ import annotations

import hashlib
import logging
import re
import shutil
from pathlib import Path
from urllib.parse import urljoin, urlparse
import asyncio
import shutil
from urllib.parse import urljoin
from parsel import Selector

import httpx
from parsel import Selector

from menu_scraper.config import get_settings
from menu_scraper.models.menu import (
    MediaFile,
    MenuItem,
    MenuResult,
    MenuSourceType,
)
from menu_scraper.processing.html_cleaner import clean_html
from menu_scraper.processing.llm_extractor import GeminiMenuExtractor

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
    absolute_links: list[str] = []
    
    for link in sel.css("a::attr(href)").getall():
        clean_link = link.strip()
        if not clean_link:
            continue
            
        full_url = urljoin(base_url, clean_link)
        absolute_links.append(full_url)
        
    return absolute_links

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
    site_dir: Path = RUN_DIR / _url_to_dirname(url)
    
    # Асинхронная очистка и создание директорий
    if site_dir.exists():
        await asyncio.to_thread(shutil.rmtree, site_dir)
    await asyncio.to_thread(site_dir.mkdir, parents=True, exist_ok=True)

    settings = get_settings()
    extractor = GeminiMenuExtractor(api_key=settings.gemini_api_key)

    visited: set[str] = {url}
    current_urls: list[str] = [url]
    
    all_media: list[MediaFile] = []
    # (clean_text, html_filename) для последующей отправки в LLM
    pending_texts: list[tuple[str, str]] = []

    # Вспомогательная функция для обработки одного URL (без LLM)
    async def _process_url(client: httpx.AsyncClient, current_url: str, depth: int):
        result = await _fetch_page(client, current_url, site_dir, depth)
        if not result:
            return None

        html, page_url = result
        sel = Selector(text=html)
        clean_text = clean_html(html)
        html_filename: str = _url_to_filename(page_url)

        media = _extract_pdf_links(sel, page_url) + _extract_menu_images(sel, page_url)
        sub_links = _find_subpage_links(sel, page_url) if depth < MAX_DEPTH else []

        return clean_text, html_filename, media, sub_links

    async with httpx.AsyncClient(
        follow_redirects=True,
        timeout=float(timeout),
        headers={"User-Agent": USER_AGENT}
    ) as client:
        # Поуровневый обход (BFS)
        for depth in range(MAX_DEPTH + 1):
            if not current_urls or len(visited) >= MAX_PAGES:
                break

            # Параллельный запуск всех URL на текущем уровне глубины
            tasks = [_process_url(client, u, depth) for u in current_urls]
            results = await asyncio.gather(*tasks)

            next_urls: set[str] = set()
            for res in results:
                if not res:
                    continue

                clean_text, html_filename, media, links = res
                if clean_text.strip():
                    pending_texts.append((clean_text, html_filename))
                all_media.extend(media)

                # Собираем уникальные ссылки для следующего уровня
                for link in links:
                    if link not in visited and len(visited) + len(next_urls) < MAX_PAGES:
                        visited.add(link)
                        next_urls.add(link)

            current_urls = list(next_urls)

    # Батчинг текстов для LLM: объединяем маленькие тексты в один запрос
    BATCH_CHAR_LIMIT: int = 8000
    all_items: list[MenuItem] = []
    batch_texts: list[tuple[str, str]] = []  # (clean_text, html_filename)
    batch_size: int = 0

    async def _flush_batch() -> None:
        nonlocal batch_texts, batch_size
        if not batch_texts:
            return
        if len(batch_texts) == 1:
            text, fname = batch_texts[0]
            log_path = site_dir / fname.replace(".html", ".llm.txt")
            items = await extractor.extract(text, log_path=log_path)
        else:
            combined = "\n\n---PAGE BREAK---\n\n".join(t for t, _ in batch_texts)
            log_name = batch_texts[0][1].replace(".html", "") + "_batch.llm.txt"
            log_path = site_dir / log_name
            items = await extractor.extract(combined, log_path=log_path)
        all_items.extend(items)
        batch_texts = []
        batch_size = 0

    for clean_text, html_filename in pending_texts:
        text_len = len(clean_text)
        # Если текст сам по себе большой — отправляем отдельно
        if text_len >= BATCH_CHAR_LIMIT:
            await _flush_batch()
            log_path = site_dir / html_filename.replace(".html", ".llm.txt")
            items = await extractor.extract(clean_text, log_path=log_path)
            all_items.extend(items)
            continue
        # Если добавление переполнит батч — сначала сбросим
        if batch_size + text_len > BATCH_CHAR_LIMIT:
            await _flush_batch()
        batch_texts.append((clean_text, html_filename))
        batch_size += text_len

    await _flush_batch()

    # Дедупликация
    seen_names = set()
    unique_items = []
    for item in all_items:
        key = item.name.lower().strip()
        if key not in seen_names:
            seen_names.add(key)
            unique_items.append(item)

    seen_urls = set()
    unique_media = []
    for mf in all_media:
        if mf.original_url not in seen_urls:
            seen_urls.add(mf.original_url)
            unique_media.append(mf)

    source_type = MenuSourceType.HTML_TEXT
    if not unique_items and unique_media:
        source_type = unique_media[0].media_type

    return MenuResult(
        url=url,
        items=unique_items,
        source_type=source_type,
        media_files=unique_media,
    )


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
