"""Core scraper: fetches URL with httpx, crawls subpages, extracts menus via OpenAI/Gemini."""
from __future__ import annotations

import asyncio
import hashlib
import logging
import re
import shutil
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx
from parsel import Selector

from menu_scraper.config import get_settings
from menu_scraper.models.menu import (
    MediaFile,
    MenuCategory,
    MenuSourceType,
)
from menu_scraper.processing.html_extractor import HtmlMenuExtractor
from menu_scraper.processing.image_extractor import ImageMenuExtractor
from menu_scraper.processing.menu_enhancer import MenuEnhancer
from menu_scraper.processing.pdf_extractor import PdfMenuExtractor

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
        # Skip non-http schemes and javascript/mailto/tel links
        if clean_link.startswith(("mailto:", "tel:", "javascript:", "#")):
            continue

        full_url = urljoin(base_url, clean_link)
        parsed = urlparse(full_url)
        if parsed.scheme not in ("http", "https"):
            continue
        absolute_links.append(full_url)

    return absolute_links

async def _fetch_page(
    client: httpx.AsyncClient,
    url: str,
    scraper_dir: Path,
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
    local_path: Path = scraper_dir / filename
    local_path.write_text(html, encoding="utf-8")
    logger.info("Saved page [depth=%d]: %s -> %s", depth, response.url, filename)

    return html, str(response.url)


async def _download_pdf(
    client: httpx.AsyncClient,
    url: str,
    pdf_dir: Path,
) -> tuple[bytes, Path] | None:
    """Download a PDF file and save to disk. Returns (pdf_bytes, local_path) or None."""
    try:
        response: httpx.Response = await client.get(url)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("Failed to download PDF %s: %s", url, exc)
        return None

    pdf_data: bytes = response.content
    if len(pdf_data) < 100:
        logger.warning("PDF too small, likely not a real PDF: %s (%d bytes)", url, len(pdf_data))
        return None

    url_hash: str = hashlib.md5(url.encode()).hexdigest()[:10]
    parsed = urlparse(url)
    stem: str = parsed.path.strip("/").replace("/", "_").removesuffix(".pdf") or "doc"
    safe_stem: str = re.sub(r"[^a-zA-Z0-9_]", "", stem)[:60]
    filename: str = f"{safe_stem}_{url_hash}.pdf"
    local_path: Path = pdf_dir / filename
    local_path.write_bytes(pdf_data)
    logger.info("Saved PDF: %s -> %s (%d bytes)", url, filename, len(pdf_data))

    return pdf_data, local_path


async def scrape_menu(
    url: str,
    timeout: int = 30,
    download_media: bool = True,
) -> list[MenuCategory]:
    site_dir: Path = RUN_DIR / _url_to_dirname(url)

    # Асинхронная очистка и создание директорий
    if site_dir.exists():
        await asyncio.to_thread(shutil.rmtree, site_dir)

    scraper_dir: Path = site_dir / "scraper"
    html_extractor_dir: Path = site_dir / "html_extractor"
    pdf_extractor_dir: Path = site_dir / "pdf_extractor"

    for d in (scraper_dir, html_extractor_dir, pdf_extractor_dir):
        await asyncio.to_thread(d.mkdir, parents=True, exist_ok=True)

    settings = get_settings()
    html_extractor = HtmlMenuExtractor(api_key=settings.openai_api_key)
    pdf_extractor = PdfMenuExtractor(api_key=settings.openai_api_key)
    menu_enhancer = MenuEnhancer(api_key=settings.openai_api_key)

    # Если URL ведёт напрямую на PDF — скачиваем и обрабатываем без краулинга
    if _looks_like_pdf(url):
        logger.info("URL is a direct PDF link, skipping crawl: %s", url)
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(timeout),
            headers={"User-Agent": USER_AGENT},
        ) as client:
            pdf_result = await _download_pdf(client, url, pdf_extractor_dir)
        if not pdf_result:
            return []
        pdf_data, _ = pdf_result
        return await pdf_extractor.extract(pdf_data, source_url=url, log_dir=pdf_extractor_dir)

    visited: set[str] = {url}
    current_urls: list[str] = [url]

    all_media: list[MediaFile] = []
    # (html, html_filename) для последующей отправки в LLM
    pending_texts: list[tuple[str, str]] = []

    # Вспомогательная функция для обработки одного URL (без LLM)
    async def _process_url(client: httpx.AsyncClient, current_url: str, depth: int):
        result = await _fetch_page(client, current_url, scraper_dir, depth)
        if not result:
            return None

        html, page_url = result
        sel = Selector(text=html)
        html_filename: str = _url_to_filename(page_url)

        media = _extract_pdf_links(sel, page_url) + _extract_menu_images(sel, page_url)
        sub_links = _find_subpage_links(sel, page_url) if depth < MAX_DEPTH else []

        return html, html_filename, media, sub_links

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

                html, html_filename, media, links = res
                if html.strip():
                    pending_texts.append((html, html_filename))
                all_media.extend(media)

                # Собираем уникальные ссылки для следующего уровня
                for link in links:
                    if link not in visited and len(visited) + len(next_urls) < MAX_PAGES:
                        visited.add(link)
                        next_urls.add(link)

            current_urls = list(next_urls)

    all_categories: list[MenuCategory] = []

    # Дедупликация медиа перед обработкой
    seen_media_urls: set[str] = set()
    deduped_media: list[MediaFile] = []
    for mf in all_media:
        if mf.original_url not in seen_media_urls:
            seen_media_urls.add(mf.original_url)
            deduped_media.append(mf)
    all_media = deduped_media

    # Скачиваем и обрабатываем PDF-файлы (могут быть с внешних доменов)
    pdf_media: list[MediaFile] = [m for m in all_media if m.media_type == MenuSourceType.PDF]
    if pdf_media:
        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=float(timeout),
            headers={"User-Agent": USER_AGENT},
        ) as pdf_client:
            pdf_tasks = [_download_pdf(pdf_client, m.original_url, pdf_extractor_dir) for m in pdf_media]
            pdf_results = await asyncio.gather(*pdf_tasks)

        for media_file, pdf_result in zip(pdf_media, pdf_results):
            if pdf_result is None:
                continue
            pdf_data, local_path = pdf_result
            media_file.local_path = str(local_path)
            logger.info("LLM: processing PDF %s", media_file.original_url)
            items = await pdf_extractor.extract(
                pdf_data, source_url=media_file.original_url, log_dir=pdf_extractor_dir,
            )
            logger.info("LLM: done PDF %s — found %d categories", media_file.original_url, len(items))
            all_categories.extend(items)

    for html, html_filename in pending_texts:
        logger.info("LLM: processing HTML %s", html_filename)
        items = await html_extractor.extract(html, filename=html_filename, log_dir=html_extractor_dir)
        logger.info("LLM: done HTML %s — found %d categories", html_filename, len(items))
        all_categories.extend(items)

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
    return await menu_enhancer.enhance(result)


def _extract_pdf_links(sel: Selector, base_url: str) -> list[MediaFile]:
    """Find PDF links on the page.

    On restaurant sites PDFs are almost always menus, so we collect every
    PDF link without keyword filtering.
    """
    results: list[MediaFile] = []
    seen_urls: set[str] = set()
    for link in sel.css("a"):
        href: str = link.attrib.get("href", "").strip()
        if not href:
            continue
        full_url: str = urljoin(base_url, href)
        # Check both the raw href and the resolved URL for .pdf
        if not (_looks_like_pdf(href) or _looks_like_pdf(full_url)):
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


def _looks_like_pdf(url: str) -> bool:
    """Check if a URL points to a PDF file."""
    parsed = urlparse(url)
    if parsed.path.lower().endswith(".pdf"):
        return True
    # Also check query parameters (e.g. ?filename=menu.pdf)
    return ".pdf" in parsed.query.lower()


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
